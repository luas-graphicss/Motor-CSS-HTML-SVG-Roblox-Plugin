local U=require(script.Parent.Util)
local Style=require(script.Parent.VisualEffectsStyle)
local Geometry=require(script.Parent.VisualGeometry)
local Clip=require(script.Parent.VisualEffectsGeometry)
local Gradient=require(script.Parent.CssGradient)
local Visual=require(script.Parent.VisualStyle)
local Background=require(script.Parent.AdvancedPaint)
local Border=require(script.Parent.BorderPaint)
local BackgroundRuntime=require(script.Parent.BackgroundRuntime)
local LayoutRuntime=require(script.Parent.LayoutRuntime)
local Groups=require(script.Parent.VisualEffectsGroups)
local P=require(script.Parent.VisualEffectsPixels)
local Assets=require(script.Parent.VisualEffectsAssets)
local Filters=require(script.Parent.SvgFilters)
local SvgGeometry=require(script.Parent.SvgGeometry)
local Cost=require(script.Parent.CostModel)
local Capture=require(script.Parent.RuntimeManifest).optional('VisualEffectsCapture')
local S={VERSION=2,MAX_SIDE=512,MAX_EFFECTS=64,PIXEL_BUDGET=16384,MIN_PIXELS=1024}
local function matrix(parent,box,object,paintState,offset)
 local projected=paintState and paintState.transformProjection
 local native=object and Groups.root(object)
 local angle=math.rad(projected and projected.rotation or native and native.Rotation or 0)
 local scale=native and native:FindFirstChild('__CssScale');scale=scale and scale.Scale or 1
 if projected and not projected.approximate then scale=projected.sx or scale end
 local a,b=math.cos(angle)*scale,math.sin(angle)*scale;local tx=box.x+box.w/2-a*box.w/2+b*box.h/2;local ty=box.y+box.h/2-b*box.w/2-a*box.h/2
 if projected then tx+=projected.x;ty+=projected.y end
 if offset then tx+=offset.x;ty+=offset.y end
 if parent and parent.object and parent.object:IsA('ScrollingFrame')then tx-=parent.object.CanvasPosition.X;ty-=parent.object.CanvasPosition.Y end
 local m={a,b,-b,a,tx,ty}
 if parent then local p=parent.m;m={p[1]*a+p[3]*b,p[2]*a+p[4]*b,p[1]*-b+p[3]*a,p[2]*-b+p[4]*a,p[1]*tx+p[3]*ty+p[5],p[2]*tx+p[4]*ty+p[6]}end;return m
end
local function world(e,x,y)local m=e.m;return m[1]*x+m[3]*y+m[5],m[2]*x+m[4]*y+m[6]end
local function localPoint(e,x,y)
 local m=e.m;local d=m[1]*m[4]-m[2]*m[3];if math.abs(d)<1e-9 then return math.huge,math.huge end
 x-=m[5];y-=m[6];return(m[4]*x-m[3]*y)/d,(-m[2]*x+m[1]*y)/d
end
local function tileAt(list,p)
 for _,tile in ipairs(list)do if p>=tile.start and p<tile.start+tile.size then return(p-tile.start)/tile.size end end;return nil
end
local function source(e,x,y)
 local box=e.box
 local c,a=Background.sampleBackground(e.backgroundPlan,x,y,e.backgroundSampler,e.backgroundBlend)
 local borderColor,borderAlpha=Border.sample(e.borderSample,x,y,e.backgroundSampler)
 if borderColor and borderAlpha>0 then c,a=P.over(c,a,borderColor,borderAlpha)end
 if e.image and x>=0 and y>=0 and x<box.w and y<box.h then
  local ink,alpha=P.sample(e.image,x/box.w*e.image.w-.5,y/box.h*e.image.h-.5);c,a=P.over(c,a,ink,alpha)
 end
 if e.svg then
  local r=e.svgRect;local u,v=(x-r.x)/r.w,(y-r.y)/r.h
  if u>=0 and u<1 and v>=0 and v<1 then local ink,alpha=P.sample(e.svg,u*e.svg.w-.5,v*e.svg.h-.5);c,a=P.over(c,a,ink,alpha)end
 end
 return c,a
end
local sample
local function content(e,gx,gy,limit)
 local x,y=localPoint(e,gx,gy);local c,a=source(e,x,y)
 if e.clipOverflow and(x<0 or y<0 or x>=e.box.w or y>=e.box.h)then return Color3.new(),0 end
 for i,child in ipairs(e.children)do if limit and i>=limit then break end
  local ink,alpha=sample(child,gx,gy);if alpha>0 then c,a=P.over(c,a,ink,alpha)end
 end;return c,a
