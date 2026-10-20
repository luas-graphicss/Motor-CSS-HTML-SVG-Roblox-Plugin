local Core=require(script.Parent.RuntimeManifest).optional('RenderCore')
local Paint=require(script.Parent.TransformPaint)
local Compose=Core.Compose or require(script.Parent.RenderCompose)
local R={VERSION=1,MAX_SIDE=320}
local floor=math.floor
local ceil=math.ceil
local clamp=math.clamp
local views=setmetatable({},{__mode='k'})
local installed=false
local sides={'top','right','bottom','left'}
local radiusKeys={'border-top-left-radius','border-top-right-radius','border-bottom-right-radius','border-bottom-left-radius'}
local named={black=Color3.new(0,0,0),white=Color3.new(1,1,1),red=Color3.fromRGB(255,0,0),green=Color3.fromRGB(0,128,0),blue=Color3.fromRGB(0,0,255),gray=Color3.fromRGB(128,128,128),grey=Color3.fromRGB(128,128,128),silver=Color3.fromRGB(192,192,192),yellow=Color3.fromRGB(255,255,0),orange=Color3.fromRGB(255,165,0),purple=Color3.fromRGB(128,0,128),navy=Color3.fromRGB(0,0,128),teal=Color3.fromRGB(0,128,128),olive=Color3.fromRGB(128,128,0),maroon=Color3.fromRGB(128,0,0),lime=Color3.fromRGB(0,255,0),aqua=Color3.fromRGB(0,255,255),cyan=Color3.fromRGB(0,255,255),fuchsia=Color3.fromRGB(255,0,255),magenta=Color3.fromRGB(255,0,255),pink=Color3.fromRGB(255,192,203),brown=Color3.fromRGB(165,42,42)}
local function trim(text)
 return (string.gsub(text,'^%s*(.-)%s*$','%1'))
end
local function number(text,fallback)
 local direct=tonumber(text)
 if direct then return direct end
 if type(text)~='string' then return fallback end
 local digits=string.match(text,'(-?%d+%.?%d*)')
 if digits then return tonumber(digits) or fallback end
 return fallback
end
local function px(value,fallback)
 if type(value)=='number' then return value end
 if type(value)~='string' then return fallback end
 local text=trim(value)
 if text=='' or text=='auto' or text=='none' or string.find(text,'%%') then return fallback end
 return number(text,fallback)
