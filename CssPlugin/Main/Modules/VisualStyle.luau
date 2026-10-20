local U=require(script.Parent.Util)
local Cost=require(script.Parent.CostModel)
local V={VERSION=1,MAX_LAYERS=8}
V.radiusKeys={'border-top-left-radius','border-top-right-radius','border-bottom-right-radius','border-bottom-left-radius'}
V.borderStyles={none=true,hidden=true,solid=true,dashed=true,dotted=true,double=true,groove=true,ridge=true,inset=true,outset=true}
V.widthNames={thin='1px',medium='3px',thick='5px'}
V.outlineKeys={'outline-width','outline-style','outline-color','outline-offset'}
V.outlineShorthandKeys={'outline-width','outline-style','outline-color'}
V.outlineStyles={none=true,hidden=true,auto=true,solid=true,dashed=true,dotted=true,double=true,groove=true,ridge=true,inset=true,outset=true}
V.backgroundKeys={'background','background-image','background-position','background-size','background-repeat','background-attachment','background-origin','background-clip'}
V.imageKeys={'border-image-source','border-image-slice','border-image-width','border-image-outset','border-image-repeat'}
local repeats={['repeat']=true,['no-repeat']=true,['repeat-x']=true,['repeat-y']=true,round=true,space=true}
local attachments={scroll=true,fixed=true,['local']=true}
local boxes={['border-box']=true,['padding-box']=true,['content-box']=true}
local clipBoxes={['border-box']=true,['padding-box']=true,['content-box']=true,text=true}
V.clipBoxes=clipBoxes
local mathFunctions={calc=true,clamp=true,min=true,max=true,var=true,round=true,mod=true,rem=true,abs=true,sign=true,attr=true,env=true}
local imageRepeats={stretch=true,['repeat']=true,round=true,space=true}
function V.segments(text,delimiter)
 local out,start,level,q,escaped={},1,0,nil,false
 for i=1,#text do
  local c=text:sub(i,i)
  if q then if escaped then escaped=false elseif c==string.char(92)then escaped=true elseif c==q then q=nil end
  elseif c=='"'or c=="'"then q=c
  elseif c=='('or c=='['then level+=1
  elseif c==')'or c==']'then level-=1;assert(level>=0,'Delimitador CSS inesperado.')
  elseif level==0 and c==delimiter then out[#out+1]=U.trim(text:sub(start,i-1));start=i+1 end
 end
 assert(not q and level==0,'Função/aspas CSS não fechadas.');out[#out+1]=U.trim(text:sub(start));return out
end
function V.four(words,label)
 if type(words)=='string'then words=U.split(words,' ')end
 assert(#words>=1 and #words<=4,(label or 'Valor')..' aceita 1 a 4 componentes.')
 return {words[1],words[2]or words[1],words[3]or words[1],words[4]or words[2]or words[1]}
end
V.imageFunctions={['cross-fade']=true,element=true,image=true,['image-set']=true}
function V.isImage(text)
 if text=='none'or text:match('^url%(')~=nil or text:match('^[%a%-]+gradient%(')~=nil then return true end
 local name=text:match('^([%a%-]+)%(')
 return name~=nil and V.imageFunctions[name:lower()]==true
end
function V.source(text)
 local body=text:match('^url%((.*)%)$');assert(body,'Use url("rbxassetid://ID") para imagens.')
 body=U.trim(body)
 local q=body:sub(1,1)
 if q=='"'or q=="'"then assert(body:sub(-1)==q,'URL com aspas incompatíveis.');body=body:sub(2,-2)end
 assert(body:match('^rbxassetid://%d+$')or body:match('^rbxasset://[%w_./%-]+$'),'Imagem CSS exige asset Roblox (rbxassetid://ID ou rbxasset://); URLs HTTP/data não são imagens nativas.')
 return body
end
function V.color(value,current)
 if (value or ''):lower()=='currentcolor'then return U.color(current or '#ffffff')end
 return U.color(value)
end
local function colorish(token)
 if token==nil or token==''then return false end
 local lower=token:lower()
 if lower=='currentcolor'then return true end
 if token:match('^[+%-%.%d]')then return false end
 local name=lower:match('^([%a%-]+)%(')
 if name and mathFunctions[name]then return false end
 return (pcall(U.color,token))
end
V.colorish=colorish
function V.shadow(text)
 local inset=false;local ink;local lengths={}
 for _,token in ipairs(U.split(text,' '))do
  if token:lower()=='inset'then assert(not inset,'box-shadow: inset repetido.');inset=true
  elseif colorish(token)then assert(not ink,'box-shadow aceita uma cor por sombra.');ink=token
  else lengths[#lengths+1]=token end
 end
 assert(#lengths>=2 and #lengths<=4,'box-shadow: [inset] x y [blur] [spread] [cor].')
 return {inset=inset,color=ink,lengths=lengths}
end
function V.shadows(value)
 local out={}
 if value==nil or value=='none'or value==''then return out end
 for _,text in ipairs(V.segments(value,','))do
  assert(text~='','Sombra vazia em box-shadow.')
  out[#out+1]=V.shadow(text)
 end
 Cost.cap('shadows',#out,'Sombras por elemento')
 return out
end
local function background(value)
 local out={background='transparent'};local fields={}
 for _,key in ipairs(V.backgroundKeys)do if key~='background'then fields[key]={}end end
 local layers=V.segments(value,',');Cost.cap('layers',#layers,'Camadas de background')
 for index,text in ipairs(layers)do
  assert(text~='','Camada de background vazia.')
  local sides=V.segments(text,'/');assert(#sides<=2,'background aceita uma barra posição/tamanho por camada.')
  local layer={['background-image']='none',['background-position']='0% 0%',['background-size']='auto auto',['background-repeat']='repeat',['background-attachment']='scroll',['background-origin']='padding-box',['background-clip']='border-box'}
  local position,size,rep,box={}, {},{},{};local imageSeen,colorSeen,attachmentSeen=false,false,false
  local textClip=false
  for side,part in ipairs(sides)do
   for _,token in ipairs(U.split(part,' '))do
    if V.isImage(token)then
     assert(not imageSeen,'Uma imagem por camada; separe backgrounds por vírgulas.');imageSeen=true
     if token:match('^url%(')then V.source(token)end
     layer['background-image']=token
    elseif repeats[token]then rep[#rep+1]=token
    elseif attachments[token]then assert(not attachmentSeen,'Attachment repetido.');attachmentSeen=true;layer['background-attachment']=token
    elseif boxes[token]then box[#box+1]=token
    elseif token=='text'then assert(not textClip,'background-clip: text repetido.');textClip=true
    else
     local isColor=token:lower()=='currentcolor'or pcall(U.color,token)
     if isColor then assert(index==#layers and not colorSeen,'A cor de fundo só pode aparecer uma vez, na última camada.');colorSeen=true;out.background=token
     elseif side==2 then size[#size+1]=token else position[#position+1]=token end
    end
   end
  end
  assert(#rep<=2 and #box<=2 and #position<=4 and #size<=2,'Componentes demais no background.')
  if #sides==2 then assert(#position>0 and #size>0,'Use background-position / background-size.')end
  if #position>0 then layer['background-position']=table.concat(position,' ')end
  if #size>0 then layer['background-size']=table.concat(size,' ')end
  if #rep>0 then layer['background-repeat']=table.concat(rep,' ')end
  if #box>0 then layer['background-origin']=box[1];layer['background-clip']=box[2]or box[1]end
  if textClip then layer['background-clip']='text'end
  for key,list in pairs(fields)do list[#list+1]=layer[key]end
 end
 for key,list in pairs(fields)do out[key]=table.concat(list,', ')end
 return out
end
local function radius(value)
 local parts=V.segments(value,'/');assert(#parts<=2,'border-radius aceita uma barra horizontal/vertical.')
 local x=V.four(parts[1],'border-radius');local y=parts[2]and V.four(parts[2],'border-radius')or x
 local out={};for i,key in ipairs(V.radiusKeys)do out[key]=x[i]==y[i]and x[i]or(x[i]..' '..y[i])end;return out
end
local function borderImage(value)
 local parts=V.segments(value,'/');assert(#parts<=3,'border-image: source slice / width / outset repeat.')
 local source,repeatTokens='none',{};local seen=false;local slices,width,outset={}, {},{}
 for section,part in ipairs(parts)do
  for _,token in ipairs(U.split(part,' '))do
   if V.isImage(token)then assert(section==1 and not seen,'Fonte border-image repetida.');seen=true;source=token;if token:match('^url%(')then V.source(token)end
   elseif imageRepeats[token]then repeatTokens[#repeatTokens+1]=token
   elseif section==1 then slices[#slices+1]=token elseif section==2 then width[#width+1]=token else outset[#outset+1]=token end
  end
 end
 assert(#repeatTokens<=2,'border-image-repeat aceita 1 ou 2 valores.')
 if #slices==0 then slices={'100%'}end
 return {['border-image-source']=source,['border-image-slice']=table.concat(slices,' '),['border-image-width']=#width>0 and table.concat(width,' ')or '1',['border-image-outset']=#outset>0 and table.concat(outset,' ')or '0',['border-image-repeat']=#repeatTokens>0 and table.concat(repeatTokens,' ')or 'stretch'}
end
local function border(value)
 local out={['border-width']='3px',['border-style']='none',['border-color']='currentColor'};local seen={}
 for _,token in ipairs(U.split(value,' '))do
  local key
  if V.borderStyles[token]then key='border-style'
  elseif V.widthNames[token]or token:match('^[+%-%.%d]')or token:match('^calc%(')or token:match('^clamp%(')then key='border-width';token=V.widthNames[token]or token
  else key='border-color';V.color(token,'white')end
  assert(not seen[key],'Componente repetido em border.');seen[key]=true;out[key]=token
 end
 if value=='0'then out['border-style']='none'end
 for k,v in pairs(borderImage('none'))do out[k]=v end
 return out
end
local function outline(value)
 local out={['outline-width']='3px',['outline-style']='none',['outline-color']='currentColor'};local seen={}
 for _,token in ipairs(U.split(value,' '))do
  local key
  if V.outlineStyles[token]then key='outline-style'
  elseif V.widthNames[token]or token:match('^[+%-%.%d]')or token:match('^calc%(')or token:match('^clamp%(')then key='outline-width';token=V.widthNames[token]or token
  else key='outline-color';if token~='invert'then V.color(token,'white')end end
  assert(not seen[key],'Componente repetido em outline.');seen[key]=true;out[key]=token
 end
 if value=='0'then out['outline-style']='none'end
 return out
end
function V.register(supported,shorthands)
 for _,k in ipairs(V.backgroundKeys)do supported[k]=true end
 for _,k in ipairs(V.imageKeys)do supported[k]=true end
 shorthands.background=V.backgroundKeys;shorthands['border-radius']=V.radiusKeys;shorthands['border-image']=V.imageKeys
 local keys={'border-width','border-style','border-color'};for _,key in ipairs(V.imageKeys)do keys[#keys+1]=key end;shorthands.border=keys
 supported['border-image']=true
 for _,k in ipairs(V.outlineKeys)do supported[k]=true end
 shorthands.outline=V.outlineShorthandKeys;supported.outline=true
end
function V.expand(name,value)
 if name=='background'then return background(value)elseif name=='border-radius'then return radius(value)elseif name=='border-image'then return borderImage(value)elseif name=='border'then return border(value)elseif name=='outline'then return outline(value)end
 return nil
end
function V.layers(style)
 local source=style['background-image'];local color=style.background or style['background-color']or 'transparent';local legacy
 if source==nil and V.isImage(color)then legacy=background(color);source=legacy['background-image'];color=legacy.background end
 if V.isImage(color)then color='transparent'end
 local sources=V.segments(source or 'none',',');Cost.cap('layers',#sources,'Backgrounds')
 local lists={};local defaults={position='0% 0%',size='auto auto',['repeat']='repeat',attachment='scroll',origin='padding-box',clip='border-box'}
 for k,default in pairs(defaults)do lists[k]=V.segments(style['background-'..k]or(legacy and legacy['background-'..k])or default,',');assert(#lists[k]>=1 and #lists[k]<=32,'Lista background inválida.')end
 local result={}
 for i,image in ipairs(sources)do
  assert(image~=''and V.isImage(image),'background-image exige url(), gradiente ou none.')
  local layer={image=image,index=i};for key,list in pairs(lists)do layer[key]=list[(i-1)%#list+1]end
  assert(attachments[layer.attachment]and boxes[layer.origin]and clipBoxes[layer.clip],'Attachment/origin/clip não suportado.')
  result[i]=layer
 end
 return result,color
end
function V.legacyBackground(style)
 local layers,color=V.layers(style)
 if #layers==1 and layers[1].image~='none'then return layers[1].image end
 return color
end
return V
