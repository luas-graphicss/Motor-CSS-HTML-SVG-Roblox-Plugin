local U=require(script.Parent.Util)
local Math=require(script.Parent.MathLength)
local Path=require(script.Parent.MotionPath)
local Overflow=require(script.Parent.Overflow)
local Bars=require(script.Parent.Scrollbars)
local S={VERSION=1,keys={},shorthands={}}
S.defaults={['scroll-snap-type']='none',['scroll-snap-align']='none',['scroll-snap-stop']='normal',['overscroll-behavior-x']='auto',['overscroll-behavior-y']='auto',['scrollbar-width']='auto',['scrollbar-color']='auto',['scrollbar-gutter']='auto',['scroll-behavior']='auto',['scroll-timeline-name']='none',['scroll-timeline-axis']='block',['view-timeline-name']='none',['view-timeline-axis']='block',['view-timeline-inset']='auto',['animation-timeline']='auto',['animation-range-start']='normal',['animation-range-end']='normal',['offset-path']='none',['offset-distance']='0px',['offset-rotate']='auto',['offset-anchor']='auto',['offset-position']='normal'}
local sides={'top','right','bottom','left'}
for _,base in ipairs({'scroll-margin','scroll-padding'})do
 local keys={};for _,side in ipairs(sides)do local k=base..'-'..side;keys[#keys+1]=k;S.defaults[k]=base=='scroll-padding'and'auto'or'0px'end;S.shorthands[base]=keys
 for _,axis in ipairs({'block','inline'})do
  local a,b=base..'-'..axis..'-start',base..'-'..axis..'-end';S.shorthands[base..'-'..axis]={a,b};S.keys[#S.keys+1]=a;S.keys[#S.keys+1]=b
 end
end
S.shorthands['overscroll-behavior']={'overscroll-behavior-x','overscroll-behavior-y'}
for _,base in ipairs({'scroll-timeline','view-timeline'})do
 S.shorthands[base]={base..'-name',base..'-axis'}
 if base=='view-timeline'then table.insert(S.shorthands[base],'view-timeline-inset')end
end
S.shorthands['animation-range']={'animation-range-start','animation-range-end'}
S.shorthands['offset']=Path.shorthand
for k in pairs(S.defaults)do S.keys[#S.keys+1]=k end
for _,k in ipairs({'overscroll-behavior-block','overscroll-behavior-inline'})do S.keys[#S.keys+1]=k end
S.axes={x=true,y=true,block=true,inline=true}
S.ranges={cover=true,contain=true,entry=true,exit=true,['entry-crossing']=true,['exit-crossing']=true}
function S.list(value)
 assert(type(value)=='string','Lista CSS inválida.')
 local out,start,depth,q,escape={},1,0,nil,false
 local function add(last)local v=U.trim(value:sub(start,last));assert(v~='','Lista CSS contém item vazio.');out[#out+1]=v;assert(#out<=64,'Lista CSS excede 64 itens.')end
 for i=1,#value do local c=value:sub(i,i)
  if q then if escape then escape=false elseif c==string.char(92)then escape=true elseif c==q then q=nil end
  elseif c=='"'or c=="'"then q=c elseif c=='('then depth+=1 elseif c==')'then depth-=1;assert(depth>=0,'Lista CSS desbalanceada.')elseif c==','and depth==0 then add(i-1);start=i+1 end
 end
 assert(not q and depth==0,'Lista CSS não fechada.');add(#value);return out
end
function S.cycle(list,index)return list[(index-1)%#list+1]end
function S.register(supported,shorthands)
 for _,k in ipairs(S.keys)do supported[k]=true end
 for k,v in pairs(S.shorthands)do supported[k]=true;shorthands[k]=v end
 Overflow.register(supported,shorthands)
end
local function wide(value)return value=='initial'or value=='inherit'or value=='unset'end
function S.endpoint(value,isEnd)
 local a=U.split(value,' ');assert(#a>=1 and #a<=2,'animation-range inválido: '..value)
 if a[1]=='normal'then assert(#a==1,'normal deve aparecer sozinho.');return {name='cover',offset=isEnd and '100%'or'0%',normal=true}end
 if S.ranges[a[1]]then
  if a[2]then Math.parse(a[2])end
  return {name=a[1],offset=a[2]or(isEnd and'100%'or'0%')}
 end
 assert(#a==1,'Nome de intervalo desconhecido: '..a[1]);Math.parse(a[1]);return {name='cover',offset=a[1]}
end
local function timelineShorthand(base,value)
 local names,axes,insets={},{},{}
 for _,item in ipairs(S.list(value))do
  local name,axis,inset;local lengths={}
  for _,token in ipairs(U.split(item,' '))do
   if token=='none'or token:match('^%-%-[%w_%-]+$')then assert(not name,'Nome de timeline repetido.');name=token
   elseif S.axes[token]then assert(not axis,'Eixo de timeline repetido.');axis=token
   else assert(base=='view-timeline','Token scroll-timeline inválido: '..token);assert(token=='auto'or pcall(Math.parse,token),'Inset de timeline inválido.');lengths[#lengths+1]=token end
  end
  assert(#lengths<=2,'view-timeline aceita até dois insets.');name=name or'none';axis=axis or'block';inset=#lengths>0 and table.concat(lengths,' ')or'auto'
  names[#names+1]=name;axes[#axes+1]=axis;insets[#insets+1]=inset
 end
 local out={[base..'-name']=table.concat(names,', '),[base..'-axis']=table.concat(axes,', ')}
 if base=='view-timeline'then out['view-timeline-inset']=table.concat(insets,', ')end;return out
end
function S.expand(name,value)
 if Overflow.shorthands[name]then return Overflow.expand(name,value)end
 local keys=S.shorthands[name];if not keys then return nil end
 if wide(value)then local out={};for _,k in ipairs(keys)do out[k]=value end;return out end
 if name=='offset'then return Path.expandOffset(value)end
 if name=='scroll-timeline'or name=='view-timeline'then return timelineShorthand(name,value)end
 if name=='animation-range'then
  local starts,ends={},{}
  for _,item in ipairs(S.list(value))do
   local a=U.split(item,' ');local first,last
   if a[1]=='normal'then assert(#a<=2 and(not a[2]or a[2]=='normal'),'animation-range inválido.');first,last='normal','normal'
   else
    local n=S.ranges[a[1]]and(a[2]and not S.ranges[a[2]]and 2 or 1)or 1
    first=table.concat(a,' ',1,n)
    if #a>n then last=table.concat(a,' ',n+1,#a)
    else last=S.ranges[a[1]]and a[1]..' 100%'or'normal'end
    S.endpoint(first,false);S.endpoint(last,true)
   end
   starts[#starts+1]=first;ends[#ends+1]=last
  end
  return {['animation-range-start']=table.concat(starts,', '),['animation-range-end']=table.concat(ends,', ')}
 end
 local a=U.split(value,' ');assert(#a>=1 and #a<=#keys,'Shorthand inválido: '..name)
 local values=#keys==4 and{a[1],a[2]or a[1],a[3]or a[1],a[4]or a[2]or a[1]}or{a[1],a[2]or a[1]}
 local out={};for i,k in ipairs(keys)do out[k]=values[i]end;return out
end
function S.normalize(style,parent)
 for _,k in ipairs(S.keys)do
  local v=style[k];local default=S.defaults[k]
  if v=='inherit'or(v=='unset'and k=='scrollbar-color')then style[k]=parent and parent[k]or default
  elseif v=='initial'or v=='unset'then style[k]=default end
 end
 if not style['scrollbar-color']and parent then style['scrollbar-color']=parent['scrollbar-color']end
 local snap=style['scroll-snap-type']
 if snap then local a=U.split(snap,' ');assert((a[1]=='none'and #a==1)or((S.axes[a[1]]or a[1]=='both')and #a==2 and(a[2]=='mandatory'or a[2]=='proximity')),'Use scroll-snap-type: x/y/block/inline/both mandatory/proximity, ou none.')end
 local align=style['scroll-snap-align'];if align then local a=U.split(align,' ');assert(#a>=1 and #a<=2,'scroll-snap-align exige 1 ou 2 valores.');for _,v in ipairs(a)do assert(v=='none'or v=='start'or v=='center'or v=='end','scroll-snap-align inválido.')end end
 local stop=style['scroll-snap-stop'];assert(not stop or stop=='normal'or stop=='always','scroll-snap-stop aceita normal/always.')
 for _,axis in ipairs({'x','y','block','inline'})do local v=style['overscroll-behavior-'..axis];assert(not v or v=='auto'or v=='contain'or v=='none','overscroll-behavior aceita auto/contain/none.')end
 Bars.normalize(style,parent)
 Overflow.normalize(style,parent)
 for _,base in ipairs({'scroll-margin','scroll-padding'})do
  for _,suffix in ipairs({'top','right','bottom','left','block-start','block-end','inline-start','inline-end'})do
   local v=style[base..'-'..suffix]
   if v and not(base=='scroll-padding'and v=='auto')then assert(base~='scroll-margin'or not v:find('%%'),'scroll-margin aceita comprimentos, não percentuais.');Math.parse(v)end
  end
 end
 for _,base in ipairs({'scroll-timeline','view-timeline'})do
  for _,v in ipairs(S.list(style[base..'-name']or'none'))do assert(v=='none'or v:match('^%-%-[%w_%-]+$'),'Timeline nomeada exige --nome.')end
  for _,v in ipairs(S.list(style[base..'-axis']or'block'))do assert(S.axes[v],'Eixo de timeline inválido.')end
 end
 for _,v in ipairs(S.list(style['view-timeline-inset']or'auto'))do local a=U.split(v,' ');assert(#a>=1 and #a<=2,'Inset exige 1 ou 2 valores.');for _,x in ipairs(a)do if x~='auto'then Math.parse(x)end end end
 for _,k in ipairs({'animation-range-start','animation-range-end'})do if style[k]then for _,v in ipairs(S.list(style[k]))do S.endpoint(v,k=='animation-range-end')end end end
 if not style['scrollbar-width']and parent then style['scrollbar-width']=parent['scrollbar-width']end
 if style['offset-path']or style['offset-distance']or style['offset-rotate']or style['offset-anchor']or style['offset-position']then Path.validate(style)end
end
function S.active(style)
 for _,k in ipairs(S.keys)do if style[k]and style[k]~=S.defaults[k]then return true end end
 return Overflow.active(style)
end
return S
