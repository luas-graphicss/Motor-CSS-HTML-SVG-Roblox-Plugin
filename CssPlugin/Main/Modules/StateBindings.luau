local B={}
local function pressed(input)
 return input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.ButtonA
end
local Appearance=require(script.Parent.FormAppearance)
local HitTesting=require(script.Parent.HitTesting)
local UserInputService=game:GetService('UserInputService')
function B.keyboard()
 local ok,last=pcall(function()return UserInputService:GetLastInputType()end)
 return ok and last~=nil and Appearance.keyboardInput[last.Name]==true
end
local function maskOf(n,contract)
 return (n.hover and 'h' or '')..(n.active and 'a' or '')..(n.focus and 'f' or '')..(n['focus-visible'] and 'v' or '')..(n.disabled and 'd' or '')..(contract and 'c' or '')
end
function B.new(owner,connect,setState)
 local self={groups={},release=nil,count=0,alive=true,contracts=0}
 local function disconnect(c,key)
  if owner._unlinkConnection then owner._unlinkConnection(c)else
   c:Disconnect();local i=table.find(owner.connections,c);if i then table.remove(owner.connections,i)end
  end
  local links=key and owner.nodeConnections[key]
  if links then local j=table.find(links,c);if j then table.remove(links,j) end end
 end
 function self:remove(key)
  local group=self.groups[key];if not group then return end
  for _,c in ipairs(group.links) do disconnect(c,key);self.count-=1 end
  if group.contract then self.contracts-=1;if owner.pointer then owner.pointer:unwatch(key)end end
  table.clear(group.links);self.groups[key]=nil
 end
 function self:contract(key)
  local group=self.groups[key]
  return group~=nil and group.contract==true
 end
 function self:sync(needs)
  if not self.alive then return end
  needs=needs or {};local activeCount=0
  for key,group in pairs(self.groups) do
   local n=needs[key]
   local mask=n and maskOf(n,owner.pointer~=nil and(n.hover or n.active)and HitTesting.contract(owner,key)) or ''
   if mask~=group.mask or owner.objects[key]~=group.object then self:remove(key) end
  end
  for key,n in pairs(needs) do
   local object=owner.objects[key]
   if object and owner.state[key] then
    if n.active then activeCount+=1 end
    local contract=owner.pointer~=nil and(n.hover or n.active)and HitTesting.contract(owner,key)
    local mask=maskOf(n,contract)
    if mask~='' and not self.groups[key] then
     local group={mask=mask,object=object,links={},contract=contract};self.groups[key]=group
     local function on(signal,fn)
      local c=connect(signal,fn,key);group.links[#group.links+1]=c;self.count+=1
     end
     if contract then
      self.contracts+=1
      owner.pointer:watchKey(key,{hover=n.hover==true,active=n.active==true})
     else
      if n.hover then on(object.MouseEnter,function()
       if HitTesting.receives(owner.styles and owner.styles[key])then setState(key,'hover',true)end
      end) end
      if n.hover or n.active then on(object.MouseLeave,function()
       if n.hover then setState(key,'hover',false) end
       if n.active then setState(key,'active',false) end
      end) end
      if n.active then on(object.InputBegan,function(input)
       local state=owner.state[key]
       if state and not state.disabled and pressed(input) and HitTesting.receives(owner.styles and owner.styles[key]) then setState(key,'active',true) end
      end) end
     end
     if n.focus or n['focus-visible'] then
      local tracksVisible=n['focus-visible']==true
      local node=owner.nodes[key]
      local function gained()
       setState(key,'focus',true)
       if tracksVisible then setState(key,'focus-visible',Appearance.focusVisible(node,B.keyboard())) end
      end
      local function lost()
       setState(key,'focus',false)
       if tracksVisible then setState(key,'focus-visible',false) end
      end
      on(object.SelectionGained,gained)
      on(object.SelectionLost,lost)
      if object:IsA('TextBox') then
       on(object.Focused,gained)
       on(object.FocusLost,lost)
      end
     end
     if n.disabled and not object:IsA('GuiButton') and not object:IsA('TextBox') then
      on(object:GetAttributeChangedSignal('CssDisabled'),function()setState(key,'disabled',object:GetAttribute('CssDisabled')==true)end)
     end
    end
   end
  end
  if activeCount>0 and not self.release then
   self.release=connect(game:GetService('UserInputService').InputEnded,function(input)
    if pressed(input) then
     for key,group in pairs(self.groups) do
      local state=owner.state[key]
      if group.mask:find('a',1,true) and state and state.active then setState(key,'active',false) end
     end
    end
   end)
   self.count+=1
  elseif activeCount==0 and self.release then
   disconnect(self.release);self.release=nil;self.count-=1
  end
 end
 function self:destroy()
  if not self.alive then return end;self.alive=false
  for key in pairs(self.groups) do self:remove(key) end
  if self.release then disconnect(self.release);self.release=nil;self.count-=1 end
  table.clear(self.groups);owner=nil
 end
 return self
end
return B
