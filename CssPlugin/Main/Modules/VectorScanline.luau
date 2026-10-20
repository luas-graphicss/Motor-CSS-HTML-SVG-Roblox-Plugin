local S={VERSION='vector-scanline-1',ALGORITHM='scanline-aet-analytic-1',EPSILON=1/2048}
local floor=math.floor
local ceil=math.ceil
local min=math.min
local max=math.max
local abs=math.abs
local readf32=buffer.readf32
local writef32=buffer.writef32
local function pointOf(entry)
 if type(entry)~='table' then return nil end
 local x=entry.x
 if x~=nil then return x,entry.y end
 return entry[1],entry[2]
end
function S.edges(contours,matrix,options)
 options=options or {}
 local limit=math.floor(tonumber(options.maxEdges) or 1048576)
 local edges={}
 local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
 for _,contour in ipairs(contours) do
  local count=#contour
  if count>=2 then
   local px,py
   for index=1,count+1 do
    local entry=contour[index<=count and index or 1]
    local ax,ay=pointOf(entry)
    if ax~=nil and ay~=nil then
     if matrix then
      local tx=matrix[1]*ax+matrix[3]*ay+matrix[5]
      local ty=matrix[2]*ax+matrix[4]*ay+matrix[6]
      ax,ay=tx,ty
     end
     assert(ax==ax and ay==ay and abs(ax)<1e12 and abs(ay)<1e12,'Coordenada vetorial fora do limite.')
     if px~=nil and py~=ay then
      local x0,y0,x1,y1=px,py,ax,ay
      local dir=1
      if y0>y1 then
       dir=-1
       x0,y0,x1,y1=x1,y1,x0,y0
      end
      edges[#edges+1]={x=x0,y=y0,bottom=y1,slope=(x1-x0)/(y1-y0),dir=dir}
      assert(#edges<=limit,'Geometria vetorial excede o orcamento de arestas.')
     end
     if ax<minX then minX=ax end
     if ay<minY then minY=ay end
     if ax>maxX then maxX=ax end
     if ay>maxY then maxY=ay end
     px,py=ax,ay
    end
   end
  end
 end
 if minX>maxX then return edges,nil end
 return edges,{x=minX,y=minY,w=maxX-minX,h=maxY-minY,right=maxX,bottom=maxY}
end
function S.region(bounds,options)
 options=options or {}
 if not bounds then return {x=0,y=0,w=0,h=0} end
 local x0=floor(bounds.x)-1
 local y0=floor(bounds.y)-1
 local x1=ceil(bounds.right or (bounds.x+bounds.w))+1
 local y1=ceil(bounds.bottom or (bounds.y+bounds.h))+1
 local clip=options.clip
 if clip then
  x0=max(x0,floor(clip.x))
  y0=max(y0,floor(clip.y))
  x1=min(x1,ceil(clip.x+clip.w))
  y1=min(y1,ceil(clip.y+clip.h))
 end
 if options.width then
  x0=max(x0,0)
  x1=min(x1,floor(options.width))
 end
 if options.height then
  y0=max(y0,0)
  y1=min(y1,floor(options.height))
 end
 return {x=x0,y=y0,w=max(0,x1-x0),h=max(0,y1-y0)}
end
function S.sweep(edges,options,emit)
 options=options or {}
 assert(type(emit)=='function','sweep exige um receptor de cobertura.')
 local rule=options.rule or 'nonzero'
 assert(rule=='nonzero' or rule=='evenodd','fill-rule deve ser nonzero ou evenodd.')
 local originX=floor(tonumber(options.x) or 0)
 local originY=floor(tonumber(options.y) or 0)
 local width=floor(tonumber(options.w) or 0)
 local height=floor(tonumber(options.h) or 0)
 if width<=0 or height<=0 or #edges==0 then return {painted=0,rows=0,active=0,edges=#edges} end
 local evenodd=rule=='evenodd'
 local epsilon=tonumber(options.epsilon) or S.EPSILON
 local levels=tonumber(options.levels)
 local yield=options.yield
 local bytes=(width+2)*4
 local area=buffer.create(bytes)
 local cover=buffer.create(bytes)
 local buckets={}
 for _,edge in ipairs(edges) do
  if edge.bottom>originY and edge.y<originY+height then
   local row=floor(edge.y)-originY
   if row<0 then row=0 end
   if row<height then
    local list=buckets[row]
    if not list then
     list={}
     buckets[row]=list
    end
    list[#list+1]=edge
   end
  end
 end
 local active={}
 local painted=0
 local rows=0
 local peak=0
 for row=0,height-1 do
  local y=originY+row
  local incoming=buckets[row]
  if incoming then
   for _,edge in ipairs(incoming) do active[#active+1]=edge end
  end
  local total=#active
  if total>0 then
   if total>peak then peak=total end
   local alive=0
   local low,high=width,-1
   for index=1,total do
    local edge=active[index]
    if edge.bottom>y then
     alive+=1
     active[alive]=edge
     local top=max(edge.y,y)
     local bottom=min(edge.bottom,y+1)
     if bottom>top then
      local delta=(bottom-top)*edge.dir
      local left=edge.x+(top-edge.y)*edge.slope-originX
      local right=edge.x+(bottom-edge.y)*edge.slope-originX
      if left>right then left,right=right,left end
      if left<0 then left=0 end
      if right<0 then right=0 end
      if left>width then left=width end
      if right>width then right=width end
      local first=floor(left)
      local last=floor(right)
      if first>=width then first=width-1 end
      if last>=width then last=width-1 end
      if first<0 then first=0 end
      if last<first then last=first end
      if first==last then
       local at=first*4
       local mid=(left+right)*0.5-first
       writef32(area,at,readf32(area,at)+delta*(1-mid))
       writef32(cover,at,readf32(cover,at)+delta)
      else
       local inverse=1/(right-left)
       for cell=first,last do
        local a=max(left,cell)
        local b=min(right,cell+1)
        if b>a then
         local part=delta*(b-a)*inverse
         local at=cell*4
         local mid=(a+b)*0.5-cell
         writef32(area,at,readf32(area,at)+part*(1-mid))
         writef32(cover,at,readf32(cover,at)+part)
        end
       end
      end
      if first<low then low=first end
      if last>high then high=last end
     end
    end
   end
   for index=total,alive+1,-1 do active[index]=nil end
   if high>=low then
    rows+=1
    local running=0
    for x=low,width-1 do
     local at=x*4
     local cellArea=readf32(area,at)
     local cellCover=readf32(cover,at)
     if cellArea~=0 then writef32(area,at,0) end
     if cellCover~=0 then writef32(cover,at,0) end
     local value=running+cellArea
     running+=cellCover
     local coverage
     if evenodd then
      local folded=abs(value)%2
      coverage=folded<=1 and folded or 2-folded
     else
      coverage=abs(value)
      if coverage>1 then coverage=1 end
     end
     if levels then coverage=floor(coverage*levels+0.5)/levels end
     if coverage>epsilon then
      emit(originX+x,y,coverage)
      painted+=1
     end
     if x>=high and abs(running)<epsilon then break end
    end
   end
  end
  if yield and row%16==0 then yield() end
 end
 return {painted=painted,rows=rows,active=peak,edges=#edges}
end
function S.fill(contours,options,emit)
 options=options or {}
 local edges,bounds=S.edges(contours,options.matrix,options)
 if not bounds then return {painted=0,rows=0,active=0,edges=0} end
 local region=options.region or S.region(bounds,options)
 local sweep={x=region.x,y=region.y,w=region.w,h=region.h,rule=options.rule,levels=options.levels,epsilon=options.epsilon,yield=options.yield}
 local stats=S.sweep(edges,sweep,emit)
 stats.region=region
 stats.bounds=bounds
 return stats
end
function S.alphaBuffer(contours,options)
 options=options or {}
 local width=floor(assert(tonumber(options.w) or tonumber(options.width),'alphaBuffer exige largura.'))
 local height=floor(assert(tonumber(options.h) or tonumber(options.height),'alphaBuffer exige altura.'))
 assert(width>0 and height>0,'alphaBuffer exige dimensoes positivas.')
 local data=buffer.create(width*height*4)
 local stats=S.fill(contours,{matrix=options.matrix,rule=options.rule,levels=options.levels,epsilon=options.epsilon,yield=options.yield,width=width,height=height,region={x=0,y=0,w=width,h=height},maxEdges=options.maxEdges},function(x,y,coverage)
  if x>=0 and y>=0 and x<width and y<height then
   local at=(y*width+x)*4
   local current=readf32(data,at)
   if coverage>current then writef32(data,at,coverage) end
  end
 end)
 return data,width,height,stats
end
function S.alphaTable(contours,options)
 options=options or {}
 local width=floor(assert(tonumber(options.w) or tonumber(options.width),'alphaTable exige largura.'))
 local height=floor(assert(tonumber(options.h) or tonumber(options.height),'alphaTable exige altura.'))
 local alpha=table.create(width*height,0)
 local stats=S.fill(contours,{matrix=options.matrix,rule=options.rule,levels=options.levels,epsilon=options.epsilon,yield=options.yield,width=width,height=height,region={x=0,y=0,w=width,h=height},maxEdges=options.maxEdges},function(x,y,coverage)
  if x>=0 and y>=0 and x<width and y<height then
   local index=y*width+x+1
   if coverage>alpha[index] then alpha[index]=coverage end
  end
 end)
 return alpha,stats
end
function S.spans(contours,options)
 options=options or {}
 local out={}
 local current=nil
 local quantum=tonumber(options.quantum) or 1/1024
 local stats=S.fill(contours,options,function(x,y,coverage)
  local key=floor(coverage/quantum+0.5)
  if current and current.y==y and current.x+current.w==x and current.key==key then
   current.w+=1
  else
   current={x=x,y=y,w=1,coverage=coverage,key=key}
   out[#out+1]=current
  end
 end)
 return out,stats
end
function S.coverageAt(contours,options,x,y)
 local total=0
 S.fill(contours,{matrix=options and options.matrix,rule=options and options.rule,region={x=x,y=y,w=1,h=1},width=x+1,height=y+1},function(_,_,coverage)
  total=coverage
 end)
 return total
end
function S.area(contours)
 local total=0
 for _,contour in ipairs(contours) do
  local count=#contour
  for index=1,count do
   local ax,ay=pointOf(contour[index])
   local bx,by=pointOf(contour[index%count+1])
   if ax and bx then total+=ax*by-bx*ay end
  end
 end
 return total*0.5
end
return S
