local U=require(script.Parent.Util)
local S=require(script.Parent.ScrollStyle)
local G=require(script.Parent.ScrollGeometry)
local T={VERSION=1}
function T.parse(value)
 if value=='auto'or value=='none'then return {kind=value}end
 if value:match('^%-%-[%w_%-]+$')then return {kind='named',name=value}end
 local fn,body=value:match('^([%a%-]+)%((.*)%)$');assert(fn=='scroll'or fn=='view','animation-timeline exige auto, none, --nome, scroll() ou view().')
 local result={kind=fn,axis='block',source='nearest'};local seen={};local inset={}
 for _,v in ipairs(U.split(body,' '))do
  if S.axes[v]then assert(not seen.axis,'Eixo timeline repetido.');seen.axis=true;result.axis=v
  elseif fn=='scroll'and(v=='nearest'or v=='root'or v=='self')then assert(not seen.source,'Fonte timeline repetida.');seen.source=true;result.source=v
  else assert(fn=='view','Token de scroll() inválido: '..v);inset[#inset+1]=v;assert(#inset<=2,'view() aceita até dois insets.')end
 end
 result.inset=#inset>0 and table.concat(inset,' ')or'auto';return result
end
function T.prepare(style,index)
 local value=S.cycle(S.list(style['animation-timeline']or'auto'),index);local result=T.parse(value)
 result.rangeStart=S.endpoint(S.cycle(S.list(style['animation-range-start']or'normal'),index),false)
 result.rangeEnd=S.endpoint(S.cycle(S.list(style['animation-range-end']or'normal'),index),true)
 return result
end
function T.index(c)
 local index={}
 for _,node in ipairs(c.sequence or{})do
  local s=c.styles[node.key]
  for _,kind in ipairs({'scroll','view'})do
   local base=kind..'-timeline';local names=S.list(s[base..'-name']or'none');local axes=S.list(s[base..'-axis']or'block');local insets=S.list(s['view-timeline-inset']or'auto')
   for i,name in ipairs(names)do if name~='none'then
    index[node.key]=index[node.key]or{};index[node.key][name]={kind=kind,axis=S.cycle(axes,i),source='self',subject=node,inset=S.cycle(insets,i)}
   end end
  end
 end
 return index
end
local function named(c,node,name,index)
 local at=node
 while at do local definitions=index[at.key];if definitions and definitions[name]then return definitions[name]end;at=c.parents[at.key]end
 return nil
end
local function boundary(point,ranges,style,width,height)
 local range=ranges[point.name];if not range then return nil end
 return range[1]+G.length(point.offset,range[2]-range[1],style,width,height)
end
function T.resolve(c,key,descriptor,index)
 if not c or not c.styles or not c.nodes then return nil end
 local node=c.nodes[key];if not node then for _,n in ipairs(c.sequence or{})do if n.key==key then node=n;break end end end
 if not node or not c.boxes[key]or c.boxes[key].hidden then return nil end
 local spec=descriptor
 if descriptor.kind=='named'then spec=named(c,node,descriptor.name,index or T.index(c));if not spec then return nil end end
 if spec.kind=='none'or spec.kind=='auto'then return nil end
 local subject=spec.subject or node
 local portNode=G.scroller(c,subject,spec.kind=='view'and'nearest'or spec.source)
 if not portNode then return nil end
 local port=c.objects[portNode.key];local s=c.styles[portNode.key]
 if not port or c.boxes[portNode.key].hidden then return nil end
 local axis,reverse=G.axis(s,spec.axis);local w,h,mx,my=G.port(c,portNode)
 local viewport=axis=='x'and w or h;local limit=axis=='x'and mx or my
 if limit<=0 then return nil end
 local position=axis=='x'and port.CanvasPosition.X or port.CanvasPosition.Y
 if reverse then position=limit-position end
 local ranges
 if spec.kind=='scroll'then ranges={cover={0,limit}}
 else
  local b=c.boxes[subject.key];if not b or b.hidden then return nil end
  local x,y=G.coordinate(c,subject,portNode);local lo=axis=='x'and x or y;local size=axis=='x'and b.w or b.h
  if reverse then lo=limit+viewport-lo-size end
  local padding=G.sides(s,'scroll-padding',w,h,c.width,c.height);local first,last=axis=='x'and 4 or 1,axis=='x'and 2 or 3
  if reverse then first,last=last,first end
  local insets=U.split(spec.inset or'auto',' ');assert(#insets>=1 and #insets<=2,'view inset inválido.')
  local a,bInset=insets[1],insets[2]or insets[1]
  local leading=a=='auto'and padding[first]or G.length(a,viewport,c.styles[subject.key],c.width,c.height)
  local trailing=bInset=='auto'and padding[last]or G.length(bInset,viewport,c.styles[subject.key],c.width,c.height)
  ranges=G.viewRanges(lo,size,viewport,leading,trailing)
 end
 local first=boundary(descriptor.rangeStart,ranges,c.styles[key],c.width,c.height)
 local last=boundary(descriptor.rangeEnd,ranges,c.styles[key],c.width,c.height)
 if not first or not last or last<first then return nil end
 if math.abs(last-first)<1e-7 then return position<first and -1 or 1 end
 return (position-first)/(last-first)
end
return T
