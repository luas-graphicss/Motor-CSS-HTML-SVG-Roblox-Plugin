local Engine=require(script.Parent.FontEngine)
local Units=require(script.Parent.FontUnitMetrics)
local Binary=require(script.Parent.FontBinary)
local T={VERSION=1}
T.limits={families=24,measure=2048,positions=2048,patterns=60000,pattern=48,word=96,languages=16,text=8192,hyphens=512}
local registry={}
local byFamily={}
local families=0
local measureCache,measureKeys,measureCursor={},{},0
local hits,misses=0,0
local hyphenation={}
local languages=0
local hyphenCache,hyphenKeys,hyphenCursor={},{},0
local function trim(s)return(s:gsub('^%s+',''):gsub('%s+$',''))end
local function unquote(s)
 s=trim(s)
 local q=s:sub(1,1)
 if(q=='"'or q=="'")and s:sub(-1)==q then return s:sub(2,-2)end
 return s
end
local function familyKey(text)
 local lower=tostring(text or''):lower()
 local name=lower:match('([%w%-_]+)%.json')or lower
 return(name:gsub('[^%a%d]',''))
end
local function weightOf(value)
 if value=='bold'then return 700 end
 if value=='normal'or value==nil then return 400 end
 local n=tonumber(value)
 assert(n and n>=1 and n<=1000,'font-weight: use normal, bold ou 1..1000.')
 return n
end
local function slantOf(value)
 if value==nil or value==false or value=='normal'then return 'normal'end
 if value==true or value=='italic'or value=='oblique'then return 'italic'end
 error('font-style aceita normal, italic ou oblique.')
end
local function entryKey(family,weight,slant)return familyKey(family)..':'..weight..':'..slant end
local function bucketFor(key)
 local list=byFamily[key]
 if not list then list={};byFamily[key]=list end
 return list
end
local function forget(entry)
 local key=familyKey(entry.family)
 local list=byFamily[key]
 if list then
  for index=#list,1,-1 do if list[index]==entry then table.remove(list,index)end end
  if #list==0 then byFamily[key]=nil end
 end
 if entry.engine then pcall(Engine.unregister,entry.engine)end
