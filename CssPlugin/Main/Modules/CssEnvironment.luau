local E={VERSION=1}
local BACKSLASH=string.char(92)
local LIMIT=32768
local DEPTH=32
local SIDES=table.freeze({'top','right','bottom','left'})
local function trim(s)return (s:gsub('^%s+',''):gsub('%s+$',''))end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local dimensions={}
for _,side in ipairs(SIDES)do
 dimensions['safe-area-inset-'..side]=0
 dimensions['safe-area-max-inset-'..side]=0
 dimensions['keyboard-inset-'..side]=0
end
for _,key in ipairs({'keyboard-inset-width','keyboard-inset-height','titlebar-area-x','titlebar-area-y','titlebar-area-width','titlebar-area-height'})do dimensions[key]=0 end
for _,key in ipairs({'viewport-segment-width','viewport-segment-height','viewport-segment-top','viewport-segment-right','viewport-segment-bottom','viewport-segment-left'})do dimensions[key]=2 end
table.freeze(dimensions)
E.dimensions=dimensions
local function identifier(name)
 return type(name)=='string'and #name<=64 and name:match('^%a[%w%-]*$')~=nil
end
E.identifier=identifier
function E.name(name,indices)
 assert(identifier(name),'Nome de env() invalido: '..tostring(name))
 name=name:lower()
 if not indices or #indices==0 then return name end
 local parts={name}
 for _,index in ipairs(indices)do parts[#parts+1]=tostring(index)end
 return table.concat(parts,' ')
end
function E.overrides(input)
 assert(input==nil or type(input)=='table','environment exige uma tabela.')
 local out,count={},0
 for key,value in pairs(input or {})do
  assert(type(key)=='string'and #key<=96,'Nome de env() invalido.')
  local words={}
  for word in key:gmatch('%S+')do words[#words+1]=word end
  assert(#words>=1,'Nome de env() vazio.')
  local name=words[1]
  assert(identifier(name),'Nome de env() invalido: '..key)
  local indices={}
  for i=2,#words do
   local n=tonumber(words[i])
   assert(n and n%1==0 and n>=0 and n<=64,'Indice de env() invalido: '..key)
   indices[#indices+1]=n
  end
  local expected=dimensions[name:lower()]
  assert(expected==nil or #indices==expected,'env('..name..') exige '..tostring(expected)..' indice(s).')
  if type(value)=='number'then assert(finite(value)and math.abs(value)<=1000000,key..' exige numero finito.')
  else assert(type(value)=='string'and #value>0 and #value<=256,key..' exige numero ou texto CSS.')end
  count+=1;assert(count<=256,'Maximo de 256 variaveis de ambiente.')
  out[E.name(name,indices)]=value
 end
 return out
end
function E.defaults()
 local out={}
 for name,count in pairs(dimensions)do if count==0 then out[name]=0 end end
 return out
end
function E.read(gui,overrides)
 local values=E.defaults();local sources={}
 for name in pairs(values)do sources[name]='fallback'end
 local service=game:GetService('GuiService')
 local ok,topLeft,bottomRight=pcall(function()return service:GetGuiInset()end)
 if ok and typeof(topLeft)=='Vector2'and typeof(bottomRight)=='Vector2'then
  values['safe-area-inset-top']=math.max(topLeft.Y,0);values['safe-area-inset-left']=math.max(topLeft.X,0)
  values['safe-area-inset-bottom']=math.max(bottomRight.Y,0);values['safe-area-inset-right']=math.max(bottomRight.X,0)
  for _,side in ipairs(SIDES)do sources['safe-area-inset-'..side]='GuiService:GetGuiInset()'end
 end
 local okTopbar,inset=pcall(function()return service.TopbarInset end)
 if okTopbar and typeof(inset)=='Rect'then
  local top=math.max(inset.Max.Y,0)
  if top>values['safe-area-inset-top']then values['safe-area-inset-top']=top;sources['safe-area-inset-top']='GuiService.TopbarInset'end
 end
 if gui then
  local map={CssSafeAreaTop='safe-area-inset-top',CssSafeAreaRight='safe-area-inset-right',CssSafeAreaBottom='safe-area-inset-bottom',CssSafeAreaLeft='safe-area-inset-left',CssKeyboardInsetBottom='keyboard-inset-bottom',CssKeyboardInsetHeight='keyboard-inset-height',CssTitlebarAreaHeight='titlebar-area-height',CssTitlebarAreaWidth='titlebar-area-width'}
  for attribute,name in pairs(map)do
   local value=gui:GetAttribute(attribute)
   if type(value)=='number'and finite(value)and value>=0 and value<=1000000 then values[name]=value;sources[name]=attribute end
  end
 end
 for _,side in ipairs(SIDES)do
  local key='safe-area-max-inset-'..side
  values[key]=math.max(values[key] or 0,values['safe-area-inset-'..side] or 0)
  if sources[key]=='fallback'then sources[key]=sources['safe-area-inset-'..side]end
 end
 for key,value in pairs(overrides or {})do values[key]=value;sources[key]='override'end
 return values,sources
end
function E.key(values)
 local keys={}
 for name in pairs(values or {})do keys[#keys+1]=name end
 table.sort(keys)
 local out={}
 for _,name in ipairs(keys)do
  local value=values[name]
  out[#out+1]=name..'='..(type(value)=='number'and string.format('%.17g',value)or tostring(value))
 end
 return table.concat(out,'|')
end
local function serialize(value)
 if type(value)=='number'then
  assert(finite(value),'Valor de env() nao finito.')
  if value%1==0 then return string.format('%dpx',value)end
  return (string.format('%.6f',value):gsub('0+$',''):gsub('%.$',''))..'px'
 end
 return value
end
local scan
local function resolve(head,fallback,values,depth,budget)
 local words={}
 for word in head:gmatch('%S+')do words[#words+1]=word end
 assert(#words>=1,'env() exige um nome.')
 local name=words[1]:lower()
 assert(identifier(name),'Nome de env() invalido: '..words[1])
 local indices={}
 for i=2,#words do
  local n=tonumber(words[i])
  assert(n and n%1==0 and n>=0 and n<=64,'Indice de env() invalido: '..words[i])
  indices[#indices+1]=n
 end
 local expected=dimensions[name]
 local value
 if expected==nil or #indices==expected then value=values and values[E.name(name,indices)]end
 if value==nil then
  assert(fallback~=nil,'env() sem valor e sem fallback: '..name)
  return scan(fallback,values,depth+1,budget)
 end
 return serialize(value)
end
scan=function(text,values,depth,budget)
 assert(depth<=DEPTH,'env() excede '..DEPTH..' niveis.')
 assert(type(text)=='string'and #text<=LIMIT,'Valor env() excede 32768 bytes.')
 local out,start,i,quote,escaped={},1,1,nil,false
 while i<=#text do
  local c=text:sub(i,i)
  if quote then
   if escaped then escaped=false elseif c==BACKSLASH then escaped=true elseif c==quote then quote=nil end
   i+=1
  elseif c=='"'or c=="'"then quote=c;i+=1
  elseif c==BACKSLASH then i+=2
  elseif text:sub(i,i+3):lower()=='env('and(i==1 or not text:sub(i-1,i-1):match('[%w_%-]'))then
   out[#out+1]=text:sub(start,i-1)
   local j,level,q,esc,comma=i+4,1,nil,false,nil
   while j<=#text and level>0 do
    local ch=text:sub(j,j)
    if q then
     if esc then esc=false elseif ch==BACKSLASH then esc=true elseif ch==q then q=nil end
    elseif ch=='"'or ch=="'"then q=ch
    elseif ch==BACKSLASH then j+=1
    elseif ch=='('then level+=1
    elseif ch==')'then level-=1
    elseif ch==','and level==1 and not comma then comma=j end
    j+=1
   end
   assert(level==0,'env() nao fechado.')
   budget.n+=1;assert(budget.n<=4096,'Orcamento de substituicoes env() excedido.')
   local head=trim(text:sub(i+4,(comma or j-1)-1))
   local fallback=comma and text:sub(comma+1,j-2)or nil
   out[#out+1]=resolve(head,fallback,values,depth,budget)
   i=j;start=j
  else i+=1 end
 end
 assert(not quote,'String CSS nao fechada em env().')
 out[#out+1]=text:sub(start)
 local result=table.concat(out)
 assert(#result<=LIMIT,'Expansao de env() excede 32768 bytes.')
 return result
end
function E.has(text)
 if type(text)~='string'then return false end
 local lower=text:lower();local from=1
 while true do
  local at=lower:find('env(',from,true)
  if not at then return false end
  if at==1 or not lower:sub(at-1,at-1):match('[%w_%-]')then return true end
  from=at+4
 end
end
function E.substitute(text,values)
 if type(text)~='string'or not E.has(text)then return text end
 return scan(text,values,0,{n=0})
end
function E.tryResolve(text,values)
 local ok,result=pcall(E.substitute,text,values)
 if not ok then return nil,tostring(result)end
 return result
end
function E.install(self,options,connect,queue)
 self.envOverrides=self.envOverrides or E.overrides(options and options.environment)
 function self:_syncEnvironment(notify)
  if not self.alive then return end
  local values,sources=E.read(self.gui,self.envOverrides)
  local key=E.key(values)
  local changed=key~=self.environmentKey
  self.environment=values;self.environmentKey=key;self.environmentSources=sources
  if changed and notify~=false then queue(nil,'style')end
  return changed
 end
 function self:getEnvironment()
  assert(self.alive,'Controller encerrado.');self:_syncEnvironment(false)
  return table.clone(self.environment),table.clone(self.environmentSources)
 end
 function self:setEnvironment(values)
  assert(self.alive,'Controller encerrado.');self.envOverrides=E.overrides(values);self:_syncEnvironment(true)
 end
 local function changed()if self.alive then self:_syncEnvironment(true)end end
 if self.gui then
  for attribute in pairs({CssSafeAreaTop=true,CssSafeAreaRight=true,CssSafeAreaBottom=true,CssSafeAreaLeft=true,CssKeyboardInsetBottom=true,CssKeyboardInsetHeight=true,CssTitlebarAreaHeight=true,CssTitlebarAreaWidth=true})do
   connect(self.gui:GetAttributeChangedSignal(attribute),changed)
  end
 end
 local service=game:GetService('GuiService')
 local ok,signal=pcall(function()local _=service.TopbarInset;return service:GetPropertyChangedSignal('TopbarInset')end)
 if ok then connect(signal,changed)end
 local okSafe,safeSignal=pcall(function()return service:GetPropertyChangedSignal('SafeZoneOffsets')end)
 if okSafe then connect(safeSignal,changed)end
 self:_syncEnvironment(false)
end
return E
