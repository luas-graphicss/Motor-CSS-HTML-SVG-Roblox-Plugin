local Binary=require(script.Parent.FontBinary)
local V={VERSION=1}
V.limits={axes=32,instances=256,regions=4096,points=20000,tuples=1024,records=512,components=64,cache=2048}
V.metricFields={hasc='ascent',hdsc='descent',hlgp='lineGap',hcla='winAscent',hcld='winDescent',xhgt='xHeight',cpht='capHeight',undo='underlinePosition',unds='underlineThickness',stro='strikeoutPosition',strs='strikeoutSize',sbys='subscriptSize',sbyo='subscriptOffset',spys='superscriptSize',spyo='superscriptOffset'}
local function segmentMap(map,value)
 if not map or #map<2 then return value end
 if value<=map[1].from then return map[1].to end
 for index=2,#map do
  local previous=map[index-1]
  local point=map[index]
  if value<=point.from then
   if point.from<=previous.from then return point.to end
   return previous.to+(point.to-previous.to)*(value-previous.from)/(point.from-previous.from)
  end
 end
 return map[#map].to
end
function V.fvar(font)
 local offset,length=Binary.locate(font,'fvar')
 if not offset or length<16 then return nil end
 local axesOffset=offset+Binary.u16(font,offset+4)
 local axisCount=Binary.u16(font,offset+8)
 local axisSize=Binary.u16(font,offset+10)
 local instanceCount=Binary.u16(font,offset+12)
 local instanceSize=Binary.u16(font,offset+14)
 assert(axisCount>=1 and axisCount<=V.limits.axes,'fvar com contagem de eixos invalida.')
 assert(axisSize>=20,'fvar com axisSize invalido.')
 local axes=table.create(axisCount)
 local byTag={}
 for index=0,axisCount-1 do
  local at=axesOffset+index*axisSize
  local axis={index=index+1,tag=Binary.tag(font,at),minimum=Binary.fixed(font,at+4),default=Binary.fixed(font,at+8),maximum=Binary.fixed(font,at+12),flags=Binary.u16(font,at+16),nameId=Binary.u16(font,at+18)}
  assert(axis.minimum<=axis.default and axis.default<=axis.maximum,'Eixo '..axis.tag..' com faixa invalida.')
  axis.hidden=bit32.band(axis.flags,1)~=0
  axes[index+1]=axis
  byTag[axis.tag]=axis
 end
 local instances={}
 if instanceCount>0 and instanceSize>=axisCount*4+4 then
  assert(instanceCount<=V.limits.instances,'fvar com instancias demais.')
  local base=axesOffset+axisCount*axisSize
  for index=0,instanceCount-1 do
   local at=base+index*instanceSize
   local coordinates={}
   for axis=1,axisCount do coordinates[axes[axis].tag]=Binary.fixed(font,at+4+(axis-1)*4) end
   local entry={nameId=Binary.u16(font,at),flags=Binary.u16(font,at+2),coordinates=coordinates}
   if instanceSize>=axisCount*4+6 then entry.postScriptNameId=Binary.u16(font,at+4+axisCount*4) end
   instances[index+1]=entry
  end
 end
 return {axes=axes,byTag=byTag,count=axisCount,instances=instances}
end
function V.avar(font,axisCount)
 local offset,length=Binary.locate(font,'avar')
 if not offset or length<8 then return nil end
 local count=Binary.u16(font,offset+6)
 if count<1 then return nil end
 local maps={}
 local cursor=offset+8
 for axis=1,count do
  local total=Binary.u16(font,cursor);cursor+=2
  assert(total<=V.limits.regions,'avar com segmentos demais.')
  local list=table.create(total)
  for item=1,total do
   list[item]={from=Binary.f2dot14(font,cursor),to=Binary.f2dot14(font,cursor+2)}
   cursor+=4
  end
  if axis<=axisCount then maps[axis]=list end
 end
 return maps
end
function V.resolve(fvar,coordinates)
 local out={}
 for _,axis in ipairs(fvar.axes) do out[axis.tag]=axis.default end
 if type(coordinates)=='table' then
  for tag,value in pairs(coordinates) do
   local axis=fvar.byTag[tag]
   if axis then
    assert(type(value)=='number' and value==value,'Eixo '..tag..' exige numero.')
    out[tag]=math.clamp(value,axis.minimum,axis.maximum)
   end
  end
 end
 return out
end
function V.normalize(fvar,avar,user)
 local out=table.create(fvar.count,0)
 for index,axis in ipairs(fvar.axes) do
  local value=user[axis.tag]
  if type(value)~='number' then value=axis.default end
  value=math.clamp(value,axis.minimum,axis.maximum)
  local normalized=0
  if value<axis.default then normalized=-(axis.default-value)/math.max(1e-9,axis.default-axis.minimum)
  elseif value>axis.default then normalized=(value-axis.default)/math.max(1e-9,axis.maximum-axis.default) end
  normalized=math.clamp(normalized,-1,1)
  out[index]=math.clamp(segmentMap(avar and avar[index],normalized),-1,1)
 end
 return out
end
function V.key(fvar,user)
 local parts={}
 for _,axis in ipairs(fvar.axes) do parts[#parts+1]=axis.tag..string.format('%.4f',user[axis.tag] or axis.default) end
 return table.concat(parts,'/')
end
local function regionList(font,offset)
 local axisCount=Binary.u16(font,offset)
 local regionCount=Binary.u16(font,offset+2)
 assert(regionCount<=V.limits.regions,'ItemVariationStore com regioes demais.')
 local regions=table.create(regionCount)
 for index=0,regionCount-1 do
  local base=offset+4+index*axisCount*6
  local axes=table.create(axisCount)
  for axis=0,axisCount-1 do
   local at=base+axis*6
   axes[axis+1]={low=Binary.f2dot14(font,at),peak=Binary.f2dot14(font,at+2),high=Binary.f2dot14(font,at+4)}
  end
  regions[index+1]=axes
 end
 return {axisCount=axisCount,regions=regions}
end
function V.store(font,offset)
 local format=Binary.u16(font,offset)
 assert(format==1,'ItemVariationStore com formato nao suportado: '..format..'.')
 local list=regionList(font,offset+Binary.u32(font,offset+2))
 local count=Binary.u16(font,offset+6)
 assert(count<=V.limits.records,'ItemVariationStore com subtabelas demais.')
 local datas=table.create(count)
 for index=0,count-1 do
  local at=offset+Binary.u32(font,offset+8+index*4)
  local itemCount=Binary.u16(font,at)
  local wordField=Binary.u16(font,at+2)
  local regionCount=Binary.u16(font,at+4)
  assert(regionCount<=#list.regions,'ItemVariationData com regioes invalidas.')
  local long=bit32.band(wordField,0x8000)~=0
  local words=bit32.band(wordField,0x7fff)
  assert(words<=regionCount,'ItemVariationData com wordDeltaCount invalido.')
  local indexes=table.create(regionCount)
  for slot=0,regionCount-1 do indexes[slot+1]=Binary.u16(font,at+6+slot*2)+1 end
  local wide=long and 4 or 2
  local narrow=long and 2 or 1
  datas[index+1]={itemCount=itemCount,words=words,long=long,regions=indexes,rowSize=words*wide+(regionCount-words)*narrow,base=at+6+regionCount*2}
 end
 return {font=font,list=list,datas=datas}
end
function V.scalars(store,coordinates)
 local out=table.create(#store.list.regions,0)
 for index,axes in ipairs(store.list.regions) do
  local factor=1
  for axis,region in ipairs(axes) do
   local peak=region.peak
   if peak~=0 then
    local coord=coordinates[axis] or 0
    if coord~=peak then
     if coord<=region.low or coord>=region.high then factor=0;break end
     if coord<peak then factor*=(coord-region.low)/(peak-region.low)
     else factor*=(region.high-coord)/(region.high-peak) end
    end
   end
  end
  out[index]=factor
 end
 return out
end
local function storeDelta(store,scalars,outer,inner)
 local data=store.datas[outer+1]
 if not data or inner<0 or inner>=data.itemCount then return 0 end
 local font=store.font
 local row=data.base+inner*data.rowSize
 local wide=data.long and 4 or 2
 local narrow=data.long and 2 or 1
 local total=0
 for slot=1,#data.regions do
  local scalar=scalars[data.regions[slot]] or 0
  if scalar~=0 then
   local value
   if slot<=data.words then
    if data.long then value=Binary.i32(font,row+(slot-1)*wide) else value=Binary.i16(font,row+(slot-1)*wide) end
   else
    local at=row+data.words*wide+(slot-1-data.words)*narrow
    if data.long then value=Binary.i16(font,at) else value=Binary.i8(font,at) end
   end
   total+=scalar*value
  end
 end
 return total
end
V.delta=storeDelta
local function indexMap(font,offset)
 local format=Binary.u8(font,offset)
 local entryFormat=Binary.u8(font,offset+1)
 local count,base
 if format==0 then count=Binary.u16(font,offset+2);base=offset+4
 elseif format==1 then count=Binary.u32(font,offset+2);base=offset+6
 else error('DeltaSetIndexMap com formato '..format..'.') end
 local entrySize=bit32.band(entryFormat,0x0f)+1
 local innerBits=bit32.rshift(bit32.band(entryFormat,0x30),4)+1
 assert(entrySize>=1 and entrySize<=4,'DeltaSetIndexMap com entrySize invalido.')
 local mask=bit32.lshift(1,innerBits)-1
 return function(glyphId)
  if count==0 then return 0,glyphId end
  local index=math.min(glyphId,count-1)
  local at=base+index*entrySize
  local value=0
  for byte=0,entrySize-1 do value=value*256+Binary.u8(font,at+byte) end
  return math.floor(value/(mask+1)),bit32.band(value,mask)
 end
end
local function advanceTable(font,tag)
 local offset,length=Binary.locate(font,tag)
 if not offset or length<20 then return nil end
 local store=V.store(font,offset+Binary.u32(font,offset+4))
 local mapOffset=Binary.u32(font,offset+8)
 return {store=store,advance=mapOffset~=0 and indexMap(font,offset+mapOffset) or nil}
end
function V.hvar(font) return advanceTable(font,'HVAR') end
function V.vvar(font) return advanceTable(font,'VVAR') end
function V.mvar(font)
 local offset,length=Binary.locate(font,'MVAR')
 if not offset or length<12 then return nil end
 local recordSize=Binary.u16(font,offset+6)
 local recordCount=Binary.u16(font,offset+8)
 local storeOffset=Binary.u16(font,offset+10)
 if recordCount==0 or storeOffset==0 then return nil end
 assert(recordSize>=8 and recordCount<=V.limits.records,'MVAR com registros invalidos.')
 local records={}
 for index=0,recordCount-1 do
  local at=offset+12+index*recordSize
  records[Binary.tag(font,at)]={outer=Binary.u16(font,at+4),inner=Binary.u16(font,at+6)}
 end
 return {store=V.store(font,offset+storeOffset),records=records}
end
function V.gvar(font)
 local offset,length=Binary.locate(font,'gvar')
 if not offset or length<20 then return nil end
 local flags=Binary.u16(font,offset+14)
 return {axisCount=Binary.u16(font,offset+4),sharedCount=Binary.u16(font,offset+6),sharedOffset=offset+Binary.u32(font,offset+8),glyphCount=Binary.u16(font,offset+12),long=bit32.band(flags,1)~=0,data=offset+Binary.u32(font,offset+16),offsets=offset+20}
end
local function packedPoints(font,cursor,limit)
 local count=Binary.u8(font,cursor);cursor+=1
 if count==0 then return nil,cursor end
 if bit32.band(count,0x80)~=0 then
  count=bit32.band(count,0x7f)*256+Binary.u8(font,cursor);cursor+=1
 end
 assert(count<=V.limits.points,'gvar com numeros de ponto demais.')
 local points=table.create(count,0)
 local value=0
 local total=0
 while total<count do
  local control=Binary.u8(font,cursor);cursor+=1
  local run=bit32.band(control,0x7f)+1
  local words=bit32.band(control,0x80)~=0
  for _=1,run do
   if total>=count then break end
   if words then value+=Binary.u16(font,cursor);cursor+=2 else value+=Binary.u8(font,cursor);cursor+=1 end
   total+=1
   points[total]=value
  end
  assert(cursor<=limit,'Numeros de ponto gvar truncados.')
 end
 return points,cursor
end
local function packedDeltas(font,cursor,count,limit)
 local out=table.create(count,0)
 for index=1,count do out[index]=0 end
 local total=0
 while total<count do
  local control=Binary.u8(font,cursor);cursor+=1
  local run=bit32.band(control,0x3f)+1
  if bit32.band(control,0x80)~=0 then total+=run
  elseif bit32.band(control,0x40)~=0 then
   for _=1,run do
    total+=1
    if total<=count then out[total]=Binary.i16(font,cursor) end
    cursor+=2
   end
  else
   for _=1,run do
    total+=1
    if total<=count then out[total]=Binary.i8(font,cursor) end
    cursor+=1
   end
  end
  assert(cursor<=limit,'Deltas gvar truncados.')
 end
 return out,cursor
end
local function tupleScalar(coordinates,peak,low,high,count)
 local factor=1
 for axis=1,count do
  local value=peak[axis] or 0
  if value~=0 then
   local coord=coordinates[axis] or 0
   if coord~=value then
    if low and high then
     local first,last=low[axis] or 0,high[axis] or 0
     if coord<=first or coord>=last then return 0 end
     if coord<value then factor*=(coord-first)/(value-first) else factor*=(last-coord)/(last-value) end
    else
     if coord==0 then return 0 end
     if coord<math.min(0,value) or coord>math.max(0,value) then return 0 end
     factor*=coord/value
    end
   end
  end
 end
 return factor
end
function V.tuples(face,glyphId,pointTotal)
 local state=face.variation
 local gvar=state and state.gvar
 if not gvar or glyphId>=gvar.glyphCount then return nil end
 local font=face.font
 local first,last
 if gvar.long then
  first=Binary.u32(font,gvar.offsets+glyphId*4)
  last=Binary.u32(font,gvar.offsets+(glyphId+1)*4)
 else
  first=Binary.u16(font,gvar.offsets+glyphId*2)*2
  last=Binary.u16(font,gvar.offsets+(glyphId+1)*2)*2
 end
 if last<=first then return nil end
 local base=gvar.data+first
 local limit=gvar.data+last
 local header=Binary.u16(font,base)
 local count=bit32.band(header,0x0fff)
 if count==0 then return nil end
 assert(count<=V.limits.tuples,'gvar com tuplas demais.')
 local axisCount=gvar.axisCount
 local cursor=base+Binary.u16(font,base+2)
 local shared
 if bit32.band(header,0x8000)~=0 then shared,cursor=packedPoints(font,cursor,limit) end
 local headerCursor=base+4
 local out={}
 for _=1,count do
  local size=Binary.u16(font,headerCursor)
  local flags=Binary.u16(font,headerCursor+2)
  headerCursor+=4
  local peak=table.create(axisCount,0)
  if bit32.band(flags,0x8000)~=0 then
   for axis=1,axisCount do peak[axis]=Binary.f2dot14(font,headerCursor);headerCursor+=2 end
  else
   local shareIndex=bit32.band(flags,0x0fff)
   assert(shareIndex<gvar.sharedCount,'Tupla compartilhada inexistente em gvar.')
   for axis=1,axisCount do peak[axis]=Binary.f2dot14(font,gvar.sharedOffset+(shareIndex*axisCount+axis-1)*2) end
  end
  local low,high
  if bit32.band(flags,0x4000)~=0 then
   low=table.create(axisCount,0);high=table.create(axisCount,0)
   for axis=1,axisCount do low[axis]=Binary.f2dot14(font,headerCursor);headerCursor+=2 end
   for axis=1,axisCount do high[axis]=Binary.f2dot14(font,headerCursor);headerCursor+=2 end
  end
  local scalar=tupleScalar(state.coordinates,peak,low,high,axisCount)
  local tupleEnd=cursor+size
  assert(tupleEnd<=limit,'Tupla gvar alem dos dados do glifo.')
  if scalar~=0 then
   local at=cursor
   local points=shared
   if bit32.band(flags,0x2000)~=0 then points,at=packedPoints(font,at,tupleEnd) end
   local deltaCount=points and #points or pointTotal+4
   if deltaCount>0 and deltaCount<=V.limits.points then
    local dx,dy
    dx,at=packedDeltas(font,at,deltaCount,tupleEnd)
    dy=packedDeltas(font,at,deltaCount,tupleEnd)
    out[#out+1]={scalar=scalar,points=points,dx=dx,dy=dy}
   end
  end
  cursor=tupleEnd
 end
 if #out==0 then return nil end
 return out
end
local function infer(values,deltas,touched,from,to)
 local size=to-from+1
 if size<=0 then return end
 local list={}
 for index=from,to do if touched[index] then list[#list+1]=index end end
 if #list==0 then return end
 if #list==1 then
  local delta=deltas[list[1]]
  if delta~=0 then for index=from,to do if not touched[index] then deltas[index]=delta end end end
  return
 end
 for slot=1,#list do
  local a=list[slot]
  local b=list[slot%#list+1]
  local index=a+1
  if index>to then index=from end
  local steps=0
  while index~=b and steps<size do
   if not touched[index] then
    local firstCoordinate,secondCoordinate=values[a],values[b]
    local firstDelta,secondDelta=deltas[a],deltas[b]
    local value=values[index]
    local result
    if firstCoordinate==secondCoordinate then
     if firstDelta==secondDelta then result=firstDelta else result=0 end
    else
     local lowCoordinate,highCoordinate=firstCoordinate,secondCoordinate
     local lowDelta,highDelta=firstDelta,secondDelta
     if lowCoordinate>highCoordinate then
      lowCoordinate,highCoordinate=highCoordinate,lowCoordinate
      lowDelta,highDelta=highDelta,lowDelta
     end
     if value<=lowCoordinate then result=lowDelta
     elseif value>=highCoordinate then result=highDelta
     else result=lowDelta+(highDelta-lowDelta)*(value-lowCoordinate)/(highCoordinate-lowCoordinate) end
    end
    deltas[index]=result
   end
   index+=1
   if index>to then index=from end
   steps+=1
  end
 end
end
function V.apply(face,glyphId,xs,ys,total,endPoints)
 if not total or total<=0 then return false end
 local list=V.tuples(face,glyphId,total)
 if not list then return false end
 local accumX=table.create(total,0)
 local accumY=table.create(total,0)
 local dx=table.create(total,0)
 local dy=table.create(total,0)
 local touched=table.create(total,false)
 for index=1,total do accumX[index]=0;accumY[index]=0 end
 for _,tuple in ipairs(list) do
  for index=1,total do dx[index]=0;dy[index]=0;touched[index]=false end
  if tuple.points then
   for slot,point in ipairs(tuple.points) do
    local index=point+1
    if index>=1 and index<=total then
     dx[index]=tuple.dx[slot] or 0
     dy[index]=tuple.dy[slot] or 0
     touched[index]=true
    end
   end
   local start=1
   for contour=1,#endPoints do
    local finish=math.min(endPoints[contour]+1,total)
    if finish>=start then
     infer(xs,dx,touched,start,finish)
     infer(ys,dy,touched,start,finish)
    end
    start=finish+1
   end
  else
   for index=1,total do
    dx[index]=tuple.dx[index] or 0
    dy[index]=tuple.dy[index] or 0
   end
  end
  local scalar=tuple.scalar
  for index=1,total do
   accumX[index]+=dx[index]*scalar
   accumY[index]+=dy[index]*scalar
  end
 end
 for index=1,total do
  xs[index]+=accumX[index]
  ys[index]+=accumY[index]
 end
 return true
end
function V.components(face,glyphId,count)
 if not count or count<=0 then return nil end
 assert(count<=V.limits.components,'Glifo composto com componentes demais.')
 local list=V.tuples(face,glyphId,count)
 if not list then return nil end
 local out=table.create(count)
 for index=1,count do out[index]={x=0,y=0} end
 for _,tuple in ipairs(list) do
  if tuple.points then
   for slot,point in ipairs(tuple.points) do
    local index=point+1
    if index>=1 and index<=count then
     out[index].x+=(tuple.dx[slot] or 0)*tuple.scalar
     out[index].y+=(tuple.dy[slot] or 0)*tuple.scalar
    end
   end
  else
   for index=1,count do
    out[index].x+=(tuple.dx[index] or 0)*tuple.scalar
    out[index].y+=(tuple.dy[index] or 0)*tuple.scalar
   end
  end
 end
 return out
end
function V.pointCount(face,glyphId)
 if not face.loca then return nil end
 local glyf=Binary.locate(face.font,'glyf')
 if not glyf then return nil end
 local offset,length=face.loca(glyphId)
 if not offset or length<10 then return 0 end
 local font=face.font
 local base=glyf+offset
 local contours=Binary.i16(font,base)
 if contours>=0 then
  if contours==0 then return 0 end
  return Binary.u16(font,base+10+(contours-1)*2)+1
 end
 local cursor=base+10
 local count=0
 while true do
  count+=1
  assert(count<=V.limits.components,'Glifo composto com componentes demais.')
  local flags=Binary.u16(font,cursor)
  cursor+=4
  if bit32.band(flags,1)~=0 then cursor+=4 else cursor+=2 end
  if bit32.band(flags,8)~=0 then cursor+=2
  elseif bit32.band(flags,64)~=0 then cursor+=4
  elseif bit32.band(flags,128)~=0 then cursor+=8 end
  if bit32.band(flags,32)==0 then break end
 end
 return count
end
function V.phantomAdvance(face,glyphId)
 local total=V.pointCount(face,glyphId)
 if not total then return 0 end
 local list=V.tuples(face,glyphId,total)
 if not list then return 0 end
 local left,right=0,0
 for _,tuple in ipairs(list) do
  local firstDelta,secondDelta=0,0
  if tuple.points then
   for slot,point in ipairs(tuple.points) do
    if point==total then firstDelta=tuple.dx[slot] or 0
    elseif point==total+1 then secondDelta=tuple.dx[slot] or 0 end
   end
  else
   firstDelta=tuple.dx[total+1] or 0
   secondDelta=tuple.dx[total+2] or 0
  end
  left+=firstDelta*tuple.scalar
  right+=secondDelta*tuple.scalar
 end
 return right-left
end
function V.advanceDelta(face,glyphId)
 local state=face.variation
 if not state then return 0 end
 local cached=state.advanceCache[glyphId]
 if cached~=nil then return cached end
 local delta=0
 if state.hvar then
  local outer,inner=0,glyphId
  if state.hvar.advance then outer,inner=state.hvar.advance(glyphId) end
  delta=storeDelta(state.hvar.store,state.hvarScalars,outer,inner)
 elseif state.gvar then
  local ok,value=pcall(V.phantomAdvance,face,glyphId)
  if ok and type(value)=='number' then delta=value end
 end
 if state.advanceCount>=V.limits.cache then table.clear(state.advanceCache);state.advanceCount=0 end
 state.advanceCache[glyphId]=delta
 state.advanceCount+=1
 return delta
end
function V.verticalDelta(face,glyphId)
 local state=face.variation
 if not state or not state.vvar then return 0 end
 local cached=state.verticalCache[glyphId]
 if cached~=nil then return cached end
 local outer,inner=0,glyphId
 if state.vvar.advance then outer,inner=state.vvar.advance(glyphId) end
 local delta=storeDelta(state.vvar.store,state.vvarScalars,outer,inner)
 if state.verticalCount>=V.limits.cache then table.clear(state.verticalCache);state.verticalCount=0 end
 state.verticalCache[glyphId]=delta
 state.verticalCount+=1
 return delta
end
function V.metricDelta(face,tag)
 local state=face.variation
 if not state or not state.mvar then return 0 end
 local record=state.mvar.records[tag]
 if not record then return 0 end
 return storeDelta(state.mvar.store,state.mvarScalars,record.outer,record.inner)
end
function V.applyMetrics(face)
 local state=face.variation
 if not state or not state.mvar or type(face.metrics)~='table' then return false end
 local applied={}
 for tag,field in pairs(V.metricFields) do
  local record=state.mvar.records[tag]
  if record and type(face.metrics[field])=='number' then
   local delta=storeDelta(state.mvar.store,state.mvarScalars,record.outer,record.inner)
   if delta~=0 then
    face.metrics[field]+=delta
    applied[field]=delta
   end
  end
 end
 if next(applied)==nil then return false end
 face.metrics.variationDeltas=applied
 face.metrics.variationSource='mvar'
 if applied.xHeight then face.metrics.xHeightSource='mvar' end
 if applied.capHeight then face.metrics.capHeightSource='mvar' end
 return true
end
function V.instances(face,fvar)
 fvar=fvar or face.fvar or V.fvar(face.font)
 if not fvar then return {} end
 local names=type(face.names)=='table' and face.names or nil
 local out={}
 for index,entry in ipairs(fvar.instances) do
  local label=names and names[entry.nameId] or nil
  local postScript=names and entry.postScriptNameId and names[entry.postScriptNameId] or nil
  out[index]={nameId=entry.nameId,coordinates=entry.coordinates,name=type(label)=='string' and label or nil,postScriptName=type(postScript)=='string' and postScript or nil}
 end
 return out
end
function V.named(face,name,fvar)
 assert(type(name)=='string' and #name>0,'Instancia nomeada exige texto.')
 local wanted=string.lower(name)
 for _,entry in ipairs(V.instances(face,fvar)) do
  if entry.name and string.lower(entry.name)==wanted then return entry.coordinates,entry end
 end
 return nil
end
function V.summary(face)
 local state=face.variation
 if not state then return nil end
 local out={}
 for _,axis in ipairs(state.fvar.axes) do
  out[#out+1]={tag=axis.tag,value=state.user[axis.tag],default=axis.default,minimum=axis.minimum,maximum=axis.maximum,normalized=state.coordinates[axis.index],hidden=axis.hidden,nameId=axis.nameId}
 end
 return out
end
function V.support(face)
 local state=face.variation
 if not state then return {variable=false} end
 local source='static'
 if state.hvar then source='hvar' elseif state.gvar then source='phantom' end
 return {variable=true,axes=#state.fvar.axes,instances=#state.fvar.instances,outlines=state.gvar~=nil,advanceSource=source,verticalAdvances=state.vvar~=nil,metrics=state.mvar~=nil,avar=state.avar~=nil,key=state.key}
end
function V.attach(face,coordinates,instanceName)
 local font=face.font
 local fvar=V.fvar(font)
 if not fvar then
  face.variable=false
  face.variation=nil
  return nil
 end
 face.fvar=fvar
 local wanted=coordinates
 if instanceName~=nil then
  local named=V.named(face,instanceName,fvar)
  assert(named,'Instancia nomeada inexistente na fonte: '..tostring(instanceName)..'.')
  local merged={}
  for tag,value in pairs(named) do merged[tag]=value end
  if type(coordinates)=='table' then for tag,value in pairs(coordinates) do merged[tag]=value end end
  wanted=merged
  face.instanceName=instanceName
 end
 local user=V.resolve(fvar,wanted)
 local avar=V.avar(font,fvar.count)
 local normalized=V.normalize(fvar,avar,user)
 local state={fvar=fvar,avar=avar,user=user,coordinates=normalized,gvar=V.gvar(font),hvar=V.hvar(font),vvar=V.vvar(font),mvar=V.mvar(font),advanceCache={},advanceCount=0,verticalCache={},verticalCount=0,key=V.key(fvar,user)}
 if state.hvar then state.hvarScalars=V.scalars(state.hvar.store,normalized) end
 if state.vvar then state.vvarScalars=V.scalars(state.vvar.store,normalized) end
 if state.mvar then state.mvarScalars=V.scalars(state.mvar.store,normalized) end
 face.variable=true
 face.variation=state
 face.axes=user
 return state
end
function V.detach(face)
 face.variation=nil
 face.variable=false
 face.axes=nil
 face.instanceName=nil
end
return V
