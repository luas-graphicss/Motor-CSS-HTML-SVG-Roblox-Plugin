local U=require(script.Parent.Util)
local Cost=require(script.Parent.CostModel)
local AdvancedPaint=require(script.Parent.AdvancedPaint)
local VisualStyle=require(script.Parent.VisualStyle)
local Motion=require(script.Parent.Motion)
local TransformPaint=require(script.Parent.TransformPaint)
local TextPaint=require(script.Parent.TextPaint)
local FontFeatures=require(script.Parent.FontFeatures)
local TextWrap=require(script.Parent.TextWrap)
local SvgRasterRuntime=require(script.Parent.SvgRasterRuntime)
local RenderOptimizer=require(script.Parent.RenderOptimizer)
local applyProperties=RenderOptimizer.properties
local LayoutRuntime=require(script.Parent.LayoutRuntime)
local ScrollRuntime=require(script.Parent.ScrollRuntime)
local Overflow=require(script.Parent.Overflow)
local TablePaint=require(script.Parent.RuntimeManifest).optional('TablePaint')
local InlineBoxes=require(script.Parent.InlineBoxes)
local TextClip=require(script.Parent.TextClipPaint)
local PagePaint=require(script.Parent.PagePaint)
local P={}
local clear=table.clear
local radiusKeys=table.freeze({'border-top-left-radius','border-top-right-radius','border-bottom-right-radius','border-bottom-left-radius'})
local gradientDirections=table.freeze({['to right']=90,['to left']=270,['to bottom']=180,['to top']=0,['to bottom right']=135,['to top right']=45})
local xa=table.freeze({left=Enum.TextXAlignment.Left,center=Enum.TextXAlignment.Center,right=Enum.TextXAlignment.Right})
local ya=table.freeze({top=Enum.TextYAlignment.Top,middle=Enum.TextYAlignment.Center,center=Enum.TextYAlignment.Center,bottom=Enum.TextYAlignment.Bottom})
local function inset(rad,dist)return rad>0 and dist<rad and rad-math.sqrt(math.max(0,rad*rad-(rad-dist)^2))or 0 end
local gradientCache,gradientSlots={},{};local gradientCursor=0
local gradientParses,gradientHits=0,0
local function radialBudget(vw,vh)
 local shortest=math.min(vw or 1280,vh or 720)
 if shortest<=480 then return 48,4 elseif shortest<=600 then return 72,3.5 end
 return 96,3
end
P.radialBudget=radialBudget
function P.gradientStats()return AdvancedPaint.gradientStats()end
local function make(class,name,parent)
 local o=RenderOptimizer.acquire(class);applyProperties(o,{Name=name});RenderOptimizer.attributes(o,{CssOwned=true})
 if o:IsA('GuiObject')then applyProperties(o,{BorderSizePixel=0})end
 if parent then o.Parent=parent;RenderOptimizer.remember(parent,name,o)end
 return o
