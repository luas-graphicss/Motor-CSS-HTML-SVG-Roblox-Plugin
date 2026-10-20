local Codec=require(script.Parent.SvgRasterRuntime)
local Pool=require(script.Parent.PoolOwnership).adapter('CssRuntime')
local Vector=require(script.Parent.VectorRaster)
local Lod=require(script.Parent.VectorLod)
local Scan=require(script.Parent.VectorScanline)
local Stroke=require(script.Parent.VectorStroke)
local Bool=require(script.Parent.VectorBoolean)
local R={VERSION='svg-raster-8-vector-engine'}
R.Vector=Vector
R.Lod=Lod
R.Scanline=Scan
R.Stroke=Stroke
R.Boolean=Bool
R.STAGES=Vector.STAGES
R.ALGORITHMS=table.concat({R.VERSION,Vector.VERSION,Vector.STAGES.lod,Vector.STAGES.flatten,Vector.STAGES.stroke,Vector.STAGES.boolean,Vector.STAGES.raster,Vector.STAGES.runs},'|')
local cache=_G.__CssSvgRasterCacheV3
if type(cache)~='table'or cache.version~=3 or cache.algorithms~=R.ALGORITHMS then cache={version=3,algorithms=R.ALGORITHMS,entries={},clock=0,size=0,cost=0,chars=0,hits=0,misses=0};_G.__CssSvgRasterCacheV3=cache end
local function evict(key)
 local e=cache.entries[key];if not e then return end
 cache.entries[key]=nil;cache.size-=1;cache.cost-=e.count;cache.chars-=#e.signature;Pool.releaseTree(e.view)
