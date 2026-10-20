local U=require(script.Parent.Util)
local Math=require(script.Parent.MathLength)
local Color=require(script.Parent.CssColor)
local Transform=require(script.Parent.Transform)
local I={VERSION=1}
local LIST_LIMIT=64
local EPSILON=1e-6
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e12 end
local function num(n)assert(finite(n),'Valor CSS interpolado fora do limite.');return n end
local function format(n)
 if math.abs(n)<EPSILON then return '0'end
 return string.format('%.6g',n)
end
local function context(base,percentDimension,ctx)
 local c=type(ctx)=='table'and table.clone(ctx)or{}
 c.base=base;c.vw=c.vw or 1280;c.vh=c.vh or 720;c.font=c.font or 16;c.rootFont=c.rootFont or 16
 if percentDimension~=nil then c.percentDimension=percentDimension end
 return c
end
local function members(text,separator)
 assert(type(text)=='string','Lista CSS inválida.')
 local out,start,depth,quote,escaped={},1,0,nil,false
 local function push(last)
  local item=U.trim(text:sub(start,last));assert(item~='','Lista CSS contém item vazio.')
  out[#out+1]=item;assert(#out<=LIST_LIMIT,'Lista CSS excede 64 itens.')
 end
 for i=1,#text do
  local c=text:sub(i,i)
  if quote then if escaped then escaped=false elseif c==string.char(92)then escaped=true elseif c==quote then quote=nil end
  elseif c=='"'or c=="'"then quote=c
  elseif c=='('or c=='['then depth+=1
  elseif c==')'or c==']'then depth-=1;assert(depth>=0,'Lista CSS desbalanceada.')
  elseif c==separator and depth==0 then push(i-1);start=i+1 end
 end
 assert(not quote and depth==0,'Lista CSS não fechada.');push(#text);return out
end
I.members=members
function I.lengthParts(text,ctx)
 local ast=Math.parse(text)
 local zero,dimension=Math.evaluate(ast,context(0,nil,ctx))
 local hundred,other=Math.evaluate(ast,context(100,nil,ctx))
 assert(dimension==other,'Dimensão CSS inconsistente: '..text)
 assert(dimension==1 or dimension==0,'Esperado comprimento ou percentual: '..text)
 local percent=hundred-zero
 if math.abs(percent)>EPSILON then
  local middle=Math.evaluate(ast,context(50,nil,ctx))
  assert(math.abs(middle-(zero+percent*0.5))<=1e-4*math.max(1,math.abs(middle)),'Percentual dentro de min/max/clamp não é interpolável: '..text)
 end
 return num(zero),num(percent),dimension
end
local transformFunctions=table.freeze({translate=true,translate3d=true,translatex=true,translatey=true,translatez=true,scale=true,scale3d=true,scalex=true,scaley=true,scalez=true,rotate=true,rotatex=true,rotatey=true,rotatez=true,skew=true,skewx=true,skewy=true,matrix=true,matrix3d=true,perspective=true})
local colorFunctions=table.freeze({rgb=true,rgba=true,hsl=true,hsla=true,hwb=true,lab=true,lch=true,oklab=true,oklch=true,color=true,['color-mix']=true,['light-dark']=true})
local mathFunctions=table.freeze({calc=true,min=true,max=true,clamp=true,abs=true,sign=true,round=true,mod=true,rem=true,hypot=true,pow=true,sqrt=true,log=true,exp=true,sin=true,cos=true,tan=true,asin=true,acos=true,atan=true,atan2=true})
I.transformFunctions=transformFunctions
local kinds={}
kinds['<number>']=function(text,ctx)
 assert(not text:find('%%'),'Esperado número sem percentual: '..text)
 local n,d=Math.evaluate(Math.parse(text),context(1,0,ctx));assert(d==0,'Esperado número: '..text)
 return {t='number',v=num(n)}
end
kinds['<integer>']=function(text,ctx)
 local value=kinds['<number>'](text,ctx);assert(value.v%1==0,'Esperado inteiro: '..text)
 return {t='integer',v=value.v}
end
kinds['<percentage>']=function(text,ctx)
 assert(text:find('%%'),'Esperado percentual: '..text)
 local n,d=Math.evaluate(Math.parse(text),context(100,0,ctx));assert(d==0,'Percentual inválido: '..text)
 return {t='percentage',v=num(n)}
end
kinds['<length>']=function(text,ctx)
 local px,percent,d=I.lengthParts(text,ctx)
 assert(math.abs(percent)<=EPSILON,'Percentual não permitido em <length>: '..text)
 assert(d==1 or px==0,'Esperado comprimento: '..text)
 return {t='length',px=px,pct=0}
end
kinds['<length-percentage>']=function(text,ctx)
 local px,percent,d=I.lengthParts(text,ctx)
 assert(d==1 or(px==0 and math.abs(percent)<=EPSILON),'Esperado comprimento ou percentual: '..text)
 return {t='length',px=px,pct=percent}
end
kinds['<angle>']=function(text,ctx)
 if tonumber(text)==0 then return {t='angle',v=0}end
 local n,d=Math.evaluate(Math.parse(text),context(0,nil,ctx));assert(d=='angle','Esperado ângulo: '..text)
 return {t='angle',v=num(math.deg(n))}
end
kinds['<time>']=function(text,ctx)
 if tonumber(text)==0 then return {t='time',v=0}end
 local n,d=Math.evaluate(Math.parse(text),context(0,nil,ctx));assert(d=='time','Esperado tempo: '..text)
 return {t='time',v=num(n)}
end
kinds['<color>']=function(text,ctx)
 return {t='color',v=Color.parse(text,ctx)}
end
kinds['<transform-list>']=function(text,ctx)
 return {t='transform',v=Transform.parse(text,ctx)}
end
kinds['<transform-function>']=function(text,ctx)
 local value=Transform.parse(text,ctx);assert(#value.operations==1,'Esperada uma única função transform: '..text)
 return {t='transform',v=value}
end
kinds['<custom-ident>']=function(text)
 assert(text:match('^%-?[%a_][%w_%-]*$'),'Esperado identificador: '..text)
 local lower=text:lower();assert(lower~='initial'and lower~='inherit'and lower~='unset'and lower~='revert'and lower~='default','Palavra reservada não é <custom-ident>: '..text)
 return {t='keyword',v=text}
end
kinds['<string>']=function(text)
 local quote=text:sub(1,1);assert((quote=='"'or quote=="'")and #text>=2 and text:sub(-1)==quote,'Esperada string CSS: '..text)
 return {t='string',v=text}
end
I.kinds=table.freeze({'<number>','<integer>','<percentage>','<length>','<length-percentage>','<angle>','<time>','<color>','<transform-list>','<transform-function>','<custom-ident>','<string>'})
function I.supports(kind)return kinds[kind]~=nil end
function I.typed(kind,text,ctx)
 local parser=kinds[kind];assert(parser,'Tipo CSS não suportado: '..tostring(kind))
 assert(type(text)=='string','Valor CSS inválido.')
 return parser(U.trim(text),ctx)
end
local function component(text,ctx)
 local lower=text:lower();local fn=lower:match('^([%a%-][%w%-]*)%(')
 if fn and transformFunctions[fn]then return I.typed('<transform-list>',text,ctx)end
 if lower=='none'then return {t='keyword',v='none'}end
 if(fn and colorFunctions[fn])or text:sub(1,1)=='#'or lower=='currentcolor'or lower=='transparent'then return I.typed('<color>',text,ctx)end
 local first=text:sub(1,1)
 if first=='"'or first=="'"then return {t='string',v=text}end
 if first:match('[%d%.%+%-]')or(fn and mathFunctions[fn])then
  for _,kind in ipairs({'<length-percentage>','<angle>','<time>','<number>'})do
   local ok,value=pcall(I.typed,kind,text,ctx);if ok then return value end
  end
 end
 local ok,value=pcall(I.typed,'<color>',text,ctx);if ok then return value end
 if fn and text:sub(-1)==')'then
  local inner=text:sub(#fn+2,-2)
  if U.trim(inner)==''then return {t='fn',name=fn,args={t='list',sep=' ',items={}}}end
  local okArgs,args=pcall(I.parse,inner,ctx)
  if okArgs then
   if args.t~='list'then args={t='list',sep=' ',items={args}}end
   return {t='fn',name=fn,args=args}
  end
 end
 assert(#text<=256,'Componente CSS longo demais.')
 return {t='keyword',v=text}
end
I.component=component
function I.parse(text,ctx)
 assert(type(text)=='string','Valor CSS inválido.')
 text=U.trim(text);assert(text~=''and #text<=8192,'Valor CSS vazio ou maior que 8192 bytes.')
 local commas=members(text,',')
 if #commas>1 then
  local items={};for i,item in ipairs(commas)do items[i]=I.parse(item,ctx)end
  return {t='list',sep=',',items=items}
 end
 local fn=text:lower():match('^([%a%-][%w%-]*)%(')
 if fn and transformFunctions[fn]then return I.typed('<transform-list>',text,ctx)end
 local words=U.split(text,' ')
 if #words>1 then
  local items={};for i,item in ipairs(words)do items[i]=component(item,ctx)end
  assert(#items<=LIST_LIMIT,'Valor composto excede 64 componentes.')
  return {t='list',sep=' ',items=items}
 end
 return component(text,ctx)
end
local function serializeOperations(operations)
 if #operations==0 then return 'none'end
 local out={}
 for _,op in ipairs(operations)do
  local v=op.values
  if op.kind=='translate'then out[#out+1]='translate3d('..format(v[1])..'px, '..format(v[2])..'px, '..format(v[3])..'px)'
  elseif op.kind=='scale'then out[#out+1]='scale3d('..format(v[1])..', '..format(v[2])..', '..format(v[3])..')'
  elseif op.kind=='rotatex'then out[#out+1]='rotateX('..format(v[1])..'deg)'
  elseif op.kind=='rotatey'then out[#out+1]='rotateY('..format(v[1])..'deg)'
  elseif op.kind=='rotatez'then out[#out+1]='rotateZ('..format(v[1])..'deg)'
  elseif op.kind=='skew'then out[#out+1]='skew('..format(v[1])..'deg, '..format(v[2])..'deg)'
  elseif op.kind=='perspective'then out[#out+1]='perspective('..format(math.abs(v[1])>EPSILON and 1/v[1] or 1e7)..'px)'
  else
   local parts={}
   for c=0,3 do for r=0,3 do parts[#parts+1]=format(op.values[r*4+c+1])end end
   out[#out+1]='matrix3d('..table.concat(parts,', ')..')'
  end
 end
 return table.concat(out,' ')
end
function I.serializeTransform(value)return serializeOperations(value.operations)end
function I.serialize(value)
 assert(type(value)=='table'and value.t,'Valor tipado inválido.')
 local kind=value.t
 if kind=='number'then return format(value.v)end
 if kind=='integer'then return tostring(math.round(value.v))end
 if kind=='percentage'then return format(value.v)..'%'end
 if kind=='angle'then return format(value.v)..'deg'end
 if kind=='time'then return format(value.v)..'s'end
 if kind=='length'then
  if math.abs(value.pct)<=EPSILON then return format(value.px)..'px'end
  if math.abs(value.px)<=EPSILON then return format(value.pct)..'%'end
  local sign=value.pct<0 and ' - 'or ' + '
  return 'calc('..format(value.px)..'px'..sign..format(math.abs(value.pct))..'%)'
 end
 if kind=='color'then return Color.serialize(value.v)end
 if kind=='transform'then return serializeOperations(value.v.operations)end
 if kind=='keyword'or kind=='string'then return value.v end
 if kind=='fn'then return value.name..'('..I.serialize(value.args)..')'end
 if kind=='list'then
  local out={};for i,item in ipairs(value.items)do out[i]=I.serialize(item)end
  return table.concat(out,value.sep==','and ', 'or ' ')
 end
 error('Tipo interpolado desconhecido: '..tostring(kind),0)
end
local function sameShape(a,b)
 if type(a)~='table'or type(b)~='table'or a.t~=b.t then return false end
 if a.t=='keyword'or a.t=='string'then return false end
 if a.t=='fn'then return a.name==b.name and sameShape(a.args,b.args)end
 if a.t=='list'then
  if a.sep~=b.sep or #a.items~=#b.items then return false end
  for i=1,#a.items do if not sameShape(a.items[i],b.items[i])then return false end end
  return true
 end
 return true
end
I.sameShape=sameShape
function I.discrete(a,b,t)return t<0.5 and a or b end
function I.interpolate(a,b,t,options)
 assert(type(a)=='table'and type(b)=='table','Interpolação exige valores tipados.')
 assert(finite(t),'Progresso de interpolação inválido.')
 if not sameShape(a,b)then return I.discrete(a,b,t)end
 local kind=a.t
 if kind=='number'or kind=='percentage'or kind=='angle'or kind=='time'then return {t=kind,v=num(a.v+(b.v-a.v)*t)}end
 if kind=='integer'then return {t=kind,v=math.round(a.v+(b.v-a.v)*t)}end
 if kind=='length'then return {t='length',px=num(a.px+(b.px-a.px)*t),pct=num(a.pct+(b.pct-a.pct)*t)}end
 if kind=='color'then
  local weight=math.clamp(t,0,1);local space=options and options.colorSpace or'oklab'
  return {t='color',v=Color.mix(a.v,b.v,space,1-weight,weight,options and options.hue or'shorter')}
 end
 if kind=='transform'then return {t='transform',v=Transform.lerp(a.v,b.v,t)}end
 if kind=='fn'then return {t='fn',name=a.name,args=I.interpolate(a.args,b.args,t,options)}end
 if kind=='list'then
  local items={};for i=1,#a.items do items[i]=I.interpolate(a.items[i],b.items[i],t,options)end
  return {t='list',sep=a.sep,items=items}
 end
 return I.discrete(a,b,t)
end
function I.composeTransform(a,b,mode)
 if mode=='accumulate'and #a.operations==#b.operations and #a.operations>0 then
  local compatible=true
  for i,x in ipairs(a.operations)do
   local y=b.operations[i]
   if x.kind~=y.kind or x.kind=='matrix'then compatible=false;break end
  end
  if compatible then
   local operations={}
   for i,x in ipairs(a.operations)do
    local y=b.operations[i];local values={}
    for j=1,#x.values do
     values[j]=x.kind=='scale'and(x.values[j]+y.values[j]-1)or(x.values[j]+y.values[j])
    end
    operations[#operations+1]={kind=x.kind,values=values}
   end
   return Transform.parse(serializeOperations(operations))
  end
 end
 local left,right=serializeOperations(a.operations),serializeOperations(b.operations)
 if left=='none'then return Transform.parse(right)end
 if right=='none'then return Transform.parse(left)end
 return Transform.parse(left..' '..right)
end
local function combine(a,b,mode)
 if not sameShape(a,b)then return b end
 local kind=a.t
 if kind=='number'or kind=='percentage'or kind=='angle'or kind=='time'then return {t=kind,v=num(a.v+b.v)}end
 if kind=='integer'then return {t=kind,v=math.round(a.v+b.v)}end
 if kind=='length'then return {t='length',px=num(a.px+b.px),pct=num(a.pct+b.pct)}end
 if kind=='transform'then return {t='transform',v=I.composeTransform(a.v,b.v,mode)}end
 if kind=='fn'then return {t='fn',name=a.name,args=combine(a.args,b.args,mode)}end
 if kind=='list'then
  local items={};for i=1,#a.items do items[i]=combine(a.items[i],b.items[i],mode)end
  return {t='list',sep=a.sep,items=items}
 end
 return b
end
function I.add(a,b)return combine(a,b,'add')end
function I.accumulate(a,b)return combine(a,b,'accumulate')end
function I.compose(mode,underlying,value)
 if mode=='add'then return combine(underlying,value,'add')end
 if mode=='accumulate'then return combine(underlying,value,'accumulate')end
 assert(mode==nil or mode=='replace','animation-composition aceita replace, add ou accumulate.')
 return value
end
function I.equal(a,b)
 if a==b then return true end
 if type(a)~='table'or type(b)~='table'or a.t~=b.t then return false end
 if a.t=='transform'then return Transform.equal(a.v,b.v)end
 if a.t=='fn'then return a.name==b.name and I.equal(a.args,b.args)end
 if a.t=='list'then
  if a.sep~=b.sep or #a.items~=#b.items then return false end
  for i=1,#a.items do if not I.equal(a.items[i],b.items[i])then return false end end
  return true
 end
 local ok,left=pcall(I.serialize,a);local okB,right=pcall(I.serialize,b)
 return ok and okB and left==right
end
return I
