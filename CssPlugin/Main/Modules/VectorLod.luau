local Cost=require(script.Parent.CostModel)
local L={VERSION='vector-lod-1',ALGORITHM='physical-scale-1',MIN=4,MAX=4096,BYTES_PER_PIXEL=20}
local qualities={
 fast={tolerance=0.4,levels=32,supersample=1},
 balanced={tolerance=0.18,levels=128,supersample=1},
 exact={tolerance=0.06,levels=256,supersample=1},
 extreme={tolerance=0.02,levels=1024,supersample=2},
}
function L.quality(name)
 local quality=qualities[name or 'exact']
 assert(quality,'Qualidade de rasterizacao desconhecida: '..tostring(name))
 return quality
end
function L.step(size)
 if size<=64 then return 1 end
 if size<=256 then return 2 end
 if size<=1024 then return 4 end
 return 8
end
function L.snap(value,step)
 local snapped=math.ceil(math.max(value,L.MIN)/step)*step
 return math.clamp(math.floor(snapped),L.MIN,L.MAX)
end
function L.pixelBudget(profile)
 local limits=Cost.limits(profile)
 return math.clamp(limits.pixels or 4194304,65536,L.MAX*L.MAX)
end
function L.layerLimit(profile)
 local limits=Cost.limits(profile)
 return math.max(256,limits.layers or 256)
end
function L.edgeLimit(profile)
 local limits=Cost.limits(profile)
 return math.clamp((limits.bands or 8000)*8,24000,1048576)
end
function L.spanLimit(width,height,maxSpans)
 local derived=math.floor(width*height*0.5)
 return math.clamp(derived,8192,math.floor(tonumber(maxSpans) or 262144))
end
function L.pixelScale(target,options)
 options=options or {}
 local scale=math.abs(tonumber(options.pixelScale) or 1)
 local node=target
 local guard=0
 while node and guard<64 do
  guard+=1
  if node:IsA('GuiObject') then
   local uiScale=node:FindFirstChildOfClass('UIScale')
   if uiScale then scale*=math.abs(uiScale.Scale) end
  end
  local ratio=node:GetAttribute('CssPixelRatio')
  if type(ratio)=='number' and ratio>0 then scale*=ratio end
  node=node.Parent
 end
 if scale~=scale or scale<=0 then scale=1 end
 return math.clamp(scale,1/64,64)
end
function L.measure(target,options)
 options=options or {}
 local width=tonumber(options.width)
 local height=tonumber(options.height)
 if (not width or not height) and target then
  local size=target.AbsoluteSize
  if size and size.X>0 and size.Y>0 then
   width=width or size.X
   height=height or size.Y
  elseif target.Size and target.Size.X.Scale==0 and target.Size.Y.Scale==0 then
   width=width or target.Size.X.Offset
   height=height or target.Size.Y.Offset
  end
 end
 local scale=L.pixelScale(target,options)
 if width and height and width>0 and height>0 then
  return {width=width,height=height,pixelScale=scale,measured=true}
 end
 return {width=nil,height=nil,pixelScale=scale,measured=false}
