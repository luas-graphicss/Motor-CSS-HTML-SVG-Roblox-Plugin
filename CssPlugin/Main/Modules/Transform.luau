local U=require(script.Parent.Util)
local Math=require(script.Parent.MathLength)
local T={VERSION=1}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<1e8 end
local function identity()return {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}end
T.identity=identity
function T.multiply(a,b)
 local m=table.create(16,0)
 for r=0,3 do for c=1,4 do local v=0;for k=0,3 do v+=a[r*4+k+1]*b[k*4+c]end;assert(finite(v),'Matriz transform fora do limite.');m[r*4+c]=v end end
 return m
end
function T.point(m,x,y,z)
 z=z or 0;local w=m[13]*x+m[14]*y+m[15]*z+m[16]
 if w<=0.00001 then return nil end
 return (m[1]*x+m[2]*y+m[3]*z+m[4])/w,(m[5]*x+m[6]*y+m[7]*z+m[8])/w,(m[9]*x+m[10]*y+m[11]*z+m[12])/w
end
function T.context(style,box,vw,vh)
 local c=style and style._unitContext and table.clone(style._unitContext)or {}
 c.width=box and box.w or 0;c.height=box and box.h or 0;c.vw=vw or c.vw or 1280;c.vh=vh or c.vh or 720
 c.font=style and(style._fontPx or tonumber(style['font-size']))or 16;c.rootFont=style and style._rootFontPx or 16
 return c
end
local function length(text,axis,context,percent)
 assert(percent or not text:find('%%'),'Percentual não permitido no eixo Z/perspective.')
 local ctx=table.clone(context or {});ctx.base=axis=='y'and(ctx.height or 0)or(ctx.width or 0);ctx.property='transform';ctx.axis=axis
 local value=Math.length(text,ctx.base,ctx.vw or 1280,ctx.vh or 720,ctx.font or 16,ctx)
 assert(finite(value),'Comprimento transform inválido.');return value
end
local function cssNumber(text)
 if type(text)~='string'then return nil end
 local value=U.trim(text);local mantissa=value:match('^(.-)[eE][+%-]?%d+$')or value
 if not mantissa:match('^[+%-]?%d*%.?%d+$')then return nil end
 local n=tonumber(value);return finite(n)and n or nil
end
local function number(text)
 local n=cssNumber(text)
 if n==nil then local d;n,d=Math.evaluate(Math.parse(text));assert(d==0,'Número transform não aceita unidade.')end
 assert(finite(n),'Número transform inválido: '..tostring(text));return n
end
local function angle(text)
 text=U.trim(text):lower();if cssNumber(text)==0 then return 0 end
 local radians,dimension=Math.evaluate(Math.parse(text));assert(dimension=='angle','Ângulo exige deg/rad/grad/turn ou função angular.')
 local n=math.deg(radians);assert(finite(n),'Ângulo CSS inválido: '..text)
 assert(math.abs(n)<=360000,'Ângulo CSS fora do limite.');return n
