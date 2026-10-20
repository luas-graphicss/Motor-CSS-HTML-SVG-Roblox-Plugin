local U=require(script.Parent.Util)
local A={VERSION=1,MAX_FADE=8,MAX_SET=8,MAX_DEPTH=4}
A.keys={'image-rendering','object-fit','object-position','image-orientation','image-resolution'}
A.resample={auto='Default',smooth='Default',['high-quality']='Default',['crisp-edges']='Pixelated',pixelated='Pixelated',optimizespeed='Pixelated',optimizequality='Default'}
A.fits={fill=true,contain=true,cover=true,none=true,['scale-down']=true}
A.maskComposites={add='source-over',subtract='source-out',intersect='source-in',exclude='xor'}
local porter={
 clear=function()return 0,0 end,
 copy=function()return 1,0 end,
 ['source-over']=function(as,ab)return 1,1-as end,
 ['destination-over']=function(as,ab)return 1-ab,1 end,
 ['source-in']=function(as,ab)return ab,0 end,
 ['destination-in']=function(as,ab)return 0,as end,
 ['source-out']=function(as,ab)return 1-ab,0 end,
 ['destination-out']=function(as,ab)return 0,1-as end,
 ['source-atop']=function(as,ab)return ab,1-as end,
 ['destination-atop']=function(as,ab)return 1-ab,as end,
 xor=function(as,ab)return 1-ab,1-as end,
 lighter=function()return 1,1 end,
}
porter.source=porter.copy
porter.over=porter['source-over']
local function finite(n,label)
 assert(n and n==n and math.abs(n)<1e7,(label or 'Valor')..' inválido ou fora do limite.');return n
