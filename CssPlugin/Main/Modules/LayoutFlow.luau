local P=require(script.Parent.LayoutProperties)
local TextFlow=require(script.Parent.RuntimeManifest).optional('LayoutTextFlow')
local Columns=require(script.Parent.RuntimeManifest).optional('LayoutColumns')
local Shapes=require(script.Parent.CssShapes)
local F={VERSION=2}
local raw,lineHeight,fragmentable,wrap,appendFragment,finishEntries=TextFlow.raw,TextFlow.lineHeight,TextFlow.fragmentable,TextFlow.wrap,TextFlow.append,TextFlow.finish
function F.columns(s)return not P.isAuto(s['column-count'])or not P.isAuto(s['column-width'])end
function F.active(s,flow,styles)
 if F.columns(s)then return true end
 for _,child in ipairs(flow)do local c=styles[child.key];if(c.float and c.float~='none')or(c.clear and c.clear~='none')then return true end end
 return false
end
function F.plan(node,flow,cw,ch,definiteH,ctx)
 local s,fs=ctx.info(node,cw,ch);local gy=math.max(0,ctx.length(s['row-gap'],cw,fs)or 0)
 if F.columns(s)then return Columns.plan(node,flow,cw,ch,definiteH,ctx)end
 local floats,entries={},{};local cursor,usedW,usedH=0,0,0
 local axes=s._writingAxes
 local function physical(value,property)
  if value=='inline-start'or value=='inline-end'then
   local side=axes and axes[value=='inline-start'and 'inlineStart'or 'inlineEnd']or(((s.direction=='rtl')==(value=='inline-start'))and 'right'or 'left')
   assert(side=='left'or side=='right',property..' lógico exige eixo inline horizontal.')
   return side
  end
  return value
 end
 local function clearY(value,y)
  value=physical(value,'clear')
  assert(value==nil or value=='none'or value=='left'or value=='right'or value=='both','clear inválido.')
  for _,f in ipairs(floats)do if value=='both'or value==f.side then y=math.max(y,f.bottom)end end;return y
 end
 local function band(y,h,shaped,list)
  local left,right,nextY=0,cw,math.huge
  for _,f in ipairs(list or floats)do if f.top<y+h-.001 and f.bottom>y+.001 then
   local a,b=f.left,f.right
   if shaped and f.shape then local lo,hi=Shapes.interval(f.shape,y-f.top,h);if lo then a=f.left+lo;b=f.left+hi else a=nil end end
   if a then if f.side=='left'then left=math.max(left,b)else right=math.min(right,a)end;nextY=math.min(nextY,f.bottom)end
  end end
  return left,math.max(left,right),nextY
 end
 local function inlineBand(child,cs)
  if not(ctx.setBand and ctx.inlineEnabled and ctx.inlineEnabled(child))then return false end
  if cs.position=='absolute'or cs.position=='fixed'then return false end
  local display=cs.display or 'block'
  if display~='block'and display~='list-item'then return false end
  if(cs.overflow or 'visible')~='visible'or(cs['overflow-x']or 'visible')~='visible'or(cs['overflow-y']or 'visible')~='visible'then return false end
  return true
 end
 for _,child in ipairs(flow)do
  local cs=ctx.styles[child.key];local side=physical(cs.float or'none','float');assert(side=='none'or side=='left'or side=='right','float aceita none/left/right/inline-start/inline-end.')
  cursor=clearY(cs.clear,cursor)
  local c=ctx.measure(child,cw,ch,nil,nil,side~='none',ctx.depth+1)
  if side~='none'and c.w>cw then c=ctx.measure(child,cw,ch,cw,nil,false,ctx.depth+1)end
  local y=cursor;local left,right,nextY=band(y,math.max(1,c.h+c.m[1]+c.m[3]))
  if side~='none'then
   local width=c.w+c.m[2]+c.m[4]
   for _=1,#floats+1 do if width<=right-left+.001 or nextY==math.huge then break end;y=nextY;left,right,nextY=band(y,math.max(1,c.h+c.m[1]+c.m[3]))end
   local x=side=='left'and left or right-width
   entries[#entries+1]={node=child,c=c,x=x+c.m[4],y=y+c.m[1]}
   floats[#floats+1]={side=side,left=x,right=x+width,top=y,bottom=y+c.h+c.m[1]+c.m[3],shape=Shapes.prepare(cs,c,ctx,cw)}
   usedW=math.max(usedW,x+width);usedH=math.max(usedH,floats[#floats].bottom)
  elseif #floats>0 and inlineBand(child,cs)then
   local _,_,pad,margins=ctx.info(child,cw,ch)
   local top=cursor+margins[1];local originX=margins[4]+pad[4];local originY=top+pad[1]
   local snapshot=table.clone(floats)
   ctx.setBand(child.key,function(lineTop,probe)
    local a,b,n=band(originY+lineTop,math.max(1,probe),true,snapshot)
    return math.max(0,a-originX),math.max(0,b-originX),n<math.huge and math.max(0,n-originY)or nil
   end)
   c=ctx.measure(child,cw,ch,nil,nil,false,ctx.depth+1)
   entries[#entries+1]={node=child,c=c,x=c.m[4],y=top}
   cursor=top+c.h+c.m[3]+gy;usedH=math.max(usedH,cursor-gy);usedW=math.max(usedW,c.w+c.m[2]+c.m[4])
  elseif #floats>0 and fragmentable(child,cs,c)and raw(child,ctx)~=''then
   local lh=lineHeight(cs,c.fs);y+=c.m[1];local entry={node=child,c=c};entries[#entries+1]=entry
   local function currentWidth()
    local a,b,n=band(y,lh,true)
    for _=1,#floats+1 do if b-a-c.m[2]-c.m[4]>0 or n==math.huge then break end;y=n;a,b,n=band(y,lh,true)end
    return math.max(1,b-a-c.m[2]-c.m[4])
   end
   wrap(raw(child,ctx),cs,c.fs,currentWidth,function(line)
    currentWidth();local a,b=band(y,lh,true);local x=a+c.m[4]
    if not entry.x then entry.x=x;entry.y=y end
    appendFragment(entry,x,y,math.max(0,b-a-c.m[2]-c.m[4]),lh,line);y+=lh
   end,ctx.checkpoint)
   cursor=y+c.m[3]+gy;usedH=math.max(usedH,cursor-gy);usedW=math.max(usedW,cw)
  else
   local width=math.max(0,right-left)
   if P.isAuto(cs.width)then c=ctx.measure(child,width,ch,nil,nil,false,ctx.depth+1)end
   for _=1,#floats+1 do if c.w+c.m[2]+c.m[4]<=width+.001 or nextY==math.huge then break end;y=nextY;left,right,nextY=band(y,math.max(1,c.h+c.m[1]+c.m[3]));width=right-left;if P.isAuto(cs.width)then c=ctx.measure(child,width,ch,nil,nil,false,ctx.depth+1)end end
   entries[#entries+1]={node=child,c=c,x=left+c.m[4],y=y+c.m[1]};cursor=y+c.h+c.m[1]+c.m[3]+gy
   usedH=math.max(usedH,cursor-gy);usedW=math.max(usedW,left+c.w+c.m[2]+c.m[4])
  end
 end
 finishEntries(entries)
 return {items=entries,usedW=usedW,usedH=usedH}
end
return F
