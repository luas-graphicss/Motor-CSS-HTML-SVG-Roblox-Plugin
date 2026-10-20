local U=require(script.Parent.Util)
local V=require(script.Parent.VisualStyle)
local L={VERSION=1,supported={},shorthands={},lengthKeys={}}
local sides={'top','right','bottom','left'}
local components={'width','style','color'}
local wide={inherit=true,initial=true,unset=true,revert=true,['revert-layer']=true}
local modes={['horizontal-tb']=true,['vertical-rl']=true,['vertical-lr']=true,['sideways-rl']=true,['sideways-lr']=true}
function L.axes(style)
 local mode=style['writing-mode']or 'horizontal-tb';local dir=style.direction or 'ltr'
 assert(modes[mode],'writing-mode inválido: '..tostring(mode));assert(dir=='ltr'or dir=='rtl','direction aceita ltr/rtl.')
 local vertical=mode~='horizontal-tb';local reverse=dir=='rtl'
 if mode=='sideways-lr'then reverse=not reverse end
 return {vertical=vertical,mode=mode,inlineStart=vertical and(reverse and 'bottom'or 'top')or(reverse and 'right'or 'left'),inlineEnd=vertical and(reverse and 'top'or 'bottom')or(reverse and 'left'or 'right'),blockStart=vertical and(mode:sub(-2)=='rl'and 'right'or 'left')or 'top',blockEnd=vertical and(mode:sub(-2)=='rl'and 'left'or 'right')or 'bottom',inlineReverse=reverse,blockReverse=vertical and mode:sub(-2)=='rl'}
end
local function register(name,keys)
 L.supported[name]=true
 if keys then L.shorthands[name]=keys;for _,key in ipairs(keys)do L.supported[key]=true end end
