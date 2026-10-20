local Budget=require(script.Parent.RenderBudget)
local Tiles=require(script.Parent.RenderTiles)
local Raster=require(script.Parent.RenderRaster)
local Compose=require(script.Parent.RenderCompose)
local Present=require(script.Parent.RenderPresent)
local Core={VERSION=1,Budget=Budget,Tiles=Tiles,Raster=Raster,Compose=Compose,Present=Present}
Core.node=Compose.node
Core.tree=Compose.tree
Core.append=Compose.append
Core.add=Compose.add
Core.prepare=Compose.prepare
Core.order=Compose.order
Core.hitTest=Compose.hitTest
Core.localPoint=Compose.localPoint
Core.preserves=Compose.preserves
function Core.capability(refresh) return Budget.capability(refresh) end
function Core.budget(options) return Budget.new(options) end
function Core.plan(width,height,options) return Budget.plan(width,height,options) end
function Core.create(width,height,options)
 options=options or {}
 local surface=Tiles.new(width,height,options)
 return {surface=surface,budget=surface.budget,plan=surface.plan,view=nil,renders=0,label=options.label or 'Render core'}
end
function Core.invalidate(context,x,y,w,h) return Tiles.invalidate(context.surface,x,y,w,h) end
function Core.invalidateAll(context,reason) return Tiles.invalidateAll(context.surface,reason) end
function Core.invalidateNode(context,prepared,node)
 local info=prepared.map[node]
 if info==nil then return false end
 return Tiles.invalidateBox(context.surface,info.bounds)
end
function Core.render(context,root,options)
 options=options or {}
 local surface=context.surface
 local prepared=options.prepared or Compose.prepare(root,{x=options.x,y=options.y})
 local order=options.order or Compose.order(prepared.root,prepared)
 if options.force then Tiles.invalidateAll(surface,'render forcado') end
 local dirty=Tiles.flush(surface)
 local stats={items=0,groups=0,painted=0,skipped=0}
 if #dirty.rects==0 then
  return {rects={},full=false,stats=stats,prepared=prepared,order=order,dirty=dirty,skipped=true}
 end
 for _,rect in ipairs(dirty.rects) do
  Tiles.clear(surface,rect)
  local partial=Compose.paint(prepared,surface,{clip=rect,order=order,samples=options.samples})
  stats.items+=partial.items
  stats.groups+=partial.groups
  stats.painted+=partial.painted
  stats.skipped+=partial.skipped
 end
 context.renders+=1
 return {rects=dirty.rects,full=dirty.full,reason=dirty.reason,stats=stats,prepared=prepared,order=order,dirty=dirty}
end
function Core.present(context,parent,options)
 options=options or {}
 if context.view==nil then
  assert(parent~=nil,'apresentacao exige um pai na primeira chamada.')
  context.view=Present.attach(parent,context.surface,options)
 end
 return Present.update(context.view,options.rects)
end
function Core.frame(context,root,parent,options)
 options=options or {}
 local result=Core.render(context,root,options)
 if parent~=nil or context.view~=nil then
  result.present=Core.present(context,parent,{rects=result.rects,x=options.x,y=options.y,zIndex=options.zIndex,name=options.name,clip=options.clip})
 end
 return result
end
function Core.stats(context)
 local out=Tiles.stats(context.surface)
 out.renders=context.renders
 out.backend=context.plan.backend
 out.describe=Budget.describe(context.plan)
 out.legacy=Budget.legacy({budget=context.budget,width=context.surface.w,height=context.surface.h,capability=context.plan.capability})
 if context.view~=nil then out.present=Present.report(context.view) end
 return out
end
function Core.release(context)
 if context.view~=nil then
  Present.release(context.view)
  context.view=nil
 end
 Tiles.release(context.surface)
 return context
end
return Core
