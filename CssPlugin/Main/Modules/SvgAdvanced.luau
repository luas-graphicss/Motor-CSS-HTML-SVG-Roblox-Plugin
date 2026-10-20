local U=require(script.Parent.Util)
local Cost=require(script.Parent.CostModel)
local Style=require(script.Parent.SvgStyle)
local G=require(script.Parent.SvgGeometry)
local Paint=require(script.Parent.SvgPaintServer)
local Filters=require(script.Parent.SvgFilters)
local P=require(script.Parent.VisualEffectsPixels)
local Raster=require(script.Parent.SvgRaster)
local Codec=require(script.Parent.SvgRasterRuntime)
local Pool=require(script.Parent.PoolOwnership).adapter('CssRuntime')
local Dom=require(script.Parent.SvgDom)
local A={VERSION='svg-advanced-1'}
local shapes={path=true,rect=true,circle=true,ellipse=true,line=true,polyline=true,polygon=true}
local definitions={defs=true,lineargradient=true,radialgradient=true,stop=true,filter=true,fegaussianblur=true,fedropshadow=true,feoffset=true,feflood=true,femerge=true,femergenode=true,fecomposite=true,fecolormatrix=true,fecomponenttransfer=true,fefuncr=true,fefuncg=true,fefuncb=true,fefunca=true,feblend=true,femorphology=true,feconvolvematrix=true,feturbulence=true,fedisplacementmap=true,feimage=true,fetile=true,fediffuselighting=true,fespecularlighting=true,fedistantlight=true,fepointlight=true,fespotlight=true,clippath=true,mask=true,marker=true,pattern=true,symbol=true}
local permitted={id=true,class=true,xmlns=true,['xmlns:xlink']=true,viewbox=true,width=true,height=true,preserveaspectratio=true,style=true,transform=true,d=true,x=true,y=true,x1=true,x2=true,y1=true,y2=true,cx=true,cy=true,r=true,rx=true,ry=true,fx=true,fy=true,points=true,['data-resolution']=true,['aria-label']=true,role=true,gradientunits=true,gradienttransform=true,spreadmethod=true,offset=true,href=true,['xlink:href']=true,filterunits=true,primitiveunits=true,stddeviation=true,['in']=true,in2=true,result=true,dx=true,dy=true,operator=true,clippathunits=true,maskunits=true,maskcontentunits=true,markerunits=true,markerwidth=true,markerheight=true,refx=true,refy=true,orient=true,pathlength=true,overflow=true,type=true,values=true,tablevalues=true,slope=true,intercept=true,amplitude=true,exponent=true,mode=true,k1=true,k2=true,k3=true,k4=true,order=true,kernelmatrix=true,divisor=true,bias=true,targetx=true,targety=true,edgemode=true,kernelunitlength=true,preservealpha=true,radius=true,basefrequency=true,numoctaves=true,seed=true,stitchtiles=true,scale=true,xchannelselector=true,ychannelselector=true,surfacescale=true,diffuseconstant=true,specularconstant=true,specularexponent=true,azimuth=true,elevation=true,z=true,pointsatx=true,pointsaty=true,pointsatz=true,limitingconeangle=true,requiredfeatures=true,requiredextensions=true,systemlanguage=true,lang=true,['xml:lang']=true,['xml:space']=true,patternunits=true,patterncontentunits=true,patterntransform=true,startoffset=true,method=true,spacing=true,rotate=true}
local function recycle(view)
 for _,child in ipairs(view:GetChildren())do if child.Name=='__SvgNative'then child:Destroy()end end
 Codec.releaseTree(view,false);Pool.releaseTree(view)
