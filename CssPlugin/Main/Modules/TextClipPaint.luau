local U=require(script.Parent.Util)
local V=require(script.Parent.VisualStyle)
local Advanced=require(script.Parent.AdvancedPaint)
local T={VERSION=1,MAX_KEYS=20,NAME='__BackgroundClip'}
local function isText(object)
 return object:IsA('TextLabel')or object:IsA('TextButton')or object:IsA('TextBox')
end
function T.active(style)
 local value=style and style['background-clip']
 return type(value)=='string'and value:find('text',1,true)~=nil
end
local function collect(object,out)
 if isText(object)then out[#out+1]=object end
 local inline=object:FindFirstChild('__InlineText')
 if inline then for _,child in ipairs(inline:GetDescendants())do if isText(child)then out[#out+1]=child end end end
 return out
end
local function offsetOf(label,object)
 local x,y=0,0
 local current=label
 while current and current~=object do
  x+=current.Position.X.Offset;y+=current.Position.Y.Offset
  current=current.Parent
 end
 return x,y
end
local function neutral(style)
 local copy=table.clone(style)
 local parts={}
 for _,part in ipairs(V.segments(tostring(style['background-clip']or'border-box'),','))do
  parts[#parts+1]=part=='text'and'border-box'or part
 end
 copy['background-clip']=table.concat(parts,', ')
 return copy
end
local function over(tc,ta,bc,ba)
 local a=ta+ba*(1-ta)
 if a<=1e-6 then return Color3.new(),0 end
 local w=ba*(1-ta)
 return Color3.new(math.clamp((tc.R*ta+bc.R*w)/a,0,1),math.clamp((tc.G*ta+bc.G*w)/a,0,1),math.clamp((tc.B*ta+bc.B*w)/a,0,1)),math.clamp(a,0,1)
end
function T.clear(object)
 if not object then return false end
 local removed=false
 for _,label in ipairs(collect(object,{}))do
  local existing=label:FindFirstChild(T.NAME)
  if existing then existing:Destroy();removed=true end
  label:SetAttribute('CssBackgroundClipText',nil)
  label:SetAttribute('CssTextClipAlpha',nil)
 end
 return removed
end
function T.samples(plan,x0,y,width,count)
 local colors=table.create(count)
 local alphas=table.create(count)
 for i=1,count do
  local t=count>1 and(i-1)/(count-1)or 0
  local px=x0+math.clamp(t,.001,.999)*width
  local color,alpha=Advanced.sampleBackground(plan,px,y)
  colors[i]=color or Color3.new()
  alphas[i]=alpha or 0
 end
 return colors,alphas
end
function T.apply(object,style,box,opacity,vw,vh)
 if not object or not T.active(style)then return T.clear(object)end
 local list=collect(object,{})
 if #list==0 then return false end
 local plan=Advanced.plan(neutral(style),box,vw,vh)
 local textColor,textAlpha=U.color(style.color or'#ffffff')
 opacity=opacity or 1
 for _,label in ipairs(list)do
  local x0,y0=offsetOf(label,object)
  local width=label.Size.X.Offset
  local height=label.Size.Y.Offset
  if width<=0 then width=box.w end
  if height<=0 then height=box.h end
  local count=math.clamp(math.floor(width/8)+2,2,T.MAX_KEYS)
  local colors,alphas=T.samples(plan,x0,y0+height/2,width,count)
  local uniform=true
  for i=2,count do
   if alphas[i]~=alphas[1]or colors[i]~=colors[1]then uniform=false;break end
  end
  local existing=label:FindFirstChild(T.NAME)
  if existing and not existing:IsA('UIGradient')then existing:Destroy();existing=nil end
  label:SetAttribute('CssBackgroundClipText',true)
  if uniform then
   if existing then existing:Destroy()end
   local color,alpha=over(textColor,textAlpha,colors[1],alphas[1])
   label.TextColor3=color
   label.TextTransparency=math.clamp(1-alpha*opacity,0,1)
   label:SetAttribute('CssTextClipAlpha',alpha)
  else
   local gradient=existing
   if not gradient then
    gradient=Instance.new('UIGradient')
    gradient.Name=T.NAME
    gradient:SetAttribute('CssOwned',true)
    gradient.Parent=label
   end
   local colorStops=table.create(count)
   local alphaStops=table.create(count)
   local raw=table.create(count)
   for i=1,count do
    local t=count>1 and(i-1)/(count-1)or 0
    local color,alpha=over(textColor,textAlpha,colors[i],alphas[i])
    colorStops[i]=ColorSequenceKeypoint.new(t,color)
    alphaStops[i]=NumberSequenceKeypoint.new(t,math.clamp(1-alpha,0,1))
    raw[i]=string.format('%.4f,%.4f',t,alpha)
   end
   gradient.Color=ColorSequence.new(colorStops)
   gradient.Transparency=NumberSequence.new(alphaStops)
   gradient.Rotation=0
   gradient:SetAttribute('CssAlphaStops',table.concat(raw,';'))
   label.TextColor3=Color3.new(1,1,1)
   label.TextTransparency=math.clamp(1-opacity,0,1)
   label:SetAttribute('CssTextClipAlpha',1)
  end
 end
 return true
end
return T
