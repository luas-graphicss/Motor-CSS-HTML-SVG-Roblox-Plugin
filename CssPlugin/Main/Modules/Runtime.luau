local U=require(script.Parent.Util)
local Manifest=require(script.Parent.RuntimeManifest)
local Styles=require(script.Parent.Styles)
local Environment=require(script.Parent.ResponsiveEnvironment)
local Env=require(script.Parent.CssEnvironment)
local FontFaces=require(script.Parent.FontFaces)
local Layout=require(script.Parent.Layout)
local LayoutRuntime=require(script.Parent.LayoutRuntime)
local ScrollRuntime=require(script.Parent.ScrollRuntime)
local Paint=require(script.Parent.Paint)
local TransformPaint=require(script.Parent.TransformPaint)
local BackgroundRuntime=require(script.Parent.BackgroundRuntime)
local VisualEffects=require(script.Parent.VisualEffects)
local VisualEffectsGroups=require(script.Parent.VisualEffectsGroups)
local SvgRasterRuntime=require(script.Parent.SvgRasterRuntime)
local SvgCssRuntime=require(script.Parent.SvgCssRuntime)
local Motion=require(script.Parent.Motion)
local Ua=require(script.Parent.UserAgentStyles)
local MotionUniversal=Manifest.optional('MotionUniversal')
local ViewTransitions=require(script.Parent.ViewTransitions)
local Transform=require(script.Parent.Transform)
local Form=require(script.Parent.FormState)
local FormAppearance=require(script.Parent.FormAppearance)
local TextSelection=Manifest.optional('TextSelection')
local RenderOptimizer=require(script.Parent.RenderOptimizer)
local RuntimeResources=require(script.Parent.RuntimeResources)
local StateBindings=require(script.Parent.StateBindings)
local SvgSmil=Manifest.optional('SvgSmil')
local HitTesting=require(script.Parent.HitTesting)
local PointerInput=require(script.Parent.PointerInput)
local Performance=require(script.Parent.Performance)
local DirtyRender=require(script.Parent.DirtyRender)
local DirtyGraph=require(script.Parent.DirtyGraph)
local Http=game:GetService('HttpService')
local RunService=game:GetService('RunService')
local R={}
local controllers=setmetatable({}, {__mode='kv'})
local viewportAttributes={CssSmallViewportWidth='smallWidth',CssSmallViewportHeight='smallHeight',CssLargeViewportWidth='largeWidth',CssLargeViewportHeight='largeHeight',CssDynamicViewportWidth='dynamicWidth',CssDynamicViewportHeight='dynamicHeight'}
local stateNames=table.freeze({hover=true,active=true,focus=true,disabled=true})
local clear=table.clear
local function runQueuedRefresh(self)
 self.pending=false;self.pendingTask=nil
 if not self.alive then return end
 local ok,err=pcall(self.flush or self.refresh,self)
 if not ok then
  DirtyRender.reset(self.cache)
  local text=tostring(err)
  if self.lastError~=text then self.lastError=text;if self.development then warn('[CssPlugin] '..text)end end
 end
