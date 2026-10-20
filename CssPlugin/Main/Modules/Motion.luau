local U=require(script.Parent.Util)
local Performance=require(script.Parent.Performance)
local Transform=require(script.Parent.Transform)
local Queries=require(script.Parent.ResponsiveQueries)
local Cascade=require(script.Parent.CssCascade)
local Math=require(script.Parent.MathLength)
local Timeline=require(script.Parent.ScrollTimeline)
local MotionPath=require(script.Parent.MotionPath)
local Advanced=require(script.Parent.MotionAdvanced)
local M={properties={'background','opacity','transform','offset-distance'}}
local allowed={background=true,['background-color']=true,opacity=true,transform=true,['offset-distance']=true,all=true,none=true}
local timingNames={linear=true,ease=true,['ease-in']=true,['ease-out']=true,['ease-in-out']=true,['step-start']=true,['step-end']=true}
local easingCache=setmetatable({}, {__mode='v'})
local curves={ease={0.25,0.1,0.25,1},['ease-in']={0.42,0,1,1},['ease-out']={0,0,0.58,1},['ease-in-out']={0.42,0,0.58,1}}
local empty=table.freeze({})
local function linear(t)return t end
local function stepStart(t,before)return before and t<=0 and 0 or 1 end
local function stepEnd(t,before)return (t>1 or(t==1 and not before))and 1 or 0 end
local function curve(t,a,b)return 3*(1-t)^2*t*a+3*(1-t)*t*t*b+t^3 end
local function byOffset(a,b)return a.offset<b.offset end
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function cssNumber(text)
 if type(text)~='string'then return nil end
 local value=U.trim(text);local mantissa=value:match('^(.-)[eE][+%-]?%d+$')or value
 if not mantissa:match('^[+%-]?%d*%.?%d+$')then return nil end
 local n=tonumber(value);return finite(n)and n or nil
