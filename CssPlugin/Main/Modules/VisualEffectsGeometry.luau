local U=require(script.Parent.Util)
local E=require(script.Parent.VisualEffectsStyle)
local G=require(script.Parent.VisualGeometry)
local Gradient=require(script.Parent.CssGradient)
local P=require(script.Parent.VisualEffectsPixels)
local Scan=require(script.Parent.VectorScanline)
local Bool=require(script.Parent.VectorBoolean)
local Cache=require(script.Parent.VectorCache)
local Lod=require(script.Parent.VectorLod)
local M={VERSION=1,ALGORITHM='clip-vector-1'}
local function unquote(text)
 text=U.trim(text);local q=text:sub(1,1);assert((q=='"'or q=="'")and text:sub(-1)==q,'path() exige SVG path entre aspas.');return text:sub(2,-2)
end
function M.clip(value,w,h,c)
 value=U.trim(value or 'none');if value=='none'then return {kind='none'}end
 local name,body=value:match('^([%a%-]+)%((.*)%)$');assert(name,'clip-path exige polygon(), circle(), ellipse(), inset(), path() ou url().')
 local out={kind=name,w=w,h=h}
 if name=='polygon'then
  local tokens=E.segments(body,',');out.rule='nonzero';if tokens[1]=='evenodd'or tokens[1]=='nonzero'then out.rule=table.remove(tokens,1)end
  assert(#tokens>=3 and #tokens<=256,'polygon exige 3 a 256 vértices.');out.points={}
  for _,token in ipairs(tokens)do local xy=U.split(token,' ');assert(#xy==2,'Vértice de polygon exige x y.');out.points[#out.points+1]={x=G.length(xy[1],w,c),y=G.length(xy[2],h,c)}end
 elseif name=='circle'or name=='ellipse'then
  local radii,position=body:match('^(.-)%s+at%s+(.+)$');if body:match('^at%s+')then radii,position='',body:match('^at%s+(.+)$')end
  radii=radii or body;local tokens=U.split(radii,' ');out.cx,out.cy=G.position(position or '50% 50%',w,h,0,0,c)
  assert(#tokens<=(name=='circle'and 1 or 2),'Raio de clip-path inválido.')
  local function radius(token,extent,center)
   if token==nil or token=='closest-side'then return math.min(math.abs(center),math.abs(extent-center))end
   if token=='farthest-side'then return math.max(math.abs(center),math.abs(extent-center))end
   return G.length(token,extent,c)
  end
  if name=='circle'then
   local token=tokens[1]
   if not token or token=='closest-side'or token=='farthest-side'then local pick=token=='farthest-side'and math.max or math.min;out.rx=pick(radius(token,w,out.cx),radius(token,h,out.cy))
   else out.rx=G.length(token,math.sqrt((w*w+h*h)/2),c)end;out.ry=out.rx
  else assert(#tokens==0 or #tokens==2,'ellipse exige rx ry.');out.rx=radius(tokens[1],w,out.cx);out.ry=radius(tokens[2],h,out.cy)end
  assert(out.rx>=0 and out.ry>=0,'Raio de clip-path não pode ser negativo.')
 elseif name=='inset'then
  local edges,round=body:match('^(.-)%s+round%s+(.+)$');local t=U.split(edges or body,' ');assert(#t>=1 and #t<=4,'inset aceita 1 a 4 distâncias.')
  t={t[1],t[2]or t[1],t[3]or t[1],t[4]or t[2]or t[1]};local top,right,bottom,left=G.length(t[1],h,c),G.length(t[2],w,c),G.length(t[3],h,c),G.length(t[4],w,c)
  out.x,out.y,out.iw,out.ih=left,top,math.max(0,w-left-right),math.max(0,h-top-bottom);out.radius=round and G.length(round,math.min(w,h),c)or 0
 elseif name=='path'then
  local tokens=E.segments(body,',');local rule='nonzero';if #tokens==2 then rule=table.remove(tokens,1);assert(rule=='evenodd'or rule=='nonzero','Regra de path inválida.')end
  assert(#tokens==1,'path aceita [fill-rule,] "d".');out.d=unquote(tokens[1]);out.rule=rule
  assert(c and c.path,'Backend SVG não instalado.');out.surface=c.path(out.d,rule,w,h)
 elseif name=='url'then
  assert(c and c.image,'Backend de máscara não instalado.');out.surface=c.image(E.url(value));assert(out.surface,'SVG de recorte não pôde ser carregado.')
 else error('clip-path não suportado: '..name,0)end
 return out
end
function M.inside(shape,x,y)
 local kind=shape.kind
 if kind=='none'then return true
 elseif kind=='circle'or kind=='ellipse'then return shape.rx>0 and shape.ry>0 and((x-shape.cx)/shape.rx)^2+((y-shape.cy)/shape.ry)^2<=1
 elseif kind=='polygon'then
  local winding=0;local points=shape.points
  for i,a in ipairs(points)do
   local b=points[i%#points+1]
   if (a.y<=y and b.y>y)or(b.y<=y and a.y>y)then local cross=a.x+(y-a.y)*(b.x-a.x)/(b.y-a.y);if cross>x then winding+=shape.rule=='evenodd'and 1 or(b.y>a.y and 1 or -1)end end
  end
  return shape.rule=='evenodd'and winding%2~=0 or shape.rule=='nonzero'and winding~=0
 elseif kind=='inset'then
  if shape.iw<=0 or shape.ih<=0 then return false end
  local xx,yy=x-shape.x,y-shape.y;if xx<0 or yy<0 or xx>shape.iw or yy>shape.ih then return false end
  local r=math.clamp(shape.radius,0,math.min(shape.iw,shape.ih)/2);local cx=math.clamp(xx,r,shape.iw-r);local cy=math.clamp(yy,r,shape.ih-r);return(xx-cx)^2+(yy-cy)^2<=r*r
 else local _,a=P.sample(shape.surface,x/shape.w*shape.surface.w-.5,y/shape.h*shape.surface.h-.5);return a>=.5 end
end
local function pushPoint(list,x,y) list[#list+1]={x=x,y=y} end
local function arcSteps(radius,tolerance,quarter)
 if radius<=0 then return 1 end
 local limit=math.clamp(tolerance,1e-5,radius*0.5)
 local span=math.acos(math.clamp(1-limit/radius,-1,1))
 if span<1e-6 then span=1e-6 end
 if quarter then return math.clamp(math.ceil(math.pi*0.5/span),2,1024) end
 return math.clamp(math.ceil(math.pi*2/span),8,4096)
end
local function ellipseContour(cx,cy,rx,ry,tolerance)
 if rx<=0 or ry<=0 then return nil end
 local steps=arcSteps(math.max(rx,ry),tolerance,false)
 local contour={closed=true}
 for index=0,steps-1 do
  local angle=index/steps*math.pi*2
  pushPoint(contour,cx+rx*math.cos(angle),cy+ry*math.sin(angle))
 end
 return contour
end
local function roundedContour(x,y,w,h,radius,tolerance)
 if w<=0 or h<=0 then return nil end
 local r=math.clamp(tonumber(radius) or 0,0,math.min(w,h)*0.5)
 local contour={closed=true}
 if r<=0 then
  pushPoint(contour,x,y);pushPoint(contour,x+w,y);pushPoint(contour,x+w,y+h);pushPoint(contour,x,y+h)
  return contour
 end
 local steps=arcSteps(r,tolerance,true)
 local corners={{x+w-r,y+r,-math.pi*0.5},{x+w-r,y+h-r,0},{x+r,y+h-r,math.pi*0.5},{x+r,y+r,math.pi}}
 for _,corner in ipairs(corners)do
  for index=0,steps do
   local angle=corner[3]+index/steps*math.pi*0.5
   pushPoint(contour,corner[1]+r*math.cos(angle),corner[2]+r*math.sin(angle))
  end
 end
 return contour
end
function M.contours(shape,options)
 if not shape then return nil end
 options=options or {}
 local tolerance=math.max(tonumber(options.tolerance) or 0.05,1e-5)
 local kind=shape.kind
 if kind=='none'then
  local w,h=tonumber(shape.w),tonumber(shape.h)
  if not w or not h or w<=0 or h<=0 then return nil end
  local contour={closed=true}
  pushPoint(contour,0,0);pushPoint(contour,w,0);pushPoint(contour,w,h);pushPoint(contour,0,h)
  return {contour},'nonzero'
 elseif kind=='polygon'then
  local contour={closed=true}
  for _,point in ipairs(shape.points)do pushPoint(contour,point.x,point.y)end
  if #contour<3 then return nil end
  return {contour},shape.rule or 'nonzero'
 elseif kind=='circle'or kind=='ellipse'then
  local contour=ellipseContour(shape.cx,shape.cy,shape.rx,shape.ry,tolerance)
  if not contour then return nil end
  return {contour},'nonzero'
 elseif kind=='inset'then
  local contour=roundedContour(shape.x,shape.y,shape.iw,shape.ih,shape.radius,tolerance)
  if not contour then return nil end
  return {contour},'nonzero'
 end
 return nil
end
local composites={add='union',subtract='difference',intersect='intersect',exclude='xor'}
function M.operation(composite)
 return composites[composite or 'add'] or 'union'
end
local function regionOf(value,options)
 if type(value)~='table'then return nil end
 if value.kind then return M.contours(value,options)end
 if #value>0 then return value end
 return nil
end
function M.combine(regions,operation,options)
 local list={}
 for _,value in ipairs(regions or {})do
  local contours=regionOf(value,options)
  if contours and #contours>0 then list[#list+1]=contours end
 end
 if #list==0 then return {} end
 local current=list[1]
 for index=2,#list do
  local other=list[index]
  if operation=='union'then current=Bool.union(current,other,options)
  elseif operation=='difference'then current=Bool.difference(current,other,options)
  elseif operation=='xor'then current=Bool.xor(current,other,options)
  else current=Bool.intersect(current,other,options)end
  if #current==0 then break end
 end
 return current
end
function M.clipRegion(subject,clips,options)
 local base=regionOf(subject,options)
 if not base then return {} end
 local list={}
 for _,value in ipairs(clips or {})do
  local contours=regionOf(value,options)
  if contours and #contours>0 then list[#list+1]=contours end
 end
 return Bool.clip(base,list,options)
end
function M.maskRegion(subject,masks,options)
 local base=regionOf(subject,options)
 if not base then return {} end
 local list={}
 for _,value in ipairs(masks or {})do
  local contours=regionOf(value,options)
  if contours and #contours>0 then list[#list+1]=contours end
 end
 if #list==0 then return base end
 return Bool.mask(base,list,options)
end
local function shapeSignature(shape)
 local kind=shape.kind
 local parts={kind,string.format('%.4f',tonumber(shape.w) or 0),string.format('%.4f',tonumber(shape.h) or 0)}
 if kind=='polygon'then
  parts[#parts+1]=shape.rule or 'nonzero'
  for _,point in ipairs(shape.points)do parts[#parts+1]=string.format('%.4f,%.4f',point.x,point.y)end
 elseif kind=='circle'or kind=='ellipse'then
  parts[#parts+1]=string.format('%.4f,%.4f,%.4f,%.4f',shape.cx,shape.cy,shape.rx,shape.ry)
 elseif kind=='inset'then
  parts[#parts+1]=string.format('%.4f,%.4f,%.4f,%.4f,%.4f',shape.x,shape.y,shape.iw,shape.ih,tonumber(shape.radius) or 0)
 end
 return table.concat(parts,':')
end
local function coverageStage()
 return Cache.stage('clip-coverage',table.concat({M.ALGORITHM,Scan.ALGORITHM,Bool.ALGORITHM,Lod.ALGORITHM},'+'),{maxEntries=64,maxBytes=12582912})
end
function M.plan(shape,step,options)
 options=options or {}
 local w,h=tonumber(shape.w),tonumber(shape.h)
 if not w or not h or w<=0 or h<=0 then return nil end
 local cell=math.clamp(tonumber(step) or 1,1/64,4096)
 return Lod.plan({viewBox={0,0,w,h},width=w,height=h,pixelScale=1/cell,quality=options.quality or 'exact',preserveAspectRatio='none',maxPixels=options.maxPixels or 1048576,profile=options.profile})
end
function M.field(shape,step,options)
 options=options or {}
 local plan=M.plan(shape,step,options)
 if not plan then return nil end
 local stage=coverageStage()
 local key=Cache.key({shapeSignature(shape),Lod.signature(plan),options.signature or '',options.rule or '',options.operation or ''})
 local cached=Cache.get(stage,key)
 if cached then return cached end
 local contours,rule=M.contours(shape,{tolerance=plan.tolerance})
 if not contours then return nil end
 if options.regions and #options.regions>0 then
  local list={contours}
  for _,region in ipairs(options.regions)do list[#list+1]=region end
  contours=M.combine(list,options.operation or 'intersect',{rule=rule,clipRule=rule})
  rule='nonzero'
 end
 local alpha=Scan.alphaTable(contours,{w=plan.width,h=plan.height,rule=options.rule or rule,levels=plan.levels,matrix={plan.scaleX,0,0,plan.scaleY,0,0},maxEdges=plan.edgeLimit})
 local field={alpha=alpha,w=plan.width,h=plan.height,scaleX=plan.scaleX,scaleY=plan.scaleY,levels=plan.levels,tolerance=plan.tolerance,plan=plan}
 Cache.put(stage,key,field,plan.width*plan.height*8+256)
 return field
end
function M.sample(field,x,y,dx,dy)
 if not field then return 0 end
 local x0,y0=x*field.scaleX,y*field.scaleY
 local x1,y1=(x+(dx or 0))*field.scaleX,(y+(dy or 0))*field.scaleY
 local first=math.floor(math.min(x0,x1))
 local last=math.floor(math.max(x0,x1)-1e-6)
 local top=math.floor(math.min(y0,y1))
 local bottom=math.floor(math.max(y0,y1)-1e-6)
 if last<first then last=first end
 if bottom<top then bottom=top end
 if last-first>15 then last=first+15 end
 if bottom-top>15 then bottom=top+15 end
 local total,count=0,0
 for gy=top,bottom do
  for gx=first,last do
   count+=1
   if gx>=0 and gy>=0 and gx<field.w and gy<field.h then total+=field.alpha[gy*field.w+gx+1] or 0 end
  end
 end
 if count==0 then return 0 end
 return math.clamp(total/count,0,1)
end
function M.coverage(shape,x,y,dx,dy)
 if shape.kind=='none'then return 1 end
 if shape.surface then local _,a=P.sample(shape.surface,x/shape.w*shape.surface.w-.5,y/shape.h*shape.surface.h-.5);return a end
 local cell=math.max(tonumber(dx) or 0,tonumber(dy) or 0)
 if cell>0 then
  local field=M.field(shape,cell)
  if field then return M.sample(field,x,y,dx or cell,dy or cell)end
 end
 if dx==0 and dy==0 then return M.inside(shape,x,y)and 1 or 0 end
 local n=0;for sy=-1,1,2 do for sx=-1,1,2 do if M.inside(shape,x+sx*(dx or 1)*.25,y+sy*(dy or 1)*.25)then n+=.25 end end end;return n
end
function M.masks(style,box,c)
 local value=style['mask-image']or 'none';if value=='none'then return nil end
 local images=E.segments(value,',');assert(#images<=4,'Máximo de 4 máscaras.')
 local fields={};local defaults={position='0% 0%',size='auto auto',['repeat']='repeat',mode='match-source',composite='add',origin='border-box',clip='border-box'}
 for name,default in pairs(defaults)do fields[name]=E.segments(style['mask-'..name]or default,',')end
 local layers={}
 for i,image in ipairs(images)do
  local layer={};for k,list in pairs(fields)do layer[k]=list[(i-1)%#list+1]end
  assert(layer.mode=='alpha'or layer.mode=='luminance'or layer.mode=='match-source','mask-mode inválido.')
  assert(layer.composite=='add'or layer.composite=='subtract'or layer.composite=='intersect'or layer.composite=='exclude','mask-composite inválido.')
  assert(layer.origin=='border-box'or layer.origin=='padding-box'or layer.origin=='content-box','mask-origin inválido.')
  assert(layer.clip=='no-clip'or layer.clip=='border-box'or layer.clip=='padding-box'or layer.clip=='content-box','mask-clip inválido.')
  layer.rect=G.rect(style,box,layer.origin,c);layer.clipRect=layer.clip~='no-clip'and G.rect(style,box,layer.clip,c)or nil
  local iw,ih
  if image=='none'then layer.empty=true
  elseif image:find('gradient(',1,true)then layer.definition=image
  else local source=E.url(image);layer.surface=c.image(source);if not layer.surface then layer.empty=true else iw,ih=layer.surface.w,layer.surface.h end end
  layer.tw,layer.th=G.size(layer.size,layer.rect.w,layer.rect.h,iw,ih,c)
  layer.x,layer.y=G.position(layer.position,layer.rect.w,layer.rect.h,layer.tw,layer.th,c)
  layer.rx,layer.ry=G.repeatModes(layer['repeat'])
  if layer.mode=='match-source'then layer.mode=layer.surface and layer.surface.maskMode or 'alpha'end
  layer.tilesX,layer.tw=G.tiles(layer.rect.w,layer.tw,layer.x,layer.rx,-layer.rect.x,box.w-layer.rect.x)
  layer.tilesY,layer.th=G.tiles(layer.rect.h,layer.th,layer.y,layer.ry,-layer.rect.y,box.h-layer.rect.y)
  if layer.definition then layer.gradient=Gradient.resolve(layer.definition,layer.tw,layer.th,c,style.color)end
  layers[#layers+1]=layer
 end;return layers
end
local function sampleLayer(layer,x,y)
 if layer.empty or layer.tw<=0 or layer.th<=0 then return 0 end
 local clip=layer.clipRect;if clip and not G.inside(clip.r,clip.w,clip.h,x-clip.x,y-clip.y)then return 0 end
 x-=layer.rect.x;y-=layer.rect.y;local u,v
 for _,tile in ipairs(layer.tilesX)do if x>=tile.start and x<tile.start+tile.size then u=(x-tile.start)/tile.size;break end end
 for _,tile in ipairs(layer.tilesY)do if y>=tile.start and y<tile.start+tile.size then v=(y-tile.start)/tile.size;break end end
 if not u or not v then return 0 end
 local color,a
 if layer.gradient then color,a=Gradient.sample(layer.gradient,u*layer.tw,v*layer.th)else color,a=P.sample(layer.surface,u*layer.surface.w-.5,v*layer.surface.h-.5)end
 if layer.mode=='luminance'then a*=.2126*color.R+.7152*color.G+.0722*color.B end
 return math.clamp(a,0,1)
end
function M.alpha(layers,x,y)
 if not layers then return 1 end
 local a=0
 for i=#layers,1,-1 do local layer=layers[i];local s=sampleLayer(layer,x,y)
  if i==#layers then a=s elseif layer.composite=='add'then a=s+a-s*a elseif layer.composite=='subtract'then a=s*(1-a)elseif layer.composite=='intersect'then a=s*a else a=s+a-2*s*a end
 end;return math.clamp(a,0,1)
end
return M
