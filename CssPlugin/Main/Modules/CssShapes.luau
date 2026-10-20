local U=require(script.Parent.Util)
local Assets=require(script.Parent.VisualEffectsAssets)
local Pixels=require(script.Parent.VisualEffectsPixels)
local S={VERSION=1}
function S.resolver(doc,checkpoint)
 local manager=Assets.new(doc,checkpoint,function(_,message)
  doc.diagnostics=doc.diagnostics or{};if #doc.diagnostics<64 then doc.diagnostics[#doc.diagnostics+1]={kind='shape-image',message=tostring(message)}end
 end)
 return function(source)return manager:image(source)end
end
local boxes={['margin-box']=true,['border-box']=true,['padding-box']=true,['content-box']=true}
local function position(text,w,h,length)
 local t=U.split(text or'50% 50%',' ');assert(#t<=2,'Centro shape aceita uma ou duas coordenadas.')
 if #t==1 then if t[1]=='top'or t[1]=='bottom'then t={'50%',t[1]}else t[2]='50%'end end
 if t[1]=='top'or t[1]=='bottom'or t[2]=='left'or t[2]=='right'then t[1],t[2]=t[2],t[1]end
 local function axis(v,size,low,high)if v==low then return 0 elseif v==high then return size elseif v=='center'then return size/2 end;return assert(length(v,size),'Coordenada shape inválida.')end
 return axis(t[1],w,'left','right'),axis(t[2],h,'top','bottom')
end
function S.prepare(style,c,ctx,containingWidth)
 local value=style['shape-outside'];if not value or value=='none'then return nil end
 local parts=U.split(value,' ');local reference='margin-box';local geometry
 for _,part in ipairs(parts)do if boxes[part]then reference=part else assert(not geometry,'shape-outside aceita uma forma e uma caixa.');geometry=part end end
 local outerW=c.w+c.m[2]+c.m[4];local outerH=c.h+c.m[1]+c.m[3]
 local x,y,w,h=0,0,outerW,outerH
 if reference~='margin-box'then x,y,w,h=c.m[4],c.m[1],c.w,c.h end
 if reference=='padding-box'then
  local border=ctx.length(style['border-width'],containingWidth,c.fs)or 0;x+=border;y+=border;w=math.max(0,w-2*border);h=math.max(0,h-2*border)
 elseif reference=='content-box'then x+=c.p[4];y+=c.p[1];w=math.max(0,w-c.p[2]-c.p[4]);h=math.max(0,h-c.p[1]-c.p[3])end
 local function length(v,base)return ctx.length(v,base,c.fs)end
 local margin=length(style['shape-margin'],containingWidth)or 0;assert(margin>=0,'shape-margin não pode ser negativo.')
 local threshold=tonumber(style['shape-image-threshold']or 0);assert(threshold and threshold==threshold,'shape-image-threshold inválido.');threshold=math.clamp(threshold,0,1)
 local shape={kind='rect',x=x,y=y,w=w,h=h,margin=margin,outerW=outerW,outerH=outerH}
 if not geometry then return shape end
 local fn,body=geometry:match('^([%a%-]+)%((.*)%)$');assert(fn,'shape-outside inválido.')
 if fn=='circle'or fn=='ellipse'then
  local radius,center=body:match('^(.-)%s+at%s+(.+)$');if not radius then if body:match('^at%s+')then radius='';center=body:sub(4)else radius=body end end
  local cx,cy=position(center,w,h,length);local tokens=U.split(radius,' ')
  local function r(token,base,near,far)if not token or token=='closest-side'then return near elseif token=='farthest-side'then return far end;local v=assert(length(token,base),'Raio shape inválido.');assert(v>=0,'Raio shape negativo.');return v end
  shape.kind='ellipse';shape.cx=x+cx;shape.cy=y+cy
  if fn=='circle'then assert(#tokens<=1,'circle aceita um raio.');local rad=r(tokens[1],math.sqrt(w*w+h*h)/math.sqrt(2),math.min(math.abs(cx),math.abs(w-cx),math.abs(cy),math.abs(h-cy)),math.max(math.abs(cx),math.abs(w-cx),math.abs(cy),math.abs(h-cy)));shape.rx=rad;shape.ry=rad
  else assert(#tokens==0 or #tokens==2,'ellipse aceita dois raios.');shape.rx=r(tokens[1],w,math.min(math.abs(cx),math.abs(w-cx)),math.max(math.abs(cx),math.abs(w-cx)));shape.ry=r(tokens[2],h,math.min(math.abs(cy),math.abs(h-cy)),math.max(math.abs(cy),math.abs(h-cy)))end
 elseif fn=='inset'then
  local offsets,round=body:match('^(.-)%s+round%s+(.+)$');offsets=offsets or body;local t=U.split(offsets,' ');assert(#t>=1 and #t<=4,'inset aceita 1 a 4 offsets.')
  local v={t[1],t[2]or t[1],t[3]or t[1],t[4]or t[2]or t[1]};local top,right,bottom,left=length(v[1],h),length(v[2],w),length(v[3],h),length(v[4],w)
  assert(top and right and bottom and left,'Offsets inset inválidos.');shape.x+=left;shape.y+=top;shape.w=math.max(0,w-left-right);shape.h=math.max(0,h-top-bottom)
  if round then local t=U.split(round,'/');local a=U.split(t[1],' ');assert(#a==1 and #t<=2,'inset round: use um raio uniforme, opcionalmente rx / ry.');shape.rx=math.max(0,length(a[1],shape.w)or 0);shape.ry=math.max(0,length(t[2]or a[1],shape.h)or 0)end
 elseif fn=='polygon'then
  local pts=U.split(body,',');if pts[1]=='evenodd'or pts[1]=='nonzero'then table.remove(pts,1)end
  assert(#pts>=3 and #pts<=256,'polygon exige 3 a 256 pontos.');shape.kind='polygon';shape.points={}
  for _,point in ipairs(pts)do local t=U.split(point,' ');assert(#t==2,'Ponto polygon exige x y.');shape.points[#shape.points+1]={x+assert(length(t[1],w)),y+assert(length(t[2],h))}end
 elseif fn=='url'then
  local source=U.trim(body);local quote=source:sub(1,1);if quote=='"'or quote=="'"then assert(source:sub(-1)==quote);source=source:sub(2,-2)end
  shape.kind='image';shape.threshold=threshold;shape.surface=ctx.shapeImage and ctx.shapeImage(source)
  if not shape.surface then return nil end
 else error('shape-outside suporta circle, ellipse, inset, polygon, caixas e url().',0)end
 return shape
end
function S.interval(shape,y,height)
 if not shape then return nil end
 local margin=shape.margin;local a,b=y,y+height
 if b<=0 or a>=shape.outerH then return nil end
 a=math.max(a,0);b=math.min(b,shape.outerH)
 local left,right
 if shape.kind=='ellipse'then
  local rx,ry=shape.rx+margin,shape.ry+margin;if rx<=0 or ry<=0 or b<=shape.cy-ry or a>=shape.cy+ry then return nil end
  local nearest=math.clamp(shape.cy,a,b);local radius=rx*math.sqrt(math.max(0,1-((nearest-shape.cy)/ry)^2));left,right=shape.cx-radius,shape.cx+radius
 elseif shape.kind=='polygon'then
  local low,high=a-margin,b+margin;local minimum,maximum=math.huge,-math.huge
  local function include(x)minimum=math.min(minimum,x);maximum=math.max(maximum,x)end
  for i,p in ipairs(shape.points)do local q=shape.points[i%#shape.points+1]
   if p[2]>=low and p[2]<=high then include(p[1])end
   if p[2]~=q[2]then for _,yy in ipairs({low,high})do local t=(yy-p[2])/(q[2]-p[2]);if t>=0 and t<=1 then include(p[1]+t*(q[1]-p[1]))end end end
  end
  if minimum==math.huge then return nil end;left,right=minimum-margin,maximum+margin
 elseif shape.kind=='image'then
  if shape.w<=0 or shape.h<=0 then return nil end;local surface=shape.surface
  local y0=math.max(0,math.floor((a-margin-shape.y)/shape.h*surface.h));local y1=math.min(surface.h-1,math.ceil((b+margin-shape.y)/shape.h*surface.h)-1)
  local minimum,maximum=surface.w,-1
  for yy=y0,y1 do for xx=0,surface.w-1 do local _,alpha=Pixels.get(surface,xx,yy);if alpha>shape.threshold then minimum=math.min(minimum,xx);maximum=math.max(maximum,xx)end end end
  if maximum<0 then return nil end;left=shape.x+minimum/surface.w*shape.w-margin;right=shape.x+(maximum+1)/surface.w*shape.w+margin
 else
  local top,bottom=shape.y-margin,shape.y+shape.h+margin;if b<=top or a>=bottom then return nil end
  left,right=shape.x-margin,shape.x+shape.w+margin
  if shape.rx and shape.ry then
   local rx=math.min(shape.rx+margin,(right-left)/2);local ry=math.min(shape.ry+margin,(bottom-top)/2);local near=math.clamp((top+bottom)/2,a,b)
   local d=math.max(0,ry-math.min(near-top,bottom-near));local inset=ry>0 and rx*(1-math.sqrt(math.max(0,1-(d/ry)^2)))or 0;left+=inset;right-=inset
  end
 end
 return math.clamp(left,0,shape.outerW),math.clamp(right,0,shape.outerW)
end
return S
