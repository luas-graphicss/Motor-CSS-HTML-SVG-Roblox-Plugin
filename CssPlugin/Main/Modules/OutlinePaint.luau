local V=require(script.Parent.VisualStyle)
local G=require(script.Parent.VisualGeometry)
local K=require(script.Parent.PaintPrimitives)
local Shapes=require(script.Parent.PaintShapes)
local O={VERSION=1,MAX_MARKS=512,MAX_WIDTH=1000}
local function grow(radii,amount)
 if not radii then return nil end
 local out={};local any=false
 for i,c in ipairs(radii)do
  local x=c.x>0 and math.max(0,c.x+amount)or 0
  local y=c.y>0 and math.max(0,c.y+amount)or 0
  out[i]={x=x,y=y}
  if x>0 or y>0 then any=true end
 end
 if not any then return nil end
 return out
end
local function shrink(rect,amount)
 return {x=rect.x+amount,y=rect.y+amount,w=math.max(0,rect.w-amount*2),h=math.max(0,rect.h-amount*2),r=grow(rect.r,-amount)}
end
local function tinted(color,light)
 if light then return Color3.new(math.min(1,color.R*1.35+.12),math.min(1,color.G*1.35+.12),math.min(1,color.B*1.35+.12))end
 return Color3.new(color.R*.55,color.G*.55,color.B*.55)
end
function O.active(style)
 local mode=style['outline-style']
 return mode~=nil and mode~='none'and mode~='hidden'
end
function O.plan(style,box,context)
 local mode=style['outline-style']
 if mode==nil then return nil end
 assert(V.outlineStyles[mode],'outline-style nao suportado: '..tostring(mode))
 if mode=='none'or mode=='hidden'then return nil end
 local width=G.length(style['outline-width']==nil and'3px'or style['outline-width'],box.w,context)or 0
 assert(width>=0,'outline-width nao pode ser negativo.')
 assert(width<=O.MAX_WIDTH,'outline-width acima de '..O.MAX_WIDTH..'px.')
 if width<=.001 then return nil end
 local offset=G.length(style['outline-offset']==nil and 0 or style['outline-offset'],box.w,context)or 0
 local ink=style['outline-color']or'currentColor'
 if ink=='invert'then ink='currentColor'end
 local color,alpha=V.color(ink,style.color)
 if alpha<=.0005 then return nil end
 local radii=G.radii(style,box.w,box.h,context)
 local total=offset+width
 local outer={x=-total,y=-total,w=box.w+total*2,h=box.h+total*2,r=grow(radii,total)}
 local inner={x=-offset,y=-offset,w=math.max(0,box.w+offset*2),h=math.max(0,box.h+offset*2),r=grow(radii,offset)}
 if outer.w<=.001 or outer.h<=.001 then return nil end
 return {mode=mode=='auto'and'solid'or mode,width=width,offset=offset,color=color,alpha=alpha,outer=outer,inner=inner,radii=radii}
end
local function ring(k,parent,outer,inner,color,alpha,z,shape)
 if outer.w<=.001 or outer.h<=.001 then return end
 local clip={x=outer.x,y=outer.y,w=outer.w,h=outer.h,r=outer.r,shape=shape}
 if inner and inner.w>.001 and inner.h>.001 then clip.hole=Shapes.rect(inner)end
 K.fill(k,parent,clip,color,alpha,z,'outline')
