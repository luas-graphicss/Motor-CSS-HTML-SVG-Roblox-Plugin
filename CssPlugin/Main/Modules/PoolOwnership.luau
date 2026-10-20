local Pool=require(script.Parent.InstancePool)
local O={VERSION=1}
local owners=setmetatable({},{__mode='k'})
local tracked={}
local metrics={claims=0,transfers=0,releases=0,recycled=0,discarded=0,rejected=0,orphans=0,adopted=0}
local function bag(owner)
 local set=tracked[owner]
 if not set then set=setmetatable({},{__mode='k'});tracked[owner]=set end
 return set
end
local function forget(object)
 local owner=owners[object]
 owners[object]=nil
 if owner~=nil then
  local set=tracked[owner]
  if set then set[object]=nil end
 end
end
function O.owner(object) return owners[object] end
function O.claim(object,owner)
 assert(typeof(object)=='Instance','Ownership exige uma Instance.')
 assert(owner~=nil,'Ownership exige um dono.')
 local current=owners[object]
 if current~=nil and current~=owner then
  metrics.rejected+=1
  error('Instancia ja pertence a outro dono do pool.',0)
 end
 if current==nil then
  owners[object]=owner;bag(owner)[object]=true;metrics.claims+=1
  pcall(function() object:SetAttribute('CssOwned',true) end)
 end
 return object
end
function O.adopt(root,owner)
 O.claim(root,owner)
 for _,descendant in ipairs(root:GetDescendants()) do
  if owners[descendant]==nil then metrics.adopted+=1 end
  O.claim(descendant,owner)
 end
 return root
end
function O.acquire(owner,className) return O.claim(Pool.acquire(className),owner) end
function O.tryAcquire(owner,className)
 local object=Pool.tryAcquire(className)
 if not object then return nil end
 return O.claim(object,owner)
end
function O.cloneTree(owner,template) return O.adopt(Pool.cloneTree(template),owner) end
function O.transfer(object,from,to)
 assert(owners[object]==from,'Transferencia recusada: dono atual diferente.')
 forget(object)
 metrics.transfers+=1
 return O.claim(object,to)
end
function O.transferTree(root,from,to)
 O.transfer(root,from,to)
 for _,descendant in ipairs(root:GetDescendants()) do
  if owners[descendant]~=nil then O.transfer(descendant,from,to) end
 end
 return root
end
function O.release(owner,object,strict)
 if not object then return false end
 assert(typeof(object)=='Instance','Descarte exige uma Instance.')
 local current=owners[object]
 if current==nil then
  metrics.orphans+=1
  if strict then error('Descarte recusado: instancia sem dono registrado.',0) end
 elseif current~=owner then
  metrics.rejected+=1
  error('Descarte recusado: instancia pertence a outro dono.',0)
 end
 local descendants=object:GetDescendants()
 for _,descendant in ipairs(descendants) do
  local holder=owners[descendant]
  if holder~=nil and holder~=owner then
   metrics.rejected+=1
   error('Descarte recusado: subarvore com dono diferente.',0)
  end
 end
 for _,descendant in ipairs(descendants) do forget(descendant) end
 forget(object)
 local recycled=Pool.releaseTree(object)
 metrics.releases+=1
 if recycled then metrics.recycled+=1 else metrics.discarded+=1 end
 return recycled
end
function O.releaseAll(owner)
 local set=tracked[owner]
 if not set then return 0 end
 local roots={}
 for object in pairs(set) do
  local parent=object.Parent
  local nested=false
  while parent do
   if set[parent] then nested=true;break end
   parent=parent.Parent
  end
  if not nested then roots[#roots+1]=object end
 end
 local count=0
 for _,root in ipairs(roots) do
  if owners[root]==owner and pcall(O.release,owner,root) then count+=1 end
 end
 for object in pairs(set) do forget(object) end
 tracked[owner]=nil
 return count
end
function O.count(owner)
 local set=tracked[owner]
 if not set then return 0 end
 local total=0
 for _ in pairs(set) do total+=1 end
 return total
end
function O.stats(owner)
 local out=table.clone(metrics)
 out.pool=Pool.stats()
 local holders=0
 for _ in pairs(tracked) do holders+=1 end
 out.holders=holders
 if owner~=nil then out.owned=O.count(owner) end
 return out
end
function O.adapter(owner)
 assert(owner~=nil,'Adapter exige um dono.')
 return {
  owner=owner,
  claim=function(object) return O.claim(object,owner) end,
  adopt=function(root) return O.adopt(root,owner) end,
  transferTo=function(object,to) return O.transferTree(object,owner,to) end,
  leaks=O.leaks,
  acquire=function(className) return O.acquire(owner,className) end,
  tryAcquire=function(className) return O.tryAcquire(owner,className) end,
  cloneTree=function(template) return O.cloneTree(owner,template) end,
  release=function(object) return O.release(owner,object) end,
  releaseTree=function(object) return O.release(owner,object) end,
  registerCleanup=function(className,cleanup) return Pool.registerCleanup(className,cleanup) end,
  trim=function(value) return Pool.trim(value) end,
  stats=function() return O.stats(owner) end,
  clear=function() return O.releaseAll(owner) end,
 }
end
function O.leaks()
 local list={}
 for object,owner in pairs(owners) do
  if object.Parent==nil then list[#list+1]={owner=owner,name=object.Name,className=object.ClassName} end
 end
 return list
end
function O.reset()
 for owner in pairs(tracked) do tracked[owner]=nil end
 for object in pairs(owners) do owners[object]=nil end
 for key in pairs(metrics) do metrics[key]=0 end
end
return O
