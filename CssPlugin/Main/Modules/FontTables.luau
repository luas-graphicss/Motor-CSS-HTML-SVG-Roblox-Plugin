local Binary=require(script.Parent.FontBinary)
local T={VERSION=1}
function T.head(font)
 local offset=Binary.need(font,'head')
 return {
  flags=Binary.u16(font,offset+16),
  unitsPerEm=Binary.u16(font,offset+18),
  xMin=Binary.i16(font,offset+36),yMin=Binary.i16(font,offset+38),
  xMax=Binary.i16(font,offset+40),yMax=Binary.i16(font,offset+42),
  macStyle=Binary.u16(font,offset+44),
  lowestRecPPEM=Binary.u16(font,offset+46),
  indexToLocFormat=Binary.i16(font,offset+50),
 }
end
function T.hhea(font)
 local offset=Binary.need(font,'hhea')
 return {
  ascender=Binary.i16(font,offset+4),descender=Binary.i16(font,offset+6),lineGap=Binary.i16(font,offset+8),
  advanceWidthMax=Binary.u16(font,offset+10),caretSlopeRise=Binary.i16(font,offset+18),caretSlopeRun=Binary.i16(font,offset+20),
  numberOfHMetrics=Binary.u16(font,offset+34),
 }
end
function T.maxp(font)
 local offset=Binary.need(font,'maxp')
 return {numGlyphs=Binary.u16(font,offset+4)}
end
function T.vhea(font)
 local offset,length=Binary.locate(font,'vhea')
 if not offset or length<36 then return nil end
 return {
  ascender=Binary.i16(font,offset+4),descender=Binary.i16(font,offset+6),lineGap=Binary.i16(font,offset+8),
  advanceHeightMax=Binary.i16(font,offset+10),numOfLongVerMetrics=Binary.u16(font,offset+34),
 }
end
function T.post(font)
 local offset,length=Binary.locate(font,'post')
 if not offset or length<16 then return nil end
 return {
  version=Binary.fixed(font,offset),italicAngle=Binary.fixed(font,offset+4),
  underlinePosition=Binary.i16(font,offset+8),underlineThickness=Binary.i16(font,offset+10),
  isFixedPitch=Binary.u32(font,offset+12),
 }
end
function T.os2(font)
 local offset,length=Binary.locate(font,'OS/2')
 if not offset or length<78 then return nil end
 local table2={
  version=Binary.u16(font,offset),xAvgCharWidth=Binary.i16(font,offset+2),
  usWeightClass=Binary.u16(font,offset+4),usWidthClass=Binary.u16(font,offset+6),
  ySubscriptXSize=Binary.i16(font,offset+10),ySubscriptYSize=Binary.i16(font,offset+12),
  ySubscriptXOffset=Binary.i16(font,offset+14),ySubscriptYOffset=Binary.i16(font,offset+16),
  ySuperscriptXSize=Binary.i16(font,offset+18),ySuperscriptYSize=Binary.i16(font,offset+20),
  ySuperscriptXOffset=Binary.i16(font,offset+22),ySuperscriptYOffset=Binary.i16(font,offset+24),
  yStrikeoutSize=Binary.i16(font,offset+26),yStrikeoutPosition=Binary.i16(font,offset+28),
  fsSelection=Binary.u16(font,offset+62),
  sTypoAscender=Binary.i16(font,offset+68),sTypoDescender=Binary.i16(font,offset+70),sTypoLineGap=Binary.i16(font,offset+72),
  usWinAscent=Binary.u16(font,offset+74),usWinDescent=Binary.u16(font,offset+76),
 }
 if table2.version>=2 and length>=96 then
  table2.sxHeight=Binary.i16(font,offset+86)
  table2.sCapHeight=Binary.i16(font,offset+88)
  table2.usDefaultChar=Binary.u16(font,offset+90)
  table2.usBreakChar=Binary.u16(font,offset+92)
  table2.usMaxContext=Binary.u16(font,offset+94)
 end
 if table2.version>=5 and length>=100 then
  table2.usLowerOpticalPointSize=Binary.u16(font,offset+96)/20
  table2.usUpperOpticalPointSize=Binary.u16(font,offset+98)/20
 end
 return table2
