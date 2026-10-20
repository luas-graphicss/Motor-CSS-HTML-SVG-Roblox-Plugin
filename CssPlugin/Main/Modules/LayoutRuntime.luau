local U=require(script.Parent.Util)
local O=require(script.Parent.RenderOptimizer)
local Groups=require(script.Parent.VisualEffectsGroups)
local Fonts=require(script.Parent.FontFaces)
local Features=require(script.Parent.FontFeatures)
local R={}
local function frame(parent,name)
 local o=O.acquire('Frame');O.properties(o,{Name=name,BorderSizePixel=0,BackgroundTransparency=1,AnchorPoint=Vector2.zero});O.attributes(o,{CssOwned=true});o.Parent=parent;return o
end
function R.decorate(paint,s,box,opacity,vw,vh)
 if not box.columnRules then return end
 local mode=s['column-rule-style']or'none'
 assert(mode=='none'or mode=='hidden'or mode=='solid'or mode=='dotted'or mode=='dashed'or mode=='double','column-rule-style inválido.')
 if mode=='none'or mode=='hidden'then return end
 local value=s['column-rule-width']or'medium';local width=({thin=1,medium=3,thick=5})[value]or U.length(value,box.w,vw,vh,box.fs)or 0
 assert(width>=0,'column-rule-width não pode ser negativo.');if width==0 then return end
 local ink=s['column-rule-color'];if not ink or ink=='currentcolor'then ink=s.color end
 local color,alpha=U.color(ink)
 local parts=0
 local function stroke(x,y,w,h)
  if h<=0 or w<=0 then return end;parts+=1;assert(parts<=2048,'column-rule excede 2048 segmentos.')
  local rule=frame(paint,'ColumnRule');O.properties(rule,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=color,BackgroundTransparency=1-alpha*opacity,ZIndex=paint.ZIndex+1})
  O.attributes(rule,{CssBaseAlpha=alpha})
 end
 for _,line in ipairs(box.columnRules)do
  local x=box.p[4]+line.x-width/2;local y=box.p[1]+line.y
  if line.horizontal then
   x=box.p[4]+line.x;y=box.p[1]+line.y-width/2
   if mode=='solid'then stroke(x,y,line.w,width)
   elseif mode=='double'then stroke(x,y,line.w,width/3);stroke(x,y+width*2/3,line.w,width/3)
   else local dash=mode=='dotted'and width or width*3;local at=0;while at<line.w do stroke(x+at,y,math.min(dash,line.w-at),width);at+=dash+width end end
   continue
  end
  if mode=='solid'then stroke(x,y,width,line.h)
  elseif mode=='double'then stroke(x,y,width/3,line.h);stroke(x+width*2/3,y,width/3,line.h)
  else
   local dash=mode=='dotted'and width or width*3;local at=0
   while at<line.h do stroke(x,y+at,width,math.min(dash,line.h-at));at+=dash+width end
  end
 end
