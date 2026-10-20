local L=require(script.Parent.LogicalProperties)
local W={VERSION=2,axes=L.axes}
local names={'top','right','bottom','left'}
local indices={top=1,right=2,bottom=3,left=4}
function W.mapRect(a,x,y,w,h,pw,ph)
 if a.vertical then return a.blockReverse and pw-y-h or y,a.inlineReverse and ph-x-w or x,h,w end
 return a.inlineReverse and pw-x-w or x,y,w,h
end
function W.spacing(a,values)
 return {values[indices[a.blockStart]],values[indices[a.inlineEnd]],values[indices[a.blockEnd]],values[indices[a.inlineStart]]}
end
local function physicalSpacing(a,values)
 local out={};out[indices[a.blockStart]]=values[1];out[indices[a.inlineEnd]]=values[2];out[indices[a.blockEnd]]=values[3];out[indices[a.inlineStart]]=values[4];return out
end
local function projectedStyle(a,s)
 local out=table.clone(s)
 if a.vertical then for _,prefix in ipairs({'','min-','max-'})do out[prefix..'width']=s[prefix..'height'];out[prefix..'height']=s[prefix..'width']end end
 local edges={a.blockStart,a.inlineEnd,a.blockEnd,a.inlineStart}
 for i,side in ipairs(names)do
  for _,base in ipairs({'margin','padding'})do out[base..'-'..side]=s[base..'-'..edges[i]]end
 end
 return out
end
function W.plan(engine,node,flow,cw,ch,definiteH,ctx,definiteW)
 local a=L.axes(ctx.styles[node.key])
 if not a.vertical and not a.inlineReverse then return engine.plan(node,flow,cw,ch,definiteH,ctx)end
 local styles=setmetatable({},{__index=function(t,k)local source=ctx.styles[k];if not source then return nil end;local v=projectedStyle(a,source);rawset(t,k,v);return v end})
 local function bases(w,h)if a.vertical then return h,w end;return w,h end
 local function logical(c)
  local out=table.clone(c);if a.vertical then out.w,out.h=c.h,c.w;out.definiteH=c.definiteW;out.definiteW=c.definiteH end
  out.p=W.spacing(a,c.p);out.m=W.spacing(a,c.m);return out
 end
 local proxy=table.clone(ctx);proxy.styles=styles;proxy.writingAxes=a
 proxy.measure=function(child,pw,ph,fw,fh,intrinsic,depth)
  local x,y=bases(pw,ph);local forceX,forceY=bases(fw,fh)
  return logical(ctx.measure(child,x,y,forceX,forceY,intrinsic,depth))
 end
 proxy.info=function(child,pw,ph)
  local x,y=bases(pw,ph);local _,fs,p,m=ctx.info(child,x,y)
  return styles[child.key],fs,W.spacing(a,p),W.spacing(a,m)
 end
 local iw,bh=bases(cw,ch)
 local plan=engine.plan(node,flow,iw,bh,a.vertical and definiteW==true or not a.vertical and definiteH,proxy)
 if plan.writingAxes then return plan end
 local signature=':'..a.mode..':'..tostring(a.inlineReverse)
 local function fragments(list,w,h)
  if not list then return nil end;local out={}
  local pw,ph=bases(w,h)
  for i,f in ipairs(list)do
   local q=table.clone(f);q.x,q.y,q.w,q.h=W.mapRect(a,f.x,f.y,f.w,f.h,pw,ph)
   if a.vertical then q.rotation=a.mode=='sideways-lr'and -90 or 90;q.drawW=f.w;q.drawH=f.h end
   q.direction=ctx.styles[node.key].direction;out[i]=q
  end
  return out
 end
 local function convertItems(list,pw,ph,rows)
  for _,item in ipairs(list or {})do if item.c then
   local c=item.c;local converted=table.clone(c)
   converted.w,converted.h=bases(c.w,c.h);converted.p=physicalSpacing(a,c.p);converted.m=physicalSpacing(a,c.m)
   if a.vertical then converted.definiteH=c.definiteW;converted.definiteW=c.definiteH end
   converted.fragments=fragments(c.fragments,c.w,c.h)
   if converted.fragments then converted.fragmentSignature=(c.fragmentSignature or '')..signature end
   if item.x~=nil then item.x,item.y=W.mapRect(a,item.x,item.y,c.w,c.h,pw,ph)end
   item.c=converted
   if item.areaWidth and rows then
    local areaH=rows.ends[item.row+item.rowSpan-1]-rows.starts[item.row]
    item.physicalAreaW,item.physicalAreaH=bases(item.areaWidth,areaH)
   end
  end end
 end
 convertItems(plan.items,cw,ch,plan.rows)
 plan.fragments=fragments(plan.fragments,iw,bh)
 if plan.fragments then plan.fragmentSignature=(plan.fragmentSignature or '')..signature end
 if plan.columnRules then
  local rules={}
  for i,line in ipairs(plan.columnRules)do
   local x,y,w,h=W.mapRect(a,line.x,line.y,0,line.h,cw,ch)
   rules[i]={x=x,y=y,w=w,h=h,horizontal=a.vertical}
  end
  plan.columnRules=rules;plan.columnSignature=(plan.columnSignature or '')..signature
 end
 if plan.bindings then
  for _,sub in pairs(plan.bindings)do
   if not sub.writingAxes then
    local pw,ph=bases(sub.usedW or 0,sub.usedH or 0)
    convertItems(sub.items,pw,ph,nil)
    if a.vertical then sub.usedW,sub.usedH=sub.usedH,sub.usedW end
    sub.writingAxes=a
   end
  end
 end
 if plan.tableBorders then
  local borders={}
  for i,line in ipairs(plan.tableBorders)do
   local q=table.clone(line);q.x,q.y,q.w,q.h=W.mapRect(a,line.x,line.y,line.w,line.h,cw,ch);borders[i]=q
  end
  plan.tableBorders=borders;plan.tableSignature=(plan.tableSignature or '')..signature
 end
 if plan.captionTop~=nil or plan.captionBottom~=nil or plan.captionLeft~=nil or plan.captionRight~=nil then
  local logicalSides={captionTop=a.blockStart,captionBottom=a.blockEnd,captionLeft=a.inlineStart,captionRight=a.inlineEnd}
  local values={};for key,side in pairs(logicalSides)do values[side]=plan[key]or 0;plan[key]=nil end
  for side,v in pairs(values)do plan['caption'..side:sub(1,1):upper()..side:sub(2)]=v end
  if a.vertical then plan.baseline=nil end
 end
 plan.logicalColumnWidth=plan.columnWidth
 if a.vertical then plan.columnWidth=nil;plan.columnHeight=plan.logicalColumnWidth;plan.usedW,plan.usedH=plan.usedH,plan.usedW end
 plan.writingAxes=a;return plan
end
return W
