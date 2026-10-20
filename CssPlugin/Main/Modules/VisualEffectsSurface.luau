local U=require(script.Parent.Util)
local P=require(script.Parent.VisualEffectsPixels)
local Clip=require(script.Parent.VisualEffectsGeometry)
local Scene=require(script.Parent.VisualEffectsScene)
local NativeText=require(script.Parent.VisualEffectsNativeText)
local Glyphs=require(script.Parent.RuntimeManifest).optional('VisualEffectsGlyphs')
local Cost=require(script.Parent.CostModel)
local F={VERSION=4,MAX_BAND_PIXELS=4096}
local bindings=setmetatable({},{__mode='k'})
local retained=setmetatable({},{__mode='k'})
local properties={'BackgroundColor3','BackgroundTransparency','Visible','ImageTransparency','ImageColor3','TextTransparency','TextColor3','TextStrokeTransparency','TextStrokeColor3'}
local textProps={'Text','FontFace','TextSize','TextColor3','TextTransparency','TextStrokeColor3','TextStrokeTransparency','TextWrapped','TextScaled','TextTruncate','TextXAlignment','TextYAlignment','RichText','LineHeight','MaxVisibleGraphemes','AutoLocalize','TextDirection','OpenTypeFeatures'}
local auxNames={'__CssMaskText','__CssGlyphFilters'}
local auxSet={};for _,name in ipairs(auxNames)do auxSet[name]=true end
 
 
 
local changed=setmetatable({},{__mode='k'})
local auxes=setmetatable({},{__mode='k'})
local primed=setmetatable({},{__mode='k'})
local function make(class,name,parent)
 local o=Instance.new(class);o.Name=name;o:SetAttribute('CssOwned',true);o:SetAttribute('CssNoPool',true);o:SetAttribute('CssEffectAux',true)
 if o:IsA('GuiObject')then o.BorderSizePixel=0;o.BackgroundTransparency=1;o.Active=false;o.Selectable=false end
 auxes[o]=true;o.Parent=parent;return o
end
local function prime(object)
 if primed[object]then return end;primed[object]=true
 for _,d in ipairs(object:GetDescendants())do
  local attributes=d:GetAttributes()
  if attributes.CssEffectAux then auxes[d]=true
  else for name in pairs(attributes)do if name:sub(1,9)=='CssFxBase'then changed[d]=true;break end end end
 end
 local attributes=object:GetAttributes()
 for name in pairs(attributes)do if name:sub(1,9)=='CssFxBase'then changed[object]=true;break end end
end
function F.change(o,key,value)
 local name='CssFxBase'..key;if o:GetAttribute(name)==nil then o:SetAttribute(name,o[key])end;o[key]=value;changed[o]=true
end
local function restoreOne(o)
 for _,key in ipairs(properties)do local name='CssFxBase'..key;local value=o:GetAttribute(name);if value~=nil then pcall(function()o[key]=value end);o:SetAttribute(name,nil)end end
 changed[o]=nil
end
local function under(o,owned)
 local p=o
 while p do if owned[p]then return true end;p=p.Parent end
 return false
end
function F.restore(object)
 prime(object);restoreOne(object)
 for o in pairs(changed)do if o~=object and o:IsDescendantOf(object)and not o:GetAttribute('CssEffectAux')then restoreOne(o)end end
end
local function release(view,keep)
 local b=bindings[view];if not b then return end;bindings[view]=nil
 if b.connection then b.connection:Disconnect()end
 if b.label then b.label:Destroy()end;if b.image then b.image:Destroy()end
 if keep then for _,child in ipairs(view:GetChildren())do if child:IsA('Frame')then child.Visible=true end end;view:SetAttribute('CssEffectBackend','NativeGradientBands')end