end
function T.hmtx(font,numGlyphs,numberOfHMetrics)
 local offset=Binary.need(font,'hmtx')
 assert(numberOfHMetrics>0 and numberOfHMetrics<=numGlyphs,'numberOfHMetrics inválido.')
 return function(glyphId)
  if type(glyphId)~='number' or glyphId<0 or glyphId>=numGlyphs then return 0,0 end
  if glyphId<numberOfHMetrics then return Binary.u16(font,offset+glyphId*4),Binary.i16(font,offset+glyphId*4+2) end
  local advance=Binary.u16(font,offset+(numberOfHMetrics-1)*4)
  local bearingAt=offset+numberOfHMetrics*4+(glyphId-numberOfHMetrics)*2
  local bearing=0
  if bearingAt+2<=font.size then bearing=Binary.i16(font,bearingAt) end
  return advance,bearing
 end
end
function T.vmtx(font,numGlyphs,numOfLongVerMetrics)
 local offset=Binary.locate(font,'vmtx')
 if not offset or not numOfLongVerMetrics or numOfLongVerMetrics<1 then return nil end
 local count=math.min(numOfLongVerMetrics,numGlyphs)
 return function(glyphId)
  if type(glyphId)~='number' or glyphId<0 or glyphId>=numGlyphs then return 0,0 end
  if glyphId<count then return Binary.u16(font,offset+glyphId*4),Binary.i16(font,offset+glyphId*4+2) end
  return Binary.u16(font,offset+(count-1)*4),0
 end
end
function T.loca(font,numGlyphs,format)
 local offset,length=Binary.locate(font,'loca')
 if not offset then return nil end
 local long=format==1
 local stride=long and 4 or 2
 assert(length>=(numGlyphs+1)*stride,'Tabela loca menor que numGlyphs.')
 return function(glyphId)
  if type(glyphId)~='number' or glyphId<0 or glyphId>=numGlyphs then return nil end
  local first,second
  if long then first=Binary.u32(font,offset+glyphId*4);second=Binary.u32(font,offset+glyphId*4+4)
  else first=Binary.u16(font,offset+glyphId*2)*2;second=Binary.u16(font,offset+glyphId*2+2)*2 end
  if second<=first then return first,0 end
  return first,second-first
 end
end
local function format0(font,offset)
 return function(codepoint)
  if codepoint>=0 and codepoint<=255 then return Binary.u8(font,offset+6+codepoint) end
  return 0
 end
end
local function format4(font,offset)
 local segments=Binary.u16(font,offset+6)//2
 assert(segments>0 and segments<=20000,'cmap formato 4 com segmentos inválidos.')
 local ends,starts,deltas,ranges=table.create(segments,0),table.create(segments,0),table.create(segments,0),table.create(segments,0)
 local endBase=offset+14
 local startBase=endBase+segments*2+2
 local deltaBase=startBase+segments*2
 local rangeBase=deltaBase+segments*2
 for i=1,segments do
  ends[i]=Binary.u16(font,endBase+(i-1)*2)
  starts[i]=Binary.u16(font,startBase+(i-1)*2)
  deltas[i]=Binary.i16(font,deltaBase+(i-1)*2)
  ranges[i]=Binary.u16(font,rangeBase+(i-1)*2)
 end
 return function(codepoint)
  if codepoint<0 or codepoint>65535 then return 0 end
  local low,high=1,segments
  while low<=high do
   local middle=(low+high)//2
   if codepoint>ends[middle] then low=middle+1
   elseif codepoint<starts[middle] then high=middle-1
   else
    local range=ranges[middle]
    if range==0 then return (codepoint+deltas[middle])%65536 end
    local glyph=Binary.u16(font,rangeBase+(middle-1)*2+range+(codepoint-starts[middle])*2)
    if glyph==0 then return 0 end
    return (glyph+deltas[middle])%65536
   end
  end
  return 0
 end
end
local function format6(font,offset)
 local first=Binary.u16(font,offset+6)
 local count=Binary.u16(font,offset+8)
 return function(codepoint)
  if codepoint>=first and codepoint<first+count then return Binary.u16(font,offset+10+(codepoint-first)*2) end
  return 0
 end
