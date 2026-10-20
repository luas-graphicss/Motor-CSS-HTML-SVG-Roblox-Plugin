local U=require(script.Parent.Util)
local V=require(script.Parent.VisualStyle)
local Geometry=require(script.Parent.VisualGeometry)
local G={};local cache,slots={},{};local cursor,parses,hits=0,0,0
local sizes={['closest-side']=true,['farthest-side']=true,['closest-corner']=true,['farthest-corner']=true}
function G.angle(text)
 local n,unit=text:match('^([+%-%.%deE]+)(%a+)$');n=tonumber(n)
 if text=='0'then return 0 end
 assert(n and n==n and math.abs(n)<1e7,'Ângulo de gradiente inválido: '..text)
 if unit=='deg'then return n elseif unit=='turn'then return n*360 elseif unit=='grad'then return n*0.9 elseif unit=='rad'then return math.deg(n)end
 error('Ângulo exige deg, turn, grad ou rad.',0)
end
local function isColor(text)return text and(text:lower()=='currentcolor'or pcall(U.color,text))end
function G.parse(value)
 local existing=cache[value];if existing then hits+=1;return existing end
 local kind,body=value:match('^([%a%-]+)%((.*)%)$');assert(kind,'Gradiente inválido.')
 local repeating=kind:sub(1,10)=='repeating-';if repeating then kind=kind:sub(11)end
 assert(kind=='linear-gradient'or kind=='radial-gradient'or kind=='conic-gradient','Tipo de gradiente não suportado: '..kind)
 local tokens=V.segments(body,',');assert(#tokens>=2 and #tokens<=128,'Gradiente exige pelo menos 2 cores e no máximo 128 componentes.')
 local d={kind=kind,repeating=repeating,angle=180,position='50% 50%',shape='ellipse',extent='farthest-corner',stops={},raw=value}
 local first=U.split(tokens[1],' ');local header=not isColor(first[1])
 if header then
  local text=table.remove(tokens,1)
  if kind=='linear-gradient'then
   if text:match('^to ')then
    local direction=U.split(text,' ');assert(#direction>=2 and #direction<=3,'Direção linear inválida.')
    local dx,dy=0,0
    for i=2,#direction do local v=direction[i];if v=='left'or v=='right'then assert(dx==0,'Eixo repetido.');dx=v=='left'and -1 or 1 elseif v=='top'or v=='bottom'then assert(dy==0,'Eixo repetido.');dy=v=='top'and -1 or 1 else error('Direção de gradiente inválida.',0)end end
    d.direction={x=dx,y=dy}
   else d.angle=G.angle(text)end
  else
   local prefix,position=text:match('^(.-)%s+at%s+(.+)$')
   if text:match('^at%s+')then prefix,position='',text:match('^at%s+(.+)$')end
   if position then d.position=position;text=U.trim(prefix)end
   if kind=='conic-gradient'then
    d.angle=0
    if text~=''then local angle=text:match('^from%s+(.+)$');assert(angle,'Use conic-gradient(from ANGLE at POSITION, ...).');d.angle=G.angle(angle)end
   else
    local lengths={};local shapeSeen,extentSeen=false,false
    for _,word in ipairs(U.split(text,' '))do
     if word=='circle'or word=='ellipse'then assert(not shapeSeen,'Forma radial repetida.');shapeSeen=true;d.shape=word
     elseif sizes[word]then assert(not extentSeen,'Extensão radial repetida.');extentSeen=true;d.extent=word
     else lengths[#lengths+1]=word end
    end
    if #lengths>0 then
     assert(not extentSeen and #lengths<=2,'Use tamanho radial explícito OU palavra-chave.')
     if not shapeSeen then d.shape=#lengths==1 and 'circle'or 'ellipse'end
     assert((d.shape=='circle'and #lengths==1)or(d.shape=='ellipse'and #lengths==2),'circle exige 1 raio; ellipse exige 2.')
     if d.shape=='circle'then assert(not lengths[1]:find('%%'),'Raio de circle não aceita porcentagem; use ellipse.')end
     d.radii=lengths
    end
   end
  end
 elseif kind=='conic-gradient'then d.angle=0 end
 local hint
 for _,token in ipairs(tokens)do
  local words=U.split(token,' ')
  if isColor(words[1])then
   assert(#words>=1 and #words<=3,'Stop aceita cor e até 2 posições.')
   d.stops[#d.stops+1]={color=words[1],position=words[2],hint=hint};hint=nil
   if words[3]then d.stops[#d.stops+1]={color=words[1],position=words[3]};d.doubleStops=true end
  else
   assert(#words==1 and #d.stops>0 and not hint,'Hint de gradiente inválido.');hint=words[1];d.hints=true
  end
 end
 assert(not hint and #d.stops>=2 and #d.stops<=64,'Gradiente exige 2 a 64 stops de cor; hint não pode encerrar o gradiente.')
 cursor=cursor%128+1;local previous=slots[cursor];if previous then cache[previous]=nil end
 slots[cursor]=value;cache[value]=d;parses+=1;return d
end
local function stopPosition(raw,definition,length,context)
 if not raw then return nil end
 if definition.kind=='conic-gradient'then
  local p=raw:match('^([+%-%.%d]+)%%$');if p then return tonumber(p)/100 end
  return G.angle(raw)/360
 end
 return Geometry.length(raw,length,context)/math.max(length,1e-9)
end
function G.resolve(value,w,h,context,currentColor)
 local d=type(value)=='table'and value or G.parse(value);local g={kind=d.kind,repeating=d.repeating,definition=d,w=w,h=h,stops={}}
 local length
 if d.kind=='linear-gradient'then
  local dx,dy
  if d.direction then dx,dy=d.direction.x,d.direction.y;if dx~=0 and dy~=0 then dx*=h;dy*=w end
  else local angle=math.rad(d.angle);dx,dy=math.sin(angle),-math.cos(angle)end
  local norm=math.sqrt(dx*dx+dy*dy);g.dx,g.dy=dx/math.max(norm,1e-9),dy/math.max(norm,1e-9)
  length=math.abs(w*g.dx)+math.abs(h*g.dy);g.length=math.max(length,1e-9)
 elseif d.kind=='radial-gradient'then
  g.cx,g.cy=Geometry.position(d.position,w,h,0,0,context)
  local rx,ry
  if d.radii then
   rx=Geometry.length(d.radii[1],w,context);ry=d.shape=='circle'and rx or Geometry.length(d.radii[2],h,context)
   assert(rx>=0 and ry>=0,'Raio radial não pode ser negativo.')
  else
   local close=d.extent:match('^closest')~=nil;local choose=close and math.min or math.max
   local sideX=choose(math.abs(g.cx),math.abs(w-g.cx));local sideY=choose(math.abs(g.cy),math.abs(h-g.cy))
   if d.shape=='circle'then
    rx=choose(sideX,sideY)
    if d.extent:match('corner$')then
     rx=close and math.huge or 0
     for _,x in ipairs({0,w})do for _,y in ipairs({0,h})do rx=choose(rx,math.sqrt((x-g.cx)^2+(y-g.cy)^2))end end
    end
    ry=rx
   else
    rx,ry=sideX,sideY
    if d.extent:match('corner$')then
     local factor=close and math.huge or 0
     for _,x in ipairs({0,w})do for _,y in ipairs({0,h})do factor=choose(factor,math.sqrt(((x-g.cx)/math.max(rx,1e-9))^2+((y-g.cy)/math.max(ry,1e-9))^2))end end
     rx*=factor;ry*=factor
    end
   end
  end
  g.rx,g.ry=math.max(rx,1e-9),math.max(ry,1e-9);length=g.rx
 else
  g.cx,g.cy=Geometry.position(d.position,w,h,0,0,context);g.from=d.angle/360;length=1
 end
 for i,s in ipairs(d.stops)do
  local color,alpha=V.color(s.color,currentColor)
  g.stops[i]={color=color,a=alpha,t=stopPosition(s.position,d,length,context),hint=stopPosition(s.hint,d,length,context)}
 end
 local stops=g.stops;stops[1].t=stops[1].t or 0;stops[#stops].t=stops[#stops].t or 1
 local previous=stops[1].t
 for i=2,#stops do if stops[i].t~=nil then stops[i].t=math.max(previous,stops[i].t);previous=stops[i].t end end
 local i=1
 while i<#stops do
  local j=i+1;while stops[j].t==nil do j+=1 end
  for k=i+1,j-1 do stops[k].t=stops[i].t+(stops[j].t-stops[i].t)*(k-i)/(j-i)end;i=j
 end
 g.first,g.last=stops[1].t,stops[#stops].t;g.period=g.last-g.first;return g
end
function G.parameter(g,x,y)
 if g.kind=='linear-gradient'then return 0.5+((x-g.w/2)*g.dx+(y-g.h/2)*g.dy)/g.length
 elseif g.kind=='radial-gradient'then return math.sqrt(((x-g.cx)/g.rx)^2+((y-g.cy)/g.ry)^2)
 else return (math.atan2(x-g.cx,-(y-g.cy))/(2*math.pi)-g.from)%1 end
end
function G.at(g,t)
 local stops=g.stops
 if g.repeating then
  if g.period<=1e-9 then
   return stops[#stops].color,stops[#stops].a
  end
  t=g.first+(t-g.first)%g.period
 end
 if t<g.first then return stops[1].color,stops[1].a end
 for i=2,#stops do
  local b=stops[i]
  if t<b.t then
   local a=stops[i-1];local f=(t-a.t)/math.max(b.t-a.t,1e-12)
   if b.hint and b.t>a.t then
    local m=math.clamp((b.hint-a.t)/(b.t-a.t),0,1)
    if m<=0 then f=1 elseif m>=1 then f=0 else f=f^(math.log(0.5)/math.log(m))end
   end
   f=math.clamp(f,0,1);local alpha=a.a+(b.a-a.a)*f
   if alpha<=1e-9 then return Color3.new(),0 end
   return Color3.new((a.color.R*a.a*(1-f)+b.color.R*b.a*f)/alpha,(a.color.G*a.a*(1-f)+b.color.G*b.a*f)/alpha,(a.color.B*a.a*(1-f)+b.color.B*b.a*f)/alpha),alpha
  end
 end
 return stops[#stops].color,stops[#stops].a
end
function G.sample(g,x,y)return G.at(g,G.parameter(g,x,y))end
function G.fastLinear(value)
 if not value:match('^linear%-gradient%(')then return false end
 local ok,d=pcall(G.parse,value);if not ok or d.doubleStops or d.hints or #d.stops>16 then return false end
 if d.direction then
  local x,y=d.direction.x,d.direction.y
  if x==-1 and y~=0 then return false end
 end
 local previous=-1
 for _,s in ipairs(d.stops)do
  if s.color:lower()=='currentcolor'then return false end
  if s.position then local n=tonumber(s.position:match('^([%d%.]+)%%$'));if not n or n<0 or n>100 or n<=previous then return false end;previous=n end
 end
 local first=U.split(assert(value:match('^linear%-gradient%((.*)%)$')),',')[1]
 if not isColor(U.split(first,' ')[1])and not first:match('deg$')and not({['to right']=true,['to left']=true,['to top']=true,['to bottom']=true,['to top right']=true,['to bottom right']=true})[first]then return false end
 return true
end
function G.stats()return {definitions=#slots,parses=parses,hits=hits}end
return G
