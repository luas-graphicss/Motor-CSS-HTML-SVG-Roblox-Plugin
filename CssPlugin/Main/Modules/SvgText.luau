local Style=require(script.Parent.SvgStyle)
local Typo=require(script.Parent.Typography)
local Engine=require(script.Parent.FontEngine)
local X={VERSION='svg-text-1'}
X.limits={chars=2048,depth=8,points=160000,paths=1024}
X.containers={text=true,tspan=true,textpath=true}
local sizes={['xx-small']=9,['x-small']=10,small=13,medium=16,large=18,['x-large']=24,['xx-large']=32}
local function trim(value)return(tostring(value):gsub('^%s+',''):gsub('%s+$',''))end
local function fmt(value)return string.format('%.4f',value)end
local function num(value)
 local parsed=tonumber(value)
 if parsed==nil or parsed~=parsed then return nil end
 return parsed
end
function X.href(attrs)
 local value=attrs and(attrs.href or attrs['xlink:href'])
 if type(value)~='string'then return nil end
 return value:match('^#(.+)$')
end
function X.size(value,parent)
 parent=num(parent)or 16
 if value==nil then return parent end
 local direct=num(value)
 if direct then return direct end
 local text=trim(value):lower()
 if text==''then return parent end
 if sizes[text]then return sizes[text]end
 if text=='smaller'then return parent/1.2 end
 if text=='larger'then return parent*1.2 end
 local amount,unit=text:match('^(-?%d*%.?%d+)%s*(%a*%%?)$')
 local base=num(amount)
 assert(base,'font-size inválido em texto SVG: '..tostring(value))
 if unit==''or unit=='px'then return base end
 if unit=='pt'then return base*4/3 end
 if unit=='pc'then return base*16 end
 if unit=='in'then return base*96 end
 if unit=='cm'then return base*96/2.54 end
 if unit=='mm'then return base*96/25.4 end
 if unit=='q'then return base*96/101.6 end
 if unit=='em'then return base*parent end
 if unit=='rem'then return base*16 end
 if unit=='ex'or unit=='ch'then return base*parent/2 end
 if unit=='%'then return parent*base/100 end
 error('Unidade não suportada em font-size de texto SVG: '..tostring(value))
end
local function spacing(value,size)
 if value==nil then return 0 end
 local text=trim(value):lower()
 if text==''or text=='normal'then return 0 end
 local parsed=num(text)
 if parsed then return parsed end
 return X.size(text,size)
