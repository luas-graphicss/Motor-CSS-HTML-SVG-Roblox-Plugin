local Tiles=require(script.Parent.RenderTiles)
local Gradient=require(script.Parent.CssGradient)
local R={VERSION=1,EPSILON=1/1024}
local read=buffer.readf32
local write=buffer.writef32
local clamp=math.clamp
local floor=math.floor
function R.solid(color,alpha)
 local a=alpha==nil and 1 or clamp(alpha,0,1)
 local c=color or Color3.new()
 return function() return c,a end
end
function R.gradient(g,ox,oy)
 ox=ox or 0
 oy=oy or 0
 return function(x,y) return Gradient.sample(g,x-ox,y-oy) end
end
function R.source(surface,ox,oy,sx,sy)
 ox=ox or 0
 oy=oy or 0
 sx=sx or 1
 sy=sy or 1
 return function(x,y) return Tiles.sample(surface,(x-ox)/sx-0.5,(y-oy)/sy-0.5) end
end
function R.shader(op,ox,oy)
 if type(op)=='function' then return op end
 if op.shader then return op.shader end
 if op.gradient then return R.gradient(op.gradient,ox or 0,oy or 0) end
 if op.surface then return R.source(op.surface,ox or 0,oy or 0,op.scaleX,op.scaleY) end
 return R.solid(op.color,op.alpha)
end
local function factor(options,x,y)
 local f=options.opacity==nil and 1 or clamp(options.opacity,0,1)
 if f<=0 then return 0 end
 if options.mask then f*=clamp(options.mask(x,y),0,1) end
 return f
end
function R.radii(value)
 if value==nil then return nil end
 if type(value)=='number' then
  local r={x=value,y=value}
  return {r,r,r,r}
 end
 local keys={'topLeft','topRight','bottomRight','bottomLeft'}
 local list={}
 local any=false
 for index=1,4 do
  local entry=value[index] or value[keys[index]]
  if type(entry)=='number' then list[index]={x=entry,y=entry}
  elseif type(entry)=='table' then list[index]={x=tonumber(entry.x or entry[1]) or 0,y=tonumber(entry.y or entry[2]) or 0}
  else list[index]={x=0,y=0} end
  if list[index].x>0 and list[index].y>0 then any=true end
 end
 if not any then return nil end
 return list
end
local function ellipse(dx,dy,rx,ry)
 local nx=dx/rx
 local ny=dy/ry
 local value=nx*nx+ny*ny-1
 local gx=2*dx/(rx*rx)
 local gy=2*dy/(ry*ry)
 local grad=math.sqrt(gx*gx+gy*gy)
 if grad<=1e-9 then return value<=0 and 1 or 0 end
 return clamp(0.5-value/grad,0,1)
end
function R.roundRectCoverage(box,radii,px,py)
 local left=box.x
 local top=box.y
 local right=box.x+box.w
 local bottom=box.y+box.h
 local cx=clamp(math.min(px+1,right)-math.max(px,left),0,1)
 local cy=clamp(math.min(py+1,bottom)-math.max(py,top),0,1)
 local base=cx*cy
 if base<=0 or not radii then return base end
 local sx=px+0.5
 local sy=py+0.5
 for index=1,4 do
  local r=radii[index]
  local rx=r and r.x or 0
  local ry=r and r.y or 0
  if rx>0 and ry>0 then
   local ox,oy
   if index==1 then ox=left+rx;oy=top+ry
   elseif index==2 then ox=right-rx;oy=top+ry
   elseif index==3 then ox=right-rx;oy=bottom-ry
   else ox=left+rx;oy=bottom-ry end
   local outside=(index==1 and sx<ox and sy<oy) or (index==2 and sx>ox and sy<oy) or (index==3 and sx>ox and sy>oy) or (index==4 and sx<ox and sy>oy)
   if outside then base=math.min(base,ellipse(sx-ox,sy-oy,rx,ry)) end
  end
 end
 return base
