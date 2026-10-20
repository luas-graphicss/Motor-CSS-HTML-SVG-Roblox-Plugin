local U=require(script.Parent.Util)
local P=require(script.Parent.VisualEffectsPixels)
local Codec=require(script.Parent.SvgRasterRuntime)
local A={VERSION=2,MAX_IMAGES=16,MAX_SIDE=64}
local definitions={defs=true,mask=true,clippath=true}
function A.visible(node)
 if node.tag=='svg'and require(script.Parent.SvgStyle).isAdvanced(node)then return node end
 if definitions[node.tag]then return nil end
 local children,changed={},false
 for _,child in ipairs(node.children or {})do
  local visible=A.visible(child);if visible~=child then changed=true end
  if visible then children[#children+1]=visible end
 end
 if not changed then return node end
 local copy=table.clone(node);copy.children=children;return copy
end
local function clipInk(node)
 local copy=table.clone(node);copy.attrs=table.clone(node.attrs or {});copy.children={}
 local attrs=copy.attrs
 attrs.fill='white';attrs.stroke='none';attrs.opacity='1';attrs['fill-opacity']='1';attrs['stroke-opacity']='0'
 attrs['fill-rule']=attrs['clip-rule']or attrs['fill-rule'];attrs['clip-rule']=nil
 if attrs.style then
  local kept={}
  for _,decl in ipairs(U.split(attrs.style,';'))do
   local key=U.trim(decl:match('^(.-):')or '')
   if key=='clip-rule'then attrs['fill-rule']=U.trim(decl:match(':(.*)$'))
   elseif key~='fill'and key~='stroke'and key~='opacity'and key~='fill-opacity'and key~='stroke-opacity'then kept[#kept+1]=decl end
  end
  attrs.style=#kept>0 and table.concat(kept,';')or nil
 end
 for _,child in ipairs(node.children or {})do local visible=A.visible(child);if visible then copy.children[#copy.children+1]=clipInk(visible)end end
 return copy
end
local referenceDefinitions={defs=true,lineargradient=true,radialgradient=true,filter=true,mask=true,clippath=true,marker=true}
local function localDefinitions(root,excludeId)
 local out={}
 local function prune(node)
  if node.attrs and node.attrs.id==excludeId then return nil end
  local copy=table.clone(node);copy.children={}
  for _,child in ipairs(node.children or {})do local value=prune(child);if value then copy.children[#copy.children+1]=value end end
  return copy
 end
 local function collect(node)
  if referenceDefinitions[node.tag]then local value=prune(node);if value then out[#out+1]=value end;return end
  for _,child in ipairs(node.children or {})do collect(child)end
 end
 for _,child in ipairs(root.children or {})do collect(child)end
 return out
end
function A.register(doc,svgs)
 local sources={};doc.effectSvgSources=sources;doc.effectSvgDefinitions={}
 local filters={};doc.effectFilterSources=filters
 local function put(id,node)
  if not id then return end
  if sources[id]then sources[id]={_effectAmbiguous=true}else sources[id]=node end
 end
 local function walk(node,root,definitionKey)
  if node.tag=='filter'and node.attrs and node.attrs.id then
   local id=node.attrs.id
   filters[id]=filters[id]and{_effectAmbiguous=true}or{node=node,defsKey=definitionKey}
  end
  if node==root then put(node.attrs.id,A.visible(root))
  elseif node.tag=='mask'or node.tag=='clippath'then
   local attrs=node.attrs or {};local kind=node.tag;local mode=kind=='mask'and(attrs['mask-type']or 'luminance')or 'alpha'
   local groupAttrs={};local declarations={}
   for _,key in ipairs({'fill','fill-opacity','fill-rule','stroke','stroke-width','stroke-opacity','color','transform'})do groupAttrs[key]=attrs[key]or(key~='transform'and root.attrs[key]or nil)end
   for _,decl in ipairs(U.split(attrs.style or '',';'))do
    local key,value=decl:match('^%s*([%w%-]+)%s*:%s*(.-)%s*$')
    if key=='mask-type'then mode=value else declarations[#declarations+1]=decl end
   end
   if #declarations>0 then groupAttrs.style=table.concat(declarations,';')end
   local units=kind=='mask'and(attrs.maskcontentunits or 'userSpaceOnUse')or(attrs.clippathunits or 'userSpaceOnUse')
   local viewbox=units=='objectBoundingBox'and '0 0 1 1'or root.attrs.viewbox or('0 0 '..(root.attrs.width or 24)..' '..(root.attrs.height or 24))
   local children={};for _,child in ipairs(node.children or {})do local visible=A.visible(child);if visible then children[#children+1]=kind=='clippath'and clipInk(visible)or visible end end
   local group={tag='g',attrs=groupAttrs,children=children}
   local source={tag='svg',attrs={viewbox=viewbox,preserveaspectratio='none'},children={group},_effectMaskMode=mode,_effectSourceKind=kind,_effectUnits=units,_effectDefsKey=definitionKey}
   put(attrs.id,source)
  end
  for _,child in ipairs(node.children or {})do walk(child,root,definitionKey)end
 end
 local serial=0
 for _,root in pairs(svgs or {})do serial+=1;local key=tostring(serial);doc.effectSvgDefinitions[key]=root;walk(root,root,key)end
 return sources
end
function A.encode(surface)
 local runs={}
 for y=0,surface.h-1 do
  local last
  for x=0,surface.w-1 do
   local color,a=P.get(surface,x,y);local r,g,b,alpha=math.floor(color.R*255+.5),math.floor(color.G*255+.5),math.floor(color.B*255+.5),math.floor(a*255+.5)
   if last and last.channels[1]==r and last.channels[2]==g and last.channels[3]==b and last.channels[5]==alpha then last.w+=1
   else last={x=x,y=y,w=1,h=1,channels={r,g,b,0,alpha}};runs[#runs+1]=last end
  end
 end
 return Codec.encode(surface.w,surface.h,runs)
end
function A.decode(data,current)
 local w,h,runs=Codec.decode(data);local surface=P.new(w,h);current=current or Color3.new(1,1,1)
 for _,r in ipairs(runs)do
  local ch=r.channels;local color=Color3.new(math.clamp((ch[1]+ch[4]*current.R)/255,0,1),math.clamp((ch[2]+ch[4]*current.G)/255,0,1),math.clamp((ch[3]+ch[4]*current.B)/255,0,1))
  for y=r.y,r.y+r.h-1 do for x=r.x,r.x+r.w-1 do P.set(surface,x,y,color,ch[5]/255)end end
 end;return surface
end
local function dataSVG(source)
 local header,body=source:match('^(data:[^,]+),(.*)$');assert(header and body,'data SVG inválido.')
 local xml
 if header:lower():find(';base64',1,true)then
  local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local digits={};for i=1,#alphabet do digits[alphabet:sub(i,i)]=i-1 end
  body=body:gsub('%s','');assert(#body<=80000 and #body%4==0,'Base64 SVG inválido ou grande demais.')
  local output={}
  for i=1,#body,4 do
   local a,b,c,d=body:sub(i,i),body:sub(i+1,i+1),body:sub(i+2,i+2),body:sub(i+3,i+3)
   assert(digits[a]and digits[b]and(c=='='or digits[c])and(d=='='or digits[d]),'Caractere Base64 inválido.')
   assert((c~='='or d=='=')and((c~='='and d~='=')or i+3==#body),'Padding Base64 inválido.')
   local n=digits[a]*262144+digits[b]*4096+(digits[c]or 0)*64+(digits[d]or 0)
   output[#output+1]=string.char(math.floor(n/65536))
   if c~='='then output[#output+1]=string.char(math.floor(n/256)%256)end
   if d~='='then output[#output+1]=string.char(n%256)end
  end
  xml=table.concat(output)
 else xml=body:gsub('%%(%x%x)',function(h)return string.char(tonumber(h,16))end)end
 assert(#xml<=60000,'SVG de máscara excede 60 KB.');return U.xml(xml)
end
function A.svg(node,w,h,color,checkpoint)
 node=assert(A.visible(node),'Use uma raiz SVG para carregar a máscara.')
 local holder=Instance.new('Frame');holder.Size=UDim2.fromOffset(w,h)
 local result
 local ok,err=xpcall(function()
  local Svg=require(script.Parent.Svg)
  Svg.render(node,holder,color or Color3.new(1,1,1),{width=w,height=h,resolution=A.MAX_SIDE,maxPrimitives=8192,images=false,cache=false,yield=checkpoint and function()checkpoint(32)end or nil})
  local view=holder:FindFirstChild('__Svg');assert(view,'SVG não gerou superfície.');local data=view:GetAttribute('SvgTextureData')
  if data then result=A.decode(data,color)else
   result=P.new(A.MAX_SIDE,A.MAX_SIDE)
   for _,span in ipairs(view:GetChildren())do if span:IsA('Frame')then
    local x0=math.floor(span.Position.X.Scale*result.w);local y0=math.floor(span.Position.Y.Scale*result.h)
    local x1=math.ceil((span.Position.X.Scale+span.Size.X.Scale)*result.w)-1;local y1=math.ceil((span.Position.Y.Scale+span.Size.Y.Scale)*result.h)-1
    for y=math.max(0,y0),math.min(result.h-1,y1)do for x=math.max(0,x0),math.min(result.w-1,x1)do local b,ba=P.get(result,x,y);local c,a=P.over(b,ba,span.BackgroundColor3,1-span.BackgroundTransparency);P.set(result,x,y,c,a)end end
   end end
  end
 end,debug.traceback)
 holder:Destroy();if not ok then error(err,0)end;return result
end
function A.filter(doc,reference)
 local id=tostring(reference or ''):gsub('^#','')
 local entry=doc.effectFilterSources and doc.effectFilterSources[id]
 assert(entry,'Filtro SVG local não encontrado: #'..id)
 assert(not entry._effectAmbiguous,'Referência de filtro SVG ambígua: #'..id)
 local root=entry.defsKey and doc.effectSvgDefinitions and doc.effectSvgDefinitions[entry.defsKey]
 return entry.node,root
end
function A.new(doc,checkpoint,diagnostic)
 local cache,failed={},{};local count=0;local encoded=doc.effectAssets or {};doc.effectAssets=encoded
 local metadata=doc.effectAssetMetadata or {};doc.effectAssetMetadata=metadata
 local self={}
 function self:image(source)
  if cache[source]then return cache[source]end;if failed[source]then return nil end
  local result;local ok,err=pcall(function()
   assert(count<A.MAX_IMAGES,'Orçamento de 16 imagens de efeito atingido.')
   if encoded[source]then result=A.decode(encoded[source])
   elseif source:sub(1,1)=='#'then
    local node=doc.effectSvgSources and doc.effectSvgSources[source:sub(2)];assert(node,'SVG local de máscara não encontrado: '..source)
    assert(not node._effectAmbiguous,'Referência SVG local ambígua: '..source)
    assert(not node._effectMaskMode or node._effectMaskMode=='alpha'or node._effectMaskMode=='luminance','mask-type SVG inválido.')
    assert(not node._effectUnits or node._effectUnits=='userSpaceOnUse'or node._effectUnits=='objectBoundingBox','Unidades SVG de máscara inválidas.')
    local definitionRoot=node._effectDefsKey and doc.effectSvgDefinitions and doc.effectSvgDefinitions[node._effectDefsKey]
    if definitionRoot then
     local copy=table.clone(node);copy.children=localDefinitions(definitionRoot,source:sub(2))
     for _,child in ipairs(node.children or {})do copy.children[#copy.children+1]=child end;node=copy
    end
    result=A.svg(node,A.MAX_SIDE,A.MAX_SIDE,Color3.new(1,1,1),checkpoint)
    result.maskMode=node._effectMaskMode or 'alpha'
   elseif source:match('^data:image/svg%+xml')then result=A.svg(dataSVG(source),A.MAX_SIDE,A.MAX_SIDE,Color3.new(1,1,1),checkpoint)
   else
    assert(source:match('^rbxassetid://%d+$')or source:match('^rbxasset://[%w_./%-]+$'),'Fonte de imagem não permitida.')
    local image
    local success,why=pcall(function()
     image=game:GetService('AssetService'):CreateEditableImageAsync(Content.fromUri(source));assert(image,'Permissão/memória de EditableImage indisponível.')
     local size=image.Size;assert(size.X*size.Y<=4194304,'Imagem de efeito excede 4MP.')
     local rgba=image:ReadPixelsBuffer(Vector2.zero,size);local ratio=math.min(1,A.MAX_SIDE/math.max(size.X,size.Y));local w,h=math.max(1,math.floor(size.X*ratio)),math.max(1,math.floor(size.Y*ratio));result=P.new(w,h)
     for y=0,h-1 do for x=0,w-1 do
      local xx=math.clamp(math.floor((x+.5)/w*size.X),0,size.X-1);local yy=math.clamp(math.floor((y+.5)/h*size.Y),0,size.Y-1);local p=(yy*size.X+xx)*4
      P.set(result,x,y,Color3.fromRGB(buffer.readu8(rgba,p),buffer.readu8(rgba,p+1),buffer.readu8(rgba,p+2)),buffer.readu8(rgba,p+3)/255)
     end end
    end)
    if image then image:Destroy()end;if not success then error(why,0)end
   end
   local saved=metadata[source]
   if saved then result.maskMode=saved.maskMode or result.maskMode end
   result.maskMode=result.maskMode or 'alpha'
   metadata[source]={maskMode=result.maskMode}
   encoded[source]=encoded[source]or A.encode(result)
  end)
  if not ok then failed[source]=true;if diagnostic then diagnostic('asset',tostring(err))end;return nil end
  count+=1;cache[source]=result;return result
 end
 function self:path(d,rule,w,h)
  local key='path:'..rule..':'..w..':'..h..':'..d
  if cache[key]then return cache[key]end
  local node={tag='svg',attrs={viewbox='0 0 '..w..' '..h,preserveaspectratio='none'},children={{tag='path',attrs={d=d,fill='white',['fill-rule']=rule},children={}}}}
  local surface=A.svg(node,w,h,Color3.new(1,1,1),checkpoint);cache[key]=surface;return surface
 end
 function self:clear()table.clear(cache);table.clear(failed)end
 return self
end
return A
