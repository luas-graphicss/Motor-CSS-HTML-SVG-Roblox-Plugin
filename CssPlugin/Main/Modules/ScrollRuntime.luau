local U=require(script.Parent.Util)
local S=require(script.Parent.ScrollStyle)
local G=require(script.Parent.ScrollGeometry)
local Timeline=require(script.Parent.ScrollTimeline)
local O=require(script.Parent.RenderOptimizer)
local Bars=require(script.Parent.Scrollbars)
local Overflow=require(script.Parent.Overflow)
local Tween=game:GetService('TweenService')
local R={VERSION=1}
local behaviors={auto=true,contain=true,none=true}
local tweens=setmetatable({},{__mode='k'})
function R.thickness(style)return Bars.thickness(style)end
function R.colors(style)return Bars.colors(style,style and style._mediaEnvironment)end
function R.animating(port)
 local tween=tweens[port]
 return tween~=nil and tween.PlaybackState==Enum.PlaybackState.Playing
end
function R.cancel(port)
 local tween=tweens[port]
 if tween then tween:Cancel();tweens[port]=nil end
end
function R.scrollTo(port,x,y,behavior)
 local target=Vector2.new(x,y);R.cancel(port)
 if behavior~='smooth'then port.CanvasPosition=target;return false end
 local tween=Tween:Create(port,TweenInfo.new(0.24,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{CanvasPosition=target})
 tweens[port]=tween
 tween.Completed:Connect(function()if tweens[port]==tween then tweens[port]=nil end end)
 tween:Play();return true
end
function R.overscroll(style)
 local out={x=style['overscroll-behavior-x']or 'auto',y=style['overscroll-behavior-y']or 'auto'}
 for _,name in ipairs({'block','inline'})do
  local value=style['overscroll-behavior-'..name]
  if value then local axis=G.axis(style,name);out[axis]=value end
 end
 for _,axis in ipairs({'x','y'})do assert(behaviors[out[axis]],'overscroll-behavior aceita auto/contain/none.')end
 return out.x,out.y
end
function R.axes(style)return Overflow.scrolling(style)end
function R.behavior(style)return Bars.behavior(style)end
function R.pages(style,box)
 local paged=Overflow.pagedAxis(style)
 if not paged or not box then return 0,nil end
 local size=paged=='x'and math.max(box.w or 0,1)or math.max(box.h or 0,1)
 local extent=paged=='x'and math.max(box.contentW or box.w or 0,box.w or 0)or math.max(box.contentH or box.h or 0,box.h or 0)
 return math.max(1,math.ceil(extent/size-0.001)),paged
end
function R.pageSize(record,box)
 if record.paged=='x'then return math.max(box and box.w or 0,1),'x'end
 if record.paged=='y'then return math.max(box and box.h or 0,1),'y'end
 return nil,nil
end
function R.native(object,style,box,vw,vh)
 if not object:IsA('ScrollingFrame')then return end
 local thickness=R.thickness(style);local colors=R.colors(style)
 local x,y=R.overscroll(style);local scrollX,scrollY=R.axes(style)
 local paged,controls=Overflow.pagedAxis(style)
 local direction=(scrollX and scrollY and Enum.ScrollingDirection.XY)or(scrollX and Enum.ScrollingDirection.X)or(scrollY and Enum.ScrollingDirection.Y)or Enum.ScrollingDirection.XY
 local gutter=Bars.gutter(style)
 local inset=gutter.stable and Enum.ScrollBarInset.Always or Enum.ScrollBarInset.ScrollBar
 local properties={ScrollBarThickness=thickness,ScrollingEnabled=(scrollX or scrollY)and tostring(style['pointer-events']or'auto'):lower()~='none',ScrollingDirection=direction,
  VerticalScrollBarInset=inset,HorizontalScrollBarInset=inset,
  ElasticBehavior=(x=='none'or y=='none')and Enum.ElasticBehavior.Never or Enum.ElasticBehavior.WhenScrollable}
 if colors then properties.ScrollBarImageColor3=colors.thumb;properties.ScrollBarImageTransparency=1-colors.thumbAlpha end
 O.properties(object,properties)
 local pageCount=R.pages(style,box)
 O.attributes(object,{CssScrollbarWidth=thickness,CssOverscrollX=x,CssOverscrollY=y,
  CssScrollbarGutter=gutter.stable and(gutter.bothEdges and'stable both-edges'or'stable')or'auto',
  CssScrollBehavior=Bars.behavior(style),CssOverflowPaged=paged or'none',CssOverflowPagedControls=controls==true,
  CssOverflowPages=pageCount,
  CssScrollSnapType=U.trim(tostring(style['scroll-snap-type']or 'none'))})
end
function R.page(port,style,box,delta)
 if not port or not port:IsA('ScrollingFrame')or not style or not box then return false end
 local step=tonumber(delta)or 0
 local pages,axis=R.pages(style,box)
 if step==0 or not axis or pages<=1 then return false end
 local size=axis=='x'and math.max(box.w or 0,1)or math.max(box.h or 0,1)
 local extent=axis=='x'and math.max(box.contentW or box.w or 0,box.w or 0)or math.max(box.contentH or box.h or 0,box.h or 0)
 local limit=math.max(0,extent-size)
 local current=port.CanvasPosition
 local index=math.clamp(math.floor((axis=='x'and current.X or current.Y)/size+0.5)+step,0,pages-1)
 local target=math.clamp(index*size,0,limit)
 local x=axis=='x'and target or current.X
 local y=axis=='y'and target or current.Y
 if math.abs(x-current.X)<0.5 and math.abs(y-current.Y)<0.5 then return false end
 R.scrollTo(port,x,y,Bars.behavior(style));return true
end
function R.controls(paint,object,style,box,opacity)
 if not paint or not object or not object:IsA('ScrollingFrame')or not style or not box then return 0 end
 local axis,enabled=Overflow.pagedAxis(style)
 if not axis or enabled~=true then return 0 end
 local w=math.max(box.w or 0,0);local h=math.max(box.h or 0,0)
 local pages=R.pages(style,box)
 if w<=0 or h<=0 or pages<=1 then return 0 end
 local unit=math.clamp(math.round(math.min(w,h)*0.2),12,28)
 if unit*2+6>(axis=='x'and w or h)then return 0 end
 local thickness=R.thickness(style);local colors=R.colors(style)
 local track=colors and colors.track or Color3.fromRGB(24,24,24)
 local trackAlpha=colors and colors.trackAlpha or 0.55
 local thumb=colors and colors.thumb or Color3.fromRGB(245,245,245)
 local thumbAlpha=colors and colors.thumbAlpha or 1
 local scrollX,scrollY=R.axes(style)
 local reserveX=(scrollY and(box.contentH or 0)>h+0.5)and thickness or 0
 local reserveY=(scrollX and(box.contentW or 0)>w+0.5)and thickness or 0
 local size=axis=='x'and math.max(w,1)or math.max(h,1)
 local index=math.clamp(math.floor((axis=='x'and object.CanvasPosition.X or object.CanvasPosition.Y)/size+0.5),0,pages-1)
 local gap=math.max(2,math.round(unit*0.3))
 local made=0
 local function control(name,delta,glyph,x,y,dim)
  local alpha=dim and trackAlpha*0.35 or trackAlpha
  local button=O.acquire('TextButton')
  O.properties(button,{Name=name,BorderSizePixel=0,AnchorPoint=Vector2.zero,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(unit,unit),
   BackgroundColor3=track,BackgroundTransparency=1-alpha*opacity,AutoButtonColor=false,Active=not dim,Selectable=false,
   Text=glyph,Font=Enum.Font.SourceSansBold,TextSize=math.max(8,unit-6),TextColor3=thumb,
   TextTransparency=1-(dim and thumbAlpha*0.4 or thumbAlpha)*opacity,ZIndex=paint.ZIndex+3})
  O.attributes(button,{CssOwned=true,CssBaseAlpha=alpha,CssPageDelta=delta,CssPageAxis=axis,CssPageIndex=index,CssPageCount=pages,CssPageDisabled=dim==true})
  local corner=O.acquire('UICorner');O.properties(corner,{Name='__PageCorner',CornerRadius=UDim.new(0,math.floor(unit/2))});corner.Parent=button
  button.Parent=paint;O.remember(paint,name,button);made+=1
 end
 if axis=='x'then
  local y=math.round((h-reserveY-unit)/2)
  control('__PagePrev',-1,'◀',gap,y,index<=0)
  control('__PageNext',1,'▶',math.round(w-reserveX-unit-gap),y,index>=pages-1)
 else
  local x=math.round((w-reserveX-unit)/2)
  control('__PagePrev',-1,'▲',x,gap,index<=0)
  control('__PageNext',1,'▼',x,math.round(h-reserveY-unit-gap),index>=pages-1)
 end
 return made
end
function R.decorate(paint,object,style,box,opacity,vw,vh)
 if not object or not object:IsA('ScrollingFrame')then return end
 R.controls(paint,object,style,box,opacity)
 local colors=R.colors(style);local thickness=R.thickness(style)
 if not colors or thickness<=0 then return end
 local scrollX,scrollY=R.axes(style)
 local verticalBar=scrollY and(box.contentH or 0)>box.h+0.5;local horizontalBar=scrollX and(box.contentW or 0)>box.w+0.5
 local function band(name,x,y,w,h)
  if w<=0 or h<=0 then return end
  local frame=O.acquire('Frame')
  O.properties(frame,{Name=name,BorderSizePixel=0,AnchorPoint=Vector2.zero,Position=UDim2.fromOffset(x,y),
   Size=UDim2.fromOffset(w,h),BackgroundColor3=colors.track,BackgroundTransparency=1-colors.trackAlpha*opacity,ZIndex=paint.ZIndex+2})
  O.attributes(frame,{CssOwned=true,CssBaseAlpha=colors.trackAlpha});frame.Parent=paint
 end
 if verticalBar then band('__ScrollTrackY',box.w-thickness,0,thickness,box.h-(horizontalBar and thickness or 0))end
 if horizontalBar then band('__ScrollTrackX',0,box.h-thickness,box.w-(verticalBar and thickness or 0),thickness)end
end
local intoModes=table.freeze({start=true,['end']=true,center=true,nearest=true})
function R.aligned(mode,start,size,viewport,padStart,padEnd,current,limit)
 local visibleStart=padStart;local visibleEnd=math.max(padStart,viewport-padEnd)
 local at
 if mode=='start'then at=start-visibleStart
 elseif mode=='end'then at=start+size-visibleEnd
 elseif mode=='center'then at=start+size/2-(visibleStart+visibleEnd)/2
 else
  at=current
  if start-current<visibleStart then at=start-visibleStart
  elseif start+size-current>visibleEnd then at=math.max(start-visibleStart,start+size-visibleEnd)end
 end
 return math.clamp(at,0,math.max(0,limit))
end
function R.into(c,node,options)
 options=options or{}
 local blockMode=options.block or'start'
 local inlineMode=options.inline or'nearest'
 assert(intoModes[blockMode]and intoModes[inlineMode],'scrollIntoView aceita start/center/end/nearest.')
 local moved=0;local target=node;local scroller=G.scroller(c,node,'parent');local first=true;local guard=0
 while scroller and guard<64 do
  guard+=1
  local port=c.objects[scroller.key];local style=c.styles[scroller.key];local box=c.boxes[scroller.key]
  local tb=c.boxes[target.key];local ts=c.styles[target.key]
  if port and port:IsA('ScrollingFrame')and style and box and tb and ts and not box.hidden and not tb.hidden then
   local w,h,mx,my=G.port(c,scroller)
   local pad=G.sides(style,'scroll-padding',w,h,c.width,c.height)
   local margin=G.sides(ts,'scroll-margin',tb.w,tb.h,c.width,c.height)
   local nx,ny=G.coordinate(c,target,scroller)
   local blockAxis=G.axis(style,'block')
   local current=port.CanvasPosition
   local modeX=first and(blockAxis=='x'and blockMode or inlineMode)or'nearest'
   local modeY=first and(blockAxis=='y'and blockMode or inlineMode)or'nearest'
   local scrollX,scrollY=R.axes(style)
   local x=scrollX and R.aligned(modeX,nx-margin[4],tb.w+margin[2]+margin[4],w,pad[4],pad[2],current.X,mx)or current.X
   local y=scrollY and R.aligned(modeY,ny-margin[1],tb.h+margin[1]+margin[3],h,pad[1],pad[3],current.Y,my)or current.Y
   if math.abs(x-current.X)>=0.5 or math.abs(y-current.Y)>=0.5 then
    R.scrollTo(port,x,y,options.behavior or Bars.behavior(style));moved+=1
   end
  end
  target=scroller;scroller=G.scroller(c,scroller,'parent');first=false
 end
 return moved
end
function R.records(c)
 local byKey,list={},{}
 for _,node in ipairs(c.sequence or{})do
  local object=c.objects[node.key];local style=c.styles[node.key]
  if object and object:IsA('ScrollingFrame')and style then
   local snap=U.trim(tostring(style['scroll-snap-type']or 'none'))~='none'
   local paged=Overflow.pagedAxis(style)
   if snap or paged then byKey[node.key]={node=node,targets={},paged=paged};list[#list+1]=byKey[node.key]end
  end
 end
 if #list==0 then return list end
 for _,node in ipairs(c.sequence or{})do
  local style=c.styles[node.key];local align=style and style['scroll-snap-align']
  if align and U.trim(tostring(align))~='none'then
   local at=c.parents[node.key]
   while at do
    local record=byKey[at.key]
    if record then table.insert(record.targets,node);break end
    at=c.parents[at.key]
   end
  end
 end
 return list
end
function R.snapTo(c,record,force,from)
 local port=c.objects[record.node.key]
 if not port or not port:IsA('ScrollingFrame')then return false end
 local box=c.boxes[record.node.key]
 if box==nil or box.hidden then return false end
 if #(record.targets or{})==0 and not record.paged then return false end
 local current=port.CanvasPosition
 local x,y=current.X,current.Y
 local page,axis=R.pageSize(record,box)
 if page then
  if axis=='x'then x=math.floor(current.X/page+0.5)*page else y=math.floor(current.Y/page+0.5)*page end
 end
 if #(record.targets or{})>0 then
  x=G.snap(c,record,'x',x,from and from.X or nil,force==true)
  y=G.snap(c,record,'y',y,from and from.Y or nil,force==true)
 end
 if math.abs(x-current.X)<0.5 and math.abs(y-current.Y)<0.5 then return false end
 R.scrollTo(port,x,y,Bars.behavior(c.styles[record.node.key]));return true
end
function R.progress(c)
 local motion=c.motion;if not motion or not motion.setProgress then return 0 end
 local index=Timeline.index(c);local changed=0
 for _,node in ipairs(c.sequence or{})do
  local descriptors=motion:timelines(node.key)
  if descriptors then
   local values={}
   for i,descriptor in pairs(descriptors)do values[i]=Timeline.resolve(c,node.key,descriptor,index)end
   if motion:setProgress(node.key,values)then changed+=1 end
  end
 end
 return changed
end
function R.new(controller)
 local self={controller=controller,links={},taps={},records={},starts={},alive=true,steps=0,snaps=0,generation=0,applying=false,chain={},contained={},last={},activeAt=0}
 function self:step()
  if not self.alive then return 0 end
  local c=self.controller;if not c or not c.styles or not c.sequence then return 0 end
  self.steps+=1;local changed=R.progress(c)
  if changed>0 and c.motion then c.motion:step(nil,true)end
  return changed
 end
 function self:settle(force)
  if not self.alive then return 0 end
  local c=self.controller;if not c or not c.styles then return 0 end
  local count=0;self.applying=true
  local ok,err=pcall(function()
   for _,record in ipairs(self.records)do
    if R.snapTo(c,record,force,self.starts[record.node.key])then count+=1 end
    self.starts[record.node.key]=nil
   end
  end)
  self.applying=false;if not ok then error(err,0)end
  if count>0 then self.snaps+=count;self:step()end
  return count
 end
 function self:changed(key,port)
  if not self.alive or self.applying or R.animating(port)then return end
  local now=os.clock();local active=self.active
  if active and active~=key and now-self.activeAt<=0.08 and self.contained[active]then
   local up=self.chain[active]
   while up do
    if up==key then
     local previous=self.last[port]
     if previous then self.applying=true;port.CanvasPosition=previous;self.applying=false end
     return
    end
    up=self.chain[up]
   end
  end
  self.last[port]=port.CanvasPosition;self.active=key;self.activeAt=now
  if self.starts[key]==nil then self.starts[key]=port.CanvasPosition end
  self:step()
  local c=self.controller
  if c and c.onScroll then pcall(c.onScroll,c,key,port)end
  if self.controller.manual then return end
  self.generation+=1;local generation=self.generation
  task.delay(0.12,function()
   if self.alive and self.generation==generation then pcall(self.settle,self,false)end
  end)
 end
 function self:sync()
  if not self.alive then return end
  local c=self.controller;if not c or not c.styles then return end
  self.records=R.records(c)
  local ports={}
  local chain,contained={},{}
  for _,node in ipairs(c.sequence or{})do
   local object=c.objects[node.key]
   if object and object:IsA('ScrollingFrame')then
    R.native(object,c.styles[node.key],c.boxes[node.key],c.width,c.height);ports[object]=node.key
    local ox,oy=R.overscroll(c.styles[node.key])
    if ox~='auto'or oy~='auto'then contained[node.key]=true end
    local up=c.parents[node.key]
    while up do
     local host=c.objects[up.key]
     if host and host:IsA('ScrollingFrame')then chain[node.key]=up.key;break end
     up=c.parents[up.key]
    end
   end
  end
  self.chain=chain;self.contained=contained
  for port in pairs(ports)do if self.last[port]==nil then self.last[port]=port.CanvasPosition end end
  for port,link in pairs(self.links)do if not ports[port]then link:Disconnect();self.links[port]=nil end end
  for port,key in pairs(ports)do
   if not self.links[port]then
    self.links[port]=port:GetPropertyChangedSignal('CanvasPosition'):Connect(function()self:changed(key,port)end)
   end
  end
  local taps={}
  for port,key in pairs(ports)do
   local axis,enabled=Overflow.pagedAxis(c.styles[key])
   local paint=axis and enabled==true and O.child(port,'__Paint')or nil
   if paint then
    for _,name in ipairs({'__PagePrev','__PageNext'})do
     local button=O.child(paint,name)
     local delta=button and button:GetAttribute('CssPageDelta')
     if button and delta then taps[button]={port=port,key=key,delta=delta}end
    end
   end
  end
  for button,record in pairs(self.taps)do
   local wanted=taps[button]
   if not wanted or wanted.port~=record.port or wanted.key~=record.key or wanted.delta~=record.delta then record.link:Disconnect();self.taps[button]=nil end
  end
  for button,wanted in pairs(taps)do
   if not self.taps[button]then
    local record={port=wanted.port,key=wanted.key,delta=wanted.delta}
    record.link=button.Activated:Connect(function()
     if not self.alive then return end
     local live=self.controller;if not live or not live.styles or not live.boxes then return end
     R.page(record.port,live.styles[record.key],live.boxes[record.key],record.delta)
    end)
    self.taps[button]=record
   end
  end
  self:step()
 end
 function self:stats()
  local ports=0;for _ in pairs(self.links)do ports+=1 end
  local controls=0;for _ in pairs(self.taps)do controls+=1 end
  return {ports=ports,snapContainers=#self.records,steps=self.steps,snaps=self.snaps,pageControls=controls}
 end
 function self:destroy()
  if not self.alive then return end;self.alive=false
  for port in pairs(self.links)do R.cancel(port)end
  for _,link in pairs(self.links)do link:Disconnect()end
  for _,record in pairs(self.taps)do record.link:Disconnect()end
  table.clear(self.links);table.clear(self.taps);table.clear(self.records);table.clear(self.starts);table.clear(self.chain);table.clear(self.contained);table.clear(self.last);self.controller=nil
 end
 return self
end
return R
