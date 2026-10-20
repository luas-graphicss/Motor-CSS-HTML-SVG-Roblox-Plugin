local Cache=require(script.Parent.VectorCache)
local Lod=require(script.Parent.VectorLod)
local Scan=require(script.Parent.VectorScanline)
local Stroke=require(script.Parent.VectorStroke)
local Bool=require(script.Parent.VectorBoolean)
local R={VERSION='vector-raster-2',MAX_BYTES=33554432,CHANNELS=5,STRIDE=20}
R.Cache=Cache
R.Lod=Lod
R.Scanline=Scan
R.Stroke=Stroke
R.Boolean=Bool
R.STAGES={lod=Lod.ALGORITHM,flatten='flatten-adaptive-1',stroke=Stroke.ALGORITHM,boolean=Bool.ALGORITHM,raster=Scan.ALGORITHM,runs='rle-vertical-2'}
local readf32=buffer.readf32
local writef32=buffer.writef32
local floor=math.floor
local clamp=math.clamp
function R.stages()
 return {
  lod=Cache.stage('lod',R.STAGES.lod,{maxEntries=256,maxBytes=262144}),
  flatten=Cache.stage('flatten',R.STAGES.flatten,{maxEntries=192,maxBytes=8388608}),
  stroke=Stroke.stage(),
  boolean=Bool.stage(),
  raster=Cache.stage('raster',R.STAGES.raster,{maxEntries=64,maxBytes=16777216}),
  runs=Cache.stage('runs',R.STAGES.runs,{maxEntries=96,maxBytes=8388608}),
 }
end
function R.plan(spec)
 spec=spec or {}
 local merged=table.clone(spec)
 merged.maxPixels=merged.maxPixels or floor(R.MAX_BYTES/R.STRIDE)
 local stage=Cache.stage('lod',R.STAGES.lod,{maxEntries=256,maxBytes=262144})
 local key=Cache.key({merged.viewBox and merged.viewBox[3] or 0,merged.viewBox and merged.viewBox[4] or 0,merged.width,merged.height,merged.pixelScale,merged.resolution,merged.quality,merged.profile,merged.maxPixels,merged.maxSpans,merged.preserveAspectRatio})
 local cached=Cache.get(stage,key)
 if cached then return cached,true end
 local plan=Lod.plan(merged)
 Cache.put(stage,key,plan,512)
 return plan,false
end
function R.planForTarget(target,spec)
 spec=spec or {}
 local measured=Lod.measure(target,spec)
 local merged=table.clone(spec)
 merged.width=measured.width
 merged.height=measured.height
 merged.pixelScale=measured.pixelScale
 local plan=select(1,R.plan(merged))
 return plan,measured
end
function R.surface(width,height)
 local w=floor(width)
 local h=floor(height)
 assert(w>0 and h>0,'Superficie vetorial exige dimensoes positivas.')
 local bytes=w*h*R.STRIDE
 assert(bytes<=R.MAX_BYTES,string.format('Superficie vetorial de %dx%d excede o orcamento de %d bytes.',w,h,R.MAX_BYTES))
 return {w=w,h=h,data=buffer.create(bytes),bytes=bytes,layers=0,painted=0,skipped=0}
end
function R.clear(surface)
 buffer.fill(surface.data,0,0)
 surface.layers=0
 surface.painted=0
 surface.skipped=0
 return surface
end
function R.get(surface,x,y)
 local at=(y*surface.w+x)*R.STRIDE
 local alpha=readf32(surface.data,at+16)
 if alpha<=0 then return 0,0,0,0,0 end
 return readf32(surface.data,at)/alpha,readf32(surface.data,at+4)/alpha,readf32(surface.data,at+8)/alpha,readf32(surface.data,at+12)/alpha,alpha
end
local function blend(surface,x,y,r,g,b,tint,alpha)
 if alpha<=0 then return false end
 if alpha>1 then alpha=1 end
 local data=surface.data
 local at=(y*surface.w+x)*R.STRIDE
 local inverse=1-alpha
 if tint>=1 then r,g,b=0,0,0 end
 writef32(data,at,readf32(data,at)*inverse+r*alpha)
 writef32(data,at+4,readf32(data,at+4)*inverse+g*alpha)
 writef32(data,at+8,readf32(data,at+8)*inverse+b*alpha)
 writef32(data,at+12,readf32(data,at+12)*inverse+tint*alpha)
 writef32(data,at+16,readf32(data,at+16)*inverse+alpha)
 return true
