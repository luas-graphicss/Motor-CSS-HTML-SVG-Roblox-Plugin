local P={};local cached={};local order={};local cachedChars=0
local arity={M=2,L=2,H=1,V=1,C=6,S=4,Q=4,T=2,A=7}
local function tokenize(d)
 local out,p={},1
 while p<=#d do
  local c=d:sub(p,p)
  if c:match('[%s,]')then p+=1
  elseif c:match('[MmLlHhVvCcSsQqTtAaZz]')then out[#out+1]=c;p+=1
  else
   local tail=d:sub(p);local n=tail:match('^[%+%-]?%d+%.?%d*')or tail:match('^[%+%-]?%.%d+')
   assert(n,'Comando/número SVG inválido: '..tail:sub(1,20));local exponent=tail:sub(#n+1):match('^[eE][%+%-]?%d+');if exponent then n..=exponent end
   local value=tonumber(n);assert(value and value==value and math.abs(value)<1e7,'Coordenada SVG fora do limite.');out[#out+1]=value;p+=#n
  end
  assert(#out<=16000,'Path SVG complexo demais.')
 end
 return out
end
function P.parse(d)
 if type(d)=='table'then return d end
 assert(type(d)=='string'and #d<=120000,'Path SVG inválido.')
 if cached[d]then return cached[d]end
 local input=tokenize(d);local result={tokens={},bounds={math.huge,math.huge,-math.huge,-math.huge},hasArc=false,relativeCommands=0}
 local out=result.tokens;local x,y,sx,sy=0,0,0,0;local i,cmd,previous=1,nil,nil;local cx,cy,qx,qy=nil,nil,nil,nil;local started=false
 local function bound(a,b)
  assert(a==a and b==b and math.abs(a)<1e9 and math.abs(b)<1e9,'Coordenada absoluta SVG fora do limite.')
  local box=result.bounds;box[1]=math.min(box[1],a);box[2]=math.min(box[2],b);box[3]=math.max(box[3],a);box[4]=math.max(box[4],b)
 end
 local function emit(command,...)
  out[#out+1]=command;for _,value in ipairs({...})do out[#out+1]=value end
 end
 while i<=#input do
  if type(input[i])=='string'then cmd=input[i];i+=1 end
  assert(cmd,'Número sem comando SVG.');local upper=cmd:upper();local relative=cmd~=upper
  if upper=='Z'then
   assert(started,'Z sem contorno.');emit('Z');x,y=sx,sy;cmd=nil;cx,cy,qx,qy=nil,nil,nil,nil;previous='Z'
  else
   local n=arity[upper];assert(n and i+n-1<=#input,'Parâmetros incompletos do comando '..upper)
   local values={};for j=1,n do assert(type(input[i])=='number','Número esperado em '..upper);values[j]=input[i];i+=1 end
   assert(started or upper=='M','Path precisa começar com M.')
   if relative then result.relativeCommands+=1 end
   local function xy(k)return values[k]+(relative and x or 0),values[k+1]+(relative and y or 0)end
   if previous=='Z'and upper~='M'then emit('M',x,y);sx,sy=x,y end
   local ex,ey;local ncx,ncy,nqx,nqy
   if upper=='M'or upper=='L'then
    ex,ey=xy(1);emit(upper,ex,ey);bound(ex,ey)
    if upper=='M'then started=true;sx,sy=ex,ey;cmd=relative and 'l'or 'L'end
   elseif upper=='H'then ex,ey=values[1]+(relative and x or 0),y;emit('L',ex,ey);bound(ex,ey)
   elseif upper=='V'then ex,ey=x,values[1]+(relative and y or 0);emit('L',ex,ey);bound(ex,ey)
   elseif upper=='C'or upper=='S'then
    local bx,by
    if upper=='C'then bx,by=xy(1);ncx,ncy=xy(3);ex,ey=xy(5)
    else bx,by=x,y;if(previous=='C'or previous=='S')and cx then bx,by=2*x-cx,2*y-cy end;ncx,ncy=xy(1);ex,ey=xy(3)end
    emit('C',bx,by,ncx,ncy,ex,ey);bound(bx,by);bound(ncx,ncy);bound(ex,ey)
   elseif upper=='Q'or upper=='T'then
    if upper=='Q'then nqx,nqy=xy(1);ex,ey=xy(3)
    else nqx,nqy=x,y;if(previous=='Q'or previous=='T')and qx then nqx,nqy=2*x-qx,2*y-qy end;ex,ey=xy(1)end
    emit('Q',nqx,nqy,ex,ey);bound(nqx,nqy);bound(ex,ey)
   elseif upper=='A'then
    assert((values[4]==0 or values[4]==1)and(values[5]==0 or values[5]==1),'Flags do arco precisam ser 0 ou 1, separadas.')
    ex,ey=xy(6);emit('A',math.abs(values[1]),math.abs(values[2]),values[3],values[4],values[5],ex,ey);bound(ex,ey);result.hasArc=true
   end
   x,y=ex,ey;cx,cy,qx,qy=ncx,ncy,nqx,nqy;previous=upper
  end
 end
 table.freeze(result.bounds);table.freeze(result.tokens);table.freeze(result)
 while #order>=128 or cachedChars+#d>500000 do local old=table.remove(order,1);if not old then break end;cached[old]=nil;cachedChars-=#old end
 cached[d]=result;order[#order+1]=d;cachedChars+=#d;return result
end
function P.outside(parsed,m,vb,pad)
 if parsed.hasArc then return false end
 local b=parsed.bounds;if b[1]==math.huge then return true end
 local loX,loY,hiX,hiY=math.huge,math.huge,-math.huge,-math.huge
 for _,p in ipairs({{b[1],b[2]},{b[3],b[2]},{b[3],b[4]},{b[1],b[4]}})do
  local x=m[1]*p[1]+m[3]*p[2]+m[5];local y=m[2]*p[1]+m[4]*p[2]+m[6]
  loX=math.min(loX,x);loY=math.min(loY,y);hiX=math.max(hiX,x);hiY=math.max(hiY,y)
 end
 local px=(pad or 0)*(math.abs(m[1])+math.abs(m[3]));local py=(pad or 0)*(math.abs(m[2])+math.abs(m[4]))
 return hiX+px<vb[1]or hiY+py<vb[2]or loX-px>vb[1]+vb[3]or loY-py>vb[2]+vb[4]
end
local function distance(p,a,b)
 local x,y=b.x-a.x,b.y-a.y;local d=x*x+y*y;local t=d>0 and math.clamp(((p.x-a.x)*x+(p.y-a.y)*y)/d,0,1)or 0
 return(p.x-a.x-t*x)^2+(p.y-a.y-t*y)^2
end
local function chain(points,epsilon)
 if #points<=2 then return points end
 local keep={[1]=true,[#points]=true};local stack={};local work=0;local anchor=1
 for i=2,#points-1 do
  local a,b,c=points[i-1],points[i],points[i+1]
  if(b.x-a.x)*(c.x-b.x)+(b.y-a.y)*(c.y-b.y)<0 then keep[i]=true;stack[#stack+1]={anchor,i};anchor=i end
 end
 stack[#stack+1]={anchor,#points}
 while #stack>0 do
  local range=table.remove(stack);local first,last=range[1],range[2];local best,index=epsilon*epsilon,nil
  for i=first+1,last-1 do
   work+=1;if work>250000 then return points end
   local d=distance(points[i],points[first],points[last]);if d>best then best,index=d,i end
  end
  if index then keep[index]=true;stack[#stack+1]={first,index};stack[#stack+1]={index,last}end
 end
 local result={};for i,p in ipairs(points)do if keep[i]then result[#result+1]=p end end;return result
end
local function area(poly)
 local a=0;for i,p in ipairs(poly)do local q=poly[i%#poly+1];a+=p.x*q.y-q.x*p.y end;return a
end
local function simple(poly)
 if #poly>256 then return false end
 local function cross(a,b,c)return(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)end
 for i=1,#poly do
  local a,b=poly[i],poly[i%#poly+1]
  for j=i+2,#poly do
   if not(i==1 and j==#poly)then
    local c,d=poly[j],poly[j%#poly+1]
    if cross(a,b,c)*cross(a,b,d)<0 and cross(c,d,a)*cross(c,d,b)<0 then return false end
   end
  end
 end
 return true
end
function P.simplify(contours,tolerance)
 local result={};local before,after=0,0
 for _,poly in ipairs(contours)do
  before+=#poly;local out=poly
  local epsilon=#contours>1 and 1e-9 or math.max(0,tolerance)
  if #poly>2 then
   if not poly.closed then out=chain(poly,epsilon)
   else
    local split,furthest=2,0
    for i=2,#poly do local d=(poly[i].x-poly[1].x)^2+(poly[i].y-poly[1].y)^2;if d>furthest then split,furthest=i,d end end
    local left,right={},{};for i=1,split do left[#left+1]=poly[i]end;for i=split,#poly do right[#right+1]=poly[i]end;right[#right+1]=poly[1]
    left,right=chain(left,epsilon),chain(right,epsilon);local candidate={closed=true}
    for i=1,#left-1 do candidate[#candidate+1]=left[i]end;for i=1,#right-1 do candidate[#candidate+1]=right[i]end
    if #candidate>=3 and area(candidate)*area(poly)>0 and simple(candidate)then
     local first,last=poly[1],poly[#poly]
     if first.x==last.x and first.y==last.y then candidate[#candidate+1]=candidate[1]end
     out=candidate
    end
   end
  end
  if out~=poly then out.closed=poly.closed end;result[#result+1]=out;after+=#out
 end
 return result,before,after
end
return P
