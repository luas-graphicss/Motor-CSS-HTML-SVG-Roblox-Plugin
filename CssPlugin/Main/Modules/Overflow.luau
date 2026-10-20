local U=require(script.Parent.Util)
local Math=require(script.Parent.MathLength)
local O={VERSION=1}
O.values=table.freeze({visible=true,hidden=true,clip=true,scroll=true,auto=true,['paged-x']=true,['paged-y']=true,['paged-x-controls']=true,['paged-y-controls']=true})
O.keys=table.freeze({'overflow-x','overflow-y','overflow-clip-margin'})
O.defaults=table.freeze({['overflow-x']='visible',['overflow-y']='visible',['overflow-clip-margin']='0px'})
O.shorthands=table.freeze({overflow=table.freeze({'overflow-x','overflow-y'})})
O.scrollables=table.freeze({scroll=true,auto=true,['paged-x']=true,['paged-y']=true,['paged-x-controls']=true,['paged-y-controls']=true})
O.boxes=table.freeze({['border-box']=true,['padding-box']=true,['content-box']=true})
local pagedAxis=table.freeze({['paged-x']='x',['paged-y']='y',['paged-x-controls']='x',['paged-y-controls']='y'})
local scrollable=O.scrollables
local wide=table.freeze({initial=true,inherit=true,unset=true,revert=true,['revert-layer']=true})
function O.keyword(value,property)
 local text=U.trim(tostring(value)):lower()
 assert(O.values[text],(property or 'overflow')..' inválido: '..tostring(value))
 return text
end
function O.register(supported,shorthands)
 for _,key in ipairs(O.keys)do supported[key]=true end
 supported.overflow=true;supported['overflow-block']=true;supported['overflow-inline']=true
 if shorthands then for key,keys in pairs(O.shorthands)do shorthands[key]=keys end end
