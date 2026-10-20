local U=require(script.Parent.Util)
local Cost=require(script.Parent.CostModel)
local Geometry=require(script.Parent.VisualGeometry)
local E={VERSION=2}
E.keys={'filter','backdrop-filter','-webkit-backdrop-filter','clip-path','mask','mask-image','mask-mode','mask-position','mask-size','mask-repeat','mask-composite','mask-origin','mask-clip','mix-blend-mode','background-blend-mode','isolation','-roblox-backdrop-scope','-roblox-backdrop-color'}
E.maskKeys={'mask-image','mask-mode','mask-position','mask-size','mask-repeat','mask-composite','mask-origin','mask-clip'}
E.blends={normal=true,multiply=true,screen=true,overlay=true,darken=true,lighten=true,['color-dodge']=true,['color-burn']=true,['hard-light']=true,['soft-light']=true,difference=true,exclusion=true,hue=true,saturation=true,color=true,luminosity=true}
E.scopes={document=1,interface=2,screen=3,world=4}
local ratioFilters={brightness=true,contrast=true,grayscale=true,sepia=true,invert=true,saturate=true,opacity=true}
local limited={grayscale=true,sepia=true,invert=true,opacity=true}
local function finite(n,label)
 assert(n and n==n and math.abs(n)<1e7,(label or 'Valor')..' inválido ou fora do limite.');return n
