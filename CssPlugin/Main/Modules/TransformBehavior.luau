local Transform=require(script.Parent.Transform)
local Warp=require(script.Parent.RenderTransform)
local Compose=require(script.Parent.RenderCompose)
local B={VERSION=1}
local abs=math.abs
local sqrt=math.sqrt
local max=math.max
local styleKinds={flat=true,['preserve-3d']=true}
local faceKinds={visible=true,hidden=true}
local sides={'top','right','bottom','left'}
B.boxKinds=Compose.boxKinds
B.styleKinds=styleKinds
B.faceKinds=faceKinds
B.context=Transform.context
local function px(value,fallback)
 fallback=fallback or 0
 if type(value)=='number' then return value end
 if type(value)~='string' then return fallback end
 local text=value:match('^%s*(.-)%s*$')
 local direct=tonumber(text)
 if direct then return direct end
 local unit=text:match('^([+%-]?%d*%.?%d+)px$')
 local parsed=unit and tonumber(unit) or nil
 if parsed then return parsed end
 return fallback
end
B.px=px
local function borderWidth(style,side)
 local kind=style['border-'..side..'-style'] or style['border-style']
 if kind=='none' or kind=='hidden' then return 0 end
 return px(style['border-'..side..'-width'] or style['border-width'],0)
end
function B.insets(style)
 style=style or {}
 local out={}
 for index,side in ipairs(sides) do out[index]=borderWidth(style,side)+px(style['padding-'..side],0) end
 return out
end
function B.style(style)
 style=style or {}
 local kind=style['transform-style'] or 'flat'
 assert(styleKinds[kind],'transform-style aceita flat/preserve-3d.')
 local face=style['backface-visibility'] or 'visible'
 assert(faceKinds[face],'backface-visibility aceita visible/hidden.')
 local box=style['transform-box'] or 'border-box'
 assert(Compose.boxKinds[box],'transform-box desconhecido: '..tostring(box))
 return {transform=style.transform or 'none',origin=style['transform-origin'] or '50% 50%',box=box,transformStyle=kind,backface=face,perspective=style.perspective or 'none',perspectiveOrigin=style['perspective-origin'] or '50% 50%'}
end
function B.boxes(style,box,extra)
 style=style or {}
 box=box or {}
 local w=max(0,tonumber(box.w) or 0)
 local h=max(0,tonumber(box.h) or 0)
 local inset=B.insets(style)
 local out={}
 out['border-box']={x=0,y=0,w=w,h=h}
 out['content-box']={x=inset[4],y=inset[1],w=max(0,w-inset[2]-inset[4]),h=max(0,h-inset[1]-inset[3])}
 local fill=extra and extra.fill or out['content-box']
 out['fill-box']={x=fill.x,y=fill.y,w=max(0,fill.w),h=max(0,fill.h)}
 local width=tonumber(extra and extra.strokeWidth) or px(style['stroke-width'],0)
 local stroke=extra and extra.stroke or {x=out['fill-box'].x-width/2,y=out['fill-box'].y-width/2,w=out['fill-box'].w+width,h=out['fill-box'].h+width}
 out['stroke-box']={x=stroke.x,y=stroke.y,w=max(0,stroke.w),h=max(0,stroke.h)}
 local view=extra and extra.view or out['border-box']
 out['view-box']={x=view.x,y=view.y,w=max(0,view.w),h=max(0,view.h)}
 return out
end
function B.reference(style,box,extra,kind)
 kind=kind or (style and style['transform-box']) or 'border-box'
 assert(Compose.boxKinds[kind],'transform-box desconhecido: '..tostring(kind))
 if kind=='border-box' then return {x=0,y=0,w=max(0,tonumber(box and box.w) or 0),h=max(0,tonumber(box and box.h) or 0)} end
 return B.boxes(style,box,extra)[kind]
end
function B.parse(value,context)
 if type(value)=='table' then
  if type(value.matrix)=='table' then return value end
  local direct=Warp.matrix(value)
  assert(direct,'Valor de transform invalido.')
  return {operations={{kind='matrix',values=direct}},matrix=direct,scale=1,rotation=0,simple=false}
 end
 return Transform.parse(value or 'none',context)
