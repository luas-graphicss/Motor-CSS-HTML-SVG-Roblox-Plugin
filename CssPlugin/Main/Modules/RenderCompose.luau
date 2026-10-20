local Tiles=require(script.Parent.RenderTiles)
local Raster=require(script.Parent.RenderRaster)
local Warp=require(script.Parent.RenderTransform)
local C={VERSION=1}
local clamp=math.clamp
local floor=math.floor
local boxKinds={['content-box']=true,['border-box']=true,['fill-box']=true,['stroke-box']=true,['view-box']=true}
C.boxKinds=boxKinds
local blends={normal=true,multiply=true,screen=true,overlay=true,darken=true,lighten=true,['color-dodge']=true,['color-burn']=true,['hard-light']=true,['soft-light']=true,difference=true,exclusion=true,hue=true,saturation=true,color=true,luminosity=true}
local inlineLevel={inline=true,['inline-block']=true,['inline-flex']=true,['inline-grid']=true,['inline-table']=true}
local atomicInline={['inline-block']=true,['inline-flex']=true,['inline-grid']=true,['inline-table']=true}
function C.node(spec)
 spec=spec or {}
 local blend=spec.blend or 'normal'
 assert(blends[blend],'mix-blend-mode desconhecido: '..tostring(blend))
 local box=spec.box or {}
 local transformStyle=spec.transformStyle or 'flat'
 assert(transformStyle=='flat' or transformStyle=='preserve-3d','transform-style aceita flat/preserve-3d.')
 local backface=spec.backface or 'visible'
 assert(backface=='visible' or backface=='hidden','backface-visibility aceita visible/hidden.')
 local transformBox=spec.transformBox or 'border-box'
 assert(boxKinds[transformBox],'transform-box desconhecido: '..tostring(transformBox))
 local perspective=tonumber(spec.perspective)
 assert(perspective==nil or perspective>0,'perspective deve ser positiva.')
 local matrix=Warp.matrix(spec.transform)
 if matrix and Warp.isIdentity(matrix) then matrix=nil end
 return {
  key=spec.key,
  box={x=tonumber(box.x) or 0,y=tonumber(box.y) or 0,w=math.max(0,tonumber(box.w) or 0),h=math.max(0,tonumber(box.h) or 0)},
  paintBounds=spec.paintBounds,
  zIndex=spec.zIndex,
  position=spec.position or 'static',
  display=spec.display or 'block',
  float=spec.float or 'none',
  opacity=clamp(spec.opacity==nil and 1 or spec.opacity,0,1),
  blend=blend,
  isolation=spec.isolation or 'auto',
  filters=spec.filters,
  mask=spec.mask,
  clip=spec.clip,
  radii=spec.radii,
  contain=spec.contain,
  transform=spec.transform,
  matrix=matrix,
  transformOrigin=spec.transformOrigin,
  transformBox=transformBox,
  transformBoxes=spec.transformBoxes,
  transformStyle=transformStyle,
  backface=backface,
  perspective=perspective,
  perspectiveOrigin=spec.perspectiveOrigin,
  pointerEvents=spec.pointerEvents or 'auto',
  willChange=spec.willChange,
  root=spec.root==true,
  ops=spec.ops or {},
  children={},
  parent=nil,
  order=0,
  depth=0,
 }