end
function R.paintText(object,s,box,opacity,cache)
 local fragments=box.fragments;local old=O.child(object,'__LayoutText')
 if not fragments or #fragments==0 then
  if old then O.release(old);O.remember(object,'__LayoutText',nil)end
  cache.layoutLabels=nil;cache.layoutTextSignature=nil;return
 end
 local color,alpha=U.color(s.color);local signature=(box.fragmentSignature or O.signature(fragments))..':'..O.signature(s)..':'..opacity..':'..object.ZIndex
 local labels=cache.layoutLabels
 if cache.layoutTextSignature~=signature or not old or not labels then
  if old then O.release(old)end
  old=frame(object,'__LayoutText');O.remember(object,'__LayoutText',old)
  O.properties(old,{Size=UDim2.fromScale(1,1),ZIndex=object.ZIndex})
  local nativeText=object:IsA('TextLabel')or object:IsA('TextButton')or object:IsA('TextBox')
  local p=nativeText and(box.textPadding or box.p)or{0,0,0,0}
  O.properties(old,{Position=UDim2.fromOffset(-p[4],-p[1])})
  local ox=box.columnCount and box.p[4]or 0;local oy=box.columnCount and box.p[1]or 0
  labels={};cache.layoutLabels=labels
  for i,f in ipairs(fragments)do
   local label=O.acquire('TextLabel');O.properties(label,{Name='Line'..i,BorderSizePixel=0,BackgroundTransparency=1,AnchorPoint=Vector2.zero,Position=UDim2.fromOffset(ox+f.x,oy+f.y),Size=UDim2.fromOffset(f.w,f.h),Text=f.text,TextWrapped=false,RichText=false,TextTruncate=Enum.TextTruncate.None,FontFace=Fonts.face(s),TextSize=box.fs,TextColor3=color,TextTransparency=1-alpha*opacity,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,ZIndex=object.ZIndex,AutoLocalize=object:IsA('TextLabel')and object.AutoLocalize or true})
   Features.apply(label,s)
   O.properties(label,{TextDirection=(f.direction or s.direction)=='rtl'and Enum.TextDirection.RightToLeft or Enum.TextDirection.LeftToRight,Rotation=f.rotation or 0})
   if f.rotation then O.properties(label,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(ox+f.x+f.w/2,oy+f.y+f.h/2),Size=UDim2.fromOffset(f.drawW or f.h,f.drawH or f.w)})end
   O.attributes(label,{CssOwned=true,CssBaseAlpha=alpha});label.Parent=old;labels[#labels+1]=label
  end
  cache.layoutTextSignature=signature
 end
 if object:IsA('TextLabel')then O.properties(object,{TextTransparency=1})end
end
function R.opacity(object,opacity,cache)
 if not cache.layoutLabels then return end
 for _,label in ipairs(cache.layoutLabels)do if label.Parent then O.properties(label,{TextTransparency=1-(label:GetAttribute('CssBaseAlpha')or 1)*opacity})end end
 if object:IsA('TextLabel')then O.properties(object,{TextTransparency=1})end
end
local function coordinate(node,stop,boxes,parents,offsets)
  local x,y=0,0
  while node and node~=stop do
   local b=boxes[node.key];if b then x+=b.x;y+=b.y end
   local d=offsets and offsets[node.key];if d then x+=d.x;y+=d.y end
   node=parents[node.key]
  end
  return x,y
 end
function R.offsets(c,records,apply)
  local offsets={}
  for _,record in ipairs(records)do
   local node=record.node;local object=c.objects[node.key];local box=c.boxes[node.key];local style=c.styles[node.key]
   if record.fixed then
    if object and box and not box.hidden and(not apply or object.Parent)then
     local dx,dy=0,0
     for _,port in ipairs(record.ports or{})do dx+=port.CanvasPosition.X;dy+=port.CanvasPosition.Y end
     local up=c.parents[node.key]
     while up do local d=offsets[up.key];if d then dx-=d.x;dy-=d.y end;up=c.parents[up.key]end
     offsets[node.key]={x=dx,y=dy}
     if apply then
      local native=O.paintBox(node,box,c.parents,c.objects,c.boxes)
      local base=UDim2.fromOffset(native.x+box.w/2+dx,native.y+box.h/2+dy)
      local entry=c.cache and c.cache[node.key]
      if entry and entry.transformPosition then entry.transformPosition=base end
      local projection=entry and entry.transformProjection
      if projection then base+=UDim2.fromOffset(projection.x,projection.y)end
      O.properties(Groups.root(object),{Position=base})
     end
    end
   elseif object and box and not box.hidden and(not apply or object.Parent)then
    local parent=c.parents[node.key];local scroll=record.scroll;local port=scroll and c.objects[scroll.key]
    local sb=scroll and c.boxes[scroll.key]or{w=c.width,h=c.height,p={0,0,0,0}}
    local sx,sy=0,0
    if port and port:IsA('ScrollingFrame')then sx=port.CanvasPosition.X;sy=port.CanvasPosition.Y end
    local nx,ny=coordinate(node,scroll,c.boxes,c.parents,offsets)
    local px,py=coordinate(parent,scroll,c.boxes,c.parents,offsets);local pb=parent and c.boxes[parent.key]or sb
    local function len(v,base)return U.length(v,base,c.width,c.height,box.fs)end
    local left,right,top,bottom=len(style.left,sb.w),len(style.right,sb.w),len(style.top,sb.h),len(style.bottom,sb.h)
    local function sticky(normal,size,scrolled,viewport,start,finish,first,last)
     if start==nil and finish==nil then return normal end
     if start~=nil and finish~=nil and viewport-start-finish<size then finish=viewport-start-size end
     local at=normal
     if finish~=nil then at=math.min(at,scrolled+viewport-finish-size)end
     if start~=nil then at=math.max(at,scrolled+start)end
     return math.clamp(at,first,math.max(first,last))
    end
    local ml=len(style['margin-left'],pb.w)or 0;local mr=len(style['margin-right'],pb.w)or 0
    local mt=len(style['margin-top'],pb.w)or 0;local mb=len(style['margin-bottom'],pb.w)or 0
    local parentW,parentH=pb.w,pb.h
    if parent==scroll and port and port:IsA('ScrollingFrame')then parentW=math.max(parentW,pb.contentW or 0);parentH=math.max(parentH,pb.contentH or 0)end
    local x=sticky(nx,box.w,sx,sb.w,left,right,px+pb.p[4]+ml,px+parentW-pb.p[2]-box.w-mr)
    local y=sticky(ny,box.h,sy,sb.h,top,bottom,py+pb.p[1]+mt,py+parentH-pb.p[3]-box.h-mb)
    local dx,dy=x-nx,y-ny;offsets[node.key]={x=dx,y=dy}
    if apply then
    local native=O.paintBox(node,box,c.parents,c.objects,c.boxes)
    local base=UDim2.fromOffset(native.x+box.w/2+dx,native.y+box.h/2+dy)
    local entry=c.cache and c.cache[node.key]
    if entry and entry.transformPosition then entry.transformPosition=base end
    local projection=entry and entry.transformProjection
    if projection then base+=UDim2.fromOffset(projection.x,projection.y)end
    O.properties(Groups.root(object),{Position=base})
    end
   end
  end
  return offsets
end
function R.records(c)
  local records,needed={},{}
  for _,node in ipairs(c.sequence or{})do
   local style=c.styles[node.key];local box=c.boxes[node.key];local object=c.objects[node.key]
   if style and box and object and not box.hidden then
    if style.position=='sticky'then
     local scroll=c.parents[node.key]
     while scroll do
      local o=c.objects[scroll.key];local s=c.styles[scroll.key]
      if(o and o:IsA('ScrollingFrame'))or s._overflowClipX==true or s._overflowClipY==true then break end
      scroll=c.parents[scroll.key]
     end
     records[#records+1]={node=node,scroll=scroll}
     local port=scroll and c.objects[scroll.key]
     if port and port:IsA('ScrollingFrame')then needed[port]=true end
    elseif style.position=='fixed'and box.fixed==true and box.fixedHost~=true then
     local ports={};local up=c.parents[node.key]
     while up do
      local o=c.objects[up.key]
      if o and o:IsA('ScrollingFrame')then ports[#ports+1]=o;needed[o]=true end
      up=c.parents[up.key]
     end
     records[#records+1]={node=node,fixed=true,ports=ports}
    end
   end
  end
  return records,needed
end
function R.new(controller)
 local self={controller=controller,links={},records={},alive=true,steps=0}
 function self:step()
  if not self.alive then return end
  local c=self.controller;if not c or not c.boxes then return end
  self.steps+=1;R.offsets(c,self.records,true)
 end
 function self:sync()
  local records,needed=R.records(self.controller)
  self.records=records
  for port,link in pairs(self.links)do if not needed[port]then link:Disconnect();self.links[port]=nil end end
  for port in pairs(needed)do if not self.links[port]then self.links[port]=port:GetPropertyChangedSignal('CanvasPosition'):Connect(function()self:step()end)end end
  self:step()
 end
 function self:destroy()
  if not self.alive then return end;self.alive=false
  for _,link in pairs(self.links)do link:Disconnect()end
  table.clear(self.links);table.clear(self.records);self.controller=nil
 end
 return self
end
return R
