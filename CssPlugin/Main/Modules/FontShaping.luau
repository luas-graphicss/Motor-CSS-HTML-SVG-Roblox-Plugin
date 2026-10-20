local Binary=require(script.Parent.FontBinary)
local Tables=require(script.Parent.FontTables)
local S={VERSION=1}
S.limits={coverage=100000,glyphs=8192,nesting=8,ligatureComponents=16,caches=4096}
S.gsubOrder={'ccmp','rlig','liga','clig','dlig','hlig','calt','hist','smcp','c2sc','pcap','c2pc','unic','titl','sups','subs','lnum','onum','pnum','tnum','frac','afrc','ordn','zero','jp78','jp83','jp90','jp04','smpl','trad','fwid','pwid','ruby'}
S.gposOrder={'curs','kern','mark','mkmk','cpsp'}
S.defaults={ccmp=1,rlig=1,liga=1,clig=1,calt=1,kern=1,mark=1,mkmk=1,curs=1}
local zeroClass={__index=function() return 0 end}
local function readCoverage(font,offset)
 local format=Binary.u16(font,offset)
 local map={}
 local total=0
 if format==1 then
  local count=Binary.u16(font,offset+2)
  assert(count<=S.limits.coverage,'Coverage OpenType grande demais.')
  for index=0,count-1 do map[Binary.u16(font,offset+4+index*2)]=index end
 elseif format==2 then
  local count=Binary.u16(font,offset+2)
  for index=0,count-1 do
   local record=offset+4+index*6
   local first=Binary.u16(font,record)
   local last=Binary.u16(font,record+2)
   local start=Binary.u16(font,record+4)
   assert(last>=first,'Coverage com faixa invertida.')
   total+=last-first+1
   assert(total<=S.limits.coverage,'Coverage OpenType grande demais.')
   for glyph=first,last do map[glyph]=start+glyph-first end
  end
 else
  error('Coverage OpenType com formato '..format..'.')
 end
 return map
end
local function readClasses(font,offset)
 local map={}
 local format=Binary.u16(font,offset)
 if format==1 then
  local start=Binary.u16(font,offset+2)
  local count=Binary.u16(font,offset+4)
  assert(count<=S.limits.coverage,'ClassDef grande demais.')
  for index=0,count-1 do map[start+index]=Binary.u16(font,offset+6+index*2) end
 elseif format==2 then
  local count=Binary.u16(font,offset+2)
  local total=0
  for index=0,count-1 do
   local record=offset+4+index*6
   local first=Binary.u16(font,record)
   local last=Binary.u16(font,record+2)
   local class=Binary.u16(font,record+4)
   total+=math.max(0,last-first+1)
   assert(total<=S.limits.coverage,'ClassDef grande demais.')
   for glyph=first,last do map[glyph]=class end
  end
 else
  error('ClassDef com formato '..format..'.')
 end
 return setmetatable(map,zeroClass)
end
local function coverage(context,offset)
 local cached=context.coverage[offset]
 if cached then return cached end
 cached=readCoverage(context.font,offset)
 context.coverage[offset]=cached
 return cached
end
local function classes(context,offset)
 local cached=context.classes[offset]
 if cached then return cached end
 cached=readClasses(context.font,offset)
 context.classes[offset]=cached
 return cached
end
local function valueFields(font,offset,format)
 local value={}
 local cursor=offset
 if bit32.band(format,1)~=0 then value.xPlacement=Binary.i16(font,cursor);cursor+=2 end
 if bit32.band(format,2)~=0 then value.yPlacement=Binary.i16(font,cursor);cursor+=2 end
 if bit32.band(format,4)~=0 then value.xAdvance=Binary.i16(font,cursor);cursor+=2 end
 if bit32.band(format,8)~=0 then value.yAdvance=Binary.i16(font,cursor);cursor+=2 end
 return value
end
local function valueSize(format)
 local size=0
 for bit=0,7 do if bit32.band(format,bit32.lshift(1,bit))~=0 then size+=2 end end
 return size
