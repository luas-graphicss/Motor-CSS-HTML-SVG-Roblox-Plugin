local Pointer=require(script.Parent.PointerStyle)
local Behavior=require(script.Parent.TransformBehavior)
local VisualEffects=require(script.Parent.VisualEffects)
local LayoutRuntime=require(script.Parent.LayoutRuntime)
local H={VERSION=1}
H.receives=Pointer.receives
H.selectable=Pointer.selectable
H.icon=Pointer.icon
H.native=Pointer.native
local keyword=Pointer.keyword
local TRANSFORMISH=table.freeze({'transform','offset-path','clip-path','mask-image','mask','rotate','scale','translate'})
local function parentOf(c,key)
 local parent=c.parents and c.parents[key]
 if parent==nil and c.nodeParents then parent=c.nodeParents[key]end
 return parent
end
function H.cursorOf(c,key)
 local styles=c.styles
 while key do
  local style=styles and styles[key]
  local value=style and style.cursor
  if value~=nil and keyword(value)~='auto'then return Pointer.icon(value)end
  local node=c.nodes and c.nodes[key]
  if node and node.ownerKey then key=node.ownerKey else
   local parent=parentOf(c,key)
   key=parent and parent.key or nil
  end
 end
 return''
end
local function clips(c,node,box,style)
 if box.clipsContent==true or node.tag=='scroll'then return true end
 if style and(style._overflowClipX==true or style._overflowClipY==true or style.overflow=='hidden'or style.overflow=='clip'or style.overflow=='scroll'or style.overflow=='auto')then return true end
 local object=c.objects[node.key]
 return object~=nil and(object:IsA('ScrollingFrame')or object.ClipsDescendants==true)
end
function H.session(c,x,y)
 local offsets={}
 if c.sequence and c.boxes and c.styles then
  local ok,records=pcall(LayoutRuntime.records,c)
  if ok and records then local ok2,result=pcall(LayoutRuntime.offsets,c,records,false);if ok2 and result then offsets=result end end
 end
 return {x=x,y=y,offsets=offsets,content={},masked={}}
end
local function localOf(s,c,node)
 local key=node.key;local box=c.boxes[key]
 if not box or box.hidden then return nil end
 local parent=parentOf(c,key)
 local px,py
 if parent then
  local memo=s.content[parent.key]
  if memo==nil then
   local lx,ly=localOf(s,c,parent)
   if lx==nil then memo=false else
    local pbox=c.boxes[parent.key];local pstyle=c.styles[parent.key]
    if clips(c,parent,pbox,pstyle)and not box.fixed and(lx<0 or ly<0 or lx>=pbox.w or ly>=pbox.h)then memo=false else
     local object=c.objects[parent.key]
     if object and object:IsA('ScrollingFrame')then local position=object.CanvasPosition;lx+=position.X;ly+=position.Y end
     memo={lx,ly}
    end
   end
   s.content[parent.key]=memo
  end
  if memo==false then return nil end
  px,py=memo[1],memo[2]
 else px,py=s.x,s.y end
 local d=s.offsets[key]
 local lx=px-(tonumber(box.x)or 0)-(d and d.x or 0);local ly=py-(tonumber(box.y)or 0)-(d and d.y or 0)
 local entry=c.cache and c.cache[key];local plan=entry and entry.transformPlan
 if plan and plan.matrix and not plan.identity then
  local _,tx,ty=Behavior.hit(plan,entry.transformBox or box,lx,ly)
  if tx==nil then return nil end
  lx,ly=tx,ty
 end
 return lx,ly
end
local function masked(s,c,key)
 local memo=s.masked[key];if memo~=nil then return memo end
 local style=c.styles[key];local result=false
 if style then
  local clip=style['clip-path'];local mask=style['mask-image']or style.mask
  if(clip and keyword(clip)~='none')or(mask and keyword(mask)~='none')then result=true end
 end
 if not result then local parent=parentOf(c,key);if parent then result=masked(s,c,parent.key)end end
 s.masked[key]=result
 return result
end
function H.visible(style,box)
 if not style or not box or box.hidden then return false end
 if style.display=='none'then return false end
 local visibility=style.visibility
 if visibility=='hidden'or visibility=='collapse'then return false end
 return true
end
function H.localPoint(c,key,x,y,session)
 local node=c.nodes and c.nodes[key]
 if not node or not c.boxes or not c.styles then return nil end
 session=session or H.session(c,x,y)
 return localOf(session,c,node)
end
function H.test(c,key,x,y,session)
 local style=c.styles and c.styles[key];local box=c.boxes and c.boxes[key]
 if not H.visible(style,box)or not Pointer.receives(style)then return false end
 local node=c.nodes[key];if not node then return false end
 session=session or H.session(c,x,y)
 local lx,ly=localOf(session,c,node)
 if lx==nil or lx<0 or ly<0 or lx>=box.w or ly>=box.h then return false end
 if masked(session,c,key)and not VisualEffects.hitTest(c.cache,key,x,y)then return false end
 return true,lx,ly
end
function H.pick(c,x,y,filter)
 local sequence=c.sequence
 if not sequence or not c.boxes or not c.styles then return nil end
 local session=H.session(c,x,y)
 local bestKey,bestZ,bestIndex,bestX,bestY=nil,nil,nil,nil,nil
 for index,node in ipairs(sequence)do
  local key=node.key;local object=c.objects[key]
  if object and(filter==nil or filter(node))then
   local hit,lx,ly=H.test(c,key,x,y,session)
   if hit then
    local z=object.ZIndex or 0
    if bestKey==nil or z>bestZ or(z==bestZ and index>bestIndex)then bestKey,bestZ,bestIndex,bestX,bestY=key,z,index,lx,ly end
   end
  end
 end
 if bestKey==nil then return nil end
 local node=c.nodes[bestKey]
 if node and node.ownerKey and c.nodes[node.ownerKey]then
  local ox,oy=localOf(session,c,c.nodes[node.ownerKey])
  return node.ownerKey,ox or bestX,oy or bestY,bestKey
 end
 return bestKey,bestX,bestY
end
function H.chain(c,key)
 local set={}
 while key do
  set[key]=true
  local node=c.nodes[key]
  if node and node.ownerKey then key=node.ownerKey else local parent=parentOf(c,key);key=parent and parent.key or nil end
 end
 return set
end
function H.fromScreen(c,sx,sy)
 local gui=c.gui
 if gui and gui:IsA('GuiBase2d')then
  local origin=gui.AbsolutePosition
  return sx-origin.X,sy-origin.Y
 end
 return sx,sy
end
function H.contract(c,key)
 local styles=c.styles
 if not styles then return false end
 while key do
  local style=styles[key]
  if style then
   local pointer=keyword(style['pointer-events'])
   if pointer~=nil and pointer~='auto'then return true end
   for _,name in ipairs(TRANSFORMISH)do
    local value=style[name]
    if value~=nil and keyword(value)~='none'then return true end
   end
  end
  local entry=c.cache and c.cache[key];local plan=entry and entry.transformPlan
  if plan and plan.matrix and not plan.identity then return true end
  local parent=parentOf(c,key);key=parent and parent.key or nil
 end
 return false
end
return H
