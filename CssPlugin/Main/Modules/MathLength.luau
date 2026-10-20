local Units=require(script.Parent.CssValueUnits)
local M={VERSION=4,units=Units.units,unitForDimension=Units.canonical}
local cache,slots={},{};local cursor,hits,misses=0,0,0
local function finite(n)
 assert(type(n)=='number'and n==n and math.abs(n)<math.huge and math.abs(n)<=1e12,'Valor CSS não finito ou fora do limite.');return n
end
local function freeze(node)
 for _,value in pairs(node)do if type(value)=='table'and not table.isfrozen(value)then freeze(value)end end
 return table.isfrozen(node)and node or table.freeze(node)
end
local functions={calc={1,1},min={1,32},max={1,32},clamp={3,3},sin={1,1},cos={1,1},tan={1,1},asin={1,1},acos={1,1},atan={1,1},atan2={2,2},hypot={1,32},sqrt={1,1},pow={2,2},log={1,2},exp={1,1},abs={1,1},sign={1,1},round={1,2},mod={2,2},rem={2,2}}
M.functions=freeze(functions)
local strategies={nearest=true,up=true,down=true,['to-zero']=true}
function M.parse(text)
 assert(type(text)=='string'and #text<=8192,'Expressão CSS deve ter até 8192 caracteres.')
 local cached=cache[text];if cached then hits+=1;return cached end;misses+=1
 local tokens={};local p=1
 while p<=#text do
  local c=text:sub(p,p);local tail=text:sub(p)
  if c:match('%s')then p+=1
  elseif c:match('[%d%.]')then
   local number=tail:match('^%d+%.?%d*')or tail:match('^%.%d+');assert(number,'Número CSS inválido: '..tail:sub(1,24))
   local exponent=tail:sub(#number+1):match('^[eE][%+%-]?%d+');if exponent then number..=exponent end
   p+=#number;local unit=text:sub(p):match('^[%a%%]+')or '';p+=#unit;unit=unit:lower()
   assert(unit==''or Units.units[unit],'Unidade CSS não suportada: '..unit)
   tokens[#tokens+1]={kind='value',value=finite(tonumber(number)),unit=unit}
  elseif c:match('[%a_]')or tail:match('^%-%-[%a_]')then
   local name=tail:match('^[%a_%-][%w_%-]*');tokens[#tokens+1]={kind='name',value=name:sub(1,2)=='--'and name or name:lower()};p+=#name
  elseif c=='+'or c=='-'or c=='*'or c=='/'or c=='('or c==')'or c==','then tokens[#tokens+1]={kind=c};p+=1
  else error('Caractere CSS inválido: '..c,0)end
  assert(#tokens<=1024,'Expressão CSS complexa demais (1024 tokens).')
 end
 assert(#tokens>0,'Expressão CSS vazia.')
 local at=1;local expression,product,primary
 local function peek(kind)return tokens[at]and tokens[at].kind==kind end
 local function expect(kind)assert(peek(kind),'Esperado '..kind..' na expressão CSS.');at+=1 end
 primary=function(depth)
  assert(depth<=64,'Expressão CSS profunda demais (64 níveis).')
  local token=tokens[at];assert(token,'Operando ausente na expressão CSS.')
  if token.kind=='+'or token.kind=='-'then at+=1;return {op='unary',sign=token.kind=='-'and -1 or 1,child=primary(depth+1)}end
  if token.kind=='value'then at+=1;return {op='value',value=token.value,unit=token.unit}end
  if token.kind=='('then at+=1;local node=expression(depth+1);expect(')');return node end
  if token.kind=='name'then
   at+=1;local name=token.value
   if name=='pi'or name=='e'then return {op='value',value=name=='pi'and math.pi or math.exp(1),unit=''}end
   if name=='infinity'or name=='nan'then return {op='nonfinite',name=name}end
   expect('(')
   if name=='anchor'or name=='anchor-size'then
    local node={op=name};local fields=0
    while not peek(')')and not peek(',')do
     local t=tokens[at];assert(t and fields<2,'Argumentos anchor inválidos.');at+=1;fields+=1
     if name=='anchor'and(t.kind=='+'or t.kind=='-')then
      local sign=t.kind=='-'and -1 or 1;t=tokens[at];at+=1
      assert(t and t.kind=='value'and t.unit=='%','Sinal em anchor() exige percentual.');t={kind='value',unit='%',value=t.value*sign}
     end
     if t.kind=='name'and t.value:sub(1,2)=='--'then assert(not node.name,'Âncora repetida.');node.name=t.value
     elseif t.kind=='name'then
      local valid=name=='anchor'and ({left=true,right=true,top=true,bottom=true,center=true,start=true,['end']=true,['self-start']=true,['self-end']=true})or ({width=true,height=true,inline=true,block=true,['self-inline']=true,['self-block']=true})
      assert(valid[t.value]and not node.side and node.percent==nil,'Lado/tamanho anchor inválido.');node.side=t.value
     elseif name=='anchor'and t.kind=='value'and t.unit=='%'then assert(not node.side and node.percent==nil,'Lado anchor repetido.');node.percent=t.value
     else error('Argumento anchor inválido.',0)end
    end
    assert(name=='anchor-size'or node.side or node.percent~=nil,'anchor() exige um lado.')
    if peek(',')then
     at+=1;node.fallback=expression(depth+1)
     local f=node.fallback;while f.op=='unary'do f=f.child end
     if f.op=='value'then local _,d=Units.literal(f.value,f.unit,{});assert(d==1 or d==0 and f.value==0,'Fallback anchor exige comprimento/%.')end
    end
    expect(')');return node
   end
   local arity=functions[name];assert(arity,'Função CSS não suportada: '..name)
   local strategy
   if name=='round'and peek('name')and strategies[tokens[at].value]then strategy=tokens[at].value;at+=1;expect(',')end
   local args={}
   local function argument()
    if name=='clamp'and(#args==0 or #args==2)and peek('name')and tokens[at].value=='none'then at+=1;return {op='none'}end
    return expression(depth+1)
   end
   args[1]=argument()
   while peek(',')do at+=1;args[#args+1]=argument();assert(#args<=32,'Função CSS aceita até 32 argumentos.')end
   expect(')');assert(#args>=arity[1]and #args<=arity[2],name..' com quantidade incorreta de argumentos.')
   if name=='calc'then return args[1]end
   return {op=name,args=args,strategy=strategy}
  end
  error('Operando CSS inválido: '..token.kind,0)
 end
 product=function(depth)
  local left=primary(depth)
  while peek('*')or peek('/')do local op=tokens[at].kind;at+=1;left={op=op,left=left,right=primary(depth)}end
  return left
 end
 expression=function(depth)
  local left=product(depth)
  while peek('+')or peek('-')do local op=tokens[at].kind;at+=1;left={op=op,left=left,right=product(depth)}end
  return left
 end
 local result=expression(0);assert(at>#tokens,'Conteúdo extra na expressão CSS.')
 freeze(result);cursor=cursor%512+1;local old=slots[cursor];if old then cache[old]=nil end
 slots[cursor]=text;cache[text]=result;return result
end
local vectors={[0]={0,0,0,0},[1]={1,0,0,0},angle={0,1,0,0},time={0,0,1,0},frequency={0,0,-1,0},resolution={0,0,0,1}}
local function same(a,b)return a==b or type(a)=='table'and type(b)=='table'and a.key==b.key end
local function compatible(a,ad,b,bd)
 if same(ad,bd)then return ad end
 if ad==0 and a==0 and bd==1 then return bd end
 if bd==0 and b==0 and ad==1 then return ad end
 error('Dimensões CSS incompatíveis para soma/comparação.',0)
end
local function multiplyDimension(a,b,sign)
 if b==0 then return a end
 if a==0 and sign==1 then return b end
 local av=type(a)=='table'and a.vector or vectors[a];local bv=type(b)=='table'and b.vector or vectors[b];local v={}
 for i=1,4 do v[i]=av[i]+sign*bv[i];assert(math.abs(v[i])<=16,'Dimensão CSS composta fora do limite.')end
 for dimension,base in pairs(vectors)do if v[1]==base[1]and v[2]==base[2]and v[3]==base[3]and v[4]==base[4]then return dimension end end
 return {vector=v,key=table.concat(v,',')}
end
function M.evaluate(ast,context)
 local c=type(context)=='number'and {rootFont=context}or context or {}
 local eval
 eval=function(node,depth)
  assert(type(node)=='table'and depth<=1100,'AST CSS inválido ou profundo demais.')
  local op=node.op
  if op=='value'then local n,d=Units.literal(node.value,node.unit,c);return finite(n),d
  elseif op=='nonfinite'then error('Constante CSS não finita não pode ser renderizada.',0)
  elseif op=='anchor'or op=='anchor-size'then
   local n,reason=Units.anchor(node,c)
   if n==nil then
    if node.fallback then local v,d=eval(node.fallback,depth+1);assert(d==1 or d==0 and v==0,'Fallback anchor exige comprimento/%.');return v,1 end
    error(reason,0)
   end
   return finite(n),1
  elseif op=='unary'then local n,d=eval(node.child,depth+1);return finite(n*node.sign),d
  elseif node.args then
   local values,dimensions={},{};local dim,reference
   local compare=op=='min'or op=='max'or op=='clamp'or op=='hypot'or op=='atan2'or op=='round'or op=='mod'or op=='rem'
   for i,child in ipairs(node.args)do
    if child.op=='none'then assert(op=='clamp'and(i==1 or i==3),'none só é permitido nos limites de clamp().');values[i]=i==1 and -math.huge or math.huge
    else
     local n,d=eval(child,depth+1);values[i]=n;dimensions[i]=d
     if compare then if dim==nil then dim=d;reference=n else dim=compatible(reference,dim,n,d);if reference==0 then reference=n end end end
    end
   end
   local a,b=values[1],values[2];local ad=dimensions[1];local n
   if op=='min'or op=='max'then n=a;for i=2,#values do n=op=='min'and math.min(n,values[i])or math.max(n,values[i])end
   elseif op=='clamp'then n=math.max(a,math.min(b,values[3]))
   elseif op=='hypot'then
    local maximum=0;for _,v in ipairs(values)do maximum=math.max(maximum,math.abs(v))end
    local sum=0;if maximum>0 then for _,v in ipairs(values)do sum+=(v/maximum)^2 end end;n=maximum*math.sqrt(sum)
   elseif op=='atan2'then assert(type(dim)~='table','atan2 exige dimensões CSS simples.');n=math.atan2(a,b);dim='angle'
   elseif op=='sin'or op=='cos'or op=='tan'then
    assert(ad==0 or ad=='angle',op..' exige número (radianos) ou ângulo.');dim=0
    if op=='sin'then n=math.sin(a)elseif op=='cos'then n=math.cos(a)else assert(math.abs(math.cos(a))>1e-14,'tan() singular.');n=math.tan(a)end
   elseif op=='asin'or op=='acos'or op=='atan'then
    assert(ad==0,op..' exige número sem unidade.');dim='angle'
    if op=='atan'then n=math.atan(a)else assert(a>=-1 and a<=1,op..' fora do domínio [-1,1].');n=op=='asin'and math.asin(a)or math.acos(a)end
   elseif op=='sqrt'or op=='pow'or op=='log'or op=='exp'then
    for _,d in pairs(dimensions)do assert(d==0,op..' exige números sem unidade.')end;dim=0
    if op=='sqrt'then assert(a>=0,'sqrt() exige número não negativo.');n=math.sqrt(a)
    elseif op=='pow'then n=a^b
    elseif op=='exp'then n=math.exp(a)
    else assert(a>0 and(not b or b>0 and b~=1),'log() fora do domínio.');n=b and math.log(a)/math.log(b)or math.log(a)end
   elseif op=='abs'then n=math.abs(a);dim=ad
   elseif op=='sign'then n=a>0 and 1 or a<0 and -1 or a;dim=0
   elseif op=='round'then
    if b==nil then assert(ad==0,'round() com unidade exige intervalo.');b=1 end
    assert(b>0,'round() exige intervalo positivo.');local ratio=a/b;local strategy=node.strategy or 'nearest'
    local rounded=strategy=='up'and math.ceil(ratio)or strategy=='down'and math.floor(ratio)or strategy=='to-zero'and(ratio<0 and math.ceil(ratio)or math.floor(ratio))or math.floor(ratio+0.5)
    n=rounded*b
   elseif op=='mod'or op=='rem'then
    assert(b~=0,op..' não aceita divisor zero.');local ratio=a/b
    local q=op=='mod'and math.floor(ratio)or(ratio<0 and math.ceil(ratio)or math.floor(ratio));n=a-b*q
   else error('Função matemática CSS desconhecida: '..op,0)end
   return finite(n),dim
  end
  assert(node.left and node.right,'Operador CSS inválido: '..tostring(op))
  local a,ad=eval(node.left,depth+1);local b,bd=eval(node.right,depth+1)
  if op=='+'or op=='-'then return finite(op=='+'and a+b or a-b),compatible(a,ad,b,bd)end
  if op=='*'then return finite(a*b),multiplyDimension(ad,bd,1)end
  assert(op=='/'and b~=0,'Divisão por zero na expressão CSS.');return finite(a/b),multiplyDimension(ad,bd,-1)
 end
 local n,d=eval(ast,0);assert(type(d)~='table','Expressão resulta em dimensão composta, não um valor CSS.');return n,d
end
function M.length(value,base,vw,vh,font,context)
 if value==nil or value=='auto'or value=='none'then return nil end
 if type(value)=='number'then return finite(value)end
 assert(type(value)=='string'or(type(value)=='table'and value.op),'Comprimento CSS inválido.')
 local c=type(context)=='table'and table.clone(context)or(type(context)=='number'and {rootFont=context}or {})
 c.base=base or c.base or 0;c.vw=vw or c.vw or c.base;c.vh=vh or c.vh or c.base;c.font=font or c.font or 16
 local n,d=M.evaluate(type(value)=='table'and value or M.parse(value),c)
 assert(d==0 or d==1,'Esperado comprimento CSS, não '..tostring(d)..'.');return n
end
function M.normalize(value)
 if type(value)~='string'then return value end
 M.parse(value);return (value:gsub('^%s+',''):gsub('%s+$',''))
end
function M.stats()local n=0;for _ in pairs(cache)do n+=1 end;return {entries=n,hits=hits,misses=misses}end
function M.clear()table.clear(cache);table.clear(slots);cursor=0 end
return M
