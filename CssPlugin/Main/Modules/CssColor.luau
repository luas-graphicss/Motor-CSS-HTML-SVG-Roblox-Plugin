local Spaces=require(script.Parent.ColorSpaces)
local C={VERSION=1}
local function trim(s)return(s:gsub('^%s+',''):gsub('%s+$',''))end
local function split(s,separator)
 local out,start,depth={},1,0
 for i=1,#s do local ch=s:sub(i,i)
  if ch=='('then depth+=1 elseif ch==')'then depth-=1;assert(depth>=0,'Parêntese de cor inesperado.')
  elseif depth==0 and(ch==separator or separator==' 'and ch:match('%s'))then local p=trim(s:sub(start,i-1));assert(separator==' 'or p~='','Canal/lista de cor vazio.');if p~=''then out[#out+1]=p end;start=i+1 end
 end
 assert(depth==0,'Função de cor não fechada.');local p=trim(s:sub(start));assert(separator==' 'or #out==0 or p~='','Canal/lista de cor vazio.');if p~=''then out[#out+1]=p end;return out
end
C.split=split
local names={}
for name,hex in ('aliceblue:f0f8ff antiquewhite:faebd7 aqua:00ffff aquamarine:7fffd4 azure:f0ffff beige:f5f5dc bisque:ffe4c4 black:000000 blanchedalmond:ffebcd blue:0000ff blueviolet:8a2be2 brown:a52a2a burlywood:deb887 cadetblue:5f9ea0 chartreuse:7fff00 chocolate:d2691e coral:ff7f50 cornflowerblue:6495ed cornsilk:fff8dc crimson:dc143c cyan:00ffff darkblue:00008b darkcyan:008b8b darkgoldenrod:b8860b darkgray:a9a9a9 darkgrey:a9a9a9 darkgreen:006400 darkkhaki:bdb76b darkmagenta:8b008b darkolivegreen:556b2f darkorange:ff8c00 darkorchid:9932cc darkred:8b0000 darksalmon:e9967a darkseagreen:8fbc8f darkslateblue:483d8b darkslategray:2f4f4f darkslategrey:2f4f4f darkturquoise:00ced1 darkviolet:9400d3 deeppink:ff1493 deepskyblue:00bfff dimgray:696969 dimgrey:696969 dodgerblue:1e90ff firebrick:b22222 floralwhite:fffaf0 forestgreen:228b22 fuchsia:ff00ff gainsboro:dcdcdc ghostwhite:f8f8ff gold:ffd700 goldenrod:daa520 gray:808080 grey:808080 green:008000 greenyellow:adff2f honeydew:f0fff0 hotpink:ff69b4 indianred:cd5c5c indigo:4b0082 ivory:fffff0 khaki:f0e68c lavender:e6e6fa lavenderblush:fff0f5 lawngreen:7cfc00 lemonchiffon:fffacd lightblue:add8e6 lightcoral:f08080 lightcyan:e0ffff lightgoldenrodyellow:fafad2 lightgray:d3d3d3 lightgrey:d3d3d3 lightgreen:90ee90 lightpink:ffb6c1 lightsalmon:ffa07a lightseagreen:20b2aa lightskyblue:87cefa lightslategray:778899 lightslategrey:778899 lightsteelblue:b0c4de lightyellow:ffffe0 lime:00ff00 limegreen:32cd32 linen:faf0e6 magenta:ff00ff maroon:800000 mediumaquamarine:66cdaa mediumblue:0000cd mediumorchid:ba55d3 mediumpurple:9370db mediumseagreen:3cb371 mediumslateblue:7b68ee mediumspringgreen:00fa9a mediumturquoise:48d1cc mediumvioletred:c71585 midnightblue:191970 mintcream:f5fffa mistyrose:ffe4e1 moccasin:ffe4b5 navajowhite:ffdead navy:000080 oldlace:fdf5e6 olive:808000 olivedrab:6b8e23 orange:ffa500 orangered:ff4500 orchid:da70d6 palegoldenrod:eee8aa palegreen:98fb98 paleturquoise:afeeee palevioletred:db7093 papayawhip:ffefd5 peachpuff:ffdab9 peru:cd853f pink:ffc0cb plum:dda0dd powderblue:b0e0e6 purple:800080 rebeccapurple:663399 red:ff0000 rosybrown:bc8f8f royalblue:4169e1 saddlebrown:8b4513 salmon:fa8072 sandybrown:f4a460 seagreen:2e8b57 seashell:fff5ee sienna:a0522d silver:c0c0c0 skyblue:87ceeb slateblue:6a5acd slategray:708090 slategrey:708090 snow:fffafa springgreen:00ff7f steelblue:4682b4 tan:d2b48c teal:008080 thistle:d8bfd8 tomato:ff6347 turquoise:40e0d0 violet:ee82ee wheat:f5deb3 white:ffffff whitesmoke:f5f5f5 yellow:ffff00 yellowgreen:9acd32'):gmatch('([%a]+):(%x+)')do names[name]='#'..hex end
names.transparent='#00000000'
local function finite(x)assert(type(x)=='number'and x==x and math.abs(x)<1e12,'Canal de cor não finito ou fora do limite.');return x end
local function arithmetic(text,env,percent)
 local tokens,p={},1
 while p<=#text do
  local tail=text:sub(p);local ws=tail:match('^%s+')
  if ws then p+=#ws else
   local n=tail:match('^%d*%.?%d+[eE][%+%-]?%d+')or tail:match('^%d*%.?%d+')
   if n then
    p+=#n;local unit=text:sub(p):match('^%%')or text:sub(p):match('^[%a]+')or '';p+=#unit
    local v=assert(tonumber(n));if unit=='%'then assert(percent,'Percentual não permitido no matiz.');v*=percent/100
    elseif unit=='deg'or unit==''then elseif unit=='turn'then v*=360 elseif unit=='rad'then v=math.deg(v)elseif unit=='grad'then v*=0.9 else error('Unidade de canal inválida: '..unit,0)end
    tokens[#tokens+1]=v
   else
    local id=tail:match('^[%a_][%w_%-]*')
    if id then tokens[#tokens+1]=id;p+=#id else local ch=tail:sub(1,1);assert(ch:match('[%+%-%*/%(%)%,]'),'Expressão de cor inválida: '..tail);tokens[#tokens+1]=ch;p+=1 end
   end
   assert(#tokens<=256,'Expressão de cor excede 256 tokens.')
  end
 end
 local at,depth=1,0;local expression,product,primary
 primary=function()
  depth+=1;assert(depth<=24,'calc() de cor profundo demais.');local t=tokens[at];at+=1;local value
  if type(t)=='number'then value=t
  elseif t=='+'or t=='-'then value=primary()*(t=='-'and -1 or 1)
  elseif t=='('then value=expression();assert(tokens[at]==')','calc() incompleto.');at+=1
  elseif type(t)=='string'and tokens[at]=='('then
   assert(t=='calc'or t=='min'or t=='max'or t=='clamp'or t=='abs'or t=='sign','Função aritmética de cor não suportada: '..t)
   at+=1;local args={expression()};while tokens[at]==','do at+=1;args[#args+1]=expression()end
   assert(tokens[at]==')','Função aritmética não fechada.');at+=1
   if t=='calc'then assert(#args==1);value=args[1]elseif t=='min'then value=math.min(table.unpack(args))elseif t=='max'then value=math.max(table.unpack(args))
   elseif t=='clamp'then assert(#args==3);value=math.max(args[1],math.min(args[2],args[3]))else assert(#args==1);value=t=='abs'and math.abs(args[1])or math.sign(args[1])end
  elseif type(t)=='string'and env and env[t]~=nil then value=env[t]
  elseif t=='pi'then value=math.pi elseif t=='e'then value=math.exp(1)
  else error('Canal/expressão desconhecido: '..tostring(t),0)end
  depth-=1;return finite(value)
 end
 product=function()local v=primary();while tokens[at]=='*'or tokens[at]=='/'do local op=tokens[at];at+=1;local r=primary();if op=='/'then assert(r~=0,'Divisão por zero em cor.');v/=r else v*=r end;finite(v)end;return v end
 expression=function()local v=product();while tokens[at]=='+'or tokens[at]=='-'do local op=tokens[at];at+=1;local r=product();v+=op=='+'and r or-r;finite(v)end;return v end
 local value=expression();assert(at>#tokens,'Tokens extras no canal de cor.');return finite(value)
end
local function channel(text,env,percent)if text=='none'then return 0,true end;return arithmetic(text,env,percent),false end
local function make(space,v,alpha,missing)return {space=space,v=v,alpha=alpha,missing=missing or{}}end
local aliases={rgb='srgb',rgba='srgb',hsla='hsl'}
local channelNames={rgb={'r','g','b'},rgba={'r','g','b'},hsl={'h','s','l'},hsla={'h','s','l'},hwb={'h','w','b'},lab={'l','a','b'},lch={'l','c','h'},oklab={'l','a','b'},oklch={'l','c','h'}}
local function scales(fn)
 if fn=='rgb'or fn=='rgba'then return {255,255,255}end
 if fn=='hsl'or fn=='hsla'or fn=='hwb'then return {false,100,100}end
 if fn=='lab'then return {100,125,125}end
 if fn=='lch'then return {100,150,false}end
 if fn=='oklab'then return {1,.4,.4}end
 if fn=='oklch'then return {1,.4,false}end
 return {1,1,1}
end
local function converted(color,space)
 local v=Spaces.convert(color.v,color.space,space);local missing={};local from,to=Spaces.groups(color.space),Spaces.groups(space)
 for i=1,3 do if color.missing[i]then for j=1,3 do if from[i]==to[j]then missing[j]=true;v[j]=0 end end end end
 missing[4]=color.missing[4]
 local hue=Spaces.hue[space];if hue and Spaces.powerless(space,v)then missing[hue]=true;v[hue]=0 end
 return make(space,v,color.alpha,missing)
end
C.convert=function(color,space)return converted(color,space)end
local function huePair(a,b,method)
 a=a%360;b=b%360;local d=b-a
 if method=='shorter'then if d>180 then a+=360 elseif d< -180 then b+=360 end
 elseif method=='longer'then if d>0 and d<180 then a+=360 elseif d<=0 and d> -180 then b+=360 end
 elseif method=='increasing'then if b<a then b+=360 end
 elseif method=='decreasing'then if a<b then a+=360 end
 else error('Interpolação de matiz inválida: '..tostring(method),0)end
 return a,b
end
function C.mix(a,b,space,w1,w2,method)
 assert(Spaces.spaces[space],'Espaço de mistura inválido.');w1=w1 or .5;w2=w2 or .5
 assert(w1>=0 and w2>=0 and w1<=1 and w2<=1 and w1+w2>0,'Pesos color-mix precisam estar entre 0% e 100%, soma positiva.')
 local sum=w1+w2;local x,y=w1/sum,w2/sum;a=converted(a,space);b=converted(b,space)
 local missing={}
 for i=1,4 do
  if a.missing[i]and b.missing[i]then missing[i]=true
  elseif a.missing[i]then if i==4 then a.alpha=b.alpha else a.v[i]=b.v[i]end
  elseif b.missing[i]then if i==4 then b.alpha=a.alpha else b.v[i]=a.v[i]end end
 end
 local alpha=a.alpha*x+b.alpha*y;local v={};local hue=Spaces.hue[space]
 for i=1,3 do
  if i==hue then local av,bv=huePair(a.v[i],b.v[i],method or'shorter');v[i]=(av*x+bv*y)%360
  else v[i]=alpha>0 and(a.v[i]*a.alpha*x+b.v[i]*b.alpha*y)/alpha or 0 end
 end
 return make(space,v,alpha*math.min(sum,1),missing)
end
local parse
parse=function(value,context,depth)
 depth=depth or 0;assert(depth<=24,'Cores aninhadas profundas demais.');assert(type(value)=='string'and #value<=8192,'Cor inválida ou maior que 8192 bytes.')
 value=trim(value):lower();value=names[value]or value
 if value=='currentcolor'then
  local current=context and context.currentColor or'#000000';if type(current)=='table'then return current end
  assert(current:lower()~='currentcolor','currentColor recursivo.');return parse(current,context,depth+1)
 end
 local hex=value:match('^#(%x+)$')
 if hex then
  if #hex==3 or #hex==4 then hex=hex:gsub('.',function(ch)return ch..ch end)end
  assert(#hex==6 or #hex==8,'Cor hexadecimal inválida.');return make('srgb',{tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255},#hex==8 and tonumber(hex:sub(7,8),16)/255 or 1)
 end
 local fn,body=value:match('^([%a][%w%-]*)%((.*)%)$');assert(fn,'Cor não suportada: '..value)
 if fn=='light-dark'then
  local args=split(body,',');assert(#args==2,'light-dark() exige duas cores.')
  local light,dark=parse(args[1],context,depth+1),parse(args[2],context,depth+1)
  return context and(context.colorScheme=='dark'or context.usedColorScheme=='dark')and dark or light
 end
 if fn=='color-mix'then
  local args=split(body,',');assert(#args==3,'color-mix() exige espaço e duas cores.');local header=split(args[1],' ')
  assert(header[1]=='in'and Spaces.spaces[header[2]]and(#header==2 or #header==4 and header[4]=='hue'),'Cabeçalho color-mix inválido.')
  local space,method=header[2],header[3]or'shorter'
  assert(#header==2 or Spaces.hue[space],'Método hue exige um espaço polar.');assert(({shorter=true,longer=true,increasing=true,decreasing=true})[method],'Método hue inválido.')
  local function stop(text)
   local tokens=split(text,' ');assert(#tokens==1 or #tokens==2,'Stop color-mix inválido.');local color,weight=tokens[1],tokens[2]
   if #tokens==2 and tokens[1]:match('%%$')then color,weight=tokens[2],tokens[1]end
   local n;if weight then assert(weight:match('%%$'),'Peso color-mix exige percentual.');n=arithmetic(weight,nil,1)end
   return parse(color,context,depth+1),n
  end
  local a,wa=stop(args[2]);local b,wb=stop(args[3]);if not wa and not wb then wa,wb=.5,.5 elseif not wa then wa=1-wb elseif not wb then wb=1-wa end
  return C.mix(a,b,space,wa,wb,method)
 end
 assert(channelNames[fn]or fn=='color','Função de cor não suportada: '..fn)
 local slash=split(body,'/');assert(#slash<=2,'Cor aceita um único alpha.');local alphaText=slash[2]
 local tokens=split(slash[1],' ');local relative=tokens[1]=='from';local source,env
 if relative then
  assert(#tokens>=2,'Origem de cor relativa ausente.');source=parse(tokens[2],context,depth+1);table.remove(tokens,1);table.remove(tokens,1)
 end
 local space=aliases[fn]or fn;local ids=channelNames[fn]
 if fn=='color'then
  space=table.remove(tokens,1);assert(Spaces.spaces[space]and not Spaces.hue[space]and space~='lab'and space~='oklab','color() exige espaço RGB/XYZ predefinido.')
  ids=space:sub(1,3)=='xyz'and{'x','y','z'}or{'r','g','b'}
 end
 local legacy=not relative and fn~='color'and #split(slash[1],',')>1
 if legacy then
  assert(fn=='rgb'or fn=='rgba'or fn=='hsl'or fn=='hsla','Vírgulas não permitidas nesta função de cor.');assert(not alphaText,'Não misture vírgulas e /.')
  tokens=split(slash[1],',');if #tokens==4 then alphaText=table.remove(tokens)end
 end
 assert(#tokens==3,'Cor exige exatamente três canais.')
 if relative then
  local origin=converted(source,space);env={alpha=origin.alpha}
  for i,name in ipairs(ids)do env[name]=origin.v[i]*(space=='srgb'and fn~='color'and 255 or 1)end
 end
 local scale=scales(fn);local v,missing={},{}
 for i=1,3 do
  v[i],missing[i]=channel(tokens[i],env,scale[i]);if legacy then assert(not missing[i],'none não é válido com vírgulas.')end
  if fn=='rgb'or fn=='rgba'then v[i]/=255;if not relative then v[i]=math.clamp(v[i],0,1)end end
 end
 if space=='lab'or space=='lch'then v[1]=math.clamp(v[1],0,100)end
 if space=='oklab'or space=='oklch'then v[1]=math.clamp(v[1],0,1)end
 if space=='lch'or space=='oklch'then v[2]=math.max(0,v[2])end
 if space=='hsl'then v[2]=math.max(v[2],0);v[3]=math.clamp(v[3],0,100)end
 if space=='hwb'then v[2]=math.clamp(v[2],0,100);v[3]=math.clamp(v[3],0,100)end
 local hue=Spaces.hue[space];if hue then v[hue]%=360 end
 local alpha=relative and source.alpha or 1
 if alphaText then alpha,missing[4]=channel(alphaText,env,1);alpha=math.clamp(alpha,0,1)elseif relative then missing[4]=source.missing[4]end
 return make(space,v,alpha,missing)
end
C.parse=parse
C.native=function(value,context)return Spaces.native(type(value)=='table'and value or parse(value,context))end
function C.serialize(color)
 local v=color.v;local suffix=string.format('%.10g %.10g %.10g / %.10g',v[1],v[2],v[3],color.alpha)
 if color.space=='lab'or color.space=='lch'or color.space=='oklab'or color.space=='oklch'then return color.space..'('..suffix..')'end
 if color.space=='hsl'or color.space=='hwb'then return color.space..'('..string.format('%.10g %.10g%% %.10g%% / %.10g',v[1],v[2],v[3],color.alpha)..')'end
 return 'color('..color.space..' '..suffix..')'
end
return C
