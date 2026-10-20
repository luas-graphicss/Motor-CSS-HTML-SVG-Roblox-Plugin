local Queries=require(script.Parent.ResponsiveQueries)
local Cascade=require(script.Parent.CssCascade)
local Features=require(script.Parent.FontFeatures)
local F={VERSION=3}
local aliases={gotham='Gotham',arial='Arial',sourcesans='SourceSans',['source sans pro']='SourceSans',['sans-serif']='SourceSans',monospace='Code',code='Code',serif='Antique'}
local fontCache={};local cacheCount=0
local function trim(s)return (s:gsub('^%s+',''):gsub('%s+$',''))end
local function unquote(s)
 s=trim(s);local q=s:sub(1,1)
 if (q=='"'or q=="'")and s:sub(-1)==q then return s:sub(2,-2)end
 return s
end
local function enumFont(name)
 name=unquote(name);local alias=aliases[name:lower()]
 if alias then return Enum.Font[alias]end
 for _,item in ipairs(Enum.Font:GetEnumItems())do if item.Name:lower()==name:lower()and item.Name~='Unknown'then return item end end
end
function F.asset(value)
 return type(value)=='string'and(value:match('^rbxassetid://%d+$')~=nil or value:match('^rbxasset://fonts/families/[%w_%-]+%.json$')~=nil)
end
function F.weight(value)
 if value=='bold'then return 700 elseif value=='normal'or value==nil then return 400 end
 local n=tonumber(value);assert(n and n>=1 and n<=1000,'font-weight: use normal, bold ou 1..1000.');return n
end
function F.fallback(style)
 for name in (style['font-family']or 'Gotham'):gmatch('[^,]+')do
  local item=enumFont(name)
  if item then
   local bold=F.weight(style._fontEffectiveWeight or style['font-weight'])>=600
   if item==Enum.Font.Gotham then return bold and Enum.Font.GothamBold or item end
   if item==Enum.Font.Arial then return bold and Enum.Font.ArialBold or item end
   if item==Enum.Font.SourceSans then return bold and Enum.Font.SourceSansBold or item end
   return item
  end
 end
 return F.weight(style._fontEffectiveWeight or style['font-weight'])>=600 and Enum.Font.GothamBold or Enum.Font.Gotham
end
function F.face(style)
 local base=Font.fromEnum(F.fallback(style))
 local family=style._fontSource or base.Family
 local wanted=F.weight(style._fontEffectiveWeight or style['font-weight']);local weight=Enum.FontWeight.Regular;local distance=math.huge
 for _,item in ipairs(Enum.FontWeight:GetEnumItems())do local d=math.abs(item.Value-wanted);if d<distance then distance=d;weight=item end end
 local slant=style['font-style']=='italic'or style['font-style']=='oblique'
 if style._fontEffectiveSlant~=nil then slant=style._fontEffectiveSlant end
 local fontStyle=slant and Enum.FontStyle.Italic or Enum.FontStyle.Normal
 local key=family..':'..weight.Value..':'..fontStyle.Value
 if fontCache[key]then return fontCache[key]end
 local face=Font.new(family,weight,fontStyle)
 if cacheCount>=128 then table.clear(fontCache);cacheCount=0 end
 fontCache[key]=face;cacheCount+=1;return face
