local Tiles=require(script.Parent.RenderTiles)
local Budget=require(script.Parent.RenderBudget)
local P={VERSION=1,SEGMENT=20}
local floor=math.floor
local clamp=math.clamp
local function mark(instance)
 instance:SetAttribute('CssOwned',true)
 instance:SetAttribute('CssNoPool',true)
 instance:SetAttribute('CssRenderAux',true)
 return instance
end
local function quantize(color,alpha)
 return floor(color.R*255+0.5)*16777216+floor(color.G*255+0.5)*65536+floor(color.B*255+0.5)*256+floor(alpha*255+0.5)
end
local function solid(view,x,y,w,color,alpha)
 local frame=Instance.new('Frame')
 frame.Name='__CssRun'
 frame.BorderSizePixel=0
 frame.Size=UDim2.fromOffset(w,1)
 frame.Position=UDim2.fromOffset(x,y)
 frame.BackgroundColor3=color
 frame.BackgroundTransparency=clamp(1-alpha,0,1)
 mark(frame)
 frame.Parent=view.root
 return frame
end
local function band(view,x,y,samples)
 local count=#samples
 local frame=Instance.new('Frame')
 frame.Name='__CssBand'
 frame.BorderSizePixel=0
 frame.Size=UDim2.fromOffset(count,1)
 frame.Position=UDim2.fromOffset(x,y)
 frame.BackgroundColor3=Color3.new(1,1,1)
 frame.BackgroundTransparency=0
 mark(frame)
 local colors={}
 local alphas={}
 for index,sample in ipairs(samples) do
  local t=(index-1)/(count-1)
  colors[index]=ColorSequenceKeypoint.new(t,sample.color)
  alphas[index]=NumberSequenceKeypoint.new(t,clamp(1-sample.alpha,0,1))
 end
 local gradient=Instance.new('UIGradient')
 gradient.Color=ColorSequence.new(colors)
 gradient.Transparency=NumberSequence.new(alphas)
 mark(gradient)
 gradient.Parent=frame
 frame.Parent=view.root
 return frame
end
function P.count(view)
 local total=0
 for _ in pairs(view.tiles) do total+=1 end
 return total
end
function P.report(view,bytes)
 if bytes~=nil then view.bytes=bytes end
 return {backend=view.backend,tiles=P.count(view),primitives=view.primitives,bytes=view.bytes,writes=view.writes,truncated=view.truncated==true,degraded=view.degraded}
end
function P.attach(parent,surface,options)
 options=options or {}
 local cap=surface.plan.capability or Budget.capability()
 local root=Instance.new('Frame')
 root.Name=options.name or '__CssRender'
 root.BackgroundTransparency=1
 root.BorderSizePixel=0
 root.ClipsDescendants=options.clip~=false
 root.Size=UDim2.fromOffset(surface.w,surface.h)
 root.Position=UDim2.fromOffset(tonumber(options.x) or 0,tonumber(options.y) or 0)
 root.ZIndex=tonumber(options.zIndex) or 0
 mark(root)
 local backend=cap.editable and 'EditableImageTiles' or 'NativeGradientBands'
 root:SetAttribute('CssRenderBackend',backend)
 root:SetAttribute('CssRenderResolution',string.format('%dx%d',surface.w,surface.h))
 root.Parent=parent
 local span=surface.tile
 if cap.maxSide and cap.maxSide>0 then span=math.max(surface.tile,math.min(cap.maxSide,floor(cap.maxSide/surface.tile)*surface.tile)) end
 return {
  parent=parent,
  root=root,
  surface=surface,
  span=span,
  cols=math.ceil(surface.w/span),
  rows=math.ceil(surface.h/span),
  tiles={},
  backend=backend,
  capability=cap,
  fallback=not cap.editable,
  bytes=0,
  writes=0,
  primitives=0,
  truncated=false,
  degraded=nil,
 }
end
function P.tileOf(view,tx,ty)
 local key=ty*view.cols+tx
 local entry=view.tiles[key]
 if entry then return entry end
 local x=tx*view.span
 local y=ty*view.span
 local w=math.min(view.span,view.surface.w-x)
 local h=math.min(view.span,view.surface.h-y)
 if w<=0 or h<=0 then return nil end
 local bytes=w*h*Budget.PRESENT_BYTES_PER_PIXEL
 view.surface.budget:spend(bytes,'Apresentacao do render core','present')
 local label=Instance.new('ImageLabel')
 label.Name=string.format('__CssTile_%d_%d',tx,ty)
 label.BackgroundTransparency=1
 label.BorderSizePixel=0
 label.Size=UDim2.fromOffset(w,h)
 label.Position=UDim2.fromOffset(x,y)
 mark(label)
 local image=nil
 local ok=pcall(function()
  image=game:GetService('AssetService'):CreateEditableImage({Size=Vector2.new(w,h)})
  label.ResampleMode=Enum.ResamplerMode.Pixelated
  label.ImageContent=Content.fromObject(image)
 end)
 if not ok or image==nil then
  label:Destroy()
  view.surface.budget:refund(bytes)
  return nil
 end
 label.Parent=view.root
 view.bytes+=bytes
 entry={x=x,y=y,w=w,h=h,image=image,label=label,bytes=bytes}
 view.tiles[key]=entry
 return entry
