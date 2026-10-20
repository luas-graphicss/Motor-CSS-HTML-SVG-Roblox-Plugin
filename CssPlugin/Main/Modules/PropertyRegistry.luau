local U=require(script.Parent.Util)
local Interpolation=require(script.Parent.CssInterpolation)
local R={VERSION=1}
local LIMIT=64
local discreteTypes=table.freeze({['<custom-ident>']=true,['<string>']=true})
function R.parseSyntax(text)
 assert(type(text)=='string','Descritor syntax inválido.')
 text=U.trim(text)
 local quote=text:sub(1,1)
 if quote=='"'or quote=="'"then
  assert(#text>=2 and text:sub(-1)==quote,'syntax exige string fechada.');text=U.trim(text:sub(2,-2))
 end
 assert(text~='','syntax vazia.')
 if text=='*'then return {universal=true,text='*'}end
 local alternatives={}
 for _,part in ipairs(U.split(text,'|'))do
  local item=U.trim(part);assert(item~='','syntax com alternativa vazia.')
  local multiplier=item:sub(-1)
  if multiplier=='+'or multiplier=='#'then item=U.trim(item:sub(1,-2))else multiplier=nil end
  if item:sub(1,1)=='<'then
   local kind=item:lower()
   assert(Interpolation.supports(kind),'Tipo de syntax não suportado: '..item)
   alternatives[#alternatives+1]={type=kind,multiplier=multiplier}
  else
   assert(item:match('^%-?[%a_][%w_%-]*$'),'Keyword de syntax inválida: '..item)
   alternatives[#alternatives+1]={keyword=item,multiplier=multiplier}
  end
  assert(#alternatives<=16,'syntax aceita até 16 alternativas.')
 end
 return {alternatives=alternatives,text=text}
end
local function single(alternative,text,ctx)
 if alternative.keyword then
  assert(text==alternative.keyword,'Keyword esperada: '..alternative.keyword)
  return {t='keyword',v=text}
 end
 return Interpolation.typed(alternative.type,text,ctx)
end
function R.coerce(descriptor,value,ctx)
 local syntax=descriptor.syntax or descriptor
 assert(type(value)=='string','Valor de custom property inválido.')
 local text=U.trim(value);assert(text~='','Valor de custom property vazio.')
 if syntax.universal then return {t='keyword',v=text}end
 for _,alternative in ipairs(syntax.alternatives)do
  local ok,result=pcall(function()
   if alternative.multiplier then
    local parts=alternative.multiplier=='#'and Interpolation.members(text,',')or U.split(text,' ')
    assert(#parts>0 and #parts<=LIMIT,'Lista de valores inválida.')
    local items={};for i,part in ipairs(parts)do items[i]=single(alternative,part,ctx)end
    if #items==1 then return items[1]end
    return {t='list',sep=alternative.multiplier=='#'and','or' ',items=items}
   end
   return single(alternative,text,ctx)
  end)
  if ok then return result end
 end
 error('Valor incompatível com a syntax de '..tostring(descriptor.name or'--?')..': '..text,0)
end
function R.parse(name,body)
 assert(type(name)=='string'and name:match('^%-%-[%w_%-]+$'),'@property exige --nome.')
 assert(type(body)=='string'and #body<=8192,'Corpo de @property inválido.')
 local descriptor={name=name}
 for _,line in ipairs(U.split(body,';'))do
  local key,value=line:match('^%s*([%a%-]+)%s*:%s*(.-)%s*$')
  assert(key and value and value~='','Descritor @property inválido: '..U.trim(line))
  key=key:lower()
  if key=='syntax'then descriptor.syntax=R.parseSyntax(value)
  elseif key=='inherits'then
   local flag=value:lower();assert(flag=='true'or flag=='false','inherits aceita true ou false.');descriptor.inherits=flag=='true'
  elseif key=='initial-value'then descriptor.initial=U.trim(value)
  else error('Descritor @property não suportado: '..key,0)end
 end
 assert(descriptor.syntax,'@property exige o descritor syntax.')
 assert(descriptor.inherits~=nil,'@property exige o descritor inherits.')
 if not descriptor.syntax.universal then assert(descriptor.initial~=nil,'@property com syntax tipada exige initial-value.')end
 if descriptor.initial then
  assert(not descriptor.initial:lower():find('var(',1,true),'initial-value não aceita var().')
  R.coerce(descriptor,descriptor.initial)
 end
 descriptor.syntaxText=descriptor.syntax.text
 descriptor.animatable=R.animatable(descriptor)
 return descriptor
end
function R.animatable(descriptor)
 local syntax=descriptor.syntax or descriptor
 if syntax.universal then return false end
 for _,alternative in ipairs(syntax.alternatives)do
  if alternative.type and not discreteTypes[alternative.type]then return true end
 end
 return false
end
function R.registry(descriptors)
 local map={}
 for _,descriptor in ipairs(descriptors or {})do
  assert(descriptor.name,'Registro @property sem nome.');map[descriptor.name]=descriptor
 end
 return map
end
function R.typed(registry,name,value,ctx)
 local descriptor=registry and registry[name]
 if not descriptor or type(value)~='string'then return nil,descriptor end
 local ok,result=pcall(R.coerce,descriptor,value,ctx)
 if ok then return result,descriptor end
 return nil,descriptor
end
function R.compute(vars,inherited,winners,registry,ctx)
 if not registry or not next(registry)or type(vars)~='table'then return vars end
 for name,descriptor in pairs(registry)do
  local declared=winners~=nil and winners[name]~=nil
  local value=vars[name]
  if not descriptor.inherits and not declared then value=nil end
  local typed
  if type(value)=='string'then
   local ok,result=pcall(R.coerce,descriptor,value,ctx)
   if ok then typed=result end
  end
  if not typed and descriptor.initial then
   local ok,result=pcall(R.coerce,descriptor,descriptor.initial,ctx)
   if ok then typed=result end
  end
  if typed then
   local ok,text=pcall(Interpolation.serialize,typed)
   vars[name]=ok and text or descriptor.initial or false
  else vars[name]=false end
 end
 return vars
end
function R.describe(registry)
 local out={}
 for name,descriptor in pairs(registry or {})do
  out[#out+1]={name=name,syntax=descriptor.syntaxText or(descriptor.syntax and descriptor.syntax.text),inherits=descriptor.inherits,initial=descriptor.initial,animatable=descriptor.animatable==true}
 end
 table.sort(out,function(a,b)return a.name<b.name end)
 return out
end
return R