end
local function chars(text)
 local out={}
 local ok=pcall(function()
  for _,codepoint in utf8.codes(text)do out[#out+1]=utf8.char(codepoint)end
 end)
 if not ok then return nil end
 return out
end
local function lowerChar(c)
 if #c==1 then return c:lower()end
 return c
end
function T.clearCache()
 table.clear(measureCache);table.clear(measureKeys);measureCursor=0;hits=0;misses=0
 table.clear(hyphenCache);table.clear(hyphenKeys);hyphenCursor=0
 pcall(Units.clear)
 return true
end
function T.register(family,data,options)
 options=options or{}
 assert(type(family)=='string'and #family>0 and #family<=128,'register exige uma familia CSS.')
 assert(not family:find('[,{}]'),'Nome de familia invalido.')
 local weight=weightOf(options.weight)
 local slant=slantOf(options.style)
 local key=entryKey(family,weight,slant)
 local previous=registry[key]
 if not previous then assert(families<T.limits.families,'Maximo de '..T.limits.families..' familias no motor tipografico.')end
 local entry={family=family,key=key,weight=weight,slant=slant,axes=options.axes,instance=options.instance,index=options.index or 1,equivalent=options.equivalent==true}
 local face
 if type(data)=='table'then
  assert(type(data.unitsPerEm)=='number'and data.unitsPerEm>0 and type(data.metrics)=='table','register exige bytes de fonte ou face carregada.')
  face=data
  entry.face=face
  entry.source='face'
 else
  local bytes=data
  if type(bytes)=='string'and bytes:sub(1,5)=='data:'then bytes=Binary.dataUrl(bytes)end
  assert(type(bytes)=='string'and #bytes>=12,'register exige bytes TTF/OTF/WOFF/WOFF2.')
  entry.engine='css-typography:'..key
  Engine.register(entry.engine,bytes,{index=entry.index,axes=entry.axes,instance=entry.instance,format=options.format})
  local loaded,failure=Engine.face(entry.engine)
  if not loaded then
   pcall(Engine.unregister,entry.engine)
   error('Fonte rejeitada pelo motor tipografico: '..tostring(failure))
  end
  face=loaded
  entry.source='binary'
  entry.bytes=#bytes
 end
 if previous then forget(previous);families-=1 end
 registry[key]=entry
 table.insert(bucketFor(familyKey(family)),entry)
 families+=1
 entry.unitsPerEm=face.unitsPerEm
 entry.name=face.family
 entry.flavor=face.flavor
 entry.variable=Engine.variable(face)~=nil
 entry.shaper=Engine.shaper(face)
 local ok,measured=pcall(Units.registerFont,family,face)
 entry.units=ok and measured or nil
 T.clearCache()
 return entry
end
function T.unregister(family,weight,style)
 local key=entryKey(family,weightOf(weight),slantOf(style))
 local entry=registry[key]
 if not entry then return false end
 registry[key]=nil
 forget(entry)
 families-=1
 T.clearCache()
 return true
end
function T.clear()
 for key,entry in pairs(registry)do forget(entry);registry[key]=nil end
 table.clear(byFamily)
 families=0
 T.clearCache()
 return true
end
function T.registered(family)
 local out={}
 for _,entry in ipairs(byFamily[familyKey(family)]or{})do
  out[#out+1]={family=entry.family,weight=entry.weight,style=entry.slant,source=entry.source,unitsPerEm=entry.unitsPerEm,name=entry.name,flavor=entry.flavor,variable=entry.variable,shaper=entry.shaper,equivalent=entry.equivalent}
 end
 table.sort(out,function(a,b)if a.weight==b.weight then return a.style<b.style end return a.weight<b.weight end)
 return out
end
function T.list()
 local seen,out={},{}
 for _,entry in pairs(registry)do
  if not seen[entry.family]then seen[entry.family]=true;out[#out+1]=entry.family end
 end
 table.sort(out)
 return out
end
local function desired(style)
 local okWeight,weight=pcall(weightOf,style._fontEffectiveWeight or style['font-weight'])
 local slantValue=style._fontEffectiveSlant
 if slantValue==nil then slantValue=style['font-style']end
 local okSlant,slant=pcall(slantOf,slantValue)
 return okWeight and weight or 400,okSlant and slant or 'normal'
end
function T.entry(style)
 if families==0 or type(style)~='table'then return nil end
 local list=style['font-family']
 if type(list)~='string'or list==''then return nil end
 local weight,slant=desired(style)
 for name in list:gmatch('[^,]+')do
  local items=byFamily[familyKey(unquote(name))]
  if items and #items>0 then
   local best,score
   for _,item in ipairs(items)do
    local cost=math.abs(item.weight-weight)+(item.slant==slant and 0 or 2000)
    if not score or cost<score then best=item;score=cost end
   end
   if best then return best end
  end
 end
 return nil
end
function T.face(style)
 local entry=T.entry(style)
 if not entry then return nil end
 if entry.face then return entry.face,entry end
 local ok,face=pcall(Engine.face,entry.engine,{axes=style._fontAxes,instance=entry.instance})
 if ok and type(face)=='table'then return face,entry end
 local retried,plain=pcall(Engine.face,entry.engine)
 if retried and type(plain)=='table'then return plain,entry end
 return nil
end
local ranges={{0x0370,0x03ff,'grek'},{0x0400,0x04ff,'cyrl'},{0x0530,0x058f,'armn'},{0x0590,0x05ff,'hebr',true},{0x0600,0x06ff,'arab',true},{0x0700,0x074f,'syrc',true},{0x0750,0x077f,'arab',true},{0x0900,0x097f,'deva'},{0x0980,0x09ff,'beng'},{0x0e00,0x0e7f,'thai'},{0x10a0,0x10ff,'geor'},{0x1100,0x11ff,'hang'},{0x3040,0x309f,'kana'},{0x30a0,0x30ff,'kana'},{0x3400,0x4dbf,'hani'},{0x4e00,0x9fff,'hani'},{0xac00,0xd7af,'hang'},{0xfb1d,0xfb4f,'hebr',true},{0xfb50,0xfdff,'arab',true},{0xfe70,0xfeff,'arab',true}}
function T.script(text)
 local script,rtl='latn',false
 if type(text)~='string'or text==''then return script,rtl end
 local ok=pcall(function()
  for _,codepoint in utf8.codes(text)do
   for _,range in ipairs(ranges)do
    if codepoint>=range[1]and codepoint<=range[2]then script=range[3];rtl=range[4]==true;return end
   end
  end
 end)
 if not ok then return 'latn',false end
 return script,rtl
end
local function languageTag(style)
 local value=style['font-language-override']
 if type(value)~='string'or value=='normal'or value==''then return nil end
 local tag=unquote(value)
 if #tag==0 or #tag>4 then return nil end
 return tag..string.rep(' ',4-#tag)
end
function T.options(style,text)
 local script,rtl=T.script(text)
 if style.direction=='rtl'then rtl=true end
 return {features=style._fontFeatures,script=script,language=languageTag(style),rtl=rtl}
end
function T.editable(tag)return tag=='input'or tag=='textarea'end
function T.path(style,text,tag)
 if tag~=nil and T.editable(tag)then return 'native','campo editavel mantem TextService para cursor, selecao e IME.'end
 local face,entry=T.face(style)
 if not face then return 'native','nenhum arquivo de fonte registrado para a familia.'end
 if type(text)=='string'then
  if text==''then return 'native','texto vazio.'end
  if #text>T.limits.text then return 'native','texto acima do limite do motor.'end
  if text:find('%c')then return 'native','texto com controles ou quebras fica no medidor nativo.'end
  if entry.equivalent and not entry.shaper and not text:find('[\128-\255]')then return 'native','fonte equivalente a nativa, sem GSUB/GPOS e texto ASCII.'end
 end
 return 'engine','shaping proprio com metricas reais da fonte.'
end
function T.metrics(style,size)
 local face=T.face(style)
 if not face then return nil end
 local value=tonumber(size)or tonumber(style._fontPx)or tonumber(style['font-size'])or 16
 if value<=0 or value>4096 then return nil end
 local ok,px=pcall(Engine.metrics,face,value)
 if not ok or type(px)~='table'then return nil end
 return px,face
end
function T.measure(style,text,size)
 if type(text)~='string'or text==''then return nil end
 if #text>T.limits.text or text:find('%c')then return nil end
 local face,entry=T.face(style)
 if not face then return nil end
 local value=tonumber(size)or tonumber(style._fontPx)or tonumber(style['font-size'])or 16
 if value<=0 or value>4096 then return nil end
 local options=T.options(style,text)
 local key=table.concat({face.id or entry.key,string.format('%.4f',value),style._openTypeFeatures or'',options.script,options.language or'',options.rtl and 'r'or'l',text},'|')
 local cached=measureCache[key]
 if cached then hits+=1;return cached end
 misses+=1
 local ok,width,lineHeight,glyphs,px,shaped=pcall(Engine.measure,face,text,value,options)
 if not ok or type(width)~='number'or width~=width or type(px)~='table'then return nil end
 local applied=shaped and table.concat(shaped.applied,',')or''
 local result=table.freeze({
  width=width,height=lineHeight,lineHeight=lineHeight,
  ascent=px.ascent,descent=px.descent,lineGap=px.lineGap,
  xHeight=px.xHeight,capHeight=px.capHeight,ch=px.ch,ic=px.ic,space=px.space,
  exRatio=px.exRatio,capRatio=px.capRatio,
  xHeightSource=px.xHeightSource,capHeightSource=px.capHeightSource,
  underlinePosition=px.underlinePosition,underlineThickness=px.underlineThickness,
  strikeoutPosition=px.strikeoutPosition,strikeoutSize=px.strikeoutSize,
  scale=px.scale,size=value,count=type(glyphs)=='table'and #glyphs or 0,
  shaped=shaped~=nil,applied=applied,
  kerned=shaped~=nil and(shaped.legacyKern==true or applied:find('kern',1,true)~=nil),
  family=face.family,source='engine',
 })
 measureCursor=measureCursor%T.limits.measure+1
 local old=measureKeys[measureCursor]
 if old then measureCache[old]=nil end
 measureKeys[measureCursor]=key
 measureCache[key]=result
 return result
end
function T.bounds(style,text,size,tag)
 local kind=T.path(style,text,tag)
 if kind~='engine'then return nil end
 local measured=T.measure(style,text,size)
 if not measured then return nil end
 return Vector2.new(measured.width,measured.height),measured
end
function T.positions(style,text,size)
 local measured=T.measure(style,text,size)
 if not measured then return nil end
 local face=T.face(style)
 if not face then return nil end
 local ok,positions,width,shaped=pcall(Engine.positions,face,text,measured.size,T.options(style,text))
 if not ok or type(positions)~='table'then return nil end
 if #positions>T.limits.positions then return nil end
 return positions,width,shaped,measured
end
function T.glyphId(style,codepoint)
 local face=T.face(style)
 if not face or type(codepoint)~='number'then return nil end
 local ok,items=pcall(Engine.glyphs,face,utf8.char(codepoint))
 if not ok or type(items)~='table'or #items==0 then return nil end
 return items[1].glyph,face
end
function T.atlasKey(style,glyph,size)
 local face=T.face(style)
 if not face then return nil end
 return table.concat({face.id or'face',tostring(face.family or''),tostring(glyph),string.format('%.3f',tonumber(size)or 0)},'|')
end
function T.outline(style,codepoint,size)
 local face=T.face(style)
 if not face or type(codepoint)~='number'then return nil end
 local ok,outline=pcall(Engine.glyphOutline,face,codepoint,face.outlineOptions)
 if not ok or type(outline)~='table'then return nil end
 if size==nil then return outline,face end
 local scaled,result=pcall(Engine.scaleOutline,outline,size)
 if scaled and type(result)=='table'then return result,face end
 return nil
end
function T.contours(style,codepoint,size,tolerance)
 local outline,face=T.outline(style,codepoint,size)
 if not outline then return nil end
 local ok,flat=pcall(Engine.flatten,outline,tolerance)
 if not ok or type(flat)~='table'then return nil end
 return flat,face
end
local function resolve(style)
 local face=T.face(style)
 if not face then return nil end
 local metrics=face.metrics
 local units=face.unitsPerEm
 if type(metrics)~='table'or type(units)~='number'or units<=0 then return nil end
 local out={source='measured',unitsPerEm=units,family=face.family}
 if type(metrics.xHeight)=='number'and metrics.xHeight>0 then out.ex=metrics.xHeight/units;out.exSource=metrics.xHeightSource or'face'end
 if type(metrics.capHeight)=='number'and metrics.capHeight>0 then out.cap=metrics.capHeight/units;out.capSource=metrics.capHeightSource or'face'end
 if type(metrics.ascent)=='number'then out.ascent=metrics.ascent/units end
 if type(metrics.descent)=='number'then out.descent=metrics.descent/units end
 if type(metrics.lineGap)=='number'then out.lineGap=metrics.lineGap/units end
 if metrics.chKnown and type(metrics.chWidth)=='number'then out.ch=metrics.chWidth/units end
 if metrics.icKnown and type(metrics.icWidth)=='number'then out.ic=metrics.icWidth/units end
 if not(out.ex or out.cap or out.ch or out.ic)then return nil end
 return out
end
T.resolve=resolve
pcall(Units.attach,resolve)
function T.registerHyphenation(language,patterns,exceptions)
 assert(type(language)=='string'and #language>0 and #language<=16,'registerHyphenation exige um idioma.')
 local list=patterns
 if type(list)=='string'then
  local parsed={}
  for token in list:gmatch('%S+')do parsed[#parsed+1]=token end
  list=parsed
 end
 assert(type(list)=='table'and #list>0,'registerHyphenation exige padroes do dicionario.')
 assert(#list<=T.limits.patterns,'Dicionario acima do limite de padroes.')
 local map={}
 local longest=0
 for _,pattern in ipairs(list)do
  assert(type(pattern)=='string'and #pattern>0 and #pattern<=T.limits.pattern,'Padrao de hifenizacao invalido.')
  local sequence=chars(pattern)
  assert(sequence,'Padrao de hifenizacao com UTF-8 invalido.')
  local letters={}
  local values={}
  local slot=0
  for _,char in ipairs(sequence)do
   if #char==1 and char:match('%d')then
    values[slot]=tonumber(char)
   else
    slot+=1
    letters[slot]=lowerChar(char)
   end
  end
  assert(slot>0,'Padrao de hifenizacao sem letras.')
  local text=table.concat(letters)
  local stored=map[text]
  if not stored then stored={};map[text]=stored end
  for at,value in pairs(values)do
   if(stored[at]or 0)<value then stored[at]=value end
  end
  if slot>longest then longest=slot end
 end
 local exceptionMap={}
 local exceptionCount=0
 for word,spelled in pairs(exceptions or{})do
  assert(type(word)=='string'and type(spelled)=='string','Excecoes exigem palavra -> pa-la-vra.')
  local wordChars=chars(word)
  local spelledChars=chars(spelled)
  assert(wordChars and spelledChars,'Excecao com UTF-8 invalido.')
  local lowered={}
  for _,char in ipairs(wordChars)do lowered[#lowered+1]=lowerChar(char)end
  local points={}
  local seen=0
  for _,char in ipairs(spelledChars)do
   if char=='-'then points[seen]=true else seen+=1 end
  end
  assert(seen==#lowered,'Excecao precisa ter as mesmas letras da palavra.')
  exceptionMap[table.concat(lowered)]=points
  exceptionCount+=1
  assert(exceptionCount<=4096,'Excecoes de hifenizacao acima do limite.')
 end
 local key=language:lower()
 if not hyphenation[key]then
  assert(languages<T.limits.languages,'Maximo de idiomas de hifenizacao atingido.')
  languages+=1
 end
 hyphenation[key]={map=map,longest=longest,exceptions=exceptionMap,patterns=#list,source='dictionary'}
 table.clear(hyphenCache);table.clear(hyphenKeys);hyphenCursor=0
 return {language=key,patterns=#list,longest=longest,exceptions=exceptionCount}
end
local function dictionary(language)
 if type(language)~='string'then return nil end
 local key=language:lower()
 if hyphenation[key]then return hyphenation[key],key end
 local base=key:match('^(%a+)')
 if base and hyphenation[base]then return hyphenation[base],base end
 return nil
end
function T.hyphenationSource(language)
 local entry=dictionary(language)
 return entry and entry.source or nil
end
function T.hyphenationLanguages()
 local out={}
 for key,entry in pairs(hyphenation)do out[#out+1]={language=key,patterns=entry.patterns,longest=entry.longest}end
 table.sort(out,function(a,b)return a.language<b.language end)
 return out
end
function T.dropHyphenation(language)
 local entry,key=dictionary(language)
 if not entry or not key then return false end
 hyphenation[key]=nil
 languages-=1
 table.clear(hyphenCache);table.clear(hyphenKeys);hyphenCursor=0
 return true
end
function T.breaks(word,language,left,right)
 local entry=dictionary(language)
 if not entry then return nil end
 if type(word)~='string'or word==''or #word>T.limits.word then return nil end
 local limitLeft=math.max(1,math.floor(tonumber(left)or 2))
 local limitRight=math.max(1,math.floor(tonumber(right)or 3))
 local key=table.concat({language:lower(),tostring(limitLeft),tostring(limitRight),word},'|')
 local cached=hyphenCache[key]
 if cached then return cached end
 local sequence=chars(word)
 if not sequence then return nil end
 local total=#sequence
 local out={}
 if total>=limitLeft+limitRight then
  local lowered={}
  for index,char in ipairs(sequence)do lowered[index]=lowerChar(char)end
  local exception=entry.exceptions[table.concat(lowered)]
  if exception then
   for position in pairs(exception)do
    if position>=limitLeft and total-position>=limitRight then out[#out+1]=position end
   end
   table.sort(out)
  else
   local padded={'.'}
   for _,char in ipairs(lowered)do padded[#padded+1]=char end
   padded[#padded+1]='.'
   local values={}
   for start=1,#padded do
    local piece={}
    local span=math.min(entry.longest,#padded-start+1)
    for length=1,span do
     piece[length]=padded[start+length-1]
     local stored=entry.map[table.concat(piece)]
     if stored then
      for slot,value in pairs(stored)do
       local at=start+slot-1
       if(values[at]or 0)<value then values[at]=value end
      end
     end
    end
   end
   for position=limitLeft,total-limitRight do
    local value=values[position+1]
    if value and value%2==1 then out[#out+1]=position end
   end
  end
 end
 local frozen=table.freeze(out)
 hyphenCursor=hyphenCursor%T.limits.hyphens+1
 local old=hyphenKeys[hyphenCursor]
 if old then hyphenCache[old]=nil end
 hyphenKeys[hyphenCursor]=key
 hyphenCache[key]=frozen
 return frozen
end
function T.hyphenate(word,language,left,right)
 local positions=T.breaks(word,language,left,right)
 if not positions or #positions==0 then return nil end
 local sequence=chars(word)
 if not sequence then return nil end
 local set={}
 for _,position in ipairs(positions)do set[position]=true end
 local soft=utf8.char(0xad)
 local out={}
 for index,char in ipairs(sequence)do
  out[#out+1]=char
  if set[index]then out[#out+1]=soft end
 end
 return table.concat(out),positions
end
function T.stats()
 local dictionaries={}
 for key,entry in pairs(hyphenation)do dictionaries[#dictionaries+1]=key..':'..entry.patterns end
 table.sort(dictionaries)
 return {families=families,hits=hits,misses=misses,cached=#measureKeys,attached=Units.attached and Units.attached()or false,engine=Engine.stats(),hyphenation=table.concat(dictionaries,',')}
end
return T
