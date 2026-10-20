local Cache=require(script.Parent.VectorCache)
local K={VERSION='vector-stroke-1',ALGORITHM='offset-union-2'}
local sqrt=math.sqrt
local abs=math.abs
local min=math.min
local max=math.max
local clamp=math.clamp
local cos=math.cos
local sin=math.sin
local atan2=math.atan2
local pi=math.pi
local function lineSegment(x0,y0,x1,y1)
 return {curve=false,x0=x0,y0=y0,x1=x1,y1=y1}
end
local function cubicSegment(x0,y0,ax,ay,bx,by,x1,y1)
 return {curve=true,x0=x0,y0=y0,ax=ax,ay=ay,bx=bx,by=by,x1=x1,y1=y1}
end
K.line=lineSegment
K.cubic=cubicSegment
local function push(out,x,y)
 assert(x==x and y==y and abs(x)<1e12 and abs(y)<1e12,'Vertice de stroke fora do limite.')
 local count=#out
 if count>0 then
  local last=out[count]
  if abs(last.x-x)<1e-9 and abs(last.y-y)<1e-9 then return end
 end
 out[count+1]={x=x,y=y}
end
local function at(seg,t)
 if not seg.curve then
  return seg.x0+(seg.x1-seg.x0)*t,seg.y0+(seg.y1-seg.y0)*t
 end
 local u=1-t
 local a=u*u*u
 local b=3*u*u*t
 local c=3*u*t*t
 local d=t*t*t
 return a*seg.x0+b*seg.ax+c*seg.bx+d*seg.x1,a*seg.y0+b*seg.ay+c*seg.by+d*seg.y1
end
local function velocity(seg,t)
 if not seg.curve then return seg.x1-seg.x0,seg.y1-seg.y0 end
 local u=1-t
 local a=3*u*u
 local b=6*u*t
 local c=3*t*t
 return a*(seg.ax-seg.x0)+b*(seg.bx-seg.ax)+c*(seg.x1-seg.bx),a*(seg.ay-seg.y0)+b*(seg.by-seg.ay)+c*(seg.y1-seg.by)
end
local function direction(seg,t)
 local dx,dy=velocity(seg,t)
 local length=sqrt(dx*dx+dy*dy)
 if length>1e-10 then return dx/length,dy/length end
 local probes={0.002,-0.002,0.02,-0.02,0.1,-0.1,0.3,-0.3}
 for _,delta in ipairs(probes) do
  local sample=clamp(t+delta,0,1)
  local vx,vy=velocity(seg,sample)
  local size=sqrt(vx*vx+vy*vy)
  if size>1e-10 then return vx/size,vy/size end
 end
 local cx,cy=seg.x1-seg.x0,seg.y1-seg.y0
 local size=sqrt(cx*cx+cy*cy)
 if size>1e-10 then return cx/size,cy/size end
 return 1,0
end
K.point=at
K.direction=direction
local function splitAt(seg,t)
 if not seg.curve then
  local mx,my=at(seg,t)
  return lineSegment(seg.x0,seg.y0,mx,my),lineSegment(mx,my,seg.x1,seg.y1)
 end
 local x01,y01=seg.x0+(seg.ax-seg.x0)*t,seg.y0+(seg.ay-seg.y0)*t
 local x12,y12=seg.ax+(seg.bx-seg.ax)*t,seg.ay+(seg.by-seg.ay)*t
 local x23,y23=seg.bx+(seg.x1-seg.bx)*t,seg.by+(seg.y1-seg.by)*t
 local x012,y012=x01+(x12-x01)*t,y01+(y12-y01)*t
 local x123,y123=x12+(x23-x12)*t,y12+(y23-y12)*t
 local mx,my=x012+(x123-x012)*t,y012+(y123-y012)*t
 return cubicSegment(seg.x0,seg.y0,x01,y01,x012,y012,mx,my),cubicSegment(mx,my,x123,y123,x23,y23,seg.x1,seg.y1)
end
local function subSegment(seg,t0,t1)
 if t0<=1e-12 and t1>=1-1e-12 then return seg end
 local part=seg
 local upper=t1
 if upper<1-1e-12 then
  part=select(1,splitAt(part,upper))
 end
 if t0>1e-12 then
  local remap=upper<1-1e-12 and t0/upper or t0
  part=select(2,splitAt(part,clamp(remap,0,1)))
 end
 return part
