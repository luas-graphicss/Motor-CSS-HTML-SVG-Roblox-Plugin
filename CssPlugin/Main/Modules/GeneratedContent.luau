local Counters=require(script.Parent.CssCounters)
local G={VERSION=1}
local MAX_TEXT=4096
local MAX_TOKENS=64
local quoteModes=table.freeze({['open-quote']='open',['close-quote']='close',['no-open-quote']='no-open',['no-close-quote']='no-close'})
local function trim(text)return(text:gsub('^%s+',''):gsub('%s+$',''))end
local function closing(text,open)
 local depth=0;local quote=nil;local i=open
 while i<=#text do
  local c=text:sub(i,i)
  if quote then
   if c==string.char(92)then i+=1 elseif c==quote then quote=nil end
  elseif c=='"'or c=="'"then quote=c
  elseif c=='('then depth+=1
  elseif c==')'then depth-=1;if depth==0 then return i end end
  i+=1
 end
 error('Funcao CSS nao fechada em content.',0)
end
local function onlyString(part,label)
 local text=trim(part or '')
 assert(text:sub(1,1)=='"'or text:sub(1,1)=="'",label..' precisa ser uma string CSS.')
 local value,after=Counters.readString(text,1)
 assert(trim(text:sub(after))=='',label..' aceita apenas uma string.')
 return value
end
local function styleArgument(part)
 local name=trim(part or '')
 if name==''then return 'decimal'end
 assert(Counters.validName(name),'Estilo de contador invalido: '..name)
 return name
end
local function imageSource(body,label)
 local text=trim(body)
 if text:sub(1,1)=='"'or text:sub(1,1)=="'"then text=onlyString(text,label)end
 return Counters.normalizeImage(text,label)
