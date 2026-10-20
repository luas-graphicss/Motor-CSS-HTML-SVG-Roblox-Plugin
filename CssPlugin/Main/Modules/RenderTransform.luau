local Transform=require(script.Parent.Transform)
local Tiles=require(script.Parent.RenderTiles)
local X={VERSION=1}
local clamp=math.clamp
local floor=math.floor
local abs=math.abs
local min=math.min
local max=math.max
local EPSILON=1e-9
local identity=Transform.identity
local multiply=Transform.multiply
X.EPSILON=EPSILON
X.identity=identity
X.multiply=multiply
local function finite(v) return type(v)=='number' and v==v and abs(v)<1e9 end
X.finite=finite
function X.matrix(values)
 if type(values)~='table' then return nil end
 local source=values
 if type(source.matrix)=='table' then source=source.matrix end
 if #source~=16 then return nil end
 local m=table.create(16,0)
 for i=1,16 do
  local v=tonumber(source[i])
  if not finite(v) then return nil end
  m[i]=v
 end
 return m
end
function X.isIdentity(m)
 if m==nil then return true end
 for i=1,16 do
  local expected=(i==1 or i==6 or i==11 or i==16) and 1 or 0
  if abs(m[i]-expected)>1e-6 then return false end
 end
 return true
end
function X.equal(a,b)
 if a==nil or b==nil then return X.isIdentity(a) and X.isIdentity(b) end
 for i=1,16 do if abs(a[i]-b[i])>1e-6 then return false end end
 return true
end
function X.translate(x,y,z)
 local m=identity()
 m[4],m[8],m[12]=tonumber(x) or 0,tonumber(y) or 0,tonumber(z) or 0
 return m
end
function X.scale(x,y,z)
 local m=identity()
 m[1],m[6],m[11]=tonumber(x) or 1,tonumber(y) or 1,tonumber(z) or 1
 return m
end
function X.perspective(distance)
 local m=identity()
 local d=tonumber(distance)
 if d and d>0 then m[15]=-1/d end
 return m
end
function X.around(m,ox,oy,oz)
 if not m then return nil end
 ox=tonumber(ox) or 0
 oy=tonumber(oy) or 0
 oz=tonumber(oz) or 0
 if ox==0 and oy==0 and oz==0 then return m end
 return multiply(X.translate(ox,oy,oz),multiply(m,X.translate(-ox,-oy,-oz)))
end
function X.flatten(m)
 if not m then return nil end
 local f=table.clone(m)
 f[3],f[7],f[15]=0,0,0
 f[9],f[10],f[12]=0,0,0
 f[11]=1
 return f
end
function X.transform(m,x,y,z)
 z=z or 0
 return m[1]*x+m[2]*y+m[3]*z+m[4],m[5]*x+m[6]*y+m[7]*z+m[8],m[9]*x+m[10]*y+m[11]*z+m[12],m[13]*x+m[14]*y+m[15]*z+m[16]
end
function X.project(m,x,y,z)
 local px,py,pz,w=X.transform(m,x,y,z)
 if w<=EPSILON or not finite(w) then return nil end
 px,py,pz=px/w,py/w,pz/w
 if not finite(px) or not finite(py) or not finite(pz) then return nil end
 return px,py,pz,w
end
function X.invert(m)
 local a11,a12,a13,a14=m[1],m[2],m[3],m[4]
 local a21,a22,a23,a24=m[5],m[6],m[7],m[8]
 local a31,a32,a33,a34=m[9],m[10],m[11],m[12]
 local a41,a42,a43,a44=m[13],m[14],m[15],m[16]
 local s0=a11*a22-a21*a12
 local s1=a11*a23-a21*a13
 local s2=a11*a24-a21*a14
 local s3=a12*a23-a22*a13
 local s4=a12*a24-a22*a14
 local s5=a13*a24-a23*a14
 local c5=a33*a44-a43*a34
 local c4=a32*a44-a42*a34
 local c3=a32*a43-a42*a33
 local c2=a31*a44-a41*a34
 local c1=a31*a43-a41*a33
 local c0=a31*a42-a41*a32
 local det=s0*c5-s1*c4+s2*c3+s3*c2-s4*c1+s5*c0
 if abs(det)<1e-12 or not finite(det) then return nil end
 local d=1/det
 local r=table.create(16,0)
 r[1]=(a22*c5-a23*c4+a24*c3)*d
 r[2]=(-a12*c5+a13*c4-a14*c3)*d
 r[3]=(a42*s5-a43*s4+a44*s3)*d
 r[4]=(-a32*s5+a33*s4-a34*s3)*d
 r[5]=(-a21*c5+a23*c2-a24*c1)*d
 r[6]=(a11*c5-a13*c2+a14*c1)*d
 r[7]=(-a41*s5+a43*s2-a44*s1)*d
 r[8]=(a31*s5-a33*s2+a34*s1)*d
 r[9]=(a21*c4-a22*c2+a24*c0)*d
 r[10]=(-a11*c4+a12*c2-a14*c0)*d
 r[11]=(a41*s4-a42*s2+a44*s0)*d
 r[12]=(-a31*s4+a32*s2-a34*s0)*d
 r[13]=(-a21*c3+a22*c1-a23*c0)*d
 r[14]=(a11*c3-a12*c1+a13*c0)*d
 r[15]=(-a41*s3+a42*s1-a43*s0)*d
 r[16]=(a31*s3-a32*s1+a33*s0)*d
 for i=1,16 do if not finite(r[i]) then return nil end end
 return r