end
K.subSegment=subSegment
local function offsetRange(seg,t0,t1,radius,tolerance,maxAlign,out,depth)
 local ax,ay=at(seg,t0)
 local dx0,dy0=direction(seg,t0)
 local bx,by=at(seg,t1)
 local dx1,dy1=direction(seg,t1)
 local tm=(t0+t1)*0.5
 local mx,my=at(seg,tm)
 local dxm,dym=direction(seg,tm)
 local p0x,p0y=ax-dy0*radius,ay+dx0*radius
 local p1x,p1y=bx-dy1*radius,by+dx1*radius
 local pmx,pmy=mx-dym*radius,my+dxm*radius
 local ex,ey=(p0x+p1x)*0.5-pmx,(p0y+p1y)*0.5-pmy
 local error=ex*ex+ey*ey
 local align=dx0*dx1+dy0*dy1
 if depth<18 and (error>tolerance*tolerance or align<maxAlign) then
  offsetRange(seg,t0,tm,radius,tolerance,maxAlign,out,depth+1)
  offsetRange(seg,tm,t1,radius,tolerance,maxAlign,out,depth+1)
  return
 end
 push(out,pmx,pmy)
 push(out,p1x,p1y)
end
local function offsetSegment(seg,radius,tolerance,maxAlign,out)
 local dx,dy=direction(seg,0)
 push(out,seg.x0-dy*radius,seg.y0+dx*radius)
 if not seg.curve then
  local ex,ey=direction(seg,1)
  push(out,seg.x1-ey*radius,seg.y1+ex*radius)
  return
 end
 offsetRange(seg,0,1,radius,tolerance,maxAlign,out,0)
end
local function arcSweep(out,cx,cy,startX,startY,delta,maxAngle)
 local radius=sqrt(startX*startX+startY*startY)
 if radius<1e-12 or abs(delta)<1e-9 then return end
 local steps=math.clamp(math.ceil(abs(delta)/max(maxAngle,0.005)),1,4096)
 local base=atan2(startY,startX)
 for step=1,steps do
  local angle=base+delta*step/steps
  push(out,cx+cos(angle)*radius,cy+sin(angle)*radius)
 end
end
local function applyJoin(out,vx,vy,inDx,inDy,outDx,outDy,radius,join,miterLimit,maxAngle)
 local cross=inDx*outDy-inDy*outDx
 local dot=inDx*outDx+inDy*outDy
 local ax,ay=vx-inDy*radius,vy+inDx*radius
 local bx,by=vx-outDy*radius,vy+outDx*radius
 push(out,ax,ay)
 if abs(cross)<1e-12 and dot>0 then
  push(out,bx,by)
  return
 end
 local outer=(radius>0 and cross<0) or (radius<0 and cross>0)
 if not outer then
  push(out,vx,vy)
  push(out,bx,by)
  return
 end
 if join=='round' then
  local delta=atan2((ax-vx)*(by-vy)-(ay-vy)*(bx-vx),(ax-vx)*(bx-vx)+(ay-vy)*(by-vy))
  arcSweep(out,vx,vy,ax-vx,ay-vy,delta,maxAngle)
  push(out,bx,by)
  return
 end
 if join=='miter' then
  local half=sqrt(max(0,(1+dot)*0.5))
  if half>1e-6 and 1/half<=miterLimit then
   local scale=((bx-ax)*outDy-(by-ay)*outDx)/cross
   local tipX=ax+inDx*scale
   local tipY=ay+inDy*scale
   if tipX==tipX and tipY==tipY and abs(tipX)<1e12 and abs(tipY)<1e12 then
    push(out,tipX,tipY)
    push(out,bx,by)
    return
   end
  end
 end
 push(out,bx,by)
end
local function capEnd(out,px,py,dx,dy,radius,cap,maxAngle)
 local lx,ly=px-dy*radius,py+dx*radius
 local rx,ry=px+dy*radius,py-dx*radius
 push(out,lx,ly)
 if cap=='square' then
  push(out,lx+dx*radius,ly+dy*radius)
  push(out,rx+dx*radius,ry+dy*radius)
 elseif cap=='round' then
  arcSweep(out,px,py,lx-px,ly-py,-pi,maxAngle)
 end
 push(out,rx,ry)