end
local function span(area,clip,target)
 local x0=area.x
 local y0=area.y
 local x1=area.x+(area.w or 0)
 local y1=area.y+(area.h or 0)
 if clip then
  x0=math.max(x0,clip.x);y0=math.max(y0,clip.y)
  x1=math.min(x1,clip.x+clip.w);y1=math.min(y1,clip.y+clip.h)
 end
 x0=math.max(x0,0);y0=math.max(y0,0)
 x1=math.min(x1,target.w);y1=math.min(y1,target.h)
 return x0,y0,x1,y1
end
function R.rect(target,area,shader,options)
 options=options or {}
 local paint=R.shader(shader)
 local x0,y0,x1,y1=span(area,options.clip,target)
 if x1<=x0 or y1<=y0 then return 0 end
 local painted=0
 for py=floor(y0),math.ceil(y1)-1 do
  local cy=math.min(y1,py+1)-math.max(y0,py)
  if cy>0 then
   for px=floor(x0),math.ceil(x1)-1 do
    local cx=math.min(x1,px+1)-math.max(x0,px)
    if cx>0 then
     local color,alpha=paint(px+0.5,py+0.5)
     if alpha and alpha>0 then
      local f=factor(options,px+0.5,py+0.5)
      if f>0 and Tiles.blend(target,px,py,color,alpha,options.mode,cx*cy*f) then painted+=1 end
     end
    end
   end
  end
 end
 return painted
end
function R.roundRect(target,box,radii,shader,options)
 options=options or {}
 local list=R.radii(radii)
 if not list then return R.rect(target,box,shader,options) end
 local paint=R.shader(shader)
 local area=Tiles.rect(target,box.x,box.y,box.w,box.h)
 if options.clip then area=Tiles.intersect(area,Tiles.rect(target,options.clip.x,options.clip.y,options.clip.w,options.clip.h)) end
 if area.w<=0 or area.h<=0 then return 0 end
 local painted=0
 for py=area.y,area.y+area.h-1 do
  for px=area.x,area.x+area.w-1 do
   local coverage=R.roundRectCoverage(box,list,px,py)
   if coverage>R.EPSILON then
    local color,alpha=paint(px+0.5,py+0.5)
    if alpha and alpha>0 then
     local f=factor(options,px+0.5,py+0.5)
     if f>0 and Tiles.blend(target,px,py,color,alpha,options.mode,coverage*f) then painted+=1 end
    end
   end
  end
 end
 return painted
end
local function accumulate(acc,index,value)
 local at=index*4
 write(acc,at,read(acc,at)+value)
end
local function edge(acc,stride,height,ax,ay,bx,by)
 if math.abs(ay-by)<1e-9 then return end
 local dir=1
 if ay>by then dir=-1;ax,ay,bx,by=bx,by,ax,ay end
 local dxdy=(bx-ax)/(by-ay)
 local x=ax
 local first=floor(ay)
 if ay<0 then x-=ay*dxdy;first=0 end
 local last=math.min(height,math.ceil(by))
 for y=math.max(0,first),last-1 do
  local dy=math.min(y+1,by)-math.max(y,ay)
  if dy>0 then
   local xnext=x+dxdy*dy
   local d=dy*dir
   local x0=clamp(math.min(x,xnext),0,stride-2)
   local x1=clamp(math.max(x,xnext),0,stride-2)
   local low=floor(x0)
   local high=math.ceil(x1)
   local base=y*stride
   if high<=low+1 then
    local mid=0.5*(x0+x1)-low
    accumulate(acc,base+low,d-d*mid)
    accumulate(acc,base+low+1,d*mid)
   else
    local s=1/(x1-x0)
    local head=x0-low
    local a0=0.5*s*(1-head)*(1-head)
    local tail=x1-high+1
    local am=0.5*s*tail*tail
    accumulate(acc,base+low,d*a0)
    if high==low+2 then
     accumulate(acc,base+low+1,d*(1-a0-am))
    else
     local a1=s*(1.5-head)
     accumulate(acc,base+low+1,d*(a1-a0))
     for xi=low+2,high-2 do accumulate(acc,base+xi,d*s) end
     local a2=a1+(high-low-3)*s
     accumulate(acc,base+high-1,d*(1-a2-am))
    end
    accumulate(acc,base+high,d*am)
   end
   x=xnext
  end
 end
end
local function point(entry)
 return tonumber(entry.x or entry[1]) or 0,tonumber(entry.y or entry[2]) or 0
