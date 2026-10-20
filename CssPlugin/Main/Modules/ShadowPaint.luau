local V=require(script.Parent.VisualStyle)
local G=require(script.Parent.VisualGeometry)
local K=require(script.Parent.PaintPrimitives)
local Shapes=require(script.Parent.PaintShapes)
local Cost=require(script.Parent.CostModel)
local S={VERSION=1,MAX_KEYS=20,MAX_ROWS=160,MIN_ALPHA=1/512,MAX_BLUR=1000}
local function grow(radii,amount)
 if not radii then return nil end
 local out={};local any=false
 for i,c in ipairs(radii)do
  local x=c.x>0 and math.max(0,c.x+amount)or 0
  local y=c.y>0 and math.max(0,c.y+amount)or 0
  out[i]={x=x,y=y}
  if x>0 or y>0 then any=true end
 end
 if not any then return nil end
 return out
end
S.grow=grow
local function distance(rect,px,py)
 local x0,y0=rect.x,rect.y
 local x1,y1=rect.x+rect.w,rect.y+rect.h
 local r=rect.r
 local cx,cy,rx,ry
 if r then
  if r[1]and px<x0+r[1].x and py<y0+r[1].y then rx,ry=r[1].x,r[1].y;cx,cy=x0+rx,y0+ry
  elseif r[2]and px>x1-r[2].x and py<y0+r[2].y then rx,ry=r[2].x,r[2].y;cx,cy=x1-rx,y0+ry
  elseif r[3]and px>x1-r[3].x and py>y1-r[3].y then rx,ry=r[3].x,r[3].y;cx,cy=x1-rx,y1-ry
  elseif r[4]and px<x0+r[4].x and py>y1-r[4].y then rx,ry=r[4].x,r[4].y;cx,cy=x0+rx,y1-ry end
 end
 if cx and rx and ry and rx>0 and ry>0 then
  local nx=(px-cx)/rx;local ny=(py-cy)/ry
  local f=nx*nx+ny*ny-1
  local gx=2*(px-cx)/(rx*rx);local gy=2*(py-cy)/(ry*ry)
  local g=math.sqrt(gx*gx+gy*gy)
  if g<1e-9 then return -math.min(rx,ry)end
  return f/g
 end
 local dx=math.max(x0-px,px-x1)
 local dy=math.max(y0-py,py-y1)
 if dx>0 and dy>0 then return math.sqrt(dx*dx+dy*dy)end
 return math.max(dx,dy)
end
S.distance=distance
local function profile(d,blur)
 if blur<=.05 then return d<=0 and 1 or 0 end
 local t=3.404*d/blur
 if t>18 then return 0 end
 if t<-18 then return 1 end
 return 1/(1+math.exp(t))
end
local function coverage(rect,blur,px,py)
 if rect.w<=0 or rect.h<=0 then return 0 end
 return profile(distance(rect,px,py),blur)
end
S.coverage=coverage
local function layerRadii(radii,amount)
 local out={};local any=false
 for i=1,4 do
  local base=radii and radii[i]and radii[i].x or 0
  local r=math.max(0,base+amount);out[i]={x=r,y=r}
  if r>0 then any=true end
 end
 return any and out or nil
end
local function layers(k,parent,rect,s,z)
 local blur=s.blur
 local count=blur<=.05 and 1 or math.clamp(math.ceil(blur/3),4,16)
 local targets=table.create(count)
 for j=1,count do
  local d=blur<=.05 and 0 or -blur+2*blur*(j-.5)/count
  targets[j]=profile(d,blur)*s.alpha
 end
 local outside=0
 for j=count,1,-1 do
  local c=targets[j]
  local a=j==count and c or 1-(1-c)/math.max(1-outside,1e-6)
  a=math.clamp(a,0,1);outside=c
  local e=blur<=.05 and 0 or -blur+2*blur*j/count
  local w,h=rect.w+2*e,rect.h+2*e
  if a>S.MIN_ALPHA and w>.001 and h>.001 then
   local f=k:make('Frame','ShadowLayer',parent)
   f.Position=UDim2.fromOffset(rect.x-e,rect.y-e);f.Size=UDim2.fromOffset(w,h);f.ZIndex=z
   f.BackgroundColor3=s.color;f.BackgroundTransparency=1-a*k.opacity
   f:SetAttribute('CssPaintRole','box-shadow');f:SetAttribute('CssPaintAlpha',a)
   K.corner(k,f,layerRadii(rect.r,e))
  end
 end