end
local function lut(seg,tolerance)
 if not seg.curve then
  local dx,dy=seg.x1-seg.x0,seg.y1-seg.y0
  local length=sqrt(dx*dx+dy*dy)
  return {length=length,samples={{t=0,s=0},{t=1,s=length}}}
 end
 local control=sqrt((seg.ax-seg.x0)^2+(seg.ay-seg.y0)^2)+sqrt((seg.bx-seg.ax)^2+(seg.by-seg.ay)^2)+sqrt((seg.x1-seg.bx)^2+(seg.y1-seg.by)^2)
 local count=math.clamp(math.ceil(sqrt(control/max(tolerance,1e-6))*4),24,1024)
 local samples={{t=0,s=0}}
 local previousX,previousY=at(seg,0)
 local total=0
 for index=1,count do
  local t=index/count
  local x,y=at(seg,t)
  total+=sqrt((x-previousX)^2+(y-previousY)^2)
  samples[index+1]={t=t,s=total}
  previousX,previousY=x,y
 end
 return {length=total,samples=samples}
end
local function tAtLength(info,distance)
 if distance<=0 then return 0 end
 if distance>=info.length then return 1 end
 local samples=info.samples
 local low,high=1,#samples
 while high-low>1 do
  local middle=(low+high)//2
  if samples[middle].s<=distance then low=middle else high=middle end
 end
 local a=samples[low]
 local b=samples[high]
 local span=b.s-a.s
 if span<=1e-12 then return a.t end
 return a.t+(b.t-a.t)*(distance-a.s)/span