end
function R.render(doc,objects,width,height,state,cache,work)
 Ua.setProfile(doc.profile or 'legacy')
 local plan=DirtyRender.plan(doc,objects,width,height,state,cache,work)
 local styles,sequence,parents,stateNeeds=plan.styles,plan.sequence,plan.parents,plan.stateNeeds
 local baseStyles=plan.baseStyles or styles
 local boxes=plan.boxes;local animationCount=0
 VisualEffects.begin(objects,cache)
 for _,node in ipairs(sequence)do
  local key=node.key;local style=styles[key];local object=objects[key]
  local entry=cache[key];local parentNode=parents[key]
  local box=boxes[key];local boxW,boxH=box and box.w or 0,box and box.h or 0
  local context,contextKey=entry.transformContext,entry.transformContextKey
   
  if context==nil or contextKey==nil or entry.transformContextStyle~=style or entry.transformContextW~=boxW or entry.transformContextH~=boxH or entry.transformContextVW~=width or entry.transformContextVH~=height then
   context=Transform.context(style,box,width,height);contextKey=RenderOptimizer.signature(context)
   entry.transformContextStyle=style;entry.transformContextW=boxW;entry.transformContextH=boxH;entry.transformContextVW=width;entry.transformContextVH=height
  end
  local parentStyle=parentNode and styles[parentNode.key]or nil
  local perspective=(parentStyle and parentStyle.perspective and parentStyle.perspective~='none')and Transform.perspective(parentStyle,boxes[parentNode.key],box,width,height)or nil
  local perspectiveKey=RenderOptimizer.signature(perspective);local projectionChanged=entry.transformParentKey~=perspectiveKey
  entry.transformParent=perspective;entry.transformParentKey=perspectiveKey;entry.transformContext=context;entry.transformContextKey=contextKey
  entry.containingBox=parentNode and boxes[parentNode.key]or nil
  assert(not style['backface-visibility']or style['backface-visibility']=='visible'or style['backface-visibility']=='hidden','backface-visibility aceita visible/hidden.')
  local motionStyle=baseStyles[key]or style
  if entry.validatedStyle~=motionStyle or entry.validatedWidth~=width or entry.validatedFrames~=doc.keyframes or entry.validatedContext~=contextKey then
   local transitions=Motion.transitions(motionStyle);local prepared=Motion.prepare(motionStyle,doc.keyframes,width,Styles.resolveValue,context)
   entry.animationCount=#prepared;local opacitySpec=transitions.opacity
   entry.motionOpacityPotential=opacitySpec~=nil and opacitySpec.duration+opacitySpec.delay>0
   for _,animation in ipairs(prepared)do if animation.frames.opacity and animation.iterations>0 then entry.motionOpacityPotential=true;break end end
   entry.validatedStyle=motionStyle;entry.validatedWidth=width;entry.validatedFrames=doc.keyframes;entry.validatedContext=contextKey
  end
  animationCount+=entry.animationCount or 0
  assert(animationCount<=128,'Máximo de 128 animações por interface.')
  local parent=parents[key];local opacity=math.clamp(tonumber(style.opacity)or 1,0,1)*(parent and cache[parent.key].cumulativeOpacity or 1)
  cache[key]=cache[key]or {};cache[key].cumulativeOpacity=opacity
  if object then
   local paintBox=RenderOptimizer.paintBox(node,boxes[key],parents,objects,boxes)
   paintBox=BackgroundRuntime.paintBox(node,paintBox,boxes,parents,objects);paintBox._checkpoint=work and work.checkpoint
   if projectionChanged or DirtyRender.paintNeeded(plan,key,entry,object,style,paintBox,1)then
    Paint.apply(node,object,style,paintBox,1,width,height,entry,node.key==doc.root.key)
    DirtyRender.painted(plan,entry,object,style,paintBox,1);entry.motionNeedsPaint=true
   end
   local receives=HitTesting.receives(style)
   if not receives then
    if entry.pointerActive==nil then entry.pointerActive=object.Active end
    RenderOptimizer.properties(object,{Active=false})
   elseif entry.pointerActive~=nil then RenderOptimizer.properties(object,{Active=entry.pointerActive});entry.pointerActive=nil end
   if receives then if object:GetAttribute('CssPointerEvents')~=nil then object:SetAttribute('CssPointerEvents',nil)end else RenderOptimizer.attributes(object,{CssPointerEvents='none'})end
   entry.userSelect=HitTesting.selectable(style)
   if object:IsA('GuiButton')or object:IsA('TextBox')then
    local disabled=(state[key]and state[key].disabled)or false
    local native=FormAppearance.native(node,object,style,state[key],work and work.mediaEnvironment)
    native.Interactable=not disabled and receives
    native.Selectable=FormAppearance.focusable(node,style,state[key])
    native.SelectionOrder=FormAppearance.focusOrder(node)
    RenderOptimizer.properties(object,native)
    if object:IsA('TextBox')then
     RenderOptimizer.properties(object,{TextEditable=not disabled and not Form.evaluate(node,state[key])['read-only']})
     local selection=node.interfacePseudo and node.interfacePseudo.selection or nil
     entry.selectionStyle=selection
     if entry.userSelect==false and object.SelectionStart~=-1 then object.SelectionStart=-1 end
     TextSelection.apply(object,entry.userSelect==false and nil or selection)
    end
   end
  end
  if work and work.checkpoint then work.checkpoint()end
 end
 local svgStatus=SvgCssRuntime.render(doc,objects,styles,boxes,sequence,parents,state,cache,width,height,work,stateNeeds,function(node,object,style,box,entry)
  local paintBox=RenderOptimizer.paintBox(node,box,parents,objects,boxes)
  paintBox=BackgroundRuntime.paintBox(node,paintBox,boxes,parents,objects);paintBox._checkpoint=work and work.checkpoint
  Paint.apply(node,object,style,paintBox,1,width,height,entry,node.key==doc.root.key)
 end)
 if type(plan.stats)=='table'then plan.stats.svg=svgStatus end
 VisualEffects.finish(doc,objects,styles,boxes,sequence,parents,cache,width,height,work)
 local root=objects[doc.root.key];local container=VisualEffectsGroups.root(root).Parent
 local hosts=nil
 for _,node in ipairs(sequence)do
  local box=boxes[node.key]
  if box and box.fixedHost==true and node.key~=doc.root.key and objects[node.key]then hosts=hosts or{};hosts[node.key]=root end
 end
 if container then RenderOptimizer.mount(doc.root,sequence,parents,objects,container,work and work.checkpoint,hosts)end
 return boxes,styles,sequence,parents,stateNeeds,plan.stats,hosts,baseStyles
end
function R.viewport(gui,width,height,explicit,measured)
 local out={dynamicWidth=width,dynamicHeight=height,smallWidth=width,smallHeight=height,largeWidth=width,largeHeight=height}
 if measured then
  local okInset,topLeft,bottomRight=pcall(function()return game:GetService('GuiService'):GetGuiInset()end)
  local top=(okInset and typeof(topLeft)=='Vector2')and topLeft.Y or 0
  local bottom=(okInset and typeof(bottomRight)=='Vector2')and bottomRight.Y or 0
  local camera=workspace.CurrentCamera
  local size=camera and camera.ViewportSize
  if size and size.X>=1 and size.Y>=1 and math.abs(size.X-width)<=1 then
   out.largeWidth=size.X;out.largeHeight=size.Y
   out.smallWidth=size.X;out.smallHeight=math.max(size.Y-top-bottom,1)
  elseif top+bottom>0 then
   out.largeHeight=height+top+bottom;out.smallHeight=math.max(height-top-bottom,1)
  end
 end
 if gui then
  for attribute,key in pairs(viewportAttributes)do
   local value=gui:GetAttribute(attribute)
   if type(value)=='number'and value>0 then out[key]=value end
  end
 end
 if explicit then
  for key,value in pairs(explicit)do
   assert(out[key]~=nil,'Métrica de viewport inválida: '..tostring(key))
   assert(type(value)=='number'and value>0,'Métrica de viewport exige número positivo.')
   out[key]=value
  end
 end
 return out
end
local function canvasOffset(self,key)
 local object=self.objects and self.objects[key]
 if object and object:IsA('ScrollingFrame')then local position=object.CanvasPosition;return position.X,position.Y end
 return 0,0
end
local function intersects(x,y,right,bottom,width,height,clip,mx,my)
 local x1,y1,x2,y2=-mx,-my,width+mx,height+my
 if clip then
  x1=math.max(x1,clip[1]-mx);y1=math.max(y1,clip[2]-my)
  x2=math.min(x2,clip[3]+mx);y2=math.min(y2,clip[4]+my)
 end
 return not(x>x2 or y>y2 or right<x1 or bottom<y1)
