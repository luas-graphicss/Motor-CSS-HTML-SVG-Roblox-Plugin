local P=require(script.Parent.LayoutProperties)
local Containment=require(script.Parent.CssContainment)
local Try=require(script.Parent.CssPositionTry)
local Logical=require(script.Parent.LogicalProperties)
local ML=require(script.Parent.MathLength)
local A={}
local sides=table.freeze({'top','right','bottom','left'})
local spanAll=table.freeze({rows=table.freeze({1,3}),cols=table.freeze({1,3})})
local alignments=table.freeze({start='start',['flex-start']='start',['self-start']='start',left='start',['end']='end',['flex-end']='end',['self-end']='end',right='end',center='center',['anchor-center']='center'})
local function anchorRect(style)
 local units=style._unitContext
 if not units then return nil end
 local name=units.positionAnchor
 if name and units.anchors then return units.anchors[name]end
 return units.anchorRect
end
local function trim(text)return (tostring(text):gsub('^%s+',''):gsub('%s+$',''))end
local function namedAnchor(style,name)
 local units=style._unitContext
 if not units then return nil end
 local wanted=trim(name):lower()
 if wanted=='auto'then return units.anchorRect end
 return units.anchors and units.anchors[wanted]or nil
end
local function blockContext(style,property,anchor,aw,ah)
 local c=style._unitContext and table.clone(style._unitContext)or {}
 c.property=property;c.anchorPending=false;c.anchorInvalid=false;c.positionAnchor=nil;c.anchorsResolved=true
 c.containingWidth=aw;c.containingHeight=ah
 if anchor then c.anchorRect=anchor end
 return c
end
local function blockLength(style,value,base,fs,ctx,property,anchor,aw,ah)
 if value==nil then return nil end
 local lower=type(value)=='string'and trim(value):lower()or value
 if lower=='auto'or lower=='none'then return nil end
 return ML.length(value,base,ctx.vw,ctx.vh,fs,blockContext(style,property,anchor,aw,ah))
end
local function mapped(block,axes)
 local out={}
 for key,value in pairs(block)do out[Try.physical(key,axes)]=value end
 return out
end
local function limited(size,style,block,axis,base,fs,ctx,anchor,aw,ah)
 local low=blockLength(style,block['min-'..axis],base,fs,ctx,'min-'..axis,anchor,aw,ah)
 local high=blockLength(style,block['max-'..axis],base,fs,ctx,'max-'..axis,anchor,aw,ah)
 local out=size
 if high then out=math.min(out,high)end
 if low then out=math.max(out,low)end
 return out
