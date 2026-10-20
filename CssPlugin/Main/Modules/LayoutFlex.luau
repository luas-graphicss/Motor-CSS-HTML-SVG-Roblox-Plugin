local F={}
function F.resolve(items,limit,gap,constrain)
 local hypothetical=gap*math.max(0,#items-1)
 for _,c in ipairs(items)do hypothetical+=c.main+c.before+c.after end
 local growing=hypothetical<limit;local frozen={};local initial=limit-gap*math.max(0,#items-1)
 for i,c in ipairs(items)do
  local factor=growing and c.grow or c.shrink
  frozen[i]=factor==0 or(growing and c.base>c.main)or(not growing and c.base<c.main)
  if not frozen[i]then c.main=c.base end
  initial-=c.main+c.before+c.after
 end
 local direct=true
 for _=1,#items+1 do
  local free=limit-gap*math.max(0,#items-1);local factors,weight,active=0,0,0
  for i,c in ipairs(items)do
   free-=(frozen[i]and c.main or c.base)+c.before+c.after
   if not frozen[i]then factors+=growing and c.grow or c.shrink;weight+=growing and c.grow or c.shrink*c.base;active+=1 end
  end
  if active==0 then break end
  if factors<1 and math.abs(initial*factors)<math.abs(free)then free=initial*factors end
  local totalViolation=0;local violations={}
  for i,c in ipairs(items)do if not frozen[i]then
   local desired=c.base+(weight>0 and free*(growing and c.grow or c.shrink*c.base)/weight or 0)
   local actual=constrain(c,desired);c.main=actual;violations[i]=actual-desired;totalViolation+=violations[i]
  end end
  if math.abs(totalViolation)<0.0001 then break end
  direct=false;local count=0
  for i in ipairs(items)do if not frozen[i]and((totalViolation>0 and violations[i]>0)or(totalViolation<0 and violations[i]<0))then frozen[i]=true;count+=1 end end
  if count==0 then break end
 end
 local free=limit-gap*math.max(0,#items-1);local count=0
 for _,c in ipairs(items)do free-=c.main+c.before+c.after;if c.autoBefore then count+=1 end;if c.autoAfter then count+=1 end end
 if free>0 and count>0 then for _,c in ipairs(items)do if c.autoBefore then c.before=free/count end;if c.autoAfter then c.after=free/count end end end
 return direct
end
return F
