local V=require(script.Parent.VisualStyle)
local G=require(script.Parent.VisualGeometry)
local S={VERSION=1}
local names={'top','right','bottom','left'}
local function inset(outer,widths,factor)
 local t,r,b,l=widths[1]*factor,widths[2]*factor,widths[3]*factor,widths[4]*factor
 return {x=l,y=t,w=math.max(0,outer.w-l-r),h=math.max(0,outer.h-t-b),r=G.insetRadii(outer.r,l,t,r,b)}
end
local function inside(rect,x,y)return rect.w>0 and rect.h>0 and G.inside(rect.r,rect.w,rect.h,x-rect.x,y-rect.y)end
function S.prepare(style,box,context,path)
 local widths=style._borderWidths;local outer={x=0,y=0,w=box.w,h=box.h,r=G.radii(style,box.w,box.h,context)}
 local p={sides={},widths=widths,outer=outer,inner=inset(outer,widths,1),third=inset(outer,widths,1/3),twoThirds=inset(outer,widths,2/3),half=inset(outer,widths,.5)}
 for i,name in ipairs(names)do
  local color,alpha=V.color(style['border-'..name..'-color']or 'currentcolor',style.color)
  local q={width=widths[i],mode=style['border-'..name..'-style']or 'solid',color=color,alpha=alpha};p.sides[i]=q
  if q.width>0 and(q.mode=='dashed'or q.mode=='dotted')then
   q.path,q.length=path(outer,q.width);local count=math.max(1,math.floor(q.length/(q.width*(q.mode=='dotted'and 2 or 5))+.5))
   assert(count<=1024,'Borda lateral excede 1024 traços.');q.period=q.length/count
  end
 end
 return p
end
function S.sample(p,x,y)
 if not inside(p.outer,x,y)or inside(p.inner,x,y)then return Color3.new(),0 end
 local distances={y,p.outer.w-x,p.outer.h-y,x};local side,score=nil,math.huge
 for i,q in ipairs(p.sides)do if q.width>0 and distances[i]/q.width<score then side=i;score=distances[i]/q.width end end
 if not side then return Color3.new(),0 end
 local q=p.sides[side];if q.mode=='none'or q.mode=='hidden'then return Color3.new(),0 end
 local color=q.color
 if q.mode=='double'and inside(p.third,x,y)and not inside(p.twoThirds,x,y)then return Color3.new(),0 end
 if q.mode=='groove'or q.mode=='ridge'or q.mode=='inset'or q.mode=='outset'then
  local reverse=q.mode=='inset'or q.mode=='groove';if(q.mode=='groove'or q.mode=='ridge')and inside(p.half,x,y)then reverse=not reverse end
  local leading=side==1 or side==4;local light=reverse and not leading or not reverse and leading
  color=color:Lerp(light and Color3.new(1,1,1)or Color3.new(),.42)
 end
 if q.path and q.period>1e-9 then
  local at,nearest=0,math.huge
  for i=2,#q.path do local a,b=q.path[i-1],q.path[i];local dx,dy=b.x-a.x,b.y-a.y;local square=dx*dx+dy*dy
   if square>1e-9 then local t=math.clamp(((x-a.x)*dx+(y-a.y)*dy)/square,0,1);local d=(x-a.x-t*dx)^2+(y-a.y-t*dy)^2
    if d<nearest then nearest=d;at=a.d+(b.d-a.d)*t end
   end
  end
  local phase=at%q.period
  if q.mode=='dashed'then if phase>=q.period*.6 or nearest>q.width*q.width/4 then return Color3.new(),0 end
  else local tangent=math.min(phase,q.period-phase);if tangent*tangent+nearest>q.width*q.width/4 then return Color3.new(),0 end end
 end
 return color,q.alpha
end
function S.draw(k,parent,p,z)
 local step=math.max(1,k.step);local y=0
 while y<p.outer.h-.001 do
  if k.checkpoint then k.checkpoint(8)end
  local h=math.min(step,p.outer.h-y);local mid=y+h/2
  local lo,hi=G.bounds(p.outer.r,p.outer.w,p.outer.h,mid)
  local il,ir=0,0
  if mid>=p.inner.y and mid<p.inner.y+p.inner.h and p.inner.w>0 then il,ir=G.bounds(p.inner.r,p.inner.w,p.inner.h,mid-p.inner.y);il+=p.inner.x;ir+=p.inner.x end
  local spans=ir>il and{{lo,math.min(hi,il)},{math.max(lo,ir),hi}}or{{lo,hi}}
  for _,span in ipairs(spans)do
   local x=span[1];local start=x;local lastColor,lastAlpha
   while x<span[2]-.001 do
    local w=math.min(step,span[2]-x);local color,alpha=S.sample(p,x+w/2,mid)
    if lastColor and(color~=lastColor or alpha~=lastAlpha)then k:solid(parent,start,y,x-start,h,lastColor,lastAlpha,z);start=x end
    lastColor,lastAlpha=color,alpha;x+=w
   end
   if lastColor then k:solid(parent,start,y,x-start,h,lastColor,lastAlpha,z)end
  end
  y+=h
 end
 parent:SetAttribute('CssSideBorders',true)
end
return S
