local U=require(script.Parent.Util)
local Cost=require(script.Parent.CostModel)
local Style=require(script.Parent.SvgStyle)
local Svg=require(script.Parent.Svg)
local Raster=require(script.Parent.SvgRaster)
local Codec=require(script.Parent.SvgRasterRuntime)
local Optimizer=require(script.Parent.RenderOptimizer)
local Smil=require(script.Parent.RuntimeManifest).optional('SvgSmil')
local B={VERSION=1}
function B.render(doc,objects,styles,boxes,sequence,parents,state,cache,width,height,work,stateNeeds,onRender)
 if not doc.svgSources or not next(doc.svgSources)then return end
 local context,needs=Style.context(doc,styles,state,width,height,boxes,work)
 local status={animation={active=false,next=nil,keys={}}}
 for key,flags in pairs(needs)do
  if styles[key]then stateNeeds[key]=stateNeeds[key]or {};for flag in pairs(flags)do stateNeeds[key][flag]=true end
  else
   local root=key:match('^(.-):svg:%d+$')
   if root and doc.svgSources[root]then status.needs=status.needs or {};status.needs[root]=status.needs[root]or {};status.needs[root][key]=flags end
  end
 end
 local nodes={};for _,n in ipairs(sequence)do nodes[n.key]=n end
 local primitives,icons=0,0;local resolvedSources={};local definitionsChanged=false
 for key,source in pairs(doc.svgSources)do
  local object,box,node=objects[key],boxes[key],nodes[key]
  if object and box and node then
   icons+=1;Cost.cap('svgs',icons,'SVGs por interface')
   local entry=cache[key]
   local plan=Smil.plan(source);local animating=false
   context.animated=nil
   if plan then
    entry.svg=entry.svg or {events={}}
    local sampled,active,nextTime=Smil.sample(plan,entry.svg,work and work.svgNow or 0,work and work.reducedMotion==true)
    if sampled then context.animated=function(nodeKey,st,attrs)return Smil.values(plan,sampled[nodeKey],st,attrs)end end
    if active then status.animation.active=true;animating=true end
    if nextTime and(status.animation.next==nil or nextTime<status.animation.next)then status.animation.next=nextTime end
    if active or nextTime then status.animation.keys[#status.animation.keys+1]=key end
    if plan.events then status.events=status.events or {};status.events[key]=true end
   end
   local color=U.color(styles[key].color);local resolved=Style.resolve(context.roots[key],color,context)
   resolvedSources[key]=resolved;entry.svgResolved=resolved
   local options=U.copy(doc.svgOptions);options.width=box.w;options.height=box.h
   if animating then options.cache=false end
   options.yield=work and work.checkpoint and function()work.checkpoint(48)end or nil
   local scale=1
   if not object.Parent then
    local ancestor=parents[key]
    while ancestor do local o=objects[ancestor.key];local s=o and o:FindFirstChild('__CssScale');if s and s:IsA('UIScale')then scale*=math.abs(s.Scale)end;ancestor=parents[ancestor.key]end
   end
   options.pixelScale=scale
   local vb=U.numbers(resolved.attrs.viewbox or('0 0 '..(resolved.attrs.width or 24)..' '..(resolved.attrs.height or 24)))
   assert(#vb==4 and vb[3]>0 and vb[4]>0,'viewBox SVG inválido.');entry.svgViewBox=vb
   local resolution,budget=Raster.plan(resolved,object,options,vb)
   local signature=Style.signature(resolved)..':'..resolution..':'..budget..':'..tostring(color)..':'..tostring(options.images)..':'..tostring(options.alphaLevels or 8)
   local view=object:FindFirstChild('__Svg')
   if not view or entry.svgSignature~=signature then
    Svg.render(resolved,object,color,options)
    entry.svgSignature=signature;entry.svgRenders=(entry.svgRenders or 0)+1;definitionsChanged=true
    Optimizer.invalidate(object);if onRender then onRender(node,object,styles[key],box,entry)end
    view=object:FindFirstChild('__Svg')
   end
   if view then Codec.paint(view,object,color,1);primitives+=view:GetAttribute('SvgPrimitives')or 0 end
   Cost.cap('bands',primitives,'Faixas SVG')
  end
 end
 if definitionsChanged then
  require(script.Parent.VisualEffectsAssets).register(doc,resolvedSources)
  for source in pairs(doc.effectAssets or {})do if source:sub(1,1)=='#'then doc.effectAssets[source]=nil;if doc.effectAssetMetadata then doc.effectAssetMetadata[source]=nil end end end
 end
 return status
end
function B.setClass(doc,key,id,className)
 assert(type(className)=='string'and #className<=1000,'Classe SVG inválida.')
 local source=assert(doc.svgSources and doc.svgSources[key],'Elemento não é um SVG editável.');local found
 local function walk(n)if n.attrs.id==id then found=n;return end;for _,child in ipairs(n.children)do if not found then walk(child)end end end
 walk(source);assert(found,'ID vetorial não encontrado: '..tostring(id));found.attrs.class=className
end
return B
