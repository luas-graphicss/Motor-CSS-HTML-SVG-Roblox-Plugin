local Http=game:GetService('HttpService')
local Presentation=require(script.Parent.Presentation)
local M={VERSION='1.3.0',FORMAT=1,ROOT='Runtime',BOOTSTRAP='Bootstrap',LIMIT=250,VALUE='_CssManifest',FOLDER='_CssRuntime'}
local REQUIRE_PATTERN='require%s*%(%s*script%.Parent%.([%w_]+)%s*%)'
local OPTIONAL_PATTERN="optional%s*%(%s*'([%w_]+)'%s*%)"
local function mul32(a,b)
 local high=math.floor(a/65536)
 local low=a%65536
 return ((high*b)%65536*65536+low*b)%4294967296
end
local digests,digestCount={},0
function M.digest(text)
 assert(type(text)=='string','Digest exige texto.')
 local cached=digests[text]
 if cached then return cached[1],cached[2],cached[3]end
 local fnv,djb=2166136261,5381
 local length=#text
 local buf=buffer.fromstring(text)
 local readu8,bxor=buffer.readu8,bit32.bxor
 for index=0,length-1 do
  local byte=readu8(buf,index)
  local x=bxor(fnv,byte)
  local high=x//65536
  local low=x-high*65536
  fnv=((high*16777619)%65536*65536+low*16777619)%4294967296
  djb=(djb*33+byte)%4294967296
 end
 if digestCount>=128 then digests={};digestCount=0 end
 digests[text]={fnv,djb,length};digestCount+=1
 return fnv,djb,length
end
function M.hash(text)
 local fnv,djb=M.digest(text)
 return string.format('%08x%08x',fnv,djb)
end
local WIDE=table.freeze({initial=true,inherit=true,unset=true,revert=true,['revert-layer']=true})
local TABLE_TAGS=table.freeze({table=true,caption=true,colgroup=true,col=true,thead=true,tbody=true,tfoot=true,tr=true,td=true,th=true})
local RANKS=table.freeze({document=1,interface=2,screen=3,world=4})
local EMPTY=table.freeze({})
local function eachDeclaration(doc,visit)
 local found=nil
 local function set(list)
  if found or type(list)~='table'then return end
  for key,entry in pairs(list)do
   local name,value,shorthand=key,entry,nil
   if type(entry)=='table'then name=entry.key or key;value=entry.value;shorthand=entry.shorthand end
   found=visit(name,value,shorthand)
   if found then return end
  end
 end
 for _,list in ipairs({doc.rules,doc.svgRules,doc.viewTransitionRules})do
  if type(list)=='table'then
   for _,rule in ipairs(list)do
    if found then break end
    if type(rule)=='table'then set(rule.declarations)end
   end
  end
 end
 if type(doc.keyframes)=='table'then
  for _,frame in ipairs(doc.keyframes)do
   if found then break end
   if type(frame)=='table'and type(frame.stops)=='table'then
    for _,stop in ipairs(frame.stops)do if type(stop)=='table'then set(stop.declarations)end end
   end
  end
 end
 local registered=type(doc.stylePlan)=='table'and doc.stylePlan.registeredProperties or nil
 if type(registered)=='table'then
  for name,descriptor in pairs(registered)do
   if found then break end
   if type(descriptor)=='table'and type(descriptor.initial)=='string'then found=visit(name,descriptor.initial,nil)end
  end
 end
 local function walk(node)
  if found then return end
  set(node.inline)
  for _,child in ipairs(node.children or {})do walk(child)end
 end
 if type(doc.root)=='table'then walk(doc.root)end
 return found
end
local function meaningful(value)
 if type(value)~='string'then return value~=nil end
 local token=value:lower():match('^%s*(.-)%s*$')
 return WIDE[token]==nil