end
local function series(value,label)
 if value==nil then return nil end
 local out={}
 for token in tostring(value):gmatch('[^%s,]+')do
  local parsed=num(token)
  assert(parsed,'Atributo '..label..' de texto SVG exige números: '..tostring(value))
  out[#out+1]=parsed
 end
 if #out==0 then return nil end
 return out
end
local function baseline(value,px)
 local text=trim(value or'auto'):lower()
 local ascent=(px and px.ascent)or 0
 local descent=math.abs((px and px.descent)or 0)
 local xheight=(px and px.xHeight)or ascent/2
 if text=='middle'or text=='mathematical'then return xheight/2 end
 if text=='central'then return(ascent-descent)/2 end
 if text=='hanging'then return ascent*.8 end
 if text=='text-before-edge'or text=='top'then return ascent end
 if text=='text-after-edge'or text=='ideographic'or text=='bottom'then return-descent end
 return 0
end
local function faceOf(attrs,state)
 local key=tostring(attrs['font-family'])..'|'..tostring(attrs['font-weight'])..'|'..tostring(attrs['font-style'])
 local hit=state.faces[key]
 if hit==nil then
  local ok,face=pcall(Typo.face,attrs)
  hit={face=(ok and type(face)=='table')and face or nil}
  state.faces[key]=hit
 end
 return hit.face
end
local function metricsOf(face,size,state)
 local key=tostring(face.id)..'|'..fmt(size)
 local hit=state.metrics[key]
 if hit==nil then
  local ok,px=pcall(Engine.metrics,face,size)
  hit={px=(ok and type(px)=='table')and px or nil}
  state.metrics[key]=hit
 end
 return hit.px
end
local function glyphOf(face,char,state)
 local key=tostring(face.id)..'|'..char
 local hit=state.glyphs[key]
 if hit==nil then
  hit={}
  local ok,items=pcall(Engine.glyphs,face,char)
  if ok and type(items)=='table'and items[1]then hit.glyph=items[1].glyph;hit.advance=items[1].advance or 0 end
  state.glyphs[key]=hit
 end
 return hit.glyph,hit.advance or 0
end
local function contoursOf(face,glyph,size,tolerance,state)
 local key=tostring(face.id)..'|'..tostring(glyph)..'|'..fmt(size)..'|'..fmt(tolerance)
 local hit=state.outlines[key]
 if hit==nil then
  hit={}
  local ok,outline=pcall(Engine.outline,face,glyph,face.outlineOptions)
  if ok and type(outline)=='table'and not outline.empty then
   local scaled,sized=pcall(Engine.scaleOutline,outline,size)
   if scaled and type(sized)=='table'then
    local flat,list=pcall(Engine.flatten,sized,tolerance)
    if flat and type(list)=='table'then hit.contours=list end
   end
  end
  state.outlines[key]=hit
 end
 return hit.contours
end
local function pathAttrs(attrs,d)
 local out={d=d}
 for key in pairs(Style.properties)do
  local value=attrs[key]
  if value~=nil then out[key]=value end
 end
 return out
end
local function locate(segments,distance)
 local first=segments[1]
 if distance<=0 then return first.x,first.y,math.atan2(first.dy,first.dx)end
 for _,segment in ipairs(segments)do
  if distance<=segment.at+segment.len then
   local along=distance-segment.at
   return segment.x+segment.dx*along,segment.y+segment.dy*along,math.atan2(segment.dy,segment.dx)
  end
 end
 local last=segments[#segments]
 return last.x+last.dx*last.len,last.y+last.dy*last.len,math.atan2(last.dy,last.dx)
end
function X.plain(node)
 local parts={}
 local function walk(target,depth)
  if depth>X.limits.depth then return end
  if type(target.text)=='string'and target.text~=''then parts[#parts+1]=target.text end
  for _,child in ipairs(target.children or{})do
   if X.containers[child.tag]then walk(child,depth+1)end
  end
 end
 walk(node,1)
 local text=table.concat(parts):gsub('%s+',' ')
 return trim(text)
end
function X.build(node,ctx)
 ctx=ctx or{}
 local tolerance=math.max(num(ctx.tolerance)or .08,.01)
 local state={faces={},metrics={},glyphs={},outlines={},points=0}
 local items={}
 local groups={}
 local function walk(target,env,depth)
  if depth>X.limits.depth then return end
  local attrs=target.attrs or{}
  local raw=attrs['font-size']
  local size=(raw~=nil and env.raw~=nil and tostring(raw)==tostring(env.raw))and env.size or X.size(raw,env.size)
  local preserve=trim(attrs['xml:space']or env.preserve or'default'):lower()=='preserve'
  local record={node=target,attrs=attrs,size=size,start=#items,stop=#items,
   xs=series(attrs.x,'x'),ys=series(attrs.y,'y'),dxs=series(attrs.dx,'dx'),dys=series(attrs.dy,'dy'),rots=series(attrs.rotate,'rotate')}
  if target.tag=='textpath'then
   record.path=X.href(attrs)
   assert(record.path,'<textPath> exige href apontando para um caminho local.')
   record.offset=attrs.startoffset
  end
  local host=env.path or(record.path and record or nil)
  record.host=host
  groups[#groups+1]=record
  local function push(value)
   if value==nil then return end
   local raw=tostring(value)
   if raw==''then return end
   if preserve then raw=raw:gsub('[\t\n\r]',' ')else raw=raw:gsub('%s+',' ')end
   for _,code in utf8.codes(raw)do
    local char=utf8.char(code)
    local skip=(not preserve)and char==' 'and(#items==0 or items[#items].char==' ')
    if not skip then
     assert(#items<X.limits.chars,'Texto SVG acima de '..X.limits.chars..' caracteres.')
     items[#items+1]={char=char,record=record,size=size,host=host}
    end
   end
  end
  local content=target.content
  if type(content)=='table'then
   for _,piece in ipairs(content)do
    if type(piece)=='string'then push(piece)
    elseif type(piece)=='number'then
     local child=(target.children or{})[piece]
     if child and X.containers[child.tag]then walk(child,{size=size,raw=raw,preserve=preserve and'preserve'or nil,path=host},depth+1)end
    end
   end
  else
   push(target.text)
   for _,child in ipairs(target.children or{})do
    if X.containers[child.tag]then walk(child,{size=size,raw=raw,preserve=preserve and'preserve'or nil,path=host},depth+1)end
   end
  end
  record.stop=#items
 end
 walk(node,{size=num(ctx.size)or 16},1)
 while #items>0 and items[#items].char==' 'do table.remove(items)end
 if #items==0 then return nil,'texto vazio'end
 for _,record in ipairs(groups)do
  local limit=math.min(record.stop,#items)
  for index=record.start+1,limit do
   local item=items[index]
   local slot=index-record.start
   if record.xs and record.xs[slot]then item.x=record.xs[slot]end
   if record.ys and record.ys[slot]then item.y=record.ys[slot]end
   if record.dxs and record.dxs[slot]then item.dx=(item.dx or 0)+record.dxs[slot]end
   if record.dys and record.dys[slot]then item.dy=(item.dy or 0)+record.dys[slot]end
   if record.rots then item.rotate=record.rots[math.min(slot,#record.rots)]end
  end
 end
 for _,item in ipairs(items)do
  local attrs=item.record.attrs
  local face=faceOf(attrs,state)
  if not face then return nil,'sem fonte registrada para '..tostring(attrs['font-family'])end
  local px=metricsOf(face,item.size,state)
  if not px then return nil,'metricas indisponiveis para '..tostring(attrs['font-family'])end
  local glyph,advance=glyphOf(face,item.char,state)
  if glyph==nil then return nil,'glifo ausente na fonte'end
  local units=num(face.unitsPerEm)or 1000
  item.face=face
  item.glyph=glyph
  item.shift=baseline(attrs['dominant-baseline'],px)
  item.advance=advance*(item.size/units)+spacing(attrs['letter-spacing'],item.size)+(item.char==' 'and spacing(attrs['word-spacing'],item.size)or 0)
 end
 local penX,penY=0,0
 local chunks={}
 local start=nil
 for index,item in ipairs(items)do
  if item.host then
   if start then
    if index-1>=start then chunks[#chunks+1]={from=start,to=index-1}end
    start=nil
   end
  else
   if item.x~=nil or start==nil then
    if start and index-1>=start then chunks[#chunks+1]={from=start,to=index-1}end
    start=index
   end
   if item.x then penX=item.x end
   if item.y then penY=item.y end
   penX+=item.dx or 0
   penY+=item.dy or 0
   item.ox=penX
   item.oy=penY+item.shift
   item.angle=math.rad(item.rotate or 0)
   penX+=item.advance
  end
 end
 if start and #items>=start then chunks[#chunks+1]={from=start,to=#items}end
 for _,chunk in ipairs(chunks)do
  local first,last=items[chunk.from],items[chunk.to]
  if first and last and first.ox and last.ox then
   local width=last.ox+last.advance-first.ox
   local anchor=trim(first.record.attrs['text-anchor']or'start'):lower()
   local delta=anchor=='middle'and-width/2 or(anchor=='end'and-width or 0)
   if delta~=0 then
    for index=chunk.from,chunk.to do
     local item=items[index]
     if item.ox then item.ox+=delta end
    end
   end
  end
 end
 for _,record in ipairs(groups)do
  if record.path then
   local target=ctx.defs and ctx.defs[record.path]
   assert(target,'<textPath> aponta para id inexistente: #'..tostring(record.path))
   assert(type(ctx.polyline)=='function','<textPath> exige geometria do caminho referenciado.')
   local contours=ctx.polyline(target)
   local points=contours and contours[1]
   assert(type(points)=='table'and #points>=2,'<textPath> aponta para um caminho sem geometria utilizavel.')
   local segments={}
   local total=0
   for index=2,#points do
    local ax,ay=points[index-1].x,points[index-1].y
    local bx,by=points[index].x,points[index].y
    local dx,dy=bx-ax,by-ay
    local length=math.sqrt(dx*dx+dy*dy)
    if length>1e-9 then
     segments[#segments+1]={x=ax,y=ay,dx=dx/length,dy=dy/length,at=total,len=length}
     total+=length
    end
   end
   assert(total>0,'<textPath> aponta para um caminho sem comprimento.')
   local offset=0
   if record.offset~=nil then
    local text=trim(record.offset)
    if text:sub(-1)=='%'then offset=total*(num(text:sub(1,-2))or 0)/100 else offset=num(text)or 0 end
   end
   local limit=math.min(record.stop,#items)
   local width=0
   for index=record.start+1,limit do
    if items[index].host==record then width+=items[index].advance end
   end
   local anchor=trim(record.attrs['text-anchor']or'start'):lower()
   local cursor=offset+(anchor=='middle'and-width/2 or(anchor=='end'and-width or 0))
   for index=record.start+1,limit do
    local item=items[index]
    if item.host==record then
     cursor+=item.dx or 0
     local middle=cursor+item.advance/2
     if middle>=0 and middle<=total then
      local ox,oy=locate(segments,cursor)
      local _,_,angle=locate(segments,middle)
      local away=(item.dy or 0)+item.shift
      item.ox=ox-math.sin(angle)*away
      item.oy=oy+math.cos(angle)*away
      item.angle=angle+math.rad(item.rotate or 0)
     else
      item.hidden=true
     end
     cursor+=item.advance
    end
   end
  end
 end
 local out={}
 local pending,owner=nil,nil
 local function flush()
  if pending and #pending>0 then
   out[#out+1]={tag='path',attrs=pathAttrs(owner.attrs,table.concat(pending,' ')),children={}}
   assert(#out<=X.limits.paths,'Texto SVG acima do limite de subcaminhos.')
  end
  pending,owner=nil,nil
 end
 for _,item in ipairs(items)do
  if not item.hidden and item.ox~=nil and item.char~=' 'then
   if owner~=item.record then flush();pending={};owner=item.record end
   local contours=contoursOf(item.face,item.glyph,item.size,tolerance,state)
   if contours then
    local cos,sin=1,0
    if item.angle and item.angle~=0 then cos,sin=math.cos(item.angle),math.sin(item.angle)end
    for _,contour in ipairs(contours)do
     if #contour>=3 then
      state.points+=#contour
      assert(state.points<=X.limits.points,'Texto SVG acima do limite de pontos.')
      local parts=table.create(#contour+1)
      for position,point in ipairs(contour)do
       local gx,gy=point.x,-point.y
       parts[position]=(position==1 and'M'or'L')..fmt(item.ox+gx*cos-gy*sin)..' '..fmt(item.oy+gx*sin+gy*cos)
      end
      parts[#parts+1]='Z'
      pending[#pending+1]=table.concat(parts,' ')
     end
    end
   end
  end
 end
 flush()
 if #out==0 then return nil,'sem contornos de glifo'end
 return out,{chars=#items,paths=#out}
end
return X
