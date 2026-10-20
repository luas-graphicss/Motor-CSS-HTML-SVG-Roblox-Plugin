local P={VERSION=1}
local allowed={Frame=true,TextLabel=true,TextButton=true,TextBox=true,ImageLabel=true,ImageButton=true,ScrollingFrame=true,UICorner=true,UIStroke=true,UIShadow=true,UIGradient=true,UIScale=true,UIPadding=true,UIAspectRatioConstraint=true,UISizeConstraint=true,UITextSizeConstraint=true}
local gui={'AnchorPoint','Position','Size','AutomaticSize','SizeConstraint','Rotation','BackgroundColor3','BackgroundTransparency','BorderColor3','BorderMode','BorderSizePixel','ClipsDescendants','Visible','ZIndex','LayoutOrder','Active','Interactable','Selectable','SelectionOrder','AutoLocalize','SelectionImageObject','NextSelectionUp','NextSelectionDown','NextSelectionLeft','NextSelectionRight'}
local text={'Text','FontFace','TextSize','TextColor3','TextTransparency','TextStrokeColor3','TextStrokeTransparency','TextWrapped','TextScaled','TextTruncate','TextXAlignment','TextYAlignment','RichText','LineHeight','MaxVisibleGraphemes'}
local image={'Image','ImageColor3','ImageTransparency','ImageRectOffset','ImageRectSize','ScaleType','SliceCenter','SliceScale','TileSize','ResampleMode'}
local perClass={
 UICorner={'CornerRadius','TopLeftRadius','TopRightRadius','BottomLeftRadius','BottomRightRadius'},
 UIStroke={'ApplyStrokeMode','Color','Thickness','Transparency','LineJoinMode','Enabled','StrokeSizingMode','BorderStrokePosition','ZIndex'},
 UIShadow={'Color','Transparency','Offset','BlurRadius','Spread','ZIndex'},
 UIGradient={'Color','Transparency','Rotation','Offset','Enabled'},UIScale={'Scale'},
 UIPadding={'PaddingTop','PaddingRight','PaddingBottom','PaddingLeft'},
 UIAspectRatioConstraint={'AspectRatio','AspectType','DominantAxis'},UISizeConstraint={'MinSize','MaxSize'},UITextSizeConstraint={'MinTextSize','MaxTextSize'},
 ScrollingFrame={'CanvasSize','CanvasPosition','AutomaticCanvasSize','ScrollBarThickness','ScrollBarImageColor3','ScrollBarImageTransparency','ScrollingDirection','ScrollingEnabled','VerticalScrollBarInset','HorizontalScrollBarInset','ElasticBehavior','VerticalScrollBarPosition','TopImage','MidImage','BottomImage'},
 TextBox={'ClearTextOnFocus','MultiLine','PlaceholderText','PlaceholderColor3','TextEditable','CursorPosition','SelectionStart','ShowNativeInput'},
 TextButton={'AutoButtonColor','Modal','Selected'},ImageButton={'AutoButtonColor','Modal','Selected','HoverImage','PressedImage'}
}
local defaults={}
local function getDefaults(class)
 local cached=defaults[class];if cached then return cached end
 local probe=Instance.new(class);local names={'Name','Archivable'}
 if probe:IsA('GuiObject')then for _,key in ipairs(gui)do names[#names+1]=key end end
 if probe:IsA('TextLabel')or probe:IsA('TextButton')or probe:IsA('TextBox')then for _,key in ipairs(text)do names[#names+1]=key end end
 if probe:IsA('ImageLabel')or probe:IsA('ImageButton')then for _,key in ipairs(image)do names[#names+1]=key end end
 for _,key in ipairs(perClass[class]or {})do names[#names+1]=key end
 local values={};for _,key in ipairs(names)do
  local ok,value=pcall(function()return probe[key]end)
  if ok then
   local writable=pcall(function()probe[key]=value end)
   if writable then values[#values+1]={key=key,value=value}end
  end
 end
 probe:Destroy();defaults[class]=values;return values
end
local function apply(object,template)
 for _,entry in ipairs(getDefaults(object.ClassName))do
  local value=entry.value;if template then value=template[entry.key]end
  if object[entry.key]~=value then object[entry.key]=value end
 end
 for key in pairs(object:GetAttributes())do object:SetAttribute(key,nil)end
 for _,tag in ipairs(object:GetTags())do object:RemoveTag(tag)end
 if template then
  for key,value in pairs(template:GetAttributes())do object:SetAttribute(key,value)end
  for _,tag in ipairs(template:GetTags())do object:AddTag(tag)end
 end
end
function P.new(options)
 options=options or {};local maxRetained=math.clamp(math.floor(options.maxRetained or 4096),0,8192)
 local maxPerClass=math.clamp(math.floor(options.maxPerClass or 2048),0,4096)
 local bins={};local idle={};local cleanup=setmetatable({},{__mode='k'});local alive=true
 local metrics={created=0,reused=0,released=0,discarded=0,retained=0,highWater=0}
 local self={}
 local function discard(object)
  metrics.discarded+=1;cleanup[object]=nil;pcall(function()object:Destroy()end)
 end
 local function runCleanup(object)
  local fn=cleanup[object];cleanup[object]=nil
  if fn then local ok=pcall(fn,object);if not ok then return false end end
  return true
 end
 function self.tryAcquire(class)
  assert(alive,'Pool encerrado.');assert(type(class)=='string','Classe de pool inválida.')
  local bin=bins[class];local object=bin and table.remove(bin)
  if object then idle[object]=nil;metrics.retained-=1;metrics.reused+=1 end
  return object
 end
 function self.acquire(class)
  local object=self.tryAcquire(class)
  if not object then object=Instance.new(class);metrics.created+=1 end
  return object
 end
 function self.registerCleanup(object,fn)assert(type(fn)=='function','Cleanup inválido.');cleanup[object]=fn end
 function self.release(object)
  if not object or idle[object]then return false end
  if not alive or not allowed[object.ClassName]or object:GetAttribute('CssNoPool')or #object:GetChildren()>0 or not runCleanup(object)then discard(object);return false end
  local bin=bins[object.ClassName];if not bin then bin={};bins[object.ClassName]=bin end
  if metrics.retained>=maxRetained or #bin>=maxPerClass then discard(object);return false end
  local ok=pcall(function()object.Parent=nil;apply(object,nil)end)
  if not ok then discard(object);return false end
  bin[#bin+1]=object;idle[object]=true;metrics.retained+=1;metrics.released+=1;metrics.highWater=math.max(metrics.highWater,metrics.retained)
  return true
 end
 function self.releaseTree(root)
  if not root or idle[root]then return false end
  local descendants=root:GetDescendants()
  if root:GetAttribute('CssNoPool')or #descendants>8192 then discard(root);return false end
  for _,o in ipairs(descendants)do
   if not allowed[o.ClassName]or o:GetAttribute('CssOwned')~=true or o:GetAttribute('CssNoPool')then
    runCleanup(root);discard(root);return false
   end
  end
  root.Parent=nil
  for i=#descendants,1,-1 do self.release(descendants[i])end
  return self.release(root)
 end
 function self.cloneTree(template)
  assert(alive,'Pool encerrado.')
  local work=0
  local function clone(source)
   work+=1;assert(work<=8192,'Template excede 8192 instâncias.')
   if not allowed[source.ClassName]or source:GetAttribute('CssNoPool')then return source:Clone()end
   local object=self.acquire(source.ClassName)
   local ok,err=xpcall(function()
    apply(object,source)
    for _,child in ipairs(source:GetChildren())do clone(child).Parent=object end
   end,debug.traceback)
   if not ok then self.releaseTree(object);error(err,0)end
   return object
  end
  return clone(template)
 end
 function self.trim(limit)
  limit=math.max(0,math.floor(limit or 0))
  for _,bin in pairs(bins)do
   while metrics.retained>limit and #bin>0 do local object=table.remove(bin);idle[object]=nil;metrics.retained-=1;discard(object)end
  end
 end
 function self.stats()return table.clone(metrics)end
 function self.destroy()
  if not alive then return end;self.trim(0);table.clear(bins);table.clear(idle);table.clear(cleanup);alive=false
 end
 return self
end
local shared=P.new()
function P.acquire(class)return shared.acquire(class)end
function P.tryAcquire(class)return shared.tryAcquire(class)end
function P.release(object)return shared.release(object)end
function P.releaseTree(object)return shared.releaseTree(object)end
function P.cloneTree(template)return shared.cloneTree(template)end
function P.registerCleanup(object,fn)return shared.registerCleanup(object,fn)end
function P.trim(limit)return shared.trim(limit)end
function P.stats()return shared.stats()end
function P.clear()shared.trim(0)end
return P
