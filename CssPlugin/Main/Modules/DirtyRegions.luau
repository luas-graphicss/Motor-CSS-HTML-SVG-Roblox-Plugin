local R={VERSION=1}
local function normalize(x,y,w,h)
 return {x=tonumber(x) or 0,y=tonumber(y) or 0,w=math.max(0,tonumber(w) or 0),h=math.max(0,tonumber(h) or 0)}
end
local function area(rect) return rect.w*rect.h end
local function union(a,b)
 local x=math.min(a.x,b.x);local y=math.min(a.y,b.y)
 local right=math.max(a.x+a.w,b.x+b.w);local bottom=math.max(a.y+a.h,b.y+b.h)
 return {x=x,y=y,w=right-x,h=bottom-y}
end
local function overlaps(a,b,slack)
 slack=slack or 0
 return a.x<b.x+b.w+slack and b.x<a.x+a.w+slack and a.y<b.y+b.h+slack and b.y<a.y+a.h+slack
end
R.union=union
R.overlaps=overlaps
R.area=area
R.rect=normalize
function R.new(options)
 options=options or {}
 local limit=math.max(1,math.floor(options.limit or 24))
 local slack=math.max(0,tonumber(options.slack) or 2)
 local growth=math.max(1,tonumber(options.growth) or 1.35)
 local threshold=math.clamp(tonumber(options.threshold) or 0.75,0.05,1)
 local viewport=options.viewport
 local self={rects={},full=false,reason=nil,stats={added=0,merged=0,skipped=0,flushes=0,full=0,queries=0}}
 local function total()
  if not viewport then return nil end
  return math.max(1,(viewport.w or 0)*(viewport.h or 0))
 end
 local function collapse()
  while #self.rects>limit do
   local bestA,bestB,bestCost
   for i=1,#self.rects-1 do
    for j=i+1,#self.rects do
     local merged=union(self.rects[i],self.rects[j])
     local cost=area(merged)-area(self.rects[i])-area(self.rects[j])
     if not bestCost or cost<bestCost then bestCost=cost;bestA=i;bestB=j end
    end
   end
   if not bestA then break end
   self.rects[bestA]=union(self.rects[bestA],self.rects[bestB])
   table.remove(self.rects,bestB);self.stats.merged+=1
  end
 end
 function self:viewport(width,height)
  viewport={w=width,h=height};return self
 end
 function self:markFull(reason)
  if not self.full then self.full=true;self.reason=reason or 'viewport';self.stats.full+=1 end
  table.clear(self.rects)
  return self
 end
 function self:audit()
  local limitArea=total()
  if not limitArea then return end
  local covered=0
  for _,rect in ipairs(self.rects) do covered+=area(rect) end
  if covered>=limitArea*threshold then self:markFull('cobertura') end
 end
 function self:add(x,y,w,h)
  if self.full then return false end
  local rect=normalize(x,y,w,h)
  if rect.w<=0 or rect.h<=0 then self.stats.skipped+=1;return false end
  for index,existing in ipairs(self.rects) do
   if overlaps(existing,rect,slack) then
    local merged=union(existing,rect)
    if area(merged)<=(area(existing)+area(rect))*growth then
     self.rects[index]=merged;self.stats.merged+=1;self:audit();return true
    end
   end
  end
  self.rects[#self.rects+1]=rect;self.stats.added+=1
  collapse();self:audit()
  return true
 end
 function self:addBox(box)
  if not box then return false end
  return self:add(box.x,box.y,box.w,box.h)
 end
 function self:addBoxes(boxes,keys)
  local count=0
  for key in pairs(keys or {}) do
   if self:addBox(boxes and boxes[key]) then count+=1 end
  end
  return count
 end
 function self:intersects(x,y,w,h)
  self.stats.queries+=1
  if self.full then return true end
  local rect=normalize(x,y,w,h)
  for _,existing in ipairs(self.rects) do if overlaps(existing,rect,0) then return true end end
  return false
 end
 function self:touches(box)
  if not box then return self.full end
  return self:intersects(box.x,box.y,box.w,box.h)
 end
 function self:bounds()
  if self.full then return viewport and {x=0,y=0,w=viewport.w,h=viewport.h} or nil end
  if #self.rects==0 then return nil end
  local out=self.rects[1]
  for index=2,#self.rects do out=union(out,self.rects[index]) end
  return out
 end
 function self:coverage()
  local covered=0
  for _,rect in ipairs(self.rects) do covered+=area(rect) end
  local limitArea=total()
  if self.full and limitArea then return limitArea,1 end
  return covered,limitArea and covered/limitArea or nil
 end
 function self:list() return table.clone(self.rects) end
 function self:count() return self.full and -1 or #self.rects end
 function self:isEmpty() return not self.full and #self.rects==0 end
 function self:flush()
  local covered,ratio=self:coverage()
  local out={full=self.full,reason=self.reason,rects=table.clone(self.rects),bounds=self:bounds(),covered=covered,ratio=ratio}
  self.stats.flushes+=1
  table.clear(self.rects);self.full=false;self.reason=nil
  return out
 end
 function self:reset()
  table.clear(self.rects);self.full=false;self.reason=nil;return self
 end
 function self:describe()
  if self.full then return 'regiao completa ('..tostring(self.reason)..')' end
  if #self.rects==0 then return 'sem regioes sujas' end
  local parts={}
  for _,rect in ipairs(self.rects) do parts[#parts+1]=string.format('%.0f,%.0f %.0fx%.0f',rect.x,rect.y,rect.w,rect.h) end
  return table.concat(parts,' | ')
 end
 return self
end
function R.fromKeys(boxes,keys,options)
 local regions=R.new(options)
 regions:addBoxes(boxes,keys)
 return regions
end
return R
