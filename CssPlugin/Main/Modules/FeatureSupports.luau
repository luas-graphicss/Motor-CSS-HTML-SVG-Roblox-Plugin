local U=require(script.Parent.Util)
local Selectors=require(script.Parent.Selectors)
local Math=require(script.Parent.MathLength)
local Transform=require(script.Parent.Transform)
local F={VERSION=1};local validators={}
local observers={}
local registered={}
local gates={}
function F.gate(callback)
 assert(type(callback)=='function','Gate de cobertura inválido.')
 gates[#gates+1]=callback
 return function()
  for index,item in ipairs(gates)do if item==callback then table.remove(gates,index);break end end
 end
end
local function gated(property,value,supported)
 if not supported then return false end
 for _,callback in ipairs(gates)do
  local ok,verdict=pcall(callback,property,value)
  if ok and verdict==false then return false end
 end
 return true
end
local function notify(kind,name,value,result)
 for _,callback in ipairs(observers)do pcall(callback,kind,name,value,result)end
end
function F.observe(callback)
 assert(type(callback)=='function','Observador de cobertura inválido.')
 observers[#observers+1]=callback
 return function()
  for index,item in ipairs(observers)do if item==callback then table.remove(observers,index);break end end
 end
end
function F.observers()return #observers end
function F.registered()
 local out={}
 for name in pairs(registered)do out[#out+1]=name end
 table.sort(out);return out
end
local globals={initial=true,inherit=true,unset=true,revert=true,['revert-layer']=true}
local enums={
 display='none block inline inline-block flex grid list-item table inline-table table-row table-cell table-row-group table-header-group table-footer-group table-caption table-column table-column-group ruby ruby-base ruby-text ruby-base-container ruby-text-container',
 ['container-type']='normal size inline-size',['box-sizing']='border-box content-box',
 ['writing-mode']='horizontal-tb vertical-rl vertical-lr sideways-rl sideways-lr',direction='ltr rtl',
 ['overscroll-behavior-x']='auto contain none',['overscroll-behavior-y']='auto contain none',
 ['text-align-last']='auto start end left right center justify',
 position='static relative absolute sticky fixed',
 overflow='visible hidden clip auto scroll paged-x paged-y paged-x-controls paged-y-controls',
 ['overflow-x']='visible hidden clip auto scroll paged-x paged-y paged-x-controls paged-y-controls',
 ['overflow-y']='visible hidden clip auto scroll paged-x paged-y paged-x-controls paged-y-controls',
 ['box-decoration-break']='slice clone',['overscroll-behavior']='auto contain none',
 ['flex-direction']='row row-reverse column column-reverse',['flex-wrap']='nowrap wrap wrap-reverse',
 ['align-items']='normal stretch start end flex-start flex-end center baseline',
 ['align-self']='auto normal stretch start end flex-start flex-end center baseline',
 ['align-content']='normal stretch start end flex-start flex-end center space-between space-around space-evenly',
 ['justify-content']='normal start end flex-start flex-end center space-between space-around space-evenly',
 ['text-align']='left right center justify start end match-parent',['vertical-align']='top middle bottom baseline',
 ['white-space']='normal nowrap pre pre-wrap pre-line break-spaces',['text-overflow']='clip ellipsis',
 ['font-style']='normal italic oblique',['font-weight']='normal bold bolder lighter 100 200 300 400 500 600 700 800 900',
 ['font-kerning']='auto normal none',['text-transform']='none uppercase lowercase capitalize full-width',
 ['word-break']='normal break-all keep-all break-word',['overflow-wrap']='normal anywhere break-word',
 ['hyphens']='none manual auto',['backface-visibility']='visible hidden',
 ['animation-play-state']='running paused',['animation-direction']='normal reverse alternate alternate-reverse',
 ['animation-fill-mode']='none forwards backwards both',['border-style']='none solid',
 ['visibility']='visible hidden collapse',['isolation']='auto isolate',
 ['background-attachment']='scroll fixed local',['background-origin']='border-box padding-box content-box',
 ['background-clip']='border-box padding-box content-box text',
}
for name in pairs(enums)do registered[name]=true end
local function keyword(list,value)return (' '..list..' '):find(' '..value..' ',1,true)~=nil end
local function balanced(text)
 local stack,q,escaped={},nil,false
 for i=1,#text do
  local c=text:sub(i,i)
  if escaped then escaped=false
  elseif c==string.char(92)then escaped=true
  elseif q then if c==q then q=nil end
  elseif c=='"'or c=="'"then q=c
  elseif c=='('or c=='['then stack[#stack+1]=c
  elseif c==')'or c==']'then assert(stack[#stack]==(c==')'and '('or '['),'Consulta desbalanceada.');stack[#stack]=nil
  elseif c=='{'or c=='}'or c==';'then error('Token inesperado na feature query.',0)end
 end
 assert(not q and #stack==0,'Consulta desbalanceada.')
end
local function outer(text)
 if text:sub(1,1)~='('then return false end
 local depth,q,escape=0,nil,false
 for i=1,#text do
  local c=text:sub(i,i)
  if escape then escape=false elseif c==string.char(92)then escape=true
  elseif q then if c==q then q=nil end
  elseif c=='"'or c=="'"then q=c
  elseif c=='('then depth+=1
  elseif c==')'then depth-=1;if depth==0 then return i==#text end end
 end
 return false
end
local function topColon(text)
 local depth,q,escape=0,nil,false
 for i=1,#text do
  local c=text:sub(i,i)
  if escape then escape=false elseif c==string.char(92)then escape=true
  elseif q then if c==q then q=nil end
  elseif c=='"'or c=="'"then q=c
  elseif c=='('or c=='['then depth+=1
  elseif c==')'or c==']'then depth-=1
  elseif c==':'and depth==0 then return i end
 end
 return nil
end
function F.parse(text)
 assert(type(text)=='string'and #text<=8192,'@supports excede 8192 bytes.');balanced(text)
 local parse
 parse=function(input,depth)
  assert(depth<=32,'@supports excede 32 níveis.');input=U.trim(input);assert(input~='','@supports vazio.')
  local nesting,q,escape,start,operator=0,nil,false,1,nil;local pieces={};local i=1
  while i<=#input do
   local c=input:sub(i,i)
   if escape then escape=false elseif c==string.char(92)then escape=true
   elseif q then if c==q then q=nil end
   elseif c=='"'or c=="'"then q=c
   elseif c=='('or c=='['then nesting+=1
   elseif c==')'or c==']'then nesting-=1
   elseif nesting==0 and c:match('%s')then
    local rest=input:sub(i);local word=rest:match('^%s+([%a]+)%s+')
    if word then word=word:lower()end
    if word=='and'or word=='or'then
     assert(not operator or operator==word,'@supports: agrupe and/or com parênteses.')
     operator=word;pieces[#pieces+1]=U.trim(input:sub(start,i-1))
     local whole=rest:match('^%s+[%a]+%s+');i+=#whole;start=i;continue
    end
   end
   i+=1
  end
  if operator then
   pieces[#pieces+1]=U.trim(input:sub(start));local args={}
   for _,piece in ipairs(pieces)do
    assert(not piece:lower():match('^not%s'),'@supports: not em uma combinação exige parênteses.')
    args[#args+1]=parse(piece,depth+1)
   end
   return {op=operator,args=args}
  end
  local notBody=input:match('^[nN][oO][tT]%s+(.+)$')
  if notBody then
   assert(not notBody:lower():match('^not%s'),'not exige uma condição entre parênteses.')
   return {op='not',child=parse(notBody,depth+1)}
  end
  if outer(input)then
   local body=U.trim(input:sub(2,-2));local colon=topColon(body)
   if colon then return {op='declaration',property=U.trim(body:sub(1,colon-1)),value=U.trim(body:sub(colon+1))}end
   if body:match('^[%a_%-][%w_%-]*$')then return {op='unknown',value=body}end
   return parse(body,depth+1)
  end
  local name,body=input:match('^([%a_%-]+)%((.*)%)$')
  assert(name,'Esperado (propriedade: valor) ou selector(...) em @supports.')
  return {op=name:lower()=='selector'and 'selector'or 'unknown',value=body}
 end
 return parse(text,0)
end
local pseudos={root=true,scope=true,empty=true,hover=true,active=true,focus=true,disabled=true,enabled=true,checked=true,valid=true,invalid=true,['read-only']=true,['read-write']=true,target=true,['focus-within']=true,['first-child']=true,['last-child']=true,['only-child']=true,['first-of-type']=true,['last-of-type']=true,['only-of-type']=true,['nth-child']=true,['nth-last-child']=true,['nth-of-type']=true,['nth-last-of-type']=true,['not']=true,is=true,where=true,has=true,before=true,after=true}
function F.selector(text)
 local ok=pcall(function()
  local stripped=text:gsub('%b[]','')
  for name in stripped:gmatch(':([%w_%-]+)')do assert(pseudos[name:lower()],'Pseudo não implementado.')end
  if stripped:find('&',1,true)then
   local nested=require(script.Parent.CssSyntax).nest(text,{':scope'});assert(#nested==1,'selector() exige um seletor complexo, não uma lista.');text=nested[1]
  end
  local selector=Selectors.parse(text)
  local function check(sel)
   for _,part in ipairs(sel.parts)do for _,p in ipairs(part.pseudos or {})do
    if p.selectors then assert(#p.selectors>0,'Lista de seletores sem alternativa válida.');for _,child in ipairs(p.selectors)do check(child)end end
   end end
  end
  check(selector)
 end)
 return ok
end
function F.register(property,validate)
 assert(type(property)=='string'and type(validate)=='function','Registro de feature inválido.');validators[property:lower()]=validate
 registered[property:lower()]=true;notify('register',property:lower())
end
local function length(value,allowNumber,nonNegative)
 local n,d=Math.evaluate(Math.parse(value),{base=200,vw=1000,vh=800,font=16,rootFont=16,anchorPending=true})
 if nonNegative and n<0 then return false end
 return d==1 or d==0 and(allowNumber or n==0)
end
function F.declaration(property,value,hooks)
 if type(property)~='string'or type(value)~='string'then return false end
 property=U.trim(property);value=U.trim(value)
 local ok,result=pcall(function()
  balanced(value)
  assert(property:match('^[%a_%-][%w_%-]*$')and not value:find('!',1,true),'Declaração de consulta inválida.')
  if property:sub(1,2)=='--'then return #property>2 end
  property=property:lower();local lower=value:lower();assert(lower~='','Valor vazio.')
  local Catalog=require(script.Parent.CssPropertyCatalog)
  local entry=hooks.catalog and Catalog.entry(hooks.catalog,property)or nil
  assert(entry~=nil or hooks.supported[property],'Propriedade não implementada.')
  if globals[lower]then return true end
  if validators[property]then return validators[property](value,hooks)==true end
  if value:lower():find('var(',1,true)then hooks.declarations(property..':'..value);require(script.Parent.CssVariables).resolve(value,setmetatable({},{__index=function()return '1px'end}));return true end
  if enums[property]then return keyword(enums[property],lower)end
  if property=='transform'then Transform.parse(value);return true end
  if property=='color'or property:match('color$')or property=='fill'or property=='stroke'then
   if lower=='currentcolor'or lower=='none'and(property=='fill'or property=='stroke')then return true end
   U.color(value);return true
  end
  if property=='background'then
   local colorOk=pcall(U.color,value);if colorOk then return true end
   return false
  end
  if property=='width'or property=='height'or property:match('^min%-')or property:match('^max%-')or property=='flex-basis'or property=='column-width'then
   if keyword('auto none min-content max-content fit-content',lower)then return true end
   return length(value,false)
  end
  if property=='left'or property=='right'or property=='top'or property=='bottom'or property=='font-size'or property=='perspective'or property:match('^padding')or property:match('^margin')or property:match('%-gap$')or property=='gap'or property:match('%-width$')or property:match('%-radius$')or property=='inset'then
   local parts=U.split(value,' ');if #parts<1 or #parts>4 then return false end
   for _,part in ipairs(parts)do
    if part=='auto'and(property=='inset'or property:match('^margin')or keyword('left right top bottom',property))then continue end
    if not length(part,false)then return false end
   end
   return true
  end
  if property=='line-height'or property=='letter-spacing'or property=='word-spacing'then return lower=='normal'or length(value,property=='line-height')end
  if(property:match('^scroll%-padding%-')or property:match('^scroll%-margin%-'))and not hooks.shorthands[property]then
   if lower=='auto'then return property:match('^scroll%-padding')~=nil end
   return length(value,false,property:match('^scroll%-padding')~=nil)
  end
  if property=='opacity'or property=='flex-grow'or property=='flex-shrink'or property=='order'or property=='z-index'then
   if lower=='auto'and property=='z-index'then return true end
   local _,dimension=Math.evaluate(Math.parse(value),{base=1,percentDimension=0});return dimension==0
  end
  if property=='anchor-name'or property=='container-name'or property=='anchor-scope'then
   if lower=='none'or property=='anchor-scope'and lower=='all'then return true end
   local values=U.split(value,' ');for _,v in ipairs(values)do if not v:match(property=='container-name'and '^[%a_%-][%w_%-]*$'or '^%-%-[%w_%-]+$')then return false end end;return #values>0
  end
  if property=='position-anchor'then return lower=='auto'or value:match('^%-%-[%w_%-]+$')~=nil end
  if property=='font-family'then return #U.split(value,',')>0 end
  if property=='content'then require(script.Parent.PseudoElements).content(value,{});return true end
  if hooks.shorthands[property]then hooks.expand(property,value);return true end
  if property:match('^grid%-template%-')or property:match('^grid%-auto%-')and property~='grid-auto-flow'then
   require(script.Parent.LayoutTracks).parse(value,function(token)assert(length(token,false));return token end);return true
  end
  if entry then
   if entry.computed=='color'then U.color(value);return true end
   if entry.computed=='number'then local _,dimension=Math.evaluate(Math.parse(value),{base=1,percentDimension=0});return dimension==0 end
   if entry.computed=='length-percentage'then
    local parts=U.split(value,' ');if #parts<1 or #parts>4 then return false end
    for _,part in ipairs(parts)do if part~='auto'and not length(part,false)then return false end end
    return true
   end
   if entry.computed=='time'then return value:match('^%-?[%d%.]+m?s$')~=nil end
   if entry.kind=='shorthand'and hooks.expand then hooks.expand(property,value);return true end
  end
  return false
 end)
 local supported=gated(property,value,ok and result==true)
 notify('declaration',property,value,supported)
 return supported
end
function F.evaluate(ast,hooks)
 local function eval(node)
  if node.op=='not'then return not eval(node.child)
  elseif node.op=='and'then for _,arg in ipairs(node.args)do if not eval(arg)then return false end end;return true
  elseif node.op=='or'then for _,arg in ipairs(node.args)do if eval(arg)then return true end end;return false
  elseif node.op=='selector'then return F.selector(node.value)
  elseif node.op=='declaration'then return F.declaration(node.property,node.value,hooks)end
  return false
 end
 return eval(ast)
end
return F
