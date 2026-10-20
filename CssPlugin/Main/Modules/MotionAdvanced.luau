local U=require(script.Parent.Util)
local Interpolation=require(script.Parent.CssInterpolation)
local Registry=require(script.Parent.PropertyRegistry)
local Universal=require(script.Parent.RuntimeManifest).optional('MotionUniversal')
local A={VERSION=2}
A.universal=Universal
local empty=table.freeze({})
local discrete=table.freeze({display=true,visibility=true})
local behaviors=table.freeze({normal=true,['allow-discrete']=true})
local compositions=table.freeze({replace=true,add=true,accumulate=true})
A.discreteProperties=discrete
A.behaviors=behaviors
A.compositions=compositions
local function custom(name)return type(name)=='string'and name:sub(1,2)=='--'end
A.custom=custom
local function registryOf(style)return style and style._registered or nil end
A.registryOf=registryOf
local function cycle(values,index)return values[(index-1)%#values+1]end
function A.propertyName(value)
 assert(type(value)=='string','Nome de propriedade inválido.')
 local text=U.trim(value)
 return custom(text)and text or text:lower()
end
function A.behaviorKeyword(value)
 if type(value)~='string'then return nil end
 local text=U.trim(value):lower();return behaviors[text]and text or nil
end
function A.animatable(name)
 return custom(name)or discrete[name]==true or Universal.supports(name)
end
function A.universalKind(name)return Universal.kind(name)end
function A.behavior(style,index)
 local values=Interpolation.members(style and style['transition-behavior']or'normal',',')
 local value=U.trim(cycle(values,index or 1)):lower()
 assert(behaviors[value],'transition-behavior aceita normal ou allow-discrete.')
 return value
end
function A.composition(style,index)
 local values=Interpolation.members(style and style['animation-composition']or'replace',',')
 local value=U.trim(cycle(values,index or 1)):lower()
 assert(compositions[value],'animation-composition aceita replace, add ou accumulate.')
 return value
end
function A.allProperties(style,visual,behavior)
 local out={}
 for _,name in ipairs(visual or empty)do out[#out+1]=name end
 local registry=registryOf(style)
 if registry then
  local names={}
  for name,descriptor in pairs(registry)do if descriptor.animatable then names[#names+1]=name end end
  table.sort(names);for _,name in ipairs(names)do out[#out+1]=name end
 end
 if behavior=='allow-discrete'then out[#out+1]='display';out[#out+1]='visibility'end
 local names={}
 for name in pairs(Universal.kinds)do if Universal.declared(style,name)then names[#names+1]=name end end
 table.sort(names);for _,name in ipairs(names)do out[#out+1]=name end
 return out
end
function A.value(property,value,context,style)
 assert(type(value)=='string','Valor animável inválido em '..tostring(property)..'.')
 if custom(property)then
  local typed=Registry.typed(registryOf(style),property,value,context)
  return typed or {t='keyword',v=U.trim(value)}
 end
 if discrete[property]then return {t='keyword',v=U.trim(value):lower()}end
 local universal=Universal.parse(property,value,context)
 if universal then return universal end
 error('Propriedade animável não suportada: '..tostring(property),0)
end
function A.ensureBase(base,property,style,context)
 if base[property]~=nil or not Universal.supports(property)then return base[property]end
 local raw=style and style[property]
 local text=Universal.coerce(property,raw)or Universal.default(property)
 if type(text)~='string'then return nil end
 local ok,value=pcall(Universal.parse,property,text,context)
 if ok and value then base[property]=value end
 return base[property]
end
function A.base(base,style,context)
 local registry=registryOf(style)
 local vars=style and style._vars or empty
 if registry then
  for name,descriptor in pairs(registry)do
   local raw=vars[name]
   local text=type(raw)=='string'and raw or descriptor.initial
   if type(text)=='string'then
    local typed=Registry.typed(registry,name,text,context)
    base[name]=typed or {t='keyword',v=U.trim(text)}
   end
  end
 end
 local mentions=(style and style['transition-property']or'')..' '..(style and style['transition-behavior']or'')
 local allowDiscrete=mentions:find('allow-discrete',1,true)~=nil
 for name in pairs(discrete)do
  if(allowDiscrete or mentions:find(name,1,true))and type(style and style[name])=='string'then
   base[name]={t='keyword',v=U.trim(style[name]):lower()}
  end
 end
 if type(style and style['transition-property'])=='string'then
  for _,item in ipairs(Interpolation.members(style['transition-property'],','))do
   local name=U.trim(item)
   if custom(name)and base[name]==nil and type(vars[name])=='string'then base[name]={t='keyword',v=U.trim(vars[name])}end
  end
 end
 for name in pairs(Universal.mentioned(style))do A.ensureBase(base,name,style,context)end
 if style and style._starting then for name in pairs(style._starting)do A.ensureBase(base,name,style,context)end end
 return base
end
function A.trackable(base,transitions)
 local out={'background','opacity','transform'}
 local extra={}
 for key in pairs(base or empty)do
  if key~='background'and key~='opacity'and key~='transform'then extra[#extra+1]=key end
 end
 for key in pairs(transitions or empty)do
  if base and base[key]==nil and key~='background'and key~='opacity'and key~='transform'then extra[#extra+1]=key end
 end
 table.sort(extra)
 local seen={}
 for _,key in ipairs(extra)do if not seen[key]then seen[key]=true;out[#out+1]=key end end
 return out
end
function A.typed(value)return type(value)=='table'and value.t~=nil end
function A.equal(a,b)
 if not(A.typed(a)and A.typed(b))then return false end
 return Interpolation.equal(a,b)
end
function A.isDiscrete(a,b)
 if not(A.typed(a)and A.typed(b))then return false end
 return not Interpolation.sameShape(a,b)
end
function A.transitionable(property,from,to,spec)
 if not A.isDiscrete(from,to)then return true end
 return spec~=nil and spec.behavior=='allow-discrete'
end
function A.lerp(property,a,b,t)
 if not(A.typed(a)and A.typed(b))then return t<0.5 and a or b end
 if property=='display'then
  if a.v=='none'then return b end
  if b.v=='none'then return t>=1 and b or a end
 end
 if not Interpolation.sameShape(a,b)then return Interpolation.discrete(a,b,t)end
 return Interpolation.interpolate(a,b,t)
end
function A.compose(mode,property,underlying,value)
 if mode==nil or mode=='replace'then return value end
 if A.typed(value)then
  if A.typed(underlying)then return Interpolation.compose(mode,underlying,value)end
  return value
 end
 if property=='opacity'and type(underlying)=='number'and type(value)=='number'then return math.clamp(underlying+value,0,1)end
 if property=='transform'and type(underlying)=='table'and type(value)=='table'and underlying.operations and value.operations then
  return Interpolation.composeTransform(underlying,value,mode)
 end
 return value
end
function A.timeline(style,index)
 if type(style)~='table'or style['animation-timeline']==nil then return nil end
 local Timeline=require(script.Parent.ScrollTimeline)
 local descriptor=Timeline.prepare(style,index or 1)
 if descriptor.kind=='auto'then return nil end
 return descriptor
end
function A.timelineSample(animation,source,key,reduced)
 local descriptor=animation and animation.timeline
 if not descriptor or descriptor.kind=='none'then return nil,false,false end
 local progress
 if type(source)=='function'then
  local ok,value=pcall(source,key,descriptor)
  if ok and type(value)=='number'and value==value and math.abs(value)<math.huge then progress=value end
 end
 if progress==nil then return nil,false,false end
 local fill=animation.fill or'none'
 if progress<0 then
  if fill=='backwards'or fill=='both'then progress=0 else return nil,false,false end
 elseif progress>1 then
  if fill=='forwards'or fill=='both'then progress=1 else return nil,false,false end
 end
 if reduced then progress=progress>=0.5 and 1 or 0 end
 local iterations=animation.iterations or 1
 if iterations<=0 then return nil,false,false end
 local count=(iterations==math.huge)and 1 or math.min(iterations,64)
 local scaled=math.clamp(progress,0,1)*count
 local iteration=math.min(math.floor(scaled),math.max(math.ceil(count)-1,0))
 local t=math.clamp(scaled-iteration,0,1)
 local direction=animation.direction or'normal'
 local reverse=direction=='reverse'or(direction=='alternate'and iteration%2==1)or(direction=='alternate-reverse'and iteration%2==0)
 if reverse then t=1-t end
 return t,false,false
end
function A.customValues(values)
 local out={}
 for key,value in pairs(values or empty)do
  if custom(key)and A.typed(value)then
   local ok,text=pcall(Interpolation.serialize,value)
   if ok then out[key]=text end
  end
 end
 return out
end
function A.register(supported,shorthands)
 supported['transition-behavior']=true
 supported['animation-composition']=true
 if shorthands then
  local transition=shorthands.transition
  if transition then
   for _,key in ipairs(transition)do if key=='transition-behavior'then return end end
   transition[#transition+1]='transition-behavior'
  end
  local animation=shorthands.animation
  if animation then
   for _,key in ipairs(animation)do if key=='animation-composition'then return end end
   animation[#animation+1]='animation-composition'
  end
 end
end
return A
