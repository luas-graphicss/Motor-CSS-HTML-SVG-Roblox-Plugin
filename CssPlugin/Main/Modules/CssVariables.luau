local Env=require(script.Parent.CssEnvironment)
local V={VERSION=3,INVALID=false}
local LIMIT,DEPTH=32768,128
local cache,slots={},{};local cursor=0
local function trim(s)return (s:gsub('^%s+',''):gsub('%s+$',''))end
local function freeze(t)
 for _,v in pairs(t)do if type(v)=='table'and not table.isfrozen(v)then freeze(v)end end
 return table.freeze(t)
end
local BACKSLASH=string.char(92)
function V.stripComments(text)
 local out;local start,i,quote,escaped=1,1,nil,false
 while i<=#text do
  local c=text:sub(i,i)
  if quote then
   if escaped then escaped=false elseif c==BACKSLASH then escaped=true elseif c==quote then quote=nil end
  elseif c=='"'or c=="'"then quote=c
  elseif c==BACKSLASH then i+=1
  elseif text:sub(i,i+1)=='/*'then
   out=out or {};out[#out+1]=text:sub(start,i-1);out[#out+1]=' '
   local close=assert(text:find('*/',i+2,true),'Comentário CSS não fechado.')
   i=close+1;start=i+1
  end
  i+=1
 end
 if not out then return text end
 out[#out+1]=text:sub(start);return table.concat(out)
end
local parse
parse=function(text,depth)
 depth=depth or 0
 assert(type(text)=='string'and #text<=LIMIT,'Valor customizado excede 32768 bytes.')
 assert(depth<=DEPTH,'var() excede 128 níveis.')
 text=V.stripComments(text)
 if cache[text]then return cache[text]end
 local parts,refs={},{};local start,i,quote,escaped=1,1,nil,false
 while i<=#text do
  local c=text:sub(i,i)
  if quote then
   if escaped then escaped=false elseif c==BACKSLASH then escaped=true elseif c==quote then quote=nil end
   i+=1
  elseif c=='"'or c=="'"then quote=c;i+=1
  elseif c==BACKSLASH then i+=2
  elseif text:sub(i,i+3):lower()=='var('and(i==1 or not text:sub(i-1,i-1):match('[%w_%-]'))then
   if i>start then parts[#parts+1]=text:sub(start,i-1)end
   local j,level,q,escape,comma=i+4,1,nil,false,nil
   while j<=#text and level>0 do
    local ch=text:sub(j,j)
    if q then
     if escape then escape=false elseif ch==BACKSLASH then escape=true elseif ch==q then q=nil end
    elseif ch=='"'or ch=="'"then q=ch
    elseif ch==BACKSLASH then j+=1
    elseif ch=='('then level+=1
    elseif ch==')'then level-=1
    elseif ch==','and level==1 and not comma then comma=j end
    j+=1
   end
   assert(level==0,'var() não fechado.')
   local name=trim(text:sub(i+4,(comma or j-1)-1))
   assert(name:match('^%-%-[%w_%-]+$'),'Nome de variável inválido: '..name)
   local item={name=name};refs[name]=true
   if comma then
    item.fallback=parse(text:sub(comma+1,j-2),depth+1)
    for ref in pairs(item.fallback.refs)do refs[ref]=true end
   end
   parts[#parts+1]=item;i=j;start=j
   assert(#parts<=2048,'Muitas substituições var() no mesmo valor.')
  else i+=1 end
 end
 assert(not quote,'String CSS não fechada em valor customizado.')
 if start<=#text then parts[#parts+1]=text:sub(start)end
 local result=freeze({parts=parts,refs=refs})
 cursor=cursor%512+1;local old=slots[cursor];if old then cache[old]=nil end
 slots[cursor]=text;cache[text]=result;return result
end
local function substitute(program,lookup,depth,budget)
 assert(depth<=DEPTH,'var() excede 128 níveis.')
 local out,size={},0
 for _,part in ipairs(program.parts)do
  local value=part
  if type(part)=='table'then
   budget.n+=1;assert(budget.n<=8192,'Orçamento de substituições var() excedido.')
   value=lookup(part.name,depth+1)
   if value==nil or value==false then
    if part.fallback then value=substitute(part.fallback,lookup,depth+1,budget)end
   end
   if value==nil or value==false then return false end
  end
  size+=#value;assert(size<=LIMIT,'Expansão de variável excede 32768 bytes.')
  out[#out+1]=value
 end
 return table.concat(out)
end
function V.compute(inherited,winners)
 local result=table.clone(inherited or {});local programs={}
 for key,declaration in pairs(winners or {})do
  if key:sub(1,2)=='--'then
   local value=type(declaration)=='table'and declaration.value or declaration
   assert(type(value)=='string','Valor de variável deve ser uma string.')
   local cleanOK,cleaned=pcall(V.stripComments,value)
   local keyword=cleanOK and trim(cleaned):lower()or ''
   if keyword=='initial'then result[key]=false
   elseif keyword=='inherit'or keyword=='unset'or keyword=='revert'or keyword=='revert-layer'then
    local inheritedValue=inherited and inherited[key]
    if inheritedValue==nil then result[key]=false else result[key]=inheritedValue end
   else
    local ok,program=pcall(parse,value)
    result[key]=false
    if ok then programs[key]=program end
   end
  end
 end
 local indices,low,onStack,stack,cyclic={},{},{},{},{};local nextIndex=0
 local function visit(key,depth)
  assert(depth<=DEPTH,'Cadeia de variáveis excede 128 níveis.')
  nextIndex+=1;indices[key]=nextIndex;low[key]=nextIndex
  stack[#stack+1]=key;onStack[key]=true
  for ref in pairs(programs[key].refs)do if programs[ref]then
   if not indices[ref]then visit(ref,depth+1);low[key]=math.min(low[key],low[ref])
   elseif onStack[ref]then low[key]=math.min(low[key],indices[ref])end
  end end
  if low[key]==indices[key]then
   local members={};local member
   repeat member=stack[#stack];stack[#stack]=nil;onStack[member]=nil;members[#members+1]=member until member==key
   if #members>1 or programs[key].refs[key]then for _,name in ipairs(members)do cyclic[name]=true end end
  end
 end
 for key in pairs(programs)do if not indices[key]then visit(key,0)end end
 local resolved={};local budget={n=0}
 local function lookup(key,depth)
  assert(depth<=DEPTH,'Cadeia de variáveis excede 128 níveis.')
  if programs[key]and not resolved[key]then
   resolved[key]=true
   if not cyclic[key]then result[key]=substitute(programs[key],lookup,depth,budget)end
  end
  return result[key]
 end
 for key in pairs(programs)do lookup(key,0)end
 return result
end
function V.tryResolve(value,vars)
 local ok,result=pcall(function()
  local budget={n=0};local visiting={}
  local lookup
  lookup=function(key,depth)
   assert(depth<=DEPTH,'Cadeia de variáveis excede 128 níveis.')
   local v=vars and vars[key]
   if v==nil or v==false or visiting[key]then return false end
   assert(type(v)=='string','Variável CSS não é texto: '..key)
   visiting[key]=true
   local result=substitute(parse(v),lookup,depth,budget)
   visiting[key]=nil;return result
  end
  return substitute(parse(value),lookup,0,budget)
 end)
 if not ok then return nil,tostring(result)end
 if result==false then return nil,'Variável CSS não definida ou circular, sem fallback válido.'end
 return result
end
function V.resolve(value,vars)
 local result,err=V.tryResolve(value,vars)
 assert(result~=nil,err);return trim(result)
end
function V.has(value)
 if type(value)~='string'then return false end
 if Env.has(value)then return true end
 local ok,p=pcall(parse,value);return ok and next(p.refs)~=nil
end
function V.clear()table.clear(cache);table.clear(slots);cursor=0 end
return V
