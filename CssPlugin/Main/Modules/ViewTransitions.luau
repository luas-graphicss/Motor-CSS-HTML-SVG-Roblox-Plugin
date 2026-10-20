local U=require(script.Parent.Util)
local V={VERSION=1}
local pseudoElements=table.freeze({['view-transition']=true,['view-transition-group']=true,['view-transition-image-pair']=true,['view-transition-old']=true,['view-transition-new']=true})
local functional=table.freeze({['view-transition-group']=true,['view-transition-image-pair']=true,['view-transition-old']=true,['view-transition-new']=true})
V.pseudoElements=pseudoElements
V.functional=functional
local DEFAULT_DURATION=0.25
local NAME_LIMIT=32
local CLONE_BUDGET=600
local identifier='^%-?[%a_][%w_%-]*$'
function V.register(supported,shorthands)
 supported['view-transition-name']=true
 supported['view-transition-class']=true
 return supported,shorthands
end
function V.parse(body)
 assert(type(body)=='string'and #body<=4096,'Corpo de @view-transition inválido.')
 local descriptor={navigation='auto',types={}}
 for _,line in ipairs(U.split(body,';'))do
  local key,value=line:match('^%s*([%a%-]+)%s*:%s*(.-)%s*$')
  assert(key and value and value~='','Descritor @view-transition inválido: '..U.trim(line))
  key=key:lower()
  if key=='navigation'then
   local flag=value:lower();assert(flag=='auto'or flag=='none','navigation aceita auto ou none.');descriptor.navigation=flag
  elseif key=='types'then
   if value:lower()=='none'then descriptor.types={}
   else
    for _,item in ipairs(U.split(value,' '))do
     local name=U.trim(item)
     assert(name:match(identifier)and name:lower()~='none','Tipo de view transition inválido: '..name)
     descriptor.types[#descriptor.types+1]=name;assert(#descriptor.types<=8,'Máximo de 8 tipos por @view-transition.')
    end
   end
  else error('Descritor @view-transition não suportado: '..key,0)end
 end
 return descriptor
end
function V.argument(name,body)
 local text=U.trim(body or'');assert(text~='','::'..name..' exige um argumento.')
 local head,classes=text,{}
 local dot=text:find('.',1,true)
 if dot then
  head=U.trim(text:sub(1,dot-1));if head==''then head='*'end
  local rest=text:sub(dot)
  for class in rest:gmatch('%.([%w_%-]+)')do classes[#classes+1]=class end
  local rebuilt={};for _,class in ipairs(classes)do rebuilt[#rebuilt+1]='.'..class end
  assert(#classes>0 and table.concat(rebuilt)==rest,'Classe de view transition inválida: '..text)
 end
 assert(head=='*'or head:match(identifier),'Nome de view transition inválido: '..head)
 return {name=head,classes=classes,universal=head=='*'}
end
function V.argumentOf(selector)
 local parts=selector and selector.parts
 local last=parts and parts[#parts]
 return last and last.pseudoArgument or nil
end
function V.classes(style)
 local out={}
 local value=style and style['view-transition-class']
 if type(value)~='string'or value==''or value:lower()=='none'then return out end
 for _,item in ipairs(U.split(value,' '))do
  local name=U.trim(item)
  if name~=''and name:lower()~='none'then
   assert(name:match(identifier),'view-transition-class inválida: '..name)
   out[#out+1]=name;assert(#out<=8,'Máximo de 8 classes de view transition.')
  end
 end
 return out
end
function V.matchesArgument(argument,name,classes)
 if argument==nil then return true end
 if argument.name~='*'and argument.name~=name then return false end
 for _,required in ipairs(argument.classes or {})do
  local found=false
  for _,class in ipairs(classes or {})do if class==required then found=true;break end end
  if not found then return false end
 end
 return true
end
function V.collect(rules)
 local out={}
 for _,rule in ipairs(rules or {})do
  local selector=rule.selector
  local kind=selector and selector.pseudoElement
  if kind and pseudoElements[kind]then
   out[#out+1]={kind=kind,argument=V.argumentOf(selector),declarations=rule.declarations or {},order=rule.order or 0,specificity=selector.specificity or 0}
  end
 end
 table.sort(out,function(a,b)
  if a.specificity~=b.specificity then return a.specificity<b.specificity end
  return a.order<b.order
 end)
 return out
end
function V.style(collected,kinds,name,classes)
 local out={}
 for _,entry in ipairs(collected or {})do
  if kinds[entry.kind]and V.matchesArgument(entry.argument,name,classes)then
   for _,declaration in ipairs(entry.declarations)do out[declaration.key]=declaration.value end
  end
 end
 return out
end
local function first(value)
 local parts=U.split(value,',');return U.trim(parts[1]or value)
end
function V.timing(declarations)
 local Motion=require(script.Parent.Motion)
 local d=declarations or {}
 local timing={duration=DEFAULT_DURATION,delay=0,ease=Motion.easing('ease'),opacity=0}
 if d['animation-duration']then timing.duration=Motion.time(first(d['animation-duration']),true)end
 if d['animation-delay']then timing.delay=Motion.time(first(d['animation-delay']),false)end
 if d['animation-timing-function']then timing.ease=Motion.easing(first(d['animation-timing-function']))end
 if d.opacity then
  local n=tonumber(d.opacity);assert(n,'opacity de view transition exige número.');timing.opacity=math.clamp(n,0,1);timing.opacitySpecified=true
 end
 assert(timing.duration>=0 and timing.duration<=10,'Duração de view transition limitada a 10s.')
 assert(timing.delay>=-10 and timing.delay<=10,'Atraso de view transition limitado a 10s.')
 return timing
end
local function absolute(controller,node)
 local box=controller.boxes and controller.boxes[node.key]
 if not box then return nil end
 local x,y=0,0;local at=node;local guard=0
 while at do
  guard+=1;assert(guard<=256,'Árvore muito profunda para view transition.')
  local b=controller.boxes[at.key]
  if b then x+=tonumber(b.x)or 0;y+=tonumber(b.y)or 0 end
  at=controller.parents and controller.parents[at.key]or nil
 end
 return {x=x,y=y,w=math.max(tonumber(box.w)or 0,0),h=math.max(tonumber(box.h)or 0,0)}
end
function V.capture(controller)
 local snapshot={names={},order={},duplicates={}}
 for _,node in ipairs(controller.sequence or {})do
  local style=controller.styles and controller.styles[node.key]
  local name=style and style['view-transition-name']
  if type(name)=='string'and name~=''and name:lower()~='none'then
   assert(name:match(identifier),'view-transition-name inválido: '..name)
   if snapshot.names[name]then snapshot.duplicates[name]=true
   else
    local box=absolute(controller,node)
    local object=controller.objects and controller.objects[node.key]
    local hidden=controller.boxes[node.key]and controller.boxes[node.key].hidden
    if box and object and not hidden and style.display~='none'then
     snapshot.names[name]={name=name,key=node.key,classes=V.classes(style),box=box,object=object,opacity=math.clamp(tonumber(style.opacity)or 1,0,1)}
     snapshot.order[#snapshot.order+1]=name
     assert(#snapshot.order<=NAME_LIMIT,'Máximo de 32 view-transition-name por transição.')
    end
   end
  end
 end
 for name in pairs(snapshot.duplicates)do snapshot.names[name]=nil end
 return snapshot
end
local groupKinds=table.freeze({['view-transition']=true,['view-transition-group']=true,['view-transition-image-pair']=true})
local function timingFor(collected,kind,name,classes)
 local kinds=table.clone(groupKinds);kinds[kind]=true
 return V.timing(V.style(collected,kinds,name,classes))
end
function V.plan(before,after,collected)
 local groups={}
 for _,name in ipairs(before.order)do
  local old=before.names[name];local new=after.names[name]
  local classes=(new or old).classes
  local group={name=name,kind=new and'pair'or'exit',from=old.box,to=new and new.box or old.box,object=old.object,fromOpacity=old.opacity,timing=timingFor(collected,'view-transition-old',name,classes),classes=classes}
  if new then
   group.newObject=new.object;group.newBox=new.box;group.newOpacity=new.opacity
   group.newTiming=timingFor(collected,'view-transition-new',name,classes)
  end
  groups[#groups+1]=group
 end
 for _,name in ipairs(after.order)do
  if not before.names[name]then
   local new=after.names[name]
   local timing=timingFor(collected,'view-transition-new',name,new.classes)
   groups[#groups+1]={name=name,kind='entry',from=new.box,to=new.box,fromOpacity=new.opacity,timing=timing,newTiming=timing,newObject=new.object,newBox=new.box,newOpacity=new.opacity,classes=new.classes}
  end
 end
 return groups
end
local function sanitize(instance)
 local count=0
 local function strip(o)
  o:SetAttribute('CssNodeKey',nil);o:SetAttribute('CssOwned',nil);o:SetAttribute('CssPseudoElement',nil)
 end
 strip(instance)
 for _,child in ipairs(instance:GetDescendants())do
  count+=1;if count>CLONE_BUDGET then break end
  strip(child)
 end
 return count
end
local function overlay(controller)
 local gui=controller.gui
 local existing=gui:FindFirstChild('_CssViewTransition')
 if existing then existing:Destroy()end
 local root=Instance.new('Frame')
 root.Name='_CssViewTransition'
 root.BackgroundTransparency=1;root.BorderSizePixel=0;root.ClipsDescendants=false;root.Active=false
 root.Size=UDim2.fromScale(1,1);root.Position=UDim2.fromOffset(0,0);root.ZIndex=2000
 root:SetAttribute('CssViewTransitionRoot',true)
 root.Parent=gui
 return root
end
local function snapshotClone(pair,object,name,w,h)
 local wrap=Instance.new('CanvasGroup')
 wrap.Name=name
 wrap.BackgroundTransparency=1;wrap.BorderSizePixel=0;wrap.ClipsDescendants=false
 wrap.Position=UDim2.fromOffset(0,0);wrap.Size=UDim2.fromOffset(math.max(w,1),math.max(h,1))
 wrap.Parent=pair
 local clone=object:Clone()
 sanitize(clone)
 clone.Name=name..'Content'
 if clone:IsA('GuiObject')then
  clone.Visible=true;clone.AnchorPoint=Vector2.zero;clone.Rotation=0
  clone.Position=UDim2.fromOffset(0,0);clone.Size=UDim2.fromOffset(w,h)
 end
 clone.Parent=wrap
 return wrap
end
local function snapshotGroup(root,group)
 local canvas=Instance.new('Frame')
 canvas.Name='CssViewTransitionGroup'
 canvas.BackgroundTransparency=1;canvas.BorderSizePixel=0;canvas.ClipsDescendants=false
 canvas.Position=UDim2.fromOffset(group.from.x,group.from.y)
 canvas.Size=UDim2.fromOffset(group.from.w,group.from.h)
 canvas:SetAttribute('CssViewTransitionName',group.name)
 canvas.Parent=root
 local pair=Instance.new('Frame')
 pair.Name='CssViewTransitionImagePair'
 pair.BackgroundTransparency=1;pair.BorderSizePixel=0;pair.ClipsDescendants=false
 pair.Size=UDim2.fromScale(1,1);pair.Position=UDim2.fromOffset(0,0)
 pair.Parent=canvas
 local old=group.object and snapshotClone(pair,group.object,'CssViewTransitionOld',group.from.w,group.from.h)or nil
 local newBox=group.newBox or group.to
 local new=group.newObject and snapshotClone(pair,group.newObject,'CssViewTransitionNew',newBox.w,newBox.h)or nil
 if new then new.GroupTransparency=1 end
 return {canvas=canvas,pair=pair,old=old,new=new}
end
function V.descriptor(controller)
 local doc=controller and controller.document
 local list=doc and doc.viewTransitions
 local out={navigation='auto',types={}}
 if type(list)=='table'then
  for _,entry in ipairs(list)do
   if entry.navigation then out.navigation=entry.navigation end
   if type(entry.types)=='table'and #entry.types>0 then out.types=entry.types end
  end
 end
 return out
end
function V.start(controller,mutate,settings)
 assert(type(controller)=='table'and controller.alive,'Controller encerrado.')
 assert(type(mutate)=='function','startViewTransition exige uma função de atualização.')
 settings=settings or {}
 local stats=controller.viewTransitions or {active=0,completed=0,skipped=0}
 local descriptor=V.descriptor(controller)
 local reduced=controller.motion~=nil and controller.motion.reduced==true
 local off=settings.animate==false or descriptor.navigation=='none'or reduced or controller.styles==nil
 local before=not off and V.capture(controller)or nil
 mutate()
 if controller.alive then controller:flush()end
 if off or not controller.alive then
  stats.skipped+=1
  return {skipped=true,active=false,progress=1,groups=0,names={},types=descriptor.types,reduced=reduced,step=function()return true end,cancel=function()end,advance=function()return true end}
 end
 local after=V.capture(controller)
 local duplicated=next(before.duplicates)~=nil or next(after.duplicates)~=nil
 local doc=controller.document
 local collected=(doc and doc.viewTransitionRules)or V.collect(doc and doc.rules)
 local plan=(not duplicated)and V.plan(before,after,collected)or {}
 local handle={active=true,progress=0,skipped=duplicated,groups=#plan,names={},types=descriptor.types,reduced=false,duplicated=duplicated}
 local snapshots={};local root=nil;local total=0;local hidden={}
 local ok,err=pcall(function()
  for _,group in ipairs(plan)do
   handle.names[#handle.names+1]=group.name
   if group.object or group.newObject then
    root=root or overlay(controller)
    snapshots[#snapshots+1]={group=group,view=snapshotGroup(root,group)}
    total=math.max(total,group.timing.delay+group.timing.duration)
    if group.newTiming then total=math.max(total,group.newTiming.delay+group.newTiming.duration)end
    if group.newObject and group.newObject:IsA('GuiObject')then hidden[#hidden+1]=group.newObject end
   end
  end
 end)
 if not ok then
  if root then root:Destroy()end
  stats.skipped+=1;error(err,0)
 end
 local clock=controller.motion and controller.motion.clock or os.clock
 local startedAt=clock()
 local function finish()
  if not handle.active then return end
  handle.active=false;handle.progress=1
  if handle.connection then handle.connection:Disconnect();handle.connection=nil end
  if root then root:Destroy();root=nil end
  for _,object in ipairs(hidden)do pcall(function()object.Visible=true end)end
  table.clear(hidden);table.clear(snapshots)
  stats.active=math.max(stats.active-1,0);stats.completed+=1
  if controller._viewTransition==handle then controller._viewTransition=nil end
  if type(settings.onFinish)=='function'then pcall(settings.onFinish,handle)end
 end
 local function phase(timing,elapsed)
  local span=timing.duration
  local t=span>0 and math.clamp((elapsed-timing.delay)/span,0,1)or(elapsed>=timing.delay and 1 or 0)
  return timing.ease(t),elapsed>=timing.delay+span
 end
 local function apply(now)
  local elapsed=now-startedAt;local done=true
  for _,item in ipairs(snapshots)do
   local group=item.group;local timing=group.timing
   local eased,over=phase(timing,elapsed)
   if not over then done=false end
   local from,to=group.from,group.to
   local w=math.max(from.w+(to.w-from.w)*eased,0);local h=math.max(from.h+(to.h-from.h)*eased,0)
   item.view.canvas.Position=UDim2.fromOffset(from.x+(to.x-from.x)*eased,from.y+(to.y-from.y)*eased)
   item.view.canvas.Size=UDim2.fromOffset(w,h)
   if item.view.old then
    local alpha=group.fromOpacity+(timing.opacity-group.fromOpacity)*eased
    item.view.old.GroupTransparency=math.clamp(1-alpha,0,1)
   end
   if item.view.new then
    local newTiming=group.newTiming or timing
    local newEased,newOver=phase(newTiming,elapsed)
    if not newOver then done=false end
    local target=newTiming.opacitySpecified and newTiming.opacity or group.newOpacity or 1
    item.view.new.GroupTransparency=math.clamp(1-target*newEased,0,1)
   end
   if group.newObject then pcall(function()if group.newObject.Visible then group.newObject.Visible=false end end)end
  end
  handle.progress=total>0 and math.clamp(elapsed/total,0,1)or 1
  return done
 end
 local function step(now)
  if not handle.active then return true end
  if not controller.alive then finish();return true end
  local done=apply(now or clock())
  if done then finish()end
  return done
 end
 handle.advance=step
 handle.cancel=function()finish()end
 handle.finish=finish
 function handle:step(now)return step(now)end
 stats.active+=1
 apply(startedAt)
 if #snapshots==0 then finish();return handle end
 local manual=settings.manual==true or controller.manual==true or(controller.motion~=nil and controller.motion.manual==true)
 if manual then return handle end
 local Performance=require(script.Parent.Performance)
 handle.connection=Performance.renderSignal():Connect(function()
  local fine,failure=pcall(step)
  if not fine then
   finish()
   if controller.development then warn('[CssPlugin] View transition interrompida: '..tostring(failure))end
  end
 end)
 return handle
end
function V.install(controller,options)
 controller.viewTransitions={active=0,completed=0,skipped=0}
 function controller:startViewTransition(mutate,settings)
  local handle=V.start(self,mutate,settings)
  self._viewTransition=handle.active and handle or nil
  return handle
 end
 function controller:viewTransitionStats()
  local stats=self.viewTransitions
  local running=self._viewTransition~=nil and self._viewTransition.active==true
  return {active=stats.active,completed=stats.completed,skipped=stats.skipped,running=running}
 end
 function controller:viewTransitionNames()return V.capture(self).order end
 return controller
end
return V
