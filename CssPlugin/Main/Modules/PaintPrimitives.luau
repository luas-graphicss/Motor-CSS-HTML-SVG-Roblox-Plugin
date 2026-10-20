local Cost=require(script.Parent.CostModel)
local O=require(script.Parent.RenderOptimizer)
local G=require(script.Parent.VisualGeometry)
local Gradient=require(script.Parent.CssGradient)
local Shapes=require(script.Parent.PaintShapes)
local K={MAX_INSTANCES=10000,MAX_ROWS=192}
local white=Color3.new(1,1,1)
local function intersect(a,b)
 local x,y=math.max(a.x,b.x),math.max(a.y,b.y)
 return {x=x,y=y,w=math.max(0,math.min(a.x+a.w,b.x+b.w)-x),h=math.max(0,math.min(a.y+a.h,b.y+b.h)-y)}
end
K.intersect=intersect
function K.new(root,opacity,box,checkpoint)
 local self={root=root,opacity=opacity,count=0,step=math.max(1,box.h/K.MAX_ROWS),checkpoint=checkpoint}
 function self:make(class,name,parent)
  self.count+=1;Cost.cap('instances',self.count,'Primitivas por elemento')
  if self.checkpoint and self.count%64==0 then self.checkpoint(64)end
  local o=O.acquire(class);o.Name=name;o:SetAttribute('CssOwned',true)
  if o:IsA('GuiObject')then o.BorderSizePixel=0;o.BackgroundTransparency=1;o.Active=false;o.Selectable=false end
  if parent then o.Parent=parent end;return o
 end
 function self:solid(parent,x,y,w,h,color,alpha,z,role)
  if w<=0.001 or h<=0.001 or(alpha<=0 and role~='background-color')then return end
  local o=self:make('Frame','ColorBand',parent);o.Position=UDim2.fromOffset(x,y);o.Size=UDim2.fromOffset(w,h);o.ZIndex=z
  o.BackgroundColor3=color;o.BackgroundTransparency=1-alpha*self.opacity;o:SetAttribute('CssPaintAlpha',alpha)
  if role then o:SetAttribute('CssPaintRole',role)end;return o
 end
 return self
end
function K.bounds(clip,y)
 if y<clip.y or y>=clip.y+clip.h then return 0,0 end
 if clip.r then local l,r=G.bounds(clip.r,clip.w,clip.h,y-clip.y);return l+clip.x,r+clip.x end
 return clip.x,clip.x+clip.w
end
function K.spans(clip,y)
 local l,r=K.bounds(clip,y)
 local spans=r-l>1e-4 and {{l,r}} or {}
 if #spans>0 and clip.shape then spans=Shapes.intersect(spans,clip.shape.rows(y))end
 if #spans>0 and clip.hole then spans=Shapes.subtract(spans,clip.hole.rows(y))end
 return spans
end
function K.maskBands(clip,rect,step,fn)
 local area=intersect(clip,rect);if area.w<=0 or area.h<=0 then return end
 local top,bottom=0,0
 if clip.r then top=math.max(clip.r[1].y,clip.r[2].y);bottom=math.max(clip.r[3].y,clip.r[4].y)end
 local simple=clip.shape==nil and clip.hole==nil
 local y=area.y
 while y<area.y+area.h-0.001 do
  local h=math.min(step,area.y+area.h-y)
  if simple and y>=clip.y+top and y<clip.y+clip.h-bottom then h=math.min(area.y+area.h,clip.y+clip.h-bottom)-y end
  for _,span in ipairs(K.spans(clip,y+h/2))do
   local l=math.max(span[1],area.x);local r=math.min(span[2],area.x+area.w)
   if r>l then fn(l,y,r-l,h)end
  end
  y+=math.max(h,0.001)
 end
end
local function circular(r,w,h)
 local limit=math.min(w,h)/2
 if r then for _,corner in ipairs(r)do if math.abs(corner.x-corner.y)>1e-6 or corner.x>limit+1e-6 then return false end end end;return true
