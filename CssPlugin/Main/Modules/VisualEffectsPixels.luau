local P={VERSION=3,MAX_SIDE=512,MAX_PIXELS=262144,HARD_SIDE=4096,HARD_PIXELS=1048576}
local clamp=math.clamp;local read,write=buffer.readf32,buffer.writef32
local function alloc(w,h)return {w=w,h=h,data=buffer.create(w*h*16)}end
function P.new(w,h,limit)
 w,h=math.max(1,math.ceil(w)),math.max(1,math.ceil(h))
 local side=math.min(limit and limit.side or P.MAX_SIDE,P.HARD_SIDE)
 local pixels=math.min(limit and limit.pixels or P.MAX_PIXELS,P.HARD_PIXELS)
 assert(w<=side and h<=side and w*h<=pixels,string.format('Superfície de efeito excede %dpx/%d pixels.',side,pixels))
 return alloc(w,h)
end
function P.like(s)return alloc(s.w,s.h)end
function P.clone(s)local out=alloc(s.w,s.h);buffer.copy(out.data,0,s.data);return out end
function P.get(s,x,y)
 if x<0 or y<0 or x>=s.w or y>=s.h then return Color3.new(),0 end
 local i=(math.floor(y)*s.w+math.floor(x))*16;local a=read(s.data,i+12)
 if a<=1e-9 then return Color3.new(),0 end
 return Color3.new(clamp(read(s.data,i)/a,0,1),clamp(read(s.data,i+4)/a,0,1),clamp(read(s.data,i+8)/a,0,1)),a
end
function P.set(s,x,y,c,a)
 if x<0 or y<0 or x>=s.w or y>=s.h then return end
 a=clamp(a,0,1);local i=(math.floor(y)*s.w+math.floor(x))*16
 write(s.data,i,c.R*a);write(s.data,i+4,c.G*a);write(s.data,i+8,c.B*a);write(s.data,i+12,a)
end
function P.sample(s,x,y)
 local x0,y0=math.floor(x),math.floor(y);local fx,fy=x-x0,y-y0;local r,g,b,a=0,0,0,0
 for dy=0,1 do for dx=0,1 do
  local xx,yy=x0+dx,y0+dy
  if xx>=0 and yy>=0 and xx<s.w and yy<s.h then
   local f=(dx==0 and 1-fx or fx)*(dy==0 and 1-fy or fy);local i=(yy*s.w+xx)*16
   r+=read(s.data,i)*f;g+=read(s.data,i+4)*f;b+=read(s.data,i+8)*f;a+=read(s.data,i+12)*f
  end
 end end
 return a>1e-9 and Color3.new(clamp(r/a,0,1),clamp(g/a,0,1),clamp(b/a,0,1))or Color3.new(),clamp(a,0,1)
end
local function lum(c)return .3*c.R+.59*c.G+.11*c.B end
local function sat(c)return math.max(c.R,c.G,c.B)-math.min(c.R,c.G,c.B)end
local function setLum(c,l)
 local d=l-lum(c);local r,g,b=c.R+d,c.G+d,c.B+d;local lo,hi=math.min(r,g,b),math.max(r,g,b)
 if lo<0 then local f=l/math.max(l-lo,1e-12);r=l+(r-l)*f;g=l+(g-l)*f;b=l+(b-l)*f end
 if hi>1 then local f=(1-l)/math.max(hi-l,1e-12);r=l+(r-l)*f;g=l+(g-l)*f;b=l+(b-l)*f end
 return Color3.new(clamp(r,0,1),clamp(g,0,1),clamp(b,0,1))
end
local function setSat(c,s)
 local values={{v=c.R,k=1},{v=c.G,k=2},{v=c.B,k=3}};table.sort(values,function(a,b)return a.v<b.v end)
 local lo,mid,hi=values[1].v,values[2].v,values[3].v;local result={0,0,0}
 if hi>lo then result[values[2].k]=(mid-lo)*s/(hi-lo);result[values[3].k]=s end
 return Color3.new(result[1],result[2],result[3])
end
local function channel(b,s,m)
 if m=='normal'then return s elseif m=='multiply'then return b*s elseif m=='screen'then return b+s-b*s
 elseif m=='overlay'then return b<=.5 and 2*b*s or 1-2*(1-b)*(1-s)
 elseif m=='darken'then return math.min(b,s)elseif m=='lighten'then return math.max(b,s)
 elseif m=='color-dodge'then return b<=0 and 0 or s>=1 and 1 or math.min(1,b/(1-s))
 elseif m=='color-burn'then return b>=1 and 1 or s<=0 and 0 or 1-math.min(1,(1-b)/s)
 elseif m=='hard-light'then return s<=.5 and 2*b*s or 1-2*(1-b)*(1-s)
 elseif m=='soft-light'then local d=b<=.25 and ((16*b-12)*b+4)*b or math.sqrt(b);return s<=.5 and b-(1-2*s)*b*(1-b)or b+(2*s-1)*(d-b)
 elseif m=='difference'then return math.abs(b-s)elseif m=='exclusion'then return b+s-2*b*s end
 error('Blend mode desconhecido: '..tostring(m),0)
