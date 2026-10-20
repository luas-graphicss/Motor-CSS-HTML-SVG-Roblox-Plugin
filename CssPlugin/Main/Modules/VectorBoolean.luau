local Cache=require(script.Parent.VectorCache)
local B={VERSION='vector-boolean-1',ALGORITHM='segment-classify-1',EPSILON=1e-6}
local abs=math.abs
local min=math.min
local max=math.max
local sqrt=math.sqrt
local floor=math.floor
local function coord(entry)
 local x=entry.x
 if x~=nil then return x,entry.y end
 return entry[1],entry[2]
end
local function snap(value,epsilon)
 return floor(value/epsilon+0.5)*epsilon
end
local function keyOf(x,y,epsilon)
 return floor(x/epsilon+0.5)..':'..floor(y/epsilon+0.5)
end
local function normalize(input)
 if not input then return {} end
 if input.x~=nil or (input[1] and type(input[1])=='number') then return {input} end
 return input
end
B.normalize=normalize
local function collect(contours,owner,epsilon,out)
 for _,contour in ipairs(contours) do
  local count=#contour
  if count>=3 then
   for index=1,count do
    local ax,ay=coord(contour[index])
    local bx,by=coord(contour[index%count+1])
    if ax and bx and (abs(ax-bx)>epsilon or abs(ay-by)>epsilon) then
     out[#out+1]={ax=ax,ay=ay,bx=bx,by=by,owner=owner,cuts={}}
    end
   end
  end
 end
 return out
end
local function windingAt(contours,x,y)
 local total=0
 for _,contour in ipairs(contours) do
  local count=#contour
  for index=1,count do
   local ax,ay=coord(contour[index])
   local bx,by=coord(contour[index%count+1])
   if ax and bx then
    if ay<=y then
     if by>y and (bx-ax)*(y-ay)-(x-ax)*(by-ay)>0 then total+=1 end
    elseif by<=y and (bx-ax)*(y-ay)-(x-ax)*(by-ay)<0 then total-=1 end
   end
  end
 end
 return total
end
B.winding=windingAt
function B.contains(contours,x,y,rule)
 local total=windingAt(normalize(contours),x,y)
 if rule=='evenodd' then return total%2~=0 end
 return total~=0
end
local function onSegment(sx,sy,ex,ey,px,py,tolerance)
 local dx,dy=ex-sx,ey-sy
 local length=dx*dx+dy*dy
 if length<=1e-24 then return false end
 local t=((px-sx)*dx+(py-sy)*dy)/length
 if t<-1e-6 or t>1+1e-6 then return false end
 local qx=sx+dx*t
 local qy=sy+dy*t
 local ox,oy=px-qx,py-qy
 return ox*ox+oy*oy<=tolerance*tolerance
end
function B.area(contours)
 local total=0
 for _,contour in ipairs(normalize(contours)) do
  local count=#contour
  for index=1,count do
   local ax,ay=coord(contour[index])
   local bx,by=coord(contour[index%count+1])
   if ax and bx then total+=ax*by-bx*ay end
  end
 end
 return total*0.5
end
function B.bounds(contours)
 local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
 for _,contour in ipairs(normalize(contours)) do
  for _,entry in ipairs(contour) do
   local x,y=coord(entry)
   if x then
    if x<minX then minX=x end
    if y<minY then minY=y end
    if x>maxX then maxX=x end
    if y>maxY then maxY=y end
   end
  end
 end
 if minX>maxX then return nil end
 return {x=minX,y=minY,w=maxX-minX,h=maxY-minY,right=maxX,bottom=maxY}
end
function B.operate(subject,clip,operation,options)
 options=options or {}
 local a=normalize(subject)
 local b=normalize(clip)
 local epsilon=max(tonumber(options.epsilon) or B.EPSILON,1e-9)
 local ruleA=options.rule or 'nonzero'
 local ruleB=options.clipRule or ruleA
 local limit=floor(tonumber(options.maxSegments) or 20000)
 if #a==0 then
  if operation=='union' or operation=='xor' then return b end
  return {}
 end
 if #b==0 then
  if operation=='intersect' then return {} end
  return a
 end
 local segments={}
 collect(a,1,epsilon,segments)
 collect(b,2,epsilon,segments)
 assert(#segments<=limit,'Operacao booleana excede o orcamento de segmentos.')
 for i=1,#segments do
  local s=segments[i]
  local sLowX=min(s.ax,s.bx)
  local sHighX=max(s.ax,s.bx)
  local sLowY=min(s.ay,s.by)
  local sHighY=max(s.ay,s.by)
  for j=i+1,#segments do
   local t=segments[j]
   if s.owner~=t.owner then
    local tLowX=min(t.ax,t.bx)
    local tHighX=max(t.ax,t.bx)
    local tLowY=min(t.ay,t.by)
    local tHighY=max(t.ay,t.by)
    if tLowX<=sHighX+epsilon and tHighX>=sLowX-epsilon and tLowY<=sHighY+epsilon and tHighY>=sLowY-epsilon then
     local r1x,r1y=s.bx-s.ax,s.by-s.ay
     local r2x,r2y=t.bx-t.ax,t.by-t.ay
     local denominator=r1x*r2y-r1y*r2x
     local dx,dy=t.ax-s.ax,t.ay-s.ay
     if abs(denominator)>1e-14 then
      local u=(dx*r2y-dy*r2x)/denominator
      local v=(dx*r1y-dy*r1x)/denominator
      if u>-1e-9 and u<1+1e-9 and v>-1e-9 and v<1+1e-9 then
       if u>1e-9 and u<1-1e-9 then s.cuts[#s.cuts+1]=u end
       if v>1e-9 and v<1-1e-9 then t.cuts[#t.cuts+1]=v end
      end
     else
      local length1=r1x*r1x+r1y*r1y
      local length2=r2x*r2x+r2y*r2y
      if length1>1e-24 and abs(dx*r1y-dy*r1x)/sqrt(length1)<=epsilon*8 then
       local pa=((t.ax-s.ax)*r1x+(t.ay-s.ay)*r1y)/length1
       local pb=((t.bx-s.ax)*r1x+(t.by-s.ay)*r1y)/length1
       if pa>1e-9 and pa<1-1e-9 then s.cuts[#s.cuts+1]=pa end
       if pb>1e-9 and pb<1-1e-9 then s.cuts[#s.cuts+1]=pb end
       local qa=((s.ax-t.ax)*r2x+(s.ay-t.ay)*r2y)/length2
       local qb=((s.bx-t.ax)*r2x+(s.by-t.ay)*r2y)/length2
       if qa>1e-9 and qa<1-1e-9 then t.cuts[#t.cuts+1]=qa end
       if qb>1e-9 and qb<1-1e-9 then t.cuts[#t.cuts+1]=qb end
      end
     end
    end
   end
  end
 end
 local pieces={}
 for _,s in ipairs(segments) do
  table.sort(s.cuts)
  local ranges={}
  local previous=0
  for _,cut in ipairs(s.cuts) do
   if cut>previous+1e-9 then
    ranges[#ranges+1]={previous,cut}
    previous=cut
   end
  end
  if previous<1-1e-9 then ranges[#ranges+1]={previous,1} end
  for _,range in ipairs(ranges) do
   local t0,t1=range[1],range[2]
   local ax=snap(s.ax+(s.bx-s.ax)*t0,epsilon)
   local ay=snap(s.ay+(s.by-s.ay)*t0,epsilon)
   local bx=snap(s.ax+(s.bx-s.ax)*t1,epsilon)
   local by=snap(s.ay+(s.by-s.ay)*t1,epsilon)
   if abs(ax-bx)>epsilon*0.5 or abs(ay-by)>epsilon*0.5 then
    pieces[#pieces+1]={ax=ax,ay=ay,bx=bx,by=by,owner=s.owner}
   end
  end
 end
 local kept={}
 for _,piece in ipairs(pieces) do
  local mx=(piece.ax+piece.bx)*0.5
  local my=(piece.ay+piece.by)*0.5
  local other=piece.owner==1 and b or a
  local otherRule=piece.owner==1 and ruleB or ruleA
  local inside=windingAt(other,mx,my)
  inside=otherRule=='evenodd' and inside%2~=0 or otherRule~='evenodd' and inside~=0
  local coincident=false
  local agree=false
  for _,contour in ipairs(other) do
   local count=#contour
   for index=1,count do
    local sx,sy=coord(contour[index])
    local ex,ey=coord(contour[index%count+1])
    if sx and ex and onSegment(sx,sy,ex,ey,mx,my,epsilon*8) then
     coincident=true
     agree=(piece.bx-piece.ax)*(ex-sx)+(piece.by-piece.ay)*(ey-sy)>0
     break
    end
   end
   if coincident then break end
  end
  local take=false
  local flip=false
  if operation=='intersect' then
   if piece.owner==1 then take=(coincident and agree) or (not coincident and inside)
   else take=not coincident and inside end
  elseif operation=='union' then
   if piece.owner==1 then take=(coincident and agree) or (not coincident and not inside)
   else take=not coincident and not inside end
  elseif operation=='difference' then
   if piece.owner==1 then take=(coincident and not agree) or (not coincident and not inside)
   else
    take=not coincident and inside
    flip=true
   end
  elseif operation=='xor' then
   take=true
   flip=inside
  else
   error('Operacao booleana desconhecida: '..tostring(operation),0)
  end
  if take then
   if flip then kept[#kept+1]={ax=piece.bx,ay=piece.by,bx=piece.ax,by=piece.ay}
   else kept[#kept+1]={ax=piece.ax,ay=piece.ay,bx=piece.bx,by=piece.by} end
  end
 end
 local buckets={}
 for index,piece in ipairs(kept) do
  local key=keyOf(piece.ax,piece.ay,epsilon)
  local list=buckets[key]
  if not list then
   list={}
   buckets[key]=list
  end
  list[#list+1]=index
 end
 local used={}
 local out={}
 for index=1,#kept do
  if not used[index] then
   local contour={}
   local cursor=index
   local guard=0
   while cursor and not used[cursor] and guard<=#kept+8 do
    guard+=1
    used[cursor]=true
    local piece=kept[cursor]
    contour[#contour+1]={x=piece.ax,y=piece.ay}
    local list=buckets[keyOf(piece.bx,piece.by,epsilon)]
    local nextIndex=nil
    if list then
     for _,candidate in ipairs(list) do
      if not used[candidate] then
       nextIndex=candidate
       break
      end
     end
    end
    cursor=nextIndex
   end
   if #contour>=3 then
    contour.closed=true
    out[#out+1]=contour
   end
  end
 end
 return out
end
function B.intersect(subject,clip,options) return B.operate(subject,clip,'intersect',options) end
function B.union(subject,clip,options) return B.operate(subject,clip,'union',options) end
function B.difference(subject,clip,options) return B.operate(subject,clip,'difference',options) end
function B.xor(subject,clip,options) return B.operate(subject,clip,'xor',options) end
function B.clip(subject,clips,options)
 local current=normalize(subject)
 for _,region in ipairs(clips or {}) do
  if #current==0 then break end
  current=B.operate(current,region,'intersect',options)
 end
 return current
end
function B.mask(subject,masks,options)
 local merged={}
 for _,region in ipairs(masks or {}) do
  local normalized=normalize(region)
  if #merged==0 then merged=normalized else merged=B.operate(merged,normalized,'union',options) end
 end
 if #merged==0 then return {} end
 return B.operate(normalize(subject),merged,'intersect',options)
end
function B.stage()
 return Cache.stage('boolean',B.ALGORITHM,{maxEntries=64,maxBytes=4194304})
end
function B.cached(operation,signature,subject,clip,options)
 local stage=B.stage()
 local key=Cache.key({operation,signature,options and options.rule or 'nonzero',options and options.clipRule or 'nonzero',options and options.epsilon or B.EPSILON})
 local cached=Cache.get(stage,key)
 if cached then return cached,true end
 local value=B.operate(subject,clip,operation,options)
 local bytes=64
 for _,contour in ipairs(value) do bytes+=#contour*32 end
 Cache.put(stage,key,value,bytes)
 return value,false
end
return B