end
local function corner(k,frame,r)
 if not r or not frame then return end
 if r[1].x+r[2].x+r[3].x+r[4].x<=0 then return end
 local c=k:make('UICorner','Corners',frame)
 if r[1].x==r[2].x and r[1].x==r[3].x and r[1].x==r[4].x then c.CornerRadius=UDim.new(0,r[1].x)
 else c.TopLeftRadius=UDim.new(0,r[1].x);c.TopRightRadius=UDim.new(0,r[2].x);c.BottomRightRadius=UDim.new(0,r[3].x);c.BottomLeftRadius=UDim.new(0,r[4].x)end
end
K.circular=circular;K.corner=corner
function K.fill(k,parent,clip,color,alpha,z,role)
 if circular(clip.r,clip.w,clip.h)and not clip.shape and not clip.hole then local f=k:solid(parent,clip.x,clip.y,clip.w,clip.h,color,alpha,z,role);corner(k,f,clip.r);return end
 K.maskBands(clip,clip,k.step,function(x,y,w,h)k:solid(parent,x,y,w,h,color,alpha,z,role)end)
end
local function errorOf(c,a,ca,aa,cb,ab)
 local alpha=(aa+ab)/2
 local r,g,b=(ca.R+cb.R)*alpha/2,(ca.G+cb.G)*alpha/2,(ca.B+cb.B)*alpha/2
 return math.max(math.abs(a-alpha),math.abs(c.R*a-r),math.abs(c.G*a-g),math.abs(c.B*a-b))