end
function L.plan(spec)
 spec=spec or {}
 local viewBox=spec.viewBox or {0,0,1,1}
 local viewWidth=tonumber(viewBox[3]) or 1
 local viewHeight=tonumber(viewBox[4]) or 1
 assert(viewWidth>0 and viewHeight>0,'viewBox exige largura e altura positivas.')
 local quality=L.quality(spec.quality)
 local pixelScale=math.max(tonumber(spec.pixelScale) or 1,1/64)
 local aspect=viewWidth/viewHeight
 local boxWidth=tonumber(spec.width)
 local boxHeight=tonumber(spec.height)
 local fitted=false
 if not boxWidth or not boxHeight or boxWidth<=0 or boxHeight<=0 then
  local base=math.max(tonumber(spec.resolution) or 64,L.MIN)
  boxWidth=aspect>=1 and base or base*aspect
  boxHeight=aspect>=1 and base/aspect or base
  pixelScale=1
 else
  local preserve=spec.preserveAspectRatio
  if preserve~='none' then
   local slice=type(preserve)=='string' and preserve:find('slice',1,true)~=nil
   if (boxWidth/boxHeight>aspect)==not slice then boxWidth=boxHeight*aspect else boxHeight=boxWidth/aspect end
   fitted=true
  end
 end
 local deviceWidth=boxWidth*pixelScale*quality.supersample
 local deviceHeight=boxHeight*pixelScale*quality.supersample
 local requested=tonumber(spec.resolution)
 if requested and requested>0 and spec.width and spec.height then
  local longest=math.max(deviceWidth,deviceHeight)
  if longest>0 then
   local factor=requested/longest
   deviceWidth*=factor
   deviceHeight*=factor
  end
 end
 local step=L.step(math.max(deviceWidth,deviceHeight))
 local width=L.snap(deviceWidth,step)
 local height=L.snap(deviceHeight,step)
 local maxPixels=math.min(math.floor(tonumber(spec.maxPixels) or 4194304),L.pixelBudget(spec.profile))
 local pixels=width*height
 local clamped=false
 if pixels>maxPixels then
  local factor=math.sqrt(maxPixels/pixels)
  width=math.clamp(math.floor(width*factor),L.MIN,L.MAX)
  height=math.clamp(math.floor(height*factor),L.MIN,L.MAX)
  clamped=true
 end
 local scaleX=width/viewWidth
 local scaleY=height/viewHeight
 local device=math.max(scaleX,scaleY,1e-6)
 local tolerance=math.max(quality.tolerance/device,1e-7)
 local bytes=width*height*L.BYTES_PER_PIXEL
 local band=math.clamp(math.floor(262144/math.max(1,width*L.BYTES_PER_PIXEL)),8,height)
 return {
  width=width,
  height=height,
  scaleX=scaleX,
  scaleY=scaleY,
  pixelScale=pixelScale,
  devicePixels=pixels,
  tolerance=tolerance,
  levels=quality.levels,
  quality=spec.quality or 'exact',
  supersample=quality.supersample,
  lod=math.max(0,math.ceil(math.log(math.max(width,height,2))/math.log(2))),
  step=step,
  band=band,
  bytes=bytes,
  clamped=clamped,
  fitted=fitted,
  aspect=aspect,
  viewBox={tonumber(viewBox[1]) or 0,tonumber(viewBox[2]) or 0,viewWidth,viewHeight},
  spanLimit=L.spanLimit(width,height,spec.maxSpans),
  layerLimit=L.layerLimit(spec.profile),
  edgeLimit=L.edgeLimit(spec.profile),
  profile=Cost.profile(spec.profile).label,
 }
end
function L.forTarget(target,spec)
 spec=spec or {}
 local measured=L.measure(target,spec)
 local merged=table.clone(spec)
 merged.width=measured.width
 merged.height=measured.height
 merged.pixelScale=measured.pixelScale
 local plan=L.plan(merged)
 plan.measured=measured.measured
 return plan
end
function L.signature(plan)
 return table.concat({L.ALGORITHM,plan.width,plan.height,plan.lod,plan.step,plan.levels,plan.quality,string.format('%.6g',plan.tolerance),plan.profile},':')
end
function L.describe(plan)
 return string.format('LOD %s %dx%d passo %d nivel %d tol %.5g escala %.4g faixas<=%d camadas<=%d bytes %d%s',plan.quality,plan.width,plan.height,plan.step,plan.lod,plan.tolerance,plan.pixelScale,plan.spanLimit,plan.layerLimit,plan.bytes,plan.clamped and ' (limitado por memoria)' or '')
end
function L.fits(plan,bytes)
 return (tonumber(bytes) or plan.bytes)<=plan.width*plan.height*L.BYTES_PER_PIXEL*4
end
return L
