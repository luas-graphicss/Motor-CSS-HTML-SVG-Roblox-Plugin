local U=require(script.Parent.Util)
local Performance=require(script.Parent.Performance)
local Dom=require(script.Parent.SvgDom)
local S={VERSION='svg-smil-2'}
S.tags={animate=true,animatetransform=true,animatemotion=true,set=true,mpath=true}
S.colorAttributes={fill=true,stroke=true,['stop-color']=true,['flood-color']=true,['lighting-color']=true,color=true}
S.events={click=true,mousedown=true,mouseup=true,mouseover=true,mouseout=true,mousemove=true,activate=true,focusin=true,focusout=true,beginevent=true,endevent=true,repeatevent=true}
S.limits={animations=96,intervals=64,events=64,values=64}
local INF=math.huge
local plans=setmetatable({},{__mode='k'})
local function trim(s)return(tostring(s or''):gsub('^%s+',''):gsub('%s+$',''))end
local function fmt(v)return string.format('%.6g',v)end
function S.time(text)
 if text==nil then return nil end
 local s=trim(text)
 if s==''or s=='indefinite'or s=='media'then return nil end
 local sign=1
 if s:sub(1,1)=='-'then sign=-1;s=trim(s:sub(2))elseif s:sub(1,1)=='+'then s=trim(s:sub(2))end
 local h,m,sec=s:match('^(%d+):(%d%d):([%d%.]+)$')
 if h then return sign*(tonumber(h)*3600+tonumber(m)*60+tonumber(sec))end
 local mm,ss=s:match('^(%d+):([%d%.]+)$')
 if mm then return sign*(tonumber(mm)*60+tonumber(ss))end
 local n,unit=s:match('^([%d%.]+)%s*(%a*)$')
 n=tonumber(n)
 if not n then return nil end
 unit=unit:lower()
 if unit==''or unit=='s'then return sign*n elseif unit=='ms'then return sign*n/1000 elseif unit=='min'then return sign*n*60 elseif unit=='h'then return sign*n*3600 end
 return nil
end
local function offsetOf(text)
 if text==nil or trim(text)==''then return 0 end
 return S.time(text)or 0