end
local function grouped(font,offset,constant)
 local groups=Binary.u32(font,offset+12)
 assert(groups<=400000,'cmap agrupado com grupos demais.')
 local base=offset+16
 return function(codepoint)
  local low,high=0,groups-1
  while low<=high do
   local middle=(low+high)//2
   local entry=base+middle*12
   local first=Binary.u32(font,entry)
   local last=Binary.u32(font,entry+4)
   if codepoint<first then high=middle-1
   elseif codepoint>last then low=middle+1
   else
    local start=Binary.u32(font,entry+8)
    if constant then return start end
    return start+codepoint-first
   end
  end
  return 0
 end
end
local function subtable(font,offset)
 local format=Binary.u16(font,offset)
 if format==0 then return format0(font,offset),0 end
 if format==4 then return format4(font,offset),4 end
 if format==6 then return format6(font,offset),6 end
 if format==12 then return grouped(font,offset,false),12 end
 if format==13 then return grouped(font,offset,true),13 end
 return nil,format
end
function T.cmap(font)
 local offset=Binary.locate(font,'cmap')
 if not offset then return {lookup=function() return 0 end,format=nil,platform=nil,symbol=false,missing=true} end
 local count=Binary.u16(font,offset+2)
 assert(count>0 and count<=64,'cmap com número de subtabelas inválido.')
 local best,bestScore,bestPlatform,bestEncoding
 for i=0,count-1 do
  local record=offset+4+i*8
  local platform=Binary.u16(font,record)
  local encoding=Binary.u16(font,record+2)
  local score=0
  if platform==3 and encoding==10 then score=6
  elseif platform==0 and (encoding==4 or encoding==6) then score=5
  elseif platform==3 and encoding==1 then score=4
  elseif platform==0 then score=3
  elseif platform==3 and encoding==0 then score=2
  elseif platform==1 and encoding==0 then score=1 end
  if score>0 and (not bestScore or score>bestScore) then
   local candidate=offset+Binary.u32(font,record+4)
   local lookup=subtable(font,candidate)
   if lookup then best=lookup;bestScore=score;bestPlatform=platform;bestEncoding=encoding end
  end
 end
 if not best then return {lookup=function() return 0 end,format=nil,platform=nil,symbol=false,missing=true} end
 local symbol=bestPlatform==3 and bestEncoding==0
 local lookup=best
 if symbol then
  lookup=function(codepoint)
   local glyph=best(codepoint)
   if glyph==0 then glyph=best(0xf000+codepoint) end
   return glyph
  end
 end
 return {lookup=lookup,platform=bestPlatform,encoding=bestEncoding,symbol=symbol,missing=false}