end
function F.release(root,keep)
 local list={};for view in pairs(bindings)do if view==root or view:IsDescendantOf(root)then list[#list+1]=view end end
 for _,view in ipairs(list)do release(view,keep)end
 for view in pairs(retained)do if view==root or view:IsDescendantOf(root)then retained[view]=nil end end
end
local function clearAux(object)
 prime(object)
 for child in pairs(auxes)do
  if auxSet[child.Name]and child:IsDescendantOf(object)then child:Destroy();auxes[child]=nil end
 end
end
local function mark(object)
 local old=object:FindFirstChild('__CssEffects')
 if old then local state=retained[old]or {};state.used=false;retained[old]=state end
end
function F.begin(object)
 F.restore(object);clearAux(object);mark(object)
end
 
function F.beginAll(objects)
 local owned={}
 for _,object in pairs(objects)do owned[object]=true;prime(object)end
 for o in pairs(changed)do
  if (owned[o]or not o:GetAttribute('CssEffectAux'))and under(o,owned)then restoreOne(o)end
 end
 for child in pairs(auxes)do
  if auxSet[child.Name]and under(child,owned)then child:Destroy();auxes[child]=nil end
 end
 for _,object in pairs(objects)do mark(object)end
end
function F.sweep(object)
 local old=object:FindFirstChild('__CssEffects');local state=old and retained[old]
 if old and not(state and state.used)then release(old,false);retained[old]=nil;old:Destroy()end
end
function F.clear(object)
 local old=object:FindFirstChild('__CssEffects');if old then release(old,false);retained[old]=nil;old:Destroy()end
 clearAux(object)
end
local function spend(budget,n)
 budget.count=(budget.count or 0)+n;assert(budget.count<=8000,'Efeitos excedem 8000 primitivas nativas; reduza a quantidade/complexidade.')
end
function F.draw(e,budget,images)
 local object=e.object;if not object or not e.surface then return end
 local p=e.isText and(e.box.textPadding or e.box.p)or {0,0,0,0}
 local signature=table.concat({e.surface.w,e.surface.h,e.region.x,e.region.y,e.region.w,e.region.h,p[1],p[4],object.ZIndex,images==false and '0'or '1'},':')..'|'..buffer.tostring(e.surface.data)
 local old=object:FindFirstChild('__CssEffects');local previous=old and retained[old]
 if previous and previous.signature==signature then
  spend(budget,previous.primitives);previous.used=true;old.Visible=true;budget.reused=(budget.reused or 0)+1;return old
 end
 local before=budget.count or 0
 local stale=object:FindFirstChild('__CssEffects');if stale then release(stale,false);retained[stale]=nil;stale:Destroy()end
 local root=make('Frame','__CssEffects',object);root:SetAttribute('CssEffectSurface',true)
 root.Position=UDim2.fromOffset(e.region.x-p[4],e.region.y-p[1]);root.Size=UDim2.fromOffset(e.region.w,e.region.h);root.ZIndex=object.ZIndex-1
 local surface=e.surface
 local grid=surface
 local bandLimit=F.MAX_BAND_PIXELS or 4096
 if surface.w*surface.h>bandLimit then
  local ratio=math.sqrt(bandLimit/(surface.w*surface.h))
  grid=P.resample(surface,math.max(1,math.floor(surface.w*ratio)),math.max(1,math.floor(surface.h*ratio)))
 end
 for y=0,grid.h-1 do
  for start=0,grid.w-1,14 do
   local last=math.min(grid.w-1,start+13);local width=last-start+1;local colors,alpha={},{}
   local firstC,firstA=P.get(grid,start,y);local solid=true
   colors[1]=ColorSequenceKeypoint.new(0,firstC);alpha[1]=NumberSequenceKeypoint.new(0,1-firstA)
   for x=start,last do
    local c,a=P.get(grid,x,y);local t=(x-start+.5)/width
    colors[#colors+1]=ColorSequenceKeypoint.new(t,c);alpha[#alpha+1]=NumberSequenceKeypoint.new(t,1-a)
    if c~=firstC or math.abs(a-firstA)>1e-6 then solid=false end
   end
   local c,a=P.get(grid,last,y);colors[#colors+1]=ColorSequenceKeypoint.new(1,c);alpha[#alpha+1]=NumberSequenceKeypoint.new(1,1-a)
   if not solid or firstA>1e-5 then
    local band=make('Frame','Band',root);band.Position=UDim2.fromScale(start/grid.w,y/grid.h);band.Size=UDim2.fromScale(width/grid.w,1/grid.h);band.ZIndex=root.ZIndex
    spend(budget,1)
    if solid then band.BackgroundColor3=firstC;band.BackgroundTransparency=1-firstA
    else band.BackgroundColor3=Color3.new(1,1,1);band.BackgroundTransparency=0;local g=make('UIGradient','Pixels',band);g.Color=ColorSequence.new(colors);g.Transparency=NumberSequence.new(alpha);spend(budget,1)end
   end
  end
 end
 root:SetAttribute('CssEffectBackend','NativeGradientBands');root:SetAttribute('CssEffectResolution',Vector2.new(surface.w,surface.h));root:SetAttribute('CssEffectBandResolution',Vector2.new(grid.w,grid.h))
 if images~=false then
  local image,label
  local ok,err=pcall(function()
   image=game:GetService('AssetService'):CreateEditableImage({Size=Vector2.new(surface.w,surface.h)});assert(image,'EditableImage indisponível.')
   image:WritePixelsBuffer(Vector2.zero,Vector2.new(surface.w,surface.h),P.rgba(surface))
   label=make('ImageLabel','__EffectImage',root);label.Size=UDim2.fromScale(1,1);label.ZIndex=root.ZIndex;label.ImageContent=Content.fromObject(image)
  end)
  if ok then
   for _,child in ipairs(root:GetChildren())do if child:IsA('Frame')then child.Visible=false end end
   local b={image=image,label=label};bindings[root]=b;b.connection=root.Destroying:Connect(function()release(root,false)end)
   root:SetAttribute('CssEffectBackend','EditableImage')
  else
   if label then label:Destroy()end;if image then image:Destroy()end;root:SetAttribute('CssEffectFallback',tostring(err):sub(1,240))
  end
 end
 retained[root]={signature=signature,primitives=(budget.count or 0)-before,used=true};budget.created=(budget.created or 0)+1
 return root
end
function F.hide(entry)
 if not entry.object then return end;local o=entry.object
 local paint=o:FindFirstChild('__Paint');if paint then F.change(paint,'Visible',false)end
 local svg=o:FindFirstChild('__Svg');if svg and entry.svg then F.change(svg,'Visible',false)end
 if entry.image then F.change(o,'ImageTransparency',1)end
 local old=o:FindFirstChild('__CssEffects');if old then old.Visible=false end
end
local function chainOf(entry)
 local chain={};local current=entry
 while current do for _,f in ipairs(current.plan.filters)do chain[#chain+1]=f end;current=current.parent end
 return chain
end
local function sigmaFrom(blurs,from)
 local sum=0
 for i=from,#blurs do local v=blurs[i].value or 0;sum+=v*v end
 return math.sqrt(sum)
end
local function stampGlyph(host,o,name,color,alpha,strokeColor,strokeAlpha,dx,dy,z)
 local label=make('TextLabel',name,host)
 for _,key in ipairs(textProps)do pcall(function()label[key]=o[key]end)end
 label.Position=UDim2.new(0,dx,0,dy);label.Size=UDim2.fromScale(1,1);label.ZIndex=z
 label.TextColor3=color;label.TextTransparency=1-math.clamp(alpha,0,1)
 if strokeColor then label.TextStrokeColor3=strokeColor end
 label.TextStrokeTransparency=1-math.clamp(strokeAlpha or 0,0,1)
 return label
end
function F.glyphFilters(entry,ink,chain,color,alpha,strokeColor,strokeAlpha,budget,report)
 local blurs,shadows={},{}
 for index,f in ipairs(chain)do
  if f.name=='blur'then blurs[#blurs+1]=f
  elseif f.name=='drop-shadow'then shadows[#shadows+1]={filter=f,index=index,from=#blurs+1}end
 end
 if #blurs==0 and #shadows==0 then return nil end
 local sigma=sigmaFrom(blurs,1)
 local limit=math.clamp(math.floor((Cost.limits().glyphs or 64)/math.max(1,#shadows+1)),4,Glyphs.MAX_TAPS)
 local host=make('Frame','__CssGlyphFilters',ink)
 host.Position=UDim2.new();host.Size=UDim2.fromScale(1,1);host.ZIndex=ink.ZIndex
 local z=0
 for i=#shadows,1,-1 do
  local item=shadows[i];local f=item.filter
  local own=math.max(0,f.blur or 0);local after=sigmaFrom(blurs,item.from)
  local tint,tintAlpha=U.color(f.ink)
  local post={}
  for k=item.index+1,#chain do local g=chain[k];if g.name~='blur'and g.name~='drop-shadow'then post[#post+1]=g end end
  tint,tintAlpha=P.colors(tint,math.clamp(tintAlpha*alpha,0,1),post)
  local stacked=Glyphs.stack(Glyphs.kernel(math.sqrt(own*own+after*after),limit),tintAlpha)
  spend(budget,#stacked)
  for _,tap in ipairs(stacked)do z+=1;stampGlyph(host,ink,'GlyphShadow',tint,tap.alpha,tint,0,(f.x or 0)+tap.dx,(f.y or 0)+tap.dy,z)end
 end
 local ratio=alpha>0 and math.clamp((strokeAlpha or 0)/alpha,0,1)or 0
 local stacked=Glyphs.stack(Glyphs.kernel(sigma,limit),alpha)
 if #stacked==0 then
  z+=1;stampGlyph(host,ink,'Glyphs',color,alpha,strokeColor,strokeAlpha,0,0,z);spend(budget,1)
 else
  spend(budget,#stacked)
  for _,tap in ipairs(stacked)do z+=1;stampGlyph(host,ink,'Glyphs',color,tap.alpha,strokeColor,tap.alpha*ratio,tap.dx,tap.dy,z)end
 end
 host:SetAttribute('CssEffectGlyphBackend','NativeStampedTaps')
 host:SetAttribute('CssEffectGlyphTaps',#host:GetChildren())
 host:SetAttribute('CssEffectGlyphSigma',sigma)
 F.change(ink,'TextTransparency',1);F.change(ink,'TextStrokeTransparency',1)
 if #shadows>1 then report(entry,'glyph-filter-chain','Cadeia com vários drop-shadow: cada sombra amostra o glifo com o desfoque acumulado; sombra de sombra não é reproduzida.')end
 report(entry,'glyph-filter-resolution',string.format('blur/drop-shadow sobre glifos: %d cópias amostradas em kernel gaussiano (sigma %.2f px).',#host:GetChildren(),sigma))
 return host
end
function F.tint(entry,report,budget)
 if not entry.object then return end
 local chain=chainOf(entry)
 if #chain==0 then return end
 local o=entry.object
 for _,target in ipairs(NativeText.targets(entry))do
  local ink=target.object
  if target.isFill then
   local c,a=P.colors(ink.BackgroundColor3,1-ink.BackgroundTransparency,chain);F.change(ink,'BackgroundColor3',c);F.change(ink,'BackgroundTransparency',1-a)
  else
   local c,a=P.colors(ink.TextColor3,1-ink.TextTransparency,chain)
   local stroke,sa=P.colors(ink.TextStrokeColor3,1-ink.TextStrokeTransparency,chain)
   F.change(ink,'TextColor3',c);F.change(ink,'TextTransparency',1-a)
   F.change(ink,'TextStrokeColor3',stroke);F.change(ink,'TextStrokeTransparency',1-sa)
   if budget then F.glyphFilters(entry,ink,chain,c,a,stroke,sa,budget,report)end
   if ink.RichText then report(entry,'rich-text','Cores explícitas em tags RichText não podem receber filtro de tinta nativa.')end
  end
 end
 if entry.unreadableImage and(o:IsA('ImageLabel')or o:IsA('ImageButton'))then local c=P.colors(o.ImageColor3,1,chain);F.change(o,'ImageColor3',c)end
end
local function blendSource(target,owner)
 local up=target
 while up do
  if up.plan and up.plan.blend and up.plan.blend~='normal'and up.backdropSample then return up end
  if up==owner then break end
  up=up.parent
 end
 return nil
end
local function bands(e,budget,rects,name,host,nativePadding,unit)
 local o=e.object
 local root=make('Frame',name,o);root.Size=UDim2.fromOffset(e.box.w,e.box.h);root.ZIndex=o.ZIndex+1
 local pad=e.box.textPadding or e.box.p or {0,0,0,0};root.Position=UDim2.fromOffset(-pad[4],-pad[1])
 local cw,ch=math.max(1,e.box.w-(pad[2]+pad[4])),math.max(1,e.box.h-(pad[1]+pad[3]))
 local created={}
 for _,r in ipairs(rects)do
  spend(budget,unit)
  local strip=make('CanvasGroup','MaskBand',root);strip.Position=UDim2.fromOffset(r.x,r.y);strip.Size=UDim2.fromOffset(r.w,r.h);strip.ClipsDescendants=true;strip.GroupTransparency=1-r.a;strip.ZIndex=o.ZIndex
  local inner
  if host then
   inner=host:Clone();inner.Parent=strip
   inner.Position=UDim2.fromOffset(pad[4]-r.x,pad[1]-r.y);inner.Size=UDim2.fromOffset(cw,ch)
  elseif e.isFill then
   inner=make('Frame','Ink',strip);inner.BackgroundColor3=o.BackgroundColor3;inner.BackgroundTransparency=o.BackgroundTransparency
   local round=o:FindFirstChildWhichIsA('UICorner');if round then local copy=make('UICorner','Round',inner);copy.CornerRadius=round.CornerRadius;spend(budget,1)end
   inner.Position=UDim2.fromOffset(-r.x,-r.y);inner.Size=UDim2.fromOffset(e.box.w,e.box.h)
  else
   inner=make('TextLabel','Glyphs',strip);for _,key in ipairs(textProps)do pcall(function()inner[key]=o[key]end)end
   if nativePadding then local copy=nativePadding:Clone();copy:SetAttribute('CssEffectAux',true);copy.Parent=inner end
   inner.Position=UDim2.fromOffset(-r.x,-r.y);inner.Size=UDim2.fromOffset(e.box.w,e.box.h)
  end
  inner.ZIndex=o.ZIndex
  created[#created+1]={rect=r,object=inner}
 end
 return root,created
end
function F.maskText(owner,entries,budget,report,checkpoint)
 if not owner.object then return end
 local targets={};for _,entry in pairs(entries)do for _,target in ipairs(NativeText.targets(entry))do targets[#targets+1]=target end end
 for _,e in ipairs(targets)do
  local under=false;local up=e;while up do if up==owner then under=true;break end;up=up.parent end
  if not under or e.box.hidden or e.box.w<=0 or e.box.h<=0 then continue end
  local o=e.object
  local host=o:FindFirstChild('__CssGlyphFilters')
  if not host then
   if e.isFill then if o.BackgroundTransparency>=1 then continue end
   elseif o.Text==''or(o.TextTransparency>=1 and o.TextStrokeTransparency>=1)then continue end
  end
  local masks={};up=e
  while up do
   if up.clip and(up.clip.kind~='none'or up.masks)then masks[#masks+1]=up end
   up=up.parent
  end
  local blender=blendSource(e,owner)
  if #masks==0 and not blender then continue end
  if o:IsA('TextBox')then report(e,'editable-mask','O campo editável permanece nativo; use um contêiner com overflow:hidden para recorte retangular do caret.');continue end
  local cost=0;for _,mask in ipairs(masks)do cost+=(mask.clip.points and #mask.clip.points or 1)+(mask.masks and #mask.masks*8 or 0)end
  if blender then cost+=4 end
  local nativePadding=o:FindFirstChild('__TextPadding')
  local unit=host and #host:GetChildren()+1 or(nativePadding and 3 or 2)
  local maxRects=math.clamp(math.floor((7800-(budget.count or 0))/math.max(1,unit)),8,4096)
  local maxCells=math.clamp(math.floor((Cost.limits().bands or 8000)*4/math.max(1,cost)),4096,65536)
  local ink,mode
  if blender then
   mode=blender.plan.blend
   if e.isFill then ink=o.BackgroundColor3
   else local first=host and host:FindFirstChild('Glyphs')or o;ink=first.TextColor3 end
  end
  local result=Glyphs.strips(e.box.w,e.box.h,{levels=255,maxRects=maxRects,maxCells=maxCells,supersample=2,cost=math.max(1,cost),colors=blender~=nil,spent=budget.maskWork or 0},function(px,py)
   local gx,gy=Scene.world(e,px,py)
   local a=1
   for _,mask in ipairs(masks)do
    local lx,ly=Scene.localPoint(mask,gx,gy)
    a*=Clip.coverage(mask.clip,lx,ly,0,0)*Clip.alpha(mask.masks,lx,ly)
    if a<=0 then break end
   end
   if not blender then return a end
   local b,ba=blender.backdropSample(gx,gy)
   if ba<=0 then return a,ink end
   return a,ink:Lerp(P.blend(b,ink,mode),math.clamp(ba,0,1))
  end,checkpoint)
  budget.maskWork=(budget.maskWork or 0)+result.work
  Cost.cap('pixels',budget.maskWork,'Amostragem de máscara/blend de texto')
  local root,created=bands(e,budget,result.rects,'__CssMaskText',host,nativePadding,unit)
  if blender then
   for _,item in ipairs(created)do
    local color=item.rect.color
    if color then
     if host then for _,child in ipairs(item.object:GetDescendants())do if child.Name=='Glyphs'and child:IsA('TextLabel')then child.TextColor3=color end end
     elseif e.isFill then item.object.BackgroundColor3=color
     else item.object.TextColor3=color end
    end
   end
  end
  if host then host.Visible=false end
  root:SetAttribute('CssEffectMaskBackend',blender and 'NativeTextBandsBlend'or 'NativeTextBands')
  root:SetAttribute('CssEffectMaskResolution',Vector2.new(result.cols,result.rows))
  root:SetAttribute('CssEffectMaskCell',Vector2.new(result.cellWidth,result.cellHeight))
  root:SetAttribute('CssEffectMaskLevels',result.levels)
  if e.isFill then F.change(o,'BackgroundTransparency',1)else F.change(o,'TextTransparency',1);F.change(o,'TextStrokeTransparency',1)end
  if #masks>0 then report(e,'text-mask-resolution',string.format('Máscara de texto em %d bandas nativas de %.2f×%.2f px com %d níveis de alfa (grade %d×%d).',#result.rects,result.cellWidth,result.cellHeight,result.levels,result.cols,result.rows))end
  if blender then report(e,'text-blend',string.format('mix-blend-mode "%s" aplicado ao texto por região: %d bandas de %.2f×%.2f px amostrando o backdrop.',mode,#result.rects,result.cellWidth,result.cellHeight))end
 end
end
return F
