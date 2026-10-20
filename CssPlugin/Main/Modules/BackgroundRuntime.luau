local A=require(script.Parent.AdvancedPaint)
local Images=require(script.Parent.BackgroundImages)
local O=require(script.Parent.RenderOptimizer)
local Performance=require(script.Parent.Performance)
local B={}
function B.paintBox(node,paintBox,boxes,parents,objects)
 local original=boxes[node.key];local x,y=original.x,original.y;local parent=parents[node.key]
 while parent do
  local b=boxes[parent.key];x+=b.x;y+=b.y
  local o=objects[parent.key];if o and o:IsA('ScrollingFrame')then x-=o.CanvasPosition.X;y-=o.CanvasPosition.Y end
  parent=parents[parent.key]
 end
 local result=table.clone(paintBox);local object=objects[node.key]
 result._backgroundX,result._backgroundY=x,y
 if object and object:IsA('ScrollingFrame')then result._backgroundScroll=true;result._backgroundScrollX=object.CanvasPosition.X;result._backgroundScrollY=object.CanvasPosition.Y end
 return result
end
function B.install(controller,Paint,options)
 options=options or {};Images.register(controller.document and controller.document.imageSizes)
 local owner=controller;local self={scrolls={},images={},alive=true,dirty=false,passes=0};owner.backgroundRuntime=self
 local function request()
  if not self.alive or not owner.alive then return end;self.dirty=true
  if not owner.manual then self.scheduler:request()end
 end
 function self:repaint(force)
  if not self.alive or not owner.alive or not owner.sequence then return end
  self.dirty=false;self.passes+=1
  local targets={}
  for _,node in ipairs(owner.sequence)do local object=owner.objects[node.key]
   if object and(force or A.dynamic(owner.styles[node.key])or object:IsA('ScrollingFrame'))then targets[node.key]=true end
  end
  owner:refresh(owner.width,owner.height,{textOnly=true,forcePaint=targets})
 end
 self.scheduler=Performance.coalesce(function()
  local ok,err=pcall(self.repaint,self,true)
  if not ok and owner.development and self.lastError~=tostring(err)then self.lastError=tostring(err);warn('[CssPlugin backgrounds] '..self.lastError)end
 end,{signal=options.frameSignal})
 function self:sync(probe)
  if not self.alive then return end
  local scrolls,images={},{}
  for _,object in pairs(owner.objects)do
   if object:IsA('ScrollingFrame')then scrolls[object]=true end
   local paint=object:FindFirstChild('__Paint')
   if paint then for _,image in ipairs(paint:GetDescendants())do
    if image:IsA('ImageLabel')and image:GetAttribute('CssBackgroundAsset')and not images[image.Image]then images[image.Image]=image end
   end end
  end
  for object,connection in pairs(self.scrolls)do if not scrolls[object]then connection:Disconnect();self.scrolls[object]=nil end end
  for object in pairs(scrolls)do if not self.scrolls[object]then self.scrolls[object]=object:GetPropertyChangedSignal('CanvasPosition'):Connect(request)end end
  for source,entry in pairs(self.images)do
   if images[source]~=entry.object then for _,connection in ipairs(entry.connections)do connection:Disconnect()end;self.images[source]=nil end
  end
  local changed=false
  for source,image in pairs(images)do
   if not self.images[source]then
    local entry={object=image,connections={}};self.images[source]=entry
    local function loaded()if self.alive and Images.probe(image)then request()end end
    for _,property in ipairs({'ContentImageSize','IsLoaded'})do
     local ok,signal=pcall(image.GetPropertyChangedSignal,image,property)
     if ok then entry.connections[#entry.connections+1]=signal:Connect(loaded)end
    end
   end
   if probe~=false and Images.probe(image)then changed=true end
  end
  if changed then request()end
 end
 function self:destroy()
  if not self.alive then return end;self.alive=false;self.scheduler:destroy()
  for _,connection in pairs(self.scrolls)do connection:Disconnect()end
  for _,entry in pairs(self.images)do for _,connection in ipairs(entry.connections)do connection:Disconnect()end end
  table.clear(self.scrolls);table.clear(self.images);owner=nil
 end
 return self
end
return B
