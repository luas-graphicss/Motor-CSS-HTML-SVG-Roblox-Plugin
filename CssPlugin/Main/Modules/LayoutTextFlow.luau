local Inline=require(script.Parent.InlineText)
local U=require(script.Parent.Util)
local T={}
local tags={p=true,span=true,text=true,label=true,h1=true,h2=true,h3=true,td=true,th=true}
function T.raw(node,ctx)
 local s=ctx.styles[node.key];local text=Inline.source(node,ctx.objects,s)
 if node.rawText and text==node.text and s['white-space']=='pre-line'then return node.rawText end;return text
end
function T.fragmentable(node,s,c)
 if not tags[node.tag]or #node.children>0 or node.generated or node.hasGeneratedText or(s.height and s.height~='auto')or(s.width and s.width~='auto')or s['break-inside']=='avoid'or s['break-inside']=='avoid-column'or s['white-space']=='nowrap'or s['white-space']=='pre'then return false end
 for i=1,4 do if c.p[i]~=0 then return false end end
 return not s['box-shadow']or s['box-shadow']=='none'
end
function T.lineHeight(s,fs)return s._lineHeight or math.max(math.ceil(fs*1.25),Inline.metric('Ag',s).Y)end
function T.wrap(text,s,fs,getWidth,emit,checkpoint)
 local line,count='',0;local cache={};local cacheCount=0
 local function width(str)
  local v=cache[str];if v then return v end;v=Inline.metric(str,s).X
  if cacheCount<1024 then cache[str]=v;cacheCount+=1 end;return v
 end
 local function flush(force)
  if line==''and not force then return end;count+=1;assert(count<=4096,'Texto excede 4096 linhas fragmentadas.');emit(line);line='';if checkpoint and count%32==0 then checkpoint()end
 end
 local preserve=s['white-space']=='pre-line'or s['white-space']=='pre-wrap'or s['white-space']=='break-spaces'
 local newline=string.char(10);text=text:gsub(string.char(13)..newline,newline):gsub(string.char(13),newline)
 if not preserve then text=text:gsub('%s+',' ')end
 local p=1
 while p<=#text do
  local close=preserve and text:find(newline,p,true);local paragraph=text:sub(p,close and close-1 or #text)
  for word in paragraph:gmatch('%S+')do
   local candidate=line==''and word or line..' '..word
   if line~=''and width(candidate)>math.max(1,getWidth())then flush(false)end
   local breakWord=s['overflow-wrap']=='anywhere'or s['overflow-wrap']=='break-word'or s['word-break']=='break-all'
   if breakWord and line==''and width(word)>math.max(1,getWidth())then
    for _,grapheme in ipairs(require(script.Parent.TextUnicode).graphemes(word))do
     if line~=''and width(line..grapheme)>math.max(1,getWidth())then flush(false)end;line..=grapheme
    end
   else line=line==''and word or line..' '..word end
  end
  if close then flush(true);p=close+1 else break end
 end
 flush(false);return count
end
function T.append(entry,x,y,w,h,text)
 entry.c.fragments=entry.c.fragments or{};entry.c.fragments[#entry.c.fragments+1]={x=x-entry.x,y=y-entry.y,w=w,h=h,text=text}
end
function T.finish(entries)
 for _,entry in ipairs(entries)do if entry.c.fragments then
  local h=0;local sig={}
  for _,f in ipairs(entry.c.fragments)do if math.abs(f.x)<.001 then h=math.max(h,f.y+f.h)end;sig[#sig+1]=f.x..','..f.y..','..f.w..','..f.h..':'..#f.text..':'..f.text end
  entry.c.h=h;entry.c.w=entry.c.fragments[1]and entry.c.fragments[1].w or entry.c.w;entry.c.fragmentSignature=table.concat(sig,'|')
 end end
end
return T