end
function X.plane(m)
 return {m[1],m[2],m[4],m[5],m[6],m[8],m[13],m[14],m[16]}
end
function X.invertPlane(h)
 local a,b,c,d,e,f,g,i,j=h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8],h[9]
 local det=a*(e*j-f*i)-b*(d*j-f*g)+c*(d*i-e*g)
 if abs(det)<1e-12 or not finite(det) then return nil end
 local s=1/det
 local out={(e*j-f*i)*s,(c*i-b*j)*s,(b*f-c*e)*s,(f*g-d*j)*s,(a*j-c*g)*s,(c*d-a*f)*s,(d*i-e*g)*s,(b*g-a*i)*s,(a*e-b*d)*s}
 for index=1,9 do if not finite(out[index]) then return nil end end
 return out
end
function X.mapPlane(h,x,y)
 local w=h[7]*x+h[8]*y+h[9]
 if w<=EPSILON then return nil end
 local u=(h[1]*x+h[2]*y+h[3])/w
 local v=(h[4]*x+h[5]*y+h[6])/w
 if not finite(u) or not finite(v) then return nil end
 return u,v
end
local function corners(box)
 local x0=tonumber(box.x) or 0
 local y0=tonumber(box.y) or 0
 local x1=x0+(tonumber(box.w) or 0)
 local y1=y0+(tonumber(box.h) or 0)
 return {{x0,y0},{x1,y0},{x1,y1},{x0,y1}}
end
X.corners=corners
function X.quad(m,box)
 if not m then
  local list=corners(box)
  local points={}
  for index,corner in ipairs(list) do points[index]={x=corner[1],y=corner[2],z=0,w=1} end
  return {valid=true,points=points,depth=0,bounds={x=points[1].x,y=points[1].y,w=points[3].x-points[1].x,h=points[3].y-points[1].y}}
 end
 local points={}
 local minX,minY,maxX,maxY
 local depth=0
 for index,corner in ipairs(corners(box)) do
  local px,py,pz=X.project(m,corner[1],corner[2],0)
  if not px then return {valid=false,points=points} end
  points[index]={x=px,y=py,z=pz,w=1}
  minX=minX and min(minX,px) or px
  minY=minY and min(minY,py) or py
  maxX=maxX and max(maxX,px) or px
  maxY=maxY and max(maxY,py) or py
  depth+=pz
 end
 return {valid=true,points=points,depth=depth/4,bounds={x=minX,y=minY,w=maxX-minX,h=maxY-minY}}
end
function X.boundsOf(m,box)
 local quad=X.quad(m,box)
 if not quad.valid then return nil end
 return quad.bounds
end
function X.sourceBounds(m,rect)
 local inverse=X.invertPlane(X.plane(m))
 if not inverse then return nil end
 local minX,minY,maxX,maxY
 for _,corner in ipairs(corners(rect)) do
  local u,v=X.mapPlane(inverse,corner[1],corner[2])
  if not u then return nil end
  minX=minX and min(minX,u) or u
  minY=minY and min(minY,v) or v
  maxX=maxX and max(maxX,u) or u
  maxY=maxY and max(maxY,v) or v
 end
 return {x=minX,y=minY,w=maxX-minX,h=maxY-minY}