end
function F.parse(body,U)
 local descriptors={}
 local allowed={['font-family']=true,src=true,['font-weight']=true,['font-style']=true,['font-display']=true}
 for _,part in ipairs(U.split(body,';'))do
  local k,v=part:match('^%s*([%w%-]+)%s*:%s*(.-)%s*$')
  assert(k and v~=''and allowed[k:lower()],'Descritor @font-face não suportado: '..part)
  descriptors[k:lower()]=v
 end
 local family=unquote(assert(descriptors['font-family'],'@font-face precisa de font-family.'))
 assert(#family>0 and #family<=128 and not family:find('[,{}]'),'Nome de família inválido.')
 local face={family=family,weight=F.weight(descriptors['font-weight']),style=descriptors['font-style']or 'normal',sources={},display=descriptors['font-display']or 'swap'}
 assert(face.style=='normal'or face.style=='italic'or face.style=='oblique','font-style inválido em @font-face.')
 assert(({auto=true,block=true,swap=true,fallback=true,optional=true})[face.display],'font-display inválido.')
 for _,source in ipairs(U.split(assert(descriptors.src,'@font-face precisa de src.'),','))do
  local kind,value,tail=source:match('^(%a+)%s*%((.-)%)%s*(.*)$')
  assert(kind=='url'or kind=='local','src aceita url(...) e local(...).')
  local format=tail~=''and tail:match('^format%s*%((.-)%)$')or nil
  assert(tail==''or format,'src: descritor desconhecido.')
  value=unquote(value);assert(#value>0 and #value<=2048,'src inválido.')
  if format then format=unquote(format):lower();assert(({truetype=true,opentype=true,woff2=true,woff=true,roblox=true})[format],'Formato de fonte não suportado: '..format)end
  face.sources[#face.sources+1]={kind=kind,value=value,format=format}
 end
 assert(#face.sources>0 and #face.sources<=16,'Use 1..16 fontes alternativas.');return face
end
function F.prepare(faces,mappings,diagnostics)
 local result={}
 for _,original in ipairs(faces or {})do
  local face=table.clone(original);face.resolved=nil
  for _,source in ipairs(face.sources)do
   local mapped=mappings and(mappings[source.value]or mappings[face.family])
   if mapped then assert(F.asset(mapped),'fontAssets exige uma família Roblox publicada, não arquivo .ttf/.otf/.woff2.');face.resolved=mapped;break end
   if source.kind=='local'then local e=enumFont(source.value);if e then face.resolved=Font.fromEnum(e).Family;break end
   elseif F.asset(source.value)then face.resolved=source.value;break end
  end
  if not face.resolved and diagnostics and #diagnostics<64 then
   diagnostics[#diagnostics+1]={kind='font',family=face.family,message='@font-face '..face.family..': Roblox não carrega TTF/OTF/WOFF2 HTTP diretamente. Use fontAssets, local(...) ou uma família rbxassetid://; fallback aplicado.'}
  end
  result[#result+1]=face
 end
 return result
end
function F.compute(style,faces,width,height,variants)
 local layerOrder=Cascade.order(faces and faces[1]and faces[1].layerEvents,width,height,style._mediaEnvironment)
 local function finish()Features.choose(style,variants);return style end
 style._fontSource=nil;style._customFont=false
 local desired=F.weight(style._fontEffectiveWeight or style['font-weight']);local slant=style['font-style']or 'normal'
 for name in (style['font-family']or 'Gotham'):gmatch('[^,]+')do
  name=unquote(name);local chosen,score
  for _,face in ipairs(faces or {})do
   if face.resolved and face.family:lower()==name:lower()and Queries.mediaActive(face,width,height,style._mediaEnvironment)then
    local distance=math.abs(face.weight-desired)+(face.style==slant and 0 or 2000)
    if not score or distance<score or distance==score and Cascade.layerCompare(face.layer,chosen.layer,false,layerOrder)>=0 then chosen=face;score=distance end
   end
  end
  if chosen then style._fontSource=chosen.resolved;style._customFont=true;return finish()end
  local e=enumFont(name)
  if e then style._fontSource=Font.fromEnum(e).Family;return finish()end
  if F.asset(name)then style._fontSource=name;style._customFont=true;return finish()end
 end
 return finish()
end
function F.register(doc,family,asset,weight,slant)
 assert(type(family)=='string'and #family>0 and #family<=128,'Família inválida.')
 assert(F.asset(asset),'Use rbxassetid://ID de família de fonte ou rbxasset://fonts/families/Nome.json.')
 doc.stylePlan=doc.stylePlan or {};local faces=doc.stylePlan.fontFaces or {};doc.stylePlan.fontFaces=faces
 weight=F.weight(weight);slant=slant or 'normal';assert(slant=='normal'or slant=='italic'or slant=='oblique','Estilo de fonte inválido.')
 for i=#faces,1,-1 do local f=faces[i];if f.family:lower()==family:lower()and f.weight==weight and f.style==slant then table.remove(faces,i)end end
 assert(#faces<32,'Máximo de 32 faces por documento.')
 faces[#faces+1]={family=family,weight=weight,style=slant,resolved=asset,sources={{kind='url',value=asset}},display='swap'}
 return faces[#faces]
end
return F