end
local function pathPoints(rect)
 local r=rect.r or {{x=0,y=0},{x=0,y=0},{x=0,y=0},{x=0,y=0}}
 local x0,y0=rect.x,rect.y
 local x1,y1=rect.x+rect.w,rect.y+rect.h
 local points={}
 local function add(x,y)
  local last=points[#points]
  if last and math.abs(last.x-x)<1e-6 and math.abs(last.y-y)<1e-6 then return end
  points[#points+1]={x=x,y=y}
 end
 local function arc(cx,cy,rx,ry,from,to)
  local steps=math.clamp(math.ceil(math.max(rx,ry)/2)+3,4,16)
  for i=0,steps do
   local a=from+(to-from)*i/steps
   add(cx+math.cos(a)*rx,cy+math.sin(a)*ry)
  end
 end
 add(x0+r[1].x,y0)
 add(x1-r[2].x,y0)
 if r[2].x>0 or r[2].y>0 then arc(x1-r[2].x,y0+r[2].y,r[2].x,r[2].y,-math.pi/2,0)end
 add(x1,y1-r[3].y)
 if r[3].x>0 or r[3].y>0 then arc(x1-r[3].x,y1-r[3].y,r[3].x,r[3].y,0,math.pi/2)end
 add(x0+r[4].x,y1)
 if r[4].x>0 or r[4].y>0 then arc(x0+r[4].x,y1-r[4].y,r[4].x,r[4].y,math.pi/2,math.pi)end
 add(x0,y0+r[1].y)
 if r[1].x>0 or r[1].y>0 then arc(x0+r[1].x,y0+r[1].y,r[1].x,r[1].y,math.pi,math.pi*1.5)end
 return points
end
O.pathPoints=pathPoints
function O.marks(k,parent,plan,z,shape)
 local width=plan.width
 local center=shrink(plan.outer,width/2)
 if center.w<=.001 or center.h<=.001 then return 0 end
 local points=pathPoints(center)
 local count=#points
 if count<2 then return 0 end
 local lengths=table.create(count)
 local total=0
 for i=1,count do
  local a=points[i];local b=points[i%count+1]
  local d=math.sqrt((b.x-a.x)^2+(b.y-a.y)^2)
  lengths[i]=d;total+=d
 end
 if total<=.001 then return 0 end
 local dotted=plan.mode=='dotted'
 local mark=dotted and width or width*3
 local gap=dotted and width*1.5 or width*2
 local period=mark+gap
 local repeats=math.max(1,math.floor(total/period+.5))
 period=total/repeats
 mark=period*(mark/(mark+gap))
 local step=math.max(width/2,.75)
 local drawn=0
 local index=1
 local traveled=0
 local position=0
 while position<total-.001 do
  while index<count and traveled+lengths[index]<position do traveled+=lengths[index];index+=1 end
  if position%period<mark then
   local a=points[index]
   local b=points[index%count+1]
   local segment=lengths[index]
   local t=segment>.0001 and math.clamp((position-traveled)/segment,0,1)or 0
   local px=a.x+(b.x-a.x)*t
   local py=a.y+(b.y-a.y)*t
   if Shapes.contains(shape,px,py)then
    local size=math.max(1,width)
    local piece=k:solid(parent,px-size/2,py-size/2,size,size,plan.color,plan.alpha,z,'outline')
    if piece and dotted then
     local corner=k:make('UICorner','Corners',piece)
     corner.CornerRadius=UDim.new(.5,0)
    end
    drawn+=1
    if drawn>=O.MAX_MARKS then break end
   end
  end
  position+=step
 end
 return drawn
end
function O.draw(k,parent,plan,z,shape)
 if not plan then return 0 end
 local mode=plan.mode
 if mode=='double'then
  local band=plan.width/3
  ring(k,parent,plan.outer,shrink(plan.outer,band),plan.color,plan.alpha,z,shape)
  ring(k,parent,shrink(plan.outer,band*2),plan.inner,plan.color,plan.alpha,z,shape)
  return 2
 end
 if mode=='groove'or mode=='ridge'or mode=='inset'or mode=='outset'then
  local middle=shrink(plan.outer,plan.width/2)
  local light=mode=='ridge'or mode=='outset'
  ring(k,parent,plan.outer,middle,tinted(plan.color,light),plan.alpha,z,shape)
  ring(k,parent,middle,plan.inner,tinted(plan.color,not light),plan.alpha,z,shape)
  return 2
 end
 if mode=='dashed'or mode=='dotted'then return O.marks(k,parent,plan,z,shape)end
 ring(k,parent,plan.outer,plan.inner,plan.color,plan.alpha,z,shape)
 return 1
end
return O
