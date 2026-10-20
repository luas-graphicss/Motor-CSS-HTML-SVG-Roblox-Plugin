local U=require(script.Parent.Util)
local G=require(script.Parent.SvgGeometry)
local B={}
function B.reference(value)
 if not value or value=='none'then return nil end
 local inside,tail=value:match('^%s*url%s*%((.-)%)%s*(.-)%s*$')
 assert(inside,'Referência SVG exige url(#id).');inside=U.trim(inside)
 local q=inside:sub(1,1);if q=='\"'or q=="'"then assert(inside:sub(-1)==q,'Aspas SVG incompatíveis.');inside=inside:sub(2,-2)end
 local id=inside:match('^#([%w_%.:%-]+)$');assert(id,'Somente referências SVG locais #id são aceitas.')
 return id,tail
end
function B.linear(v)return v<=.04045 and v/12.92 or ((v+.055)/1.055)^2.4 end
function B.srgb(v)return v<=.0031308 and v*12.92 or 1.055*v^(1/2.4)-.055 end
function B.color(value,attrs,current,context)
 value=value or '#000000'
 if value=='context-fill'or value=='context-stroke'then
  value=context and context[value=='context-fill'and 'fill'or 'stroke']or 'none'
 end
 if value=='none'then return Color3.new(),0 end
 if value:lower()=='currentcolor'then value=attrs.color;if not value or value:lower()=='currentcolor'then return current,1 end end
 return U.color(value)
