local U=require(script.Parent.Util)
local TextService=game:GetService('TextService')
local S={VERSION=1}
local HOLDER='__selection'
local MAX_LINES=32
local function rows(text)
 local out={};local start=1
 while true do
  local at=string.find(text,'\n',start,true)
  if not at then out[#out+1]={text=string.sub(text,start),from=start};break end
  out[#out+1]={text=string.sub(text,start,at-1),from=start};start=at+1
 end
 return out
end
local function advance(object,text)
 if text==''then return 0 end
 local ok,bounds=pcall(function()return TextService:GetTextSize(text,object.TextSize,object.Font,Vector2.new(100000,100000))end)
 if ok and typeof(bounds)=='Vector2'and bounds.X>0 then return bounds.X end
 local full=object.Text
 if full==''then return 0 end
 return object.TextBounds.X*(#text/#full)
end
local function tint(value,fallback)
 if value==nil or value=='none'then return fallback,fallback~=nil and 1 or 0 end
 local ok,color,alpha=pcall(U.color,value)
 if not ok or typeof(color)~='Color3'then return fallback,fallback~=nil and 1 or 0 end
 return color,alpha==nil and 1 or alpha
end
function S.clear(object)
 local holder=object:FindFirstChild(HOLDER)
 if holder then holder:Destroy()end
 return false
end
function S.range(object)
 local cursor=object.CursorPosition;local anchor=object.SelectionStart
 if type(cursor)~='number'or type(anchor)~='number'then return nil end
 if cursor<1 or anchor<1 or cursor==anchor then return nil end
 return math.min(cursor,anchor),math.max(cursor,anchor)
end
function S.active(object)
 return object:FindFirstChild(HOLDER)~=nil
end
function S.apply(object,style)
 if object==nil or not object:IsA('TextBox')then return false end
 if style==nil then return S.clear(object)end
 local text=object.Text
 local from,to=S.range(object)
 if from==nil or text==''then return S.clear(object)end
 local holder=object:FindFirstChild(HOLDER)
 if holder==nil then
  holder=Instance.new('Frame')
  holder.Name=HOLDER;holder.BackgroundTransparency=1;holder.BorderSizePixel=0
  holder.Position=UDim2.fromOffset(0,0);holder.Size=UDim2.fromScale(1,1)
  holder.ClipsDescendants=true;holder.Active=false
  holder:SetAttribute('CssSelectionOverlay',true)
  holder.Parent=object
 end
 holder.ZIndex=object.ZIndex
 local background,backgroundAlpha=tint(style['background-color']or style.background,Color3.fromRGB(51,144,255))
 local foreground,foregroundAlpha=tint(style.color,nil)
 local size=object.AbsoluteSize
 local height=math.max(object.TextSize*(tonumber(object.LineHeight)or 1),1)
 local list=rows(text)
 local top=0
 if object.TextYAlignment==Enum.TextYAlignment.Center then top=(size.Y-#list*height)/2
 elseif object.TextYAlignment==Enum.TextYAlignment.Bottom then top=size.Y-#list*height end
 local used=0
 for index,row in ipairs(list)do
  local lineFrom=row.from;local lineTo=row.from+#row.text
  local start=math.max(from,lineFrom);local finish=math.min(to,lineTo)
  if finish>start and used<MAX_LINES then
   used+=1
   local selected=string.sub(text,start,finish-1)
   local x=0
   if object.TextXAlignment==Enum.TextXAlignment.Center then x=(size.X-advance(object,row.text))/2
   elseif object.TextXAlignment==Enum.TextXAlignment.Right then x=size.X-advance(object,row.text)end
   x+=advance(object,string.sub(text,lineFrom,start-1))
   local rect=holder:FindFirstChild('Line'..used)
   if rect==nil then
    rect=Instance.new('Frame');rect.Name='Line'..used;rect.BorderSizePixel=0;rect.Parent=holder
    local label=Instance.new('TextLabel')
    label.Name='Text';label.BackgroundTransparency=1;label.BorderSizePixel=0
    label.Position=UDim2.fromOffset(0,0);label.Size=UDim2.fromScale(1,1)
    label.TextXAlignment=Enum.TextXAlignment.Left;label.TextYAlignment=Enum.TextYAlignment.Center
    label.Parent=rect
   end
   rect.Visible=true;rect.ZIndex=object.ZIndex
   rect.BackgroundColor3=background
   rect.BackgroundTransparency=1-math.clamp(backgroundAlpha,0,1)
   rect.Position=UDim2.fromOffset(math.floor(x),math.floor(top+(index-1)*height))
   rect.Size=UDim2.fromOffset(math.max(math.ceil(advance(object,selected)),1),math.ceil(height))
   local label=rect:FindFirstChild('Text')
   if label then
    if foreground~=nil then
     label.Visible=true;label.Text=selected;label.TextColor3=foreground
     label.TextTransparency=1-math.clamp(foregroundAlpha,0,1)
     label.TextSize=object.TextSize;label.ZIndex=object.ZIndex
     pcall(function()label.FontFace=object.FontFace end)
    else label.Visible=false;label.Text=''end
   end
  end
 end
 for _,child in ipairs(holder:GetChildren())do
  local n=tonumber(string.match(child.Name,'^Line(%d+)$'))
  if n~=nil and n>used then child.Visible=false end
 end
 if used==0 then return S.clear(object)end
 return true
end
return S
