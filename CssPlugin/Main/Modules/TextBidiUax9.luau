local Seg=require(script.Parent.UnicodeSegmentation)
local B={VERSION=1,UAX9='15.1.0',MAX_DEPTH=125}
local table_=table
local classes={}
local function add(class,list)for _,r in ipairs(list)do classes[#classes+1]={r[1],r[2]or r[1],class}end end
add('B',{{0xa},{0xd},{0x1c,0x1e},{0x85},{0x2029}})
add('S',{{0x9},{0xb},{0x1f}})
add('WS',{{0xc},{0x20},{0x1680},{0x2000,0x200a},{0x2028},{0x205f},{0x3000}})
add('BN',{{0x0,0x8},{0xe,0x1b},{0x7f,0x84},{0x86,0x9f},{0xad},{0x180e},{0x200b,0x200d},{0x2060,0x2064},{0x206a,0x206f},{0xfeff},{0xfff0,0xfff8},{0xe0000,0xe0fff}})
add('LRE',{{0x202a}});add('RLE',{{0x202b}});add('PDF',{{0x202c}});add('LRO',{{0x202d}});add('RLO',{{0x202e}})
add('LRI',{{0x2066}});add('RLI',{{0x2067}});add('FSI',{{0x2068}});add('PDI',{{0x2069}})
add('L',{{0x200e}});add('R',{{0x200f}});add('AL',{{0x61c}})
add('EN',{{0x30,0x39},{0xb2,0xb3},{0xb9},{0x6f0,0x6f9},{0x2070},{0x2074,0x2079},{0x2080,0x2089},{0x2488,0x249b},{0xff10,0xff19},{0x1d7ce,0x1d7ff},{0x1f100,0x1f10a}})
add('ES',{{0x2b},{0x2d},{0x207a,0x207b},{0x208a,0x208b},{0x2212},{0xfb29},{0xfe62,0xfe63},{0xff0b},{0xff0d}})
add('ET',{{0x23,0x25},{0xa2,0xa5},{0xb0,0xb1},{0x58f},{0x609,0x60a},{0x66a},{0x9f2,0x9f3},{0x9fb},{0xaf1},{0xbf9},{0xe3f},{0x17db},{0x2030,0x2034},{0x20a0,0x20c0},{0x212e},{0x2213},{0xa838,0xa839},{0xfe5f},{0xfe69,0xfe6a},{0xff03,0xff05},{0xffe0,0xffe1},{0xffe5,0xffe6}})
add('CS',{{0x2c},{0x2e,0x2f},{0x3a},{0xa0},{0x60c},{0x202f},{0x2044},{0xfe50},{0xfe52},{0xfe55},{0xff0c},{0xff0e,0xff0f},{0xff1a}})
add('AN',{{0x600,0x605},{0x660,0x669},{0x66b,0x66c},{0x6dd},{0x890,0x891},{0x8e2},{0x10d30,0x10d39},{0x10e60,0x10e7e}})
add('AL',{{0x608},{0x60b},{0x60d},{0x61b},{0x61d,0x64a},{0x66d,0x66f},{0x671,0x6d5},{0x6e5,0x6e6},{0x6ee,0x6ef},{0x6fa,0x70d},{0x70f,0x710},{0x712,0x72f},{0x74b,0x7a5},{0x7b1,0x7bf},{0x860,0x88f},{0x8a0,0x8c9},{0xfb50,0xfd3d},{0xfd40,0xfdcf},{0xfdf0,0xfdfc},{0xfe70,0xfefc},{0x10d00,0x10d23},{0x10ec0,0x10eff},{0x10f30,0x10f45},{0x10f51,0x10f59},{0x1ec70,0x1ecbf},{0x1ed00,0x1ed4f},{0x1ee00,0x1eeff}})
add('R',{{0x5be},{0x5c0},{0x5c3},{0x5c6},{0x5c8,0x5ff},{0x7c0,0x7ea},{0x7f4,0x7f5},{0x7fa,0x7ff},{0x800,0x815},{0x81a},{0x824},{0x828},{0x82e,0x858},{0x85c,0x85f},{0x200f},{0xfb1d},{0xfb1f,0xfb28},{0xfb2a,0xfb4f},{0x10800,0x10cff},{0x10d40,0x10ebf},{0x10f00,0x10f2f},{0x10f70,0x10fff},{0x1e800,0x1e8cf},{0x1e900,0x1e943},{0x1e94b,0x1e95f},{0x1e960,0x1ec6f},{0x1ecc0,0x1ecff},{0x1ed50,0x1edff},{0x1ef00,0x1efff}})
add('ON',{{0x21,0x22},{0x26,0x2a},{0x3b,0x40},{0x5b,0x60},{0x7b,0x7e},{0xa1},{0xa6,0xa9},{0xab,0xac},{0xae,0xaf},{0xb4},{0xb6,0xb8},{0xbb,0xbf},{0xd7},{0xf7},{0x2b9,0x2ba},{0x2c2,0x2cf},{0x2d2,0x2df},{0x2e5,0x2ed},{0x2ef,0x2ff},{0x374,0x375},{0x37e},{0x384,0x385},{0x387},{0x3f6},{0x58a},{0x58d,0x58e},{0x606,0x607},{0x60e,0x60f},{0x6de},{0x6e9},{0xbf3,0xbf8},{0xbfa},{0xc78,0xc7e},{0xf3a,0xf3d},{0x1390,0x1399},{0x1400},{0x169b,0x169c},{0x17f0,0x17f9},{0x1800,0x180a},{0x1940},{0x1944,0x1945},{0x19de,0x19ff},{0x1fbd},{0x1fbf,0x1fc1},{0x1fcd,0x1fcf},{0x1fdd,0x1fdf},{0x1fed,0x1fef},{0x1ffd,0x1ffe},{0x2010,0x2027},{0x2035,0x2043},{0x2045,0x205e},{0x207c,0x207e},{0x208c,0x208e},{0x2100,0x2101},{0x2103,0x2106},{0x2108,0x2109},{0x2114},{0x2116,0x2118},{0x211e,0x2123},{0x2125},{0x2127},{0x2129},{0x213a,0x213b},{0x2140,0x2144},{0x214a,0x214d},{0x2150,0x215f},{0x2189,0x218b},{0x2190,0x2211},{0x2214,0x2335},{0x237b,0x2394},{0x2396,0x2426},{0x2440,0x244a},{0x2460,0x2487},{0x24ea,0x26ab},{0x26ad,0x27ff},{0x2900,0x2b73},{0x2b76,0x2b95},{0x2b97,0x2bff},{0x2ce5,0x2cea},{0x2cf9,0x2cff},{0x2e00,0x2e5d},{0x2e80,0x2e99},{0x2e9b,0x2ef3},{0x2f00,0x2fd5},{0x2ff0,0x2ffb},{0x3001,0x3004},{0x3008,0x3020},{0x3030},{0x3036,0x3037},{0x303d,0x303f},{0x309b,0x309c},{0x30a0},{0x30fb},{0x31c0,0x31e3},{0x321d,0x321e},{0x3250},{0x3251,0x325f},{0x327c,0x327e},{0x32b1,0x32bf},{0x32cc,0x32cf},{0x3377,0x337a},{0x33de,0x33df},{0x33ff},{0x4dc0,0x4dff},{0xa490,0xa4c6},{0xa60d,0xa60f},{0xa673},{0xa67e,0xa67f},{0xa700,0xa716},{0xa720,0xa721},{0xa788},{0xa828,0xa82b},{0xa874,0xa877},{0xfd3e,0xfd3f},{0xfdfd},{0xfe10,0xfe19},{0xfe30,0xfe4f},{0xfe51},{0xfe54},{0xfe56,0xfe5e},{0xfe60,0xfe61},{0xfe64,0xfe66},{0xfe68},{0xfe6b},{0xff01,0xff02},{0xff06,0xff0a},{0xff1b,0xff20},{0xff3b,0xff40},{0xff5b,0xff65},{0xffe2,0xffe4},{0xffe8,0xffee},{0xfff9,0xfffd},{0x1d200,0x1d241},{0x1d245},{0x1d300,0x1d356},{0x1d6db},{0x1d715},{0x1d74f},{0x1d789},{0x1d7c3},{0x1eef0,0x1eef1},{0x1f000,0x1f02b},{0x1f030,0x1f093},{0x1f0a0,0x1f0f5},{0x1f10b,0x1f10f},{0x1f12f},{0x1f16a,0x1f16f},{0x1f1ad},{0x1f260,0x1f265},{0x1f300,0x1f3fa},{0x1f400,0x1f6d7},{0x1f6dc,0x1f6ec},{0x1f6f0,0x1f6fc},{0x1f700,0x1f776},{0x1f77b,0x1f7d9},{0x1f7e0,0x1f7eb},{0x1f7f0},{0x1f800,0x1f80b},{0x1f810,0x1f847},{0x1f850,0x1f859},{0x1f860,0x1f887},{0x1f890,0x1f8ad},{0x1f8b0,0x1f8b1},{0x1f900,0x1fa53},{0x1fa60,0x1fa6d},{0x1fa70,0x1fa7c},{0x1fa80,0x1fa88},{0x1fa90,0x1fabd},{0x1fabf,0x1fac5},{0x1face,0x1fadb},{0x1fae0,0x1fae8},{0x1faf0,0x1faf8},{0x1fb00,0x1fb92},{0x1fb94,0x1fbca}})
table_.sort(classes,function(a,b)return a[1]<b[1]end)
local nsmExtra={[0x300]=true}
function B.class(cp)
 local c=Seg.lookup(classes,cp)
 if c and c~=true then return c end
 if Seg.graphemeClass(cp)=='Extend'and cp~=0x200c and cp~=0x200d and not(cp>=0x1f3fb and cp<=0x1f3ff)then return 'NSM'end
 if cp>=0x590 and cp<=0x5ff or cp>=0x7c0 and cp<=0x8ff and not(cp>=0x860 and cp<=0x8ff)then return 'R'end
 if cp>=0x600 and cp<=0x7bf or cp>=0x860 and cp<=0x8ff then return 'AL'end
 if cp>=0x10800 and cp<=0x10fff then return 'R'end
 return 'L'
end
local mirrors={[0x28]=0x29,[0x29]=0x28,[0x3c]=0x3e,[0x3e]=0x3c,[0x5b]=0x5d,[0x5d]=0x5b,[0x7b]=0x7d,[0x7d]=0x7b,[0xab]=0xbb,[0xbb]=0xab,[0x2039]=0x203a,[0x203a]=0x2039,[0x2045]=0x2046,[0x2046]=0x2045,[0x207d]=0x207e,[0x207e]=0x207d,[0x208d]=0x208e,[0x208e]=0x208d,[0x2208]=0x220b,[0x220b]=0x2208,[0x2264]=0x2265,[0x2265]=0x2264,[0x2282]=0x2283,[0x2283]=0x2282,[0x2286]=0x2287,[0x2287]=0x2286,[0x2308]=0x2309,[0x2309]=0x2308,[0x230a]=0x230b,[0x230b]=0x230a,[0x2329]=0x232a,[0x232a]=0x2329,[0x2768]=0x2769,[0x2769]=0x2768,[0x276a]=0x276b,[0x276b]=0x276a,[0x276c]=0x276d,[0x276d]=0x276c,[0x276e]=0x276f,[0x276f]=0x276e,[0x2770]=0x2771,[0x2771]=0x2770,[0x2772]=0x2773,[0x2773]=0x2772,[0x2774]=0x2775,[0x2775]=0x2774,[0x27e6]=0x27e7,[0x27e7]=0x27e6,[0x27e8]=0x27e9,[0x27e9]=0x27e8,[0x27ea]=0x27eb,[0x27eb]=0x27ea,[0x2983]=0x2984,[0x2984]=0x2983,[0x2985]=0x2986,[0x2986]=0x2985,[0x3008]=0x3009,[0x3009]=0x3008,[0x300a]=0x300b,[0x300b]=0x300a,[0x300c]=0x300d,[0x300d]=0x300c,[0x300e]=0x300f,[0x300f]=0x300e,[0x3010]=0x3011,[0x3011]=0x3010,[0x3014]=0x3015,[0x3015]=0x3014,[0x3016]=0x3017,[0x3017]=0x3016,[0x3018]=0x3019,[0x3019]=0x3018,[0x301a]=0x301b,[0x301b]=0x301a,[0xfe59]=0xfe5a,[0xfe5a]=0xfe59,[0xfe5b]=0xfe5c,[0xfe5c]=0xfe5b,[0xfe5d]=0xfe5e,[0xfe5e]=0xfe5d,[0xff08]=0xff09,[0xff09]=0xff08,[0xff1c]=0xff1e,[0xff1e]=0xff1c,[0xff3b]=0xff3d,[0xff3d]=0xff3b,[0xff5b]=0xff5d,[0xff5d]=0xff5b,[0xff5f]=0xff60,[0xff60]=0xff5f,[0xff62]=0xff63,[0xff63]=0xff62}
local openers={[0x28]=0x29,[0x5b]=0x5d,[0x7b]=0x7d,[0x2045]=0x2046,[0x207d]=0x207e,[0x208d]=0x208e,[0x2308]=0x2309,[0x230a]=0x230b,[0x2329]=0x232a,[0x2768]=0x2769,[0x276a]=0x276b,[0x276c]=0x276d,[0x276e]=0x276f,[0x2770]=0x2771,[0x2772]=0x2773,[0x2774]=0x2775,[0x27e6]=0x27e7,[0x27e8]=0x27e9,[0x27ea]=0x27eb,[0x2983]=0x2984,[0x2985]=0x2986,[0x3008]=0x3009,[0x300a]=0x300b,[0x300c]=0x300d,[0x300e]=0x300f,[0x3010]=0x3011,[0x3014]=0x3015,[0x3016]=0x3017,[0x3018]=0x3019,[0x301a]=0x301b,[0xfe59]=0xfe5a,[0xfe5b]=0xfe5c,[0xfe5d]=0xfe5e,[0xff08]=0xff09,[0xff3b]=0xff3d,[0xff5b]=0xff5d,[0xff5f]=0xff60,[0xff62]=0xff63}
function B.mirror(cp)return mirrors[cp]end
function B.mirrored(text)
 local out={}
 for _,cp in utf8.codes(text)do out[#out+1]=utf8.char(mirrors[cp]or cp)end
 return table_.concat(out)
end
local function isolateInitiator(c)return c=='LRI'or c=='RLI'or c=='FSI'end
local function strongLevelFor(c)return (c=='R'or c=='AL')and 1 or c=='L'and 0 or nil end
local function matchingPDI(types,i,n)
 local depth=1
 for j=i+1,n do
  local t=types[j]
  if isolateInitiator(t)then depth+=1 elseif t=='PDI'then depth-=1;if depth==0 then return j end end
 end
 return n+1
end
function B.paragraphLevel(types,first,last)
 local i=first
 while i<=last do
  local t=types[i]
  if t=='L'then return 0 elseif t=='R'or t=='AL'then return 1
  elseif isolateInitiator(t)then i=matchingPDI(types,i,last)
  elseif t=='B'then break end
  i+=1
 end
 return 0
end
local function least(level,rtl)
 if rtl then return level%2==0 and level+1 or level+2 end
 return level%2==1 and level+1 or level+2
end
function B.resolve(points,baseLevel)
 local n=#points
 local orig={};for i=1,n do orig[i]=B.class(points[i])end
 local types=table_.clone(orig)
 if baseLevel==nil then baseLevel=B.paragraphLevel(types,1,n)end
 local levels={}
 local stack={{level=baseLevel,override=nil,isolate=false}}
 local overflowIsolates,overflowEmbeddings,validIsolates=0,0,0
 local function top()return stack[#stack]end
 for i=1,n do
  local t=types[i]
  if t=='RLE'or t=='LRE'or t=='RLO'or t=='LRO'then
   local rtl=t=='RLE'or t=='RLO';local new=least(top().level,rtl)
   levels[i]=top().level
   if new<=B.MAX_DEPTH and overflowIsolates==0 and overflowEmbeddings==0 then
    stack[#stack+1]={level=new,override=(t=='RLO'and 'R')or(t=='LRO'and 'L')or nil,isolate=false}
   elseif overflowIsolates==0 then overflowEmbeddings+=1 end
   types[i]='BN'
  elseif t=='RLI'or t=='LRI'or t=='FSI'then
   local rtl=t=='RLI'
   if t=='FSI'then local finish=matchingPDI(types,i,n);rtl=B.paragraphLevel(types,i+1,finish-1)==1 end
   levels[i]=top().level
   if top().override then types[i]=top().override end
   local new=least(top().level,rtl)
   if new<=B.MAX_DEPTH and overflowIsolates==0 and overflowEmbeddings==0 then
    validIsolates+=1;stack[#stack+1]={level=new,override=nil,isolate=true}
   else overflowIsolates+=1 end
  elseif t=='PDI'then
   if overflowIsolates>0 then overflowIsolates-=1
   elseif validIsolates>0 then
    overflowEmbeddings=0
    while not top().isolate do table_.remove(stack)end
    table_.remove(stack);validIsolates-=1
   end
   levels[i]=top().level
   if top().override then types[i]=top().override end
  elseif t=='PDF'then
   levels[i]=top().level
   if overflowIsolates>0 then
   elseif overflowEmbeddings>0 then overflowEmbeddings-=1
   elseif not top().isolate and #stack>=2 then table_.remove(stack)end
   types[i]='BN'
  elseif t=='B'then levels[i]=baseLevel
  elseif t=='BN'then levels[i]=top().level
  else
   levels[i]=top().level
   if top().override then types[i]=top().override end
  end
 end
 local runs={}
 do
  local i=1
  while i<=n do
   local level=levels[i];local j=i
   while j<n and(levels[j+1]==level or types[j+1]=='BN')do j+=1 end
   while j>i and types[j]=='BN'and levels[j]~=level do j-=1 end
   runs[#runs+1]={first=i,last=j,level=level};i=j+1
  end
 end
 local sequences={}
 local runByStart={};for _,r in ipairs(runs)do runByStart[r.first]=r end
 local consumed={}
 for _,run in ipairs(runs)do
  if not consumed[run]then
   local seq={runs={run},level=run.level};consumed[run]=true
   local current=run
   while true do
    local lastIndex=current.last
    while lastIndex>current.first and types[lastIndex]=='BN'do lastIndex-=1 end
    if isolateInitiator(types[lastIndex])then
     local pdi=matchingPDI(types,lastIndex,n)
     local nextRun=pdi<=n and runByStart[pdi]
     if nextRun and not consumed[nextRun]then seq.runs[#seq.runs+1]=nextRun;consumed[nextRun]=true;current=nextRun else break end
    else break end
   end
   sequences[#sequences+1]=seq
  end
 end
 for _,seq in ipairs(sequences)do
  local indices={}
  for _,run in ipairs(seq.runs)do for i=run.first,run.last do if types[i]~='BN'then indices[#indices+1]=i end end end
  if #indices>0 then
   local level=seq.level
   local firstIndex=indices[1];local lastIndex=indices[#indices]
   local before=firstIndex-1;while before>=1 and types[before]=='BN'do before-=1 end
   local prevLevel=before>=1 and levels[before]or baseLevel
   local after=lastIndex+1;while after<=n and types[after]=='BN'do after+=1 end
   local nextLevel=(after<=n and not isolateInitiator(types[lastIndex]))and levels[after]or baseLevel
   if isolateInitiator(types[lastIndex])then nextLevel=baseLevel end
   local sos=math.max(level,prevLevel)%2==1 and 'R'or 'L'
   local eos=math.max(level,nextLevel)%2==1 and 'R'or 'L'
   local seqTypes={};for k,i in ipairs(indices)do seqTypes[k]=types[i]end
   local m=#seqTypes
   for k=1,m do if seqTypes[k]=='NSM'then local p=k>1 and seqTypes[k-1]or sos;if isolateInitiator(p)or p=='PDI'then seqTypes[k]='ON'else seqTypes[k]=p end end end
   local lastStrong=sos
   for k=1,m do local t=seqTypes[k];if t=='L'or t=='R'or t=='AL'then lastStrong=t elseif t=='EN'and lastStrong=='AL'then seqTypes[k]='AN'end end
   for k=1,m do if seqTypes[k]=='AL'then seqTypes[k]='R'end end
   for k=2,m-1 do
    local t=seqTypes[k]
    if t=='ES'and seqTypes[k-1]=='EN'and seqTypes[k+1]=='EN'then seqTypes[k]='EN'
    elseif t=='CS'and seqTypes[k-1]==seqTypes[k+1]and(seqTypes[k-1]=='EN'or seqTypes[k-1]=='AN')then seqTypes[k]=seqTypes[k-1]end
   end
   for k=1,m do
    if seqTypes[k]=='ET'then
     local j=k;while j<=m and seqTypes[j]=='ET'do j+=1 end
     local isEN=(k>1 and seqTypes[k-1]=='EN')or(j<=m and seqTypes[j]=='EN')
     if isEN then for q=k,j-1 do seqTypes[q]='EN'end end
    end
   end
   for k=1,m do local t=seqTypes[k];if t=='ET'or t=='ES'or t=='CS'then seqTypes[k]='ON'end end
   lastStrong=sos
   for k=1,m do local t=seqTypes[k];if t=='L'or t=='R'then lastStrong=t elseif t=='EN'and lastStrong=='L'then seqTypes[k]='L'end end
   local pairs_={};local openStack={}
   for k=1,m do
    local i=indices[k];local cp=points[i];local t=seqTypes[k]
    if t=='ON'then
     if openers[cp]then if #openStack<63 then openStack[#openStack+1]={close=openers[cp],pos=k}else openStack={};break end
     elseif mirrors[cp]and not openers[cp]then
      for s=#openStack,1,-1 do
       local o=openStack[s];local alt=cp==0x232a and 0x3009 or cp==0x3009 and 0x232a or nil
       if o.close==cp or o.close==alt then pairs_[#pairs_+1]={o.pos,k};for _=s,#openStack do table_.remove(openStack)end;break end
      end
     end
    end
   end
   table_.sort(pairs_,function(a,b)return a[1]<b[1]end)
   local embedding=level%2==1 and 'R'or 'L'
   local function strongType(t)if t=='L'then return 'L'elseif t=='R'or t=='EN'or t=='AN'then return 'R'end;return nil end
   for _,pair in ipairs(pairs_)do
    local found,foundOpposite=false,false
    for k=pair[1]+1,pair[2]-1 do local s=strongType(seqTypes[k]);if s==embedding then found=true;break elseif s then foundOpposite=true end end
    local newType
    if found then newType=embedding
    elseif foundOpposite then
     local context=sos
     for k=pair[1]-1,1,-1 do local s=strongType(seqTypes[k]);if s then context=s;break end end
     newType=context~=embedding and context or embedding
    end
    if newType then
     seqTypes[pair[1]]=newType;seqTypes[pair[2]]=newType
     for _,pos in ipairs({pair[1],pair[2]})do local q=pos+1;while q<=m and orig[indices[q]]=='NSM'do seqTypes[q]=newType;q+=1 end end
    end
   end
   local function isNI(t)return t=='B'or t=='S'or t=='WS'or t=='ON'or isolateInitiator(t)or t=='PDI'end
   local k=1
   while k<=m do
    if isNI(seqTypes[k])then
     local j=k;while j<=m and isNI(seqTypes[j])do j+=1 end
     local prev=k>1 and seqTypes[k-1]or sos;local nxt=j<=m and seqTypes[j]or eos
     local a=(prev=='EN'or prev=='AN')and 'R'or prev;local b=(nxt=='EN'or nxt=='AN')and 'R'or nxt
     local result=(a==b and(a=='L'or a=='R'))and a or embedding
     for q=k,j-1 do seqTypes[q]=result end
     k=j
    else k+=1 end
   end
   for k=1,m do
    local i=indices[k];local t=seqTypes[k];local lv=levels[i]
    if lv%2==0 then if t=='R'then levels[i]=lv+1 elseif t=='AN'or t=='EN'then levels[i]=lv+2 end
    else if t=='L'or t=='EN'or t=='AN'then levels[i]=lv+1 end end
   end
  end
 end
 for i=1,n do
  local t=orig[i]
  if t=='S'or t=='B'then levels[i]=baseLevel
   local j=i-1;while j>=1 and(orig[j]=='WS'or orig[j]=='BN'or isolateInitiator(orig[j])or orig[j]=='PDI')do levels[j]=baseLevel;j-=1 end
  end
 end
 do local j=n;while j>=1 and(orig[j]=='WS'or orig[j]=='BN'or isolateInitiator(orig[j])or orig[j]=='PDI')do levels[j]=baseLevel;j-=1 end end
 for i=1,n do if types[i]=='BN'and orig[i]~='WS'then levels[i]=i>1 and levels[i-1]or baseLevel end end
 return levels,baseLevel,orig
end
function B.reorder(levels,first,last)
 first=first or 1;last=last or #levels
 local order={};for i=first,last do order[#order+1]=i end
 local highest,lowestOdd=0,math.huge
 for i=first,last do local l=levels[i];highest=math.max(highest,l);if l%2==1 then lowestOdd=math.min(lowestOdd,l)end end
 if lowestOdd==math.huge then return order end
 for level=highest,lowestOdd,-1 do
  local i=1
  while i<=#order do
   if levels[order[i]]>=level then
    local j=i;while j<#order and levels[order[j+1]]>=level do j+=1 end
    local a,b=i,j;while a<b do order[a],order[b]=order[b],order[a];a+=1;b-=1 end;i=j+1
   else i+=1 end
  end
 end
 return order
end
function B.runs(text,base)
 local points={};for _,cp in utf8.codes(text)do points[#points+1]=cp end
 local levels,paragraph=B.resolve(points,base=='rtl'and 1 or base=='ltr'and 0 or nil)
 local order=B.reorder(levels)
 local out={};local current
 for _,i in ipairs(order)do
  local level=levels[i]
  if current and current.level==level then current.points[#current.points+1]=points[i]
  else current={level=level,points={points[i]},direction=level%2==1 and 'rtl'or 'ltr'};out[#out+1]=current end
 end
 for _,run in ipairs(out)do
  if run.direction=='rtl'then local r={};for k=#run.points,1,-1 do r[#r+1]=run.points[k]end;run.points=r end
  local chars={};for _,cp in ipairs(run.points)do chars[#chars+1]=utf8.char(cp)end
  run.text=table_.concat(chars);run.points=nil
 end
 return out,paragraph==1 and 'rtl'or 'ltr'
end
function B.controls(mode,direction,plaintext)
 if mode=='embed'then return utf8.char(direction=='rtl'and 0x202b or 0x202a),utf8.char(0x202c)end
 if mode=='bidi-override'then return utf8.char(direction=='rtl'and 0x202e or 0x202d),utf8.char(0x202c)end
 if mode=='isolate'then return utf8.char(direction=='rtl'and 0x2067 or 0x2066),utf8.char(0x2069)end
 if mode=='isolate-override'then return utf8.char(direction=='rtl'and 0x2067 or 0x2066)..utf8.char(direction=='rtl'and 0x202e or 0x202d),utf8.char(0x202c)..utf8.char(0x2069)end
 if mode=='plaintext'then return utf8.char(0x2068),utf8.char(0x2069)end
 return '',''
end
return B