end
 
 
local nativeSupport
local function nativeAvailable()
 if S.NATIVE==false then return false end
 if nativeSupport==nil then nativeSupport=pcall(function()local probe=Instance.new('UIShadow');probe:Destroy()end)end
 return nativeSupport
end
S.nativeAvailable=nativeAvailable
local function nativeShadow(k,parent,rect,s,z)
 local host=k:make('Frame','ShadowHost',parent)
 host.Position=UDim2.fromOffset(rect.x,rect.y);host.Size=UDim2.fromOffset(rect.w,rect.h);host.ZIndex=z
 host.BackgroundColor3=s.color;host.BackgroundTransparency=1
 host:SetAttribute('CssPaintRole','box-shadow')
 K.corner(k,host,rect.r)
 local shadow=k:make('UIShadow','Shadow',host)
 shadow.Color=s.color;shadow.Transparency=1-s.alpha*k.opacity
 shadow.BlurRadius=UDim.new(0,s.blur);shadow.Offset=UDim2.new();shadow.Spread=UDim2.new()
 shadow:SetAttribute('CssPaintRole','box-shadow');shadow:SetAttribute('CssPaintAlpha',s.alpha)
 return host
end
local function sampleBand(left,right,alphaAt)
 local width=right-left
 if width<=.01 then return nil end
 local count=math.clamp(math.floor(width/4)+2,2,S.MAX_KEYS)
 local values=table.create(count)
 local uniform=true
 local peak=0
 for i=1,count do
  local t=(i-1)/(count-1)
  local a=math.clamp(alphaAt(left+t*width),0,1)
  values[i]=a
  if a>peak then peak=a end
  if math.abs(a-values[1])>1/255 then uniform=false end
 end
 return {left=left,width=width,count=count,values=values,peak=peak,uniform=uniform}
end
local function sameBand(a,b)
 if a.count~=b.count or math.abs(a.left-b.left)>.01 or math.abs(a.width-b.width)>.01 then return false end
 local va,vb=a.values,b.values
 for i=1,a.count do if math.abs(va[i]-vb[i])>1/255 then return false end end
 return true
end
local function emitBand(k,parent,z,color,b,y,h)
 if h<=.001 or b.peak<=S.MIN_ALPHA then return end
 local left,width,count,values=b.left,b.width,b.count,b.values
 if b.uniform then k:solid(parent,left,y,width,h,color,values[1],z,'box-shadow');return end
 local frame=k:make('Frame','ShadowBand',parent)
 frame.Position=UDim2.fromOffset(left,y)
 frame.Size=UDim2.fromOffset(width,h)
 frame.ZIndex=z
 frame.BackgroundColor3=color
 frame.BackgroundTransparency=0
 frame:SetAttribute('CssPaintRole','box-shadow')
 frame:SetAttribute('CssPaintAlpha',b.peak)
 local stops=table.create(count)
 local raw=table.create(count)
 for i=1,count do
  local t=(i-1)/(count-1)
  stops[i]=NumberSequenceKeypoint.new(t,math.clamp(1-values[i]*k.opacity,0,1))
  raw[i]=string.format('%.4f,%.4f',t,values[i])
 end
 local gradient=k:make('UIGradient','Gradient',frame)
 gradient.Color=ColorSequence.new(color)
 gradient.Transparency=NumberSequence.new(stops)
 gradient.Rotation=0
 gradient:SetAttribute('CssAlphaStops',table.concat(raw,';'))
