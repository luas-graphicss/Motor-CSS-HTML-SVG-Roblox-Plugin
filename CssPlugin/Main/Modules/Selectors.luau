local U=require(script.Parent.Util)
local Form=require(script.Parent.FormState)
local ViewTransitions=require(script.Parent.ViewTransitions)
local X={VERSION=2}
local EMPTY=table.freeze({})
local stateNames={hover=true,active=true,focus=true,['focus-visible']=true,disabled=true,enabled=true,checked=true,valid=true,invalid=true,['read-only']=true,['read-write']=true,target=true,indeterminate=true,autofill=true,['placeholder-shown']=true,['user-valid']=true,['user-invalid']=true,['in-range']=true,['out-of-range']=true}
local simpleNames={root=true,scope=true,empty=true,['first-child']=true,['last-child']=true,['only-child']=true,['first-of-type']=true,['last-of-type']=true,['only-of-type']=true,['focus-within']=true,defined=true,required=true,optional=true,default=true}
local pseudoElements=table.freeze({before=true,after=true,marker=true,placeholder=true,selection=true,['file-selector-button']=true,['first-line']=true,['first-letter']=true})
local documentNames=table.freeze({defined=true,required=true,optional=true,default=true})
local identNames=table.freeze({lang=true,dir=true,state=true})
X.pseudoElements=pseudoElements
X.identNames=identNames
X.stateNames=stateNames
local nthNames={['nth-child']=true,['nth-last-child']=true,['nth-of-type']=true,['nth-last-of-type']=true}
local functional={['not']=true,is=true,where=true,has=true}
local NAMESPACES={html='http://www.w3.org/1999/xhtml',svg='http://www.w3.org/2000/svg',mathml='http://www.w3.org/1998/Math/MathML'}
X.NAMESPACES=NAMESPACES
local function nodeNamespace(node)return NAMESPACES[node.ns or 'html']or NAMESPACES.html end
local function resolveNamespace(prefix,budget,typed)
 local namespaces=budget and budget.namespaces
 if prefix==nil then if typed and namespaces and namespaces['']~=nil then return namespaces['']end;return nil end
 if prefix=='*'then return nil end
 if prefix==''then return''end
 local uri=namespaces and namespaces[prefix]
 assert(uri,'Prefixo de namespace não declarado: '..prefix)
 return uri
end
local function ident(text,p)
 local name=text:sub(p):match('^([%w_%-]+)');assert(name and name~='-','Identificador CSS inválido: '..text);return name,p+#name
end
local function enclosed(text,p,open,close)
 local start=p+1;local level,q,escaped=1,nil,false;p+=1
 while p<=#text do
  local c=text:sub(p,p)
  if q then if escaped then escaped=false elseif c==string.char(92)then escaped=true elseif c==q then q=nil end
  elseif c=='"'or c=="'"then q=c elseif c==open then level+=1 elseif c==close then level-=1;if level==0 then return text:sub(start,p-1),p+1 end end
  p+=1
 end
 error('Delimitador de seletor não fechado: '..text,0)
