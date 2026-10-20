local Logical=require(script.Parent.LogicalProperties)
local FontFeatures=require(script.Parent.FontFeatures)
local TextWrap=require(script.Parent.TextWrap)
local Typography=require(script.Parent.TypographyStyle)
local Effects=require(script.Parent.VisualEffectsStyle)
local Tracks=require(script.Parent.LayoutTracks)
local LayoutProperties=require(script.Parent.LayoutProperties)
local B={VERSION=1}
local AXES={vertical=false,inlineStart='left',inlineEnd='right',blockStart='top',blockEnd='bottom'}
local CONTEXT={base=200,vw=1000,vh=800,font=16,rootFont=16,lineHeight=20,rootLineHeight=20,anchorPending=true}
local function shape(defaults,key,value)
 local out={}
 if type(defaults)=='table'then for k,v in pairs(defaults)do out[k]=v end end
 if key then out[key]=value end
 return out
end
local function guard(fn)
 return function(value,hooks)
  local ok,result=pcall(fn,value,hooks)
  return ok and result~=false
 end
end
function B.font(key)
 return guard(function(value)
  FontFeatures.normalize(shape(FontFeatures.defaults,key,value),shape(FontFeatures.defaults))
 end)
end
function B.textWrap(key)
 return guard(function(value)
  TextWrap.normalize(shape(TextWrap.defaults,key,value),shape(TextWrap.defaults),function()return 0 end)
 end)
end
function B.typography(key)
 return guard(function(value)
  local style=shape(Typography.defaults,key,value)
  Typography.normalize(style,shape(Typography.defaults),CONTEXT.vw,CONTEXT.vh)
  Typography.advanced(style)
 end)
end
function B.install(supports)
 assert(type(supports)=='table'and type(supports.register)=='function'and type(supports.declaration)=='function','FeatureSupports incompativel com o bridge.')
 local function delegate(key,physical)
  supports.register(key,function(value,hooks)return supports.declaration(physical,value,hooks)==true end)
 end
 for _,key in ipairs({'font-feature-settings','font-variation-settings','font-variant-caps','font-variant-numeric','font-variant-ligatures','font-variant-alternates','font-variant-east-asian','font-variant-position','font-stretch','font-optical-sizing','font-kerning'})do
  supports.register(key,B.font(key))
 end
 for _,key in ipairs({'text-wrap-style','line-break','hyphenate-character','hyphenate-limit-chars','hyphenate-limit-lines','hyphenate-limit-zone','unicode-bidi'})do
  supports.register(key,B.textWrap(key))
 end
 for _,key in ipairs({'text-orientation','text-shadow','text-decoration-line','text-decoration-thickness','text-combine-upright','ruby-position','ruby-align','writing-mode','direction','text-align-last'})do
  supports.register(key,B.typography(key))
 end
 for key in pairs(Logical.supported)do
  local ok,physical=pcall(Logical.physical,key,AXES)
  if ok and type(physical)=='string'and physical~=key then delegate(key,physical)end
 end
 for _,key in ipairs({'filter','backdrop-filter'})do
  supports.register(key,guard(function(value)
   if value:lower()~='none'then Effects.filters(value,CONTEXT)end
  end))
 end
 supports.register('aspect-ratio',function(value)
  if value:lower():match('^%s*auto%s*$')then return true end
  local ok,ratio=pcall(LayoutProperties.ratio,value)
  return ok and type(ratio)=='number'
 end)
 supports.register('mix-blend-mode',function(value)return Effects.blends[value:lower()]==true end)
 supports.register('background-blend-mode',guard(function(value)Effects.blendList(value)end))
 supports.register('clip-path',function(value,hooks)
  local lower=value:lower()
  if lower=='none'then return true end
  return supports.declaration('shape-outside',value,hooks)==true
 end)
 supports.register('grid-template-areas',guard(function(value)
  if value:lower()~='none'then Tracks.areas(value)end
 end))
 delegate('justify-items','align-items')
 delegate('justify-self','align-self')
 return supports
end
return B
