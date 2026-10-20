local U=require(script.Parent.Util)
local F=require(script.Parent.FontFaces)
local Features=require(script.Parent.FontFeatures)
local Bidi=require(script.Parent.TextBidi)
local O=require(script.Parent.RenderOptimizer)
local T={VERSION=1}
local function make(class,name,parent,properties,attributes)
 local o=O.acquire(class);properties=properties or {};properties.Name=name
 if o:IsA('GuiObject')then properties.BorderSizePixel=0;properties.Active=false;properties.Selectable=false end
 O.properties(o,properties);O.attributes(o,{CssOwned=true,CssInlinePart=true})
 if attributes then O.attributes(o,attributes)end
 if parent then o.Parent=parent end;return o
end
local function ink(value,style)
 if not value or value:lower()=='currentcolor'then value=style.color end
 return U.color(value or '#ffffff')
end
local function label(parent,f,style,color,alpha,dx,dy,z,name)
 local object=make('TextLabel',name,parent,{
  BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(f.cx+(dx or 0),f.cy+(dy or 0)),
  Size=UDim2.fromOffset(f.drawW+2,f.drawH),Rotation=f.rotation,Text=Bidi.paintText(f.text,f.bidiOverride),FontFace=F.face(style),TextSize=style._fontPx or 16,
  TextColor3=color,TextTransparency=1-alpha,TextStrokeTransparency=1,TextWrapped=false,RichText=false,AutoLocalize=false,
  TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Top,TextTruncate=Enum.TextTruncate.None,
  TextDirection=f.direction=='rtl'and Enum.TextDirection.RightToLeft or Enum.TextDirection.LeftToRight,ZIndex=z,
 },{CssTextAlpha=alpha})
 Features.apply(object,style);return object
end
local function stroke(parent,x1,y1,x2,y2,thickness,color,alpha,z,round)
 local dx,dy=x2-x1,y2-y1;local length=math.sqrt(dx*dx+dy*dy)
 if length<=0 or thickness<=0 then return end
 local o=make('Frame','Decoration',parent,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset((x1+x2)/2,(y1+y2)/2),Size=UDim2.fromOffset(length,thickness),Rotation=math.deg(math.atan2(dy,dx)),BackgroundColor3=color,BackgroundTransparency=1-alpha,ZIndex=z},{CssFillAlpha=alpha})
 if round then make('UICorner','Round',o,{CornerRadius=UDim.new(1,0)})end
end
local function decoration(parent,f,style,opacity,z)
 local color,alpha=ink(style['text-decoration-color'],style);alpha*=opacity
 local fs=style._fontPx or 16;local thick=tonumber(style['text-decoration-thickness'])or math.max(1,fs/16)
 local pattern=style['text-decoration-style']or 'solid'
 for line in (style['text-decoration-line']or 'none'):gmatch('%S+')do
  if line~='none'then
   local offset=line=='underline'and f.drawH*.9 or line=='overline'and 1 or f.drawH*.52
   local length=f.advance
   local function point(u,v)
    if f.vertical then return f.cx+f.drawH/2-v,f.cy-f.advance/2+u end
    return f.x+u,f.y+v
   end
   local function segment(a,b,va,vb,rounded)
    local x1,y1=point(a,va);local x2,y2=point(b,vb);stroke(parent,x1,y1,x2,y2,thick,color,alpha,z,rounded)
   end
   if pattern=='solid'or pattern=='double'then
    segment(0,length,offset,offset)
    if pattern=='double'then segment(0,length,offset+thick*2,offset+thick*2)end
   elseif pattern=='wavy'then
    local count=math.clamp(math.ceil(length/math.max(2,thick*2)),1,160);local prev=0
    for i=1,count do local at=length*i/count;local a=(i%2==0 and -1 or 1)*math.max(1,thick);segment(length*(i-1)/count,at,offset+prev,offset+a);prev=a end
   else
    local dash=pattern=='dotted'and thick or thick*3;local step=dash+thick*2
    local count=math.min(160,math.ceil(length/math.max(step,1)))
    for i=0,count-1 do local at=i*step;segment(at,math.min(length,at+dash),offset,offset,pattern=='dotted')end
   end
  end
 end
