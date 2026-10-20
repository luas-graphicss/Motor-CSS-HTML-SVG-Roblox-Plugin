local O=require(script.Parent.RenderOptimizer)
local Styles=require(script.Parent.Styles)
local DirtyRender=require(script.Parent.DirtyRender)
local Cost=require(script.Parent.CostModel)
local X={}
local function copy(value)
 if type(value)~='table'then return value end
 local result={};for k,v in pairs(value)do result[k]=copy(v)end;return result
end
local function clean(resource)
 local kind=typeof(resource)
 if kind=='RBXScriptConnection'then resource:Disconnect()
 elseif kind=='thread'then if resource~=coroutine.running()then pcall(task.cancel,resource)end
 elseif kind=='function'then pcall(resource)
 elseif kind=='Instance'then resource:Destroy()
 elseif kind=='table'then local fn=resource.Destroy or resource.destroy or resource.Disconnect or resource.Cancel or resource.cancel;if fn then pcall(fn,resource)end
 end
end
function X.install(self,bind,queue,collect,connect)
 local templates,templateSlots={},{};local templateCursor=0
 local watched,mounted,resources,reserved={},{},{},{}
 local removing={};local positions={};self._connectionPositions=positions
 local stats={templateHits=0,templateMisses=0,clones=0,removed=0,cleaned=0}
 local nativeCount=#self.gui:GetDescendants();local reserveCount=0
 local function keyOf(id)return self.ids[id]or id end
 local function invalidate()
  if Styles.invalidate then Styles.invalidate(self.document.root)end
  DirtyRender.reset(self.cache)
 end
 local function unlink(connection)
  connection:Disconnect();local index=positions[connection]
  if index then
   local last=self.connections[#self.connections];self.connections[index]=last;self.connections[#self.connections]=nil
   positions[connection]=nil;if last~=connection then positions[last]=index end
  end
 end
 self._unlinkConnection=unlink
 local function cleanupKey(key)
  if self.stateBindings then self.stateBindings:remove(key)end
  if self.stateNeeds then self.stateNeeds[key]=nil end
  local links=self.nodeConnections[key]
  if links then for _,connection in ipairs(links)do unlink(connection)end;table.clear(links)end
  self.nodeConnections[key]=nil
  local object=self.objects[key]
  if self.interactive then self.interactive[key]=nil end
  if self.objectKeys and object then self.objectKeys[object]=nil end
  if self.dirtyKeys then self.dirtyKeys[key]=nil end
  for _,resource in ipairs(resources[key]or {})do clean(resource);stats.cleaned+=1 end
  resources[key]=nil;watched[key]=nil;mounted[key]=nil
  if reserved[key]then reserveCount-=reserved[key];reserved[key]=nil end
  if self.motion then self.motion:remove(key)end
 end
 local drop
 drop=function(key,recycle)
  local root=self.nodes[key];if not root or removing[key]then return end
  if root==self.document.root then self:destroy();return end
  local parent=self.nodeParents[key];local index=parent and table.find(parent.children,root)
  if index then table.remove(parent.children,index)end
  local removed={};local objects={}
  local function visit(node)
   removing[node.key]=true;removed[node.key]=true
   for _,child in ipairs(node.children)do visit(child)end
   local object=self.objects[node.key];if object then objects[node.key]=object end
   cleanupKey(node.key)
   if node.attrs.id then self.ids[node.attrs.id]=nil end
   self.objects[node.key]=nil;self.nodes[node.key]=nil;self.state[node.key]=nil;self.cache[node.key]=nil;self.nodeParents[node.key]=nil
   if self.boxes then self.boxes[node.key]=nil end
   if self.styles then self.styles[node.key]=nil end
   if self.parents then self.parents[node.key]=nil end
   self.nodeCount-=1;stats.removed+=1
  end
  visit(root)
  for generatedKey,object in pairs(self.objects)do
   local owner=generatedKey:match('^(.-)::')
   if owner and removed[owner]then
    objects[generatedKey]=object;removed[generatedKey]=true;cleanupKey(generatedKey)
    self.objects[generatedKey]=nil;self.cache[generatedKey]=nil;self.state[generatedKey]=nil
    if self.boxes then self.boxes[generatedKey]=nil end
    if self.styles then self.styles[generatedKey]=nil end
    if self.parents then self.parents[generatedKey]=nil end
   end
  end
  if self.sequence then for i=#self.sequence,1,-1 do if removed[self.sequence[i].key]then table.remove(self.sequence,i)end end end
  if recycle then O.dispose(objects)end;table.clear(objects)
  for gone in pairs(removed)do removing[gone]=nil end
  if self.motion then local motion=self.motion:stats();self.motion:_sync(motion.transitions>0 or motion.animations>0)end
  if self.stateBindings then self.stateBindings:sync(self.stateNeeds)end
  invalidate();queue()
 end
 function self:track(id,resource)
  assert(self.alive,'Runtime encerrado.');local key=keyOf(id);assert(self.nodes[key],'ID desconhecido.')
  local kind=typeof(resource)
  assert(kind=='RBXScriptConnection'or kind=='thread'or kind=='function'or kind=='Instance'or(kind=='table'and(resource.Destroy or resource.destroy or resource.Disconnect or resource.Cancel or resource.cancel)),'Recurso sem método de limpeza.')
  resources[key]=resources[key]or {};resources[key][#resources[key]+1]=resource;return resource
 end
 function self:_watchNode(key,object)
  if watched[key]==object then return end
  watched[key]=object;mounted[key]=object:IsDescendantOf(self.gui)
  connect(object.Destroying,function()
   if self.alive and self.objects[key]==object and not removing[key]then drop(key,false)end
  end,key)
  connect(object.AncestryChanged,function()
   if not self.alive or self.objects[key]~=object or removing[key]then return end
   if object:IsDescendantOf(self.gui)then mounted[key]=true elseif mounted[key]then drop(key,false)end
  end,key)
 end
 function self:_syncResources()
  for key,object in pairs(self.objects)do
   if self.nodes[key]and watched[key]~=object then self:_watchNode(key,object)end
   if object:IsDescendantOf(self.gui)then mounted[key]=true;if reserved[key]then reserveCount-=reserved[key];reserved[key]=nil end end
  end
  Cost.cap('instances',nativeCount,'Saida dinamica')
 end
 local function templateFor(source)
  local entry=O.entry(source,{disabled=source.attrs.disabled~=nil and source.attrs.disabled~='false'})
  local properties=copy(entry.properties);properties.Name=nil
  local signature=entry.className..O.signature(properties)..(source.tag=='svg'and source.key or '')
  local record=templates[signature]
  if record then stats.templateHits+=1;return record end
  local prototype
  if source.tag=='svg'then
   prototype=self.objects[source.key]:Clone()
   for _,child in ipairs(prototype:GetChildren())do
    if child:GetAttribute('CssPseudoElement')then O.release(child)end
   end
  else prototype=O.instantiate(entry)end
  O.properties(prototype,{Name='__CssCleanTemplate'});prototype:SetAttribute('CssNodeKey',nil);prototype:SetAttribute('CssClass',nil);prototype:SetAttribute('CssDisabled',nil)
  record={prototype=prototype,cost=#prototype:GetDescendants()+1};templates[signature]=record
  templateCursor=templateCursor%16+1;local previous=templateSlots[templateCursor]
  if previous and previous~=signature then local old=templates[previous];if old then O.release(old.prototype);templates[previous]=nil end end
  templateSlots[templateCursor]=signature;stats.templateMisses+=1;return record
 end
 function self:cloneItem(templateId,newId,parentId)
  assert(self.alive,'Runtime encerrado.')
  assert(type(newId)=='string'and newId:match('^[%a_][%w_%-]*$')and #newId<=60 and not self.ids[newId],'ID novo inválido ou duplicado.')
  Cost.cap('nodes',self.nodeCount+1,'Elementos por interface')
  local source=assert(self.nodes[keyOf(templateId)],'Template desconhecido.')
  assert(#source.children==0 and source~=self.document.root,'cloneItem aceita um elemento sem filhos HTML.')
  local parent=assert(self.nodes[keyOf(parentId)],'Contêiner desconhecido.');local parentObject=self.objects[parent.key]
  assert(parentObject and(parentObject:IsA('Frame')or parentObject:IsA('ScrollingFrame'))and parent.tag~='svg','O destino deve ser um contêiner HTML.')
  local depth,ancestor=1,parent
  while ancestor do depth+=1;assert(depth<=Cost.limits().depth,'Lista excede a profundidade maxima.');ancestor=self.nodeParents[ancestor.key]end
  local record=templateFor(source);local budget=math.max(record.cost,32)
  Cost.cap('instances',nativeCount+reserveCount+budget,'Itens dinamicos')
  local node=copy(source);self.nextDynamic+=1;self.maxOrder+=1
  node.key='d'..self.nextDynamic;node.order=self.maxOrder;node.attrs.id=newId;node.dynamic=true
  local entry=O.entry(node,{disabled=node.attrs.disabled~=nil and node.attrs.disabled~='false'})
  local object=O.cloneTemplate and O.cloneTemplate(record.prototype,entry,record.cost)or record.prototype:Clone()
  O.properties(object,entry.properties);O.attributes(object,entry.attributes)
  table.insert(parent.children,node);self.objects[node.key]=object;collect(node,parent)
  reserved[node.key]=budget;reserveCount+=budget
  local ok,err=pcall(bind,node.key,object)
  if not ok then drop(node.key,true);error(err,0)end
  stats.clones+=1;invalidate();queue()
  return object
 end
 function self:removeItem(id)
  local key=keyOf(id);local node=assert(self.nodes[key],'Item desconhecido.')
  assert(node.dynamic,'removeItem remove itens criados com cloneItem.');drop(key,true)
 end
 function self:resourceStats()
  local result=copy(stats);local count=0;for _ in pairs(templates)do count+=1 end
  result.templates=count;result.instances=nativeCount;result.reserved=reserveCount;return result
 end
 function self:_cleanupResources()
  for key,list in pairs(resources)do for _,resource in ipairs(list)do clean(resource);stats.cleaned+=1 end;resources[key]=nil end
  for _,record in pairs(templates)do O.release(record.prototype)end
  local pending={};for key in pairs(reserved)do local object=self.objects[key];if object and not object.Parent then pending[key]=object end end
  O.dispose(pending)
  table.clear(templates);table.clear(templateSlots);table.clear(watched);table.clear(mounted);table.clear(reserved);table.clear(positions)
  reserveCount=0;self._connectionPositions=nil;self._unlinkConnection=nil;self._watchNode=nil;self._syncResources=nil;self._cleanupResources=nil
 end
 connect(self.gui.DescendantAdded,function()nativeCount+=1 end)
 connect(self.gui.DescendantRemoving,function()nativeCount=math.max(0,nativeCount-1)end)
 local previouslyParented=self.gui.Parent~=nil
 connect(self.gui.AncestryChanged,function()
  if not self.alive then return end
  if self.gui.Parent then previouslyParented=true elseif previouslyParented then self:destroy()end
 end)
end
return X
