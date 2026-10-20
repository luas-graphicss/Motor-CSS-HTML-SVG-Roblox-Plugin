local U=require(script.Parent.Util)
local Preferences=require(script.Parent.UserPreferences)
local A={VERSION=1}
local appearanceValues=table.freeze({auto=true,none=true,button=true,['push-button']=true,['square-button']=true,textfield=true,textarea=true,searchfield=true,checkbox=true,radio=true,menulist=true,['menulist-button']=true,listbox=true,meter=true,['progress-bar']=true})
A.appearanceValues=appearanceValues
A.properties=table.freeze({'accent-color','appearance'})
A.inherited=table.freeze({'accent-color'})
A.initial=table.freeze({['accent-color']='auto',appearance='auto'})
A.glyphs=table.freeze({radio='●',checkbox='✓',indeterminate='–'})
local function isColor(value)return (pcall(U.color,value))end
local function keyword(value)return type(value)=='string' and value:lower() or nil end
function A.validate(name,value)
 local v=keyword(value)
 if not v then return false end
 if name=='appearance'then return appearanceValues[v]==true end
 if name=='accent-color'then return v=='auto'or isColor(value)end
 return false
end
function A.check(name,value)
 assert(A.validate(name,value),name..' aceita '..(name=='appearance' and 'auto, none ou um controle nativo.' or 'auto ou uma cor.'))
 return value
end
function A.register(supported,shorthandKeys)
 supported['accent-color']=true;supported.appearance=true
 return supported,shorthandKeys
end
function A.install(supports)
 supports.register('appearance',function(value)return A.validate('appearance',value)end)
 supports.register('accent-color',function(value)return A.validate('accent-color',value)end)
end
local function scheme(style,environment)
 local used=style and style._usedColorScheme
 if used=='dark'or used=='light'then return used end
 return (environment and environment.colorScheme)=='dark' and 'dark' or 'light'
end
A.scheme=scheme
local function luminance(c)
 local function channel(v)return v<=0.03928 and v/12.92 or ((v+0.055)/1.055)^2.4 end
 return 0.2126*channel(c.R)+0.7152*channel(c.G)+0.0722*channel(c.B)
end
function A.contrast(color)return luminance(color)>0.45 and Color3.new(0,0,0) or Color3.new(1,1,1)end
function A.accent(style,environment)
 local declared=style and style['accent-color'] or 'auto'
 local forced=(environment and environment.forcedColors)=='active'
 local pinned=forced and (style and style['forced-color-adjust'])~='none'
 if keyword(declared)~='auto' and not pinned then
  local ok,color=pcall(U.color,declared)
  if ok then return color,A.contrast(color),false end
 end
 local palette=Preferences.palette(scheme(style,environment))
 local ok,color=pcall(U.color,palette.accentcolor)
 if not ok then return nil,nil,true end
 local okText,text=pcall(U.color,palette.accentcolortext)
 return color,okText and text or A.contrast(color),true
end
function A.control(node,style)
 local declared=keyword(style and style.appearance) or 'auto'
 if declared=='none'then return 'none',declared end
 if declared~='auto' and appearanceValues[declared] then return declared,declared end
 local tag=node.tag
 if tag=='input'then
  local kind=(node.attrs and node.attrs.type) or 'text'
  if kind=='checkbox' or kind=='radio' then return kind,declared end
  return 'textfield',declared
 end
 if tag=='textarea'then return 'textarea',declared end
 if tag=='button'then return 'button',declared end
 return 'auto',declared
end
local toggles=table.freeze({checkbox=true,radio=true})
function A.glyph(node,style,state)
 if node.tag~='input'then return nil end
 local kind=node.attrs and node.attrs.type
 if not toggles[kind]then return nil end
 if A.control(node,style)=='none'then return ''end
 if state and state.indeterminate then return A.glyphs.indeterminate end
 if state and state.checked then return A.glyphs[kind]end
 return ''
end
function A.native(node,object,style,state,environment)
 local out={}
 local control=A.control(node,style)
 if object:IsA('GuiButton')then out.AutoButtonColor=control~='none'end
 if toggles[control] and state and (state.checked or state.indeterminate) then
  local accent=A.accent(style,environment)
  if accent then out.TextColor3=accent end
 end
 return out,control
end
function A.tabindex(node)
 local raw=node.attrs and node.attrs.tabindex
 if raw==nil then return nil end
 local value=tonumber(raw)
 assert(value and value==math.floor(value),'tabindex aceita um inteiro.')
 return value
end
function A.focusOrder(node)
 local index=A.tabindex(node)
 if index and index>0 then return index end
 return 1000+(node.order or 0)
end
function A.focusable(node,style,state)
 if state and state.disabled then return false end
 if style and (style.display=='none' or style.visibility=='hidden')then return false end
 local index=A.tabindex(node)
 if index and index<0 then return false end
 return true
end
function A.autofocus(node)
 local raw=node.attrs and node.attrs.autofocus
 return raw~=nil and raw~='false'
end
function A.ring(sequence,styles,state,eligible)
 local list={}
 for _,node in ipairs(sequence or {})do
  if (not eligible or eligible(node))and A.focusable(node,styles and styles[node.key],state and state[node.key])then
   list[#list+1]={key=node.key,order=A.focusOrder(node),document=node.order or 0}
  end
 end
 table.sort(list,function(a,b)if a.order~=b.order then return a.order<b.order end return a.document<b.document end)
 return list
end
function A.autofocusNode(sequence,styles,state,eligible)
 for _,node in ipairs(sequence or {})do
  if A.autofocus(node)and(not eligible or eligible(node))and A.focusable(node,styles and styles[node.key],state and state[node.key])then return node end
 end
 return nil
end
A.keyboardInput=table.freeze({Keyboard=true,Gamepad1=true,Gamepad2=true,Gamepad3=true,Gamepad4=true,Gamepad5=true,Gamepad6=true,Gamepad7=true,Gamepad8=true})
function A.alwaysVisible(node)
 if node.tag=='textarea'then return true end
 if node.tag~='input'then return false end
 local kind=(node.attrs and node.attrs.type) or 'text'
 return not toggles[kind]
end
function A.focusVisible(node,keyboard)
 if A.alwaysVisible(node)then return true end
 return keyboard==true
end
return A
