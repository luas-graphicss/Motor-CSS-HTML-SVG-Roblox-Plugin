local U=require(script.Parent.Util)
local W={VERSION=1}
W.reserved=table.freeze({auto=true,none=true,initial=true,inherit=true,unset=true,default=true,
 ['revert']=true,['revert-layer']=true,['will-change']=true})
W.accelerated=table.freeze({transform=true,opacity=true,filter=true,['backdrop-filter']=true,
 ['offset-distance']=true,['offset-path']=true,['background']=true,['background-color']=true,
 ['clip-path']=true,perspective=true,rotate=true,scale=true,translate=true})
local cache,slots,cursor={},{},0
local EMPTY=table.freeze({auto=true,features={},properties={},contents=false,scrollPosition=false,count=0})
W.EMPTY=EMPTY
function W.parse(value)
 local text=U.trim(tostring(value or'auto'))
 local key=text:lower()
 if key==''or key=='auto'then return EMPTY end
 local hit=cache[key];if hit then return hit end
 local features,properties={},{}
 local contents,scrollPosition,count=false,false,0
 for _,raw in ipairs(U.split(text,','))do
  local ident=U.trim(raw):lower()
  assert(ident~='','will-change contém um item vazio.')
  assert(ident:match('^%-?%-?[%a][%w%-]*$'),'will-change aceita apenas identificadores: '..ident)
  assert(not W.reserved[ident],'will-change não aceita a palavra reservada '..ident..'.')
  assert(not features[ident],'will-change repetido: '..ident)
  features[ident]=true;count+=1
  assert(count<=32,'will-change aceita no máximo 32 itens.')
  if ident=='contents'then contents=true
  elseif ident=='scroll-position'then scrollPosition=true
  else properties[ident]=true end
 end
 local result=table.freeze({auto=false,features=table.freeze(features),properties=table.freeze(properties),
  contents=contents,scrollPosition=scrollPosition,count=count})
 cursor=cursor%64+1;local old=slots[cursor];if old then cache[old]=nil end
 slots[cursor]=key;cache[key]=result;return result
end
function W.normalize(style)
 local value=style['will-change']
 if value==nil then return style end
 if value=='initial'or value=='unset'or value=='inherit'then value='auto';style['will-change']='auto'end
 local hint=W.parse(value)
 style['will-change']=hint.auto and'auto'or style['will-change']
 if not hint.auto then style._willChange=hint end
 return style
end
function W.hint(style)
 if style==nil then return EMPTY end
 return style._willChange or(style['will-change']and W.parse(style['will-change']))or EMPTY
end
function W.active(style)
 return W.hint(style).auto==false
end
function W.wants(style,property)
 return W.hint(style).properties[property]==true
end
function W.materialize(style)
 local hint=W.hint(style)
 if hint.auto then return false end
 if hint.contents or hint.scrollPosition then return true end
 for property in pairs(hint.properties)do if W.accelerated[property]then return true end end
 return hint.count>0
end
function W.volatileSubtree(style)
 local hint=W.hint(style)
 return hint.contents==true
end
function W.suggestedContainment(style)
 local hint=W.hint(style)
 if hint.auto then return nil end
 if hint.contents then return 'layout paint'end
 if hint.properties.transform or hint.properties.opacity or hint.properties.filter then return 'paint'end
 return nil
end
function W.install(supports)
 supports.register('will-change',function(value)return (pcall(W.parse,value))end)
end
return W
