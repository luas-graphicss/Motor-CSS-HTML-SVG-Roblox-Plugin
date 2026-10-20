local P=require(script.Parent.VisualEffectsPixels)
local G=require(script.Parent.SvgGeometry)
local Paint=require(script.Parent.SvgPaintServer)
local U=require(script.Parent.Util)
local F={MAX_PRIMITIVES=32}
F.BLEND_MODES={normal=true,multiply=true,screen=true,overlay=true,darken=true,lighten=true,['color-dodge']=true,['color-burn']=true,['hard-light']=true,['soft-light']=true,difference=true,exclusion=true,hue=true,saturation=true,color=true,luminosity=true}
F.LIGHTS={fedistantlight=true,fepointlight=true,fespotlight=true}
function F.extent(definition)
 local total=0
 for _,node in ipairs(definition and definition.children or{})do
  local tag=node.tag;local attrs=node.attrs or{}
  if tag=='fegaussianblur'or tag=='fedropshadow'then
   local ns=U.numbers(attrs.stddeviation or(tag=='fedropshadow'and'2'or'0'))
   total+=3*math.max(ns[1]or 0,ns[2]or ns[1]or 0)
  end
  if tag=='feoffset'or tag=='fedropshadow'then
   local d=tag=='fedropshadow'and 2 or 0
   total+=math.max(math.abs(tonumber(attrs.dx)or d),math.abs(tonumber(attrs.dy)or d))
  end
  if tag=='femorphology'then local ns=U.numbers(attrs.radius or'0');total+=math.max(ns[1]or 0,ns[2]or ns[1]or 0)end
  if tag=='feconvolvematrix'then
   local ns=U.numbers(attrs.order or'3');local ox,oy=math.floor(ns[1]or 3),math.floor(ns[2]or ns[1]or 3)
   local tx=math.floor(tonumber(attrs.targetx)or math.floor(ox/2));local ty=math.floor(tonumber(attrs.targety)or math.floor(oy/2))
   total+=math.max(tx,ox-1-tx,ty,oy-1-ty)
  end
  if tag=='fedisplacementmap'then total+=math.abs(tonumber(attrs.scale)or 0)/2 end
 end
 return total
end
local read,write=buffer.readf32,buffer.writef32
local BS,BM,PERLIN=256,255,4096
local RAND_M,RAND_A,RAND_Q,RAND_R=2147483647,16807,127773,2836
local function checkpoint(c,y)if c.checkpoint and y%8==0 then c.checkpoint()end end
local function convert(s,toLinear,c)
 local out=P.new(s.w,s.h);local fn=toLinear and Paint.linear or Paint.srgb
 for y=0,s.h-1 do for x=0,s.w-1 do local color,a=P.get(s,x,y);P.set(out,x,y,Color3.new(fn(color.R),fn(color.G),fn(color.B)),a)end;checkpoint(c,y)end;return out
end
local function alpha(s)
 local out=P.new(s.w,s.h)
 for i=0,s.w*s.h-1 do write(out.data,i*16+12,read(s.data,i*16+12))end;return out
end
local function gaussian(src,sigma,vx,vy,c)
 local length=math.sqrt(vx*vx+vy*vy);sigma*=length
 if sigma<=.01 then return P.clone(src)end
 assert(sigma<=64,'Desvio Gaussian SVG excede 64 pixels de trabalho.')
 vx,vy=vx/length,vy/length;local radius=math.ceil(3*sigma);local kernel,total={},0
 for d=-radius,radius do local v=math.exp(-d*d/(2*sigma*sigma));kernel[d+radius+1]=v;total+=v end
 for i=1,#kernel do kernel[i]/=total end
 local out=P.new(src.w,src.h)
 local aligned=math.abs(vy)<1e-7 or math.abs(vx)<1e-7
 for y=0,src.h-1 do
  for x=0,src.w-1 do
   local r,g,b,a=0,0,0,0
   for d=-radius,radius do
    local xx,yy=x+vx*d,y+vy*d;local weight=kernel[d+radius+1]
    if aligned then
     xx,yy=math.floor(xx+.5),math.floor(yy+.5)
     if xx>=0 and yy>=0 and xx<src.w and yy<src.h then local i=(yy*src.w+xx)*16;r+=read(src.data,i)*weight;g+=read(src.data,i+4)*weight;b+=read(src.data,i+8)*weight;a+=read(src.data,i+12)*weight end
    else
     local x0,y0=math.floor(xx),math.floor(yy);local fx,fy=xx-x0,yy-y0
     for oy=0,1 do for ox=0,1 do local px,py=x0+ox,y0+oy
      if px>=0 and py>=0 and px<src.w and py<src.h then local i=(py*src.w+px)*16;local w=weight*(ox==0 and 1-fx or fx)*(oy==0 and 1-fy or fy);r+=read(src.data,i)*w;g+=read(src.data,i+4)*w;b+=read(src.data,i+8)*w;a+=read(src.data,i+12)*w end
     end end
    end
   end
   local i=(y*src.w+x)*16;write(out.data,i,r);write(out.data,i+4,g);write(out.data,i+8,b);write(out.data,i+12,a)
  end;checkpoint(c,y)
 end;return out
