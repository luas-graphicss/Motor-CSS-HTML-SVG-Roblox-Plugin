local Http=game:GetService('HttpService')
local Storage=game:GetService('ServerStorage')
local Runtime=require(script.Parent.RuntimeManifest)
local M={VERSION=1,PLUGIN=Runtime.VERSION,FOLDER='CssPluginManifests',OWNER='CssPlugin'}
M.digest=Runtime.digest
M.hash=Runtime.hash
function M.sources(root)
 root=root or script.Parent.Parent
 local out={}
 if root:IsA('LuaSourceContainer')then out[root.Name]=root.Source end
 for _,item in ipairs(root:GetDescendants())do
  if item:IsA('LuaSourceContainer')then
   local path=item.Name
   local parent=item.Parent
   while parent and parent~=root do path=parent.Name..'/'..path;parent=parent.Parent end
   out[path]=item.Source
  end
 end
 return out
end
function M.build(options)
 options=options or {}
 local sources=options.sources or M.sources(options.root)
 local order={}
 for name in pairs(sources)do order[#order+1]=name end
 table.sort(order)
 local modules,bytes,lines={},0,{}
 for _,name in ipairs(order)do
  local fnv,djb,length=M.digest(sources[name])
  local entry={hash=string.format('%08x%08x',fnv,djb),fnv=fnv,djb=djb,bytes=length}
  modules[name]=entry;bytes+=length
  lines[#lines+1]=name..'@'..entry.hash..':'..length
 end
 local fnv,djb=M.digest(table.concat(lines,'\n'))
 return {version=M.VERSION,plugin=M.PLUGIN,label=options.label or 'dev',created=os.date('!%Y-%m-%dT%H:%M:%SZ'),place=game.PlaceId,count=#order,bytes=bytes,order=order,modules=modules,aggregate=string.format('%08x%08x',fnv,djb)}
end
local currentCache=nil
local function signature(root)
 root=root or script.Parent.Parent
 local count,bytes=0,0
 for _,item in ipairs(root:GetDescendants())do
  if item:IsA('LuaSourceContainer')then count+=1;bytes+=#item.Source end
 end
 return count..':'..bytes
end
function M.current(options)
 options=options or {}
 local key=signature(options.root)
 if currentCache and currentCache.key==key and not options.refresh then return currentCache.manifest end
 local manifest=M.build({root=options.root,label=options.label or 'current'})
 currentCache={key=key,manifest=manifest}
 return manifest
end
function M.drift(name,options)
 local stored=M.load(name or 'release')
 if not stored then return nil end
 local diff=M.compare(stored,M.current(options))
 diff.stored=stored
 return diff
end
function M.compare(before,after)
 assert(type(before)=='table'and type(after)=='table','compare exige dois manifestos.')
 local added,removed,changed,same={},{},{},0
 for name,entry in pairs(after.modules or {})do
  local previous=(before.modules or {})[name]
  if not previous then added[#added+1]=name
  elseif previous.hash~=entry.hash then changed[#changed+1]={name=name,from=previous.hash,to=entry.hash,bytes=(entry.bytes or 0)-(previous.bytes or 0)}
  else same+=1 end
 end
 for name in pairs(before.modules or {})do
  if not (after.modules or {})[name] then removed[#removed+1]=name end
 end
 table.sort(added);table.sort(removed)
 table.sort(changed,function(a,b)return a.name<b.name end)
 return {ok=#added==0 and #removed==0 and #changed==0,added=added,removed=removed,changed=changed,same=same,from=before.aggregate,to=after.aggregate,fromLabel=before.label,toLabel=after.label}
end
function M.verify(manifest,options)
 assert(type(manifest)=='table','verify exige um manifesto.')
 local current=M.build(options)
 local diff=M.compare(manifest,current)
 diff.current=current
 return diff.ok,diff
end
local function folder(create)
 local existing=Storage:FindFirstChild(M.FOLDER)
 if existing then
  assert(existing:IsA('Folder')and existing:GetAttribute('CssOwner')==M.OWNER,'ServerStorage.'..M.FOLDER..' pertence a outro sistema.')
  return existing
 end
 if not create then return nil end
 local created=Instance.new('Folder')
 created.Name=M.FOLDER
 created:SetAttribute('CssOwner',M.OWNER)
 created.Parent=Storage
 return created
end
function M.store(manifest,name)
 assert(type(manifest)=='table'and manifest.aggregate,'store exige um manifesto.')
 name=name or manifest.label or 'dev'
 assert(type(name)=='string'and name:match('^[%a_][%w_%-%.]*$')and #name<=48,'Nome de manifesto invalido.')
 local root=folder(true)
 local value=root:FindFirstChild(name)
 if not value then value=Instance.new('StringValue');value.Name=name;value.Parent=root end
 assert(value:IsA('StringValue'),'Manifesto existente nao e StringValue.')
 value.Value=Http:JSONEncode(manifest)
 value:SetAttribute('CssAggregate',manifest.aggregate)
 value:SetAttribute('CssCreated',manifest.created)
 value:SetAttribute('CssModules',manifest.count)
 return value
end
function M.load(name)
 local root=folder(false)
 local value=root and root:FindFirstChild(name or 'dev')
 if not value then return nil end
 assert(value:IsA('StringValue'),'Manifesto invalido: '..tostring(name))
 local ok,decoded=pcall(function()return Http:JSONDecode(value.Value)end)
 assert(ok and type(decoded)=='table','Manifesto corrompido: '..tostring(name))
 return decoded
end
function M.list()
 local root=folder(false)
 local out={}
 if not root then return out end
 for _,item in ipairs(root:GetChildren())do
  if item:IsA('StringValue')then out[#out+1]={name=item.Name,aggregate=item:GetAttribute('CssAggregate'),created=item:GetAttribute('CssCreated'),count=item:GetAttribute('CssModules')}end
 end
 table.sort(out,function(a,b)return a.name<b.name end)
 return out
end
function M.remove(name)
 local root=folder(false)
 local value=root and root:FindFirstChild(name or '')
 if not value then return false end
 value:Destroy()
 return true
end
function M.report(value,limit)
 assert(type(value)=='table','report exige manifesto ou comparacao.')
 limit=math.max(1,math.floor(limit or 10))
 if value.modules then
  local lines={string.format('Manifesto %s | %s | %d modulos | %d bytes | hash %s',tostring(value.label),tostring(value.created),value.count or 0,value.bytes or 0,tostring(value.aggregate))}
  local order={}
  for name,entry in pairs(value.modules)do order[#order+1]={name=name,bytes=entry.bytes or 0,hash=entry.hash}end
  table.sort(order,function(a,b)if a.bytes==b.bytes then return a.name<b.name end return a.bytes>b.bytes end)
  for index=1,math.min(limit,#order)do
   local entry=order[index]
   lines[#lines+1]=string.format('  %-34s %7d  %s',entry.name,entry.bytes,tostring(entry.hash))
  end
  if #order>limit then lines[#lines+1]=string.format('  ... mais %d modulos',#order-limit)end
  return table.concat(lines,'\n')
 end
 local lines={string.format('Comparacao %s -> %s | %s',tostring(value.from),tostring(value.to),value.ok and 'identico' or 'divergente')}
 lines[#lines+1]=string.format('  iguais %d | alterados %d | novos %d | removidos %d',value.same or 0,#(value.changed or {}),#(value.added or {}),#(value.removed or {}))
 for _,entry in ipairs(value.changed or {})do lines[#lines+1]=string.format('  ~ %-32s %s -> %s (%+d bytes)',entry.name,tostring(entry.from),tostring(entry.to),entry.bytes or 0)end
 for _,name in ipairs(value.added or {})do lines[#lines+1]='  + '..name end
 for _,name in ipairs(value.removed or {})do lines[#lines+1]='  - '..name end
 return table.concat(lines,'\n')
end
return M