end
function R.bounds(subpaths)
 local minx=math.huge
 local miny=math.huge
 local maxx=-math.huge
 local maxy=-math.huge
 for _,points in ipairs(subpaths) do
  for _,entry in ipairs(points) do
   local px,py=point(entry)
   if px<minx then minx=px end
   if py<miny then miny=py end
   if px>maxx then maxx=px end
   if py>maxy then maxy=py end
  end
 end
 if minx>maxx then return nil end
 return {x=minx,y=miny,w=maxx-minx,h=maxy-miny}
end
function R.path(target,subpaths,shader,options)
 options=options or {}
 local box=R.bounds(subpaths)
 if not box then return 0 end
 local area=Tiles.rect(target,box.x-1,box.y-1,box.w+2,box.h+2)
 if options.clip then area=Tiles.intersect(area,Tiles.rect(target,options.clip.x,options.clip.y,options.clip.w,options.clip.h)) end
 if area.w<=0 or area.h<=0 then return 0 end
 local paint=R.shader(shader)
 local stride=area.w+2
 local bytes=stride*area.h*4
 target.budget:spend(bytes,'Acumulador analitico do render core','scratch')
 local acc=buffer.create(bytes)
 local evenodd=options.rule=='evenodd'
 for _,points in ipairs(subpaths) do
  local count=#points
  if count>=2 then
   for index=1,count do
    local ax,ay=point(points[index])
    local bx,by=point(points[index%count+1])
    edge(acc,stride,area.h,ax-area.x,ay-area.y,bx-area.x,by-area.y)
   end
  end
 end
 local painted=0
 for y=0,area.h-1 do
  local sum=0
  local base=y*stride
  for x=0,area.w-1 do
   sum+=read(acc,(base+x)*4)
   local coverage
   if evenodd then
    local t=math.abs(sum)%2
    coverage=t<=1 and t or 2-t
   else
    coverage=math.min(math.abs(sum),1)
   end
   if coverage>R.EPSILON then
    local px=area.x+x
    local py=area.y+y
    local color,alpha=paint(px+0.5,py+0.5)
    if alpha and alpha>0 then
     local f=factor(options,px+0.5,py+0.5)
     if f>0 and Tiles.blend(target,px,py,color,alpha,options.mode,coverage*f) then painted+=1 end
    end
   end
  end
 end
 target.budget:refund(bytes)
 return painted
end
function R.polygon(target,points,shader,options)
 return R.path(target,{points},shader,options)
end
function R.ring(target,box,radii,width,shader,options)
 options=options or {}
 local outer=R.radii(radii)
 local inner={}
 local list=outer or {{x=0,y=0},{x=0,y=0},{x=0,y=0},{x=0,y=0}}
 for index=1,4 do
  inner[index]={x=math.max(0,list[index].x-width),y=math.max(0,list[index].y-width)}
 end
 local hole={x=box.x+width,y=box.y+width,w=math.max(0,box.w-width*2),h=math.max(0,box.h-width*2)}
 local paint=R.shader(shader)
 local area=Tiles.rect(target,box.x,box.y,box.w,box.h)
 if options.clip then area=Tiles.intersect(area,Tiles.rect(target,options.clip.x,options.clip.y,options.clip.w,options.clip.h)) end
 if area.w<=0 or area.h<=0 then return 0 end
 local painted=0
 for py=area.y,area.y+area.h-1 do
  for px=area.x,area.x+area.w-1 do
   local coverage=R.roundRectCoverage(box,outer,px,py)-R.roundRectCoverage(hole,R.radii(inner),px,py)
   if coverage>R.EPSILON then
    local color,alpha=paint(px+0.5,py+0.5)
    if alpha and alpha>0 then
     local f=factor(options,px+0.5,py+0.5)
     if f>0 and Tiles.blend(target,px,py,color,alpha,options.mode,clamp(coverage,0,1)*f) then painted+=1 end
    end
   end
  end
 end
 return painted
end
function R.coverageMask(box,radii)
 local list=R.radii(radii)
 return function(x,y) return R.roundRectCoverage(box,list,floor(x),floor(y)) end
end
return R