end
local function args(body)
 local parts,start,depth,commas={},1,0,false
 local function push(last)
  local value=U.trim(body:sub(start,last));assert(value~='','Argumento transform vazio.');parts[#parts+1]=value
 end
 for i=1,#body do
  local c=body:sub(i,i)
  if c=='('then depth+=1 elseif c==')'then depth-=1;assert(depth>=0,'Argumentos transform desbalanceados.')
  elseif c==','and depth==0 then push(i-1);start=i+1;commas=true end
 end
 assert(depth==0,'Argumentos transform não fechados.')
 if commas then push(#body);return parts end
 return U.split(body,' ')
end
local function matrix(op)
 local k,v=op.kind,op.values;local m=identity()
 if k=='translate'then m[4],m[8],m[12]=v[1],v[2],v[3]
 elseif k=='scale'then m[1],m[6],m[11]=v[1],v[2],v[3]
 elseif k=='rotatex'then local a=math.rad(v[1]);local c,s=math.cos(a),math.sin(a);m[6],m[7],m[10],m[11]=c,-s,s,c
 elseif k=='rotatey'then local a=math.rad(v[1]);local c,s=math.cos(a),math.sin(a);m[1],m[3],m[9],m[11]=c,s,-s,c
 elseif k=='rotatez'then local a=math.rad(v[1]);local c,s=math.cos(a),math.sin(a);m[1],m[2],m[5],m[6]=c,-s,s,c
 elseif k=='skew'then m[2],m[5]=math.tan(math.rad(v[1])),math.tan(math.rad(v[2]))
 elseif k=='perspective'then m[15]=-v[1]
 elseif k=='matrix'then return table.clone(v)
 end
 return m
end
local function assemble(ops)
 local m=identity();local scale,rotation,simple=1,0,true
 for _,op in ipairs(ops)do
  m=T.multiply(m,matrix(op));local k,v=op.kind,op.values
  if k=='rotatez'then rotation+=v[1]
  elseif k=='scale'and v[1]==v[2]and v[1]>=0 then scale*=v[1]
  elseif k=='translate'and v[3]==0 then
  else simple=false end
 end
 if not simple then scale=math.sqrt(m[1]^2+m[5]^2);rotation=math.deg(math.atan2(m[5],m[1]))end
 return {operations=ops,matrix=m,scale=scale,rotation=rotation,simple=simple}
end
function T.parse(value,context)
 value=U.trim(value or 'none');if value:lower()=='none'then return assemble({})end
 local ops={};local p=1
 while p<=#value do
  while value:sub(p,p):match('%s')do p+=1 end;if p>#value then break end
  local name=value:sub(p):match('^([%a][%w]*)');assert(name,'Função transform inválida: '..value);p+=#name;name=name:lower()
  assert(value:sub(p,p)=='(','transform exige função(...).');local start=p+1;local level=1;p+=1
  while p<=#value and level>0 do local c=value:sub(p,p);if c=='('then level+=1 elseif c==')'then level-=1 end;p+=1 end
  assert(level==0,'transform não fechado.');local a=args(value:sub(start,p-2));local op
  if name=='translate'or name=='translate3d'or name=='translatex'or name=='translatey'or name=='translatez'then
   local x,y,z=0,0,0
   if name=='translate3d'then assert(#a==3,'translate3d exige 3 comprimentos.');x=length(a[1],'x',context,true);y=length(a[2],'y',context,true);z=length(a[3],'z',context,false)
   elseif name=='translate'then assert(#a>=1 and #a<=2,'translate exige 1 ou 2 comprimentos.');x=length(a[1],'x',context,true);y=a[2]and length(a[2],'y',context,true)or 0
   else assert(#a==1,'translateX/Y/Z exige um comprimento.');local v=length(a[1],name:sub(-1),context,name~='translatez');if name=='translatex'then x=v elseif name=='translatey'then y=v else z=v end end
   op={kind='translate',values={x,y,z}}
  elseif name=='scale'or name=='scale3d'or name=='scalex'or name=='scaley'or name=='scalez'then
   local x,y,z=1,1,1
   if name=='scale3d'then assert(#a==3,'scale3d exige 3 números.');x,y,z=number(a[1]),number(a[2]),number(a[3])
   elseif name=='scale'then assert(#a>=1 and #a<=2,'scale exige 1 ou 2 números.');x=number(a[1]);y=a[2]and number(a[2])or x
   else assert(#a==1,'scaleX/Y/Z exige um número.');local v=number(a[1]);if name=='scalex'then x=v elseif name=='scaley'then y=v else z=v end end
   assert(math.max(math.abs(x),math.abs(y),math.abs(z))<=20,'Escalas limitadas a magnitude 20.');op={kind='scale',values={x,y,z}}
  elseif name=='rotate'or name=='rotatex'or name=='rotatey'or name=='rotatez'then
   assert(#a==1,'rotateX/Y/Z exige um ângulo.');op={kind=name=='rotate'and 'rotatez'or name,values={angle(a[1])}}
  elseif name=='skew'or name=='skewx'or name=='skewy'then
   assert(#a>=1 and #a<=(name=='skew'and 2 or 1),'skew exige um ou dois ângulos.');local x,y=angle(a[1]),a[2]and angle(a[2])or 0;if name=='skewy'then x,y=0,x end
   assert(math.abs(math.cos(math.rad(x)))>0.00001 and math.abs(math.cos(math.rad(y)))>0.00001,'skew singular.');op={kind='skew',values={x,y}}
  elseif name=='matrix'or name=='matrix3d'then
   assert(#a==(name=='matrix'and 6 or 16),name..' tem quantidade incorreta de números.');local v={};for i,s in ipairs(a)do v[i]=number(s)end;local m=identity()
   if name=='matrix'then m[1],m[2],m[4],m[5],m[6],m[8]=v[1],v[3],v[5],v[2],v[4],v[6]
   else for r=0,3 do for c=0,3 do m[r*4+c+1]=v[c*4+r+1]end end end
   op={kind='matrix',values=m}
  elseif name=='perspective'then assert(#a==1,'perspective exige distância.');local d=length(a[1],'z',context,false);assert(d>0,'perspective deve ser positiva.');op={kind='perspective',values={1/math.max(d,1)}}
  else error('Transform não suportado: '..name,0)end
  ops[#ops+1]=op;assert(#ops<=32,'Máximo de 32 funções transform.')
 end
 assert(#ops>0,'Transform vazio.');return assemble(ops)
end
function T.build(ops)
 assert(type(ops)=='table'and #ops>0,'Transform vazio.');assert(#ops<=32,'Máximo de 32 funções transform.')
 return assemble(ops)
end
function T.compose(a,b)
 if not a then return b end
 if not b then return a end
 local ops={}
 for _,op in ipairs(a.operations)do ops[#ops+1]=op end
 for _,op in ipairs(b.operations)do ops[#ops+1]=op end
 assert(#ops<=64,'Composição de transform excede 64 funções.')
 return assemble(ops)
end
function T.equal(a,b)
 if not a or not b then return a==b end
 if a.rotation~=b.rotation or a.scale~=b.scale then return false end
 local x,y=a.matrix,b.matrix;if not x or not y then return false end
 for i=1,16 do if x[i]~=y[i]then return false end end;return true
end
local function neutral(op)
 local values={};for i=1,#op.values do values[i]=op.kind=='scale'and 1 or 0 end
 if op.kind=='matrix'then values=identity()end;return {kind=op.kind,values=values}
end
local function affine(m)return m[3]==0 and m[7]==0 and m[9]==0 and m[10]==0 and m[11]==1 and m[12]==0 and m[13]==0 and m[14]==0 and m[15]==0 and m[16]==1 end
local function decompose(m)
 local sx=math.sqrt(m[1]^2+m[5]^2);if sx<1e-8 then return nil end
 return {x=m[4],y=m[8],sx=sx,sy=(m[1]*m[6]-m[2]*m[5])/sx,rotation=math.atan2(m[5],m[1]),shear=(m[1]*m[2]+m[5]*m[6])/(sx*sx)}
end
function T.lerp(a,b,t)
 local ops={};local aa,bb=a.operations,b.operations;local compatible=true
 for i=1,math.max(#aa,#bb)do
  local x,y=aa[i],bb[i];if not x then x=neutral(y)end;if not y then y=neutral(x)end
  if x.kind~=y.kind or x.kind=='matrix'then compatible=false;break end
  local v={};for j=1,#x.values do v[j]=x.values[j]+(y.values[j]-x.values[j])*t end;ops[#ops+1]={kind=x.kind,values=v}
 end
 if compatible then return assemble(ops)end
 local m={};local da=affine(a.matrix)and decompose(a.matrix);local db=affine(b.matrix)and decompose(b.matrix)
 if da and db then
  local angleDelta=(db.rotation-da.rotation+math.pi)%(2*math.pi)-math.pi;local theta=da.rotation+angleDelta*t
  local sx=da.sx+(db.sx-da.sx)*t;local sy=da.sy+(db.sy-da.sy)*t;local sh=da.shear+(db.shear-da.shear)*t;local c,s=math.cos(theta),math.sin(theta)
  m=identity();m[1],m[5]=c*sx,s*sx;m[2],m[6]=c*sh*sx-s*sy,s*sh*sx+c*sy;m[4],m[8]=da.x+(db.x-da.x)*t,da.y+(db.y-da.y)*t
 else for i=1,16 do m[i]=a.matrix[i]+(b.matrix[i]-a.matrix[i])*t end end
 return assemble({{kind='matrix',values=m}})
end
local origins={left='0%',right='100%',top='0%',bottom='100%',center='50%'}
function T.origin(value,context)
 local a=U.split(value or '50% 50%',' ');assert(#a>=1 and #a<=3,'transform-origin exige 1 a 3 valores.')
 for i,v in ipairs(a)do if origins[v:lower()]then a[i]=v:lower()end end
 if #a==1 then if a[1]=='top'or a[1]=='bottom'then a={'50%',a[1]}else a[2]='50%'end end
 if a[1]=='top'or a[1]=='bottom'or a[2]=='left'or a[2]=='right'then a[1],a[2]=a[2],a[1]end
 return length(origins[a[1]]or a[1],'x',context,true),length(origins[a[2]]or a[2],'y',context,true),a[3]and length(a[3],'z',context,false)or 0
end
function T.project(value,context,origin,parent)
 local w,h=context.width,context.height;local ox,oy,oz=T.origin(origin,context)
 local function point(x,y)
  local px,py,pz=T.point(value.matrix,x-ox,y-oy,-oz);if not px then return nil end;px+=ox;py+=oy;pz+=oz
  if parent and parent.distance then
   local divisor=1-pz/parent.distance;if divisor<=0.00001 then return nil end
   px=parent.ox+(px+parent.x-parent.ox)/divisor-parent.x;py=parent.oy+(py+parent.y-parent.oy)/divisor-parent.y
  end
  return px,py
 end
 local cx,cy=point(w/2,h/2);local rx,ry=point(w/2+math.max(w/2,1),h/2);local bx,by=point(w/2,h/2+math.max(h/2,1))
 if not cx or not rx or not bx then return {hidden=true,x=0,y=0,sx=1,sy=1,rotation=0,approximate=true}end
 local ax,ay=(rx-cx)/math.max(w/2,1),(ry-cy)/math.max(w/2,1);local dx,dy=(bx-cx)/math.max(h/2,1),(by-cy)/math.max(h/2,1)
 local sx,sy=math.sqrt(ax*ax+ay*ay),math.sqrt(dx*dx+dy*dy);local determinant=ax*dy-ay*dx
 local similarity=math.abs(ax*dx+ay*dy)<0.00001 and math.abs(sx-sy)<0.00001 and determinant>=0
 local approximate=not similarity or not affine(value.matrix)
 local rotation=value.simple and value.rotation or math.deg(math.atan2(ay,ax))
 return {x=cx-w/2,y=cy-h/2,sx=math.clamp(sx,0,100),sy=math.clamp(sy,0,100),rotation=rotation,approximate=approximate,backFacing=determinant<0,hidden=not finite(cx)or not finite(cy)or sx>100 or sy>100}
end
function T.perspective(style,box,childBox,vw,vh)
 if not style or not style.perspective or U.trim(tostring(style.perspective)):lower()=='none'then return nil end
 local ctx=T.context(style,box,vw,vh);local distance=length(tostring(style.perspective),'z',ctx,false);assert(distance>0,'perspective deve ser positiva.')
 local ox,oy=T.origin(style['perspective-origin'],ctx)
 return {distance=math.max(1,distance),ox=ox,oy=oy,x=childBox.x,y=childBox.y}
end
return T
