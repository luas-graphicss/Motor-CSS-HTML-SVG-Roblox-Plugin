local Syntax={LIMIT=16000}
local ESCAPE={['&']='&amp;',['<']='&lt;',['>']='&gt;',['"']='&quot;',["'"]='&apos;'}
local GROUP={media=true,container=true,supports=true,layer=true,keyframes=true,['-webkit-keyframes']=true,scope=true,['starting-style']=true,document=true}
function Syntax.escape(text)
 return (string.gsub(text,'[&<>"\']',ESCAPE))
end
local function writer(colors)
 local out,count={},0
 local kind,parts,size=nil,{},0
 local function flush()
  if size==0 then return end
  local text=Syntax.escape(table.concat(parts,'',1,size))
  local color=kind and colors[kind]
  count+=1
  out[count]=color and ('<font color="#'..color..'">'..text..'</font>') or text
  table.clear(parts);size=0
 end
 local function emit(nextKind,text)
  if text=='' then return end
  if nextKind~='space' and nextKind~=kind then flush();kind=nextKind end
  size+=1;parts[size]=text
 end
 local function finish()
  flush()
  return table.concat(out,'',1,count)
 end
 return emit,finish
end
function Syntax.html(text,colors)
 local emit,finish=writer(colors)
 local i,n=1,#text
 while i<=n do
  local open=string.find(text,'<',i,true)
  if not open then emit('text',string.sub(text,i));break end
  if open>i then emit('text',string.sub(text,i,open-1))end
  if string.sub(text,open,open+3)=='<!--' then
   local close=string.find(text,'-->',open+4,true)
   local stop=close and close+2 or n
   emit('comment',string.sub(text,open,stop));i=stop+1
  elseif string.find(text,'^<[!?]',open) then
   local stop=string.find(text,'>',open,true) or n
   emit('comment',string.sub(text,open,stop));i=stop+1
  else
   local j=open+1
   if string.sub(text,j,j)=='/' then j+=1 end
   local nameStart,nameStop=string.find(text,'^[%a_][%w_:%.%-]*',j)
   if not nameStart then
    emit('text','<');i=open+1
   else
    emit('punct',string.sub(text,open,nameStart-1));emit('tag',string.sub(text,nameStart,nameStop));j=nameStop+1
    while j<=n do
     local c=string.sub(text,j,j)
     if c=='>' then emit('punct','>');j+=1;break
     elseif c=='/' and string.sub(text,j+1,j+1)=='>' then emit('punct','/>');j+=2;break
     elseif c=='<' then break
     elseif c=='"' or c=="'" then
      local close=string.find(text,c,j+1,true) or n
      emit('string',string.sub(text,j,close));j=close+1
     elseif c=='=' then emit('punct','=');j+=1
     elseif string.find(c,'^%s') then
      local _,stop=string.find(text,'^%s+',j)
      emit('space',string.sub(text,j,stop));j=stop+1
     else
      local _,stop=string.find(text,'^[^%s=>/<"\']+',j)
      stop=stop or j
      emit('attr',string.sub(text,j,stop));j=stop+1
     end
    end
    i=j
   end
  end
 end
 return finish()
end
function Syntax.css(text,colors)
 local emit,finish=writer(colors)
 local stack,depth={'rules'},1
 local mode,first,at='prelude',nil,nil
 local i,n=1,#text
 while i<=n do
  local c=string.sub(text,i,i)
  local top=stack[depth]
  if c=='/' and string.sub(text,i+1,i+1)=='*' then
   local close=string.find(text,'*/',i+2,true)
   local stop=close and close+1 or n
   emit('comment',string.sub(text,i,stop));i=stop+1
  elseif c=='"' or c=="'" then
   local j=i+1
   while j<=n do
    local d=string.sub(text,j,j)
    if d=='\\' then j+=2 elseif d==c or d=='\n' then break else j+=1 end
   end
   local stop=math.min(j,n)
   emit('string',string.sub(text,i,stop));i=stop+1
  elseif string.find(c,'^%s') then
   local _,stop=string.find(text,'^%s+',i)
   emit('space',string.sub(text,i,stop));i=stop+1
  elseif c=='{' then
   local kind=(top=='rules' and at and GROUP[at]) and 'rules' or 'decls'
   depth+=1;stack[depth]=kind
   emit('punct',c);i+=1
   mode=kind=='rules' and 'prelude' or 'property';first=nil;at=nil
  elseif c=='}' then
   if depth>1 then stack[depth]=nil;depth-=1 end
   emit('punct',c);i+=1
   mode=stack[depth]=='rules' and 'prelude' or 'property';first=nil;at=nil
  elseif c==';' then
   emit('punct',c);i+=1
   mode=top=='rules' and 'prelude' or 'property';first=nil;at=nil
  elseif c==':' and top=='decls' and mode=='property' then
   emit('punct',c);i+=1;mode='value'
  else
   local pattern=(top=='decls' and mode=='property') and '^[^%s{};:"\']+' or '^[^%s{};"\']+'
   local _,stop=string.find(text,pattern,i)
   stop=stop or i
   local word=string.sub(text,i,stop)
   local cut=string.find(word,'/*',2,true)
   if cut then stop=i+cut-2;word=string.sub(word,1,cut-1)end
   if top=='rules' then
    if not first then
     first=word
     local name=string.match(word,'^@([%w%-]+)')
     at=name and string.lower(name) or nil
    end
    emit(string.sub(word,1,1)=='@' and 'keyword' or (at and 'value' or 'tag'),word)
   elseif mode=='property' then
    emit('property',word)
   else
    emit(word=='!important' and 'important' or 'value',word)
   end
   i=stop+1
  end
 end
 return finish()
end
return Syntax