end
function P.blend(back,source,mode)
 mode=mode or 'normal'
 if mode=='hue'then return setLum(setSat(source,sat(back)),lum(back))
 elseif mode=='saturation'then return setLum(setSat(back,sat(source)),lum(back))
 elseif mode=='color'then return setLum(source,lum(back))elseif mode=='luminosity'then return setLum(back,lum(source))end
 return Color3.new(channel(back.R,source.R,mode),channel(back.G,source.G,mode),channel(back.B,source.B,mode))
end
function P.over(back,ba,source,sa,mode)
 ba,sa=clamp(ba,0,1),clamp(sa,0,1);local a=sa+ba*(1-sa);if a<=1e-9 then return Color3.new(),0 end
 local mixed=P.blend(back,source,mode)
 return Color3.new(((1-sa)*ba*back.R+(1-ba)*sa*source.R+ba*sa*mixed.R)/a,((1-sa)*ba*back.G+(1-ba)*sa*source.G+ba*sa*mixed.G)/a,((1-sa)*ba*back.B+(1-ba)*sa*source.B+ba*sa*mixed.B)/a),a
end
function P.composite(dst,src,dx,dy,mode,opacity)
 dx,dy=dx or 0,dy or 0;opacity=opacity or 1
 for y=math.max(0,math.floor(dy)),math.min(dst.h-1,math.ceil(dy+src.h)-1)do for x=math.max(0,math.floor(dx)),math.min(dst.w-1,math.ceil(dx+src.w)-1)do
  local c,a=P.sample(src,x-dx,y-dy);if a>0 then local b,ba=P.get(dst,x,y);local o,oa=P.over(b,ba,c,a*opacity,mode);P.set(dst,x,y,o,oa)end
 end end;return dst
end
function P.color(c,a,f)
 local r,g,b=c.R,c.G,c.B;local n=f.value or 0;local name=f.name
 if name=='brightness'then r*=n;g*=n;b*=n
 elseif name=='contrast'then r=(r-.5)*n+.5;g=(g-.5)*n+.5;b=(b-.5)*n+.5
 elseif name=='invert'then r=r*(1-2*n)+n;g=g*(1-2*n)+n;b=b*(1-2*n)+n
 elseif name=='grayscale'then local l=.2126*r+.7152*g+.0722*b;r=r*(1-n)+l*n;g=g*(1-n)+l*n;b=b*(1-n)+l*n
 elseif name=='sepia'then r,g,b=r*(1-.607*n)+g*.769*n+b*.189*n,r*.349*n+g*(1-.314*n)+b*.168*n,r*.272*n+g*.534*n+b*(1-.869*n)
 elseif name=='saturate'then local l=.213*r+.715*g+.072*b;r=l+(r-l)*n;g=l+(g-l)*n;b=l+(b-l)*n
 elseif name=='hue-rotate'then
  local co,si=math.cos(n),math.sin(n)
  r,g,b=r*(.213+.787*co-.213*si)+g*(.715-.715*co-.715*si)+b*(.072-.072*co+.928*si),r*(.213-.213*co+.143*si)+g*(.715+.285*co+.140*si)+b*(.072-.072*co-.283*si),r*(.213-.213*co-.787*si)+g*(.715-.715*co+.715*si)+b*(.072+.928*co+.072*si)
 elseif name=='opacity'then a*=n
 end
 return Color3.new(clamp(r,0,1),clamp(g,0,1),clamp(b,0,1)),clamp(a,0,1)