end
local function timing(text)
 local out={}
 for item in tostring(text or''):gmatch('[^;]+')do
  local s=trim(item)
  if s=='indefinite'then out[#out+1]={kind='indefinite'}
  elseif s:match('^[%+%-]?[%d%.:]+%s*%a*$')then local t=S.time(s);if t then out[#out+1]={kind='offset',offset=t}end
  else
   local base,rest=s:match('^([%w_%-%.]+)(.*)$')
   if base then
    local ref,name=base:match('^([%w_%-]+)%.([%w]+)$')
    local off=offsetOf(rest)
    if ref and(name=='begin'or name=='end')then out[#out+1]={kind='sync',ref=ref,which=name,offset=off}
    elseif ref and S.events[name:lower()]then out[#out+1]={kind='event',ref=ref,name=name:lower(),offset=off}
    elseif not ref and S.events[base:lower()]then out[#out+1]={kind='event',name=base:lower(),offset=off}
    end
   end
  end
 end
 return out
end
local function splitValues(text)
 local out={}
 for item in tostring(text):gmatch('[^;]+')do local s=trim(item);if s~=''then out[#out+1]=s end end
 assert(#out<=S.limits.values,'SMIL values acima do limite.')
 return out
end
local function numberList(text)
 local out={}
 for item in tostring(text or''):gmatch('[^;]+')do for _,n in ipairs(U.numbers(item))do out[#out+1]=n end end
 return out
end
local function splines(text)
 local out={}
 for item in tostring(text or''):gmatch('[^;]+')do
  local n=U.numbers(item)
  if #n==4 then out[#out+1]=n end
 end
 return out
end
function S.plan(source)
 if type(source)~='table'then return nil end
 local cached=plans[source]
 if cached~=nil then return cached or nil end
 local ids,keys,parents,order={},{},{},{}
 local function harvest(node,parent)
  if node.attrs and node.attrs.id then ids[node.attrs.id]=node.key end
  keys[node.key]=node;parents[node.key]=parent;order[#order+1]=node
  for _,child in ipairs(node.children or{})do harvest(child,node)end
 end
 harvest(source,nil)
 local animations={};local events=false
 for index,node in ipairs(order)do
  local tag=node.tag
  if tag=='animate'or tag=='set'or tag=='animatetransform'or tag=='animatemotion'then
   local a=node.attrs or{}
   local ref=Dom.reference(a)
   local target=ref and ids[ref]or(parents[node.key]and parents[node.key].key)
   if target then
    local kind=tag=='set'and'set'or tag=='animatetransform'and'transform'or tag=='animatemotion'and'motion'or'animate'
    local attr=trim(a.attributename or''):lower()
    if kind=='transform'or kind=='motion'then attr='transform'end
    if attr~=''then
     local anim={key=node.key,order=index,target=target,attr=attr,kind=kind}
     anim.dur=S.time(a.dur)
     anim.begins=timing(a.begin or'0s')
     anim.ends=a['end']~=nil and timing(a['end'])or nil
     local rc=trim(a.repeatcount or'')
     anim.repeatCount=rc=='indefinite'and INF or tonumber(rc)or nil
     anim.repeatDur=S.time(a.repeatdur)
     anim.freeze=trim(a.fill or''):lower()=='freeze'
     anim.restart=trim(a.restart or'always'):lower()
     anim.additive=trim(a.additive or''):lower()=='sum'
     anim.accumulate=trim(a.accumulate or''):lower()=='sum'
     anim.calc=trim(a.calcmode or(kind=='motion'and'paced'or'linear')):lower()
     if kind=='set'then anim.calc='discrete';anim.to=a.to
     else
      if a.values~=nil then anim.values=splitValues(a.values)end
      anim.from=a.from;anim.to=a.to;anim.by=a.by
     end
     if a.keytimes~=nil then anim.keyTimes=numberList(a.keytimes)end
     if a.keysplines~=nil then anim.keySplines=splines(a.keysplines)end
     if kind=='transform'then anim.type=trim(a.type or'translate')end
     if kind=='motion'then
      local path=a.path
      for _,child in ipairs(node.children or{})do
       if child.tag=='mpath'then local mref=Dom.reference(child.attrs);local pathNode=mref and keys[ids[mref]];if pathNode and pathNode.attrs and pathNode.attrs.d then path=pathNode.attrs.d end end
      end
      anim.path=path
      anim.rotate=trim(a.rotate or'0')
      if a.keypoints~=nil then anim.keyPoints=numberList(a.keypoints)end
     end
     for _,b in ipairs(anim.begins)do if b.kind=='event'then events=true end end
     for _,e in ipairs(anim.ends or{})do if e.kind=='event'then events=true end end
     animations[#animations+1]=anim
     assert(#animations<=S.limits.animations,'SMIL acima de '..S.limits.animations..' animações por SVG.')
    end
   end
  end
 end
 if #animations==0 then plans[source]=false;return nil end
 local byId={}
 for _,anim in ipairs(animations)do local node=keys[anim.key];if node.attrs.id then byId[node.attrs.id]=anim end end
 local plan={animations=animations,ids=ids,byId=byId,events=events,keys=keys}
 plans[source]=plan
 return plan
end
local function activeDuration(anim)
 local dur=anim.dur
 local out=INF
 if dur then
  if anim.repeatCount then out=anim.repeatCount==INF and INF or dur*anim.repeatCount
  elseif not anim.repeatDur then out=dur end
 end
 if anim.repeatDur then out=math.min(out,anim.repeatDur)end
 return out
end
local function eventInstances(list,spec,anim,plan,out)
 local target=spec.ref and plan.ids[spec.ref]or anim.target
 if not target then return end
 for _,event in ipairs(list)do
  if event.name==spec.name or(spec.name=='activate'and event.name=='click')then
   for _,key in ipairs(event.chain)do if key==target then out[#out+1]=event.time+spec.offset;break end end
  end
 end
end
local function instances(specs,anim,plan,resolved,events)
 local out={}
 for _,spec in ipairs(specs)do
  if spec.kind=='offset'then out[#out+1]=spec.offset
  elseif spec.kind=='sync'then
   local ref=plan.byId[spec.ref];local list=ref and resolved[ref]
   if list then for _,iv in ipairs(list)do local t=spec.which=='begin'and iv.b or iv.e;if t<INF then out[#out+1]=t+spec.offset end end end
  elseif spec.kind=='event'then eventInstances(events,spec,anim,plan,out)end
 end
 table.sort(out)
 return out
end
local function intervalsOf(anim,plan,resolved,events)
 local begins=instances(anim.begins,anim,plan,resolved,events)
 local list={}
 if #begins==0 then return list end
 local ends=anim.ends and instances(anim.ends,anim,plan,resolved,events)or nil
 local active=activeDuration(anim)
 local previousEnd=-INF;local index=1
 while index<=#begins and #list<S.limits.intervals do
  local b=begins[index];index+=1
  if b>=previousEnd then
   local e=b+active
   if ends then for _,t in ipairs(ends)do if t>=b then e=math.min(e,t);break end end end
   if anim.restart=='always'then for j=index,#begins do local nb=begins[j];if nb>b and nb<e then e=nb;break end end end
   list[#list+1]={b=b,e=e}
   if e==INF or anim.restart=='never'then break end
   previousEnd=e
  end
 end
 return list
end
local function progressAt(anim,t)
 local dur=anim.dur
 if not dur or dur<=0 then return nil,0 end
 local limit=activeDuration(anim)
 if t>=limit and limit<INF then
  if anim.repeatCount and anim.repeatCount<INF and not anim.repeatDur then
   local whole=math.floor(anim.repeatCount)
   local frac=anim.repeatCount-whole
   if frac>1e-9 then return frac,whole end
   return 1,math.max(whole-1,0)
  end
  local iteration=math.floor(limit/dur)
  local frac=(limit-iteration*dur)/dur
  if frac<=1e-9 then return 1,math.max(iteration-1,0)end
  return frac,iteration
 end
 local iteration=math.floor(t/dur)
 return (t-iteration*dur)/dur,iteration
end
function S.sample(plan,state,now,reduced)
 now=now or 0
 state.events=state.events or{}
 local resolved={}
 for _=1,math.min(#plan.animations,8)do
  for _,anim in ipairs(plan.animations)do resolved[anim]=intervalsOf(anim,plan,resolved,state.events)end
 end
 local sampled={};local active=false;local nextTime=nil
 local function schedule(t)if t>now and t<INF and(nextTime==nil or t<nextTime)then nextTime=t end end
 for _,anim in ipairs(plan.animations)do
  local list=resolved[anim]
  local segment
  for i,iv in ipairs(list)do
   if now>=iv.b and now<iv.e then
    local t=now-iv.b
    local progress,iteration=progressAt(anim,t)
    if anim.kind=='set'then segment={anim=anim,progress=1,iteration=0}
    elseif progress then
     if reduced then segment={anim=anim,progress=0,iteration=0}
     else segment={anim=anim,progress=progress,iteration=iteration};active=true end
    end
    if iv.e<INF then schedule(iv.e)end
    break
   elseif now<iv.b then schedule(iv.b);break
   elseif anim.freeze and(list[i+1]==nil or now<list[i+1].b)then
    local progress,iteration=progressAt(anim,iv.e-iv.b)
    if anim.kind=='set'then segment={anim=anim,progress=1,iteration=0,frozen=true}
    elseif progress then segment={anim=anim,progress=progress,iteration=iteration,frozen=true}end
    if list[i+1]then schedule(list[i+1].b)end
   end
  end
  if segment then
   local bucket=sampled[anim.target]
   if not bucket then bucket={};sampled[anim.target]=bucket end
   bucket[#bucket+1]=segment
  end
 end
 if reduced then active=false;nextTime=nil end
 return next(sampled)and sampled or nil,active,nextTime
end
local function parseTyped(text,attr)
 if text==nil then return nil end
 local s=trim(text)
 if S.colorAttributes[attr]and s~='none'and s:lower()~='currentcolor'and not s:find('url%(')then
  local ok,c,a=pcall(U.color,s)
  if ok and typeof(c)=='Color3'then return {kind='color',r=c.R,g=c.G,b=c.B,a=a or 1}end
 end
 if attr=='d'then
  local ok,parsed=pcall(function()return require(script.Parent.SvgPath).parse(s)end)
  if ok and parsed and parsed.tokens then
   local shape,nums={},{}
   for _,token in ipairs(parsed.tokens)do if type(token)=='string'then shape[#shape+1]=token..#nums else nums[#nums+1]=token end end
   return {kind='path',shape=table.concat(shape,','),tokens=parsed.tokens,nums=nums}
  end
  return {kind='text',text=s}
 end
 if s:match('^[%s,%d%.%+%-eE]+$')then
  local ok,list=pcall(U.numbers,s)
  if ok and #list>0 then return {kind='nums',list=list}end
 end
 local number,unit=s:match('^([%+%-]?[%d%.]+)(%%?%a*)$')
 if number and tonumber(number)then return {kind='nums',list={tonumber(number)},unit=unit}end
 return {kind='text',text=s}
end
local function transformTyped(text,kind)
 local list=U.numbers(text)
 if kind=='scale'then if #list==1 then list[2]=list[1]end
 elseif kind=='rotate'then list[2]=list[2]or 0;list[3]=list[3]or 0
 elseif kind=='translate'then list[2]=list[2]or 0 end
 return {kind='nums',list=list}
end
local function lerp(a,b,t)
 if a.kind~=b.kind then return t<1 and a or b end
 if a.kind=='color'then return {kind='color',r=a.r+(b.r-a.r)*t,g=a.g+(b.g-a.g)*t,b=a.b+(b.b-a.b)*t,a=a.a+(b.a-a.a)*t}end
 if a.kind=='nums'then
  if #a.list~=#b.list then return t<1 and a or b end
  local out={}
  for i,v in ipairs(a.list)do out[i]=v+(b.list[i]-v)*t end
  return {kind='nums',list=out,unit=a.unit or b.unit}
 end
 if a.kind=='path'then
  if a.shape~=b.shape then return t<1 and a or b end
  local out={}
  for i,v in ipairs(a.nums)do out[i]=v+(b.nums[i]-v)*t end
  return {kind='path',shape=a.shape,tokens=a.tokens,nums=out}
 end
 return t<1 and a or b
end
local function add(a,b,scale)
 scale=scale or 1
 if not a then return b end
 if not b or a.kind~=b.kind then return a end
 if a.kind=='color'then return {kind='color',r=a.r+b.r*scale,g=a.g+b.g*scale,b=a.b+b.b*scale,a=a.a}end
 if a.kind=='nums'and #a.list==#b.list then local out={};for i,v in ipairs(a.list)do out[i]=v+b.list[i]*scale end;return {kind='nums',list=out,unit=a.unit}end
 if a.kind=='path'and a.shape==b.shape then local out={};for i,v in ipairs(a.nums)do out[i]=v+b.nums[i]*scale end;return {kind='path',shape=a.shape,tokens=a.tokens,nums=out}end
 return a
end
local function distance(a,b)
 if a.kind~=b.kind then return 1 end
 if a.kind=='color'then return math.sqrt((a.r-b.r)^2+(a.g-b.g)^2+(a.b-b.b)^2)end
 if a.kind=='nums'and #a.list==#b.list then local sum=0;for i,v in ipairs(a.list)do sum+=(b.list[i]-v)^2 end;return math.sqrt(sum)end
 return 1
end
local function serialize(v)
 if v==nil then return nil end
 if v.kind=='color'then
  local r,g,b=math.clamp(v.r,0,1)*255,math.clamp(v.g,0,1)*255,math.clamp(v.b,0,1)*255
  if v.a<1 then return string.format('rgba(%.4g,%.4g,%.4g,%.4g)',r,g,b,math.clamp(v.a,0,1))end
  return string.format('rgb(%.4g,%.4g,%.4g)',r,g,b)
 end
 if v.kind=='nums'then
  local out={}
  for i,n in ipairs(v.list)do out[i]=fmt(n)end
  return table.concat(out,' ')..(v.unit or'')
 end
 if v.kind=='path'then
  local out={};local index=0
  for _,token in ipairs(v.tokens)do
   if type(token)=='string'then out[#out+1]=token else index+=1;out[#out+1]=fmt(v.nums[index])end
  end
  return table.concat(out,' ')
 end
 return v.text
end
local function bezier(t,x1,y1,x2,y2)
 if t<=0 then return 0 elseif t>=1 then return 1 end
 local lo,hi=0,1;local u=t
 for _=1,24 do
  u=(lo+hi)/2
  local x=3*(1-u)^2*u*x1+3*(1-u)*u*u*x2+u^3
  if x<t then lo=u else hi=u end
 end
 return 3*(1-u)^2*u*y1+3*(1-u)*u*u*y2+u^3
end
local function keyframes(anim,values,progress)
 local n=#values
 if n==0 then return nil end
 if n==1 then return values[1]end
 local times=anim.keyTimes
 if not times or #times~=n then
  times={}
  if anim.calc=='paced'then
   local total=0;local acc={0}
   for i=2,n do total+=distance(values[i-1],values[i]);acc[i]=total end
   for i=1,n do times[i]=total>0 and acc[i]/total or(i-1)/(n-1)end
  elseif anim.calc=='discrete'then for i=1,n do times[i]=(i-1)/n end
  else for i=1,n do times[i]=(i-1)/(n-1)end end
 end
 if anim.calc=='discrete'then
  local pick=values[1]
  for i=1,n do if progress>=times[i]then pick=values[i]end end
  return pick
 end
 if progress>=times[n]then return values[n]end
 for i=1,n-1 do
  local t0,t1=times[i],times[i+1]
  if progress>=t0 and progress<=t1 then
   local localT=t1>t0 and(progress-t0)/(t1-t0)or 0
   if anim.calc=='spline'and anim.keySplines and anim.keySplines[i]then local k=anim.keySplines[i];localT=bezier(localT,k[1],k[2],k[3],k[4])end
   return lerp(values[i],values[i+1],localT)
  end
 end
 return values[n]
end
local function motionValue(anim,progress)
 local contours
 if anim.path then
  local V=require(script.Parent.Svg)
  contours=V.geometry.paths(anim.path,0.05)
 else
  local pts={}
  if anim.values then for _,v in ipairs(anim.values)do pts[#pts+1]=U.numbers(v)end
  else
   local from=anim.from and U.numbers(anim.from)or{0,0}
   if anim.to then pts={from,U.numbers(anim.to)}elseif anim.by then local by=U.numbers(anim.by);pts={from,{from[1]+by[1],from[2]+(by[2]or 0)}}end
  end
  if #pts<1 then return nil end
  local contour={}
  for _,p in ipairs(pts)do contour[#contour+1]={x=p[1]or 0,y=p[2]or 0}end
  contours={contour}
 end
 local segments={};local total=0
 for _,contour in ipairs(contours)do
  local count=#contour-(contour.closed and 0 or 1)
  for i=1,count do
   local a,b=contour[i],contour[i%#contour+1]
   local len=math.sqrt((b.x-a.x)^2+(b.y-a.y)^2)
   if len>1e-9 then total+=len;segments[#segments+1]={a=a,b=b,len=len,acc=total}end
  end
 end
 if #segments==0 then
  local p=contours[1]and contours[1][1]
  if not p then return nil end
  return p.x,p.y,0
 end
 if anim.keyPoints and anim.keyTimes and #anim.keyPoints==#anim.keyTimes then
  local pts={};for i,v in ipairs(anim.keyPoints)do pts[i]={kind='nums',list={v}}end
  local saved=anim.calc;anim.calc=anim.calc=='paced'and'linear'or anim.calc
  local picked=keyframes(anim,pts,progress);anim.calc=saved
  progress=picked and picked.list[1]or progress
 end
 local target=math.clamp(progress,0,1)*total
 for _,seg in ipairs(segments)do
  if target<=seg.acc+1e-9 then
   local start=seg.acc-seg.len
   local t=seg.len>0 and math.clamp((target-start)/seg.len,0,1)or 0
   local x=seg.a.x+(seg.b.x-seg.a.x)*t;local y=seg.a.y+(seg.b.y-seg.a.y)*t
   return x,y,math.deg(math.atan2(seg.b.y-seg.a.y,seg.b.x-seg.a.x))
  end
 end
 local last=segments[#segments]
 return last.b.x,last.b.y,math.deg(math.atan2(last.b.y-last.a.y,last.b.x-last.a.x))
end
local function transformValue(anim,segment,base)
 local kind=anim.type or'translate'
 local values={}
 if anim.values then for i,v in ipairs(anim.values)do values[i]=transformTyped(v,kind)end
 elseif anim.from or anim.to or anim.by then
  local from=anim.from and transformTyped(anim.from,kind)or transformTyped(kind=='scale'and'1'or'0',kind)
  local to=anim.to and transformTyped(anim.to,kind)or(anim.by and add(from,transformTyped(anim.by,kind)))or from
  values={from,to}
 end
 local v=keyframes(anim,values,segment.progress)
 if not v then return base end
 if anim.accumulate and segment.iteration>0 and #values>0 then v=add(v,values[#values],segment.iteration)end
 local text=kind..'('..serialize(v)..')'
 if anim.additive then return trim((base~='none'and base or'')..' '..text)end
 return text
end
local function zero(v)
 if v.kind=='color'then return {kind='color',r=0,g=0,b=0,a=0}end
 if v.kind=='nums'then local out={};for i in ipairs(v.list)do out[i]=0 end;return {kind='nums',list=out,unit=v.unit}end
 if v.kind=='path'then local out={};for i in ipairs(v.nums)do out[i]=0 end;return {kind='path',shape=v.shape,tokens=v.tokens,nums=out}end
 return v
end
local function animateValue(anim,segment,attr,base)
 if anim.kind=='set'then return anim.to~=nil and trim(anim.to)or base end
 local baseTyped=parseTyped(base,attr)
 local values={};local additive=anim.additive
 if anim.values then for i,v in ipairs(anim.values)do values[i]=parseTyped(v,attr)end
 elseif anim.to then
  local to=parseTyped(anim.to,attr)
  local from=anim.from and parseTyped(anim.from,attr)or baseTyped or to
  if not anim.from then additive=false end
  values={from,to}
 elseif anim.by then
  local by=parseTyped(anim.by,attr)
  if anim.from then local from=parseTyped(anim.from,attr);values={from,add(from,by)}
  else values={zero(by),by};additive=true end
 end
 if #values==0 then return base end
 local v=keyframes(anim,values,segment.progress)
 if not v then return base end
 if anim.accumulate and segment.iteration>0 then v=add(v,values[#values],segment.iteration)end
 if additive and baseTyped then v=add(baseTyped,v)end
 return serialize(v)or base
end
function S.values(plan,segments,style,attrs)
 if not segments then return nil end
 local out={}
 local byAttr={}
 for _,segment in ipairs(segments)do
  local attr=segment.anim.attr
  local list=byAttr[attr]
  if not list then list={};byAttr[attr]=list end
  list[#list+1]=segment
 end
 for attr,list in pairs(byAttr)do
  table.sort(list,function(a,b)return a.anim.order<b.anim.order end)
  local value=style[attr]
  if value==nil then value=attrs[attr]end
  if attr=='transform'then value=value or'none'end
  for _,segment in ipairs(list)do
   local anim=segment.anim
   if anim.kind=='transform'then value=transformValue(anim,segment,value or'none')
   elseif anim.kind=='motion'then
    local x,y,angle=motionValue(anim,segment.progress)
    if x then
     local rotate=anim.rotate
     local text=' translate('..fmt(x)..' '..fmt(y)..')'
     if rotate=='auto'then text=text..' rotate('..fmt(angle)..')'
     elseif rotate=='auto-reverse'then text=text..' rotate('..fmt(angle+180)..')'
     elseif tonumber(rotate)and tonumber(rotate)~=0 then text=text..' rotate('..fmt(tonumber(rotate))..')'end
     value=trim(((value and value~='none')and value or'')..text)
    end
   else value=animateValue(anim,segment,attr,value)end
  end
  if value~=nil then out[attr]=value end
 end
 return out
end
local function invert(m)
 local det=m[1]*m[4]-m[2]*m[3]
 if math.abs(det)<1e-12 then return nil end
 local a,b,c,d=m[4]/det,-m[2]/det,-m[3]/det,m[1]/det
 return {a,b,c,d,-(a*m[5]+c*m[6]),-(b*m[5]+d*m[6])}
end
local function apply(m,x,y)return m[1]*x+m[3]*y+m[5],m[2]*x+m[4]*y+m[6]end
local function inside(contours,x,y,evenodd)
 local winding,crossings=0,0
 for _,contour in ipairs(contours)do
  local n=#contour
  for i=1,n do
   local a,b=contour[i],contour[i%n+1]
   if(a.y<=y and b.y>y)or(b.y<=y and a.y>y)then
    local t=(y-a.y)/(b.y-a.y);local ix=a.x+(b.x-a.x)*t
    if ix>x then crossings+=1;winding+=(b.y>a.y)and 1 or-1 end
   end
  end
 end
 if evenodd then return crossings%2==1 end
 return winding~=0
end
local function nearStroke(contours,x,y,radius)
 local r2=radius*radius
 for _,contour in ipairs(contours)do
  local n=#contour;local count=n-(contour.closed and 0 or 1)
  if n==1 then local p=contour[1];if(p.x-x)^2+(p.y-y)^2<=r2 then return true end end
  for i=1,count do
   local a,b=contour[i],contour[i%n+1]
   local dx,dy=b.x-a.x,b.y-a.y;local len=dx*dx+dy*dy
   local t=len>0 and math.clamp(((x-a.x)*dx+(y-a.y)*dy)/len,0,1)or 0
   local px,py=a.x+dx*t,a.y+dy*t
   if(px-x)^2+(py-y)^2<=r2 then return true end
  end
 end
 return false
end
local function contoursOf(node,geometry,tolerance)
 local a=node.attrs;local tag=node.tag
 local function num(k,d)return tonumber(a[k])or d or 0 end
 if tag=='path'then if not a.d or a.d==''then return nil end;return geometry.paths(a.d,tolerance)end
 if tag=='circle'then return {geometry.circle(num'cx',num'cy',num'r',num'r',tolerance)}end
 if tag=='ellipse'then return {geometry.circle(num'cx',num'cy',num'rx',num'ry',tolerance)}end
 if tag=='rect'then
  local x,y,w,h=num'x',num'y',num'width',num'height'
  return {{{x=x,y=y},{x=x+w,y=y},{x=x+w,y=y+h},{x=x,y=y+h},closed=true}}
 end
 if tag=='line'then return {{{x=num'x1',y=num'y1'},{x=num'x2',y=num'y2'}}}end
 if tag=='polyline'or tag=='polygon'then
  local n=U.numbers(a.points or'');local poly={closed=tag=='polygon'}
  for i=1,#n-1,2 do poly[#poly+1]={x=n[i],y=n[i+1]}end
  return {poly}
 end
 return nil
end
local shapes={path=true,rect=true,circle=true,ellipse=true,line=true,polyline=true,polygon=true}
function S.hit(resolved,viewBox,width,height,px,py,cache)
 if not resolved or not viewBox or width<=0 or height<=0 then return nil end
 local V=require(script.Parent.Svg)
 local geometry=V.geometry
 local aspect=Dom.aspect(resolved.attrs.preserveaspectratio)
 local sx,sy,tx,ty=Dom.scale(aspect,viewBox,width,height)
 local ux,uy=(px-tx)/sx,(py-ty)/sy
 if ux<viewBox[1]or uy<viewBox[2]or ux>viewBox[1]+viewBox[3]or uy>viewBox[2]+viewBox[4]then return nil end
 local tolerance=math.max(viewBox[3]/math.max(width,1),viewBox[4]/math.max(height,1))*.5
 cache=cache or{}
 local chain={}
 local function pointerMode(a)
  local mode=trim(a['pointer-events']or'visiblePainted')
  if mode=='none'then return nil end
  local visible=(a.visibility==nil or a.visibility=='visible')and a.display~='none'
  local lower=mode:lower()
  if lower:sub(1,7)=='visible'and not visible then return nil end
  local fill,stroke
  if lower=='all'or lower=='bounding-box'or lower=='visible'then fill,stroke=true,true
  elseif lower=='visiblefill'or lower=='fill'then fill,stroke=true,false
  elseif lower=='visiblestroke'or lower=='stroke'then fill,stroke=false,true
  else fill=a.fill~=nil and a.fill~='none';stroke=a.stroke~=nil and a.stroke~='none'end
  return fill,stroke
 end
 local function walk(node,parentMatrix,depth)
  assert(depth<=64,'Profundidade SVG acima do orçamento.')
  local a=node.attrs or{}
  if a.display=='none'or S.tags[node.tag]then return false end
  local ok,m=pcall(function()return geometry.matrix(parentMatrix,geometry.transform(a.transform~='none'and a.transform or nil))end)
  if not ok then m=parentMatrix end
  chain[#chain+1]=node.key
  if shapes[node.tag]then
   local fill,stroke=pointerMode(a)
   if fill==nil then chain[#chain]=nil;return false end
   local inv=invert(m)
   if not inv then chain[#chain]=nil;return false end
   local lx,ly=apply(inv,ux,uy)
   local signature=node.tag..'|'..(a.d or'')..'|'..(a.points or'')..'|'..(a.cx or'')..','..(a.cy or'')..','..(a.r or'')..','..(a.rx or'')..','..(a.ry or'')..'|'..(a.x or'')..','..(a.y or'')..','..(a.width or'')..','..(a.height or'')..'|'..(a.x1 or'')..','..(a.y1 or'')..','..(a.x2 or'')..','..(a.y2 or'')
   local slot=cache[node.key]
   local contours
   if slot and slot.signature==signature then contours=slot.contours
   else
    local okc,result=pcall(contoursOf,node,geometry,tolerance)
    contours=okc and result or nil
    cache[node.key]={signature=signature,contours=contours}
   end
   if contours then
    if fill and node.tag~='line'and inside(contours,lx,ly,a['fill-rule']=='evenodd')then return true end
    if stroke then
     local width=tonumber(a['stroke-width'])or 1
     if nearStroke(contours,lx,ly,math.max(width/2,tolerance))then return true end
    end
   end
   chain[#chain]=nil
   return false
  end
  if node.tag=='g'or node.tag=='svg'or node.tag=='a'then
   local children=node.children or{}
   for i=#children,1,-1 do
    if walk(children[i],m,depth+1)then return true end
   end
  end
  chain[#chain]=nil
  return false
 end
 if walk(resolved,{1,0,0,1,0,0},1)then return chain end
 return {resolved.key}
end
function S.driver(queue,clock,options)
 options=options or{}
 local self={alive=true,connection=nil,last=-INF,status=nil,interval=1/math.clamp(tonumber(options.fps)or 30,1,120)}
 local function disconnect()if self.connection then self.connection:Disconnect();self.connection=nil end end
 function self:sync(status)
  if not self.alive then return end
  self.status=status
  local wanted=status~=nil and(status.active or status.next~=nil)and #status.keys>0
  if wanted and not self.connection then
   self.connection=Performance.renderSignal():Connect(function()
    local current=self.status
    if not current or not self.alive then return end
    local now=clock()
    local due=(current.active and now-self.last>=self.interval)or(current.next~=nil and now>=current.next)
    if due then
     self.last=now
     for _,key in ipairs(current.keys)do queue(key,'style')end
    end
   end)
  elseif not wanted then disconnect()end
 end
 function self:destroy()self.alive=false;disconnect();self.status=nil end
 return self
end
local function pressedInput(input)
 return input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch
end
local function pointerInput(input)
 return input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch
end
function S.interaction(owner,connect,queue,clock)
 local self={groups={},alive=true,count=0}
 local function disconnect(c,key)
  if owner._unlinkConnection then owner._unlinkConnection(c)else
   c:Disconnect();local i=table.find(owner.connections,c);if i then table.remove(owner.connections,i)end
  end
  local links=key and owner.nodeConnections[key]
  if links then local j=table.find(links,c);if j then table.remove(links,j)end end
 end
 local function record(root,chain,name)
  local entry=owner.cache[root]
  if not entry then return end
  entry.svg=entry.svg or{events={}}
  local events=entry.svg.events
  events[#events+1]={chain=table.clone(chain),name=name,time=clock()}
  while #events>S.limits.events do table.remove(events,1)end
 end
 local function setState(key,name,value)
  local state=owner.state[key]
  if not state then state={};owner.state[key]=state end
  if state[name]~=value then state[name]=value;return true end
  return false
 end
 local function inChain(chain,key)for _,k in ipairs(chain)do if k==key then return true end end;return false end
 local function mask(n,hasEvents)
  local keys={}
  for key,flags in pairs(n or{})do keys[#keys+1]=key..(flags.hover and'h'or'')..(flags.active and'a'or'')end
  table.sort(keys)
  return table.concat(keys,';')..(hasEvents and'|e'or'')
 end
 function self:chainAt(root,x,y)
  local object=owner.objects[root];local entry=owner.cache[root]
  if not object or not entry or not entry.svgResolved then return {root}end
  local size=object.AbsoluteSize
  local box=owner.boxes and owner.boxes[root]
  local width=size.X>0 and size.X or(box and box.w)or 0
  local height=size.Y>0 and size.Y or(box and box.h)or 0
  entry.svgHitCache=entry.svgHitCache or{}
  return S.hit(entry.svgResolved,entry.svgViewBox,width,height,x,y,entry.svgHitCache)or{root}
 end
 function self:pointer(root,x,y)
  local group=self.groups[root]
  if not group then return nil end
  local chain=(x~=nil and y~=nil)and self:chainAt(root,x,y)or{}
  local previous=group.chain or{}
  local changed=false
  if group.events then
   for _,key in ipairs(previous)do if not inChain(chain,key)then record(root,previous,'mouseout');changed=true;break end end
   for _,key in ipairs(chain)do if not inChain(previous,key)then record(root,chain,'mouseover');changed=true;break end end
  end
  for key,flags in pairs(group.needs)do
   if flags.hover and setState(key,'hover',inChain(chain,key))then changed=true end
  end
  group.chain=chain
  if changed then queue(root,'style')end
  return chain
 end
 function self:press(root)
  local group=self.groups[root];if not group then return end
  local chain=group.chain or{}
  local changed=false
  for key,flags in pairs(group.needs)do
   if flags.active and inChain(chain,key)and setState(key,'active',true)then changed=true end
  end
  if group.events and #chain>0 then record(root,chain,'mousedown');changed=true end
  group.pressed=table.clone(chain)
  if changed then queue(root,'style')end
 end
 function self:release(root)
  local group=self.groups[root];if not group then return end
  local chain=group.chain or{}
  local changed=false
  for key,flags in pairs(group.needs)do
   if flags.active and setState(key,'active',false)then changed=true end
  end
  if group.events and #chain>0 then
   record(root,chain,'mouseup');changed=true
   local pressed=group.pressed
   if pressed and pressed[#pressed]==chain[#chain]then record(root,chain,'click')end
  end
  group.pressed=nil
  if changed then queue(root,'style')end
 end
 function self:fire(root,key,name)
  local chain={}
  local entry=owner.cache[root]
  local node=entry and entry.svgResolved
  local function find(n,path)
   path[#path+1]=n.key
   if n.key==key then return true end
   for _,child in ipairs(n.children or{})do if find(child,path)then return true end end
   path[#path]=nil
   return false
  end
  if not node or not find(node,chain)then chain={root}end
  record(root,chain,name)
  queue(root,'style')
 end
 function self:remove(root)
  local group=self.groups[root];if not group then return end
  for _,c in ipairs(group.links)do disconnect(c,root);self.count-=1 end
  for key in pairs(group.needs)do local state=owner.state[key];if state then state.hover=nil;state.active=nil end end
  self.groups[root]=nil
 end
 function self:sync(status)
  if not self.alive then return end
  local needs=status and status.needs or{}
  local events=status and status.events or{}
  for root,group in pairs(self.groups)do
   if mask(needs[root],events[root])~=group.mask or owner.objects[root]~=group.object then self:remove(root)end
  end
  local roots={}
  for root in pairs(needs)do roots[root]=true end
  for root in pairs(events)do roots[root]=true end
  for root in pairs(roots)do
   local object=owner.objects[root]
   if object and not self.groups[root]then
    local n=needs[root]or{}
    local group={mask=mask(n,events[root]),object=object,links={},needs=n,events=events[root]==true,chain=nil}
    self.groups[root]=group
    for key in pairs(n)do owner.state[key]=owner.state[key]or{}end
    local function on(signal,fn)local c=connect(signal,fn,root);group.links[#group.links+1]=c;self.count+=1 end
    on(object.InputChanged,function(input)
     if pointerInput(input)then local p=object.AbsolutePosition;self:pointer(root,input.Position.X-p.X,input.Position.Y-p.Y)end
    end)
    on(object.MouseLeave,function()self:pointer(root,nil,nil)end)
    on(object.InputBegan,function(input)
     if pressedInput(input)then
      local p=object.AbsolutePosition;self:pointer(root,input.Position.X-p.X,input.Position.Y-p.Y);self:press(root)
     end
    end)
    on(object.InputEnded,function(input)
     if pressedInput(input)then self:release(root)end
    end)
   end
  end
 end
 function self:destroy()
  if not self.alive then return end;self.alive=false
  for root in pairs(self.groups)do self:remove(root)end
  table.clear(self.groups);owner=nil
 end
 return self
end
return S