end
function R.syncContentVisibility(self,width,height)
 local styles=self.styles;local boxes=self.boxes;local sequence=self.sequence
 if not styles or not boxes or not sequence then return false end
 local map=self.contentVisibility or {}
 local left,top,clips={},{},{}
 local marginX=math.max(width,1)*.5;local marginY=math.max(height,1)*.5
 local changed=false
 for _,node in ipairs(sequence)do
  local key=node.key;local box=boxes[key]
  if box then
   local parent=self.parents[key]
   local ox,oy,clip=0,0,nil
   if parent and not box.fixed then
    ox=left[parent.key]or 0;oy=top[parent.key]or 0;clip=clips[parent.key]
    local sx,sy=canvasOffset(self,parent.key)
    ox-=sx;oy-=sy
   end
   local x=ox+(tonumber(box.x)or 0);local y=oy+(tonumber(box.y)or 0)
   left[key]=x;top[key]=y
   local right=x+(tonumber(box.w)or 0);local bottom=y+(tonumber(box.h)or 0)
   local style=styles[key]
   if box.clipsContent==true or(style~=nil and(style._overflowClipX==true or style._overflowClipY==true))then
    local x1,y1,x2,y2=x,y,right,bottom
    if clip then x1=math.max(x1,clip[1]);y1=math.max(y1,clip[2]);x2=math.min(x2,clip[3]);y2=math.min(y2,clip[4])end
    clips[key]={x1,y1,x2,y2}
   else clips[key]=clip end
   if style~=nil and style._contentVisibility=='auto'then
    local wide=intersects(x,y,right,bottom,width,height,clip,marginX,marginY)
    local tight=intersects(x,y,right,bottom,width,height,clip,marginX*.5,marginY*.5)
    local skipped
    if box.hidden==true then skipped=true elseif map[key]==true then skipped=not tight else skipped=not wide end
    if map[key]~=skipped then
     map[key]=skipped;changed=true;self.dirtyKeys[key]=true
     if self.graph then self.graph:touch(key,'layout')end
    end
   elseif map[key]~=nil then map[key]=nil end
  end
 end
 for key in pairs(map)do if styles[key]==nil then map[key]=nil end end
 self.contentVisibility=map
 if changed then
  self.dirtyStyles=true
  if not self.manual and not self.pending and self.frameScheduler then self.pending=true;self.frameScheduler:request()end
 end
 return changed
