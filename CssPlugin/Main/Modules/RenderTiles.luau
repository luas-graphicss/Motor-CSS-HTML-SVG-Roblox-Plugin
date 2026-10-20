local Pixels=require(script.Parent.VisualEffectsPixels)
local Regions=require(script.Parent.DirtyRegions)
local Budget=require(script.Parent.RenderBudget)
local T={VERSION=1}
local read=buffer.readf32
local write=buffer.writef32
local clamp=math.clamp
local floor=math.floor
local black=Color3.new()
function T.new(width,height,options)
 options=options or {}
 local plan=options.plan or Budget.plan(width,height,options)
 local self={w=plan.width,h=plan.height,tile=plan.tile,cols=plan.cols,rows=plan.rows,span=plan.span,tiles={},bytes=0,budget=plan.budget,plan=plan,allocated=0,writes=0,label=options.label or 'Superficie de render'}
 self.regions=Regions.new({limit=options.regions or 32,slack=options.slack or 1,viewport={w=self.w,h=self.h}})
 self.regions:markFull('nova superficie')
 self.budget.counts.surfaces+=1
 return self
end
function T.tileBytes(s) return s.tile*s.tile*16 end
function T.tile(s,tx,ty,create)
 if tx<0 or ty<0 or tx>=s.cols or ty>=s.rows then return nil end
 local key=ty*s.cols+tx
 local data=s.tiles[key]
 if data or not create then return data end
 local bytes=T.tileBytes(s)
 s.budget:spend(bytes,s.label,'tiles')
 data=buffer.create(bytes)
 s.tiles[key]=data
 s.bytes+=bytes
 s.allocated+=1
 return data
end
function T.at(s,x,y,create)
 if x<0 or y<0 or x>=s.w or y>=s.h then return nil,0 end
 local data=T.tile(s,floor(x/s.tile),floor(y/s.tile),create)
 if not data then return nil,0 end
 return data,((y%s.tile)*s.tile+(x%s.tile))*16
end
function T.raw(s,x,y)
 local data,i=T.at(s,floor(x),floor(y),false)
 if not data then return 0,0,0,0 end
 return read(data,i),read(data,i+4),read(data,i+8),read(data,i+12)
end
function T.setRaw(s,x,y,r,g,b,a)
 local data,i=T.at(s,floor(x),floor(y),a>0 or r>0 or g>0 or b>0)
 if not data then return false end
 write(data,i,r);write(data,i+4,g);write(data,i+8,b);write(data,i+12,a)
 s.writes+=1
 return true
end
function T.get(s,x,y)
 local data,i=T.at(s,floor(x),floor(y),false)
 if not data then return black,0 end
 local a=read(data,i+12)
 if a<=1e-9 then return black,0 end
 return Color3.new(clamp(read(data,i)/a,0,1),clamp(read(data,i+4)/a,0,1),clamp(read(data,i+8)/a,0,1)),clamp(a,0,1)
end
function T.set(s,x,y,color,alpha)
 alpha=clamp(alpha or 0,0,1)
 local data,i=T.at(s,floor(x),floor(y),alpha>0)
 if not data then return false end
 write(data,i,color.R*alpha);write(data,i+4,color.G*alpha);write(data,i+8,color.B*alpha);write(data,i+12,alpha)
 s.writes+=1
 return true
end
function T.blend(s,x,y,color,alpha,mode,coverage)
 local a=clamp((alpha or 0)*(coverage==nil and 1 or coverage),0,1)
 if a<=1e-6 then return false end
 x=floor(x);y=floor(y)
 if mode==nil or mode=='normal' then
  local data,i=T.at(s,x,y,true)
  if not data then return false end
  local keep=1-a
  write(data,i,color.R*a+read(data,i)*keep)
  write(data,i+4,color.G*a+read(data,i+4)*keep)
  write(data,i+8,color.B*a+read(data,i+8)*keep)
  write(data,i+12,a+read(data,i+12)*keep)
  s.writes+=1
  return true
 end
 local back,ba=T.get(s,x,y)
 local mixed,mixedAlpha=Pixels.over(back,ba,color,a,mode)
 return T.set(s,x,y,mixed,mixedAlpha)
end
function T.sample(s,x,y)
 local x0=floor(x)
 local y0=floor(y)
 local fx=x-x0
 local fy=y-y0
 local r,g,b,a=0,0,0,0
 for dy=0,1 do
  for dx=0,1 do
   local pr,pg,pb,pa=T.raw(s,x0+dx,y0+dy)
   local f=(dx==0 and 1-fx or fx)*(dy==0 and 1-fy or fy)
   r+=pr*f;g+=pg*f;b+=pb*f;a+=pa*f
  end
 end
 if a<=1e-9 then return black,0 end
 return Color3.new(clamp(r/a,0,1),clamp(g/a,0,1),clamp(b/a,0,1)),clamp(a,0,1)
