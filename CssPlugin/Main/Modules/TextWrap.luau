local Values=require(script.Parent.FontFeatures)
local Seg=require(script.Parent.UnicodeSegmentation)
local T={VERSION=2,UAX14=Seg.UAX14}
T.defaults={['text-wrap-mode']='wrap',['text-wrap-style']='auto',['line-break']='auto',['hyphenate-character']='auto',['hyphenate-limit-chars']='auto',['hyphenate-limit-lines']='no-limit',['hyphenate-limit-zone']='0px',['unicode-bidi']='normal'}
T.properties={'text-wrap','word-wrap'};T.inherited={}
for k in pairs(T.defaults)do T.properties[#T.properties+1]=k;if k~='unicode-bidi'then T.inherited[#T.inherited+1]=k end end
table.sort(T.inherited)
T.shorthands={['text-wrap']={'text-wrap-mode','text-wrap-style'},['white-space']={'white-space','text-wrap-mode'},['word-wrap']={'overflow-wrap'}}
local whitespace={normal='wrap',nowrap='nowrap',pre='nowrap',['pre-wrap']='wrap',['pre-line']='wrap',['break-spaces']='wrap'}
local styles={auto=true,balance=true,pretty=true,stable=true}
function T.expand(name,value)
 local keys=T.shorthands[name];if not keys then return nil end
 if value=='initial'or value=='inherit'or value=='unset'or value=='revert'or value=='revert-layer'then local out={};for _,key in ipairs(keys)do out[key]=value end;return out end
 if name=='white-space'then assert(whitespace[value],'white-space não suportado.');return {['white-space']=value,['text-wrap-mode']=whitespace[value]}end
 if name=='word-wrap'then return {['overflow-wrap']=value}end
 local mode,style='wrap','auto';local seen={}
 for _,token in ipairs(Values.split(value,' '))do
  if token=='wrap'or token=='nowrap'then assert(not seen.mode,'text-wrap-mode repetido.');mode=token;seen.mode=true
  else assert(styles[token]and not seen.style,'text-wrap inválido.');style=token;seen.style=true end
 end
 assert(next(seen),'text-wrap vazio.');return {['text-wrap-mode']=mode,['text-wrap-style']=style}
end
function T.normalize(style,parent,length)
 for k,default in pairs(T.defaults)do
  local v=style[k]or default
  if v=='inherit'then v=parent and parent[k]or default elseif v=='initial'or v=='unset'and k=='unicode-bidi'then v=default
  elseif v=='unset'or v=='revert'or v=='revert-layer'then v=parent and parent[k]or default end
  style[k]=v
 end
 assert(style['text-wrap-mode']=='wrap'or style['text-wrap-mode']=='nowrap','text-wrap-mode aceita wrap/nowrap.')
 assert(styles[style['text-wrap-style']],'text-wrap-style aceita auto/balance/pretty/stable.')
 assert(({auto=true,loose=true,normal=true,strict=true,anywhere=true})[style['line-break']],'line-break inválido.')
 assert(({normal=true,embed=true,['bidi-override']=true,isolate=true,['isolate-override']=true,plaintext=true})[style['unicode-bidi']],'unicode-bidi inválido.')
 local character=style['hyphenate-character'];style._hyphenateCharacter=character=='auto'and '-'or Values.unquote(character)
 assert(utf8.len(style._hyphenateCharacter)and #style._hyphenateCharacter<=64,'hyphenate-character inválido ou longo demais.')
 local limits=Values.split(style['hyphenate-limit-chars'],' ');assert(#limits>=1 and #limits<=3,'hyphenate-limit-chars aceita 1..3 valores.')
 local parsed={}
 for i,v in ipairs(limits)do local n=v~='auto'and tonumber(v)or nil;assert(v=='auto'or n and n%1==0 and n>=1 and n<=8192,'hyphenate-limit-chars exige auto ou inteiro positivo.');parsed[i]=n end
 style._hyphenChars={parsed[1]or 6,parsed[2]or 2,parsed[3]or parsed[2]or 2}
 local lines=style['hyphenate-limit-lines'];local n=lines~='no-limit'and tonumber(lines)or nil
 assert(lines=='no-limit'or n and n%1==0 and n>=1 and n<=4096,'hyphenate-limit-lines inválido.');style._hyphenLines=n or math.huge
 local zone=style['hyphenate-limit-zone'];assert(zone=='0px'or zone=='0'or length,'Resolvedor de comprimento ausente.')
 style._hyphenZone=zone;return style
end
function T.nowrap(style)
 if style['text-wrap-mode']~=nil then return style['text-wrap-mode']=='nowrap'end
 return style['white-space']=='nowrap'or style['white-space']=='pre'
end
local noStart={};local noEnd={}
for _,cp in utf8.codes(')]}〉》」』】〕〗〙〛’”»、。，．？！：；!?,.:;％‰℃°')do noStart[cp]=true end
for _,cp in utf8.codes('([{〈《「『【〔〖〘〚‘“«')do noEnd[cp]=true end
local smallKana={};for _,cp in utf8.codes('ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶー々〻')do smallKana[cp]=true end
local function cp(s)return s and s~=''and utf8.codepoint(s)or 0 end
local function glue(n)return n==0xa0 or n==0x202f or n==0x2060 or n==0xfeff end
function T.cjk(text)
 local n=cp(text);return n>=0x2e80 and n<=0x9fff or n>=0xac00 and n<=0xd7af or n>=0xf900 and n<=0xfaff or n>=0xff01 and n<=0xff60 or n>=0x20000 and n<=0x3134f
end
function T.boundary(left,right,style)
 if not left or not right then return false end
 local a,b=cp(left),cp(right);local line=style['line-break']or 'auto'
 if line=='anywhere'then return true end
 if glue(a)or glue(b)or a==0x200d or b==0x200d then return false end
 if noEnd[a]or noStart[b]then return false end
 if line=='strict'and smallKana[b]then return false end
 if a==0x200b then return true end
 local word=style['word-break']or 'normal'
 if word=='break-all'then return true end
 if word=='manual'then return false end
 if word=='keep-all'and(T.cjk(left)or T.cjk(right))then return false end
 return Seg.canBreakAfter(left,right,{strict=line=='strict',eastAsian=style._language~=nil and(style._language:lower():match('^ja')or style._language:lower():match('^zh')or style._language:lower():match('^ko'))~=nil})
end
function T.dictionaryBreaks(chars,language,dictionaries)
 local language=(language or ''):lower();local short=language:match('^[a-z]+')or ''
 local words=dictionaries and(dictionaries[language]or dictionaries[short]);if not words then return {}end
 local set={};for key,v in pairs(words)do if type(key)=='number'and type(v)=='string'then set[v]=true elseif v==true then set[key]=true end end
 local points={};local i=1;local steps=0
 while i<=#chars do
  local text,last='',nil
  for j=i,math.min(#chars,i+63)do steps+=1;assert(steps<=524288,'Dicionário excedeu orçamento de segmentação.');text..=chars[j];if set[text]then last=j end end
  if last then if last<#chars then points[last]=true end;i=last+1 else i+=1 end
 end
 return points
end
function T.optimize(tokens,limit,measure,style,checkpoint)
 local mode=style['text-wrap-style']or 'auto';if T.nowrap(style)or(mode~='balance'and mode~='pretty')then return {}end
 local breaks={};local paragraph={};local pendingSpace=0
 local function flush()
  local n=#paragraph;if n<2 or n>256 then paragraph={};pendingSpace=0;return end
  local prefix={0};local lines,used=1,0
  for i,word in ipairs(paragraph)do
   if word.width>limit+.01 then paragraph={};pendingSpace=0;return end
   local w=word.width+(i>1 and word.space or 0)
   if used>0 and used+w>limit+.01 then lines+=1;used=word.width else used+=w end
   prefix[i+1]=prefix[i]+word.width+word.space
  end
  if lines<=1 or lines>128 then paragraph={};pendingSpace=0;return end
  local function width(first,last)return prefix[last+1]-prefix[first]-paragraph[first].space end
  local previous={[0]=0};local paths={};local operations=0
  for count=1,lines do
   local current={};paths[count]={}
   for finish=count,n do
    local best,chosen
    for first=finish,count,-1 do
     local w=width(first,finish);if w>limit+.01 then break end
     local old=previous[first-1]
     if old then
      local cost=(limit-w)^2
      if mode=='pretty'and finish==n then cost*=.12;if finish==first then cost+=limit*limit*2 end end
      local total=old+cost;if not best or total<best then best=total;chosen=first-1 end
     end
     operations+=1;if checkpoint and operations%1024==0 then checkpoint(16)end
    end
    if best then current[finish]=best;paths[count][finish]=chosen end
   end
   previous=current
  end
  if previous[n]then local at=n;for count=lines,2,-1 do local before=paths[count][at];if before and paragraph[before+1]then breaks[paragraph[before+1].index]=true;at=before end end end
  paragraph={};pendingSpace=0
 end
 for index,token in ipairs(tokens)do
  if token.kind=='break'then flush()
  elseif token.kind=='space'then
   if token.preserve then flush();return {}end
   local _,w=measure(token.atoms);pendingSpace+=w
  else
   local _,w=measure(token.atoms)
   paragraph[#paragraph+1]={index=index,width=w,space=#paragraph==0 and 0 or pendingSpace};pendingSpace=0
  end
 end
 flush();return breaks
end
return T