end
for _,axis in ipairs({'inline','block'})do
 for _,prefix in ipairs({'','min-','max-'})do local k=prefix..axis..'-size';register(k);L.lengthKeys[k]=true end
 for _,base in ipairs({'margin','padding','inset'})do
  local keys={base..'-'..axis..'-start',base..'-'..axis..'-end'};register(base..'-'..axis,keys)
  for _,key in ipairs(keys)do L.lengthKeys[key]=true end
 end
 local both={}
 for _,edge in ipairs({'start','end'})do
  local keys={};for _,component in ipairs(components)do local k='border-'..axis..'-'..edge..'-'..component;keys[#keys+1]=k;both[#both+1]=k;if component=='width'then L.lengthKeys[k]=true end end
  register('border-'..axis..'-'..edge,keys)
 end
 register('border-'..axis,both)
 for _,component in ipairs(components)do register('border-'..axis..'-'..component,{'border-'..axis..'-start-'..component,'border-'..axis..'-end-'..component})end
end
for _,a in ipairs({'start','end'})do for _,b in ipairs({'start','end'})do register('border-'..a..'-'..b..'-radius')end end
register('inset',sides)
register('overflow-block');register('overflow-inline')
register('overscroll-behavior-block');register('overscroll-behavior-inline');register('overscroll-behavior-x');register('overscroll-behavior-y')
for _,base in ipairs({'scroll-margin','scroll-padding'})do
 for _,axis in ipairs({'inline','block'})do register(base..'-'..axis,{base..'-'..axis..'-start',base..'-'..axis..'-end'})end
 for _,side in ipairs(sides)do register(base..'-'..side)end
end
for _,side in ipairs(sides)do
 local keys={};for _,component in ipairs(components)do local key='border-'..side..'-'..component;keys[#keys+1]=key;if component=='width'then L.lengthKeys[key]=true end end
 register('border-'..side,keys)
end
for _,component in ipairs(components)do local keys={};for _,side in ipairs(sides)do keys[#keys+1]='border-'..side..'-'..component end;register('border-'..component,keys)end
local allBorder={};for _,side in ipairs(sides)do for _,component in ipairs(components)do allBorder[#allBorder+1]='border-'..side..'-'..component end end
for _,key in ipairs(V.imageKeys)do allBorder[#allBorder+1]=key end
register('border',allBorder)
function L.register(supported,shorthands)
 for key in pairs(L.supported)do supported[key]=true end
 for key,values in pairs(L.shorthands)do shorthands[key]=values end
end
function L.expand(name,value)
 local keys=L.shorthands[name];if not keys then return nil end
 local out={}
 if wide[value]then for _,key in ipairs(keys)do out[key]=value end;return out end
 if name=='inset'then local words=V.four(value,'inset');for i,key in ipairs(keys)do out[key]=words[i]end;return out end
 if name=='border-width'or name=='border-style'or name=='border-color'then
  local words=V.four(value,name);for i,key in ipairs(keys)do out[key]=words[i]end;return out
 end
 if name:sub(1,7)=='border-'or name=='border'then
  if #keys==2 then
   local words=U.split(value,' ');assert(#words>=1 and #words<=2,name..' aceita 1 ou 2 valores.')
   out[keys[1]]=words[1];out[keys[2]]=words[2]or words[1];return out
  end
  local parsed=V.expand('border',value)
  for _,key in ipairs(keys)do
   local component=key:match('%-(width)$')or key:match('%-(style)$')or key:match('%-(color)$')
   if key:sub(1,13)=='border-image-'then out[key]=parsed[key]
   elseif component then out[key]=parsed['border-'..component]end
  end
  return out
 end
 local words=U.split(value,' ');assert(#words>=1 and #words<=2,name..' aceita 1 ou 2 valores.')
 out[keys[1]]=words[1];out[keys[2]]=words[2]or words[1];return out
end
function L.physical(key,axes)
 if key=='overflow-block'then return axes.vertical and 'overflow-x'or 'overflow-y'end
 if key=='overflow-inline'then return axes.vertical and 'overflow-y'or 'overflow-x'end
 if key=='overscroll-behavior-block'then return axes.vertical and 'overscroll-behavior-x'or 'overscroll-behavior-y'end
 if key=='overscroll-behavior-inline'then return axes.vertical and 'overscroll-behavior-y'or 'overscroll-behavior-x'end
 local scrollBase,scrollAxis,scrollEdge=key:match('^(scroll%-%a+)%-(%a+)%-(%a+)$')
 if(scrollBase=='scroll-margin'or scrollBase=='scroll-padding')and(scrollAxis=='inline'or scrollAxis=='block')and(scrollEdge=='start'or scrollEdge=='end')then return scrollBase..'-'..axes[scrollAxis..(scrollEdge=='start'and 'Start'or 'End')]end
 for _,axis in ipairs({'inline','block'})do
  for _,prefix in ipairs({'','min-','max-'})do if key==prefix..axis..'-size'then return prefix..((axis=='inline')~=axes.vertical and 'width'or 'height')end end
  for _,edge in ipairs({'start','end'})do
   local side=axes[axis..(edge=='start'and 'Start'or 'End')]
   for _,base in ipairs({'margin','padding','inset'})do if key==base..'-'..axis..'-'..edge then return base=='inset'and side or base..'-'..side end end
   for _,component in ipairs(components)do if key=='border-'..axis..'-'..edge..'-'..component then return 'border-'..side..'-'..component end end
  end
 end
 local a,b=key:match('^border%-(%a+)%-(%a+)%-radius$')
 if(a=='start'or a=='end')and(b=='start'or b=='end')then
  local block=axes[a=='start'and 'blockStart'or 'blockEnd'];local inline=axes[b=='start'and 'inlineStart'or 'inlineEnd']
  local top=(block=='top'or block=='bottom')and block or inline;local left=(block=='left'or block=='right')and block or inline
  return 'border-'..top..'-'..left..'-radius'
 end
 return key
end
local function initial(key)
 if key=='overflow-x'or key=='overflow-y'or key=='overflow-block'or key=='overflow-inline'then return 'visible'end
 if key:match('^overscroll%-behavior')then return 'auto'end
 if key:match('^scroll%-padding')then return 'auto'end
 if key:match('^scroll%-margin')then return '0px'end
 if key=='writing-mode'then return 'horizontal-tb'elseif key=='direction'then return 'ltr'elseif key=='text-orientation'then return 'mixed'end
 if key:find('radius',1,true)then return '0px'end
 if key:match('^border%-.+%-width$')then return '3px'elseif key:match('^border%-.+%-style$')then return 'none'elseif key:match('^border%-.+%-color$')then return 'currentcolor'end
 if key:match('^margin%-')or key:match('^padding%-')or key:match('^min%-')then return '0px'end
 if key:match('^max%-')then return 'none'end
 return 'auto'
end
local function owned(key)
 return L.supported[key]or key=='overflow-x'or key=='overflow-y'or key=='writing-mode'or key=='direction'or key=='text-orientation'or key=='width'or key=='height'or key:match('^m[ia][nx]%-')or key:match('^padding%-')or key:match('^margin%-')or key:match('^border%-.+%-radius$')or table.find(sides,key)
end
local Cascade=require(script.Parent.CssCascade)
local function later(a,b)
 if a.specificity~=nil then return Cascade.better(a,b)end
 return not b or a.priority>b.priority or(a.priority==b.priority and(a.index or 0)>=(b.index or 0))
end
function L.resolve(style,winners,parent)
 for _,key in ipairs({'writing-mode','direction','text-orientation'})do
  local v=style[key]
  if wide[v]then style[key]=v=='initial'and initial(key)or(parent and parent[key]or initial(key))end
 end
 local axes=L.axes(style);local parentAxes=parent and L.axes(parent)or axes
 for key in pairs(winners or {})do
  local v=style[key]
  if owned(key)and wide[v]then
   local inheriting=v=='inherit'
   style[key]=inheriting and parent and parent[L.physical(key,parentAxes)]or initial(L.physical(key,axes))
  end
 end
 local mapped={}
 for key,d in pairs(winners or {})do
  if owned(key)then local physical=L.physical(key,axes);if later(d,mapped[physical]and mapped[physical].declaration)then mapped[physical]={declaration=d,value=style[key]}end end
 end
 for key,item in pairs(mapped)do style[key]=item.value;style._important[key]=item.declaration.important==true end
 for key in pairs(winners or {})do
  if L.supported[key]and(key:match('^scroll%-')or key:match('^overscroll%-'))and L.physical(key,axes)~=key then style[key]=nil end
 end
 for _,side in ipairs(sides)do for _,component in ipairs(components)do
  local key='border-'..side..'-'..component
  style[key]=style[key]or style['border-'..component]or(component=='width'and '0px'or component=='style'and 'solid'or 'currentcolor')
 end end
 style._writingAxes=axes
 style._parentWritingKey=parent and((parent['writing-mode']or 'horizontal-tb')..':'..(parent.direction or 'ltr'))or 'root'
 return style
end
function L.finish(style)
 local widths={};local uniform=true;local maximum=0
 for i,side in ipairs(sides)do
  local w=style['border-'..side..'-width']or 0;local mode=style['border-'..side..'-style']or 'solid'
  assert(V.borderStyles[mode],'border-'..side..'-style inválido.')
  assert(type(w)=='number'and w>=0,'border-'..side..'-width exige comprimento não negativo, sem %.')
  if mode=='none'or mode=='hidden'then w=0 end
  widths[i]=w;maximum=math.max(maximum,w)
  if i>1 then uniform=uniform and w==widths[1]and mode==style['border-top-style']and style['border-'..side..'-color']==style['border-top-color']end
 end
 style._borderWidths=widths;style._hasSideBorders=not uniform
 style['border-width']=uniform and widths[1]or maximum
 style['border-style']=style['border-top-style'];style['border-color']=style['border-top-color']
 return style
end
return L
