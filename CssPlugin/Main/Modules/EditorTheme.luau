local Theme={SANS='rbxasset://fonts/families/BuilderSans.json',MONO='rbxasset://fonts/families/BuilderMono.json'}
local PALETTES={
 dark={canvas='141519',surface='1b1c21',raised='24262c',hover='2c2e36',press='34373f',line='2a2c33',band='1d1e24',ink='ecedf1',muted='9a9daa',faint='5e616d',punct='6f7280',comment='7c7f8c',accent='ffa35c',accentHover='ffb577',accentPress='f0914a',accentText='ffa35c',accentInk='1f1408',success='9ccb86',danger='ff7a7a',scroll='3a3d46'},
 light={canvas='fbfbfc',surface='f3f4f6',raised='ffffff',hover='e8e9ed',press='dddfe4',line='dfe1e6',band='eff0f3',ink='17181d',muted='5d6170',faint='a3a6b2',punct='868a97',comment='7d8190',accent='f59a4e',accentHover='f7a965',accentPress='e58a3f',accentText='b45f14',accentInk='1f1408',success='2f7d3a',danger='c93a3a',scroll='c9ccd4'},
}
local SYNTAX={tag='accentText',keyword='accentText',attr='muted',property='ink',string='success',value='success',punct='punct',comment='comment',important='danger'}
for _,palette in pairs(PALETTES)do
 for token,hex in pairs(palette)do palette[token]=Color3.fromHex(hex)end
end
local function detect()
 local ok,color=pcall(function()return settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)end)
 if not ok or typeof(color)~='Color3' then return 'dark' end
 return (0.2126*color.R+0.7152*color.G+0.0722*color.B)<0.5 and 'dark' or 'light'
end
function Theme.font(kind,weight)
 return Font.new(kind=='mono' and Theme.MONO or Theme.SANS,weight or Enum.FontWeight.Regular)
end
function Theme.new()
 local self={}
 local bindings,listeners,connection={},{},nil
 local function load(mode)
  self.mode=mode;self.colors=PALETTES[mode]
  local syntax={}
  for kind,token in pairs(SYNTAX)do syntax[kind]=self.colors[token]:ToHex()end
  self.syntax=syntax
 end
 local function apply(instance,map)
  for property,token in pairs(map)do instance[property]=self.colors[token]end
 end
 function self:bind(instance,map)
  bindings[instance]=map;apply(instance,map)
  return instance
 end
 function self:changed(callback)
  listeners[#listeners+1]=callback
  return callback
 end
 function self:refresh(force)
  local mode=detect()
  if mode==self.mode and not force then return false end
  load(mode)
  for instance,map in pairs(bindings)do apply(instance,map)end
  for _,callback in ipairs(listeners)do callback(mode)end
  return true
 end
 function self:destroy()
  if connection then connection:Disconnect();connection=nil end
  table.clear(bindings);table.clear(listeners)
 end
 load(detect())
 local ok,signal=pcall(function()return settings().Studio.ThemeChanged end)
 if ok and typeof(signal)=='RBXScriptSignal' then connection=signal:Connect(function()self:refresh()end)end
 return self
end
return Theme