end
function T.full(s) return {x=0,y=0,w=s.w,h=s.h} end
function T.rect(s,x,y,w,h)
 local ox=tonumber(x) or 0
 local oy=tonumber(y) or 0
 local x0=math.max(0,floor(ox))
 local y0=math.max(0,floor(oy))
 local x1=math.min(s.w,math.ceil(ox+(tonumber(w) or 0)))
 local y1=math.min(s.h,math.ceil(oy+(tonumber(h) or 0)))
 return {x=x0,y=y0,w=math.max(0,x1-x0),h=math.max(0,y1-y0)}
end
function T.intersect(a,b)
 local x=math.max(a.x,b.x)
 local y=math.max(a.y,b.y)
 return {x=x,y=y,w=math.max(0,math.min(a.x+a.w,b.x+b.w)-x),h=math.max(0,math.min(a.y+a.h,b.y+b.h)-y)}
end
function T.tilesIn(s,area)
 local r=area and T.rect(s,area.x,area.y,area.w,area.h) or T.full(s)
 local out={}
 if r.w<=0 or r.h<=0 then return out end
 for ty=floor(r.y/s.tile),floor((r.y+r.h-1)/s.tile) do
  for tx=floor(r.x/s.tile),floor((r.x+r.w-1)/s.tile) do
   local ox=tx*s.tile
   local oy=ty*s.tile
   out[#out+1]={tx=tx,ty=ty,x=ox,y=oy,w=math.min(s.tile,s.w-ox),h=math.min(s.tile,s.h-oy),allocated=T.tile(s,tx,ty,false)~=nil}
  end
 end
 return out
end
function T.clear(s,area)
 local r=area and T.rect(s,area.x,area.y,area.w,area.h) or T.full(s)
 if r.w<=0 or r.h<=0 then return s end
 for _,entry in ipairs(T.tilesIn(s,r)) do
  local data=T.tile(s,entry.tx,entry.ty,false)
  if data then
   local left=math.max(r.x,entry.x)
   local right=math.min(r.x+r.w,entry.x+entry.w)
   local top=math.max(r.y,entry.y)
   local bottom=math.min(r.y+r.h,entry.y+entry.h)
   if left<=entry.x and top<=entry.y and right>=entry.x+entry.w and bottom>=entry.y+entry.h then
    buffer.fill(data,0,0)
   else
    for y=top,bottom-1 do
     buffer.fill(data,((y-entry.y)*s.tile+(left-entry.x))*16,0,(right-left)*16)
    end
   end
  end
 end
 return s
end
function T.invalidate(s,x,y,w,h)
 if x==nil then return s.regions:markFull('completo') end
 return s.regions:add(x,y,w,h)
end
function T.invalidateBox(s,box) return s.regions:addBox(box) end
function T.invalidateAll(s,reason) return s.regions:markFull(reason or 'completo') end
function T.dirty(s) return s.regions:list() end
function T.touches(s,box) return s.regions:touches(box) end
function T.flush(s)
 local out=s.regions:flush()
 local rects={}
 if out.full then
  rects[1]=T.full(s)
 else
  for _,r in ipairs(out.rects) do
   local clipped=T.rect(s,r.x,r.y,r.w,r.h)
   if clipped.w>0 and clipped.h>0 then rects[#rects+1]=clipped end
  end
 end
 out.rects=rects
 return out
end
function T.composite(dst,src,dx,dy,options)
 options=options or {}
 local opacity=clamp(options.opacity==nil and 1 or options.opacity,0,1)
 if opacity<=0 then return 0 end
 dx=floor(dx or 0)
 dy=floor(dy or 0)
 local area=T.rect(dst,dx,dy,src.w,src.h)
 if options.clip then area=T.intersect(area,T.rect(dst,options.clip.x,options.clip.y,options.clip.w,options.clip.h)) end
 if area.w<=0 or area.h<=0 then return 0 end
 local mode=options.mode or 'normal'
 local mask=options.mask
 local painted=0
 for y=area.y,area.y+area.h-1 do
  for x=area.x,area.x+area.w-1 do
   local color,alpha=T.get(src,x-dx,y-dy)
   if alpha>0 then
    local factor=opacity
    if mask then factor*=clamp(mask(x+0.5,y+0.5),0,1) end
    if factor>0 and T.blend(dst,x,y,color,alpha,mode,factor) then painted+=1 end
   end
  end
 end
 return painted
end
function T.colorize(s,area,filters)
 local r=area and T.rect(s,area.x,area.y,area.w,area.h) or T.full(s)
 for y=r.y,r.y+r.h-1 do
  for x=r.x,r.x+r.w-1 do
   local color,alpha=T.get(s,x,y)
   if alpha>0 then
    local nc,na=Pixels.colors(color,alpha,filters)
    T.set(s,x,y,nc,na)
   end
  end
 end
 return s
end
function T.blur(s,area,sigma)
 sigma=math.min(math.max(tonumber(sigma) or 0,0),64)
 if sigma<=0.01 then return s end
 local r=area and T.rect(s,area.x,area.y,area.w,area.h) or T.full(s)
 if r.w<=0 or r.h<=0 then return s end
 local radius=math.min(192,math.ceil(3*sigma))
 local kernel={}
 local total=0
 for i=-radius,radius do
  local n=math.exp(-i*i/(2*sigma*sigma))
  kernel[i+radius+1]=n
  total+=n
 end
 for i=1,#kernel do kernel[i]/=total end
 local bytes=r.w*r.h*16
 s.budget:spend(bytes,'Desfoque do render core','scratch')
 local scratch=buffer.create(bytes)
 for y=0,r.h-1 do
  for x=0,r.w-1 do
   local cr,cg,cb,ca=0,0,0,0
   for d=math.max(-radius,-x),math.min(radius,r.w-1-x) do
    local pr,pg,pb,pa=T.raw(s,r.x+x+d,r.y+y)
    local f=kernel[d+radius+1]
    cr+=pr*f;cg+=pg*f;cb+=pb*f;ca+=pa*f
   end
   local i=(y*r.w+x)*16
   write(scratch,i,cr);write(scratch,i+4,cg);write(scratch,i+8,cb);write(scratch,i+12,ca)
  end
 end
 for y=0,r.h-1 do
  for x=0,r.w-1 do
   local cr,cg,cb,ca=0,0,0,0
   for d=math.max(-radius,-y),math.min(radius,r.h-1-y) do
    local i=((y+d)*r.w+x)*16
    local f=kernel[d+radius+1]
    cr+=read(scratch,i)*f;cg+=read(scratch,i+4)*f;cb+=read(scratch,i+8)*f;ca+=read(scratch,i+12)*f
   end
   T.setRaw(s,r.x+x,r.y+y,cr,cg,cb,ca)
  end
 end
 s.budget:refund(bytes)
 return s
end
function T.maskWith(s,area,fn)
 local r=area and T.rect(s,area.x,area.y,area.w,area.h) or T.full(s)
 for y=r.y,r.y+r.h-1 do
  for x=r.x,r.x+r.w-1 do
   local pr,pg,pb,pa=T.raw(s,x,y)
   if pa>0 then
    local f=clamp(fn(x+0.5,y+0.5),0,1)
    T.setRaw(s,x,y,pr*f,pg*f,pb*f,pa*f)
   end
  end
 end
 return s
end
function T.rgba(s,area)
 local r=area and T.rect(s,area.x,area.y,area.w,area.h) or T.full(s)
 local out=buffer.create(math.max(1,r.w*r.h)*4)
 for y=0,r.h-1 do
  for x=0,r.w-1 do
   local color,alpha=T.get(s,r.x+x,r.y+y)
   local i=(y*r.w+x)*4
   buffer.writeu8(out,i,floor(color.R*255+0.5))
   buffer.writeu8(out,i+1,floor(color.G*255+0.5))
   buffer.writeu8(out,i+2,floor(color.B*255+0.5))
   buffer.writeu8(out,i+3,floor(alpha*255+0.5))
  end
 end
 return out,r
end
function T.fromPixels(source,options)
 local s=T.new(source.w,source.h,options)
 for y=0,source.h-1 do
  for x=0,source.w-1 do
   local color,alpha=Pixels.get(source,x,y)
   if alpha>0 then T.set(s,x,y,color,alpha) end
  end
 end
 return s
end
function T.toPixels(s,area)
 local r=area and T.rect(s,area.x,area.y,area.w,area.h) or T.full(s)
 local out=Pixels.new(r.w,r.h)
 for y=0,r.h-1 do
  for x=0,r.w-1 do
   local color,alpha=T.get(s,r.x+x,r.y+y)
   if alpha>0 then Pixels.set(out,x,y,color,alpha) end
  end
 end
 return out
end
function T.clone(s,label)
 local copy=T.new(s.w,s.h,{budget=s.budget,tile=s.tile,capability=s.plan.capability,label=label or s.label})
 for key,data in pairs(s.tiles) do
  local target=T.tile(copy,key%s.cols,floor(key/s.cols),true)
  buffer.copy(target,0,data)
 end
 copy.regions:markFull('clone')
 return copy
end
function T.release(s)
 if s.bytes>0 then s.budget:refund(s.bytes) end
 table.clear(s.tiles)
 s.bytes=0
 s.allocated=0
 s.regions:markFull('liberado')
 return s
end
function T.stats(s)
 return {width=s.w,height=s.h,tile=s.tile,cols=s.cols,rows=s.rows,tiles=s.allocated,capacity=s.cols*s.rows,bytes=s.bytes,bytesPerPixel=Budget.BYTES_PER_PIXEL,writes=s.writes,dirty=s.regions:count(),budget=s.budget:report()}
end
return T