end
function R.clearCache()local keys={};for k in pairs(cache.entries)do keys[#keys+1]=k end;for _,k in ipairs(keys)do evict(k)end end
function R.cacheStats()return {entries=cache.size,primitives=cache.cost,hits=cache.hits,misses=cache.misses}end
function R.stages()return Vector.stages()end
function R.invalidate(stage)return Vector.invalidate(stage)end
local ignored={id=true,class=true,['aria-label']=true,role=true}
function R.signature(svg,resolution,budget,options)
 options=options or {}
 local pieces={R.ALGORITHMS,':',tostring(resolution),':',tostring(budget),':',tostring(options.images),':',tostring(options.decimation),':',tostring(options.alphaLevels or 'plan'),':',tostring(options.quality or 'auto'),':',tostring(options.profile or 'auto'),':',tostring(options.pack)}
 local function append(text)text=tostring(text);pieces[#pieces+1]=#text..':'..text end
 local function walk(node)
  append(node.tag);local keys={};for k in pairs(node.attrs or {})do if not ignored[k]then keys[#keys+1]=k end end;table.sort(keys)
  for _,k in ipairs(keys)do append(k);append(node.attrs[k])end;append('/')
  for _,child in ipairs(node.children or {})do walk(child)end;append('end')
 end
 walk(svg);local signature=table.concat(pieces);return Codec.hash(signature),signature
end
function R.get(key,signature,target,color)
 local e=cache.entries[key]
 if not e or e.signature~=signature then cache.misses+=1;return nil end
 cache.clock+=1;e.used=cache.clock;cache.hits+=1
 local view=Pool.cloneTree(e.view);view:SetAttribute('SvgCacheHit',true);view.ZIndex=target.ZIndex
 Codec.paint(view,target,color,1,{images=false});view.Parent=target
 return e.count,view
end
function R.put(key,signature,view,count)
 if count>Codec.MAX_RUNS or #signature>240000 then return end
 if cache.entries[key]then evict(key)end
 while cache.size>=64 or cache.cost+count>131072 or cache.chars+#signature>2000000 do
  local oldest,stamp=nil,math.huge;for k,e in pairs(cache.entries)do if e.used<stamp then oldest,stamp=k,e.used end end
  if not oldest then break end;evict(oldest)
 end
 cache.clock+=1;cache.entries[key]={signature=signature,view=Pool.cloneTree(view),count=count,used=cache.clock};cache.size+=1;cache.cost+=count;cache.chars+=#signature
end
local function measure(target,options)
 local w,h=tonumber(options.width),tonumber(options.height)
 if not w or not h then
  local size=target.AbsoluteSize
  if size.X>0 and size.Y>0 then w,h=size.X,size.Y
  elseif target.Size.X.Scale==0 and target.Size.Y.Scale==0 then w,h=target.Size.X.Offset,target.Size.Y.Offset end
 end
 local scale=tonumber(options.pixelScale)or 1
 local ancestor=target
 while ancestor and ancestor:IsA('GuiObject')do
  local s=ancestor:FindFirstChild('__CssScale')
  if s and s:IsA('UIScale')then scale*=math.abs(s.Scale)end
  ancestor=ancestor.Parent
 end
 local ratio=tonumber(target:GetAttribute('CssPixelRatio'))
 if ratio and ratio>0 then scale*=ratio end
 return w,h,math.clamp(scale,1/64,64)
end
function R.plan(svg,target,options,vb)
 options=options or {}
 local attrs=svg and svg.attrs or {}
 local w,h,scale=measure(target,options)
 local preserve=attrs.preserveaspectratio or 'xMidYMid meet'
 if w and h and w>0 and h>0 then
  local aspect=vb[3]/vb[4]
  if preserve~='none'then
   local slice=preserve:find('slice',1,true)~=nil
   if(w/h>aspect)==not slice then w=h*aspect else h=w/aspect end
  end
  w,h=math.max(1,math.floor(w*scale+0.5)),math.max(1,math.floor(h*scale+0.5))
 else w,h=nil,nil end
 local explicit=tonumber(attrs['data-resolution'])or tonumber(options.resolution)
 local base=math.max(Lod.MIN,math.ceil(explicit or(w and math.max(w,h))or 64))
 local planned=select(1,Vector.plan({viewBox=vb,resolution=base,quality=options.quality or attrs['data-quality'],preserveAspectRatio=preserve,profile=options.profile,maxPixels=tonumber(options.maxPixels),maxSpans=tonumber(options.maxSpans)}))
 local plan=table.clone(planned)
 plan.physicalWidth=w
 plan.physicalHeight=h
 plan.measuredScale=scale
 plan.requestedResolution=base
 plan.allowDownsample=explicit==nil and options.maxPrimitives==nil
 local area=plan.width*plan.height
 local ceiling=math.max(128,math.floor(plan.spanLimit))
 local budget=math.clamp(math.floor(tonumber(options.maxPrimitives)or math.min(2048,math.max(96+area*0.25,math.min(area,768)))),128,ceiling)
 return math.max(plan.width,plan.height),budget,plan.width,plan.height,plan
end
function R.new(vb,width,height,options)
 options=options or {}
 local plan=options.plan
 local self={jobs={},regions=nil,options=options,plan=plan,width=math.max(1,math.floor(width)),height=math.max(1,math.floor(height)),culled=0,vertices=0,fast=0,skipped=0,strokes=0,clipped=0,levels=0,passes=0}
 local scaleX=self.width/vb[3]
 local scaleY=self.height/vb[4]
 local layerLimit=math.floor((plan and plan.layerLimit)or 256)
 local edgeLimit=math.floor((plan and plan.edgeLimit)or 262144)
 local spanCeiling=math.floor((plan and plan.spanLimit)or Lod.spanLimit(self.width,self.height,tonumber(options.maxSpans)))
 local epsilon=1e-9*math.max(1,self.width,self.height)
 local function project(polygons,m)
  local polys={}
  local lowX,lowY,highX,highY=math.huge,math.huge,-math.huge,-math.huge
  for _,poly in ipairs(polygons)do
   if #poly>=3 then
    local points=table.create(#poly)
    for index,p in ipairs(poly)do
     local px=p.x or p[1]
     local py=p.y or p[2]
     local x=(m[1]*px+m[3]*py+m[5]-vb[1])*scaleX
     local y=(m[2]*px+m[4]*py+m[6]-vb[2])*scaleY
     assert(x==x and y==y and math.abs(x)<1e12 and math.abs(y)<1e12,'Transformação SVG fora do limite.')
     points[index]={x=x,y=y}
     if x<lowX then lowX=x end
     if y<lowY then lowY=y end
     if x>highX then highX=x end
     if y>highY then highY=y end
    end
    points.closed=true
    polys[#polys+1]=points
    self.vertices+=#points
   end
  end
  return polys,lowX,lowY,highX,highY
 end
 local function bounds(polys)
  local lowX,lowY,highX,highY=math.huge,math.huge,-math.huge,-math.huge
  for _,poly in ipairs(polys)do
   for _,p in ipairs(poly)do
    local x=p.x or p[1]
    local y=p.y or p[2]
    if x<lowX then lowX=x end
    if y<lowY then lowY=y end
    if x>highX then highX=x end
    if y>highY then highY=y end
   end
  end
  return lowX,lowY,highX,highY
 end
 function self:add(polygons,rule,color,alpha,tint,m)
  if alpha<=0 then return end
  assert(rule=='evenodd'or rule=='nonzero','fill-rule deve ser evenodd ou nonzero.')
  local polys,lowX,lowY,highX,highY=project(polygons,m)
  if #polys==0 or highX<=0 or highY<=0 or lowX>=self.width or lowY>=self.height then self.culled+=1;return end
  if self.regions and #self.regions>0 then
   polys=Vector.clip(polys,self.regions,{rule=rule})
   if #polys==0 then self.culled+=1;return end
   rule='nonzero'
   lowX,lowY,highX,highY=bounds(polys)
   if highX<=0 or highY<=0 or lowX>=self.width or lowY>=self.height then self.culled+=1;return end
   self.clipped+=1
  end
  assert(#self.jobs+1<=layerLimit,string.format('Camadas vetoriais SVG (%d) acima do teto derivado %d.',#self.jobs+1,layerLimit))
  local rect=false
  if #polys==1 then
   local poly=polys[1]
   if #poly>=4 and #poly<=8 and highX>lowX+epsilon and highY>lowY+epsilon then
    rect=true
    local corners={}
    local distinct=0
    for _,p in ipairs(poly)do
     local left=math.abs(p.x-lowX)<=epsilon
     local right=math.abs(p.x-highX)<=epsilon
     local top=math.abs(p.y-lowY)<=epsilon
     local bottom=math.abs(p.y-highY)<=epsilon
     if not(left or right)or not(top or bottom)then rect=false;break end
     local key=(left and 0 or 1)+(top and 0 or 2)
     if not corners[key]then corners[key]=true;distinct+=1 end
    end
    if rect then
     for i,a in ipairs(poly)do
      local b=poly[i%#poly+1]
      if math.abs(a.x-b.x)>epsilon and math.abs(a.y-b.y)>epsilon then rect=false;break end
     end
    end
    rect=rect and distinct==4
   end
   if rect then self.fast+=1 end
  end
  self.jobs[#self.jobs+1]={polys=polys,rule=rule,color=color,alpha=alpha,tint=tint,rect=rect,x0=lowX,y0=lowY,x1=highX,y1=highY}
 end
 function self:stroke(subpaths,style,color,alpha,tint,m)
  if alpha<=0 or not subpaths or #subpaths==0 then return 0 end
  local resolved=table.clone(style or {})
  resolved.tolerance=resolved.tolerance or (plan and plan.tolerance)or 0.1
  local signature=resolved.signature
  resolved.signature=nil
  local outline
  if signature then outline=select(1,Stroke.cachedOutline(signature,subpaths,resolved))
  else outline=Stroke.outline(subpaths,resolved)end
  if not outline or #outline==0 then return 0 end
  self.strokes+=1
  self:add(outline,'nonzero',color,alpha,tint,m)
  return #outline
 end
 function self:clip(polygons,m)
  local polys=project(polygons,m)
  if #polys==0 then return 0 end
  self.regions=self.regions or {}
  self.regions[#self.regions+1]=polys
  return #polys
 end
 function self:mask(polygons,m)
  local polys=project(polygons,m)
  if #polys==0 then return 0 end
  self.regions=self.regions or {}
  self.regions[#self.regions+1]=Bool.normalize(polys)
  return #polys
 end
 function self:resetClip()
  self.regions=nil
 end
 local function composite(levels)
  local surface=Vector.surface(self.width,self.height)
  local data=surface.data
  local stride=Vector.STRIDE
  local width=self.width
  local height=self.height
  local skipped=0
  local painted=0
  for index=#self.jobs,1,-1 do
   local job=self.jobs[index]
   surface.layers+=1
   assert(surface.layers<=layerLimit,string.format('Camadas vetoriais SVG (%d) acima do teto derivado %d.',surface.layers,layerLimit))
   local red,green,blue=job.color.R,job.color.G,job.color.B
   local tint=job.tint and 1 or 0;if job.tint then red,green,blue=0,0,0 end
   local base=job.alpha
   Scan.fill(job.polys,{rule=job.rule,levels=levels,yield=self.options.yield,width=width,height=height,maxEdges=edgeLimit},function(x,y,coverage)
    if x<0 or y<0 or x>=width or y>=height then return end
    local at=(y*width+x)*stride
    local current=buffer.readf32(data,at+16)
    if current>=1 then skipped+=1;return end
    local weight=coverage*base*(1-current)
    if weight<=0 then return end
    buffer.writef32(data,at,buffer.readf32(data,at)+red*weight)
    buffer.writef32(data,at+4,buffer.readf32(data,at+4)+green*weight)
    buffer.writef32(data,at+8,buffer.readf32(data,at+8)+blue*weight)
    buffer.writef32(data,at+12,buffer.readf32(data,at+12)+tint*weight)
    local total=current+weight
    buffer.writef32(data,at+16,total>1 and 1 or total)
    painted+=1
   end)
  end
  surface.painted=painted
  surface.skipped=skipped
  self.skipped=skipped
  return surface
 end
 local function downsample(surface,k)
  local w,h=math.max(1,math.ceil(surface.w/k)),math.max(1,math.ceil(surface.h/k))
  local out=Vector.surface(w,h)
  local src,dst=surface.data,out.data
  local stride=Vector.STRIDE
  local sw,sh=surface.w,surface.h
  local painted=0
  for y=0,h-1 do
   local y0,y1=y*k,math.min(sh,(y+1)*k)
   for x=0,w-1 do
    local x0,x1=x*k,math.min(sw,(x+1)*k)
    local r,g,b,t,a=0,0,0,0,0
    for sy=y0,y1-1 do
     local row=sy*sw
     for sx=x0,x1-1 do
      local at=(row+sx)*stride
      r+=buffer.readf32(src,at);g+=buffer.readf32(src,at+4);b+=buffer.readf32(src,at+8);t+=buffer.readf32(src,at+12);a+=buffer.readf32(src,at+16)
     end
    end
    local n=(y1-y0)*(x1-x0)
    if a>0 then
     local at=(y*w+x)*stride
     buffer.writef32(dst,at,r/n);buffer.writef32(dst,at+4,g/n);buffer.writef32(dst,at+8,b/n);buffer.writef32(dst,at+12,t/n);buffer.writef32(dst,at+16,a/n)
     painted+=1
    end
   end
   if self.options.yield and y%32==0 then self.options.yield()end
  end
  out.layers=surface.layers;out.painted=painted;out.skipped=surface.skipped
  return out
 end
 local function extract(budget)
  local levels=self.options.alphaLevels and math.clamp(math.floor(self.options.alphaLevels),4,4096)or math.floor((plan and plan.levels)or 256)
  local surface=composite(levels)
  local ladder={{false,false},{64,64},{24,32},{12,16},{8,8},{5,4},{3,3}}
  local best,failure=nil,nil
  local passes=-1
  local scaled=false
  local index=1
  local allowDownsample=budget~=nil and plan~=nil and plan.allowDownsample==true
  while index<=#ladder do
   local pair=ladder[index]
   local ok,runs,info=pcall(Vector.toRuns,surface,{plan=plan,spanLimit=spanCeiling,yield=self.options.yield,colorLevels=pair[1]or nil,alphaLevels=pair[2]and math.min(pair[2],levels)or nil})
   passes+=1
   if ok then
    if not best or #runs<#best.runs then best={runs=runs,info=info,colorLevels=pair[1],surface=surface}end
    if not budget or #runs<=budget then break end
   else failure=runs end
   local estimate=ok and #runs or (spanCeiling*2)
   if allowDownsample and not scaled and estimate>budget and math.min(surface.w,surface.h)>=48 then
    local k=math.clamp(math.ceil(math.sqrt(estimate/budget)*1.25),2,8)
    while k>2 and math.min(surface.w,surface.h)/k<24 do k-=1 end
    surface=downsample(surface,k);scaled=k
    index=math.max(index,1)
   else index+=1 end
  end
  if not best then error(failure or 'Falha ao extrair faixas vetoriais.',0)end
  self.levels=levels
  self.passes=passes
  self.colorLevels=best.colorLevels
  self.downsample=scaled or 1
  return best.surface,best.runs,best.info
 end
 function self:finish(view,target,color,budget)
  view:SetAttribute('SvgFlattened',true)
  view:SetAttribute('SvgIsolation','CompositedPlane')
  view:SetAttribute('SvgBackend','Frames')
  view.ZIndex=target.ZIndex
  local rw,rh=self.width,self.height
  local requestedBudget=budget
  local count=0
  local usesTint=false
  view:SetAttribute('SvgBudgetExpanded',false)
  for _,job in ipairs(self.jobs)do if job.tint then usesTint=true end end
  if #self.jobs==1 and self.jobs[1].rect then
   local job=self.jobs[1]
   local x0=math.max(0,job.x0/rw)
   local y0=math.max(0,job.y0/rh)
   local x1=math.min(1,job.x1/rw)
   local y1=math.min(1,job.y1/rh)
   local f=Pool.acquire('Frame')
   f.Name='Span'
   f.BorderSizePixel=0
   f.Position=UDim2.fromScale(x0,y0)
   f.Size=UDim2.fromScale(x1-x0,y1-y0)
   f.ZIndex=target.ZIndex+1
   f.BackgroundColor3=job.tint and color or job.color
   f.BackgroundTransparency=1-job.alpha
   f:SetAttribute('CssOwned',true)
   f:SetAttribute('SvgLayer',1)
   f:SetAttribute('SvgAlpha',job.alpha)
   if job.tint then f:SetAttribute('SvgCurrentColor',true)end
   f.Parent=view
   count=1
   self.levels=math.floor((plan and plan.levels)or 256)
   view:SetAttribute('SvgMergedHorizontal',0)
   view:SetAttribute('SvgMergedVertical',0)
   view:SetAttribute('SvgImageCandidate',false)
   view:SetAttribute('SvgPaintedPixels',0)
   view:SetAttribute('SvgInstances',1)
   view:SetAttribute('SvgPacked',false)
  else
   local surface,runs,info=extract(budget)
   rw,rh=surface.w,surface.h;self.width,self.height=rw,rh
   view:SetAttribute('SvgDownsample',self.downsample or 1)
   rw,rh=surface.w,surface.h;self.width,self.height=rw,rh
   view:SetAttribute('SvgDownsample',self.downsample or 1)
   if #runs>budget then budget=#runs;view:SetAttribute('SvgBudgetExpanded',true)end
   count=#runs
   view:SetAttribute('SvgInstances',Codec.spans(view,runs,rw,rh,color,target.ZIndex+1,{pack=self.options.pack,yield=self.options.yield}))
   local candidate=self.options.images~=false and count>=12 and count<=math.min(spanCeiling,32768)and rw<=Codec.MAX_TEXTURE_DIMENSION and rh<=Codec.MAX_TEXTURE_DIMENSION and rw*rh<=Codec.MAX_TEXTURE_PIXELS
   if candidate then view:SetAttribute('SvgTextureData',Codec.encode(rw,rh,runs))end
   view:SetAttribute('SvgImageCandidate',candidate)
   view:SetAttribute('SvgMergedHorizontal',info.horizontal)
   view:SetAttribute('SvgMergedVertical',info.vertical)
   view:SetAttribute('SvgPaintedPixels',surface.painted)
  end
  view:SetAttribute('SvgPrimitives',count)
  view:SetAttribute('SvgResolution',math.max(rw,rh))
  view:SetAttribute('SvgRasterWidth',rw)
  view:SetAttribute('SvgRasterHeight',rh)
  view:SetAttribute('SvgPrimitiveBudget',budget)
  view:SetAttribute('SvgRequestedBudget',requestedBudget)
  view:SetAttribute('SvgAdaptivePasses',self.passes)
  view:SetAttribute('SvgUsesCurrentColor',usesTint)
  view:SetAttribute('SvgCulledPaints',self.culled)
  view:SetAttribute('SvgInputVertices',self.vertices)
  view:SetAttribute('SvgFastPaths',self.fast)
  view:SetAttribute('SvgOccludedSamples',self.skipped)
  view:SetAttribute('SvgVectorEngine',R.VERSION)
  view:SetAttribute('SvgAlphaLevels',self.levels)
  view:SetAttribute('SvgLayerLimit',layerLimit)
  view:SetAttribute('SvgSpanLimit',spanCeiling)
  view:SetAttribute('SvgEdgeLimit',edgeLimit)
  view:SetAttribute('SvgStrokeOutlines',self.strokes)
  view:SetAttribute('SvgClippedPaints',self.clipped)
  if plan then
   view:SetAttribute('SvgLodQuality',tostring(plan.quality))
   view:SetAttribute('SvgLodStep',plan.step)
   view:SetAttribute('SvgTolerance',plan.tolerance)
   view:SetAttribute('SvgPixelScale',plan.pixelScale)
   view:SetAttribute('SvgDevicePixels',plan.devicePixels)
  end
  return count
 end
 return self
end
return R