end
local function commaList(text)
 assert(type(text)=='string','Lista Motion inválida.')
 local result,start,level,quote,escaped={},1,0,nil,false
 local function push(last)
  local item=U.trim(text:sub(start,last));assert(item~='','Lista Motion contém um item vazio.')
  result[#result+1]=item;assert(#result<=64,'Máximo de 64 valores por lista Motion.')
 end
 for i=1,#text do
  local c=text:sub(i,i)
  if quote then if escaped then escaped=false elseif c==string.char(92)then escaped=true elseif c==quote then quote=nil end
  elseif c=='"'or c=="'"then quote=c
  elseif c=='('or c=='['then level+=1
  elseif c==')'or c==']'then level-=1;assert(level>=0,'Lista Motion desbalanceada.')
  elseif c==','and level==0 then push(i-1);start=i+1 end
 end
 assert(not quote and level==0,'Lista Motion não fechada.');push(#text);return result
end
function M.time(s,nonnegative)
 assert(type(s)=='string','Tempo CSS inválido: '..tostring(s))
 local text=U.trim(s):lower();local raw,unit=text:match('^(.-)(m?s)$');local n=cssNumber(raw)
 if not unit and cssNumber(text)==0 then n,unit=0,'s' end
 if text:find('(',1,true)then local dimension;n,dimension=Math.evaluate(Math.parse(text));assert(dimension=='time','Tempo CSS exige s/ms.');unit='s'end
 assert(finite(n) and (not nonnegative or n>=0),'Tempo CSS inválido: '..tostring(s))
 n=unit=='ms' and n/1000 or n;assert(math.abs(n)<=3600,'Tempo CSS limitado a uma hora.');return n
end
local function isTime(s)
 if s:find('(',1,true)then local ok,_,dimension=pcall(function()return Math.evaluate(Math.parse(s))end);return ok and dimension=='time'end
 local raw=s:lower():match('^(.-)m?s$')
 return raw~=nil and cssNumber(raw)~=nil
end
local function isTiming(s)s=s:lower();return timingNames[s]or s:match('^cubic%-bezier%(')or s:match('^steps%(')end
function M.easing(text)
 text=U.trim(text):lower();if easingCache[text] then return easingCache[text]end
 local fn
 if text=='linear' then fn=linear
 elseif text=='step-start' then fn=stepStart
 elseif text=='step-end' then fn=stepEnd
 else
  local c=curves[text]
  if not c and text:match('^cubic%-bezier%(')then
   local parts=commaList(assert(text:match('^cubic%-bezier%((.*)%)$'),'cubic-bezier inválido.'))
   assert(#parts==4,'cubic-bezier exige 4 números separados por vírgula.');c={}
   for i,part in ipairs(parts)do c[i]=assert(cssNumber(part),'Número cubic-bezier inválido: '..part)end
  end
  if c then
   assert(c[1]>=0 and c[1]<=1 and c[3]>=0 and c[3]<=1,'cubic-bezier: coordenadas X devem estar entre 0 e 1.')
   fn=function(x)
    if x<=0 then return 0 elseif x>=1 then return 1 end
    local lo,hi,t=0,1,x
    for _=1,18 do local v=curve(t,c[1],c[3]);if math.abs(v-x)<0.000001 then break end;if v<x then lo=t else hi=t end;t=(lo+hi)/2 end
    return curve(t,c[2],c[4])
   end
  else
   local body=text:match('^steps%((.*)%)$');assert(body,'Timing não suportado: '..text)
   local p=commaList(body);local n=cssNumber(p[1]);local mode=p[2] or 'end'
   assert(n and n%1==0 and n>=1 and n<=1000 and #p<=2,'steps exige 1 a 1000 passos.')
   assert(mode=='start' or mode=='end' or mode=='jump-start' or mode=='jump-end' or mode=='jump-none' or mode=='jump-both','Modo steps inválido.')
   assert(mode~='jump-none' or n>1,'steps jump-none exige pelo menos 2 passos.')
   fn=function(t,before)
    local scaled=math.clamp(t,0,1)*n;local k=math.floor(scaled);local jumps=n
    if mode=='start' or mode=='jump-start' then k+=1 elseif mode=='jump-both' then k+=1;jumps+=1 elseif mode=='jump-none' then jumps-=1 end
    if before and scaled%1==0 then k-=1 end
    return math.clamp(k/jumps,0,1)
   end
  end
 end
 easingCache[text]=fn;return fn
end
function M.expandTransition(value)
 local out={['transition-property']={},['transition-duration']={},['transition-timing-function']={},['transition-delay']={},['transition-behavior']={}}
 local entries=commaList(value)
 for _,entry in ipairs(entries)do
  local property,duration,easing,delay='all','0s','ease','0s';local behavior='normal';local times=0;local hasProperty,hasTiming,hasBehavior=false,false,false
  for _,v in ipairs(U.split(entry,' '))do
   if isTime(v) or v=='0' then times+=1;assert(times<=2,'Transição aceita duração e atraso.');M.time(v,times==1);if times==1 then duration=v else delay=v end
   elseif isTiming(v) then assert(not hasTiming,'Timing repetido.');M.easing(v);easing=v;hasTiming=true
   elseif Advanced.behaviorKeyword(v)then assert(not hasBehavior,'transition-behavior repetido.');behavior=Advanced.behaviorKeyword(v);hasBehavior=true
   else local name=Advanced.propertyName(v);assert(not hasProperty and(allowed[name]or Advanced.animatable(name)),'Transição não suportada: '..v);property=name;hasProperty=true end
  end
  assert(property~='none'or #entries==1,'transition: none deve aparecer sozinho.')
  table.insert(out['transition-property'],property);table.insert(out['transition-duration'],duration)
  table.insert(out['transition-timing-function'],easing);table.insert(out['transition-delay'],delay);table.insert(out['transition-behavior'],behavior)
 end
 for k,v in pairs(out)do out[k]=table.concat(v,', ')end;return out
end
local animDefaults={name='none',duration='0s',delay='0s',['timing-function']='ease',['iteration-count']='1',direction='normal',['fill-mode']='none',['play-state']='running'}
local animationKeys={};for key in pairs(animDefaults)do animationKeys[key]='animation-'..key end
local directions={normal=true,reverse=true,alternate=true,['alternate-reverse']=true}
local fills={none=true,forwards=true,backwards=true,both=true}
function M.expandAnimation(value)
 local out={};for k in pairs(animDefaults)do out[animationKeys[k]]={}end
 local entries=commaList(value)
 for _,entry in ipairs(entries)do
  local a=U.copy(animDefaults);local times=0;local seen={}
  for _,v in ipairs(U.split(entry,' '))do
   local key;local lower=v:lower();local count=cssNumber(v)
   if isTime(v) then times+=1;assert(times<=2,'Animação aceita duração e atraso.');key=times==1 and 'duration' or 'delay';M.time(v,times==1)
   elseif not seen['timing-function']and isTiming(v)then key='timing-function';M.easing(v);v=lower
   elseif not seen['iteration-count']and(lower=='infinite'or count~=nil)then key='iteration-count';assert(lower=='infinite'or(count>=0 and count<=100000),'Número de repetições inválido.');v=lower
   elseif not seen.direction and directions[lower]then key='direction';v=lower
   elseif not seen['play-state']and(lower=='running'or lower=='paused')then key='play-state';v=lower
   elseif not seen['fill-mode']and fills[lower]then key='fill-mode';v=lower
   else
    assert(v:match('^[%a_][%w_%-]*$'),'Nome de animação inválido: '..v);key='name';if lower=='none'then v='none'end
   end
   assert(not seen[key],'Campo repetido na animação: '..key);seen[key]=true;a[key]=v
  end
  for k,v in pairs(a)do table.insert(out[animationKeys[k]],v)end
 end
 for k,v in pairs(out)do out[k]=table.concat(v,', ')end;return out
end
local function list(style,key,default)return commaList(style[key] or default)end
local function cycle(a,i)return a[(i-1)%#a+1]end
function M.transitions(style)
 local props=list(style,'transition-property','all');local durations=list(style,'transition-duration','0s');local delays=list(style,'transition-delay','0s');local easings=list(style,'transition-timing-function','ease');local out={}
 for i,p in ipairs(props)do
  p=Advanced.propertyName(p);assert(allowed[p]or Advanced.animatable(p),'Transição não suportada: '..p);assert(p~='none'or #props==1,'transition-property: none deve aparecer sozinho.');p=p=='background-color' and 'background' or p
  local spec={duration=M.time(cycle(durations,i),true),delay=M.time(cycle(delays,i),false),ease=M.easing(cycle(easings,i)),behavior=Advanced.behavior(style,i)}
  if p=='all' then for _,k in ipairs(Advanced.allProperties(style,M.properties,spec.behavior))do out[k]=spec end elseif p~='none' then out[p]=spec end
 end
 return out
end
function M.transform(value,context)return Transform.parse(value,context)end
function M.value(property,value,context,style)
 if property=='opacity'then
  local n=tonumber(value)
  if not n then local c=table.clone(context or {});c.base=1;c.percentDimension=0;local d;n,d=Math.evaluate(Math.parse(value),c);assert(d==0,'Opacity exige número ou %.')end
  assert(finite(n),'Opacity inválida.');return math.clamp(n,0,1)
 elseif property=='transform' then return M.transform(value,context)
 elseif property=='offset-distance' then return MotionPath.distance(value,context)
 elseif property=='background' then if value:find('gradient(',1,true)then return nil end;local color,a=U.color(value);return {color=color,alpha=a}end
 return Advanced.value(property,value,context,style)
end
function M.base(style,context)
 local base={background=M.value('background',style.background or style['background-color'] or 'transparent'),opacity=M.value('opacity',style.opacity or '1'),transform=M.transform(style.transform,context),['offset-distance']=MotionPath.distance(style['offset-distance']or'0px',context)}
 return Advanced.base(base,style,context)
end
function M.equal(a,b)
 if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
 if a.kind=='offset-distance'or b.kind=='offset-distance'then return MotionPath.same(a,b)end
 if a.color then return b.color==a.color and b.alpha==a.alpha end
 if a.t or b.t then return Advanced.equal(a,b)end
 return Transform.equal(a,b)
end
function M.lerp(property,a,b,t)
 if(type(a)=='table'and a.t)or(type(b)=='table'and b.t)then return Advanced.lerp(property,a,b,t)end
 if property=='opacity' then return math.clamp(a+(b-a)*t,0,1)
 elseif property=='offset-distance' then return MotionPath.lerp(a,b,t)
 elseif property=='transform' then return Transform.lerp(a,b,t)
 else t=math.clamp(t,0,1);local alpha=a.alpha+(b.alpha-a.alpha)*t;return {color=a.color:Lerp(b.color,alpha>0.000001 and b.alpha*t/alpha or 0),alpha=alpha}end
end
function M.prepare(style,definitions,width,resolve,context)
 local layerOrder=Cascade.order(definitions and definitions[1]and definitions[1].layerEvents,width,context and context.vh,style._mediaEnvironment)
 local names=list(style,'animation-name','none')
 local fields={};for k,v in pairs(animDefaults)do fields[k]=list(style,animationKeys[k],v)end
 local base=M.base(style,context);local prepared={}
 for i,name in ipairs(names)do if name:lower()~='none'then
  local def,defined;for _,d in ipairs(definitions or empty)do if d.name==name then defined=true;if Queries.mediaActive(d,width,context and context.vh,style._mediaEnvironment)and(not def or Cascade.layerCompare(d.layer,def.layer,false,layerOrder)>=0)then def=d end end end
  assert(defined,'@keyframes não definido: '..name)
  if not def then continue end
  local a={name=name,duration=M.time(cycle(fields.duration,i),true),delay=M.time(cycle(fields.delay,i),false),direction=cycle(fields.direction,i):lower(),fill=cycle(fields['fill-mode'],i):lower(),play=cycle(fields['play-state'],i):lower(),timing=cycle(fields['timing-function'],i):lower(),composition=Advanced.composition(style,i),frames={}}
  local n=cycle(fields['iteration-count'],i);a.iterations=n:lower()=='infinite' and math.huge or cssNumber(n)
  assert(a.iterations and a.iterations>=0 and (a.iterations==math.huge or a.iterations<=100000),'animation-iteration-count inválido.')
  assert(directions[a.direction]and fills[a.fill]and(a.play=='running'or a.play=='paused'),'Direção, fill-mode ou play-state inválido.');a.ease=M.easing(a.timing)
  a.signature=table.concat({name,a.duration,a.delay,a.iterations,a.direction,a.fill,a.timing,def.order or 0},'|')
  local timeline=Timeline.prepare(style,i)
  if timeline and timeline.kind~='auto'then
   a.timeline=timeline
   a.signature=a.signature..'|'..table.concat({timeline.kind,timeline.name or'',timeline.axis or'',timeline.source or'',timeline.inset or'',timeline.rangeStart.name,timeline.rangeStart.offset,timeline.rangeEnd.name,timeline.rangeEnd.offset},'~')
  end
  for _,stop in ipairs(def.stops)do
   local easing=a.ease
   for _,d in ipairs(stop.declarations)do if d.key=='animation-timing-function'then easing=M.easing(resolve(d.value,style._vars or empty))end end
   for _,d in ipairs(stop.declarations)do if d.key~='animation-timing-function' and not (style._important and style._important[d.key])then
    Advanced.ensureBase(base,d.key,style,context)
    local value=M.value(d.key,resolve(d.value,style._vars or empty),context,style);assert(value~=nil and base[d.key]~=nil,'Animação de background-color exige cores sólidas, não gradientes.')
    a.frames[d.key]=a.frames[d.key]or {};table.insert(a.frames[d.key],{offset=stop.offset,value=value,ease=easing})
   end end
  end
  for property,frames in pairs(a.frames)do
   table.sort(frames,byOffset)
   if frames[1].offset>0 then table.insert(frames,1,{offset=0,value=base[property],ease=a.ease})end
   if frames[#frames].offset<1 then table.insert(frames,{offset=1,value=base[property],ease=a.ease})end
  end
  table.insert(prepared,a)
 end end
 return prepared
end
local function frameSample(property,frames,t,before)
 if t<frames[1].offset or #frames==1 then return frames[1].value end
 for i=2,#frames do
  local b=frames[i]
  if t<b.offset or(before and t==b.offset)or i==#frames then
   local a=frames[i-1];local span=b.offset-a.offset
   return M.lerp(property,a.value,b.value,a.ease(span>0 and math.clamp((t-a.offset)/span,0,1)or 1,before))
  end
 end
 return frames[#frames].value
end
local function directed(a,t,iteration)
 local reverse=a.direction=='reverse'or(a.direction=='alternate'and iteration%2==1)or(a.direction=='alternate-reverse'and iteration%2==0)
 return reverse and 1-t or t,reverse
end
local function animationProgress(a,now,reduced)
 if a.timeline then
  local p=a.progress
  if p==nil then return nil,false end
  if reduced and not(a.fill=='forwards'or a.fill=='both')then return nil,false end
  local iterations=a.iterations==math.huge and 1 or a.iterations
  if p<0 then
   if a.fill=='backwards'or a.fill=='both'then local t,reversed=directed(a,0,0);return t,false,not reversed end
   return nil,false
  end
  if iterations<=0 or p>1 then
   if a.fill~='forwards'and a.fill~='both'then return nil,false end
   if iterations<=0 then local t,reversed=directed(a,0,0);return t,false,reversed end
   local whole=math.ceil(iterations)-1;local fraction=iterations-whole;local t,reversed=directed(a,fraction,whole);return t,false,reversed
  end
  local phase=p*iterations;local iteration=math.min(math.floor(phase),math.max(0,math.ceil(iterations)-1))
  local t,reversed=directed(a,phase-iteration,iteration);return t,false,reversed
 end
 local elapsed=(a.pausedAt or now)-a.start-a.delay;local total=a.duration==0 and 0 or a.duration*a.iterations
 if reduced then if (a.fill=='forwards'or a.fill=='both')and a.iterations<math.huge then elapsed=total else return nil,false end end
 local active=not reduced and not a.pausedAt and (elapsed<0 or (a.duration>0 and elapsed<total))
 if elapsed<0 then
  if a.fill=='backwards'or a.fill=='both'then local t,reversed=directed(a,0,0);return t,active,not reversed end
  return nil,active
 end
 if a.duration==0 or elapsed>=total then
  if a.fill~='forwards'and a.fill~='both'then return nil,false end
  if a.iterations==0 then local t,reversed=directed(a,0,0);return t,false,reversed end
  if a.iterations==math.huge then local t,reversed=directed(a,1,0);return t,false,reversed end
  local whole=math.ceil(a.iterations)-1;local fraction=a.iterations-whole;local t,reversed=directed(a,fraction,whole);return t,false,reversed
 end
 local phase=elapsed/a.duration;local iteration=math.floor(phase);local t=directed(a,phase-iteration,iteration);return t,active,false
end
function M.new(options)
 options=options or {};local applyCallback=options.apply
 local self={nodes={},values={},clock=options.clock or os.clock,manual=options.manual==true,reduced=options.reduced==true,development=options.development==true,alive=true,connection=nil,steps=0}
 local function sample(record,now)
  if record.settled then return record.settled,false end
  if #record.animations==0 and next(record.tracks)==nil then return record.base,false end
  local values=U.copy(record.base);local active=false
  for _,a in ipairs(record.animations)do local t,work,before=animationProgress(a,now,self.reduced);active=active or work;if t then for p,frames in pairs(a.frames)do values[p]=Advanced.compose(a.composition,p,values[p],frameSample(p,frames,t,before))end end end
  for p,track in pairs(record.tracks)do
   if self.reduced then record.tracks[p]=nil
   elseif now<track.start then values[p]=track.from;active=true
   elseif track.duration==0 or now>=track.start+track.duration then record.tracks[p]=nil
   else values[p]=M.lerp(p,track.from,track.to,track.ease((now-track.start)/track.duration));active=true end
  end
  if not active then record.settled=values end
  return values,active
 end
 function self:_sync(work)
  if self.manual then return end
  if work and not self.connection and self.alive then
   local signal=Performance.renderSignal()
   self.connection=signal:Connect(function()
    local ok,err=pcall(self.step,self)
    if not ok then self.lastError=tostring(err);self:destroy();if self.development then warn('[CssPlugin] Animação interrompida: '..self.lastError)end end
   end)
  elseif not work and self.connection then self.connection:Disconnect();self.connection=nil end
 end
 function self:update(key,style,definitions,width,resolve,enabled,context)
  if not self.alive then return end
  local now=self.clock();local base=M.base(style,context);local transitions=M.transitions(style);local old=self.nodes[key]
  local starting=(old==nil or old.hidden==true)and enabled~=false and type(style._starting)=='table'and next(style._starting)~=nil
  local current
  if starting then
   local startStyle=table.clone(style);for k,v in pairs(style._starting)do startStyle[k]=v end;startStyle._starting=nil
   current=M.base(startStyle,context)
  else current=old and sample(old,now)or base end
  local record={base=base,tracks=old and old.tracks or {},animations={},hidden=enabled==false}
  local prepared=enabled~=false and M.prepare(style,definitions,width,resolve,context)or {}
  local matched={}
  for i=#prepared,1,-1 do
   local a=prepared[i];local previous
   if old then for j=#old.animations,1,-1 do
    if not matched[j]and old.animations[j].name==a.name then previous=old.animations[j];matched[j]=true;break end
   end end
   if previous then
    a.start=previous.start;a.pausedAt=previous.pausedAt;a.progress=previous.progress
    if a.play=='paused'and not a.pausedAt then a.pausedAt=now elseif a.play=='running'and a.pausedAt then a.start+=now-a.pausedAt;a.pausedAt=nil end
   else a.start=now;a.pausedAt=a.play=='paused'and now or nil end
   record.animations[i]=a
  end
  for _,p in ipairs(Advanced.trackable(base,transitions))do
   local spec=transitions[p];if not spec then record.tracks[p]=nil end
   local changed=(old~=nil and not old.hidden and not M.equal(old.base[p],base[p]))or(starting and current[p]~=nil and base[p]~=nil and not M.equal(current[p],base[p]))
   if changed then
    if enabled~=false and not self.reduced and spec and spec.duration+spec.delay>0 and current[p]~=nil and base[p]~=nil and not M.equal(current[p],base[p])and Advanced.transitionable(p,current[p],base[p],spec)then
     record.tracks[p]={from=current[p],to=base[p],start=now+spec.delay,duration=spec.duration,ease=spec.ease}
    else record.tracks[p]=nil end
   end
  end
  if enabled==false then record.tracks={}end
  self.nodes[key]=record
 end
 function self:step(now,force)
  if not self.alive then return end;now=now or self.clock();local work=false
  force=force==true or self.forceNext==true;self.forceNext=nil
  for key,record in pairs(self.nodes)do local values,active=sample(record,now);self.values[key]=values;work=work or active end
  self.steps+=1;if applyCallback then applyCallback(self.values,force==true)end;self:_sync(work);return self.values,work
 end
 function self:setReducedMotion(value)
  if not self.alive then return end
  value=value==true;if self.reduced==value then return end;self.reduced=value
  for _,r in pairs(self.nodes)do r.settled=nil end
  if value then for _,r in pairs(self.nodes)do table.clear(r.tracks)end end
  if self.manual then self:step(nil,true)else self.forceNext=true;self:_sync(true)end
 end
 function self:timelines(key)
  local record=self.nodes[key];if not record then return nil end
  local out
  for i,a in ipairs(record.animations)do if a.timeline then out=out or{};out[i]=a.timeline end end
  return out
 end
 function self:setProgress(key,progress)
  local record=self.nodes[key];if not record then return false end
  local changed=false
  for i,a in ipairs(record.animations)do
   if a.timeline and not a.pausedAt then
    local p=progress and progress[i]
    if a.progress~=p then a.progress=p;changed=true end
   end
  end
  if changed then record.settled=nil end
  return changed
 end
 function self:remove(key)self.nodes[key]=nil;self.values[key]=nil end
 function self:stats()
  local transitions,animations=0,0;local now=self.clock()
  for _,r in pairs(self.nodes)do for _ in pairs(r.tracks)do transitions+=1 end;for _,a in ipairs(r.animations)do local _,active=animationProgress(a,now,self.reduced);if active then animations+=1 end end end
  return {transitions=transitions,animations=animations,connected=self.connection~=nil,steps=self.steps}
 end
 function self:destroy()
  if not self.alive then return end;self.alive=false;if self.connection then self.connection:Disconnect();self.connection=nil end
  table.clear(self.nodes);table.clear(self.values);applyCallback=nil;self.clock=os.clock;self.forceNext=nil
 end
 return self
end
return M
