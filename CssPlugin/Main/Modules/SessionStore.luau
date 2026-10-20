local S={BLOCK_BYTES=8192,MAX_BYTES=120000}
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local lookup={};for i=1,#alphabet do lookup[alphabet:sub(i,i)]=i-1 end
local function hash(text)
 local h=5381;for i=1,#text do h=(h*33+text:byte(i))%4294967296 end;return h
end
local function base64(text)
 local out={}
 for i=1,#text,3 do
  local a,b,c=text:byte(i,i+2);local n=a*65536+(b or 0)*256+(c or 0)
  out[#out+1]=alphabet:sub(math.floor(n/262144)+1,math.floor(n/262144)+1)
  local k=math.floor(n/4096)%64+1;out[#out+1]=alphabet:sub(k,k)
  k=math.floor(n/64)%64+1;out[#out+1]=b and alphabet:sub(k,k)or '='
  k=n%64+1;out[#out+1]=c and alphabet:sub(k,k)or '='
 end
 return table.concat(out)
end
local function unbase64(text)
 assert(#text%4==0 and #text<=S.BLOCK_BYTES*4,'Bloco base64 inválido.')
 local out={}
 for i=1,#text,4 do
  local a,b,c,d=text:sub(i,i),text:sub(i+1,i+1),text:sub(i+2,i+2),text:sub(i+3,i+3)
  assert(lookup[a] and lookup[b] and (lookup[c] or c=='=') and (lookup[d] or d=='='),'Base64 corrompido.')
  assert(c~='=' or d=='=','Padding inválido.');assert((c~='=' and d~='=')or i+3==#text,'Padding intermediário.')
  local n=lookup[a]*262144+lookup[b]*4096+(lookup[c]or 0)*64+(lookup[d]or 0)
  out[#out+1]=string.char(math.floor(n/65536))
  if c~='='then out[#out+1]=string.char(math.floor(n/256)%256)end
  if d~='='then out[#out+1]=string.char(n%256)end
 end
 return table.concat(out)
end
function S.encode(text)
 assert(type(text)=='string'and #text<=S.BLOCK_BYTES,'Bloco grande demais.')
 local dictionary={};for i=0,255 do dictionary[string.char(i)]=i end
 local nextCode=256;local word='';local out={}
 local function emit(code)out[#out+1]=string.char(math.floor(code/256),code%256)end
 for i=1,#text do
  local char=text:sub(i,i);local combined=word..char
  if dictionary[combined]then word=combined else
   emit(dictionary[word]);if nextCode<4096 then dictionary[combined]=nextCode;nextCode+=1 end;word=char
  end
 end
 if word~=''then emit(dictionary[word])end
 local compressed=base64(table.concat(out));local codec='lzw16'
 if #compressed>=#text then compressed=text;codec='raw'end
 return {codec=codec,data=compressed,size=#text,hash=hash(text)}
end
function S.decode(record)
 assert(type(record)=='table'and type(record.data)=='string','Bloco ausente.')
 assert(type(record.size)=='number'and record.size>=0 and record.size<=S.BLOCK_BYTES,'Tamanho de bloco inválido.')
 local text
 if record.codec=='raw'then text=record.data else
  assert(record.codec=='lzw16','Codec de rascunho desconhecido.')
  local bytes=unbase64(record.data);assert(#bytes%2==0,'LZW truncado.')
  local dictionary={};for i=0,255 do dictionary[i]=string.char(i)end
  local nextCode=256;local previous;local out={};local size=0
  for i=1,#bytes,2 do
   local code=bytes:byte(i)*256+bytes:byte(i+1)
   local entry=dictionary[code]
   if not entry and code==nextCode and previous then entry=previous..previous:sub(1,1)end
   assert(entry,'Código LZW inválido.');size+=#entry;assert(size<=record.size,'Bloco expandido além do limite.')
   out[#out+1]=entry
   if previous and nextCode<4096 then dictionary[nextCode]=previous..entry:sub(1,1);nextCode+=1 end
   previous=entry
  end
  text=table.concat(out)
 end
 assert(#text==record.size and hash(text)==record.hash,'Checksum do rascunho inválido.')
 return text
end
local function chunks(text)
 local out={};local pos=1
 while pos<=#text do
  local last=math.min(#text,pos+S.BLOCK_BYTES-1)
  while last<#text and text:byte(last+1)>=128 and text:byte(last+1)<192 do last-=1 end
  assert(last>=pos,'UTF-8 inválido.');out[#out+1]=text:sub(pos,last);pos=last+1
 end
 return out
end
function S.new(plugin,key)
 local self={manifest=nil,raw={markup={},css={}},writes=0,bytes=0,loaded=false,generation=0,destroyed=false}
 local headKey=key..'_blocks_v2'
 local function blockKey(field,index,slot)return headKey..'_'..field..'_'..index..'_'..slot end
 local function valid(draft)
  return type(draft)=='table'and type(draft.markup)=='string'and type(draft.css)=='string'and #draft.markup<=S.MAX_BYTES and #draft.css<=S.MAX_BYTES
 end
 function self:load()
  self.loaded=true
  local ok,result=pcall(function()
   local manifest=plugin:GetSetting(headKey)
   if type(manifest)~='table'or manifest.version~=2 then return nil end
   assert(type(manifest.fields)=='table','Manifesto inválido.')
   local draft={name=type(manifest.name)=='string'and manifest.name or 'CssDemo'};local raw={}
   for _,field in ipairs({'markup','css'})do
    local refs=manifest.fields[field];assert(type(refs)=='table'and #refs<=16,'Manifesto excede o limite.')
    raw[field]={};local size=0
    for index,ref in ipairs(refs)do
     assert(type(ref)=='table'and(ref.slot==1 or ref.slot==2),'Referência de bloco inválida.')
     local record=plugin:GetSetting(blockKey(field,index,ref.slot))
     local text=S.decode(record);assert(ref.hash==record.hash and ref.size==#text,'Bloco de outra versão.')
     size+=#text;assert(size<=S.MAX_BYTES,'Rascunho grande demais.');raw[field][index]=text
    end
    draft[field]=table.concat(raw[field])
   end
   self.manifest=manifest;self.raw=raw;return draft
  end)
  if ok and result then return result end
  local legacyOk,legacy=pcall(function()return plugin:GetSetting(key)end)
  if legacyOk and valid(legacy)then return legacy,'Rascunho anterior recuperado; migração no próximo salvamento.'end
  return nil,not ok and tostring(result)or nil
 end
 function self:save(draft,options)
  assert(not self.destroyed,'Armazenamento de rascunhos encerrado.')
  assert(valid(draft),'Rascunho excede 120 KB por campo.')
  if not self.loaded then self:load()end
  options=options or {};self.generation+=1;local generation=self.generation
  local function current()
   return not self.destroyed and self.generation==generation and(not options.cancelled or not options.cancelled())
  end
  local function checkpoint()
   if not current()then return false end
   if options.checkpoint then options.checkpoint()end
   return current()
  end
  if not current()then return {writes=0,bytes=0,cancelled=true}end
  local old=self.manifest;local manifest={version=2,name=tostring(draft.name or 'CssDemo'):sub(1,128),fields={}}
  local raw={};local pending={};local changed=not old or old.name~=manifest.name;local bytes=0
  for _,field in ipairs({'markup','css'})do
   raw[field]=chunks(draft[field]);manifest.fields[field]={}
   local refs=old and old.fields[field]or {}
   if #refs~=#raw[field]then changed=true end
   for index,text in ipairs(raw[field])do
    local ref=refs[index]
    if ref and self.raw[field][index]==text then manifest.fields[field][index]=ref else
     changed=true;local record=S.encode(text);local slot=ref and(3-ref.slot)or 1
     manifest.fields[field][index]={slot=slot,hash=record.hash,size=record.size}
     pending[#pending+1]={key=blockKey(field,index,slot),record=record};bytes+=#record.data
    end
    if not checkpoint()then return {writes=0,bytes=0,cancelled=true}end
   end
  end
  if not current()then return {writes=0,bytes=0,cancelled=true}end
  if not changed then return {writes=0,bytes=0}end
  for _,block in ipairs(pending)do plugin:SetSetting(block.key,block.record)end
  plugin:SetSetting(headKey,manifest)
  self.manifest=manifest;self.raw=raw;self.writes+=#pending+1;self.bytes+=bytes
  return {writes=#pending+1,bytes=bytes}
 end
 function self:clearBuffers()
  table.clear(self.raw.markup);table.clear(self.raw.css)
 end
 function self:destroy()
  self.destroyed=true;self.generation+=1
  self:clearBuffers();self.manifest=nil;plugin=nil
 end
 return self
end
return S
