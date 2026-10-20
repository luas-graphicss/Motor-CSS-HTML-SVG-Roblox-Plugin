local U=require(script.Parent.Util)
local V=require(script.Parent.VisualStyle)
local G=require(script.Parent.VisualGeometry)
local Gradient=require(script.Parent.CssGradient)
local Images=require(script.Parent.BackgroundImages)
local K=require(script.Parent.PaintPrimitives)
local Border=require(script.Parent.BorderPaint)
local Imaging=require(script.Parent.AdvancedImaging)
local Shapes=require(script.Parent.PaintShapes)
local Shadow=require(script.Parent.ShadowPaint)
local Outline=require(script.Parent.OutlinePaint)
local A={VERSION=1}
local nativeFits={fill=Enum.ScaleType.Stretch,contain=Enum.ScaleType.Fit,cover=Enum.ScaleType.Crop}
local elementSources={}
function A.element(id,source)
 if type(id)~='string'then return nil end
 if id:sub(1,1)~='#'then id='#'..id end
 if source==nil then return elementSources[id]end
 if source==false or source==''then elementSources[id]=nil else elementSources[id]=source end
 return elementSources[id]
end
function A.elements()return elementSources end
function A.fade(gradient,alpha)
 if alpha>=0.999 then return gradient end
 local copy=table.clone(gradient);local stops=table.create(#gradient.stops)
 for index,stop in ipairs(gradient.stops)do local s=table.clone(stop);s.a=(stop.a or 1)*alpha;stops[index]=s end
 copy.stops=stops;return copy
end
local function flatten(descriptor,weight,out,dppx)
 descriptor=Imaging.select(descriptor,dppx)
 local kind=type(descriptor)=='table'and descriptor.kind or 'none'
 if kind=='asset'then out[#out+1]={source=descriptor.source,weight=weight}
 elseif kind=='element'then
  local source=A.element(descriptor.source)
  out[#out+1]={source=source,element=descriptor.source,missing=source==nil or nil,weight=weight}
 elseif kind=='gradient'then out[#out+1]={value=descriptor.value,weight=weight}
 elseif kind=='image'then
  if descriptor.source then flatten(descriptor.source,weight,out,dppx)
  elseif descriptor.fallback then out[#out+1]={color=descriptor.fallback,weight=weight}end
 elseif kind=='cross-fade'then
  for _,item in ipairs(descriptor.layers)do flatten(item.image,weight*(item.percent or 0)/100,out,dppx)end
 end
 return out
end
function A.legacy(style)return V.legacyBackground(style)end
function A.dynamic(style)
 local value=style['background-attachment']or ''
 return value:find('fixed',1,true)~=nil or value:find('local',1,true)~=nil
end
function A.needs(style)
 if style._hasSideBorders then return true end
 if style['box-shadow']and style['box-shadow']~='none'then return true end
 if style['clip-path']and style['clip-path']~='none'then return true end
 if Outline.active(style)then return true end
 if type(style['background-clip'])=='string'and style['background-clip']:find('text',1,true)then return true end
 if style['border-image-source']and style['border-image-source']~='none'then return true end
 local border=style['border-style'];if border and border~='solid'and border~='none'and border~='hidden'then return true end
 local firstRadius=style[V.radiusKeys[1]]or 0
 for _,key in ipairs(V.radiusKeys)do
  local r=style[key]or 0
  if r~=firstRadius or type(r)=='table'or(type(r)=='string'and(r:find('%%')or #U.split(r,' ')>1))then return true end
 end
 local layers=V.layers(style);if #layers>1 then return true end
 local l=layers[1]
 if l.attachment~='scroll'or l.clip~='border-box'then return true end
 if l.image=='none'then return false end
 return true
end
local function zeroRect(x,y,w,h)return {x=x,y=y,w=w,h=h}end
local function clipKind(value)return value=='text'and'border-box'or value end
function A.plan(style,box,vw,vh)
 local layers,color=V.layers(style);local context=G.context(style,vw,vh)
 local shape=Shapes.clipPath(style['clip-path'],box.w,box.h,context)
 local plan={layers={},box=box,context=context,color=color,shape=shape,colorText=layers[#layers].clip=='text',colorClip=G.rect(style,box,clipKind(layers[#layers].clip),context)}
 if shape then plan.colorClip.shape=shape end
 plan.borderBox=G.rect(style,box,'border-box',context)
 plan.paddingBox=G.rect(style,box,'padding-box',context)
 plan.shadows=Shadow.plan(style,box,context)
 plan.outline=Outline.plan(style,box,context)
 plan.baseColor,plan.baseAlpha=V.color(color,style.color)
 local imaging=Imaging.plan(style,context)
 plan.imaging=imaging;plan.resample=imaging.resample;plan.dppx=imaging.resolution.dppx
 for index,l in ipairs(layers)do
  local clip=G.rect(style,box,clipKind(l.clip),context);local origin=G.rect(style,box,l.origin,context)
  if shape then clip.shape=shape end
  if l.attachment=='fixed'then origin=zeroRect(-(box._backgroundX or 0),-(box._backgroundY or 0),vw,vh)
  elseif l.attachment=='local'and box._backgroundScroll then
   local content=table.clone(box);content.w=math.max(box.w,box.contentW or box.w);content.h=math.max(box.h,box.contentH or box.h)
   origin=G.rect(style,content,l.origin,context);origin.x-=box._backgroundScrollX or 0;origin.y-=box._backgroundScrollY or 0
  end
  local p={index=index,image=l.image,clip=clip,origin=origin,attachment=l.attachment,repeatValue=l['repeat'],resample=plan.resample,textClip=l.clip=='text'};plan.layers[index]=p
  if l.image~='none'and origin.w>0 and origin.h>0 then
   local iw,ih
   if l.image:match('^url%(')then p.source=V.source(l.image);iw,ih=Images.size(p.source)
   elseif not l.image:find('gradient(',1,true)then
    local units=flatten(Imaging.parseImage(l.image),1,{},plan.dppx)
    if #units==1 and units[1].source then p.source=units[1].source
    elseif #units>0 then p.units=units end
    for _,unit in ipairs(units)do
     if unit.missing then p.missingElement=unit.element end
     if unit.source and not iw then iw,ih=Images.size(unit.source)end
    end
   end
   local tw,th=G.size(l.size,origin.w,origin.h,iw,ih,context);local rx,ry=G.repeatModes(l['repeat']);p.rx,p.ry=rx,ry
   if tw>0 and th>0 then
    local words=U.split(l.size,' ');local xAuto=words[1]=='auto';local yAuto=not words[2]or words[2]=='auto'
    if rx=='round'then tw=origin.w/math.max(1,math.floor(origin.w/tw+.5));if ry~='round'and yAuto and iw then th=tw*ih/iw end end
    if ry=='round'then th=origin.h/math.max(1,math.floor(origin.h/th+.5));if rx~='round'and xAuto and iw then tw=th*iw/ih end end
    local x,y=G.position(l.position,origin.w,origin.h,tw,th,context)
    p.xt=G.tiles(origin.w,tw,x,rx,clip.x-origin.x,clip.x+clip.w-origin.x)
    p.yt=G.tiles(origin.h,th,y,ry,clip.y-origin.y,clip.y+clip.h-origin.y)
    p.tw,p.th,p.iw,p.ih=tw,th,iw or tw,ih or th
    p.fit=not iw and(l.size=='cover'or l.size=='contain')and l.size or nil
    if p.units then
     for _,unit in ipairs(p.units)do if unit.value then unit.gradient=Gradient.resolve(unit.value,tw,th,context,style.color)end end
    elseif not p.source then p.gradient=Gradient.resolve(l.image,tw,th,context,style.color)end
   else p.xt,p.yt={},{}end
  else p.xt,p.yt={},{}end
  if p.textClip then p.xt,p.yt={},{};p.gradient=nil;p.units=nil end
 end
 return plan
end
local function mapFor(layer,x,y)
 return {sx=0,sy=0,sw=layer.iw,sh=layer.ih,iw=layer.iw,ih=layer.ih,dx=layer.origin.x+x.start,dy=layer.origin.y+y.start,dw=x.size,dh=y.size}
end
local function paintUnits(k,layer,p,map,z,style)
 local total=0
 for _,unit in ipairs(p.units)do total+=math.max(unit.weight or 0,0)end
 if total<=1e-6 then return end
 local cumulative=0
 for _,unit in ipairs(p.units)do
  local weight=math.max(unit.weight or 0,0)
  if weight>1e-6 then
   cumulative+=weight
   local alpha=math.clamp(weight/cumulative,0,1)
   if unit.source then K.image(k,layer,p.clip,map,unit.source,z,{fit=p.fit,resample=p.resample,alpha=alpha})
   elseif unit.gradient then
    local field=table.clone(map);field.sw,field.sh=p.tw,p.th
    K.field(k,layer,p.clip,field,A.fade(unit.gradient,alpha),z)
   elseif unit.color then
    local color,a=V.color(unit.color,style and style.color)
    K.maskBands(p.clip,{x=map.dx,y=map.dy,w=map.dw,h=map.dh},k.step,function(bx,by,bw,bh)
     local band=k:make('Frame','ColorBand',layer);band.Position=UDim2.fromOffset(bx,by);band.Size=UDim2.fromOffset(bw,bh);band.ZIndex=z
     band.BackgroundColor3=color;band.BackgroundTransparency=1-a*alpha*k.opacity;band:SetAttribute('CssPaintAlpha',a*alpha)
    end)
   end
  end
 end
end
function A.draw(paint,style,box,opacity,vw,vh,host)
 local plan=A.plan(style,box,vw,vh);local k=K.new(paint,opacity,box,box._checkpoint);local top=paint.ZIndex
 paint.BackgroundTransparency=1;paint:SetAttribute('CssAdvancedPaint',true);paint:SetAttribute('CssPaintBackend','NativeFieldBands');paint:SetAttribute('CssBackgroundLayers',#plan.layers)
 local depth=#plan.layers+2
 local colorClip=plan.colorClip
 local opaque=not host and not plan.colorText and plan.baseAlpha>=.999 and not colorClip.shape and colorClip.x<=.001 and colorClip.y<=.001 and colorClip.x+colorClip.w>=box.w-.001 and colorClip.y+colorClip.h>=box.h-.001
 if plan.shadows then Shadow.draw(k,paint,plan.shadows,{box=plan.borderBox,radii=plan.borderBox.r,padding=plan.paddingBox,shape=plan.shape,opaque=opaque},top-depth-1,top-1)end
 if plan.colorText then
 elseif host then
  local r=colorClip.r
  paint:SetAttribute('CssTextHost',true);paint:SetAttribute('CssTextHostAlpha',plan.baseAlpha)
  host(plan.baseColor,plan.baseAlpha,r and{r[1].x,r[2].x,r[3].x,r[4].x}or{0,0,0,0})
 else K.fill(k,paint,colorClip,plan.baseColor,plan.baseAlpha,top-depth,'background-color')end
 for i=#plan.layers,1,-1 do
  local p=plan.layers[i];local z=top-i-1
  local layer=k:make('Frame','BackgroundLayer'..i,paint);layer.Size=UDim2.fromScale(1,1);layer.ZIndex=z
  layer:SetAttribute('CssBackgroundLayer',i);layer:SetAttribute('CssBackgroundSource',p.image);layer:SetAttribute('CssBackgroundAttachment',p.attachment)
  if p.gradient then layer:SetAttribute('CssGradientKind',p.gradient.kind);layer:SetAttribute('CssGradientRepeating',p.gradient.repeating)end
  if #p.xt>0 and #p.yt>0 then
   if p.source and p.rx~='space'and p.ry~='space'and(#p.xt>1 or #p.yt>1)then
    local x,y=p.xt[1],p.yt[1];local lastX,lastY=p.xt[#p.xt],p.yt[#p.yt];local map=mapFor(p,x,y)
    map.dw=lastX.start+lastX.size-x.start;map.dh=lastY.start+lastY.size-y.start
    K.image(k,layer,p.clip,map,p.source,z,{tile={w=p.tw,h=p.th},resample=p.resample})
   else
    assert(#p.xt*#p.yt<=1024,'Background excede 1024 tiles; use tamanho maior ou repeat nativo de imagem.')
    for _,y in ipairs(p.yt)do for _,x in ipairs(p.xt)do
     local map=mapFor(p,x,y)
     if p.source then K.image(k,layer,p.clip,map,p.source,z,{fit=p.fit,resample=p.resample})
     elseif p.units then paintUnits(k,layer,p,map,z,style)
     else map.sw,map.sh=p.tw,p.th;K.field(k,layer,p.clip,map,p.gradient,z)end
    end end
   end
  end
 end
 local border=k:make('Frame','AdvancedBorder',paint);border.Size=UDim2.fromScale(1,1);border.ZIndex=top
 border:SetAttribute('CssBorderStyle',style['border-style']or 'solid')
 if not Border.image(k,border,style,box,plan.context,top,plan.shape)then Border.stroke(k,border,style,box,plan.context,top,plan.shape)end
 if plan.outline then
  local outline=k:make('Frame','AdvancedOutline',paint);outline.Size=UDim2.fromScale(1,1);outline.ZIndex=top+1
  outline:SetAttribute('CssOutlineStyle',plan.outline.mode)
  Outline.draw(k,outline,plan.outline,top+1,plan.shape)
 end
 paint:SetAttribute('CssPaintPrimitives',k.count);paint:SetAttribute('CssPaintRowStep',k.step)
 paint:SetAttribute('CssPaintShadows',plan.shadows and #plan.shadows or 0)
 paint:SetAttribute('CssPaintOutline',plan.outline and plan.outline.mode or nil)
 paint:SetAttribute('CssPaintClipShape',plan.shape and true or nil)
 paint:SetAttribute('CssPaintOrderDepth',depth)
 paint:SetAttribute('CssBackgroundClipText',plan.colorText or nil)
 return plan
end
local function over(c,a,s,b)
 local out=b+a*(1-b);if out<=1e-9 then return Color3.new(),0 end
 return Color3.new((s.R*b+c.R*a*(1-b))/out,(s.G*b+c.G*a*(1-b))/out,(s.B*b+c.B*a*(1-b))/out),out
end
function A.sampleUnits(p,px,py,imageSampler,complete)
 local total=0
 for _,unit in ipairs(p.units)do total+=math.max(unit.weight or 0,0)end
 if total<=1e-6 then return nil,nil,complete end
 local r,g,b,a=0,0,0,0
 for _,unit in ipairs(p.units)do
  local weight=math.max(unit.weight or 0,0)/total
  if weight>1e-6 then
   local color,alpha
   if unit.gradient then color,alpha=Gradient.sample(unit.gradient,px*p.tw,py*p.th)
   elseif unit.color then color,alpha=V.color(unit.color)
   elseif unit.source and imageSampler then color,alpha=imageSampler(unit.source,px*p.iw,py*p.ih,p.iw,p.ih)
   else complete=false end
   if color then r+=color.R*alpha*weight;g+=color.G*alpha*weight;b+=color.B*alpha*weight;a+=alpha*weight end
  end
 end
 if a<=1e-9 then return Color3.new(),0,complete end
 return Color3.new(math.clamp(r/a,0,1),math.clamp(g/a,0,1),math.clamp(b/a,0,1)),math.clamp(a,0,1),complete
end
function A.sampleBackground(plan,x,y,imageSampler,blend)
 local c,a=Color3.new(),0;local complete=true;local clip=plan.colorClip
 if plan.shape and not Shapes.contains(plan.shape,x,y)then return c,a,complete end
 if not plan.colorText and G.inside(clip.r,clip.w,clip.h,x-clip.x,y-clip.y)then c,a=plan.baseColor,plan.baseAlpha end
 for i=#plan.layers,1,-1 do
  local p=plan.layers[i];clip=p.clip
  if G.inside(clip.r,clip.w,clip.h,x-clip.x,y-clip.y)then
   local tx,ty
   for _,t in ipairs(p.xt)do if x>=p.origin.x+t.start and x<p.origin.x+t.start+t.size then tx=t;break end end
   for _,t in ipairs(p.yt)do if y>=p.origin.y+t.start and y<p.origin.y+t.start+t.size then ty=t;break end end
   if tx and ty then
    local px=(x-p.origin.x-tx.start)/tx.size;local py=(y-p.origin.y-ty.start)/ty.size;local color,alpha
    if p.gradient then color,alpha=Gradient.sample(p.gradient,px*p.tw,py*p.th)
    elseif p.units then color,alpha,complete=A.sampleUnits(p,px,py,imageSampler,complete)
    elseif imageSampler then color,alpha=imageSampler(p.source,px*p.iw,py*p.ih,p.iw,p.ih)else complete=false end
    if color then if blend then c,a=blend(c,a,color,alpha,i)else c,a=over(c,a,color,alpha)end end
   end
  end
 end
 return c,a,complete
end
function A.motion(paint,values,opacity,cache)
 if not paint or not paint:GetAttribute('CssAdvancedPaint')then return end
 if cache.advancedMotionPaint~=paint then
  cache.advancedMotionPaint=paint;cache.advancedAlphaTargets={}
  for _,o in ipairs(paint:GetDescendants())do local a=o:GetAttribute('CssPaintAlpha');if a~=nil then cache.advancedAlphaTargets[#cache.advancedAlphaTargets+1]={object=o,a=a,role=o:GetAttribute('CssPaintRole'),image=o:IsA('ImageLabel'),shadow=o:IsA('UIShadow')}end end
 end
 for _,t in ipairs(cache.advancedAlphaTargets)do
  local alpha=t.a;local o=t.object
  if t.role=='background-color'and values.background then o.BackgroundColor3=values.background.color;alpha=values.background.alpha end
  if t.shadow then o.Transparency=1-alpha*opacity elseif t.image then o.ImageTransparency=1-alpha*opacity else o.BackgroundTransparency=1-alpha*opacity end
 end
end
function A.fit(object,style,box,opacity)
 if not object:IsA('ImageLabel')then return false end
 style=style or {}
 local plan=Imaging.plan(style,{})
 K.resample(object,plan.resample)
 local source=object.Image
 local proxy=object:FindFirstChild('__ObjectFit')
 local aw=box and box.w or object.AbsoluteSize.X
 local ah=box and box.h or object.AbsoluteSize.Y
 local nw=object:GetAttribute('CssImageIntrinsicWidth')
 local nh=object:GetAttribute('CssImageIntrinsicHeight')
 if not nw or not nh then nw,nh=Images.size(source)end
 local position=plan.position
 local centered=position.x.edge=='left'and position.x.offset=='50%'and position.y.edge=='top'and position.y.offset=='50%'
 local native=nativeFits[plan.fit]
 if source==''or not nw or not nh or nw<=0 or nh<=0 or(native and centered)then
  if proxy then proxy:Destroy()end
  object:SetAttribute('CssObjectFitProxy',nil);object:SetAttribute('CssObjectFit',plan.fit)
  object.ScaleType=native or Enum.ScaleType.Stretch
  object.ImageTransparency=1-(opacity or 1)
  return false
 end
 local fitted=Imaging.objectBox(plan.fit,style['object-position']or '50% 50%',{w=aw,h=ah},{w=nw,h=nh},function(text,base)return G.length(text,base,{})end)
 if not proxy then
  proxy=Instance.new('ImageLabel');proxy.Name='__ObjectFit';proxy.BackgroundTransparency=1;proxy.BorderSizePixel=0;proxy:SetAttribute('CssOwned',true);proxy.Parent=object
 end
 proxy.Image=source;proxy.ScaleType=Enum.ScaleType.Stretch;proxy.ZIndex=object.ZIndex
 proxy.Position=UDim2.fromOffset(fitted.x,fitted.y);proxy.Size=UDim2.fromOffset(math.max(fitted.w,0),math.max(fitted.h,0))
 proxy.ImageTransparency=1-(opacity or 1);proxy:SetAttribute('CssObjectFit',plan.fit)
 K.resample(proxy,plan.resample)
 object.ClipsDescendants=true;object.ImageTransparency=1
 object:SetAttribute('CssObjectFitProxy',true);object:SetAttribute('CssObjectFit',plan.fit)
 return true
end
function A.imageOpacity(object,opacity)
 local proxy=object:GetAttribute('CssObjectFitProxy')and object:FindFirstChild('__ObjectFit')
 if proxy then proxy.ImageTransparency=1-opacity;object.ImageTransparency=1;return true end
 object.ImageTransparency=1-opacity
 return false
end
local function cornerScalar(corner)
 if type(corner)=='table'then
  local x=corner.x or 0;local y=corner.y or 0
  return math.min(x,y),x~=y
 end
 return corner or 0,false
end
function A.contentClip(style,box,vw,vh)
 local context=G.context(style,vw,vh)
 local rect=G.rect(style,box,'padding-box',context)
 local radii={0,0,0,0};local approximate=false
 if rect and rect.r then
  for i=1,4 do local scalar,uneven=cornerScalar(rect.r[i]);radii[i]=math.max(scalar,0);approximate=approximate or uneven end
 end
 local out={clips=false,shape=nil,radii=radii,approximate=approximate,w=(rect and rect.w)or box.w,h=(rect and rect.h)or box.h}
 local value=style['clip-path']
 if value and value~='none'then
  local parsed=Shapes.parse(value,box.w,box.h,context)
  local kind=parsed and parsed.kind
  if kind and kind~='none'then
   out.clips=true;out.shape=kind
   if kind=='circle'or kind=='ellipse'then
    local rx=math.max(parsed.rx or 0,0);local ry=math.max(parsed.ry or 0,0);local scalar=math.min(rx,ry)
    radii[1],radii[2],radii[3],radii[4]=scalar,scalar,scalar,scalar
    out.w,out.h=rx*2,ry*2;out.approximate=rx~=ry
   elseif kind=='inset'then
    local scalar=math.max(parsed.radius or 0,0)
    radii[1],radii[2],radii[3],radii[4]=scalar,scalar,scalar,scalar
    out.w,out.h=math.max(parsed.iw or 0,0),math.max(parsed.ih or 0,0)
   else out.approximate=true end
  end
 end
 local limit=math.max(math.min(out.w,out.h)/2,0)
 for i=1,4 do radii[i]=math.clamp(radii[i],0,limit)end
 out.rounded=radii[1]>0 or radii[2]>0 or radii[3]>0 or radii[4]>0
 return out
end
A.shadowPaint=Shadow
A.outlinePaint=Outline
A.clipShape=Shapes.clipPath
A.assetVersion=Images.version
A.gradientStats=Gradient.stats
return A
