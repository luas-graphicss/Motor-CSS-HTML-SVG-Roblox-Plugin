local U=require(script.Parent.Util)
local G=require(script.Parent.VisualGeometry)
local S={VERSION=1,EPSILON=1e-4}
local EPS=S.EPSILON
local empty=table.freeze({})
local Pixels,Clip
local function pixels()
 if not Pixels then Pixels=require(script.Parent.VisualEffectsPixels)end
 return Pixels
end
local function clipper()
 if not Clip then Clip=require(script.Parent.VisualEffectsGeometry)end
 return Clip
end
local function merge(spans)
 table.sort(spans,function(a,b)return a[1]<b[1]end)
 local out={}
 for _,s in ipairs(spans)do
  if s[2]-s[1]>EPS then
   local last=out[#out]
   if last and s[1]<=last[2]+EPS then if s[2]>last[2]then last[2]=s[2]end
   else out[#out+1]={s[1],s[2]}end
  end
 end
 return out
end
S.merge=merge
function S.intersect(a,b)
 if #a==0 or #b==0 then return {}end
 local out={};local i,j=1,1
 while i<=#a and j<=#b do
  local l=math.max(a[i][1],b[j][1]);local r=math.min(a[i][2],b[j][2])
  if r-l>EPS then out[#out+1]={l,r}end
  if a[i][2]<b[j][2] then i+=1 else j+=1 end
 end
 return out
end
function S.subtract(a,b)
 if #a==0 then return {}end
 if #b==0 then return a end
 local out={}
 for _,s in ipairs(a)do
  local l=s[1]
  for _,c in ipairs(b)do
   if c[2]>l and c[1]<s[2]then
    if c[1]-l>EPS then out[#out+1]={l,c[1]}end
    if c[2]>l then l=c[2]end
   end
  end
  if s[2]-l>EPS then out[#out+1]={l,s[2]}end
 end
 return out
end
function S.union(a,b)
 local all={}
 for _,s in ipairs(a)do all[#all+1]={s[1],s[2]}end
 for _,s in ipairs(b)do all[#all+1]={s[1],s[2]}end
 return merge(all)
end
local function build(rows,bounds)
 return {rows=rows,x=bounds and bounds.x or 0,y=bounds and bounds.y or 0,w=bounds and bounds.w or 0,h=bounds and bounds.h or 0}
end
S.build=build
function S.rect(rect)
 return build(function(y)
  if rect.w<=EPS or rect.h<=EPS then return empty end
  if y<rect.y-EPS or y>=rect.y+rect.h then return empty end
  if rect.r then
   local l,r=G.bounds(rect.r,rect.w,rect.h,y-rect.y)
   if r-l<=EPS then return empty end
   return {{rect.x+l,rect.x+r}}
  end
  return {{rect.x,rect.x+rect.w}}
 end,rect)
end
function S.ellipse(cx,cy,rx,ry)
 return build(function(y)
  if rx<=EPS or ry<=EPS then return empty end
  local t=(y-cy)/ry
  if t<=-1 or t>=1 then return empty end
  local d=rx*math.sqrt(math.max(0,1-t*t))
  if d<=EPS then return empty end
  return {{cx-d,cx+d}}
 end,{x=cx-rx,y=cy-ry,w=rx*2,h=ry*2})
end
function S.polygons(contours,rule)
 rule=rule=='evenodd'and'evenodd'or'nonzero'
 local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
 local total=0
 for _,points in ipairs(contours)do
  total+=#points
  for _,p in ipairs(points)do
   if p.x<minX then minX=p.x end
   if p.x>maxX then maxX=p.x end
   if p.y<minY then minY=p.y end
   if p.y>maxY then maxY=p.y end
  end
 end
 assert(total<=20000,'Recorte poligonal excede 20000 pontos.')
 if total==0 then minX,minY,maxX,maxY=0,0,0,0 end
 return build(function(y)
  local crossings={}
  for _,points in ipairs(contours)do
   local count=#points
   if count>=3 then
    for i=1,count do
     local a=points[i];local b=points[i%count+1]
     if (a.y<=y and b.y>y)or(b.y<=y and a.y>y)then
      crossings[#crossings+1]={a.x+(y-a.y)*(b.x-a.x)/(b.y-a.y),b.y>a.y and 1 or-1}
     end
    end
   end
  end
  if #crossings<2 then return empty end
  table.sort(crossings,function(p,q)return p[1]<q[1]end)
  local out={};local winding=0
  for i=1,#crossings-1 do
   winding+=crossings[i][2]
   local inside
   if rule=='evenodd'then inside=i%2==1 else inside=winding~=0 end
   if inside then out[#out+1]={crossings[i][1],crossings[i+1][1]}end
  end
  return merge(out)
 end,{x=minX,y=minY,w=math.max(0,maxX-minX),h=math.max(0,maxY-minY)})
end
function S.surface(surface,w,h,threshold)
 threshold=threshold or .5
 return build(function(y)
  if not surface or w<=EPS or h<=EPS then return empty end
  local sy=math.clamp(math.floor(y/h*surface.h),0,surface.h-1)
  local out={};local start
  local get=pixels().get
  for x=0,surface.w-1 do
   local _,a=get(surface,x,sy)
   if a>threshold then
    if not start then start=x end
   elseif start then out[#out+1]={start/surface.w*w,x/surface.w*w};start=nil end
  end
  if start then out[#out+1]={start/surface.w*w,w}end
  return out
 end,{x=0,y=0,w=w,h=h})
end
function S.all(list)
 local items={}
 for _,item in ipairs(list or {})do if item then items[#items+1]=item end end
 if #items==0 then return nil end
 if #items==1 then return items[1]end
 return build(function(y)
  local spans=items[1].rows(y)
  for i=2,#items do
   if #spans==0 then break end
   spans=S.intersect(spans,items[i].rows(y))
  end
  return spans
 end,items[1])
end
function S.without(base,hole)
 if not base then return nil end
 if not hole then return base end
 return build(function(y)return S.subtract(base.rows(y),hole.rows(y))end,base)
end
function S.contains(object,x,y)
 if not object then return true end
 for _,span in ipairs(object.rows(y))do if x>=span[1]-EPS and x<=span[2]+EPS then return true end end
 return false
end
local nativeShapes={polygon=true,circle=true,ellipse=true,inset=true}
function S.native(value)
 value=U.trim(tostring(value or'none'))
 if value=='none'or value==''then return false end
 local name=value:match('^([%a%-]+)%(')
 return name~=nil and nativeShapes[name]==true
end
function S.fromClip(parsed)
 if not parsed then return nil end
 local kind=parsed.kind
 if kind=='none'then return nil end
 if kind=='circle'or kind=='ellipse'then return S.ellipse(parsed.cx,parsed.cy,parsed.rx,parsed.ry)end
 if kind=='inset'then
  local limit=math.min(parsed.iw,parsed.ih)/2
  local radius=math.clamp(parsed.radius or 0,0,math.max(0,limit))
  local r
  if radius>0 then r={{x=radius,y=radius},{x=radius,y=radius},{x=radius,y=radius},{x=radius,y=radius}}end
  return S.rect({x=parsed.x,y=parsed.y,w=parsed.iw,h=parsed.ih,r=r})
 end
 if kind=='polygon'then return S.polygons({parsed.points},parsed.rule)end
 if parsed.surface then return S.surface(parsed.surface,parsed.w,parsed.h,.5)end
 return nil
end
function S.parse(value,w,h,context)
 value=U.trim(tostring(value or'none'))
 if value=='none'or value==''then return nil end
 local native=S.native(value)
 local ok,parsed=pcall(clipper().clip,value,w,h,context)
 if not ok then
  if native then error(parsed,0)end
  return nil
 end
 return parsed
end
function S.clipPath(value,w,h,context)
 return S.fromClip(S.parse(value,w,h,context))
end
return S
