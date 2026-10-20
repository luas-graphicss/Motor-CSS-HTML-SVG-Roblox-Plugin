local U=require(script.Parent.Util)
local Style=require(script.Parent.VisualEffectsStyle)
local Groups=require(script.Parent.VisualEffectsGroups)
local Scene=require(script.Parent.VisualEffectsScene)
local Surface=require(script.Parent.VisualEffectsSurface)
local Assets=require(script.Parent.VisualEffectsAssets)
local Geometry=require(script.Parent.VisualEffectsGeometry)
local TransformRaster=require(script.Parent.TransformRaster)
local E={VERSION=2}
local contexts=setmetatable({},{__mode='k'})
TransformRaster.install()
function E.begin(objects,cache)
 local context=contexts[cache]
 if context and context.assets then context.assets:clear()end
 Surface.beginAll(objects)
 for _,object in pairs(objects)do Groups.begin(object)end
end
function E.paintOpacity()return 1 end
local function effective(styles,values)
 if not values then return styles end
 local result={}
 for key,s in pairs(styles)do
  local v=values[key]
  if v then
   s=U.copy(s);s.opacity=tostring(v.opacity)
   if v.background then local b=v.background;s.background=string.format('rgba(%.8g,%.8g,%.8g,%.8g)',b.color.R*255,b.color.G*255,b.color.B*255,b.alpha)end
  end;result[key]=s
 end;return result
end
function E.finish(doc,objects,styles,boxes,sequence,parents,cache,width,height,work,motionValues)
 styles=effective(styles,motionValues);work=work or {};local diagnostics={};local byKey={};local budget={count=0}
 if doc.svgSources then
  local htmlStyles=table.clone(styles)
  for key in pairs(doc.svgSources)do if styles[key]then htmlStyles[key]=require(script.Parent.SvgStyle).htmlStyle(styles[key])end end
  styles=htmlStyles
 end
 doc.diagnostics=doc.diagnostics or {}
 local known={};for _,d in ipairs(doc.diagnostics)do if d.kind=='effect'then known[(d.key or '')..':'..(d.code or '')]=true end end
 local function report(entry,code,message)
  local key=entry and entry.node.key or '';local token=key..':'..code
  if diagnostics[token]then return end;diagnostics[token]=true
  if not known[token]and #doc.diagnostics<128 then doc.diagnostics[#doc.diagnostics+1]={kind='effect',key=key,code=code,message=message};known[token]=true end
  if entry and entry.object then byKey[key]=byKey[key]or {};byKey[key][#byKey[key]+1]=code end
 end
 local assets=Assets.new(doc,work.checkpoint,function(code,message)report(nil,code,message)end)
 local entries,root=Scene.build(doc,objects,styles,boxes,sequence,parents,assets,report,width,height,work.checkpoint,cache)
 local context={entries=entries,objects=objects,assets=assets,width=width,height=height,diagnostics=diagnostics,scrolls={},layout={objects=objects,styles=styles,boxes=boxes,sequence=sequence,parents=parents,width=width,height=height}}
 for _,object in pairs(objects)do if object:IsA('ScrollingFrame')then context.scrolls[object]=object.CanvasPosition end end
 contexts[cache]=context
 local top={}
 for _,node in ipairs(sequence)do
  local entry=entries[node.key]
  if entry then
   Surface.tint(entry,report,budget)
   if entry.surface and entry.object then
    local up=entry.parent;local covered=false
    while up do if up.surface and up.object then covered=true;break end;up=up.parent end
    if not covered then top[#top+1]=entry end
   end
  end
 end
 local function hide(entry)Surface.hide(entry);for _,child in ipairs(entry.children)do hide(child)end end
 for _,entry in ipairs(top)do
  hide(entry);Surface.draw(entry,budget,doc.effectImages~=false);Surface.maskText(entry,entries,budget,report,work.checkpoint)
  local view=entry.object:FindFirstChild('__CssEffects')
  if view and view:GetAttribute('CssEffectBackend')=='NativeGradientBands'then report(entry,'native-raster-fallback','EditableImage indisponível: bandas de gradiente persistentes aproximam a superfície de pixels.')end
 end
 local bounds={}
 for i=#sequence,1,-1 do
  local node=sequence[i];local key=node.key;local box=boxes[key];local entry=entries[key]
  local b=bounds[key]or {x=0,y=0,right=box.w,bottom=box.h};bounds[key]=b
  if entry and entry.region then local r=entry.region;b={x=r.x,y=r.y,right=r.x+r.w,bottom=r.y+r.h};bounds[key]=b end
  local parent=parents[key]
  local ps=parent and styles[parent.key]or nil
  if parent and not(ps._overflowClipX==true or ps._overflowClipY==true)and parent.tag~='scroll'then
   local pbox=boxes[parent.key];local pb=bounds[parent.key]or {x=0,y=0,right=pbox.w,bottom=pbox.h};bounds[parent.key]=pb
   pb.x=math.min(pb.x,box.x+b.x);pb.y=math.min(pb.y,box.y+b.y);pb.right=math.max(pb.right,box.x+b.right);pb.bottom=math.max(pb.bottom,box.y+b.bottom)
  end
 end
 for _,node in ipairs(sequence)do
  local key=node.key;local object=objects[key]
  if object then
   Surface.sweep(object)
   TransformRaster.sweep(object,cache[key])
   Groups.finish(object,styles[key],boxes[key],cache[key],bounds[key])
   object:SetAttribute('CssEffectsVersion',Style.active(styles[key])and E.VERSION or nil)
   object:SetAttribute('CssEffectsDiagnostics',byKey[key]and table.concat(byKey[key],', ')or nil)
  end
 end
 context.primitives=budget.count;context.surfaces=#top;context.reused=budget.reused or 0;context.created=budget.created or 0
end
function E.hitTest(cache,key,x,y)
 local ctx=contexts[cache];local entry=ctx and ctx.entries[key];if not entry then return true end
 local changed=false;for object,position in pairs(ctx.scrolls)do if object.CanvasPosition~=position then ctx.scrolls[object]=object.CanvasPosition;changed=true end end
 if changed then Scene.reposition(ctx.layout,ctx.entries)end
 local lx,ly=Scene.localPoint(entry,x,y);if lx<0 or ly<0 or lx>=entry.box.w or ly>=entry.box.h then return false end
 while entry do
  lx,ly=Scene.localPoint(entry,x,y)
  if entry.clip and Geometry.coverage(entry.clip,lx,ly,1,1)*Geometry.alpha(entry.masks,lx,ly)<=.01 then return false end
  if entry.clipOverflow and(lx<0 or ly<0 or lx>=entry.box.w or ly>=entry.box.h)then return false end
  entry=entry.parent
 end;return true
end
function E.stats(cache)
 local context=contexts[cache];return {surfaces=context and context.surfaces or 0,primitives=context and context.primitives or 0,maxSide=Scene.MAX_SIDE,reusedSurfaces=context and context.reused or 0,createdSurfaces=context and context.created or 0}
end
function E.release(cache,keepSnapshot)
 local context=contexts[cache];if not context then return end;contexts[cache]=nil
 for _,object in pairs(context.objects or {})do Surface.release(object,keepSnapshot~=false);TransformRaster.release(object)end
 if context.assets then context.assets:clear()end
 table.clear(context.entries);table.clear(context.scrolls);context.objects=nil;context.assets=nil;context.layout=nil
end
return E
