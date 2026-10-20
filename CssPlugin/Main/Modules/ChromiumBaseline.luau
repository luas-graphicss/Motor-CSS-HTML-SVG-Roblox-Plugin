local Http=game:GetService('HttpService')
local Storage=game:GetService('ServerStorage')
local Goldens=require(script.Parent.ConformanceGoldens)
local Manifest=require(script.Parent.ReleaseManifest)
local B={VERSION=1,FOLDER='CssChromiumBaselines',OWNER='CssPlugin',GRID=16,SOURCE='chromium-headless'}
function B.channels(value)
 if value==nil then return nil end
 local text=Goldens.normalizeColor(value)
 local r,g,b,a=text:match('^rgba%((%d+), (%d+), (%d+), ([%d%.]+)%)$')
 if not r then r,g,b=text:match('^rgb%((%d+), (%d+), (%d+)%)$')end
 if not r then return nil end
 return tonumber(r),tonumber(g),tonumber(b),tonumber(a)or 1
end
function B.blank(size,background)
 size=size or B.GRID
 local r,g,b=255,255,255
 local cr,cg,cb=B.channels(background)
 if cr then r,g,b=cr,cg,cb end
 local out=table.create(size*size*3,255)
 for index=0,size*size-1 do out[index*3+1]=r;out[index*3+2]=g;out[index*3+3]=b end
 return out
end
local function mix(current,color,alpha)return math.clamp(math.floor((current or 255)*(1-alpha)+color*alpha+0.5),0,255)end
function B.fill(buffer,size,width,height,box,r,g,b,alpha)
 if not box or width<=0 or height<=0 then return 0 end
 local x1,y1=box.x or 0,box.y or 0
 local x2,y2=x1+(box.w or 0),y1+(box.h or 0)
 local painted=0
 for row=0,size-1 do
  local y=(row+0.5)*height/size
  if y>=y1 and y<y2 then
   for column=0,size-1 do
    local x=(column+0.5)*width/size
    if x>=x1 and x<x2 then
     local base=(row*size+column)*3
     buffer[base+1]=mix(buffer[base+1],r,alpha)
     buffer[base+2]=mix(buffer[base+2],g,alpha)
     buffer[base+3]=mix(buffer[base+3],b,alpha)
     painted+=1
    end
   end
  end
 end
 return painted
end
function B.paint(render,options)
 options=options or {}
 local size=options.grid or B.GRID
 assert(type(size)=='number'and size>=2 and size<=128,'Grade de amostragem fora do limite.')
 local buffer=B.blank(size,options.background)
 local width=render.width or 0
 local height=render.height or 0
 local painted=0
 for _,key in ipairs(render.order or {})do
  local box=render.boxes and render.boxes[key]
  local style=render.styles and render.styles[key]
  if box and style and not box.hidden and style.display~='none' and style.visibility~='hidden' then
   local color=style['background-color']
   if color==nil or color=='transparent' then color=style.background end
   local r,g,b,alpha=B.channels(color)
   if r and alpha and alpha>0 then
    local opacity=tonumber(style.opacity)
    if opacity==nil then opacity=1 end
    painted+=B.fill(buffer,size,width,height,box,r,g,b,math.clamp(alpha*opacity,0,1))
   end
  end
 end
 return {grid=size,width=width,height=height,pixels=buffer,painted=painted}