end
local function parseColor(value)
 if type(value)~='string' then return nil end
 local text=string.lower(trim(value))
 if text=='' or text=='none' or text=='transparent' or text=='inherit' or text=='initial' or text=='currentcolor' then return nil end
 local hex=string.match(text,'^#(%x+)$')
 if hex then
  local parts={}
  if #hex==3 or #hex==4 then
   for index=1,#hex do local digit=string.sub(hex,index,index);parts[index]=tonumber(digit..digit,16) end
  elseif #hex==6 or #hex==8 then
   for index=1,#hex,2 do parts[#parts+1]=tonumber(string.sub(hex,index,index+1),16) end
  else
   return nil
  end
  if parts[1]==nil or parts[2]==nil or parts[3]==nil then return nil end
  local alpha=parts[4] and parts[4]/255 or 1
  return Color3.fromRGB(parts[1],parts[2],parts[3]),alpha
 end
 local body=string.match(text,'^rgba?%((.+)%)$')
 if body then
  local tokens={}
  for token in string.gmatch(body,'[^,%s/]+') do tokens[#tokens+1]=token end
  if #tokens<3 then return nil end
  local function channel(token)
   if string.find(token,'%%') then return number(token,0)/100*255 end
   return number(token,0)
  end
  local alpha=1
  if tokens[4] then
   if string.find(tokens[4],'%%') then alpha=number(tokens[4],100)/100 else alpha=number(tokens[4],1) end
  end
  return Color3.fromRGB(clamp(channel(tokens[1]),0,255),clamp(channel(tokens[2]),0,255),clamp(channel(tokens[3]),0,255)),clamp(alpha,0,1)
 end
 local hit=named[text]
 if hit then return hit,1 end
 return nil
end
local function radiiOf(style)
 local list={}
 local any=false
 for index,key in ipairs(radiusKeys) do
  local value=math.max(0,px(style[key] or style['border-radius'],0))
  list[index]=value
  if value>0 then any=true end
 end
 if not any then return nil end
 return list
end
local function borderOf(style,side)
 local kind=style['border-'..side..'-style'] or style['border-style']
 if kind=='none' or kind=='hidden' then return 0 end
 local width=math.max(0,px(style['border-'..side..'-width'] or style['border-width'],0))
 if width<=0 then return 0 end
 local color,alpha=parseColor(style['border-'..side..'-color'] or style['border-color'] or style.color)
 if color==nil then return 0 end
 return width,color,alpha or 1
end
local function opsOf(style,box)
 local out={}
 local corners=radiiOf(style)
 local color,alpha=parseColor(style['background-color'] or style.background)
 if color and (alpha or 1)>0.002 then
  out[#out+1]={kind=corners and 'roundRect' or 'rect',x=0,y=0,w=box.w,h=box.h,radii=corners,color=color,alpha=alpha or 1}
 end
 local edges={}
 local uniform=true
 for index,side in ipairs(sides) do
  local width,edgeColor,edgeAlpha=borderOf(style,side)
  edges[index]={width=width,color=edgeColor,alpha=edgeAlpha}
  if index>1 and (width~=edges[1].width or edgeColor~=edges[1].color or edgeAlpha~=edges[1].alpha) then uniform=false end
 end
 if edges[1].width>0 and edges[1].color and uniform then
  out[#out+1]={kind='ring',x=0,y=0,w=box.w,h=box.h,radii=corners,width=edges[1].width,color=edges[1].color,alpha=edges[1].alpha}
 else
  local top,right,bottom,left=edges[1],edges[2],edges[3],edges[4]
  if top.width>0 and top.color then out[#out+1]={kind='rect',x=0,y=0,w=box.w,h=top.width,color=top.color,alpha=top.alpha} end
  if bottom.width>0 and bottom.color then out[#out+1]={kind='rect',x=0,y=box.h-bottom.width,w=box.w,h=bottom.width,color=bottom.color,alpha=bottom.alpha} end
  if left.width>0 and left.color then out[#out+1]={kind='rect',x=0,y=0,w=left.width,h=box.h,color=left.color,alpha=left.alpha} end
  if right.width>0 and right.color then out[#out+1]={kind='rect',x=box.w-right.width,y=0,w=right.width,h=box.h,color=right.color,alpha=right.alpha} end
 end
 return out,corners
end
local function drawable(child)
 if child:IsA('UIGradient') or child:IsA('UIStroke') then return true end
 if not child:IsA('GuiObject') then return false end
 if not child.Visible then return false end
 if child.BackgroundTransparency<1 then return true end
 if (child:IsA('TextLabel') or child:IsA('TextButton') or child:IsA('TextBox')) and child.Text~='' and child.TextTransparency<1 then return true end
 if (child:IsA('ImageLabel') or child:IsA('ImageButton')) and child.Image~='' and child.ImageTransparency<1 then return true end
 return false
end
local function eligible(object)
 if object:IsA('TextBox') then return false end
 if (object:IsA('TextLabel') or object:IsA('TextButton')) and object.Text~='' and object.TextTransparency<1 then return false end
 if (object:IsA('ImageLabel') or object:IsA('ImageButton')) and object.Image~='' and object.ImageTransparency<1 then return false end
 for _,child in ipairs(object:GetDescendants()) do
  if drawable(child) then return false end
 end
 return true
end
local function signature(plan,box,list,bx,by,bw,bh)
 local parts={string.format('%d:%d:%d:%d:%.2f:%.2f',bx,by,bw,bh,box.w,box.h)}
 for index=1,16 do parts[#parts+1]=string.format('%.4f',tonumber(plan.matrix[index]) or 0) end
 for _,op in ipairs(list) do
  parts[#parts+1]=string.format('%s:%.2f:%.2f:%.2f:%.2f:%.2f:%.3f:%s',tostring(op.kind),op.x,op.y,op.w or 0,op.h or 0,op.width or 0,op.alpha or 1,tostring(op.color))
 end
 return table.concat(parts,'|')
end
function R.release(object)
 local entry=views[object]
 if entry==nil then return false end
 views[object]=nil
 pcall(Core.release,entry.context)
 local parent=entry.parent
 if typeof(parent)=='Instance' then
  local root=parent:FindFirstChild(entry.name)
  if root then pcall(function() root:Destroy() end) end
 end
 return true
end
function R.render(object,style,plan,cache)
 if typeof(object)~='Instance' or not object:IsA('GuiObject') then return false end
 if plan==nil or plan.raster~=true or plan.matrix==nil or plan.bounds==nil or plan.identity==true then R.release(object) return false end
 if plan.visible==false or plan.hidden==true then R.release(object) return false end
 local parent=object.Parent
 if parent==nil or not (parent:IsA('GuiObject') or parent:IsA('LayerCollector')) then R.release(object) return false end
 local box=cache and cache.transformBox
 if box==nil or (tonumber(box.w) or 0)<=0 or (tonumber(box.h) or 0)<=0 then R.release(object) return false end
 if not eligible(object) then R.release(object) return false end
 local list=opsOf(style or {},box)
 if #list==0 then R.release(object) return false end
 local bounds=plan.bounds
 local left=tonumber(bounds.x) or 0
 local top=tonumber(bounds.y) or 0
 local bx=floor(left)-1
 local by=floor(top)-1
 local bw=ceil(left+(tonumber(bounds.w) or 0))-bx+1
 local bh=ceil(top+(tonumber(bounds.h) or 0))-by+1
 if bw<2 or bh<2 or bw>R.MAX_SIDE or bh>R.MAX_SIDE then R.release(object) return false end
 local entry=views[object]
 if entry and (entry.w~=bw or entry.h~=bh or entry.parent~=parent) then R.release(object) entry=nil end
 if entry==nil then
  local label=(string.gsub(tostring(object:GetAttribute('CssNodeKey') or object.Name),'[^%w]','_'))
  entry={context=Core.create(bw,bh,{label='Transform raster'}),w=bw,h=bh,parent=parent,key=label,name='__CssTransformRaster_'..label}
  views[object]=entry
 end
 local stamp=signature(plan,box,list,bx,by,bw,bh)
 if entry.stamp~=stamp then
  local node=Compose.node({key=entry.key,box={x=-bx,y=-by,w=box.w,h=box.h},ops=list,transform=plan.matrix,transformOrigin={x=0,y=0,z=0},transformBox='border-box',pointerEvents='auto',root=true})
  if Core.invalidateAll then Core.invalidateAll(entry.context,'transform') end
  Core.frame(entry.context,node,parent,{x=0,y=0,force=true,name=entry.name,zIndex=object.ZIndex})
 end
 local root=parent:FindFirstChild(entry.name)
 if root==nil or not root:IsA('GuiObject') then R.release(object) return false end
 local position=cache.transformPosition or object.Position
 root.Position=UDim2.new(position.X.Scale,position.X.Offset+bx,position.Y.Scale,position.Y.Offset+by)
 root.ZIndex=object.ZIndex
 root.Visible=true
 root:SetAttribute('CssOwned',true)
 root:SetAttribute('CssNoPool',true)
 root:SetAttribute('CssTransformRaster',true)
 root:SetAttribute('CssTransformRoute',plan.route or 'raster')
 entry.stamp=stamp
 cache.transformRasterView=root
 cache.transformRasterName=entry.name
 return true
end
function R.sweep(object,entry)
 if typeof(object)~='Instance' then return false end
 if entry~=nil and entry.transformRastered==true then return false end
 return R.release(object)
end
function R.active(object)
 return views[object]~=nil
end
function R.stats(object)
 local entry=views[object]
 if entry==nil then return nil end
 local ok,report=pcall(Core.stats,entry.context)
 if not ok then return nil end
 return report
end
function R.install(force)
 if installed and not force then return R end
 installed=true
 Paint.renderer(function(object,style,plan,cache)
  local ok,handled=pcall(R.render,object,style,plan,cache)
  if not ok then
   pcall(R.release,object)
   return false
  end
  return handled==true
 end)
 return R
end
function R.installed()
 return installed
end
return R
