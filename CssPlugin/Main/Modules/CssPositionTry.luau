local U=require(script.Parent.Util)
local T={VERSION=1}
local ANY,BLOCK,INLINE,GENERIC,HORIZONTAL,VERTICAL='any','block','inline','generic','h','v'
local words=table.freeze({
 top={VERTICAL,1,1},bottom={VERTICAL,3,3},['span-top']={VERTICAL,1,2},['span-bottom']={VERTICAL,2,3},
 ['y-start']={VERTICAL,1,1},['y-end']={VERTICAL,3,3},['span-y-start']={VERTICAL,1,2},['span-y-end']={VERTICAL,2,3},
 left={HORIZONTAL,1,1},right={HORIZONTAL,3,3},['span-left']={HORIZONTAL,1,2},['span-right']={HORIZONTAL,2,3},
 ['x-start']={HORIZONTAL,1,1},['x-end']={HORIZONTAL,3,3},['span-x-start']={HORIZONTAL,1,2},['span-x-end']={HORIZONTAL,2,3},
 ['block-start']={BLOCK,1,1},['block-end']={BLOCK,3,3},['span-block-start']={BLOCK,1,2},['span-block-end']={BLOCK,2,3},
 ['self-block-start']={BLOCK,1,1},['self-block-end']={BLOCK,3,3},
 ['inline-start']={INLINE,1,1},['inline-end']={INLINE,3,3},['span-inline-start']={INLINE,1,2},['span-inline-end']={INLINE,2,3},
 ['self-inline-start']={INLINE,1,1},['self-inline-end']={INLINE,3,3},
 start={GENERIC,1,1},['end']={GENERIC,3,3},['span-start']={GENERIC,1,2},['span-end']={GENERIC,2,3},
 ['self-start']={GENERIC,1,1},['self-end']={GENERIC,3,3},
 center={ANY,2,2},['span-all']={ANY,1,3},
})
local tacticNames=table.freeze({['flip-block']=true,['flip-inline']=true,['flip-start']=true})
local orders=table.freeze({normal=true,['most-width']=true,['most-height']=true,['most-block-size']=true,['most-inline-size']=true})
local visibilities=table.freeze({always=true,['anchors-valid']=true,['anchors-visible']=true,['no-overflow']=true})
T.tactics=tacticNames
T.keywords=words
local function axisOf(spec,index,vertical,rtl,blockReverse)
 local kind,from,to=spec[1],spec[2],spec[3]
 local axis,reverse
 if kind==VERTICAL then axis='v';reverse=false
 elseif kind==HORIZONTAL then axis='h';reverse=false
 elseif kind==BLOCK then axis=vertical and'h'or'v';reverse=blockReverse==true
 elseif kind==INLINE then axis=vertical and'v'or'h';reverse=rtl==true
 elseif index==1 then axis=vertical and'h'or'v';reverse=blockReverse==true
 else axis=vertical and'v'or'h';reverse=rtl==true end
 if reverse then from,to=4-to,4-from end
 return axis,from,to