end
function A.order(value)
 local text=value and tostring(value)or ''
 text=text:lower():gsub('^%s+',''):gsub('%s+$','')
 local out,seen={},{}
 if text~=''and text~='normal'then
  for token in text:gmatch('%S+')do
   assert(token=='fill'or token=='stroke'or token=='markers','paint-order inválido: '..tostring(value))
   if not seen[token]then seen[token]=true;out[#out+1]=token end
  end
 end
 for _,token in ipairs({'fill','stroke','markers'})do if not seen[token]then out[#out+1]=token end end
 return out
end
function A.surface(svg,currentColor,options,legacy)
 options=options or {};assert(legacy and legacy.paths,'Geometria SVG básica ausente.')
 if not svg._svgResolved then svg=Style.resolve(Style.prepare(svg,svg.key or '__vector'),currentColor)end
 assert(svg.tag=='svg','A raiz vetorial precisa ser svg.')
 local vb=U.numbers(svg.attrs.viewbox or('0 0 '..(svg.attrs.width or 24)..' '..(svg.attrs.height or 24)))
 assert(#vb==4 and vb[3]>0 and vb[4]>0,'SVG exige viewBox positivo.')
 local resolution=math.clamp(math.ceil(options.resolution or 64),16,128);local aspect=vb[3]/vb[4]
 local rw=aspect>=1 and resolution or math.max(1,math.floor(resolution*aspect));local rh=aspect>=1 and math.max(1,math.floor(resolution/aspect))or resolution
 local tolerance=math.max(vb[3]/rw,vb[4]/rh)*.22
 local expansion
 svg,expansion=Dom.expand(svg,{currentColor=currentColor,viewport={width=vb[3],height=vb[4]},tolerance=tolerance,languages=options.languages,inherited=Style.inherited,size=G.number(svg.attrs['font-size'],16,vb[4]),resolve=function(node)return(Style.resolve(Style.prepare(node,(svg.key or '__vector')..':dom'),currentColor))end,polyline=function(node)return G.shape(node,legacy,tolerance,vb)end})
 local defs,hasFilter={},false;local total=0
 local function index(n,depth)
  total+=1;Cost.cap('nodes',total,'Nós SVG avançado');assert(depth<=96,'Profundidade SVG acima do orçamento.')
  assert(shapes[n.tag]or definitions[n.tag]or n.tag=='svg'or n.tag=='g'or n.tag=='title'or n.tag=='desc'or n.tag=='image'or n.tag=='text','Elemento SVG não suportado: <'..n.tag..'>')
  local id=n.attrs.id;if id then assert(not defs[id],'ID SVG duplicado: '..id);defs[id]=n end
  if n.tag=='filter'or(n.attrs.filter and n.attrs.filter~='none')then hasFilter=true end
  for _,child in ipairs(n.children)do index(child,depth+1)end
 end;index(svg,1)
 local pad=hasFilter and math.min(64,resolution)or 0
 local c={vb=vb,rw=rw,rh=rh,w=rw+2*pad,h=rh+2*pad,pad=pad,sx=rw/vb[3],sy=rh/vb[4],color=currentColor or Color3.new(),checkpoint=options.yield,alphaLevels=math.clamp(options.alphaLevels or 8,4,32),paints=0}
 local contourCache,boundsCache={},{}
 local natives={}
 local function contours(n,m)
  local scale=math.max(math.sqrt(m[1]^2+m[2]^2),math.sqrt(m[3]^2+m[4]^2),1)
  local cached=contourCache[n];if cached and cached.scale>=scale then return cached.value end
  local value=G.shape(n,legacy,tolerance/scale,vb);contourCache[n]={scale=scale,value=value};return value
 end
 local function bounds(n)
  if boundsCache[n]then return boundsCache[n]end
  local box
  if shapes[n.tag]then box=G.box(contours(n,G.I))else
   for _,child in ipairs(n.children)do if shapes[child.tag]or child.tag=='g'then
    local b=bounds(child);local m=G.transform(child.attrs.transform,legacy);box=G.union(box,G.box(G.rect(b.x,b.y,b.w,b.h),m))
   end end
  end
  box=box or {x=0,y=0,right=0,bottom=0,w=0,h=0};boundsCache[n]=box;return box
 end
 local function paint(surface,polys,rule,sampler,m,opacity)
  if not sampler or opacity<=0 then return end
  c.paints+=1;Cost.cap('layers',c.paints,'Camadas vetoriais SVG')
  local coverage=G.coverage(polys,m,rule,c)
  for y=0,c.h-1 do for x=0,c.w-1 do local a=coverage[y*c.w+x+1]*opacity
   if a>0 then
    local color,ca=sampler(vb[1]+(x-pad+.5)/c.sx,vb[2]+(y-pad+.5)/c.sy)
    if ca>0 then local back,ba=P.get(surface,x,y);local result,alpha=P.over(back,ba,color,a*ca);P.set(surface,x,y,result,alpha)end
   end
  end;if c.checkpoint and y%16==0 then c.checkpoint()end end
 end
 local active={};local draw
 local function reference(value,kind,fn)
  local id,tail=Paint.reference(value);assert(id and(not tail or tail==''),'Referência de '..kind..' inválida.')
  local node=assert(defs[id],kind..' SVG não encontrado: #'..id);assert(node.tag==kind,'Referência #'..id..' não é '..kind)
  local token=kind..':'..id;assert(not active[token],'Ciclo em referência SVG: #'..id)
  local depth=0;for _ in pairs(active)do depth+=1 end;assert(depth<16,'Referências SVG excedem 16 níveis.')
  active[token]=true;local result=fn(node);active[token]=nil;return result
 end
 local function patternSampler(def,a,box,pm,context)
  local attrs=def.attrs
  local tile=Dom.pattern(attrs,box,vb[3],vb[4])
  local inner=Dom.patternContent(attrs,tile,box)
  local full=G.mul(pm,G.transform(attrs.patterntransform,legacy))
  local reverse=G.inverse(full)
  if not reverse or tile.width<=0 or tile.height<=0 then return nil end
  local cu,cv=G.at(reverse,vb[1]+vb[3]/2,vb[2]+vb[4]/2)
  local ox=tile.x+math.floor((cu-tile.x)/tile.width)*tile.width
  local oy=tile.y+math.floor((cv-tile.y)/tile.height)*tile.height
  local placement=G.mul(full,{1,0,0,1,ox,oy})
  local tm=inner and G.mul(placement,G.transform(inner,legacy))or placement
  local layer=draw({tag='g',attrs={transform='none'},children=def.children},tm,'paint',true,context)
  local region=G.coverage(G.rect(0,0,tile.width,tile.height),placement,'nonzero',c)
  P.mask(layer,function(x,y)return region[y*c.w+x+1]end)
  return function(x,y)
   local u,v=G.at(reverse,x,y)
   local sx,sy=G.at(full,ox+(u-tile.x)%tile.width,oy+(v-tile.y)%tile.height)
   local ix=math.floor((sx-vb[1])*c.sx+pad)
   local iy=math.floor((sy-vb[2])*c.sy+pad)
   if ix<0 or iy<0 or ix>=c.w or iy>=c.h then return Color3.new(),0 end
   return P.get(layer,ix,iy)
  end
 end
 local function paintFor(value,a,box,m,context)
  if value and value:find('url%(')then
   local id=Paint.reference(value)
   local node=id and defs[id]
   if node and node.tag=='pattern'then return reference(value,'pattern',function(def)return patternSampler(def,a,box,m,context)end)end
  end
  return Paint.sampler(value,a,box,m,c,defs,legacy,context)
 end
 local function clip(value,box,m)
  return reference(value,'clippath',function(def)
   local units=def.attrs.clippathunits or 'userSpaceOnUse';assert(units=='userSpaceOnUse'or units=='objectBoundingBox','clipPathUnits inválido.')
   local cm=G.mul(m,units=='objectBoundingBox'and G.bboxMatrix(box)or G.I)
   return draw(def,cm,'clip',true)
  end)
 end
 local function applyMask(layer,value,box,m)
  return reference(value,'mask',function(def)
   local attrs=def.attrs;local units=attrs.maskcontentunits or 'userSpaceOnUse';assert(units=='userSpaceOnUse'or units=='objectBoundingBox','maskContentUnits inválido.')
   local mm=G.mul(m,units=='objectBoundingBox'and G.bboxMatrix(box)or G.I)
   local mask=draw(def,mm,'paint',true)
   local regionUnits=attrs.maskunits or 'objectBoundingBox';assert(regionUnits=='objectBoundingBox'or regionUnits=='userSpaceOnUse','maskUnits inválido.')
   local rm=G.mul(m,regionUnits=='objectBoundingBox'and G.bboxMatrix(box)or G.I)
   local bw,bh=regionUnits=='objectBoundingBox'and 1 or vb[3],regionUnits=='objectBoundingBox'and 1 or vb[4]
   local x,y=G.number(attrs.x or '-10%',0,bw),G.number(attrs.y or '-10%',0,bh)
   if regionUnits=='userSpaceOnUse'then if(attrs.x or '-10%'):sub(-1)=='%'then x+=vb[1]end;if(attrs.y or '-10%'):sub(-1)=='%'then y+=vb[2]end end
   local w,h=G.number(attrs.width or '120%',0,bw),G.number(attrs.height or '120%',0,bh);assert(w>=0 and h>=0,'Região de máscara negativa.')
   local region=G.coverage(G.rect(x,y,w,h),rm,'nonzero',c);local mode=attrs['mask-type']or 'luminance';assert(mode=='alpha'or mode=='luminance','mask-type inválido.')
   P.mask(layer,function(px,py)
    local color,a=P.get(mask,px,py);local luminance=mode=='alpha'and 1 or(.2126*color.R+.7152*color.G+.0722*color.B)
    return region[py*c.w+px+1]*a*luminance
   end);return layer
  end)
 end
 local function markers(node,layer,polys,a,m,box,context)
  for _,key in ipairs({'marker-start','marker-mid','marker-end'})do
   local value=a[key];if not value or value=='none'then continue end
   reference(value,'marker',function(def)
    local da=def.attrs;local units=da.markerunits or 'strokeWidth';assert(units=='strokeWidth'or units=='userSpaceOnUse','markerUnits inválido.')
    local width,height=G.number(da.markerwidth,3),G.number(da.markerheight,3);assert(width>=0 and height>=0,'Dimensão de marker negativa.');if width==0 or height==0 then return end
    local scale=units=='strokeWidth'and G.number(a['stroke-width'],1,math.sqrt((vb[3]^2+vb[4]^2)/2))or 1
    local markerView=da.viewbox and U.numbers(da.viewbox)or {0,0,width,height};assert(#markerView==4 and markerView[3]>0 and markerView[4]>0,'viewBox de marker inválido.')
    local sx,sy=width/markerView[3],height/markerView[4];local ox,oy=0,0;local preserve=da.preserveaspectratio or 'xMidYMid meet'
    if preserve~='none'then
     local ax,ay,fit=preserve:match('^x(%a+)Y(%a+)%s*(%a*)$');local align={Min=0,Mid=.5,Max=1};assert(align[ax]and align[ay]and(fit==''or fit=='meet'or fit=='slice'),'preserveAspectRatio de marker inválido.')
     local s=fit=='slice'and math.max(sx,sy)or math.min(sx,sy);ox,oy=(width-markerView[3]*s)*align[ax],(height-markerView[4]*s)*align[ay];sx,sy=s,s
    end
    local view={sx,0,0,sy,ox-markerView[1]*sx,oy-markerView[2]*sy}
    local refx,refy=G.at(view,G.number(da.refx,0,markerView[3]),G.number(da.refy,0,markerView[4]))
    local function place(p,angle,start)
     local orient=da.orient or '0'
     if orient~='auto'and orient~='auto-start-reverse'then angle=math.rad(G.number((orient:gsub('deg$',''))))elseif start and orient=='auto-start-reverse'then angle+=math.pi end
     local co,si=math.cos(angle)*scale,math.sin(angle)*scale
     local base=G.mul(m,{co,si,-si,co,p.x,p.y})
     local position=G.mul(base,{1,0,0,1,-refx,-refy});local cm=G.mul(position,view)
     local group=draw(def,cm,'paint',true,{fill=a.fill,stroke=a.stroke})
     if da.overflow~='visible'then local region=G.coverage(G.rect(0,0,width,height),position,'nonzero',c);P.mask(group,function(x,y)return region[y*c.w+x+1]end)end
     P.composite(layer,group)
    end
    for _,position in ipairs(require(script.Parent.SvgMarkers).positions(node,polys,key,legacy))do
     place(position.point,position.angle,position.start)
    end
   end)
  end
 end
 draw=function(node,parentMatrix,mode,allowDefinition,context)
  local layer=P.new(c.w,c.h);local a=node.attrs
  if a.display=='none'or node.tag=='title'or node.tag=='desc'or(definitions[node.tag]and not allowDefinition)then return layer end
  local m=G.mul(parentMatrix,G.transform(a.transform,legacy));local box=bounds(node)
  if not G.inverse(m)then return layer end
  if node.tag=='image'or node.tag=='text'then
   if mode~='clip'and a.visibility~='hidden'and a.visibility~='collapse'then natives[#natives+1]={node=node,matrix=m,opacity=G.opacity(a.opacity,1)}end
   return layer
  end
  if shapes[node.tag]then
   if a.visibility=='hidden'or a.visibility=='collapse'then return layer end
   local polys=contours(node,m)
   if mode=='clip'then paint(layer,polys,a['clip-rule']or 'nonzero',function()return Color3.new(1,1,1),1 end,m,1)
   else
    local effect=a['vector-effect']or 'none'
    assert(effect=='none'or effect=='non-scaling-stroke','vector-effect sem suporte: '..tostring(effect))
    local function fillPass()
     if node.tag~='line'then paint(layer,polys,a['fill-rule']or 'nonzero',paintFor(a.fill or '#000000',a,box,m,context),m,G.opacity(a['fill-opacity'],1))end
    end
    local function strokePass()
     local width=G.number(a['stroke-width'],1,math.sqrt((vb[3]^2+vb[4]^2)/2));assert(width>=0 and width<=1e5,'stroke-width SVG inválido.')
     if width>0 and a.stroke and a.stroke~='none'then
      local dashed=G.dashes(polys,a['stroke-dasharray'],a['stroke-dashoffset'],math.sqrt((vb[3]^2+vb[4]^2)/2),a.pathlength)
      local sm=m
      if effect=='non-scaling-stroke'then
       local mapped={}
       for _,poly in ipairs(dashed)do
        local points=table.create(#poly)
        for i,p in ipairs(poly)do local px,py=G.at(m,p.x,p.y);points[i]={x=px,y=py}end
        points.closed=poly.closed;mapped[#mapped+1]=points
       end
       dashed=mapped;sm=G.I
      end
      local outline=legacy.stroke(dashed,width,a['stroke-linecap']or 'butt',a['stroke-linejoin']or 'miter',G.number(a['stroke-miterlimit'],4),tolerance)
      paint(layer,outline,'nonzero',paintFor(a.stroke,a,box,m,context),sm,G.opacity(a['stroke-opacity'],1))
     end
    end
    for _,step in ipairs(A.order(a['paint-order']))do
     if step=='fill'then fillPass()elseif step=='stroke'then strokePass()else markers(node,layer,polys,a,m,box,context)end
    end
   end
  else
   assert(node==svg or node.tag=='g'or(allowDefinition and(node.tag=='clippath'or node.tag=='mask'or node.tag=='marker')),'Contêiner SVG não suportado: '..node.tag)
   for _,child in ipairs(node.children)do if not definitions[child.tag]then P.composite(layer,draw(child,m,mode,false,context))end end
  end
  if mode~='clip'and a.filter and a.filter~='none'then
   layer=reference(a.filter,'filter',function(def)return Filters.apply(layer,def,box,m,c,legacy,{defs=defs,shapes=shapes,render=function(n,mx)return draw(n,mx,'paint',true)end})end)
  end
  if a['data-viewport']then
   local r=U.numbers(a['data-viewport']);assert(#r==4,'data-viewport interno inválido.')
   if r[3]>0 and r[4]>0 then local region=G.coverage(G.rect(r[1],r[2],r[3],r[4]),m,'nonzero',c);P.mask(layer,function(x,y)return region[y*c.w+x+1]end)else P.mask(layer,function()return 0 end)end
  end
  if a['clip-path']and a['clip-path']~='none'then local coverage=clip(a['clip-path'],box,m);P.mask(layer,function(x,y)return select(2,P.get(coverage,x,y))end)end
  if mode~='clip'and a.mask and a.mask~='none'then layer=applyMask(layer,a.mask,box,m)end
  if mode~='clip'and G.opacity(a.opacity,1)~=1 then local opacity=G.opacity(a.opacity,1);P.mask(layer,function()return opacity end)end
  return layer
 end
 local surface=draw(svg,G.I,'paint',false)
 local cropped=P.new(rw,rh)
 for y=0,rh-1 do buffer.copy(cropped.data,y*rw*16,surface.data,((y+pad)*c.w+pad)*16,rw*16)end
 return cropped,{paints=c.paints,resolution=resolution,vb=vb,aspect=aspect,definitionCount=total,pad=pad,width=c.w,height=c.h,sx=c.sx,sy=c.sy,natives=natives,expansion=expansion},svg
end
function A.natives(view,target,stats)
 local list=stats.natives or{}
 if #list==0 then return 0 end
 Cost.cap('layers',#list,'Camadas nativas de <image>/<text> do SVG avançado')
 local vb=stats.vb;local count=0
 for _,entry in ipairs(list)do
  local a=entry.node.attrs
  assert((a.filter or'none')=='none'and(a['clip-path']or'none')=='none'and(a.mask or'none')=='none','<image> raster e <text> nativo não aceitam filter, clip-path ou mask.')
  local size=G.number(a['font-size'],16,vb[4])
  local x,y=G.number(a.x,0,vb[3]),G.number(a.y,0,vb[4])
  local w,h=G.number(a.width,0,vb[3]),G.number(a.height,0,vb[4])
  if entry.node.tag=='text'then
   local text=entry.node.text or''
   w=size*.62*math.max(utf8.len(text)or #text,1);h=size*1.25
   local anchor=a['text-anchor']or'start'
   if anchor=='middle'then x-=w*.5 elseif anchor=='end'then x-=w end
   y-=size
  end
  if w>0 and h>0 then
   local minX,minY,maxX,maxY
   for _,corner in ipairs({{x,y},{x+w,y},{x,y+h},{x+w,y+h}})do
    local px,py=G.at(entry.matrix,corner[1],corner[2])
    minX=minX and math.min(minX,px)or px;maxX=maxX and math.max(maxX,px)or px
    minY=minY and math.min(minY,py)or py;maxY=maxY and math.max(maxY,py)or py
   end
   local layer=Instance.new(entry.node.tag=='image'and'ImageLabel'or'TextLabel')
   layer.Name='__SvgNative';layer.BackgroundTransparency=1;layer.BorderSizePixel=0
   layer.Position=UDim2.fromScale(((minX-vb[1])*stats.sx+stats.pad)/stats.width,((minY-vb[2])*stats.sy+stats.pad)/stats.height)
   layer.Size=UDim2.fromScale((maxX-minX)*stats.sx/stats.width,(maxY-minY)*stats.sy/stats.height)
   layer.ZIndex=target.ZIndex+2
   layer:SetAttribute('CssOwned',true)
   if entry.node.tag=='image'then
    layer.Image=a.href or''
    layer.ImageTransparency=1-math.clamp(entry.opacity,0,1)
    local shape=Dom.aspect(a.preserveaspectratio)
    layer.ScaleType=shape.none and Enum.ScaleType.Stretch or(shape.slice and Enum.ScaleType.Crop or Enum.ScaleType.Fit)
    layer:SetAttribute('SvgNativeKind','image')
   else
    layer.Text=entry.node.text or''
    layer.TextScaled=true;layer.RichText=false
    layer.TextTransparency=1-math.clamp(entry.opacity,0,1)
    local ok,color=pcall(U.color,a.fill or'#000000')
    if ok and typeof(color)=='Color3'then layer.TextColor3=color end
    layer.TextXAlignment=Enum.TextXAlignment.Left;layer.TextYAlignment=Enum.TextYAlignment.Center
    layer:SetAttribute('SvgNativeKind','text');layer:SetAttribute('SvgNativeReason',a['data-native']or'texto nativo')
   end
   layer.Parent=view;count+=1
  end
 end
 return count
end
function A.render(svg,target,currentColor,options,legacy)
 options=options or {};local old=target:FindFirstChild('__Svg');assert(not old or old:GetAttribute('CssOwned')==true,'__Svg pertence a outro sistema.')
 if not svg._svgResolved then svg=Style.resolve(Style.prepare(svg,svg.key or '__vector'),currentColor)end
 local vb=U.numbers(svg.attrs.viewbox or('0 0 '..(svg.attrs.width or 24)..' '..(svg.attrs.height or 24)));assert(#vb==4 and vb[3]>0 and vb[4]>0,'viewBox SVG inválido.')
 local resolution,budget=Raster.plan(svg,target,options,vb)
 local signature=A.VERSION..':'..Style.signature(svg)..':'..resolution..':'..budget..':'..tostring(options.images)..':'..tostring(options.alphaLevels or 8)..':'..tostring(currentColor)
 local hash=Codec.hash(signature)
 if options.cache~=false then local count=Raster.get(hash,signature,target,currentColor);if count~=nil then if old then recycle(old)end;return count end end
 local view=Pool.acquire('Frame');view.Name='__Svg';view.BackgroundTransparency=1;view.BorderSizePixel=0;view.ClipsDescendants=true;view.Size=UDim2.fromScale(1,1);view.ZIndex=target.ZIndex;view:SetAttribute('CssOwned',true)
 local count
 local ok,err=xpcall(function()
  local work=U.copy(options);work.resolution=resolution;local surface,stats=A.surface(svg,currentColor,work,legacy)
  local preserve=svg.attrs.preserveaspectratio or 'xMidYMid meet'
  local shape=Dom.aspect(preserve)
  local runs,previous={},{};local tokenBuffer=buffer.create(20)
  local function pixel(x,y)
   local color,a=P.get(surface,x,y);if a<=1e-9 then return nil end
   local channels={color.R*255,color.G*255,color.B*255,0,a*255}
   for i,v in ipairs(channels)do buffer.writef32(tokenBuffer,(i-1)*4,v)end;return buffer.tostring(tokenBuffer),channels
  end
  for y=0,surface.h-1 do
   local row={};local x=0
   while x<surface.w do
    local token,ch=pixel(x,y)
    if not token then x+=1 else
     local first=x;x+=1;while x<surface.w do if pixel(x,y)~=token then break end;x+=1 end
     local key=first..':'..x..':'..token;local run=previous[key]
     if run then run.h+=1 else run={x=first,y=y,w=x-first,h=1,channels=ch};runs[#runs+1]=run end;row[key]=run
    end
   end;previous=row;if options.yield and y%16==0 then options.yield()end
  end
  Cost.cap('bands',#runs,'Faixas do SVG avançado (use data-resolution="64" ou simplifique os efeitos)')
  for i,r in ipairs(runs)do Codec.span(view,r,surface.w,surface.h,currentColor,target.ZIndex+1);if options.yield and i%128==0 then options.yield()end end
  count=#runs
  view:SetAttribute('SvgAspect',stats.aspect);view:SetAttribute('SvgPreserve',preserve);view:SetAttribute('SvgAdvanced',true);view:SetAttribute('SvgFlattened',true);view:SetAttribute('SvgIsolation','CompositedPlane');view:SetAttribute('SvgBackend','Frames')
  view:SetAttribute('SvgPrimitives',count);view:SetAttribute('SvgResolution',resolution);view:SetAttribute('SvgOriginalResolution',resolution);view:SetAttribute('SvgRasterWidth',surface.w);view:SetAttribute('SvgRasterHeight',surface.h)
  view:SetAttribute('SvgPrimitiveBudget',math.max(budget,count));view:SetAttribute('SvgRequestedBudget',budget);view:SetAttribute('SvgBudgetExpanded',count>budget);view:SetAttribute('SvgAdaptivePasses',0);view:SetAttribute('SvgUsesCurrentColor',false)
  view:SetAttribute('SvgCacheHash',hash);view:SetAttribute('SvgCacheHit',false);view:SetAttribute('SvgVectorPaints',stats.paints)
  view:SetAttribute('SvgPreserveAlign',shape.align);view:SetAttribute('SvgPreserveSlice',shape.slice);view:SetAttribute('SvgPreserveDefer',shape.defer)
  local natives=A.natives(view,target,stats)
  view:SetAttribute('SvgNativeLayers',natives)
  if stats.expansion then
   view:SetAttribute('SvgDomUse',stats.expansion.use);view:SetAttribute('SvgDomSymbol',stats.expansion.symbol);view:SetAttribute('SvgDomViewport',stats.expansion.viewport)
   view:SetAttribute('SvgDomImage',stats.expansion.image);view:SetAttribute('SvgDomText',stats.expansion.text);view:SetAttribute('SvgDomSwitch',stats.expansion.switch)
   view:SetAttribute('SvgDomNative',stats.expansion.native);view:SetAttribute('SvgDomDropped',stats.expansion.dropped)
  end
  local candidate=options.images~=false and count>=12;view:SetAttribute('SvgImageCandidate',candidate)
  if count<=8192 then view:SetAttribute('SvgTextureData',Codec.encode(surface.w,surface.h,runs))end
  if options.cache~=false and natives==0 then Raster.put(hash,signature,view,count)end
 end,debug.traceback)
 if not ok then recycle(view);error(err,0)end
 if old then recycle(old)end;view.Parent=target;return count
end
return A
