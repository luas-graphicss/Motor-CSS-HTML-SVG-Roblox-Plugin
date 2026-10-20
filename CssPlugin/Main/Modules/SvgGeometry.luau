local U=require(script.Parent.Util)
local G={I={1,0,0,1,0,0}}
function G.mul(a,b)return {a[1]*b[1]+a[3]*b[2],a[2]*b[1]+a[4]*b[2],a[1]*b[3]+a[3]*b[4],a[2]*b[3]+a[4]*b[4],a[1]*b[5]+a[3]*b[6]+a[5],a[2]*b[5]+a[4]*b[6]+a[6]}end
function G.at(m,x,y)return m[1]*x+m[3]*y+m[5],m[2]*x+m[4]*y+m[6]end
function G.inverse(m)
 local d=m[1]*m[4]-m[2]*m[3];if math.abs(d)<1e-12 then return nil end
 return {m[4]/d,-m[2]/d,-m[3]/d,m[1]/d,(m[3]*m[6]-m[4]*m[5])/d,(m[2]*m[5]-m[1]*m[6])/d}
end
function G.number(text,default,base)
 if text==nil then return default or 0 end
 text=U.trim(tostring(text));local pct=text:sub(-1)=='%'
 if pct then text=text:sub(1,-2)else text=text:gsub('px$','')end
 local n=tonumber(text);assert(n and n==n and math.abs(n)<=1e7,'Comprimento SVG inválido: '..tostring(text))
 return pct and n*(base or 1)/100 or n
end
function G.opacity(value,default)return math.clamp(G.number(value,default or 1,1),0,1)end
function G.transform(text,legacy)
 if not text or text=='none'then return G.I end
 return legacy.transform((text:gsub('([%d%.])px','%1'):gsub('([%d%.])deg','%1')))
end
function G.box(contours,m)
 local b={x=math.huge,y=math.huge,right=-math.huge,bottom=-math.huge}
 for _,poly in ipairs(contours)do for _,p in ipairs(poly)do local x,y=G.at(m or G.I,p.x,p.y);b.x=math.min(b.x,x);b.y=math.min(b.y,y);b.right=math.max(b.right,x);b.bottom=math.max(b.bottom,y)end end
 if b.x==math.huge then b.x,b.y,b.right,b.bottom=0,0,0,0 end;b.w=b.right-b.x;b.h=b.bottom-b.y;return b
end
function G.union(a,b)
 if not a then return table.clone(b)end
 a.x=math.min(a.x,b.x);a.y=math.min(a.y,b.y);a.right=math.max(a.right,b.right);a.bottom=math.max(a.bottom,b.bottom);a.w=a.right-a.x;a.h=a.bottom-a.y;return a
