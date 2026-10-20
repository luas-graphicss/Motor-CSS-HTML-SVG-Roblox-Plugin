local Selectors=require(script.Parent.Selectors)
local Queries=require(script.Parent.ResponsiveQueries)
local Cascade=require(script.Parent.CssCascade)
local Ua=require(script.Parent.UserAgentStyles)
local O = {VERSION = 3}
local scopes = setmetatable({}, {__mode = 'k'})
local EMPTY = table.freeze({})
local Typography=require(script.Parent.TypographyStyle)
local SvgStyle=require(script.Parent.SvgStyle)
local INHERITED = table.clone(Typography.inherited)
for _,key in ipairs(SvgStyle.inherited)do INHERITED[#INHERITED+1]=key end
for _,key in ipairs({'color-scheme','border-collapse','border-spacing','caption-side','empty-cells','orphans','widows'})do INHERITED[#INHERITED+1]=key end
for _,key in ipairs({'quotes','list-style-type','list-style-position','list-style-image'})do INHERITED[#INHERITED+1]=key end
for _,key in ipairs({'cursor','pointer-events','user-select'})do INHERITED[#INHERITED+1]=key end
O.inherited = table.freeze(INHERITED)
local DEFAULTS = {
 display='block',position='relative',color='#eaf0fa',background='transparent',
 ['color-scheme']='normal',['border-collapse']='separate',['border-spacing']='0px',['caption-side']='top',['empty-cells']='show',orphans='2',widows='2',
 ['font-family']='Gotham',['font-size']='16px',['font-weight']='400',
 ['text-align']='start',['vertical-align']='middle',['white-space']='normal',
 ['box-sizing']='border-box',['flex-direction']='column',['flex-wrap']='nowrap',
 ['flex-grow']='0',['flex-shrink']='1',['flex-basis']='auto',['align-self']='auto',
 ['align-content']='stretch',['align-items']='stretch',['justify-content']='flex-start',
 ['border-width']='0px',['border-style']='solid',['row-gap']='0px',['column-gap']='0px',
 opacity='1',overflow='visible',transform='none',
 quotes='auto',['list-style-type']='disc',['list-style-position']='outside',['list-style-image']='none',
 cursor='auto',['pointer-events']='auto',['user-select']='auto',
}
for _,base in ipairs({'padding','margin'}) do
 for _,side in ipairs({'top','right','bottom','left'}) do DEFAULTS[base..'-'..side]='0px' end
end
for key,value in pairs(Typography.defaults)do DEFAULTS[key]=value end
for _,key in ipairs(SvgStyle.inherited)do if DEFAULTS[key]==nil then DEFAULTS[key]=SvgStyle.defaults[key]end end
O.defaults = DEFAULTS
local bases = {}
local function refreshProfile()
 local initial=Ua.initial()
 for key,value in pairs(initial)do DEFAULTS[key]=value end
 table.clear(bases)
 table.clear(scopes)
end
Ua.onChange(refreshProfile)
refreshProfile()
function O.setProfile(name)
 Ua.setProfile(name)
 return Ua.profile()
end
function O.profile()
 return Ua.profile()
end
local function baseFor(tag)
 local cacheKey=Ua.profile()..'|'..tag
 if bases[cacheKey] then return bases[cacheKey] end
 local base = table.clone(DEFAULTS)
 for key,value in pairs(Ua.declarations(tag))do base[key]=value end
 if base.display:find('table',1,true)then base['vertical-align']='top'end
 if tag=='th'then base['font-weight']='700'end
 if tag=='ui' then base.width='100%';base.height='100%' end
 if tag=='ul'or tag=='ol'then base['padding-left']='24px'end
 if tag=='ol'then base['list-style-type']='decimal'end
 if tag=='button' or tag=='input' then
  base.height='44px';base['text-align']=tag=='button' and 'center' or 'left';base.background='#223047'
 end
 if tag=='h1' then base['font-size']='32px';base['font-weight']='700' end
 if tag=='h2' then base['font-size']='24px';base['font-weight']='700' end
 for key,value in pairs(Ua.base(tag))do base[key]=value end
 bases[cacheKey]=table.freeze(base);return bases[cacheKey]
end
function O.newStyle(node,parent)
 local style=table.clone(baseFor(node.tag))
 if parent then
  for _,key in ipairs(INHERITED) do style[key]=parent[key] or DEFAULTS[key] end
  if node.tag=='h1' then style['font-size']='32px';style['font-weight']='700' end
  if node.tag=='h2' then style['font-size']='24px';style['font-weight']='700' end
  if node.tag=='button' or node.tag=='input' then style['text-align']=node.tag=='button' and 'center' or 'left' end
  for key,value in pairs(Ua.declarations(node.tag))do style[key]=value end
  for key,value in pairs(Ua.base(node.tag))do style[key]=value end
 end
 if node.aliases then for alias in pairs(node.aliases)do for key,value in pairs(Ua.base(alias))do style[key]=value end end end
 if node.anonymousText then style.display='inline'end
 if node.pseudoElement or node.pseudoText then style.display='block'end
 if node.pseudoElement then
  style['list-style-type']='none';style['counter-reset']=nil;style['counter-increment']=nil;style['counter-set']=nil
  if node.pseudoElement=='marker'then
   style['white-space']='nowrap'
   if parent and parent['list-style-position']=='inside'then style.display='inline'
   else style.position='absolute';style.left='-1.5em';style.width='1.3em';style['text-align']='right'end
  elseif node.pseudoElement=='file-selector-button'then
   style['text-align']='center';style.background='#223047';style['padding-left']='10px';style['padding-right']='10px'
  end
 end
 if node.tag=='ol'then style['list-style-type']='decimal'end
 if node.tag=='b'or node.tag=='strong'then style['font-weight']='700'end
 if node.tag=='i'or node.tag=='em'then style['font-style']='italic'end
 if node.tag=='u'then style['text-decoration-line']='underline'end
 if node.tag=='s'then style['text-decoration-line']='line-through'end
 if node.tag=='small'then style['font-size']='0.8em'end
 if node.attrs.lang then style._language=node.attrs.lang end
 if node.attrs.dir then style.direction=node.attrs.dir;style['text-align']='start'end
 if node.tag=='svg' then
  style.width=node.attrs.width or '24px';style.height=node.attrs.height or '24px'
  for key,value in pairs(node.attrs)do if SvgStyle.properties[key]and key~='transform'then style[key]=value end end
 end
 return style
end
local function atom(v)
 local text=v==nil and ''or tostring(v);return type(v)..':'..#text..':'..text
end
local function append(bucket,key,index)
 local list=bucket[key];if not list then list={};bucket[key]=list end
 list[#list+1]=index
end
local function dynamic(pseudo) return pseudo~='root' end
function O.index(rules)
 local plan={layerEvents=rules[1]and rules[1].layerEvents,version=O.VERSION,ruleCount=#rules,byId={},byClass={},byTag={},universal={},ids={},states={},contextual=false,stateParts={},containerRules={}}
 for index,rule in ipairs(rules) do
  if Queries.hasContainer(rule)then plan.containerRules[#plan.containerRules+1]=index end
  local sel=rule.selector;local parts=sel.parts;local last=parts[#parts]
  local dependencies=sel.dependencies
  if dependencies then
   if dependencies.complex then plan.complex=true end
   for id in pairs(dependencies.ids or EMPTY)do plan.ids[id]=true end
   for name in pairs(dependencies.states or EMPTY)do plan.states[name]=true end
  end
  if #parts>1 then plan.contextual=true end
  if last.id then append(plan.byId,last.id,index)
  elseif last.classes and last.classes[1] then append(plan.byClass,last.classes[1],index)
  elseif last.tag and last.tag~='*' then append(plan.byTag,last.tag,index)
  else plan.universal[#plan.universal+1]=index end
  for partIndex,part in ipairs(parts) do
   if part.id then plan.ids[part.id]=true end
   for _,pseudo in ipairs(part.states or {}) do
    if dynamic(pseudo) then
     plan.states[pseudo]=true
     plan.stateParts[#plan.stateParts+1]={rule=index,part=partIndex,state=pseudo}
    end
   end
  end
 end
 return plan
end
function O.prepare(root,rules)
 local tags={}
 local function collect(node)
  tags[node.tag]=true
  if node.aliases then for alias in pairs(node.aliases)do tags[alias]=true end end
  for _,child in ipairs(node.children or EMPTY) do collect(child) end
 end
 collect(root)
 local filtered={}
 for _,rule in ipairs(rules) do
  local possible=true
  for _,part in ipairs(rule.selector.parts) do
   if part.tag and part.tag~='*' and not tags[part.tag] then possible=false;break end
  end
  if possible then filtered[#filtered+1]=rule end
 end
 local plan=O.index(filtered)
 plan.inputRules=#rules;plan.prunedRules=#rules-#filtered
 return filtered,plan
end
local function classSet(node,scope)
 local raw=node.attrs.class or ''
 local old=scope.classes[node.key]
 if old and old.raw==raw then return old.set,old.signature end
 local set,sorted={},{}
 for class in raw:gmatch('%S+') do if not set[class] then set[class]=true;sorted[#sorted+1]=class end end
 table.sort(sorted)
 local encoded={};for _,class in ipairs(sorted) do encoded[#encoded+1]=atom(class) end
 local sig=table.concat(encoded)
 scope.classes[node.key]={raw=raw,set=set,signature=sig}
 return set,sig
end
local function inlineKey(decls)
 local out={}
 for _,d in ipairs(decls or EMPTY) do
  out[#out+1]=atom(d.key)..atom(d.value)..atom(d.shorthand)..(d.important and '1' or '0')
 end
 return table.concat(out)
end
local function bounded(scope,kind,key,value,limit)
 local cache=scope[kind]
 if cache[key]==nil then
  local countName=kind..'Count'
  if scope[countName]>=limit then table.clear(cache);scope[countName]=0;scope.stats.evictions+=1 end
  scope[countName]+=1
 end
 cache[key]=value
end
local function scopeFor(root,rules,prepared)
 local scope=scopes[root]
 if not scope or scope.rules~=rules or scope.ruleCount~=#rules or (prepared and scope.prepared~=prepared) then
  local plan=prepared
  if not plan or plan.version~=O.VERSION or plan.ruleCount~=#rules then plan=O.index(rules) end
  scope={rules=rules,ruleCount=#rules,plan=plan,prepared=prepared,classes={},candidates={},cascade={},computed={},
   candidatesCount=0,cascadeCount=0,computedCount=0,nextCascade=0,
   stats={passes=0,selectorTests=0,cascadeHits=0,cascadeMisses=0,computedHits=0,computedMisses=0,evictions=0}}
  scopes[root]=scope
 end
 return scope
end
function O.begin(root,rules,state,width,height,prepared,options)
 local checkpoint=options and options.checkpoint
 local scope=scopeFor(root,rules,prepared);local plan=scope.plan
 local session={scope=scope,plan=plan,sequence={},parents={},classes={},localKeys={},contextKeys={},cascadeKeys={},state=state or EMPTY,checkpoint=checkpoint}
 session.mediaEnvironment=table.freeze(Queries.environment(options and options.mediaEnvironment))
 session.querySnapshot=options and options.querySnapshot;session.containerActive={};session.containerKeys={}
 local media={};session.active={}
 for index,rule in ipairs(rules) do
  local active=Queries.mediaActive(rule,width,height,session.mediaEnvironment)
  session.active[index]=active
  if rule.minWidth or rule.maxWidth or rule.conditions then media[#media+1]=active and '1' or '0' end
 end
 local layerKey
 session.layerOrder,layerKey=Cascade.order(plan.layerEvents,width,height,session.mediaEnvironment)
 session.mediaKey=table.concat(media)..'|'..layerKey
 session.viewport=options and options.viewport
 session.viewportKey=atom(Ua.profile())..atom(width)..atom(height or 0)..atom(Queries.environmentKey(session.mediaEnvironment))..atom(options and options.environmentKey or '')..atom(session.viewport and table.concat({session.viewport.smallWidth or 0,session.viewport.smallHeight or 0,session.viewport.largeWidth or 0,session.viewport.largeHeight or 0,session.viewport.dynamicWidth or 0,session.viewport.dynamicHeight or 0},'/')or '')
 session.unitContexts=options and options.unitContexts
 local seen={}
 local function walk(node,parent,lineage)
  if checkpoint then checkpoint()end
  local key=node.key;seen[key]=true;session.parents[key]=parent;session.sequence[#session.sequence+1]=node
  local set,classSignature=classSet(node,scope);session.classes[key]=set
  local localKey=atom(node.tag)..atom(plan.ids[node.attrs.id] and node.attrs.id or '')..atom(classSignature)..(parent and 'N' or 'R')
  localKey..=atom(node.pseudo or node.pseudoElement or node._pseudo)..atom(node.anonymousText and 'text-run'or '')
  session.localKeys[key]=localKey
  local states={}
  for _,name in ipairs({'hover','active','focus','disabled','checked','valid','invalid','readonly','read-only','target'}) do
   if plan.states[name] then states[#states+1]=(session.state[key] and session.state[key][name]) and '1' or '0' end
  end
  local own=localKey..table.concat(states)
  local contextual=plan.contextual and atom(lineage)..atom(own) or own
  session.contextKeys[key]=contextual
  local bits,active={},{}
  for _,index in ipairs(plan.containerRules or EMPTY)do
   active[index]=Queries.matches(rules[index],width,height,session.mediaEnvironment,node,session.parents,session.querySnapshot)
   bits[#bits+1]=active[index]and '1'or '0'
  end
  session.containerActive[key]=active;session.containerKeys[key]=table.concat(bits)
  session.cascadeKeys[key]=atom(session.containerKeys[key])..atom(session.mediaKey)..atom(contextual)..atom(inlineKey(node.inline))..atom(inlineKey(node.hints))
  for _,child in ipairs(node.children or EMPTY) do walk(child,node,contextual) end
 end
 walk(root,nil,'')
 local queryStamp={};if #(plan.containerRules or EMPTY)>0 then for _,node in ipairs(session.sequence)do queryStamp[#queryStamp+1]=atom(node.key)..session.containerKeys[node.key]end end
 session.queryKey=table.concat(queryStamp)
 session.ruleActive=function(index,node)return O.ruleActive(session,node,index)end
 if plan.complex then
  local stamp={}
  for _,node in ipairs(session.sequence)do
   local parent=session.parents[node.key]
   stamp[#stamp+1]=atom(node.key)..atom(parent and parent.key)..atom(node.tag)..atom(node.text)
   for _,map in ipairs({node.attrs or EMPTY,session.state[node.key]or EMPTY})do
    local keys={};for name in pairs(map)do keys[#keys+1]=name end;table.sort(keys)
    for _,name in ipairs(keys)do stamp[#stamp+1]=atom(name)..atom(map[name])end
   end
  end
  local signature=table.concat(stamp)
  if scope.complexSignature~=signature then scope.complexSignature=signature;scope.complexGeneration=(scope.complexGeneration or 0)+1 end
  session.complexGeneration=scope.complexGeneration
  for _,node in ipairs(session.sequence)do
   session.cascadeKeys[node.key]=atom(scope.complexGeneration)..atom(node.key)..session.cascadeKeys[node.key]
  end
 end
 for key in pairs(scope.classes) do if not seen[key] then scope.classes[key]=nil end end
 scope.stats.passes+=1
 return session
end
function O.ruleActive(session,node,index)
 local active=session.containerActive[node.key]
 return session.active[index]and(not active or active[index]~=false)
end
function O.candidates(session,node)
 local key=session.localKeys[node.key];local scope=session.scope
 local cached=scope.candidates[key];if cached then return cached end
 local plan=session.plan;local out={}
 local function add(list) for _,index in ipairs(list or EMPTY) do out[#out+1]=index end end
 add(plan.universal);add(plan.byTag[node.tag]);add(plan.byId[node.attrs.id])
 if node.aliases then for alias in pairs(node.aliases)do add(plan.byTag[alias])end end
 for class in pairs(session.classes[node.key] or EMPTY) do add(plan.byClass[class]) end
 table.sort(out)
 bounded(scope,'candidates',key,out,1024);return out
end
function O.getCascade(session,node)
 local scope=session.scope;local cached=scope.cascade[session.cascadeKeys[node.key]]
 if cached then scope.stats.cascadeHits+=1 else scope.stats.cascadeMisses+=1 end
 return cached
end
function O.putCascade(session,node,winners)
 local scope=session.scope;scope.nextCascade+=1
 local entry={id=scope.nextCascade,winners=winners}
 bounded(scope,'cascade',session.cascadeKeys[node.key],entry,2048);return entry
end
function O.selectorTest(session) session.scope.stats.selectorTests+=1 end
local function inheritanceKey(style)
 if not style then return '' end
 local out={}
 for _,key in ipairs(INHERITED) do out[#out+1]=atom(style[key]) end
 out[#out+1]=atom(style._fontPx);out[#out+1]=atom(style._rootFontPx)
 out[#out+1]=atom(style._lineHeight);out[#out+1]=atom(style._rootLineHeight)
 out[#out+1]=atom(style._chPx);out[#out+1]=atom(style._exPx)
 out[#out+1]=atom(style._icPx)..atom(style._capPx)..atom(style._rootChPx)..atom(style._rootExPx)..atom(style._rootIcPx)..atom(style._rootCapPx)
 local keys={};for key in pairs(style._vars or EMPTY) do keys[#keys+1]=key end;table.sort(keys)
 for _,key in ipairs(keys) do out[#out+1]=atom(key)..atom(style._vars[key]) end
 return table.concat(out)
end
function O.computedKey(session,node,parent,cascade)
 local attrs=node.attrs
 local unit=session.unitContexts and session.unitContexts[node.key]
 local unitKey=unit and(atom(unit.containerWidth)..atom(unit.containerHeight)..atom(unit.containerInline)..atom(unit.containerBlock)..atom(unit.containersResolved)..atom(unit.anchorKey))or ''
 return atom(unitKey)..atom(cascade.id)..atom(node.tag)..atom(attrs.width)..atom(attrs.height)..atom(attrs.dir)..atom(attrs.lang)..atom(node.anonymousText)..atom(inheritanceKey(parent))..session.viewportKey
end
local function copyStyle(style)
 local copy=table.clone(style)
 if style._vars then copy._vars=table.clone(style._vars) end
 if style._important then copy._important=table.clone(style._important) end
 return copy
end
local origins=setmetatable({},{__mode='k'})
 
 
function O.originOf(style)return origins[style]end
function O.getComputed(session,key)
 local scope=session.scope;local value=scope.computed[key]
 if value then scope.stats.computedHits+=1;local copy=copyStyle(value);origins[copy]=value;return copy end
 scope.stats.computedMisses+=1;return nil
end
function O.putComputed(session,key,style)
 bounded(session.scope,'computed',key,copyStyle(style),2048)
end
local function staticMatch(part,node,classes,parent)
 if part.tag and part.tag~='*' and part.tag~=node.tag then return false end
 if part.id and part.id~=node.attrs.id then return false end
 for _,class in ipairs(part.classes or EMPTY) do if not classes[class] then return false end end
 for _,state in ipairs(part.states or EMPTY) do if state=='root' and parent then return false end end
 return true
end
function O.statePlan(session)
 if session.plan.complex then
  local scope=session.scope;local key=session.mediaKey..':'..tostring(session.complexGeneration)..':'..session.queryKey
  if scope.complexStateKey~=key then scope.complexStateKey=key;scope.complexStateValue=Selectors.statePlan(session)end
  return scope.complexStateValue
 end
 local scope=session.scope;local stamp={session.mediaKey,session.queryKey}
 for _,node in ipairs(session.sequence) do
  local parent=session.parents[node.key]
  stamp[#stamp+1]=atom(node.key)..atom(parent and parent.key)..atom(session.localKeys[node.key])
 end
 local signature=table.concat(stamp)
 if scope.statePlanKey==signature then return scope.statePlanValue end
 local needs,seenRules={},{};local parents=session.parents
 for _,entry in ipairs(session.plan.stateParts) do
  if session.active[entry.rule] and not seenRules[entry.rule] then
   seenRules[entry.rule]=true
   local sel=scope.rules[entry.rule].selector;local memo,marked={},{}
   local function matches(index,node)
    if not node then return false end
    local id=index..':'..node.key
    if memo[id]~=nil then return memo[id] end
    local result=false
    if staticMatch(sel.parts[index],node,session.classes[node.key] or EMPTY,parents[node.key]) then
     if index==1 then result=true
     elseif sel.combinators[index-1]=='>' then result=matches(index-1,parents[node.key])
     else local up=parents[node.key];while up do if matches(index-1,up) then result=true;break end;up=parents[up.key] end end
    end
    memo[id]=result;return result
   end
   local function mark(index,node)
    if not node or not matches(index,node) then return end
    local id=index..':'..node.key;if marked[id] then return end;marked[id]=true
    for _,name in ipairs(sel.parts[index].states or EMPTY) do
     if dynamic(name) then needs[node.key]=needs[node.key] or {};needs[node.key][name]=true end
    end
    if index>1 then
     if sel.combinators[index-1]=='>' then mark(index-1,parents[node.key])
     else local up=parents[node.key];while up do mark(index-1,up);up=parents[up.key] end end
    end
   end
   for _,target in ipairs(session.sequence)do if session.checkpoint then session.checkpoint()end;if O.ruleActive(session,target,entry.rule)then mark(#sel.parts,target)end end
  end
 end
 scope.statePlanKey=signature;scope.statePlanValue=needs
 return needs
end
function O.invalidate(root) scopes[root]=nil end
function O.stats(root)
 local scope=scopes[root];if not scope then return {} end
 local out=table.clone(scope.stats)
 out.cascadeEntries=scope.cascadeCount;out.computedEntries=scope.computedCount;out.candidateEntries=scope.candidatesCount
 out.rules=scope.ruleCount;out.prunedRules=scope.plan.prunedRules or 0
 return out
end
return O