end
function B.decode(value,size)
 if type(value)=='string' then
  local ok,decoded=pcall(function()return Http:JSONDecode(value)end)
  assert(ok and type(decoded)=='table','Pixels da captura invalidos.')
  value=decoded
 end
 assert(type(value)=='table','Pixels da captura exigem tabela.')
 local out={}
 for _,item in ipairs(value)do
  if type(item)=='number' then out[#out+1]=math.clamp(math.floor(item+0.5),0,255)
  elseif type(item)=='string' then
   local r,g,b=B.channels(item)
   assert(r,'Cor invalida na captura: '..item)
   out[#out+1]=r;out[#out+1]=g;out[#out+1]=b
  elseif type(item)=='table' then
   for _,channel in ipairs(item)do
    local number=tonumber(channel)or 0
    out[#out+1]=math.clamp(math.floor(number+0.5),0,255)
   end
  else error('Pixel invalido na captura.',0)end
 end
 if size then assert(#out==size*size*3,string.format('Captura com %d canais; esperado %d na grade %d.',#out,size*size*3,size))end
 return out
end
function B.resample(pixels,from,to)
 if from==to then return pixels end
 local out={}
 for row=0,to-1 do
  local sourceRow=math.min(from-1,math.floor((row+0.5)*from/to))
  for column=0,to-1 do
   local sourceColumn=math.min(from-1,math.floor((column+0.5)*from/to))
   local base=(sourceRow*from+sourceColumn)*3
   out[#out+1]=pixels[base+1]or 255
   out[#out+1]=pixels[base+2]or 255
   out[#out+1]=pixels[base+3]or 255
  end
 end
 return out
end
local function fingerprint(capture)
 return Manifest.hash(Http:JSONEncode({capture.geometry or {},capture.computed or {},capture.pixels or {}}))
end
function B.capture(payload)
 assert(type(payload)=='table','Captura exige tabela.')
 assert(type(payload.id)=='string'and payload.id:match('^[%a_][%w_%-%.]*$')and #payload.id<=64,'Id de captura invalido.')
 local size=payload.grid or B.GRID
 local capture={id=payload.id,module=payload.module,version=B.VERSION,source=payload.source or B.SOURCE,agent=payload.agent,created=payload.created or os.date('!%Y-%m-%dT%H:%M:%SZ'),width=payload.width,height=payload.height,grid=size,geometry=payload.geometry,computed=payload.computed}
 if payload.pixels~=nil then capture.pixels=B.decode(payload.pixels,size)end
 assert(capture.geometry or capture.computed or capture.pixels,'Captura sem geometria, computado ou pixels.')
 capture.hash=fingerprint(capture)
 return capture
end
local function folder(create)
 local existing=Storage:FindFirstChild(B.FOLDER)
 if existing then
  assert(existing:IsA('Folder')and existing:GetAttribute('CssOwner')==B.OWNER,'ServerStorage.'..B.FOLDER..' pertence a outro sistema.')
  return existing
 end
 if not create then return nil end
 local created=Instance.new('Folder')
 created.Name=B.FOLDER
 created:SetAttribute('CssOwner',B.OWNER)
 created.Parent=Storage
 return created
end
function B.store(capture)
 assert(type(capture)=='table'and capture.id,'store exige uma captura com id.')
 local root=folder(true)
 local value=root:FindFirstChild(capture.id)
 if not value then value=Instance.new('StringValue');value.Name=capture.id;value.Parent=root end
 assert(value:IsA('StringValue'),'Captura existente nao e StringValue.')
 capture.hash=capture.hash or fingerprint(capture)
 value.Value=Http:JSONEncode(capture)
 value:SetAttribute('CssBaselineHash',capture.hash)
 value:SetAttribute('CssBaselineSource',tostring(capture.source))
 value:SetAttribute('CssBaselineGrid',capture.grid or B.GRID)
 return value
end
function B.load(id)
 local root=folder(false)
 local value=root and root:FindFirstChild(tostring(id))
 if not value then return nil end
 assert(value:IsA('StringValue'),'Captura invalida: '..tostring(id))
 local ok,decoded=pcall(function()return Http:JSONDecode(value.Value)end)
 assert(ok and type(decoded)=='table','Captura corrompida: '..tostring(id))
 return decoded
end
function B.list()
 local root=folder(false)
 local out={}
 if not root then return out end
 for _,item in ipairs(root:GetChildren())do
  if item:IsA('StringValue')then out[#out+1]={id=item.Name,hash=item:GetAttribute('CssBaselineHash'),source=item:GetAttribute('CssBaselineSource'),grid=item:GetAttribute('CssBaselineGrid')}end
 end
 table.sort(out,function(a,b)return a.id<b.id end)
 return out
end
function B.remove(id)
 local root=folder(false)
 local value=root and root:FindFirstChild(tostring(id))
 if not value then return false end
 value:Destroy()
 return true
end
function B.verify(capture)
 if type(capture)~='table' then return false,'captura ausente' end
 local hash=fingerprint(capture)
 if capture.hash and capture.hash~=hash then return false,'hash divergente: '..tostring(capture.hash)..' -> '..hash end
 if (capture.version or B.VERSION)~=B.VERSION then return false,'versao de captura incompativel' end
 return true,hash
end
function B.diff(capture,actual,options)
 assert(type(capture)=='table','Captura ausente.')
 actual=actual or {}
 options=options or {}
 local sections={}
 if capture.geometry then sections[#sections+1]=Goldens.geometry(capture.geometry,actual.geometry,options)end
 if capture.computed then sections[#sections+1]=Goldens.computed(capture.computed,actual.computed)end
 if capture.pixels then
  local size=options.grid or (type(actual.grid)=='table' and actual.grid.grid)or(type(actual.grid)=='number' and actual.grid)or capture.grid or B.GRID
  local expected=B.resample(capture.pixels,capture.grid or size,size)
  sections[#sections+1]=Goldens.pixels(expected,actual.pixels,options)
 end
 local ok,checked,failures=true,0,{}
 for _,section in ipairs(sections)do
  checked+=section.checked
  if not section.ok then ok=false end
  for _,failure in ipairs(section.failures)do failure.kind=section.kind;failures[#failures+1]=failure end
 end
 return {ok=ok,id=capture.id,module=capture.module,source=capture.source,sections=sections,failures=failures,checked=checked,missing=false}
end
function B.compare(case,actual,options)
 local id=type(case)=='table' and case.id or case
 local capture=B.load(id)
 if not capture then return {ok=nil,id=id,missing=true,reason='sem captura headless',sections={},failures={},checked=0} end
 local valid,hash=B.verify(capture)
 if not valid then return {ok=false,id=id,missing=false,sections={},failures={{kind='captura',field='hash',expected=capture.hash,actual=hash}},checked=0} end
 return B.diff(capture,actual,options)
end
function B.report(result)
 if not result then return 'sem resultado' end
 if result.missing then return string.format('Chromium %s | %s',tostring(result.id),tostring(result.reason))end
 local lines={string.format('Chromium %s | %s | %d verificacoes | fonte %s',tostring(result.id),result.ok and 'conforme' or 'divergente',result.checked or 0,tostring(result.source))}
 for _,section in ipairs(result.sections or {})do
  lines[#lines+1]=string.format('  %-8s %s (%d checagens, tolerancia %s)',section.kind,section.ok and 'ok' or 'falhou',section.checked,tostring(section.tolerance))
 end
 for index,failure in ipairs(result.failures or {})do
  if index>8 then break end
  lines[#lines+1]=string.format('  %s %s.%s esperado %s obtido %s',tostring(failure.kind),tostring(failure.id or '-'),tostring(failure.field),tostring(failure.expected),tostring(failure.actual))
 end
 return table.concat(lines,'\n')
end
function B.describe()
 local stored=B.list()
 local lines={string.format('Capturas headless | %d armazenada(s) | grade padrao %d',#stored,B.GRID)}
 for _,item in ipairs(stored)do lines[#lines+1]=string.format('  %-28s %s (%s)',item.id,tostring(item.hash),tostring(item.source))end
 return table.concat(lines,'\n')
end
return B
