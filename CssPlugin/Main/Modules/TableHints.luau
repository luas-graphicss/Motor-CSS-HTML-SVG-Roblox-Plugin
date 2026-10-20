local H={VERSION=1}
local cells={td=true,th=true}
local groups={thead=true,tbody=true,tfoot=true,tr=true}
local aligns={left='left',center='center',right='right',justify='justify',middle='center'}
local valigns={top='top',middle='middle',bottom='bottom',baseline='baseline',center='middle'}
local sides={'top','right','bottom','left'}
local function trim(value)return(tostring(value):gsub('^%s+',''):gsub('%s+$',''))end
local function px(value)
 if value==nil then return nil end;value=trim(value)
 local pct=value:match('^(%d+%.?%d*)%%$');if pct then return pct..'%'end
 local n=value:match('^(%d+%.?%d*)$')or value:match('^(%d+%.?%d*)px$');if n then return n..'px'end
end
local function color(value)
 if value==nil then return nil end;value=trim(value);if value==''then return nil end
 if value:match('^%x%x%x%x%x%x$')or value:match('^%x%x%x$')then return'#'..value end
 return value
end
local function lower(value)return value~=nil and tostring(value):lower()or nil end
local function add(list,key,value)if value~=nil then list[#list+1]={key=key,value=value}end;return list end
local function concat(a,b)local out={};for _,d in ipairs(a or{})do out[#out+1]=d end;for _,d in ipairs(b or{})do out[#out+1]=d end;return out end
function H.table(node)
 local a=node.attrs or{};local out={}
 local border=a.border~=nil and(tonumber(trim(a.border))or(trim(a.border)==''and 1))or nil
 if border and border>0 then add(out,'border-width',border..'px');add(out,'border-style','outset')end
 local spacing=px(a.cellspacing);if spacing then add(out,'border-spacing',spacing)end
 add(out,'width',px(a.width));add(out,'height',px(a.height));add(out,'background-color',color(a.bgcolor))
 local align=lower(a.align)
 if align=='center'then add(out,'margin-left','auto');add(out,'margin-right','auto')elseif align=='left'or align=='right'then add(out,'float',align)end
 local shared={}
 if border and border>0 then add(shared,'border-width','1px');add(shared,'border-style','inset')end
 local padding=px(a.cellpadding);if padding then for _,side in ipairs(sides)do add(shared,'padding-'..side,padding)end end
 return out,#shared>0 and shared or nil
end
function H.row(node)
 local a=node.attrs or{};local out={};add(out,'background-color',color(a.bgcolor));add(out,'height',px(a.height))
 local inherit={};add(inherit,'text-align',aligns[lower(a.align)]);add(inherit,'vertical-align',valigns[lower(a.valign)])
 return out,inherit
end
function H.cell(node,inherited)
 local a=node.attrs or{};local out=concat(inherited)
 add(out,'width',px(a.width));add(out,'height',px(a.height));add(out,'background-color',color(a.bgcolor))
 add(out,'text-align',aligns[lower(a.align)]);add(out,'vertical-align',valigns[lower(a.valign)])
 if a.nowrap~=nil then add(out,'white-space','nowrap')end
 return out
end
function H.column(node)local a=node.attrs or{};return add({},'width',px(a.width))end
function H.caption(node)local align=lower((node.attrs or{}).align);return add({},'caption-side',(align=='top'or align=='bottom')and align or nil)end
local function walk(node,shared)
 for _,child in ipairs(node.children or{})do
  if child.tag=='table'then elseif cells[child.tag]then child._tableHints=concat(child._tableHints,shared)elseif groups[child.tag]then walk(child,shared)end
 end
end
function H.apply(node)
 local tag=node.tag
 if tag=='table'then
  local own,shared=H.table(node);if #own>0 then node.hints=concat(node.hints,own)end
  if shared then walk(node,shared)end
 elseif tag=='tr'then
  local own,inherit=H.row(node);if #own>0 then node.hints=concat(node.hints,own)end
  if #inherit>0 then for _,child in ipairs(node.children or{})do if cells[child.tag]then child._tableHints=concat(child._tableHints,inherit)end end end
 elseif cells[tag]then local list=H.cell(node,node._tableHints);node._tableHints=nil;if #list>0 then node.hints=concat(node.hints,list)end
 elseif tag=='col'or tag=='colgroup'then local list=H.column(node);if #list>0 then node.hints=concat(node.hints,list)end
 elseif tag=='caption'then local list=H.caption(node);if #list>0 then node.hints=concat(node.hints,list)end
 end
end
return H
