local Binary=require(script.Parent.FontBinary)
local O={VERSION=1}
O.limits={points=20000,components=32,depth=6,subrDepth=10,commands=40000,cache=512}
local function contourCommands(points,out)
 local count=#points
 if count==0 then return end
 local origin,sequence
 if points[1].on then
  origin={x=points[1].x,y=points[1].y}
  sequence={}
  for index=2,count do sequence[#sequence+1]=points[index] end
 elseif points[count].on then
  origin={x=points[count].x,y=points[count].y}
  sequence={}
  for index=1,count-1 do sequence[#sequence+1]=points[index] end
 else
  origin={x=(points[1].x+points[count].x)/2,y=(points[1].y+points[count].y)/2}
  sequence=points
 end
 out[#out+1]={kind='move',x=origin.x,y=origin.y}
 local control
 for _,point in ipairs(sequence) do
  if point.on then
   if control then out[#out+1]={kind='quad',cx=control.x,cy=control.y,x=point.x,y=point.y};control=nil
   else out[#out+1]={kind='line',x=point.x,y=point.y} end
  else
   if control then out[#out+1]={kind='quad',cx=control.x,cy=control.y,x=(control.x+point.x)/2,y=(control.y+point.y)/2} end
   control=point
  end
 end
 if control then out[#out+1]={kind='quad',cx=control.x,cy=control.y,x=origin.x,y=origin.y}
 else out[#out+1]={kind='line',x=origin.x,y=origin.y} end
 out[#out+1]={kind='close'}
end
local function transformCommands(commands,a,b,c,d,dx,dy,out)
 for _,command in ipairs(commands) do
  if command.kind=='close' then out[#out+1]={kind='close'}
  else
   local copy={kind=command.kind}
   copy.x=a*command.x+c*command.y+dx
   copy.y=b*command.x+d*command.y+dy
   if command.cx~=nil then
    copy.cx=a*command.cx+c*command.cy+dx
    copy.cy=b*command.cx+d*command.cy+dy
   end
   if command.c1x~=nil then
    copy.c1x=a*command.c1x+c*command.c1y+dx
    copy.c1y=b*command.c1x+d*command.c1y+dy
    copy.c2x=a*command.c2x+c*command.c2y+dx
    copy.c2y=b*command.c2x+d*command.c2y+dy
   end
   out[#out+1]=copy
  end
 end
end
local function simpleOutline(face,base,contours,out,deltas,glyphId)
 local font=face.font
 local endPoints=table.create(contours,0)
 for index=1,contours do endPoints[index]=Binary.u16(font,base+10+(index-1)*2) end
 local total=endPoints[contours]+1
 assert(total>0 and total<=O.limits.points,'Glifo com pontos demais.')
 local instructions=Binary.u16(font,base+10+contours*2)
 local cursor=base+12+contours*2+instructions
 local flags=table.create(total,0)
 local index=1
 while index<=total do
  local flag=Binary.u8(font,cursor);cursor+=1
  flags[index]=flag;index+=1
  if bit32.band(flag,8)~=0 then
   local repeats=Binary.u8(font,cursor);cursor+=1
   for _=1,repeats do
    assert(index<=total,'Repetição de flags além do total de pontos.')
    flags[index]=flag;index+=1
   end
  end
 end
 local xs=table.create(total,0)
 local value=0
 for point=1,total do
  local flag=flags[point]
  if bit32.band(flag,2)~=0 then
   local delta=Binary.u8(font,cursor);cursor+=1
   value+=bit32.band(flag,16)~=0 and delta or -delta
  elseif bit32.band(flag,16)==0 then
   value+=Binary.i16(font,cursor);cursor+=2
  end
  xs[point]=value
 end
 local ys=table.create(total,0)
 value=0
 for point=1,total do
  local flag=flags[point]
  if bit32.band(flag,4)~=0 then
   local delta=Binary.u8(font,cursor);cursor+=1
   value+=bit32.band(flag,32)~=0 and delta or -delta
  elseif bit32.band(flag,32)==0 then
   value+=Binary.i16(font,cursor);cursor+=2
  end
  ys[point]=value
 end
 if deltas then deltas(glyphId,xs,ys,total,endPoints) end
 local start=1
 for contour=1,contours do
  local last=endPoints[contour]+1
  assert(last>=start-1 and last<=total,'Contorno com índices inválidos.')
  local points={}
  for point=start,last do points[#points+1]={x=xs[point],y=ys[point],on=bit32.band(flags[point],1)~=0} end
  contourCommands(points,out)
  start=last+1
 end
 return total
end
local function glyfOutline(face,glyphId,out,options,depth)
 depth=depth or 0
 assert(depth<=O.limits.depth,'Glifo composto profundo demais.')
 local font=face.font
 if not face.loca then return {empty=true} end
 local glyf=Binary.locate(font,'glyf')
 if not glyf then return {empty=true} end
 local offset,length=face.loca(glyphId)
 if not offset or length<10 then return {empty=true} end
 local base=glyf+offset
 local contours=Binary.i16(font,base)
 local header={xMin=Binary.i16(font,base+2),yMin=Binary.i16(font,base+4),xMax=Binary.i16(font,base+6),yMax=Binary.i16(font,base+8)}
 if contours>=0 then
  local total=simpleOutline(face,base,contours,out,options and options.deltas,glyphId)
  return {header=header,points=total,composite=false}
 end
 local cursor=base+10
 local components=0
 local pointMatching=false
 local shifts=options and options.componentDeltas and options.componentDeltas(glyphId)
 while true do
  components+=1
  assert(components<=O.limits.components,'Glifo composto com componentes demais.')
  local flags=Binary.u16(font,cursor)
  local component=Binary.u16(font,cursor+2)
  cursor+=4
  local dx,dy=0,0
  if bit32.band(flags,1)~=0 then
   if bit32.band(flags,2)~=0 then dx=Binary.i16(font,cursor);dy=Binary.i16(font,cursor+2) else pointMatching=true end
   cursor+=4
  else
   if bit32.band(flags,2)~=0 then dx=Binary.i8(font,cursor);dy=Binary.i8(font,cursor+1) else pointMatching=true end
   cursor+=2
  end
  local a,b,c,d=1,0,0,1
  if bit32.band(flags,8)~=0 then a=Binary.f2dot14(font,cursor);d=a;cursor+=2
  elseif bit32.band(flags,64)~=0 then a=Binary.f2dot14(font,cursor);d=Binary.f2dot14(font,cursor+2);cursor+=4
  elseif bit32.band(flags,128)~=0 then
   a=Binary.f2dot14(font,cursor);b=Binary.f2dot14(font,cursor+2)
   c=Binary.f2dot14(font,cursor+4);d=Binary.f2dot14(font,cursor+6);cursor+=8
  end
  if bit32.band(flags,2048)~=0 then dx=dx*a;dy=dy*d end
  local shift=shifts and shifts[components]
  if shift then dx+=shift.x;dy+=shift.y end
  local child={}
  assert(component~=glyphId,'Glifo composto referencia a si mesmo.')
  glyfOutline(face,component,child,options,depth+1)
  transformCommands(child,a,b,c,d,dx,dy,out)
  if bit32.band(flags,32)==0 then break end
 end
 return {header=header,composite=true,components=components,pointMatching=pointMatching}
end
local function cffIndex(font,offset)
 local count=Binary.u16(font,offset)
 if count==0 then return {count=0,items={},last=offset+2} end
 local offSize=Binary.u8(font,offset+2)
 assert(offSize>=1 and offSize<=4,'INDEX CFF com offSize inválido.')
 assert(count<=65535,'INDEX CFF com itens demais.')
 local offsets=table.create(count+1,0)
 local base=offset+3
 for item=0,count do
  local value=0
  for byte=0,offSize-1 do value=value*256+Binary.u8(font,base+item*offSize+byte) end
  offsets[item+1]=value
 end
 local start=base+(count+1)*offSize-1
 local items=table.create(count,0)
 for item=1,count do
  local size=offsets[item+1]-offsets[item]
  assert(size>=0,'Item CFF com tamanho negativo.')
  items[item]={offset=start+offsets[item],length=size}
 end
 return {count=count,items=items,last=start+offsets[count+1]}
end
local function cffDict(font,offset,length)
 local result={}
 local operands={}
 local cursor=offset
 local limit=offset+length
 while cursor<limit do
  local lead=Binary.u8(font,cursor)
  if lead<=21 then
   local operator=lead
   cursor+=1
   if lead==12 then operator=1200+Binary.u8(font,cursor);cursor+=1 end
   result[operator]=operands
   operands={}
  elseif lead==28 then operands[#operands+1]=Binary.i16(font,cursor+1);cursor+=3
  elseif lead==29 then operands[#operands+1]=Binary.i32(font,cursor+1);cursor+=5
  elseif lead==30 then
   local text={}
   cursor+=1
   local finished=false
   while not finished do
    local byte=Binary.u8(font,cursor);cursor+=1
    local nibbles={math.floor(byte/16),byte%16}
    for _,nibble in ipairs(nibbles) do
     if nibble<=9 then text[#text+1]=tostring(nibble)
     elseif nibble==10 then text[#text+1]='.'
     elseif nibble==11 then text[#text+1]='E'
     elseif nibble==12 then text[#text+1]='E-'
     elseif nibble==14 then text[#text+1]='-'
     elseif nibble==15 then finished=true;break end
    end
    assert(cursor<limit+8,'Número real CFF sem terminador.')
   end
   operands[#operands+1]=tonumber(table.concat(text)) or 0
  elseif lead>=32 and lead<=246 then operands[#operands+1]=lead-139;cursor+=1
  elseif lead>=247 and lead<=250 then operands[#operands+1]=(lead-247)*256+Binary.u8(font,cursor+1)+108;cursor+=2
  elseif lead>=251 and lead<=254 then operands[#operands+1]=-(lead-251)*256-Binary.u8(font,cursor+1)-108;cursor+=2
  else error('Operando DICT CFF inválido.') end
  assert(#operands<=48,'DICT CFF com operandos demais.')
 end
 return result
end
local function privateFrom(font,offset,entry)
 local result={defaultWidthX=0,nominalWidthX=0}
 if not entry then return result end
 local size,at=entry[1],entry[2]
 if not size or not at then return result end
 local private=cffDict(font,offset+at,size)
 result.defaultWidthX=private[20] and private[20][1] or 0
 result.nominalWidthX=private[21] and private[21][1] or 0
 if private[19] then result.localSubrs=cffIndex(font,offset+at+private[19][1]) end
 return result
end
function O.cff(face)
 if face._cff then return face._cff end
 local font=face.font
 local offset=Binary.need(font,'CFF ')
 local headerSize=Binary.u8(font,offset+2)
 local names=cffIndex(font,offset+headerSize)
 local tops=cffIndex(font,names.last)
 local strings=cffIndex(font,tops.last)
 local globals=cffIndex(font,strings.last)
 assert(tops.count>=1,'CFF sem Top DICT.')
 local top=cffDict(font,tops.items[1].offset,tops.items[1].length)
 local charStringsOffset=top[17] and top[17][1]
 assert(charStringsOffset,'CFF sem CharStrings.')
 local charStrings=cffIndex(font,offset+charStringsOffset)
 assert(charStrings.count>0,'CharStrings CFF vazio.')
 local cff={offset=offset,charStrings=charStrings,globals=globals,strings=strings,top=top,cid=top[1230]~=nil}
 local private=privateFrom(font,offset,top[18])
 cff.defaultWidthX=private.defaultWidthX
 cff.nominalWidthX=private.nominalWidthX
 cff.localSubrs=private.localSubrs
 if cff.cid and top[1236] then
  local fdArray=cffIndex(font,offset+top[1236][1])
  cff.fonts={}
  for item=1,fdArray.count do
   local fd=cffDict(font,fdArray.items[item].offset,fdArray.items[item].length)
   cff.fonts[item]=privateFrom(font,offset,fd[18])
  end
  if top[1237] then cff.fdSelect=offset+top[1237][1] end
 end
 if top[1207] then
  local matrix=top[1207]
  cff.matrix={matrix[1] or 0.001,matrix[2] or 0,matrix[3] or 0,matrix[4] or 0.001,matrix[5] or 0,matrix[6] or 0}
 end
 face._cff=cff
 return cff
end
local function subrBias(index)
 local count=index and index.count or 0
 if count<1240 then return 107 elseif count<33900 then return 1131 end
 return 32768
end
local function fontDictIndex(font,cff,glyphId)
 if not cff.fdSelect then return nil end
 local format=Binary.u8(font,cff.fdSelect)
 if format==0 then return Binary.u8(font,cff.fdSelect+1+glyphId)+1 end
 if format==3 then
  local ranges=Binary.u16(font,cff.fdSelect+1)
  for range=0,ranges-1 do
   local first=Binary.u16(font,cff.fdSelect+3+range*3)
   local selected=Binary.u8(font,cff.fdSelect+3+range*3+2)
   local following=Binary.u16(font,cff.fdSelect+3+(range+1)*3)
   if glyphId>=first and glyphId<following then return selected+1 end
  end
 end
 return nil
end
local function cffOutline(face,glyphId,out)
 local font=face.font
 local cff=O.cff(face)
 assert(glyphId<cff.charStrings.count,'Glifo fora do CharStrings.')
 local locals=cff.localSubrs
 local defaultWidth,nominalWidth=cff.defaultWidthX,cff.nominalWidthX
 local selected=fontDictIndex(font,cff,glyphId)
 if selected and cff.fonts and cff.fonts[selected] then
  local entry=cff.fonts[selected]
  locals=entry.localSubrs
  defaultWidth=entry.defaultWidthX
  nominalWidth=entry.nominalWidthX
 end
 local state={x=0,y=0,stems=0,width=defaultWidth,haveWidth=false,open=false,seac=false,flexing=false,flex={}}
 local stack={}
 local localBias=subrBias(locals)
 local globalBias=subrBias(cff.globals)
 local function clear() table.clear(stack) end
 local function moveTo(x,y)
  if state.open then out[#out+1]={kind='close'} end
  out[#out+1]={kind='move',x=x,y=y}
  state.open=true
 end
 local function lineTo(x,y) out[#out+1]={kind='line',x=x,y=y} end
 local function curveTo(c1x,c1y,c2x,c2y,x,y) out[#out+1]={kind='cubic',c1x=c1x,c1y=c1y,c2x=c2x,c2y=c2y,x=x,y=y} end
 local function takeWidth(expected)
  if not state.haveWidth then
   if #stack>expected then
    state.width=nominalWidth+stack[1]
    table.remove(stack,1)
   end
   state.haveWidth=true
  end
 end
 local function takeStems()
  if not state.haveWidth and #stack%2==1 then
   state.width=nominalWidth+stack[1]
   table.remove(stack,1)
  end
  state.haveWidth=true
  state.stems+=#stack//2
  clear()
 end
 local execute
 execute=function(offset,length,depth)
  assert(depth<=O.limits.subrDepth,'Charstring CFF com recursão profunda.')
  local cursor=offset
  local limit=offset+length
  while cursor<limit do
   assert(#out<=O.limits.commands,'Charstring CFF com comandos demais.')
   local lead=Binary.u8(font,cursor);cursor+=1
   if lead>=32 or lead==28 then
    local value
    if lead==28 then value=Binary.i16(font,cursor);cursor+=2
    elseif lead<=246 then value=lead-139
    elseif lead<=250 then value=(lead-247)*256+Binary.u8(font,cursor)+108;cursor+=1
    elseif lead<=254 then value=-(lead-251)*256-Binary.u8(font,cursor)-108;cursor+=1
    else value=Binary.i32(font,cursor)/65536;cursor+=4 end
    assert(#stack<48,'Pilha de charstring CFF cheia.')
    stack[#stack+1]=value
   elseif lead==1 or lead==3 or lead==18 or lead==23 then takeStems()
   elseif lead==19 or lead==20 then
    takeStems()
    cursor+=math.max(1,math.ceil(state.stems/8))
   elseif lead==21 then
    takeWidth(2)
    state.x+=stack[1] or 0;state.y+=stack[2] or 0
    moveTo(state.x,state.y);clear()
   elseif lead==22 then
    takeWidth(1)
    state.x+=stack[1] or 0
    moveTo(state.x,state.y);clear()
   elseif lead==4 then
    takeWidth(1)
    state.y+=stack[1] or 0
    moveTo(state.x,state.y);clear()
   elseif lead==5 then
    local index=1
    while index+1<=#stack do
     state.x+=stack[index];state.y+=stack[index+1]
     lineTo(state.x,state.y);index+=2
    end
    clear()
   elseif lead==6 or lead==7 then
    local horizontal=lead==6
    for index=1,#stack do
     if horizontal then state.x+=stack[index] else state.y+=stack[index] end
     lineTo(state.x,state.y)
     horizontal=not horizontal
    end
    clear()
   elseif lead==8 then
    local index=1
    while index+5<=#stack do
     local c1x=state.x+stack[index];local c1y=state.y+stack[index+1]
     local c2x=c1x+stack[index+2];local c2y=c1y+stack[index+3]
     state.x=c2x+stack[index+4];state.y=c2y+stack[index+5]
     curveTo(c1x,c1y,c2x,c2y,state.x,state.y);index+=6
    end
    clear()
   elseif lead==24 then
    local index=1
    while #stack-index>=7 do
     local c1x=state.x+stack[index];local c1y=state.y+stack[index+1]
     local c2x=c1x+stack[index+2];local c2y=c1y+stack[index+3]
     state.x=c2x+stack[index+4];state.y=c2y+stack[index+5]
     curveTo(c1x,c1y,c2x,c2y,state.x,state.y);index+=6
    end
    state.x+=stack[index] or 0;state.y+=stack[index+1] or 0
    lineTo(state.x,state.y);clear()
   elseif lead==25 then
    local index=1
    while #stack-index>=7 do
     state.x+=stack[index];state.y+=stack[index+1]
     lineTo(state.x,state.y);index+=2
    end
    local c1x=state.x+(stack[index] or 0);local c1y=state.y+(stack[index+1] or 0)
    local c2x=c1x+(stack[index+2] or 0);local c2y=c1y+(stack[index+3] or 0)
    state.x=c2x+(stack[index+4] or 0);state.y=c2y+(stack[index+5] or 0)
    curveTo(c1x,c1y,c2x,c2y,state.x,state.y);clear()
   elseif lead==26 or lead==27 then
    local index=1
    local extra=0
    if #stack%4==1 then extra=stack[1];index=2 end
    while index+3<=#stack do
     local c1x,c1y
     if lead==26 then c1x=state.x+extra;c1y=state.y+stack[index]
     else c1x=state.x+stack[index];c1y=state.y+extra end
     local c2x=c1x+stack[index+1];local c2y=c1y+stack[index+2]
     if lead==26 then state.x=c2x;state.y=c2y+stack[index+3]
     else state.x=c2x+stack[index+3];state.y=c2y end
     curveTo(c1x,c1y,c2x,c2y,state.x,state.y)
     extra=0;index+=4
    end
    clear()
   elseif lead==30 or lead==31 then
    local horizontal=lead==31
    local index=1
    while index+3<=#stack do
     local c1x,c1y,c2x,c2y
     if horizontal then
      c1x=state.x+stack[index];c1y=state.y
      c2x=c1x+stack[index+1];c2y=c1y+stack[index+2]
      state.y=c2y+stack[index+3]
      state.x=c2x+((#stack-index==4) and stack[index+4] or 0)
     else
      c1x=state.x;c1y=state.y+stack[index]
      c2x=c1x+stack[index+1];c2y=c1y+stack[index+2]
      state.x=c2x+stack[index+3]
      state.y=c2y+((#stack-index==4) and stack[index+4] or 0)
     end
     curveTo(c1x,c1y,c2x,c2y,state.x,state.y)
     horizontal=not horizontal
     index+=4
    end
    clear()
   elseif lead==10 or lead==29 then
    local target=lead==10 and locals or cff.globals
    local bias=lead==10 and localBias or globalBias
    local reference=table.remove(stack)
    assert(type(reference)=='number','callsubr sem índice.')
    local position=reference+bias+1
    assert(target and position>=1 and position<=target.count,'Subrotina CFF inexistente.')
    local item=target.items[position]
    execute(item.offset,item.length,depth+1)
   elseif lead==11 then return
   elseif lead==14 then
    if #stack>=4 then state.seac=true end
    takeWidth(0)
    if state.open then out[#out+1]={kind='close'};state.open=false end
    clear()
    return
   elseif lead==12 then
    local second=Binary.u8(font,cursor);cursor+=1
    if second==35 then
     local c1x=state.x+stack[1];local c1y=state.y+stack[2]
     local c2x=c1x+stack[3];local c2y=c1y+stack[4]
     local jx=c2x+stack[5];local jy=c2y+stack[6]
     curveTo(c1x,c1y,c2x,c2y,jx,jy)
     local c3x=jx+stack[7];local c3y=jy+stack[8]
     local c4x=c3x+stack[9];local c4y=c3y+stack[10]
     state.x=c4x+stack[11];state.y=c4y+stack[12]
     curveTo(c3x,c3y,c4x,c4y,state.x,state.y)
     clear()
    elseif second==34 then
     local startY=state.y
     local c1x=state.x+stack[1];local c1y=startY
     local c2x=c1x+stack[2];local c2y=c1y+stack[3]
     local jx=c2x+stack[4];local jy=c2y
     curveTo(c1x,c1y,c2x,c2y,jx,jy)
     local c3x=jx+stack[5];local c3y=c2y
     local c4x=c3x+stack[6];local c4y=startY
     state.x=c4x+stack[7];state.y=startY
     curveTo(c3x,c3y,c4x,c4y,state.x,state.y)
     clear()
    elseif second==36 then
     local startY=state.y
     local c1x=state.x+stack[1];local c1y=state.y+stack[2]
     local c2x=c1x+stack[3];local c2y=c1y+stack[4]
     local jx=c2x+stack[5];local jy=c2y
     curveTo(c1x,c1y,c2x,c2y,jx,jy)
     local c3x=jx+stack[6];local c3y=c2y
     local c4x=c3x+stack[7];local c4y=c3y+stack[8]
     state.x=c4x+stack[9];state.y=startY
     curveTo(c3x,c3y,c4x,c4y,state.x,state.y)
     clear()
    elseif second==37 then
     local startX,startY=state.x,state.y
     local c1x=state.x+stack[1];local c1y=state.y+stack[2]
     local c2x=c1x+stack[3];local c2y=c1y+stack[4]
     local jx=c2x+stack[5];local jy=c2y+stack[6]
     curveTo(c1x,c1y,c2x,c2y,jx,jy)
     local c3x=jx+stack[7];local c3y=jy+stack[8]
     local c4x=c3x+stack[9];local c4y=c3y+stack[10]
     local dx=c4x-startX;local dy=c4y-startY
     if math.abs(dx+stack[11])>math.abs(dy) then state.x=c4x+stack[11];state.y=startY
     else state.x=startX;state.y=c4y+stack[11] end
     curveTo(c3x,c3y,c4x,c4y,state.x,state.y)
     clear()
    else clear() end
   else clear() end
  end
 end
 local item=cff.charStrings.items[glyphId+1]
 execute(item.offset,item.length,0)
 if state.open then out[#out+1]={kind='close'} end
 local scaled=false
 if cff.matrix and (math.abs(cff.matrix[1]-0.001)>1e-9 or math.abs(cff.matrix[4]-0.001)>1e-9) then
  local units=face.unitsPerEm
  local copy={}
  transformCommands(out,cff.matrix[1]*units,cff.matrix[2]*units,cff.matrix[3]*units,cff.matrix[4]*units,cff.matrix[5],cff.matrix[6],copy)
  table.clear(out)
  for index,command in ipairs(copy) do out[index]=command end
  scaled=true
 end
 return {width=state.width,seac=state.seac,cff=true,matrixApplied=scaled}
end
local function extremaQuad(p0,p1,p2,include)
 local denominator=p0-2*p1+p2
 if math.abs(denominator)>1e-9 then
  local t=(p0-p1)/denominator
  if t>0 and t<1 then
   local rest=1-t
   include(rest*rest*p0+2*rest*t*p1+t*t*p2)
  end
 end
end
local function extremaCubic(p0,p1,p2,p3,include)
 local a=-p0+3*p1-3*p2+p3
 local b=2*(p0-2*p1+p2)
 local c=p1-p0
 local function at(t)
  local rest=1-t
  return rest*rest*rest*p0+3*rest*rest*t*p1+3*rest*t*t*p2+t*t*t*p3
 end
 if math.abs(a)<1e-9 then
  if math.abs(b)>1e-9 then
   local t=-c/b
   if t>0 and t<1 then include(at(t)) end
  end
  return
 end
 local discriminant=b*b-4*a*c
 if discriminant<0 then return end
 local root=math.sqrt(discriminant)
 for _,t in ipairs({(-b+root)/(2*a),(-b-root)/(2*a)}) do
  if t>0 and t<1 then include(at(t)) end
 end
end
function O.bbox(commands)
 if #commands==0 then return nil end
 local xMin,yMin,xMax,yMax=math.huge,math.huge,-math.huge,-math.huge
 local function includeX(x) if x<xMin then xMin=x end;if x>xMax then xMax=x end end
 local function includeY(y) if y<yMin then yMin=y end;if y>yMax then yMax=y end end
 local x,y=0,0
 local any=false
 for _,command in ipairs(commands) do
  if command.kind=='move' or command.kind=='line' then
   includeX(command.x);includeY(command.y);x,y=command.x,command.y;any=true
  elseif command.kind=='quad' then
   includeX(command.x);includeY(command.y)
   extremaQuad(x,command.cx,command.x,includeX)
   extremaQuad(y,command.cy,command.y,includeY)
   x,y=command.x,command.y;any=true
  elseif command.kind=='cubic' then
   includeX(command.x);includeY(command.y)
   extremaCubic(x,command.c1x,command.c2x,command.x,includeX)
   extremaCubic(y,command.c1y,command.c2y,command.y,includeY)
   x,y=command.x,command.y;any=true
  end
 end
 if not any then return nil end
 return {xMin=xMin,yMin=yMin,xMax=xMax,yMax=yMax}
end
function O.outline(face,glyphId,options)
 options=options or face.outlineOptions or {}
 assert(type(glyphId)=='number' and glyphId>=0 and glyphId<face.numGlyphs,'Glifo fora da fonte.')
 local cacheKey=(options.deltas==nil or options.cacheable==true) and glyphId or nil
 face._outlineCache=face._outlineCache or {}
 face._outlineCount=face._outlineCount or 0
 if cacheKey~=nil then
  local cached=face._outlineCache[cacheKey]
  if cached then return cached end
 end
 local commands={}
 local info
 if face.flavor=='cff' then info=cffOutline(face,glyphId,commands)
 else info=glyfOutline(face,glyphId,commands,options,0) end
 local outline={
  glyph=glyphId,commands=commands,bbox=O.bbox(commands),
  advance=face.advance(glyphId),unitsPerEm=face.unitsPerEm,
  header=info and info.header or nil,composite=info and info.composite or false,
  pointMatching=info and info.pointMatching or false,
  charstringWidth=info and info.width or nil,seac=info and info.seac or false,
  empty=#commands==0,
 }
 if cacheKey~=nil then
  if face._outlineCount>=O.limits.cache then table.clear(face._outlineCache);face._outlineCount=0 end
  face._outlineCache[cacheKey]=outline
  face._outlineCount+=1
 end
 return outline
end
function O.box(face,glyphId)
 local ok,outline=pcall(O.outline,face,glyphId)
 if not ok then return nil end
 return outline.bbox
end
function O.scale(outline,size)
 local factor=size/outline.unitsPerEm
 local out=table.create(#outline.commands,nil)
 for index,command in ipairs(outline.commands) do
  if command.kind=='close' then out[index]={kind='close'}
  else
   local copy={kind=command.kind,x=command.x*factor,y=command.y*factor}
   if command.cx~=nil then copy.cx=command.cx*factor;copy.cy=command.cy*factor end
   if command.c1x~=nil then
    copy.c1x=command.c1x*factor;copy.c1y=command.c1y*factor
    copy.c2x=command.c2x*factor;copy.c2y=command.c2y*factor
   end
   out[index]=copy
  end
 end
 return {glyph=outline.glyph,commands=out,size=size,scale=factor,advance=outline.advance*factor}
end
function O.flatten(outline,tolerance)
 tolerance=tolerance or 0.25
 assert(tolerance>0,'Tolerância de achatamento deve ser positiva.')
 local contours={}
 local current
 local x,y=0,0
 local function push(px,py)
  if current then current[#current+1]={x=px,y=py} end
 end
 local function steps(distance)
  return math.clamp(math.ceil(math.sqrt(distance/tolerance)),1,64)
 end
 for _,command in ipairs(outline.commands) do
  if command.kind=='move' then
   current={{x=command.x,y=command.y}}
   contours[#contours+1]=current
   x,y=command.x,command.y
  elseif command.kind=='line' then
   push(command.x,command.y);x,y=command.x,command.y
  elseif command.kind=='quad' then
   local total=steps(math.abs(command.cx-x)+math.abs(command.cy-y)+math.abs(command.x-command.cx)+math.abs(command.y-command.cy))
   for step=1,total do
    local t=step/total
    local rest=1-t
    push(rest*rest*x+2*rest*t*command.cx+t*t*command.x,rest*rest*y+2*rest*t*command.cy+t*t*command.y)
   end
   x,y=command.x,command.y
  elseif command.kind=='cubic' then
   local total=steps(math.abs(command.c1x-x)+math.abs(command.c1y-y)+math.abs(command.c2x-command.c1x)+math.abs(command.c2y-command.c1y)+math.abs(command.x-command.c2x)+math.abs(command.y-command.c2y))
   for step=1,total do
    local t=step/total
    local rest=1-t
    push(rest*rest*rest*x+3*rest*rest*t*command.c1x+3*rest*t*t*command.c2x+t*t*t*command.x,rest*rest*rest*y+3*rest*rest*t*command.c1y+3*rest*t*t*command.c2y+t*t*t*command.y)
   end
   x,y=command.x,command.y
  end
 end
 return contours
end
return O
