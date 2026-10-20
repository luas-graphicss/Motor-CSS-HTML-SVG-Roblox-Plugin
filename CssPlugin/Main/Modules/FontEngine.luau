local Binary=require(script.Parent.FontBinary)
local Tables=require(script.Parent.FontTables)
local Outlines=require(script.Parent.FontOutlines)
local Shaping=require(script.Parent.FontShaping)
local Variations=require(script.Parent.FontVariations)
local E={VERSION=1}
E.limits={faces=24,registry=32,textLength=8192}
local registry={}
local faces={}
local order={}
local stats={parsed=0,hits=0,misses=0,registered=0}
local function key(name)
 assert(type(name)=='string' and #name>0 and #name<=256,'Nome de fonte inválido.')
 return name:lower()
end
function E.register(name,data,options)
 local id=key(name)
 local bytes=data
 if type(bytes)=='string' and bytes:sub(1,5)=='data:' then bytes=Binary.dataUrl(bytes) end
 assert(type(bytes)=='string' and #bytes>=12,'Registro de fonte exige bytes TTF/OTF/WOFF.')
 assert(#bytes<=Binary.MAX_BYTES,'Fonte maior que o limite do motor.')
 local count=0
 for _ in pairs(registry) do count+=1 end
 assert(registry[id] or count<E.limits.registry,'Máximo de '..E.limits.registry..' fontes registradas.')
 local entry={id=id,name=name,data=bytes,size=#bytes,fingerprint=Binary.fingerprint(bytes),format=options and options.format or nil,index=options and options.index or 1,axes=options and options.axes or nil,instance=options and options.instance or nil}
 registry[id]=entry
 stats.registered+=1
 return entry
end
function E.unregister(name)
 local id=key(name)
 local entry=registry[id]
 registry[id]=nil
 if entry then
  local prefix=entry.fingerprint..':'
  for cached in pairs(faces) do
   if string.sub(cached,1,#prefix)==prefix then faces[cached]=nil end
  end
 end
 return entry~=nil
end
function E.registered(name) return registry[key(name)] end
function E.names()
 local out={}
 for _,entry in pairs(registry) do out[#out+1]=entry.name end
 table.sort(out)
 return out
end
function E.clear()
 table.clear(registry);table.clear(faces);table.clear(order)
 stats.parsed=0;stats.hits=0;stats.misses=0;stats.registered=0
end
local function remember(id,face)
 faces[id]=face
 order[#order+1]=id
 while #order>E.limits.faces do
  local oldest=table.remove(order,1)
  if oldest~=id then faces[oldest]=nil end
 end
 return face
end
local function variationId(options)
 if type(options.axes)~='table' and options.instance==nil then return '' end
 local parts={}
 if type(options.axes)=='table' then
  local tags={}
  for tag in pairs(options.axes) do tags[#tags+1]=tostring(tag) end
  table.sort(tags)
  for _,tag in ipairs(tags) do parts[#parts+1]=tag..'='..string.format('%.4f',tonumber(options.axes[tag]) or 0) end
 end
 if options.instance~=nil then parts[#parts+1]='@'..string.lower(tostring(options.instance)) end
 return ':'..table.concat(parts,',')
end
function E.load(data,options)
 options=options or {}
 local bytes=data
 if type(bytes)=='string' and bytes:sub(1,5)=='data:' then bytes=Binary.dataUrl(bytes) end
 assert(type(bytes)=='string','Carregar fonte exige bytes.')
 local index=options.index or 1
 local id=Binary.fingerprint(bytes)..':'..index..variationId(options)
 local cached=faces[id]
 if cached then stats.hits+=1;return cached end
 stats.misses+=1
 local font=Binary.open(bytes,{index=index})
 local face=Tables.face(font)
 local state=Variations.attach(face,options.axes,options.instance)
 if state then
  local static=face.advance
  face.staticAdvance=static
  face.advance=function(glyphId) return static(glyphId)+Variations.advanceDelta(face,glyphId) end
  if state.gvar then
   face.outlineOptions={cacheable=true,deltas=function(glyphId,xs,ys,total,endPoints) return Variations.apply(face,glyphId,xs,ys,total,endPoints) end,componentDeltas=function(glyphId) return Variations.components(face,glyphId,Variations.pointCount(face,glyphId)) end}
  end
 end
 if face.flavor=='cff' or (state and state.gvar) then
  face.inkBox=function(glyphId) return Outlines.box(face,glyphId) end
  Tables.refresh(face)
 end
 if state then Variations.applyMetrics(face) end
 face.id=id
 stats.parsed+=1
 return remember(id,face)
end
function E.face(name,options)
 local entry=registry[key(name)]
 if not entry then return nil end
 local request={index=entry.index,axes=entry.axes,instance=entry.instance}
 if type(options)=='table' then
  if options.axes~=nil then request.axes=options.axes end
  if options.instance~=nil then request.instance=options.instance end
 end
 local ok,face=pcall(E.load,entry.data,request)
 if not ok then entry.error=tostring(face);return nil,entry.error end
 entry.error=nil
 return face
end
function E.metrics(face,size) return Tables.px(face,size) end
function E.outline(face,glyphId,options) return Outlines.outline(face,glyphId,options) end
function E.glyphOutline(face,codepoint,options) return Outlines.outline(face,Tables.glyph(face,codepoint),options) end
function E.flatten(outline,tolerance) return Outlines.flatten(outline,tolerance) end
function E.scaleOutline(outline,size) return Outlines.scale(outline,size) end
function E.codepoints(text)
 assert(type(text)=='string','Texto exige string.')
 assert(#text<=E.limits.textLength,'Texto maior que o limite do motor tipográfico.')
 local out={}
 local index=1
 for position,codepoint in utf8.codes(text) do
  out[index]={codepoint=codepoint,cluster=position}
  index+=1
 end
 return out
end
function E.glyphs(face,text)
 local items=E.codepoints(text)
 for _,item in ipairs(items) do
  item.glyph=Tables.glyph(face,item.codepoint)
  item.advance=face.advance(item.glyph)
 end
 return items
end
function E.shaper(face)
 local tables=face.font.tables
 return tables.GSUB~=nil or tables.GPOS~=nil or tables.kern~=nil
end
function E.shape(face,text,options)
 assert(type(text)=='string','Shaping exige texto.')
 assert(#text<=E.limits.textLength,'Texto maior que o limite do motor tipográfico.')
 return Shaping.shape(face,text,options)
end
function E.positions(face,text,size,options)
 local shaped=E.shape(face,text,options)
 local positions,width=Shaping.positions(shaped,size)
 return positions,width,shaped
end
function E.measure(face,text,size,options)
 options=options or {}
 local metrics=Tables.px(face,size)
 if options.shape~=false and E.shaper(face) then
  local shaped=E.shape(face,text,options)
  return shaped.width*metrics.scale,metrics.lineHeight,shaped.glyphs,metrics,shaped
 end
 local items=E.glyphs(face,text)
 local units=0
 for _,item in ipairs(items) do units+=item.advance end
 return units*metrics.scale,metrics.lineHeight,items,metrics
end
function E.variable(face) return Variations.support(face) end
function E.axes(face) return Variations.summary(face) end
function E.instances(face) return Variations.instances(face) end
function E.instance(face,name) return Variations.named(face,name) end
function E.vary(name,axes,instance)
 local entry=registry[key(name)]
 assert(entry,'Fonte não registrada: '..tostring(name)..'.')
 return E.load(entry.data,{index=entry.index,axes=axes,instance=instance})
end
function E.stats()
 local count=0
 for _ in pairs(registry) do count+=1 end
 return {parsed=stats.parsed,hits=stats.hits,misses=stats.misses,registered=count,cached=#order}
end
return E