end
local function noiseState(seed)
 seed=math.floor(seed)
 if seed<=0 then seed=-math.fmod(seed,RAND_M-1)+1 end
 if seed>RAND_M-1 then seed=RAND_M-1 end
 local function advance()
  local result=RAND_A*(seed%RAND_Q)-RAND_R*math.floor(seed/RAND_Q)
  if result<=0 then result+=RAND_M end
  seed=result;return result
 end
 local lattice,gx,gy={},{},{}
 for k=1,4 do gx[k]={};gy[k]={}end
 for k=1,4 do
  for i=0,BS-1 do
   if k==1 then lattice[i]=i end
   local a=((advance()%(BS+BS))-BS)/BS
   local b=((advance()%(BS+BS))-BS)/BS
   local length=math.sqrt(a*a+b*b)
   if length>0 then a,b=a/length,b/length end
   gx[k][i]=a;gy[k][i]=b
  end
 end
 for i=BS-1,1,-1 do
  local k=lattice[i];local j=advance()%BS
  lattice[i]=lattice[j];lattice[j]=k
 end
 for i=0,BS+1 do
  lattice[BS+i]=lattice[i]
  for k=1,4 do gx[k][BS+i]=gx[k][i];gy[k][BS+i]=gy[k][i]end
 end
 return {lattice=lattice,gx=gx,gy=gy}
end
local function noise2(state,channel,vx,vy,stitch)
 local t=vx+PERLIN
 local bx0=math.floor(t);local rx0=t-bx0;local bx1=bx0+1;local rx1=rx0-1
 t=vy+PERLIN
 local by0=math.floor(t);local ry0=t-by0;local by1=by0+1;local ry1=ry0-1
 if stitch then
  if bx0>=stitch.wrapX then bx0-=stitch.width end
  if bx1>=stitch.wrapX then bx1-=stitch.width end
  if by0>=stitch.wrapY then by0-=stitch.height end
  if by1>=stitch.wrapY then by1-=stitch.height end
 end
 bx0=bit32.band(bx0,BM);bx1=bit32.band(bx1,BM);by0=bit32.band(by0,BM);by1=bit32.band(by1,BM)
 local lattice=state.lattice;local gx=state.gx[channel];local gy=state.gy[channel]
 local i=lattice[bx0];local j=lattice[bx1]
 local b00,b10,b01,b11=lattice[i+by0],lattice[j+by0],lattice[i+by1],lattice[j+by1]
 local sx=rx0*rx0*(3-2*rx0);local sy=ry0*ry0*(3-2*ry0)
 local u=rx0*gx[b00]+ry0*gy[b00];local v=rx1*gx[b10]+ry0*gy[b10]
 local a=u+sx*(v-u)
 u=rx0*gx[b01]+ry1*gy[b01];v=rx1*gx[b11]+ry1*gy[b11]
 local b=u+sx*(v-u)
 return a+sy*(b-a)
end
local function turbulence(state,channel,x,y,fx,fy,octaves,fractal,stitch)
 local sum,ratio=0,1
 local vx,vy=x*fx,y*fy
 local info=stitch and {width=stitch.width,height=stitch.height,wrapX=stitch.wrapX,wrapY=stitch.wrapY}or nil
 for _=1,octaves do
  local value=noise2(state,channel,vx,vy,info)
  sum+=(fractal and value or math.abs(value))/ratio
  vx*=2;vy*=2;ratio*=2
  if info then info.width*=2;info.wrapX=2*info.wrapX-PERLIN;info.height*=2;info.wrapY=2*info.wrapY-PERLIN end
 end
 return sum