end
function K.fromContours(contours)
 local out={}
 for _,contour in ipairs(contours) do
  local count=#contour
  local segments={}
  if count==1 then
   local entry=contour[1]
   local x=entry.x or entry[1]
   local y=entry.y or entry[2]
   segments[1]=lineSegment(x,y,x,y)
  elseif count>=2 then
   local limit=contour.closed and count or count-1
   for index=1,limit do
    local a=contour[index]
    local b=contour[index%count+1]
    local ax=a.x or a[1]
    local ay=a.y or a[2]
    local bx=b.x or b[1]
    local by=b.y or b[2]
    segments[#segments+1]=lineSegment(ax,ay,bx,by)
   end
  end
  if #segments>0 then out[#out+1]={segments=segments,closed=contour.closed==true} end
 end
 return out
end
function K.arcToCubics(out,x0,y0,rx,ry,rotation,large,sweep,x1,y1)
 rx,ry=abs(rx),abs(ry)
 if rx<1e-12 or ry<1e-12 or (abs(x1-x0)<1e-12 and abs(y1-y0)<1e-12) then
  out[#out+1]=lineSegment(x0,y0,x1,y1)
  return out
 end
 local phi=math.rad(rotation%360)
 local co,si=cos(phi),sin(phi)
 local halfX,halfY=(x0-x1)/2,(y0-y1)/2
 local xp=co*halfX+si*halfY
 local yp=-si*halfX+co*halfY
 local lambda=xp*xp/(rx*rx)+yp*yp/(ry*ry)
 if lambda>1 then
  local scale=sqrt(lambda)
  rx*=scale
  ry*=scale
 end
 local numerator=max(0,rx*rx*ry*ry-rx*rx*yp*yp-ry*ry*xp*xp)
 local denominator=rx*rx*yp*yp+ry*ry*xp*xp
 local factor=((large~=0)==(sweep~=0) and -1 or 1)*sqrt(numerator/max(denominator,1e-20))
 local cxp=factor*rx*yp/ry
 local cyp=-factor*ry*xp/rx
 local cx=co*cxp-si*cyp+(x0+x1)/2
 local cy=si*cxp+co*cyp+(y0+y1)/2
 local ux,uy=(xp-cxp)/rx,(yp-cyp)/ry
 local vx,vy=(-xp-cxp)/rx,(-yp-cyp)/ry
 local start=atan2(uy,ux)
 local delta=atan2(ux*vy-uy*vx,ux*vx+uy*vy)
 if sweep==0 and delta>0 then delta-=2*pi elseif sweep~=0 and delta<0 then delta+=2*pi end
 local count=math.clamp(math.ceil(abs(delta)/(pi/2)),1,16)
 local step=delta/count
 local k=4/3*math.tan(step/4)
 local angle=start
 local px,py=x0,y0
 for _=1,count do
  local nextAngle=angle+step
  local cosA,sinA=cos(angle),sin(angle)
  local cosB,sinB=cos(nextAngle),sin(nextAngle)
  local endX=cx+co*rx*cosB-si*ry*sinB
  local endY=cy+si*rx*cosB+co*ry*sinB
  local d1x,d1y=-rx*sinA,ry*cosA
  local d2x,d2y=-rx*sinB,ry*cosB
  out[#out+1]=cubicSegment(px,py,px+k*(co*d1x-si*d1y),py+k*(si*d1x+co*d1y),endX-k*(co*d2x-si*d2y),endY-k*(si*d2x+co*d2y),endX,endY)
  px,py=endX,endY
  angle=nextAngle
 end
 return out
end
function K.fromTokens(tokens)
 local subpaths={}
 local current=nil
 local x,y,sx,sy=0,0,0,0
 local index=1
 local function open(px,py)
  current={segments={},closed=false}
  subpaths[#subpaths+1]=current
  sx,sy=px,py
 end
 local function ensure()
  if not current then open(x,y) end
  return current
 end
 while index<=#tokens do
  local command=tokens[index]
  index+=1
  if command=='M' then
   x,y=tokens[index],tokens[index+1]
   index+=2
   open(x,y)
  elseif command=='L' then
   local nx,ny=tokens[index],tokens[index+1]
   index+=2
   local target=ensure()
   target.segments[#target.segments+1]=lineSegment(x,y,nx,ny)
   x,y=nx,ny
  elseif command=='C' then
   local ax,ay,bx,by,nx,ny=tokens[index],tokens[index+1],tokens[index+2],tokens[index+3],tokens[index+4],tokens[index+5]
   index+=6
   local target=ensure()
   target.segments[#target.segments+1]=cubicSegment(x,y,ax,ay,bx,by,nx,ny)
   x,y=nx,ny
  elseif command=='Q' then
   local qx,qy,nx,ny=tokens[index],tokens[index+1],tokens[index+2],tokens[index+3]
   index+=4
   local target=ensure()
   target.segments[#target.segments+1]=cubicSegment(x,y,x+2*(qx-x)/3,y+2*(qy-y)/3,nx+2*(qx-nx)/3,ny+2*(qy-ny)/3,nx,ny)
   x,y=nx,ny
  elseif command=='A' then
   local rx,ry,rotation,large,sweep,nx,ny=tokens[index],tokens[index+1],tokens[index+2],tokens[index+3],tokens[index+4],tokens[index+5],tokens[index+6]
   index+=7
   local target=ensure()
   K.arcToCubics(target.segments,x,y,rx,ry,rotation,large,sweep,nx,ny)
   x,y=nx,ny
  elseif command=='Z' then
   if current then
    if abs(x-sx)>1e-9 or abs(y-sy)>1e-9 then
     current.segments[#current.segments+1]=lineSegment(x,y,sx,sy)
    end
    current.closed=true
    current=nil
   end
   x,y=sx,sy
  else
   error('Token de path desconhecido: '..tostring(command),0)
  end
 end
 local out={}
 for _,sub in ipairs(subpaths) do
  if #sub.segments>0 then out[#out+1]=sub end
 end
 return out
end
function K.length(subpaths,tolerance)
 local total=0
 for _,sub in ipairs(subpaths) do
  for _,seg in ipairs(sub.segments) do total+=lut(seg,tolerance or 0.1).length end
 end
 return total
end
function K.dash(subpaths,pattern,offset,tolerance)
 local dashes={}
 local sum=0
 for _,value in ipairs(pattern) do
  local size=tonumber(value) or 0
  assert(size>=0,'stroke-dasharray nao aceita valores negativos.')
  dashes[#dashes+1]=size
  sum+=size
 end
 if #dashes==0 or sum<=1e-12 then return subpaths end
 if #dashes%2==1 then
  local count=#dashes
  for i=1,count do dashes[#dashes+1]=dashes[i] end
  sum*=2
 end
 local out={}
 for _,sub in ipairs(subpaths) do
  local tables={}
  local total=0
  for i,seg in ipairs(sub.segments) do
   tables[i]=lut(seg,tolerance)
   total+=tables[i].length
  end
  local function locate(distance)
   local base=0
   for i,seg in ipairs(sub.segments) do
    local info=tables[i]
    if distance<=base+info.length or i==#sub.segments then
     local t=tAtLength(info,distance-base)
     local px,py=at(seg,t)
     local dx,dy=direction(seg,t)
     return px,py,dx,dy
    end
    base+=info.length
   end
   return sub.segments[1].x0,sub.segments[1].y0,1,0
  end
  local function slice(from,to)
   local segments={}
   local base=0
   for i,seg in ipairs(sub.segments) do
    local info=tables[i]
    if info.length>1e-12 and to>base-1e-9 and from<base+info.length+1e-9 then
     local localFrom=max(from-base,0)
     local localTo=min(to-base,info.length)
     if localTo>localFrom+1e-9 then
      local t0=tAtLength(info,localFrom)
      local t1=tAtLength(info,localTo)
      if t1>t0+1e-12 then segments[#segments+1]=subSegment(seg,t0,t1) end
     end
    end
    base+=info.length
   end
   return segments
  end
  if total<=1e-12 then
   out[#out+1]={segments=sub.segments,closed=false,dot=true}
  else
   local phase=((tonumber(offset) or 0)%sum+sum)%sum
   local index=1
   local guard=0
   while phase>=dashes[index] and guard<4096 do
    guard+=1
    phase-=dashes[index]
    index=index%#dashes+1
   end
   local remaining=dashes[index]-phase
   local position=0
   local pieces={}
   local steps=0
   while position<total-1e-9 and steps<65536 do
    steps+=1
    local step=min(remaining,total-position)
    if index%2==1 and step>1e-9 then pieces[#pieces+1]={from=position,to=position+step} end
    position+=step
    remaining-=step
    if remaining<=1e-9 then
     local zeros=0
     repeat
      index=index%#dashes+1
      remaining=dashes[index]
      if remaining<=1e-12 and index%2==1 then pieces[#pieces+1]={from=position,to=position,dot=true} end
      zeros+=1
     until remaining>1e-12 or zeros>#dashes
    end
   end
   local built={}
   for _,piece in ipairs(pieces) do
    if piece.dot then
     local px,py=locate(piece.from)
     built[#built+1]={segments={lineSegment(px,py,px,py)},closed=false,dot=true}
    else
     local segments=slice(piece.from,piece.to)
     if #segments>0 then built[#built+1]={segments=segments,closed=false} end
    end
   end
   if sub.closed and #built>1 and #pieces>1 and pieces[1].from<=1e-9 and pieces[#pieces].to>=total-1e-9 then
    local first=table.remove(built,1)
    local last=built[#built]
    if first and last and not first.dot and not last.dot then
     for _,seg in ipairs(first.segments) do last.segments[#last.segments+1]=seg end
    elseif first then
     built[#built+1]=first
    end
   end
   for _,piece in ipairs(built) do out[#out+1]=piece end
  end
 end
 return out
end
local function signedArea(contour)
 local area=0
 local count=#contour
 for i=1,count do
  local a=contour[i]
  local b=contour[i%count+1]
  area+=a.x*b.y-b.x*a.y
 end
 return area*0.5
end
local function flattenRange(seg,t0,t1,radius,tolerance,maxAlign,out,depth)
 local ax,ay=at(seg,t0)
 local dx0,dy0=direction(seg,t0)
 local bx,by=at(seg,t1)
 local dx1,dy1=direction(seg,t1)
 local tm=(t0+t1)*0.5
 local mx,my=at(seg,tm)
 local dxm,dym=direction(seg,tm)
 local p0x,p0y=ax-dy0*radius,ay+dx0*radius
 local p1x,p1y=bx-dy1*radius,by+dx1*radius
 local pmx,pmy=mx-dym*radius,my+dxm*radius
 local ex,ey=(p0x+p1x)*0.5-pmx,(p0y+p1y)*0.5-pmy
 local q0x,q0y=ax+dy0*radius,ay-dx0*radius
 local q1x,q1y=bx+dy1*radius,by-dx1*radius
 local qmx,qmy=mx+dym*radius,my-dxm*radius
 local fx,fy=(q0x+q1x)*0.5-qmx,(q0y+q1y)*0.5-qmy
 local error=max(ex*ex+ey*ey,fx*fx+fy*fy)
 local align=dx0*dx1+dy0*dy1
 if depth<18 and (error>tolerance*tolerance or align<maxAlign) then
  flattenRange(seg,t0,tm,radius,tolerance,maxAlign,out,depth+1)
  flattenRange(seg,tm,t1,radius,tolerance,maxAlign,out,depth+1)
  return
 end
 out[#out+1]={x=bx,y=by}
end
local function flattenSegment(seg,radius,tolerance,maxAlign,out)
 if #out==0 then out[1]={x=seg.x0,y=seg.y0} end
 if not seg.curve then
  out[#out+1]={x=seg.x1,y=seg.y1}
  return
 end
 flattenRange(seg,0,1,radius,tolerance,maxAlign,out,0)
end
function K.outline(subpaths,style)
 style=style or {}
 local width=tonumber(style.width) or 1
 assert(width>0 and width<1e6,'stroke-width invalido para contorno exato.')
 local radius=width/2
 local tolerance=max(tonumber(style.tolerance) or 0.1,1e-7)
 local cap=style.cap or 'butt'
 local join=style.join or 'miter'
 assert(cap=='butt' or cap=='round' or cap=='square','stroke-linecap nao suportado: '..tostring(cap))
 assert(join=='miter' or join=='round' or join=='bevel','stroke-linejoin nao suportado: '..tostring(join))
 local miterLimit=max(tonumber(style.miterLimit) or 4,1)
 local maxAngle=max(2*math.acos(clamp(1-tolerance/max(radius,tolerance),-1,1)),0.01)
 local maxAlign=cos(maxAngle)
 local vertexLimit=math.floor(tonumber(style.maxVertices) or 524288)
 local work=subpaths
 if style.dash and #style.dash>0 then work=K.dash(subpaths,style.dash,style.dashOffset,tolerance) end
 local out={}
 local vertices=0
 local function emit(contour)
  if #contour<3 then return end
  local area=signedArea(contour)
  if abs(area)<1e-14 then return end
  if area<0 then
   local reversed={}
   for i=#contour,1,-1 do reversed[#reversed+1]=contour[i] end
   contour=reversed
  end
  contour.closed=true
  vertices+=#contour
  assert(vertices<=vertexLimit,'Contorno de stroke excede o orcamento de vertices.')
  out[#out+1]=contour
 end
 local function emitQuad(ax,ay,bx,by)
  local dx,dy=bx-ax,by-ay
  local length=sqrt(dx*dx+dy*dy)
  if length<1e-12 then return end
  dx,dy=dx/length,dy/length
  local nx,ny=-dy*radius,dx*radius
  emit({{x=ax+nx,y=ay+ny},{x=bx+nx,y=by+ny},{x=bx-nx,y=by-ny},{x=ax-nx,y=ay-ny}})
 end
 local function emitJoin(vx,vy,inDx,inDy,outDx,outDy,kind)
  local cross=inDx*outDy-inDy*outDx
  local dot=inDx*outDx+inDy*outDy
  if abs(cross)<1e-12 and dot>0 then return end
  local side=cross<0 and radius or -radius
  local wedge={{x=vx,y=vy}}
  applyJoin(wedge,vx,vy,inDx,inDy,outDx,outDy,side,kind,miterLimit,maxAngle)
  emit(wedge)
  if dot<-0.999999 then
   local disc={}
   arcSweep(disc,vx,vy,radius,0,2*pi,maxAngle)
   emit(disc)
  end
 end
 local function emitCap(px,py,dx,dy)
  if cap=='butt' then return end
  local contour={}
  capEnd(contour,px,py,dx,dy,radius,cap,maxAngle)
  emit(contour)
 end
 for _,sub in ipairs(work) do
  local segments={}
  for _,seg in ipairs(sub.segments) do
   local dx=seg.x1-seg.x0
   local dy=seg.y1-seg.y0
   local extent=abs(dx)+abs(dy)
   if seg.curve then extent+=abs(seg.ax-seg.x0)+abs(seg.ay-seg.y0)+abs(seg.bx-seg.x1)+abs(seg.by-seg.y1) end
   if extent>1e-9 then segments[#segments+1]=seg end
  end
  if #segments==0 then
   local seed=sub.segments[1]
   if seed then
    local px,py=seed.x0,seed.y0
    if cap=='round' then
     local circle={}
     arcSweep(circle,px,py,radius,0,2*pi,maxAngle)
     emit(circle)
    elseif cap=='square' then
     emit({{x=px-radius,y=py-radius},{x=px+radius,y=py-radius},{x=px+radius,y=py+radius},{x=px-radius,y=py+radius}})
    end
   end
  else
   if sub.closed then
    local first=segments[1]
    local last=segments[#segments]
    if abs(last.x1-first.x0)>1e-9 or abs(last.y1-first.y0)>1e-9 then
     segments[#segments+1]=lineSegment(last.x1,last.y1,first.x0,first.y0)
    end
   end
   local points={}
   local boundary={}
   for _,seg in ipairs(segments) do
    flattenSegment(seg,radius,tolerance,maxAlign,points)
    boundary[#points]=true
   end
   local cleaned={}
   local cleanedBoundary={}
   for i,p in ipairs(points) do
    local last=cleaned[#cleaned]
    if last and abs(last.x-p.x)<1e-9 and abs(last.y-p.y)<1e-9 then
     if boundary[i] then cleanedBoundary[#cleaned]=true end
    else
     cleaned[#cleaned+1]=p
     if boundary[i] then cleanedBoundary[#cleaned]=true end
    end
   end
   points=cleaned
   local count=#points
   if sub.closed and count>=2 then
    local first,last=points[1],points[count]
    if abs(first.x-last.x)<1e-9 and abs(first.y-last.y)<1e-9 then
     points[count]=nil
     cleanedBoundary[1]=true
     count-=1
    end
   end
   if count>=2 then
    local edgeCount=sub.closed and count or count-1
    local dirs={}
    for i=1,edgeCount do
     local a=points[i]
     local b=points[i%count+1]
     emitQuad(a.x,a.y,b.x,b.y)
     local dx,dy=b.x-a.x,b.y-a.y
     local length=sqrt(dx*dx+dy*dy)
     dirs[i]=length>1e-12 and {dx/length,dy/length} or nil
    end
    local firstJoin=sub.closed and 1 or 2
    for i=firstJoin,count do
     local incoming=dirs[i==1 and edgeCount or i-1]
     local outgoing=dirs[i]
     if incoming and outgoing then
      local kind=(cleanedBoundary[i] or (i==1 and sub.closed)) and join or 'round'
      emitJoin(points[i].x,points[i].y,incoming[1],incoming[2],outgoing[1],outgoing[2],kind)
     end
    end
    if not sub.closed then
     local head=dirs[1]
     local tail=dirs[edgeCount]
     if head then emitCap(points[1].x,points[1].y,-head[1],-head[2]) end
     if tail then emitCap(points[count].x,points[count].y,tail[1],tail[2]) end
    end
   end
  end
 end
 return out
end
function K.legacy(contours,width,cap,join,miterLimit,tolerance)
 local size=tonumber(width) or 0
 if size<=0 then return {} end
 return K.outline(K.fromContours(contours),{width=size,cap=cap or 'butt',join=join or 'miter',miterLimit=tonumber(miterLimit) or 4,tolerance=tolerance or 0.1})
end
function K.stage()
 return Cache.stage('stroke',K.ALGORITHM,{maxEntries=96,maxBytes=6291456})
end
function K.cachedOutline(signature,subpaths,style)
 local stage=K.stage()
 local key=Cache.key({signature,style.width,style.cap,style.join,style.miterLimit,style.tolerance,style.dashOffset,style.dash and table.concat(style.dash,',') or 'none'})
 local cached=Cache.get(stage,key)
 if cached then return cached,true end
 local value=K.outline(subpaths,style)
 local bytes=64
 for _,contour in ipairs(value) do bytes+=#contour*32 end
 Cache.put(stage,key,value,bytes)
 return value,false
end
return K
