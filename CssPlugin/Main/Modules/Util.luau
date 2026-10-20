local U = {}
local Cost=require(script.Parent.CostModel)
function U.trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
function U.split(s, delimiter)
 local out, start, level, quote, escaped = {}, 1, 0, nil, false
 for i=1,#s do
  local c=s:sub(i,i)
  if quote then
   if escaped then escaped=false elseif c==string.char(92)then escaped=true elseif c==quote then quote=nil end
  elseif c=='"' or c=="'" then quote=c
  elseif c=='(' or c=='[' then level+=1
  elseif c==')' or c==']' then level-=1; assert(level>=0,'Delimitador inesperado: '..s)
  elseif level==0 and ((delimiter==' ' and c:match('%s')) or c==delimiter) then
   local part=U.trim(s:sub(start,i-1)); if part~='' then table.insert(out,part) end; start=i+1
  end
 end
 assert(not quote and level==0,'Aspas ou parênteses não fechados: '..s)
 local part=U.trim(s:sub(start)); if part~='' then table.insert(out,part) end
 return out
end
function U.copy(t) local r={}; if t then for k,v in pairs(t) do r[k]=v end end; return r end
local entities=table.freeze({amp='&',lt='<',gt='>',quot='"',apos="'",nbsp=utf8.char(0xa0),shy=utf8.char(0xad)})
local function decodeEntity(e)
 if entities[e] then return entities[e] end
 local n=e:match('^#x(%x+)$'); n=n and tonumber(n,16) or tonumber(e:match('^#(%d+)$'))
 if n and n<=0x10ffff and not (n>=0xd800 and n<=0xdfff) then return utf8.char(n) end
 error('Entidade XML não suportada: &'..e..';',0)
end
function U.decode(s)
 if not s:find('&',1,true)then return s end
 return (s:gsub('&([^;]+);',decodeEntity))
end
local function doubleHex(c)return c..c end
function U.xml(source,options)
 options=options or {};local checkpoint=options.checkpoint
 Cost.cap('bytes',#source,'Documento')
 assert(not source:find('<!DOCTYPE') and not source:find('<!ENTITY'),'DOCTYPE e entidades externas não são aceitos.')
 source=source:gsub('<!%-%-.-%-%->',''):gsub('<%?xml.-%?>','')
 local root={tag='_root',attrs={},children={},text='',content=options.orderedText and {}or nil}; local stack={root}; local pos,count=1,0
 local function appendText(node,raw)
  if node.invalid or raw==''then return end
  local text=U.decode(raw);node.text..=text
  if node.content then local last=#node.content;if type(node.content[last])=='string'then node.content[last]..=text else node.content[last+1]=text end end
 end
 while pos<=#source do
  if checkpoint then checkpoint()end
  local a=source:find('<',pos,true)
  if not a then appendText(stack[#stack],source:sub(pos));break end
  appendText(stack[#stack],source:sub(pos,a-1))
  local b,q=a+1,nil
  while b<=#source do
   if checkpoint and (b-a)%1024==0 then checkpoint(8)end
   local c=source:sub(b,b)
   if q then if c==q then q=nil end elseif c=='"' or c=="'" then q=c elseif c=='>' then break end
   b+=1
  end
  assert(b<=#source,'Tag não fechada perto do caractere '..a)
  local body=U.trim(source:sub(a+1,b-1)); pos=b+1
  if body:sub(1,1)=='/' then
   local tag=U.trim(body:sub(2)):lower()
   assert(#stack>1 and stack[#stack].tag==tag,'Fechamento incompatível: '..body)
   table.remove(stack)
  else
   local selfClosing=body:sub(-1)=='/'; if selfClosing then body=U.trim(body:sub(1,-2)) end
   local tag,rest=body:match('^([%w_:%-]+)(.*)$'); assert(tag,'Tag inválida perto de '..a)
   tag=tag:lower(); assert(tag~='script' and tag~='foreignobject','Conteúdo executável/foreignObject não é aceito.')
   local function parseAttributes()
   local attrs={};local p=1
   while p<=#rest do
    local _,e=rest:find('^%s+',p); if e then p=e+1 end; if p>#rest then break end
    local s,e,key=rest:find('([%w_:%-]+)',p); assert(s==p,'Atributo inválido em <'..tag..'>')
    key=key:lower(); p=e+1
    local _,ws=rest:find('^%s+',p); if ws then p=ws+1 end
    local value='true'
    if rest:sub(p,p)=='=' then
     p+=1; local _,ws2=rest:find('^%s+',p); if ws2 then p=ws2+1 end
     local quote=rest:sub(p,p); assert(quote=='"' or quote=="'",'Use aspas no atributo '..key)
     local close=rest:find(quote,p+1,true); assert(close,'Aspas não fechadas: '..key)
     value=U.decode(rest:sub(p+1,close-1)); p=close+1
    end
    assert(not attrs[key],'Atributo repetido: '..key)
    assert(not key:match('^on'),'Eventos HTML não executam código; use LocalScript.')
    attrs[key]=value
   end
   return attrs
   end
   local ok,attrs=pcall(parseAttributes)
   if not ok then
    if not options.recover or #stack==1 then error(attrs,0)end
    local diagnostics=options.diagnostics
    if diagnostics and #diagnostics<64 then diagnostics[#diagnostics+1]={kind='tag',tag=tag,offset=a,message=tostring(attrs)}end
    attrs={}
   end
   count+=1;Cost.cap('nodes',count,'Tags do documento')
   local node={tag=tag,attrs=attrs,children={},text='',content=options.orderedText and {}or nil,invalid=not ok or stack[#stack].invalid}
   if not node.invalid then
    local parent=stack[#stack];table.insert(parent.children,node)
    if parent.content then parent.content[#parent.content+1]=#parent.children end
   end
   if not selfClosing and tag~='input' and tag~='img' and tag~='br' then table.insert(stack,node); assert(#stack<=Cost.limits().depth,'Arvore profunda demais.') end
  end
 end
 assert(#stack==1,'Tag não fechada: '..stack[#stack].tag)
 assert(#root.children==1 and U.trim(root.text)=='','Use uma única tag raiz.')
 return root.children[1]
end
function U.numbers(s)
 local out,p={},1
 while p<=#s do
  local c=s:sub(p,p)
  if c:match('[%s,]') then p+=1 else
   local tail=s:sub(p)
   local n=tail:match('^[%+%-]?%d*%.?%d+[eE][%+%-]?%d+') or tail:match('^[%+%-]?%d*%.?%d+')
   assert(n,'Número inválido: '..tail:sub(1,24)); local v=tonumber(n)
   assert(v and v==v and math.abs(v)<1e8,'Número fora do limite.'); table.insert(out,v); p+=#n
  end
 end
 return out
end
local CssColor=require(script.Parent.CssColor)
function U.color(value,context)return CssColor.native(value or 'transparent',context)end
U.length=require(script.Parent.MathLength).length
local Fonts=require(script.Parent.FontFaces)
U.font=Fonts.fallback
U.fontFace=Fonts.face
return U