end
function C.append(parent,child)
 child.parent=parent
 child.depth=(parent.depth or 0)+1
 parent.children[#parent.children+1]=child
 child.order=#parent.children
 return child
end
function C.add(parent,spec) return C.append(parent,C.node(spec)) end
function C.tree(spec)
 local node=C.node(spec)
 node.root=true
 return node
end
function C.zOf(node)
 local z=node.zIndex
 if z==nil or z=='auto' then return 0 end
 return floor(tonumber(z) or 0)
end
function C.explicitZ(node) return node.zIndex~=nil and node.zIndex~='auto' end
function C.positioned(node) return node.position~='static' end
function C.flattens(node)
 if node.opacity<1 then return true end
 if node.blend~='normal' then return true end
 if node.isolation=='isolate' then return true end
 if node.filters and #node.filters>0 then return true end
 if node.mask then return true end
 if node.contain=='paint' then return true end
 return false
end
function C.group(node)
 if node.matrix then return true end
 return C.flattens(node)
end
function C.warps(node) return node.matrix~=nil end
function C.preserves(node)
 return node.transformStyle=='preserve-3d' and not C.flattens(node)
end
function C.referenceBox(node,info)
 local base={x=info.x,y=info.y,w=info.w,h=info.h}
 local kind=node.transformBox or 'border-box'
 local custom=node.transformBoxes and node.transformBoxes[kind]
 if not custom then return base end
 return {x=info.x+(tonumber(custom.x) or 0),y=info.y+(tonumber(custom.y) or 0),w=math.max(0,tonumber(custom.w) or base.w),h=math.max(0,tonumber(custom.h) or base.h)}
end
function C.originOf(node,reference)
 local origin=node.transformOrigin
 local ox=reference.w/2
 local oy=reference.h/2
 local oz=0
 if origin then
  if origin[1]~=nil then ox=tonumber(origin[1]) or ox end
  if origin[2]~=nil then oy=tonumber(origin[2]) or oy end
  if origin[3]~=nil then oz=tonumber(origin[3]) or 0 end
  if origin.x~=nil then ox=tonumber(origin.x) or ox end
  if origin.y~=nil then oy=tonumber(origin.y) or oy end
  if origin.z~=nil then oz=tonumber(origin.z) or 0 end
 end
 return reference.x+ox,reference.y+oy,oz
end
function C.childMatrix(node,info,matrix)
 local m=matrix
 if m and not C.preserves(node) then m=Warp.flatten(m) end
 if node.perspective and node.perspective>0 then
  local reference=info.reference or {x=info.x,y=info.y,w=info.w,h=info.h}
  local px=reference.w/2
  local py=reference.h/2
  local origin=node.perspectiveOrigin
  if origin then
   if origin[1]~=nil then px=tonumber(origin[1]) or px end
   if origin[2]~=nil then py=tonumber(origin[2]) or py end
   if origin.x~=nil then px=tonumber(origin.x) or px end
   if origin.y~=nil then py=tonumber(origin.y) or py end
  end
  local lens=Warp.around(Warp.perspective(node.perspective),reference.x+px,reference.y+py,0)
  m=m and Warp.multiply(m,lens) or lens
 end
 return m
end
function C.stacking(node)
 if node.root then return true end
 if C.group(node) then return true end
 if C.positioned(node) and C.explicitZ(node) then return true end
 if node.position=='fixed' or node.position=='sticky' then return true end
 if node.transform then return true end
 if node.willChange then return true end
 return false
end
function C.atomic(node)
 return C.stacking(node) or C.positioned(node) or node.float~='none' or atomicInline[node.display]==true
end
local function collect(node,buckets)
 for _,child in ipairs(node.children) do
  if C.stacking(child) then
   local z=C.zOf(child)
   local slot=buckets.zero
   if z<0 then slot=buckets.negative elseif z>0 then slot=buckets.positive end
   slot[#slot+1]=child
  elseif C.positioned(child) then
   buckets.zero[#buckets.zero+1]=child
  elseif child.float~='none' then
   buckets.floats[#buckets.floats+1]=child
  elseif atomicInline[child.display] then
   buckets.inline[#buckets.inline+1]=child
  elseif inlineLevel[child.display] then
   buckets.inline[#buckets.inline+1]=child
   collect(child,buckets)
  else
   buckets.block[#buckets.block+1]=child
   collect(child,buckets)
  end
 end
end
local function sortSlot(list)
 for index,node in ipairs(list) do node.slot=index end
 table.sort(list,function(a,b)
  local za=C.zOf(a)
  local zb=C.zOf(b)
  if za~=zb then return za<zb end
  return a.slot<b.slot
 end)
 return list
end
function C.order(root,prepared)
 local out={}
 local map=prepared and prepared.map or nil
 local function depthOf(node)
  local info=map and map[node]
  return info and info.depth or 0
 end
 local function emit(node,isRoot)
  local warped=node.matrix~=nil
  if not isRoot and warped and not C.preserves(node) then
   out[#out+1]={node=node,phase='warp'}
   return
  end
  if not isRoot and not warped and C.group(node) then
   out[#out+1]={node=node,phase='group'}
   return
  end
  out[#out+1]={node=node,phase=isRoot and 'root' or (warped and 'plane' or 'self')}
  local buckets={negative={},block={},floats={},inline={},zero={},positive={}}
  collect(node,buckets)
  sortSlot(buckets.negative)
  sortSlot(buckets.positive)
  if map and C.preserves(node) then
   local scene={}
   for _,child in ipairs(buckets.negative) do scene[#scene+1]=child end
   for _,child in ipairs(buckets.zero) do scene[#scene+1]=child end
   for _,child in ipairs(buckets.positive) do scene[#scene+1]=child end
   Warp.sort(scene,depthOf)
   for _,child in ipairs(buckets.block) do out[#out+1]={node=child,phase='block'} end
   for _,child in ipairs(buckets.floats) do emit(child,false) end
   for _,child in ipairs(buckets.inline) do
    if C.atomic(child) then emit(child,false) else out[#out+1]={node=child,phase='inline'} end
   end
   for _,child in ipairs(scene) do emit(child,false) end
   return
  end
  for _,child in ipairs(buckets.negative) do emit(child,false) end
  for _,child in ipairs(buckets.block) do out[#out+1]={node=child,phase='block'} end
  for _,child in ipairs(buckets.floats) do emit(child,false) end
  for _,child in ipairs(buckets.inline) do
   if C.atomic(child) then emit(child,false) else out[#out+1]={node=child,phase='inline'} end
  end
  for _,child in ipairs(buckets.zero) do emit(child,false) end
  for _,child in ipairs(buckets.positive) do emit(child,false) end
 end
 emit(root,true)
 return out
end
function C.keys(root)
 local out={}
 for _,item in ipairs(C.order(root)) do out[#out+1]=tostring(item.node.key or '?') end
 return out
end
function C.prepare(root,options)
 options=options or {}
 local map={}
 local sequence={}
 local function walk(node,x,y)
  local ax=x+node.box.x
  local ay=y+node.box.y
  local bounds={x=ax,y=ay,w=node.box.w,h=node.box.h}
  if node.paintBounds then
   local extra={x=ax+(tonumber(node.paintBounds.x) or 0),y=ay+(tonumber(node.paintBounds.y) or 0),w=math.max(0,tonumber(node.paintBounds.w) or 0),h=math.max(0,tonumber(node.paintBounds.h) or 0)}
   local left=math.min(bounds.x,extra.x)
   local top=math.min(bounds.y,extra.y)
   local right=math.max(bounds.x+bounds.w,extra.x+extra.w)
   local bottom=math.max(bounds.y+bounds.h,extra.y+extra.h)
   bounds={x=left,y=top,w=right-left,h=bottom-top}
  end
  local info={node=node,x=ax,y=ay,w=node.box.w,h=node.box.h,bounds=bounds,ownBounds=bounds}
  map[node]=info
  sequence[#sequence+1]=node
  local parentInfo=node.parent and map[node.parent] or nil
  local base=parentInfo and parentInfo.childMatrix or nil
  if not parentInfo and options.baseMatrix then base=Warp.matrix(options.baseMatrix) end
  local reference=C.referenceBox(node,info)
  info.reference=reference
  local own=node.matrix
  if own and node==root and options.skipRootTransform then own=nil end
  local matrix=base
  if own then
   local ox,oy,oz=C.originOf(node,reference)
   local placed=Warp.around(own,ox,oy,oz)
   matrix=base and Warp.multiply(base,placed) or placed
  end
  info.matrix=matrix
  info.childMatrix=C.childMatrix(node,info,matrix)
  local frame={x=ax,y=ay,w=node.box.w,h=node.box.h}
  info.depth=matrix and Warp.depth(matrix,frame) or (parentInfo and parentInfo.depth or 0)
  info.backFacing=matrix~=nil and Warp.backFacing(matrix,frame) or false
  if matrix then
   local projected=Warp.boundsOf(matrix,bounds)
   info.bounds=projected or bounds
   info.projected=projected~=nil
  end
  if not options.ownOnly then
   for _,child in ipairs(node.children) do walk(child,ax,ay) end
  end
 end
 walk(root,tonumber(options.x) or 0,tonumber(options.y) or 0)
 for _,node in ipairs(sequence) do
  local info=map[node]
  local rect=nil
  local masks=nil
  local outerRect=nil
  local outerMasks=nil
  local ownRect=nil
  local ownMasks=nil
  local current=node
  while current and map[current] do
   local ci=map[current]
   local isRoot=current==root
   local outer=current~=node
   if current.clip and not (isRoot and options.ignoreRootClip) then
    local c={x=ci.x+(tonumber(current.clip.x) or 0),y=ci.y+(tonumber(current.clip.y) or 0),w=tonumber(current.clip.w) or ci.w,h=tonumber(current.clip.h) or ci.h}
    rect=rect and Tiles.intersect(rect,c) or c
    if outer then outerRect=outerRect and Tiles.intersect(outerRect,c) or c else ownRect=ownRect and Tiles.intersect(ownRect,c) or c end
    local radii=current.clip.radii
    if radii==nil and current.clip.round then radii=current.radii end
    local list=Raster.radii(radii)
    if list then
     local entry={box=c,radii=list}
     masks=masks or {}
     masks[#masks+1]=entry
     if outer then
      outerMasks=outerMasks or {}
      outerMasks[#outerMasks+1]=entry
     else
      ownMasks=ownMasks or {}
      ownMasks[#ownMasks+1]=entry
     end
    end
   end
   if current.mask and not (isRoot and options.ignoreRootMask) then
    local entry={fn=current.mask,x=ci.x,y=ci.y}
    masks=masks or {}
    masks[#masks+1]=entry
    if outer then
     outerMasks=outerMasks or {}
     outerMasks[#outerMasks+1]=entry
    else
     ownMasks=ownMasks or {}
     ownMasks[#ownMasks+1]=entry
    end
   end
   current=current.parent
  end
  info.clip=rect
  info.masks=masks
  info.ancestorClip=outerRect
  info.ancestorMasks=outerMasks
  info.ownClip=ownRect
  info.ownMasks=ownMasks
 end
 for index=#sequence,2,-1 do
  local node=sequence[index]
  local info=map[node]
  local pi=node.parent and map[node.parent]
  if pi then
   local b=info.bounds
   local pb=pi.bounds
   local left=math.min(pb.x,b.x)
   local top=math.min(pb.y,b.y)
   local right=math.max(pb.x+pb.w,b.x+b.w)
   local bottom=math.max(pb.y+pb.h,b.y+b.h)
   pi.bounds={x=left,y=top,w=right-left,h=bottom-top}
  end
 end
 return {map=map,sequence=sequence,root=root}
end
local function maskFactor(info)
 local masks=info.masks
 if not masks then return nil end
 return function(x,y)
  local value=1
  for _,entry in ipairs(masks) do
   if entry.fn then
    value*=clamp(entry.fn(x-entry.x,y-entry.y),0,1)
   else
    value*=Raster.roundRectCoverage(entry.box,entry.radii,floor(x),floor(y))
   end
   if value<=0 then return 0 end
  end
  return value
 end
end
C.maskFactor=maskFactor
function C.execute(node,info,target,origin,options)
 local painted=0
 local clip=info.clip
 if options.clip then clip=clip and Tiles.intersect(clip,options.clip) or options.clip end
 local mask=maskFactor(info)
 local localClip=clip and {x=clip.x-origin.x,y=clip.y-origin.y,w=clip.w,h=clip.h} or nil
 local shiftedMask=mask and function(x,y) return mask(x+origin.x,y+origin.y) end or nil
 for _,op in ipairs(node.ops) do
  local dx=info.x+(tonumber(op.x) or 0)
  local dy=info.y+(tonumber(op.y) or 0)
  local paint=Raster.shader(op,dx,dy)
  local shifted=function(x,y) return paint(x+origin.x,y+origin.y) end
  local opts={clip=localClip,mask=shiftedMask,mode=op.mode or 'normal',opacity=op.opacity,rule=op.rule}
  local area={x=dx-origin.x,y=dy-origin.y,w=tonumber(op.w) or info.w,h=tonumber(op.h) or info.h}
  if op.kind=='path' or op.kind=='polygon' then
   local source=op.subpaths or {op.points}
   local subpaths={}
   for slot,points in ipairs(source) do
    local list={}
    for index,entry in ipairs(points) do
     list[index]={x=(tonumber(entry.x or entry[1]) or 0)+dx-origin.x,y=(tonumber(entry.y or entry[2]) or 0)+dy-origin.y}
    end
    subpaths[slot]=list
   end
   painted+=Raster.path(target,subpaths,shifted,opts)
  elseif op.kind=='ring' or op.kind=='border' then
   painted+=Raster.ring(target,area,op.radii or node.radii,tonumber(op.width) or 1,shifted,opts)
  elseif op.kind=='roundRect' or op.radii~=nil or node.radii~=nil then
   painted+=Raster.roundRect(target,area,op.radii or node.radii,shifted,opts)
  else
   painted+=Raster.rect(target,area,shifted,opts)
  end
 end
 return painted
end
function C.applyFilters(surface,filters)
 local current=surface
 for _,f in ipairs(filters) do
  if f.name=='blur' then
   Tiles.blur(current,nil,tonumber(f.value) or 0)
  elseif f.name=='drop-shadow' then
   local shadow=Tiles.new(current.w,current.h,{budget=current.budget,tile=current.tile,capability=current.plan.capability,label='Sombra de grupo'})
   local color=f.color or Color3.new()
   local alpha=f.alpha==nil and 1 or clamp(f.alpha,0,1)
   for y=0,current.h-1 do
    for x=0,current.w-1 do
     local _,a=Tiles.get(current,x,y)
     if a>0 then Tiles.set(shadow,x,y,color,a*alpha) end
    end
   end
   Tiles.blur(shadow,nil,tonumber(f.blur) or 0)
   local layer=Tiles.new(current.w,current.h,{budget=current.budget,tile=current.tile,capability=current.plan.capability,label='Camada de sombra'})
   Tiles.composite(layer,shadow,tonumber(f.x) or 0,tonumber(f.y) or 0,{})
   Tiles.composite(layer,current,0,0,{})
   Tiles.release(shadow)
   Tiles.release(current)
   current=layer
  else
   Tiles.colorize(current,nil,{f})
  end
 end
 return current
end
function C.renderTransformed(node,info,target,origin,options,ownOnly)
 local matrix=info.matrix
 if not matrix then return C.renderGroup(node,info,target,origin,options) end
 local view={x=origin.x,y=origin.y,w=target.w,h=target.h}
 local prepared=C.prepare(node,{x=info.x-node.box.x,y=info.y-node.box.y,skipRootTransform=true,ownOnly=ownOnly==true})
 local inner=prepared.map[node]
 local sourceBounds=inner and inner.bounds or info.ownBounds
 local destBounds=Warp.boundsOf(matrix,sourceBounds)
 if not destBounds then return 0 end
 local area=Tiles.intersect(destBounds,view)
 if options.clip then area=Tiles.intersect(area,options.clip) end
 if info.ancestorClip then area=Tiles.intersect(area,info.ancestorClip) end
 if area.w<=0 or area.h<=0 then return 0 end
 local needed=Warp.sourceBounds(matrix,area)
 local source=needed and Tiles.intersect(sourceBounds,needed) or sourceBounds
 if source.w<=0 or source.h<=0 then return 0 end
 source={x=floor(source.x)-1,y=floor(source.y)-1,w=math.ceil(source.w)+2,h=math.ceil(source.h)+2}
 local surface=Tiles.new(source.w,source.h,{budget=target.budget,tile=math.min(target.tile,math.max(8,math.max(source.w,source.h))),capability=target.plan.capability,label='Grupo transformado'})
 C.paint(prepared,surface,{origin={x=source.x,y=source.y},clip=source,samples=options.samples})
 if node.filters and #node.filters>0 then surface=C.applyFilters(surface,node.filters) end
 local mask=maskFactor({masks=info.ancestorMasks})
 local painted=Warp.composite(target,surface,matrix,{sourceX=source.x,sourceY=source.y,destX=origin.x,destY=origin.y,opacity=node.opacity,mode=node.blend,samples=options.samples,clip={x=area.x-origin.x,y=area.y-origin.y,w=area.w,h=area.h},mask=mask and function(x,y) return mask(x+origin.x,y+origin.y) end or nil})
 Tiles.release(surface)
 return painted
end
function C.renderGroup(node,info,target,origin,options)
 local view={x=origin.x,y=origin.y,w=target.w,h=target.h}
 local area=Tiles.intersect(info.bounds,view)
 if options.clip then area=Tiles.intersect(area,options.clip) end
 if info.clip then area=Tiles.intersect(area,info.clip) end
 if area.w<=0 or area.h<=0 then return 0 end
 area={x=floor(area.x),y=floor(area.y),w=math.ceil(area.w),h=math.ceil(area.h)}
 local surface=Tiles.new(area.w,area.h,{budget=target.budget,tile=math.min(target.tile,math.max(8,math.max(area.w,area.h))),capability=target.plan.capability,label='Grupo de composicao'})
 local prepared=C.prepare(node,{x=info.x-node.box.x,y=info.y-node.box.y,ignoreRootClip=true,ignoreRootMask=true})
 C.paint(prepared,surface,{origin={x=area.x,y=area.y},clip=area})
 if node.filters and #node.filters>0 then surface=C.applyFilters(surface,node.filters) end
 local mask=maskFactor(info)
 local clip=options.clip and {x=options.clip.x-origin.x,y=options.clip.y-origin.y,w=options.clip.w,h=options.clip.h} or nil
 if info.clip then
  local bounded={x=info.clip.x-origin.x,y=info.clip.y-origin.y,w=info.clip.w,h=info.clip.h}
  clip=clip and Tiles.intersect(clip,bounded) or bounded
 end
 local painted=Tiles.composite(target,surface,area.x-origin.x,area.y-origin.y,{opacity=node.opacity,mode=node.blend,clip=clip,mask=mask and function(x,y) return mask(x+origin.x,y+origin.y) end or nil})
 Tiles.release(surface)
 return painted
end
function C.paint(prepared,target,options)
 options=options or {}
 local origin=options.origin or {x=0,y=0}
 local map=prepared.map
 local rootInfo=map[prepared.root]
 if rootInfo and rootInfo.matrix and options.warpRoot~=false then
  return {items=0,groups=1,painted=C.renderTransformed(prepared.root,rootInfo,target,origin,options,false),skipped=0}
 end
 local items=options.order or C.order(prepared.root,prepared)
 local view={x=origin.x,y=origin.y,w=target.w,h=target.h}
 local stats={items=0,groups=0,painted=0,skipped=0}
 for _,item in ipairs(items) do
  local node=item.node
  local info=map[node]
  local drawable=info~=nil and (item.phase=='group' or item.phase=='warp' or #node.ops>0)
  if not drawable then
   stats.skipped+=1
  else
   local bounds=info.bounds
   local area=nil
   if bounds.w>0 and bounds.h>0 then
    area=Tiles.intersect(bounds,view)
    if options.clip then area=Tiles.intersect(area,options.clip) end
   end
   if area and (area.w<=0 or area.h<=0) then
    stats.skipped+=1
   elseif node.backface=='hidden' and info.backFacing then
    stats.skipped+=1
   elseif item.phase=='warp' or item.phase=='plane' then
    stats.groups+=1
    stats.painted+=C.renderTransformed(node,info,target,origin,options,item.phase=='plane')
   elseif item.phase=='group' then
    stats.groups+=1
    stats.painted+=C.renderGroup(node,info,target,origin,options)
   else
    stats.items+=1
    stats.painted+=C.execute(node,info,target,origin,options)
   end
  end
 end
 return stats
end
local function insideRect(rect,x,y)
 if not rect then return true end
 return x>=rect.x and y>=rect.y and x<=rect.x+rect.w and y<=rect.y+rect.h
end
C.insideRect=insideRect
function C.localPoint(node,info,x,y)
 if not info.matrix then
  if not insideRect({x=info.x,y=info.y,w=info.w,h=info.h},x,y) then return false end
  return true,x,y
 end
 local hit,lx,ly=Warp.hit(info.matrix,{x=info.x,y=info.y,w=info.w,h=info.h},x,y)
 if not hit then return false end
 return true,lx,ly
end
function C.hitTest(prepared,x,y,options)
 options=options or {}
 local map=prepared.map
 local items=options.order or C.order(prepared.root,prepared)
 for index=#items,1,-1 do
  local item=items[index]
  local node=item.node
  local info=map[node]
  local testable=info~=nil and node.pointerEvents~='none' and not (node.backface=='hidden' and info.backFacing)
  if testable then
   local hit,lx,ly=C.localPoint(node,info,x,y)
   if hit then
    local clip=info.clip
    local masks=info.masks
    if info.matrix then
     clip=info.ownClip
     masks=info.ownMasks
    end
    local blocked=not insideRect(clip,lx,ly)
    if not blocked and info.matrix and not insideRect(info.ancestorClip,x,y) then blocked=true end
    if not blocked and info.matrix then
     local outer=maskFactor({masks=info.ancestorMasks})
     if outer and outer(x,y)<=0 then blocked=true end
    end
    if not blocked then
     local own=maskFactor({masks=masks})
     if own and own(lx,ly)<=0 then blocked=true end
    end
    if not blocked then return {node=node,key=node.key,phase=item.phase,x=lx,y=ly,depth=info.depth} end
   end
  end
 end
 return nil
end
return C