end
function P.colors(c,a,filters)for _,f in ipairs(filters)do c,a=P.color(c,a,f)end;return c,a end
function P.blur(src,sigma,checkpoint)
 if sigma<=.01 then return P.clone(src)end
 sigma=math.min(sigma,64);local radius=math.min(192,math.ceil(3*sigma));local kernel,total={},0
 for i=-radius,radius do local n=math.exp(-i*i/(2*sigma*sigma));kernel[i+radius+1]=n;total+=n end
 for i=1,#kernel do kernel[i]/=total end
 local function pass(s,horizontal)
  local out=alloc(s.w,s.h)
  for y=0,s.h-1 do
   for x=0,s.w-1 do
    local r,g,b,a=0,0,0,0
    local low=math.max(-radius,horizontal and -x or -y);local high=math.min(radius,horizontal and s.w-1-x or s.h-1-y)
    for d=low,high do
     local xx,yy=x+(horizontal and d or 0),y+(horizontal and 0 or d);local i=(yy*s.w+xx)*16;local f=kernel[d+radius+1]
     r+=read(s.data,i)*f;g+=read(s.data,i+4)*f;b+=read(s.data,i+8)*f;a+=read(s.data,i+12)*f
    end
    local i=(y*s.w+x)*16;write(out.data,i,r);write(out.data,i+4,g);write(out.data,i+8,b);write(out.data,i+12,a)
   end
   if checkpoint and y%8==0 then checkpoint(32)end
  end;return out
 end
 return pass(pass(src,true),false)
end
function P.filter(src,filters,scale,checkpoint)
 local out=P.clone(src);scale=scale or 1
 for _,f in ipairs(filters)do
  if f.name=='blur'then out=P.blur(out,f.value*scale,checkpoint)
  elseif f.name=='drop-shadow'then
   local color,alpha=require(script.Parent.Util).color(f.ink);local shadow=alloc(out.w,out.h)
   for y=0,out.h-1 do for x=0,out.w-1 do local _,a=P.get(out,x,y);P.set(shadow,x,y,color,a*alpha)end end
   shadow=P.blur(shadow,f.blur*scale,checkpoint);local layer=alloc(out.w,out.h);P.composite(layer,shadow,f.x*scale,f.y*scale);P.composite(layer,out);out=layer
  else
   for y=0,out.h-1 do for x=0,out.w-1 do local c,a=P.get(out,x,y);c,a=P.color(c,a,f);P.set(out,x,y,c,a)end;if checkpoint and y%16==0 then checkpoint(16)end end
  end
 end;return out
end
function P.mask(src,fn)
 for y=0,src.h-1 do for x=0,src.w-1 do
  local i=(y*src.w+x)*16;local a=clamp(fn(x,y),0,1)
  for k=0,3 do write(src.data,i+k*4,read(src.data,i+k*4)*a)end
 end end;return src
end
function P.rgba(s)
 local out=buffer.create(s.w*s.h*4)
 for y=0,s.h-1 do for x=0,s.w-1 do local c,a=P.get(s,x,y);local i=(y*s.w+x)*4
  buffer.writeu8(out,i,math.floor(c.R*255+.5));buffer.writeu8(out,i+1,math.floor(c.G*255+.5));buffer.writeu8(out,i+2,math.floor(c.B*255+.5));buffer.writeu8(out,i+3,math.floor(a*255+.5))
 end end;return out
end
function P.resample(src,w,h)
 w,h=math.max(1,math.floor(w)),math.max(1,math.floor(h))
 if w==src.w and h==src.h then return P.clone(src)end
 local out=P.new(w,h,{side=math.max(w,h),pixels=w*h})
 local sx,sy=src.w/w,src.h/h
 for y=0,h-1 do
  local y0,y1=y*sy,(y+1)*sy
  local fy0,fy1=math.floor(y0),math.min(src.h-1,math.ceil(y1)-1)
  for x=0,w-1 do
   local x0,x1=x*sx,(x+1)*sx
   local fx0,fx1=math.floor(x0),math.min(src.w-1,math.ceil(x1)-1)
   local r,g,b,a,weight=0,0,0,0,0
   for yy=fy0,fy1 do
    local cy=math.min(y1,yy+1)-math.max(y0,yy)
    if cy>0 then
     for xx=fx0,fx1 do
      local cx=math.min(x1,xx+1)-math.max(x0,xx)
      if cx>0 then
       local i=(yy*src.w+xx)*16;local k=cx*cy
       r+=read(src.data,i)*k;g+=read(src.data,i+4)*k;b+=read(src.data,i+8)*k;a+=read(src.data,i+12)*k;weight+=k
      end
     end
    end
   end
   if weight>0 then
    local i=(y*w+x)*16
    write(out.data,i,r/weight);write(out.data,i+4,g/weight);write(out.data,i+8,b/weight);write(out.data,i+12,clamp(a/weight,0,1))
   end
  end
 end
 return out
end
function P.fromRGBA(w,h,data)
 assert(buffer.len(data)==w*h*4,'RGBA de imagem incompleto.');local s=P.new(w,h,{side=math.max(w,h),pixels=w*h})
 for y=0,h-1 do for x=0,w-1 do local i=(y*w+x)*4;P.set(s,x,y,Color3.fromRGB(buffer.readu8(data,i),buffer.readu8(data,i+1),buffer.readu8(data,i+2)),buffer.readu8(data,i+3)/255)end end;return s
end
return P
