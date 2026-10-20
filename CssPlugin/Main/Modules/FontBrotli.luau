local Context=require(script.Parent.FontBrotliContext)
local Br={VERSION=1}
Br.MAX_OUTPUT=24*1024*1024
Br.dictionary=nil
local ORDER={1,2,3,4,0,5,17,6,16,7,8,9,10,11,12,13,14,15}
local PREFIX_LENGTH={2,2,2,3,2,2,2,4,2,2,2,3,2,2,2,4}
local PREFIX_VALUE={0,4,3,2,0,4,3,1,0,4,3,2,0,4,3,5}
local INSERT_RANGE={0,0,8,8,0,16,8,16,16}
local COPY_RANGE={0,8,0,8,16,0,16,8,16}
local INSERT_BITS={0,0,0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,7,8,9,10,12,14,24}
local INSERT_OFFSET={0,1,2,3,4,5,6,8,10,14,18,26,34,50,66,98,130,194,322,578,1090,2114,6210,22594}
local COPY_BITS={0,0,0,0,0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,7,8,9,10,24}
local COPY_OFFSET={2,3,4,5,6,7,8,9,10,12,14,18,22,30,38,54,70,102,134,198,326,582,1094,2118}
local BLOCK_BITS={2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,6,6,7,8,9,10,11,12,13,24}
local BLOCK_OFFSET={1,5,9,13,17,25,33,41,49,65,81,97,113,145,177,209,241,305,369,497,753,1265,2289,4337,8433,16625}
local WORD_BITS={10,10,11,11,10,10,10,10,10,9,9,8,7,7,8,7,7,6,6,5,5}
local WORD_OFFSET={}
local DICTIONARY_SIZE=0
for index=1,#WORD_BITS do
 WORD_OFFSET[index]=DICTIONARY_SIZE
 DICTIONARY_SIZE+=(index+3)*bit32.lshift(1,WORD_BITS[index])