end
local function unquote(body)
 body=U.trim(body or '');local q=body:sub(1,1)
 if q=='"'or q=="'"then assert(#body>=2 and body:sub(-1)==q,'Aspas incompatíveis em imagem CSS.');body=body:sub(2,-2)end
 return U.trim(body)
end
function A.segments(text,delimiter)
 local out,start,depth,q,escape={},1,0,nil,false
 for i=1,#text do
  local c=text:sub(i,i)
  if q then if escape then escape=false elseif c==string.char(92)then escape=true elseif c==q then q=nil end
  elseif c=='"'or c=="'"then q=c
  elseif c=='('or c=='['then depth+=1
  elseif c==')'or c==']'then depth-=1;assert(depth>=0,'Parêntese inesperado em valor de imagem.')
  elseif depth==0 and c==delimiter then out[#out+1]=U.trim(text:sub(start,i-1));start=i+1 end
 end
 assert(depth==0 and not q,'Função/aspas de imagem não fechadas.');out[#out+1]=U.trim(text:sub(start));return out
end
function A.call(text)
 local name,body=U.trim(text or ''):match('^([%a%-]+)%((.*)%)$')
 if not name then return nil end
 return name:lower(),U.trim(body)
end
function A.porter(op)
 local key=U.trim(tostring(op or ''):lower());key=A.maskComposites[key]or key
 return assert(porter[key],'Operador de composição não suportado: '..key),key
end
function A.composite(op)
 local fn=A.porter(op)
 return function(source,backdrop,as,ab)
  local fa,fb=fn(as or 0,ab or 0)
  return source*fa+backdrop*fb
 end
end
function A.angle(text)
 text=U.trim(text or '')
 if text==''or text=='0'then return 0 end
 local n,unit=text:match('^([+%-%.%deE]+)(%a+)$');n=finite(tonumber(n),'Ângulo')
 if unit=='deg'then return math.rad(n)elseif unit=='rad'then return n
 elseif unit=='turn'then return n*2*math.pi elseif unit=='grad'then return n*math.pi/200 end
 error('Ângulo exige deg, rad, grad ou turn.',0)
end
function A.rendering(value)
 local key=U.trim(tostring(value or 'auto'):lower())
 return assert(A.resample[key],'image-rendering inválido: '..key),key
end
local function isEdgeX(t)return t=='left'or t=='right'end
local function isEdgeY(t)return t=='top'or t=='bottom'end
local function axisValue(token,axis)
 local t=token:lower()
 if t=='center'then return {edge=axis=='x'and 'left'or 'top',offset='50%'}end
 if axis=='x'and isEdgeX(t)then return {edge=t,offset='0%'}end
 if axis=='y'and isEdgeY(t)then return {edge=t,offset='0%'}end
 assert(not isEdgeX(t)and not isEdgeY(t),'Palavra-chave de eixo trocada em object-position: '..t)
 return {edge=axis=='x'and 'left'or 'top',offset=token}
end
function A.position(value)
 local tokens=U.split(U.trim(tostring(value or '50% 50%')),' ')
 assert(#tokens>=1 and #tokens<=4,'object-position aceita 1 a 4 componentes.')
 for _,t in ipairs(tokens)do assert(t~='','Componente vazio em object-position.')end
 if #tokens<=2 then
  local a=tokens[1]:lower()
  if #tokens==1 then
   if isEdgeY(a)then return {x={edge='left',offset='50%'},y={edge=a,offset='0%'}}end
   return {x=axisValue(tokens[1],'x'),y={edge='top',offset='50%'}}
  end
  local b=tokens[2]:lower()
  if(isEdgeY(a)and(isEdgeX(b)or b=='center'))or(a=='center'and isEdgeX(b))then tokens[1],tokens[2]=tokens[2],tokens[1]end
  return {x=axisValue(tokens[1],'x'),y=axisValue(tokens[2],'y')}
 end
 local parts,i={},1
 while i<=#tokens do
  local t=tokens[i]:lower()
  assert(isEdgeX(t)or isEdgeY(t)or t=='center','object-position com 3 ou 4 componentes exige palavras-chave de borda.')
  local offset=t=='center'and '50%'or '0%'
  local following=tokens[i+1]and tokens[i+1]:lower()
  if following and not(isEdgeX(following)or isEdgeY(following)or following=='center')then
   assert(t~='center','center não aceita deslocamento em object-position.')
   offset=tokens[i+1];i+=1
  end
  parts[#parts+1]={kw=t,offset=offset};i+=1
 end
 assert(#parts==2,'object-position: use um componente horizontal e um vertical.')
 local x,y
 for _,part in ipairs(parts)do
  if isEdgeX(part.kw)then assert(not x,'object-position com dois componentes horizontais.');x={edge=part.kw,offset=part.offset}
  elseif isEdgeY(part.kw)then assert(not y,'object-position com dois componentes verticais.');y={edge=part.kw,offset=part.offset}end
 end
 for _,part in ipairs(parts)do
  if part.kw=='center'then
   if not x then x={edge='left',offset=part.offset}elseif not y then y={edge='top',offset=part.offset}end
  end
 end
 assert(x and y,'object-position exige um componente horizontal e um vertical.')
 return {x=x,y=y}
end
function A.resolvePosition(parsed,area,size,length)
 assert(type(length)=='function','A resolução de comprimento é obrigatória.')
 local free={x=(area.w or 0)-(size.w or 0),y=(area.h or 0)-(size.h or 0)}
 local out={}
 for _,axis in ipairs({'x','y'})do
  local part=parsed[axis];local base=free[axis]
  local n=finite(length(part.offset,base),'Deslocamento de object-position')
  if part.edge=='right'or part.edge=='bottom'then n=base-n end
  out[axis]=n
 end
 return out.x,out.y
end
function A.objectBox(fit,position,area,natural,length)
 local key=U.trim(tostring(fit or 'fill'):lower());assert(A.fits[key],'object-fit inválido: '..key)
 local aw,ah=area.w or 0,area.h or 0
 local nw,nh=natural and natural.w,natural and natural.h
 local w,h
 if not nw or not nh or nw<=0 or nh<=0 then w,h=aw,ah
 elseif key=='fill'then w,h=aw,ah
 elseif key=='none'then w,h=nw,nh
 else
  local scale
  if key=='contain'then scale=math.min(aw/nw,ah/nh)
  elseif key=='cover'then scale=math.max(aw/nw,ah/nh)
  else scale=math.min(1,math.min(aw/nw,ah/nh))end
  w,h=nw*scale,nh*scale
 end
 local x,y=A.resolvePosition(A.position(position or '50% 50%'),{w=aw,h=ah},{w=w,h=h},length)
 return {x=x,y=y,w=w,h=h,fit=key}
end
function A.orientation(value)
 local text=U.trim(tostring(value or 'from-image'):lower())
 if text=='none'then return {angle=0,flip=false,fromImage=false}end
 if text=='from-image'then return {angle=0,flip=false,fromImage=true}end
 local angle,flip
 for _,token in ipairs(U.split(text,' '))do
  if token=='flip'then assert(not flip,'image-orientation aceita um flip.');flip=true
  else assert(not angle,'image-orientation aceita um ângulo.');angle=A.angle(token)end
 end
 assert(angle or flip,'image-orientation exige ângulo e/ou flip.')
 local quarter=math.pi/2
 angle=(math.round((angle or 0)/quarter)%4)*quarter
 return {angle=angle,flip=flip==true,fromImage=false}
end
local resolutionUnits={dppx=1,x=1,dpi=1/96,dpcm=2.54/96}
function A.resolutionValue(text)
 local n,unit=U.trim(text):lower():match('^([+%-%.%deE]+)(%a+)$')
 n=finite(tonumber(n),'Resolução');assert(n>0,'Resolução exige valor positivo.')
 local factor=resolutionUnits[unit or ''];assert(factor,'Resolução exige dpi, dpcm, dppx ou x.')
 return n*factor
end
function A.resolution(value)
 local text=U.trim(tostring(value or 'from-image'):lower());assert(text~='','image-resolution vazio.')
 local fromImage,snap,dppx=false,false,nil
 for _,token in ipairs(U.split(text,' '))do
  if token=='from-image'then assert(not fromImage,'image-resolution aceita um from-image.');fromImage=true
  elseif token=='snap'then assert(not snap,'image-resolution aceita um snap.');snap=true
  else assert(not dppx,'image-resolution aceita uma resolução.');dppx=A.resolutionValue(token)end
 end
 assert(fromImage or dppx,'image-resolution exige from-image ou uma resolução.')
 return {fromImage=fromImage,snap=snap,dppx=dppx or 1}
end
function A.isImage(text)
 text=U.trim(tostring(text or ''))
 if text=='none'then return true end
 local name=A.call(text)
 if not name then return false end
 return name=='url'or name:match('gradient$')~=nil or name=='image'or name=='cross-fade'or name=='element'or name=='image-set'
end
function A.assetSource(text)
 local name,body=A.call(text)
 assert(name=='url','Esperado url(...) na imagem CSS.')
 local value=unquote(body)
 assert(value:match('^rbxassetid://%d+$')or value:match('^rbxasset://[%w_./%-]+$')or value:match('^#[%w_%-]+$')or value:match('^data:image/svg%+xml[;,]'),
  'Imagem CSS exige asset Roblox, SVG local #id ou data:image/svg+xml; HTTP não é carregado.')
 return value
end
function A.parseImage(text,depth)
 depth=(depth or 0)+1;assert(depth<=A.MAX_DEPTH,'Funções de imagem aninhadas demais.')
 text=U.trim(tostring(text or ''))
 if text=='none'then return {kind='none'}end
 local name,body=A.call(text)
 assert(name,'Valor de imagem inválido: '..text:sub(1,40))
 if name=='url'then return {kind='asset',source=A.assetSource(text)}end
 if name:match('gradient$')then return {kind='gradient',value=text}end
 if name=='element'then
  local id=unquote(body)
  assert(id:match('^#[%w_%-]+$'),'element() exige um id local, por exemplo element(#cartao).')
  return {kind='element',source=id}
 end
 if name=='image'then
  local source,fallback,direction
  for _,part in ipairs(A.segments(body,','))do
   if part~=''then
    local tag,rest=part:match('^(%a+)%s+(.+)$')
    if tag and(tag:lower()=='ltr'or tag:lower()=='rtl')then
     assert(not direction,'image() aceita uma direção.');direction=tag:lower();part=rest
    end
    local lower=part:lower()
    if lower=='ltr'or lower=='rtl'then assert(not direction,'image() aceita uma direção.');direction=lower
    elseif A.isImage(part)then assert(not source,'image() aceita uma fonte.');source=A.parseImage(part,depth)
    else assert(not fallback,'image() aceita uma cor de fallback.');U.color(part);fallback=part end
   end
  end
  assert(source or fallback,'image() exige uma fonte ou uma cor.')
  return {kind='image',source=source,fallback=fallback,direction=direction}
 end
 if name=='cross-fade'then
  local parts=A.segments(body,',')
  assert(#parts>=2 and #parts<=A.MAX_FADE,'cross-fade() aceita de 2 a 8 imagens.')
  local layers,sum,explicit={},0,0
  for _,part in ipairs(parts)do
   local percent,image
   for _,token in ipairs(U.split(part,' '))do
    if token:sub(-1)=='%'then
     assert(not percent,'cross-fade() aceita uma porcentagem por imagem.')
     percent=finite(tonumber(token:sub(1,-2)),'Porcentagem de cross-fade')
     assert(percent>=0 and percent<=100,'cross-fade() aceita 0% a 100%.')
    else assert(not image,'cross-fade() aceita uma imagem por camada.');image=A.parseImage(token,depth)end
   end
   assert(image,'cross-fade() exige uma imagem em cada camada.')
   if percent then sum+=percent;explicit+=1 end
   layers[#layers+1]={percent=percent,image=image}
  end
  assert(sum<=100.001,'Soma das porcentagens de cross-fade() excede 100%.')
  local missing=#layers-explicit
  for _,layer in ipairs(layers)do
   if not layer.percent then layer.percent=missing>0 and(100-sum)/missing or 0 end
  end
  return {kind='cross-fade',layers=layers}
 end
 if name=='image-set'then
  local parts=A.segments(body,',')
  assert(#parts>=1 and #parts<=A.MAX_SET,'image-set() aceita de 1 a 8 opções.')
  local options={}
  for _,part in ipairs(parts)do
   local image,dppx,mime
   for _,token in ipairs(U.split(part,' '))do
    local lower=token:lower()
    if lower:match('^[+%-%.%deE]+%a+$')and resolutionUnits[lower:match('%a+$')]then
     assert(not dppx,'image-set() aceita uma resolução por opção.');dppx=A.resolutionValue(lower)
    elseif lower:sub(1,5)=='type('then
     assert(not mime,'image-set() aceita um type() por opção.')
     mime=unquote(token:match('^[Tt][Yy][Pp][Ee]%((.*)%)$')or '');assert(mime~='','type() vazio em image-set().')
    else assert(not image,'image-set() aceita uma imagem por opção.');image=A.parseImage(token,depth)end
   end
   assert(image,'image-set() exige uma imagem em cada opção.')
   options[#options+1]={image=image,dppx=dppx or 1,type=mime}
  end
  return {kind='image-set',options=options}
 end
 error('Função de imagem não suportada: '..name..'()',0)
end
function A.select(descriptor,dppx)
 if type(descriptor)~='table'or descriptor.kind~='image-set'then return descriptor end
 local target=dppx or 1;local best
 for _,option in ipairs(descriptor.options)do
  if option.dppx>=target and(not best or option.dppx<best.dppx)then best=option end
 end
 if not best then for _,option in ipairs(descriptor.options)do if not best or option.dppx>best.dppx then best=option end end end
 return best and best.image or {kind='none'}
end
function A.sources(descriptor,out)
 out=out or {}
 if type(descriptor)~='table'then return out end
 if descriptor.kind=='asset'or descriptor.kind=='element'then out[#out+1]=descriptor.source
 elseif descriptor.kind=='image'then A.sources(descriptor.source,out)
 elseif descriptor.kind=='cross-fade'then for _,layer in ipairs(descriptor.layers)do A.sources(layer.image,out)end
 elseif descriptor.kind=='image-set'then for _,option in ipairs(descriptor.options)do A.sources(option.image,out)end end
 return out
end
function A.filterReference(text)
 local name,body=A.call(text)
 if name~='url'then return nil end
 local value=unquote(body)
 assert(value:match('^#[%w_%-]+$'),'filter: url() exige a referência local #id de um <filter> SVG.')
 return value
end
function A.register(supported,shorthands)
 for _,key in ipairs(A.keys)do supported[key]=true end
 return supported
end
function A.validate(style)
 if style['image-rendering']~=nil then A.rendering(style['image-rendering'])end
 if style['object-fit']~=nil then
  local key=U.trim(tostring(style['object-fit']):lower());assert(A.fits[key],'object-fit inválido: '..key)
 end
 if style['object-position']~=nil then A.position(style['object-position'])end
 if style['image-orientation']~=nil then A.orientation(style['image-orientation'])end
 if style['image-resolution']~=nil then A.resolution(style['image-resolution'])end
 return style
end
function A.install(supports)
 supports.register('image-rendering',function(value)return A.resample[U.trim(value:lower())]~=nil end)
 supports.register('object-fit',function(value)return A.fits[U.trim(value:lower())]==true end)
 supports.register('object-position',function(value)return(pcall(A.position,value))end)
 supports.register('image-orientation',function(value)return(pcall(A.orientation,value))end)
 supports.register('image-resolution',function(value)return(pcall(A.resolution,value))end)
end
function A.plan(style,context)
 style=style or {};context=context or {}
 local resample=A.rendering(style['image-rendering']or 'auto')
 return {
  resample=resample,
  fit=U.trim(tostring(style['object-fit']or 'fill'):lower()),
  position=A.position(style['object-position']or '50% 50%'),
  orientation=A.orientation(style['image-orientation']or 'from-image'),
  resolution=A.resolution(style['image-resolution']or 'from-image'),
 }
end
return A
