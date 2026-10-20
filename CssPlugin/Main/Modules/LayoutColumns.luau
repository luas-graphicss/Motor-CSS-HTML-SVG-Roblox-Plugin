local P=require(script.Parent.LayoutProperties)
local Text=require(script.Parent.LayoutTextFlow)
local C={VERSION=1}
local function forced(v)return v=='column'or v=='always'end
local function avoid(v)return v=='avoid'or v=='avoid-column'end
local function avoidInside(v)return v=='avoid'or v=='avoid-column'or v=='avoid-page'or v=='avoid-region'end
local function integer(value,name)
 local n=tonumber(value or 2);assert(n and n%1==0 and n>=1 and n<=1024,name..' exige inteiro entre 1 e 1024.');return n
end
local blockers=table.freeze({'transform','rotate','scale','translate','filter','backdrop-filter','mask','mask-image','clip-path','mix-blend-mode','isolation','contain','content-visibility','column-count','column-width','view-transition-name','anchor-name'})
local decorations=table.freeze({'background-color','background-image','background','box-shadow','border-radius','border-top-left-radius','border-top-right-radius','border-bottom-right-radius','border-bottom-left-radius'})
local neutral=table.freeze({none=true,normal=true,visible=true,auto=true,['0px']=true,transparent=true,['0']=true})
local insetKeys=table.freeze({'left','right','top','bottom','inset','inset-block-start','inset-block-end','inset-inline-start','inset-inline-end'})
local function plain(cs)
 if(cs.display or'block')~='block'then return false end
 local position=cs.position or'static'
 if position~='static'and position~='relative'then return false end
 if position=='relative'then
  for _,key in ipairs(insetKeys)do
   local value=cs[key]
   if value~=nil and value~='auto'and value~='0px'and value~='0'then return false end
  end
 end
 if(cs.float or'none')~='none'or(cs.clear or'none')~='none'then return false end
 if(cs.overflow or'visible')~='visible'or(cs['overflow-x']or'visible')~='visible'or(cs['overflow-y']or'visible')~='visible'then return false end
 local opacity=tonumber(cs.opacity);if opacity and opacity<1 then return false end
 if not P.isAuto(cs.width)or not P.isAuto(cs.height)then return false end
 for _,key in ipairs(blockers)do
  local value=cs[key]
  if value~=nil and not neutral[tostring(value)]then return false end
 end
 local decorated=false
 for _,key in ipairs(decorations)do
  local value=cs[key]
  if value~=nil and not neutral[tostring(value)]then decorated=true;break end
 end
 return true,decorated
end
local function splittable(child,cs,c,ctx)
 if #child.children<2 then return false end
 if avoidInside(cs['break-inside'])then return false end
 local simple,decorated=plain(cs)
 if not simple then return false end
 for i=1,4 do if(c.p[i]or 0)~=0 or(c.m[i]or 0)~=0 then return false end end
 if Text.raw(child,ctx)~=''then return false end
 local flowing=0
 for _,grand in ipairs(child.children)do
  local gs=ctx.styles[grand.key]
  if not gs then return false end
  if gs.display~='none'then
   local position=gs.position or'static'
   if position~='static'and position~='relative'then return false end
   if(gs.float or'none')~='none'then return false end
   flowing+=1
  end
 end
 if flowing<2 then return false end
 return true,decorated
