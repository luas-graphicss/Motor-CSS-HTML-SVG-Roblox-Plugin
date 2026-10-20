local U=require(script.Parent.Util)
local C={VERSION=1}
local NONE=table.freeze({layout=false,paint=false,size=false,inlineSize=false,style=false})
local STRICT=table.freeze({layout=true,paint=true,size=true,inlineSize=false,style=true})
local CONTENT=table.freeze({layout=true,paint=true,size=false,inlineSize=false,style=true})
local fields=table.freeze({size='size',['inline-size']='inlineSize',layout='layout',style='style',paint='paint'})
local visibilities=table.freeze({visible=true,auto=true,hidden=true})
local axisKeys=table.freeze({width='contain-intrinsic-width',height='contain-intrinsic-height'})
local logicalKeys=table.freeze({'contain-intrinsic-inline-size','contain-intrinsic-block-size'})
C.NONE=NONE
C.axisKeys=axisKeys
local cache,slots,cursor={},{},0
function C.flags(value)
 local lower=U.trim(tostring(value)):lower()
 local hit=cache[lower];if hit then return hit end
 assert(lower~='','contain vazio.')
 local result
 if lower=='none'then result=NONE
 elseif lower=='strict'then result=STRICT
 elseif lower=='content'then result=CONTENT
 else
  local flags={layout=false,paint=false,size=false,inlineSize=false,style=false};local seen={}
  local list=U.split(lower,' ');assert(#list>=1 and #list<=4,'contain aceita no máximo 4 palavras-chave.')
  for _,word in ipairs(list)do
   local field=fields[word];assert(field,'contain inválido: '..word)
   assert(not seen[field],'contain repetido: '..word);seen[field]=true;flags[field]=true
  end
  assert(not(flags.size and flags.inlineSize),'contain não aceita size e inline-size juntos.')
  result=table.freeze(flags)
 end
 cursor=cursor%64+1;local old=slots[cursor];if old then cache[old]=nil end
 slots[cursor]=lower;cache[lower]=result;return result
end
function C.intrinsicValue(text)
 local trimmed=U.trim(tostring(text));assert(trimmed~='','contain-intrinsic-size vazio.')
 local auto=false;local rest=trimmed:match('^[Aa][Uu][Tt][Oo]%s+(.+)$')
 if rest then auto=true;trimmed=U.trim(rest)end
 assert(trimmed:lower()~='auto','contain-intrinsic-size: auto exige um tamanho de reserva.')
 return auto,trimmed
end
function C.expand(value)
 local list=U.split(U.trim(tostring(value)),' ')
 assert(#list>=1 and #list<=4,'contain-intrinsic-size aceita 1 ou 2 valores.')
 local parts,i={},1
 while i<=#list do
  local prefix=''
  if list[i]:lower()=='auto'then prefix='auto ';i+=1;assert(list[i],'contain-intrinsic-size: auto exige um tamanho de reserva.')end
  parts[#parts+1]=prefix..list[i];i+=1
 end
 assert(#parts>=1 and #parts<=2,'contain-intrinsic-size aceita 1 ou 2 valores.')
 return parts[1],parts[2]or parts[1]
end
function C.normalize(style)
 local vertical=tostring(style['writing-mode']or'horizontal-tb'):sub(1,8)=='vertical'
 for _,key in ipairs(logicalKeys)do
  local value=style[key]
  if value~=nil then
   local inline=key=='contain-intrinsic-inline-size'
   local target=(inline~=vertical)and'contain-intrinsic-width'or'contain-intrinsic-height'
   if style[target]==nil then style[target]=value end
   style[key]=nil
  end
 end
 if style.contain~=nil then style._containFlags=C.flags(style.contain)end
 local cv=style['content-visibility']
 if cv~=nil then
  cv=U.trim(tostring(cv)):lower();assert(visibilities[cv],'content-visibility aceita visible, auto ou hidden.')
  style['content-visibility']=cv;style._contentVisibility=cv
 end
 for axis,key in pairs(axisKeys)do
  local value=style[key]
  if value~=nil then
   local text=U.trim(tostring(value))
   if text:lower()=='none'then style[key]='none'
   else
    local auto,size=C.intrinsicValue(text)
    if auto then
     local remembered=style._containIntrinsicAuto
     if not remembered then remembered={};style._containIntrinsicAuto=remembered end
     remembered[axis]=true
    end
    style[key]=size
   end
  end
 end
 if style._containFlags or style._contentVisibility then style._usesContainment=true end
 return style
end
function C.state(style,skipped)
 local flags=style._containFlags or NONE
 local cv=style._contentVisibility
 if not cv or cv=='visible'then return flags,false end
 local skip=cv=='hidden'or(cv=='auto'and skipped==true)
 return {layout=true,paint=true,style=true,size=flags.size or skip,inlineSize=flags.inlineSize},skip
end
function C.isolates(style)
 local flags=style._containFlags
 if flags and(flags.layout or flags.paint)then return true end
 local cv=style._contentVisibility
 return cv=='hidden'or cv=='auto'
end
function C.clips(style)
 local flags=style._containFlags
 if flags and flags.paint then return true end
 local cv=style._contentVisibility
 return cv=='hidden'or cv=='auto'
end
function C.intrinsic(style,axis,length,remembered)
 local auto=style._containIntrinsicAuto
 if auto and auto[axis]and remembered and remembered>0 then return remembered end
 local value=style[axisKeys[axis]]
 if value==nil or value=='none'then return 0 end
 return math.max(0,length(value)or 0)
end
function C.uses(style)
 return style.contain~=nil or style['content-visibility']~=nil or style['contain-intrinsic-width']~=nil
  or style['contain-intrinsic-height']~=nil or style['contain-intrinsic-inline-size']~=nil or style['contain-intrinsic-block-size']~=nil
end
function C.install(supports,length)
 supports.register('contain',function(value)C.flags(value);return true end)
 supports.register('content-visibility',function(value)return visibilities[U.trim(value):lower()]==true end)
 local function one(value)
  local text=U.trim(value)
  if text:lower()=='none'then return true end
  local _,size=C.intrinsicValue(text)
  return size:lower()=='none'or length(size)==true
 end
 supports.register('contain-intrinsic-width',one)
 supports.register('contain-intrinsic-height',one)
 supports.register('contain-intrinsic-inline-size',one)
 supports.register('contain-intrinsic-block-size',one)
 supports.register('contain-intrinsic-size',function(value)local a,b=C.expand(value);return one(a)and one(b)end)
end
return C
