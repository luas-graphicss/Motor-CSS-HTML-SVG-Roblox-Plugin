local Pool=require(script.Parent.PoolOwnership).adapter('CssRuntime')
local RunService=game:GetService('RunService')
local S={VERSION=2,FORMAT=3,MAX_DIMENSION=4096,MAX_RUNS=262144,MAX_TEXTURE_DIMENSION=1024,MAX_TEXTURE_PIXELS=1048576}
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local inverse={};for i=1,#alphabet do inverse[alphabet:byte(i)]=i-1 end
function S.hash(text)
 local h=5381;for i=1,#text do h=(h*33+text:byte(i))%4294967296 end
 return string.format('%08x:%d',h,#text)
end
local function base64(raw)
 local out={}
 for i=0,buffer.len(raw)-1,3 do
  local left=buffer.len(raw)-i;local a=buffer.readu8(raw,i);local b=left>1 and buffer.readu8(raw,i+1)or 0;local c=left>2 and buffer.readu8(raw,i+2)or 0
  local n=a*65536+b*256+c
  out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)..(left>1 and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1)or '=')..(left>2 and alphabet:sub(n%64+1,n%64+1)or '=')
 end
 return table.concat(out)
end
local function unbase64(text)
 assert(type(text)=='string'and #text<=12000000 and #text%4==0,'Buffer SVG inválido.')
 local padding=text:sub(-2)=='=='and 2 or text:sub(-1)=='='and 1 or 0
 local raw=buffer.create(#text/4*3-padding);local p=0
 for i=1,#text,4 do
  local a,b=inverse[text:byte(i)],inverse[text:byte(i+1)];local c,d=inverse[text:byte(i+2)],inverse[text:byte(i+3)]
  assert(a and b and(c or text:sub(i+2,i+2)=='=')and(d or text:sub(i+3,i+3)=='='),'Base64 SVG inválido.')
  assert((c and d)or i==#text-3,'Padding SVG inválido.')
  local n=a*262144+b*4096+(c or 0)*64+(d or 0)
  for shift=2,0,-1 do if p<buffer.len(raw)then buffer.writeu8(raw,p,math.floor(n/(256^shift))%256);p+=1 end end
 end
 return raw
end
function S.encode(width,height,runs)
 assert(width>=1 and height>=1 and width<=S.MAX_DIMENSION and height<=S.MAX_DIMENSION and #runs<=S.MAX_RUNS,'Textura SVG excede limites.')
 local raw=buffer.create(9+#runs*28);buffer.writeu8(raw,0,S.FORMAT);buffer.writeu16(raw,1,width);buffer.writeu16(raw,3,height);buffer.writeu32(raw,5,#runs)
 for i,r in ipairs(runs)do
  local p=9+(i-1)*28
  for k,v in ipairs({r.x,r.y,r.w,r.h})do buffer.writeu16(raw,p+(k-1)*2,v)end
  for k,v in ipairs(r.channels)do buffer.writef32(raw,p+8+(k-1)*4,v)end
 end
 return base64(raw)
end
function S.decode(text)
 local raw=unbase64(text);assert(buffer.len(raw)>=7,'Buffer SVG incompleto.')
 local version=buffer.readu8(raw,0);assert(version==1 or version==2 or version==3,'Versão de textura SVG inválida.');local stride=version==1 and 13 or 28;local header=version==3 and 9 or 7
 assert(buffer.len(raw)>=header,'Buffer SVG incompleto.')
 local w,h=buffer.readu16(raw,1),buffer.readu16(raw,3)
 local n=version==3 and buffer.readu32(raw,5)or buffer.readu16(raw,5)
 assert(w>=1 and h>=1 and w<=S.MAX_DIMENSION and h<=S.MAX_DIMENSION and n<=S.MAX_RUNS and buffer.len(raw)==header+n*stride,'Dimensões SVG inválidas.')
 local runs={}
 for i=1,n do
  local p=header+(i-1)*stride;local r={x=buffer.readu16(raw,p),y=buffer.readu16(raw,p+2),w=buffer.readu16(raw,p+4),h=buffer.readu16(raw,p+6),channels={}}
  assert(r.w>0 and r.h>0 and r.x+r.w<=w and r.y+r.h<=h,'Faixa SVG fora da textura.')
  for k=1,5 do
   local value=version==1 and buffer.readu8(raw,p+7+k)or buffer.readf32(raw,p+8+(k-1)*4)
   assert(value==value and value>=0 and value<=255.001,'Canal SVG inválido.');r.channels[k]=math.min(255,value)
  end
  runs[i]=r
 end
 return w,h,runs
end
local function colorOf(channels,color)
 local t=channels[4]/255
 return Color3.new(math.clamp(channels[1]/255+t*color.R,0,1),math.clamp(channels[2]/255+t*color.G,0,1),math.clamp(channels[3]/255+t*color.B,0,1))
end
function S.span(view,r,w,h,color,z)
 local a=r.channels;local f=Pool.acquire('Frame');f.Name='Span';f.BorderSizePixel=0
 f.Position=UDim2.fromScale(r.x/w,r.y/h);f.Size=UDim2.fromScale(r.w/w,r.h/h);f.BackgroundColor3=colorOf(a,color);f.BackgroundTransparency=1-a[5]/255;f.ZIndex=z
 f:SetAttribute('CssOwned',true);f:SetAttribute('SvgLayer',1);f:SetAttribute('SvgAlpha',a[5]/255)
 if a[4]>0 then
  f:SetAttribute('SvgTintWeight',a[4]/255);f:SetAttribute('SvgFixedColor',Color3.fromRGB(a[1],a[2],a[3]))
  if a[4]==255 and a[1]+a[2]+a[3]==0 then f:SetAttribute('SvgCurrentColor',true)end
 end
 f.Parent=view;return f
end
S.PACK_MAX_WIDTH=256
S.PACK_CHUNK=64
S.PACK_INTERIOR=16
local WHITE=Color3.new(1,1,1)
local function rowsOf(w,h,runs)
 local rows=table.create(h)
 for _,r in ipairs(runs)do
  local c=r.channels
  for y=r.y+1,r.y+r.h do
   local row=rows[y]
   if not row then row={};rows[y]=row end
   for x=r.x+1,r.x+r.w do row[x]=c end
  end
 end
 return rows
end
local function sameChannels(a,b)
 if a==b then return true end
 if not a or not b then return false end
 for k=1,5 do if a[k]~=b[k]then return false end end
 return true
end
local function sameRow(a,b,w)
 if a==b then return true end
 if not a or not b then return false end
 for x=1,w do if not sameChannels(a[x],b[x])then return false end end
 return true
end
local function rowMode(row,w)
 local mode
 for x=1,w do
  local c=row[x]
  if c then
   local m
   if c[4]==0 then m='fixed'elseif c[4]==255 and c[1]==0 and c[2]==0 and c[3]==0 then m='tint'else return nil end
   if mode and mode~=m then return nil end
   mode=m
  end
 end
 return mode
end
local function solidSegments(row,w,y0,gh,segments)
 local count=0;local start,current=nil,nil
 for x=1,w+1 do
  local c=row[x]
  if not sameChannels(c,current)or x==w+1 then
   if current then segments[#segments+1]={kind='solid',x0=start,x1=x-1,y0=y0,gh=gh,channels=current};count+=1 end
   start,current=x,c
  end
 end
 return count
end
local function planRow(row,w,mode,color,y0,gh,segments)
 local first
 for x=1,w do if row[x]then first=colorOf(row[x],color);break end end
 local vals=table.create(w)
 local current=first
 for x=1,w do
  local c=row[x]
  if c then current=colorOf(c,color);vals[x]={a=c[5]/255,c=current}else vals[x]={a=0,c=current}end
 end
 local key=table.create(w,0)
 local prefix=table.create(w,0)
 for x=2,w-1 do
  local p,v,n=vals[x-1],vals[x],vals[x+1]
  local k=0
  if math.abs(p.a+n.a-2*v.a)>1e-9 then k=1
  elseif mode=='fixed'then
   local pc,vc,nc=p.c,v.c,n.c
   if math.abs(pc.R+nc.R-2*vc.R)>1e-9 or math.abs(pc.G+nc.G-2*vc.G)>1e-9 or math.abs(pc.B+nc.B-2*vc.B)>1e-9 then k=1 end
  end
  key[x]=k
 end
 for x=1,w do prefix[x]=(prefix[x-1]or 0)+key[x]end
 local dp=table.create(w+1,math.huge);dp[1]=0
 local choice={}
 for i=1,w do
  local base=dp[i]
  if base<math.huge then
   local c=row[i]
   if not c then
    if base<dp[i+1]then dp[i+1]=base;choice[i+1]={i,i,'skip'}end
   else
    local limit=math.min(w,i+S.PACK_CHUNK-1)
    local solid=true
    for e=i,limit do
     local ce=row[e]
     if solid and not sameChannels(ce,c)then solid=false end
     if ce then
      local interior=e>i+1 and prefix[e-1]-prefix[i]or 0
      if interior<=S.PACK_INTERIOR then
       local cost=base+2
       if cost<dp[e+1]then dp[e+1]=cost;choice[e+1]={i,e,'ramp'}end
      elseif not solid then break end
      if solid then
       local cost=base+1
       if cost<=dp[e+1]then dp[e+1]=cost;choice[e+1]={i,e,'solid'}end
      end
     end
    end
   end
  end
 end
 local total=dp[w+1]
 if total==math.huge then return nil end
 local picked={}
 local at=w+1
 while at>1 do
  local ch=choice[at]
  if not ch then return nil end
  if ch[3]~='skip'then picked[#picked+1]=ch end
  at=ch[1]
 end
 for i=#picked,1,-1 do
  local ch=picked[i]
  if ch[3]=='solid'then segments[#segments+1]={kind='solid',x0=ch[1],x1=ch[2],y0=y0,gh=gh,channels=row[ch[1]]}
  else segments[#segments+1]={kind='ramp',x0=ch[1],x1=ch[2],y0=y0,gh=gh,vals=vals,key=key,mode=mode}end
 end
 return total
end
function S.pack(w,h,runs,color,yield)
 local rows=rowsOf(w,h,runs)
 local segments={};local instances=0
 local y=1
 while y<=h do
  local row=rows[y];local y2=y+1
  while y2<=h and sameRow(rows[y2],row,w)do y2+=1 end
  if row then
   local mode=rowMode(row,w)
   local cost=mode and planRow(row,w,mode,color,y-1,y2-y,segments)
   if not cost then cost=solidSegments(row,w,y-1,y2-y,segments)end
   instances+=cost
  end
  if yield and y%16==0 then yield()end
  y=y2
 end
 return segments,instances
end
local function ramp(view,s,w,h,color,z)
 local x0,x1,vals,key,mode=s.x0,s.x1,s.vals,s.key,s.mode
 local f=Pool.acquire('Frame');f.Name='Span';f.BorderSizePixel=0
 f.Position=UDim2.fromScale((x0-1)/w,s.y0/h);f.Size=UDim2.fromScale((x1-x0+1)/w,s.gh/h)
 f.BackgroundTransparency=0;f.ZIndex=z
 f.BackgroundColor3=mode=='tint'and color or WHITE
 f:SetAttribute('CssOwned',true);f:SetAttribute('SvgLayer',1);f:SetAttribute('SvgAlpha',1);f:SetAttribute('SvgRamp',true)
 if mode=='tint'then f:SetAttribute('SvgCurrentColor',true)end
 local n=x1-x0+1
 local tk,ck={},{}
 local function push(t,v)
  tk[#tk+1]=NumberSequenceKeypoint.new(t,1-v.a)
  if mode=='fixed'then ck[#ck+1]=ColorSequenceKeypoint.new(t,v.c)end
 end
 push(0,vals[x0])
 for x=x0,x1 do if x==x0 or x==x1 or key[x]==1 then push((x-x0+0.5)/n,vals[x])end end
 push(1,vals[x1])
 local g=Pool.acquire('UIGradient');g.Name='Ramp';g.Rotation=0;g.Offset=Vector2.zero;g.Enabled=true
 g.Transparency=NumberSequence.new(tk)
 g.Color=mode=='fixed'and ColorSequence.new(ck)or ColorSequence.new(WHITE)
 g:SetAttribute('CssOwned',true);g.Parent=f;f.Parent=view
 return f
end
function S.spans(view,runs,w,h,color,z,options)
 options=options or {}
 if options.pack~=false and w<=S.PACK_MAX_WIDTH and #runs>=4 then
  local segments,instances=S.pack(w,h,runs,color,options.yield)
  if segments and instances<#runs then
   for _,s in ipairs(segments)do
    if s.kind=='solid'then S.span(view,{x=s.x0-1,y=s.y0,w=s.x1-s.x0+1,h=s.gh,channels=s.channels},w,h,color,z)
    else ramp(view,s,w,h,color,z)end
   end
   view:SetAttribute('SvgPacked',true)
   return instances
  end
 end
 for _,r in ipairs(runs)do S.span(view,r,w,h,color,z)end
 view:SetAttribute('SvgPacked',false)
 return #runs
end
local function native(view,color,z,opacity)
 if not view:FindFirstChild('Span')then
  local data=view:GetAttribute('SvgTextureData')
  if data then local w,h,runs=S.decode(data);S.spans(view,runs,w,h,color,z,{pack=view:GetAttribute('SvgPacked')~=false})end
 end
 for _,f in ipairs(view:GetChildren())do
  if f:IsA('Frame')and f:GetAttribute('SvgAlpha')~=nil then
   f.ZIndex=z;f.BackgroundTransparency=1-f:GetAttribute('SvgAlpha')*opacity
   local weight=f:GetAttribute('SvgTintWeight')
   if weight then
    local fixed=f:GetAttribute('SvgFixedColor')or Color3.new()
    f.BackgroundColor3=Color3.new(math.clamp(fixed.R+weight*color.R,0,1),math.clamp(fixed.G+weight*color.G,0,1),math.clamp(fixed.B+weight*color.B,0,1))
   elseif f:GetAttribute('SvgCurrentColor')then f.BackgroundColor3=color end
  end
 end
end
local shared=_G.__CssSvgTextureCacheV1
if type(shared)~='table'or shared.version~=1 then shared={version=1,entries={},pixels=0,count=0};_G.__CssSvgTextureCacheV1=shared end
local bindings=setmetatable({},{__mode='k'})
local function drop(entry)
 entry.refs-=1
 if entry.refs<=0 then
  if shared.entries[entry.key]==entry then shared.entries[entry.key]=nil end
  shared.pixels-=entry.width*entry.height;shared.count-=1;entry.image:Destroy()
 end
end
local function release(view,restore,color,z,opacity)
 local b=bindings[view];if not b then return end;bindings[view]=nil
 if b.connection then b.connection:Disconnect()end
 if restore and opacity==nil and b.label then
  local ok,current=pcall(function()return 1-b.label.ImageTransparency end)
  if ok then opacity=math.clamp(current,0,1)end
 end
 if b.label then b.label:Destroy()end;drop(b.entry)
 if restore then native(view,color or b.color,z or b.z,opacity or b.opacity);view:SetAttribute('SvgBackend','Frames')end
end
function S.releaseTree(root,restore)
 local list={};for view in pairs(bindings)do if view==root or view:IsDescendantOf(root)then list[#list+1]=view end end
 for _,view in ipairs(list)do release(view,restore)end
end
local function pureTint(runs)
 if #runs==0 then return false end
 for _,r in ipairs(runs)do local c=r.channels;if c[4]<255 or c[1]+c[2]+c[3]>0 then return false end end
 return true
end
local function acquire(data,color,usesTint)
 local hash=S.hash(data)
 if usesTint then
  local tinted=shared.entries[hash..':tint']
  if tinted and tinted.data==data then tinted.refs+=1;return tinted end
  tinted=shared.entries[hash..':tint:'..data]
  if tinted then tinted.refs+=1;return tinted end
 end
 local colorKey=usesTint and string.format('%.9g,%.9g,%.9g',color.R,color.G,color.B)or 'fixed'
 local key=hash..':'..colorKey;local cached=shared.entries[key]
 if cached and cached.data==data and(not usesTint or cached.color==color)then cached.refs+=1;return cached end
 if cached then key=key..':'..data end
 cached=shared.entries[key];if cached then cached.refs+=1;return cached end
 local w,h,runs=S.decode(data)
 local pure=usesTint and pureTint(runs)
 if pure then key=hash..':tint';if shared.entries[key]then key=key..':'..data end;color=WHITE end
 if w>S.MAX_TEXTURE_DIMENSION or h>S.MAX_TEXTURE_DIMENSION then return nil,'Textura acima do limite de EditableImage.'end
 if shared.count>=64 or shared.pixels+w*h>S.MAX_TEXTURE_PIXELS then return nil,'Orçamento de memória de imagens atingido.'end
 local image
 local ok,err=pcall(function()
  image=game:GetService('AssetService'):CreateEditableImage({Size=Vector2.new(w,h)});assert(image,'EditableImage indisponível.')
  local pixels=buffer.create(w*h*4)
  for _,r in ipairs(runs)do
   local c=colorOf(r.channels,color);local red,green,blue=math.floor(c.R*255+0.5),math.floor(c.G*255+0.5),math.floor(c.B*255+0.5)
   for y=r.y,r.y+r.h-1 do for x=r.x,r.x+r.w-1 do local p=(y*w+x)*4;buffer.writeu8(pixels,p,red);buffer.writeu8(pixels,p+1,green);buffer.writeu8(pixels,p+2,blue);buffer.writeu8(pixels,p+3,math.clamp(math.floor(r.channels[5]+0.5),0,255))end end
  end
  image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),pixels)
 end)
 if not ok then if image then image:Destroy()end;return nil,tostring(err)end
 local entry={key=key,data=data,color=color,pure=pure,width=w,height=h,image=image,refs=1}
 shared.entries[key]=entry;shared.pixels+=w*h;shared.count+=1;return entry
end
function S.paint(view,target,color,opacity,options)
 options=options or {};local z=target.ZIndex+1;view.ZIndex=target.ZIndex
 local enabled=options.images
 if enabled==nil then
  local gui=target:FindFirstAncestorOfClass('ScreenGui');enabled=gui and gui:GetAttribute('CssSvgImages')
  if enabled==nil then enabled=RunService:IsRunning()and RunService:IsClient()end
 end
 local candidate=view:GetAttribute('SvgImageCandidate')==true;local data=view:GetAttribute('SvgTextureData');local b=bindings[view]
 if not enabled or not candidate or not data then
  if b then release(view,true,color,z,opacity)end
  local orphan=view:FindFirstChild('__SvgImage');if orphan then orphan:Destroy()end
  view:SetAttribute('SvgBackend','Frames');native(view,color,z,opacity);return
 end
 local usesTint=view:GetAttribute('SvgUsesCurrentColor')==true
 if b and(b.data~=data or(usesTint and not b.entry.pure and b.color~=color)or not b.label.Parent)then release(view,false);b=nil end
 if not b then
  local orphan=view:FindFirstChild('__SvgImage');if orphan then orphan:Destroy()end
  view:SetAttribute('SvgBackend','Frames')
  local retry=view:GetAttribute('SvgImageRetryAt')or 0
  if not options.retry and os.clock()<retry then native(view,color,z,opacity);return end
  local entry,err=acquire(data,color,usesTint)
  if entry then
   local label=Instance.new('ImageLabel');label.Name='__SvgImage';label.BackgroundTransparency=1;label.BorderSizePixel=0;label.Size=UDim2.fromScale(1,1);label.ZIndex=z;label.ImageTransparency=1-opacity
   label:SetAttribute('CssOwned',true);label:SetAttribute('SvgAlpha',1)
   label:SetAttribute('CssNoPool',true)
   local ok,why=pcall(function()label.ImageContent=Content.fromObject(entry.image)end)
   if ok then
    local orphan=view:FindFirstChild('__SvgImage');if orphan then orphan:Destroy()end
    label.Parent=view
    for _,f in ipairs(view:GetChildren())do if f:IsA('Frame')and f:GetAttribute('SvgAlpha')~=nil then f:Destroy()end end
    b={entry=entry,label=label,color=color,z=z,opacity=opacity,data=data};bindings[view]=b
    b.connection=view.Destroying:Connect(function()release(view,false)end)
    view:SetAttribute('SvgBackend','EditableImage');view:SetAttribute('SvgImageRetryAt',nil);view:SetAttribute('SvgImageFallback',nil)
   else label:Destroy();drop(entry);err=tostring(why)end
  end
  if not b then
   local orphan=view:FindFirstChild('__SvgImage');if orphan then orphan:Destroy()end
   view:SetAttribute('SvgImageFallback',tostring(err or 'EditableImage indisponível.'):sub(1,240));view:SetAttribute('SvgImageRetryAt',os.clock()+15);view:SetAttribute('SvgBackend','Frames');native(view,color,z,opacity);return
  end
 end
 b.color,b.z,b.opacity=color,z,opacity;b.label.ZIndex=z;b.label.ImageTransparency=1-opacity
 if b.entry.pure then b.label.ImageColor3=color end
end
function S.stats()return {images=shared.count,pixels=shared.pixels}end
return S