end
C.splittable=splittable
local function pagination(units,height,checkpoint)
 local ranges={};local start=1;local relaxed=false
 while start<=#units do
  local y,j,best,last=0,start,nil,start-1;local forcedEnd=false
  while j<=#units do
   local unit=units[j];local h=unit.h+(unit.before or 0)+(unit.after or 0)
   if j>start and unit.forceBefore then last=j-1;forcedEnd=true;break end
   if j>start and y+h>height+.001 then break end
   y+=h;last=j
   local nextUnit=units[j+1];local valid=true
   if nextUnit and nextUnit.entry==unit.entry and unit.entry.avoidInside then valid=false
   elseif nextUnit and nextUnit.entry==unit.entry and unit.text then
    local fragmentStart=math.max(start,unit.entry.first);local inFragment=j-fragmentStart+1;local remaining=unit.entry.last-j
    valid=inFragment>=unit.entry.orphans and remaining>=unit.entry.widows
   elseif nextUnit then valid=not unit.avoidAfter and not nextUnit.avoidBefore end
   if valid then best=j end
   if unit.forceAfter then forcedEnd=true;break end
   j+=1
  end
  if last<start then last=start;relaxed=true end
  if not forcedEnd and last<#units and best and best>=start then last=best
  elseif not forcedEnd and last<#units and not best then relaxed=true end
  local used=0;for k=start,last do local u=units[k];used+=u.h+(u.before or 0)+(u.after or 0)end
  ranges[#ranges+1]={first=start,last=last,h=used};start=last+1
  assert(#ranges<=4096,'Fragmentação excede 4096 colunas de overflow.');if checkpoint and #ranges%32==0 then checkpoint()end
 end
 return ranges,relaxed
end
C.paginate=pagination
function C.plan(node,flow,cw,ch,definiteH,ctx)
 local s,fs=ctx.info(node,cw,ch);local gy=math.max(0,ctx.length(s['row-gap'],cw,fs)or 0)
 local count=P.isAuto(s['column-count'])and nil or tonumber(s['column-count'])
 assert(P.isAuto(s['column-count'])or(count and count%1==0 and count>=1 and count<=64),'column-count aceita auto ou inteiro de 1 a 64.')
 local preferred=ctx.length(s['column-width'],cw,fs);assert(not preferred or preferred>0,'column-width deve ser positivo.')
 local explicit=s._important and s._important['column-gap']~=nil
 local gap=explicit and math.max(0,ctx.length(s['column-gap'],cw,fs)or fs)or fs
 if preferred then count=math.min(count or 64,math.max(1,math.floor((cw+gap)/(preferred+gap))))end
 count=count or 1;local width=math.max(0,(cw-gap*(count-1))/count)
 local fill=s['column-fill']or'balance';assert(fill=='auto'or fill=='balance'or fill=='balance-all','column-fill aceita auto, balance e balance-all.')
 local own=#flow==0 and Text.raw(node,ctx)~='';local children=own and{node}or flow
 local entries,rules,sets,hosts={},{},{},{};local cursor,usedW,usedH,maxUsedCols=0,cw,0,count;local ownEntry;local relaxed=false
 local fragmentsByHost={}
 local function set(list,beforeSpanner)
  if #list==0 then return end
  local units,localEntries={},{}
  local placement,hostRanges={},{}
  local function push(child,cs,c)
   local entry={node=child,c=c,first=#units+1,orphans=integer(cs.orphans,'orphans'),widows=integer(cs.widows,'widows'),avoidInside=avoidInside(cs['break-inside'])};localEntries[#localEntries+1]=entry;entries[#entries+1]=entry
   if own then ownEntry=entry end
   local text=Text.raw(child,ctx)
   if(own or Text.fragmentable(child,cs,c))and text~=''then
    local lh=Text.lineHeight(cs,c.fs);Text.wrap(text,cs,c.fs,function()return math.max(1,width-c.m[2]-c.m[4])end,function(line)units[#units+1]={entry=entry,h=lh,text=line};assert(#units<=4096,'Conjunto de colunas excede 4096 linhas.')end,ctx.checkpoint)
   else units[#units+1]={entry=entry,h=c.h}end
   entry.last=#units
   if units[entry.first]then
    units[entry.first].before=c.m[1];units[entry.first].forceBefore=forced(cs['break-before']);units[entry.first].avoidBefore=avoid(cs['break-before'])
    units[entry.last].after=c.m[3]+gy;units[entry.last].forceAfter=forced(cs['break-after']);units[entry.last].avoidAfter=avoid(cs['break-after'])
   end
   return entry
  end
  local function emit(child,depth)
   local cs=ctx.styles[child.key];local c
   if own then c={w=width,h=0,p={0,0,0,0},m={0,0,0,0},fs=fs}else c=ctx.measure(child,width,ch,nil,nil,false,ctx.depth+1)end
   local canSplit,decorated=splittable(child,cs,c,ctx)
   if not own and depth<4 and canSplit then
    hosts[#hosts+1]=child
    local hostRange={node=child,first=#units+1,decorated=decorated,clone=cs['box-decoration-break']=='clone'}
    hostRanges[#hostRanges+1]=hostRange
    for _,grand in ipairs(child.children)do
     local gs=ctx.styles[grand.key]
     if gs then
      if gs.display=='none'then
       local gc=ctx.measure(grand,width,ch,nil,nil,false,ctx.depth+1)
       local entry={node=grand,c=gc,first=#units+1,orphans=1,widows=1,avoidInside=false}
       localEntries[#localEntries+1]=entry;entries[#entries+1]=entry
       units[#units+1]={entry=entry,h=0};entry.last=#units
      else emit(grand,depth+1)end
     end
    end
    hostRange.last=#units
    return
   end
   push(child,cs,c)
  end
  for _,child in ipairs(list)do emit(child,0)end
  if #units==0 then return end
  units[#units].after=math.max(0,(units[#units].after or 0)-gy)
  local total,maxUnit=0,0;for _,unit in ipairs(units)do local h=unit.h+(unit.before or 0)+(unit.after or 0);total+=h;maxUnit=math.max(maxUnit,h)end
  local remaining=math.max(0,ch-cursor);local target
  if definiteH and fill=='auto'and not beforeSpanner then target=remaining
  else
   local low,high=math.max(maxUnit,total/count),math.max(total,maxUnit)
   for _=1,24 do local mid=(low+high)/2;if #pagination(units,mid,ctx.checkpoint)<=count then high=mid else low=mid end end
   target=high;if definiteH then target=math.min(remaining,target)end
  end
  local ranges,relax=pagination(units,target,ctx.checkpoint);relaxed=relaxed or relax
  local height=0
  for col,range in ipairs(ranges)do
   local y=cursor
   for i=range.first,range.last do local unit=units[i];local entry=unit.entry;local before,after=unit.before or 0,unit.after or 0
    local x=(col-1)*(width+gap)+entry.c.m[4];local top=y+before
    if not entry.x then entry.x=x;entry.y=top end
    if unit.text then Text.append(entry,x,top,math.max(0,width-entry.c.m[2]-entry.c.m[4]),unit.h,unit.text)end
    placement[i]={col=col,top=top,bottom=top+unit.h}
    y+=before+unit.h+after
   end
   height=math.max(height,y-cursor)
  end
  for _,host in ipairs(hostRanges)do
   if host.decorated and host.last then
    local order,slots={},{}
    for i=host.first,host.last do
     local at=placement[i]
     if at then
      local slot=slots[at.col]
      if slot then slot.top=math.min(slot.top,at.top);slot.bottom=math.max(slot.bottom,at.bottom);slot.first=math.min(slot.first,i);slot.last=math.max(slot.last,i)
      else slot={col=at.col,top=at.top,bottom=at.bottom,first=i,last=i};slots[at.col]=slot;order[#order+1]=slot end
     end
    end
    table.sort(order,function(a,b)return a.col<b.col end)
    local out=fragmentsByHost[host.node.key]
    if not out then out={};fragmentsByHost[host.node.key]=out end
    for _,slot in ipairs(order)do
     out[#out+1]={x=(slot.col-1)*(width+gap),y=slot.top,w=width,h=math.max(0,slot.bottom-slot.top),startEdge=host.clone or slot.first<=host.first,endEdge=host.clone or slot.last>=host.last}
    end
   end
  end
  local usedCols=math.max(count,#ranges);maxUsedCols=math.max(maxUsedCols,usedCols);usedW=math.max(usedW,usedCols*(width+gap)-gap)
  local ruleHeight=definiteH and not beforeSpanner and fill=='auto'and remaining or height
  for i=1,usedCols-1 do rules[#rules+1]={x=i*width+(i-.5)*gap,y=cursor,h=ruleHeight}end
  sets[#sets+1]={y=cursor,h=height,columns=usedCols};cursor+=height;usedH=math.max(usedH,cursor)
  Text.finish(localEntries)
 end
 local pending={}
 for _,child in ipairs(children)do
  local cs=ctx.styles[child.key];local value=cs['column-span']or'none';assert(value=='none'or value=='all','column-span aceita none/all.')
  if value=='all'and not own then
   set(pending,true);pending={}
   local c=ctx.measure(child,cw,ch,nil,nil,false,ctx.depth+1);cursor+=c.m[1]
   entries[#entries+1]={node=child,c=c,x=c.m[4],y=cursor,spanner=true};cursor+=c.h+c.m[3];usedH=math.max(usedH,cursor);usedW=math.max(usedW,c.w+c.m[2]+c.m[4])
  else pending[#pending+1]=child end
 end
 set(pending,false)
 local fragmentCount=0;for _,list in pairs(fragmentsByHost)do fragmentCount+=#list end
 local signature={count,width,gap,usedH,maxUsedCols,'hosts:'..#hosts,'frags:'..fragmentCount};for _,setInfo in ipairs(sets)do signature[#signature+1]=setInfo.y..':'..setInfo.h..':'..setInfo.columns end
 local result={items=own and{}or entries,usedW=usedW,usedH=usedH,columnCount=count,columnWidth=width,columnRules=rules,columnSignature=table.concat(signature,'|'),columnSets=sets,fragmentationRelaxed=relaxed,hosts=#hosts>0 and hosts or nil,hostFragments=fragmentCount>0 and fragmentsByHost or nil}
 if ownEntry then result.fragments=ownEntry.c.fragments;result.fragmentSignature=ownEntry.c.fragmentSignature end
 return result
end
return C