end
function X.backFacing(m,box)
 if not m then return false end
 box=box or {x=0,y=0,w=1,h=1}
 local cx=(tonumber(box.x) or 0)+(tonumber(box.w) or 0)/2
 local cy=(tonumber(box.y) or 0)+(tonumber(box.h) or 0)/2
 local ax,ay=X.project(m,cx,cy,0)
 local bx,by=X.project(m,cx+1,cy,0)
 local dx,dy=X.project(m,cx,cy+1,0)
 if not ax or not bx or not dx then return false end
 return (bx-ax)*(dy-ay)-(by-ay)*(dx-ax)<0
end
function X.depth(m,box)
 local quad=X.quad(m,box)
 if not quad.valid then return 0 end
 return quad.depth
end
function X.contains(quad,x,y)
 if not quad or not quad.valid then return false end
 local points=quad.points
 local sign=0
 for index=1,4 do
  local a=points[index]
  local b=points[index%4+1]
  local cross=(b.x-a.x)*(y-a.y)-(b.y-a.y)*(x-a.x)
  if abs(cross)>1e-9 then
   local current=cross>0 and 1 or -1
   if sign==0 then sign=current elseif sign~=current then return false end
  end
 end
 return true
end
function X.unproject(m,x,y)
 if not m then return x,y end
 local inverse=X.invertPlane(X.plane(m))
 if not inverse then return nil end
 return X.mapPlane(inverse,x,y)
end
function X.hit(m,box,x,y)
 local u,v=X.unproject(m,x,y)
 if not u then return false end
 local x0=tonumber(box.x) or 0
 local y0=tonumber(box.y) or 0
 local x1=x0+(tonumber(box.w) or 0)
 local y1=y0+(tonumber(box.h) or 0)
 if u<x0 or v<y0 or u>x1 or v>y1 then return false,u,v end
 return true,u,v
end
function X.sort(list,depthOf)
 for index,node in ipairs(list) do node.depthSlot=index end
 table.sort(list,function(a,b)
  local da=depthOf and depthOf(a) or 0
  local db=depthOf and depthOf(b) or 0
  if abs(da-db)>1e-6 then return da<db end
  return a.depthSlot<b.depthSlot
 end)
 return list
end
function X.composite(dst,src,matrix,options)
 options=options or {}
 local opacity=clamp(options.opacity==nil and 1 or options.opacity,0,1)
 if opacity<=0 then return 0 end
 local sx=tonumber(options.sourceX) or 0
 local sy=tonumber(options.sourceY) or 0
 local dx=tonumber(options.destX) or 0
 local dy=tonumber(options.destY) or 0
 local placed=multiply(X.translate(-dx,-dy,0),multiply(matrix or identity(),X.translate(sx,sy,0)))
 local quad=X.quad(placed,{x=0,y=0,w=src.w,h=src.h})
 if not quad.valid then return 0 end
 local inverse=X.invertPlane(X.plane(placed))
 if not inverse then return 0 end
 local area=Tiles.rect(dst,quad.bounds.x,quad.bounds.y,quad.bounds.w,quad.bounds.h)
 if options.clip then area=Tiles.intersect(area,Tiles.rect(dst,options.clip.x,options.clip.y,options.clip.w,options.clip.h)) end
 if area.w<=0 or area.h<=0 then return 0 end
 local mode=options.mode or 'normal'
 local mask=options.mask
 local grid=clamp(floor(tonumber(options.samples) or 2),1,4)
 local step=1/grid
 local total=grid*grid
 local width=src.w
 local height=src.h
 local painted=0
 for y=area.y,area.y+area.h-1 do
  for x=area.x,area.x+area.w-1 do
   local r,g,b,a=0,0,0,0
   for sj=0,grid-1 do
    local py=y+(sj+0.5)*step
    for si=0,grid-1 do
     local px=x+(si+0.5)*step
     local u,v=X.mapPlane(inverse,px,py)
     if u and u>=0 and v>=0 and u<=width and v<=height then
      local color,alpha=Tiles.sample(src,u-0.5,v-0.5)
      if alpha>0 then
       r+=color.R*alpha
       g+=color.G*alpha
       b+=color.B*alpha
       a+=alpha
      end
     end
    end
   end
   if a>EPSILON then
    local factor=opacity
    if mask then factor*=clamp(mask(x+0.5,y+0.5),0,1) end
    if factor>0 then
     local color=Color3.new(clamp(r/a,0,1),clamp(g/a,0,1),clamp(b/a,0,1))
     if Tiles.blend(dst,x,y,color,a/total,mode,factor) then painted+=1 end
    end
   end
  end
 end
 return painted
end
return X
