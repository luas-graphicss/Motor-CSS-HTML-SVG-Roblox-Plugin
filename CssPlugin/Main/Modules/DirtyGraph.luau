local G={VERSION=1}
local channels={style=1,layout=2,paint=3}
local cascade={style={'layout','paint'},layout={'paint'},paint={}}
G.channels=channels
function G.new(options)
 options=options or {}
 local self={parents={},children={},tokens={},owned={},dirty={style={},layout={},paint={}},counts={style=0,layout=0,paint=0},fullReason=nil,generation=0,inherit=options.inherit~=false,stats={touches=0,marks=0,invalidations=0,ancestors=0,descendants=0,plans=0,fullPlans=0,tokens=0}}
 local function mark(channel,key)
  local set=self.dirty[channel]
  if set[key] then return false end
  set[key]=true;self.counts[channel]+=1;self.stats.marks+=1;return true
 end
 function self:link(key,parentKey)
  local previous=self.parents[key]
  if previous and self.children[previous] then self.children[previous][key]=nil end
  self.parents[key]=parentKey
  if parentKey then
   local list=self.children[parentKey]
   if not list then list={};self.children[parentKey]=list end
   list[key]=true
  end
 end
 function self:structure(sequence,parents)
  for _,node in ipairs(sequence or {}) do
   local parent=parents and parents[node.key]
   self:link(node.key,parent and parent.key or nil)
  end
  return self
 end
 function self:depend(key,channel,token)
  assert(channels[channel],'Canal invalido: '..tostring(channel))
  assert(token~=nil,'Dependencia exige token.')
  local bucket=self.tokens[token]
  if not bucket then bucket={style={},layout={},paint={}};self.tokens[token]=bucket;self.stats.tokens+=1 end
  if not bucket[channel][key] then
   bucket[channel][key]=true
   local list=self.owned[key]
   if not list then list={};self.owned[key]=list end
   list[#list+1]={token=token,channel=channel}
  end
  return self
 end
 function self:dependsOn(key,channel,token)
  local bucket=self.tokens[token]
  return bucket~=nil and bucket[channel][key]==true
 end
 function self:touch(key,channel)
  channel=channel or 'style'
  assert(channels[channel],'Canal invalido: '..tostring(channel))
  self.stats.touches+=1
  if not mark(channel,key) then return false end
  for _,downstream in ipairs(cascade[channel]) do mark(downstream,key) end
  local parent=self.parents[key]
  while parent do
   if not mark('layout',parent) then break end
   mark('paint',parent);self.stats.ancestors+=1;parent=self.parents[parent]
  end
  if channel=='style' and self.inherit then
   local stack={key}
   while #stack>0 do
    local current=table.remove(stack)
    for child in pairs(self.children[current] or {}) do
     if mark('style',child) then
      mark('layout',child);mark('paint',child);self.stats.descendants+=1;stack[#stack+1]=child
     end
    end
   end
  end
  return true
 end
 function self:touchAll(keys,channel)
  local count=0
  for _,key in ipairs(keys or {}) do if self:touch(key,channel) then count+=1 end end
  return count
 end
 function self:invalidate(token)
  local bucket=self.tokens[token]
  if not bucket then return 0 end
  self.stats.invalidations+=1
  local total=0
  for channel in pairs(channels) do
   for key in pairs(bucket[channel]) do if self:touch(key,channel) then total+=1 end end
  end
  return total
 end
 function self:forget(key)
  for _,entry in ipairs(self.owned[key] or {}) do
   local bucket=self.tokens[entry.token]
   if bucket then bucket[entry.channel][key]=nil end
  end
  self.owned[key]=nil
  for channel,set in pairs(self.dirty) do
   if set[key] then set[key]=nil;self.counts[channel]-=1 end
  end
  local parent=self.parents[key]
  if parent and self.children[parent] then self.children[parent][key]=nil end
  self.parents[key]=nil;self.children[key]=nil
 end
 function self:full(reason) self.fullReason=reason or 'completo';return self end
 function self:pending()
  if self.fullReason then return true end
  return self.counts.style+self.counts.layout+self.counts.paint>0
 end
 function self:snapshot()
  return {style=self.dirty.style,layout=self.dirty.layout,paint=self.dirty.paint,counts=table.clone(self.counts),full=self.fullReason,generation=self.generation}
 end
 function self:consume()
  self.generation+=1;self.stats.plans+=1
  if self.fullReason then self.stats.fullPlans+=1 end
  local out={style=self.dirty.style,layout=self.dirty.layout,paint=self.dirty.paint,counts=table.clone(self.counts),full=self.fullReason,generation=self.generation}
  self.dirty={style={},layout={},paint={}};self.counts={style=0,layout=0,paint=0};self.fullReason=nil
  return out
 end
 function self:apply(work)
  work=work or {}
  local plan=self:consume()
  work.dirtyKeys=plan
  if plan.full then work.full=true end
  return work,plan
 end
 function self:reset(reason)
  self.dirty={style={},layout={},paint={}};self.counts={style=0,layout=0,paint=0};self.fullReason=reason or 'reset';return self
 end
 return self
end
function G.count(set)
 local total=0
 for _ in pairs(set or {}) do total+=1 end
 return total
end
function G.empty(plan)
 if not plan then return true end
 if plan.full then return false end
 for channel in pairs(channels) do if next(plan[channel] or {}) then return false end end
 return true
end
function G.merge(target,source)
 target=target or {style={},layout={},paint={},counts={style=0,layout=0,paint=0}}
 if not source then return target end
 for channel in pairs(channels) do
  for key in pairs(source[channel] or {}) do target[channel][key]=true end
 end
 if source.full then target.full=source.full end
 for channel in pairs(channels) do target.counts[channel]=G.count(target[channel]) end
 return target
end
function G.describe(plan)
 if not plan then return 'sem plano' end
 if plan.full then return 'completo ('..tostring(plan.full)..')' end
 return string.format('style %d | layout %d | paint %d',G.count(plan.style),G.count(plan.layout),G.count(plan.paint))
end
return G
