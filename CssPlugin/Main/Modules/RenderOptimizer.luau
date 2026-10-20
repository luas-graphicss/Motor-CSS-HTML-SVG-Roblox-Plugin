local U=require(script.Parent.Util)
local Form=require(script.Parent.FormState)
local Presentation=require(script.Parent.Presentation)
local WillChange=require(script.Parent.WillChange)
local StyleOptimizer=require(script.Parent.StyleOptimizer)
local O={}
O.classes=Presentation.classes
O.className=Presentation.className
local pool=require(script.Parent.PoolOwnership).adapter('CssRuntime')
function O.setPool(value)pool=value end
local metrics={propertyWrites=0,propertySkips=0,attributeWrites=0,attributeSkips=0,styleHits=0,styleMisses=0,created=0,acquires=0,nativeNew=0,poolReuse=0,templateClones=0,treeClones=0,collapsed=0,emptyText=0,reclassified=0}
local childIndexes=setmetatable({},{__mode='k'})
local signatures=setmetatable({},{__mode='k'})
local interned,slots=setmetatable({}, {__mode='v'}),{};local cursor=0
local childValues=table.freeze({__mode='v'})
local function compareKeys(a,b)return tostring(a)<tostring(b)end
local function encode(value)
 local kind=type(value)
 if kind~='table'then local s=tostring(value);return kind..#s..':'..s end
 local keys={};for k in pairs(value)do if k~='_renderSignature'then keys[#keys+1]=k end end
 table.sort(keys,compareKeys)
 local out={'{'};for _,k in ipairs(keys)do out[#out+1]=encode(k);out[#out+1]=encode(value[k])end
 out[#out+1]='}';return table.concat(out)
end
function O.signature(value)
 if type(value)~='table'then return encode(value)end
 local known=signatures[value];if known then return known end
 known=encode(value)
  
 if table.isfrozen(value)then signatures[value]=known end
 return known
end
local function frozenCopy(value)
 if type(value)~='table'then return value end
 local copy={};for k,v in pairs(value)do copy[k]=frozenCopy(v)end;return table.freeze(copy)
end
 
 
local byOrigin=setmetatable({},{__mode='k'})
function O.internStyles(styles)
 for key,style in pairs(styles)do
  local shared
  if table.isfrozen(style)and signatures[style]then shared=style;metrics.styleHits+=1
  else
   local origin=StyleOptimizer.originOf(style)
   shared=origin and byOrigin[origin]or nil
   if shared then metrics.styleHits+=1 else
    local signature=O.signature(style);shared=interned[signature]
    if shared then metrics.styleHits+=1 else
     shared=frozenCopy(style);signatures[shared]=signature
     cursor=cursor%512+1;local previous=slots[cursor];if previous then interned[previous]=nil end
     slots[cursor]=signature;interned[signature]=shared;metrics.styleMisses+=1
    end
    if origin then byOrigin[origin]=shared end
   end
  end
  styles[key]=shared
 end
 return styles
end
function O.properties(object,values)
 for property,value in pairs(values)do
  if object[property]~=value then object[property]=value;metrics.propertyWrites+=1 else metrics.propertySkips+=1 end
 end
end
function O.attributes(object,values)
 for name,value in pairs(values)do
  if object:GetAttribute(name)~=value then object:SetAttribute(name,value);metrics.attributeWrites+=1 else metrics.attributeSkips+=1 end
 end
end
function O.remember(parent,name,object)
 local index=childIndexes[parent];if not index then index=O.indexChildren(parent)end
 index[name]=object or false
end
function O.indexChildren(parent)
 local index=setmetatable({},childValues);for _,child in ipairs(parent:GetChildren())do index[child.Name]=child end
 childIndexes[parent]=index;return index
end
function O.child(parent,name)
 local index=childIndexes[parent]or O.indexChildren(parent);local child=index[name]
 if child and child.Parent==parent and child.Name==name then return child end
 child=parent:FindFirstChild(name);index[name]=child or false;return child
end
function O.invalidate(parent)childIndexes[parent]=nil end
function O.acquire(className)
 local object=pool and pool.tryAcquire and pool.tryAcquire(className)
 if object then metrics.poolReuse+=1
 else
  object=pool and pool.acquire and pool.acquire(className)or Instance.new(className)
  metrics.nativeNew+=1
 end
 childIndexes[object]=nil;metrics.acquires+=1;metrics.created=metrics.acquires;return object
end
function O.cloneTemplate(template,entry,cost)
 local object
 if cost==1 then
  object=pool and pool.tryAcquire and pool.tryAcquire(template.ClassName)
  if object then metrics.poolReuse+=1 else object=pool.adopt(template:Clone());metrics.templateClones+=1 end
  O.properties(object,entry.properties);O.attributes(object,entry.attributes)
 else object=pool and pool.cloneTree(template)or template:Clone();metrics.treeClones+=1 end
 O.invalidate(object);return object
end
function O.release(object)
 object=require(script.Parent.VisualEffectsGroups).root(object)
 for _,child in ipairs(object:GetDescendants())do childIndexes[child]=nil end
 childIndexes[object]=nil
 if pool and pool.releaseTree then return pool.releaseTree(object)end
 object:Destroy()
end
local function zero(value)
 if value==nil then return true end
 if type(value)=='number'then return value==0 end
 if type(value)~='string'then return false end
 return value:match('^[+%-]?0*%.?0+[a-z%%]*$')~=nil or value=='0'
end
local function passive(node,rules)
 for key in pairs(node.attrs or {})do if key~='class'and key~='style'then return false end end
 if node.dynamic or node.pseudo or node.pseudoElement or node.generated then return false end
 for _,rule in ipairs(rules or {})do
  local dependencies=rule.selector and rule.selector.dependencies
  if dependencies and dependencies.complex and next(dependencies.states or {})then return false end
  for _,part in ipairs(rule.selector and rule.selector.parts or {})do
   local hasState=false;for _,state in ipairs(part.states or {})do if state~='root'then hasState=true end end
   if hasState and(not part.tag or part.tag=='*'or part.tag==node.tag)and(not part.id or part.id==node.attrs.id)then
    local matches=true;local classes=' '..(node.attrs.class or ''):gsub('%s+',' ')..' '
    for _,class in ipairs(part.classes or {})do if not classes:find(' '..class..' ',1,true)then matches=false;break end end
    if matches then return false end
   end
  end
 end
 return true
end
local function nonvisual(style)
 if style.display and(style.display:find('table',1,true))then return false end
 if style.position=='sticky'or style.position=='fixed'or(style['column-count']and style['column-count']~='auto')or(style['column-width']and style['column-width']~='auto')then return false end
 if require(script.Parent.VisualEffectsStyle).active(style)then return false end
 if style['background-image']and style['background-image']~='none'then return false end
 if style['border-image-source']and style['border-image-source']~='none'then return false end
 if style.overflow and style.overflow~='visible'then return false end
 if tonumber(style.opacity or '1')~=1 then return false end
 if style.transform and style.transform~='none'then return false end
 if style.perspective and style.perspective~='none'then return false end
 if style['box-shadow']and style['box-shadow']~='none'then return false end
 if style['z-index']then return false end
 if style['animation-name']and style['animation-name']~='none'then return false end
 for key in pairs(style)do if key:sub(1,11)=='transition-'then return false end end
 if not zero(style['border-width'])then return false end
 for _,side in ipairs({'top','right','bottom','left'})do if not zero(style['padding-'..side])then return false end end
 local ok,_,alpha=pcall(U.color,style.background or style['background-color']or 'transparent')
 return ok and alpha==0
end
function O.virtualKind(node,style,doc)
 if node.pseudoText then return 'text-slot'end
 if node.key==doc.root.key or doc.renderOptimizations==false or not style then return nil end
 if WillChange.materialize(style)then return nil end
 if not passive(node,doc.rules)or not nonvisual(style)then return nil end
 if node.tag=='div'and style.display=='flex'then return 'container'end
 if Presentation.className(node,style)=='TextLabel'and(node.text or ''):match('^%s*$')and #node.children==0 then return 'text'end
 return nil
end
function O.initialStates(root)
 local states={}
 local function visit(node)
  states[node.key]=Form.initial(node)
  for _,child in ipairs(node.children)do visit(child)end
 end
 visit(root);return states
end
local barsModule
local function bars()
 if not barsModule then barsModule=require(script.Parent.Scrollbars)end
 return barsModule
end
function O.entry(node,state,style)
 local className=Presentation.className(node,style)
 local props={Name=node.pseudoElement and ('__'..node.pseudoElement)or node.attrs.id or(node.tag..'_'..node.order),BorderSizePixel=0,BackgroundTransparency=1}
 local text=className=='TextLabel'or className=='TextButton'or className=='TextBox'
 if text then props.Text=node.text or '';props.RichText=false;props.AutoLocalize=true end
 if Form.isToggle(node)then props.Text=(state and state.checked)and(node.attrs.type=='radio'and '●'or '✓')or ''end
 if className=='TextBox'then
  props.ClearTextOnFocus=false;props.MultiLine=node.tag=='textarea';props.PlaceholderText=node.attrs.placeholder or ''
  if node.tag=='input'and node.attrs.type=='password'then props.Text=Form.mask(props.Text or '')end
  local placeholder=node.interfacePseudo and node.interfacePseudo.placeholder
  if placeholder and placeholder.color then
   local ok,color=pcall(U.color,placeholder.color)
   if ok then props.PlaceholderColor3=color end
  end
 end
 if className=='TextButton'then props.AutoButtonColor=false end
 if className=='ImageLabel'then
  assert((node.attrs.src or ''):match('^rbxassetid://%d+$'),'img exige src="rbxassetid://ID" de asset publicado.');props.Image=node.attrs.src
 end
 if className=='ScrollingFrame'then
  props.AutomaticCanvasSize=Enum.AutomaticSize.None
  props.ScrollBarThickness=style and bars().thickness(style)or 6
 end
 return {key=node.key,node=node,className=className,properties=props,attributes={CssNodeKey=node.key,CssClass=node.attrs.class or '',CssOwned=true,CssPseudoElement=node.pseudoElement,CssPseudoOwner=node.ownerKey,CssDisabled=state and state.disabled==true or false,CssChecked=state and state.checked==true or false,CssReadOnly=state and state.readonly==true or false}}
end
function O.plan(doc,styles,sequence,parents,states,checkpoint)
 local plan={entries={},ids={},parents={},virtual={},collapsed=0,emptyText=0}
 for _,node in ipairs(sequence)do
  if checkpoint then checkpoint()end
  if node.attrs.id then plan.ids[node.attrs.id]=node.key end
  local parent=parents[node.key];plan.parents[node.key]=parent and parent.key or nil
  local virtual=O.virtualKind(node,styles[node.key],doc)
  if virtual then
   plan.virtual[node.key]=virtual
   if virtual=='container'then plan.collapsed+=1 else plan.emptyText+=1 end
  else plan.entries[#plan.entries+1]=O.entry(node,states[node.key],styles[node.key])end
 end
 return plan
end
function O.instantiate(entry)
 local object=O.acquire(entry.className);O.properties(object,entry.properties);O.attributes(object,entry.attributes);return object
end
function O.allocate(plan,objects,checkpoint)
 for _,entry in ipairs(plan.entries)do
  objects[entry.key]=O.instantiate(entry)
  if checkpoint then checkpoint()end
 end
 metrics.collapsed+=plan.collapsed;metrics.emptyText+=plan.emptyText;return objects
end
local boxClasses=table.freeze({Frame=true,ScrollingFrame=true})
function O.reclassify(node,style,objects,states,cache)
 local object=objects[node.key];if not object then return false end
 local className=Presentation.className(node,style)
 if object.ClassName==className then return false end
 if not(boxClasses[object.ClassName]and boxClasses[className])then return false end
 local groups=require(script.Parent.VisualEffectsGroups)
 local host=groups.get(object)
 if host then groups.begin(object);object.Parent=host.Parent;host:Destroy()end
 local replacement=O.instantiate(O.entry(node,states[node.key],style))
 O.properties(replacement,{Position=object.Position,Size=object.Size,AnchorPoint=object.AnchorPoint,ZIndex=object.ZIndex,Visible=object.Visible,ClipsDescendants=object.ClipsDescendants})
 for _,child in ipairs(object:GetChildren())do child.Parent=replacement end
 O.invalidate(replacement);O.invalidate(object)
 replacement.Parent=object.Parent
 objects[node.key]=replacement;cache[node.key]={}
 O.release(object);metrics.reclassified+=1
 return true
end
function O.ensure(doc,styles,sequence,objects,states,cache,checkpoint)
 for _,node in ipairs(sequence)do
  if checkpoint then checkpoint()end
  if node.pseudoElement and objects[node.key]then
   O.properties(objects[node.key],{Text=node.text or ''})
  end
  if objects[node.key]then O.reclassify(node,styles[node.key],objects,states,cache)
  elseif not O.virtualKind(node,styles[node.key],doc)then
   states[node.key]=states[node.key]or Form.initial(node)
   objects[node.key]=O.instantiate(O.entry(node,states[node.key],styles[node.key]));cache[node.key]={}
  end
 end
end
function O.paintBox(node,box,parents,objects,boxes)
 local parent=parents[node.key];local x,y=box.x,box.y
 while parent and not objects[parent.key]do local up=boxes[parent.key];x+=up.x;y+=up.y;parent=parents[parent.key]end
 if parent then
  local object=objects[parent.key]
  if object and(object:IsA('TextLabel')or object:IsA('TextButton')or object:IsA('TextBox'))then
   local up=boxes[parent.key];local padding=up.textPadding or up.p
   x-=padding[4];y-=padding[1]
  end
 end
 if x==box.x and y==box.y then return box end
 local copy=U.copy(box);copy.x=x;copy.y=y;return copy
end
function O.mount(root,sequence,parents,objects,container,checkpoint,hosts)
 for i=#sequence,1,-1 do
  if checkpoint then checkpoint()end
  local node=sequence[i];local object=objects[node.key]
  if object and node.key~=root.key then
   local host=hosts and hosts[node.key]
   local parent=parents[node.key];while parent and not objects[parent.key]do parent=parents[parent.key]end
   local target=host or(parent and objects[parent.key]);assert(target,'Pai visual ausente: '..node.key)
   local visual=require(script.Parent.VisualEffectsGroups).root(object)
   if visual.Parent~=target then visual.Parent=target end
  end
 end
 local object=require(script.Parent.VisualEffectsGroups).root(objects[root.key]);if container and object.Parent~=container then object.Parent=container end
 require(script.Parent.VisualEffectsGroups).configure(container)
end
function O.dispose(objects)
 local owned={};for _,object in pairs(objects)do owned[object]=true;owned[require(script.Parent.VisualEffectsGroups).root(object)]=true end
 local roots,seen={},{};for _,object in pairs(objects)do local visual=require(script.Parent.VisualEffectsGroups).root(object);if not owned[visual.Parent]and not seen[visual]then roots[#roots+1]=visual;seen[visual]=true end end
 for _,object in ipairs(roots)do O.release(object)end;table.clear(objects)
end
function O.stats()
 local copy=U.copy(metrics);local count=0;for _ in pairs(interned)do count+=1 end;copy.styleEntries=count
 if pool and pool.stats then local ok,stats=pcall(pool.stats);if ok and type(stats)=='table'then copy.pool=stats end end
 return copy
end
return O