end
function E.segments(text,separator)
 local out,start,depth,q,escape={},1,0,nil,false
 for i=1,#text do
  local c=text:sub(i,i)
  if q then if escape then escape=false elseif c==string.char(92)then escape=true elseif c==q then q=nil end
  elseif c=='"'or c=="'"then q=c
  elseif c=='('then depth+=1 elseif c==')'then depth-=1;assert(depth>=0,'Parêntese inesperado em efeito CSS.')
  elseif depth==0 and c==separator then out[#out+1]=U.trim(text:sub(start,i-1));start=i+1 end
 end
 assert(depth==0 and not q,'Função/aspas de efeito CSS não fechadas.');out[#out+1]=U.trim(text:sub(start));return out
end
function E.functions(value)
 value=U.trim(value or 'none');if value=='none'then return {}end
 Cost.cap('bytes',#value,'Lista de filtros')
 local result,i={},1
 while i<=#value do
  local whitespace=value:sub(i):match('^%s*');i+=#whitespace;if i>#value then break end
  local name=value:sub(i):match('^([%a%-]+)%(');assert(name,'Esperada função CSS perto de '..value:sub(i,i+24))
  i+=#name+1;local start=i;local depth,q,escape=1,nil,false
  while i<=#value and depth>0 do
   local c=value:sub(i,i)
   if q then if escape then escape=false elseif c==string.char(92)then escape=true elseif c==q then q=nil end
   elseif c=='"'or c=="'"then q=c elseif c=='('then depth+=1 elseif c==')'then depth-=1 end;i+=1
  end
  assert(depth==0 and not q,'Filtro não fechado: '..name)
  result[#result+1]={name=name:lower(),body=U.trim(value:sub(start,i-2))};Cost.cap('filters',#result,'Filtros encadeados')
 end
 assert(#result>0,'Lista de filtros vazia.');return result
end
function E.length(text,base,c)
 return finite(Geometry.length(text,base or 0,c or {}),'Comprimento de efeito')
end
function E.angle(text)
 if text==''or text=='0'then return 0 end
 local n,unit=text:match('^([+%-%.%deE]+)(%a+)$');n=finite(tonumber(n),'Ângulo')
 if unit=='deg'then return math.rad(n)elseif unit=='rad'then return n elseif unit=='turn'then return n*2*math.pi elseif unit=='grad'then return n*math.pi/200 end
 error('hue-rotate exige deg, rad, grad ou turn.',0)
end
local function ratio(body,name)
 if body==''then return 1 end
 local pct=body:sub(-1)=='%';local n=finite(tonumber(pct and body:sub(1,-2)or body),name)/(pct and 100 or 1)
 assert(n>=0,name..' não aceita valor negativo.');return limited[name]and math.min(n,1)or n
end
function E.filters(value,context)
 local out={};context=context or {}
 for _,fn in ipairs(E.functions(value))do
  local name,body=fn.name,fn.body;local f={name=name}
  if ratioFilters[name]then f.value=ratio(body,name)
  elseif name=='hue-rotate'then f.value=E.angle(body)
  elseif name=='blur'then
   body=body==''and '0'or body;assert(not body:find('%%'),'blur não aceita porcentagem.');f.value=E.length(body,0,context);assert(f.value>=0 and f.value<=1000,'blur aceita 0 a 1000px.')
  elseif name=='drop-shadow'then
   local lengths={};local ink
   for _,token in ipairs(U.split(body,' '))do
    local isColor=token:lower()=='currentcolor'or pcall(U.color,token)
    if isColor then assert(not ink,'drop-shadow aceita uma cor.');ink=token else lengths[#lengths+1]=token end
   end
   assert(#lengths==2 or #lengths==3,'drop-shadow: x y [blur] [cor]; spread/inset não são válidos.')
   for _,v in ipairs(lengths)do assert(not v:find('%%'),'drop-shadow não aceita porcentagem.')end
   f.x=E.length(lengths[1],0,context);f.y=E.length(lengths[2],0,context);f.blur=lengths[3]and E.length(lengths[3],0,context)or 0
   assert(f.blur>=0 and f.blur<=1000,'Blur de drop-shadow fora do limite.');f.ink=ink or context.color or '#ffffff'
   if f.ink:lower()=='currentcolor'then f.ink=context.color or '#ffffff'end
  elseif name=='url'then f.reference=require(script.Parent.AdvancedImaging).filterReference('url('..body..')')
  else error('Filtro não suportado: '..name,0)end
  out[#out+1]=f
 end
 return out
end
function E.blendList(value)
 local out=E.segments(value or 'normal',',');Cost.cap('layers',#out,'Modos de mistura de fundo')
 for _,v in ipairs(out)do assert(E.blends[v],'Blend mode não suportado: '..v)end;return out
end
function E.url(text)
 local value=assert(text:match('^url%((.*)%)$'),'Máscara exige url().');value=U.trim(value)
 local q=value:sub(1,1);if q=='"'or q=="'"then assert(value:sub(-1)==q,'Aspas incompatíveis na máscara.');value=value:sub(2,-2)end
 assert(value:match('^rbxassetid://%d+$')or value:match('^rbxasset://[%w_./%-]+$')or value:match('^#[%w_%-]+$')or value:match('^data:image/svg%+xml[;,]'),'Máscara exige asset Roblox, SVG local #id ou data:image/svg+xml; HTTP não é carregado.')
 assert(#value<=60000,'SVG de máscara excede 60 KB.');return value
end
local boxes={['border-box']=true,['padding-box']=true,['content-box']=true}
function E.expand(name,value)
 if name~='mask'then return nil end
 local sources,positions,sizes,repeats,modes,composites,origins,clips={},{},{},{},{},{},{},{}
 local layers=E.segments(value,',');Cost.cap('layers',#layers,'Camadas de máscara')
 for _,text in ipairs(layers)do
  local image,mode,composite='none','match-source','add';local rep,box,pos,size={},{},{},{}
  local parts=E.segments(text,'/');assert(#parts<=2,'mask aceita uma barra posição/tamanho.')
  local seenImage=false
  for side,part in ipairs(parts)do for _,t in ipairs(U.split(part,' '))do
   if t=='none'or t:match('^url%(')or t:find('gradient(',1,true)then assert(not seenImage,'Use vírgula entre máscaras.');seenImage=true;image=t;if t:match('^url%(')then E.url(t)end
   elseif t=='alpha'or t=='luminance'or t=='match-source'then mode=t
   elseif t=='add'or t=='subtract'or t=='intersect'or t=='exclude'then composite=t
   elseif t=='repeat'or t=='no-repeat'or t=='repeat-x'or t=='repeat-y'or t=='space'or t=='round'then rep[#rep+1]=t
   elseif boxes[t]or t=='no-clip'then box[#box+1]=t
   elseif side==1 then pos[#pos+1]=t else size[#size+1]=t end
  end end
  assert(#rep<=2 and #box<=2 and #pos<=4 and #size<=2,'Componentes demais na máscara.')
  assert(#parts==1 or(#pos>0 and #size>0),'mask: posição / tamanho incompleta.')
  sources[#sources+1]=image;positions[#positions+1]=#pos>0 and table.concat(pos,' ')or '0% 0%';sizes[#sizes+1]=#size>0 and table.concat(size,' ')or 'auto auto'
  repeats[#repeats+1]=#rep>0 and table.concat(rep,' ')or 'repeat';modes[#modes+1]=mode;composites[#composites+1]=composite
  assert(box[1]~='no-clip'or #box==1,'no-clip não pode ser origem.')
  origins[#origins+1]=box[1]~='no-clip'and(box[1]or 'border-box')or 'border-box';clips[#clips+1]=box[2]or box[1]or 'border-box'
 end
 return {['mask-image']=table.concat(sources,', '),['mask-position']=table.concat(positions,', '),['mask-size']=table.concat(sizes,', '),['mask-repeat']=table.concat(repeats,', '),['mask-mode']=table.concat(modes,', '),['mask-composite']=table.concat(composites,', '),['mask-origin']=table.concat(origins,', '),['mask-clip']=table.concat(clips,', ')}
end
function E.register(supported,shorthands)
 for _,key in ipairs(E.keys)do supported[key]=true end
 if shorthands then shorthands.mask=E.maskKeys end
end
function E.needsSurface(s)
 for _,key in ipairs({'filter','clip-path','mask','mask-image'})do if s[key]and s[key]~='none'then return true end end
 local backdrop=s['backdrop-filter']or s['-webkit-backdrop-filter']
 if backdrop and backdrop~='none'then return true end
 if s['mix-blend-mode']and s['mix-blend-mode']~='normal'then return true end
 if s['background-blend-mode']then for _,mode in ipairs(E.blendList(s['background-blend-mode']))do if mode~='normal'then return true end end end
 return false
end
function E.active(s)return s.isolation=='isolate'or E.needsSurface(s)end
function E.scope(value)
 value=U.trim(value or 'document')
 assert(E.scopes[value],'-roblox-backdrop-scope aceita document, interface, screen ou world.')
 return value
end
function E.plan(s,c)
 c=table.clone(c or {});c.color=s.color or '#ffffff'
 local isolation=s.isolation or 'auto';assert(isolation=='auto'or isolation=='isolate','isolation aceita auto ou isolate.')
 local blend=s['mix-blend-mode']or 'normal';assert(E.blends[blend],'mix-blend-mode inválido.')
 return {filters=E.filters(s.filter,c),backdrop=E.filters(s['backdrop-filter']or s['-webkit-backdrop-filter'],c),clip=s['clip-path']or 'none',blend=blend,backgroundBlends=E.blendList(s['background-blend-mode']),isolation=isolation,backdropScope=E.scope(s['-roblox-backdrop-scope']),backdropColor=s['-roblox-backdrop-color']and U.color(s['-roblox-backdrop-color'])or nil}
end
return E