end
Br.dictionarySize=DICTIONARY_SIZE
local ALPHABET='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local lookup
local function decode64(text)
 if not lookup then
  lookup={}
  for index=1,#ALPHABET do lookup[string.byte(ALPHABET,index)]=index-1 end
  lookup[45]=62
  lookup[95]=63
 end
 local out=buffer.create(math.max(8,math.floor(#text*3/4)+3))
 local length,accumulator,bits=0,0,0
 for index=1,#text do
  local code=string.byte(text,index)
  if code>32 and code~=61 then
   local value=lookup[code]
   assert(value,'Base64 invalido no motor brotli.')
   accumulator=accumulator*64+value
   bits+=6
   if bits>=8 then
    bits-=8
    local byte=math.floor(accumulator/2^bits)
    accumulator-=byte*2^bits
    buffer.writeu8(out,length,byte)
    length+=1
   end
  end
 end
 return out,length
end
Br.decode64=function(text)
 local out,length=decode64(text)
 return buffer.readstring(out,0,length)
end
local CONTEXT,CONTEXT_SIZE=decode64(Context.data)
assert(CONTEXT_SIZE==Context.size,'Tabela de contexto brotli corrompida.')
function Br.installDictionary(provider)
 assert(type(provider)=='table','installDictionary exige um provedor.')
 assert(type(provider.data)=='string' and #provider.data==DICTIONARY_SIZE,'Dicionario brotli com tamanho inesperado.')
 assert(type(provider.transform)=='function','Dicionario brotli exige transform(word,id).')
 Br.dictionary=provider
 return true
end
function Br.hasDictionary() return Br.dictionary~=nil end
function Br.decompress(data,sizeHint)
 assert(type(data)=='string' and #data>0,'Fluxo brotli vazio.')
 local input=buffer.fromstring(data)
 local size=#data
 local pos=0
 local hold=0
 local bits=0
 local overrun=0
 local function fill(count)
  while bits<count do
   local byte=0
   if pos<size then byte=buffer.readu8(input,pos) else overrun+=1;assert(overrun<=8,'Fluxo brotli truncado.') end
   pos+=1
   hold+=byte*2^bits
   bits+=8
  end
 end
 local function take(count)
  if count==0 then return 0 end
  fill(count)
  local value=hold%2^count
  hold=(hold-value)/2^count
  bits-=count
  return value
 end
 local function align()
  local drop=bits%8
  if drop>0 then take(drop) end
 end
 local function readByte()
  if bits>=8 then
   local value=hold%256
   hold=(hold-value)/256
   bits-=8
   return value
  end
  assert(pos<size,'Fluxo brotli truncado.')
  local value=buffer.readu8(input,pos)
  pos+=1
  return value
 end
 local capacity=math.max(65536,math.min(sizeHint or 0,Br.MAX_OUTPUT))
 local out=buffer.create(capacity)
 local length=0
 local function reserve(extra)
  if length+extra<=capacity then return end
  assert(length+extra<=Br.MAX_OUTPUT,'Saida brotli maior que o limite.')
  local target=capacity
  while target<length+extra do target*=2 end
  if target>Br.MAX_OUTPUT then target=Br.MAX_OUTPUT end
  local bigger=buffer.create(target)
  buffer.copy(bigger,0,out,0,length)
  out=bigger
  capacity=target
 end
 local function push(byte)
  reserve(1)
  buffer.writeu8(out,length,byte)
  length+=1
 end
 local function build(lengths,alphabet)
  local counts=table.create(16,0)
  local total=0
  local last=0
  for index=1,alphabet do
   local width=lengths[index] or 0
   if width>0 then
    assert(width<=15,'Comprimento Huffman brotli invalido.')
    counts[width]+=1
    total+=1
    last=index-1
   end
  end
  if total<=1 then return {single=last} end
  local offsets=table.create(16,0)
  local running=0
  for width=1,15 do offsets[width]=running;running+=counts[width] end
  local symbols=table.create(running,0)
  for index=1,alphabet do
   local width=lengths[index] or 0
   if width>0 then offsets[width]+=1;symbols[offsets[width]]=index-1 end
  end
  return {counts=counts,symbols=symbols}
 end
 local function decode(tree)
  local single=tree.single
  if single then return single end
  local counts=tree.counts
  local symbols=tree.symbols
  local code,first,index=0,0,1
  for width=1,15 do
   code+=take(1)
   local count=counts[width]
   if code-first<count then return symbols[index+code-first] end
   index+=count
   first=(first+count)*2
   code*=2
  end
  error('Codigo Huffman brotli invalido.')
 end
 local function readPrefix(alphabet)
  local kind=take(2)
  if kind==1 then
   local width=0
   while bit32.lshift(1,width)<alphabet do width+=1 end
   local count=take(2)+1
   local symbols=table.create(count,0)
   for index=1,count do
    local symbol=take(width)
    assert(symbol<alphabet,'Simbolo fora do alfabeto brotli.')
    for check=1,index-1 do assert(symbols[check]~=symbol,'Simbolo repetido em codigo simples brotli.') end
    symbols[index]=symbol
   end
   if count==1 then return {single=symbols[1]} end
   local lengths={}
   if count==2 then
    lengths[symbols[1]+1]=1
    lengths[symbols[2]+1]=1
   elseif count==3 then
    lengths[symbols[1]+1]=1
    lengths[symbols[2]+1]=2
    lengths[symbols[3]+1]=2
   elseif take(1)==1 then
    lengths[symbols[1]+1]=1
    lengths[symbols[2]+1]=2
    lengths[symbols[3]+1]=3
    lengths[symbols[4]+1]=3
   else
    for index=1,4 do lengths[symbols[index]+1]=2 end
   end
   return build(lengths,alphabet)
  end
  local codeLengths=table.create(18,0)
  local space=32
  local nonzero=0
  local index=kind+1
  while index<=18 and space>0 do
   fill(4)
   local peek=hold%16
   take(PREFIX_LENGTH[peek+1])
   local value=PREFIX_VALUE[peek+1]
   codeLengths[ORDER[index]+1]=value
   if value~=0 then
    space-=bit32.rshift(32,value)
    nonzero+=1
   end
   index+=1
  end
  assert(nonzero==1 or space==0,'Tabela de comprimentos brotli invalida.')
  local lengthTree=build(codeLengths,18)
  local lengths=table.create(alphabet,0)
  local symbol=1
  local previous=8
  local repeated=0
  local repeatLength=0
  local remaining=32768
  while symbol<=alphabet and remaining>0 do
   local value=decode(lengthTree)
   if value<16 then
    repeated=0
    lengths[symbol]=value
    symbol+=1
    if value~=0 then
     previous=value
     remaining-=bit32.rshift(32768,value)
    end
   else
    local extra=value-14
    local target=0
    if value==16 then target=previous end
    if repeatLength~=target then
     repeated=0
     repeatLength=target
    end
    local old=repeated
    if repeated>0 then repeated=(repeated-2)*bit32.lshift(1,extra) end
    repeated+=take(extra)+3
    local delta=repeated-old
    assert(symbol+delta-1<=alphabet,'Repeticao de comprimentos brotli fora do alfabeto.')
    for _=1,delta do
     lengths[symbol]=repeatLength
     symbol+=1
    end
    if repeatLength~=0 then remaining-=delta*bit32.lshift(1,15-repeatLength) end
   end
  end
  assert(remaining==0,'Espaco Huffman brotli inconsistente.')
  return build(lengths,alphabet)
 end
 local function readTypes()
  if take(1)==0 then return 1 end
  local width=take(3)
  return bit32.lshift(1,width)+1+take(width)
 end
 local function readContextMap(entries,trees)
  local map=table.create(entries,0)
  for index=1,entries do map[index]=0 end
  if trees<=1 then return map end
  local maxRun=0
  if take(1)==1 then maxRun=take(4)+1 end
  local tree=readPrefix(trees+maxRun)
  local index=1
  while index<=entries do
   local value=decode(tree)
   if value==0 then
    map[index]=0
    index+=1
   elseif value<=maxRun then
    local run=bit32.lshift(1,value)+take(value)
    assert(index+run-1<=entries,'Mapa de contexto brotli grande demais.')
    for _=1,run do
     map[index]=0
     index+=1
    end
   else
    map[index]=value-maxRun
    index+=1
   end
  end
  if take(1)==1 then
   local mtf=table.create(256,0)
   for value=0,255 do mtf[value+1]=value end
   for position=1,entries do
    local slot=map[position]+1
    local value=mtf[slot]
    table.remove(mtf,slot)
    table.insert(mtf,1,value)
    map[position]=value
   end
  end
  return map
 end
 local function blockLength(tree)
  local code=decode(tree)
  assert(code>=0 and code<26,'Codigo de tamanho de bloco brotli invalido.')
  return BLOCK_OFFSET[code+1]+take(BLOCK_BITS[code+1])
 end
 local function category()
  local state={count=readTypes(),type=0,previous=1,left=268435456}
  if state.count>=2 then
   state.typeTree=readPrefix(state.count+2)
   state.countTree=readPrefix(26)
   state.left=blockLength(state.countTree)
  end
  return state
 end
 local function switchBlock(state)
  local symbol=decode(state.typeTree)
  local target
  if symbol==0 then target=state.previous
  elseif symbol==1 then target=(state.type+1)%state.count
  else target=symbol-2 end
  assert(target<state.count,'Tipo de bloco brotli fora da faixa.')
  state.previous=state.type
  state.type=target
  state.left=blockLength(state.countTree)
 end
 local wbits
 if take(1)==0 then wbits=16
 else
  local value=take(3)
  if value~=0 then wbits=17+value
  else
   value=take(3)
   if value==0 then wbits=17 else wbits=8+value end
  end
 end
 assert(wbits>=10 and wbits<=24,'Janela brotli invalida.')
 local maxBackward=bit32.lshift(1,wbits)-16
 local distances={4,11,15,16}
 local p1,p2=0,0
 while true do
  local isLast=take(1)==1
  if isLast and take(1)==1 then break end
  local nibbles=take(2)
  if nibbles==3 then
   assert(not isLast,'Metadados brotli no ultimo metabloco.')
   assert(take(1)==0,'Bit reservado brotli invalido.')
   local count=take(2)
   local skip=0
   if count>0 then skip=take(count*8)+1 end
   align()
   for _=1,skip do readByte() end
  else
   local metaLength=take((nibbles+4)*4)+1
   local uncompressed=false
   if not isLast then uncompressed=take(1)==1 end
   if uncompressed then
    align()
    reserve(metaLength)
    for _=1,metaLength do
     local byte=readByte()
     buffer.writeu8(out,length,byte)
     length+=1
     p2=p1
     p1=byte
    end
   else
    local literals=category()
    local commands=category()
    local dists=category()
    local postfix=take(2)
    local direct=take(4)*bit32.lshift(1,postfix)
    local modes=table.create(literals.count,0)
    for index=1,literals.count do modes[index]=take(2) end
    local literalTrees=readTypes()
    local literalMap=readContextMap(64*literals.count,literalTrees)
    local distanceTrees=readTypes()
    local distanceMap=readContextMap(4*dists.count,distanceTrees)
    local literalCodes=table.create(literalTrees,nil)
    for index=1,literalTrees do literalCodes[index]=readPrefix(256) end
    local commandCodes=table.create(commands.count,nil)
    for index=1,commands.count do commandCodes[index]=readPrefix(704) end
    local distanceAlphabet=16+direct+bit32.lshift(48,postfix)
    local distanceCodes=table.create(distanceTrees,nil)
    for index=1,distanceTrees do distanceCodes[index]=readPrefix(distanceAlphabet) end
    local produced=0
    while produced<metaLength do
     if commands.left==0 then switchBlock(commands) end
     commands.left-=1
     local code=decode(commandCodes[commands.type+1])
     local range=bit32.rshift(code,6)
     local implicit=range<2
     if not implicit then range-=2 end
     local insertCode=INSERT_RANGE[range+1]+bit32.band(bit32.rshift(code,3),7)
     local copyCode=COPY_RANGE[range+1]+bit32.band(code,7)
     local insertLength=INSERT_OFFSET[insertCode+1]+take(INSERT_BITS[insertCode+1])
     local copyLength=COPY_OFFSET[copyCode+1]+take(COPY_BITS[copyCode+1])
     assert(produced+insertLength<=metaLength,'Insercao brotli maior que o metabloco.')
     if insertLength>0 then
      reserve(insertLength)
      for _=1,insertLength do
       if literals.left==0 then switchBlock(literals) end
       literals.left-=1
       local mode=modes[literals.type+1]
       local id
       if mode==0 then id=p1%64
       elseif mode==1 then id=math.floor(p1/4)
       elseif mode==2 then id=bit32.bor(buffer.readu8(CONTEXT,p1),buffer.readu8(CONTEXT,256+p2))
       else id=bit32.bor(buffer.readu8(CONTEXT,512+p1),buffer.readu8(CONTEXT,768+p2)) end
       local slot=literalMap[literals.type*64+id+1]
       local byte=decode(literalCodes[slot+1])
       buffer.writeu8(out,length,byte)
       length+=1
       p2=p1
       p1=byte
      end
      produced+=insertLength
     end
     if produced>=metaLength then break end
     local distance
     local fromRing=true
     if implicit then distance=distances[1]
     else
      if dists.left==0 then switchBlock(dists) end
      dists.left-=1
      local context=copyLength>4 and 3 or copyLength-2
      local slot=distanceMap[dists.type*4+context+1]
      local code2=decode(distanceCodes[slot+1])
      if code2==0 then distance=distances[1]
      elseif code2<4 then distance=distances[code2+1];fromRing=false
      elseif code2<16 then
       local base=distances[code2<10 and 1 or 2]
       local step=(code2-4)%6
       local delta=math.floor(step/2)+1
       if step%2==0 then distance=base-delta else distance=base+delta end
       fromRing=false
      elseif code2<16+direct then
       distance=code2-15
       fromRing=false
      else
       local mask=bit32.lshift(1,postfix)-1
       local value=code2-direct-16
       local extraBits=1+bit32.rshift(value,postfix+1)
       local high=bit32.rshift(value,postfix)
       local low=bit32.band(value,mask)
       local offset=bit32.lshift(2+bit32.band(high,1),extraBits)-4
       distance=bit32.lshift(offset+take(extraBits),postfix)+low+direct+1
       fromRing=false
      end
     end
     assert(distance>=1,'Distancia brotli invalida.')
     local allowed=math.min(length,maxBackward)
     if distance<=allowed then
      assert(produced+copyLength<=metaLength,'Copia brotli maior que o metabloco.')
      reserve(copyLength)
      local start=length-distance
      for offset=0,copyLength-1 do
       buffer.writeu8(out,length,buffer.readu8(out,start+offset))
       length+=1
      end
      produced+=copyLength
      if not fromRing then
       table.insert(distances,1,distance)
       distances[5]=nil
      end
     else
      local provider=Br.dictionary
      assert(provider,'Fluxo brotli usa o dicionario estatico; instale FontBrotliDictionary para ler esta fonte.')
      assert(copyLength>=4 and copyLength<=24,'Palavra de dicionario brotli com tamanho invalido.')
      local slot=copyLength-3
      local span=bit32.lshift(1,WORD_BITS[slot])
      local wordIndex=distance-allowed-1
      local id=wordIndex%span
      local transform=math.floor(wordIndex/span)
      assert(transform<=120,'Transformacao de dicionario brotli invalida.')
      local at=WORD_OFFSET[slot]+id*copyLength
      local text=provider.transform(string.sub(provider.data,at+1,at+copyLength),transform)
      assert(type(text)=='string','Transformacao de dicionario brotli devolveu valor invalido.')
      assert(produced+#text<=metaLength,'Palavra de dicionario brotli maior que o metabloco.')
      reserve(#text)
      for offset=1,#text do
       buffer.writeu8(out,length,string.byte(text,offset))
       length+=1
      end
      produced+=#text
     end
     if length>=2 then
      p1=buffer.readu8(out,length-1)
      p2=buffer.readu8(out,length-2)
     elseif length==1 then
      p1=buffer.readu8(out,0)
      p2=0
     end
    end
    assert(produced==metaLength,'Metabloco brotli incompleto.')
   end
  end
  if isLast then break end
 end
 return buffer.readstring(out,0,length)
end
return Br
