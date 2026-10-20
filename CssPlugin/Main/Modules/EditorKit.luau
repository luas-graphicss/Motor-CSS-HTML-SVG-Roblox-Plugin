local TweenService=game:GetService('TweenService')
local Theme=require(script.Parent.EditorTheme)
local Kit={}
local QUICK=TweenInfo.new(0.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local BREATH=TweenInfo.new(0.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true)
local RIPPLE=TweenInfo.new(1.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out,-1)
function Kit.new(theme,connect)
 local kit={}
 local function make(class,parent,props,map)
  local object=Instance.new(class)
  for key,value in pairs(props)do object[key]=value end
  if map then theme:bind(object,map)end
  object.Parent=parent
  return object
 end
 kit.make=make
 function kit.corner(parent,radius)
  return make('UICorner',parent,{CornerRadius=typeof(radius)=='UDim' and radius or UDim.new(0,radius)})
 end
 function kit.pad(parent,top,right,bottom,left)
  return make('UIPadding',parent,{PaddingTop=UDim.new(0,top),PaddingRight=UDim.new(0,right or top),PaddingBottom=UDim.new(0,bottom or top),PaddingLeft=UDim.new(0,left or right or top)})
 end
 function kit.list(parent,direction,gap,horizontal,vertical)
  return make('UIListLayout',parent,{FillDirection=direction,Padding=UDim.new(0,gap or 0),SortOrder=Enum.SortOrder.LayoutOrder,HorizontalAlignment=horizontal or Enum.HorizontalAlignment.Left,VerticalAlignment=vertical or Enum.VerticalAlignment.Center})
 end
 function kit.divider(parent,edge)
  local top=edge=='top'
  return make('Frame',parent,{Name=top and 'TopRule' or 'BottomRule',AnchorPoint=Vector2.new(0,top and 0 or 1),Position=UDim2.fromScale(0,top and 0 or 1),Size=UDim2.new(1,0,0,1),BorderSizePixel=0,ZIndex=2},{BackgroundColor3='line'})
 end
 function kit.text(parent,props,token)
  if props.BackgroundTransparency==nil then props.BackgroundTransparency=1 end
  props.BorderSizePixel=0
  props.FontFace=props.FontFace or Theme.font('sans')
  props.TextSize=props.TextSize or 14
  props.TextXAlignment=props.TextXAlignment or Enum.TextXAlignment.Left
  props.TextYAlignment=props.TextYAlignment or Enum.TextYAlignment.Center
  return make('TextLabel',parent,props,token~=false and {TextColor3=token or 'ink'} or nil)
 end
 function kit.button(parent,spec)
  local variant=spec.variant or 'secondary'
  local button=make('TextButton',parent,{Name=spec.name,Text='',AutoButtonColor=false,BorderSizePixel=0,Size=spec.size or UDim2.fromOffset(0,spec.height or 34),AutomaticSize=spec.size and Enum.AutomaticSize.None or Enum.AutomaticSize.X,Position=spec.position or UDim2.new(),AnchorPoint=spec.anchor or Vector2.zero,LayoutOrder=spec.order or 0})
  kit.corner(button,6)
  kit.pad(button,0,spec.pad or 14,0,spec.pad or 14)
  kit.list(button,Enum.FillDirection.Horizontal,7,Enum.HorizontalAlignment.Center)
  local stroke=make('UIStroke',button,{Thickness=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
  local pending
  if spec.pending then
   pending=make('Frame',button,{Name='Pending',Size=UDim2.fromOffset(6,6),BorderSizePixel=0,Visible=false,LayoutOrder=1})
   kit.corner(pending,UDim.new(0.5,0))
  end
  local label=make('TextLabel',button,{Name='Label',Text=spec.text,BackgroundTransparency=1,BorderSizePixel=0,AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.fromScale(0,1),FontFace=Theme.font('sans',Enum.FontWeight.SemiBold),TextSize=14,LayoutOrder=2})
  local state={hover=false,press=false,enabled=true,tone=nil}
  local function paint(animate)
   local c=theme.colors
   local live=state.enabled and (state.hover or state.press)
   local pressed=state.enabled and state.press
   local background,transparency,foreground,line,outlined
   if variant=='primary' then
    background=pressed and c.accentPress or live and c.accentHover or c.accent
    transparency=state.enabled and 0 or 0.45;foreground=c.accentInk;line=c.accent;outlined=false
   elseif variant=='secondary' then
    background=pressed and c.press or live and c.hover or c.raised
    transparency=0;foreground=c.ink;line=c.line;outlined=true
   else
    background=pressed and c.press or c.hover
    transparency=live and 0 or 1;foreground=live and c.ink or c.muted;line=c.line;outlined=false
   end
   if state.tone=='confirm' then foreground=c.accentText;line=c.accentText;outlined=true end
   stroke.Enabled=outlined;stroke.Color=line;stroke.Transparency=state.enabled and 0 or 0.5
   label.TextColor3=foreground;label.TextTransparency=state.enabled and 0 or 0.5
   if pending then pending.BackgroundColor3=c.accentText end
   if animate then
    TweenService:Create(button,QUICK,{BackgroundColor3=background,BackgroundTransparency=transparency}):Play()
   else
    button.BackgroundColor3=background;button.BackgroundTransparency=transparency
   end
  end
  connect(button.MouseEnter,function()state.hover=true;paint(true)end)
  connect(button.MouseLeave,function()state.hover=false;state.press=false;paint(true)end)
  connect(button.MouseButton1Down,function()state.press=true;paint(true)end)
  connect(button.MouseButton1Up,function()state.press=false;paint(true)end)
  theme:changed(function()paint(false)end)
  paint(false)
  local handle={instance=button,label=label,Activated=button.Activated}
  function handle.setText(text)
   if label.Text~=text then label.Text=text end
  end
  function handle.setEnabled(enabled)
   if state.enabled==enabled then return end
   state.enabled=enabled;button.Interactable=enabled
   if not enabled then state.hover=false;state.press=false end
   paint(true)
  end
  function handle.setTone(tone)
   if state.tone~=tone then state.tone=tone;paint(true)end
  end
  function handle.setPending(visible)
   if pending and pending.Visible~=visible then pending.Visible=visible end
  end
  return handle
 end
 function kit.tabs(parent,items,onSelect)
  local holder=make('Frame',parent,{Name='Tabs',BackgroundTransparency=1,Size=UDim2.fromScale(0,1),AutomaticSize=Enum.AutomaticSize.X,ZIndex=3})
  kit.list(holder,Enum.FillDirection.Horizontal,0)
  local entries,selected={},nil
  local function paint()
   local c=theme.colors
   for key,entry in pairs(entries)do
    local active=key==selected
    entry.glyph.TextColor3=active and c.accentText or c.faint
    entry.label.TextColor3=(active or entry.hover) and c.ink or c.muted
    entry.label.FontFace=Theme.font('sans',active and Enum.FontWeight.SemiBold or Enum.FontWeight.Medium)
    entry.bar.BackgroundColor3=c.accent
    entry.bar.Visible=active
   end
  end
  for index,item in ipairs(items)do
   local button=make('TextButton',holder,{Name=item.name,Text='',AutoButtonColor=false,BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromScale(0,1),AutomaticSize=Enum.AutomaticSize.X,LayoutOrder=index})
   kit.pad(button,0,12,0,12)
   local content=make('Frame',button,{Name='Content',BackgroundTransparency=1,Size=UDim2.fromScale(0,1),AutomaticSize=Enum.AutomaticSize.X})
   kit.list(content,Enum.FillDirection.Horizontal,7)
   local glyph=make('TextLabel',content,{Name='Glyph',Text=item.glyph,BackgroundTransparency=1,AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.fromScale(0,1),FontFace=Theme.font('mono',Enum.FontWeight.Medium),TextSize=13,LayoutOrder=1})
   local label=make('TextLabel',content,{Name='Label',Text=item.text,BackgroundTransparency=1,AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.fromScale(0,1),FontFace=Theme.font('sans',Enum.FontWeight.Medium),TextSize=14,LayoutOrder=2})
   local bar=make('Frame',button,{Name='Indicator',AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale(0,1),Size=UDim2.new(1,0,0,2),BorderSizePixel=0,Visible=false,ZIndex=4})
   local entry={button=button,glyph=glyph,label=label,bar=bar,hover=false}
   entries[item.key]=entry
   connect(button.MouseEnter,function()entry.hover=true;paint()end)
   connect(button.MouseLeave,function()entry.hover=false;paint()end)
   connect(button.Activated,function()onSelect(item.key)end)
  end
  theme:changed(paint)
  local handle={holder=holder,entries=entries}
  function handle.select(key)
   selected=key;paint()
  end
  return handle
 end
 function kit.field(parent,spec)
  local frame=make('Frame',parent,{Name=spec.name,BorderSizePixel=0,Size=spec.size,Position=spec.position or UDim2.new(),AnchorPoint=spec.anchor or Vector2.zero},{BackgroundColor3='raised'})
  kit.corner(frame,6)
  local stroke=make('UIStroke',frame,{Thickness=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
  kit.pad(frame,0,10,0,10)
  kit.list(frame,Enum.FillDirection.Horizontal,0)
  kit.text(frame,{Name='Prefix',Text=spec.prefix or '',FontFace=Theme.font('mono'),TextSize=14,AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.fromScale(0,1),LayoutOrder=1},'faint')
  local box=make('TextBox',frame,{Name='Input',Text=spec.text or '',PlaceholderText=spec.placeholder or '',ClearTextOnFocus=false,BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromScale(0,1),FontFace=Theme.font('mono'),TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,ClipsDescendants=true,LayoutOrder=2},{TextColor3='ink',PlaceholderColor3='faint'})
  make('UIFlexItem',box,{FlexMode=Enum.UIFlexMode.Fill})
  local state={focused=false,invalid=false}
  local function paint()
   local c=theme.colors
   stroke.Color=state.invalid and c.danger or state.focused and c.accentText or c.line
  end
  connect(box.Focused,function()state.focused=true;paint()end)
  connect(box.FocusLost,function()state.focused=false;paint()end)
  theme:changed(paint)
  paint()
  local handle={frame=frame,box=box}
  function handle.setInvalid(invalid)
   if state.invalid~=invalid then state.invalid=invalid;paint()end
  end
  return handle
 end
 function kit.chip(parent,order,text)
  local frame=make('Frame',parent,{Name='Chip',BorderSizePixel=0,AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.fromOffset(0,22),LayoutOrder=order or 0,Visible=text~=nil},{BackgroundColor3='raised'})
  kit.corner(frame,4)
  kit.pad(frame,0,7,0,7)
  local label=kit.text(frame,{Name='Label',Text=text or '',FontFace=Theme.font('mono'),TextSize=13,AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.fromScale(0,1)},'muted')
  local handle={frame=frame,label=label}
  function handle.set(value)
   frame.Visible=value~=nil
   label.Text=value or ''
  end
  return handle
 end
 function kit.mark(parent,spec)
  local holder=make('Frame',parent,{Name='Mark',BackgroundTransparency=1,Size=UDim2.fromOffset(24,24),Position=spec.position or UDim2.new(),AnchorPoint=spec.anchor or Vector2.zero})
  local function layer(name,size,transparency,radius)
   local frame=make('Frame',holder,{Name=name,AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(size,size),BorderSizePixel=0,BackgroundTransparency=transparency},{BackgroundColor3='accent'})
   kit.corner(frame,radius)
   return frame
  end
  local margin=layer('Margin',24,0.86,7)
  local border=layer('Border',16,1,4)
  make('UIStroke',border,{Thickness=1.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},{Color='accent'})
  local padding=layer('Padding',10,0.5,2)
  layer('Content',4,0,1)
  local tweens={}
  local handle={frame=holder}
  function handle.setBusy(busy)
   for _,tween in ipairs(tweens)do tween:Cancel()end
   table.clear(tweens)
   if busy then
    tweens[1]=TweenService:Create(margin,BREATH,{BackgroundTransparency=0.6})
    tweens[2]=TweenService:Create(padding,BREATH,{BackgroundTransparency=0.12})
    for _,tween in ipairs(tweens)do tween:Play()end
   else
    margin.BackgroundTransparency=0.86;padding.BackgroundTransparency=0.5
   end
  end
  return handle
 end
 function kit.status(parent,spec)
  local holder=make('Frame',parent,{Name='State',BackgroundTransparency=1,Size=UDim2.fromOffset(10,10),Position=spec.position or UDim2.new(),AnchorPoint=spec.anchor or Vector2.zero})
  local ring=make('Frame',holder,{Name='Ring',AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(10,10),BackgroundTransparency=1,BorderSizePixel=0})
  kit.corner(ring,UDim.new(0.5,0))
  local ringStroke=make('UIStroke',ring,{Thickness=1.5,Transparency=1})
  local core=make('Frame',holder,{Name='Core',AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(8,8),BorderSizePixel=0})
  kit.corner(core,UDim.new(0.5,0))
  local token,pulsing='faint',false
  local tweens={}
  local function paint()
   local color=theme.colors[token]
   core.BackgroundColor3=color;ringStroke.Color=color
  end
  local function stop()
   for _,tween in ipairs(tweens)do tween:Cancel()end
   table.clear(tweens)
   ring.Size=UDim2.fromOffset(10,10);ringStroke.Transparency=1
  end
  theme:changed(paint)
  paint()
  local handle={frame=holder}
  function handle.set(nextToken,pulse)
   token=nextToken;paint()
   if pulse==pulsing then return end
   pulsing=pulse;stop()
   if pulse then
    ringStroke.Transparency=0.15
    tweens[1]=TweenService:Create(ring,RIPPLE,{Size=UDim2.fromOffset(24,24)})
    tweens[2]=TweenService:Create(ringStroke,RIPPLE,{Transparency=1})
    for _,tween in ipairs(tweens)do tween:Play()end
   end
  end
  function handle.destroy()
   pulsing=false;stop()
  end
  return handle
 end
 return kit
end
return Kit
