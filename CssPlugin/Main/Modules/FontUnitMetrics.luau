local F=require(script.Parent.FontFaces)
local Engine=require(script.Parent.FontEngine)
local TextService=game:GetService('TextService')
local M={VERSION=3};local cache={};local count=0
local designs={sourcesanspro={ex=0.486,cap=0.66},gotham={ex=0.51,cap=0.7},gothamssm={ex=0.51,cap=0.7},arial={ex=0.519,cap=0.716},helvetica={ex=0.523,cap=0.717},legacy={ex=0.5,cap=0.7},roboto={ex=0.528,cap=0.711},robotomono={ex=0.528,cap=0.711},robotocondensed={ex=0.528,cap=0.711},montserrat={ex=0.517,cap=0.7},ubuntu={ex=0.52,cap=0.693},nunito={ex=0.49,cap=0.705},merriweather={ex=0.553,cap=0.741},oswald={ex=0.542,cap=0.73},inconsolata={ex=0.48,cap=0.66},jura={ex=0.492,cap=0.687},titilliumweb={ex=0.484,cap=0.66},josefinsans={ex=0.427,cap=0.68},fondamento={ex=0.445,cap=0.66},kalam={ex=0.48,cap=0.7},indieflower={ex=0.523,cap=0.7},patrickhand={ex=0.48,cap=0.7},permanentmarker={ex=0.545,cap=0.72},bangers={ex=0.605,cap=0.72},creepster={ex=0.52,cap=0.7},luckiestguy={ex=0.54,cap=0.72},fredokaone={ex=0.545,cap=0.73},amaticsc={ex=0.4,cap=0.64},denkone={ex=0.52,cap=0.72},michroma={ex=0.52,cap=0.7},pressstart2p={ex=0.5,cap=0.7},specialelite={ex=0.48,cap=0.66},sarpanch={ex=0.5,cap=0.7},grenzegotisch={ex=0.5,cap=0.7},guru={ex=0.5,cap=0.7},balthazar={ex=0.47,cap=0.66},garamond={ex=0.44,cap=0.66},nunitosans={ex=0.49,cap=0.705},accanthis={ex=0.46,cap=0.66},builderman={ex=0.5,cap=0.7}}
local custom={}
local function familyKey(text)
 local lower=tostring(text or ''):lower()
 local name=lower:match('([%w%-_]+)%.json')or lower
 return (name:gsub('[^%a%d]',''))
end
local resolver
local function lookup(style)
 if resolver then
  local ok,resolved=pcall(resolver,style)
  if ok and type(resolved)=='table' then return resolved end
 end
 local direct=familyKey(style._fontSource)
 local entry=custom[direct]or designs[direct]
 if entry then return entry end
 local ok,family=pcall(function()return Font.fromEnum(F.fallback(style)).Family end)
 if ok then
  local native=familyKey(family)
  entry=custom[native]or designs[native]
  if entry then return entry end
 end
 return nil
end
local function advanceRatio(face,text,units)
 local ok,items=pcall(Engine.glyphs,face,text)
 if not ok or type(items)~='table' or #items==0 then return nil end
 local item=items[1]
 if not item or item.glyph==0 or type(item.advance)~='number' or item.advance<=0 then return nil end
 return item.advance/units
end
function M.ratios(style)
 local entry=lookup(style)
 return entry and entry.ex or 0.5,entry and entry.cap or 0.7,entry~=nil,entry and entry.source or 'fallback'
end
function M.metrics(style)
 local entry=lookup(style)
 if not entry then return nil end
 return {ex=entry.ex,cap=entry.cap,ch=entry.ch,ic=entry.ic,ascent=entry.ascent,descent=entry.descent,lineGap=entry.lineGap,unitsPerEm=entry.unitsPerEm,source=entry.source or 'table',exSource=entry.exSource,capSource=entry.capSource,family=entry.family}
