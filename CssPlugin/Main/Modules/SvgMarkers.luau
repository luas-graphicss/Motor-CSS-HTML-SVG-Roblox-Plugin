local M={}
local function vector(x,y)return {x=x,y=y}end
local function nonzero(v)return v and v.x*v.x+v.y*v.y>1e-16 end
function M.vertices(node,polys,legacy)
 if node.tag~='path'then
  local result={}
  for _,poly in ipairs(polys)do
   local p={closed=poly.closed};for _,v in ipairs(poly)do p[#p+1]={x=v.x,y=v.y}end
   for i=1,#p-(p.closed and 0 or 1)do local a,b=p[i],p[i%#p+1];local d=vector(b.x-a.x,b.y-a.y);a.outgoing=d;b.incoming=d end
   result[#result+1]=p
  end;return result
 end
 local tokens=legacy.parsePath(node.attrs.d or '').tokens;local result,p={},nil;local i=1
 local function segment(x,y,startDirection,endDirection)
  local previous=p[#p];previous.outgoing=startDirection;p[#p+1]={x=x,y=y,incoming=endDirection}
 end
 while i<=#tokens do
  local cmd=tokens[i];i+=1
  if cmd=='M'then p={{x=tokens[i],y=tokens[i+1]}};result[#result+1]=p;i+=2
  elseif cmd=='Z'then
   local a,b=p[#p],p[1];local d=vector(b.x-a.x,b.y-a.y);a.outgoing=d;b.incoming=d;p.closed=true
  else
   local a=p[#p];local x,y=a.x,a.y
   if cmd=='L'then local ex,ey=tokens[i],tokens[i+1];local d=vector(ex-x,ey-y);segment(ex,ey,d,d);i+=2
   elseif cmd=='C'then
    local bx,by,cx,cy,ex,ey=tokens[i],tokens[i+1],tokens[i+2],tokens[i+3],tokens[i+4],tokens[i+5]
    local start=vector(bx-x,by-y);if not nonzero(start)then start=vector(cx-x,cy-y)end;if not nonzero(start)then start=vector(ex-x,ey-y)end
    local finish=vector(ex-cx,ey-cy);if not nonzero(finish)then finish=vector(ex-bx,ey-by)end;if not nonzero(finish)then finish=vector(ex-x,ey-y)end
    segment(ex,ey,start,finish);i+=6
   elseif cmd=='Q'then
    local cx,cy,ex,ey=tokens[i],tokens[i+1],tokens[i+2],tokens[i+3];local start=vector(cx-x,cy-y);local finish=vector(ex-cx,ey-cy)
    if not nonzero(start)then start=vector(ex-x,ey-y)end;if not nonzero(finish)then finish=vector(ex-x,ey-y)end
    segment(ex,ey,start,finish);i+=4
   elseif cmd=='A'then
    local ts={'M',x,y,'A'};for k=0,6 do ts[#ts+1]=tokens[i+k]end
    local arc=legacy.paths({tokens=ts},.001)[1];local ex,ey=tokens[i+5],tokens[i+6]
    local start,finish=vector(ex-x,ey-y),vector(ex-x,ey-y)
    if arc and #arc>=2 then start=vector(arc[2].x-arc[1].x,arc[2].y-arc[1].y);finish=vector(arc[#arc].x-arc[#arc-1].x,arc[#arc].y-arc[#arc-1].y)end
    segment(ex,ey,start,finish);i+=7
   else error('Comando canônico SVG inválido para marker: '..tostring(cmd),0)end
  end
 end;return result
end
function M.positions(node,polys,key,legacy)
 local result={}
 if not(node.tag=='path'or node.tag=='line'or node.tag=='polyline'or node.tag=='polygon')then return result end
 for _,p in ipairs(M.vertices(node,polys,legacy))do
  local n=#p;if n==0 then continue end
  local function angle(index,outgoing)
   local field=outgoing and 'outgoing'or 'incoming';local step=outgoing and 1 or -1
   for k=0,n-1 do
    local j=index+step*k;if p.closed then j=(j-1)%n+1 elseif j<1 or j>n then break end
    local d=p[j][field];if nonzero(d)then return math.atan2(d.y,d.x)end
   end;return nil
  end
  local function add(v,a,start)result[#result+1]={point=v,angle=a or 0,start=start==true}end
  if key=='marker-start'then add(p[1],angle(1,true),true)
  elseif key=='marker-end'then local index=p.closed and 1 or n;add(p[index],angle(index,false),false)
  else
   for j=2,n-(p.closed and 0 or 1)do
    local before,after=angle(j,false),angle(j,true);local a=before or after or 0
    if before and after then a=before+((after-before+math.pi)%(2*math.pi)-math.pi)/2 end
    add(p[j],a,false)
   end
  end
 end;return result
end
return M
