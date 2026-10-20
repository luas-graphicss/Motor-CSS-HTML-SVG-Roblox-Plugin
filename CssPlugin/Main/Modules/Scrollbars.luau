local U=require(script.Parent.Util)
local Prefs=require(script.Parent.UserPreferences)
local B={VERSION=1}
B.widths=table.freeze({auto=6,thin=3,none=0})
B.behaviors=table.freeze({auto=true,smooth=true})
B.defaults=table.freeze({['scrollbar-width']='auto',['scrollbar-color']='auto',
 ['scrollbar-gutter']='auto',['scroll-behavior']='auto'})
B.keys=table.freeze({'scrollbar-width','scrollbar-color','scrollbar-gutter','scroll-behavior'})
B.inherited=table.freeze({'scrollbar-width','scrollbar-color'})
local function lower(style,key,fallback)
 local value=style and style[key]
 if value==nil or value==''then return fallback end
 return U.trim(tostring(value)):lower()
end
function B.width(value)
 local keyword=U.trim(tostring(value or'auto')):lower()
 assert(B.widths[keyword],'scrollbar-width aceita auto/thin/none.')
 return keyword
end
function B.thickness(style)
 return B.widths[B.width(lower(style,'scrollbar-width','auto'))]
end
function B.gutter(style)
 local value=lower(style,'scrollbar-gutter','auto')
 if value=='auto'then return {stable=false,bothEdges=false}end
 local parts=U.split(value,' ')
 assert(parts[1]=='stable','scrollbar-gutter aceita auto ou stable [both-edges].')
 if #parts==1 then return {stable=true,bothEdges=false}end
 assert(#parts==2 and parts[2]=='both-edges','scrollbar-gutter aceita auto ou stable [both-edges].')
 return {stable=true,bothEdges=true}
end
function B.behavior(style)
 local value=lower(style,'scroll-behavior','auto')
 assert(B.behaviors[value],'scroll-behavior aceita auto/smooth.')
 return value
end
function B.reserve(style,thickness)
 local gutter=B.gutter(style)
 if not gutter.stable then return 0,0 end
 local size=thickness or B.thickness(style)
 if size<=0 then return 0,0 end
 return gutter.bothEdges and size or 0,size
end
function B.colors(style,environment)
 if Prefs.active(environment)and Prefs.adjustment(style)~='none'then
  local palette=Prefs.palette(environment and environment.colorScheme or'light')
  local thumb,thumbAlpha=U.color(palette.buttontext)
  local track,trackAlpha=U.color(palette.buttonface)
  return {thumb=thumb,thumbAlpha=thumbAlpha,track=track,trackAlpha=trackAlpha,forced=true}
 end
 local raw=U.trim(tostring(style and style['scrollbar-color']or'auto'))
 local keyword=raw:lower()
 if raw==''or keyword=='auto'or keyword=='initial'or keyword=='unset'then return nil end
 local parts=U.split(raw,' ')
 assert(#parts==2,'scrollbar-color exige duas cores: polegar e trilho.')
 local thumb,thumbAlpha=U.color(parts[1])
 local track,trackAlpha=U.color(parts[2])
 return {thumb=thumb,thumbAlpha=thumbAlpha,track=track,trackAlpha=trackAlpha,forced=false}
end
function B.normalize(style,parent)
 for _,key in ipairs(B.inherited)do
  local value=style[key]
  if value=='inherit'or value=='unset'then style[key]=parent and parent[key]or B.defaults[key]
  elseif value=='initial'then style[key]=B.defaults[key]
  elseif value==nil and parent then style[key]=parent[key]end
 end
 for _,key in ipairs({'scrollbar-gutter','scroll-behavior'})do
  local value=style[key]
  if value=='inherit'then style[key]=parent and parent[key]or B.defaults[key]
  elseif value=='initial'or value=='unset'then style[key]=B.defaults[key]end
 end
 B.width(lower(style,'scrollbar-width','auto'));B.gutter(style);B.behavior(style)
 if style['scrollbar-color']~=nil then B.colors(style,nil)end
 return style
end
function B.active(style)
 for _,key in ipairs(B.keys)do
  local value=style and style[key]
  if value~=nil and U.trim(tostring(value)):lower()~=B.defaults[key]then return true end
 end
 return false
end
function B.install(supports)
 supports.register('scrollbar-width',function(value)return B.widths[U.trim(value):lower()]~=nil end)
 supports.register('scrollbar-gutter',function(value)return pcall(B.gutter,{['scrollbar-gutter']=value})end)
 supports.register('scroll-behavior',function(value)return B.behaviors[U.trim(value):lower()]==true end)
 supports.register('scrollbar-color',function(value)
  local keyword=U.trim(value):lower()
  if keyword=='auto'then return true end
  return pcall(B.colors,{['scrollbar-color']=value},nil)
 end)
end
return B