end
function M.registerFont(family,data,options)
 assert(type(family)=='string' and #family>0,'registerFont exige uma família.')
 local face=data
 if type(face)=='string' then face=Engine.load(face,options) end
 assert(type(face)=='table' and type(face.unitsPerEm)=='number' and face.unitsPerEm>0,'registerFont exige bytes de fonte ou face carregada.')
 local units=face.unitsPerEm
 local metrics=type(face.metrics)=='table' and face.metrics or {}
 local entry={source='measured',unitsPerEm=units,family=face.family}
 if type(metrics.xHeight)=='number' and metrics.xHeight>0 then entry.ex=metrics.xHeight/units;entry.exSource=metrics.xHeightSource or 'face' end
 if type(metrics.capHeight)=='number' and metrics.capHeight>0 then entry.cap=metrics.capHeight/units;entry.capSource=metrics.capHeightSource or 'face' end
 if type(metrics.ascent)=='number' then entry.ascent=metrics.ascent/units end
 if type(metrics.descent)=='number' then entry.descent=metrics.descent/units end
 if type(metrics.lineGap)=='number' then entry.lineGap=metrics.lineGap/units end
 entry.ch=advanceRatio(face,'0',units)
 entry.ic=advanceRatio(face,utf8.char(0x6c34),units)
 assert(entry.ex or entry.cap or entry.ch or entry.ic,'Fonte sem métricas utilizáveis para unidades.')
 custom[familyKey(family)]=entry
 M.clear()
 return entry
end
function M.measure(style,size)
 local font=F.fallback(style);local source=style._fontSource
 local key=table.concat({tostring(font),tostring(source or ''),tostring(style['font-weight']or 400),tostring(style['font-style']or 'normal'),tostring(size)},'|')
 local result=cache[key];if result then return result.ch,result.ex,result.fallback end
 local measured=lookup(style)
 if measured and measured.source=='measured' and measured.ch then
  result={ch=size*measured.ch,ex=size*(measured.ex or 0.5),fallback=false,exKnown=measured.ex~=nil,source='measured'}
  if count>=256 then table.clear(cache);count=0 end
  count+=1;cache[key]=result;return result.ch,result.ex,result.fallback
 end
 local ch=size*0.5;local fallback=true
 local face=F.face(style)
 local nativeFamily=Font.fromEnum(font).Family
 if source and(source~=nativeFamily or style['font-style']=='italic'or style['font-style']=='oblique')then
  local params=Instance.new('GetTextBoundsParams')
  params.Text='0';params.Font=face;params.Size=size;params.Width=100000
  local ok,bounds=pcall(TextService.GetTextBoundsAsync,TextService,params)
  params:Destroy()
  if ok and bounds.X>0 then ch=bounds.X;fallback=false end
 else
  local ok,bounds=pcall(TextService.GetTextSize,TextService,'0',size,font,Vector2.new(100000,100000))
  if ok and bounds.X>0 then ch=bounds.X;fallback=false end
 end
 local exRatio,_,known=M.ratios(style)
 result={ch=ch,ex=size*exRatio,fallback=fallback,exKnown=known}
 if count>=256 then table.clear(cache);count=0 end
 count+=1;cache[key]=result;return result.ch,result.ex,result.fallback
end
local modernCache={};local modernCount=0
function M.modern(style,size)
 local font=F.fallback(style)
 local key=table.concat({tostring(font),tostring(style._fontSource or ''),tostring(style['font-weight']),tostring(style['font-style']),tostring(size)},'|')
 local item=modernCache[key];if item then return item.ic,item.cap,item.fallback end
 local measured=lookup(style)
 if measured and measured.source=='measured' and measured.ic then
  item={ic=size*measured.ic,cap=size*(measured.cap or 0.7),fallback=false,capKnown=measured.cap~=nil,source='measured'}
  if modernCount>=256 then table.clear(modernCache);modernCount=0 end
  modernCount+=1;modernCache[key]=item;return item.ic,item.cap,item.fallback
 end
 local ic=size;local fallback=true;local params=Instance.new('GetTextBoundsParams')
 params.Text=utf8.char(0x6c34);params.Font=F.face(style);params.Size=size;params.Width=100000
 local ok,bounds=pcall(TextService.GetTextBoundsAsync,TextService,params);params:Destroy()
 if ok and bounds.X>0 then ic=bounds.X;fallback=false end
 local _,capRatio,known=M.ratios(style)
 item={ic=ic,cap=size*capRatio,fallback=fallback,capKnown=known}
 if modernCount>=256 then table.clear(modernCache);modernCount=0 end
 modernCount+=1;modernCache[key]=item;return item.ic,item.cap,item.fallback
end
function M.register(family,metrics)
 assert(type(family)=='string'and #family>0,'register exige uma família.')
 assert(type(metrics)=='table','register exige métricas.')
 local entry={}
 for _,name in ipairs({'ex','cap'})do
  local value=metrics[name]
  if value~=nil then
   assert(type(value)=='number'and value>0 and value<2,name..' exige razão em em entre 0 e 2.')
   entry[name]=value
  end
 end
 assert(next(entry)~=nil,'register exige ex e/ou cap.')
 custom[familyKey(family)]=entry
 M.clear()
 return entry
end
function M.attach(fn)assert(type(fn)=='function','attach exige uma função de resolução.');resolver=fn;M.clear();return true end
function M.detach()resolver=nil;M.clear();return true end
function M.attached()return resolver~=nil end
function M.known(style)local _,_,ok=M.ratios(style);return ok end
function M.clear()table.clear(cache);count=0;table.clear(modernCache);modernCount=0 end
return M