end
function R.attach(gui,options)
 if controllers[gui]then return controllers[gui]end
 options=U.copy(options);local mediaOverrides=Environment.overrides(options);local value=gui:FindFirstChild('_CssDocument');assert(value and value:IsA('StringValue'),'Documento CSS ausente.')
 if options.svgImages~=nil then gui:SetAttribute('CssSvgImages',options.svgImages==true)end
 local text=value.Value;local parts=value:GetAttribute('CssDocumentParts')
 if type(parts)=='number'then for i=2,parts do local part=value:FindFirstChild('Part'..i);assert(part and part:IsA('StringValue'),'Documento CSS incompleto.');text..=part.Value end end
 local doc=Http:JSONDecode(text);assert(doc.version==1 or doc.version==2,'Versão de documento não suportada.')
 Manifest.verify(gui)
 if options.effectImages~=nil then doc.effectImages=options.effectImages==true end
 local self={gui=gui,document=doc,objects={},state={},cache={},connections={},nodeConnections={},ids={},nodes={},nodeParents={},alive=true,pending=false,nodeCount=0,nextDynamic=0,maxOrder=0,layoutPasses=0}
 self.interactive={};self.objectKeys={};self.dirtyKeys={};self.graph=DirtyGraph.new();self.motionOverlay={}
 self.mediaOverrides=mediaOverrides;self.mediaEnvironment=Environment.read(gui,mediaOverrides,options.useStudioTheme==true)
 self.manual=options.manual==true;self.development=options.development==true or gui:GetAttribute('CssDevelopment')==true
 local layoutEvent=Instance.new('BindableEvent');self.LayoutChanged=layoutEvent.Event
 controllers[gui]=self
 local function collect(node,parent)
  self.nodeCount+=1;self.nodes[node.key]=node;self.nodeParents[node.key]=parent;self.maxOrder=math.max(self.maxOrder,node.order)
  if node.attrs.id then self.ids[node.attrs.id]=node.key end
  self.state[node.key]=Form.initial(node)
  for _,child in ipairs(node.children)do collect(child,node)end
 end
 collect(doc.root,nil)
 for _,o in ipairs(gui:GetDescendants())do local key=o:GetAttribute('CssNodeKey');if key then self.objects[key]=o end end
 assert(self.objects[doc.root.key],'Raiz de layout ausente.')
 local function keyOf(id)return self.ids[id]or id end
 function self:get(id)return self.objects[keyOf(id)]end
 function self:effectHitTest(id,x,y)return VisualEffects.hitTest(self.cache,keyOf(id),x,y)end
 function self:effectStats()return VisualEffects.stats(self.cache)end
 function self:transformHitTest(id,x,y)
  local key=typeof(id)=='Instance'and self.objectKeys[id]or keyOf(id)
  local entry=self.cache[key]
  if entry==nil then return false end
  local hit,lx,ly=TransformPaint.hitTest(entry,x,y)
  if not hit then return false end
  return true,lx,ly
 end
 function self:transformMatrix(id)
  local key=typeof(id)=='Instance'and self.objectKeys[id]or keyOf(id)
  local entry=self.cache[key]
  return entry and TransformPaint.matrix(entry)or nil
 end
 function self:transformRoute(id)
  local key=typeof(id)=='Instance'and self.objectKeys[id]or keyOf(id)
  local entry=self.cache[key]
  local plan=entry and TransformPaint.plan(entry)or nil
  if plan==nil then return nil end
  return {route=plan.route,reasons=plan.reasons,raster=plan.raster==true,rastered=entry.transformRastered==true,backFacing=plan.backFacing==true,visible=plan.visible~=false}
 end
 function self:effectHitTestTransformed(id,x,y)
  local key=typeof(id)=='Instance'and self.objectKeys[id]or keyOf(id)
  local entry=self.cache[key]
  local lx,ly=x,y
  if entry then
   local plan=TransformPaint.plan(entry)
   if plan and plan.matrix then
    local hit,tx,ty=TransformPaint.hitTest(entry,x,y)
    if not hit then return false end
    lx,ly=tx,ty
   end
  end
  return VisualEffects.hitTest(self.cache,key,lx,ly),lx,ly
 end
 local function nameOf(key)
  local node=self.nodes[key]
  return node and(node.attrs.id or key)or key
 end
 function self:hitTest(id,x,y)
  local key=typeof(id)=='Instance'and self.objectKeys[id]or keyOf(id)
  if not self.nodes[key]then return false end
  return HitTesting.test(self,key,x,y)
 end
 function self:localPoint(id,x,y)
  local key=typeof(id)=='Instance'and self.objectKeys[id]or keyOf(id)
  if not self.nodes[key]then return nil end
  return HitTesting.localPoint(self,key,x,y)
 end
 function self:pick(x,y)
  local key,lx,ly,pseudo=HitTesting.pick(self,x,y)
  if key==nil then return nil end
  return nameOf(key),lx,ly,key,pseudo
 end
 function self:pickScreen(sx,sy)
  local x,y=HitTesting.fromScreen(self,sx,sy)
  return self:pick(x,y)
 end
 function self:cursorAt(x,y)
  local key=HitTesting.pick(self,x,y)
  return HitTesting.cursorOf(self,key)
 end
 function self:pointerMove(x,y)
  if not self.pointer then return nil end
  local key=self.pointer:move(x,y)
  return key and nameOf(key)or nil
 end
 function self:pointerDown(x,y)if self.pointer then self.pointer:press(x,y)end end
 function self:pointerUp()if self.pointer then self.pointer:release()end end
 function self:pointerLeave()if self.pointer then self.pointer:leave()end end
 function self:hovered()
  local key=self.pointer and self.pointer.hoverKey
  return key and nameOf(key)or nil
 end
 function self:getInteractive(id)
  local key=typeof(id)=='Instance'and self.objectKeys[id]or keyOf(id)
  local entry=self.interactive[key]
  if entry and self.objects[key]==entry.object then return entry end
  return nil
 end
 local animate=options.animate
 if animate==nil then animate=not options.manual and RunService:IsRunning()and RunService:IsClient()end
 local function reducedPreference()return self.mediaEnvironment.reducedMotion end
 local function applyMotion(values,force)
  if not self.alive or not self.sequence then return end
  VisualEffects.begin(self.objects,self.cache)
  for _,node in ipairs(self.sequence)do
   local key=node.key;local v=values[key];local parent=self.parents[key]
   if v then
    local opacity=v.opacity*(parent and self.cache[parent.key].motionOpacity or 1)
    local c=self.cache[key];c.motionOpacity=opacity
    if self.objects[key]and(force or c.motionNeedsPaint or c.lastMotionValues~=v or c.lastCumulativeOpacity~=opacity)then
     Paint.applyMotion(self.objects[key],self.styles[key],v,1,c,force or c.motionNeedsPaint)
     c.motionNeedsPaint=nil;c.lastMotionValues=v;c.lastCumulativeOpacity=opacity
    end
   end
  end
  VisualEffects.finish(doc,self.objects,self.styles,self.boxes,self.sequence,self.parents,self.cache,self.width or doc.width,self.height or doc.height,nil,values)
  RenderOptimizer.mount(doc.root,self.sequence,self.parents,self.objects,gui,nil,self.visualHosts)
  if self:_syncMotionOverlay(values)and not self.manual and not self.pending and self.frameScheduler then self.pending=true;self.frameScheduler:request()end
 end
 function self:_syncMotionOverlay(values)
  local overlay=self.motionOverlay;local records=self.motion and self.motion.nodes
  if not overlay or not records then return false end
  local touched=false
  for _,node in ipairs(self.sequence)do
   local key=node.key;local v=values[key];local record=records[key]
   local current=overlay[key]
   if v and record then
    for p,value in pairs(v)do
     if type(value)=='table'and value.t~=nil and MotionUniversal.supports(p)then
      local settled=record.base[p]==value
      local baseStyle=(self.baseStyles or self.styles)[key]
      local text=not settled and MotionUniversal.materialize(p,value,baseStyle and baseStyle[p])or nil
      if text~=nil then
       if current==nil then current={};overlay[key]=current end
       if current[p]~=text then current[p]=text;touched=true;self.dirtyKeys[key]=true;self.dirtyStyles=true;if self.graph and not DirtyRender.isVisual(p)then self.graph:touch(key,'layout')end end
      elseif current and current[p]~=nil then
       current[p]=nil;touched=true;self.dirtyKeys[key]=true;self.dirtyStyles=true;if self.graph and not DirtyRender.isVisual(p)then self.graph:touch(key,'layout')end
      end
     end
    end
   elseif current then
    overlay[key]=nil;touched=true;self.dirtyKeys[key]=true;self.dirtyStyles=true;if self.graph then self.graph:touch(key,'layout')end
   end
   if current and next(current)==nil then overlay[key]=nil end
  end
  return touched
 end
 if animate then self.motion=Motion.new({manual=options.motionManual==true,clock=options.clock,reduced=reducedPreference(),apply=applyMotion,development=self.development})end
 self.layoutRuntime=LayoutRuntime.new(self)
 self.scrollRuntime=ScrollRuntime.new(self)
 function self:onScroll()
  if not self.alive or not self.styles then return end
  R.syncContentVisibility(self,self.width or doc.width,self.height or doc.height)
 end
 function self:scrollIntoView(id,options)
  assert(self.alive,'Controller encerrado.')
  local key=typeof(id)=='Instance'and self.objectKeys[id]or keyOf(id)
  local node=assert(self.nodes[key],'ID desconhecido.')
  assert(self.boxes and self.styles,'Layout ainda nao resolvido.')
  local moved=ScrollRuntime.into(self,node,options)
  if moved>0 then R.syncContentVisibility(self,self.width or doc.width,self.height or doc.height)end
  return moved
 end
 function self:scrollTo(id,x,y,behavior)
  assert(self.alive,'Controller encerrado.')
  local key=typeof(id)=='Instance'and self.objectKeys[id]or keyOf(id)
  local port=assert(self.objects[key],'ID desconhecido.')
  assert(port:IsA('ScrollingFrame'),'Elemento nao e um container de scroll.')
  local style=self.styles and self.styles[key]
  local position=port.CanvasPosition
  ScrollRuntime.scrollTo(port,tonumber(x)or position.X,tonumber(y)or position.Y,behavior or(style and ScrollRuntime.behavior(style))or'auto')
  return port.CanvasPosition
 end
 function self:scrollInfo(id)
  assert(self.alive,'Controller encerrado.')
  local key=typeof(id)=='Instance'and self.objectKeys[id]or keyOf(id)
  assert(self.nodes[key],'ID desconhecido.')
  local port=self.objects[key];local box=self.boxes and self.boxes[key];local style=self.styles and self.styles[key]
  if not port or not port:IsA('ScrollingFrame')or not box or not style then return nil end
  local pages,axis=ScrollRuntime.pages(style,box)
  local overscrollX,overscrollY=ScrollRuntime.overscroll(style)
  local scrollX,scrollY=ScrollRuntime.axes(style)
  return {x=port.CanvasPosition.X,y=port.CanvasPosition.Y,width=box.w,height=box.h,contentWidth=box.contentW,contentHeight=box.contentH,
   pages=pages,pagedAxis=axis,scrollX=scrollX,scrollY=scrollY,overscrollX=overscrollX,overscrollY=overscrollY,
   scrollbar=ScrollRuntime.thickness(style),behavior=ScrollRuntime.behavior(style)}
 end
 local svgSource=options.clock or os.clock
 local svgEpoch=svgSource()
 local function svgClock()return svgSource()-svgEpoch end
 local bind
 function self:refresh(width,height,work)
  if not self.alive then return end
  if self._syncMediaEnvironment then self:_syncMediaEnvironment(false)end
  work=table.clone(work or {});work.mediaEnvironment=self.mediaEnvironment
  if self._syncEnvironment then self:_syncEnvironment(false)end
  work.environment=self.environment;work.environmentKey=self.environmentKey
  if self.frameScheduler then self.frameScheduler:cancel()end;self.pending=false
  self.dirtyText=false;self.dirtyStyles=false;self.dirtyAll=false;clear(self.dirtyKeys)
  if self.graph and not work.dirtyKeys and self.graph:pending()then work.dirtyKeys=self.graph:consume()end
  if work.dirtyKeys and work.dirtyKeys.full then work.full=true end
  local measured=width==nil and height==nil
  width=width or gui.AbsoluteSize.X;height=height or gui.AbsoluteSize.Y
  if width<1 or height<1 then width,height=doc.width,doc.height;measured=false end
  work.viewport=R.viewport(gui,width,height,self.viewportOverrides or(options and options.viewport),measured)
  work.svgNow=self.svgClockOverride or svgClock();work.reducedMotion=self.mediaEnvironment~=nil and self.mediaEnvironment.reducedMotion==true
  work.contentVisibility=self.contentVisibility;work.motionOverlay=self.motionOverlay
  if self._syncFormState then self:_syncFormState()end
  local previousSequence=self.sequence
  self.boxes,self.styles,self.sequence,self.parents,self.stateNeeds,self.renderStats,self.visualHosts,self.baseStyles=R.render(doc,self.objects,width,height,self.state,self.cache,work)
  self.regions=work.regions
  if self.graph then self.graph:structure(self.sequence,self.parents)end
  for _,old in ipairs(previousSequence or {})do
   if old.generated and not self.styles[old.key]then
    if self.motion then self.motion:remove(old.key)end
    self.state[old.key]=nil;self.cache[old.key]=nil
   end
  end
  R.syncContentVisibility(self,width,height)
  self.width,self.height=width,height;self.refreshPasses=(self.refreshPasses or 0)+1
  if self.renderStats.relayout then self.layoutPasses+=1 end
  for key,entry in pairs(self.interactive)do if self.objects[key]~=entry.object then self.objectKeys[entry.object]=nil;self.interactive[key]=nil end end
  if bind then for key,object in pairs(self.objects)do if self.nodes[key]and not self.nodeConnections[key]then bind(key,object)end end end
  if self.stateBindings then self.stateBindings:sync(self.stateNeeds)end
  local svgStatus=type(self.renderStats)=='table'and self.renderStats.svg or nil
  if self.svgInteraction then self.svgInteraction:sync(svgStatus)end
  if self.svgDriver and not self.manual then self.svgDriver:sync(svgStatus and svgStatus.animation or nil)end
  if self.pointer then self.pointer:sync()end
  if self._syncResources then self:_syncResources()end
  if self.motion then
   for _,node in ipairs(self.sequence)do
    local key=node.key;local parent=self.parents[key];local c=self.cache[key]
    local motionStyle=(self.baseStyles or self.styles)[key]or self.styles[key]
    local visible=self.styles[key].display~='none'and(not parent or self.cache[parent.key].motionVisible)
    if c.motionStyleRef~=motionStyle or c.motionWidth~=width or c.motionVisible~=visible or c.motionContextKey~=c.transformContextKey then
     self.motion:update(key,motionStyle,doc.keyframes,width,Styles.resolveValue,visible,c.transformContext)
     c.motionStyleRef=motionStyle;c.motionWidth=width;c.motionContextKey=c.transformContextKey
    end
    c.motionVisible=visible
   end
   self.motion:step(nil,false)
  end
  if self.layoutRuntime then self.layoutRuntime:sync()end
  if self.scrollRuntime then self.scrollRuntime:sync()end
  if self.backgroundRuntime then self.backgroundRuntime:sync()end
  gui:SetAttribute('CssRuntimeReady',true);layoutEvent:Fire(self.boxes,width,height)
 end
 function self:flush()
  if not self.alive then return end
  local work={textOnly=self.dirtyText and not self.dirtyStyles and not self.dirtyAll,full=self.dirtyAll==true}
  if self.graph and self.graph:pending()then
   local plan=self.graph:consume()
   if work.full or plan.full then work.full=true else work.dirtyKeys=plan end
  end
  return self:refresh(self.manual and self.width or nil,self.manual and self.height or nil,work)
 end
 self.frameScheduler=Performance.coalesce(function()runQueuedRefresh(self)end,{signal=options.frameSignal})
 local function queue(key,kind)
  if not self.alive then return end
  if type(key)=='string'then
   self.dirtyKeys[key]=true
   if kind=='text'then self.dirtyText=true else self.dirtyStyles=true end
   if self.graph then self.graph:touch(key,(kind=='text'or kind=='layout')and'layout'or kind=='paint'and'paint'or'style')end
  else
   self.dirtyAll=true;if self.graph then self.graph:full(tostring(kind or 'completo'))end
  end
  if self.pending or self.manual then return end
  self.pending=true;self.frameScheduler:request()
 end
 local function connect(signal,callback,key)
  local c=signal:Connect(callback);table.insert(self.connections,c)
  if self._connectionPositions then self._connectionPositions[c]=#self.connections end
  if key then self.nodeConnections[key]=self.nodeConnections[key]or {};table.insert(self.nodeConnections[key],c)end;return c
 end
 local function setStateKey(key,name,value)
  if not self.state[key]then return end
  if self.state[key][name]~=value then self.state[key][name]=value;queue(key,'style')end
 end
 self.pointer=PointerInput.new(self,connect,setStateKey,options)
 self.stateBindings=StateBindings.new(self,connect,setStateKey)
 self.svgInteraction=SvgSmil.interaction(self,connect,queue,function()return self.svgClockOverride or svgClock()end)
 self.svgDriver=animate and SvgSmil.driver(queue,svgClock,{fps=options.svgAnimationFps or(doc.svgOptions and doc.svgOptions.animationFps)})or nil
 function self:setState(id,name,value)
  local key=keyOf(id);assert(self.state[key],'ID desconhecido: '..id)
  if name=='checked'then return self:setChecked(id,value)end
  if name=='read-only'or name=='readonly'then return self:setReadOnly(id,value)end
  if name=='valid'then return self:setValidity(id,value==true)end
  if name=='invalid'then return self:setValidity(id,value~=true)end
  if name=='target'then return self:setTarget(value and self.nodes[key].attrs.id or nil)end
  assert(stateNames[name],'Estado inválido.');setStateKey(key,name,value==true)
 end
 function self:setDisabled(id,disabled)
  local key=keyOf(id);local o=assert(self.objects[key],'ID desconhecido.');disabled=disabled==true
  if self.state[key].disabled==disabled and o:GetAttribute('CssDisabled')==disabled then return end
  self.state[key].disabled=disabled;o:SetAttribute('CssDisabled',disabled);queue(key,'style')
 end
 function self:setClass(id,className)
  local key=keyOf(id);local o=assert(self.objects[key],'ID desconhecido.');assert(type(className)=='string'and #className<=1000,'Classe inválida.')
  if self.nodes[key].attrs.class==className and o:GetAttribute('CssClass')==className then return end
  self.nodes[key].attrs.class=className;o:SetAttribute('CssClass',className);queue(key,'style')
 end
 local GuiService=game:GetService('GuiService')
 local function focusEligible(node)
  local object=self.objects[node.key]
  return object~=nil and(object:IsA('GuiButton')or object:IsA('TextBox'))
 end
 local function focusRing()return FormAppearance.ring(self.sequence,self.styles,self.state,focusEligible)end
 local function focusName(key)
  local node=self.nodes[key]
  return node and(node.attrs.id or key)or key
 end
 local function applyFocus(key,object,keyboardLike)
  if object:IsA('TextBox')then pcall(function()object:CaptureFocus()end)
  else pcall(function()GuiService.SelectedObject=object end)end
  setStateKey(key,'focus',true);self.focusKey=key
  setStateKey(key,'focus-visible',FormAppearance.focusVisible(self.nodes[key],keyboardLike==true or StateBindings.keyboard()))
  return focusName(key)
 end
 function self:focus(id)
  local key=typeof(id)=='Instance'and self.objectKeys[id]or keyOf(id)
  local node=assert(self.nodes[key],'ID desconhecido.');local object=assert(self.objects[key],'ID desconhecido.')
  assert(focusEligible(node),'Elemento não recebe foco: '..tostring(id))
  assert(FormAppearance.focusable(node,self.styles and self.styles[key],self.state[key]),'Elemento não focalizável: '..tostring(id))
  return applyFocus(key,object)
 end
 function self:blur(id)
  local key=id~=nil and(typeof(id)=='Instance'and self.objectKeys[id]or keyOf(id))or self.focusKey
  local object=key and self.objects[key]
  if not object then return nil end
  if object:IsA('TextBox')then pcall(function()object:ReleaseFocus(false)end)end
  pcall(function()if GuiService.SelectedObject==object then GuiService.SelectedObject=nil end end)
  setStateKey(key,'focus',false);setStateKey(key,'focus-visible',false);if self.focusKey==key then self.focusKey=nil end
  return focusName(key)
 end
 function self:focused()
  local key=self.focusKey
  if not key or not self.objects[key]then
   key=nil
   for candidate,s in pairs(self.state)do if s.focus and self.objects[candidate]then key=candidate;break end end
  end
  return key and focusName(key)or nil
 end
 function self:focusNext(step)
  step=tonumber(step)or 1;assert(step==math.floor(step),'focusNext aceita um inteiro.')
  local ring=focusRing();if #ring==0 then return nil end
  local current=self.focusKey
  if not current or not self.objects[current]then
   current=nil
   for _,entry in ipairs(ring)do local s=self.state[entry.key];if s and s.focus then current=entry.key;break end end
  end
  local index=0
  for i,entry in ipairs(ring)do if entry.key==current then index=i;break end end
  local target=index==0 and ring[step>=0 and 1 or #ring]or ring[((index-1+step)%#ring)+1]
  if current and current~=target.key then self:blur(current)end
  return applyFocus(target.key,self.objects[target.key],true)
 end
 function self:focusPrevious()return self:focusNext(-1)end
 function self:focusOrder()
  local out={}
  for _,entry in ipairs(focusRing())do out[#out+1]=focusName(entry.key)end
  return out
 end
 if self.pointer then self.pointer:installKeyboard(function(step)return self:focusNext(step)end)end
 function self:setViewportMetrics(values)
  assert(self.alive,'Controller encerrado.')
  if values==nil then self.viewportOverrides=nil
  else
   assert(type(values)=='table','setViewportMetrics exige tabela.')
   self.viewportOverrides=table.clone(values)
  end
  queue(nil,'style')
 end
 function self:getViewportMetrics()
  assert(self.alive,'Controller encerrado.')
  return R.viewport(gui,self.width or gui.AbsoluteSize.X,self.height or gui.AbsoluteSize.Y,self.viewportOverrides or(options and options.viewport),self.width==nil and self.height==nil)
 end
 function self:setSvgClass(svgId,elementId,className)
  assert(self.alive,'Controller encerrado.');local key=keyOf(svgId)
  SvgCssRuntime.setClass(doc,key,elementId,className);queue(key,'style')
 end
 local function svgElementKey(key,elementId)
  local source=assert(doc.svgSources and doc.svgSources[key],'Elemento não é um SVG.')
  if elementId==nil then return key end
  local found
  local function walk(n)if n.attrs.id==elementId then found=n.key;return true end;for _,c in ipairs(n.children or {})do if walk(c)then return true end end;return false end
  assert(walk(source),'ID SVG desconhecido: '..tostring(elementId))
  return found
 end
 local function svgIds(key)
  local node=self.cache[key]and self.cache[key].svgResolved;local ids={}
  local function walk(n)if n.attrs.id then ids[n.key]=n.attrs.id end;for _,c in ipairs(n.children or {})do walk(c)end end
  if node then walk(node)end
  return ids
 end
 function self:setSvgTime(seconds)
  assert(self.alive,'Controller encerrado.')
  self.svgClockOverride=seconds~=nil and assert(tonumber(seconds),'setSvgTime exige número ou nil.')or nil
  for key in pairs(doc.svgSources or {})do queue(key,'style')end
 end
 function self:getSvgTime()return self.svgClockOverride or svgClock()end
 function self:svgHit(svgId,x,y)
  assert(self.alive,'Controller encerrado.');local key=keyOf(svgId)
  local chain=self.svgInteraction and self.svgInteraction:chainAt(key,x,y)or nil
  if not chain then return nil end
  local ids=svgIds(key);local out={}
  for i,k in ipairs(chain)do out[i]=ids[k]or k end
  return out
 end
 function self:svgPointer(svgId,x,y)
  assert(self.alive,'Controller encerrado.');local key=keyOf(svgId)
  local chain=self.svgInteraction and self.svgInteraction:pointer(key,x,y)or nil
  if not chain or #chain==0 then return nil end
  local ids=svgIds(key);local last=chain[#chain]
  return ids[last]or last
 end
 function self:svgPress(svgId)assert(self.alive,'Controller encerrado.');if self.svgInteraction then self.svgInteraction:press(keyOf(svgId))end end
 function self:svgRelease(svgId)assert(self.alive,'Controller encerrado.');if self.svgInteraction then self.svgInteraction:release(keyOf(svgId))end end
 function self:svgEvent(svgId,elementId,name)
  assert(self.alive,'Controller encerrado.');local key=keyOf(svgId)
  local target=svgElementKey(key,elementId)
  if self.svgInteraction then self.svgInteraction:fire(key,target,tostring(name or 'click'):lower())end
 end
 function self:svgAnimation()
  local status=type(self.renderStats)=='table'and self.renderStats.svg or nil
  local animation=status and status.animation or {active=false,keys={}}
  return {active=animation.active==true,next=animation.next,animated=#(animation.keys or {}),interactive=self.svgInteraction and self.svgInteraction.count or 0}
 end
 function self:registerFont(family,asset,weight,slant)
  assert(self.alive,'Controller encerrado.')
  local face=FontFaces.register(doc,family,asset,weight,slant)
  Styles.invalidate(doc.root);DirtyRender.reset(self.cache);queue(nil,'style')
  return face
 end
 bind=function(key,object)
  local node=self.nodes[key]
  if object:IsA('GuiButton')or object:IsA('TextBox')then
   self.interactive[key]={key=key,id=node.attrs.id,node=node,object=object,isInput=object:IsA('TextBox'),isButton=object:IsA('GuiButton')};self.objectKeys[object]=key
  end
  if object:GetAttribute('CssDisabled')~=nil then self.state[key].disabled=object:GetAttribute('CssDisabled')==true end
  if object:GetAttribute('CssClass')~=nil then node.attrs.class=object:GetAttribute('CssClass')end
  connect(object:GetAttributeChangedSignal('CssClass'),function()node.attrs.class=object:GetAttribute('CssClass')or '';queue(key,'style')end,key)
  if object:IsA('GuiButton')or object:IsA('TextBox')then
   connect(object:GetAttributeChangedSignal('CssDisabled'),function()if self.state[key]then self.state[key].disabled=object:GetAttribute('CssDisabled')==true;queue(key,'style')end end,key)
  end
  if object:IsA('TextLabel')or object:IsA('TextButton')or object:IsA('TextBox')then connect(object:GetPropertyChangedSignal('Text'),function()queue(key,'text')end,key)end
  if object:IsA('TextBox')then
   local function selectionChanged()
    if not self.alive then return end
    local entry=self.cache[key]
    if entry and entry.userSelect==false then
     if object.SelectionStart~=-1 then object.SelectionStart=-1 end
     TextSelection.apply(object,nil);return
    end
    TextSelection.apply(object,entry and entry.selectionStyle or nil)
   end
   connect(object:GetPropertyChangedSignal('SelectionStart'),selectionChanged,key)
   connect(object:GetPropertyChangedSignal('CursorPosition'),selectionChanged,key)
   connect(object.FocusLost,selectionChanged,key)
  end
  if self._bindFormNode then self:_bindFormNode(key,object)end
  if self._watchNode then self:_watchNode(key,object)end
 end
 function self:stats()
  local motion=self.motion and self.motion:stats()or {transitions=0,animations=0,connected=false,steps=0}
  return {effects=VisualEffects.stats(self.cache),elements=self.nodeCount,layoutPasses=self.layoutPasses,refreshPasses=self.refreshPasses or 0,incremental=self.renderStats or {},resizeRequests=self.frameScheduler and self.frameScheduler.requests or 0,motion=motion,styles=doc and Styles.cacheStats(doc.root)or {},pseudoConnections=self.stateBindings and self.stateBindings.count or 0,pointer=self.pointer and self.pointer:stats()or {},resources=self.resourceStats and self:resourceStats()or {},render=RenderOptimizer.stats()}
 end
 function self:destroy()
  if not self.alive then return end;self.alive=false
  if self.pendingTask then pcall(task.cancel,self.pendingTask);self.pendingTask=nil end;self.pending=false
  if self.frameScheduler then self.frameScheduler:destroy();self.frameScheduler=nil end
  VisualEffects.release(self.cache,not self._svgDestroying)
  DirtyRender.reset(self.cache);clear(self.interactive);clear(self.objectKeys);clear(self.dirtyKeys)
  if self.motion then self.motion:destroy();self.motion=nil end
  if self.motionOverlay then clear(self.motionOverlay)end;self.baseStyles=nil
  if self.layoutRuntime then self.layoutRuntime:destroy();self.layoutRuntime=nil end
  if self.scrollRuntime then self.scrollRuntime:destroy();self.scrollRuntime=nil end
  if self.backgroundRuntime then self.backgroundRuntime:destroy();self.backgroundRuntime=nil end
  SvgRasterRuntime.releaseTree(gui,not self._svgDestroying)
  if self.stateBindings then self.stateBindings:destroy();self.stateBindings=nil end
  if self.svgInteraction then self.svgInteraction:destroy();self.svgInteraction=nil end
  if self.svgDriver then self.svgDriver:destroy();self.svgDriver=nil end
  if self.pointer then self.pointer:destroy();self.pointer=nil end
  if self._cleanupResources then self:_cleanupResources()end
  if doc then Styles.invalidate(doc.root)end;self.stateNeeds=nil
  for _,c in ipairs(self.connections)do c:Disconnect()end
  clear(self.connections);for _,links in pairs(self.nodeConnections)do clear(links)end;clear(self.nodeConnections)
  if controllers[gui]==self then controllers[gui]=nil end
  layoutEvent:Destroy();layoutEvent=nil;self.LayoutChanged=nil
  for _,entry in pairs(self.cache)do clear(entry)end
  clear(self.cache);clear(self.objects);clear(self.state);clear(self.ids);clear(self.nodes);clear(self.nodeParents)
  self.boxes=nil;self.styles=nil;self.sequence=nil;self.parents=nil
  self.document=nil;self.gui=nil;self.nodeCount=0;self.lastError=nil
  self.mediaEnvironment=nil;self.mediaEnvironmentKey=nil;self.mediaEnvironmentSources=nil;self.mediaOverrides=nil;self._syncMediaEnvironment=nil
  self.environment=nil;self.environmentKey=nil;self.environmentSources=nil;self.envOverrides=nil;self._syncEnvironment=nil
  value=nil;doc=nil;gui=nil;options=nil
 end
 Form.install(self,connect,queue)
 RuntimeResources.install(self,bind,queue,collect,connect)
 BackgroundRuntime.install(self,Paint,options)
 ViewTransitions.install(self,options)
 for key,object in pairs(self.objects)do if self.nodes[key]then bind(key,object)end end
 connect(gui:GetPropertyChangedSignal('AbsoluteSize'),queue)
 for attribute in pairs(viewportAttributes)do connect(gui:GetAttributeChangedSignal(attribute),function()queue(nil,'style')end)end
 connect(gui.Destroying,function()self._svgDestroying=true;self:destroy()end)
 Environment.install(self,options,connect,queue)
 Env.install(self,options,connect,queue)
 local ok,err=pcall(self.refresh,self,options.width,options.height)
 if not ok then self:destroy();error(err,0)end
 if options.autofocus~=false then
  local node=FormAppearance.autofocusNode(self.sequence,self.styles,self.state,focusEligible)
  if node then pcall(function()self:focus(node.key)end)end
 end
 return self
end
return R
