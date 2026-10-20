local U=require(script.Parent.Util)
local Cost=require(script.Parent.CostModel)
local Motion=require(script.Parent.Motion)
local MotionAdvanced=require(script.Parent.MotionAdvanced)
local PropertyRegistry=require(script.Parent.PropertyRegistry)
local ViewTransitions=require(script.Parent.ViewTransitions)
local Selectors=require(script.Parent.Selectors)
local Counters=require(script.Parent.CssCounters)
local Optimizer=require(script.Parent.StyleOptimizer)
local PseudoElements=require(script.Parent.PseudoElements)
local Units=require(script.Parent.StyleUnits)
local Variables=require(script.Parent.CssVariables)
local Typography=require(script.Parent.TypographyStyle)
local FontFaces=require(script.Parent.FontFaces)
local FontFeatures=require(script.Parent.FontFeatures)
local LayoutProperties=require(script.Parent.LayoutProperties)
local Logical=require(script.Parent.LogicalProperties)
local VisualStyle=require(script.Parent.VisualStyle)
local VisualEffectsStyle=require(script.Parent.VisualEffectsStyle)
local SvgStyle=require(script.Parent.SvgStyle)
local Scroll=require(script.Parent.ScrollStyle)
local Queries=require(script.Parent.ResponsiveQueries)
local ColorTheme=require(script.Parent.ColorTheme)
local Cascade=require(script.Parent.CssCascade)
local Syntax=require(script.Parent.CssSyntax)
local Supports=require(script.Parent.FeatureSupports)
local AdvancedCssSupport=require(script.Parent.AdvancedCssSupport)
local AdvancedImaging=require(script.Parent.AdvancedImaging)
local FeatureSupportsBridge=require(script.Parent.FeatureSupportsBridge)
local Containment=require(script.Parent.CssContainment)
local Overflow=require(script.Parent.Overflow)
local Scrollbars=require(script.Parent.Scrollbars)
local PositionTry=require(script.Parent.CssPositionTry)
local Catalog=require(script.Parent.CssPropertyCatalog)
local Page=require(script.Parent.CssPage)
local Env=require(script.Parent.CssEnvironment)
local WillChange=require(script.Parent.WillChange)
AdvancedCssSupport.install(Supports)
AdvancedImaging.install(Supports)
FeatureSupportsBridge.install(Supports)
Containment.install(Supports,function(value)return U.length(value,200,1280,720,16)~=nil end)
PositionTry.install(Supports)
Overflow.install(Supports)
Scrollbars.install(Supports)
WillChange.install(Supports)
local S={}
function S.prepare(root,rules,meta)
 local filtered,plan=Optimizer.prepare(root,rules)
 plan.units=Units.prepare(root,filtered)
 plan.layerEvents=rules[1]and rules[1].layerEvents
 plan.positionTry=PositionTry.blocks(rules[1]and rules[1].positionTry)
 plan.meta=rules[1]and rules[1].meta or meta or nil
 plan.counterStyles=rules[1]and rules[1].counterStyles or(plan.meta and plan.meta.counterStyles and plan.meta.counterStyles[1]and plan.meta.counterStyles)or nil
 if filtered[1]and plan.layerEvents then filtered[1]=table.clone(filtered[1]);filtered[1].layerEvents=plan.layerEvents end
 return filtered,plan
