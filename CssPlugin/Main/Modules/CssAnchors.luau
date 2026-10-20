local Containment=require(script.Parent.CssContainment)
local A={VERSION=1}
local function names(value)
 local out={}
 if not value or value=='none'or value=='auto'then return out end
 for name in value:gmatch('%S+')do assert(name:match('^%-%-[%w_%-]+$'),'Nome de âncora exige --ident.');out[#out+1]=name end
 return out
end
function A.validate(style)
 names(style['anchor-name'])
 if style['anchor-scope']~='all'then names(style['anchor-scope'])end
 local position=names(style['position-anchor']);assert(#position<=1,'position-anchor aceita um nome ou auto.')
end
function A.uses(style)
 local area=style['position-area']
 if area~=nil and area~='none'then return true end
 for key,value in pairs(style)do
  if key:sub(1,1)~='_'and type(value)=='string'and(value:lower():find('anchor(',1,true)or value:lower():find('anchor-size(',1,true))then return true end
 end
 return false
end
local function vertical(s)return s and s['writing-mode']and s['writing-mode']~='horizontal-tb'or false end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
function A.enrich(contexts,styles,sequence,parents,boxes,vw,vh)
 local registry={};local nodes={};local root=sequence[1];local worldCache={};local hidden={};local byId={}
 local function world(node)
  if not node then return 0,0 end
  local cached=worldCache[node.key];if cached then return cached[1],cached[2]end
  local x,y=world(parents[node.key]);local box=boxes and boxes[node.key]
  if box then x+=box.x or 0;y+=box.y or 0 end
  worldCache[node.key]={x,y};return x,y
 end
 local function within(node,ancestor)
  while node do if node.key==ancestor.key then return true end;node=parents[node.key]end
  return false
 end
 local function scope(node,name)
  while node do
   local style=styles[node.key];local value=style and style['anchor-scope']
   if value=='all'then return node.key end
   for _,declared in ipairs(names(value))do if declared==name then return node.key end end
   node=parents[node.key]
  end
  return nil
 end
 for index,node in ipairs(sequence)do
  nodes[node.key]=index
  local style=styles[node.key];local parent=parents[node.key]
  hidden[node.key]=style.display=='none'or parent and hidden[parent.key]or false
  if not hidden[node.key]then
   local id=node.attrs and node.attrs.id
   if id then byId[id]=node end
   for _,name in ipairs(names(style['anchor-name']))do
    local list=registry[name]or {};registry[name]=list;list[#list+1]=node
   end
  end
 end
 for _,node in ipairs(sequence)do
  local style=styles[node.key]
  if not style._usesAnchor then continue end
  local c=contexts[node.key]or {};contexts[node.key]=c
  c.anchorsResolved=boxes~=nil;c.anchorPending=not c.anchorsResolved;c.anchorInvalid=style.position~='absolute';c.anchors={}
  local containing=parents[node.key]or root
  while containing and containing~=root do
   local st=styles[containing.key]
   if st.position~='static'or st.transform and st.transform~='none'or Containment.isolates(st)then break end
   containing=parents[containing.key]or root
  end
  local box=boxes and containing and boxes[containing.key]
  local st=containing and styles[containing.key]or {}
  local border=tonumber(st['border-width'])or 0
  local borders=st._borderWidths or {border,border,border,border}
  local x,y=world(containing);x+=borders[4];y+=borders[1]
  c.containingWidth=box and math.max(0,box.w-borders[2]-borders[4])or vw;c.containingHeight=box and math.max(0,box.h-borders[1]-borders[3])or vh
  c.containingVertical=vertical(st);c.containingWritingMode=st['writing-mode'];c.containingDirection=st.direction
  c.positionAnchor=names(style['position-anchor'])[1]
  local stamp={tostring(c.anchorsResolved),tostring(c.anchorInvalid),string.format('%.9g,%.9g',c.containingWidth,c.containingHeight),tostring(c.containingWritingMode),tostring(c.containingDirection),tostring(c.positionAnchor)}
  local allNames={};for name in pairs(registry)do allNames[#allNames+1]=name end;table.sort(allNames)
  for _,name in ipairs(allNames)do
   local chosen;local consumerScope=scope(node,name)
   for _,candidate in ipairs(registry[name])do
    local cs=styles[candidate.key]
    if not within(candidate,node)and scope(candidate,name)==consumerScope and(cs.position~='absolute'or nodes[candidate.key]<nodes[node.key])then chosen=candidate end
   end
   local cb=chosen and boxes and boxes[chosen.key]
   if cb then
    local cx,cy=world(chosen);local r={x=cx-x,y=cy-y,width=cb.w,height=cb.h,vertical=vertical(styles[chosen.key])}
    assert(finite(r.x)and finite(r.y)and finite(r.width)and finite(r.height),'Geometria de âncora não finita.')
    c.anchors[name]=r;stamp[#stamp+1]=#name..':'..name..':'..string.format('%.9g,%.9g,%.9g,%.9g',r.x,r.y,r.width,r.height)..':'..tostring(r.vertical)
   end
  end
  if not c.positionAnchor then
   local target=node.attrs and node.attrs.anchor and byId[node.attrs.anchor]or nil
   if not target then
    local ancestor=parents[node.key]
    while ancestor do
     local ancestorStyle=styles[ancestor.key]
     if ancestorStyle and not hidden[ancestor.key]and #names(ancestorStyle['anchor-name'])>0 then target=ancestor;break end
     ancestor=parents[ancestor.key]
    end
   end
   local tb=target and not hidden[target.key]and not within(target,node)and boxes and boxes[target.key]or nil
   if tb then
    local tx,ty=world(target)
    local r={x=tx-x,y=ty-y,width=tb.w,height=tb.h,vertical=vertical(styles[target.key])}
    assert(finite(r.x)and finite(r.y)and finite(r.width)and finite(r.height),'Geometria de âncora implícita não finita.')
    c.anchorRect=r;stamp[#stamp+1]='implicit:'..string.format('%.9g,%.9g,%.9g,%.9g',r.x,r.y,r.width,r.height)
   end
  end
  c.anchorKey=table.concat(stamp,'|')
 end
 return contexts
end
return A
