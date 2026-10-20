local U=require(script.Parent.Util)
local Math=require(script.Parent.MathLength)
local Svg=require(script.Parent.SvgPath)
local Transform=require(script.Parent.Transform)
local P={VERSION=1,keys={'offset-path','offset-distance','offset-rotate','offset-anchor','offset-position'}}
P.defaults={['offset-path']='none',['offset-distance']='0px',['offset-rotate']='auto',['offset-anchor']='auto',['offset-position']='normal'}
P.shorthand={'offset-path','offset-distance','offset-rotate','offset-anchor'}
P.sizes={['closest-side']=true,['closest-corner']=true,['farthest-side']=true,['farthest-corner']=true,sides=true}
local sample={width=100,height=100,vw=1280,vh=720,font=16,rootFont=16}
local cache,order={},{}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e8 end
local function flatten(d)
 local tokens=Svg.parse(d).tokens
 local points={};local total=0;local x,y,sx,sy=0,0,0,0;local i=1;local started=false
 local function push(px,py,advance)
  assert(finite(px)and finite(py),'Coordenada de offset-path fora do limite.')
  local last=points[#points]
  if last and advance then
   local step=math.sqrt((px-last.x)^2+(py-last.y)^2)
   if step<1e-9 then return end
   total+=step
  end
  points[#points+1]={x=px,y=py,at=total};assert(#points<=8192,'offset-path excede 8192 amostras.')
 end
 local function cubic(a,b,c,e,depth)
  local dx,dy=e.x-a.x,e.y-a.y;local length=math.sqrt(dx*dx+dy*dy);local flat
  if length<1e-7 then flat=math.max(math.abs(b.x-a.x)+math.abs(b.y-a.y),math.abs(c.x-a.x)+math.abs(c.y-a.y))
  else
   local function distance(p)
    local t=math.clamp(((p.x-a.x)*dx+(p.y-a.y)*dy)/(length*length),0,1)
    return math.sqrt((p.x-a.x-t*dx)^2+(p.y-a.y-t*dy)^2)
   end
   flat=math.max(distance(b),distance(c))
  end
  if flat<=0.05 or depth>=10 then push(e.x,e.y,true);return end
  local function mid(p,q)return {x=(p.x+q.x)/2,y=(p.y+q.y)/2}end
  local ab,bc,ce=mid(a,b),mid(b,c),mid(c,e);local abc,bce=mid(ab,bc),mid(bc,ce);local center=mid(abc,bce)
  cubic(a,ab,abc,center,depth+1);cubic(center,bce,ce,e,depth+1)
 end
 local function arc(rx,ry,rotation,large,sweep,ex,ey)
  rx,ry=math.abs(rx),math.abs(ry)
  if rx==0 or ry==0 or math.abs(ex-x)+math.abs(ey-y)<1e-9 then push(ex,ey,true);return end
  local phi=math.rad(rotation%360);local co,si=math.cos(phi),math.sin(phi)
  local dx,dy=(x-ex)/2,(y-ey)/2;local xp,yp=co*dx+si*dy,-si*dx+co*dy
  local lambda=xp*xp/(rx*rx)+yp*yp/(ry*ry);if lambda>1 then local k=math.sqrt(lambda);rx*=k;ry*=k end
  local numerator=math.max(0,rx*rx*ry*ry-rx*rx*yp*yp-ry*ry*xp*xp);local denominator=rx*rx*yp*yp+ry*ry*xp*xp
  local factor=(large==sweep and -1 or 1)*math.sqrt(numerator/math.max(denominator,1e-20))
  local cxp,cyp=factor*rx*yp/ry,-factor*ry*xp/rx
  local cx=co*cxp-si*cyp+(x+ex)/2;local cy=si*cxp+co*cyp+(y+ey)/2
  local a1=math.atan2((yp-cyp)/ry,(xp-cxp)/rx);local a2=math.atan2((-yp-cyp)/ry,(-xp-cxp)/rx);local delta=a2-a1
  if sweep==0 and delta>0 then delta-=2*math.pi elseif sweep==1 and delta<0 then delta+=2*math.pi end
  local steps=math.clamp(math.ceil(math.abs(delta)/0.12),1,512)
  for step=1,steps do
   local a=a1+delta*step/steps;local cosA,sinA=math.cos(a),math.sin(a)
   push(cx+rx*cosA*co-ry*sinA*si,cy+rx*cosA*si+ry*sinA*co,true)
  end
 end
 while i<=#tokens do
  local cmd=tokens[i];i+=1
  if cmd=='M'then x,y=tokens[i],tokens[i+1];i+=2;sx,sy=x,y;started=true;push(x,y,false)
  elseif cmd=='L'then local ex,ey=tokens[i],tokens[i+1];i+=2;push(ex,ey,true);x,y=ex,ey
  elseif cmd=='C'then
   local x1,y1,x2,y2,ex,ey=tokens[i],tokens[i+1],tokens[i+2],tokens[i+3],tokens[i+4],tokens[i+5];i+=6
   cubic({x=x,y=y},{x=x1,y=y1},{x=x2,y=y2},{x=ex,y=ey},0);x,y=ex,ey
  elseif cmd=='Q'then
   local qx,qy,ex,ey=tokens[i],tokens[i+1],tokens[i+2],tokens[i+3];i+=4
   cubic({x=x,y=y},{x=x+2*(qx-x)/3,y=y+2*(qy-y)/3},{x=ex+2*(qx-ex)/3,y=ey+2*(qy-ey)/3},{x=ex,y=ey},0);x,y=ex,ey
  elseif cmd=='A'then
   local rx,ry,rotation,large,sweep,ex,ey=tokens[i],tokens[i+1],tokens[i+2],tokens[i+3],tokens[i+4],tokens[i+5],tokens[i+6];i+=7
   arc(rx,ry,rotation,large,sweep,ex,ey);x,y=ex,ey
  elseif cmd=='Z'then push(sx,sy,true);x,y=sx,sy
  else error('Comando de offset-path não suportado: '..tostring(cmd),0)end
 end
 assert(started and #points>0,'offset-path precisa começar com M.')
 local first,last=points[1],points[#points]
 local closed=#points>2 and math.abs(first.x-last.x)+math.abs(first.y-last.y)<1e-6
 return table.freeze({points=points,total=total,closed=closed})
end
function P.geometry(d)
 assert(type(d)=='string'and d~='','Dados de offset-path vazios.')
 local hit=cache[d];if hit then return hit end
 local result=flatten(d)
 while #order>=64 do local old=table.remove(order,1);if not old then break end;cache[old]=nil end
 cache[d]=result;order[#order+1]=d;return result
end
function P.at(geometry,distance)
 local points=geometry.points;local total=geometry.total
 if #points<2 or total<=0 then return points[1].x,points[1].y,0 end
 local d=geometry.closed and distance%total or math.clamp(distance,0,total)
 local lo,hi=1,#points
 while lo<hi do local mid=math.floor((lo+hi)/2);if points[mid].at<d then lo=mid+1 else hi=mid end end
 local index=math.max(2,lo);local a,b=points[index-1],points[index];local span=b.at-a.at
 local t=span>1e-9 and(d-a.at)/span or 0
 local px,py=a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t
 local dx,dy=b.x-a.x,b.y-a.y
 if math.abs(dx)+math.abs(dy)<1e-9 then
  for j=index+1,#points do local q=points[j];if math.abs(q.x-a.x)+math.abs(q.y-a.y)>1e-9 then dx,dy=q.x-a.x,q.y-a.y;break end end
 end
 if math.abs(dx)+math.abs(dy)<1e-9 then return px,py,0 end
 return px,py,math.deg(math.atan2(dy,dx))
end
local function angleOf(text)
 if tonumber(text)==0 then return 0 end
 local radians,dimension=Math.evaluate(Math.parse(text))
 assert(dimension=='angle','Ângulo CSS exige deg/rad/grad/turn.')
 local degrees=math.deg(radians);assert(finite(degrees)and math.abs(degrees)<=360000,'Ângulo CSS fora do limite.')
 return degrees
end
local function isAngle(text)
 if tonumber(text)==0 then return true end
 local ok,_,dimension=pcall(function()return Math.evaluate(Math.parse(text))end)
 return ok and dimension=='angle'
end
function P.rotate(value)
 local out={auto=false,angle=0};local tokens=U.split(U.trim(tostring(value or 'auto')),' ')
 assert(#tokens>=1 and #tokens<=2,'offset-rotate aceita auto/reverse e/ou um ângulo.')
 local seen={}
 for _,token in ipairs(tokens)do
  local lower=token:lower()
  if lower=='auto'or lower=='reverse'then
   assert(not seen.auto,'Palavra-chave de offset-rotate repetida.');seen.auto=true;out.auto=true
   if lower=='reverse'then out.angle+=180 end
  else
   assert(not seen.angle,'Ângulo de offset-rotate repetido.');seen.angle=true;out.angle+=angleOf(lower)
  end
 end
 assert(seen.auto or seen.angle,'offset-rotate inválido.');return out
end
function P.distance(value,context)
 local text=U.trim(tostring(value or '0px'));assert(text~='','offset-distance vazio.')
 local vw=(context and context.vw)or 1280;local vh=(context and context.vh)or 720;local font=(context and context.font)or 16
 local zero=U.length(text,0,vw,vh,font);local hundred=U.length(text,100,vw,vh,font)
 assert(finite(zero)and finite(hundred),'offset-distance inválido: '..text)
 return {kind='offset-distance',fraction=(hundred-zero)/100,px=zero}
end
function P.same(a,b)
 if a==b then return true end
 if type(a)~='table'or type(b)~='table'then return false end
 return a.kind=='offset-distance'and b.kind=='offset-distance'and a.fraction==b.fraction and a.px==b.px
end
function P.lerp(a,b,t)
 t=math.clamp(t,0,1)
 return {kind='offset-distance',fraction=a.fraction+(b.fraction-a.fraction)*t,px=a.px+(b.px-a.px)*t}
end
function P.parse(value)
 local text=U.trim(tostring(value or 'none'))
 if text==''or text:lower()=='none'then return nil end
 local body=text:match('^[Pp][Aa][Tt][Hh]%((.*)%)$')
 if body then
  body=U.trim(body);local quoted=body:match('^"(.*)"$')or body:match("^'(.*)'$")
  return {kind='path',d=U.trim(quoted or body)}
 end
 body=text:match('^[Rr][Aa][Yy]%((.*)%)$')
 if body then
  local ray={kind='ray',angle=0,size='closest-side',contain=false};local seen={};local tokens=U.split(body,' ');local index=1
  while index<=#tokens do
   local token=tokens[index];local lower=token:lower();index+=1
   if lower=='contain'then assert(not ray.contain,'ray() com contain repetido.');ray.contain=true
   elseif P.sizes[lower]then assert(not seen.size,'Tamanho de ray() repetido.');seen.size=true;ray.size=lower
   elseif lower=='at'then
    local rest={};while index<=#tokens do rest[#rest+1]=tokens[index];index+=1 end
    assert(#rest>=1 and not ray.at,'ray(at ...) exige uma posição.');ray.at=table.concat(rest,' ')
   else assert(not seen.angle,'Ângulo de ray() repetido.');seen.angle=true;ray.angle=angleOf(lower)end
  end
  assert(seen.angle,'ray() exige um ângulo.');return ray
 end
 if text:match('^[Mm][%s%-%+%.%d]')then return {kind='path',d=text}end
 error('offset-path aceita none, path(), ray() ou dados de caminho SVG.',0)
end
function P.expandOffset(value)
 local parts=U.split(value,'/');assert(#parts>=1 and #parts<=2,'offset aceita um único / antes de offset-anchor.')
 local out={['offset-path']='none',['offset-distance']='0px',['offset-rotate']='auto',['offset-anchor']=parts[2]and U.trim(parts[2])or 'auto'}
 local tokens=U.split(parts[1],' ');local seen={};local index=1
 while index<=#tokens do
  local token=tokens[index];local lower=token:lower();index+=1
  if lower=='none'or lower:match('^path%(')or lower:match('^ray%(')or token:match('^[Mm][%s%-%+%.%d]')then
   assert(not seen.path,'offset-path repetido em offset.');seen.path=true;out['offset-path']=token
  elseif lower=='auto'or lower=='reverse'then
   assert(not seen.rotate,'offset-rotate repetido em offset.');seen.rotate=true;out['offset-rotate']=token
   local following=tokens[index]
   if following and isAngle(following:lower())then out['offset-rotate']=token..' '..following;index+=1 end
  elseif isAngle(lower)then assert(not seen.rotate,'offset-rotate repetido em offset.');seen.rotate=true;out['offset-rotate']=token
  else assert(not seen.distance,'offset-distance repetido em offset.');seen.distance=true;out['offset-distance']=token end
 end
 assert(seen.path,'offset exige um offset-path.');return out
end
function P.validate(style)
 local spec=P.parse(style['offset-path'])
 P.rotate(style['offset-rotate'])
 P.distance(style['offset-distance'],sample)
 local anchor=U.trim(tostring(style['offset-anchor']or 'auto'))
 if anchor:lower()~='auto'then Transform.origin(anchor,sample)end
 local place=U.trim(tostring(style['offset-position']or 'normal'))
 if place:lower()~='normal'and place:lower()~='auto'then Transform.origin(place,sample)end
 if spec and spec.kind=='path'then P.geometry(spec.d)end
 if spec and spec.at then Transform.origin(spec.at,sample)end
 return spec~=nil
end
function P.active(style)
 return P.parse(style['offset-path'])~=nil
end
function P.rayLength(spec,px,py,outer,box,ax,ay,dirx,diry)
 local w=math.max(0,outer.w or 0);local h=math.max(0,outer.h or 0);local length
 if spec.size=='sides'then
  length=math.huge
  if dirx>1e-9 then length=math.min(length,(w-px)/dirx)elseif dirx<-1e-9 then length=math.min(length,-px/dirx)end
  if diry>1e-9 then length=math.min(length,(h-py)/diry)elseif diry<-1e-9 then length=math.min(length,-py/diry)end
  if length==math.huge then length=0 end
 elseif spec.size=='closest-side'then length=math.min(math.max(px,0),math.max(py,0),math.max(w-px,0),math.max(h-py,0))
 elseif spec.size=='farthest-side'then length=math.max(px,py,w-px,h-py,0)
 else
  local best=spec.size=='closest-corner'and math.huge or 0
  for _,corner in ipairs({{0,0},{w,0},{0,h},{w,h}})do
   local d=math.sqrt((corner[1]-px)^2+(corner[2]-py)^2)
   best=spec.size=='closest-corner'and math.min(best,d)or math.max(best,d)
  end
  length=best
 end
 if spec.contain then
  local overhang=(dirx>=0 and(box.w-ax)or ax)*math.abs(dirx)+(diry>=0 and(box.h-ay)or ay)*math.abs(diry)
  length=math.max(0,length-overhang)
 end
 assert(finite(length),'ray() fora do limite.');return math.max(0,length)
end
function P.prepare(style,box,context,containing)
 local spec=P.parse(style['offset-path'])
 if not spec then return nil end
 local element=context or {width=box.w,height=box.h,vw=1280,vh=720,font=16}
 local outer={w=(containing and containing.w)or element.width or box.w,h=(containing and containing.h)or element.height or box.h}
 local outerContext=table.clone(element);outerContext.width=outer.w;outerContext.height=outer.h
 local ox,oy=Transform.origin(style['transform-origin'],element)
 local anchor=U.trim(tostring(style['offset-anchor']or 'auto'));local ax,ay=ox,oy
 if anchor:lower()~='auto'then ax,ay=Transform.origin(anchor,element)end
 local place=U.trim(tostring(style['offset-position']or 'normal'));local lower=place:lower();local px,py
 if spec.at then px,py=Transform.origin(spec.at,outerContext)
 elseif lower=='auto'then px,py=box.x+(spec.kind=='ray'and ax or 0),box.y+(spec.kind=='ray'and ay or 0)
 elseif lower=='normal'then
  if spec.kind=='ray'then px,py=outer.w/2,outer.h/2 else px,py=0,0 end
 else px,py=Transform.origin(place,outerContext)end
 local geometry=spec.kind=='path'and P.geometry(spec.d)or nil
 local total=geometry and geometry.total or 0;local dirx,diry=0,0
 if spec.kind=='ray'then
  local radians=math.rad(spec.angle-90);dirx,diry=math.cos(radians),math.sin(radians)
  total=P.rayLength(spec,px,py,outer,box,ax,ay,dirx,diry)
 end
 return {spec=spec,geometry=geometry,total=total,dirx=dirx,diry=diry,px=px,py=py,ax=ax,ay=ay,ox=ox,oy=oy,
  rotate=P.rotate(style['offset-rotate']),distance=P.distance(style['offset-distance'],element),
  box={x=box.x,y=box.y,w=box.w,h=box.h}}
end
function P.transform(prepared,distance)
 local value=distance or prepared.distance
 local d=value.px+value.fraction*prepared.total
 local x,y,tangent
 if prepared.geometry then x,y,tangent=P.at(prepared.geometry,d)
 else
  local at=math.clamp(d,0,prepared.total)
  x,y=prepared.dirx*at,prepared.diry*at;tangent=math.deg(math.atan2(prepared.diry,prepared.dirx))
 end
 local angle=prepared.rotate.angle+(prepared.rotate.auto and tangent or 0)
 local ops={{kind='translate',values={prepared.px+x-prepared.box.x-prepared.ax,prepared.py+y-prepared.box.y-prepared.ay,0}}}
 if math.abs(angle%360)>1e-9 then
  local dx,dy=prepared.ax-prepared.ox,prepared.ay-prepared.oy
  local shifted=math.abs(dx)>1e-9 or math.abs(dy)>1e-9
  if shifted then ops[#ops+1]={kind='translate',values={dx,dy,0}}end
  ops[#ops+1]={kind='rotatez',values={angle}}
  if shifted then ops[#ops+1]={kind='translate',values={-dx,-dy,0}}end
 end
 return Transform.build(ops)
end
function P.compose(prepared,transform,distance)
 if not prepared then return transform end
 return Transform.compose(P.transform(prepared,distance),transform)
end
return P