end
local function byPrefix(prefixes)
 return function(name)
  for _,prefix in ipairs(prefixes)do if name:sub(1,#prefix)==prefix then return true end end
  return false
 end
end
local function byName(names)
 local set={}
 for _,name in ipairs(names)do set[name]=true end
 return function(name)return set[name]==true end
end
local function declares(doc,test)
 return eachDeclaration(doc,function(name,value,shorthand)
  if type(name)~='string'or not meaningful(value)then return nil end
  if test(name)then return name end
  if type(shorthand)=='string'and test(shorthand)then return shorthand end
  return nil
 end)
end
local function mentions(doc,token)
 return eachDeclaration(doc,function(name,value)
  if type(value)=='string'and value:lower():find(token,1,true)then return tostring(name)..':'..token end
  return nil
 end)
end
local function hasNodeClass(doc,className)
 local found=nil
 local function walk(node)
  if found then return end
  if node.tag~='text'and node.tag~='svg'and Presentation.className(node)==className then found=node.tag;return end
  for _,child in ipairs(node.children or {})do walk(child)end
 end
 if type(doc.root)=='table'then walk(doc.root)end
 return found
end
local function tableNode(doc)
 local found=nil
 local function walk(node)
  if found then return end
  if TABLE_TAGS[node.tag]then found='tag:'..node.tag;return end
  if type(node.display)=='string'and node.display:sub(1,5)=='table'then found='display:'..node.display;return end
  for _,child in ipairs(node.children or {})do walk(child)end
 end
 if type(doc.root)=='table'then walk(doc.root)end
 return found
end
local function family(name,modules,detect)
 return table.freeze({name=name,modules=table.freeze(modules),detect=detect})
end
M.FAMILIES=table.freeze({
 family('layout-table',{'LayoutTable','TablePaint'},function(doc)return tableNode(doc)or mentions(doc,'table')end),
 family('layout-columns',{'LayoutColumns'},function(doc)return declares(doc,byName({'column-count','column-width','columns'}))end),
 family('layout-floats',{'LayoutTextFlow'},function(doc)return declares(doc,byName({'float','clear'}))end),
 family('layout-subgrid',{'LayoutSubgrid'},function(doc)return mentions(doc,'subgrid')end),
 family('transform-raster',{'RenderCore','RenderPresent'},function(doc)return declares(doc,byPrefix({'transform','perspective','offset','rotate','scale','translate'}))end),
 family('effects-backdrop',{'VisualEffectsCapture'},function(doc)return declares(doc,byName({'-roblox-backdrop-scope'}))end),
 family('effects-glyphs',{'VisualEffectsGlyphs'},function(doc)return declares(doc,byPrefix({'filter','backdrop-filter','-webkit-backdrop-filter','clip-path','mask','-webkit-mask','mix-blend-mode','background-blend-mode','isolation'}))end),
 family('svg-smil',{'SvgSmil'},function(doc)
  if type(doc.svgSources)=='table'and next(doc.svgSources)~=nil then return 'svgSources' end
  return nil
 end),
 family('text-selection',{'TextSelection'},function(doc)return hasNodeClass(doc,'TextBox')end),
 family('motion-typed',{'MotionUniversal'},function(doc)
  if type(doc.keyframes)=='table'and #doc.keyframes>0 then return 'keyframes' end
  if doc.viewTransitions~=nil then return 'viewTransitions' end
  return declares(doc,byPrefix({'transition','animation'}))
 end),
})
local function missing(family,name,method)
 return function()error('Módulo '..name..' da família '..family..' não foi exportado nesta interface; '..method..' indisponível.',0)end
end
local function no()return nil end
local function never()return false end
local function nothing()end
local FALLBACKS=table.freeze({
 SvgSmil=table.freeze({driver=no,interaction=no,plan=no,sample=function()return nil,false,nil end,values=no,hit=no,time=function()return 0 end}),
 TextSelection=table.freeze({apply=never,clear=never,active=never,range=no}),
 MotionUniversal=table.freeze({kinds=EMPTY,kind=no,supports=never,default=no,coerce=no,parse=no,serialize=no,materialize=no,declared=no,mentioned=function()return EMPTY end,list=function()return {}end}),
 LayoutTable=table.freeze({container=never,active=never,orphan=never,wrapped=never,shrinks=never,related=never,bind=nothing,plan=missing('layout-table','LayoutTable','plan')}),
 TablePaint=table.freeze({style=function(style)return style end,draw=nothing}),
 LayoutColumns=table.freeze({plan=missing('layout-columns','LayoutColumns','plan')}),
 LayoutTextFlow=table.freeze({raw=function()return ''end,fragmentable=never,finish=nothing,append=missing('layout-floats','LayoutTextFlow','append'),wrap=missing('layout-floats','LayoutTextFlow','wrap'),lineHeight=missing('layout-floats','LayoutTextFlow','lineHeight')}),
 LayoutSubgrid=table.freeze({is=never,binding=no,signature=function()return ''end,definitions=no,contribute=nothing,slice=missing('layout-subgrid','LayoutSubgrid','slice')}),
 RenderCore=table.freeze({VERSION=0,release=function(context)return context end,invalidateAll=never,invalidate=never,invalidateNode=never,create=missing('transform-raster','RenderCore','create'),frame=missing('transform-raster','RenderCore','frame'),render=missing('transform-raster','RenderCore','render'),present=missing('transform-raster','RenderCore','present'),stats=missing('transform-raster','RenderCore','stats'),plan=missing('transform-raster','RenderCore','plan'),budget=missing('transform-raster','RenderCore','budget'),capability=missing('transform-raster','RenderCore','capability')}),
 RenderPresent=table.freeze({release=nothing,attach=missing('transform-raster','RenderPresent','attach'),update=missing('transform-raster','RenderPresent','update'),report=missing('transform-raster','RenderPresent','report')}),
 VisualEffectsCapture=table.freeze({ranks=RANKS,rank=function(scope)return RANKS[scope or 'document']or 1 end,plan=no,world=missing('effects-backdrop','VisualEffectsCapture','world'),sampler=missing('effects-backdrop','VisualEffectsCapture','sampler'),describe=missing('effects-backdrop','VisualEffectsCapture','describe')}),
 VisualEffectsGlyphs=table.freeze({VERSION=0,MAX_TAPS=128,MAX_RINGS=12,MAX_LEVELS=255,MAX_CELL=16,MIN_ALPHA=1/255,sigma=missing('effects-glyphs','VisualEffectsGlyphs','sigma'),kernel=missing('effects-glyphs','VisualEffectsGlyphs','kernel'),stack=missing('effects-glyphs','VisualEffectsGlyphs','stack'),strips=missing('effects-glyphs','VisualEffectsGlyphs','strips')}),
})
local optionalOwners={}
for _,family in ipairs(M.FAMILIES)do
 for _,name in ipairs(family.modules)do
  assert(optionalOwners[name]==nil,'Módulo opcional em duas famílias: '..name)
  assert(FALLBACKS[name]~=nil,'Módulo opcional sem substituto: '..name)
  optionalOwners[name]=family.name
 end
end
M.optionalOwners=table.freeze(optionalOwners)
function M.optional(name)
 assert(optionalOwners[name],'Módulo opcional não declarado no manifesto: '..tostring(name))
 local module=script.Parent:FindFirstChild(name)
 if module and module:IsA('ModuleScript')then return require(module)end
 return FALLBACKS[name]
end
function M.capabilities(doc)
 assert(type(doc)=='table','capabilities exige o documento compilado.')
 local list,enabled,disabled={},{},{}
 for _,family in ipairs(M.FAMILIES)do
  local evidence=family.detect(doc)
  local modules=table.clone(family.modules)
  list[#list+1]={name=family.name,enabled=evidence~=nil,evidence=evidence,modules=modules}
  if evidence~=nil then enabled[#enabled+1]=family.name else disabled[#disabled+1]=family.name end
 end
 return {list=list,enabled=enabled,disabled=disabled}
end
function M.skipped(capabilities)
 local skip={}
 for _,family in ipairs(capabilities.list)do
  if not family.enabled then for _,name in ipairs(family.modules)do skip[name]=true end end
 end
 return skip
end
local dependencyCache,dependencyCount={},0
local function dependencies(text)
 local cached=dependencyCache[text]
 if cached then return cached end
 local required,optional={},{}
 for dependency in text:gmatch(REQUIRE_PATTERN)do required[#required+1]=dependency end
 for dependency in text:gmatch(OPTIONAL_PATTERN)do optional[#optional+1]=dependency end
 if dependencyCount>=512 then dependencyCache={};dependencyCount=0 end
 cached={required=required,optional=optional}
 dependencyCache[text]=cached;dependencyCount+=1
 return cached
end
function M.closure(source,roots,skip,checkpoint)
 skip=skip or {}
 local order,seen,forced={},{},{}
 for _,name in ipairs(roots or {M.ROOT})do
  if not seen[name]then
   local module=source:FindFirstChild(name)
   assert(module and module:IsA('ModuleScript'),'Raiz do runtime ausente: '..name)
   seen[name]=true;order[#order+1]=module
  end
 end
 local index=1
 while index<=#order do
  local module=order[index];index+=1
  local deps=dependencies(module.Source)
  for _,dependency in ipairs(deps.required)do
   if not seen[dependency]then
    local original=source:FindFirstChild(dependency)
    assert(original,'Dependência de runtime ausente: '..dependency..' (em '..module.Name..')')
    assert(original:IsA('ModuleScript'),'Dependência de runtime não é ModuleScript: '..dependency)
    if skip[dependency]then forced[dependency]=module.Name end
    seen[dependency]=true;order[#order+1]=original
    assert(#order<=M.LIMIT,'Runtime excede '..M.LIMIT..' módulos.')
   end
  end
  for _,dependency in ipairs(deps.optional)do
   assert(optionalOwners[dependency],'Módulo opcional não declarado no manifesto: '..dependency..' (em '..module.Name..')')
   assert(source:FindFirstChild(dependency),'Módulo opcional ausente na origem: '..dependency)
  end
  if checkpoint and index%16==0 then checkpoint()end
 end
 return order,forced
end
function M.resolve(doc,source,checkpoint)
 local capabilities=M.capabilities(doc)
 local modules,forced
 for _=1,#M.FAMILIES+1 do
  local skip=M.skipped(capabilities)
  local roots={M.ROOT}
  for _,family in ipairs(capabilities.list)do
   if family.enabled then for _,name in ipairs(family.modules)do roots[#roots+1]=name end end
  end
  modules,forced=M.closure(source,roots,skip,checkpoint)
  local changed=false
  for _,family in ipairs(capabilities.list)do
   if not family.enabled then
    for _,name in ipairs(family.modules)do
     if forced[name]then family.enabled=true;family.forcedBy=forced[name];family.evidence='require:'..forced[name];changed=true;break end
    end
   end
  end
  if not changed then break end
 end
 local enabled,disabled,skipped={},{},{}
 for _,family in ipairs(capabilities.list)do
  if family.enabled then enabled[#enabled+1]=family.name else disabled[#disabled+1]=family.name;for _,name in ipairs(family.modules)do skipped[#skipped+1]=name end end
 end
 table.sort(skipped)
 capabilities.enabled=enabled;capabilities.disabled=disabled;capabilities.skipped=skipped
 return capabilities,modules
end
local function record(entries,lines,name,text)
 local fnv,djb,length=M.digest(text)
 local hash=string.format('%08x%08x',fnv,djb)
 entries[name]={hash=hash,bytes=length}
 lines[#lines+1]=name..'@'..hash..':'..length
 return length
end
function M.describe(doc,source)
 local capabilities,modules=M.resolve(doc,source)
 local names={}
 for index,module in ipairs(modules)do names[index]=module.Name end
 table.sort(names)
 return {capabilities=capabilities,modules=names}
end
function M.export(runtime,doc,source,templates,checkpoint)
 assert(runtime and runtime:IsA('Folder'),'export exige a pasta de runtime.')
 assert(source and templates,'export exige a origem dos módulos e os templates.')
 local capabilities,modules=M.resolve(doc,source,checkpoint)
 local entries,lines,names,bytes={},{},{},0
 for _,module in ipairs(modules)do
  local copy=module:Clone();copy.Parent=runtime
  names[#names+1]=module.Name
  bytes+=record(entries,lines,module.Name,module.Source)
  if checkpoint and #names%16==0 then checkpoint()end
 end
 local template=assert(templates:FindFirstChild(M.BOOTSTRAP),'Template de arranque ausente.')
 local bootstrap=template:Clone();bootstrap.Disabled=false;bootstrap.Parent=runtime
 names[#names+1]=M.BOOTSTRAP
 bytes+=record(entries,lines,M.BOOTSTRAP,template.Source)
 table.sort(names);table.sort(lines)
 return {format=M.FORMAT,version=M.VERSION,root=M.ROOT,count=#names,bytes=bytes,aggregate=M.hash(table.concat(lines,'\n')),modules=names,hashes=entries,capabilities=capabilities.list,enabled=capabilities.enabled,disabled=capabilities.disabled,skipped=capabilities.skipped}
end
function M.read(gui)
 local value=gui and gui:FindFirstChild(M.VALUE)
 if not value or not value:IsA('StringValue')or value.Value==''then return nil end
 local ok,manifest=pcall(Http.JSONDecode,Http,value.Value)
 assert(ok and type(manifest)=='table','Manifesto de runtime ilegível.')
 return manifest
end
function M.verify(gui,runtime)
 local manifest=M.read(gui)
 if manifest==nil then return nil end
 assert(manifest.format==M.FORMAT,'Formato de manifesto não suportado: '..tostring(manifest.format))
 assert(manifest.version==M.VERSION,'Runtime exportado '..tostring(manifest.version)..' difere do runtime carregado '..M.VERSION..'.')
 runtime=runtime or gui:FindFirstChild(M.FOLDER)
 assert(runtime,'Pasta de runtime ausente.')
 for _,name in ipairs(manifest.modules or {})do
  local module=runtime:FindFirstChild(name)
  assert(module and module:IsA('LuaSourceContainer'),'Módulo do manifesto ausente: '..name)
 end
 return manifest
end
function M.audit(gui,runtime)
 local manifest=M.verify(gui,runtime)
 if manifest==nil then return nil end
 runtime=runtime or gui:FindFirstChild(M.FOLDER)
 local changed,extra,listed={},{},{}
 for name,entry in pairs(manifest.hashes or {})do
  listed[name]=true
  local module=runtime:FindFirstChild(name)
  if module and M.hash(module.Source)~=entry.hash then changed[#changed+1]=name end
 end
 for _,child in ipairs(runtime:GetChildren())do
  if child:IsA('LuaSourceContainer')and not listed[child.Name]then extra[#extra+1]=child.Name end
 end
 table.sort(changed);table.sort(extra)
 return {ok=#changed==0 and #extra==0,changed=changed,extra=extra,manifest=manifest}
end
return M
