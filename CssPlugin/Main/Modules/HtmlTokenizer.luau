local Entities=require(script.Parent.HtmlEntities)
local T={VERSION=1}
T.rawtext=table.freeze({style=true,script=true,xmp=true,iframe=true,noembed=true,noframes=true,listing=true})
T.rcdata=table.freeze({title=true,textarea=true})
function T.tokenize(source,options)
 assert(type(source)=='string','O markup precisa ser texto.')
 options=options or {}
 if source:find('\r',1,true)then source=source:gsub('\r\n','\n'):gsub('\r','\n')end
 local checkpoint=options.checkpoint
 local diagnostics=options.diagnostics
 local function note(kind,message,offset)
  if diagnostics and #diagnostics<64 then diagnostics[#diagnostics+1]={kind=kind,message=message,offset=offset}end
 end
 local tokens={}
 local buffer={}
 local length=#source
 local pos=1
 local mode='data'
 local rawTag=nil
 local function flush()
  if #buffer>0 then
   tokens[#tokens+1]={type='character',data=table.concat(buffer)}
   table.clear(buffer)
  end
 end
 local function push(text)
  if text and text~=''then buffer[#buffer+1]=text end
 end
 local function emit(token)
  flush()
  tokens[#tokens+1]=token
  return token
 end
 local function readAttributes(start)
  local attrs={}
  local p=start
  local selfClosing=false
  while p<=length do
   if checkpoint and(p-start)%256==0 then checkpoint(4)end
   local _,spaces=source:find('^%s+',p)
   if spaces then p=spaces+1 end
   local char=source:sub(p,p)
   if char==''then break end
   if char=='>'then p+=1;break end
   if char=='/'then
    if source:sub(p+1,p+1)=='>'then selfClosing=true;p+=2;break end
    p+=1
   else
    local _,nameStop,name=source:find('^([^%s/>=]+)',p)
    if not nameStop then p+=1 else
     name=string.lower(name)
     p=nameStop+1
     local _,gap=source:find('^%s+',p)
     if gap then p=gap+1 end
     local value='true'
     if source:sub(p,p)=='='then
      p+=1
      local _,gap2=source:find('^%s+',p)
      if gap2 then p=gap2+1 end
      local quote=source:sub(p,p)
      if quote=='"'or quote=="'"then
       local close=source:find(quote,p+1,true)
       if close then value=Entities.decode(source:sub(p+1,close-1),true);p=close+1
       else value=Entities.decode(source:sub(p+1),true);p=length+1;note('tag','Aspas nao fechadas em '..name,p)end
      else
       local _,valueStop,raw=source:find('^([^%s>]*)',p)
       value=Entities.decode(raw or'',true)
       p=(valueStop or p)+1
      end
     end
     if #name>2 and name:match('^on')then note('attribute','Evento HTML ignorado: '..name,p)
     elseif name~=''then
      if attrs[name]==nil then attrs[name]=value else note('tag','Atributo repetido: '..name,p)end
     end
    end
   end
  end
  return attrs,selfClosing,p
 end
 local function markupDeclaration(start)
  if source:sub(start+2,start+3)=='--'then
   local close=source:find('-->',start+4,true)
   local bogus=source:find('--!>',start+4,true)
   if bogus and(not close or bogus<close)then
    emit({type='comment',data=source:sub(start+4,bogus-1),offset=start})
    return bogus+4
   end
   if close then
    emit({type='comment',data=source:sub(start+4,close-1),offset=start})
    return close+3
   end
   emit({type='comment',data=source:sub(start+4),offset=start})
   note('comment','Comentario nao fechado.',start)
   return length+1
  end
  if string.upper(source:sub(start+2,start+8))=='DOCTYPE'then
   local close=source:find('>',start,true)
   local body=source:sub(start+9,(close or length+1)-1)
   assert(not string.upper(body):find('ENTITY',1,true),'Entidades externas nao sao aceitas.')
   emit({type='doctype',name=string.lower(body:match('^%s*([%w_:%-]+)')or''),offset=start})
   return(close or length)+1
  end
  if source:sub(start+2,start+8)=='[CDATA['then
   local close=source:find(']]>',start+9,true)
   push(source:sub(start+9,(close or length+1)-1))
   return close and close+3 or length+1
  end
  local close=source:find('>',start,true)
  local body=source:sub(start+2,(close or length+1)-1)
  assert(not string.upper(body):find('ENTITY',1,true),'Entidades externas nao sao aceitas.')
  emit({type='comment',data=body,offset=start})
  return(close or length)+1
 end
 local function rawTextEnd(start)
  local searchPos=start
  while true do
   local found=source:find('</',searchPos,true)
   if not found then return nil,nil end
   local candidate=string.lower(source:sub(found+2,found+1+#rawTag))
   local following=source:sub(found+2+#rawTag,found+2+#rawTag)
   if candidate==rawTag and(following==''or following:match('[%s/>]'))then
    return found,source:find('>',found,true)
   end
   searchPos=found+2
  end
 end
 while pos<=length do
  if checkpoint then checkpoint()end
  if mode=='data'then
   local char=source:sub(pos,pos)
   if char=='<'then
    local nextChar=source:sub(pos+1,pos+1)
    if nextChar=='!'then
     pos=markupDeclaration(pos)
    elseif nextChar=='/'then
     local _,nameStop,name=source:find('^</%s*(%a[^%s/>]*)',pos)
     if nameStop then
      local close=source:find('>',nameStop+1,true)
      emit({type='endTag',name=string.lower(name),offset=pos})
      pos=(close or length)+1
     else
      local close=source:find('>',pos,true)
      note('tag','Fechamento invalido ignorado.',pos)
      pos=(close or length)+1
     end
    elseif nextChar:match('%a')then
     local _,nameStop,name=source:find('^<(%a[^%s/>]*)',pos)
     name=string.lower(name)
     local attrs,selfClosing,nextPos=readAttributes(nameStop+1)
     emit({type='startTag',name=name,attrs=attrs,selfClosing=selfClosing,offset=pos})
     pos=nextPos
     if not selfClosing then
      if T.rawtext[name]then mode='rawtext';rawTag=name
      elseif T.rcdata[name]then mode='rcdata';rawTag=name end
     end
    elseif nextChar=='?'then
     local close=source:find('>',pos,true)
     note('tag','Instrucao de processamento ignorada.',pos)
     pos=(close or length)+1
    else
     push('<')
     pos+=1
    end
   elseif char=='&'then
    local value,nextPos=Entities.consume(source,pos,false)
    if value then push(value);pos=nextPos else push('&');pos+=1 end
   else
    local stop=source:find('[<&]',pos)
    local chunk
    if stop then chunk=source:sub(pos,stop-1);pos=stop else chunk=source:sub(pos);pos=length+1 end
    push((chunk:gsub('%z',Entities.replacement)))
   end
  else
   local endStart,endStop=rawTextEnd(pos)
   local text=source:sub(pos,(endStart or length+1)-1)
   if mode=='rcdata'then text=Entities.decode(text,false)end
   push(text)
   if endStart then
    emit({type='endTag',name=rawTag,offset=endStart})
    pos=(endStop or length)+1
   else
    note('tag','Texto bruto nao fechado em <'..tostring(rawTag)..'>',pos)
    pos=length+1
   end
   mode='data'
   rawTag=nil
  end
 end
 flush()
 tokens[#tokens+1]={type='eof'}
 return tokens
end
return T