end
function O.expand(name,value)
 local keys=O.shorthands[name];if not keys then return nil end
 local out={}
 local text=U.trim(tostring(value))
 if wide[text:lower()]then for _,key in ipairs(keys)do out[key]=text:lower()end;return out end
 local parts=U.split(text,' ')
 assert(#parts>=1 and #parts<=2,'overflow aceita 1 ou 2 valores.')
 out[keys[1]]=O.keyword(parts[1],'overflow');out[keys[2]]=O.keyword(parts[2]or parts[1],'overflow')
 return out
end
function O.clipMarginValue(value)
 local text=U.trim(tostring(value))
 local box,length=nil,nil
 for _,token in ipairs(U.split(text,' '))do
  local lower=token:lower()
  if O.boxes[lower]then assert(not box,'overflow-clip-margin repete a caixa de referência.');box=lower
  else assert(not length,'overflow-clip-margin aceita uma caixa e um comprimento.');Math.parse(token);length=token end
 end
 assert(box or length,'overflow-clip-margin vazio.')
 return box or 'padding-box',length or '0px'
end
local function pick(style,key,fallback)
 local value=style[key]
 if value==nil or value==''then return fallback end
 return O.keyword(value,key)
end
function O.serialize(x,y)
 if x==y then return x end
 return x..' '..y
end
local function base(style)
 local value=style.overflow
 if value==nil or value==''then return nil,nil end
 local text=U.trim(tostring(value)):lower()
 if wide[text]then return nil,nil end
 local ok,parts=pcall(O.expand,'overflow',text)
 if not ok then return nil,nil end
 return parts['overflow-x'],parts['overflow-y']
end
local logicalKeys=table.freeze({['overflow-block']='block',['overflow-inline']='inline'})
O.logicalKeys=logicalKeys
function O.axisOf(style,name)
 local vertical=tostring(style['writing-mode']or''):match('^vertical')~=nil
 if name=='block'then return vertical and'x'or'y'end
 return vertical and'y'or'x'
end
function O.logical(style)
 local out={}
 for key,name in pairs(logicalKeys)do
  local value=style[key]
  if value~=nil and value~=''then
   local text=U.trim(tostring(value)):lower()
   if not wide[text]then out[O.axisOf(style,name)]=O.keyword(text,key)end
  end
 end
 return out.x,out.y
end
function O.resolve(style)
 local bx,by=base(style)
 local lx,ly=O.logical(style)
 local x=pick(style,'overflow-x',bx or'visible')
 local y=pick(style,'overflow-y',by or'visible')
 if lx then x=lx end
 if ly then y=ly end
 local px,py=pagedAxis[x],pagedAxis[y]
 if px and y=='visible'then y='hidden'end
 if py and x=='visible'then x='hidden'end
 local ox,oy=x,y
 if ox=='visible'and oy~='visible'then x=oy=='clip'and'hidden'or'auto'end
 if oy=='visible'and ox~='visible'then y=ox=='clip'and'hidden'or'auto'end
 return x,y
end
function O.normalize(style,parent)
 for _,key in ipairs(O.keys)do
  local value=style[key]
  if value~=nil then
   local lower=type(value)=='string'and U.trim(value):lower()or value
   if lower=='inherit'then style[key]=parent and parent[key]or O.defaults[key]
   elseif wide[lower]then style[key]=O.defaults[key]end
  end
 end
 for key in pairs(logicalKeys)do
  local value=style[key]
  if value~=nil then
   local lower=type(value)=='string'and U.trim(value):lower()or value
   if lower=='inherit'then style[key]=parent and parent[key]or nil
   elseif wide[lower]then style[key]=nil end
  end
 end
 local margin=style['overflow-clip-margin']
 if margin~=nil then
  local box,length=O.clipMarginValue(margin)
  style._clipMarginBox=box;style['overflow-clip-margin']=length
 end
 local x,y=O.resolve(style)
 style._overflowX=x;style._overflowY=y
 style._overflowScrollX=scrollable[x]==true;style._overflowScrollY=scrollable[y]==true
 style._overflowClipX=x~='visible';style._overflowClipY=y~='visible'
 style._overflowPaged=pagedAxis[x]or pagedAxis[y]
 style._overflowPagedControls=(x=='paged-x-controls'or y=='paged-y-controls')or nil
 style.overflow=O.serialize(x,y)
 return style
end
function O.axes(style)
 if style._overflowX then return style._overflowX,style._overflowY end
 return O.resolve(style)
end
function O.scrolling(style)
 local x,y=O.axes(style)
 return scrollable[x]==true,scrollable[y]==true
end
function O.clipping(style)
 local x,y=O.axes(style)
 return x~='visible',y~='visible'
end
function O.container(style)
 local x,y=O.scrolling(style)
 return x or y
end
function O.clips(style)
 local x,y=O.clipping(style)
 return x or y
end
function O.pagedAxis(style)
 if style._overflowX then return style._overflowPaged,style._overflowPagedControls==true end
 local x,y=O.resolve(style)
 return pagedAxis[x]or pagedAxis[y],(x=='paged-x-controls'or y=='paged-y-controls')
end
function O.clipMargin(style,base,vw,vh,fs)
 local value=style['overflow-clip-margin']
 if value==nil then return 0,'padding-box'end
 local length=U.length(value,base,vw,vh,fs)or 0
 assert(length>=0,'overflow-clip-margin não aceita comprimento negativo.')
 return length,style._clipMarginBox or'padding-box'
end
function O.relaxed(style,margin,insets)
 if not insets or type(margin)~='number'or margin<=0 then return false end
 local x,y=O.axes(style)
 if x~='clip'and x~='visible'then return false end
 if y~='clip'and y~='visible'then return false end
 if x=='visible'and y=='visible'then return false end
 for i=1,4 do if(insets[i]or 0)>margin+0.01 then return false end end
 return true
end
function O.active(style)
 local x,y=O.axes(style)
 return x~='visible'or y~='visible'or(style['overflow-clip-margin']~=nil and style['overflow-clip-margin']~='0px')
end
function O.install(supports)
 local function keyword(value)return pcall(O.keyword,value,'overflow')end
 supports.register('overflow',function(value)return pcall(O.expand,'overflow',value)end)
 supports.register('overflow-x',keyword)
 supports.register('overflow-y',keyword)
 supports.register('overflow-block',keyword)
 supports.register('overflow-inline',keyword)
 supports.register('overflow-clip-margin',function(value)return pcall(O.clipMarginValue,value)end)
end
return O