end
S.invalidate=Optimizer.invalidate
S.cacheStats=Optimizer.stats
local supported={['color-scheme']=true,content=true,['container-type']=true,['container-name']=true,['transform-origin']=true,perspective=true,['perspective-origin']=true,['backface-visibility']=true,['transform-style']=true,['transform-box']=true}
for _,property in ipairs({'anchor-name','anchor-scope','position-anchor','position-area','position-try','position-try-order','position-try-fallbacks','position-visibility'})do supported[property]=true end
for _,property in ipairs({'contain','contain-intrinsic-size','contain-intrinsic-width','contain-intrinsic-height','contain-intrinsic-inline-size','contain-intrinsic-block-size','content-visibility','container'})do supported[property]=true end
for _,property in ipairs({'counter-reset','counter-increment','counter-set','quotes','list-style','list-style-type','list-style-position','list-style-image'})do supported[property]=true end
for _,property in ipairs(Typography.properties)do supported[property]=true end
for key in pairs(LayoutProperties.supported)do supported[key]=true end
for word in ('display position width height min-width max-width min-height max-height left right top bottom padding margin gap row-gap column-gap flex flex-flow flex-wrap align-content transition transition-property transition-duration transition-delay transition-timing-function animation animation-name animation-duration animation-delay animation-timing-function animation-iteration-count animation-direction animation-fill-mode animation-play-state flex-direction flex-grow flex-shrink flex-basis align-items align-self justify-content grid-template-columns background background-color color border border-width border-color border-style border-radius border-top-left-radius border-top-right-radius border-bottom-left-radius border-bottom-right-radius box-shadow font-family font-size font-weight text-align vertical-align white-space text-overflow opacity overflow z-index transform box-sizing'):gmatch('%S+') do supported[word]=true end
for _,base in ipairs({'padding','margin'}) do for _,side in ipairs({'top','right','bottom','left'}) do supported[base..'-'..side]=true end end
for _,property in ipairs(Page.properties)do supported[property]=true end
supported['will-change']=true
local FormAppearance=require(script.Parent.FormAppearance)
local PointerStyle=require(script.Parent.PointerStyle)
local inherited=table.clone(Optimizer.inherited)
for _,key in ipairs(SvgStyle.inherited)do inherited[#inherited+1]=key end
for _,key in ipairs(FormAppearance.inherited)do inherited[#inherited+1]=key end
for _,key in ipairs(Page.properties)do inherited[#inherited+1]=key end
local shorthandKeys={
 ['text-decoration']=Typography.decorationKeys,
 transition={'transition-property','transition-duration','transition-timing-function','transition-delay'},
 animation={'animation-name','animation-duration','animation-delay','animation-timing-function','animation-iteration-count','animation-direction','animation-fill-mode','animation-play-state'},
 ['flex-flow']={'flex-direction','flex-wrap'},flex={'flex-grow','flex-shrink','flex-basis'}
}
for key,values in pairs(LayoutProperties.shorthands)do shorthandKeys[key]=values end
shorthandKeys.container={'container-name','container-type'}
shorthandKeys['contain-intrinsic-size']={'contain-intrinsic-width','contain-intrinsic-height'}
shorthandKeys['position-try']={'position-try-order','position-try-fallbacks'}
shorthandKeys['list-style']={'list-style-type','list-style-position','list-style-image'}
VisualStyle.register(supported,shorthandKeys)
VisualEffectsStyle.register(supported,shorthandKeys)
AdvancedImaging.register(supported,shorthandKeys)
SvgStyle.register(supported,shorthandKeys)
Logical.register(supported,shorthandKeys)
Typography.register(supported,shorthandKeys)
Scroll.register(supported,shorthandKeys)
MotionAdvanced.register(supported,shorthandKeys)
ViewTransitions.register(supported,shorthandKeys)
FormAppearance.register(supported,shorthandKeys)
FormAppearance.install(Supports)
PointerStyle.register(supported,shorthandKeys)
PointerStyle.install(Supports)
local deferredKeys={padding={'padding-top','padding-right','padding-bottom','padding-left'},margin={'margin-top','margin-right','margin-bottom','margin-left'},['border-radius']={'border-top-left-radius','border-top-right-radius','border-bottom-right-radius','border-bottom-left-radius'},gap={'row-gap','column-gap'},border={'border-width','border-color'}}
local catalog=Catalog.build({supported=supported,shorthands=shorthandKeys,deferred=deferredKeys,defaults=Optimizer.defaults,inherited=inherited})
S.catalog=catalog
S.ORIGIN=Catalog.ORIGIN
function S.describeCatalog()return Catalog.describe(catalog)end
function S.property(name)return Catalog.entry(catalog,name)end
local function expand(name,value)
 if name=='container'then
  local parts=U.split(value,'/');assert(#parts>=1 and #parts<=2,'container aceita <nome> / <tipo>.')
  local names=U.trim(parts[1])
  return {['container-name']=names==''and'none'or names,['container-type']=parts[2]and U.trim(parts[2])or'normal'}
 end
 if name=='contain-intrinsic-size'then
  local w,h=Containment.expand(value);return {['contain-intrinsic-width']=w,['contain-intrinsic-height']=h}
 end
 if name=='position-try'then
  local order,fallbacks=PositionTry.expandShorthand(value);return {['position-try-order']=order,['position-try-fallbacks']=fallbacks}
 end
 if name=='list-style'then return Counters.expandListStyle(value)end
 local logical=Logical.expand(name,value);if logical then return logical end
 local scroll=Scroll.expand(name,value);if scroll then return scroll end
 local text=Typography.expandProperty(name,value);if text then return text end
 local vector=SvgStyle.expand(name,value);if vector then return vector end
 local effect=VisualEffectsStyle.expand(name,value);if effect then return effect end
 local visual=VisualStyle.expand(name,value);if visual then return visual end
 if deferredKeys[name]and not shorthandKeys[name]then
  local out={};for _,declaration in ipairs(S.declarations(name..':'..value))do out[declaration.key]=declaration.value end
  return out
 end
 if name=='text-decoration'then return Typography.expand(value)end
 if LayoutProperties.shorthands[name]then return LayoutProperties.expand(name,value)end
 if name=='transition' then return Motion.expandTransition(value)elseif name=='animation'then return Motion.expandAnimation(value)end
 local tokens=U.split(value,' ')
 if name=='flex-flow'then
  local out={['flex-direction']='row',['flex-wrap']='nowrap'};local seen={}
  for _,v in ipairs(tokens)do local k=({row=true,column=true,['row-reverse']=true,['column-reverse']=true})[v] and 'flex-direction' or (({nowrap=true,wrap=true,['wrap-reverse']=true})[v] and 'flex-wrap')
   assert(k and not seen[k],'flex-flow inválido: '..value);seen[k]=true;out[k]=v end;return out
 end
 local g,s,b='1','1','0%'
 if value=='none'then g,s,b='0','0','auto'elseif value=='auto'then b='auto'elseif value=='initial'then g,b='0','auto'
 else
  assert(#tokens>=1 and #tokens<=3,'flex inválido.')
  if tonumber(tokens[1])then g=tokens[1];if #tokens==2 then if tonumber(tokens[2])then s=tokens[2]else b=tokens[2]end elseif #tokens==3 then s,b=tokens[2],tokens[3];assert(tonumber(s),'flex-shrink inválido.')end
  else assert(#tokens==1,'flex inválido.');b=tokens[1]end
  assert(tonumber(g)>=0 and tonumber(s)>=0,'flex-grow/shrink devem ser positivos.')
 end
 return {['flex-grow']=g,['flex-shrink']=s,['flex-basis']=b}
end
local function put(out,k,v,important)
 if k=='all'then
  local token=assert(Catalog.wide(v),'all aceita apenas initial, inherit, unset, revert ou revert-layer.')
  for _,key in ipairs(catalog.resettable)do put(out,key,token,important)end
  return
 end
 if k=='background-color'then table.insert(out,{key='background',value=v,important=important});return end
 if deferredKeys[k]and not shorthandKeys[k]and Variables.has(v)then
  for _,key in ipairs(deferredKeys[k])do table.insert(out,{key=key,value=v,important=important,shorthand=k})end
  return
 end
 if shorthandKeys[k]then
  for _,key in ipairs(shorthandKeys[k])do table.insert(out,{key=key,value=v,important=important,shorthand=k})end
 elseif k=='padding' or k=='margin' or k=='border-radius' then
  local w=U.split(v,' '); assert(#w>=1 and #w<=4,'Shorthand inválido: '..k)
  local vals={w[1],w[2] or w[1],w[3] or w[1],w[4] or w[2] or w[1]}
  local keys=k=='border-radius' and {'border-top-left-radius','border-top-right-radius','border-bottom-right-radius','border-bottom-left-radius'} or {k..'-top',k..'-right',k..'-bottom',k..'-left'}
  for i,key in ipairs(keys) do table.insert(out,{key=key,value=vals[i],important=important}) end
 elseif k=='gap' then local gaps=U.split(v,' '); assert(#gaps==1 or #gaps==2,'gap aceita 1 ou 2 valores.'); put(out,'row-gap',gaps[1],important); put(out,'column-gap',gaps[2] or gaps[1],important)
 elseif k=='border' then
  if v=='none' or v=='0' then put(out,'border-width','0',important) else
   local parts=U.split(v,' '); assert(#parts==3 and parts[2]=='solid','Use border: 1px solid #cor.')
   put(out,'border-width',parts[1],important); put(out,'border-color',parts[3],important)
  end
 else table.insert(out,{key=k,value=v,important=important}) end
end
function S.declarations(body,recovery)
 body=Variables.stripComments(body)
 local out={}
 local recover=type(recovery)=='table'and recovery.recover==true
 local diagnostics=type(recovery)=='table'and recovery.diagnostics or nil
 local function readOne(line)
  local k,v=line:match('^%s*([%w_%-]+)%s*:%s*(.-)%s*$'); assert(k and(v~=''or k:sub(1,2)=='--'),'Declaração CSS inválida: '..line)
  if k:sub(1,2)~='--'then k=k:lower()end
  assert(supported[k]or k=='all'or k:match('^%-%-[%w_%-]+$'),'Propriedade não suportada: '..k)
  local important=v:match('%s*![iI][mM][pP][oO][rR][tT][aA][nN][tT]%s*$')~=nil
  v=U.trim(v:gsub('%s*![iI][mM][pP][oO][rR][tT][aA][nN][tT]%s*$',''))
  put(out,k,v,important)
 end
 for _,line in ipairs(U.split(body,';')) do
  local mark=#out
  local ok,err=pcall(readOne,line)
  if not ok then
   for index=#out,mark+1,-1 do out[index]=nil end
   if not recover then error(err,0)end
   if diagnostics then diagnostics[#diagnostics+1]={scope='declaration',source=U.trim(line),message=tostring(err)}end
  end
 end
 return out
end
local selector=Selectors.parse
local frameProperties={background=true,opacity=true,transform=true,['offset-distance']=true,['animation-timing-function']=true}
local function readKeyframes(name,body,minWidth,maxWidth,order)
 local byOffset={};local pos,count=1,0
 while pos<=#body do
  local ws=body:sub(pos):match('^%s*');pos+=#ws;if pos>#body then break end
  local open=assert(body:find('{',pos,true),'Keyframe sem bloco.');local close=assert(body:find('}',open+1,true),'Keyframe não fechado.')
  local selectors=U.split(U.trim(body:sub(pos,open-1)),',');local decls=S.declarations(body:sub(open+1,close-1));pos=close+1
  for _,d in ipairs(decls)do assert((frameProperties[d.key]or d.key:sub(1,2)=='--'or MotionAdvanced.animatable(d.key))and not d.important,'Keyframes animam propriedades animáveis; !important não é permitido em '..d.key..'.')end
  for _,sel in ipairs(selectors)do
   local offset=sel=='from'and 0 or sel=='to'and 1 or tonumber(sel:match('^([%d%.]+)%%$'))
   if sel~='from'and sel~='to'and offset then offset/=100 end
   assert(offset and offset>=0 and offset<=1,'Offset de keyframe inválido: '..sel)
   if not byOffset[offset]then count+=1;assert(count<=64,'Máximo de 64 offsets por @keyframes.');byOffset[offset]={}end
   for _,d in ipairs(decls)do byOffset[offset][d.key]=d end
  end
 end
 assert(count>0,'@keyframes vazio.');local stops={}
 for offset,map in pairs(byOffset)do local decls={};for _,d in pairs(map)do table.insert(decls,d)end;table.sort(decls,function(a,b)return a.key<b.key end);table.insert(stops,{offset=offset,declarations=decls})end
 table.sort(stops,function(a,b)return a.offset<b.offset end)
 return {name=name,stops=stops,minWidth=minWidth,maxWidth=maxWidth,order=order}
end
local function stripComments(text,checkpoint)
 local out,start,i,q,escaped={},1,1,nil,false
 while i<=#text do
  if checkpoint and i%1024==0 then checkpoint(8)end
  local c=text:sub(i,i)
  if q then
   if escaped then escaped=false elseif c==string.char(92)then escaped=true elseif c==q then q=nil end
  elseif c=='"'or c=="'"then q=c
  elseif text:sub(i,i+1)=='/*'then
   out[#out+1]=text:sub(start,i-1);out[#out+1]=' '
   local close=assert(text:find('*/',i+2,true),'Comentário CSS não fechado.')
   i=close+2;start=i;continue
  end
  i+=1
 end
 out[#out+1]=text:sub(start);return table.concat(out)
end
local supportHooks={supported=supported,declarations=S.declarations,shorthands=shorthandKeys,expand=expand,catalog=catalog,entry=function(name)return Catalog.entry(catalog,name)end}
function S.supports(expression)
 local ok,result=pcall(function()return Supports.evaluate(Supports.parse(expression),supportHooks)end)
 return ok and result==true
end
function S.supportsDeclaration(property,value)return Supports.declaration(property,value,supportHooks)end
function S.parse(css,options)
 options=options or {};assert(type(css)=='string','CSS precisa ser texto.');Cost.cap('bytes',#css,'Folha de estilo')
 css=stripComments(css,options.checkpoint)
 local recovery={recover=options.recover==true,diagnostics=options.diagnostics}
 local packed=table.pack(Syntax.parse(css,{declarations=function(body)return S.declarations(body,recovery)end,page=function(body)return Page.declarations(body,function(rest)return S.declarations(rest,recovery)end)end,selector=selector,keyframes=readKeyframes,queries=Queries,fontFace=function(body)return FontFaces.parse(body,U)end,counterStyle=function(name,body)return Counters.parse(name,body)end,property=function(name,body)return PropertyRegistry.parse(name,body)end,viewTransition=ViewTransitions.parse,supports=function(expression)return Supports.evaluate(Supports.parse(expression),supportHooks)end,catalog=catalog,import=function(entry)
  local resolver=options.imports
  if type(resolver)=='function'then return resolver(entry)end
  if type(resolver)=='table'then return resolver[entry.href]end
  return nil
 end},options))
 if options.origin and type(packed[1])=='table'then
  local origin=Catalog.origin(options.origin)
  for _,rule in ipairs(packed[1])do rule.origin=origin end
 end
 return table.unpack(packed,1,packed.n)
end
S.matches=Selectors.matches
S.scoped=Selectors.scoped
local variables=Variables.resolve
S.resolveValue=variables
function S.compute(root,rules,state,width,height,prepared,options)
 options=options or {};local checkpoint=options.checkpoint
 local envValues=options.environment or Env.defaults()
 if not options.environmentKey then options.environmentKey=Env.key(envValues)end
 local function envText(text)
  if envValues and Env.has(text)then return Env.substitute(text,envValues)end
  return text
 end
 local function envWinners(source)
  if not envValues then return source end
  local out=source
  for k,d in pairs(source)do
   if Env.has(d.value)then
    if out==source then out=table.clone(source)end
    local copy=table.clone(d);copy.value=Env.substitute(d.value,envValues);out[k]=copy
   end
  end
  return out
 end
 local session=Optimizer.begin(root,rules,state,width,height,prepared,options)
 local styles={};local parents,sequence=session.parents,session.sequence;local expansionCache={}
 state=state or {}
 local featureValues=prepared and prepared.fontFeatureValues
 if featureValues then
  local active={}
  for _,entry in ipairs(featureValues)do if not entry.conditions or Queries.mediaActive(entry,width,height,session.mediaEnvironment)then active[#active+1]=entry end end
  featureValues=active[1]and active or nil
 end
 for _,node in ipairs(sequence) do
  if checkpoint then checkpoint()end
  local parent=parents[node.key];local ps=parent and styles[parent.key]
  local cascade=Optimizer.getCascade(session,node)
  local winners=cascade and cascade.winners or {}
  local function apply(decls,spec,order,layer,inline,origin,proximity)
   Cascade.apply(winners,decls,spec,order,layer,inline,session.layerOrder,origin,proximity)
  end
  if not cascade then
   local startingWinners,startingRules
   if node.hints then apply(node.hints,0,0,nil,false) end
   for _,index in ipairs(Optimizer.candidates(session,node)) do
    local rule=rules[index]
    if Optimizer.ruleActive(session,node,index) then
     Optimizer.selectorTest(session)
     local matched,proximity
     if rule.scope then matched,proximity=Selectors.scoped(rule.scope,rule.selector,node,state,parents,session.classes)
     else matched=S.matches(rule.selector,node,state,parents,session.classes) end
     if matched then
      if rule.startingStyle then
       startingRules=startingRules or {}
       startingRules[#startingRules+1]={rule=rule,proximity=proximity}
      else apply(rule.declarations,rule.selector.specificity,rule.order,rule.layer,false,rule.origin,proximity) end
     end
    end
   end
   if startingRules then
    startingWinners=Cascade.clone(winners)
    for _,entry in ipairs(startingRules)do
     local rule=entry.rule
     Cascade.apply(startingWinners,rule.declarations,rule.selector.specificity,rule.order,rule.layer,false,session.layerOrder,rule.origin,entry.proximity)
    end
   end
   if node.inline then
    apply(node.inline,0,501,nil,true)
    if startingWinners then Cascade.apply(startingWinners,node.inline,0,501,nil,true,session.layerOrder)end
   end
   Cascade.finish(winners)
   cascade=Optimizer.putCascade(session,node,winners)
   if startingWinners then
    Cascade.finish(startingWinners)
    local differs={}
    for k,d in pairs(startingWinners)do
     local normal=winners[k]
     if not normal or normal.value~=d.value or normal.shorthand~=d.shorthand then differs[k]=d end
    end
    if next(differs)then cascade.starting=differs end
   end
  end
  local computedKey=Optimizer.computedKey(session,node,ps,cascade)
  local style=cascade.starting==nil and Optimizer.getComputed(session,computedKey)or nil
  if not style then
  style=Optimizer.newStyle(node,ps)
  local resolvedWinners=envWinners(winners)
  local vars=Variables.compute(ps and ps._vars,resolvedWinners)
  local registered=prepared and prepared.registeredProperties
  if registered then PropertyRegistry.compute(vars,ps and ps._vars,resolvedWinners,registered);style._registered=registered end
  style._important={}
  for k,d in pairs(resolvedWinners) do if k:sub(1,2)~='--'then
   local value=variables(d.value,vars)
   if d.shorthand then local cacheKey=d.shorthand..'|'..value;local expanded=expansionCache[cacheKey];if not expanded then expanded=expand(d.shorthand,value);expansionCache[cacheKey]=expanded end;value=expanded[k]end
   style[k]=Logical.supported[k]and value or Cascade.wide(value,k,ps,Optimizer.defaults,inherited,catalog);style._important[k]=d.important==true
   if k=='vertical-align'then style._alignSet=true end
  end end
  for _,k in ipairs(inherited) do if style[k]=='inherit' then style[k]=ps and ps[k] or Optimizer.defaults[k] end end
  style._vars=vars;style._mediaEnvironment=session.mediaEnvironment
  Logical.resolve(style,resolvedWinners,ps)
  ColorTheme.normalize(style,ps,session.mediaEnvironment)
  AdvancedCssSupport.validate(style)
  WillChange.normalize(style)
  PointerStyle.check(style)
  Typography.prepare(style,ps)
  if featureValues then FontFeatures.resolveAlternates(style,featureValues)end
  FontFaces.compute(style,prepared and prepared.fontFaces,width,height,prepared and prepared.fontVariants)
  Units.normalize(style,ps,width,height,prepared and prepared.units,node==root,session.unitContexts and session.unitContexts[node.key],session.viewport)
  Logical.finish(style)
  Typography.normalize(style,ps,width,height)
  Scroll.normalize(style,ps)
  if node==root and prepared and prepared.meta and prepared.meta.pages and prepared.meta.pages[1]and session.mediaEnvironment and session.mediaEnvironment.mediaType=='print'then Page.applyRoot(style,prepared.meta.pages,{first=true,side='right'},function(value)return U.length(value,width,width,height)end)end
  if cascade.starting then
   local startingValues={}
   for k,d in pairs(cascade.starting)do if k:sub(1,2)~='--'then
    local value=variables(envText(d.value),vars)
    if d.shorthand then local expanded=expand(d.shorthand,value);value=expanded[k]end
    if value~=nil then startingValues[k]=value end
   end end
   style._starting=startingValues
  else Optimizer.putComputed(session,computedKey,style)end
  end
  if style['position-try-fallbacks']and prepared and prepared.positionTry then style._positionTryBlocks=prepared.positionTry end
  styles[node.key]=style
 end
 local statePlan=Optimizer.statePlan(session)
 local visualRoot
 styles,sequence,parents,visualRoot=PseudoElements.expand(root,rules,state,width,height or width,styles,sequence,parents,S.matches,variables,expand,Optimizer.newStyle,session,prepared)
 return styles,sequence,parents,statePlan,visualRoot
end
return S
