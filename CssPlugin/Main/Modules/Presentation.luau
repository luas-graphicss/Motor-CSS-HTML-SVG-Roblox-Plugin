local Ua=require(script.Parent.UserAgentStyles)
local Form=require(script.Parent.FormState)
local Overflow=require(script.Parent.Overflow)
local P={VERSION=1}
local natives={ui='Frame',frame='Frame',svg='Frame',br='Frame',img='ImageLabel',image='ImageLabel',input='TextBox',textarea='TextBox',button='TextButton',select='TextButton',scroll='ScrollingFrame'}
P.natives=natives
function P.display(node,style)
 if style and style.display then return style.display end
 if node.display then return node.display end
 return Ua.display(node.tag,node.attrs)
end
function P.className(node,style)
 local tag=node.tag or 'div'
 if node.attrs and Form.isToggle(node)then return 'TextButton'end
 local native=natives[tag]
 if native then
  if native=='Frame'and style and Overflow.container(style)then return 'ScrollingFrame'end
  return native
 end
 if node.anonymousText or node.pseudoText then return 'TextLabel'end
 local display=node.display or(style and style.display)or Ua.display(tag,node.attrs)
 if Ua.textual(tag,display)then return 'TextLabel'end
 if style and Overflow.container(style)then return 'ScrollingFrame'end
 return 'Frame'
end
P.classes=setmetatable({},{__index=function(self,tag)
 if type(tag)~='string'then return nil end
 local class=P.className({tag=tag,attrs={}})
 rawset(self,tag,class)
 return class
end})
local known='ui frame text scroll svg div span p a b strong i em u s small code pre kbd samp var sub sup mark time abbr cite q del ins bdi bdo dfn big tt strike font nobr label img input textarea button select option optgroup form fieldset legend ul ol li dl dt dd h1 h2 h3 h4 h5 h6 header footer main nav section article aside figure figcaption blockquote address details summary dialog hgroup menu br hr table thead tbody tfoot tr td th caption col colgroup progress meter canvas video audio iframe object embed picture map output data ruby rt rp center dir search'
for tag in known:gmatch('%S+')do P.classes[tag]=P.className({tag=tag,attrs={}})end
P.legacyClasses=P.classes
function P.isText(node,style)return P.className(node,style)=='TextLabel'end
function P.isTextTag(tag)return P.classes[tag]=='TextLabel'end
function P.isContainer(node,style)local class=P.className(node,style);return class=='Frame'or class=='ScrollingFrame'end
function P.scrolls(node,style)return P.className(node,style)=='ScrollingFrame'end
return P
