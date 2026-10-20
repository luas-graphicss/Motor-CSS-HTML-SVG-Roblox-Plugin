local U=require(script.Parent.Util)
local G=require(script.Parent.SvgGeometry)
local Style=require(script.Parent.SvgStyle)
local Text=require(script.Parent.SvgText)
local D={VERSION='svg-dom-1'}
D.limits={depth=24,use=8,nodes=4096,data=1048576}
D.aligns={none=true,xMinYMin=true,xMidYMin=true,xMaxYMin=true,xMinYMid=true,xMidYMid=true,xMaxYMid=true,xMinYMax=true,xMidYMax=true,xMaxYMax=true}
D.structural={use=true,symbol=true,image=true,switch=true,text=true,tspan=true,textpath=true,foreignobject=true,pattern=true}
D.renderable={path=true,rect=true,circle=true,ellipse=true,line=true,polyline=true,polygon=true,g=true,svg=true,use=true,text=true,image=true,switch=true}
D.conditionalAttributes={requiredfeatures=true,requiredextensions=true,systemlanguage=true}
D.features={}
for _,name in ipairs({'SVG','SVG-static','CoreAttribute','Structure','BasicStructure','ConditionalProcessing','Image','Style','Shape','Text','BasicText','PaintAttribute','BasicPaintAttribute','OpacityAttribute','GraphicsAttribute','Gradient','Pattern','Clip','BasicClip','Mask','Filter','BasicFilter','Marker','View','Hyperlinking','XlinkAttribute','ExternalResourcesRequired'})do
 D.features['http://www.w3.org/TR/SVG11/feature#'..name]=true
