local U=require(script.Parent.Util)
local Interpolation=require(script.Parent.CssInterpolation)
local M={VERSION=1}
local kinds={}
local function register(kind,names)for name in names:gmatch('%S+')do kinds[name]=kind end end
register('<color>','color border-color border-top-color border-right-color border-bottom-color border-left-color outline-color text-decoration-color caret-color accent-color column-rule-color text-emphasis-color fill stroke stop-color flood-color lighting-color')
register('<length-percentage>','width height min-width max-width min-height max-height inline-size block-size min-inline-size max-inline-size min-block-size max-block-size top left right bottom inset-inline-start inset-inline-end inset-block-start inset-block-end padding-top padding-right padding-bottom padding-left margin-top margin-right margin-bottom margin-left row-gap column-gap flex-basis font-size letter-spacing word-spacing text-indent outline-offset border-spacing column-width perspective shape-margin text-underline-offset scroll-padding-top scroll-padding-right scroll-padding-bottom scroll-padding-left scroll-margin-top scroll-margin-right scroll-margin-bottom scroll-margin-left')
register('<number>','flex-grow flex-shrink font-weight fill-opacity stroke-opacity stop-opacity flood-opacity zoom tab-size shape-image-threshold')
register('<integer>','z-index order column-count orphans widows')
register('auto','border-width border-top-width border-right-width border-bottom-width border-left-width outline-width border-radius border-top-left-radius border-top-right-radius border-bottom-right-radius border-bottom-left-radius box-shadow text-shadow filter backdrop-filter clip-path transform-origin perspective-origin background-position background-size object-position rotate scale translate stroke-width stroke-dasharray stroke-dashoffset offset-position offset-anchor offset-rotate font-variation-settings font-stretch vertical-align line-height text-decoration-thickness mask-position mask-size columns grid-template-columns grid-template-rows border-image-width border-image-outset border-image-slice text-emphasis-position')
local keywordDefaults={['<color>']='transparent',['<length-percentage>']='0px',['<number>']='0',['<integer>']='0',auto='none'}
local defaults={width='auto',height='auto',['min-width']='0px',['min-height']='0px',['max-width']='none',['max-height']='none',['font-size']='16px',['font-weight']='400',['line-height']='normal',['flex-grow']='0',['flex-shrink']='1',['flex-basis']='auto',['z-index']='auto',order='0',color='currentcolor',['border-color']='currentcolor',['outline-color']='currentcolor',fill='black',stroke='none',['fill-opacity']='1',['stroke-opacity']='1',['stroke-width']='1px',['letter-spacing']='normal',['word-spacing']='normal',['border-radius']='0px',['border-width']='0px',['outline-width']='0px',['transform-origin']='50% 50%',['perspective-origin']='50% 50%',['background-position']='0% 0%',['background-size']='auto',['box-shadow']='none',['text-shadow']='none',filter='none',['backdrop-filter']='none',['clip-path']='none',rotate='none',scale='none',translate='none',zoom='1',['tab-size']='8',['column-count']='auto',['vertical-align']='baseline'}
M.kinds=kinds
function M.kind(name)return kinds[name]end
function M.supports(name)return kinds[name]~=nil end
function M.default(name)
 local kind=kinds[name];if not kind then return nil end
 return defaults[name]or keywordDefaults[kind]
end
local function idents(text)
 local lower=U.trim(text):lower()
 return lower=='auto'or lower=='none'or lower=='normal'or lower=='inherit'or lower=='initial'or lower=='unset'
end
function M.coerce(name,raw)
 local kind=kinds[name];if not kind then return nil end
 if type(raw)=='number'then
  if raw~=raw or math.abs(raw)==math.huge then return nil end
  if kind=='<length-percentage>'or kind=='auto'then return string.format('%.6g',raw)..'px'end
  return string.format('%.6g',raw)
 end
 if type(raw)=='string'then return raw end
 return nil
end
function M.parse(name,text,context)
 local kind=kinds[name];if not kind then return nil end
 text=M.coerce(name,text)
 assert(type(text)=='string','Valor animável inválido em '..tostring(name)..'.')
 local trimmed=U.trim(text)
 if trimmed==''then return nil end
 if kind=='auto'or idents(trimmed)then
  local ok,value=pcall(Interpolation.parse,trimmed,context)
  if ok then return value end
  return {t='keyword',v=trimmed}
 end
 local ok,value=pcall(Interpolation.typed,kind,trimmed,context)
 if ok then return value end
 local okList,list=pcall(Interpolation.parse,trimmed,context)
 if okList then return list end
 return {t='keyword',v=trimmed}
end
function M.serialize(value)
 if type(value)~='table'or value.t==nil then return nil end
 local ok,text=pcall(Interpolation.serialize,value)
 return ok and text or nil
end
function M.materialize(name,value,raw)
 if type(value)~='table'or value.t==nil then return nil end
 if type(raw)=='number'then
  if value.t=='length'and math.abs(value.pct)<=1e-6 then return value.px end
  if value.t=='number'or value.t=='integer'or value.t=='percentage'then return value.v end
 end
 return M.serialize(value)
end
function M.declared(style,name)
 local raw=style and style[name]
 return type(raw)=='string'or type(raw)=='number'
end
function M.mentioned(style)
 local out={}
 local property=style and style['transition-property']
 if type(property)=='string'then
  for _,item in ipairs(Interpolation.members(property,','))do
   local name=U.trim(item):lower()
   if name=='all'then
    for key in pairs(kinds)do if M.declared(style,key)then out[key]=true end end
   elseif kinds[name]then out[name]=true end
  end
 end
 return out
end
function M.list()
 local names={};for name in pairs(kinds)do names[#names+1]=name end;table.sort(names);return names
end
return M