end
local function imageSet(body,label)
 local candidates={}
 for _,part in ipairs(Counters.commas(body))do
  local text=trim(part)
  if text~=''then
   local source,rest
   local fn=text:match('^[%a%-][%w%-]*%s*%b()')
   if fn then source=fn;rest=trim(text:sub(#fn+1))
   elseif text:sub(1,1)=='"'or text:sub(1,1)=="'"then
    local value,after=Counters.readString(text,1)
    source=value;rest=trim(text:sub(after))
   else
    source=text:match('^%S+')or text;rest=trim(text:sub(#source+1))
   end
   local scale=1
   if rest~=''then
    local n,unit=rest:match('^([%d%.]+)%s*(%a*)$')
    assert(n,label..' aceita resolucao em x, dppx, dpi ou dpcm.')
    scale=tonumber(n)or 0
    local u=(unit or ''):lower()
    if u=='dpi'then scale/=96
    elseif u=='dpcm'then scale*=2.54/96
    else assert(u==''or u=='x'or u=='dppx',label..' aceita x, dppx, dpi ou dpcm.')end
   end
   assert(scale>0 and scale<64,label..' exige resolucao positiva.')
   candidates[#candidates+1]={source=imageSource(source,label),resolution=scale}
   assert(#candidates<=16,label..' aceita no maximo 16 alternativas.')
  end
 end
 assert(#candidates>0,label..' vazio.')
 table.sort(candidates,function(a,b)return a.resolution<b.resolution end)
 return candidates
end
local function pickImage(token,dpr)
 local list=token.candidates
 if not list or #list==0 then return token.source end
 local target=tonumber(dpr)or 1
 local best,score
 for _,item in ipairs(list)do
  local delta=math.abs(item.resolution-target)
  if item.resolution<target then delta+=0.0005 end
  if score==nil or delta<score then best=item;score=delta end
 end
 return best and best.source or token.source
end
local cache={};local cacheCount=0
function G.parse(value)
 assert(type(value)=='string','content precisa ser texto.')
 local cached=cache[value]
 if cached then return cached end
 assert(#value<=MAX_TEXT,'content excede '..MAX_TEXT..' caracteres.')
 local trimmed=trim(value)
 local parsed
 if trimmed=='none'then parsed={mode='none'}
 elseif trimmed==''or trimmed=='normal'then parsed={mode='normal'}
 else
  local tokens={};local alt=nil;local target=tokens;local p=1
  while p<=#value do
   local c=value:sub(p,p)
   if c:match('%s')then p+=1
   elseif c=='"'or c=="'"then
    local text;text,p=Counters.readString(value,p)
    target[#target+1]={kind='string',text=text}
   elseif c=='/'then
    assert(alt==nil,'content aceita um unico texto alternativo depois de "/".')
    alt={};target=alt;p+=1
   else
    local name=value:match('^([%a%-][%w%-]*)%s*%(',p)
    if name then
     local open=value:find('(',p,true)
     local close=closing(value,open)
     local body=value:sub(open+1,close-1)
     local lower=name:lower()
     if lower=='attr'then
      local parts=Counters.commas(body)
      assert(#parts<=2,'attr() aceita nome e fallback.')
      local attribute,typeToken=trim(parts[1]or ''):match('^([%w_%-]+)%s*(%S*)$')
      assert(attribute,'attr() exige o nome do atributo, ex.: attr(data-mark).')
      if typeToken~=''then assert(typeToken:lower()=='string','attr() devolve apenas strings neste plugin.')end
      target[#target+1]={kind='attr',name=attribute,fallback=parts[2]and onlyString(parts[2],'O fallback de attr()')or nil}
     elseif lower=='counter'or lower=='counters'then
      local parts=Counters.commas(body)
      local counter=trim(parts[1]or '')
      assert(Counters.validName(counter),'Nome de contador invalido em '..lower..'(): '..counter)
      if lower=='counter'then
       assert(#parts<=2,'counter() aceita nome e estilo.')
       target[#target+1]={kind='counter',name=counter,style=styleArgument(parts[2])}
      else
       assert(#parts>=2,'counters() exige o separador, ex.: counters(item,".").')
       assert(#parts<=3,'counters() aceita nome, separador e estilo.')
       target[#target+1]={kind='counters',name=counter,separator=onlyString(parts[2],'O separador de counters()'),style=styleArgument(parts[3])}
      end
     elseif lower=='url'or lower=='image'or lower=='src'then
      target[#target+1]={kind='image',source=imageSource(body,lower..'()')}
     elseif lower=='image-set'or lower=='-webkit-image-set'then
      local candidates=imageSet(body,lower..'()')
      target[#target+1]={kind='image',source=candidates[1].source,candidates=candidates}
     else
      error('content nao aceita '..name..'(). Use strings, attr(), counter(), counters(), url() ou image-set().',0)
     end
     p=close+1
    else
     local word=value:match('^%-?[%a][%w%-]*',p)
     assert(word,'Valor invalido em content: '..value:sub(p,p+16))
     local mode=quoteModes[word:lower()]
     assert(mode,"content nao reconhece '"..word.."'. Use strings, attr(), counter(), counters(), url() ou as palavras de aspas.")
     target[#target+1]={kind='quote',mode=mode}
     p+=#word
    end
   end
   assert(#tokens<=MAX_TOKENS and(alt==nil or #alt<=MAX_TOKENS),'content aceita no maximo '..MAX_TOKENS..' partes.')
  end
  assert(#tokens>0,'content vazio.')
  parsed={mode='list',tokens=tokens,alt=alt}
 end
 parsed=table.freeze(parsed)
 if cacheCount<256 then cache[value]=parsed;cacheCount+=1 end
 return parsed
end
function G.needsCounters(parsed)
 if parsed.mode~='list'then return false end
 for _,token in ipairs(parsed.tokens)do
  if token.kind=='counter'or token.kind=='counters'or token.kind=='quote'then return true end
 end
 return false
end
local function run(tokens,ctx)
 local out={};local image=nil
 for _,token in ipairs(tokens)do
  local kind=token.kind
  if kind=='string'then out[#out+1]=token.text
  elseif kind=='attr'then
   local value=ctx.attrs and ctx.attrs[token.name]
   if value==nil then value=token.fallback or ''end
   out[#out+1]=tostring(value)
  elseif kind=='counter'then
   out[#out+1]=Counters.render(ctx.styles,token.style,ctx.scope and ctx.scope:value(token.name)or 0,false)
  elseif kind=='counters'then
   local parts={}
   for index,value in ipairs(ctx.scope and ctx.scope:list(token.name)or {})do
    parts[index]=Counters.render(ctx.styles,token.style,value,false)
   end
   out[#out+1]=table.concat(parts,token.separator)
  elseif kind=='quote'then
   out[#out+1]=ctx.scope and ctx.scope:quoteText(token.mode,ctx.quotes)or ''
  elseif kind=='image'then
   assert(image==nil,'content aceita uma unica imagem.')
   image=pickImage(token,ctx.dpr)
  end
 end
 return table.concat(out),image
end
function G.resolve(parsed,ctx)
 if parsed.mode~='list'then return nil,nil,nil,parsed.mode end
 ctx=ctx or {}
 local text,image=run(parsed.tokens,ctx)
 assert(#text<=MAX_TEXT,'Texto gerado excede '..MAX_TEXT..' bytes.')
 assert(not(image and text~=''),'content aceita imagem ou texto; use dois pseudo-elementos para combinar os dois.')
 local alt=nil
 if parsed.alt then alt=(run(parsed.alt,ctx))end
 return text,image,alt,'list'
end
function G.text(value,attrs)
 local parsed=G.parse(value)
 if parsed.mode~='list'then return nil end
 local text,image=G.resolve(parsed,{attrs=attrs})
 return text,image
end
return G
