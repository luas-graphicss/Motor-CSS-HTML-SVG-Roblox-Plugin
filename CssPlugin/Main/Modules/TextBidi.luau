local Uax9=require(script.Parent.TextBidiUax9)
local B={VERSION=2,UAX9=Uax9.UAX9}
local function kind(cp)
 local c=Uax9.class(cp)
 if c=='L'then return 'ltr'elseif c=='R'or c=='AL'then return 'rtl'elseif c=='EN'or c=='AN'then return 'number'elseif c=='NSM'then return 'mark'end
 return 'neutral'
end
B.kind=kind
function B.class(text)
 local number=false
 for _,cp in utf8.codes(text or '')do local k=kind(cp);if k=='ltr'or k=='rtl'then return k elseif k=='number'then number=true end end
 return number and 'number'or 'neutral'
end
function B.direction(text)local k=B.class(text);return k=='number'and 'ltr'or(k=='ltr'or k=='rtl')and k or nil end
function B.firstStrong(text,fallback)
 local points={};for _,cp in utf8.codes(text or '')do points[#points+1]=cp end
 local types={};for i,cp in ipairs(points)do types[i]=Uax9.class(cp)end
 local i=1
 while i<=#types do
  local t=types[i]
  if t=='L'then return 'ltr'elseif t=='R'or t=='AL'then return 'rtl'
  elseif t=='LRI'or t=='RLI'or t=='FSI'then local depth=1;i+=1;while i<=#types and depth>0 do if types[i]=='LRI'or types[i]=='RLI'or types[i]=='FSI'then depth+=1 elseif types[i]=='PDI'then depth-=1 end;i+=1 end;i-=1 end
  i+=1
 end
 return fallback or 'ltr'
end
local function nextLevel(parent,dir)
 local level=parent and parent.level or 0;local wanted=dir=='rtl'and 1 or 0
 local n=level+1;if n%2~=wanted then n+=1 end;assert(n<=Uax9.MAX_DEPTH,'Bidi excede 125 níveis.');return n
end
function B.root(direction)return {direction=direction or 'ltr',level=direction=='rtl'and 1 or 0,root=true}end
function B.scope(style,parent,text)
 local mode=style['unicode-bidi']or 'normal';if mode=='normal'then return parent end
 local direction=mode=='plaintext'and B.firstStrong(text,style.direction)or style.direction or 'ltr'
 return {parent=parent,direction=direction,level=nextLevel(parent,direction),mode=mode,isolate=mode=='isolate'or mode=='isolate-override'or mode=='plaintext',override=mode=='bidi-override'or mode=='isolate-override',plaintext=mode=='plaintext'}
end
function B.consume(raw,state,following)
 local cp=utf8.codepoint(raw)
 local explicit=cp==0x202a or cp==0x202b or cp==0x202d or cp==0x202e or cp==0x2066 or cp==0x2067 or cp==0x2068
 if explicit then
  local direction=(cp==0x202b or cp==0x202e or cp==0x2067)and 'rtl'or 'ltr';if cp==0x2068 then direction=B.firstStrong(following,state.current.direction)end
  local parent=state.current
  local isolate=cp>=0x2066;local override=cp==0x202d or cp==0x202e
  state.current={parent=parent,direction=direction,level=nextLevel(parent,direction),isolate=isolate,override=override,control=true,mode=cp==0x2068 and 'plaintext'or isolate and 'isolate'or override and 'bidi-override'or 'embed'}
  return true
 elseif cp==0x202c then
  if state.current.control and not state.current.isolate then state.current=state.current.parent end;return true
 elseif cp==0x2069 then
  local current=state.current
  while current and current.control do if current.isolate then state.current=current.parent;break end;current=current.parent end
  return true
 end
 return false
end
local function chain(scope,within)
 local list={};local s=scope
 while s and s~=within and not s.root do table.insert(list,1,s);s=s.parent end
 return list
end
local function nearestOverride(scope,within)
 local s=scope
 while s and s~=within and not s.root do if s.override then return s.direction end;s=s.parent end
 return nil
end
function B.levels(items,base,within)
 local points,owner={},{}
 local function push(text,index)for _,cp in utf8.codes(text)do points[#points+1]=cp;owner[#owner+1]=index end end
 local current={}
 for i,item in ipairs(items)do
  local target=chain(item.bidi,within)
  local k=1;while current[k]and target[k]and current[k]==target[k]do k+=1 end
  for j=#current,k,-1 do local _,close=Uax9.controls(current[j].mode or(current[j].isolate and 'isolate'or current[j].override and 'bidi-override'or 'embed'),current[j].direction);push(close,false);current[j]=nil end
  for j=k,#target do local open=Uax9.controls(target[j].mode or(target[j].isolate and 'isolate'or target[j].override and 'bidi-override'or 'embed'),target[j].direction);push(open,false);current[j]=target[j]end
  local text=item.text
  if item.atomic then text=utf8.char(0xfffc)elseif item.edge then text=utf8.char(0x2060)elseif not text or text==''then text=utf8.char(0x2060)end
  push(text,i)
 end
 for j=#current,1,-1 do local _,close=Uax9.controls(current[j].mode or(current[j].isolate and 'isolate'or current[j].override and 'bidi-override'or 'embed'),current[j].direction);push(close,false)end
 local levels,paragraph=Uax9.resolve(points,base=='rtl'and 1 or 0)
 local out={}
 for p,index in ipairs(owner)do if index and out[index]==nil then out[index]=levels[p]end end
 for i=1,#items do if out[i]==nil then out[i]=i>1 and out[i-1]or(base=='rtl'and 1 or 0)end end
 return out,paragraph
end
function B.visualOrder(items,base,within)
 base=base or 'ltr'
 if #items==0 then return {}end
 local levels=B.levels(items,base,within)
 local order=Uax9.reorder(levels)
 local out={}
 for visual,index in ipairs(order)do
  local q=table.clone(items[index]);q.level=levels[index]
  q.direction=q.level%2==1 and 'rtl'or 'ltr'
  if q.atomic or q.edge then q.direction=items[index].direction or q.direction end
  local override=nearestOverride(q.bidi,within);if override then q.bidiOverride=override;q.direction=override end
  out[visual]=q
 end
 return out
end
function B.paintText(text,override)
 if override then return utf8.char(override=='rtl'and 0x202e or 0x202d)..text..utf8.char(0x202c)end
 return text
end
B.mirror=Uax9.mirror;B.mirrored=Uax9.mirrored;B.runs=Uax9.runs;B.resolve=Uax9.resolve;B.reorder=Uax9.reorder
return B