end
function P.fallback(view)
 local surface=view.surface
 view.fallback=true
 view.backend='NativeGradientBands'
 for _,child in ipairs(view.root:GetChildren()) do child:Destroy() end
 if view.bytes>0 then surface.budget:refund(view.bytes) end
 table.clear(view.tiles)
 view.primitives=0
 view.truncated=false
 local budget=surface.budget
 local bytes=0
 local function spend()
  if not budget:fits(Budget.FALLBACK_BYTES) then
   view.truncated=true
   return false
  end
  budget:spend(Budget.FALLBACK_BYTES,'Fallback portatil do render core','fallback')
  bytes+=Budget.FALLBACK_BYTES
  view.primitives+=1
  return true
 end
 for y=0,surface.h-1 do
  local x=0
  while x<surface.w do
   local color,alpha=Tiles.get(surface,x,y)
   local key=quantize(color,alpha)
   local run=1
   while x+run<surface.w do
    local nc,na=Tiles.get(surface,x+run,y)
    if quantize(nc,na)~=key then break end
    run+=1
   end
   if alpha<=0.002 then
    x+=run
   elseif run>=2 then
    if not spend() then return P.report(view,bytes) end
    solid(view,x,y,run,color,alpha)
    x+=run
   else
    local samples={}
    local cursor=x
    while cursor<surface.w and #samples<P.SEGMENT do
     local sc,sa=Tiles.get(surface,cursor,y)
     if sa<=0.002 then break end
     local length=1
     local skey=quantize(sc,sa)
     while cursor+length<surface.w do
      local nc,na=Tiles.get(surface,cursor+length,y)
      if quantize(nc,na)~=skey then break end
      length+=1
     end
     if length>=3 and #samples>0 then break end
     samples[#samples+1]={color=sc,alpha=sa}
     cursor+=1
    end
    if #samples<=1 then
     if not spend() then return P.report(view,bytes) end
     solid(view,x,y,1,color,alpha)
     x+=1
    else
     if not spend() then return P.report(view,bytes) end
     band(view,x,y,samples)
     x+=#samples
    end
   end
  end
 end
 view.root:SetAttribute('CssRenderBackend','NativeGradientBands')
 view.root:SetAttribute('CssRenderFallback',true)
 view.root:SetAttribute('CssRenderPrimitives',view.primitives)
 return P.report(view,bytes)
end
function P.degrade(view,reason)
 view.degraded=tostring(reason)
 view.root:SetAttribute('CssRenderDegraded',view.degraded)
 return P.fallback(view)
end
function P.update(view,rects)
 if view.fallback then return P.fallback(view) end
 local list=rects
 if list==nil or #list==0 then list={Tiles.full(view.surface)} end
 local written=0
 for _,rect in ipairs(list) do
  local area=Tiles.rect(view.surface,rect.x,rect.y,rect.w,rect.h)
  if area.w>0 and area.h>0 then
   for ty=floor(area.y/view.span),floor((area.y+area.h-1)/view.span) do
    for tx=floor(area.x/view.span),floor((area.x+area.w-1)/view.span) do
     local entry=P.tileOf(view,tx,ty)
     if entry==nil then return P.degrade(view,'EditableImage indisponivel') end
     local bounds=Tiles.intersect(area,{x=entry.x,y=entry.y,w=entry.w,h=entry.h})
     if bounds.w>0 and bounds.h>0 then
      local rgba=Tiles.rgba(view.surface,bounds)
      local ok=pcall(function()
       entry.image:WritePixelsBuffer(Vector2.new(bounds.x-entry.x,bounds.y-entry.y),Vector2.new(bounds.w,bounds.h),rgba)
      end)
      if not ok then return P.degrade(view,'WritePixelsBuffer falhou') end
      written+=bounds.w*bounds.h
      view.writes+=1
     end
    end
   end
  end
 end
 view.root:SetAttribute('CssRenderWrites',view.writes)
 local out=P.report(view)
 out.pixels=written
 return out
end
function P.resize(view,width,height)
 view.root.Size=UDim2.fromOffset(math.max(0,floor(tonumber(width) or 0)),math.max(0,floor(tonumber(height) or 0)))
 return view
end
function P.release(view)
 if view.bytes>0 then view.surface.budget:refund(view.bytes) end
 view.bytes=0
 view.primitives=0
 table.clear(view.tiles)
 if view.root then view.root:Destroy() end
 return view
end
return P
