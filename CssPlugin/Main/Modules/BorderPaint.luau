local U=require(script.Parent.Util)
local V=require(script.Parent.VisualStyle)
local G=require(script.Parent.VisualGeometry)
local Gradient=require(script.Parent.CssGradient)
local Images=require(script.Parent.BackgroundImages)
local K=require(script.Parent.PaintPrimitives)
local SideBorders=require(script.Parent.SideBorders)
local Shapes=require(script.Parent.PaintShapes)
local B={}
local function inset(rect,n)
 return {x=rect.x+n,y=rect.y+n,w=math.max(0,rect.w-2*n),h=math.max(0,rect.h-2*n),r=G.insetRadii(rect.r,n,n,n,n)}
end
local function tinted(c,light)
 return light and c:Lerp(Color3.new(1,1,1),.42)or c:Lerp(Color3.new(),.42)
end
local function piece(k,parent,x,y,w,h,color,alpha,z,shape,mid)
 if not shape then return k:solid(parent,x,y,w,h,color,alpha,z)end
 for _,span in ipairs(Shapes.intersect({{x,x+w}},shape.rows(mid)))do
  k:solid(parent,span[1],y,span[2]-span[1],h,color,alpha,z)
 end
 return nil
end
local function ring(k,parent,outer,inner,color,alpha,z,shaded,reverse,shape)
 local y=outer.y
 while y<outer.y+outer.h-.001 do
  local h=math.min(k.step,outer.y+outer.h-y);local mid=y+h/2;local l,r=K.bounds(outer,mid);local il,ir=K.bounds(inner,mid)
  if inner.w<=0 or inner.h<=0 then il,ir=0,0 end
  local cuts={l,r};if ir>il then cuts[#cuts+1]=math.clamp(il,l,r);cuts[#cuts+1]=math.clamp(ir,l,r)end
  if shaded then
   local top,bottom=mid-outer.y,outer.y+outer.h-mid
   for _,x in ipairs({outer.x+top,outer.x+bottom,outer.x+outer.w-top,outer.x+outer.w-bottom})do if x>l and x<r then cuts[#cuts+1]=x end end
  end
  table.sort(cuts)
  for i=1,#cuts-1 do local a,b=cuts[i],cuts[i+1];local x=(a+b)/2
   if b-a>.001 and not(ir>il and x>=il and x<ir)then
    local c=color
    if shaded then
     local leading=math.min(x-outer.x,mid-outer.y)<=math.min(outer.x+outer.w-x,outer.y+outer.h-mid)
     c=tinted(color,reverse and not leading or not reverse and leading)
    end
    piece(k,parent,a,y,b-a,h,c,alpha,z,shape,mid)
   end
  end;y+=h
 end
end
function B.path(rect,width)
 local mid=inset(rect,width/2);local points={};local total=0
 local function add(x,y)
  local last=points[#points];if last then total+=math.sqrt((x-last.x)^2+(y-last.y)^2)end
  points[#points+1]={x=x,y=y,d=total}
 end
 local r=mid.r;local x,y,w,h=mid.x,mid.y,mid.w,mid.h
 add(x+r[1].x,y);add(x+w-r[2].x,y)
 local function arc(cx,cy,rx,ry,a,b)
  local count=math.clamp(math.ceil(math.max(rx,ry)*(b-a)/2),1,128)
  for i=1,count do local angle=a+(b-a)*i/count;add(cx+rx*math.cos(angle),cy+ry*math.sin(angle))end
 end
 arc(x+w-r[2].x,y+r[2].y,r[2].x,r[2].y,-math.pi/2,0);add(x+w,y+h-r[3].y)
 arc(x+w-r[3].x,y+h-r[3].y,r[3].x,r[3].y,0,math.pi/2);add(x+r[4].x,y+h)
 arc(x+r[4].x,y+h-r[4].y,r[4].x,r[4].y,math.pi/2,math.pi);add(x,y+r[1].y)
 arc(x+r[1].x,y+r[1].y,r[1].x,r[1].y,math.pi,math.pi*1.5)
 return points,total
end
local function pointAt(points,d)
 for i=2,#points do local b=points[i];if d<=b.d then local a=points[i-1];local t=(d-a.d)/math.max(b.d-a.d,1e-9);return a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t end end
 local p=points[#points];return p.x,p.y
end
function B.stroke(k,parent,style,box,context,z,shape)
 if style._hasSideBorders then return SideBorders.draw(k,parent,SideBorders.prepare(style,box,context,B.path),z,shape)end
 local width=G.length(style['border-width']or 0,box.w,context);local mode=style['border-style']or 'solid'
 assert(V.borderStyles[mode],'border-style não suportado: '..tostring(mode))
 if mode=='none'or mode=='hidden'or width<=0 then return end
 assert(width>=0,'border-width não pode ser negativo.');width=math.min(width,math.max(box.w,box.h))
 local color,alpha=V.color(style['border-color']or 'currentColor',style.color)
 local outer={x=0,y=0,w=box.w,h=box.h,r=G.radii(style,box.w,box.h,context)}
 if mode=='solid'and not shape and K.circular(outer.r,outer.w,outer.h)then
  local frame=k:make('Frame','BorderRing',parent);frame.ZIndex=z;frame:SetAttribute('CssPaintRole','border')
  local stroke=k:make('UIStroke','Border',frame);stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;stroke.Thickness=width;stroke.Color=color;stroke.Transparency=1-alpha*k.opacity;stroke:SetAttribute('CssBaseAlpha',alpha)
  if pcall(function()stroke.BorderStrokePosition=Enum.BorderStrokePosition.Inside end)then
   frame.Position=UDim2.fromOffset(0,0);frame.Size=UDim2.fromOffset(outer.w,outer.h);K.corner(k,frame,outer.r)
  else
   local inner=inset(outer,width);frame.Position=UDim2.fromOffset(inner.x,inner.y);frame.Size=UDim2.fromOffset(inner.w,inner.h);K.corner(k,frame,inner.r)
  end
  return
 end
 if mode=='dashed'or mode=='dotted'then
  local points,length=B.path(outer,width);if length<=.001 then return end
  local count=math.max(1,math.floor(length/(width*(mode=='dotted'and 2 or 5))+.5));assert(count<=1024,'Borda tracejada/pontilhada densa demais.')
  local period=length/count
  if mode=='dotted'then
   for i=0,count-1 do local x,y=pointAt(points,i*period);local f=Shapes.contains(shape,x,y)and k:solid(parent,x-width/2,y-width/2,width,width,color,alpha,z)or nil
    if f then f.Name='BorderDot';local c=k:make('UICorner','DotRadius',f);c.CornerRadius=UDim.new(.5,0)end
   end
  else
   for i=0,count-1 do
    local first,last=i*period,i*period+period*.6
    for j=2,#points do local a,b=points[j-1],points[j];local lo,hi=math.max(first,a.d),math.min(last,b.d)
     if hi-lo>.001 then
      local x1,y1=pointAt({a,b},lo);local x2,y2=pointAt({a,b},hi);local dx,dy=x2-x1,y2-y1
      local f=Shapes.contains(shape,(x1+x2)/2,(y1+y2)/2)and k:solid(parent,(x1+x2)/2,(y1+y2)/2,math.sqrt(dx*dx+dy*dy)+.02,width,color,alpha,z)or nil
      if f then f.Name='BorderDash';f.AnchorPoint=Vector2.new(.5,.5);f.Rotation=math.deg(math.atan2(dy,dx))end
     end
    end
   end
  end
 elseif mode=='double'then
  ring(k,parent,outer,inset(outer,width/3),color,alpha,z,false,false,shape)
  local inside=inset(outer,width*2/3);ring(k,parent,inside,inset(outer,width),color,alpha,z,false,false,shape)
 elseif mode=='groove'or mode=='ridge'then
  local middle=inset(outer,width/2);ring(k,parent,outer,middle,color,alpha,z,true,mode=='groove',shape);ring(k,parent,middle,inset(outer,width),color,alpha,z,true,mode=='ridge',shape)
 else ring(k,parent,outer,inset(outer,width),color,alpha,z,mode=='inset'or mode=='outset',mode=='inset',shape)end
end
local function four(value,label)return V.four(U.split(value,' '),label)end
local function scalar(value,base,width,context,auto)
 if value=='auto'then return assert(auto,'auto inválido.')end
 local n=tonumber(value);n=n and n*width or G.length(value,base,context);assert(n>=0,'border-image não aceita valor negativo.');return n
end
function B.imagePlan(style,box,context)
 local source=style['border-image-source']or 'none';if source=='none'then return nil end
 local width=G.length(style['border-width']or 0,box.w,context)
 if style['border-style']=='none'or style['border-style']=='hidden'then width=0 end
 local outset=four(style['border-image-outset']or '0','border-image-outset');local offsets={}
 for i,v in ipairs(outset)do assert(not v:find('%%'),'border-image-outset não aceita %.');offsets[i]=scalar(v,0,style._borderWidths and style._borderWidths[i]or width,context)end
 local area={x=-offsets[4],y=-offsets[1],w=box.w+offsets[2]+offsets[4],h=box.h+offsets[1]+offsets[3]}
 local image,iw,ih
 if source:match('^url%(')then image=V.source(source);iw,ih=Images.size(image)end
 iw,ih=iw or area.w,ih or area.h;if iw<=0 or ih<=0 then return nil end
 local tokens=U.split(style['border-image-slice']or '100%',' ');local values,fill={},false
 for _,v in ipairs(tokens)do if v=='fill'then assert(not fill,'fill repetido.');fill=true else values[#values+1]=v end end
 values=V.four(values,'border-image-slice');local slices={}
 for i,v in ipairs(values)do
  local n=tonumber(v);if not n then local percentage=tonumber(v:match('^([+%-%.%d]+)%%$'));assert(percentage,'slice exige número ou %.');n=percentage*(i%2==0 and iw or ih)/100 end
  assert(n>=0,'border-image-slice não aceita valores negativos.');slices[i]=math.min(n,i%2==0 and iw or ih)
 end
 local widths={};for i,v in ipairs(four(style['border-image-width']or '1','border-image-width'))do widths[i]=scalar(v,i%2==0 and area.w or area.h,style._borderWidths and style._borderWidths[i]or width,context,slices[i])end
 local f=math.min(1,area.w/math.max(widths[2]+widths[4],1e-9),area.h/math.max(widths[1]+widths[3],1e-9));for i=1,4 do widths[i]*=f end
 local rep=U.split(style['border-image-repeat']or 'stretch',' ');local allowed={stretch=true,['repeat']=true,round=true,space=true}
 assert(#rep>=1 and #rep<=2 and allowed[rep[1]]and(not rep[2]or allowed[rep[2]]),'border-image-repeat inválido.')
 return {source=source,image=image,iw=iw,ih=ih,area=area,slices=slices,widths=widths,fill=fill,rx=rep[1],ry=rep[2]or rep[1],gradient=not image and Gradient.resolve(source,iw,ih,context,style.color)or nil}
end
local function axisTiles(extent,tile,mode)
 if extent<=.001 or tile<=.001 then return {}end
 if mode=='stretch'then return {{start=0,size=extent}}end
 if mode=='round'then return G.tiles(extent,tile,0,mode,0,extent)end
 if mode=='space'then
  local count=math.floor(extent/tile)
  assert(count<=2048,'border-image excede 2048 tiles por eixo.')
  if count>=1 then
   local gap=(extent-count*tile)/(count+1);local out={}
   for i=0,count-1 do out[#out+1]={start=gap+i*(tile+gap),size=tile}end
   return out
  end
 end
 return G.tiles(extent,tile,(extent-tile)/2,mode,0,extent)
end
function B.pieces(p,emit)
 local s,d,a=p.slices,p.widths,p.area
 local sourceX={0,s[4],p.iw-s[2]};local sourceY={0,s[1],p.ih-s[3]}
 local sourceW={s[4],math.max(0,p.iw-s[4]-s[2]),s[2]};local sourceH={s[1],math.max(0,p.ih-s[1]-s[3]),s[3]}
 local destX={a.x,a.x+d[4],a.x+a.w-d[2]};local destY={a.y,a.y+d[1],a.y+a.h-d[3]}
 local destW={d[4],math.max(0,a.w-d[4]-d[2]),d[2]};local destH={d[1],math.max(0,a.h-d[1]-d[3]),d[3]}
 for row=1,3 do for col=1,3 do
  if (row~=2 or col~=2 or p.fill)and sourceW[col]>.001 and sourceH[row]>.001 and destW[col]>.001 and destH[row]>.001 then
   local clip={x=destX[col],y=destY[row],w=destW[col],h=destH[row]}
   local mx,my=col==2 and p.rx or 'stretch',row==2 and p.ry or 'stretch'
   local scaleX=col~=2 and destW[col]/sourceW[col]or(d[4]/math.max(s[4],1e-9))
   local scaleY=row~=2 and destH[row]/sourceH[row]or(d[1]/math.max(s[1],1e-9))
   if scaleX<=0 then scaleX=1 end;if scaleY<=0 then scaleY=1 end
   local tx=axisTiles(clip.w,sourceW[col]*scaleY,mx);local ty=axisTiles(clip.h,sourceH[row]*scaleX,my)
   assert(#tx*#ty<=1024,'border-image excede 1024 tiles por fatia.')
   for _,y in ipairs(ty)do for _,x in ipairs(tx)do
    local map={sx=sourceX[col],sy=sourceY[row],sw=sourceW[col],sh=sourceH[row],iw=p.iw,ih=p.ih,dx=clip.x+x.start,dy=clip.y+y.start,dw=x.size,dh=y.size}
    emit(clip,map)
   end end
  end
 end end
 end
function B.image(k,parent,style,box,context,z,shape)
 local p=B.imagePlan(style,box,context);if not p then return false end
 B.pieces(p,function(clip,map)
  if shape then clip=table.clone(clip);clip.shape=shape end
  if p.image then K.image(k,parent,clip,map,p.image,z)else K.field(k,parent,clip,map,p.gradient,z)end
 end)
 parent:SetAttribute('CssBorderImage',p.source);return true
end
function B.prepareSample(style,box,context)
 local image=B.imagePlan(style,box,context)
 if image then local pieces={};B.pieces(image,function(clip,map)pieces[#pieces+1]={clip=clip,map=map}end);return {image=image,pieces=pieces}end
 if style._hasSideBorders then return {sidePlan=SideBorders.prepare(style,box,context,B.path)}end
 local width=math.max(0,G.length(style['border-width']or 0,box.w,context));local mode=style['border-style']or 'solid'
 local outer={x=0,y=0,w=box.w,h=box.h,r=G.radii(style,box.w,box.h,context)}
 local color,alpha=V.color(style['border-color']or 'currentColor',style.color)
 local p={width=width,mode=mode,outer=outer,inner=inset(outer,width),color=color,alpha=alpha}
 if width<=0 or mode=='none'or mode=='hidden'then p.empty=true;return p end
 if mode=='double'then p.third=inset(outer,width/3);p.twoThirds=inset(outer,2*width/3)
 elseif mode=='groove'or mode=='ridge'then p.half=inset(outer,width/2)
 elseif mode=='dashed'or mode=='dotted'then
  p.path,p.length=B.path(outer,width);p.count=math.max(1,math.floor(p.length/(width*(mode=='dotted'and 2 or 5))+.5));p.period=p.length/p.count
  if mode=='dotted'then p.dots={};for i=0,p.count-1 do local x,y=pointAt(p.path,i*p.period);p.dots[i+1]={x=x,y=y}end end
 end
 return p
end
local function inside(rect,x,y)
 return rect.w>0 and rect.h>0 and G.inside(rect.r,rect.w,rect.h,x-rect.x,y-rect.y)
end
local function inRect(rect,x,y)return x>=rect.x and y>=rect.y and x<rect.x+rect.w and y<rect.y+rect.h end
function B.sample(p,x,y,imageSampler)
 if p.sidePlan then return SideBorders.sample(p.sidePlan,x,y)end
 if p.image then
  for _,piece in ipairs(p.pieces)do local m=piece.map
   if inRect(piece.clip,x,y)and x>=m.dx and x<m.dx+m.dw and y>=m.dy and y<m.dy+m.dh then
    local sx=m.sx+(x-m.dx)/m.dw*m.sw;local sy=m.sy+(y-m.dy)/m.dh*m.sh
    if p.image.gradient then return Gradient.sample(p.image.gradient,sx,sy)
    elseif imageSampler then return imageSampler(p.image.image,sx,sy,p.image.iw,p.image.ih)end
   end
  end;return Color3.new(),0
 end
 if p.empty or not inside(p.outer,x,y)or inside(p.inner,x,y)then return Color3.new(),0 end
 local color=p.color
 if p.mode=='double'and inside(p.third,x,y)and not inside(p.twoThirds,x,y)then return Color3.new(),0
 elseif p.mode=='groove'or p.mode=='ridge'or p.mode=='inset'or p.mode=='outset'then
  local leading=math.min(x,y)<=math.min(p.outer.w-x,p.outer.h-y)
  local reverse=p.mode=='inset'or p.mode=='groove'
  if p.half and inside(p.half,x,y)then reverse=not reverse end
  color=tinted(color,reverse and not leading or not reverse and leading)
 elseif p.path then
  if p.period<=1e-9 then return color,p.alpha end
  local distance,best=0,math.huge
  for i=2,#p.path do local a,b=p.path[i-1],p.path[i];local dx,dy=b.x-a.x,b.y-a.y;local len=dx*dx+dy*dy
   if len>1e-10 then local t=math.clamp(((x-a.x)*dx+(y-a.y)*dy)/len,0,1);local d=(x-a.x-t*dx)^2+(y-a.y-t*dy)^2
    if d<best then best=d;distance=a.d+(b.d-a.d)*t end
   end
  end
  if p.mode=='dotted'then
   local closest=math.floor(distance/p.period+.5);local square=math.huge
   for n=closest-1,closest+1 do local dot=p.dots[n%p.count+1];square=math.min(square,(x-dot.x)^2+(y-dot.y)^2)end
   if square>(p.width/2)^2 then return Color3.new(),0 end
  elseif best>(p.width/2)^2 or distance%p.period>=p.period*.6 then return Color3.new(),0 end
 end
 return color,p.alpha
end
return B