end
sample=function(e,gx,gy)
 if e.box.hidden then return Color3.new(),0 end
 local c,a
 if e.surface then local x,y=localPoint(e,gx,gy);local r=e.region;c,a=P.sample(e.surface,(x-r.x)/r.w*e.surface.w-.5,(y-r.y)/r.h*e.surface.h-.5)
 else c,a=content(e,gx,gy)end
 return c,a*e.opacity
end
S.sample=sample;S.localPoint=localPoint;S.world=world
function S.reposition(layout,entries)
 local records=LayoutRuntime.records(layout);local offsets=LayoutRuntime.offsets(layout,records)
 for _,node in ipairs(layout.sequence)do
  local e=entries[node.key];if e then e.m=matrix(e.parent,e.box,e.object,e.paintState,offsets[node.key])end
 end
end
local function resolvedLayer(raw,e,assets)
 local layer={};local context=e.context;local box=e.box
 layer.rect=Geometry.rect(e.style,box,raw.origin,context);layer.clipRect=Geometry.rect(e.style,box,raw.clip,context)
 local iw,ih
 if raw.image=='none'then layer.empty=true
 elseif raw.image:find('gradient(',1,true)then layer.definition=raw.image
 else layer.surface=assets:image(Visual.source(raw.image));if layer.surface then iw,ih=layer.surface.w,layer.surface.h else layer.empty=true;e.unreadableImage=true end end
 layer.tw,layer.th=Geometry.size(raw.size,layer.rect.w,layer.rect.h,iw,ih,context)
 local x,y=Geometry.position(raw.position,layer.rect.w,layer.rect.h,layer.tw,layer.th,context)
 local rx,ry=Geometry.repeatModes(raw['repeat'])
 layer.tilesX,layer.tw=Geometry.tiles(layer.rect.w,layer.tw,x,rx,-layer.rect.x,box.w-layer.rect.x)
 layer.tilesY,layer.th=Geometry.tiles(layer.rect.h,layer.th,y,ry,-layer.rect.y,box.h-layer.rect.y)
 if layer.definition then layer.gradient=Gradient.resolve(layer.definition,layer.tw,layer.th,context,e.style.color)end
 return layer