end
R.blend=blend
function R.fill(surface,contours,paint,options)
 options=options or {}
 paint=paint or {}
 local plan=options.plan
 local color=paint.color or Color3.new()
 local base=paint.alpha==nil and 1 or clamp(paint.alpha,0,1)
 local tint=paint.tint and 1 or 0
 local sampler=paint.sampler
 local mask=options.mask
 surface.layers+=1
 local layerLimit=options.layerLimit or (plan and plan.layerLimit) or Lod.layerLimit(options.profile)
 assert(surface.layers<=layerLimit,string.format('Camadas vetoriais (%d) acima do teto derivado %d.',surface.layers,layerLimit))
 if base<=0 then return 0,nil end
 local painted=0
 local red,green,blue=color.R,color.G,color.B
 local stats=Scan.fill(contours,{
  matrix=options.matrix,
  rule=options.rule,
  levels=options.levels or (plan and plan.levels),
  epsilon=options.epsilon,
  yield=options.yield,
  width=surface.w,
  height=surface.h,
  clip=options.clip,
  maxEdges=options.maxEdges or (plan and plan.edgeLimit),
 },function(x,y,coverage)
  if x<0 or y<0 or x>=surface.w or y>=surface.h then return end
  local weight=coverage*base
  if mask then
   weight*=clamp(mask(x,y),0,1)
  end
  if weight<=0 then return end
  local r,g,b=red,green,blue
  if sampler then
   local sampled,alpha=sampler(x+0.5,y+0.5)
   if not sampled or not alpha or alpha<=0 then return end
   r,g,b=sampled.R,sampled.G,sampled.B
   weight*=clamp(alpha,0,1)
  end
  if blend(surface,x,y,r,g,b,tint,weight) then painted+=1 end
 end)
 surface.painted+=painted
 return painted,stats
end
function R.stroke(surface,subpaths,style,paint,options)
 options=options or {}
 local plan=options.plan
 local resolved=table.clone(style or {})
 resolved.tolerance=resolved.tolerance or (plan and plan.tolerance) or 0.1
 local outline
 if options.signature then
  outline=select(1,Stroke.cachedOutline(options.signature,subpaths,resolved))
 else
  outline=Stroke.outline(subpaths,resolved)
 end
 if #outline==0 then return 0,nil,outline end
 local merged=table.clone(options)
 merged.rule='nonzero'
 local painted,stats=R.fill(surface,outline,paint,merged)
 return painted,stats,outline
end
function R.clip(contours,regions,options)
 options=options or {}
 if not regions or #regions==0 then return contours end
 if options.signature then
  local current=contours
  for index,region in ipairs(regions) do
   current=select(1,Bool.cached('intersect',options.signature..'/'..index,current,region,options))
   if #current==0 then break end
  end
  return current
 end
 return Bool.clip(contours,regions,options)
end
function R.mask(contours,regions,options)
 return Bool.mask(contours,regions,options or {})
end
local function quantize(value)
 return floor(clamp(value,0,1)*65536+0.5)/65536
end
function R.toRuns(surface,options)
 options=options or {}
 local plan=options.plan
 local limit=floor(options.spanLimit or (plan and plan.spanLimit) or Lod.spanLimit(surface.w,surface.h))
 local width=surface.w
 local height=surface.h
 local data=surface.data
 local key=buffer.create(R.STRIDE)
 local runs={}
 local previous={}
 local horizontal=0
 local vertical=0
 local colorSteps=tonumber(options.colorLevels) and math.max(2,floor(options.colorLevels))-1 or nil
 local alphaSteps=tonumber(options.alphaLevels) and math.max(2,floor(options.alphaLevels))-1 or nil
 local function bucket(value,steps)
  if not steps then return quantize(value)*255 end
  return floor(clamp(value,0,1)*steps+0.5)/steps*255
 end
 local function token(x,y)
  local at=(y*width+x)*R.STRIDE
  local alpha=readf32(data,at+16)
  if alpha<=1/8192 then return nil end
  local channels={
   bucket(readf32(data,at)/alpha,colorSteps),
   bucket(readf32(data,at+4)/alpha,colorSteps),
   bucket(readf32(data,at+8)/alpha,colorSteps),
   bucket(readf32(data,at+12)/alpha,colorSteps),
   bucket(alpha,alphaSteps),
  }
  for index=1,R.CHANNELS do writef32(key,(index-1)*4,channels[index]) end
  return buffer.tostring(key),channels
 end
 for y=0,height-1 do
  local row={}
  local x=0
  while x<width do
   local current,channels=token(x,y)
   if not current then
    x+=1
   else
    local start=x
    x+=1
    while x<width do
     local nextToken=token(x,y)
     if nextToken~=current then break end
     x+=1
    end
    horizontal+=x-start-1
    local identity=start..':'..x..':'..current
    local run=previous[identity]
    if run then
     run.h+=1
     vertical+=1
    else
     run={x=start,y=y,w=x-start,h=1,channels=channels}
     runs[#runs+1]=run
     assert(#runs<=limit,string.format('Faixas vetoriais (%d) acima do teto derivado %d.',#runs,limit))
    end
    row[identity]=run
   end
  end
  previous=row
  if options.yield and y%16==0 then options.yield() end
 end
 return runs,{horizontal=horizontal,vertical=vertical,limit=limit,pixels=width*height}
end
function R.coverageMask(contours,options)
 options=options or {}
 local width=floor(options.width or options.w)
 local height=floor(options.height or options.h)
 local alpha=Scan.alphaBuffer(contours,{matrix=options.matrix,rule=options.rule,levels=options.levels,w=width,h=height,maxEdges=options.maxEdges})
 return function(x,y)
  if x<0 or y<0 or x>=width or y>=height then return 0 end
  return readf32(alpha,(floor(y)*width+floor(x))*4)
 end,alpha
end
function R.describe(plan)
 return Lod.describe(plan)
end
function R.stats()
 local out=Cache.stats()
 out.version=R.VERSION
 out.stages=out.stages or {}
 out.algorithms=R.STAGES
 return out
end
function R.invalidate(stage)
 if stage then return Cache.invalidate(stage) end
 return Cache.clear()
end
return R