end
A.anchorRect=anchorRect
function A.absolute(child,parent,ctx)
 local anchor=parent
 while anchor~=ctx.root do
  local style=ctx.styles[anchor.key]
  if style.position~='static'or(style.transform and style.transform~='none')or Containment.isolates(style)then break end
  anchor=ctx.parents[anchor.key]or ctx.root
 end
 local box=assert(ctx.boxes[anchor.key]);local as=ctx.styles[anchor.key]
 local border=math.max(0,ctx.length(as['border-width'],box.w,box.fs)or 0)
 if as['border-style']=='none'or as['border-style']=='hidden'then border=0 end
 local borders=as._borderWidths or {border,border,border,border}
 local aw,ah=math.max(0,box.w-borders[2]-borders[4]),math.max(0,box.h-borders[1]-borders[3])
 local function world(node)
  local x,y=0,0
  while node do local b=ctx.boxes[node.key];if b then x+=b.x;y+=b.y end;node=ctx.parents[node.key]end
  return x,y
 end
 local ax,ay=world(anchor);local px,py=world(parent)
 local cs,fs,_,m=ctx.info(child,aw,ah)
 local left,right=ctx.length(cs.left,aw,fs),ctx.length(cs.right,aw,fs)
 local top,bottom=ctx.length(cs.top,ah,fs),ctx.length(cs.bottom,ah,fs)
 local fw=P.isAuto(cs.width)and left~=nil and right~=nil and math.max(0,aw-left-right-m[2]-m[4])or nil
 local fh=P.isAuto(cs.height)and top~=nil and bottom~=nil and math.max(0,ah-top-bottom-m[1]-m[3])or nil
 local function position(start,finish,size,available,before,after,beforeAuto,afterAuto,fallback)
  if start~=nil then
   local extra=finish~=nil and available-start-finish-size-before-after or 0
   if extra>0 and beforeAuto then before+=extra/(afterAuto and 2 or 1)end
   return start+before
  elseif finish~=nil then return available-finish-size-after end
  return fallback+before
 end
 local rect=(cs._positionArea or cs._positionTry)and anchorRect(cs)or nil
 if not rect then
  local c=ctx.measure(child,aw,ah,fw,fh,true,ctx.depth+1)
  local x=position(left,right,c.w,aw,c.m[4],c.m[2],cs['margin-left']=='auto',cs['margin-right']=='auto',box.p[4]-borders[4])
  local y=position(top,bottom,c.h,ah,c.m[1],c.m[3],cs['margin-top']=='auto',cs['margin-bottom']=='auto',box.p[1]-borders[1])
  if (cs._positionArea or cs._positionTry)and cs['position-visibility']=='anchors-valid'then c=table.clone(c);c.hidden=true end
  return ax-px+borders[4]+x,ay-py+borders[1]+y,c,aw,ah
 end
 local containing={w=aw,h=ah}
 local clip={x=0,y=0,w=aw,h=ah}
 if ctx.vw and ctx.vh then
  local ox,oy=ax+borders[4],ay+borders[1]
  local x1,y1=math.max(0,-ox),math.max(0,-oy)
  local x2,y2=math.min(aw,ctx.vw-ox),math.min(ah,ctx.vh-oy)
  clip={x=x1,y=y1,w=math.max(0,x2-x1),h=math.max(0,y2-y1)}
 end
 local blocks=cs._positionTryBlocks or {}
 local axes=Logical.axes(cs)
 local attempts={{}}
 for _,item in ipairs(cs._positionTry or {})do
  if item.area then attempts[#attempts+1]={area=Try.area(item.area,axes.vertical,axes.inlineReverse,axes.blockReverse)}
  elseif item.name then
   local block=blocks[item.name]
   if block then attempts[#attempts+1]={block=mapped(block,axes)}end
  else attempts[#attempts+1]={flips=item.flips}end
 end
 local candidates={}
 for _,attempt in ipairs(attempts)do
  local block=attempt.block
  local anchor=rect
  if block and block['position-anchor']then anchor=namedAnchor(cs,block['position-anchor'])or rect end
  local area=attempt.area
  if not area and block and block['position-area']then area=Try.area(block['position-area'],axes.vertical,axes.inlineReverse,axes.blockReverse)end
  local explicitArea=area or cs._positionArea
  area=explicitArea or spanAll
  local rx,ry,rw,rh=Try.rect(area,anchor,containing)
  local alignH,alignV=Try.alignment(area)
  if not explicitArea then alignH,alignV='start','start'end
  local margins={m[1],m[2],m[3],m[4]}
  if block then
   if block['justify-self']then alignH=alignments[trim(block['justify-self']):lower()]or alignH end
   if block['align-self']then alignV=alignments[trim(block['align-self']):lower()]or alignV end
   for i,side in ipairs(sides)do
    local override=block['margin-'..side]
    if override~=nil then margins[i]=blockLength(cs,override,i%2==0 and aw or ah,fs,ctx,'margin-'..side,anchor,aw,ah)or 0 end
   end
  end
  rx+=margins[4];ry+=margins[1];rw=math.max(0,rw-margins[2]-margins[4]);rh=math.max(0,rh-margins[1]-margins[3])
  local sizeW,sizeH=fw,fh
  if block then
   sizeW=blockLength(cs,block.width,aw,fs,ctx,'width',anchor,aw,ah)or sizeW
   sizeH=blockLength(cs,block.height,ah,fs,ctx,'height',anchor,aw,ah)or sizeH
  end
  local c=ctx.measure(child,rw,rh,sizeW,sizeH,true,ctx.depth+1)
  if block and(block['min-width']or block['max-width']or block['min-height']or block['max-height'])then
   local lw=limited(c.w,cs,block,'width',aw,fs,ctx,anchor,aw,ah)
   local lh=limited(c.h,cs,block,'height',ah,fs,ctx,anchor,aw,ah)
   if lw~=c.w or lh~=c.h then c=ctx.measure(child,rw,rh,lw,lh,true,ctx.depth+1)end
  end
  local x,y=Try.align(rx,ry,rw,rh,c.w,c.h,alignH,alignV)
  local insets={top,right,bottom,left}
  if block then
   for i,side in ipairs(sides)do
    local override=block[side]
    if override~=nil then insets[i]=blockLength(cs,override,i%2==0 and aw or ah,fs,ctx,side,anchor,aw,ah)end
   end
  end
  if insets[4]~=nil then x=rx+insets[4]elseif insets[2]~=nil then x=rx+rw-c.w-insets[2]elseif not explicitArea then x=rx+box.p[4]-borders[4]end
  if insets[1]~=nil then y=ry+insets[1]elseif insets[3]~=nil then y=ry+rh-c.h-insets[3]elseif not explicitArea then y=ry+box.p[1]-borders[1]end
  for _,tactic in ipairs(attempt.flips or{})do x,y=Try.flip(x,y,c.w,c.h,tactic,anchor)end
  local overflow,visibleW,visibleH=Try.overflow(x,y,c.w,c.h,clip)
  candidates[#candidates+1]={x=x,y=y,c=c,overflow=overflow,visibleW=visibleW,visibleH=visibleH}
 end
 local chosen=Try.choose(candidates,cs['position-try-order'])
 local c=chosen.c
 if cs['position-visibility']=='no-overflow'and chosen.overflow>0.001 then c=table.clone(c);c.hidden=true end
 return ax-px+borders[4]+chosen.x,ay-py+borders[1]+chosen.y,c,aw,ah
end
function A.fixed(child,parent,ctx)
 local host=nil
 local node=parent
 while node do
  local style=ctx.styles[node.key]
  if node~=ctx.root and((style.transform and style.transform~='none')or(style.perspective and style.perspective~='none')or(style.filter and style.filter~='none')or Containment.isolates(style))then host=node;break end
  node=ctx.parents[node.key]
 end
 if host then return A.absolute(child,host,ctx)end
 local aw=math.max(0,ctx.vw or 0);local ah=math.max(0,ctx.vh or 0)
 local function world(n)
  local x,y=0,0
  while n do local b=ctx.boxes[n.key];if b then x+=b.x;y+=b.y end;n=ctx.parents[n.key]end
  return x,y
 end
 local px,py=world(parent)
 local pb=ctx.boxes[parent.key];local pad=pb and pb.p or {0,0,0,0}
 local cs,fs,_,m=ctx.info(child,aw,ah)
 local left,right=ctx.length(cs.left,aw,fs),ctx.length(cs.right,aw,fs)
 local top,bottom=ctx.length(cs.top,ah,fs),ctx.length(cs.bottom,ah,fs)
 local fw=P.isAuto(cs.width)and left~=nil and right~=nil and math.max(0,aw-left-right-m[2]-m[4])or nil
 local fh=P.isAuto(cs.height)and top~=nil and bottom~=nil and math.max(0,ah-top-bottom-m[1]-m[3])or nil
 local c=ctx.measure(child,aw,ah,fw,fh,true,ctx.depth+1)
 local function anchored(start,finish,size,available,before,after,beforeAuto,afterAuto,fallback)
  if start~=nil then
   local extra=finish~=nil and available-start-finish-size-before-after or 0
   if extra>0 and beforeAuto then before+=extra/(afterAuto and 2 or 1)end
   return start+before
  elseif finish~=nil then return available-finish-size-after end
  return fallback+before
 end
 local x=anchored(left,right,c.w,aw,c.m[4],c.m[2],cs['margin-left']=='auto',cs['margin-right']=='auto',px+pad[4])
 local y=anchored(top,bottom,c.h,ah,c.m[1],c.m[3],cs['margin-top']=='auto',cs['margin-bottom']=='auto',py+pad[1])
 local out=table.clone(c);out.fixed=true
 if (cs._positionArea or cs._positionTry)and cs['position-visibility']=='anchors-valid'and not anchorRect(cs)then out.hidden=true end
 return x-px,y-py,out,aw,ah
end
return A
