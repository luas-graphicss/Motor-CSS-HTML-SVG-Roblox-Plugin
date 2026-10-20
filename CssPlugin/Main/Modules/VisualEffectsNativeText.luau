local T={VERSION=1}
local function product(a,b)
 return {a[1]*b[1]+a[3]*b[2],a[2]*b[1]+a[4]*b[2],a[1]*b[3]+a[3]*b[4],a[2]*b[3]+a[4]*b[4],a[1]*b[5]+a[3]*b[6]+a[5],a[2]*b[5]+a[4]*b[6]+a[6]}
end
local function padding(o,w,h)
 local p=o:FindFirstChildWhichIsA('UIPadding');if not p then return {0,0,0,0}end
 local function x(v)return v.Scale*w+v.Offset end;local function y(v)return v.Scale*h+v.Offset end
 return {y(p.PaddingTop),x(p.PaddingRight),y(p.PaddingBottom),x(p.PaddingLeft)}
end
function T.targets(entry)
 local result={};local root=entry.object;if not root or not root:IsA('GuiObject')then return result end
 local box=entry.box or {w=math.max(0,root.Size.X.Offset),h=math.max(0,root.Size.Y.Offset)}
 local matrix=entry.m or {1,0,0,1,0,0}
 local function walk(o,m,w,h,visible,isRoot)
  if not isRoot and(o:GetAttribute('CssNodeKey')or o:GetAttribute('CssEffectAux'))then return end
  if o:IsA('GuiObject')then visible=visible and o.Visible end
  if not visible then return end
  local isText=o:IsA('TextLabel')or o:IsA('TextButton')or o:IsA('TextBox')
  local isFill=o:IsA('Frame')and o:GetAttribute('CssInlinePart')and o:GetAttribute('CssFillAlpha')~=nil
  if (isText or isFill)and(isRoot or o:GetAttribute('CssOwned'))then
   if isRoot then result[#result+1]=entry else
    result[#result+1]={node=entry.node,object=o,box={w=w,h=h,p=padding(o,w,h),hidden=box.hidden},m=m,parent=entry,isText=isText,isFill=isFill}
   end
  end
  local pad=o:IsA('GuiObject')and padding(o,w,h)or {0,0,0,0}
  local cw,ch=math.max(0,w-pad[2]-pad[4]),math.max(0,h-pad[1]-pad[3])
  for _,child in ipairs(o:GetChildren())do
   if child:GetAttribute('CssEffectAux')or child:GetAttribute('CssNodeKey')then continue end
   if child:IsA('GuiObject')then
    local ww=math.max(0,child.Size.X.Scale*cw+child.Size.X.Offset);local hh=math.max(0,child.Size.Y.Scale*ch+child.Size.Y.Offset)
    local x=pad[4]+child.Position.X.Scale*cw+child.Position.X.Offset-child.AnchorPoint.X*ww
    local y=pad[1]+child.Position.Y.Scale*ch+child.Position.Y.Offset-child.AnchorPoint.Y*hh
    if o:IsA('ScrollingFrame')then x-=o.CanvasPosition.X;y-=o.CanvasPosition.Y end
    local scale=child:FindFirstChildWhichIsA('UIScale');scale=scale and scale.Scale or 1
    local radians=math.rad(child.Rotation);local a,b=math.cos(radians)*scale,math.sin(radians)*scale
    local localMatrix={a,b,-b,a,x+ww/2-a*ww/2+b*hh/2,y+hh/2-b*ww/2-a*hh/2}
    walk(child,product(m,localMatrix),ww,hh,visible,false)
   elseif child:IsA('Folder')then walk(child,m,w,h,visible,false)end
  end
 end
 walk(root,matrix,box.w,box.h,true,true);return result
end
return T
