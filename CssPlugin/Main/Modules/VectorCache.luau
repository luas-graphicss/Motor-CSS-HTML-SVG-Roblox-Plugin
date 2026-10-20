local C={VERSION='vector-cache-1'}
local store=_G.__CssVectorStageCacheV1
if type(store)~='table' or store.version~=1 then
 store={version=1,stages={},clock=0}
 _G.__CssVectorStageCacheV1=store
end
C.store=store
local bxor=bit32.bxor
function C.hash(text)
 assert(type(text)=='string','Hash exige texto.')
 local h1=2166136261
 local h2=5381
 for i=1,#text do
  local b=text:byte(i)
  h1=bxor(h1,b)
  h1=(h1*16777619)%4294967296
  h2=(h2*33+b)%4294967296
 end
 return string.format('%08x%08x%x',h1,h2,#text)
end
function C.key(parts)
 if type(parts)=='string' then return C.hash(parts) end
 assert(type(parts)=='table','Chave de cache exige texto ou lista.')
 local out={}
 local count=tonumber(parts.n) or 0
 for index in pairs(parts) do if type(index)=='number' and index>count then count=index end end
 for i=1,count do
  local value=parts[i]
  local text
  if type(value)=='number' then text=string.format('%.10g',value)
  elseif type(value)=='boolean' then text=value and 'T' or 'F'
  elseif value==nil then text='N'
  else text=tostring(value) end
  out[i]=#text..':'..text
 end
 return C.hash(table.concat(out,'|'))
end
local function resolve(stage)
 if type(stage)=='table' then return stage end
 local found=store.stages[stage]
 assert(found,'Estagio de cache desconhecido: '..tostring(stage))
 return found
end
local function dispose(stage,entry)
 if stage.dispose then
  local ok,err=pcall(stage.dispose,entry.value)
  if not ok then warn('VectorCache dispose: '..tostring(err)) end
 end
end
local function drop(stage,key)
 local entry=stage.entries[key]
 if not entry then return false end
 stage.entries[key]=nil
 stage.count-=1
 stage.bytes-=entry.bytes
 dispose(stage,entry)
 return true
end
local function prune(stage)
 local guard=0
 while (stage.count>stage.maxEntries or stage.bytes>stage.maxBytes) and guard<4096 do
  guard+=1
  local oldest,stamp=nil,math.huge
  for key,entry in pairs(stage.entries) do
   if entry.used<stamp then oldest,stamp=key,entry.used end
  end
  if not oldest then break end
  drop(stage,oldest)
  stage.evictions+=1
 end
end
function C.reset(stage)
 local s=resolve(stage)
 local keys={}
 for key in pairs(s.entries) do keys[#keys+1]=key end
 for _,key in ipairs(keys) do drop(s,key) end
 s.count=0
 s.bytes=0
 return s
end
function C.stage(name,algorithm,options)
 assert(type(name)=='string' and #name>0,'Estagio de cache exige nome.')
 assert(type(algorithm)=='string' and #algorithm>0,'Estagio de cache exige versao de algoritmo.')
 options=options or {}
 local stage=store.stages[name]
 if not stage then
  stage={name=name,algorithm=algorithm,entries={},count=0,bytes=0,hits=0,misses=0,evictions=0,invalidations=0,generation=1,maxEntries=128,maxBytes=8388608}
  store.stages[name]=stage
 elseif stage.algorithm~=algorithm then
  C.reset(stage)
  stage.algorithm=algorithm
  stage.generation+=1
  stage.invalidations+=1
 end
 if options.maxEntries then stage.maxEntries=math.max(1,math.floor(options.maxEntries)) end
 if options.maxBytes then stage.maxBytes=math.max(4096,math.floor(options.maxBytes)) end
 if options.dispose~=nil then stage.dispose=options.dispose end
 prune(stage)
 return stage
end
function C.namespace(stage)
 local s=resolve(stage)
 return s.name..'@'..s.algorithm..'#'..s.generation
end
function C.signature(stage,parts)
 local s=resolve(stage)
 return C.namespace(s)..'/'..C.key(parts)
end
function C.get(stage,key)
 local s=resolve(stage)
 local entry=s.entries[key]
 if not entry then
  s.misses+=1
  return nil
 end
 if entry.algorithm~=s.algorithm or entry.generation~=s.generation then
  drop(s,key)
  s.misses+=1
  s.invalidations+=1
  return nil
 end
 store.clock+=1
 entry.used=store.clock
 s.hits+=1
 return entry.value,entry
end
function C.put(stage,key,value,bytes)
 local s=resolve(stage)
 assert(type(key)=='string','Chave de cache invalida.')
 if value==nil then return nil end
 drop(s,key)
 store.clock+=1
 local entry={value=value,bytes=math.max(1,math.floor(tonumber(bytes) or 128)),used=store.clock,algorithm=s.algorithm,generation=s.generation}
 s.entries[key]=entry
 s.count+=1
 s.bytes+=entry.bytes
 prune(s)
 return value
end
function C.fetch(stage,key,producer,bytes)
 local s=resolve(stage)
 local cached=C.get(s,key)
 if cached~=nil then return cached,true end
 local value=producer()
 if value==nil then return nil,false end
 C.put(s,key,value,bytes)
 return value,false
end
function C.forget(stage,key)
 local s=resolve(stage)
 return drop(s,key)
end
function C.invalidate(stage)
 local s=resolve(stage)
 C.reset(s)
 s.generation+=1
 s.invalidations+=1
 return s.generation
end
function C.clear()
 local names={}
 for name in pairs(store.stages) do names[#names+1]=name end
 for _,name in ipairs(names) do C.reset(store.stages[name]) end
 store.clock=0
 return #names
end
function C.stats(name)
 if name then
  local s=resolve(name)
  return {name=s.name,algorithm=s.algorithm,generation=s.generation,entries=s.count,bytes=s.bytes,hits=s.hits,misses=s.misses,evictions=s.evictions,invalidations=s.invalidations,maxEntries=s.maxEntries,maxBytes=s.maxBytes}
 end
 local out={stages={},entries=0,bytes=0,hits=0,misses=0}
 for stageName,s in pairs(store.stages) do
  local info=C.stats(stageName)
  out.stages[stageName]=info
  out.entries+=info.entries
  out.bytes+=info.bytes
  out.hits+=info.hits
  out.misses+=info.misses
 end
 return out
end
return C