end
function S.plan(style,box,context)
 local value=style['box-shadow']
 if value==nil or value=='none'or value==''then return nil end
 local items=style._shadows
 if type(items)~='table'or #items==0 then items=V.shadows(value)end
 if #items==0 then return nil end
 Cost.cap('shadows',#items,'Sombras por elemento')
 local out=table.create(#items)
 for index,item in ipairs(items)do
  local lengths=item.lengths
  assert(type(lengths)=='table'and #lengths>=2 and #lengths<=4,'box-shadow: [inset] x y [blur] [spread] [cor].')
  local color,alpha=V.color(item.color or'currentColor',style.color)
  local x=G.length(lengths[1],box.w,context)or 0
  local y=G.length(lengths[2],box.h,context)or 0
  local blur=lengths[3]~=nil and(G.length(lengths[3],box.w,context)or 0)or 0
  local spread=lengths[4]~=nil and(G.length(lengths[4],box.w,context)or 0)or 0
  assert(blur>=0,'box-shadow: desfoque nao pode ser negativo.')
  assert(blur<=S.MAX_BLUR,'box-shadow: desfoque acima de '..S.MAX_BLUR..'px.')
  out[index]={x=x,y=y,blur=blur,spread=spread,inset=item.inset==true,color=color,alpha=alpha}
 end
 return out
end
 
 
function S.bands(k,parent,clip,bounds,shadow,z,alphaAt)
 local step=math.max(bounds.h/S.MAX_ROWS,math.min(k.step,math.max(1.5,shadow.blur/4)))
 local y=bounds.y
 local guard=0
 local pending
 local function flush()
  if not pending then return end
  for _,b in ipairs(pending.bands)do emitBand(k,parent,z,shadow.color,b,pending.y,pending.h)end
  pending=nil
 end
 while y<bounds.y+bounds.h-.001 do
  guard+=1
  if guard>S.MAX_ROWS+8 then break end
  local h=math.min(step,bounds.y+bounds.h-y)
  local mid=y+h/2
  local row={}
  for _,span in ipairs(K.spans(clip,mid))do
   local b=sampleBand(span[1],span[2],function(px)return alphaAt(px,mid)end)
   if b then row[#row+1]=b end
  end
  local merge=pending~=nil and #pending.bands==#row
  if merge then for i=1,#row do if not sameBand(pending.bands[i],row[i])then merge=false;break end end end
  if merge then pending.h=(y+h)-pending.y else flush();pending={y=y,h=h,bands=row}end
  y+=math.max(h,.001)
 end
 flush()
end
function S.draw(k,parent,shadows,geometry,zOuter,zInset)
 if not shadows or #shadows==0 then return 0 end
 local box=geometry.box
 local radii=geometry.radii
 local padding=geometry.padding or {x=0,y=0,w=box.w,h=box.h,r=radii}
 local shape=geometry.shape
 local border=Shapes.rect({x=0,y=0,w=box.w,h=box.h,r=radii})
 local painted=0
 for index=#shadows,1,-1 do
  local s=shadows[index]
  if s.alpha>.0005 then
   if s.inset then
    local rect={x=padding.x+s.x+s.spread,y=padding.y+s.y+s.spread,w=math.max(0,padding.w-s.spread*2),h=math.max(0,padding.h-s.spread*2),r=grow(padding.r,-s.spread)}
    local clip={x=padding.x,y=padding.y,w=padding.w,h=padding.h,r=padding.r,shape=shape}
    if s.blur<=.05 then
     clip.hole=Shapes.rect(rect)
     K.fill(k,parent,clip,s.color,s.alpha,zInset,'box-shadow')
    else
     S.bands(k,parent,clip,{x=padding.x,y=padding.y,w=padding.w,h=padding.h},s,zInset,function(px,py)return (1-coverage(rect,s.blur,px,py))*s.alpha end)
    end
    painted+=1
   else
    local rect={x=s.x-s.spread,y=s.y-s.spread,w=math.max(0,box.w+s.spread*2),h=math.max(0,box.h+s.spread*2),r=grow(radii,s.spread)}
    if rect.w>.001 and rect.h>.001 then
     if geometry.opaque and not shape and K.circular(rect.r,rect.w,rect.h)then
      if nativeAvailable()then nativeShadow(k,parent,rect,s,zOuter)else layers(k,parent,rect,s,zOuter)end
     elseif s.blur<=.05 then
      local clip={x=rect.x,y=rect.y,w=rect.w,h=rect.h,r=rect.r,shape=shape,hole=border}
      K.fill(k,parent,clip,s.color,s.alpha,zOuter,'box-shadow')
     else
      local pad=s.blur*1.5+2
      local bounds={x=rect.x-pad,y=rect.y-pad,w=rect.w+pad*2,h=rect.h+pad*2}
      local clip={x=bounds.x,y=bounds.y,w=bounds.w,h=bounds.h,shape=shape,hole=border}
      S.bands(k,parent,clip,bounds,s,zOuter,function(px,py)return coverage(rect,s.blur,px,py)*s.alpha end)
     end
     painted+=1
    end
   end
  end
 end
 return painted
end
function S.extent(shadows)
 local out=0
 for _,s in ipairs(shadows or {})do
  if not s.inset then
   out=math.max(out,math.abs(s.x)+s.spread+s.blur*1.5,math.abs(s.y)+s.spread+s.blur*1.5)
  end
 end
 return out
end
return S