end
function S.build(doc,objects,styles,boxes,sequence,parents,assets,report,width,height,checkpoint,paintCache)
 local entries,root={},nil;local hasRaster=false
 for _,node in ipairs(sequence)do
  local s=styles[node.key];if Style.needsSurface(s)then hasRaster=true;break end
 end
 if not hasRaster then return entries,nil end
 local layout={objects=objects,styles=styles,boxes=boxes,sequence=sequence,parents=parents,width=width,height=height}
 local stickyRecords=LayoutRuntime.records(layout);local stickyOffsets=LayoutRuntime.offsets(layout,stickyRecords)
 local count=0
 for _,node in ipairs(sequence)do
  local box=boxes[node.key];local parent=parents[node.key]and entries[parents[node.key].key];local object=objects[node.key];local s=styles[node.key]
  local context=Geometry.context(s,width,height);context.fs=box.fs;context.color=s.color
  context.image=function(url)return assets:image(url)end;context.path=function(d,rule,w,h)return assets:path(d,rule,w,h)end
  local plan=Style.plan(s,context);local active=Style.needsSurface(s)
  for _,chain in ipairs({plan.filters,plan.backdrop})do
   for _,f in ipairs(chain)do
    if f.reference and not f.graph then f.graph=Assets.filter(doc,f.reference);f.extent=Filters.extent(f.graph)end
   end
  end
  local e={node=node,object=object,style=s,box=box,parent=parent,children={},context=context,plan=plan,active=active,opacity=math.clamp(tonumber(s.opacity)or 1,0,1),clipOverflow=s.overflow=='hidden'or node.tag=='scroll'}
  e.paintState=paintCache and paintCache[node.key];e.m=matrix(parent,box,object,e.paintState,stickyOffsets[node.key]);entries[node.key]=e;if parent then parent.children[#parent.children+1]=e else root=e end
  local backgroundBox=BackgroundRuntime.paintBox(node,box,boxes,parents,objects)
  e.backgroundPlan=Background.plan(s,backgroundBox,width,height);e.borderSample=Border.prepareSample(s,box,context)
  local surfaces={}
  local function load(source)
   if surfaces[source]==nil then surfaces[source]=assets:image(source)or false end
   if not surfaces[source]then e.unreadableBackground=true;e.unreadableImage=true end
  end
  for _,layer in ipairs(e.backgroundPlan.layers)do if layer.source then load(layer.source)end end
  if e.borderSample.image and e.borderSample.image.image then load(e.borderSample.image.image)end
  e.backgroundSampler=function(source,x,y,iw,ih)
   local surface=surfaces[source];if not surface then return Color3.new(),0 end
   return P.sample(surface,x/math.max(iw,1e-9)*surface.w-.5,y/math.max(ih,1e-9)*surface.h-.5)
  end
  e.backgroundBlend=function(c,a,ink,alpha,index)return P.over(c,a,ink,alpha,plan.backgroundBlends[(index-1)%#plan.backgroundBlends+1])end
  e.radii=Geometry.radii(s,box.w,box.h,context);e.border=math.max(0,Geometry.length(s['border-width']or '0',box.w,context)or 0)
  if s['border-style']=='none'or s['border-style']=='hidden'then e.border=0 end
  e.borderColor,e.borderAlpha=Visual.color(s['border-color']or s.color or 'white',s.color)
  if object and(object:IsA('ImageLabel')or object:IsA('ImageButton'))then e.image=assets:image(object.Image);e.unreadableImage=not e.image end
  if object then
   local view=object:FindFirstChild('__Svg');local data=view and view:GetAttribute('SvgTextureData')
   if data then
    e.svg=Assets.decode(data,U.color(s.color or 'white'));e.svgRect={x=view.Position.X.Scale*box.w+view.Position.X.Offset,y=view.Position.Y.Scale*box.h+view.Position.Y.Offset,w=view.Size.X.Scale*box.w+view.Size.X.Offset,h=view.Size.Y.Scale*box.h+view.Size.Y.Offset}
   end
   e.isText=object:IsA('TextLabel')or object:IsA('TextButton')or object:IsA('TextBox')
  end
  if active then
   count+=1;Cost.cap('surfaces',count,'Elementos com efeitos raster');assert(count<=S.MAX_EFFECTS,string.format('Máximo de %d elementos com efeitos raster por interface.',S.MAX_EFFECTS))
   e.clip=Clip.clip(plan.clip,box.w,box.h,context);e.masks=Clip.masks(s,box,context)
  end
  if checkpoint then checkpoint(8)end
 end
 for _,e in pairs(entries)do
  table.sort(e.children,function(a,b)
   local za,zb=tonumber(a.style['z-index'])or 0,tonumber(b.style['z-index'])or 0
   if za~=zb then return za<zb end
   return a.node.order<b.node.order
  end)
  if e.unreadableBackground then local up=e;while up do up.skipUnreadableBackground=true;up=up.parent end end
 end
 local function graphFilter(surface,f,e,scale,left,top)
  local c={vb={left,top,math.max(e.box.w,1e-6),math.max(e.box.h,1e-6)},sx=scale,sy=scale,pad=0,padBudget=math.ceil((f.extent or 0)*scale)+16,w=surface.w,h=surface.h,color=U.color(e.style.color or 'white'),checkpoint=checkpoint and function()checkpoint(32)end or nil}
  return Filters.apply(surface,f.graph,{x=0,y=0,w=math.max(e.box.w,1e-6),h=math.max(e.box.h,1e-6)},SvgGeometry.I,c)
 end
 local function applyChain(surface,chain,e,scale,left,top)
  if #chain==0 then return surface end
  local pending={}
  for _,f in ipairs(chain)do
   if f.graph then
    if #pending>0 then surface=P.filter(surface,pending,scale,checkpoint);pending={}end
    surface=graphFilter(surface,f,e,scale,left,top)
   else pending[#pending+1]=f end
  end
  if #pending>0 then surface=P.filter(surface,pending,scale,checkpoint)end
  return surface
 end
 local transparent=function()return Color3.new(),0 end
 local state={scope='document'}
 local scope,scopeColor='document',nil
 for _,node in ipairs(sequence)do
  local entry=entries[node.key]
  if entry and entry.active and Capture.rank(entry.plan.backdropScope)>Capture.rank(scope)then scope=entry.plan.backdropScope;scopeColor=entry.plan.backdropColor end
 end
 local capturePlan=Capture.plan(root and root.object,scope,scopeColor)
 local origin=Vector2.zero
 if root and root.object and root.object:IsA('GuiObject')then origin=root.object.AbsolutePosition-Vector2.new(root.box.x,root.box.y)end
 local external=Capture.rank(scope)>1 and Capture.sampler(capturePlan,origin,state)or transparent
 local function render(e,backdrop)
  e.backdropSample=function(gx,gy)
   local previous=state.scope
   state.scope=e.plan.backdropScope
   local color,alpha=backdrop(gx,gy)
   state.scope=previous
   return color,alpha
  end
  for i,child in ipairs(e.children)do
   local function behind(gx,gy)
    local b,ba=Color3.new(),0
    if e.plan.isolation~='isolate'and e.opacity==1 and #e.plan.filters==0 then b,ba=backdrop(gx,gy)end
    local c,a=content(e,gx,gy,i);return P.over(b,ba,c,a)
   end
   render(child,behind)
  end
  local left,top,right,bottom=0,0,e.box.w,e.box.h
  if e.borderSample.image then local r=e.borderSample.image.area;left=math.min(left,r.x);top=math.min(top,r.y);right=math.max(right,r.x+r.w);bottom=math.max(bottom,r.y+r.h)end
  if not e.clipOverflow then
   for _,child in ipairs(e.children)do
    local r=child.region or {x=0,y=0,w=child.box.w,h=child.box.h}
    for _,p in ipairs({{r.x,r.y},{r.x+r.w,r.y},{r.x,r.y+r.h},{r.x+r.w,r.y+r.h}})do local gx,gy=world(child,p[1],p[2]);local x,y=localPoint(e,gx,gy);left=math.min(left,x);top=math.min(top,y);right=math.max(right,x);bottom=math.max(bottom,y)end
   end
  end
  if e.active then
   local padding=0
   for _,chain in ipairs({e.plan.filters,e.plan.backdrop})do
    for _,f in ipairs(chain)do
     if f.name=='blur'then padding+=3*f.value
     elseif f.name=='drop-shadow'then padding+=3*f.blur+math.max(math.abs(f.x),math.abs(f.y))
     elseif f.extent then padding+=f.extent end
    end
   end
   padding=math.min(4096,padding);left-=padding;top-=padding;right+=padding;bottom+=padding
  end
  e.region={x=left,y=top,w=math.max(1,right-left),h=math.max(1,bottom-top)}
  if not e.active or e.box.hidden then return end
  if e.skipUnreadableBackground then report(e,'background-image-permission','Efeito raster não aplicado a este grupo: uma imagem de fundo/borda não pôde ser lida. A pintura nativa foi preservada.');return end
  assert(e.region.w<=16384 and e.region.h<=16384,'Extensão de efeito excede 16384px.')
  local allowance=math.max(S.MIN_PIXELS,math.floor(S.PIXEL_BUDGET/math.max(1,count)))
  local scale=math.min(1,S.MAX_SIDE/math.max(e.region.w,e.region.h),math.sqrt(allowance/math.max(1,e.region.w*e.region.h)))
  local w,h=math.max(1,math.ceil(e.region.w*scale)),math.max(1,math.ceil(e.region.h*scale));local image=P.new(w,h);local back=P.new(w,h)
  state.scope=e.plan.backdropScope
  if scale>=1 then report(e,'effect-resolution',string.format('Filtros, blend e máscara compostos em pixels reais (%dx%d).',w,h))
  else report(e,'effect-resolution',string.format('Filtros, blend e máscara compostos a %d%% da resolução real (%dx%d de %dx%d px).',math.floor(scale*100+.5),w,h,math.ceil(e.region.w),math.ceil(e.region.h)))end
  for y=0,h-1 do for x=0,w-1 do
   local lx=left+(x+.5)/w*e.region.w;local ly=top+(y+.5)/h*e.region.h;local gx,gy=world(e,lx,ly)
   local c,a=content(e,gx,gy);P.set(image,x,y,c,a)
   if #e.plan.backdrop>0 or e.plan.blend~='normal'then local b,ba=backdrop(gx,gy);P.set(back,x,y,b,ba)end
  end;if checkpoint and y%4==0 then checkpoint(48)end end
  if #e.plan.backdrop>0 then
   local glass=applyChain(back,e.plan.backdrop,e,scale,left,top)
   P.mask(glass,function(x,y)local lx=left+(x+.5)/w*e.region.w;local ly=top+(y+.5)/h*e.region.h;return Geometry.inside(e.radii,e.box.w,e.box.h,lx,ly)and 1 or 0 end)
   P.composite(glass,image);image=glass
   if Capture.rank(e.plan.backdropScope)<2 then report(e,'backdrop-scope','backdrop-filter amostra a árvore CSS composta sob o elemento; use -roblox-backdrop-scope: interface, screen ou world para incluir a GUI nativa, outras ScreenGuis ou uma base do mundo 3D.')
   else report(e,'backdrop-scope','backdrop-filter com '..Capture.describe(capturePlan,e.plan.backdropScope)..'.')end
  end
  image=applyChain(image,e.plan.filters,e,scale,left,top)
  P.mask(image,function(x,y)local lx=left+(x+.5)/w*e.region.w;local ly=top+(y+.5)/h*e.region.h;return Clip.coverage(e.clip,lx,ly,e.region.w/w,e.region.h/h)*Clip.alpha(e.masks,lx,ly)end)
  if e.plan.blend~='normal'then
   for y=0,h-1 do for x=0,w-1 do
    local c,a=P.get(image,x,y);local b,ba=P.get(back,x,y);local mixed=P.blend(b,c,e.plan.blend);P.set(image,x,y,c:Lerp(mixed,ba),a)
   end end
  end
  e.surface=image
  if e.unreadableImage then report(e,'image-permission','Uma imagem não pôde ser lida; a imagem nativa é preservada sem filtros de pixels.')end
 end
 render(root,external);return entries,root
end
return S