end
local taps={{0,0,0.28},{1,0,0.09},{-1,0,0.09},{0,1,0.09},{0,-1,0.09},{.707,.707,.09},{-.707,.707,.09},{.707,-.707,.09},{-.707,-.707,.09}}
function T.opacity(object,opacity,cache)
 local targets=cache.inlineTargets
 if not targets then
  targets={};local layer=O.child(object,'__InlineText')
  if layer then for _,child in ipairs(layer:GetDescendants())do
   local a=child:GetAttribute('CssTextAlpha');if a then targets[#targets+1]={object=child,alpha=a,text=true}end
   local b=child:GetAttribute('CssFillAlpha');if b then targets[#targets+1]={object=child,alpha=b,text=false}end
  end end
  cache.inlineTargets=targets
 end
 for _,item in ipairs(targets)do
  if item.text then O.properties(item.object,{TextTransparency=1-math.clamp(item.alpha*opacity,0,1)})
  else O.properties(item.object,{BackgroundTransparency=1-math.clamp(item.alpha*opacity,0,1)})end
 end
 if object:IsA('TextLabel')or object:IsA('TextButton')then O.properties(object,{TextTransparency=1})end
end
function T.apply(node,object,style,box,opacity,cache)
 local old=O.child(object,'__InlineText')
 if not box.inlineManaged then
  if old then O.release(old);O.remember(object,'__InlineText',nil)end
  O.attributes(object,{CssInlineManaged=false});cache.inlineTargets=nil;cache.inlineStamp=nil;return
 end
 O.attributes(object,{CssInlineManaged=true})
 if object:IsA('TextLabel')or object:IsA('TextButton')then O.properties(object,{TextTransparency=1,TextTruncate=Enum.TextTruncate.None})end
 local p=box.textPadding or box.p
 if cache.inlineStamp~=box.inlineStamp or cache.inlineStyle~=style or not old then
  local layer=make('Frame','__InlineText',nil,{BackgroundTransparency=1,Position=UDim2.fromOffset(-p[4],-p[1]),Size=UDim2.new(1,p[2]+p[4],1,p[1]+p[3]),ZIndex=object.ZIndex,ClipsDescendants=false})
  local count=0
  local ok,err=xpcall(function()
   for _,f in ipairs(box.inlineFragments or {})do
    local s=f.style;local z=object.ZIndex
    if not f.space then
     for index=#(s._textShadows or {}),1,-1 do
      local shadow=s._textShadows[index];local color,alpha=ink(shadow.color,s)
      if shadow.blur>0 then
       for _,tap in ipairs(taps)do label(layer,f,s,color,alpha*tap[3],shadow.x+tap[1]*shadow.blur*.5,shadow.y+tap[2]*shadow.blur*.5,z+4-index,'TextShadow');count+=1 end
      else label(layer,f,s,color,alpha,shadow.x,shadow.y,z+4-index,'TextShadow');count+=1 end
     end
     local color,alpha=ink(s.color,s);label(layer,f,s,color,alpha,0,0,z+10,'Glyph');count+=1
    end
    for _,deco in ipairs(f.decorations or {})do decoration(layer,f,deco,1,z+20)end
    assert(count<=10000,'Texto excedeu o orçamento de sombras/fragmentos.')
   end
  end,debug.traceback)
  if not ok then O.release(layer);error(err,0)end
  if old then O.release(old)end
  layer.Parent=object;O.remember(object,'__InlineText',layer)
  cache.inlineStamp=box.inlineStamp;cache.inlineStyle=style;cache.inlineTargets=nil
 end
 T.opacity(object,opacity,cache)
end
return T