end
local function affine(m)
 return m[3]==0 and m[7]==0 and m[9]==0 and m[10]==0 and m[11]==1 and m[12]==0 and m[13]==0 and m[14]==0 and m[15]==0 and m[16]==1
end
local function similarity(m)
 if not affine(m) then return false end
 local ax,ay,bx,by=m[1],m[5],m[2],m[6]
 if abs(ax*bx+ay*by)>1e-6 then return false end
 local sx=sqrt(ax*ax+ay*ay)
 local sy=sqrt(bx*bx+by*by)
 if abs(sx-sy)>1e-6 then return false end
 return ax*by-ay*bx>=0
end
B.affine=affine
B.similarity=similarity
local function lens(distance,ox,oy)
 local value=tonumber(distance)
 if not value or value<=0 then return nil end
 return Warp.around(Warp.perspective(value),ox or 0,oy or 0,0)
end
B.lens=lens
function B.classify(spec,parsed,parent)
 local reasons={}
 local seen={}
 local function note(reason)
  if not seen[reason] then seen[reason]=true;reasons[#reasons+1]=reason end
 end
 if spec.transformStyle=='preserve-3d' then note('preserve-3d') end
 if spec.perspective~='none' then note('perspective') end
 if parent and parent.distance then note('perspective herdada') end
 local matrix=parsed.matrix
 if not affine(matrix) then note('matriz 3D') elseif not similarity(matrix) then note('matriz afim nao similar') end
 for _,op in ipairs(parsed.operations or {}) do
  local kind=op.kind
  local values=op.values or {}
  if kind=='skew' then note('skew')
  elseif kind=='rotatex' or kind=='rotatey' then note('rotacao 3D')
  elseif kind=='perspective' then note('perspective()')
  elseif kind=='scale' then
   if values[1]~=values[2] then note('escala nao uniforme') end
   if values[3]~=nil and values[3]~=1 then note('escala em Z') end
   if (values[1] or 1)<0 or (values[2] or 1)<0 then note('escala negativa') end
  elseif kind=='translate' then
   if (values[3] or 0)~=0 then note('translateZ') end
  elseif kind=='matrix' then
   if not similarity(values) then note('matrix()') end
  end
 end
 local route='none'
 if #reasons>0 then route='raster' elseif not Warp.isIdentity(matrix) then route='native' end
 return {route=route,reasons=reasons,raster=#reasons>0}
end
function B.plan(style,box,vw,vh,options)
 options=options or {}
 style=style or {}
 box=box or {}
 local spec=B.style(style)
 local context=options.context or Transform.context(style,box,vw,vh)
 local reference=B.reference(style,box,options.boxes,spec.box)
 local declared=options.value~=nil and options.value or spec.transform
 local parsed=B.parse(declared,context)
 local originContext=context
 if reference.w~=context.width or reference.h~=context.height then originContext=Transform.context(style,{w=reference.w,h=reference.h},vw or context.vw,vh or context.vh) end
 local ox,oy,oz=Transform.origin(spec.origin,originContext)
 local origin={x=reference.x+ox,y=reference.y+oy,z=oz}
 local own=Warp.around(parsed.matrix,origin.x,origin.y,origin.z)
 local parent=options.parent
 local inherited=nil
 if parent and parent.distance then
  inherited=lens(parent.distance,(tonumber(parent.ox) or 0)-(tonumber(parent.x) or 0),(tonumber(parent.oy) or 0)-(tonumber(parent.y) or 0))
 end
 local matrix=inherited and Warp.multiply(inherited,own) or own
 local frame={x=0,y=0,w=max(0,tonumber(box.w) or 0),h=max(0,tonumber(box.h) or 0)}
 local quad=Warp.quad(matrix,frame)
 local child=matrix
 if spec.transformStyle~='preserve-3d' then child=Warp.flatten(child) end
 local perspective=nil
 if spec.perspective~='none' then
  local declaredLens=Transform.perspective(style,box,{x=tonumber(box.x) or 0,y=tonumber(box.y) or 0},vw or context.vw,vh or context.vh)
  if declaredLens then
   perspective={distance=declaredLens.distance,x=declaredLens.ox,y=declaredLens.oy}
   local childLens=lens(declaredLens.distance,declaredLens.ox,declaredLens.oy)
   if childLens then child=Warp.multiply(child,childLens) end
  end
 end
 local classification=B.classify(spec,parsed,parent)
 local backFacing=Warp.backFacing(matrix,frame)
 local plan={spec=spec,parsed=parsed,context=context,reference=reference,origin=origin,matrix=matrix,own=own,inherited=inherited,childMatrix=child,perspective=perspective,depth=quad.valid and quad.depth or 0,bounds=quad.valid and quad.bounds or nil,backFacing=backFacing,hidden=not quad.valid,route=classification.route,reasons=classification.reasons,raster=classification.raster,identity=Warp.isIdentity(matrix)}
 plan.visible=not plan.hidden and not (spec.backface=='hidden' and backFacing)
 if options.projection~=false then plan.projection=Transform.project(parsed,context,spec.origin,parent) end
 return plan
end
function B.attributes(plan,handled)
 local approximate=plan.raster==true
 local backFacing=plan.backFacing==true
 if plan.projection then
  if plan.projection.approximate==true then approximate=true end
  if plan.projection.backFacing==true then backFacing=true end
 end
 if handled==true then approximate=false end
 return {CssTransformApproximate=approximate,CssTransformBackFacing=backFacing,CssTransformRaster=handled==true,CssTransformRoute=plan.route,CssTransformReason=table.concat(plan.reasons,', ')}
end
function B.hit(plan,box,x,y)
 if plan==nil then return false end
 if plan.spec.backface=='hidden' and plan.backFacing then return false end
 local frame={x=0,y=0,w=max(0,tonumber(box and box.w) or 0),h=max(0,tonumber(box and box.h) or 0)}
 if plan.matrix==nil or plan.identity then
  if x<frame.x or y<frame.y or x>frame.w or y>frame.h then return false end
  return true,x,y
 end
 return Warp.hit(plan.matrix,frame,x,y)
end
function B.spec(entry,options)
 options=options or {}
 assert(type(entry)=='table','Entrada de cena invalida.')
 assert(entry.key~=nil,'Entrada de cena exige key.')
 local style=entry.style or {}
 local box=entry.box or {}
 local vw=options.width
 local vh=options.height
 local spec=B.style(style)
 local boxes=B.boxes(style,box,entry.boxes)
 local reference=boxes[spec.box]
 local context=Transform.context(style,box,vw,vh)
 local declared=entry.value~=nil and entry.value or spec.transform
 local parsed=B.parse(declared,context)
 local hasTransform=declared~=nil and declared~='none'
 local originContext=context
 if reference.w~=context.width or reference.h~=context.height then originContext=Transform.context(style,{w=reference.w,h=reference.h},vw,vh) end
 local ox,oy,oz=Transform.origin(spec.origin,originContext)
 local perspective=nil
 local perspectiveOrigin=nil
 if spec.perspective~='none' then
  local declaredLens=Transform.perspective(style,box,{x=tonumber(box.x) or 0,y=tonumber(box.y) or 0},vw,vh)
  if declaredLens then
   perspective=declaredLens.distance
   perspectiveOrigin={x=declaredLens.ox,y=declaredLens.oy}
  end
 end
 local willChange=entry.willChange
 if willChange==nil then
  local change=style['will-change']
  if change~=nil and change~='auto' then willChange=change end
 end
 return {key=entry.key,box={x=tonumber(box.x) or 0,y=tonumber(box.y) or 0,w=max(0,tonumber(box.w) or 0),h=max(0,tonumber(box.h) or 0)},paintBounds=entry.paintBounds,zIndex=entry.zIndex~=nil and entry.zIndex or style['z-index'],position=entry.position or style.position or 'static',display=entry.display or style.display or 'block',float=entry.float or style.float or 'none',opacity=entry.opacity~=nil and entry.opacity or tonumber(style.opacity) or 1,blend=entry.blend or style['mix-blend-mode'] or 'normal',isolation=entry.isolation or style.isolation or 'auto',filters=entry.filters,mask=entry.mask,clip=entry.clip,radii=entry.radii,contain=entry.contain,transform=hasTransform and parsed.matrix or nil,transformOrigin={x=ox,y=oy,z=oz},transformBox=spec.box,transformBoxes=boxes,transformStyle=spec.transformStyle,backface=spec.backface,perspective=perspective,perspectiveOrigin=perspectiveOrigin,pointerEvents=entry.pointerEvents or style['pointer-events'] or 'auto',willChange=willChange,ops=entry.ops or {},root=entry.root==true}
end
function B.refresh(scene)
 scene.prepared=Compose.prepare(scene.root,{x=scene.x,y=scene.y,baseMatrix=scene.baseMatrix})
 scene.order=Compose.order(scene.root,scene.prepared)
 return scene
end
function B.scene(entries,options)
 options=options or {}
 assert(type(entries)=='table' and #entries>0,'Cena de transform exige entradas.')
 local nodes={}
 local list={}
 local root=nil
 for index,entry in ipairs(entries) do
  local spec=B.spec(entry,options)
  local node
  if entry.parent==nil then
   assert(root==nil,'Cena de transform aceita uma unica raiz.')
   node=Compose.tree(spec)
   root=node
  else
   local parent=assert(nodes[entry.parent],'Pai desconhecido na cena: '..tostring(entry.parent))
   node=Compose.add(parent,spec)
  end
  nodes[entry.key]=node
  list[index]=node
 end
 assert(root~=nil,'Cena de transform exige uma raiz.')
 local scene={root=root,nodes=nodes,list=list,width=options.width,height=options.height,x=options.x,y=options.y,baseMatrix=options.baseMatrix}
 return B.refresh(scene)
end
function B.info(scene,key)
 local node=type(key)=='table' and key or scene.nodes[key]
 if node==nil then return nil end
 return scene.prepared.map[node],node
end
function B.matrixOf(scene,key)
 local info=B.info(scene,key)
 return info and info.matrix or nil
end
function B.childMatrixOf(scene,key)
 local info=B.info(scene,key)
 return info and info.childMatrix or nil
end
function B.depthOf(scene,key)
 local info=B.info(scene,key)
 return info and info.depth or 0
end
function B.backFacing(scene,key)
 local info=B.info(scene,key)
 return info~=nil and info.backFacing==true
end
function B.bounds(scene,key)
 local info=B.info(scene,key)
 return info and info.bounds or nil
end
function B.visible(scene,key)
 local info,node=B.info(scene,key)
 if info==nil then return false end
 return not (node.backface=='hidden' and info.backFacing)
end
function B.keys(scene)
 local out={}
 for _,item in ipairs(scene.order) do out[#out+1]=tostring(item.node.key or '?') end
 return out
end
function B.phases(scene)
 local out={}
 for _,item in ipairs(scene.order) do out[#out+1]=tostring(item.node.key or '?')..':'..item.phase end
 return out
end
function B.paint(scene,target,options)
 options=options or {}
 return Compose.paint(scene.prepared,target,{origin=options.origin or {x=0,y=0},clip=options.clip,order=scene.order,samples=options.samples,warpRoot=options.warpRoot})
end
function B.hitTest(scene,x,y)
 return Compose.hitTest(scene.prepared,x,y,{order=scene.order})
end
function B.localPoint(scene,key,x,y)
 local info,node=B.info(scene,key)
 if info==nil then return false end
 return Compose.localPoint(node,info,x,y)
end
function B.device(scene,key,x,y,z)
 local info=B.info(scene,key)
 if info==nil then return nil end
 local ax=info.x+(tonumber(x) or 0)
 local ay=info.y+(tonumber(y) or 0)
 if info.matrix==nil then return ax,ay end
 return Warp.project(info.matrix,ax,ay,tonumber(z) or 0)
end
function B.glyphs(parent,runs,options)
 options=options or {}
 assert(parent~=nil,'Glifos exigem um elemento pai.')
 local out={}
 for index,run in ipairs(runs or {}) do
  out[index]={key=run.key or (tostring(parent)..'#glyph'..index),parent=parent,box=run.box,style=run.style or options.style or {},value=run.transform,ops=run.ops or {},display=run.display or 'inline-block',position=run.position or 'static',pointerEvents=run.pointerEvents or options.pointerEvents or 'none'}
 end
 return out
end
return B