end
function G.bboxMatrix(b)return {b.w,0,0,b.h,b.x,b.y}end
function G.rect(x,y,w,h)return {{{x=x,y=y},{x=x+w,y=y},{x=x+w,y=y+h},{x=x,y=y+h},closed=true}}end
function G.shape(node,legacy,tolerance,vb)
 local a=node.attrs;local tag=node.tag;local diagonal=math.sqrt((vb[3]^2+vb[4]^2)/2)
 local function n(k,d)local base=({x=true,x1=true,x2=true,cx=true,width=true,rx=true})[k]and vb[3]or({y=true,y1=true,y2=true,cy=true,height=true,ry=true})[k]and vb[4]or diagonal;return G.number(a[k],d,base)end
 if tag=='path'then return legacy.paths(a.d or '',tolerance)
 elseif tag=='rect'then
  local x,y,w,h=n('x'),n('y'),n('width'),n('height');assert(w>=0 and h>=0,'Retângulo SVG negativo.');if w==0 or h==0 then return {}end
  local rx=math.min(n('rx',n('ry')),w/2);local ry=math.min(n('ry',rx),h/2);assert(rx>=0 and ry>=0,'Raio SVG negativo.')
  if rx>0 and ry>0 then
   return legacy.paths(string.format('M %g %g H %g A %g %g 0 0 1 %g %g V %g A %g %g 0 0 1 %g %g H %g A %g %g 0 0 1 %g %g V %g A %g %g 0 0 1 %g %g Z',x+rx,y,x+w-rx,rx,ry,x+w,y+ry,y+h-ry,rx,ry,x+w-rx,y+h,x+rx,rx,ry,x,y+h-ry,y+ry,rx,ry,x+rx,y),tolerance)
  end;return G.rect(x,y,w,h)
 elseif tag=='circle'or tag=='ellipse'then
  local rx=tag=='circle'and n('r')or n('rx');local ry=tag=='circle'and rx or n('ry');assert(rx>=0 and ry>=0,'Raio SVG negativo.');if rx==0 or ry==0 then return {}end
  return {legacy.circle(n('cx'),n('cy'),rx,ry,tolerance)}
 elseif tag=='line'then return {{{x=n('x1'),y=n('y1')},{x=n('x2'),y=n('y2')}}}
 elseif tag=='polygon'or tag=='polyline'then
  local ns=U.numbers(a.points or '');assert(#ns%2==0,'points exige pares x,y.');local p={closed=tag=='polygon'}
  for i=1,#ns,2 do p[#p+1]={x=ns[i],y=ns[i+1]}end;return {p}
 end
 error('Forma SVG não suportada: '..tag,0)
end
function G.length(contours)
 local length=0
 for _,p in ipairs(contours)do for i=1,#p-(p.closed and 0 or 1)do local a,b=p[i],p[i%#p+1];length+=math.sqrt((b.x-a.x)^2+(b.y-a.y)^2)end end;return length
end
function G.dashes(contours,value,offset,base,pathLength)
 if not value or value=='none'then return contours end
 local values=U.split(value:gsub(',',' '),' ');assert(#values>0 and #values<=128,'stroke-dasharray exige 1 a 128 comprimentos.')
 local factor=1;if pathLength then local n=G.number(pathLength);assert(n>0,'pathLength deve ser positivo.');factor=G.length(contours)/n end
 local dash,sum={},0
 for _,v in ipairs(values)do local n=G.number(v,0,base)*factor;assert(n>=0,'stroke-dasharray não aceita valores negativos.');dash[#dash+1]=n;sum+=n end
 if sum<=1e-12 then return contours end
 if #dash%2==1 then local n=#dash;for i=1,n do dash[#dash+1]=dash[i]end;sum*=2 end
 local phase=G.number(offset,0,base)*factor;local result={};local work=0
 for _,p in ipairs(contours)do
  if #p==0 then continue end
  local index,skip=1,phase%sum
  while dash[index]==0 or skip>=dash[index]do if dash[index]>0 then skip-=dash[index]end;index=index%#dash+1 end
  local remain=dash[index]-skip;local active;local startIndex=#result+1
  local function at(a,b,d,len)return {x=a.x+(b.x-a.x)*d/len,y=a.y+(b.y-a.y)*d/len}end
  if phase%sum==0 and dash[1]==0 then result[#result+1]={{x=p[1].x,y=p[1].y},{x=p[1].x,y=p[1].y}}end
  for i=1,#p-(p.closed and 0 or 1)do
   local a,b=p[i],p[i%#p+1];local len=math.sqrt((b.x-a.x)^2+(b.y-a.y)^2);local distance=0
   while distance<len-1e-9 do
    work+=1;assert(work<=16384,'Tracejado SVG excede 16384 segmentos.')
    local step=math.min(remain,len-distance)
    if index%2==1 then if not active then active={at(a,b,distance,len)};result[#result+1]=active end;active[#active+1]=at(a,b,distance+step,len)end
    distance+=step;remain-=step
    if remain<=1e-9 then
     active=nil;index=index%#dash+1
     while dash[index]==0 do
      if index%2==1 then local dot=at(a,b,distance,len);result[#result+1]={dot,{x=dot.x,y=dot.y}}end
      index=index%#dash+1
     end;remain=dash[index]
    end
   end
  end
  if p.closed and #result>=startIndex then
   local first,last=result[startIndex],result[#result];local a,b=first[1],last[#last]
   if #result>startIndex and math.abs(a.x-b.x)+math.abs(a.y-b.y)<1e-7 then
    local joined={};for _,q in ipairs(last)do joined[#joined+1]=q end;for i=2,#first do joined[#joined+1]=first[i]end
    result[startIndex]=joined;table.remove(result)
   end
  end
 end;return result
end
function G.coverage(contours,m,rule,c)
 assert(rule=='nonzero'or rule=='evenodd','fill-rule/clip-rule deve ser nonzero ou evenodd.')
 local edges={};local loY,hiY=math.huge,-math.huge
 for _,p in ipairs(contours)do if #p>=3 then for i,a in ipairs(p)do
  local b=p[i%#p+1];local ax,ay=G.at(m,a.x,a.y);local bx,by=G.at(m,b.x,b.y)
  ax=(ax-c.vb[1])*c.sx+c.pad;ay=(ay-c.vb[2])*c.sy+c.pad;bx=(bx-c.vb[1])*c.sx+c.pad;by=(by-c.vb[2])*c.sy+c.pad
  assert(ax==ax and ay==ay and bx==bx and by==by and math.max(math.abs(ax),math.abs(ay),math.abs(bx),math.abs(by))<1e10,'Transformação SVG fora do limite.')
  loY=math.min(loY,ay,by);hiY=math.max(hiY,ay,by)
  if math.abs(ay-by)>1e-12 then edges[#edges+1]={ax=ax,ay=ay,bx=bx,by=by,w=by>ay and 1 or -1}end
 end end end
 assert(#edges<=24000,'SVG excede 24000 arestas por camada.')
 local alpha=table.create(c.w*c.h,0)
 for y=math.max(0,math.floor(loY)),math.min(c.h-1,math.ceil(hiY)-1)do
  for sub=0,1 do
   local scan=y+.25+sub*.5;local crosses={}
   for _,e in ipairs(edges)do if scan>=math.min(e.ay,e.by)and scan<math.max(e.ay,e.by)then crosses[#crosses+1]={x=e.ax+(scan-e.ay)*(e.bx-e.ax)/(e.by-e.ay),w=e.w}end end
   table.sort(crosses,function(a,b)return a.x<b.x end)
   local winding,start=0,nil
   for _,p in ipairs(crosses)do
    local was=rule=='evenodd'and winding%2~=0 or rule=='nonzero'and winding~=0
    winding+=rule=='evenodd'and 1 or p.w
    local inside=rule=='evenodd'and winding%2~=0 or rule=='nonzero'and winding~=0
    if not was and inside then start=p.x
    elseif was and not inside and start then
     local a,b=math.max(0,start),math.min(c.w,p.x)
     for x=math.max(0,math.floor(a)),math.min(c.w-1,math.ceil(b)-1)do local i=y*c.w+x+1;alpha[i]+=math.max(0,math.min(x+1,b)-math.max(x,a))*.5 end
    end
   end
  end
  if c.checkpoint and y%16==0 then c.checkpoint()end
 end
 local levels=c.alphaLevels or 8
 for i,a in ipairs(alpha)do alpha[i]=math.floor(math.clamp(a,0,1)*levels+.5)/levels end
 return alpha
end
return G
