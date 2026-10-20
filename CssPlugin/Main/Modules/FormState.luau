local F={VERSION=1}
F.types=table.freeze({text=true,email=true,url=true,number=true,checkbox=true,radio=true,file=true,password=true,search=true,tel=true,date=true,time=true,['datetime-local']=true,month=true,week=true,color=true,range=true,hidden=true,submit=true,button=true,reset=true})
F.mask=function(value)return string.rep('•',utf8.len(value)or #value)end
F.attributes=table.freeze({checked=true,readonly=true,required=true,min=true,max=true,step=true,minlength=true,maxlength=true,['aria-checked']=true,indeterminate=true,autofill=true,placeholder=true})
local function flag(value)return value~=nil and value~=false and value~='false'end
F.flag=flag
local Appearance=require(script.Parent.FormAppearance)
function F.isToggle(node)return node.tag=='input'and(node.attrs.type=='checkbox'or node.attrs.type=='radio')end
function F.isInput(node)return node.tag=='input'or node.tag=='textarea'end
local function finite(n)return n and n==n and math.abs(n)<math.huge end
local function email(value)
 local a,b=value:match('^([^@%s]+)@([^@%s]+)$');if not a or not b then return false end
 if a:find('[^%w.!#$%%&\'*+/=?^_`{|}~%-]')then return false end
 for label in (b..'.'):gmatch('(.-)%.')do
  if label==''or label:find('[^%w%-]')or label:sub(1,1)=='-'or label:sub(-1)=='-'then return false end
 end
 return true
end
function F.evaluate(node,state)
 state=state or {};local attrs=node.attrs or {};local input=F.isInput(node)
 local disabled=state.disabled;if disabled==nil then disabled=flag(attrs.disabled)end
 local checked=state.checked;if checked==nil then checked=flag(attrs.checked)or attrs['aria-checked']=='true'end
 local readonly=state.readonly;if readonly==nil then readonly=flag(attrs.readonly)end
 local requiredFlag=flag(attrs.required)or state.groupRequired==true
 local result={disabled=disabled==true,checked=checked==true,['read-only']=not input or F.isToggle(node)or disabled==true or readonly==true or(node.tag=='input'and attrs.type=='file')}
 result.required=(input and requiredFlag)==true
 result.optional=(input and not requiredFlag)==true
 result.default=((F.isToggle(node)and flag(attrs.checked))or(node.tag=='button'and(attrs.type==nil or attrs.type=='submit')))==true
 local indeterminate=state.indeterminate;if indeterminate==nil then indeterminate=flag(attrs.indeterminate)end
 result.indeterminate=((F.isToggle(node)or attrs.role=='checkbox')and indeterminate)==true
 local autofill=state.autofill;if autofill==nil then autofill=flag(attrs.autofill)end
 result.autofill=(input and autofill)==true
 result['placeholder-shown']=false;result['user-valid']=false;result['user-invalid']=false;result['in-range']=false;result['out-of-range']=false
 if not input or disabled then return result end
 local value=state.value;if value==nil then value=attrs.value or node.text or ''end;value=tostring(value)
 local valid=true;local kind=attrs.type or 'text'
 if state.customValidity~=nil then valid=state.customValidity==true
 elseif readonly then valid=true
 elseif F.isToggle(node)then valid=not(flag(attrs.required)or state.groupRequired)or(state.groupChecked~=nil and state.groupChecked or checked)==true
 else
  if flag(attrs.required)and value==''then valid=false end
  if value~=''then
   local size=utf8.len(value)or #value;local lo,hi=tonumber(attrs.minlength),tonumber(attrs.maxlength)
   if(lo and size<lo)or(hi and size>hi)then valid=false end
   if kind=='email'then valid=valid and email(value)
   elseif kind=='url'then valid=valid and value:match('^%a[%w+%.%-]*:%S+$')~=nil
   elseif kind=='number'then
    local number=tonumber(value);valid=valid and finite(number)~=nil and finite(number)~=false
    if finite(number)then
     local min,max=tonumber(attrs.min),tonumber(attrs.max)
     if(min and number<min)or(max and number>max)then valid=false end
     if attrs.step~='any'then
      local step=tonumber(attrs.step)or 1
      if step<=0 then valid=false else local q=(number-(min or 0))/step;if math.abs(q-math.round(q))>1e-7 then valid=false end end
     end
    end
   end
  end
 end
 result.valid=valid==true;result.invalid=not result.valid
 if not F.isToggle(node)then
  local placeholder=attrs.placeholder
  result['placeholder-shown']=value==''and placeholder~=nil and placeholder~=''
  if state.touched==true then result['user-valid']=result.valid;result['user-invalid']=result.invalid end
  local number=tonumber(value)
  if kind=='number'and value~=''and finite(number)then
   local min,max=tonumber(attrs.min),tonumber(attrs.max)
   if min or max then
    local outside=(min and number<min)or(max and number>max)
    result['out-of-range']=outside==true;result['in-range']=outside~=true
   end
  end
 end
 return result
end
function F.initial(node)
 local s={disabled=flag(node.attrs.disabled),checked=flag(node.attrs.checked)or node.attrs['aria-checked']=='true',readonly=flag(node.attrs.readonly)}
 for k,v in pairs(F.evaluate(node,s))do s[k]=v end;return s
end
function F.matches(name,node,state)
 local s=state and state[node.key]or {}
 if name=='target'then return s.target==true end
 if name=='enabled'then return(F.isInput(node)or node.tag=='button')and not F.evaluate(node,s).disabled end
 if name=='read-write'then return not F.evaluate(node,s)['read-only']end
 return F.evaluate(node,s)[name]==true
end
function F.install(owner,connect,queue)
 local function keyOf(id)return owner.ids[id]or id end
 local function changed(key)queue(key,'style')end
 local function nodeFor(id)local key=keyOf(id);return assert(owner.nodes[key],'ID desconhecido: '..tostring(id)),key end
 local function native(key,name,value)
  local object=owner.objects[key];if object and object:GetAttribute(name)~=value then object:SetAttribute(name,value)end
 end
 local function group(node)
  local parent=owner.nodeParents[node.key]
  while parent and parent.tag~='form'do parent=owner.nodeParents[parent.key]end
  return(parent and parent.key or owner.document.root.key)..':'..(node.attrs.name or node.key)
 end
 function owner:setChecked(id,value)
  local node,key=nodeFor(id);value=value==true
  assert(F.isToggle(node)or node.attrs.role=='checkbox'or node.attrs.role=='radio',':checked exige checkbox/radio ou role correspondente.')
  if value and node.attrs.type=='radio'then
   for otherKey,other in pairs(self.nodes)do
    if otherKey~=key and other.attrs.type=='radio'and group(other)==group(node)then
     self.state[otherKey].checked=false;other.attrs.checked=nil;native(otherKey,'CssChecked',false);changed(otherKey)
    end
   end
  end
  self.state[key].checked=value;node.attrs.checked=value and 'true'or nil;native(key,'CssChecked',value);changed(key)
 end
 function owner:setReadOnly(id,value)
  local node,key=nodeFor(id);assert(F.isInput(node),'read-only: controle de entrada esperado.')
  self.state[key].readonly=value==true;node.attrs.readonly=value and 'true'or nil;native(key,'CssReadOnly',value==true);changed(key)
 end
 function owner:setValidity(id,value)
  local node,key=nodeFor(id);assert(F.isInput(node),'Validação exige input/textarea.');assert(value==nil or type(value)=='boolean','Validade deve ser boolean ou nil.')
  self.state[key].customValidity=value;native(key,'CssValid',value);changed(key)
 end
 function owner:setIndeterminate(id,value)
  local node,key=nodeFor(id);assert(F.isToggle(node)or node.attrs.role=='checkbox',':indeterminate exige checkbox/radio ou role correspondente.')
  self.state[key].indeterminate=value==true;node.attrs.indeterminate=value==true and 'true'or nil;native(key,'CssIndeterminate',value==true);changed(key)
 end
 function owner:setAutofill(id,value)
  local node,key=nodeFor(id);assert(F.isInput(node),':autofill exige input/textarea.')
  self.state[key].autofill=value==true;native(key,'CssAutofill',value==true);changed(key)
 end
 function owner:setUserInteracted(id,value)
  local node,key=nodeFor(id);assert(F.isInput(node),':user-valid/:user-invalid exigem input/textarea.')
  self.state[key].touched=value~=false;changed(key)
 end
 function owner:setCustomState(id,name,value)
  local _,key=nodeFor(id)
  assert(type(name)=='string'and #name<=48 and name:match('^[%a_][%w_%-]*$'),':state() exige um identificador simples.')
  local s=self.state[key];s.customStates=s.customStates or {}
  if value==false then s.customStates[name:lower()]=nil else s.customStates[name:lower()]=true end
  local count=0;for _ in pairs(s.customStates)do count+=1 end
  assert(count<=32,'Maximo de 32 estados customizados por elemento.')
  changed(key)
 end
 function owner:setValue(id,value)
  local node,key=nodeFor(id);assert(F.isInput(node)and not F.isToggle(node),'setValue exige uma entrada de texto.')
  assert(type(value)=='string'and #value<=32000,'Valor de entrada inválido.')
  local object=self.objects[key];if object and object:IsA('TextBox')then object.Text=value end
  self.state[key].value=value;node.attrs.value=value;changed(key)
 end
 local function importFilter(node)
  local accept=node.attrs.accept
  if type(accept)~='string'or accept==''then return nil end
  local out={}
  for item in accept:gmatch('[^,]+')do
   local token=item:gsub('%s',''):lower()
   local extension=token:match('^%.([%w%+%-]+)$')or token:match('^[%w%-]+/([%w%+%-]+)$')
   if extension and extension~='*'then out[#out+1]=extension end
  end
  if #out==0 then return nil end
  return out
 end
 function owner:openFileDialog(id)
  local node,key=nodeFor(id)
  assert(node.tag=='input'and node.attrs.type=='file','openFileDialog exige input[type=file].')
  local current=self.state[key]
  if not self.alive or not current or current.disabled then return nil end
  self._filePrompts=self._filePrompts or {}
  if self._filePrompts[key]then return nil end
  self._filePrompts[key]=true
  local okService,service=pcall(function()return game:GetService('StudioService')end)
  local imported
  if okService and service then
   local filter=importFilter(node)
   local okPrompt,result=pcall(function()
    if flag(node.attrs.multiple)and service.PromptImportFiles then return service:PromptImportFiles(filter)end
    if service.PromptImportFile then return service:PromptImportFile(filter)end
    return nil
   end)
   if okPrompt then imported=result end
  end
  self._filePrompts[key]=nil
  if not self.alive or not self.state[key]then return nil end
  local list={}
  if typeof(imported)=='Instance'then list[1]=imported
  elseif type(imported)=='table'then for _,item in ipairs(imported)do if typeof(item)=='Instance'then list[#list+1]=item end end end
  if #list==0 then return nil end
  local names={}
  for _,file in ipairs(list)do names[#names+1]=file.Name end
  local text=table.concat(names,', ')
  self.files=self.files or {}
  self.files[key]=list
  self.state[key].value=text;self.state[key].touched=true;node.attrs.value=text
  local object=self.objects[key]
  if object then
   if object:IsA('TextBox')and object.Text~=text then object.Text=text end
   if object:GetAttribute('CssFileName')~=names[1]then object:SetAttribute('CssFileName',names[1])end
   if object:GetAttribute('CssFileCount')~=#list then object:SetAttribute('CssFileCount',#list)end
  end
  changed(key)
  return text
 end
 function owner:importedFiles(id)
  local _,key=nodeFor(id)
  return self.files and self.files[key]or nil
 end
 function owner:setTarget(id)
  assert(id==nil or type(id)=='string','Target deve ser um ID, fragmento #id ou nil.')
  local target=(id or ''):gsub('^#','');self.target=target
  for key,node in pairs(self.nodes)do local value=target~=''and node.attrs.id==target;if self.state[key].target~=value then self.state[key].target=value;changed(key)end end
  if self.gui:GetAttribute('CssTarget')~=target then self.gui:SetAttribute('CssTarget',target)end
 end
 function owner:setAttribute(id,name,value)
  local node,key=nodeFor(id)
  assert(type(name)=='string'and(F.attributes[name]or name:sub(1,5)=='data-'),'Atributo dinâmico não suportado; use setClass/setValue para classe/valor.')
  assert(value==nil or type(value)=='boolean'or type(value)=='string'or type(value)=='number','Atributo inválido.')
  if name=='checked'then return self:setChecked(id,flag(value))elseif name=='readonly'then return self:setReadOnly(id,flag(value))
  elseif name=='indeterminate'then return self:setIndeterminate(id,flag(value))elseif name=='autofill'then return self:setAutofill(id,flag(value))end
  node.attrs[name]=value~=nil and tostring(value)or nil;changed(key)
 end
 function owner:_syncFormState()
  local groups={}
  for key,node in pairs(self.nodes)do
   local s=self.state[key];local object=self.objects[key]
   if object and F.isInput(node)and object:IsA('TextBox')then s.value=object.Text end
   if node.attrs.type=='radio'then
    local g=group(node);groups[g]=groups[g]or {checked=false,required=false};groups[g].checked=groups[g].checked or s.checked==true;groups[g].required=groups[g].required or flag(node.attrs.required)
   end
  end
  for key,node in pairs(self.nodes)do
   local s=self.state[key]
   if node.attrs.type=='radio'then
    local g=groups[group(node)];s.groupChecked=g.checked;s.groupRequired=g.required
    local copy=table.clone(node);copy.attrs=table.clone(node.attrs);if g.required then copy.attrs.required='true'end
    for k,v in pairs(F.evaluate(copy,s))do s[k]=v end
   else
    s.valid=nil;s.invalid=nil
    for k,v in pairs(F.evaluate(node,s))do s[k]=v end
   end
   if s.disabled then s.valid=nil;s.invalid=nil end
   local object=self.objects[key]
   if object and F.isToggle(node)and object:IsA('TextButton')then
    local glyph=Appearance.glyph(node,self.styles and self.styles[key],s)
    if object.Text~=glyph then object.Text=glyph end
   end
  end
 end
 function owner:_bindFormNode(key,object)
  local node=self.nodes[key];local s=self.state[key]
  if not F.isInput(node)and node.attrs.role~='checkbox'and node.attrs.role~='radio'then return end
  for _,pair in ipairs({{'CssChecked','checked'},{'CssReadOnly','readonly'},{'CssValid','customValidity'},{'CssIndeterminate','indeterminate'},{'CssAutofill','autofill'}})do
   local attr,name=pair[1],pair[2]
   local existing=object:GetAttribute(attr);if existing~=nil then s[name]=existing==true end
   connect(object:GetAttributeChangedSignal(attr),function()
    if not self.alive or not self.state[key]then return end
    local value=object:GetAttribute(attr)
    if name=='checked'and value==true and node.attrs.type=='radio'then self:setChecked(key,true)
    else
     if value==nil then self.state[key][name]=nil else self.state[key][name]=value==true end
     changed(key)
    end
   end,key)
  end
  if object:IsA('TextBox')and node.tag=='input'and node.attrs.type=='password'then
   local masking=false
   connect(object:GetPropertyChangedSignal('Text'),function()
    if masking or not self.state[key]then return end
    local shown=object.Text;local real=self.state[key].value or ''
    local shownLen=utf8.len(shown)or #shown;local realLen=utf8.len(real)or #real
    if shownLen<realLen then
     local cut=utf8.offset(real,shownLen+1);real=cut and real:sub(1,cut-1)or real
    else
     local extra={};for _,cp in utf8.codes(shown)do if cp~=0x2022 then extra[#extra+1]=utf8.char(cp)end end
     real=real..table.concat(extra)
    end
    self.state[key].value=real;self.state[key].touched=true
    masking=true;object.Text=F.mask(real);masking=false
    changed(key)
   end,key)
   connect(object.FocusLost,function()if self.state[key]then self.state[key].touched=true;changed(key)end end,key)
  elseif object:IsA('TextBox')then
   connect(object:GetPropertyChangedSignal('Text'),function()if self.state[key]then self.state[key].value=object.Text;self.state[key].touched=true;changed(key)end end,key)
   connect(object.FocusLost,function()if self.state[key]then self.state[key].touched=true;changed(key)end end,key)
  end
  if node.tag=='input'and node.attrs.type=='file'then
   connect(object.InputBegan,function(input)
    if not self.alive or not self.state[key]or self.state[key].disabled then return end
    local kind=input.UserInputType
    if kind~=Enum.UserInputType.MouseButton1 and kind~=Enum.UserInputType.Touch then return end
    if object:IsA('TextBox')then pcall(function()object:ReleaseFocus(false)end)end
    task.spawn(function()pcall(function()self:openFileDialog(key)end)end)
   end,key)
  end
  if F.isToggle(node)and object:IsA('GuiButton')then connect(object.Activated,function()
   if self.alive and self.state[key]and not self.state[key].disabled then self:setChecked(key,node.attrs.type=='radio'or not self.state[key].checked)end
  end,key)end
 end
 connect(owner.gui:GetAttributeChangedSignal('CssTarget'),function()if owner.alive then owner:setTarget(owner.gui:GetAttribute('CssTarget'))end end)
 owner:setTarget(owner.gui:GetAttribute('CssTarget'))
end
return F
