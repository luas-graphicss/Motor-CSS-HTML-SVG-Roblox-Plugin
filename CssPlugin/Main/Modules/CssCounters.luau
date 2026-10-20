local C={VERSION=1}
local MAX_SYMBOLS=64
local MAX_STYLES=64
local MAX_COUNTERS=32
local EMPTY=table.freeze({})
local systems=table.freeze({cyclic=true,numeric=true,alphabetic=true,symbolic=true,additive=true,fixed=true,extends=true})
local descriptors=table.freeze({system=true,symbols=true,['additive-symbols']=true,prefix=true,suffix=true,range=true,pad=true,negative=true,fallback=true})
C.systems=systems
C.descriptors=descriptors
local function trim(text)return(text:gsub('^%s+',''):gsub('%s+$',''))end
C.trim=trim
function C.readString(text,p)
 local quote=text:sub(p,p);assert(quote=='"'or quote=="'",'String CSS esperada em: '..text:sub(p,p+16))
 local out={};p+=1
 while p<=#text do
  local c=text:sub(p,p)
  if c==quote then return table.concat(out),p+1 end
  if c==string.char(92)then
   p+=1;assert(p<=#text,'Escape CSS incompleto.')
   local hex=text:sub(p):match('^%x%x?%x?%x?%x?%x?')
   if hex then
    local n=tonumber(hex,16);if n==0 or n>0x10ffff or(n>=0xd800 and n<=0xdfff)then n=0xfffd end
    out[#out+1]=utf8.char(n);p+=#hex
    if text:sub(p,p):match('%s')then p+=1 end
   else out[#out+1]=text:sub(p,p);p+=1 end
  else
   assert(c~='\n'and c~='\r','String CSS nao pode conter quebra de linha sem escape.')
   out[#out+1]=c;p+=1
  end
 end
 error('String CSS nao fechada.',0)
end
function C.validName(name)
 return type(name)=='string'and #name<=48 and name:match('^%-?[%a_][%w_%-]*$')~=nil
end
local function split(value,sep)
 local out={};local depth=0;local quote=nil;local start=1;local i=1
 while i<=#value do
  local c=value:sub(i,i)
  if quote then
   if c==string.char(92)then i+=1 elseif c==quote then quote=nil end
  elseif c=='"'or c=="'"then quote=c
  elseif c=='('then depth+=1
  elseif c==')'then depth-=1
  elseif c==sep and depth==0 then out[#out+1]=value:sub(start,i-1);start=i+1 end
  i+=1
 end
 out[#out+1]=value:sub(start)
 return out
end
local function commas(value)return split(value,',')end
C.split=split
C.commas=commas
local function words(value)
 local out={};for word in value:gmatch('%S+')do out[#out+1]=word end;return out
end
local function symbolList(value,allowIdent,label)
 local out={};local p=1
 while p<=#value do
  local c=value:sub(p,p)
  if c:match('%s')or c==','then p+=1
  elseif c=='"'or c=="'"then local text;text,p=C.readString(value,p);out[#out+1]=text
  elseif allowIdent then
   local word=value:match('^[^%s,]+',p)
   assert(word and not word:find('(',1,true),'Simbolo invalido em '..label..': use strings CSS ou identificadores.')
   out[#out+1]=word;p+=#word
  else error('Use strings CSS em '..label..'.',0)end
  assert(#out<=MAX_SYMBOLS,label..' aceita no maximo '..MAX_SYMBOLS..' simbolos.')
 end
 return out
end
local function additivePairs(value)
 local out={}
 for _,part in ipairs(commas(value))do
  part=trim(part)
  if part~=''then
   local weight,rest=part:match('^(%d+)%s*(.*)$')
   assert(weight,'additive-symbols usa "peso simbolo", ex.: 10 "X".')
   local symbol=symbolList(rest,true,'additive-symbols')
   assert(#symbol==1,'Cada par de additive-symbols precisa de exatamente um simbolo.')
   out[#out+1]={weight=tonumber(weight),symbol=symbol[1]}
  end
 end
 assert(#out>0,'additive-symbols vazio.')
 table.sort(out,function(a,b)return a.weight>b.weight end)
 return out
end
local function rangeList(value)
 if trim(value)=='auto'then return nil end
 local out={}
 for _,part in ipairs(commas(value))do
  local low,high=trim(part):match('^(%S+)%s+(%S+)$')
  assert(low and high,'range usa pares "inicio fim", ex.: range:1 10.')
  local entry={}
  if low~='infinite'then entry.min=assert(tonumber(low),'range invalido: '..low)end
  if high~='infinite'then entry.max=assert(tonumber(high),'range invalido: '..high)end
  out[#out+1]=entry
  assert(#out<=16,'range aceita no maximo 16 faixas.')
 end
 return out
end
function C.parse(name,decls)
 assert(C.validName(name),'Nome invalido em @counter-style: '..tostring(name))
 local lowered=name:lower()
 assert(lowered~='none'and lowered~='inherit'and lowered~='initial'and lowered~='unset'and lowered~='auto','Nome reservado em @counter-style: '..name)
 local map={}
 if type(decls)=='string'then
  for _,line in ipairs(split(decls,';'))do
   if trim(line)~=''then
    local key,value=line:match('^%s*([%w_%-]+)%s*:%s*(.-)%s*$')
    assert(key,'Descritor invalido em @counter-style '..name..': '..trim(line))
    map[key:lower()]=trim(value)
   end
  end
 elseif type(decls)=='table'then
  if decls[1]~=nil then
   for _,item in ipairs(decls)do
    local key=item.property or item.name or item.key or item[1]
    local value=item.value or item[2]
    if key then map[tostring(key):lower()]=trim(tostring(value or ''))end
   end
  else
   for key,value in pairs(decls)do map[tostring(key):lower()]=trim(tostring(value or ''))end
  end
 end
 for key in pairs(map)do assert(descriptors[key],'Descritor nao suportado em @counter-style: '..key)end
 local def={name=name}
 local system=map.system or 'symbolic'
 local base,argument=system:match('^(%S+)%s*(.*)$')
 base=base or system;argument=trim(argument or '')
 assert(systems[base],'system nao suportado em @counter-style: '..base)
 def.system=base
 if base=='fixed'then
  def.first=argument~=''and assert(tonumber(argument),'system fixed usa um inteiro opcional.')or 1
  def.first=math.floor(def.first)
 elseif base=='extends'then
  assert(argument~='','system extends exige o nome de outro estilo.')
  assert(C.validName(argument),'Nome invalido em extends: '..argument)
  assert(map.symbols==nil and map['additive-symbols']==nil,'system extends nao aceita symbols nem additive-symbols.')
  def.extends=argument
 else assert(argument=='','system '..base..' nao aceita argumentos.')end
 if base=='additive'then
  def.additive=additivePairs(assert(map['additive-symbols'],'system additive exige additive-symbols.'))
 elseif base~='extends'then
  local list=symbolList(assert(map.symbols,'@counter-style '..name..' exige symbols.'),true,'symbols')
  assert(#list>0,'symbols vazio em @counter-style '..name..'.')
  if base=='numeric'then assert(#list>=2,'system numeric exige pelo menos 2 simbolos.')end
  if base=='alphabetic'then assert(#list>=2,'system alphabetic exige pelo menos 2 simbolos.')end
  def.symbols=list
 end
 if map.prefix then local list=symbolList(map.prefix,true,'prefix');assert(#list==1,'prefix aceita um valor.');def.prefix=list[1]end
 if map.suffix then local list=symbolList(map.suffix,true,'suffix');assert(#list==1,'suffix aceita um valor.');def.suffix=list[1]end
 if map.negative then
  local list=symbolList(map.negative,true,'negative');assert(#list>=1 and #list<=2,'negative aceita um ou dois valores.')
  def.negative={list[1],list[2]or ''}
 end
 if map.pad then
  local length,rest=map.pad:match('^(%d+)%s*(.*)$')
  assert(length,'pad usa "quantidade simbolo", ex.: pad:2 "0".')
  local list=symbolList(rest,true,'pad');assert(#list==1,'pad exige exatamente um simbolo.')
  assert(tonumber(length)<=MAX_SYMBOLS,'pad aceita no maximo '..MAX_SYMBOLS..'.')
  def.pad={length=math.floor(tonumber(length)),symbol=list[1]}
 end
 if map.range then def.ranges=rangeList(map.range)end
 if map.fallback then
  assert(C.validName(map.fallback),'fallback invalido: '..map.fallback)
  def.fallback=map.fallback
 end
 return def
end
function C.registry(defs,width)
 if defs==nil then return nil end
 local custom={};local count=0
 for _,def in ipairs(defs)do
  assert(type(def)=='table'and def.name,'@counter-style sem nome.')
  local active=(not width)or((not def.minWidth or width>=def.minWidth)and(not def.maxWidth or width<=def.maxWidth))
  if active then
   if custom[def.name]==nil then count+=1 end
   assert(count<=MAX_STYLES,'Maximo de '..MAX_STYLES..' regras @counter-style por documento.')
   custom[def.name]=def
  end
 end
 if count==0 then return nil end
 return custom
end
local digits={'0','1','2','3','4','5','6','7','8','9'}
local lowerAlpha={};for i=0,25 do lowerAlpha[i+1]=string.char(97+i)end
local upperAlpha={};for i=0,25 do upperAlpha[i+1]=string.char(65+i)end
local lowerGreek={};for code=0x3b1,0x3c9 do if code~=0x3c2 then lowerGreek[#lowerGreek+1]=utf8.char(code)end end
local function additiveFrom(list)
 local out={};for _,pair in ipairs(list)do out[#out+1]={weight=pair[1],symbol=pair[2]}end;return out
end
local romanUpper=additiveFrom({{1000,'M'},{900,'CM'},{500,'D'},{400,'CD'},{100,'C'},{90,'XC'},{50,'L'},{40,'XL'},{10,'X'},{9,'IX'},{5,'V'},{4,'IV'},{1,'I'}})
local romanLower=additiveFrom({{1000,'m'},{900,'cm'},{500,'d'},{400,'cd'},{100,'c'},{90,'xc'},{50,'l'},{40,'xl'},{10,'x'},{9,'ix'},{5,'v'},{4,'iv'},{1,'i'}})
local builtin={
 none={system='cyclic',symbols={''},suffix=''},
 disc={system='cyclic',symbols={utf8.char(0x2022)},suffix=' '},
 circle={system='cyclic',symbols={utf8.char(0x25e6)},suffix=' '},
 square={system='cyclic',symbols={utf8.char(0x25aa)},suffix=' '},
 ['disclosure-open']={system='cyclic',symbols={utf8.char(0x25be)},suffix=' '},
 ['disclosure-closed']={system='cyclic',symbols={utf8.char(0x25b8)},suffix=' '},
 decimal={system='numeric',symbols=digits,suffix='. '},
 ['decimal-leading-zero']={system='numeric',symbols=digits,suffix='. ',pad={length=2,symbol='0'}},
 ['lower-alpha']={system='alphabetic',symbols=lowerAlpha,suffix='. '},
 ['upper-alpha']={system='alphabetic',symbols=upperAlpha,suffix='. '},
 ['lower-greek']={system='alphabetic',symbols=lowerGreek,suffix='. '},
 ['upper-roman']={system='additive',additive=romanUpper,suffix='. '},
 ['lower-roman']={system='additive',additive=romanLower,suffix='. '},
}
builtin['lower-latin']=builtin['lower-alpha']
builtin['upper-latin']=builtin['upper-alpha']
for _,def in pairs(builtin)do if not table.isfrozen(def)then table.freeze(def)end end
C.builtin=table.freeze(builtin)
function C.style(custom,name)
 if custom and custom[name]then return custom[name]end
 return builtin[name]
end
function C.known(custom,name)return C.style(custom,name)~=nil end
local function effective(custom,name,depth)
 local def=C.style(custom,name)
 assert(def,'Estilo de contador desconhecido: '..tostring(name))
 if def.system~='extends'then return def end
 assert(depth<8,'Cadeia de extends muito profunda em @counter-style '..tostring(name)..'.')
 local base=effective(custom,def.extends or 'decimal',depth+1)
 local merged=table.clone(base)
 for key,value in pairs(def)do if key~='system'and key~='extends'and key~='name'then merged[key]=value end end
 merged.system=base.system
 return merged
end
local function inRange(def,value)
 if def.ranges then
  for _,entry in ipairs(def.ranges)do
   if(entry.min==nil or value>=entry.min)and(entry.max==nil or value<=entry.max)then return true end
  end
  return false
 end
 local system=def.system
 if system=='alphabetic'or system=='symbolic'then return value>=1 end
 if system=='additive'then return value>=0 end
 return true
end
local function symbolic(def,value)
 local n=#def.symbols;local reps=math.ceil(value/n)
 if reps>MAX_SYMBOLS then return nil end
 return string.rep(def.symbols[(value-1)%n+1],reps)
end
local function alphabetic(def,value)
 local n=#def.symbols;local out={}
 while value>0 do
  local rest=(value-1)%n
  table.insert(out,1,def.symbols[rest+1])
  value=math.floor((value-1)/n)
  if #out>MAX_SYMBOLS then return nil end
 end
 return table.concat(out)
end
local function numeric(def,value)
 local n=#def.symbols
 if value==0 then return def.symbols[1]end
 local out={}
 while value>0 do
  table.insert(out,1,def.symbols[value%n+1])
  value=math.floor(value/n)
  if #out>MAX_SYMBOLS then return nil end
 end
 return table.concat(out)
end
local function additive(def,value)
 if value==0 then
  for _,entry in ipairs(def.additive)do if entry.weight==0 then return entry.symbol end end
  return nil
 end
 local out={};local left=value;local total=0
 for _,entry in ipairs(def.additive)do
  if entry.weight>0 and left>=entry.weight then
   local times=math.floor(left/entry.weight);left-=times*entry.weight
   total+=times;if total>MAX_SYMBOLS then return nil end
   out[#out+1]=string.rep(entry.symbol,times)
  end
 end
 if left>0 then return nil end
 return table.concat(out)
end
function C.render(custom,name,value,affixes,depth)
 depth=depth or 0
 assert(depth<8,'Cadeia de fallback de contador muito profunda.')
 local def=effective(custom,name,0)
 value=math.floor(tonumber(value)or 0)
 if not inRange(def,value)then return C.render(custom,def.fallback or 'decimal',value,affixes,depth+1)end
 local system=def.system
 local signed=(system=='numeric'or system=='additive')and value<0
 local magnitude=value<0 and-value or value
 local text
 if system=='cyclic'then text=def.symbols[(value-1)%#def.symbols+1]
 elseif system=='fixed'then
  local index=value-(def.first or 1)+1
  if index>=1 and index<=#def.symbols then text=def.symbols[index]end
 elseif system=='symbolic'then if magnitude>=1 then text=symbolic(def,magnitude)end
 elseif system=='alphabetic'then if magnitude>=1 then text=alphabetic(def,magnitude)end
 elseif system=='numeric'then text=numeric(def,magnitude)
 elseif system=='additive'then text=additive(def,magnitude)end
 if text==nil then return C.render(custom,def.fallback or 'decimal',value,affixes,depth+1)end
 local negative=signed and(def.negative and def.negative[1]or '-')or ''
 if def.pad and def.pad.length then
  local size=(utf8.len(text)or #text)+(utf8.len(negative)or #negative)
  local missing=math.max(0,def.pad.length-size)
  if missing>0 then text=string.rep(def.pad.symbol or '0',missing)..text end
 end
 if signed then text=negative..text..(def.negative and def.negative[2]or '')end
 if affixes then text=(def.prefix or '')..text..(def.suffix or '')end
 return text
end
local declarationCache={};local declarationCount=0
function C.declaration(value,default)
 if value==nil or value==''then return EMPTY end
 local key=tostring(default)..'|'..value
 local cached=declarationCache[key]
 if cached then return cached end
 local list=words(value);local out={}
 if #list==1 and(list[1]=='none'or list[1]=='initial'or list[1]=='unset')then out=EMPTY
 else
  local i=1
  while i<=#list do
   local name=list[i]
   assert(C.validName(name),'Nome de contador invalido: '..name)
   local delta=tonumber(list[i+1])
   if delta then i+=2 else delta=default;i+=1 end
   delta=math.floor(delta)
   assert(math.abs(delta)<=1000000,'Valor de contador fora do intervalo: '..delta)
   out[#out+1]={name=name,value=delta}
   assert(#out<=MAX_COUNTERS,'Maximo de '..MAX_COUNTERS..' contadores por declaracao.')
  end
  out=table.freeze(out)
 end
 if declarationCount<512 then declarationCache[key]=out;declarationCount+=1 end
 return out
end
local defaultQuotes=table.freeze({table.freeze({utf8.char(0x201c),utf8.char(0x201d)}),table.freeze({utf8.char(0x2018),utf8.char(0x2019)})})
C.defaultQuotes=defaultQuotes
local quoteCache={};local quoteCount=0
function C.quotes(value)
 if value==nil or value==''or value=='auto'or value=='initial'or value=='unset'then return defaultQuotes end
 if value=='none'then return EMPTY end
 local cached=quoteCache[value]
 if cached then return cached end
 local list=symbolList(value,false,'quotes')
 assert(#list>=2 and #list%2==0,'quotes exige pares de strings, ex.: quotes:"<<" ">>".')
 local out={}
 for i=1,#list,2 do out[#out+1]=table.freeze({list[i],list[i+1]})end
 out=table.freeze(out)
 if quoteCount<64 then quoteCache[value]=out;quoteCount+=1 end
 return out
end
function C.scope()
 local self={values={},frames={},depth=0,quote=0}
 function self:push(key,isolate)
  self.depth+=1
  local frame={key=key}
  if isolate then
   frame.isolated=true;frame.savedValues=self.values;frame.savedQuote=self.quote
   self.values={};self.quote=0
  end
  self.frames[self.depth]=frame
 end
 function self:pop()
  local frame=self.frames[self.depth]
  if not frame then return end
  local cleanup=frame.cleanup
  if cleanup then
   for i=#cleanup,1,-1 do
    local stack=self.values[cleanup[i]]
    if stack then
     stack[#stack]=nil
     if #stack==0 then self.values[cleanup[i]]=nil end
    end
   end
  end
  if frame.savedValues then self.values=frame.savedValues;self.quote=frame.savedQuote end
  self.frames[self.depth]=nil;self.depth-=1
 end
 function self:reset(name,value)
  local frame=self.frames[self.depth]
  local barrier=frame~=nil and frame.isolated==true
  local level=barrier and self.depth or self.depth-1
  local stack=self.values[name]
  if stack and #stack>0 and stack[#stack].level==level then stack[#stack].value=value;return end
  if not stack then stack={};self.values[name]=stack end
  stack[#stack+1]={value=value,level=level}
  local holder=barrier and frame or self.frames[self.depth>1 and self.depth-1 or self.depth]
  if holder then
   holder.cleanup=holder.cleanup or {}
   holder.cleanup[#holder.cleanup+1]=name
  end
 end
 function self:ensure(name)
  local stack=self.values[name]
  if not stack or #stack==0 then self:reset(name,0)end
 end
 function self:increment(name,delta)
  self:ensure(name);local stack=self.values[name];stack[#stack].value+=delta
 end
 function self:set(name,value)
  self:ensure(name);local stack=self.values[name];stack[#stack].value=value
 end
 function self:value(name)
  local stack=self.values[name]
  if not stack or #stack==0 then return 0 end
  return stack[#stack].value
 end
 function self:list(name)
  local stack=self.values[name];local out={}
  if stack then for i,entry in ipairs(stack)do out[i]=entry.value end end
  return out
 end
 function self:quoteText(mode,pairList)
  local list=pairList or defaultQuotes
  if mode=='open'or mode=='no-open'then
   local index=math.min(self.quote+1,#list)
   if self.quote<64 then self.quote+=1 end
   if mode=='no-open'or #list==0 then return ''end
   return list[index][1]
  end
  if self.quote<=0 then return ''end
  self.quote-=1
  if mode=='no-close'or #list==0 then return ''end
  return list[math.min(self.quote+1,#list)][2]
 end
 return self
end
function C.enter(scope,style,node,isolate)
 scope:push(node and node.key or '?',isolate)
 local attrs=node and node.attrs or EMPTY
 local resets=C.declaration(style['counter-reset'],0)
 for _,item in ipairs(resets)do scope:reset(item.name,item.value)end
 local tag=node and node.tag
 if tag=='ol'or tag=='ul'then
  local explicit=false
  for _,item in ipairs(resets)do if item.name=='list-item'then explicit=true end end
  if not explicit then
   local start=tonumber(attrs.start)
   scope:reset('list-item',start and math.floor(start)-1 or 0)
  end
 end
 local increments=C.declaration(style['counter-increment'],1)
 for _,item in ipairs(increments)do scope:increment(item.name,item.value)end
 if style.display=='list-item'then
  local explicit=false
  for _,item in ipairs(increments)do if item.name=='list-item'then explicit=true end end
  if not explicit then scope:increment('list-item',1)end
  local value=tonumber(attrs.value)
  if value then scope:set('list-item',math.floor(value))end
 end
 for _,item in ipairs(C.declaration(style['counter-set'],0))do scope:set(item.name,item.value)end
end
function C.exit(scope)scope:pop()end
function C.normalizeImage(value,label)
 label=label or 'Imagem'
 local text=trim(tostring(value))
 local body=text:match('^[uU][rR][lL]%s*%((.*)%)$')or text:match('^[sS][rR][cC]%s*%((.*)%)$')or text:match('^[iI][mM][aA][gG][eE]%s*%((.*)%)$')
 text=trim(body or text)
 if text:sub(1,1)=='"'or text:sub(1,1)=="'"then text=(C.readString(text,1))end
 text=trim(text)
 assert(#text>0 and #text<=512,label..' exige uma fonte de 1 a 512 caracteres.')
 local digits=text:match('^(%d+)$')
 if digits then
  assert(#digits<=19,label..' recebeu um ID numerico longo demais.')
  return 'rbxassetid://'..digits
 end
 if text:lower():match('^https?://')then
  local host=(text:match('^%a+://([^/]+)')or ''):lower()
  local id=text:match('[%?&][iI][dD]=(%d+)')or text:match('/asset/(%d+)')or text:match('/library/(%d+)')
  assert(host:match('roblox%.com$')or host:match('rbxcdn%.com$'),label..' nao aceita URLs externas; o Roblox nao as carrega.')
  assert(id,label..' nao encontrou o ID do asset na URL.')
  return 'rbxassetid://'..id
 end
 local scheme,rest=text:match('^(%a[%w%+%.%-]*)://(.*)$')
 assert(scheme and rest~='',label..' aceita rbxassetid://ID, rbxasset://, rbxthumb://, rbxgameasset:// ou um ID numerico.')
 scheme=scheme:lower()
 if scheme=='rbxassetid'then
  local only=rest:match('^(%d+)$');assert(only,label..' espera rbxassetid://ID.')
  return 'rbxassetid://'..only
 end
 if scheme=='rbxasset'then assert(rest:match('^[%w%._%-/]+$'),label..' aceita rbxasset://caminho.');return text end
 if scheme=='rbxgameasset'then assert(rest:match('^[%w%._%- /]+$'),label..' aceita rbxgameasset://Nome.');return text end
 if scheme=='rbxthumb'then assert(rest:match('^type=%a+&id=%d+'),label..' aceita rbxthumb://type=Asset&id=ID&w=L&h=A.');return text end
 if scheme=='rbxhttp'then assert(rest:match('^[%w%._%-/%?&=]+$'),label..' aceita rbxhttp://caminho.');return text end
 error(label..' nao aceita o esquema '..scheme..'://; use assets do Roblox.',0)
end
function C.imageSource(value)return C.normalizeImage(value,'Imagem de marcador')end
function C.expandListStyle(value)
 local out={['list-style-type']='disc',['list-style-position']='outside',['list-style-image']='none'}
 local text=trim(value);local seen={};local p=1
 while p<=#text do
  local c=text:sub(p,p)
  if c:match('%s')then p+=1
  elseif c=='"'or c=="'"then
   local _,after=C.readString(text,p)
   assert(not seen.type,'list-style aceita um unico tipo de marcador.')
   out['list-style-type']=text:sub(p,after-1);seen.type=true;p=after
  else
   local word=text:match('^%S+',p);local lower=word:lower()
   if lower=='inside'or lower=='outside'then
    assert(not seen.position,'list-style aceita uma unica posicao.')
    out['list-style-position']=lower;seen.position=true
   elseif lower:match('^url%(')or lower:match('^image%(')then
    assert(not seen.image,'list-style aceita uma unica imagem.')
    C.imageSource(word);out['list-style-image']=word;seen.image=true
   elseif lower=='none'then
    if seen.type then out['list-style-image']='none';seen.image=true else out['list-style-type']='none';seen.type=true end
   else
    assert(not seen.type,'list-style aceita um unico tipo de marcador.')
    assert(C.validName(word),'list-style invalido: '..word)
    out['list-style-type']=word;seen.type=true
   end
   p+=#word
  end
 end
 return out
end
function C.marker(style,custom,value)
 local image=style['list-style-image']
 if image and image~='none'and image~=''then return nil,C.imageSource(image)end
 local name=style['list-style-type']or 'disc'
 if name=='none'then return '',nil end
 local first=name:sub(1,1)
 if first=='"'or first=="'"then return C.readString(name,1)..' ',nil end
 return C.render(custom,name,value,true),nil
end
return C