end
local function gradient(value)
 local cached=gradientCache[value]
 if cached then gradientHits+=1;return cached end
 local kind,body=value:match('^([%a%-]+)%((.*)%)$'); assert(kind=='linear-gradient' or kind=='radial-gradient','Somente linear-gradient e radial-gradient são suportados.')
 local tokens=U.split(body,','); local rotation,centerX,centerY=90,0.5,0.5
 if kind=='linear-gradient' then
  local first=tokens[1];local directions=gradientDirections
  if directions[first] then rotation=directions[first]; table.remove(tokens,1)
  elseif first:match('deg$') then rotation=assert(tonumber(first:match('^([%+%-%.%d]+)deg$')),'Ângulo de gradiente inválido.'); table.remove(tokens,1) end
 elseif tokens[1]:match('^circle') or tokens[1]:match('^ellipse') then
  local shape=tokens[1]; assert(shape=='circle' or shape=='ellipse' or shape:match('^circle at ') or shape:match('^ellipse at '),'Cabeçalho radial não suportado.')
  local x,y=shape:match('at ([%d%.]+)%% ([%d%.]+)%%'); if x then centerX,centerY=tonumber(x)/100,tonumber(y)/100 else assert(not shape:find('at',1,true),'Use centro radial em percentuais.') end
  table.remove(tokens,1)
 end
 assert(#tokens>=2 and #tokens<=16,'Use 2 a 16 stops por gradiente.')
 local stops={}
 for _,token in ipairs(tokens) do
  local words=U.split(token,' '); assert(#words==1 or #words==2,'Stop de gradiente inválido: '..token)
  local color,a=U.color(words[1]); local position=words[2] and tonumber(words[2]:match('^([%d%.]+)%%$'))
  assert(not words[2] or position,'Stops precisam estar em %.'); table.insert(stops,{color=color,a=a,t=position and position/100})
 end
 stops[1].t=stops[1].t or 0; stops[#stops].t=stops[#stops].t or 1
 local i=1
 while i<#stops do
  local j=i+1; while not stops[j].t do j+=1 end
  assert(stops[j].t>=stops[i].t and stops[j].t<=1 and stops[i].t>=0,'Stops devem crescer entre 0% e 100%.')
  for k=i+1,j-1 do stops[k].t=stops[i].t+(stops[j].t-stops[i].t)*(k-i)/(j-i) end
  i=j
 end
 if stops[1].t>0 then table.insert(stops,1,{color=stops[1].color,a=stops[1].a,t=0}) end
 if stops[#stops].t<1 then table.insert(stops,{color=stops[#stops].color,a=stops[#stops].a,t=1}) end
 for k=2,#stops do assert(stops[k].t>stops[k-1].t,'Stops coincidentes não são suportados; separe as posições.') end
 local colors,raw={},{}
 for _,stop in ipairs(stops)do colors[#colors+1]=ColorSequenceKeypoint.new(stop.t,stop.color);raw[#raw+1]=stop.t..','..stop.a end
 local definition={kind=kind,rotation=(rotation-90)%360,offset=Vector2.zero,stops=stops,cx=centerX,cy=centerY,colorSequence=ColorSequence.new(colors),rawAlpha=table.concat(raw,';'),alphaCache={},alphaCount=0}
 gradientCursor=gradientCursor%128+1;local previous=gradientSlots[gradientCursor]
 if previous then gradientCache[previous]=nil end
 gradientSlots[gradientCursor]=value;gradientCache[value]=definition;gradientParses+=1
 return definition
end
local function sequence(parent,stops,opacity,rotation,definition)
 if definition then
  local transparency=definition.alphaCache[opacity]
  if not transparency then
   local points={};for _,stop in ipairs(stops)do points[#points+1]=NumberSequenceKeypoint.new(stop.t,1-stop.a*opacity)end
   transparency=NumberSequence.new(points)
   if definition.alphaCount>=16 then table.clear(definition.alphaCache);definition.alphaCount=0 end
   definition.alphaCache[opacity]=transparency;definition.alphaCount+=1
  end
  local g=make('UIGradient','Gradient',parent)
  applyProperties(g,{Color=definition.colorSequence,Transparency=transparency,Rotation=definition.rotation,Offset=definition.offset})
  RenderOptimizer.attributes(g,{CssAlphaStops=definition.rawAlpha});return g
 end
 local colors,trans,raw={},{},{}
 for _,stop in ipairs(stops) do table.insert(colors,ColorSequenceKeypoint.new(stop.t,stop.color)); table.insert(trans,NumberSequenceKeypoint.new(stop.t,1-stop.a*opacity));table.insert(raw,stop.t..','..stop.a)end
 local g=make('UIGradient','Gradient',parent); g.Color=ColorSequence.new(colors); g.Transparency=NumberSequence.new(trans); g.Rotation=rotation or 0;g:SetAttribute('CssAlphaStops',table.concat(raw,';'))
end
local function sample(stops,t)
 t=math.clamp(t,0,1)
 for i=2,#stops do if t<=stops[i].t then local a,b=stops[i-1],stops[i]; local f=(t-a.t)/(b.t-a.t); return a.color:Lerp(b.color,f),a.a+(b.a-a.a)*f end end
 return stops[#stops].color,stops[#stops].a
end
local function radiusValues(s,w,h,vw,vh,fs)
 local r={}; for i,key in ipairs(radiusKeys) do r[i]=math.clamp(U.length(s[key],math.min(w,h),vw,vh,fs) or 0,0,math.min(w,h)/2) end
 return r
end
local function radial(parent,g,w,h,r,opacity,z,vw,vh)
 local budget,spacing=radialBudget(vw,vh)
 local rows=math.clamp(math.ceil(h/spacing),1,budget);local cx,cy=g.cx*w,g.cy*h
 parent:SetAttribute('CssRadialRows',rows)
 local radius=math.max(math.sqrt(cx*cx+cy*cy),math.sqrt((w-cx)^2+cy*cy),math.sqrt(cx*cx+(h-cy)^2),math.sqrt((w-cx)^2+(h-cy)^2),1)
 for y=0,rows-1 do
  local top,bottom=y*h/rows,(y+1)*h/rows; local mid=(top+bottom)/2; local left,right=0,w
  left=math.max(inset(r[1],mid),inset(r[4],h-mid)); right=w-math.max(inset(r[2],mid),inset(r[3],h-mid))
  if right>left then
   local band=make('Frame','RadialBand',parent); band.BackgroundColor3=Color3.new(1,1,1); band.Position=UDim2.fromOffset(left,top); band.Size=UDim2.fromOffset(right-left,bottom-top+0.05); band.ZIndex=z
   local stops={}; for x=0,15 do local px=left+(right-left)*x/15; local t=math.sqrt((px-cx)^2+(mid-cy)^2)/radius; local color,a=sample(g.stops,t); table.insert(stops,{t=x/15,color=color,a=a}) end
   sequence(band,stops,opacity,0)
  end
 end
end
local function inlineFragments(parent,s,box,rects,opacity,vw,vh)
 assert(#rects<=512,'Mais de 512 fragmentos de linha decorados em um elemento.')
 local fs=box.fs;local advanced=AdvancedPaint.needs(s);local zIndex=parent.ZIndex
 for index,rect in ipairs(rects)do
  local pw,ph=math.max(0,rect.w),math.max(0,rect.h)
  if pw>0 and ph>0 then
   local piece=make('Frame','InlineFragment'..index,parent)
   applyProperties(piece,{Position=UDim2.fromOffset(rect.x,rect.y),Size=UDim2.fromOffset(pw,ph),BackgroundTransparency=1,ZIndex=zIndex})
   local r=radiusValues(s,pw,ph,vw,vh,fs)
   if rect.block then
    if not rect.startEdge then r[1]=0;r[2]=0 end
    if not rect.endEdge then r[3]=0;r[4]=0 end
   else r=InlineBoxes.maskRadii(r,rect.startEdge,rect.endEdge,rect.rtl)end
   local widths=rect.widths
   if not widths then local value=math.max(0,U.length(s['border-width'],pw,vw,vh,fs)or 0);widths={value,value,value,value}end
   if rect.block then
    widths={widths[1],widths[2],widths[3],widths[4]}
    if not rect.startEdge then widths[1]=0 end
    if not rect.endEdge then widths[3]=0 end
   else widths=InlineBoxes.maskWidths(widths,rect.startEdge,rect.endEdge,rect.rtl)end
   if advanced then AdvancedPaint.draw(piece,s,{w=pw,h=ph,fs=fs,p=box.p,x=rect.x,y=rect.y,contentW=pw,contentH=ph},opacity,vw,vh)
   else
    local background=AdvancedPaint.legacy(s)
    if background:find('gradient(',1,true)then
     local g=gradient(background)
     if g.kind=='linear-gradient'then piece.BackgroundColor3=Color3.new(1,1,1);piece.BackgroundTransparency=0;sequence(piece,g.stops,opacity,g.rotation,g)
     else radial(piece,g,pw,ph,r,opacity,zIndex,vw,vh)end
    else local c,a=VisualStyle.color(background,s.color);piece.BackgroundColor3=c;piece.BackgroundTransparency=1-a*opacity end
    local corner=make('UICorner','Corners',piece)
    if r[1]==r[2]and r[1]==r[3]and r[1]==r[4]then corner.CornerRadius=UDim.new(0,r[1])
    else corner.TopLeftRadius=UDim.new(0,r[1]);corner.TopRightRadius=UDim.new(0,r[2]);corner.BottomRightRadius=UDim.new(0,r[3]);corner.BottomLeftRadius=UDim.new(0,r[4])end
    local style=s['border-style']or 'none'
    if style~='none'and style~='hidden'then
     local c,a=VisualStyle.color(s['border-color']or 'currentColor',s.color)
     if widths[1]>0 and widths[1]==widths[2]and widths[1]==widths[3]and widths[1]==widths[4]then
      local stroke=make('UIStroke','Border',piece)
      stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;stroke.Thickness=widths[1];stroke.Color=c;stroke.Transparency=1-a*opacity;stroke:SetAttribute('CssBaseAlpha',a)
      pcall(function()stroke.BorderStrokePosition=Enum.BorderStrokePosition.Inside end)
     else
      local sides={{0,0,pw,widths[1]},{pw-widths[2],0,widths[2],ph},{0,ph-widths[3],pw,widths[3]},{0,0,widths[4],ph}}
      for side=1,4 do
       local geometry=sides[side]
       if widths[side]>0 and geometry[3]>0 and geometry[4]>0 then
        local edge=make('Frame','Edge'..index..'_'..side,piece)
        applyProperties(edge,{Position=UDim2.fromOffset(geometry[1],geometry[2]),Size=UDim2.fromOffset(geometry[3],geometry[4]),BackgroundColor3=c,BackgroundTransparency=1-a*opacity,ZIndex=zIndex+1})
        edge:SetAttribute('CssBaseAlpha',a)
       end
      end
     end
    end
   end
  end
 end
end
local textClasses=table.freeze({TextLabel=true,TextButton=true,TextBox=true})
local function isTextObject(object)return textClasses[object.ClassName]==true end
local function dropChild(object,name)
 local child=RenderOptimizer.child(object,name)
 if child then RenderOptimizer.release(child);RenderOptimizer.remember(object,name,nil)end
end
local function hostCorners(object,r)
 if RenderOptimizer.child(object,'__ClipCorners')then dropChild(object,'__Corners');return end
 if not r or(r[1]<=0 and r[2]<=0 and r[3]<=0 and r[4]<=0)then dropChild(object,'__Corners');return end
 local corner=RenderOptimizer.child(object,'__Corners')or make('UICorner','__Corners',object)
 if r[1]==r[2]and r[1]==r[3]and r[1]==r[4]then applyProperties(corner,{CornerRadius=UDim.new(0,r[1])})
 else applyProperties(corner,{TopLeftRadius=UDim.new(0,r[1]),TopRightRadius=UDim.new(0,r[2]),BottomRightRadius=UDim.new(0,r[3]),BottomLeftRadius=UDim.new(0,r[4])})end
end
local function hostBorder(object,thickness,c,a,opacity)
 if not thickness or thickness<=0 then dropChild(object,'__Border');return end
 local stroke=RenderOptimizer.child(object,'__Border')or make('UIStroke','__Border',object)
 applyProperties(stroke,{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Thickness=thickness,Color=c,Transparency=1-a*opacity,Enabled=true})
 stroke:SetAttribute('CssBaseAlpha',a)
 pcall(function()stroke.BorderStrokePosition=Enum.BorderStrokePosition.Inside end)
end
local function hostBackground(object,paint,c,a,opacity,r)
 paint:SetAttribute('CssTextHost',true);paint:SetAttribute('CssTextHostAlpha',a)
 applyProperties(object,{BackgroundColor3=c,BackgroundTransparency=1-a*opacity});hostCorners(object,r)
end
local function hostReset(object)
 applyProperties(object,{BackgroundTransparency=1});dropChild(object,'__Corners');dropChild(object,'__Border')
end
local function hostedTransparency(object)
 local paint=RenderOptimizer.child(object,'__Paint')
 if paint and paint:GetAttribute('CssTextHost')then return object.BackgroundTransparency end
 return 1
end
local function decorate(object,s,box,opacity,vw,vh)
 local old=RenderOptimizer.child(object,'__Paint')
 local paint=make('Frame','__Paint',nil)
 local text=isTextObject(object);local hosted,hostedBorder=false,false
 local ok,err=pcall(function()
 applyProperties(paint,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=object.ZIndex-1})
 if object:IsA('TextLabel') or object:IsA('TextButton') or object:IsA('TextBox') then
  local p=box.textPadding or box.p
  paint.Position=UDim2.fromOffset(-p[4],-p[1])
  paint.Size=UDim2.new(1,p[2]+p[4],1,p[1]+p[3])
 end
 local capTop,capBottom,capLeft,capRight=box.captionTop or 0,box.captionBottom or 0,box.captionLeft or 0,box.captionRight or 0
 if capTop>0 or capBottom>0 or capLeft>0 or capRight>0 then applyProperties(paint,{Position=UDim2.fromOffset(capLeft,capTop),Size=UDim2.new(1,-(capLeft+capRight),1,-(capTop+capBottom))});box=table.clone(box);box.h=math.max(0,box.h-capTop-capBottom);box.w=math.max(0,box.w-capLeft-capRight);box.captionShift=capTop;box.captionShiftX=capLeft end
 local w,h,fs=box.w,box.h,box.fs
 local fragments=box.inlineFragmentRects
 if fragments then inlineFragments(paint,s,box,fragments,opacity,vw,vh)
 elseif AdvancedPaint.needs(s)then
  AdvancedPaint.draw(paint,s,box,opacity,vw,vh,text and function(c,a,r)hostBackground(object,paint,c,a,opacity,r)end or nil)
  hosted=paint:GetAttribute('CssTextHost')==true
 else
 local r=radiusValues(s,w,h,vw,vh,fs)
 local background=AdvancedPaint.legacy(s)
 hosted=text and not background:find('gradient(',1,true)
 if background:find('gradient(',1,true) then
  local g=gradient(background)
  if g.kind=='linear-gradient' then paint.BackgroundColor3=Color3.new(1,1,1); paint.BackgroundTransparency=0; sequence(paint,g.stops,opacity,g.rotation,g)
  else radial(paint,g,w,h,r,opacity,paint.ZIndex,vw,vh) end
 else
  local c,a=VisualStyle.color(background,s.color); paint.BackgroundColor3=c; paint.BackgroundTransparency=hosted and 1 or 1-a*opacity
  if hosted then hostBackground(object,paint,c,a,opacity,r)end
 end
 local thickness=math.max(0,U.length(s['border-width'],w,vw,vh,fs) or 0)
 local bordered=thickness>0 and s['border-style']~='none'and s['border-style']~='hidden'
 if hosted then
  if bordered then local c,a=VisualStyle.color(s['border-color']or 'currentColor',s.color);hostBorder(object,thickness,c,a,opacity)else hostBorder(object,0)end
  hostedBorder=true
 else
 local corner=make('UICorner','Corners',paint)
 if r[1]==r[2] and r[1]==r[3] and r[1]==r[4] then corner.CornerRadius=UDim.new(0,r[1])
 else corner.TopLeftRadius=UDim.new(0,r[1]); corner.TopRightRadius=UDim.new(0,r[2]); corner.BottomRightRadius=UDim.new(0,r[3]); corner.BottomLeftRadius=UDim.new(0,r[4]) end
 if bordered then
  local stroke=make('UIStroke','Border',paint); local c,a=VisualStyle.color(s['border-color']or 'currentColor',s.color)
  stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; stroke.Thickness=thickness; stroke.Color=c; stroke.Transparency=1-a*opacity;stroke:SetAttribute('CssBaseAlpha',a)
  pcall(function() stroke.BorderStrokePosition=Enum.BorderStrokePosition.Inside end)
 end
 end
 end
 if text then
  if not hosted then hostReset(object)elseif not hostedBorder then hostBorder(object,0)end
 end
 if object:IsA('ScrollingFrame')then paint.Position=UDim2.fromOffset(box._backgroundScrollX or 0,box._backgroundScrollY or 0);paint.Size=UDim2.fromOffset(w,h)end
 LayoutRuntime.decorate(paint,s,box,opacity,vw,vh)
 TablePaint.draw(paint,box,opacity)
 end)
 if not ok then RenderOptimizer.release(paint);error(err,0)end
 if old then RenderOptimizer.release(old)end
 paint.Parent=object;RenderOptimizer.remember(object,'__Paint',paint)
end
local function clipCorners(object,clip,enabled)
 local corner=RenderOptimizer.child(object,'__ClipCorners')
 local rounded=enabled and clip.rounded
 if not rounded and not corner then
  object:SetAttribute('CssContentClip',clip.shape or nil)
  object:SetAttribute('CssContentClipApproximate',nil)
  return
 end
 if not corner then dropChild(object,'__Corners');corner=make('UICorner','__ClipCorners',object)end
 local r=rounded and clip.radii or {0,0,0,0}
 if r[1]==r[2]and r[1]==r[3]and r[1]==r[4]then applyProperties(corner,{CornerRadius=UDim.new(0,r[1])})
 else applyProperties(corner,{TopLeftRadius=UDim.new(0,r[1]),TopRightRadius=UDim.new(0,r[2]),BottomRightRadius=UDim.new(0,r[3]),BottomLeftRadius=UDim.new(0,r[4])})end
 object:SetAttribute('CssContentClip',clip.shape or(rounded and'rounded')or nil)
 object:SetAttribute('CssContentClipApproximate',(rounded and clip.approximate)or nil)
end
 
 
 
local cornerKeys=table.freeze({'TopLeftRadius','TopRightRadius','BottomRightRadius','BottomLeftRadius'})
local function frameRect(child,pw,ph)
 local size,pos,anchor=child.Size,child.Position,child.AnchorPoint
 local w=size.X.Scale*pw+size.X.Offset;local h=size.Y.Scale*ph+size.Y.Offset
 return pos.X.Scale*pw+pos.X.Offset-anchor.X*w,pos.Y.Scale*ph+pos.Y.Offset-anchor.Y*h,w,h
end
local function paddedBox(parent,pw,ph)
 local pad=parent:FindFirstChildOfClass('UIPadding')
 if not pad then return 0,0,pw,ph end
 local l=pad.PaddingLeft.Offset+pad.PaddingLeft.Scale*pw;local t=pad.PaddingTop.Offset+pad.PaddingTop.Scale*ph
 local r=pad.PaddingRight.Offset+pad.PaddingRight.Scale*pw;local b=pad.PaddingBottom.Offset+pad.PaddingBottom.Scale*ph
 return l,t,math.max(0,pw-l-r),math.max(0,ph-t-b)
end
local function roundedClipContext(object)
 local child=object;local ox,oy=0,0
 for _=1,64 do
  local parent=child.Parent
  if not parent or not parent:IsA('GuiObject')then return nil end
  local ps=parent.Size
  if ps.X.Scale~=0 or ps.Y.Scale~=0 then return nil end
  local pw,ph=ps.X.Offset,ps.Y.Offset
  local pl,pt,cw,ch=paddedBox(parent,pw,ph)
  local x,y=frameRect(child,cw,ch)
  ox+=x+pl;oy+=y+pt
  if parent.ClipsDescendants and parent:GetAttribute('CssContentClip')=='rounded'then
   local corner=parent:FindFirstChild('__ClipCorners')
   if corner and corner:IsA('UICorner')then return parent,ox,oy,pw,ph,corner end
  end
  child=parent
 end
 return nil
end
local function paintsSurface(inst)
 if inst.BackgroundTransparency<1 then return true end
 if(inst:IsA('ImageLabel')or inst:IsA('ImageButton'))and inst.Image~=''then return true end
 return inst:FindFirstChildOfClass('UIStroke')~=nil
end
local function roundSurface(inst,x,y,w,h,pw,ph,radii)
 local dist={{x,y},{pw-(x+w),y},{pw-(x+w),ph-(y+h)},{x,ph-(y+h)}}
 local want;local props
 for i=1,4 do
  local r=radii[i];local dx,dy=dist[i][1],dist[i][2]
  if r>0 and dx<r and dy<r then
   local v=math.floor(r-math.max(0,math.min(dx,dy))+0.5)
   if v>0 then want=want or{};want[i]=v end
  end
 end
 if not want then return end
 local ui=inst:FindFirstChildOfClass('UICorner')or make('UICorner','__InheritedCorners',inst)
 for i,v in pairs(want)do
  local key=cornerKeys[i]
  if ui[key].Offset<v then props=props or{};props[key]=UDim.new(0,v)end
 end
 if props then applyProperties(ui,props)end
end
function P.inheritClipCorners(object)
 if not object:IsA('GuiObject')then return end
 local size=object.Size;if size.X.Scale~=0 or size.Y.Scale~=0 then return end
 local container,ox,oy,pw,ph,corner=roundedClipContext(object)
 if not container then return end
 local radii={corner.TopLeftRadius.Offset,corner.TopRightRadius.Offset,corner.BottomRightRadius.Offset,corner.BottomLeftRadius.Offset}
 local w,h=size.X.Offset,size.Y.Offset
 local touches=(ox<radii[1]and oy<radii[1])or(ox+w>pw-radii[2]and oy<radii[2])or(ox+w>pw-radii[3]and oy+h>ph-radii[3])or(ox<radii[4]and oy+h>ph-radii[4])
 if not touches then return end
 local budget=512
 local function visit(inst,x,y,iw,ih)
  budget-=1;if budget<0 then return end
  if paintsSurface(inst)then roundSurface(inst,x,y,iw,ih,pw,ph,radii)end
  local pl,pt,cw,ch=paddedBox(inst,iw,ih)
  for _,c in ipairs(inst:GetChildren())do
   if c:IsA('GuiObject')and c:GetAttribute('CssNodeKey')==nil then
    local cx,cy,cw2,ch2=frameRect(c,cw,ch)
    visit(c,x+pl+cx,y+pt+cy,cw2,ch2)
   end
  end
 end
 visit(object,ox,oy,w,h)
end
function P.apply(node,object,s,box,opacity,vw,vh,cache,isRoot)
 s=TablePaint.style(s,box)
 local z=tonumber(s['z-index']); if z then assert(z>=1 and z<=10000,'z-index deve estar entre 1 e 10000.') end
 local clipX,clipY=Overflow.clipping(s)
 local contentClip=AdvancedPaint.contentClip(s,box,vw,vh)
 local clipsContent=(((clipX or clipY)and box.clipRelaxed~=true)or contentClip.clips or box.clipsContent==true or object:IsA('ScrollingFrame'))
 applyProperties(object,{
  ZIndex=(z or node.order)*100,AnchorPoint=Vector2.new(0.5,0.5),
  Position=isRoot and UDim2.fromScale(0.5,0.5)or UDim2.fromOffset((box.viewportX or box.x)+box.w/2,(box.viewportY or box.y)+box.h/2),
  Size=(isRoot and not(s._page and s._page.size))and UDim2.fromScale(1,1)or UDim2.fromOffset(box.w,box.h),
  Visible=not box.hidden,BackgroundTransparency=hostedTransparency(object),
  ClipsDescendants=clipsContent})
 clipCorners(object,contentClip,clipsContent)
 if object:IsA('ScrollingFrame')then
  applyProperties(object,{CanvasSize=UDim2.fromOffset(box.contentW,box.contentH)});ScrollRuntime.native(object,s,box,vw,vh)
 elseif Overflow.container(s)then
  RenderOptimizer.attributes(object,{CssOverflowFallback=Overflow.serialize(Overflow.axes(s))})
 end
 if box.clipMargin then RenderOptimizer.attributes(object,{CssOverflowClipMargin=box.clipMargin,CssOverflowClipRelaxed=box.clipRelaxed==true})end
 TransformPaint.prepare(object,s,box,vw,vh,cache)
 TransformPaint.apply(object,s,Motion.transform(s.transform,cache.transformContext),cache)
 local isText=object:IsA('TextLabel') or object:IsA('TextButton') or object:IsA('TextBox')
 local color,alpha=U.color(s.color or '#ffffff')
 if isText then
  FontFeatures.apply(object,s)
  applyProperties(object,{Font=U.font(s),TextSize=box.fs,TextColor3=color,TextTransparency=1-alpha*opacity,RichText=false})
  applyProperties(object,{FontFace=U.fontFace(s),TextDirection=s.direction=='rtl'and Enum.TextDirection.RightToLeft or Enum.TextDirection.LeftToRight,LineHeight=math.clamp((s._lineHeight or box.fs*1.25)/math.max(box.fs,1),1,3)})
  local alignment=s['text-align']or 'left'
  if alignment=='start'then alignment=s.direction=='rtl'and 'right'or 'left'elseif alignment=='end'then alignment=s.direction=='rtl'and 'left'or 'right'elseif alignment=='justify'then alignment='left'end
  applyProperties(object,{
   TextXAlignment=assert(xa[alignment],'text-align não suportado.'),TextYAlignment=(box.inlineManaged and Enum.TextYAlignment.Top)or ya[s['vertical-align']or 'middle']or InlineBoxes.native(s['vertical-align']),
   TextWrapped=not TextWrap.nowrap(s),TextTruncate=s['text-overflow']=='ellipsis'and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None})
  local pad=RenderOptimizer.child(object,'__TextPadding') or make('UIPadding','__TextPadding',object)
  local p=box.textPadding or box.p
  applyProperties(pad,{PaddingTop=UDim.new(0,p[1]),PaddingRight=UDim.new(0,p[2]),PaddingBottom=UDim.new(0,p[3]),PaddingLeft=UDim.new(0,p[4])})
  local paint=RenderOptimizer.child(object,'__Paint')
  if paint then applyProperties(paint,{Position=UDim2.fromOffset(-p[4],-p[1]),Size=UDim2.new(1,p[2]+p[4],1,p[1]+p[3])})end
 end
 local elementId=node.attrs and node.attrs.id
 if elementId then AdvancedPaint.element('#'..tostring(elementId),(object:IsA('ImageLabel')and object.Image~=''and object.Image)or false)end
 if object:IsA('ImageLabel')then AdvancedPaint.fit(object,s,box,opacity)end
 local radialQuality=(s.background or ''):find('radial-gradient(',1,true)and radialBudget(vw,vh)or 0
 local signature=RenderOptimizer.signature(s);local zIndex=object.ZIndex
 local dynamicBackground=AdvancedPaint.dynamic(s)or object:IsA('ScrollingFrame')
 local assetVersion=AdvancedPaint.assetVersion()
 local attachmentChanged=dynamicBackground and(cache.paintBGX~=box._backgroundX or cache.paintBGY~=box._backgroundY or cache.paintScrollX~=box._backgroundScrollX or cache.paintScrollY~=box._backgroundScrollY or cache.paintContentW~=box.contentW or cache.paintContentH~=box.contentH)
 if cache.paintInlineStamp~=box.inlineStamp or cache.tableSignature~=box.tableSignature or attachmentChanged or cache.paintAssetVersion~=assetVersion or cache.layoutColumnSignature~=box.columnSignature or cache.paintSignature~=signature or cache.paintW~=box.w or cache.paintH~=box.h or cache.paintOpacity~=opacity or cache.paintZ~=zIndex or cache.paintQuality~=radialQuality or cache.paintVW~=vw or cache.paintVH~=vh or cache.paintFS~=box.fs or cache.paintTop~=box.p[1]or cache.paintRight~=box.p[2]or cache.paintBottom~=box.p[3]or cache.paintLeft~=box.p[4]then
  decorate(object,s,box,opacity,vw,vh)
  local scrollPaint=RenderOptimizer.child(object,'__Paint')
  if scrollPaint then ScrollRuntime.decorate(scrollPaint,object,s,box,opacity,vw,vh)end
  cache.layoutColumnSignature=box.columnSignature;cache.tableSignature=box.tableSignature;cache.paintInlineStamp=box.inlineStamp
  cache.paintAssetVersion=assetVersion;cache.paintBGX=box._backgroundX;cache.paintBGY=box._backgroundY;cache.paintScrollX=box._backgroundScrollX;cache.paintScrollY=box._backgroundScrollY;cache.paintContentW=box.contentW;cache.paintContentH=box.contentH
  cache.paintSignature=signature;cache.paintW=box.w;cache.paintH=box.h;cache.paintOpacity=opacity;cache.paintZ=zIndex;cache.paintQuality=radialQuality
  cache.paintVW=vw;cache.paintVH=vh;cache.paintFS=box.fs
  cache.paintTop=box.p[1];cache.paintRight=box.p[2];cache.paintBottom=box.p[3];cache.paintLeft=box.p[4];cache.paintKey=nil
 end
 if isRoot then
  local pageSignature=PagePaint.signature(s)
  if cache.pageSignature~=pageSignature or cache.pageW~=box.w or cache.pageH~=box.h or cache.pageOpacity~=opacity then
   PagePaint.apply(object,s,box,opacity)
   cache.pageSignature=pageSignature;cache.pageW=box.w;cache.pageH=box.h;cache.pageOpacity=opacity
  end
 end
 TextPaint.apply(node,object,s,box,opacity,cache)
 LayoutRuntime.paintText(object,s,box,opacity,cache)
 local textClip=TextClip.active(s)
 if textClip then TextClip.apply(object,s,box,opacity,vw,vh)
 elseif object:GetAttribute('CssTextClip')then TextClip.clear(object)end
 object:SetAttribute('CssTextClip',textClip or nil)
 local svg=RenderOptimizer.child(object,'__Svg')
 if svg then
  local aspect=svg:GetAttribute('SvgAspect'); local mode=svg:GetAttribute('SvgPreserve'); local sw,sh=box.w,box.h
  if mode~='none' then
   if (sw/math.max(sh,0.001)>aspect)==(not mode:find('slice',1,true)) then sw=sh*aspect else sh=sw/aspect end
  end
  local ax=mode:find('xMin',1,true) and 0 or mode:find('xMax',1,true) and 1 or 0.5
  local ay=mode:find('YMin',1,true) and 0 or mode:find('YMax',1,true) and 1 or 0.5
  svg.Size=UDim2.fromOffset(sw,sh); svg.Position=UDim2.fromOffset((box.w-sw)*ax,(box.h-sh)*ay); object.ClipsDescendants=true
  if svg:GetAttribute('SvgFlattened')then SvgRasterRuntime.paint(svg,object,color,opacity)
  else
   for _,span in ipairs(svg:GetChildren())do
    if span:IsA('Frame')then
     span.ZIndex=object.ZIndex+(span:GetAttribute('SvgLayer')or 1)
     span.BackgroundTransparency=1-(span:GetAttribute('SvgAlpha')or 1)*opacity
     if span:GetAttribute('SvgCurrentColor')then span.BackgroundColor3=color end
    end
   end
  end
 end
 P.inheritClipCorners(object)
end

local function alphaTargets(object,cache)
 local paint=RenderOptimizer.child(object,'__Paint');local svg=RenderOptimizer.child(object,'__Svg')
 local svgImage=svg and svg:FindFirstChild('__SvgImage')
 if cache.motionPaint~=paint or cache.motionSvg~=svg or cache.motionSvgImage~=svgImage or not cache.alphaTargets then
  cache.motionPaint,cache.motionSvg,cache.motionSvgImage=paint,svg,svgImage
  cache.alphaTargets=cache.alphaTargets or {};cache.gradientTargets=cache.gradientTargets or {};cache.svgTargets=cache.svgTargets or {}
  clear(cache.alphaTargets);clear(cache.gradientTargets);clear(cache.svgTargets)
  cache.motionHosted=paint~=nil and paint:GetAttribute('CssTextHost')==true
  local border=RenderOptimizer.child(object,'__Border')
  if border then table.insert(cache.alphaTargets,{object=border,alpha=border:GetAttribute('CssBaseAlpha')or 1})end
  if paint then
   for _,o in ipairs(paint:GetDescendants())do
    local a=o:GetAttribute('CssBaseAlpha')
    if a~=nil then table.insert(cache.alphaTargets,{object=o,alpha=a})end
    local raw=o:GetAttribute('CssAlphaStops')
    if raw then local stops={};for _,item in ipairs(U.split(raw,';'))do local n=U.numbers(item);table.insert(stops,{t=n[1],a=n[2]})end;table.insert(cache.gradientTargets,{object=o,stops=stops})end
   end
  end
  if svg then for _,o in ipairs(svg:GetChildren())do if o:IsA('Frame')or o:IsA('ImageLabel')then table.insert(cache.svgTargets,{object=o,alpha=o:GetAttribute('SvgAlpha')or 1,image=o:IsA('ImageLabel')})end end end
  cache.motionLastOpacity=nil;cache.motionLastBackground=nil;cache.motionLastTransform=nil;cache.motionLastDistance=nil
 end
 return paint
end
function P.applyMotion(object,style,values,opacity,cache,force)
 local paint=alphaTargets(object,cache)
 local opacityChanged=force or cache.motionLastOpacity~=opacity
 if opacityChanged or not Motion.equal(cache.motionLastBackground,values.background)then AdvancedPaint.motion(paint,values,opacity,cache)end
 local backgroundChanged=opacityChanged or not Motion.equal(cache.motionLastBackground,values.background)
 if paint and not paint:GetAttribute('CssAdvancedPaint')and values.background and backgroundChanged then
  paint.BackgroundColor3=values.background.color
  if not cache.motionHosted then paint.BackgroundTransparency=1-values.background.alpha*opacity end
 end
 if paint and cache.motionHosted and backgroundChanged then
  local background=values.background
  if background then object.BackgroundColor3=background.color;object.BackgroundTransparency=1-background.alpha*opacity
  else object.BackgroundTransparency=1-(paint:GetAttribute('CssTextHostAlpha')or 1)*opacity end
 end
 if opacityChanged then
  for _,a in ipairs(cache.alphaTargets)do if a.object:IsA('GuiObject')then a.object.BackgroundTransparency=1-a.alpha*opacity else a.object.Transparency=1-a.alpha*opacity end end
  if #cache.gradientTargets>0 then
   local seq=cache.motionSequence;if not seq then seq=table.create(18);cache.motionSequence=seq end
   for _,g in ipairs(cache.gradientTargets)do
    clear(seq);for i,stop in ipairs(g.stops)do seq[i]=NumberSequenceKeypoint.new(stop.t,1-stop.a*opacity)end
    g.object.Transparency=NumberSequence.new(seq)
   end
   clear(seq)
  end
  for _,a in ipairs(cache.svgTargets)do
   if a.image then a.object.ImageTransparency=1-a.alpha*opacity else a.object.BackgroundTransparency=1-a.alpha*opacity end
  end
  if object:GetAttribute('CssInlineManaged')then TextPaint.opacity(object,opacity,cache)
  elseif object:GetAttribute('CssTextClip')then object.TextTransparency=math.clamp(1-(object:GetAttribute('CssTextClipAlpha')or 1)*opacity,0,1)
  elseif object:IsA('TextLabel')or object:IsA('TextButton')or object:IsA('TextBox')then local _,a=U.color(style.color or '#ffffff');object.TextTransparency=1-a*opacity end
  if object:IsA('ImageLabel')then AdvancedPaint.imageOpacity(object,opacity)end
 end
 local distance=values['offset-distance']
 if force or not Motion.equal(cache.motionLastTransform,values.transform)or not Motion.equal(cache.motionLastDistance,distance)then
  TransformPaint.apply(object,style,values.transform,cache,distance)
 end
 LayoutRuntime.opacity(object,opacity,cache)
 cache.motionLastOpacity=opacity;cache.motionLastBackground=values.background;cache.motionLastTransform=values.transform;cache.motionLastDistance=distance
end
return P