end
function F.apply(source,definition,bbox,m,c,legacy,env)
 local a=definition.attrs;local children=definition.children or {};assert(#children<=F.MAX_PRIMITIVES,'Filtro SVG excede '..F.MAX_PRIMITIVES..' primitivas.')
 local units=a.primitiveunits or 'userSpaceOnUse';assert(units=='objectBoundingBox'or units=='userSpaceOnUse','primitiveUnits inválido.')
 local pm=G.mul(m,units=='objectBoundingBox'and G.bboxMatrix(bbox)or G.I)
 local budget=c.padBudget or c.pad
 local xx,xy,yx,yy=pm[1]*c.sx,pm[2]*c.sy,pm[3]*c.sx,pm[4]*c.sy
 local scaleX,scaleY=math.sqrt(xx*xx+xy*xy),math.sqrt(yx*yx+yy*yy)
 local device={xx,xy,yx,yy,(pm[5]-c.vb[1])*c.sx+c.pad,(pm[6]-c.vb[2])*c.sy+c.pad}
 local toFilter=G.inverse(device)
 local colorSpace=a['color-interpolation-filters']or 'linearRGB';assert(colorSpace=='linearRGB'or colorSpace=='sRGB','color-interpolation-filters inválido.')
 local regionUnits=a.filterunits or 'objectBoundingBox';assert(regionUnits=='objectBoundingBox'or regionUnits=='userSpaceOnUse','filterUnits inválido.')
 local rm=G.mul(m,regionUnits=='objectBoundingBox'and G.bboxMatrix(bbox)or G.I)
 local bw,bh=regionUnits=='objectBoundingBox'and 1 or c.vb[3],regionUnits=='objectBoundingBox'and 1 or c.vb[4]
 local rx,ry=G.number(a.x or '-10%',0,bw),G.number(a.y or '-10%',0,bh)
 if regionUnits=='userSpaceOnUse'then if(a.x or '-10%'):sub(-1)=='%'then rx+=c.vb[1]end;if(a.y or '-10%'):sub(-1)=='%'then ry+=c.vb[2]end end
 local regionW,regionH=G.number(a.width or '120%',0,bw),G.number(a.height or '120%',0,bh);assert(regionW>=0 and regionH>=0,'Região de filtro negativa.')
 local function rectPixels(x,y,w,h,mx)
  local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
  for _,point in ipairs({{x,y},{x+w,y},{x,y+h},{x+w,y+h}})do
   local ux,uy=G.at(mx,point[1],point[2])
   local px,py=(ux-c.vb[1])*c.sx+c.pad,(uy-c.vb[2])*c.sy+c.pad
   x0=math.min(x0,px);y0=math.min(y0,py);x1=math.max(x1,px);y1=math.max(y1,py)
  end
  return {x0=math.clamp(math.floor(x0+.5),0,c.w),y0=math.clamp(math.floor(y0+.5),0,c.h),x1=math.clamp(math.floor(x1+.5),0,c.w),y1=math.clamp(math.floor(y1+.5),0,c.h)}
 end
 local defaultRect=rectPixels(rx,ry,regionW,regionH,rm)
 local function subregion(node)
  local attrs=node.attrs
  if not(attrs.x or attrs.y or attrs.width or attrs.height)then return nil end
  local ox=units=='objectBoundingBox'and 0 or c.vb[1]
  local oy=units=='objectBoundingBox'and 0 or c.vb[2]
  local sw=units=='objectBoundingBox'and 1 or c.vb[3]
  local sh=units=='objectBoundingBox'and 1 or c.vb[4]
  local x,y=G.number(attrs.x,ox,sw),G.number(attrs.y,oy,sh)
  local w,h=G.number(attrs.width,sw,sw),G.number(attrs.height,sh,sh)
  assert(w>=0 and h>=0,'Subregião de filtro negativa.')
  return {x=x,y=y,w=w,h=h}
 end
 local original=colorSpace=='linearRGB'and convert(source,true,c)or P.clone(source)
 local named={SourceGraphic=original};local out=original;local extent=0
 local regions={[original]=defaultRect}
 local function input(value)
  if not value then return out end
  if value=='SourceAlpha'and not named.SourceAlpha then named.SourceAlpha=alpha(original);regions[named.SourceAlpha]=defaultRect end
  local selected=named[value];assert(selected,'Entrada de filtro SVG desconhecida: '..value)
  return selected
 end
 local function blur(s,node)
  local ns=U.numbers(node.attrs.stddeviation or(node.tag=='fedropshadow'and '2'or '0'))
  assert((#ns==1 or #ns==2)and ns[1]>=0 and(ns[2]or ns[1])>=0,'stdDeviation exige um ou dois números não negativos.')
  local sx,sy=ns[1],ns[2]or ns[1]
  extent+=math.ceil(3*(sx*scaleX+sy*scaleY))
  assert(extent<=budget,'Filtro SVG excede a margem segura; reduza stdDeviation/offset ou a resolução.')
  local horizontal=gaussian(s,sx,xx,xy,c);return gaussian(horizontal,sy,yx,yy,c)
 end
 local function offset(s,node)
  local dx=G.number(node.attrs.dx,node.tag=='fedropshadow'and 2 or 0);local dy=G.number(node.attrs.dy,node.tag=='fedropshadow'and 2 or 0)
  local px,py=dx*xx+dy*yx,dx*xy+dy*yy
  extent+=math.ceil(math.max(math.abs(px),math.abs(py)));assert(extent<=budget,'Offset de filtro SVG excede a margem segura.')
  local layer=P.new(s.w,s.h);return P.composite(layer,s,px,py)
 end
 local function flood(node,s)
  local color,opacity=Paint.color(node.attrs['flood-color']or '#000000',node.attrs,c.color)
  opacity*=G.opacity(node.attrs['flood-opacity'],1)
  if colorSpace=='linearRGB'then color=Color3.new(Paint.linear(color.R),Paint.linear(color.G),Paint.linear(color.B))end
  local layer=P.new(source.w,source.h)
  for y=0,layer.h-1 do for x=0,layer.w-1 do local alphaValue=s and select(2,P.get(s,x,y))or 1;P.set(layer,x,y,color,opacity*alphaValue)end;checkpoint(c,y)end
  return layer
 end
 local function lightingColor(node)
  local color=Paint.color(node.attrs['lighting-color']or '#ffffff',node.attrs,c.color)
  if colorSpace=='linearRGB'then color=Color3.new(Paint.linear(color.R),Paint.linear(color.G),Paint.linear(color.B))end
  return color
 end
 for _,node in ipairs(children)do
  local tag=node.tag;local rect=subregion(node);local sourceInput=input(node.attrs['in'])
  if tag=='fegaussianblur'then out=blur(sourceInput,node)
  elseif tag=='fedropshadow'then
   local shadow=offset(blur(flood(node,sourceInput),node),node);P.composite(shadow,sourceInput);out=shadow
  elseif tag=='feoffset'then out=offset(sourceInput,node)
  elseif tag=='feflood'then out=flood(node)
  elseif tag=='femerge'then
   local merged=P.new(source.w,source.h);assert(#node.children<=16,'feMerge excede 16 entradas.')
   for _,child in ipairs(node.children)do assert(child.tag=='femergenode','feMerge aceita feMergeNode.');P.composite(merged,input(child.attrs['in']))end;out=merged
  elseif tag=='fecomposite'then
   local second=input(assert(node.attrs.in2,'feComposite exige in2.'));local op=node.attrs.operator or 'over'
   assert(op=='over'or op=='in'or op=='out'or op=='atop'or op=='xor'or op=='arithmetic','Operador feComposite não suportado.')
   out=P.new(source.w,source.h)
   local k1,k2,k3,k4=G.number(node.attrs.k1,0),G.number(node.attrs.k2,0),G.number(node.attrs.k3,0),G.number(node.attrs.k4,0)
   for i=0,source.w*source.h-1 do
    local p=i*16;local aa,ba=read(sourceInput.data,p+12),read(second.data,p+12);local fa,fb=1,1-aa
    if op=='in'then fa,fb=ba,0 elseif op=='out'then fa,fb=1-ba,0 elseif op=='atop'then fa,fb=ba,1-aa elseif op=='xor'then fa,fb=1-ba,1-aa end
    if op=='arithmetic'then
     for k=0,3 do local i1,i2=read(sourceInput.data,p+k*4),read(second.data,p+k*4);write(out.data,p+k*4,math.clamp(k1*i1*i2+k2*i1+k3*i2+k4,0,1))end
    else
     for k=0,3 do write(out.data,p+k*4,read(sourceInput.data,p+k*4)*fa+read(second.data,p+k*4)*fb)end
    end
   end
  elseif tag=='fecolormatrix'then
   local kind=(node.attrs.type or 'matrix'):lower();local mx
   if kind=='matrix'then mx=U.numbers(assert(node.attrs.values,'feColorMatrix type="matrix" exige values.'));assert(#mx==20,'feColorMatrix exige 20 valores.')
   elseif kind=='saturate'then
    local s=tonumber(node.attrs.values)or 1
    mx={0.213+0.787*s,0.715-0.715*s,0.072-0.072*s,0,0,0.213-0.213*s,0.715+0.285*s,0.072-0.072*s,0,0,0.213-0.213*s,0.715-0.715*s,0.072+0.928*s,0,0,0,0,0,1,0}
   elseif kind=='huerotate'then
    local angle=math.rad(tonumber(node.attrs.values)or 0);local cs,sn=math.cos(angle),math.sin(angle)
    mx={0.213+cs*0.787-sn*0.213,0.715-cs*0.715-sn*0.715,0.072-cs*0.072+sn*0.928,0,0,0.213-cs*0.213+sn*0.143,0.715+cs*0.285+sn*0.140,0.072-cs*0.072-sn*0.283,0,0,0.213-cs*0.213-sn*0.787,0.715-cs*0.715+sn*0.715,0.072+cs*0.928+sn*0.072,0,0,0,0,0,1,0}
   elseif kind=='luminancetoalpha'then mx={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0.2125,0.7154,0.0721,0,0}
   else error('feColorMatrix type não suportado: '..kind,0)end
   out=P.new(source.w,source.h)
   for i=0,source.w*source.h-1 do
    local p=i*16;local av=read(sourceInput.data,p+12)
    local r,g,b=read(sourceInput.data,p),read(sourceInput.data,p+4),read(sourceInput.data,p+8)
    if av>0 then r,g,b=r/av,g/av,b/av end
    local na=math.clamp(mx[16]*r+mx[17]*g+mx[18]*b+mx[19]*av+mx[20],0,1)
    write(out.data,p,math.clamp(mx[1]*r+mx[2]*g+mx[3]*b+mx[4]*av+mx[5],0,1)*na)
    write(out.data,p+4,math.clamp(mx[6]*r+mx[7]*g+mx[8]*b+mx[9]*av+mx[10],0,1)*na)
    write(out.data,p+8,math.clamp(mx[11]*r+mx[12]*g+mx[13]*b+mx[14]*av+mx[15],0,1)*na)
    write(out.data,p+12,na)
   end
  elseif tag=='feblend'then
   local second=input(assert(node.attrs.in2,'feBlend exige in2.'));local mode=(node.attrs.mode or 'normal'):lower()
   assert(F.BLEND_MODES[mode],'Modo feBlend não suportado: '..mode)
   out=P.new(source.w,source.h)
   for i=0,source.w*source.h-1 do
    local p=i*16;local as,ab=read(sourceInput.data,p+12),read(second.data,p+12)
    local sr,sg,sb=read(sourceInput.data,p),read(sourceInput.data,p+4),read(sourceInput.data,p+8)
    local br,bg,bb=read(second.data,p),read(second.data,p+4),read(second.data,p+8)
    if as>0 then sr,sg,sb=sr/as,sg/as,sb/as end
    if ab>0 then br,bg,bb=br/ab,bg/ab,bb/ab end
    local mr,mg,mb=sr,sg,sb
    if mode~='normal'and(as>0 or ab>0)then
     local mixed=P.blend(Color3.new(math.clamp(br,0,1),math.clamp(bg,0,1),math.clamp(bb,0,1)),Color3.new(math.clamp(sr,0,1),math.clamp(sg,0,1),math.clamp(sb,0,1)),mode)
     mr,mg,mb=mixed.R,mixed.G,mixed.B
    end
    write(out.data,p,math.clamp(sr*as*(1-ab)+br*ab*(1-as)+mr*as*ab,0,1))
    write(out.data,p+4,math.clamp(sg*as*(1-ab)+bg*ab*(1-as)+mg*as*ab,0,1))
    write(out.data,p+8,math.clamp(sb*as*(1-ab)+bb*ab*(1-as)+mb*as*ab,0,1))
    write(out.data,p+12,math.clamp(as+ab-as*ab,0,1))
   end
  elseif tag=='fecomponenttransfer'then
   local funcs={}
   for _,child in ipairs(node.children or{})do
    local key=child.tag:match('^fefunc([rgba])$');assert(key,'feComponentTransfer aceita feFuncR/G/B/A.')
    assert(not funcs[key],'feComponentTransfer repetiu feFunc'..key:upper()..'.');funcs[key]=child.attrs or{}
   end
   local function transfer(attrs,v)
    if not attrs then return v end
    local kind=(attrs.type or'identity'):lower()
    if kind=='identity'then return v end
    if kind=='linear'then return G.number(attrs.slope,1)*v+G.number(attrs.intercept,0)end
    if kind=='gamma'then return G.number(attrs.amplitude,1)*math.max(v,0)^G.number(attrs.exponent,1)+G.number(attrs.offset,0)end
    assert(kind=='table'or kind=='discrete','feComponentTransfer type não suportado: '..kind)
    local values=U.numbers(attrs.tablevalues or'');assert(#values<=128,'tableValues excede 128 entradas.')
    if #values==0 then return v end
    if #values==1 then return values[1]end
    v=math.clamp(v,0,1)
    if kind=='discrete'then return values[math.min(math.floor(v*#values),#values-1)+1]end
    local n=#values-1;local k=math.min(math.floor(v*n),n-1)
    return values[k+1]+(v*n-k)*(values[k+2]-values[k+1])
   end
   out=P.new(source.w,source.h)
   for i=0,source.w*source.h-1 do
    local p=i*16;local av=read(sourceInput.data,p+12)
    local r,g,b=read(sourceInput.data,p),read(sourceInput.data,p+4),read(sourceInput.data,p+8)
    if av>0 then r,g,b=r/av,g/av,b/av end
    local na=math.clamp(transfer(funcs.a,av),0,1)
    write(out.data,p,math.clamp(transfer(funcs.r,r),0,1)*na)
    write(out.data,p+4,math.clamp(transfer(funcs.g,g),0,1)*na)
    write(out.data,p+8,math.clamp(transfer(funcs.b,b),0,1)*na)
    write(out.data,p+12,na)
   end
  elseif tag=='femorphology'then
   local op=(node.attrs.operator or'erode'):lower();assert(op=='erode'or op=='dilate','Operador feMorphology não suportado: '..op)
   local ns=U.numbers(node.attrs.radius or'0');assert(#ns==1 or #ns==2,'feMorphology aceita um ou dois raios.')
   local radiusX,radiusY=ns[1],ns[2]or ns[1];assert(radiusX>=0 and radiusY>=0,'feMorphology não aceita raio negativo.')
   local px=math.floor(radiusX*scaleX+.5);local py=math.floor(radiusY*scaleY+.5)
   extent+=math.max(px,py);assert(extent<=budget,'feMorphology excede a margem segura.')
   if px<=0 and py<=0 then out=P.clone(sourceInput)else
    out=P.new(source.w,source.h);local erode=op=='erode'
    for y=0,source.h-1 do for x=0,source.w-1 do
     local r,g,b,av=erode and 1 or 0,erode and 1 or 0,erode and 1 or 0,erode and 1 or 0
     for oy=-py,py do for ox=-px,px do
      local sx2,sy2=x+ox,y+oy
      if sx2>=0 and sy2>=0 and sx2<source.w and sy2<source.h then
       local q=(sy2*source.w+sx2)*16
       local qr,qg,qb,qa=read(sourceInput.data,q),read(sourceInput.data,q+4),read(sourceInput.data,q+8),read(sourceInput.data,q+12)
       if erode then r,g,b,av=math.min(r,qr),math.min(g,qg),math.min(b,qb),math.min(av,qa)
       else r,g,b,av=math.max(r,qr),math.max(g,qg),math.max(b,qb),math.max(av,qa)end
      elseif erode then r,g,b,av=0,0,0,0 end
     end end
     local p=(y*source.w+x)*16;write(out.data,p,r);write(out.data,p+4,g);write(out.data,p+8,b);write(out.data,p+12,av)
    end;checkpoint(c,y)end
   end
  elseif tag=='feconvolvematrix'then
   local ns=U.numbers(node.attrs.order or'3');assert(#ns==1 or #ns==2,'feConvolveMatrix aceita um ou dois valores em order.')
   local ox,oy=math.floor(ns[1]),math.floor(ns[2]or ns[1])
   assert(ox>=1 and oy>=1 and ox<=9 and oy<=9,'order de feConvolveMatrix fica entre 1 e 9.')
   local kernel=U.numbers(assert(node.attrs.kernelmatrix,'feConvolveMatrix exige kernelMatrix.'))
   assert(#kernel==ox*oy,'kernelMatrix exige orderX*orderY valores.')
   local sum=0;for _,v in ipairs(kernel)do sum+=v end
   local divisor=node.attrs.divisor and G.number(node.attrs.divisor,1)or(sum~=0 and sum or 1)
   assert(divisor~=0,'divisor de feConvolveMatrix não pode ser zero.')
   local bias=G.number(node.attrs.bias,0)
   local tx=node.attrs.targetx and math.floor(G.number(node.attrs.targetx,0))or math.floor(ox/2)
   local ty=node.attrs.targety and math.floor(G.number(node.attrs.targety,0))or math.floor(oy/2)
   assert(tx>=0 and tx<ox and ty>=0 and ty<oy,'targetX/targetY fora do kernel.')
   local edge=(node.attrs.edgemode or'duplicate'):lower()
   assert(edge=='duplicate'or edge=='wrap'or edge=='none','edgeMode de feConvolveMatrix não suportado: '..edge)
   local preserve=(node.attrs.preservealpha or'false'):lower()
   assert(preserve=='true'or preserve=='false','preserveAlpha inválido.')
   if node.attrs.kernelunitlength then local ku=U.numbers(node.attrs.kernelunitlength);assert(#ku>=1 and ku[1]>0,'kernelUnitLength inválido.')end
   extent+=math.max(tx,ox-1-tx,ty,oy-1-ty);assert(extent<=budget,'feConvolveMatrix excede a margem segura.')
   local keep=preserve=='true'
   local function fetch(x,y)
    if edge=='wrap'then x=x%source.w;y=y%source.h
    elseif edge=='duplicate'then x=math.clamp(x,0,source.w-1);y=math.clamp(y,0,source.h-1)
    elseif x<0 or y<0 or x>=source.w or y>=source.h then return 0,0,0,0 end
    local q=(y*source.w+x)*16
    local r,g,b,av=read(sourceInput.data,q),read(sourceInput.data,q+4),read(sourceInput.data,q+8),read(sourceInput.data,q+12)
    if keep and av>0 then r,g,b=r/av,g/av,b/av end
    return r,g,b,av
   end
   out=P.new(source.w,source.h)
   for y=0,source.h-1 do for x=0,source.w-1 do
    local r,g,b,av=0,0,0,0
    for j=0,oy-1 do for i=0,ox-1 do
     local weight=kernel[(oy-j-1)*ox+(ox-i-1)+1]
     if weight~=0 then
      local sr,sg,sb,sa=fetch(x-tx+i,y-ty+j)
      r+=sr*weight;g+=sg*weight;b+=sb*weight;av+=sa*weight
     end
    end end
    local p=(y*source.w+x)*16
    if keep then
     local sa=select(4,fetch(x,y))
     write(out.data,p,math.clamp(r/divisor+bias,0,1)*sa);write(out.data,p+4,math.clamp(g/divisor+bias,0,1)*sa)
     write(out.data,p+8,math.clamp(b/divisor+bias,0,1)*sa);write(out.data,p+12,sa)
    else
     local na=math.clamp(av/divisor+bias,0,1)
     write(out.data,p,math.clamp(r/divisor+bias*na,0,na));write(out.data,p+4,math.clamp(g/divisor+bias*na,0,na))
     write(out.data,p+8,math.clamp(b/divisor+bias*na,0,na));write(out.data,p+12,na)
    end
   end;checkpoint(c,y)end
  elseif tag=='feturbulence'then
   local freq=U.numbers(node.attrs.basefrequency or'0');assert(#freq==1 or #freq==2,'baseFrequency aceita um ou dois números.')
   local fx,fy=freq[1],freq[2]or freq[1];assert(fx>=0 and fy>=0,'baseFrequency não aceita valores negativos.')
   local octaves=math.floor(G.number(node.attrs.numoctaves,1));assert(octaves>=0 and octaves<=6,'numOctaves aceita de 0 a 6.')
   local kind=(node.attrs.type or'turbulence'):lower();assert(kind=='turbulence'or kind=='fractalnoise','type de feTurbulence não suportado: '..kind)
   local mode=(node.attrs.stitchtiles or'nostitch'):lower();assert(mode=='nostitch'or mode=='stitch','stitchTiles inválido.')
   assert(toFilter,'feTurbulence exige uma matriz inversível.')
   out=P.new(source.w,source.h)
   if octaves>0 and(fx>0 or fy>0)then
    local area=rect and rectPixels(rect.x,rect.y,rect.w,rect.h,pm)or defaultRect
    local samples=math.max(area.x1-area.x0,0)*math.max(area.y1-area.y0,0)*octaves
    assert(samples<=262144,'feTurbulence excede o orçamento de amostras; reduza numOctaves, a subregião ou a resolução.')
    local stitch
    if mode=='stitch'then
     local tile=rect or {x=rx,y=ry,w=regionW,h=regionH}
     if fx>0 and tile.w>0 then
      local lo,hi=math.floor(tile.w*fx)/tile.w,math.ceil(tile.w*fx)/tile.w
      fx=(lo>0 and fx/lo<hi/fx)and lo or hi
     end
     if fy>0 and tile.h>0 then
      local lo,hi=math.floor(tile.h*fy)/tile.h,math.ceil(tile.h*fy)/tile.h
      fy=(lo>0 and fy/lo<hi/fy)and lo or hi
     end
     local width,height=math.floor(tile.w*fx+.5),math.floor(tile.h*fy+.5)
     stitch={width=width,height=height,wrapX=math.floor(tile.x*fx+PERLIN+width),wrapY=math.floor(tile.y*fy+PERLIN+height)}
    end
    local state=noiseState(G.number(node.attrs.seed,0))
    local fractal=kind=='fractalnoise'
    for y=area.y0,area.y1-1 do
     for x=area.x0,area.x1-1 do
      local ux,uy=G.at(toFilter,x+.5,y+.5)
      local cr=math.clamp(fractal and(turbulence(state,1,ux,uy,fx,fy,octaves,true,stitch)+1)/2 or turbulence(state,1,ux,uy,fx,fy,octaves,false,stitch),0,1)
      local cg=math.clamp(fractal and(turbulence(state,2,ux,uy,fx,fy,octaves,true,stitch)+1)/2 or turbulence(state,2,ux,uy,fx,fy,octaves,false,stitch),0,1)
      local cb=math.clamp(fractal and(turbulence(state,3,ux,uy,fx,fy,octaves,true,stitch)+1)/2 or turbulence(state,3,ux,uy,fx,fy,octaves,false,stitch),0,1)
      local ca=math.clamp(fractal and(turbulence(state,4,ux,uy,fx,fy,octaves,true,stitch)+1)/2 or turbulence(state,4,ux,uy,fx,fy,octaves,false,stitch),0,1)
      local p=(y*source.w+x)*16
      write(out.data,p,cr*ca);write(out.data,p+4,cg*ca);write(out.data,p+8,cb*ca);write(out.data,p+12,ca)
     end
     checkpoint(c,y)
    end
   end
  elseif tag=='fedisplacementmap'then
   local second=input(assert(node.attrs.in2,'feDisplacementMap exige in2.'))
   local channels={R=1,G=2,B=3,A=4}
   local xs=(node.attrs.xchannelselector or'A'):upper();local ys=(node.attrs.ychannelselector or'A'):upper()
   assert(channels[xs]and channels[ys],'Canal de feDisplacementMap inválido.')
   local scale=G.number(node.attrs.scale,0)
   local dsx,dsy=scale*scaleX,scale*scaleY
   extent+=math.ceil(math.max(math.abs(dsx),math.abs(dsy))/2);assert(extent<=budget,'feDisplacementMap excede a margem segura.')
   local xi,yi=channels[xs],channels[ys]
   local function pick(x,y,index)
    local color,av=P.get(second,x,y)
    if index==1 then return color.R elseif index==2 then return color.G elseif index==3 then return color.B end
    return av
   end
   local function texel(x,y)
    if x<0 or y<0 or x>=source.w or y>=source.h then return 0,0,0,0 end
    local q=(y*source.w+x)*16
    return read(sourceInput.data,q),read(sourceInput.data,q+4),read(sourceInput.data,q+8),read(sourceInput.data,q+12)
   end
   out=P.new(source.w,source.h)
   for y=0,source.h-1 do for x=0,source.w-1 do
    local fx2=x+dsx*(pick(x,y,xi)-.5)
    local fy2=y+dsy*(pick(x,y,yi)-.5)
    local x0,y0=math.floor(fx2),math.floor(fy2)
    local tx2,ty2=fx2-x0,fy2-y0
    local r,g,b,av=0,0,0,0
    for oy=0,1 do for ox=0,1 do
     local weight=(ox==0 and 1-tx2 or tx2)*(oy==0 and 1-ty2 or ty2)
     if weight>0 then
      local pr,pg,pb,pa=texel(x0+ox,y0+oy)
      r+=pr*weight;g+=pg*weight;b+=pb*weight;av+=pa*weight
     end
    end end
    local p=(y*source.w+x)*16;write(out.data,p,r);write(out.data,p+4,g);write(out.data,p+8,b);write(out.data,p+12,av)
   end;checkpoint(c,y)end
  elseif tag=='feimage'then
   local href=node.attrs.href or node.attrs['xlink:href'];assert(href,'feImage exige href.')
   local id=href:match('^%s*#([^%s]+)%s*$');assert(id,'feImage aceita apenas referências locais #id.')
   assert(env and env.defs and env.render,'feImage exige o documento SVG resolvido.')
   local target=assert(env.defs[id],'Referência de feImage não encontrada: #'..id)
   assert((env.shapes and env.shapes[target.tag])or target.tag=='g'or target.tag=='svg','feImage aceita apenas formas ou grupos: <'..target.tag..'>')
   local preserve=node.attrs.preserveaspectratio
   if preserve and preserve~='none'then
    local ax,ay,fit=preserve:match('^x(%a+)Y(%a+)%s*(%a*)$');local align={Min=true,Mid=true,Max=true}
    assert(align[ax]and align[ay]and(fit==''or fit=='meet'or fit=='slice'),'preserveAspectRatio de feImage inválido.')
   end
   local placed=rect and G.mul(pm,{1,0,0,1,rect.x,rect.y})or pm
   local rendered=env.render(target,placed)
   out=colorSpace=='linearRGB'and convert(rendered,true,c)or P.clone(rendered)
  elseif tag=='fetile'then
   local tile=regions[sourceInput]or defaultRect
   local dest=rect and rectPixels(rect.x,rect.y,rect.w,rect.h,pm)or defaultRect
   out=P.new(source.w,source.h)
   local tw,th=tile.x1-tile.x0,tile.y1-tile.y0
   if tw>0 and th>0 then
    for y=dest.y0,dest.y1-1 do
     for x=dest.x0,dest.x1-1 do
      local sx2,sy2=tile.x0+(x-tile.x0)%tw,tile.y0+(y-tile.y0)%th
      local q=(sy2*source.w+sx2)*16;local p=(y*source.w+x)*16
      write(out.data,p,read(sourceInput.data,q));write(out.data,p+4,read(sourceInput.data,q+4))
      write(out.data,p+8,read(sourceInput.data,q+8));write(out.data,p+12,read(sourceInput.data,q+12))
     end
     checkpoint(c,y)
    end
   end
  elseif tag=='fediffuselighting'or tag=='fespecularlighting'then
   assert(toFilter,'Iluminação SVG exige uma matriz inversível.')
   local light
   for _,child in ipairs(node.children or{})do
    if F.LIGHTS[child.tag]then assert(not light,'Primitiva de iluminação aceita apenas uma fonte de luz.');light=child
    else error('Filho de iluminação SVG não suportado: <'..child.tag..'>',0)end
   end
   assert(light,'feDiffuseLighting/feSpecularLighting exigem uma fonte de luz.')
   local specular=tag=='fespecularlighting'
   local surfaceScale=G.number(node.attrs.surfacescale,1)
   local kd=G.number(node.attrs.diffuseconstant,1);local ks=G.number(node.attrs.specularconstant,1)
   assert(kd>=0 and ks>=0,'Constantes de iluminação não aceitam valores negativos.')
   local exponent=G.number(node.attrs.specularexponent,1);assert(exponent>=1 and exponent<=128,'specularExponent fica entre 1 e 128.')
   local color=lightingColor(node)
   local zScale=math.max(math.sqrt(math.max(scaleX*scaleY,0)),1e-6)
   local la=light.attrs;local lightAt
   if light.tag=='fedistantlight'then
    local az,el=math.rad(G.number(la.azimuth,0)),math.rad(G.number(la.elevation,0))
    local lx,ly,lz=math.cos(az)*math.cos(el),math.sin(az)*math.cos(el),math.sin(el)
    lightAt=function()return lx,ly,lz,1 end
   else
    local lx,ly=G.at(device,G.number(la.x,0),G.number(la.y,0))
    local lz=G.number(la.z,0)*zScale
    local spot=light.tag=='fespotlight'
    local sx3,sy3,sz3,cone,falloff
    if spot then
     local ax,ay=G.at(device,G.number(la.pointsatx,0),G.number(la.pointsaty,0))
     sx3,sy3,sz3=ax-lx,ay-ly,G.number(la.pointsatz,0)*zScale-lz
     local len=math.sqrt(sx3*sx3+sy3*sy3+sz3*sz3)
     if len>0 then sx3,sy3,sz3=sx3/len,sy3/len,sz3/len end
     falloff=G.number(la.specularexponent,1)
     if la.limitingconeangle then cone=math.cos(math.rad(math.abs(G.number(la.limitingconeangle,0))))end
    end
    lightAt=function(x,y,z)
     local dx,dy,dz=lx-x,ly-y,lz-z
     local len=math.sqrt(dx*dx+dy*dy+dz*dz)
     if len<=0 then return 0,0,1,0 end
     dx,dy,dz=dx/len,dy/len,dz/len
     if not spot then return dx,dy,dz,1 end
     local dot=-(dx*sx3+dy*sy3+dz*sz3)
     if dot<=0 or(cone and dot<cone)then return dx,dy,dz,0 end
     return dx,dy,dz,dot^falloff
    end
   end
   local function alphaAt(x,y)
    x=math.clamp(x,0,source.w-1);y=math.clamp(y,0,source.h-1)
    return read(sourceInput.data,(y*source.w+x)*16+12)
   end
   out=P.new(source.w,source.h)
   for y=0,source.h-1 do for x=0,source.w-1 do
    local nx=-surfaceScale*((alphaAt(x+1,y-1)+2*alphaAt(x+1,y)+alphaAt(x+1,y+1))-(alphaAt(x-1,y-1)+2*alphaAt(x-1,y)+alphaAt(x-1,y+1)))/4
    local ny=-surfaceScale*((alphaAt(x-1,y+1)+2*alphaAt(x,y+1)+alphaAt(x+1,y+1))-(alphaAt(x-1,y-1)+2*alphaAt(x,y-1)+alphaAt(x+1,y-1)))/4
    local nlen=math.sqrt(nx*nx+ny*ny+1)
    local unx,uny,unz=nx/nlen,ny/nlen,1/nlen
    local lx2,ly2,lz2,attenuation=lightAt(x,y,surfaceScale*alphaAt(x,y))
    local p=(y*source.w+x)*16
    if specular then
     local hx,hy,hz=lx2,ly2,lz2+1
     local hlen=math.sqrt(hx*hx+hy*hy+hz*hz)
     local dot=hlen>0 and(unx*hx+uny*hy+unz*hz)/hlen or 0
     local factor=dot>0 and ks*dot^exponent*attenuation or 0
     local r=math.clamp(factor*color.R,0,1);local g=math.clamp(factor*color.G,0,1);local b=math.clamp(factor*color.B,0,1)
     write(out.data,p,r);write(out.data,p+4,g);write(out.data,p+8,b);write(out.data,p+12,math.max(r,g,b))
    else
     local factor=kd*math.max(unx*lx2+uny*ly2+unz*lz2,0)*attenuation
     write(out.data,p,math.clamp(factor*color.R,0,1));write(out.data,p+4,math.clamp(factor*color.G,0,1))
     write(out.data,p+8,math.clamp(factor*color.B,0,1));write(out.data,p+12,1)
    end
   end;checkpoint(c,y)end
  else error('Primitiva de filtro SVG não suportada: <'..tag..'>',0)end
  if rect then
   local coverage=G.coverage(G.rect(rect.x,rect.y,rect.w,rect.h),pm,'nonzero',c);P.mask(out,function(px,py)return coverage[py*c.w+px+1]end)
   regions[out]=rectPixels(rect.x,rect.y,rect.w,rect.h,pm)
  else regions[out]=defaultRect end
  local result=node.attrs.result
  if result then assert(result~='SourceGraphic'and result~='SourceAlpha'and #result<=80,'Nome result SVG inválido.');named[result]=out end
 end
 local cover=G.coverage(G.rect(rx,ry,regionW,regionH),rm,'nonzero',c);P.mask(out,function(px,py)return cover[py*c.w+px+1]end)
 return colorSpace=='linearRGB'and convert(out,false,c)or out
end
return F