end
function B.sampler(value,attrs,bbox,m,c,defs,legacy,context)
 if not value or value=='none'then return nil end
 if value=='context-fill'or value=='context-stroke'then value=context and context[value=='context-fill'and 'fill'or 'stroke']or 'none';if value=='none'then return nil end end
 if not value:match('^%s*url')then local color,a=B.color(value,attrs,c.color,context);return function()return color,a end end
 local id,fallback=B.reference(value);local definition=defs[id]
 if not definition then if fallback and fallback~=''then return B.sampler(fallback,attrs,bbox,m,c,defs,legacy,context)end;error('Paint server SVG não encontrado: #'..id,0)end
 local seen={};local function load(n,depth)
  assert(depth<=16 and not seen[n],'Ciclo em gradiente SVG.');seen[n]=true
  assert(n.tag=='lineargradient'or n.tag=='radialgradient','fill/stroke exige linearGradient ou radialGradient.')
  local a,stops={},{};local href=n.attrs.href or n.attrs['xlink:href']
  if href then
   local ref=href:match('^#([%w_%.:%-]+)$');assert(ref and defs[ref],'href de gradiente deve apontar para um gradiente local existente.')
   a,stops=load(defs[ref],depth+1)
  end
  for k,v in pairs(n.attrs)do a[k]=v end
  local own={};for _,child in ipairs(n.children or {})do if child.tag=='stop'then own[#own+1]=child else assert(child.tag=='title'or child.tag=='desc','Gradiente aceita apenas stop.')end end
  if #own>0 then stops=own end;seen[n]=nil;return a,stops
 end
 local a,nodes=load(definition,1);assert(#nodes<=128,'Gradiente excede 128 stops.')
 local units=a.gradientunits or 'objectBoundingBox';assert(units=='objectBoundingBox'or units=='userSpaceOnUse','gradientUnits inválido.')
 if units=='objectBoundingBox'and(bbox.w<=1e-12 or bbox.h<=1e-12)then return nil end
 local baseX,baseY=units=='objectBoundingBox'and 1 or c.vb[3],units=='objectBoundingBox'and 1 or c.vb[4]
 local originX,originY=units=='objectBoundingBox'and 0 or c.vb[1],units=='objectBoundingBox'and 0 or c.vb[2]
 local function coordinate(k,default,axis)
  local raw=a[k]or default;local pct=raw:sub(-1)=='%'
  return G.number(raw,0,axis=='x'and baseX or baseY)+(pct and(axis=='x'and originX or originY)or 0)
 end
 local gm=G.mul(m,units=='objectBoundingBox'and G.bboxMatrix(bbox)or G.I)
 gm=G.mul(gm,G.transform(a.gradienttransform,legacy));local inverse=G.inverse(gm);if not inverse then return nil end
 local spread=a.spreadmethod or 'pad';assert(spread=='pad'or spread=='repeat'or spread=='reflect','spreadMethod inválido.')
 local interpolation=a['color-interpolation']or 'sRGB';assert(interpolation=='sRGB'or interpolation=='linearRGB','color-interpolation inválido.')
 local stops,last={},0
 for _,node in ipairs(nodes)do
  local at=math.clamp(G.number(node.attrs.offset,0,1),last,1);last=at
  local color,alpha=B.color(node.attrs['stop-color']or '#000000',node.attrs,c.color)
  alpha*=G.opacity(node.attrs['stop-opacity'],1)
  local r,g,b=color.R,color.G,color.B
  if interpolation=='linearRGB'then r,g,b=B.linear(r),B.linear(g),B.linear(b)end
  stops[#stops+1]={t=at,r=r*alpha,g=g*alpha,b=b*alpha,a=alpha}
 end
 if #stops==0 then return nil end
 local x1,y1,x2,y2,cx,cy,rx,ry,fx,fy
 if definition.tag=='lineargradient'then x1=coordinate('x1','0%','x');y1=coordinate('y1','0%','y');x2=coordinate('x2','100%','x');y2=coordinate('y2','0%','y')
 else
  cx=coordinate('cx','50%','x');cy=coordinate('cy','50%','y');rx=G.number(a.r or '50%',0,math.sqrt((baseX^2+baseY^2)/2));ry=rx
  assert(rx>=0,'Raio de radialGradient negativo.');fx=coordinate('fx',a.cx or '50%','x');fy=coordinate('fy',a.cy or '50%','y')
  local distance=math.sqrt((fx-cx)^2+(fy-cy)^2);if distance>=rx and distance>0 then local f=rx*.999999/distance;fx,fy=cx+(fx-cx)*f,cy+(fy-cy)*f end
 end
 local function sample(x,y)
  x,y=G.at(inverse,x,y);local t
  if x1 then local dx,dy=x2-x1,y2-y1;local length=dx*dx+dy*dy;t=length<1e-16 and 1 or ((x-x1)*dx+(y-y1)*dy)/length
  else
   if rx<=1e-12 then t=1 else
    local dx,dy=x-fx,y-fy;local ox,oy=fx-cx,fy-cy;local aa=dx*dx+dy*dy;local bb=2*(ox*dx+oy*dy);local cc=ox*ox+oy*oy-rx*rx
    local hit=aa<=1e-16 and math.huge or(-bb+math.sqrt(math.max(0,bb*bb-4*aa*cc)))/(2*aa);t=hit>1e-12 and 1/hit or 0
   end
  end
  if spread=='repeat'then t=t%1 elseif spread=='reflect'then t=t%2;if t>1 then t=2-t end else t=math.clamp(t,0,1)end
  local left,right=stops[1],stops[#stops]
  for i,s in ipairs(stops)do if s.t<=t then left=s else right=s;break end end
  if t>=stops[#stops].t then left,right=stops[#stops],stops[#stops]end
  local f=right.t>left.t and math.clamp((t-left.t)/(right.t-left.t),0,1)or 0
  local alpha=left.a+(right.a-left.a)*f;if alpha<=1e-9 then return Color3.new(),0 end
  local r=(left.r+(right.r-left.r)*f)/alpha;local g=(left.g+(right.g-left.g)*f)/alpha;local b=(left.b+(right.b-left.b)*f)/alpha
  if interpolation=='linearRGB'then r,g,b=B.srgb(r),B.srgb(g),B.srgb(b)end
  return Color3.new(math.clamp(r,0,1),math.clamp(g,0,1),math.clamp(b,0,1)),alpha
 end
 return sample
end
return B
