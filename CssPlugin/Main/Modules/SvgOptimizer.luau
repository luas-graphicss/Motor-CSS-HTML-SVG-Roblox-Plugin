local O={VERSION=1}
local function same(a,b)return math.abs(a.x-b.x)<=1e-10 and math.abs(a.y-b.y)<=1e-10 end
local function redundant(a,b,c)
 local ax,ay=b.x-a.x,b.y-a.y;local bx,by=c.x-b.x,c.y-b.y
 local cross=ax*by-ay*bx;local dot=ax*bx+ay*by
 return dot>=0 and math.abs(cross)<=1e-10*math.max(1,math.sqrt((ax*ax+ay*ay)*(bx*bx+by*by)))
end
function O.simplifyContours(contours)
 local output={};local before,after=0,0
 for _,source in ipairs(contours)do
  before+=#source;local points={closed=source.closed}
  for _,p in ipairs(source)do
   if #points==0 or not same(points[#points],p)then
    while #points>=2 and redundant(points[#points-1],points[#points],p)do points[#points]=nil end
    points[#points+1]=p
   end
  end
  local explicitSeam=source.closed and #source>1 and same(source[1],source[#source])
  if source.closed then
   if #points>1 and same(points[1],points[#points])then points[#points]=nil end
   while #points>3 and redundant(points[#points],points[1],points[2])do table.remove(points,1)end
   while #points>3 and redundant(points[#points-1],points[#points],points[1])do points[#points]=nil end
  end
  if #points<(source.closed and 3 or math.min(2,#source))then
   points=table.clone(source)
  end
  if explicitSeam and #points>2 and not same(points[1],points[#points])then points[#points+1]=points[1]end
  after+=#points;output[#output+1]=points
 end
 return output,{before=before,after=after,removed=before-after}
end
function O.mergeRuns(runs,keyOf)
 local out={};local previous={}
 for _,source in ipairs(runs)do
  local r=table.clone(source)
  local ink=keyOf and keyOf(source)or table.concat(source.channels or {},',')..':'..tostring(source.layer or 0)
  local key=ink..':'..r.x..':'..r.w
  local up=previous[key]
  if up and up.y+up.h==r.y then up.h+=r.h else out[#out+1]=r;previous[key]=r end
 end
 return out
end
return O