end
function K.breaks(g,y,lo,hi)
 local values={lo,hi};local minT,maxT=0,1
 if g.kind=='linear-gradient'then local a,b=Gradient.parameter(g,lo,y),Gradient.parameter(g,hi,y);minT,maxT=math.min(a,b),math.max(a,b)
 elseif g.kind=='radial-gradient'then minT=Gradient.parameter(g,math.clamp(g.cx,lo,hi),y);maxT=math.max(Gradient.parameter(g,lo,y),Gradient.parameter(g,hi,y))end
 local function add(x)if x>lo+1e-6 and x<hi-1e-6 then values[#values+1]=x end end
 local function crossing(t)
  if g.kind=='linear-gradient'then
   if math.abs(g.dx)>1e-10 then add(g.w/2+((t-.5)*g.length-(y-g.h/2)*g.dy)/g.dx)end
  elseif g.kind=='radial-gradient'then
   local v=t*t-((y-g.cy)/g.ry)^2;if t>=0 and v>=0 then local d=g.rx*math.sqrt(v);add(g.cx-d);add(g.cx+d)end
  else
   local angle=(t+g.from)*2*math.pi;local dy=-math.cos(angle)
   if math.abs(dy)>1e-10 then local distance=(y-g.cy)/dy;if distance>=0 then add(g.cx+distance*math.sin(angle))end end
  end
 end
 if g.kind=='conic-gradient'then crossing(0);crossing(1);if math.abs(y-g.cy)<1e-6 then add(g.cx)end end
 if g.repeating and g.period>1e-9 then
  local first=math.floor((minT-g.first)/g.period)-1;local last=math.ceil((maxT-g.first)/g.period)+1
  assert((last-first)*#g.stops<=4096,'Gradiente repetido denso demais para o renderizador persistente.')
  for n=first,last do for _,s in ipairs(g.stops)do local t=s.t+n*g.period;if t>=minT-1e-9 and t<=maxT+1e-9 then crossing(t)end end end
 else for _,s in ipairs(g.stops)do crossing(s.t)end end
 table.sort(values);local unique={}
 for _,x in ipairs(values)do if #unique==0 or x-unique[#unique]>1e-5 then unique[#unique+1]=x end end
 return unique
end
local function strip(k,parent,x,y,w,h,z,points)
 if w<=.001 then return end
 local initial=points[1];local constant=true
 for i=2,#points do local p=points[i];if p.c~=initial.c or math.abs(p.a-initial.a)>1e-7 then constant=false;break end end
 if constant then k:solid(parent,x,y,w,h,initial.c,initial.a,z);return end
 local first=1
 while first<#points do
  local last=math.min(first+19,#points);local left,right=points[first].x,points[last].x;local span=right-left
  if span>.001 then
   local f=k:make('Frame','GradientBand',parent);f.Position=UDim2.fromOffset(x+left,y);f.Size=UDim2.fromOffset(span,h);f.ZIndex=z;f.BackgroundColor3=white;f.BackgroundTransparency=0
   local cs,ts,raw={},{},{}
   for i=first,last do local p=points[i];local t=(p.x-left)/span
    cs[#cs+1]=ColorSequenceKeypoint.new(t,p.c);ts[#ts+1]=NumberSequenceKeypoint.new(t,1-p.a*k.opacity);raw[#raw+1]=t..','..p.a
   end
   local grad=k:make('UIGradient','Gradient',f);grad.Color=ColorSequence.new(cs);grad.Transparency=NumberSequence.new(ts);grad.Rotation=0;grad:SetAttribute('CssAlphaStops',table.concat(raw,';'))
  end
  first=last
 end
end
 
 
 
K.ROTATED_LINEAR=true
local function uniformStops(g)
 local previous=-math.huge;local alpha=g.stops[1].a
 for _,s in ipairs(g.stops)do if s.t<=previous or math.abs(s.a-alpha)>1e-9 then return false end;previous=s.t end
 return true
end
local function rotatedLinear(k,parent,clip,map,g,z,window)
 if not K.ROTATED_LINEAR or g.kind~='linear-gradient'or g.repeating or g.definition.hints or #g.stops>18 or clip.shape or clip.hole then return false end
 if math.abs(g.dx)<=1e-9 or math.abs(g.dy)<=1e-9 then return false end
 if map.sx~=0 or map.sy~=0 or map.sw~=g.w or map.sh~=g.h or map.dx~=clip.x or map.dy~=clip.y or map.dw~=clip.w or map.dh~=clip.h then return false end
 if not uniformStops(g)then return false end
 local w,h=clip.w,clip.h
 local px,py=w*g.dx,h*g.dy
 local norm=math.sqrt(px*px+py*py);if norm<=1e-9 then return false end
 local s=g.length/norm
 local rotation=math.deg(math.atan2(py/norm,px/norm))
 local holder=k:make('Frame','GradientWindow',parent)
 holder.Position=UDim2.fromOffset(window.x,window.y);holder.Size=UDim2.fromOffset(window.w,window.h);holder.ClipsDescendants=true;holder.ZIndex=z
 local f=k:make('Frame','RotatedLinearGradient',holder)
 f.Position=UDim2.fromOffset(clip.x+w/2-s*w/2-window.x,clip.y+h/2-s*h/2-window.y);f.Size=UDim2.fromOffset(s*w,s*h)
 f.BackgroundColor3=white;f.BackgroundTransparency=0;f.ZIndex=z
 local positions={0,1}
 for _,st in ipairs(g.stops)do if st.t>0 and st.t<1 then positions[#positions+1]=st.t end end;table.sort(positions)
 local cs,ts,raw={},{},{}
 for _,t in ipairs(positions)do local color,a=Gradient.at(g,t);cs[#cs+1]=ColorSequenceKeypoint.new(t,color);ts[#ts+1]=NumberSequenceKeypoint.new(t,1-a*k.opacity);raw[#raw+1]=t..','..a end
 local grad=k:make('UIGradient','Gradient',f);grad.Rotation=rotation;grad.Color=ColorSequence.new(cs);grad.Transparency=NumberSequence.new(ts);grad:SetAttribute('CssAlphaStops',table.concat(raw,';'))
 return true
end
local function nativeLinear(k,parent,clip,map,g,z)
 if g.kind~='linear-gradient'or g.repeating or g.definition.hints or #g.stops>18 or clip.shape or clip.hole or not circular(clip.r,clip.w,clip.h)then return false end
 if math.abs(g.dx)>1e-9 and math.abs(g.dy)>1e-9 then return false end
 if map.sx~=0 or map.sy~=0 or map.sw~=g.w or map.sh~=g.h or map.dx~=clip.x or map.dy~=clip.y or map.dw~=clip.w or map.dh~=clip.h then return false end
 local previous=-math.huge;local alpha=g.stops[1].a
 for _,s in ipairs(g.stops)do if s.t<=previous or math.abs(s.a-alpha)>1e-9 then return false end;previous=s.t end
 local reverse=g.dx< -1e-9 or g.dy< -1e-9;local positions={0,1}
 for _,s in ipairs(g.stops)do if s.t>0 and s.t<1 then positions[#positions+1]=reverse and 1-s.t or s.t end end;table.sort(positions)
 local f=k:make('Frame','NativeLinearGradient',parent);f.Position=UDim2.fromOffset(clip.x,clip.y);f.Size=UDim2.fromOffset(clip.w,clip.h);f.BackgroundColor3=white;f.BackgroundTransparency=0;f.ZIndex=z
 local cs,ts,raw={},{},{}
 for _,t in ipairs(positions)do local color,a=Gradient.at(g,reverse and 1-t or t);cs[#cs+1]=ColorSequenceKeypoint.new(t,color);ts[#ts+1]=NumberSequenceKeypoint.new(t,1-a*k.opacity);raw[#raw+1]=t..','..a end
 local grad=k:make('UIGradient','Gradient',f);grad.Rotation=math.abs(g.dy)>1e-9 and 90 or 0;grad.Color=ColorSequence.new(cs);grad.Transparency=NumberSequence.new(ts);grad:SetAttribute('CssAlphaStops',table.concat(raw,';'));corner(k,f,clip.r);return true
end
 
 
 
local function nativeRadial(k,parent,clip,map,g,z)
 if g.kind~='radial-gradient'or g.repeating or clip.shape or clip.hole or clip.r then return false end
 if g.rx==math.huge or g.rx<=0 or math.abs(g.rx-g.ry)>1e-6 then return false end
 if map.dw<=.001 or map.dh<=.001 then return false end
 local sx,sy=map.sw/map.dw,map.sh/map.dh
 if math.abs(sx-sy)>1e-6 then return false end
 if map.dx>clip.x+1e-3 or map.dy>clip.y+1e-3 or map.dx+map.dw<clip.x+clip.w-1e-3 or map.dy+map.dh<clip.y+clip.h-1e-3 then return false end
 local cx,cy=map.dx+(g.cx-map.sx)/sx,map.dy+(g.cy-map.sy)/sy
 local radius=g.rx/sx
 if radius<1 or radius>8192 then return false end
 local probes=64;local previous
 local minR,minG,minB,minA,maxR,maxG,maxB,maxA=1,1,1,1,0,0,0,0
 for i=0,probes do
  local c,a=Gradient.at(g,i/probes)
  if previous and a>previous+1e-6 then return false end
  previous=a
  local pr,pg,pb=c.R*a,c.G*a,c.B*a
  if pr<minR then minR=pr end;if pr>maxR then maxR=pr end
  if pg<minG then minG=pg end;if pg>maxG then maxG=pg end
  if pb<minB then minB=pb end;if pb>maxB then maxB=pb end
  if a<minA then minA=a end;if a>maxA then maxA=a end
 end
 local range=math.max(maxR-minR,maxG-minG,maxB-minB,maxA-minA)
 local rings=math.clamp(math.ceil(range*255/1.5),4,48)
 local container=k:make('Frame','RadialClip',parent)
 container.Position=UDim2.fromOffset(clip.x,clip.y);container.Size=UDim2.fromOffset(clip.w,clip.h);container.ClipsDescendants=true;container.ZIndex=z
 local lastColor,lastA=Gradient.at(g,1)
 local baseR,baseG,baseB,baseA=0,0,0,0
 if lastA>1e-6 then
  k:solid(container,0,0,clip.w,clip.h,lastColor,lastA,z)
  baseR,baseG,baseB,baseA=lastColor.R*lastA,lastColor.G*lastA,lastColor.B*lastA,lastA
 end
 for j=rings,1,-1 do
  local c,a=Gradient.at(g,(j-.5)/rings)
  local pr,pg,pb=c.R*a,c.G*a,c.B*a
  local la=baseA>=1-1e-6 and 1 or math.clamp((a-baseA)/(1-baseA),0,1)
  if la>1e-4 then
   local r,gg,b
   if la>=1-1e-6 then r,gg,b=pr,pg,pb else r=(pr-(1-la)*baseR)/la;gg=(pg-(1-la)*baseG)/la;b=(pb-(1-la)*baseB)/la end
   local rad=radius*j/rings
   local f=k:make('Frame','RadialRing',container)
   f.Position=UDim2.fromOffset(cx-rad-clip.x,cy-rad-clip.y);f.Size=UDim2.fromOffset(rad*2,rad*2);f.ZIndex=z
   f.BackgroundColor3=Color3.new(math.clamp(r,0,1),math.clamp(gg,0,1),math.clamp(b,0,1));f.BackgroundTransparency=1-la*k.opacity
   f:SetAttribute('CssPaintAlpha',la)
   local corner=k:make('UICorner','Corners',f);corner.CornerRadius=UDim.new(.5,0)
   baseR,baseG,baseB,baseA=pr,pg,pb,a
  end
 end
 return true
end
function K.field(k,parent,clip,map,gradient,z)
 local rect={x=map.dx,y=map.dy,w=map.dw,h=map.dh};local area=intersect(clip,rect)
 if area.w<=.001 or area.h<=.001 or map.sw<=.001 or map.sh<=.001 then return end
 if nativeLinear(k,parent,clip,map,gradient,z)then return end
 if nativeRadial(k,parent,clip,map,gradient,z)then return end
 local ranges={{area.y,area.y+area.h}}
 do
  local top,bottom=0,0
  if clip.r then top=math.max(clip.r[1].y,clip.r[2].y);bottom=math.max(clip.r[3].y,clip.r[4].y)end
  local midY0,midY1=math.max(area.y,clip.y+top),math.min(area.y+area.h,clip.y+clip.h-bottom)
  if midY1-midY0>.001 and rotatedLinear(k,parent,clip,map,gradient,z,{x=area.x,y=midY0,w=area.w,h=midY1-midY0})then
   ranges={{area.y,midY0},{midY1,area.y+area.h}}
  end
 end
 local sx,sy=map.sw/map.dw,map.sh/map.dh
 local verticalCuts,nextCut
 if gradient.kind=='linear-gradient'and math.abs(gradient.dx)<1e-10 then
  local rotated=table.clone(gradient);rotated.dx=gradient.dy;rotated.dy=0;rotated.w,rotated.h=gradient.h,gradient.w
  verticalCuts=K.breaks(rotated,0,map.sy+(area.y-map.dy)*sy,map.sy+(area.y+area.h-map.dy)*sy)
  for i,value in ipairs(verticalCuts)do verticalCuts[i]=map.dy+(value-map.sy)/sy end;nextCut=2
 end
 for _,range in ipairs(ranges)do
 local y,yEnd=range[1],range[2]
 while y<yEnd-.001 do
  local h=math.min(k.step,yEnd-y)
  if verticalCuts then while nextCut<=#verticalCuts and verticalCuts[nextCut]<=y+1e-6 do nextCut+=1 end;if verticalCuts[nextCut]then h=math.min(h,verticalCuts[nextCut]-y)end end
  if gradient.kind=='linear-gradient'and math.abs(gradient.dy)<1e-10 and clip.shape==nil and clip.hole==nil then
   local top,bottom=0,0;if clip.r then top=math.max(clip.r[1].y,clip.r[2].y);bottom=math.max(clip.r[3].y,clip.r[4].y)end
   if y>=clip.y+top and y<clip.y+clip.h-bottom then h=math.min(yEnd,clip.y+clip.h-bottom)-y end
  end
  local mid=y+h/2
  for _,span in ipairs(K.spans(clip,mid))do
  local l=math.max(span[1],area.x);local r=math.min(span[2],area.x+area.w)
  if r-l>.001 then
   local gy=map.sy+(mid-map.dy)*sy;local gx1=map.sx+(l-map.dx)*sx;local gx2=map.sx+(r-map.dx)*sx
   local crossings=K.breaks(gradient,gy,gx1,gx2)
   for interval=1,#crossings-1 do
    local left=map.dx+(crossings[interval]-map.sx)/sx;local right=map.dx+(crossings[interval+1]-map.sx)/sx;local width=right-left
    if width>.001 then
     local epsilon=math.min(1e-5,width/1000)
     local function sample(x)return Gradient.sample(gradient,map.sx+(left+math.clamp(x,epsilon,width-epsilon)-map.dx)*sx,gy)end
     local c,a=sample(0);local points={{x=0,c=c,a=a}}
     local function segment(x1,c1,a1,x2,c2,a2,depth)
      local xm=(x1+x2)/2;local cm,am=sample(xm)
      if depth<8 and x2-x1>.5 and errorOf(cm,am,c1,a1,c2,a2)>1/300 and #points<240 then
       segment(x1,c1,a1,xm,cm,am,depth+1);segment(xm,cm,am,x2,c2,a2,depth+1)
      else points[#points+1]={x=x2,c=c2,a=a2}end
     end
     local seeds=8;local previous=points[1]
     for i=1,seeds do local x2=width*i/seeds;local c2,a2=sample(x2);segment(previous.x,previous.c,previous.a,x2,c2,a2,0);previous=points[#points]end
     strip(k,parent,left,y,width,h,z,points)
    end
   end
  end
  end;y+=h
 end
 end
end
local resamplers={Default=Enum.ResamplerMode.Default,Pixelated=Enum.ResamplerMode.Pixelated}
K.resamplers=resamplers
function K.resample(image,mode)
 local value=mode and resamplers[mode]
 if not value then return false end
 image.ResampleMode=value;image:SetAttribute('CssImageRendering',mode);return true
end
function K.image(k,parent,clip,map,source,z,options)
 options=options or {};local rect={x=map.dx,y=map.dy,w=map.dw,h=map.dh}
 if map.sw<=.001 or map.sh<=.001 or map.dw<=.001 or map.dh<=.001 then return end
 local alpha=options.alpha==nil and 1 or math.clamp(options.alpha,0,1)
 if alpha<=0.0005 then return end
 K.maskBands(clip,rect,k.step,function(x,y,w,h)
  local mask=k:make('Frame','ImageClip',parent);mask.Position=UDim2.fromOffset(x,y);mask.Size=UDim2.fromOffset(w,h);mask.ClipsDescendants=true;mask.ZIndex=z
  local image=k:make('ImageLabel','BackgroundImage',mask);image.Image=source;image.ZIndex=z;image.ImageTransparency=1-alpha*k.opacity
  image:SetAttribute('CssPaintAlpha',alpha);image:SetAttribute('CssBackgroundAsset',true)
  K.resample(image,options.resample)
  if options.object then
   local o=options.object
   image.Position=UDim2.fromOffset(map.dx+o.x-x,map.dy+o.y-y);image.Size=UDim2.fromOffset(math.max(o.w,0),math.max(o.h,0));image.ScaleType=Enum.ScaleType.Stretch
   image:SetAttribute('CssObjectFit',o.fit or 'fill')
  elseif options.tile then
   image.Position=UDim2.fromOffset(map.dx-x,map.dy-y);image.Size=UDim2.fromOffset(map.dw,map.dh);image.ScaleType=Enum.ScaleType.Tile;image.TileSize=UDim2.fromOffset(options.tile.w,options.tile.h)
  else
   local scaleX,scaleY=map.dw/map.sw,map.dh/map.sh
   image.Position=UDim2.fromOffset(map.dx-map.sx*scaleX-x,map.dy-map.sy*scaleY-y);image.Size=UDim2.fromOffset(map.iw*scaleX,map.ih*scaleY)
   image.ScaleType=options.fit=='cover'and Enum.ScaleType.Crop or options.fit=='contain'and Enum.ScaleType.Fit or Enum.ScaleType.Stretch
  end
 end)
end
return K
