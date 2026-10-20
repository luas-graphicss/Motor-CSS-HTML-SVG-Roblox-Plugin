local Compiler=require(script.Parent.Compiler)
local Runtime=require(script.Parent.Runtime)
local CssColor=require(script.Parent.CssColor)
local Transform=require(script.Parent.Transform)
local Http=game:GetService('HttpService')
local H={VERSION=1}
local COLORISH={color=true,['background-color']=true,['border-top-color']=true,['border-right-color']=true,['border-bottom-color']=true,['border-left-color']=true,['outline-color']=true,fill=true,stroke=true,['text-decoration-color']=true,['caret-color']=true,['accent-color']=true}
local function round(n)return math.floor((n or 0)*100+0.5)/100 end
local function hex(c)return string.format('#%02x%02x%02x',math.floor(c.R*255+0.5),math.floor(c.G*255+0.5),math.floor(c.B*255+0.5))end
function H.normalizeColor(value)
 if value==nil then return nil end
 if value=='transparent'then return 'rgba(0, 0, 0, 0)'end
 local ok,c,a=pcall(CssColor.native,value)
 if not ok or typeof(c)~='Color3'then return tostring(value)end
 local r,g,b=math.floor(c.R*255+0.5),math.floor(c.G*255+0.5),math.floor(c.B*255+0.5)
 if a>=0.999 then return string.format('rgb(%d, %d, %d)',r,g,b)end
 return string.format('rgba(%d, %d, %d, %s)',r,g,b,string.format('%.3g',a))
end
local function describe(o)
 local d={class=o.ClassName,name=o.Name}
 if o:IsA('GuiObject')then
  d.pos={round(o.Position.X.Offset),round(o.Position.Y.Offset)};d.size={round(o.Size.X.Offset),round(o.Size.Y.Offset)}
  d.bg=hex(o.BackgroundColor3);d.bgt=round(o.BackgroundTransparency);d.visible=o.Visible;d.z=o.ZIndex;d.clips=o.ClipsDescendants;d.rot=round(o.Rotation)
  local corner=o:FindFirstChildWhichIsA('UICorner');if corner then d.corner={corner.CornerRadius.Scale,corner.CornerRadius.Offset}end
  local stroke=o:FindFirstChildWhichIsA('UIStroke');if stroke then d.stroke={hex(stroke.Color),round(stroke.Thickness),round(stroke.Transparency)}end
  local grad=o:FindFirstChildWhichIsA('UIGradient');if grad then local k={};for _,kp in ipairs(grad.Color.Keypoints)do k[#k+1]={round(kp.Time),hex(kp.Value)}end;d.gradient={rotation=round(grad.Rotation),keypoints=k}end
  local scale=o:FindFirstChildWhichIsA('UIScale');if scale then d.scale=round(scale.Scale)end
 end
 if o:IsA('TextLabel')or o:IsA('TextButton')or o:IsA('TextBox')then
  d.text=o.Text;d.textColor=hex(o.TextColor3);d.textSize=round(o.TextSize);d.font=tostring(o.FontFace.Family):match('[^/]+$');d.weight=o.FontFace.Weight.Name;d.style=o.FontFace.Style.Name;d.xa=o.TextXAlignment.Name;d.ya=o.TextYAlignment.Name;d.wrapped=o.TextWrapped;d.rich=o.RichText;d.textTransparency=round(o.TextTransparency);d.truncate=o.TextTruncate.Name
 end
 if o:IsA('ImageLabel')or o:IsA('ImageButton')then d.image=o.Image;d.imageColor=hex(o.ImageColor3);d.imageTransparency=round(o.ImageTransparency);d.scaleType=o.ScaleType.Name end
 if o:IsA('ScrollingFrame')then d.canvas={round(o.CanvasSize.X.Offset),round(o.CanvasSize.Y.Offset)};d.scrollbar=o.ScrollBarThickness end
 return d
end
function H.measure(markup,options)
 options=options or {}
 local width,height=options.width or 800,options.height or 600
 local result={ok=true,geometry={},computed={},objects={},diagnostics={}}
 local built
 local ok,err=pcall(function()
  built=Compiler.build(markup,options.css or '',options.name or 'E2E_Case',{width=width,height=height,recover=options.recover==true,yield=true,profile=options.profile})
 end)
 if not ok then result.ok=false;result.error=tostring(err);return result end
 local controller
 ok,err=pcall(function()
  controller=Runtime.attach(built.gui,{manual=true,width=width,height=height})
  controller:refresh(width,height)
  for id,key in pairs(controller.ids)do
   local box=controller.boxes[key]
   if box then
    local ax,ay=0,0
    local cur=key
    local guard=0
    while cur and guard<200 do
     local b=controller.boxes[cur]
     if b then ax+=b.x or 0;ay+=b.y or 0 end
     local parentNode=controller.parents[cur]
     cur=type(parentNode)=='table'and parentNode.key or parentNode
     guard+=1
    end
    local layoutX,layoutY=ax,ay
    local o=controller.objects[key]
    if o and o:IsA('GuiObject')then ax,ay=o.AbsolutePosition.X,o.AbsolutePosition.Y end
    local g={x=round(ax),y=round(ay),w=round(box.w),h=round(box.h),lx=round(box.x),ly=round(box.y),lines=box.lineCount,hidden=box.hidden or nil}
    local matrix=controller:transformMatrix(key)
    if matrix then
     local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
     local okAll=true
     for _,corner in ipairs({{0,0},{box.w,0},{0,box.h},{box.w,box.h}})do
      local px,py=Transform.point(matrix,corner[1],corner[2],0)
      if not px then okAll=false break end
      minX=math.min(minX,px);minY=math.min(minY,py);maxX=math.max(maxX,px);maxY=math.max(maxY,py)
     end
     if okAll then g.tbox={x=round(layoutX+minX),y=round(layoutY+minY),w=round(maxX-minX),h=round(maxY-minY)}end
     local route=controller:transformRoute(key)
     if route then g.route=route.route end
    end
    result.geometry[id]=g
   end
   local style=controller.styles[key]
   if style and options.props then
    local values={}
    for _,p in ipairs(options.props)do
     local v=style[p]
     if v==nil and p=='background-color'then v=style.background end
     if p=='line-height'then v=(v=='normal'or v==nil)and 'normal'or tostring(style._lineHeight)..'px'end
     if p=='font-size'and style._fontPx then v=tostring(style._fontPx)..'px'end
     if COLORISH[p]then v=H.normalizeColor(v)end
     values[p]=v
    end
    result.computed[id]=values
   end
   local o=controller.objects[key]
   if o then
    local d=describe(o)
    local kids={}
    for _,c in ipairs(o:GetChildren())do if c:IsA('GuiObject')and not c:GetAttribute('CssNodeKey')then kids[#kids+1]=describe(c)end end
    if #kids>0 then d.children=kids end
    result.objects[id]=d
   end
  end
  result.nodes=#(controller.sequence or {})
 end)
 if not ok then result.ok=false;result.error=tostring(err)end
 if built and built.stats then
  result.diagnostics=built.stats.diagnostics or {}
  result.stats={elements=built.stats.elements,instances=built.stats.instances,seconds=round(built.stats.seconds),icons=built.stats.icons,svgPrimitives=built.stats.svgPrimitives}
 end
 if controller then pcall(function()controller:destroy()end)end
 if built and built.gui then built.gui:Destroy()end
 return result
end
function H.json(markup,options)
 return Http:JSONEncode(H.measure(markup,options))
end
return H
