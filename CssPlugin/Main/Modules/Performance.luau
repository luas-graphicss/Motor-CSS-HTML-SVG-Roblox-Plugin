local RunService=game:GetService('RunService')
local P={VERSION=1}
function P.renderSignal()
 return RunService:IsRunning() and RunService:IsServer() and RunService.Heartbeat or RunService.RenderStepped
end
function P.coalesce(callback,options)
 options=options or {}
 local self={alive=true,pending=false,running=false,connection=nil,requests=0,flushes=0}
 local invoke
 local function arm()
  if self.alive and self.pending and not self.running and not self.connection then
   self.connection=(options.signal or P.renderSignal()):Connect(invoke)
  end
 end
 invoke=function()
  if not self.alive or not self.pending or self.running then return end
  if self.connection then self.connection:Disconnect();self.connection=nil end
  self.pending=false;self.running=true;self.flushes+=1
  local ok,err=pcall(callback)
  self.running=false
  if not self.alive then return end
  if not ok then
   self.lastError=tostring(err)
   if options.onError then
    local handled,handlerError=pcall(options.onError,err)
    if not handled and self.alive then self.lastError=tostring(handlerError)end
   elseif options.development==true then warn('[CssPlugin] '..self.lastError)end
  end
  arm()
 end
 function self:request()
  if not self.alive then return end
  self.requests+=1;self.pending=true
  arm()
 end
 function self:flush()invoke()end
 function self:cancel()
  self.pending=false
  if self.connection then self.connection:Disconnect();self.connection=nil end
 end
 function self:destroy()
  if not self.alive then return end
  self:cancel();self.alive=false;callback=nil;options=nil;self.lastError=nil
 end
 return self
end
function P.budget(options)
 options=options or {}
 local clock=options.clock or os.clock
 local self={units=0,yields=0,last=clock(),total=0}
 local limit=math.max(1,options.chunkSize or 48)
 local seconds=math.max(0.0001,options.frameBudget or 0.010)
 local minimum=seconds*0.25
 function self:check()
  assert(not options.cancelled or not options.cancelled(),'Compilação cancelada; a saída anterior foi preservada.')
 end
 function self:step(units)
  self:check();units=units or 1;self.units+=units;self.total+=units
  local elapsed=clock()-self.last
  if options.yield~=false and (elapsed>=seconds or (self.units>=limit and elapsed>=minimum)) then
   if type(options.yield)=='function' then options.yield() else task.wait() end
   self:check();self.units=0;self.yields+=1;self.last=clock()
  end
 end
 return self
end
function P.same(a,b)
 if a==b then return true end
 if type(a)~='table' or type(b)~='table' then return false end
 for k,v in pairs(a)do if not P.same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
return P
