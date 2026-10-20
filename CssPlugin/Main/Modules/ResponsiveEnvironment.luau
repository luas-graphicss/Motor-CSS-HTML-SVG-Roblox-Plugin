local Q=require(script.Parent.ResponsiveQueries)
local E={VERSION=2}
local attributeKeys=table.freeze({CssColorScheme='colorScheme',CssDevicePixelRatio='devicePixelRatio',CssReducedMotion='reducedMotion',CssMediaType='mediaType',CssInitialFontSize='initialFontSize',CssPointer='pointer',CssAnyPointer='anyPointer',CssHover='hover',CssAnyHover='anyHover',CssForcedColors='forcedColors',CssInvertedColors='invertedColors',CssPrefersContrast='contrast',CssReducedTransparency='reducedTransparency',CssColorGamut='colorGamut'})
local function accept(values,sources,key,value,source)
 if value==nil then return false end
 if not pcall(Q.overrides,{[key]=value})then return false end
 values[key]=value;sources[key]=source;return true
end
local function readDevice(values,sources)
 local ok,input=pcall(function()return game:GetService('UserInputService')end)
 if not ok or not input then return end
 local function flag(name)local s,v=pcall(function()return input[name]end);return s and v==true end
 local mouse,touch,gamepad=flag('MouseEnabled'),flag('TouchEnabled'),flag('GamepadEnabled')
 if not(mouse or touch or gamepad)then return end
 local primary=mouse and 'fine'or(touch or gamepad)and 'coarse'or 'none'
 local hover=mouse and 'hover'or 'none'
 values.pointer=primary;values.anyPointer=primary;values.hover=hover;values.anyHover=hover
 for _,key in ipairs({'pointer','anyPointer','hover','anyHover'})do sources[key]='UserInputService'end
end
function E.overrides(options)
 options=options or {};local out=Q.overrides(options.mediaEnvironment)
 if options.reducedMotion~=nil then assert(type(options.reducedMotion)=='boolean','reducedMotion exige boolean.');out.reducedMotion=options.reducedMotion end
 return out
end
function E.read(gui,overrides,useStudioTheme)
 local values,sources={},{colorScheme='fallback',devicePixelRatio='fallback',reducedMotion='fallback',pointer='fallback',anyPointer='fallback',hover='fallback',anyHover='fallback',forcedColors='fallback',invertedColors='fallback',contrast='fallback',reducedTransparency='fallback',colorGamut='fallback'}
 local service=game:GetService('GuiService')
 local ok,reduced=pcall(function()return service.ReducedMotionEnabled end)
 if ok and type(reduced)=='boolean'then values.reducedMotion=reduced;sources.reducedMotion='GuiService.ReducedMotionEnabled'end
 local okTransparency,transparency=pcall(function()return service.PreferredTransparency end)
 if okTransparency and type(transparency)=='number'and transparency==transparency then
  values.reducedTransparency=transparency<1;sources.reducedTransparency='GuiService.PreferredTransparency'
 end
 readDevice(values,sources)
 if useStudioTheme then
  local success,name=pcall(function()return settings().Studio.Theme.Name end)
  if success and(name=='Dark'or name=='Light')then values.colorScheme=name:lower();sources.colorScheme='Studio.Theme (not OS)'end
 end
 if gui then
  for attribute,key in pairs(attributeKeys)do accept(values,sources,key,gui:GetAttribute(attribute),attribute)end
 end
 for key,value in pairs(overrides or {})do values[key]=value;sources[key]='override'end
 return Q.environment(values),sources
end
function E.install(self,options,connect,queue)
 local useStudioTheme=options and options.useStudioTheme==true
 self.mediaOverrides=self.mediaOverrides or E.overrides(options)
 function self:_syncMediaEnvironment(notify)
  if not self.alive then return end
  local env,sources=E.read(self.gui,self.mediaOverrides,useStudioTheme);local key=Q.environmentKey(env)
  local changed=key~=self.mediaEnvironmentKey
  self.mediaEnvironment=env;self.mediaEnvironmentKey=key;self.mediaEnvironmentSources=sources
  if self.motion then self.motion:setReducedMotion(env.reducedMotion)end
  if changed and notify~=false then queue(nil,'style')end
  return changed
 end
 function self:getMediaEnvironment()
  assert(self.alive,'Controller encerrado.');self:_syncMediaEnvironment(false)
  return table.clone(self.mediaEnvironment),table.clone(self.mediaEnvironmentSources)
 end
 function self:setMediaEnvironment(values)
  assert(self.alive,'Controller encerrado.');self.mediaOverrides=Q.overrides(values);self:_syncMediaEnvironment(true)
 end
 function self:setReducedMotion(value)
  assert(self.alive,'Controller encerrado.');assert(value==nil or type(value)=='boolean','reducedMotion exige boolean ou nil.')
  self.mediaOverrides.reducedMotion=value;self:_syncMediaEnvironment(true)
 end
 local function changed()if self.alive then self:_syncMediaEnvironment(true)end end
 for attribute in pairs(attributeKeys)do connect(self.gui:GetAttributeChangedSignal(attribute),changed)end
 local service=game:GetService('GuiService')
 local ok,signal=pcall(function()local _=service.ReducedMotionEnabled;return service:GetPropertyChangedSignal('ReducedMotionEnabled')end)
 if ok then connect(signal,changed)end
 local okTransparency,transparencySignal=pcall(function()local _=service.PreferredTransparency;return service:GetPropertyChangedSignal('PreferredTransparency')end)
 if okTransparency then connect(transparencySignal,changed)end
 local okInput,input=pcall(function()return game:GetService('UserInputService')end)
 if okInput and input then
  for _,name in ipairs({'MouseEnabled','TouchEnabled','GamepadEnabled'})do
   local okDevice,deviceSignal=pcall(function()return input:GetPropertyChangedSignal(name)end)
   if okDevice then connect(deviceSignal,changed)end
  end
 end
 if useStudioTheme then
  local success,themeSignal=pcall(function()return settings().Studio:GetPropertyChangedSignal('Theme')end)
  if success then connect(themeSignal,changed)end
 end
 self:_syncMediaEnvironment(false)
end
return E