end
local function list(text)
 local out,start,level,q,escaped={},1,0,nil,false
 for i=1,#text do
  local c=text:sub(i,i)
  if q then if escaped then escaped=false elseif c==string.char(92)then escaped=true elseif c==q then q=nil end
  elseif c=='"'or c=="'"then q=c elseif c=='('or c=='['then level+=1 elseif c==')'or c==']'then level-=1;assert(level>=0,'Seletor desbalanceado.')
  elseif c==','and level==0 then out[#out+1]=U.trim(text:sub(start,i-1));start=i+1 end
 end
 assert(not q and level==0,'Seletor desbalanceado.');out[#out+1]=U.trim(text:sub(start));return out
end
local function tokens(text)
 local out,buffer={},{};local level,q,escaped=0,nil,false
 local function flush()if #buffer>0 then out[#out+1]=table.concat(buffer);table.clear(buffer)end end
 for i=1,#text do
  local c=text:sub(i,i)
  if q then buffer[#buffer+1]=c;if escaped then escaped=false elseif c==string.char(92)then escaped=true elseif c==q then q=nil end
  elseif c=='"'or c=="'"then q=c;buffer[#buffer+1]=c
  elseif c=='('or c=='['then level+=1;buffer[#buffer+1]=c
  elseif c==')'or c==']'then level-=1;assert(level>=0,'Seletor desbalanceado.');buffer[#buffer+1]=c
  elseif level==0 and c:match('%s')then flush()
  elseif level==0 and(c=='>'or c=='+'or c=='~')then flush();out[#out+1]=c
  else buffer[#buffer+1]=c end
 end
 assert(not q and level==0,'Seletor desbalanceado.');flush();return out
end
local function attribute(body,budget)
 body=U.trim(body);local prefix,name,p
 if body:sub(1,1)=='|'then prefix='';name,p=ident(body,2)
 elseif body:sub(1,2)=='*|'then prefix='*';name,p=ident(body,3)
 else
  name,p=ident(body,1)
  if body:sub(p,p)=='|'and body:sub(p+1,p+1)~='='then prefix=name;name,p=ident(body,p+1)end
 end
 name=name:lower();local rest=U.trim(body:sub(p))
 local out={name=name}
 if prefix=='*'then out.nsAny=true
 elseif prefix~=nil and prefix~=''then resolveNamespace(prefix,budget,false);out.name=prefix:lower()..':'..name end
 if rest==''then return out end
 local op=rest:match('^([~|^$*]=)')or rest:match('^(=)');assert(op,'Operador de atributo inválido.')
 rest=U.trim(rest:sub(#op+1));local value,tail
 if rest:sub(1,1)=='"'or rest:sub(1,1)=="'"then
  local quote=rest:sub(1,1);local chars={};local i=2
  while i<=#rest and rest:sub(i,i)~=quote do local c=rest:sub(i,i);if c==string.char(92)then i+=1;c=rest:sub(i,i)end;chars[#chars+1]=c;i+=1 end
  assert(i<=#rest,'Valor de atributo não fechado.');value=table.concat(chars);tail=U.trim(rest:sub(i+1))
 else value,tail=rest:match('^(%S+)%s*(.-)$')end
 assert(value~=nil and(tail==''or tail=='i'or tail=='s'),'Valor/flag de atributo inválido.');out.op=op;out.value=value;out.insensitive=tail=='i';return out
end
function X.nth(expression)
 local s=U.trim(expression):lower():gsub('%s+','')
 if s=='odd'then return 2,1 elseif s=='even'then return 2,0 end
 local integer=tonumber(s);if integer and integer%1==0 then return 0,integer end
 local a,b=s:match('^([+%-]?%d*)n([+%-]?%d*)$');assert(a and(b==''or b:match('^[+%-]%d+$')),'Expressão An+B inválida: '..expression)
 a=(a==''or a=='+')and 1 or a=='-'and -1 or tonumber(a);b=b==''and 0 or tonumber(b)
 assert(a and b and math.abs(a)<=100000 and math.abs(b)<=100000,'An+B fora do limite.');return a,b
end
local parse
local function partOf(text,depth,inHas,budget)
 local part={classes={},states={},pseudos={},attributes={}};local p,specificity=1,0
 local prefix,tag
 local nsPrefix,nsTag=text:match('^([%a_%*][%w_%-]*)|([%a_%*][%w_%-]*)')
 if nsPrefix and text:sub(#nsPrefix+1,#nsPrefix+2)~='|='then prefix=nsPrefix;tag=nsTag;p=#nsPrefix+#nsTag+2
 elseif text:sub(1,1)=='|'then tag=text:match('^|([%a_%*][%w_%-]*)');assert(tag,'Seletor de namespace inválido: '..text);prefix='';p=#tag+2
 else tag=text:match('^([%a_][%w_%-]*)')or text:match('^(%*)');if tag then p=#tag+1 end end
 if tag then part.tag=tag:lower();if tag~='*'then specificity+=1 end end
 local ns=resolveNamespace(prefix,budget,tag~=nil)
 if ns~=nil then part.ns=ns end
 while p<=#text do
  budget.n+=1;assert(budget.n<=256,'Seletor complexo demais.')
  local c=text:sub(p,p)
  if c=='#'or c=='.'then
   local name;name,p=ident(text,p+1)
   if c=='#'then assert(not part.id,'Use apenas um ID por seletor simples.');part.id=name;specificity+=1000000 else part.classes[#part.classes+1]=name;specificity+=1000 end
  elseif c=='['then local body;body,p=enclosed(text,p,'[',']');part.attributes[#part.attributes+1]=attribute(body,budget);specificity+=1000
  elseif c==':'then
   if text:sub(p+1,p+1)==':'then
    local name;name,p=ident(text,p+2);name=name:lower()
    if ViewTransitions.functional[name]then
     assert(text:sub(p,p)=='(','::'..name..' exige argumento.')
     local body;body,p=enclosed(text,p,'(',')');part.pseudoArgument=ViewTransitions.argument(name,body)
    end
    assert(pseudoElements[name]or ViewTransitions.pseudoElements[name],'Pseudo-elemento nao suportado: ::'..name)
    assert(p>#text,'Pseudo-elemento deve encerrar o seletor: ::'..name);part.pseudoElement=name;specificity+=1
   else
    local name;name,p=ident(text,p+1);name=name:lower();local pseudo={name=name}
    if functional[name]or nthNames[name]then
     assert(text:sub(p,p)=='(',':'..name..' exige argumentos.');local body;body,p=enclosed(text,p,'(',')');assert(U.trim(body)~='','Pseudo-classe vazia.')
     if nthNames[name]then
      local formula,of=body:match('^(.-)%s+[oO][fF]%s+(.+)$');formula=formula or body
      assert(not of or(name=='nth-child'or name=='nth-last-child'),'of <selector> só se aplica a nth-child.')
      pseudo.a,pseudo.b=X.nth(formula);specificity+=1000
      if of then pseudo.selectors={};local max=0;for _,item in ipairs(list(of))do local sel=parse(item,depth+1,inHas,budget);assert(not sel.pseudoElement,'Pseudo-elemento não pode ser argumento.');pseudo.selectors[#pseudo.selectors+1]=sel;max=math.max(max,sel.specificity)end;specificity+=max end
     else
      assert(not(name=='has'and inHas),':has() aninhado não é permitido.');pseudo.selectors={};local max=0
      for _,item in ipairs(list(body))do
       local relative=name=='has';local first=relative and U.trim(item):sub(1,1)or nil
       local input=relative and(':scope '..item)or item
       local ok,sel=pcall(parse,input,depth+1,inHas or relative,budget)
       if ok and not sel.pseudoElement then
        if relative then sel.specificity-=1000;sel.relative=(first=='+'or first=='~'or first=='>')and first or ' 'end
        pseudo.selectors[#pseudo.selectors+1]=sel;max=math.max(max,sel.specificity)
       elseif name~='is'and name~='where'then error(ok and 'Pseudo-elementos não podem ser argumentos.'or sel,0)end
      end
      if name~='where'then specificity+=max end
     end
    elseif identNames[name]then
     assert(text:sub(p,p)=='(',':'..name..' exige argumentos.');local body;body,p=enclosed(text,p,'(',')')
     pseudo.idents=X.idents(name,body);specificity+=1000
    else
     assert(stateNames[name]or simpleNames[name],'Pseudo-classe não suportada: '..name);assert(text:sub(p,p)~='(',':'..name..' não aceita argumentos.')
     part.states[#part.states+1]=name;specificity+=1000
    end
    part.pseudos[#part.pseudos+1]=pseudo
   end
  else error('Seletor inválido: '..text,0)end
 end
 assert(tag or #part.classes>0 or part.id or #part.pseudos>0 or #part.attributes>0 or part.pseudoElement,'Seletor simples vazio.')
 return part,specificity
end
function X.idents(name,body)
 local out={}
 for _,item in ipairs(list(body))do
  local value=U.trim(item)
  if value:sub(1,1)=='"'or value:sub(1,1)=="'"then value=U.trim(value:sub(2,#value-1))end
  assert(value~=''and #value<=64 and value:match('^[%w_%-%*]+$'),'Argumento invalido em :'..name..'(): '..item)
  out[#out+1]=value:lower()
 end
 assert(#out>0 and #out<=16,'Numero invalido de argumentos em :'..name..'().')
 if name=='dir'then assert(#out==1 and(out[1]=='ltr'or out[1]=='rtl'),':dir() aceita ltr ou rtl.')end
 if name=='state'then assert(#out==1 and out[1]:match('^[%a_][%w_%-]*$'),':state() aceita um unico identificador.')end
 return out
end
local function inheritedAttr(node,parents,attr)
 local current=node
 while current do
  local value=current.attrs and current.attrs[attr]
  if value~=nil and value~=''then return tostring(value):lower()end
  current=parents[current.key]
 end
 return nil
end
function X.direction(name,idents,node,parents)
 if name=='dir'then return(inheritedAttr(node,parents,'dir')or'ltr')==idents[1]end
 local language=inheritedAttr(node,parents,'lang')
 if not language then return false end
 for _,tag in ipairs(idents)do
  if tag=='*'then return true end
  if tag:sub(1,2)=='*-'then
   if('-'..language..'-'):find('-'..tag:sub(3)..'-',1,true)then return true end
  elseif language==tag or language:sub(1,#tag+1)==tag..'-'then return true end
 end
 return false
end
function X.customState(name,node,state)
 local s=state and state[node.key]
 if s then
  local set=s.customStates
  if type(set)=='table'and set[name]then return true end
 end
 local attr=node.attrs and node.attrs['data-state']
 if attr then for token in tostring(attr):lower():gmatch('[^%s,]+')do if token==name then return true end end end
 return false
end
local function dependencies(sel)
 local out={states={},ids={},complex=false}
 local function walk(s)
  for _,c in ipairs(s.combinators)do if c=='+'or c=='~'then out.complex=true end end
  for _,part in ipairs(s.parts)do
   if part.id then out.ids[part.id]=true end
   if #(part.attributes or EMPTY)>0 then out.complex=true end
   for _,p in ipairs(part.pseudos or EMPTY)do
    local name=p.name
    if stateNames[name]then out.states[name]=true end
    if name=='focus-within'then out.states.focus=true end
    if name=='focus-visible'then out.states.focus=true;out.states['focus-visible']=true end
    if name~='root'and name~='hover'and name~='active'and name~='focus'and name~='focus-visible'and name~='disabled'then out.complex=true end
    for _,child in ipairs(p.selectors or EMPTY)do walk(child)end
   end
  end
 end
 walk(sel);return out
end
parse=function(text,depth,inHas,budget)
 depth=depth or 0;assert(depth<=12,'Seletores funcionais aninhados demais.');budget=budget or {n=0}
 text=U.trim(text);assert(#text>0 and #text<=4096,'Seletor vazio ou longo demais.')
 local pieces=tokens(text);local parts,combinators,score={},{},0;local pending
 for _,item in ipairs(pieces)do
  if item=='>'or item=='+'or item=='~'then assert(#parts>0 and not pending,'Combinador CSS inválido.');pending=item
  else
   assert(#parts<32 and(not parts[#parts]or not parts[#parts].pseudoElement),'Pseudo-elemento deve encerrar o seletor.')
   if #parts>0 then combinators[#parts]=pending or ' 'end
   local part,specificity=partOf(item,depth,inHas,budget);parts[#parts+1]=part;score+=specificity;pending=nil
  end
 end
 assert(#parts>0 and not pending,'Seletor incompleto.')
 local sel={text=text,parts=parts,combinators=combinators,specificity=score};sel.dependencies=dependencies(sel)
 local pseudo=parts[#parts].pseudoElement
 if pseudo then
  sel.pseudoElement=pseudo;sel.ownerSelector={text=text,parts=parts,combinators=combinators,specificity=score-1,dependencies=sel.dependencies}
 end
 return sel
end
X.parse=parse
local function attrMatch(a,node)
 local value=node.attrs[a.name]
 if value==nil and a.nsAny then
  local suffix=':'..a.name
  for key,v in pairs(node.attrs)do if key:sub(-#suffix)==suffix then value=v;break end end
 end
 if value==nil then return false end;if not a.op then return true end
 value=tostring(value);local expected=a.value;if a.insensitive then value=value:lower();expected=expected:lower()end
 if a.op=='='then return value==expected end
 if expected==''then return false end
 if a.op=='~='then return(' '..value:gsub('%s+',' ')..' '):find(' '..expected..' ',1,true)~=nil
 elseif a.op=='|='then return value==expected or value:sub(1,#expected+1)==expected..'-'
 elseif a.op=='^='then return value:sub(1,#expected)==expected
 elseif a.op=='$='then return value:sub(-#expected)==expected
 else return value:find(expected,1,true)~=nil end
end
function X.static(part,node,classSets)
 if node.generated or node.anonymousText then return false end
 if part.tag and part.tag~='*'and part.tag~=node.tag and not(node.aliases and node.aliases[part.tag])then return false end
 if part.ns~=nil and part.ns~=nodeNamespace(node)then return false end
 if part.id and part.id~=node.attrs.id then return false end
 local classes=classSets and classSets[node.key]
 local text=not classes and(' '..(node.attrs.class or ''):gsub('%s+',' ')..' ')
 for _,name in ipairs(part.classes or EMPTY)do if classes then if not classes[name]then return false end elseif not text:find(' '..name..' ',1,true)then return false end end
 for _,a in ipairs(part.attributes or EMPTY)do if not attrMatch(a,node)then return false end end
 return true
end
local function siblings(node,parents)
 local p=parents[node.key];return p and p.children or {node}
end
local function previous(node,parents)
 local before
 for _,n in ipairs(siblings(node,parents))do if n.key==node.key then return before end;if not n.generated and not n.anonymousText then before=n end end
 return nil
end
local matches
local function any(selectors,node,state,parents,classes,scope,ctx)
 for _,sel in ipairs(selectors or EMPTY)do if matches(sel,node,state,parents,classes,scope,ctx)then return true end end;return false
end
local function childIndex(node,parents,ofType,selectors,state,classes,scope,ctx)
 local index,count=0,0
 for _,other in ipairs(siblings(node,parents))do
  if not other.generated and not other.anonymousText and(not ofType or other.tag==node.tag)and(not selectors or any(selectors,other,state,parents,classes,scope,ctx))then
   count+=1;if other.key==node.key then index=count end
  end
 end
 return index,count
end
local function visit(nodes,fn,ctx)
 for _,node in ipairs(nodes)do
  ctx.work+=1;assert(ctx.work<=100000,'Orçamento de correspondência CSS excedido.')
  if not node.generated and not node.anonymousText and(fn(node)or visit(node.children or EMPTY,fn,ctx))then return true end
 end
 return false
end
local function pseudoMatch(p,node,state,parents,classes,scope,ctx)
 local name=p.name;local s=state[node.key]or EMPTY
 if name=='root'then return parents[node.key]==nil
 elseif name=='scope'then return scope and node.key==scope.key or not scope and not parents[node.key]
 elseif name=='hover'or name=='active'or name=='focus'then return s[name]==true
 elseif name=='focus-visible'then return s['focus-visible']==true
 elseif stateNames[name]then return Form.matches(name,node,state)
 elseif documentNames[name]then return name=='defined'or Form.matches(name,node,state)
 elseif name=='lang'or name=='dir'then return X.direction(name,p.idents,node,parents)
 elseif name=='state'then return X.customState(p.idents[1],node,state)
 elseif name=='empty'then return #(node.children or EMPTY)==0 and(node.text or '')==''
 elseif name=='focus-within'then return s.focus==true or visit(node.children or EMPTY,function(n)return state[n.key]and state[n.key].focus==true end,ctx)
 elseif name=='is'or name=='where'then return any(p.selectors,node,state,parents,classes,scope,ctx)
 elseif name=='not'then return not any(p.selectors,node,state,parents,classes,scope,ctx)
 elseif name=='has'then
  for _,sel in ipairs(p.selectors)do
   local candidates=node.children or EMPTY
   if sel.relative=='+'or sel.relative=='~'then
    candidates={};local found=false
    for _,n in ipairs(siblings(node,parents))do if found and not n.generated and not n.anonymousText then candidates[#candidates+1]=n;if sel.relative=='+'then break end end;if n.key==node.key then found=true end end
   end
   if visit(candidates,function(n)return matches(sel,n,state,parents,classes,node,ctx)end,ctx)then return true end
  end
  return false
 else
  local ofType=name:find('of-type',1,true)~=nil
  local i,n=childIndex(node,parents,ofType,p.selectors,state,classes,scope,ctx);if i==0 then return false end
  if name:sub(1,6)=='first-'then return i==1 elseif name:sub(1,5)=='last-'then return i==n elseif name:sub(1,5)=='only-'then return n==1 end
  if name:find('nth-last-',1,true)then i=n-i+1 end
  if p.a==0 then return i==p.b end;local q=(i-p.b)/p.a;return q>=0 and q%1==0
 end
end
matches=function(sel,node,state,parents,classes,scope,ctx)
 if not node or node.generated or node.anonymousText or sel.pseudoElement then return false end
 state=state or EMPTY;parents=parents or EMPTY;ctx=ctx or {work=0};local memo={}
 local function step(index,current)
  if not current then return false end;ctx.work+=1;assert(ctx.work<=100000,'Orçamento de correspondência CSS excedido.')
  local key=index..':'..current.key;if memo[key]~=nil then return memo[key]end
  local part=sel.parts[index];local ok=X.static(part,current,classes)
  if ok then
   if part.pseudos then for _,p in ipairs(part.pseudos)do if not pseudoMatch(p,current,state,parents,classes,scope,ctx)then ok=false;break end end
   else for _,name in ipairs(part.states or EMPTY)do if not pseudoMatch({name=name},current,state,parents,classes,scope,ctx)then ok=false;break end end end
  end
  local result=false
  if ok then
   if index==1 then result=true
   else
    local c=sel.combinators[index-1]
    if c=='>'then result=step(index-1,parents[current.key])
    elseif c=='+'then result=step(index-1,previous(current,parents))
    elseif c=='~'then local n=previous(current,parents);while n do if step(index-1,n)then result=true;break end;n=previous(n,parents)end
    else local up=parents[current.key];while up do if step(index-1,up)then result=true;break end;up=parents[up.key]end end
   end
  end
  memo[key]=result;return result
 end
 return step(#sel.parts,node)
end
X.matches=matches
local scopeRoots
local function scopeRootMatches(scope,candidate,state,parents,classes,ctx)
 local roots=scope.rootSelectors
 if scope.parent then
  local ok=false
  scopeRoots(scope.parent,candidate,state,parents,classes,ctx,function(outerRoot)
   if not roots then ok=candidate.key==outerRoot.key;return ok end
   for _,rootSel in ipairs(roots)do if matches(rootSel,candidate,state,parents,classes,outerRoot,ctx)then ok=true;return true end end
   return false
  end)
  return ok
 end
 if roots then
  for _,rootSel in ipairs(roots)do if matches(rootSel,candidate,state,parents,classes,nil,ctx)then return true end end
  return false
 end
 return parents[candidate.key]==nil
end
local function limitedBy(scope,path,root,state,parents,classes,ctx)
 local limits=scope.limitSelectors
 if not limits then return false end
 for _,between in ipairs(path)do
  for _,limitSel in ipairs(limits)do if matches(limitSel,between,state,parents,classes,root,ctx)then return true end end
 end
 return false
end
scopeRoots=function(scope,node,state,parents,classes,ctx,visitor)
 local path={};local current,hops=node,0
 while current and hops<256 do
  if not current.generated and not current.anonymousText and scopeRootMatches(scope,current,state,parents,classes,ctx)and not limitedBy(scope,path,current,state,parents,classes,ctx)then
   if visitor(current,hops)then return true end
  end
  path[#path+1]=current
  current=parents[current.key];hops+=1
 end
 return false
end
X.scopeRoots=scopeRoots
function X.inScope(scope,node,state,parents,classes,ctx)
 if not scope then return true,nil end
 if not node or node.generated or node.anonymousText then return false,nil end
 local best
 scopeRoots(scope,node,state or EMPTY,parents or EMPTY,classes,ctx or {work=0},function(_,hops)best=hops;return true end)
 return best~=nil,best
end
function X.scoped(scope,sel,node,state,parents,classes,ctx)
 if not scope then return matches(sel,node,state,parents,classes,nil,ctx),nil end
 if not node or node.generated or node.anonymousText then return false,nil end
 parents=parents or EMPTY;ctx=ctx or {work=0}
 local best
 scopeRoots(scope,node,state,parents,classes,ctx,function(root,hops)
  if matches(sel,node,state,parents,classes,root,ctx)then best=hops;return true end
  return false
 end)
 return best~=nil,best
end
function X.statePlan(session)
 local needs={}
 local function inspect(sel)
  for _,part in ipairs(sel.parts)do
   for _,p in ipairs(part.pseudos or EMPTY)do
    local name=p.name=='focus-within'and 'focus'or p.name=='enabled'and 'disabled'or p.name
    if stateNames[name]then
     for _,node in ipairs(session.sequence)do
      if not node.anonymousText and(p.name=='focus-within'or X.static(part,node,session.classes))then needs[node.key]=needs[node.key]or {};needs[node.key][name]=true end
     end
    end
    for _,child in ipairs(p.selectors or EMPTY)do inspect(child)end
   end
  end
 end
 for index,rule in ipairs(session.scope.rules)do if session.active[index]then inspect(rule.selector)end end
 return needs
end
return X
