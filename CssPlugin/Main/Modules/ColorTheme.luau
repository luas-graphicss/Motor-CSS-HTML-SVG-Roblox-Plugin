local Color=require(script.Parent.CssColor)
local T={VERSION=1}
local functions={rgb=true,rgba=true,hsl=true,hsla=true,hwb=true,lab=true,lch=true,oklab=true,oklch=true,color=true,['color-mix']=true,['light-dark']=true}
local fields={color=true,background=true,['background-color']=true,['background-image']=true,['border-color']=true,['outline-color']=true,['column-rule-color']=true,['text-decoration-color']=true,['text-emphasis-color']=true,['text-shadow']=true,['box-shadow']=true,fill=true,stroke=true,['stop-color']=true,['flood-color']=true,['lighting-color']=true,filter=true,['backdrop-filter']=true}
for _,side in ipairs({'top','right','bottom','left'})do fields['border-'..side..'-color']=true end
local function trim(s)return(s:gsub('^%s+',''):gsub('%s+$',''))end
local function used(value,environment)
 local allowed,first={},nil
 for token in value:lower():gmatch('%S+')do
  assert(token=='normal'or token=='only'or token=='light'or token=='dark','color-scheme aceita normal, light, dark e only.')
  assert(not allowed[token],'color-scheme repetido.');allowed[token]=true
  if token=='light'or token=='dark'then first=first or token end
 end
 assert(next(allowed),'color-scheme vazio.');assert(not allowed.normal or not first and not allowed.only,'normal não pode ser combinado em color-scheme.')
 assert(not allowed.only or first,'only exige light ou dark.')
 local preferred=environment and environment.colorScheme or'light'
 return allowed[preferred]and preferred or first or'light'
end
function T.resolve(text,context)
 local out,p={},1
 while p<=#text do
  local ch=text:sub(p,p)
  if ch=='"'or ch=="'"then
   local start=p;local quote=ch;p+=1
   while p<=#text do local c=text:sub(p,p);if c==string.char(92)then p+=2 elseif c==quote then p+=1;break else p+=1 end end
   out[#out+1]=text:sub(start,p-1)
  else
   local name=text:sub(p):match('^[%a][%w%-]*')
   if name then
    local finish=p+#name;local lower=name:lower()
    if text:sub(finish,finish)=='('then
     local q,escaped,depth=nil,false,1;local e=finish+1
     while e<=#text and depth>0 do local c=text:sub(e,e)
      if q then if escaped then escaped=false elseif c==string.char(92)then escaped=true elseif c==q then q=nil end
      elseif c=='"'or c=="'"then q=c elseif c=='('then depth+=1 elseif c==')'then depth-=1 end;e+=1
     end
     assert(depth==0,'Função CSS não fechada durante resolução de cor.')
     local whole=text:sub(p,e-1)
     if functions[lower]then out[#out+1]=Color.serialize(Color.parse(whole,context))
     elseif lower=='url'then out[#out+1]=whole
     else out[#out+1]=name..'('..T.resolve(text:sub(finish+1,e-2),context)..')'end
     p=e
    else out[#out+1]=lower=='currentcolor'and Color.serialize(Color.parse('currentcolor',context))or name;p=finish end
   else out[#out+1]=ch;p+=1 end
  end
 end
 return table.concat(out)
end
function T.normalize(style,parent,environment)
 local scheme=style['color-scheme']or(parent and parent['color-scheme'])or'normal'
 if scheme=='inherit'or scheme=='unset'then scheme=parent and parent['color-scheme']or'normal'elseif scheme=='initial'then scheme='normal'end
 style['color-scheme']=scheme;style._usedColorScheme=used(scheme,environment or style._mediaEnvironment)
 local context={colorScheme=style._usedColorScheme,currentColor=parent and parent.color or'#eaf0fa'}
 local ink=style.color or context.currentColor
 if ink=='inherit'or ink=='unset'then ink=context.currentColor elseif ink=='initial'then ink='#000000'end
 style.color=T.resolve(ink,context);context.currentColor=style.color
 for key in pairs(fields)do
  local value=style[key]
  if key~='color'and type(value)=='string'and(value:find('(',1,true)or value:lower():find('currentcolor',1,true))then style[key]=T.resolve(value,context)end
 end
 return style
end
T.used=used
return T