end
function T.area(value,vertical,rtl,blockReverse)
 local lower=U.trim(tostring(value)):lower()
 if lower==''or lower=='none'then return nil end
 local list=U.split(lower,' ')
 assert(#list>=1 and #list<=2,'position-area aceita 1 ou 2 palavras-chave.')
 local specs={}
 for i,word in ipairs(list)do specs[i]=assert(words[word],'position-area inválido: '..word)end
 if #specs==1 then
  local kind=specs[1][1]
  specs[2]=(kind==ANY or kind==GENERIC)and specs[1]or words['span-all']
 end
 local out={}
 for i=1,2 do
  local spec=specs[i]
  if spec[1]~=ANY then
   local axis,from,to=axisOf(spec,i,vertical,rtl,blockReverse)
   assert(not out[axis],'position-area repete o mesmo eixo: '..lower)
   out[axis]={from,to}
  end
 end
 for i=1,2 do
  local spec=specs[i]
  if spec[1]==ANY then
   local axis=(not out.v)and'v'or'h'
   assert(not out[axis],'position-area repete o mesmo eixo: '..lower)
   out[axis]={spec[2],spec[3]}
  end
 end
 return {rows=out.v or{1,3},cols=out.h or{1,3}}
end
function T.rect(area,anchor,containing)
 local xs={0,anchor.x,anchor.x+anchor.width,containing.w}
 local ys={0,anchor.y,anchor.y+anchor.height,containing.h}
 local x1,x2=xs[area.cols[1]],xs[area.cols[2]+1]
 local y1,y2=ys[area.rows[1]],ys[area.rows[2]+1]
 return math.min(x1,x2),math.min(y1,y2),math.abs(x2-x1),math.abs(y2-y1)
end
function T.alignment(area)
 local function pick(range)
  if range[2]<2 then return 'end'end
  if range[1]>2 then return 'start'end
  return 'center'
 end
 return pick(area.cols),pick(area.rows)
end
function T.align(rx,ry,rw,rh,w,h,alignH,alignV)
 local function at(space,mode)
  if mode=='center'then return space/2 elseif mode=='end'then return space end
  return 0
 end
 return rx+at(rw-w,alignH),ry+at(rh-h,alignV)
end
function T.fallbacks(value)
 local lower=U.trim(tostring(value)):lower()
 if lower==''or lower=='none'then return nil end
 local out={}
 for _,entry in ipairs(U.split(lower,','))do
  local item={flips={}};local seen={};local area={}
  for _,word in ipairs(U.split(entry,' '))do
   if tacticNames[word]then
    assert(not seen[word],'position-try-fallbacks repete '..word..'.');seen[word]=true;item.flips[#item.flips+1]=word
   elseif word:match('^%-%-[%w_%-]+$')then
    assert(not item.name,'Use um único --nome por alternativa em position-try-fallbacks.');item.name=word
   else
    assert(words[word],'position-try-fallbacks inválido: '..word);area[#area+1]=word
   end
  end
  if #area>0 then
   assert(not item.name and #item.flips==0,'Combine <position-area> apenas com outros <position-area>.')
   item.area=table.concat(area,' ')
  end
  assert(item.name or item.area or #item.flips>0,'Alternativa vazia em position-try-fallbacks.')
  assert(#out<16,'Máximo de 16 alternativas em position-try-fallbacks.')
  out[#out+1]=item
 end
 assert(#out>0,'position-try-fallbacks vazio.')
 return out
end
function T.order(value)
 local lower=U.trim(tostring(value)):lower();assert(orders[lower],'position-try-order inválido: '..lower);return lower
end
function T.visibility(value)
 local lower=U.trim(tostring(value)):lower();assert(visibilities[lower],'position-visibility inválido: '..lower);return lower
end
function T.expandShorthand(value)
 local trimmed=U.trim(tostring(value));assert(trimmed~='','position-try vazio.')
 local first=U.split(trimmed,' ')[1]
 if first and orders[first:lower()]then
  local rest=U.trim(trimmed:sub(#first+1))
  assert(rest~='','position-try exige as alternativas após a ordem.')
  return first:lower(),rest
 end
 return 'normal',trimmed
end
function T.flip(x,y,w,h,tactic,anchor)
 if tactic=='flip-block'then return x,2*(anchor.y+anchor.height/2)-y-h,w,h end
 if tactic=='flip-inline'then return 2*(anchor.x+anchor.width/2)-x-w,y,w,h end
 return anchor.x+(y-anchor.y),anchor.y+(x-anchor.x),h,w
end
function T.flipArea(area,tactic)
 local rows,cols=area.rows,area.cols
 if tactic=='flip-block'then return {rows={4-rows[2],4-rows[1]},cols={cols[1],cols[2]}}end
 if tactic=='flip-inline'then return {rows={rows[1],rows[2]},cols={4-cols[2],4-cols[1]}}end
 return {rows={cols[1],cols[2]},cols={rows[1],rows[2]}}
end
function T.overflow(x,y,w,h,clip)
 local left=math.max(0,clip.x-x);local top=math.max(0,clip.y-y)
 local right=math.max(0,(x+w)-(clip.x+clip.w));local bottom=math.max(0,(y+h)-(clip.y+clip.h))
 local visibleW=math.max(0,math.min(x+w,clip.x+clip.w)-math.max(x,clip.x))
 local visibleH=math.max(0,math.min(y+h,clip.y+clip.h)-math.max(y,clip.y))
 return left+right+top+bottom,visibleW,visibleH
end
function T.choose(candidates,order)
 for _,c in ipairs(candidates)do if c.overflow<=0.001 then return c end end
 if order==nil or order=='normal'then return candidates[1]end
 local key=(order=='most-width'or order=='most-inline-size')and'visibleW'or'visibleH'
 local best=candidates[1]
 for _,c in ipairs(candidates)do if c[key]>best[key]+0.001 then best=c end end
 return best
end
local function pieces(value)
 local out={};local depth=0;local current={}
 for i=1,#value do
  local ch=value:sub(i,i)
  if ch=='('then depth+=1 elseif ch==')'then depth=math.max(0,depth-1)end
  if depth==0 and(ch==' 'or ch=='\t'or ch=='\n')then
   if #current>0 then out[#out+1]=table.concat(current);current={}end
  else current[#current+1]=ch end
 end
 if #current>0 then out[#out+1]=table.concat(current)end
 return out
end
local function box4(value,label)
 local list=pieces(U.trim(tostring(value)))
 assert(#list>=1 and #list<=4,label..' aceita de 1 a 4 valores em @position-try.')
 local top=list[1];local right=list[2]or top;local bottom=list[3]or top;local left=list[4]or right
 return top,right,bottom,left
end
local function pair2(value,label)
 local list=pieces(U.trim(tostring(value)))
 assert(#list>=1 and #list<=2,label..' aceita 1 ou 2 valores em @position-try.')
 return list[1],list[2]or list[1]
end
local blockShorthands={
 inset=function(value,into)local t,r,b,l=box4(value,'inset');into.top=t;into.right=r;into.bottom=b;into.left=l end,
 margin=function(value,into)local t,r,b,l=box4(value,'margin');into['margin-top']=t;into['margin-right']=r;into['margin-bottom']=b;into['margin-left']=l end,
 ['inset-block']=function(value,into)local a,b=pair2(value,'inset-block');into['inset-block-start']=a;into['inset-block-end']=b end,
 ['inset-inline']=function(value,into)local a,b=pair2(value,'inset-inline');into['inset-inline-start']=a;into['inset-inline-end']=b end,
 ['margin-block']=function(value,into)local a,b=pair2(value,'margin-block');into['margin-block-start']=a;into['margin-block-end']=b end,
 ['margin-inline']=function(value,into)local a,b=pair2(value,'margin-inline');into['margin-inline-start']=a;into['margin-inline-end']=b end,
 ['place-self']=function(value,into)local a,b=pair2(value,'place-self');into['align-self']=a;into['justify-self']=b end,
}
T.blockShorthands=blockShorthands
T.pieces=pieces
local blockProperties={}
for _,key in ipairs({'top','right','bottom','left','inset','width','height','min-width','min-height','max-width','max-height','align-self','justify-self','place-self','position-anchor','position-area','margin','inset-block','inset-inline','margin-block','margin-inline'})do blockProperties[key]=true end
for _,side in ipairs({'top','right','bottom','left'})do blockProperties['margin-'..side]=true end
for _,axis in ipairs({'inline','block'})do
 blockProperties[axis..'-size']=true;blockProperties['min-'..axis..'-size']=true;blockProperties['max-'..axis..'-size']=true
 for _,edge in ipairs({'start','end'})do blockProperties['inset-'..axis..'-'..edge]=true;blockProperties['margin-'..axis..'-'..edge]=true end
end
T.blockProperties=table.freeze(blockProperties)
local logicalEdges=table.freeze({inset={block={'blockStart','blockEnd'},inline={'inlineStart','inlineEnd'}},margin={block={'blockStart','blockEnd'},inline={'inlineStart','inlineEnd'}}})
function T.physical(key,axes)
 local base,axis,edge=key:match('^(%a+)%-(%a+)%-(%a+)$')
 local group=base and logicalEdges[base]
 local pair=group and group[axis]
 if pair and(edge=='start'or edge=='end')then
  local side=axes[pair[edge=='start'and 1 or 2]]
  if side then return base=='inset'and side or 'margin-'..side end
 end
 local prefix,sizeAxis=key:match('^(.-)(%a+)%-size$')
 if sizeAxis=='inline'or sizeAxis=='block'then
  local horizontal=(sizeAxis=='inline')~=(axes.vertical==true)
  return prefix..(horizontal and'width'or'height')
 end
 return key
end
function T.blocks(list)
 local map={}
 for _,entry in ipairs(list or{})do
  local declarations={}
  for _,d in ipairs(entry.declarations or{})do
   local property=d.key or d.property or d[1];local value=d.value or d[2]
   if property then
    assert(blockProperties[property],'Propriedade não aceita em @position-try: '..property)
    assert(not d.important,'!important não é aceito em @position-try.')
    local raw=type(value)=='table'and value.value or value
    local expand=blockShorthands[property]
    if expand then expand(raw,declarations)else declarations[property]=raw end
   end
  end
  if declarations['position-area']then T.area(declarations['position-area'],false,false,false)end
  map[entry.name]=declarations
 end
 return map
end
function T.blockUsage(block)
 local anchor,container=false,false
 if type(block)~='table'then return anchor,container end
 if block['position-anchor']or block['position-area']then anchor=true end
 for _,value in pairs(block)do
  if type(value)=='string'then
   local lower=value:lower()
   if lower:find('anchor%s*%(')or lower:find('anchor%-size%s*%(')then anchor=true end
   if lower:match('[%d%.]cq[%a]+')then container=true end
  end
 end
 return anchor,container
end
function T.uses(style)
 return style['position-area']~=nil or style['position-try-fallbacks']~=nil or style['position-try']~=nil
end
function T.install(supports)
 supports.register('position-area',function(value)
  if U.trim(value):lower()=='none'then return true end
  return T.area(value,false,false,false)~=nil
 end)
 supports.register('position-try-fallbacks',function(value)T.fallbacks(value);return true end)
 supports.register('position-try-order',function(value)return orders[U.trim(value):lower()]==true end)
 supports.register('position-visibility',function(value)return visibilities[U.trim(value):lower()]==true end)
 supports.register('position-try',function(value)local _,fallbacks=T.expandShorthand(value);T.fallbacks(fallbacks);return true end)
end
return T
