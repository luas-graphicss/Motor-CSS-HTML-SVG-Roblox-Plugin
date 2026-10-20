local F={VERSION=1}
F.defaults={['font-feature-settings']='normal',['font-variation-settings']='normal',['font-kerning']='auto',['font-optical-sizing']='auto',['font-stretch']='normal',['font-variant-ligatures']='normal',['font-variant-caps']='normal',['font-variant-numeric']='normal',['font-variant-east-asian']='normal',['font-variant-position']='normal',['font-variant-alternates']='normal',['font-variant-emoji']='normal',['font-language-override']='normal'}
F.variantKeys={'font-variant-ligatures','font-variant-caps','font-variant-numeric','font-variant-east-asian','font-variant-position','font-variant-alternates','font-variant-emoji'}
F.properties={'font-variant'};F.inherited={}
for key in pairs(F.defaults)do F.properties[#F.properties+1]=key;F.inherited[#F.inherited+1]=key end
table.sort(F.inherited)
local function trim(s)return(s:gsub('^%s+',''):gsub('%s+$',''))end
local function split(text,delimiter)
 local out,start,q,depth,escape={},1,nil,0,false
 for i=1,#text do local c=text:sub(i,i)
  if q then if escape then escape=false elseif c=='\\'then escape=true elseif c==q then q=nil end
  elseif c=='"'or c=="'"then q=c elseif c=='('then depth+=1 elseif c==')'then depth-=1;assert(depth>=0,'Parêntese inesperado em fonte.')
  elseif depth==0 and(c==delimiter or delimiter==' 'and c:match('%s'))then local v=trim(text:sub(start,i-1));if v~=''then out[#out+1]=v end;start=i+1 end
 end
 assert(not q and depth==0,'Valor de fonte incompleto.');local v=trim(text:sub(start));if v~=''then out[#out+1]=v end;return out
end
F.split=split
function F.unquote(value)
 value=trim(value);local q=value:sub(1,1);assert((q=='"'or q=="'")and value:sub(-1)==q,'Use uma string CSS entre aspas.')
 local text=value:sub(2,-2);local out={};local i=1
 while i<=#text do
  local c=text:sub(i,i)
  if c=='\\'then
   i+=1;assert(i<=#text,'Escape de fonte incompleto.')
   local hex=text:sub(i):match('^%x%x?%x?%x?%x?%x?')
   if hex then local cp=tonumber(hex,16);assert(cp>0 and cp<=0x10ffff and not(cp>=0xd800 and cp<=0xdfff),'Escape Unicode inválido.');out[#out+1]=utf8.char(cp);i+=#hex;if text:sub(i,i):match('%s')then i+=1 end
   else out[#out+1]=text:sub(i,i);i+=1 end
  else assert(c~='\n'and c~='\r','Quebra de linha em string CSS.');out[#out+1]=c;i+=1 end
 end
 return table.concat(out)
end
function F.settings(value,variations)
 local out={};if value==nil or value=='normal'then return out end
 local list=split(value,',');assert(#list>=1 and #list<=64,'Use 1..64 ajustes OpenType/eixos.')
 for _,part in ipairs(list)do
  local t=split(part,' ');assert(#t>=1 and #t<=2,'Ajuste de fonte: "tag" [valor].')
  local tag=F.unquote(t[1]);assert(#tag==4 and not tag:find('[^ -~]'),'Tags OpenType/eixos exigem 4 caracteres ASCII imprimíveis.')
  local n
  if variations then n=tonumber(t[2]);assert(n and n==n and math.abs(n)<=1000000,'Eixo variável exige número finito.')
  else n=t[2]=='off'and 0 or(t[2]==nil or t[2]=='on')and 1 or tonumber(t[2]);assert(n and n%1==0 and n>=0 and n<=65535,'Feature exige on/off ou inteiro 0..65535.')end
  out[tag]=n
 end
 return out
end
local maps={
 ['font-variant-caps']={['small-caps']={smcp=1},['all-small-caps']={smcp=1,c2sc=1},['petite-caps']={pcap=1},['all-petite-caps']={pcap=1,c2pc=1},unicase={unic=1},['titling-caps']={titl=1}},
 ['font-variant-position']={sub={subs=1},super={sups=1}},
 ['font-variant-ligatures']={['common-ligatures']={liga=1,clig=1},['no-common-ligatures']={liga=0,clig=0},['discretionary-ligatures']={dlig=1},['no-discretionary-ligatures']={dlig=0},['historical-ligatures']={hlig=1},['no-historical-ligatures']={hlig=0},contextual={calt=1},['no-contextual']={calt=0}},
 ['font-variant-numeric']={['lining-nums']={lnum=1},['oldstyle-nums']={onum=1},['proportional-nums']={pnum=1},['tabular-nums']={tnum=1},['diagonal-fractions']={frac=1},['stacked-fractions']={afrc=1},ordinal={ordn=1},['slashed-zero']={zero=1}},
 ['font-variant-east-asian']={jis78={jp78=1},jis83={jp83=1},jis90={jp90=1},jis04={jp04=1},simplified={smpl=1},traditional={trad=1},['full-width']={fwid=1},['proportional-width']={pwid=1},ruby={ruby=1}},
 ['font-variant-alternates']={['historical-forms']={hist=1}},
}
local exclusive={['lining-nums']='figure',['oldstyle-nums']='figure',['proportional-nums']='spacing',['tabular-nums']='spacing',['diagonal-fractions']='fraction',['stacked-fractions']='fraction',jis78='form',jis83='form',jis90='form',jis04='form',simplified='form',traditional='form',['full-width']='width',['proportional-width']='width'}
local alternateFunctions={stylistic=true,styleset=true,['character-variant']=true,swash=true,ornaments=true,annotation=true}
function F.expand(value)
 local out={};for _,k in ipairs(F.variantKeys)do out[k]='normal'end
 if value=='initial'or value=='inherit'or value=='unset'or value=='revert'or value=='revert-layer'then for _,k in ipairs(F.variantKeys)do out[k]=value end;return out end
 if value=='normal'then return out elseif value=='none'then out['font-variant-ligatures']='none';return out end
 local groups={}
 for _,token in ipairs(split(value,' '))do
  local key;for k,map in pairs(maps)do if map[token]then key=k;break end end
  if not key and alternateFunctions[token:match('^(%a[%w%-]*)%(')]then key='font-variant-alternates'end
  assert(key,'font-variant inválido: '..token);groups[key]=groups[key]or {};groups[key][#groups[key]+1]=token
 end
 for k,tokens in pairs(groups)do out[k]=table.concat(tokens,' ')end;return out
end
local stretches={normal=100,['ultra-condensed']=50,['extra-condensed']=62.5,condensed=75,['semi-condensed']=87.5,['semi-expanded']=112.5,expanded=125,['extra-expanded']=150,['ultra-expanded']=200}
function F.normalize(style,parent)
 for key,default in pairs(F.defaults)do
  local value=style[key]or default
  if value=='inherit'or value=='unset'or value=='revert'or value=='revert-layer'then value=parent and parent[key]or default elseif value=='initial'then value=default end
  style[key]=value
 end
 local kerning=style['font-kerning'];assert(kerning=='auto'or kerning=='normal'or kerning=='none','font-kerning aceita auto/normal/none.')
 local optical=style['font-optical-sizing'];assert(optical=='auto'or optical=='none','font-optical-sizing aceita auto/none.')
 assert(({normal=true,text=true,emoji=true,unicode=true})[style['font-variant-emoji']],'font-variant-emoji inválido.')
 local features={};if kerning~='auto'then features.kern=kerning=='none'and 0 or 1 end
 local unresolved={}
 for key,map in pairs(maps)do
  local value=style[key];local words=split(value,' ');local seen={}
  if value=='none'and key=='font-variant-ligatures'then for _,tag in ipairs({'liga','clig','dlig','hlig','calt'})do features[tag]=0 end
  elseif value~='normal'then
   assert(#words>=1,'Valor font-variant vazio.')
   if key=='font-variant-caps'or key=='font-variant-position'then assert(#words==1,key..' aceita um valor.')end
   for _,token in ipairs(words)do
    local settings=map[token]
    if settings then
     local category=exclusive[token]or token:gsub('^no%-','');assert(not seen[category],'Alternativas conflitantes em '..key);seen[category]=true
     for tag,n in pairs(settings)do features[tag]=n end
    else
     local name,args=token:match('^(%a[%w%-]*)%((.+)%)$')
     assert(key=='font-variant-alternates'and alternateFunctions[name],key..' inválido: '..token)
     for _,id in ipairs(split(args,','))do assert(id:match('^[%a_%-][%w_%-]*$'),'Identificador de feature inválido.')end
     unresolved[#unresolved+1]=token
    end
   end
  end
 end
 for tag,n in pairs(F.settings(style['font-feature-settings'],false))do features[tag]=n end
 local axes=F.settings(style['font-variation-settings'],true)
 local stretch=stretches[style['font-stretch']]or tonumber(style['font-stretch']:match('^([%d%.]+)%%$'))
 assert(stretch and stretch>0 and stretch<=1000,'font-stretch exige keyword ou percentual positivo.');axes.wdth=axes.wdth or stretch
 local weight=style['font-weight'];weight=weight=='bold'and 700 or weight=='normal'and 400 or tonumber(weight)or 400;axes.wght=axes.wght or weight
 assert(axes.wght>=1 and axes.wght<=1000,'Eixo wght deve estar em 1..1000.')
 if axes.slnt then assert(axes.slnt>=-90 and axes.slnt<=90,'Eixo slnt fora de -90..90.')end
 if axes.opsz then assert(axes.opsz>0,'Eixo opsz precisa ser positivo.')end
 local tags={};for tag in pairs(features)do tags[#tags+1]=tag end;table.sort(tags)
 local native={};for _,tag in ipairs(tags)do native[#native+1]=tag..'='..features[tag]end
 style._fontFeatures=features;style._openTypeFeatures=table.concat(native,',');style._fontAxes=axes;style._unresolvedFontAlternates=unresolved
 style._fontInstance=nil;style._fontInstanceAxes=nil;style._fontInstanceExact=nil;style._fontSynthesis=nil;style._fontTracking=nil;style._fontEmbolden=nil;style._letterSpacingBase=nil
 style._fontEffectiveWeight=axes.wght;style._fontEffectiveSlant=axes.slnt and axes.slnt~=0 or axes.ital and axes.ital~=0 or style['font-style']=='italic'or style['font-style']=='oblique'
 local language=style['font-language-override'];if language~='normal'then assert(#F.unquote(language)<=4,'Language override exige tag de até 4 caracteres.')end
 return style
end
local axisDefaults={wght=400,wdth=100,slnt=0,ital=0,grad=0}
local nativeWeights
local function nativeWeight(value)
 if not nativeWeights then
  nativeWeights={}
  for _,item in ipairs(Enum.FontWeight:GetEnumItems())do nativeWeights[#nativeWeights+1]=item.Value end
  table.sort(nativeWeights)
 end
 local best,distance=400,math.huge
 for _,candidate in ipairs(nativeWeights)do
  local d=math.abs(candidate-value)
  if d<distance then distance=d;best=candidate end
 end
 return best
end
function F.deliver(style)
 local axes=style._fontAxes or {}
 local mapped=style._fontInstanceAxes
 local fontPx=style._fontPx or tonumber(style['font-size'])or 16
 local wanted={}
 for tag,default in pairs(axisDefaults)do wanted[tag]=axes[tag]or default end
 wanted.opsz=axes.opsz or fontPx*.75
 local italic=style._fontEffectiveSlant==true
 local delivered={}
 delivered.wght=mapped and mapped.wght or nativeWeight(wanted.wght)
 delivered.wdth=mapped and mapped.wdth or axisDefaults.wdth
 delivered.slnt=mapped and mapped.slnt or(italic and -12 or 0)
 delivered.ital=mapped and mapped.ital or(italic and 1 or 0)
 delivered.grad=mapped and mapped.grad or 0
 delivered.opsz=mapped and mapped.opsz or nil
 return wanted,delivered,fontPx,mapped
end
function F.synthesize(style)
 if not style._fontAxes then return style end
 local wanted,delivered,fontPx,mapped=F.deliver(style)
 local weightGap=wanted.wght+wanted.grad*.6-delivered.wght-delivered.grad*.6
 local widthRatio=wanted.wdth/math.max(1,delivered.wdth)
 local slantGap=wanted.slnt-delivered.slnt
 if wanted.ital>=.5 and delivered.ital<.5 then slantGap-=12 end
 local opticalBase=mapped and mapped.opsz or fontPx*.75
 local optical=1
 if delivered.opsz==nil and style['font-optical-sizing']~='none'then optical=math.clamp(wanted.opsz/math.max(1,opticalBase),.35,3)end
 local embolden=math.clamp(weightGap,0,600)/1000*fontPx*.62+math.clamp(1-optical,0,.65)*fontPx*.035
 local tracking=(widthRatio-1)*fontPx*.26+math.clamp(1-optical,-.6,.6)*fontPx*.012+math.clamp(weightGap,0,600)/1000*fontPx*.05
 if math.abs(embolden)<.01 then embolden=0 end
 if math.abs(tracking)<.01 then tracking=0 end
 local unsupported={}
 for tag in pairs(style._fontAxes)do
  if axisDefaults[tag]==nil and tag~='opsz'and not(mapped and mapped[tag]~=nil)then unsupported[#unsupported+1]=tag end
 end
 table.sort(unsupported)
 local exact=math.abs(weightGap)<.5 and math.abs(widthRatio-1)<.002 and math.abs(slantGap)<.5 and math.abs(1-optical)<.01 and #unsupported==0
 style._fontSynthesis=table.freeze({
  weightWanted=wanted.wght,weightDelivered=delivered.wght,weightGap=weightGap,
  widthWanted=wanted.wdth,widthDelivered=delivered.wdth,widthRatio=widthRatio,
  slantWanted=wanted.slnt,slantDelivered=delivered.slnt,slantGap=slantGap,
  opticalWanted=wanted.opsz,opticalRatio=optical,
  embolden=embolden,tracking=tracking,scaleX=math.clamp(widthRatio,.5,2),shear=math.clamp(slantGap,-30,30),
  strokeAlpha=math.clamp(embolden/math.max(.5,fontPx*.08),0,1),
  exact=exact,source=mapped and 'mapped-static'or 'native-synthetic',
  unsupported=table.freeze(unsupported),
 })
 style._fontTracking=tracking
 style._fontEmbolden=embolden
 return style
end
function F.finish(style)
 if style._fontAxes and not style._fontAxes.opsz and style['font-optical-sizing']=='auto'then
  local axes=table.clone(style._fontAxes);axes.opsz=(style._fontPx or 16)*.75;style._fontAxes=axes
 end
 return F.synthesize(style)
end
local alternateTags={stylistic='salt',swash='swsh',ornaments='ornm',annotation='nalt'}
local function familiesOf(style)
 local out={}
 for _,family in ipairs(split(style['font-family']or '',','))do
  local clean=trim(family)
  local head=clean:sub(1,1)
  if(head=='"'or head=="'")and clean:sub(-1)==head then clean=clean:sub(2,#clean-1)end
  clean=trim(clean):lower()
  if clean~=''then out[#out+1]=clean end
 end
 return out
end
local function lookupAlternate(entries,families,group,name)
 for _,family in ipairs(families)do
  for _,entry in ipairs(entries)do
   for _,declared in ipairs(entry.families)do
    if declared:lower()==family then
     local values=entry.groups[group]
     local indexes=values and values[name:lower()]
     if indexes then return indexes end
    end
   end
  end
 end
 return nil
end
function F.resolveAlternates(style,entries)
 local unresolved=style._unresolvedFontAlternates
 if not entries or not unresolved or #unresolved==0 then return false end
 local families=familiesOf(style)
 if #families==0 then return false end
 local features=style._fontFeatures or {}
 local remaining,changed={},false
 for _,token in ipairs(unresolved)do
  local group,args=token:match('^(%a[%w%-]*)%((.+)%)$')
  local pending=false
  for _,id in ipairs(split(args,','))do
   local indexes=lookupAlternate(entries,families,group,trim(id))
   if not indexes then pending=true
   elseif group=='styleset'then for _,n in ipairs(indexes)do if n>=1 and n<=99 then features[string.format('ss%02d',n)]=1;changed=true end end
   elseif group=='character-variant'then local cv=indexes[1];if cv>=1 and cv<=99 then features[string.format('cv%02d',cv)]=indexes[2]or 1;changed=true end
   else local tag=alternateTags[group];if tag then features[tag]=indexes[1];changed=true;if group=='swash'then features.cswh=indexes[1]end end end
  end
  if pending then remaining[#remaining+1]=token end
 end
 if changed then
  local tags={};for tag in pairs(features)do tags[#tags+1]=tag end;table.sort(tags)
  local native={};for _,tag in ipairs(tags)do native[#native+1]=tag..'='..features[tag]end
  style._fontFeatures=features;style._openTypeFeatures=table.concat(native,',')
 end
 style._unresolvedFontAlternates=remaining
 return changed
end
function F.prepareVariants(variants)
 local out={};local count=0
 for family,list in pairs(variants or {})do
  assert(type(family)=='string'and #family<=128 and type(list)=='table','fontVariants: família -> lista de instâncias estáticas.')
  local target={};out[family:lower()]=target
  for _,entry in ipairs(list)do
   count+=1;assert(count<=128,'Máximo de 128 instâncias de fonte mapeadas.')
   assert(type(entry.asset)=='string'and(entry.asset:match('^rbxassetid://%d+$')or entry.asset:match('^rbxasset://fonts/families/[%w_%-]+%.json$')),'fontVariants.asset exige família Roblox.')
   local axes={};for tag,n in pairs(entry.axes or {})do assert(type(tag)=='string'and #tag==4 and type(n)=='number'and n==n and math.abs(n)<=1000000,'Eixo mapeado inválido.');axes[tag]=n end
   target[#target+1]={asset=entry.asset,axes=axes}
  end
 end
 return out
end
function F.choose(style,variants)
 if not variants or not style._fontAxes then return false end
 for _,name in ipairs(split(style['font-family']or '',','))do
  if name:sub(1,1)=='"'or name:sub(1,1)=="'"then name=F.unquote(name)end
  local list=variants[name:lower()];local winner,score
  for _,entry in ipairs(list or {})do
   local cost=0
   for tag,want in pairs(style._fontAxes)do
    local value=entry.axes[tag]
    if value then cost+=math.abs(value-want)/math.max(1,math.abs(want),math.abs(value))
    elseif tag~='wght'and tag~='wdth'and tag~='opsz'then cost+=100 end
   end
   if not score or cost<score then winner=entry;score=cost end
  end
  if winner then style._fontSource=winner.asset;style._customFont=true;style._fontInstance='mapped-static';style._fontInstanceExact=score<1e-9;style._fontInstanceAxes=winner.axes;F.synthesize(style);return true end
 end
 return false
end
local capability={}
function F.paint(object,style)
 local synthesis=style._fontSynthesis
 local alpha=synthesis and synthesis.strokeAlpha or 0
 if alpha<=.02 then return pcall(function()object.TextStrokeTransparency=1 end)end
 return pcall(function()
  object.TextStrokeColor3=object.TextColor3
  object.TextStrokeTransparency=math.clamp(1-alpha*(1-object.TextTransparency),0,1)
 end)
end
function F.apply(object,style)
 local class=object.ClassName;if capability[class]==false then return false end
 local ok=pcall(function()object.OpenTypeFeatures=style._openTypeFeatures or ''end)
 capability[class]=ok
 if ok then F.paint(object,style)end
 return ok
end
function F.diagnostics(root,rules,out,variants,featureValues)
 local hasFeatureValues=type(featureValues)=='table'and featureValues[1]~=nil
 local seen={};for _,d in ipairs(out)do if d.code then seen[d.code]=true end end
 local function warn(code,message)if not seen[code]and #out<64 then seen[code]=true;out[#out+1]={kind='typography',code=code,message=message}end end
 local function inspect(declarations)
  for _,d in ipairs(declarations or {})do
   if d.key=='font-variation-settings'and d.value~='normal'or d.key=='font-stretch'and d.value~='normal'or d.key=='font-optical-sizing'and d.value~='none'then warn('variable-font-native-limit','Fontes variáveis: Roblox não expõe eixos contínuos, então o motor próprio resolve o vetor de eixos, escolhe a instância estática mais próxima (fontVariants) e sintetiza o resíduo: wght/grad viram encorpamento por contorno, wdth vira tracking, slnt/ital usam itálico nativo com cisalhamento reportado e opsz ajusta contorno e tracking. Eixos sem mapeamento ficam listados em _fontSynthesis.unsupported.')end
   if d.key=='font-variant-alternates'and d.value:find('(',1,true)and not hasFeatureValues then warn('font-feature-values-required','Alternantes nomeadas exigem @font-feature-values para a família usada; sem ele o token fica sem efeito. Use font-feature-settings com tags OpenType explícitas.')end
   if d.key=='font-language-override'or d.key=='font-variant-emoji'then warn('font-language-native-limit','Language override/seleção de emoji são preservados; o fallback/shaping de idioma continua a cargo da fonte nativa.')end
  end
 end
 for _,rule in ipairs(rules)do inspect(rule.declarations)end
 local function walk(node)inspect(node.inline);for _,child in ipairs(node.children)do walk(child)end end;walk(root)
end
return F
