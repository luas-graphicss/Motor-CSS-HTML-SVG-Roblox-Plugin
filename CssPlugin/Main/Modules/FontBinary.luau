local Brotli=require(script.Parent.FontBrotli)
local B={VERSION=2}
B.MAX_BYTES=8*1024*1024
local MAX_TABLES=512
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local alphabetValues
local function base64Values()
 if alphabetValues then return alphabetValues end
 alphabetValues={}
 for i=1,#alphabet do alphabetValues[string.byte(alphabet,i)]=i-1 end
 alphabetValues[45]=62;alphabetValues[95]=63
 return alphabetValues
end
local function readU16(data,offset)
 local a,b=string.byte(data,offset+1,offset+2)
 assert(b,'Leitura fora dos limites da fonte.')
 return a*256+b
end
local function readU32(data,offset)
 local a,b,c,d=string.byte(data,offset+1,offset+4)
 assert(d,'Leitura fora dos limites da fonte.')
 return ((a*256+b)*256+c)*256+d
end
function B.base64(text)
 assert(type(text)=='string' and #text>0,'base64 exige texto.')
 assert(#text<=B.MAX_BYTES*2,'Fonte base64 grande demais.')
 local map=base64Values()
 local out=buffer.create(math.max(16,math.floor(#text*3/4)+3))
 local length,accumulator,bits=0,0,0
 for i=1,#text do
  local code=string.byte(text,i)
  if code>32 and code~=61 then
   local value=map[code]
   assert(value,'Base64 inválido na fonte.')
   accumulator=accumulator*64+value;bits+=6
   if bits>=8 then
    bits-=8
    local byte=math.floor(accumulator/2^bits)
    accumulator-=byte*2^bits
    buffer.writeu8(out,length,byte);length+=1
   end
  end
 end
 assert(length>0 and length<=B.MAX_BYTES,'Bytes de fonte fora do limite.')
 return buffer.readstring(out,0,length)
end
function B.dataUrl(value)
 if type(value)~='string' then return nil end
 local head,body=value:match('^data:([^,]*),(.*)$')
 if not head then return nil end
 local mime=(head:match('^([^;]*)') or ''):lower()
 local allowed=mime==''or mime=='application/octet-stream'or mime:find('font',1,true)~=nil or mime:find('truetype',1,true)~=nil or mime:find('opentype',1,true)~=nil or mime:find('woff',1,true)~=nil or mime:find('sfnt',1,true)~=nil
 assert(allowed,'data: URL de fonte com tipo inesperado: '..mime)
 if head:lower():find(';base64',1,true) then return B.base64(body) end
 return (body:gsub('%%(%x%x)',function(hex) return string.char(tonumber(hex,16)) end))
end
function B.fingerprint(data)
 assert(type(data)=='string','fingerprint exige bytes.')
 local hash=5381
 local step=math.max(1,math.floor(#data/2048))
 for i=1,#data,step do hash=(hash*131+string.byte(data,i))%4294967296 end
 return string.format('%d:%d',#data,hash)
end
local lengthBase={3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local lengthExtra={0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local distanceBase={1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local distanceExtra={0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local codeOrder={16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}
local function huffman(lengths,count)
 local counts=table.create(16,0)
 for i=1,count do
  local length=lengths[i] or 0
  assert(length>=0 and length<=15,'Comprimento Huffman inválido.')
  if length>0 then counts[length]+=1 end
 end
 local offsets=table.create(16,0)
 local total=0
 for length=1,15 do offsets[length]=total;total+=counts[length] end
 local symbols=table.create(math.max(1,total),0)
 for i=1,count do
  local length=lengths[i] or 0
  if length>0 then offsets[length]+=1;symbols[offsets[length]]=i-1 end
 end
 return {counts=counts,symbols=symbols,total=total}
end
local fixedLiteral,fixedDistance
local function fixedTrees()
 if not fixedLiteral then
  local literals=table.create(288,8)
  for i=145,256 do literals[i]=9 end
  for i=257,280 do literals[i]=7 end
  fixedLiteral=huffman(literals,288)
  fixedDistance=huffman(table.create(30,5),30)
 end
 return fixedLiteral,fixedDistance
end
function B.inflate(data,raw)
 assert(type(data)=='string' and #data>0,'Fluxo comprimido vazio.')
 local position=1
 if not raw then
  local cmf,flg=string.byte(data,1,2)
  assert(cmf and flg,'Cabeçalho zlib truncado.')
  assert(cmf%16==8,'Método zlib não suportado.')
  assert((cmf*256+flg)%31==0,'Cabeçalho zlib inválido.')
  assert(bit32.band(flg,32)==0,'zlib com dicionário externo não suportado.')
  position=3
 end
 local hold,bits=0,0
 local function take(count)
  while bits<count do
   local byte=string.byte(data,position)
   assert(byte,'Fluxo deflate truncado.')
   position+=1;hold+=byte*2^bits;bits+=8
  end
  local value=hold%2^count
  hold=(hold-value)/2^count;bits-=count
  return value
 end
 local capacity=math.max(4096,#data*4)
 local out=buffer.create(capacity)
 local length=0
 local function push(byte)
  if length>=capacity then
   assert(capacity*2<=B.MAX_BYTES*2,'Saída deflate maior que o limite.')
   capacity*=2
   local bigger=buffer.create(capacity)
   buffer.copy(bigger,0,out,0,length)
   out=bigger
  end
  buffer.writeu8(out,length,byte);length+=1
 end
 local function decode(tree)
  local code,first,index=0,0,1
  for bitLength=1,15 do
   code+=take(1)
   local count=tree.counts[bitLength]
   if code-first<count then return tree.symbols[index+code-first] end
   index+=count;first=(first+count)*2;code*=2
  end
  error('Código Huffman inválido.')
 end
 repeat
  local final=take(1)
  local kind=take(2)
  if kind==0 then
   hold,bits=0,0
   local low,high=string.byte(data,position,position+1)
   assert(low and high,'Bloco deflate armazenado truncado.')
   local size=low+high*256
   position+=4
   for i=0,size-1 do
    local byte=string.byte(data,position+i)
    assert(byte,'Bloco deflate armazenado truncado.')
    push(byte)
   end
   position+=size
  else
   local literal,distance
   if kind==1 then literal,distance=fixedTrees()
   else
    assert(kind==2,'Bloco deflate reservado.')
    local literalCount=take(5)+257
    local distanceCount=take(5)+1
    local codeCount=take(4)+4
    local codeLengths=table.create(19,0)
    for i=1,codeCount do codeLengths[codeOrder[i]+1]=take(3) end
    local codeTree=huffman(codeLengths,19)
    local total=literalCount+distanceCount
    local lengths=table.create(total,0)
    local index=1
    while index<=total do
     local symbol=decode(codeTree)
     if symbol<16 then lengths[index]=symbol;index+=1
     elseif symbol==16 then
      assert(index>1,'Repetição Huffman sem valor anterior.')
      local previous=lengths[index-1]
      for _=1,3+take(2) do lengths[index]=previous;index+=1 end
     elseif symbol==17 then for _=1,3+take(3) do lengths[index]=0;index+=1 end
     else for _=1,11+take(7) do lengths[index]=0;index+=1 end end
    end
    assert(index==total+1,'Tabela de comprimentos deflate inconsistente.')
    local literalLengths=table.create(literalCount,0)
    for i=1,literalCount do literalLengths[i]=lengths[i] end
    local distanceLengths=table.create(distanceCount,0)
    for i=1,distanceCount do distanceLengths[i]=lengths[literalCount+i] end
    literal=huffman(literalLengths,literalCount)
    distance=huffman(distanceLengths,distanceCount)
   end
   while true do
    local symbol=decode(literal)
    if symbol<256 then push(symbol)
    elseif symbol==256 then break
    else
     local index=symbol-256
     assert(index>=1 and index<=29,'Símbolo de comprimento deflate inválido.')
     local size=lengthBase[index]+take(lengthExtra[index])
     local slot=decode(distance)+1
     assert(slot>=1 and slot<=30,'Símbolo de distância deflate inválido.')
     local back=distanceBase[slot]+take(distanceExtra[slot])
     assert(back<=length,'Distância deflate antes do início da saída.')
     local start=length-back
     for i=0,size-1 do push(buffer.readu8(out,start+i)) end
    end
   end
  end
 until final==1
 return buffer.readstring(out,0,length)
end
local function checksum(chunk)
 local padded=chunk..string.rep('\0',(4-#chunk%4)%4)
 local sum=0
 for offset=0,#padded-4,4 do sum=(sum+readU32(padded,offset))%4294967296 end
 return sum
end
local WOFF2_TAGS={'cmap','head','hhea','hmtx','maxp','name','OS/2','post','cvt ','fpgm','glyf','loca','prep','CFF ','VORG','EBDT','EBLC','gasp','hdmx','kern','LTSH','PCLT','VDMX','vhea','vmtx','BASE','GDEF','GPOS','GSUB','EBSC','JSTF','MATH','CBDT','CBLC','COLR','CPAL','SVG ','sbix','acnt','avar','bdat','bloc','bsln','cvar','fdsc','feat','fmtx','fvar','gvar','hsty','just','lcar','mort','morx','opbd','prop','trak','Zapf','Silf','Glat','Gloc','Feat','Sill'}
local function ensureDictionary()
 if Brotli.hasDictionary() then return end
 local module=script.Parent:FindFirstChild('FontBrotliDictionary')
 if module and module:IsA('ModuleScript') then Brotli.installDictionary(require(module)) end
end
local function base128(data,pos)
 local value=0
 for i=1,5 do
  local byte=string.byte(data,pos)
  assert(byte,'UIntBase128 truncado.')
  assert(not(i==1 and byte==128),'UIntBase128 com zero inicial.')
  assert(value<33554432,'UIntBase128 fora do limite.')
  value=value*128+byte%128
  pos+=1
  if byte<128 then return value,pos end
 end
 error('UIntBase128 com mais de 5 bytes.')
end
local function reader(data,start,stop,label)
 local r={pos=start,stop=stop}
 function r.u8() assert(r.pos<=r.stop,label..' truncado.'); local b=string.byte(data,r.pos); r.pos+=1; return b end
 function r.u16() assert(r.pos+1<=r.stop,label..' truncado.'); local a,b=string.byte(data,r.pos,r.pos+1); r.pos+=2; return a*256+b end
 function r.i16() local v=r.u16(); if v>=32768 then v-=65536 end; return v end
 function r.u32() assert(r.pos+3<=r.stop,label..' truncado.'); local a,b,c,d=string.byte(data,r.pos,r.pos+3); r.pos+=4; return ((a*256+b)*256+c)*256+d end
 function r.u255() local code=r.u8(); if code==253 then return r.u16() elseif code==255 then return 253+r.u8() elseif code==254 then return 506+r.u8() end; return code end
 function r.bytes(n) assert(n>=0 and r.pos+n-1<=r.stop,label..' truncado.'); local s=data:sub(r.pos,r.pos+n-1); r.pos+=n; return s end
 return r
end
local function withSign(flag,value) if flag%2==1 then return value end return -value end
local function triplet(flag,glyph)
 local onCurve=flag<128
 flag=flag%128
 local dx,dy
 if flag<10 then
  dx=0; dy=withSign(flag,bit32.lshift(bit32.band(flag,14),7)+glyph.u8())
 elseif flag<20 then
  dx=withSign(flag,bit32.lshift(bit32.band(flag-10,14),7)+glyph.u8()); dy=0
 elseif flag<84 then
  local b0=flag-20; local b1=glyph.u8()
  dx=withSign(flag,1+bit32.band(b0,48)+bit32.rshift(b1,4))
  dy=withSign(bit32.rshift(flag,1),1+bit32.lshift(bit32.band(b0,12),2)+bit32.band(b1,15))
 elseif flag<120 then
  local b0=flag-84; local b1=glyph.u8(); local b2=glyph.u8()
  dx=withSign(flag,1+bit32.lshift(math.floor(b0/12),8)+b1)
  dy=withSign(bit32.rshift(flag,1),1+bit32.lshift(bit32.rshift(b0%12,2),8)+b2)
 elseif flag<124 then
  local b1=glyph.u8(); local b2=glyph.u8(); local b3=glyph.u8()
  dx=withSign(flag,bit32.lshift(b1,4)+bit32.rshift(b2,4))
  dy=withSign(bit32.rshift(flag,1),bit32.lshift(bit32.band(b2,15),8)+b3)
 else
  local b1,b2,b3,b4=glyph.u8(),glyph.u8(),glyph.u8(),glyph.u8()
  dx=withSign(flag,bit32.lshift(b1,8)+b2)
  dy=withSign(bit32.rshift(flag,1),bit32.lshift(b3,8)+b4)
 end
 return onCurve,dx,dy
end
local function encodeSimple(nContours,endPts,points,instructions,bbox,overlap)
 local flags,xs,ys={},{},{}
 for i,p in ipairs(points) do
  local f=p.on and 1 or 0
  if i==1 and overlap then f+=64 end
  local dx,dy=p.dx,p.dy
  if dx==0 then f+=16 elseif dx>-256 and dx<256 then f+=2; if dx>0 then f+=16 end; xs[#xs+1]=string.char(math.abs(dx)) else xs[#xs+1]=string.pack('>i2',dx) end
  if dy==0 then f+=32 elseif dy>-256 and dy<256 then f+=4; if dy>0 then f+=32 end; ys[#ys+1]=string.char(math.abs(dy)) else ys[#ys+1]=string.pack('>i2',dy) end
  flags[i]=string.char(f)
 end
 local parts={string.pack('>i2i2i2i2i2',nContours,bbox[1],bbox[2],bbox[3],bbox[4])}
 for _,e in ipairs(endPts) do parts[#parts+1]=string.pack('>I2',e) end
 parts[#parts+1]=string.pack('>I2',#instructions)..instructions
 parts[#parts+1]=table.concat(flags)..table.concat(xs)..table.concat(ys)
 return table.concat(parts)
end
local function bitAt(bitmap,index)
 local byte=string.byte(bitmap,math.floor(index/8)+1) or 0
 return bit32.band(bit32.rshift(byte,7-index%8),1)==1
end
local function reconstructGlyf(transformed)
 local head=reader(transformed,1,#transformed,'glyf transformado')
 head.u16()
 local optionFlags=head.u16()
 local numGlyphs=head.u16()
 head.u16()
 local labels={'nContour','nPoints','flag','glyph','composite','bbox','instruction'}
 local sizes={}
 for i=1,7 do sizes[i]=head.u32() end
 local offset=head.pos
 local streams={}
 for i=1,7 do
  assert(offset+sizes[i]-1<=#transformed,'Fluxo '..labels[i]..' do glyf fora dos limites.')
  streams[i]=reader(transformed,offset,offset+sizes[i]-1,'fluxo '..labels[i])
  offset+=sizes[i]
 end
 local nContourS,nPointsS,flagS,glyphS,compositeS,bboxS,instrS=streams[1],streams[2],streams[3],streams[4],streams[5],streams[6],streams[7]
 local bboxBitmap=bboxS.bytes(math.floor((numGlyphs+31)/32)*4)
 local overlapBitmap=nil
 if optionFlags%2==1 then
  local size=math.floor((numGlyphs+7)/8)
  overlapBitmap=transformed:sub(offset,offset+size-1)
  assert(#overlapBitmap==size,'Bitmap de sobreposicao do glyf truncado.')
 end
 local glyphs,xMins={},{}
 for g=0,numGlyphs-1 do
  local nContours=nContourS.i16()
  local hasBbox=bitAt(bboxBitmap,g)
  local record
  if nContours==0 then
   assert(not hasBbox,'Glifo vazio com bbox explicito.')
   record=''
   xMins[g+1]=0
  elseif nContours>0 then
   local endPts,total={},0
   for c=1,nContours do total+=nPointsS.u255(); endPts[c]=total-1 end
   assert(total<=65535,'Glifo com pontos demais.')
   local points={}
   local x,y=0,0
   local minX,minY,maxX,maxY=32767,32767,-32768,-32768
   for p=1,total do
    local on,dx,dy=triplet(flagS.u8(),glyphS)
    x+=dx;y+=dy
    if x<minX then minX=x end; if x>maxX then maxX=x end
    if y<minY then minY=y end; if y>maxY then maxY=y end
    points[p]={on=on,dx=dx,dy=dy}
   end
   if total==0 then minX,minY,maxX,maxY=0,0,0,0 end
   local instructions=instrS.bytes(glyphS.u255())
   local bbox
   if hasBbox then bbox={bboxS.i16(),bboxS.i16(),bboxS.i16(),bboxS.i16()} else bbox={minX,minY,maxX,maxY} end
   xMins[g+1]=bbox[1]
   record=encodeSimple(nContours,endPts,points,instructions,bbox,overlapBitmap~=nil and bitAt(overlapBitmap,g))
  else
   assert(hasBbox,'Glifo composto sem bbox.')
   local bbox={bboxS.i16(),bboxS.i16(),bboxS.i16(),bboxS.i16()}
   xMins[g+1]=bbox[1]
   local parts={string.pack('>i2i2i2i2i2',-1,bbox[1],bbox[2],bbox[3],bbox[4])}
   local haveInstructions=false
   while true do
    local flags=compositeS.u16()
    local index=compositeS.u16()
    local argBytes=bit32.band(flags,1)==1 and 4 or 2
    if bit32.band(flags,8)~=0 then argBytes+=2 elseif bit32.band(flags,64)~=0 then argBytes+=4 elseif bit32.band(flags,128)~=0 then argBytes+=8 end
    parts[#parts+1]=string.pack('>I2I2',flags,index)..compositeS.bytes(argBytes)
    if bit32.band(flags,256)~=0 then haveInstructions=true end
    if bit32.band(flags,32)==0 then break end
   end
   if haveInstructions then
    local size=glyphS.u255()
    parts[#parts+1]=string.pack('>I2',size)..instrS.bytes(size)
   end
   record=table.concat(parts)
  end
  glyphs[g+1]=record
 end
 local loca={string.pack('>I4',0)}
 local body={}
 local total=0
 for i=1,numGlyphs do
  local rec=glyphs[i]
  local padding=(4-#rec%4)%4
  body[i]=rec..string.rep('\0',padding)
  total+=#rec+padding
  loca[i+1]=string.pack('>I4',total)
 end
 return table.concat(body),table.concat(loca),numGlyphs,xMins
end
local function reconstructHmtx(transformed,numGlyphs,numHMetrics,xMins)
 local r=reader(transformed,1,#transformed,'hmtx transformado')
 local flags=r.u8()
 assert(flags<4,'Flags de hmtx transformado invalidas.')
 local hasLsb=flags%2==0
 local hasLeft=bit32.band(flags,2)==0
 assert(numHMetrics>=1 and numHMetrics<=numGlyphs,'hhea.numberOfHMetrics invalido.')
 local advances={}
 for i=1,numHMetrics do advances[i]=r.u16() end
 local out={}
 for i=1,numHMetrics do
  local lsb=hasLsb and r.i16() or xMins[i]
  out[i]=string.pack('>I2i2',advances[i],lsb)
 end
 for i=numHMetrics+1,numGlyphs do
  local lsb=hasLeft and r.i16() or xMins[i]
  out[i]=string.pack('>i2',lsb)
 end
 return table.concat(out)
end
local function buildSfnt(flavor,entries)
 local numTables=#entries
 table.sort(entries,function(a,b) return a.tag<b.tag end)
 local searchRange,entrySelector=1,0
 while searchRange*2<=numTables do searchRange*=2;entrySelector+=1 end
 local directory={flavor..string.pack('>I2I2I2I2',numTables,searchRange*16,entrySelector,numTables*16-searchRange*16)}
 local body={}
 local offset=12+numTables*16
 for _,entry in ipairs(entries) do
  local padding=(4-#entry.data%4)%4
  directory[#directory+1]=entry.tag..string.pack('>I4I4I4',checksum(entry.data),offset,#entry.data)
  body[#body+1]=entry.data..string.rep('\0',padding)
  offset+=#entry.data+padding
 end
 return table.concat(directory)..table.concat(body)
end
function B.sfntFromWoff2(data)
 assert(#data>=48 and data:sub(1,4)=='wOF2','WOFF2 inválido ou truncado.')
 local flavor=data:sub(5,8)
 assert(flavor==string.char(0,1,0,0) or flavor=='OTTO' or flavor=='true','WOFF2 com sabor não suportado (coleções ttcf não são aceitas).')
 assert(readU32(data,8)<=#data,'WOFF2 declara tamanho maior que os bytes recebidos.')
 local numTables=readU16(data,12)
 assert(numTables>0 and numTables<=MAX_TABLES,'WOFF2 com número de tabelas inválido.')
 assert(readU32(data,16)<=B.MAX_BYTES,'WOFF2 expandido maior que o limite.')
 local totalCompressed=readU32(data,20)
 local pos=49
 local tables,byTag,total={},{},0
 for i=1,numTables do
  local flags=string.byte(data,pos)
  assert(flags,'Diretório WOFF2 truncado.')
  pos+=1
  local tagIndex=flags%64
  local tag
  if tagIndex==63 then tag=data:sub(pos,pos+3); assert(#tag==4,'Diretório WOFF2 truncado.'); pos+=4 else tag=WOFF2_TAGS[tagIndex+1] end
  local version=math.floor(flags/64)%4
  local origLength; origLength,pos=base128(data,pos)
  local transformed
  if tag=='glyf' or tag=='loca' then transformed=version==0 else transformed=version~=0 end
  local transformLength=nil
  if transformed then transformLength,pos=base128(data,pos) end
  assert(origLength<=B.MAX_BYTES and (transformLength or 0)<=B.MAX_BYTES,'Tabela WOFF2 com tamanhos inválidos.')
  assert(byTag[tag]==nil,'Tabela WOFF2 duplicada: '..tag)
  local entry={tag=tag,origLength=origLength,transformLength=transformLength,transformed=transformed,offset=total}
  total+=transformed and transformLength or origLength
  tables[i]=entry
  byTag[tag]=entry
 end
 assert(total<=B.MAX_BYTES,'WOFF2 descomprimido maior que o limite.')
 assert(pos+totalCompressed-1<=#data,'Fluxo comprimido WOFF2 fora dos limites.')
 if byTag.glyf and byTag.glyf.transformed then
  assert(byTag.loca and byTag.loca.transformed and byTag.loca.transformLength==0,'WOFF2 com glyf transformado exige loca transformado vazio.')
 end
 ensureDictionary()
 local stream=Brotli.decompress(data:sub(pos,pos+totalCompressed-1),total)
 assert(#stream==total,'Fluxo WOFF2 descomprimido com tamanho inesperado.')
 local entries,built={},{}
 local glyf,loca,numGlyphs,xMins
 local pendingHmtx=nil
 for _,entry in ipairs(tables) do
  local size=entry.transformed and entry.transformLength or entry.origLength
  local chunk=stream:sub(entry.offset+1,entry.offset+size)
  if entry.transformed then
   if entry.tag=='glyf' then glyf,loca,numGlyphs,xMins=reconstructGlyf(chunk)
   elseif entry.tag=='hmtx' then pendingHmtx=chunk
   elseif entry.tag~='loca' then error('Transformação WOFF2 não suportada para a tabela '..entry.tag..'.') end
  else
   assert(#chunk==entry.origLength,'Tabela WOFF2 '..entry.tag..' com tamanho inesperado.')
   local built_entry={tag=entry.tag,data=chunk}
   entries[#entries+1]=built_entry
   built[entry.tag]=built_entry
  end
 end
 if glyf then
  entries[#entries+1]={tag='glyf',data=glyf}
  entries[#entries+1]={tag='loca',data=loca}
  local head=built.head
  assert(head and #head.data>=54,'WOFF2 sem tabela head válida.')
  head.data=head.data:sub(1,50)..string.pack('>i2',1)..head.data:sub(53)
 end
 if pendingHmtx then
  assert(xMins,'hmtx transformado exige glyf transformado.')
  local hhea,maxp=built.hhea,built.maxp
  assert(hhea and #hhea.data>=36 and maxp and #maxp.data>=6,'WOFF2 sem hhea/maxp para reconstruir hmtx.')
  assert(readU16(maxp.data,4)==numGlyphs,'maxp.numGlyphs difere do glyf reconstruído.')
  entries[#entries+1]={tag='hmtx',data=reconstructHmtx(pendingHmtx,numGlyphs,readU16(hhea.data,34),xMins)}
 end
 return buildSfnt(flavor,entries)
end
function B.sfntFromWoff(data)
 assert(#data>=44 and data:sub(1,4)=='wOFF','WOFF inválido ou truncado.')
 local flavor=data:sub(5,8)
 assert(flavor==string.char(0,1,0,0) or flavor=='OTTO' or flavor=='true','WOFF com sabor não suportado.')
 local numTables=readU16(data,12)
 assert(numTables>0 and numTables<=MAX_TABLES,'WOFF com número de tabelas inválido.')
 assert(readU32(data,16)<=B.MAX_BYTES,'WOFF expandido maior que o limite.')
 local entries={}
 for i=0,numTables-1 do
  local base=44+i*20
  local tag=data:sub(base+1,base+4)
  assert(#tag==4,'Entrada de tabela WOFF truncada.')
  local offset=readU32(data,base+4)
  local compressed=readU32(data,base+8)
  local original=readU32(data,base+12)
  assert(offset+compressed<=#data,'Tabela WOFF fora dos limites.')
  assert(original<=B.MAX_BYTES and compressed<=original,'Tabela WOFF com tamanhos inválidos.')
  local chunk=data:sub(offset+1,offset+compressed)
  if compressed<original then chunk=B.inflate(chunk,false) end
  assert(#chunk==original,'Tabela WOFF descomprimida com tamanho inesperado.')
  entries[#entries+1]={tag=tag,data=chunk}
 end
 return buildSfnt(flavor,entries)
end
function B.open(data,options)
 options=options or {}
 if type(data)=='string' and data:sub(1,5)=='data:' then data=B.dataUrl(data) end
 assert(type(data)=='string','Fonte exige bytes.')
 assert(#data>=12,'Fonte truncada.')
 assert(#data<=B.MAX_BYTES,'Fonte maior que '..math.floor(B.MAX_BYTES/1048576)..' MiB.')
 local signature=data:sub(1,4)
 if signature=='wOF2' then data=B.sfntFromWoff2(data);signature=data:sub(1,4) end
 if signature=='wOFF' then data=B.sfntFromWoff(data);signature=data:sub(1,4) end
 local base=0
 if signature=='ttcf' then
  local count=readU32(data,8)
  local index=options.index or 1
  assert(count>0 and count<=256 and index>=1 and index<=count,'Índice fora da coleção de fontes.')
  base=readU32(data,12+(index-1)*4)
  assert(base+12<=#data,'Coleção de fontes truncada.')
  signature=data:sub(base+1,base+4)
 end
 local flavor
 if signature==string.char(0,1,0,0) or signature=='true' or signature=='typ1' then flavor='truetype'
 elseif signature=='OTTO' then flavor='cff'
 else error('Assinatura de fonte não reconhecida.') end
 local numTables=readU16(data,base+4)
 assert(numTables>0 and numTables<=MAX_TABLES,'Fonte com número de tabelas inválido.')
 local tables={}
 for i=0,numTables-1 do
  local entry=base+12+i*16
  local tag=data:sub(entry+1,entry+4)
  assert(#tag==4,'Diretório de tabelas truncado.')
  local offset=readU32(data,entry+8)
  local length=readU32(data,entry+12)
  assert(offset+length<=#data,'Tabela '..tag..' fora dos limites.')
  tables[tag]={offset=offset,length=length}
 end
 assert(tables.head,'Fonte sem tabela head.')
 assert(flavor~='cff' or tables['CFF '] or tables.CFF2,'OpenType CFF sem tabela de contornos.')
 return {data=data,buf=buffer.fromstring(data),size=#data,tables=tables,flavor=flavor,index=options.index or 1,fingerprint=B.fingerprint(data)}
end
local function bounds(font,offset,size)
 assert(type(offset)=='number' and offset>=0 and offset+size<=font.size,'Leitura fora dos limites da fonte.')
end
function B.u8(font,offset)
 bounds(font,offset,1)
 return buffer.readu8(font.buf,offset)
end
function B.i8(font,offset)
 local value=B.u8(font,offset)
 return value>=128 and value-256 or value
end
function B.u16(font,offset)
 bounds(font,offset,2)
 return buffer.readu8(font.buf,offset)*256+buffer.readu8(font.buf,offset+1)
end
function B.i16(font,offset)
 local value=B.u16(font,offset)
 return value>=32768 and value-65536 or value
end
function B.u24(font,offset)
 bounds(font,offset,3)
 local b=font.buf
 return (buffer.readu8(b,offset)*256+buffer.readu8(b,offset+1))*256+buffer.readu8(b,offset+2)
end
function B.u32(font,offset)
 bounds(font,offset,4)
 local b=font.buf
 return ((buffer.readu8(b,offset)*256+buffer.readu8(b,offset+1))*256+buffer.readu8(b,offset+2))*256+buffer.readu8(b,offset+3)
end
function B.i32(font,offset)
 local value=B.u32(font,offset)
 return value>=2147483648 and value-4294967296 or value
end
function B.fixed(font,offset) return B.i32(font,offset)/65536 end
function B.f2dot14(font,offset) return B.i16(font,offset)/16384 end
function B.tag(font,offset)
 bounds(font,offset,4)
 return buffer.readstring(font.buf,offset,4)
end
function B.chunk(font,offset,size)
 bounds(font,offset,size)
 return buffer.readstring(font.buf,offset,size)
end
function B.has(font,tag) return font.tables[tag]~=nil end
function B.locate(font,tag)
 local entry=font.tables[tag]
 if not entry then return nil end
 return entry.offset,entry.length
end
function B.need(font,tag)
 local offset,length=B.locate(font,tag)
 assert(offset,'Fonte sem tabela '..tag..'.')
 return offset,length
end
return B
