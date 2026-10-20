local HitTesting=require(script.Parent.HitTesting)
local UserInputService=game:GetService('UserInputService')
local RunService=game:GetService('RunService')
local P={VERSION=1}
local function pressed(input)
 return input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.ButtonA
end
local function moving(input)
 return input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch
end
function P.new(owner,connect,setState,options)
 options=options or {}
 local self={watch={},count=0,alive=true,hoverKey=nil,hoverChain={},lastX=nil,lastY=nil,icon=nil,iconHidden=false,cursorActive=false,links={},keyboard=nil}
 local live=RunService:IsRunning()and RunService:IsClient()
 local function disconnect(c)
  if owner._unlinkConnection then owner._unlinkConnection(c)else
   c:Disconnect();local i=table.find(owner.connections,c);if i then table.remove(owner.connections,i)end
  end
 end
 local function applyIcon(icon)
  if icon==self.icon then return end
  self.icon=icon
  if not live then return end
  pcall(function()
   if icon=='none'then UserInputService.MouseIconEnabled=false;self.iconHidden=true
   else
    if self.iconHidden then UserInputService.MouseIconEnabled=true;self.iconHidden=false end
    UserInputService.MouseIcon=icon or''
   end
  end)
 end
 function self:cursorAt(x,y)
  local key=HitTesting.pick(owner,x,y)
  if key==nil then return''end
  return HitTesting.cursorOf(owner,key)
 end
 function self:cursorFor(key)
  if key==nil then return''end
  return HitTesting.cursorOf(owner,key)
 end
 function self:apply(x,y)
  if not self.alive or not owner.alive or not owner.sequence then return nil end
  self.lastX,self.lastY=x,y
  local key=HitTesting.pick(owner,x,y)
  local chain=key and HitTesting.chain(owner,key)or {}
  self.hoverKey=key;self.hoverChain=chain
  for k,needs in pairs(self.watch)do
   local over=chain[k]==true
   if needs.hover then setState(k,'hover',over)end
   if needs.active and not over then local state=owner.state[k];if state and state.active then setState(k,'active',false)end end
  end
  if self.cursorActive then applyIcon(key and HitTesting.cursorOf(owner,key)or'')else applyIcon('')end
  return key
 end
 function self:move(x,y)return self:apply(x,y)end
 function self:moveScreen(sx,sy)local x,y=HitTesting.fromScreen(owner,sx,sy);return self:apply(x,y)end
 function self:press(x,y)
  if x~=nil then self:apply(x,y)end
  local chain=self.hoverChain
  for k,needs in pairs(self.watch)do
   if needs.active and chain[k]then
    local state=owner.state[k]
    if state and not state.disabled and HitTesting.receives(owner.styles and owner.styles[k])then setState(k,'active',true)end
   end
  end
 end
 function self:release()
  for k,needs in pairs(self.watch)do if needs.active then local state=owner.state[k];if state and state.active then setState(k,'active',false)end end end
 end
 function self:leave()
  self.hoverKey=nil;self.hoverChain={};self.lastX,self.lastY=nil,nil
  for k,needs in pairs(self.watch)do
   if needs.hover then setState(k,'hover',false)end
   if needs.active then setState(k,'active',false)end
  end
  applyIcon('')
 end
 function self:refresh()
  if self.lastX~=nil then self:apply(self.lastX,self.lastY)end
 end
 local function ensure()
  local wanted=self.alive and(self.count>0 or self.cursorActive)
  if wanted and #self.links==0 then
   self.links[1]=connect(UserInputService.InputChanged,function(input)if moving(input)then self:moveScreen(input.Position.X,input.Position.Y)end end)
   self.links[2]=connect(UserInputService.InputBegan,function(input)
    if pressed(input)then
     if input.UserInputType==Enum.UserInputType.Touch then self:moveScreen(input.Position.X,input.Position.Y)end
     self:press()
    end
   end)
   self.links[3]=connect(UserInputService.InputEnded,function(input)
    if pressed(input)then self:release();if input.UserInputType==Enum.UserInputType.Touch then self:leave()end end
   end)
   self.links[4]=connect(UserInputService.WindowFocusReleased,function()self:leave()end)
  elseif not wanted and #self.links>0 then
   for _,c in ipairs(self.links)do disconnect(c)end
   table.clear(self.links);applyIcon('')
  end
 end
 function self:watchKey(key,needs)
  if self.watch[key]==nil then self.count+=1 end
  self.watch[key]=needs;ensure()
 end
 function self:unwatch(key)
  if self.watch[key]==nil then return end
  self.watch[key]=nil;self.count-=1;ensure()
 end
 function self:sync()
  if not self.alive then return end
  local active=false
  local styles=owner.styles
  if styles then
   for _,style in pairs(styles)do
    local cursor=style.cursor
    if cursor~=nil and cursor~='auto'and cursor~='default'then active=true;break end
   end
  end
  self.cursorActive=active
  ensure()
  self:refresh()
 end
 function self:installKeyboard(focusNext)
  if self.keyboard or options.keyboardNavigation==false or not live then return end
  self.keyboard=connect(UserInputService.InputBegan,function(input,processed)
   if input.KeyCode~=Enum.KeyCode.Tab then return end
   local focused=UserInputService:GetFocusedTextBox()
   if focused and focused:IsA('TextBox')and focused.MultiLine then return end
   local shift=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
   pcall(focusNext,shift and -1 or 1)
  end)
 end
 function self:stats()return {watched=self.count,connections=#self.links+(self.keyboard and 1 or 0),cursor=self.icon or'',hover=self.hoverKey}end
 function self:destroy()
  if not self.alive then return end;self.alive=false
  for _,c in ipairs(self.links)do disconnect(c)end;table.clear(self.links)
  if self.keyboard then disconnect(self.keyboard);self.keyboard=nil end
  if self.iconHidden then pcall(function()UserInputService.MouseIconEnabled=true end)end
  if live and self.icon and self.icon~=''then pcall(function()UserInputService.MouseIcon=''end)end
  table.clear(self.watch);self.count=0;owner=nil
 end
 return self
end
return P