end
local function anchorAt(font,base,offset)
 if offset==0 then return nil end
 local at=base+offset
 return {x=Binary.i16(font,at+2),y=Binary.i16(font,at+4)}
end
local function lookupList(font,base)
 local count=Binary.u16(font,base)
 local lookups=table.create(count,nil)
 for index=1,count do
  local at=base+Binary.u16(font,base+index*2)
  local subCount=Binary.u16(font,at+4)
  local subtables=table.create(subCount,0)
  for sub=1,subCount do subtables[sub]=at+Binary.u16(font,at+4+sub*2) end
  local flag=Binary.u16(font,at+2)
  local filtering
  if bit32.band(flag,0x0010)~=0 then filtering=Binary.u16(font,at+6+subCount*2) end
  lookups[index]={kind=Binary.u16(font,at),flag=flag,subtables=subtables,filtering=filtering}
 end
 return lookups
end
local function featurePlan(font,tag,script,language)
 local base=Binary.locate(font,tag)
 if not base then return nil end
 local scripts=base+Binary.u16(font,base+4)
 local featureList=base+Binary.u16(font,base+6)
 local lookups=base+Binary.u16(font,base+8)
 local scriptCount=Binary.u16(font,scripts)
 local chosen,latin,first
 for index=0,scriptCount-1 do
  local record=scripts+2+index*6
  local scriptTag=Binary.tag(font,record)
  local at=scripts+Binary.u16(font,record+4)
  if scriptTag==script then chosen=at end
  if scriptTag=='DFLT' or scriptTag=='latn' then latin=latin or at end
  first=first or at
 end
 chosen=chosen or latin or first
 local features={}
 if chosen then
  local defaultLang=Binary.u16(font,chosen)
  local langCount=Binary.u16(font,chosen+2)
  local langSys
  if language then
   for index=0,langCount-1 do
    local record=chosen+4+index*6
    if Binary.tag(font,record)==language then langSys=chosen+Binary.u16(font,record+4) end
   end
  end
  if not langSys and defaultLang~=0 then langSys=chosen+defaultLang end
  if langSys then
   local indices={}
   local required=Binary.u16(font,langSys+2)
   if required~=0xffff then indices[#indices+1]=required end
   local count=Binary.u16(font,langSys+4)
   for index=0,count-1 do indices[#indices+1]=Binary.u16(font,langSys+6+index*2) end
   local featureCount=Binary.u16(font,featureList)
   for _,index in ipairs(indices) do
    if index<featureCount then
     local record=featureList+2+index*6
     local featureTag=Binary.tag(font,record)
     local at=featureList+Binary.u16(font,record+4)
     local lookupCount=Binary.u16(font,at+2)
     local list=features[featureTag] or {}
     for lookup=0,lookupCount-1 do list[#list+1]=Binary.u16(font,at+4+lookup*2)+1 end
     features[featureTag]=list
    end
   end
  end
 end
 return {features=features,lookups=lookupList(font,lookups),base=base}
end
function S.gdef(face)
 if face._gdef~=nil then return face._gdef or nil end
 local font=face.font
 local base=Binary.locate(font,'GDEF')
 if not base then
  face._gdef=false
  return nil
 end
 local glyphClassOffset=Binary.u16(font,base+4)
 local markAttachOffset=Binary.u16(font,base+10)
 local gdef={
  glyphClass=glyphClassOffset~=0 and readClasses(font,base+glyphClassOffset) or nil,
  markAttach=markAttachOffset~=0 and readClasses(font,base+markAttachOffset) or nil,
 }
 face._gdef=gdef
 return gdef
end
function S.plan(face,tag,script,language)
 local key=tag..':'..(script or 'latn')..':'..(language or '')
 face._plans=face._plans or {}
 local cached=face._plans[key]
 if cached~=nil then return cached or nil end
 local plan=featurePlan(face.font,tag,script or 'latn',language)
 face._plans[key]=plan or false
 return plan
end
function S.kernPairs(face)
 if face._kern~=nil then return face._kern or nil end
 local font=face.font
 local base=Binary.locate(font,'kern')
 if not base then
  face._kern=false
  return nil
 end
 local map={}
 local subtables=Binary.u16(font,base+2)
 local cursor=base+4
 local found=false
 for _=1,math.min(subtables,8) do
  local length=Binary.u16(font,cursor+2)
  local coverageFlags=Binary.u16(font,cursor+4)
  local format=bit32.rshift(coverageFlags,8)
  local horizontal=bit32.band(coverageFlags,1)~=0
  if format==0 and horizontal then
   local count=Binary.u16(font,cursor+6)
   assert(count<=S.limits.coverage,'Tabela kern grande demais.')
   for index=0,count-1 do
    local record=cursor+14+index*6
    map[Binary.u16(font,record)*65536+Binary.u16(font,record+2)]=Binary.i16(font,record+4)
    found=true
   end
  end
  if length<=0 then break end
  cursor+=length
 end
 if not found then
  face._kern=false
  return nil
 end
 face._kern=map
 return map
end
local function glyphClass(context,glyph)
 local gdef=context.gdef
 if not gdef or not gdef.glyphClass then return 0 end
 return gdef.glyphClass[glyph]
end
local function ignored(context,glyph)
 local flag=context.flag
 if flag==0 then return false end
 local class=glyphClass(context,glyph)
 if bit32.band(flag,0x0002)~=0 and class==1 then return true end
 if bit32.band(flag,0x0004)~=0 and class==2 then return true end
 if bit32.band(flag,0x0008)~=0 and class==3 then return true end
 local attachment=bit32.rshift(bit32.band(flag,0xff00),8)
 if attachment~=0 and class==3 then
  local gdef=context.gdef
  local actual=gdef and gdef.markAttach and gdef.markAttach[glyph] or 0
  if actual~=attachment then return true end
 end
 return false
end
local function nextIndex(context,run,from)
 local index=from
 while index<=#run do
  if not ignored(context,run[index].glyph) then return index end
  index+=1
 end
 return nil
end
local function previousIndex(context,run,from)
 local index=from
 while index>=1 do
  if not ignored(context,run[index].glyph) then return index end
  index-=1
 end
 return nil
end
local function extension(font,offset)
 return Binary.u16(font,offset+2),offset+Binary.u32(font,offset+4)
end
local function substituteSingle(context,offset,run,position)
 local font=context.font
 local format=Binary.u16(font,offset)
 local index=coverage(context,offset+Binary.u16(font,offset+2))[run[position].glyph]
 if index==nil then return nil end
 if format==1 then
  run[position].glyph=(run[position].glyph+Binary.i16(font,offset+4))%65536
  run[position].substituted=true
  return 1
 end
 if index>=Binary.u16(font,offset+4) then return nil end
 run[position].glyph=Binary.u16(font,offset+6+index*2)
 run[position].substituted=true
 return 1
end
local function substituteMultiple(context,offset,run,position)
 local font=context.font
 local index=coverage(context,offset+Binary.u16(font,offset+2))[run[position].glyph]
 if index==nil then return nil end
 if index>=Binary.u16(font,offset+4) then return nil end
 local sequence=offset+Binary.u16(font,offset+6+index*2)
 local count=Binary.u16(font,sequence)
 assert(count<=S.limits.ligatureComponents,'Substituição múltipla longa demais.')
 if count==0 then return nil end
 local source=run[position]
 local replacements={}
 for item=0,count-1 do
  replacements[#replacements+1]={glyph=Binary.u16(font,sequence+2+item*2),codepoint=source.codepoint,cluster=source.cluster,advance=0,advanceAdjust=0,xOffset=0,yOffset=0,decomposed=true}
 end
 table.remove(run,position)
 for item=#replacements,1,-1 do table.insert(run,position,replacements[item]) end
 return count
end
local function substituteAlternate(context,offset,run,position,alternate)
 local font=context.font
 local index=coverage(context,offset+Binary.u16(font,offset+2))[run[position].glyph]
 if index==nil then return nil end
 if index>=Binary.u16(font,offset+4) then return nil end
 local set=offset+Binary.u16(font,offset+6+index*2)
 local count=Binary.u16(font,set)
 if count==0 then return nil end
 local pick=math.clamp(alternate or 1,1,count)
 run[position].glyph=Binary.u16(font,set+2+(pick-1)*2)
 run[position].substituted=true
 return 1
end
local function substituteLigature(context,offset,run,position)
 local font=context.font
 local index=coverage(context,offset+Binary.u16(font,offset+2))[run[position].glyph]
 if index==nil then return nil end
 if index>=Binary.u16(font,offset+4) then return nil end
 local set=offset+Binary.u16(font,offset+6+index*2)
 local total=Binary.u16(font,set)
 for item=0,total-1 do
  local ligature=set+Binary.u16(font,set+2+item*2)
  local components=Binary.u16(font,ligature+2)
  assert(components>=1 and components<=S.limits.ligatureComponents,'Ligatura com componentes inválidos.')
  local matched={position}
  local cursor=position+1
  local ok=true
  for component=2,components do
   local at=nextIndex(context,run,cursor)
   if not at or run[at].glyph~=Binary.u16(font,ligature+2+(component-1)*2) then ok=false;break end
   matched[#matched+1]=at
   cursor=at+1
  end
  if ok then
   local cluster=run[position].cluster
   for _,at in ipairs(matched) do cluster=math.min(cluster,run[at].cluster) end
   run[position].glyph=Binary.u16(font,ligature)
   run[position].cluster=cluster
   run[position].ligature=components
   run[position].substituted=true
   for slot=#matched,2,-1 do table.remove(run,matched[slot]) end
   return 1
  end
 end
 return nil
end
local function chainMatch(context,offset,run,position,records)
 local font=context.font
 if Binary.u16(font,offset)~=3 then return nil end
 local cursor=offset+2
 local backtrack=Binary.u16(font,cursor);cursor+=2
 local backtrackOffsets={}
 for item=1,backtrack do backtrackOffsets[item]=offset+Binary.u16(font,cursor);cursor+=2 end
 local input=Binary.u16(font,cursor);cursor+=2
 local inputOffsets={}
 for item=1,input do inputOffsets[item]=offset+Binary.u16(font,cursor);cursor+=2 end
 local lookahead=Binary.u16(font,cursor);cursor+=2
 local lookaheadOffsets={}
 for item=1,lookahead do lookaheadOffsets[item]=offset+Binary.u16(font,cursor);cursor+=2 end
 local substCount=Binary.u16(font,cursor);cursor+=2
 if input==0 then return nil end
 local matched={}
 local at=position
 for item=1,input do
  if item>1 then at=nextIndex(context,run,at+1) end
  if not at or coverage(context,inputOffsets[item])[run[at].glyph]==nil then return nil end
  matched[item]=at
 end
 local before=position
 for item=1,backtrack do
  before=previousIndex(context,run,before-1)
  if not before or coverage(context,backtrackOffsets[item])[run[before].glyph]==nil then return nil end
 end
 local after=matched[input]
 for item=1,lookahead do
  after=nextIndex(context,run,after+1)
  if not after or coverage(context,lookaheadOffsets[item])[run[after].glyph]==nil then return nil end
 end
 for item=0,substCount-1 do
  records[#records+1]={sequence=Binary.u16(font,cursor+item*4),lookup=Binary.u16(font,cursor+item*4+2)+1}
 end
 return matched
end
local applyGsubLookup
applyGsubLookup=function(context,plan,lookupIndex,run,position,depth,alternate)
 assert(depth<=S.limits.nesting,'Cadeia GSUB profunda demais.')
 local lookup=plan.lookups[lookupIndex]
 if not lookup then return nil end
 local previous=context.flag
 context.flag=lookup.flag
 local consumed
 for _,subtable in ipairs(lookup.subtables) do
  local kind=lookup.kind
  local offset=subtable
  if kind==7 then kind,offset=extension(context.font,subtable) end
  if kind==1 then consumed=substituteSingle(context,offset,run,position)
  elseif kind==2 then consumed=substituteMultiple(context,offset,run,position)
  elseif kind==3 then consumed=substituteAlternate(context,offset,run,position,alternate)
  elseif kind==4 then consumed=substituteLigature(context,offset,run,position)
  elseif kind==6 then
   local records={}
   local matched=chainMatch(context,offset,run,position,records)
   if matched then
    for _,record in ipairs(records) do
     local target=matched[record.sequence+1]
     if target then applyGsubLookup(context,plan,record.lookup,run,target,depth+1,alternate) end
    end
    consumed=#matched
   end
  end
  if consumed then break end
 end
 context.flag=previous
 return consumed
end
local function applyGsubFeature(context,plan,indices,run,alternate)
 local changed=false
 for _,lookupIndex in ipairs(indices) do
  local lookup=plan.lookups[lookupIndex]
  if lookup then
   context.flag=lookup.flag
   local position=1
   while position<=#run do
    local consumed
    if not ignored(context,run[position].glyph) then
     consumed=applyGsubLookup(context,plan,lookupIndex,run,position,0,alternate)
    end
    if consumed then
     changed=true
     position+=math.max(1,consumed)
    else
     position+=1
    end
   end
   context.flag=0
  end
 end
 return changed
end
local function positionSingle(context,offset,run,position)
 local font=context.font
 local format=Binary.u16(font,offset)
 local index=coverage(context,offset+Binary.u16(font,offset+2))[run[position].glyph]
 if index==nil then return nil end
 local valueFormat=Binary.u16(font,offset+4)
 local value
 if format==1 then value=valueFields(font,offset+6,valueFormat)
 else
  if index>=Binary.u16(font,offset+6) then return nil end
  value=valueFields(font,offset+8+index*valueSize(valueFormat),valueFormat)
 end
 local item=run[position]
 item.xOffset+=value.xPlacement or 0
 item.yOffset+=value.yPlacement or 0
 item.advanceAdjust+=value.xAdvance or 0
 return 1
end
local function positionPair(context,offset,run,position)
 local font=context.font
 local format=Binary.u16(font,offset)
 local index=coverage(context,offset+Binary.u16(font,offset+2))[run[position].glyph]
 if index==nil then return nil end
 local second=nextIndex(context,run,position+1)
 if not second then return nil end
 local firstFormat=Binary.u16(font,offset+4)
 local secondFormat=Binary.u16(font,offset+6)
 local firstSize=valueSize(firstFormat)
 local secondSize=valueSize(secondFormat)
 local firstValue,secondValue
 if format==1 then
  if index>=Binary.u16(font,offset+8) then return nil end
  local set=offset+Binary.u16(font,offset+10+index*2)
  local total=Binary.u16(font,set)
  local stride=2+firstSize+secondSize
  for item=0,total-1 do
   local record=set+2+item*stride
   if Binary.u16(font,record)==run[second].glyph then
    firstValue=valueFields(font,record+2,firstFormat)
    secondValue=valueFields(font,record+2+firstSize,secondFormat)
    break
   end
  end
 elseif format==2 then
  local firstClasses=classes(context,offset+Binary.u16(font,offset+8))
  local secondClasses=classes(context,offset+Binary.u16(font,offset+10))
  local class1Count=Binary.u16(font,offset+12)
  local class2Count=Binary.u16(font,offset+14)
  local firstClass=firstClasses[run[position].glyph]
  local secondClass=secondClasses[run[second].glyph]
  if firstClass>=class1Count or secondClass>=class2Count then return nil end
  local stride=firstSize+secondSize
  local record=offset+16+(firstClass*class2Count+secondClass)*stride
  firstValue=valueFields(font,record,firstFormat)
  secondValue=valueFields(font,record+firstSize,secondFormat)
 end
 if not firstValue then return nil end
 run[position].advanceAdjust+=firstValue.xAdvance or 0
 run[position].xOffset+=firstValue.xPlacement or 0
 run[position].yOffset+=firstValue.yPlacement or 0
 if secondValue then
  run[second].advanceAdjust+=secondValue.xAdvance or 0
  run[second].xOffset+=secondValue.xPlacement or 0
  run[second].yOffset+=secondValue.yPlacement or 0
 end
 return 1
end
local function positionMark(context,offset,run,position,toMark)
 local font=context.font
 local markCoverage=coverage(context,offset+Binary.u16(font,offset+2))
 local baseCoverage=coverage(context,offset+Binary.u16(font,offset+4))
 local markIndex=markCoverage[run[position].glyph]
 if markIndex==nil then return nil end
 local classCount=Binary.u16(font,offset+6)
 local markArray=offset+Binary.u16(font,offset+8)
 local baseArray=offset+Binary.u16(font,offset+10)
 if markIndex>=Binary.u16(font,markArray) then return nil end
 local markClass=Binary.u16(font,markArray+2+markIndex*4)
 if markClass>=classCount then return nil end
 local markAnchor=anchorAt(font,markArray,Binary.u16(font,markArray+2+markIndex*4+2))
 if not markAnchor then return nil end
 local baseIndex,anchorIndex
 local search=position-1
 while search>=1 do
  local candidate=run[search]
  local class=glyphClass(context,candidate.glyph)
  if toMark then
   if baseCoverage[candidate.glyph]~=nil then
    baseIndex=search
    anchorIndex=baseCoverage[candidate.glyph]
    break
   end
   if class~=3 then break end
  elseif class~=3 then
   if baseCoverage[candidate.glyph]~=nil then
    baseIndex=search
    anchorIndex=baseCoverage[candidate.glyph]
   end
   break
  end
  search-=1
 end
 if not baseIndex then return nil end
 if anchorIndex>=Binary.u16(font,baseArray) then return nil end
 local baseAnchor=anchorAt(font,baseArray,Binary.u16(font,baseArray+2+(anchorIndex*classCount+markClass)*2))
 if not baseAnchor then return nil end
 local between=0
 for index=baseIndex,position-1 do between+=run[index].advance+run[index].advanceAdjust end
 run[position].xOffset=baseAnchor.x-markAnchor.x-between+run[baseIndex].xOffset
 run[position].yOffset=baseAnchor.y-markAnchor.y+run[baseIndex].yOffset
 run[position].attachedTo=baseIndex
 return 1
end
local function applyGposFeature(context,plan,indices,run)
 local applied=false
 for _,lookupIndex in ipairs(indices) do
  local lookup=plan.lookups[lookupIndex]
  if lookup then
   context.flag=lookup.flag
   local position=1
   while position<=#run do
    if not ignored(context,run[position].glyph) then
     for _,subtable in ipairs(lookup.subtables) do
      local kind=lookup.kind
      local offset=subtable
      if kind==9 then kind,offset=extension(context.font,subtable) end
      local handled
      if kind==1 then handled=positionSingle(context,offset,run,position)
      elseif kind==2 then handled=positionPair(context,offset,run,position)
      elseif kind==4 then handled=positionMark(context,offset,run,position,false)
      elseif kind==6 then handled=positionMark(context,offset,run,position,true)
      end
      if handled then
       applied=true
       break
      end
     end
    end
    position+=1
   end
   context.flag=0
  end
 end
 return applied
end
function S.features(requested)
 local features={}
 for tag,value in pairs(S.defaults) do features[tag]=value end
 for tag,value in pairs(requested or {}) do features[tag]=value end
 local gsub,gpos={},{}
 for _,tag in ipairs(S.gsubOrder) do
  local value=features[tag]
  if value and value~=0 then gsub[#gsub+1]={tag=tag,value=value} end
 end
 local extra={}
 for tag,value in pairs(features) do
  if value and value~=0 and not table.find(S.gsubOrder,tag) and not table.find(S.gposOrder,tag) then extra[#extra+1]=tag end
 end
 table.sort(extra)
 for _,tag in ipairs(extra) do gsub[#gsub+1]={tag=tag,value=features[tag]} end
 for _,tag in ipairs(S.gposOrder) do
  local value=features[tag]
  if value and value~=0 then gpos[#gpos+1]={tag=tag,value=value} end
 end
 return gsub,gpos,features
end
function S.shape(face,text,options)
 options=options or {}
 assert(type(text)=='string','Shaping exige texto.')
 local gsubFeatures,gposFeatures,resolved=S.features(options.features)
 local run={}
 local count=0
 for position,codepoint in utf8.codes(text) do
  count+=1
  assert(count<=S.limits.glyphs,'Texto longo demais para shaping.')
  run[count]={glyph=Tables.glyph(face,codepoint),codepoint=codepoint,cluster=position,advance=0,advanceAdjust=0,xOffset=0,yOffset=0}
 end
 face._coverageCache=face._coverageCache or {}
 face._classCache=face._classCache or {}
 local context={face=face,font=face.font,gdef=S.gdef(face),flag=0,coverage=face._coverageCache,classes=face._classCache}
 local applied={}
 local gsubPlan=S.plan(face,'GSUB',options.script,options.language)
 if gsubPlan then
  for _,feature in ipairs(gsubFeatures) do
   local indices=gsubPlan.features[feature.tag]
   if indices and #indices>0 then
    local alternate=nil
    if feature.tag:sub(1,2)=='ss' or feature.tag:sub(1,2)=='cv' or feature.tag=='salt' then alternate=feature.value end
    if applyGsubFeature(context,gsubPlan,indices,run,alternate) then applied[#applied+1]=feature.tag end
   end
  end
 end
 for _,item in ipairs(run) do item.advance=face.advance(item.glyph) end
 local gposPlan=S.plan(face,'GPOS',options.script,options.language)
 local kerned=false
 if gposPlan then
  for _,feature in ipairs(gposFeatures) do
   local indices=gposPlan.features[feature.tag]
   if indices and #indices>0 then
    if feature.tag=='kern' then kerned=true end
    if applyGposFeature(context,gposPlan,indices,run) then applied[#applied+1]=feature.tag end
   end
  end
 end
 local legacyKern=false
 if not kerned and resolved.kern and resolved.kern~=0 then
  local map=S.kernPairs(face)
  if map then
   for index=1,#run-1 do
    local adjustment=map[run[index].glyph*65536+run[index+1].glyph]
    if adjustment then
     run[index].advanceAdjust+=adjustment
     legacyKern=true
    end
   end
   if legacyKern then applied[#applied+1]='kern~legacy' end
  end
 end
 local width=0
 for _,item in ipairs(run) do
  item.total=item.advance+item.advanceAdjust
  width+=item.total
 end
 if options.rtl then
  local reversed={}
  for index=#run,1,-1 do reversed[#reversed+1]=run[index] end
  run=reversed
 end
 return {
  glyphs=run,width=width,unitsPerEm=face.unitsPerEm,
  applied=applied,legacyKern=legacyKern,features=resolved,
  script=options.script or 'latn',language=options.language,
  hasGsub=gsubPlan~=nil,hasGpos=gposPlan~=nil,rtl=options.rtl==true,
 }
end
function S.measure(face,text,size,options)
 local shaped=S.shape(face,text,options)
 local scale=size/face.unitsPerEm
 return shaped.width*scale,shaped,scale
end
function S.positions(shaped,size)
 local scale=size/shaped.unitsPerEm
 local out=table.create(#shaped.glyphs,nil)
 local pen=0
 for index,item in ipairs(shaped.glyphs) do
  out[index]={
   glyph=item.glyph,cluster=item.cluster,codepoint=item.codepoint,
   x=(pen+item.xOffset)*scale,y=item.yOffset*scale,
   advance=item.total*scale,ligature=item.ligature,attachedTo=item.attachedTo,
  }
  pen+=item.total
 end
 return out,pen*scale
end
return S