end
local function fmt(value)return string.format('%.9g',value)end
local function trim(value)return(tostring(value):gsub('^%s+',''):gsub('%s+$',''))end
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local inverse={}
for index=1,#alphabet do inverse[alphabet:sub(index,index)]=index-1 end
local function unbase64(text)
 local clean=text:gsub('%s','')
 assert(#clean<=D.limits.data,'data URI de <image> acima do limite de bytes.')
 local out={}
 local acc,bits=0,0
 for index=1,#clean do
  local char=clean:sub(index,index)
  if char~='='then
   local value=inverse[char]
   assert(value,'data URI base64 invalido em <image>.')
   acc=acc*64+value
   bits+=6
   if bits>=8 then
    bits-=8
    local divisor=2^bits
    out[#out+1]=string.char(math.floor(acc/divisor)%256)
    acc=acc%divisor
   end
  end
 end
 return table.concat(out)
end
function D.href(attrs)
 local value=attrs and(attrs.href or attrs['xlink:href'])
 if type(value)~='string'then return nil end
 return trim(value)
end
function D.reference(attrs)
 local value=D.href(attrs)
 if value==nil then return nil end
 return value:match('^#(.+)$')
end
function D.aspect(value)
 local text=trim(value or'')
 if text==''then text='xMidYMid meet'end
 local defer=false
 local rest=text:match('^defer%s+(.+)$')
 if rest then defer=true;text=trim(rest)end
 local align,fit=text:match('^(%a+)%s+(%a+)$')
 if not align then align,fit=text,'meet'end
 assert(D.aligns[align],'preserveAspectRatio invalido: '..tostring(value))
 assert(fit=='meet'or fit=='slice','preserveAspectRatio aceita meet ou slice: '..tostring(value))
 return {align=align,slice=fit=='slice',defer=defer,none=align=='none'}
end
function D.viewBox(value)
 if value==nil then return nil end
 local text=trim(value)
 if text==''then return nil end
 local list={}
 for token in text:gmatch('[^%s,]+')do
  local parsed=tonumber(token)
  assert(parsed and parsed==parsed,'viewBox exige quatro numeros: '..tostring(value))
  list[#list+1]=parsed
 end
 assert(#list==4,'viewBox exige quatro numeros: '..tostring(value))
 assert(list[3]>0 and list[4]>0,'viewBox exige width e height positivos: '..tostring(value))
 return list
end
function D.scale(aspect,box,width,height)
 local sx,sy=width/box[3],height/box[4]
 if not aspect.none then
  local uniform=aspect.slice and math.max(sx,sy)or math.min(sx,sy)
  sx,sy=uniform,uniform
 end
 local tx,ty=-box[1]*sx,-box[2]*sy
 if not aspect.none then
  local restX,restY=width-box[3]*sx,height-box[4]*sy
  local align=aspect.align
  if align:find('xMid',1,true)then tx+=restX/2 elseif align:find('xMax',1,true)then tx+=restX end
  if align:find('YMid',1,true)then ty+=restY/2 elseif align:find('YMax',1,true)then ty+=restY end
 end
 return sx,sy,tx,ty
end
function D.transform(aspect,box,x,y,width,height)
 if box==nil then
  if x==0 and y==0 then return nil end
  return 'translate('..fmt(x)..' '..fmt(y)..')'
 end
 local sx,sy,tx,ty=D.scale(aspect,box,width,height)
 return 'matrix('..fmt(sx)..' 0 0 '..fmt(sy)..' '..fmt(x+tx)..' '..fmt(y+ty)..')'
end
local function primary(tag)return tag:match('^(%a+)')or tag end
function D.conditional(attrs,options)
 local features=attrs.requiredfeatures
 if features~=nil then
  local text=trim(features)
  if text==''then return false end
  for token in text:gmatch('%S+')do
   if not D.features[token]then return false end
  end
 end
 local extensions=attrs.requiredextensions
 if extensions~=nil then
  if trim(extensions)~=''then return false end
 end
 local language=attrs.systemlanguage
 if language~=nil then
  local wanted={}
  for token in tostring(language):gmatch('[^,]+')do
   local tag=trim(token):lower()
   if tag~=''then wanted[#wanted+1]=tag end
  end
  if #wanted==0 then return false end
  local list=(options and options.languages)or{'en'}
  local matched=false
  for _,tag in ipairs(wanted)do
   for _,current in ipairs(list)do
    local value=trim(current):lower()
    if value==tag or primary(value)==primary(tag)then matched=true;break end
   end
   if matched then break end
  end
  if not matched then return false end
 end
 return true
end
function D.dataSvg(source)
 local head,rest=source:match('^data:([^,]*),(.*)$')
 if head==nil then return nil end
 local mime=(head:match('^([^;]*)')or''):lower()
 if mime~='image/svg+xml'and mime~=''then return nil,mime end
 if head:lower():find('base64',1,true)then return unbase64(rest)end
 local decoded=rest:gsub('+',' '):gsub('%%(%x%x)',function(hex)return string.char(tonumber(hex,16))end)
 return decoded
end
function D.pattern(attrs,box,width,height)
 local units=trim(attrs.patternunits or'objectBoundingBox')
 local tile
 if units=='userSpaceOnUse'then
  tile={x=G.number(attrs.x,0,width),y=G.number(attrs.y,0,height),width=G.number(attrs.width,0,width),height=G.number(attrs.height,0,height)}
 else
  assert(units=='objectBoundingBox','patternUnits aceita userSpaceOnUse ou objectBoundingBox.')
  tile={x=box.x+G.number(attrs.x,0,1)*box.width,y=box.y+G.number(attrs.y,0,1)*box.height,width=G.number(attrs.width,0,1)*box.width,height=G.number(attrs.height,0,1)*box.height}
 end
 assert(tile.width>0 and tile.height>0,'<pattern> exige width e height positivos.')
 tile.units=units
 return tile
end
function D.patternContent(attrs,tile,box)
 local viewBox=D.viewBox(attrs.viewbox)
 if viewBox then return D.transform(D.aspect(attrs.preserveaspectratio),viewBox,0,0,tile.width,tile.height)end
 local units=trim(attrs.patterncontentunits or'userSpaceOnUse')
 if units=='objectBoundingBox'then return 'matrix('..fmt(box.width)..' 0 0 '..fmt(box.height)..' 0 0)'end
 assert(units=='userSpaceOnUse','patternContentUnits aceita userSpaceOnUse ou objectBoundingBox.')
 return nil
end
function D.expand(root,ctx)
 ctx=ctx or{}
 local inherited=ctx.inherited or Style.inherited or{}
 local languages=ctx.languages or{'en'}
 local stats={use=0,symbol=0,viewport=0,image=0,text=0,switch=0,native=0,dropped=0,nodes=0}
 local ids={}
 local parents={}
 local function harvest(node,parent)
  local attrs=node.attrs
  local id=attrs and attrs.id
  if type(id)=='string'and id~=''and ids[id]==nil then ids[id]=node end
  parents[node]=parent
  for _,child in ipairs(node.children or{})do harvest(child,node)end
 end
 harvest(root,nil)
 local viewport={width=(ctx.viewport and ctx.viewport.width)or 100,height=(ctx.viewport and ctx.viewport.height)or 100}
 local active={}
 local process
 local function properties(attrs)
  local out={}
  for key in pairs(Style.properties)do
   if attrs[key]~=nil then out[key]=attrs[key]end
  end
  return out
 end
 local function structure(attrs)
  local out=properties(attrs)
  if attrs.transform~=nil then out.transform=attrs.transform end
  return out
 end
 local function inheritInto(target,source,sourceParent,newParent)
  if newParent==nil then return end
  local attrs=source.attrs or{}
  for _,key in ipairs(inherited)do
   local value=newParent[key]
   if value~=nil then
    local own=attrs[key]
    local from=sourceParent and sourceParent[key]
    if own==nil or(from~=nil and own==from)then target.attrs[key]=value end
   end
  end
 end
 local function clone(node,sourceParent,newParent,depth)
  stats.nodes+=1
  assert(stats.nodes<=D.limits.nodes,'Arvore SVG expandida acima de '..D.limits.nodes..' nos.')
  assert(depth<=D.limits.depth,'SVG aninhado alem do limite de profundidade.')
  local attrs=U.copy(node.attrs or{})
  attrs.id=nil
  local copy={tag=node.tag,attrs=attrs,children={},text=node.text,content=node.content,key=node.key}
  inheritInto(copy,node,sourceParent,newParent)
  for _,child in ipairs(node.children or{})do
   copy.children[#copy.children+1]=clone(child,node.attrs,attrs,depth+1)
  end
  return copy
 end
 local function viewportOf(node,options)
  local attrs=node.attrs or{}
  local width=G.number(options.width,viewport.width,viewport.width)
  local height=G.number(options.height,viewport.height,viewport.height)
  assert(width>=0 and height>=0,'width e height de viewport SVG nao podem ser negativos.')
  if width<=0 or height<=0 then stats.dropped+=1;return nil end
  local box=D.viewBox(attrs.viewbox)
  local aspect=D.aspect(attrs.preserveaspectratio)
  local effective=U.copy(attrs)
  if options.parentAttrs then inheritInto({attrs=effective},node,options.sourceParent,options.parentAttrs)end
  local outer={tag='g',attrs=properties(effective),children={}}
  if attrs.transform~=nil then outer.attrs.transform=attrs.transform end
  local overflow=trim(effective.overflow or'hidden'):lower()
  if overflow~='visible'and overflow~='auto'then
   outer.attrs['data-viewport']=fmt(options.x)..' '..fmt(options.y)..' '..fmt(width)..' '..fmt(height)
  end
  local inner={tag='g',attrs={},children={}}
  local transform=D.transform(aspect,box,options.x,options.y,width,height)
  if transform then inner.attrs.transform=transform end
  local previous=viewport
  viewport=box and{width=box[3],height=box[4]}or{width=width,height=height}
  stats.viewport+=1
  for _,child in ipairs(node.children or{})do
   local source=child
   if options.parentAttrs then source=clone(child,attrs,effective,options.depth+1)end
   local built=process(source,options.depth+1,options.useDepth)
   if built then inner.children[#inner.children+1]=built end
  end
  viewport=previous
  outer.children[1]=inner
  return outer
 end
 process=function(node,depth,useDepth)
  assert(depth<=D.limits.depth,'SVG aninhado alem do limite de profundidade.')
  local tag=node.tag
  local attrs=node.attrs or{}
  assert(tag~='foreignobject','<foreignObject> nao e suportado: o plugin recusa HTML embutido em SVG de forma definitiva.')
  if depth>1 and not D.conditional(attrs,{languages=languages})then stats.dropped+=1;return nil end
  if tag=='symbol'or Style.timed and Style.timed[tag]then stats.dropped+=1;return nil end
  if tag=='tspan'or tag=='textpath'then stats.dropped+=1;return nil end
  if tag=='switch'then
   stats.switch+=1
   local out={tag='g',attrs=structure(attrs),children={}}
   for _,child in ipairs(node.children or{})do
    local childTag=child.tag
    if childTag~='foreignobject'and D.renderable[childTag]and D.conditional(child.attrs or{},{languages=languages})then
     local built=process(child,depth+1,useDepth)
     if built then out.children[1]=built end
     break
    end
   end
   return out
  end
  if tag=='use'then
   local ref=D.reference(attrs)
   assert(ref,'<use> exige href ou xlink:href apontando para um id local.')
   local target=ids[ref]
   assert(target,'<use> aponta para id inexistente: #'..ref)
   assert(not active[target],'<use> cria referencia circular: #'..ref)
   assert(useDepth<D.limits.use,'<use> encadeado alem de '..D.limits.use..' niveis.')
   assert(target.tag~='foreignobject','<use> nao instancia <foreignObject>.')
   stats.use+=1
   active[target]=true
   local x=G.number(attrs.x,0,viewport.width)
   local y=G.number(attrs.y,0,viewport.height)
   local group={tag='g',attrs=structure(attrs),children={}}
   local move='translate('..fmt(x)..' '..fmt(y)..')'
   local own=attrs.transform~=nil and trim(attrs.transform)or''
   if own=='none'then own=''end
   group.attrs.transform=(own~=''and(own..' ')or'')..move
   local parentAttrs=parents[target]and parents[target].attrs or nil
   local built
   if target.tag=='symbol'or target.tag=='svg'then
    if target.tag=='symbol'then stats.symbol+=1 end
    local targetAttrs=target.attrs or{}
    local width=attrs.width~=nil and attrs.width or targetAttrs.width or'100%'
    local height=attrs.height~=nil and attrs.height or targetAttrs.height or'100%'
    built=viewportOf(target,{x=0,y=0,width=width,height=height,depth=depth,useDepth=useDepth+1,parentAttrs=group.attrs,sourceParent=parentAttrs})
   else
    local copy=clone(target,parentAttrs,group.attrs,depth+1)
    built=process(copy,depth+1,useDepth+1)
   end
   active[target]=nil
   if built then group.children[1]=built end
   return group
  end
  if tag=='svg'and depth>1 then
   local x=G.number(attrs.x,0,viewport.width)
   local y=G.number(attrs.y,0,viewport.height)
   return viewportOf(node,{x=x,y=y,width=attrs.width or'100%',height=attrs.height or'100%',depth=depth,useDepth=useDepth})
  end
  if tag=='image'then
   local source=D.href(attrs)
   assert(type(source)=='string'and source~='','<image> exige href ou xlink:href.')
   local x=G.number(attrs.x,0,viewport.width)
   local y=G.number(attrs.y,0,viewport.height)
   local inline,mime=D.dataSvg(source)
   if inline then
    local parsed=U.xml(inline)
    assert(type(parsed)=='table'and parsed.tag=='svg','data URI de <image> precisa conter um <svg> valido.')
    local resolved=(type(ctx.resolve)=='function'and ctx.resolve(parsed))or parsed
    local inner=U.copy(resolved.attrs or{})
    if inner.viewbox==nil then
     local iw=tonumber(tostring(inner.width or''):match('^(-?%d*%.?%d+)'))
     local ih=tonumber(tostring(inner.height or''):match('^(-?%d*%.?%d+)'))
     if iw and ih and iw>0 and ih>0 then inner.viewbox='0 0 '..fmt(iw)..' '..fmt(ih)end
    end
    if attrs.preserveaspectratio~=nil then inner.preserveaspectratio=attrs.preserveaspectratio end
    local host={tag='svg',attrs=inner,children=resolved.children or{},text=resolved.text}
    local width=attrs.width~=nil and attrs.width or inner.width or'100%'
    local height=attrs.height~=nil and attrs.height or inner.height or'100%'
    stats.image+=1
    local group={tag='g',attrs=structure(attrs),children={}}
    local built=viewportOf(host,{x=x,y=y,width=width,height=height,depth=depth,useDepth=useDepth})
    if built then group.children[1]=built end
    return group
   end
   assert(mime==nil,'<image> aceita data:image/svg+xml; o tipo '..tostring(mime)..' nao e suportado sem rede nem decodificacao raster.')
   local asset=nil
   if source:match('^rbxassetid://%d+$')or source:match('^rbxasset://')or source:match('^rbxthumb://')then asset=source
   elseif source:match('^%d+$')then asset='rbxassetid://'..source end
   assert(asset,'<image> aceita data:image/svg+xml inline ou rbxassetid://; fontes externas nao sao suportadas: '..source:sub(1,80))
   local width=G.number(attrs.width,0,viewport.width)
   local height=G.number(attrs.height,0,viewport.height)
   assert(width>0 and height>0,'<image> raster exige width e height positivos.')
   stats.image+=1
   stats.native+=1
   local out={tag='image',attrs=properties(attrs),children={}}
   out.attrs.x=fmt(x)
   out.attrs.y=fmt(y)
   out.attrs.width=fmt(width)
   out.attrs.height=fmt(height)
   out.attrs.href=asset
   out.attrs.preserveaspectratio=attrs.preserveaspectratio or'xMidYMid meet'
   if attrs.transform~=nil then out.attrs.transform=attrs.transform end
   return out
  end
  if tag=='text'then
   stats.text+=1
   local group={tag='g',attrs=structure(attrs),children={}}
   local built,reason=Text.build(node,{defs=ids,tolerance=ctx.tolerance,polyline=ctx.polyline,size=ctx.size})
   if built then
    for _,child in ipairs(built)do
     for _,key in ipairs({'transform','opacity','filter','clip-path','mask','mask-image','display'})do child.attrs[key]=nil end
     group.children[#group.children+1]=child
    end
    return group
   end
   local plain=Text.plain(node)
   if plain==''then stats.dropped+=1;return nil end
   stats.native+=1
   local fallback={tag='text',attrs=properties(attrs),children={},text=plain}
   fallback.attrs.transform=nil
   local firstX=attrs.x~=nil and tostring(attrs.x):match('^[^%s,]+')or nil
   local firstY=attrs.y~=nil and tostring(attrs.y):match('^[^%s,]+')or nil
   fallback.attrs.x=fmt(G.number(firstX,0,viewport.width))
   fallback.attrs.y=fmt(G.number(firstY,0,viewport.height))
   fallback.attrs['data-native']=tostring(reason or'fonte indisponivel'):sub(1,120)
   group.children[1]=fallback
   return group
  end
  local out={tag=tag,attrs=U.copy(attrs),children={},text=node.text,content=node.content,key=node.key}
  for _,child in ipairs(node.children or{})do
   local built=process(child,depth+1,useDepth)
   if built then out.children[#out.children+1]=built end
  end
  return out
 end
 local expanded=process(root,1,0)
 assert(expanded,'Arvore SVG vazia apos o processamento condicional.')
 for key,value in pairs(root)do
  if key~='tag'and key~='attrs'and key~='children'and key~='text'and key~='content'then expanded[key]=value end
 end
 stats.ids=ids
 return expanded,stats
end
return D