end
local function decodeName(font,offset,length,platform)
 if length<=0 then return '' end
 if platform==1 then return Binary.chunk(font,offset,length) end
 local units={}
 for i=0,length-2,2 do units[#units+1]=Binary.u16(font,offset+i) end
 local out={}
 local index=1
 while index<=#units do
  local unit=units[index]
  if unit>=0xd800 and unit<=0xdbff and units[index+1] and units[index+1]>=0xdc00 and units[index+1]<=0xdfff then
   out[#out+1]=utf8.char(0x10000+(unit-0xd800)*1024+(units[index+1]-0xdc00))
   index+=2
  else
   if unit>=0xd800 and unit<=0xdfff then out[#out+1]='?' else out[#out+1]=utf8.char(unit) end
   index+=1
  end
 end
 return table.concat(out)
end
function T.names(font)
 local offset,length=Binary.locate(font,'name')
 local result={}
 if not offset or length<6 then return result end
 local count=Binary.u16(font,offset+2)
 local storage=offset+Binary.u16(font,offset+4)
 assert(count<=1024,'Tabela name com registros demais.')
 local scores={}
 for i=0,count-1 do
  local record=offset+6+i*12
  local platform=Binary.u16(font,record)
  local encoding=Binary.u16(font,record+2)
  local language=Binary.u16(font,record+4)
  local nameId=Binary.u16(font,record+6)
  local size=Binary.u16(font,record+8)
  local at=storage+Binary.u16(font,record+10)
  local score=platform==3 and (language==0x409 and 4 or 3) or platform==0 and 2 or 1
  if at+size<=font.size and (not scores[nameId] or score>scores[nameId]) then
   local ok,text=pcall(decodeName,font,at,size,platform)
   if ok and text~='' then result[nameId]=text;scores[nameId]=score end
  end
 end
 return result
end
function T.glyphBox(face,glyphId)
 if not face.loca then return nil end
 local glyf=Binary.locate(face.font,'glyf')
 if not glyf then return nil end
 local offset,length=face.loca(glyphId)
 if not offset or length<10 then return nil end
 local base=glyf+offset
 return {
  contours=Binary.i16(face.font,base),
  xMin=Binary.i16(face.font,base+2),yMin=Binary.i16(face.font,base+4),
  xMax=Binary.i16(face.font,base+6),yMax=Binary.i16(face.font,base+8),
 }
end
function T.glyph(face,codepoint)
 local cached=face._glyphCache[codepoint]
 if cached~=nil then return cached end
 local glyph=face.cmap.lookup(codepoint) or 0
 if glyph>=face.numGlyphs then glyph=0 end
 if face._glyphCacheCount>=4096 then table.clear(face._glyphCache);face._glyphCacheCount=0 end
 face._glyphCache[codepoint]=glyph;face._glyphCacheCount+=1
 return glyph
end
local function inkTop(face,codepoint)
 local glyph=T.glyph(face,codepoint)
 if glyph==0 then return nil end
 local box=face.inkBox and face.inkBox(glyph) or T.glyphBox(face,glyph)
 if not box or box.yMax==nil or box.yMax<=0 then return nil end
 return box.yMax
end
function T.metrics(face)
 local units=face.unitsPerEm
 assert(units>=16 and units<=16384,'unitsPerEm fora da faixa suportada.')
 local os2=face.os2
 local hhea=face.hhea
 local useTypo=os2~=nil and bit32.band(os2.fsSelection,128)~=0 and os2.sTypoAscender~=0
 local ascent=useTypo and os2.sTypoAscender or hhea.ascender
 local descent=useTypo and os2.sTypoDescender or hhea.descender
 local lineGap=useTypo and os2.sTypoLineGap or hhea.lineGap
 if ascent==0 and os2 and os2.usWinAscent>0 then ascent=os2.usWinAscent;descent=-os2.usWinDescent;lineGap=0 end
 assert(ascent>descent,'Métricas verticais inconsistentes na fonte.')
 local xHeight,xSource
 if os2 and os2.sxHeight and os2.sxHeight>0 then xHeight=os2.sxHeight;xSource='os2'
 else
  xHeight=inkTop(face,0x78)
  xSource=xHeight and 'ink' or 'fallback'
  xHeight=xHeight or units*0.5
 end
 local capHeight,capSource
 if os2 and os2.sCapHeight and os2.sCapHeight>0 then capHeight=os2.sCapHeight;capSource='os2'
 else
  capHeight=inkTop(face,0x48)
  capSource=capHeight and 'ink' or 'fallback'
  capHeight=capHeight or units*0.7
 end
 local zero=T.glyph(face,0x30)
 local water=T.glyph(face,0x6c34)
 local space=T.glyph(face,0x20)
 local chWidth=zero~=0 and face.advance(zero) or units*0.5
 local icWidth=water~=0 and face.advance(water) or units
 local spaceWidth=space~=0 and face.advance(space) or units*0.25
 local post=face.post
 return {
  unitsPerEm=units,
  ascent=ascent,descent=descent,lineGap=lineGap,
  winAscent=os2 and os2.usWinAscent or ascent,winDescent=os2 and os2.usWinDescent or -descent,
  hheaAscent=hhea.ascender,hheaDescent=hhea.descender,hheaLineGap=hhea.lineGap,
  xHeight=xHeight,xHeightSource=xSource,
  capHeight=capHeight,capHeightSource=capSource,
  chWidth=chWidth,chKnown=zero~=0,
  icWidth=icWidth,icKnown=water~=0,
  spaceWidth=spaceWidth,
  underlinePosition=post and post.underlinePosition or -units*0.1,
  underlineThickness=post and post.underlineThickness~=0 and post.underlineThickness or units*0.05,
  strikeoutPosition=os2 and os2.yStrikeoutPosition~=0 and os2.yStrikeoutPosition or math.floor(xHeight/2),
  strikeoutSize=os2 and os2.yStrikeoutSize~=0 and os2.yStrikeoutSize or units*0.05,
  subscriptSize=os2 and os2.ySubscriptYSize~=0 and os2.ySubscriptYSize or units*0.65,
  subscriptOffset=os2 and os2.ySubscriptYOffset~=0 and os2.ySubscriptYOffset or math.floor(units*0.2),
  superscriptSize=os2 and os2.ySuperscriptYSize~=0 and os2.ySuperscriptYSize or units*0.65,
  superscriptOffset=os2 and os2.ySuperscriptYOffset~=0 and os2.ySuperscriptYOffset or math.floor(units*0.34),
  italicAngle=post and post.italicAngle or 0,
  monospace=post~=nil and post.isFixedPitch~=0,
  weightClass=os2 and os2.usWeightClass or 400,
  widthClass=os2 and os2.usWidthClass or 5,
  advanceMax=hhea.advanceWidthMax,
  verticalAscent=face.vhea and face.vhea.ascender or math.floor(units/2),
  verticalDescent=face.vhea and face.vhea.descender or -math.floor(units/2),
  bbox={xMin=face.head.xMin,yMin=face.head.yMin,xMax=face.head.xMax,yMax=face.head.yMax},
  numGlyphs=face.numGlyphs,
  measured=true,
 }
end
function T.px(face,size)
 assert(type(size)=='number' and size>0 and size<=4096,'Tamanho de fonte inválido.')
 local metrics=face.metrics
 local scale=size/metrics.unitsPerEm
 return {
  scale=scale,size=size,
  ascent=metrics.ascent*scale,descent=metrics.descent*scale,lineGap=metrics.lineGap*scale,
  lineHeight=(metrics.ascent-metrics.descent+metrics.lineGap)*scale,
  xHeight=metrics.xHeight*scale,capHeight=metrics.capHeight*scale,
  ch=metrics.chWidth*scale,ic=metrics.icWidth*scale,space=metrics.spaceWidth*scale,
  underlinePosition=metrics.underlinePosition*scale,underlineThickness=metrics.underlineThickness*scale,
  strikeoutPosition=metrics.strikeoutPosition*scale,strikeoutSize=metrics.strikeoutSize*scale,
  subscriptSize=metrics.subscriptSize*scale,subscriptOffset=metrics.subscriptOffset*scale,
  superscriptSize=metrics.superscriptSize*scale,superscriptOffset=metrics.superscriptOffset*scale,
  exRatio=metrics.xHeight/metrics.unitsPerEm,capRatio=metrics.capHeight/metrics.unitsPerEm,
  xHeightSource=metrics.xHeightSource,capHeightSource=metrics.capHeightSource,
 }
end
function T.refresh(face)
 face.metrics=T.metrics(face)
 return face
end
function T.face(font)
 local head=T.head(font)
 local hhea=T.hhea(font)
 local maxp=T.maxp(font)
 local face={
  font=font,flavor=font.flavor,fingerprint=font.fingerprint,
  head=head,hhea=hhea,os2=T.os2(font),post=T.post(font),vhea=T.vhea(font),
  numGlyphs=maxp.numGlyphs,unitsPerEm=head.unitsPerEm,
  _glyphCache={},_glyphCacheCount=0,
 }
 assert(face.numGlyphs>0 and face.numGlyphs<=65535,'numGlyphs inválido.')
 face.advance=T.hmtx(font,face.numGlyphs,hhea.numberOfHMetrics)
 face.verticalAdvance=face.vhea and T.vmtx(font,face.numGlyphs,face.vhea.numOfLongVerMetrics) or nil
 face.loca=T.loca(font,face.numGlyphs,head.indexToLocFormat)
 face.cmap=T.cmap(font)
 face.names=T.names(font)
 face.family=face.names[16] or face.names[1] or 'Fonte sem nome'
 face.subfamily=face.names[17] or face.names[2] or 'Regular'
 face.postscriptName=face.names[6]
 face.metrics=T.metrics(face)
 return face
end
return T
