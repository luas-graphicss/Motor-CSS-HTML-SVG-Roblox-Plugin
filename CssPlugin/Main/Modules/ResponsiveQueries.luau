local Q={VERSION=2}
local function trim(s)return (s:gsub('^%s+',''):gsub('%s+$',''))end
local function styleAtom(text)
 local body=trim(text)
 assert(#body>0 and #body<=512,'style() exige 1..512 bytes.')
 local property,value=body:match('^(%-%-[%w_%-]+)%s*:%s*(.+)$')
 if not property then
  property,value=body:match('^(%-?%a[%w_%-]*)%s*:%s*(.+)$')
  if property then property=property:lower()end
 end
 if property then
  value=trim(value);assert(#value>0,'style() exige um valor.')
  return {op='style',property=property,value=value}
 end
 property=body:match('^(%-%-[%w_%-]+)$')
 if not property then
  local plain=body:match('^(%-?%a[%w_%-]*)$')
  property=plain and plain:lower()or nil
 end
 assert(property,'style() aceita propriedades CSS ou customizadas: '..body)
 return {op='style',property=property}
end
local function styleOnly(query)
 if query.op=='style'then return true end
 if query.op=='feature'or query.op=='type'then return false end
 if query.item then return styleOnly(query.item)end
 for _,item in ipairs(query.items or {})do if not styleOnly(item)then return false end end
 return true
end
Q.styleOnly=styleOnly
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function number(s)
 local mantissa=s:match('^(.-)[eE][+%-]?%d+$')or s
 if not mantissa:match('^[+%-]?%d*%.?%d+$')then return nil end
 local n=tonumber(s);return finite(n)and n or nil
end
local environmentKeys={colorScheme=true,reducedMotion=true,devicePixelRatio=true,mediaType=true,initialFontSize=true,pointer=true,anyPointer=true,hover=true,anyHover=true,forcedColors=true,invertedColors=true,contrast=true,reducedTransparency=true,colorGamut=true}
local environmentEnums=table.freeze({colorScheme={dark=true,light=true},mediaType={screen=true,print=true,speech=true},pointer={none=true,coarse=true,fine=true},anyPointer={none=true,coarse=true,fine=true},hover={none=true,hover=true},anyHover={none=true,hover=true},forcedColors={none=true,active=true},invertedColors={none=true,inverted=true},contrast={['no-preference']=true,more=true,less=true,custom=true},colorGamut={srgb=true,p3=true,rec2020=true}})
local environmentFlags=table.freeze({reducedMotion=true,reducedTransparency=true})
function Q.overrides(input)
 assert(input==nil or type(input)=='table','mediaEnvironment exige uma tabela.')
 local out={}
 for key,value in pairs(input or {})do
  assert(environmentKeys[key],'Campo mediaEnvironment desconhecido: '..tostring(key))
  local allowed=environmentEnums[key]
  if allowed then assert(type(value)=='string'and allowed[value],key..' recebeu um valor inválido.')
  elseif environmentFlags[key]then assert(type(value)=='boolean',key..' exige boolean.')
  else assert(finite(value)and value>0 and value<=10000,key..' exige número positivo finito.')end
  out[key]=value
 end
 return out
end
function Q.environment(input)
 local out=Q.overrides(input)
 if out.colorScheme==nil then out.colorScheme='light'end
 if out.reducedMotion==nil then out.reducedMotion=false end
 if out.reducedTransparency==nil then out.reducedTransparency=false end
 out.devicePixelRatio=out.devicePixelRatio or 1;out.mediaType=out.mediaType or 'screen';out.initialFontSize=out.initialFontSize or 16
 out.pointer=out.pointer or 'fine';out.anyPointer=out.anyPointer or out.pointer
 out.hover=out.hover or 'hover';out.anyHover=out.anyHover or out.hover
 out.forcedColors=out.forcedColors or 'none';out.invertedColors=out.invertedColors or 'none'
 out.contrast=out.contrast or 'no-preference';out.colorGamut=out.colorGamut or 'srgb'
 return out
end
function Q.environmentKey(input)
 local e=Q.environment(input)
 return table.concat({e.mediaType,e.colorScheme,e.reducedMotion and '1'or '0',string.format('%.17g',e.devicePixelRatio),string.format('%.17g',e.initialFontSize),e.pointer,e.anyPointer,e.hover,e.anyHover,e.forcedColors,e.invertedColors,e.contrast,e.colorGamut,e.reducedTransparency and '1'or '0'},'|')
end
local function tokenize(text)
 assert(type(text)=='string'and #text>0 and #text<=4096,'Condição CSS exige 1..4096 bytes.')
 local tokens={};local p=1
 while p<=#text do
  local rest=text:sub(p);local ws=rest:match('^%s+')
  if ws then p+=#ws;continue end
  local token=rest:match('^[+%-]?%d*%.?%d+[eE][+%-]?%d+')or rest:match('^[+%-]?%d*%.?%d+')
  if token then
   p+=#token;local unit=text:sub(p):match('^[%a]+')or '';p+=#unit;token..=unit
  else
   token=rest:match('^[%a_%-][%w_%-]*')
   if token then p+=#token
   else
    token=rest:sub(1,1);assert(token:match('[():,/<>=]'),'Token de consulta não suportado: '..rest:sub(1,24))
    p+=1;if(token=='<'or token=='>')and text:sub(p,p)=='='then token..='=';p+=1 end
   end
  end
  tokens[#tokens+1]=token:lower();assert(#tokens<=256,'Máximo de 256 tokens por consulta.')
 end
 assert(#tokens>0,'Consulta CSS vazia.');return tokens
end
local lengths={px=1,em=true,rem=true,pt=96/72,['in']=96,cm=96/2.54,mm=96/25.4,q=96/101.6,pc=16}
local numeric={width='length',height='length',['inline-size']='length',['block-size']='length',resolution='resolution',['device-pixel-ratio']='ratio',['aspect-ratio']='ratio'}
local enums={orientation={portrait=true,landscape=true},['prefers-color-scheme']={dark=true,light=true},['prefers-reduced-motion']={reduce=true,['no-preference']=true},pointer={none=true,coarse=true,fine=true},['any-pointer']={none=true,coarse=true,fine=true},hover={none=true,hover=true},['any-hover']={none=true,hover=true},['forced-colors']={none=true,active=true},['inverted-colors']={none=true,inverted=true},['prefers-contrast']={['no-preference']=true,more=true,less=true,custom=true},['prefers-reduced-transparency']={reduce=true,['no-preference']=true},['color-gamut']={srgb=true,p3=true,rec2020=true}}
local booleanForms=table.freeze({['prefers-reduced-motion']='reduce',['prefers-reduced-transparency']='reduce',['forced-colors']='active',['inverted-colors']='inverted',hover='hover',['any-hover']='hover',pointer='!none',['any-pointer']='!none',['prefers-contrast']='!no-preference',['color-gamut']='srgb'})
local enumFields=table.freeze({pointer='pointer',['any-pointer']='anyPointer',hover='hover',['any-hover']='anyHover',['forced-colors']='forcedColors',['inverted-colors']='invertedColors',['prefers-contrast']='contrast',['color-gamut']='colorGamut'})
local enumDefaults=table.freeze({pointer='fine',['any-pointer']='fine',hover='hover',['any-hover']='hover',['forced-colors']='none',['inverted-colors']='none',['prefers-contrast']='no-preference',['color-gamut']='srgb'})
local function measurement(parts,kind)
 if kind=='ratio'and #parts==3 and parts[2]=='/'then
  local a,b=number(parts[1]),number(parts[3]);assert(a and b and a>=0 and b>0,'Razão CSS inválida.');return {number=a/b,unit=''}
 end
 assert(#parts==1,'Valor de consulta inválido: '..table.concat(parts,' '))
 local text=parts[1];local n=number(text);local unit=''
 if not n then local raw,u=text:match('^(.-)(%a+)$');n=raw and number(raw);unit=u or ''end
 assert(n and n>=0,'Valor de consulta deve ser não negativo e finito: '..text)
 if kind=='length'then assert(lengths[unit]or(unit==''and n==0),'Comprimento de consulta exige px/em/rem ou unidade física, não %/cq*.')
 elseif kind=='resolution'then assert(unit=='dpi'or unit=='dpcm'or unit=='dppx'or unit=='x','Resolução exige dpi, dpcm ou dppx.')
 else assert(unit=='','device-pixel-ratio/aspect-ratio exige número ou razão sem unidade.')end
 return {number=n,unit=unit}
end
local comparisons={['<']=true,['<=']=true,['>']=true,['>=']=true,['=']=true}
local reverse={['<']='>',['<=']='>=',['>']='<',['>=']='<=',['=']='='}
local function feature(parts,kind)
 local raw=parts[1];local name=raw;local comparison='='
 if name:sub(1,8)=='-webkit-'then name=name:sub(9)end
 if name:sub(1,4)=='min-'then comparison='>=';name=name:sub(5)
 elseif name:sub(1,4)=='max-'then comparison='<=';name=name:sub(5)end
 if numeric[name]or enums[name]then
  assert(kind~='container'or name=='width'or name=='height'or name=='inline-size'or name=='block-size'or name=='orientation'or name=='aspect-ratio','Feature não suportada em @container: '..raw)
  if #parts==1 then
   assert(comparison=='=','min-/max- exige um valor.')
   local boolean=booleanForms[name]
   if boolean then
    if boolean:sub(1,1)=='!'then return {op='not',item={op='feature',name=name,comparison='=',value=boolean:sub(2)}}end
    return {op='feature',name=name,comparison='=',value=boolean}
   end
   if name=='orientation'then return {op='type',value='all'}end
   assert(numeric[name],'Feature exige um valor: '..name)
   return {op='feature',name=name,comparison='>',value={number=0,unit=numeric[name]=='resolution'and 'dppx'or ''}}
  end
  local separator=parts[2];assert(separator==':'or comparisons[separator],'Esperado : ou comparação na consulta.')
  if separator~=':'then assert(raw==name,'Comparações não usam prefixo min-/max-.');comparison=separator end
  local values={};for i=3,#parts do values[#values+1]=parts[i]end
  if enums[name]then
   assert(raw==name and separator==':'and #values==1 and enums[name][values[1]],'Valor de '..name..' inválido.')
   return {op='feature',name=name,comparison='=',value=values[1]}
  end
  return {op='feature',name=name,comparison=comparison,value=measurement(values,numeric[name])}
 end
 local at
 for i=2,#parts do if numeric[parts[i]]then at=i;break end end
 assert(at and at>=3 and comparisons[parts[at-1]],'Feature de consulta desconhecida: '..table.concat(parts,' '))
 local left={parts[at],reverse[parts[at-1]]};for i=1,at-2 do left[#left+1]=parts[i]end
 local first=feature(left,kind)
 if at==#parts then return first end
 assert(comparisons[parts[at+1]]and parts[at+1]~='='and parts[at-1]~='=','Intervalo de consulta inválido.')
 assert(parts[at-1]:sub(1,1)==parts[at+1]:sub(1,1),'Os dois operadores de intervalo devem ter a mesma direção.')
 local right={};for i=at,#parts do right[#right+1]=parts[i]end
 return {op='and',items={first,feature(right,kind)}}
end
function Q.parse(text,kind)
 kind=kind or 'media';assert(kind=='media'or kind=='container','Tipo de consulta inválido.')
 local styleAtoms={}
 if text:find('style(',1,true)then
  assert(kind=='container','style() existe apenas em @container.')
  text=text:gsub('style%b()',function(chunk)
   assert(#styleAtoms<32,'Máximo de 32 style() por consulta.')
   styleAtoms[#styleAtoms+1]=styleAtom(chunk:sub(7,-2))
   return ' cssstyleatom'..#styleAtoms..' '
  end)
 end
 local tokens=tokenize(text);local p,depth=1,0
 local expression,conjunction,unary
 local function atom()
  local token=tokens[p];assert(token,'Condição CSS incompleta.')
  if token=='('then
   p+=1;depth+=1;assert(depth<=32,'Máximo de 32 níveis por consulta.')
   local result
   if tokens[p]=='('or tokens[p]=='not'or(tokens[p]and tokens[p]:match('^cssstyleatom%d+$'))then result=expression()
   else
    local parts={}
    while tokens[p]and tokens[p]~=')'do
     assert(tokens[p]~='(','Função não suportada em consulta CSS.');parts[#parts+1]=tokens[p];p+=1
    end
    assert(#parts>0,'Condição CSS vazia.');result=feature(parts,kind)
   end
   assert(tokens[p]==')','Consulta CSS não fechada.');p+=1;depth-=1;return result
  end
  local index=token:match('^cssstyleatom(%d+)$')
  if index then p+=1;return assert(styleAtoms[tonumber(index)],'style() inválido na consulta.')end
  assert(kind=='media'and(token=='all'or token=='screen'or token=='print'or token=='speech'),'Esperado (feature: valor) na consulta; recebido '..token)
  p+=1;return {op='type',value=token}
 end
 unary=function()
  if tokens[p]=='not'then p+=1;return {op='not',item=unary()}end
  return atom()
 end
 conjunction=function()
  local result=unary()
  while tokens[p]=='and'do p+=1;result={op='and',items={result,unary()}}end
  return result
 end
 expression=function()
  local result=conjunction()
  while tokens[p]=='or'do p+=1;result={op='or',items={result,conjunction()}}end
  return result
 end
 local queries={}
 repeat
  local negate=false
  if tokens[p]=='only'then assert(kind=='media'and tokens[p+1]~='(','only exige um tipo de mídia.');p+=1
  elseif tokens[p]=='not'and tokens[p+1]and tokens[p+1]~='('and tokens[p+1]~='not'then negate=true;p+=1 end
  local query=expression();queries[#queries+1]=negate and {op='not',item=query}or query
  if tokens[p]~=','then break end;p+=1;assert(tokens[p],'Lista de consultas termina com vírgula.')
 until false
 assert(p>#tokens,'Conteúdo inesperado na consulta: '..tostring(tokens[p]))
 return #queries==1 and queries[1]or {op='or',items=queries}
end
function Q.container(text)
 text=trim(text);local name,body=text:match('^([%a_][%w_%-]*)%s+(.+)$')
 if name and name:lower()~='not'then
  assert(not({none=true,normal=true,['and']=true,['or']=true,only=true,style=true})[name:lower()],'Nome de contêiner reservado.')
  return {kind='container',name=name,query=Q.parse(body,'container')}
 end
 return {kind='container',query=Q.parse(text,'container')}
end
function Q.append(conditions,condition)
 local out=table.clone(conditions or {});assert(#out<32,'Máximo de 32 grupos condicionais aninhados.');out[#out+1]=condition;return out
end
local function required(query,axes)
 if query.op=='feature'then
  local n=query.name
  if n=='width'then axes.x=true elseif n=='height'then axes.y=true
  elseif n=='inline-size'then axes.inline=true elseif n=='block-size'then axes.block=true
  elseif n=='orientation'or n=='aspect-ratio'then axes.x=true;axes.y=true end
 elseif query.item then required(query.item,axes)
 else for _,item in ipairs(query.items or {})do required(item,axes)end end
 return axes
end
local function compare(a,b,op)
 if op=='<'then return a<b elseif op=='>'then return a>b
 elseif op=='<='then return a<=b+1e-7 elseif op=='>='then return a+1e-7>=b end
 return math.abs(a-b)<=1e-7
end
function Q.evaluate(query,context)
 local op=query.op
 if op=='and'then for _,item in ipairs(query.items)do if not Q.evaluate(item,context)then return false end end;return true
 elseif op=='or'then for _,item in ipairs(query.items)do if Q.evaluate(item,context)then return true end end;return false
 elseif op=='not'then return not Q.evaluate(query.item,context)
 elseif op=='type'then return query.value=='all'or query.value==(context.mediaType or 'screen')
 elseif op=='style'then
  local actual
  if query.property:sub(1,2)=='--'then
   local vars=context.vars;if not vars then return false end
   actual=vars[query.property]
  else
   local computed=context.style;if not computed then return false end
   actual=computed[query.property]
  end
  if actual==nil or actual==false then return false end
  local kind=type(actual)
  if kind=='boolean'then actual='true'
  elseif kind~='string'and kind~='number'then return false end
  actual=trim(tostring(actual)):gsub('%s+',' ')
  if query.value==nil then return actual~=''and actual:lower()~='none'end
  local wanted=trim(query.value):gsub('%s+',' ')
  if actual==wanted or actual:lower()==wanted:lower()then return true end
  local a,b=tonumber(actual),tonumber(wanted)
  return a~=nil and b~=nil and math.abs(a-b)<=1e-7
 end
 local name=query.name;local width,height=context.width or 0,context.height or 0
 if name=='orientation'then return query.value==(width>height and 'landscape'or 'portrait')
 elseif name=='prefers-color-scheme'then return query.value==(context.colorScheme or 'light')
 elseif name=='prefers-reduced-motion'then return query.value==(context.reducedMotion and 'reduce'or 'no-preference')
 elseif name=='prefers-reduced-transparency'then return query.value==(context.reducedTransparency and 'reduce'or 'no-preference')
 elseif enumFields[name]then return query.value==(context[enumFields[name]]or enumDefaults[name])end
 local actual
 if name=='width'then actual=width elseif name=='height'then actual=height
 elseif name=='inline-size'then actual=context.vertical and height or width
 elseif name=='block-size'then actual=context.vertical and width or height
 elseif name=='aspect-ratio'then actual=height>0 and width/height or(width>0 and math.huge or 0)
 else actual=context.devicePixelRatio or 1 end
 local value=query.value;local unit=value.unit;local wanted=value.number
 if unit=='em'then wanted*=context.fontSize or context.initialFontSize or 16
 elseif unit=='rem'then wanted*=context.initialFontSize or 16
 elseif unit=='dpi'then wanted/=96 elseif unit=='dpcm'then wanted*=2.54/96
 elseif type(lengths[unit])=='number'then wanted*=lengths[unit]end
 return compare(actual,wanted,query.comparison)
end
function Q.widthBounds(query)
 if query.op=='and'then
  local lo,hi
  for _,item in ipairs(query.items)do local a,b=Q.widthBounds(item);if a then lo=math.max(lo or 0,a)end;if b then hi=math.min(hi or math.huge,b)end end
  return lo,hi
 elseif query.op=='feature'and query.name=='width'and query.value.unit=='px'then
  local c,n=query.comparison,query.value.number
  return (c=='>='or c=='=')and n or nil,(c=='<='or c=='=')and n or nil
 end
end
function Q.hasContainer(rule)
 for _,condition in ipairs(rule.conditions or {})do if condition.kind=='container'then return true end end
 return false
end
function Q.hasContainers(rules)
 for _,rule in ipairs(rules or {})do if Q.hasContainer(rule)then return true end end
 return false
end
function Q.mediaActive(rule,width,height,environment)
 if rule.minWidth and width<rule.minWidth or rule.maxWidth and width>rule.maxWidth then return false end
 local context
 for _,condition in ipairs(rule.conditions or {})do if condition.kind=='media'then
  if not context then context=table.clone(environment or {});context.width=width;context.height=height or width end
  if not Q.evaluate(condition.query,context)then return false end
 end end
 return true
end
local function containerContext(condition,node,parents,snapshot,environment)
 local onlyStyle=styleOnly(condition.query)
 if not snapshot or not snapshot.styles then return nil end
 if not onlyStyle and not snapshot.boxes then return nil end
 local parent=parents[node.key];local axes=condition.name and required(condition.query,{})or nil
 while parent do
  local style=snapshot.styles[parent.key]or {};local box=snapshot.boxes and snapshot.boxes[parent.key]
  local eligible=not condition.name
  if condition.name then
   local named=false;for name in (style['container-name']or ''):gmatch('%S+')do if name==condition.name then named=true;break end end
   if onlyStyle then eligible=named
   else
    local kind=style['container-type'];local vertical=(style['writing-mode']or ''):sub(1,8)=='vertical'
    eligible=named and(kind=='size'or(kind=='inline-size'and not axes.block and not(vertical and axes.x)and not(not vertical and axes.y)))
   end
  end
  if eligible then
   if style.display=='none'then return nil end
   if not onlyStyle and(not box or box.hidden)then return nil end
   local context=table.clone(environment or {});local padding=box and box.p or {}
   if box then
    context.width=math.max(0,box.w-(padding[2]or 0)-(padding[4]or 0));context.height=math.max(0,box.h-(padding[1]or 0)-(padding[3]or 0))
   end
   context.fontSize=style._fontPx or 16;context.vertical=(style['writing-mode']or ''):sub(1,8)=='vertical'
   context.vars=style._vars;context.style=style
   return context
  end
  if not condition.name then break end;parent=parents[parent.key]
 end
 return nil
end
function Q.matches(rule,width,height,environment,node,parents,snapshot)
 if not Q.mediaActive(rule,width,height,environment)then return false end
 for _,condition in ipairs(rule.conditions or {})do if condition.kind=='container'then
  local context=node and containerContext(condition,node,parents,snapshot,environment)
  if not context or not Q.evaluate(condition.query,context)then return false end
 end end
 return true
end
function Q.truthKey(rules,sequence,parents,snapshot,width,height,environment,checkpoint)
 local out={}
 for _,node in ipairs(sequence)do
  if not node.generated then
   out[#out+1]=node.key..':'
   for _,rule in ipairs(rules)do if Q.hasContainer(rule)then out[#out+1]=Q.matches(rule,width,height,environment,node,parents,snapshot)and '1'or '0'end end
  end
  if checkpoint then checkpoint()end
 end
 return table.concat(out)
end
return Q
