local P=require(script.Parent.VisualEffectsPixels)
local Cost=require(script.Parent.CostModel)
local C={VERSION=1,MAX_OBJECTS=512}
C.ranks={document=1,interface=2,screen=3,world=4}
local function layerRoot(object)
 local current=object
 while current do
  if current:IsA('LayerCollector')then return current end
  current=current.Parent
 end
 return nil
end
local function radius(o,size)
 local corner=o:FindFirstChildWhichIsA('UICorner')
 if not corner then return 0 end
 local extent=math.min(size.X,size.Y)
 return math.clamp(corner.CornerRadius.Scale*extent+corner.CornerRadius.Offset,0,extent/2)
end
local function inside(item,x,y)
 local lx,ly=x-(item.x+item.w/2),y-(item.y+item.h/2)
 if item.angle~=0 then
  local cos,sin=math.cos(-item.angle),math.sin(-item.angle)
  lx,ly=lx*cos-ly*sin,lx*sin+ly*cos
 end
 lx+=item.w/2;ly+=item.h/2
 if lx<0 or ly<0 or lx>item.w or ly>item.h then return false end
 local r=item.r
 if r<=0 then return true end
 local cx=math.clamp(lx,r,item.w-r);local cy=math.clamp(ly,r,item.h-r)
 return(lx-cx)^2+(ly-cy)^2<=r*r
end
local function push(list,o,rank,z,order,note)
 local size=o.AbsoluteSize
 if size.X<=0 or size.Y<=0 then return end
 if(o:IsA('TextLabel')or o:IsA('TextButton')or o:IsA('TextBox'))and o.Text~=''and o.TextTransparency<1 then note.text=true end
 if(o:IsA('ImageLabel')or o:IsA('ImageButton'))and o.Image~=''and o.ImageTransparency<1 then note.image=true end
 if o:FindFirstChildWhichIsA('UIGradient')then note.gradient=true end
 local alpha=1-math.clamp(o.BackgroundTransparency,0,1)
 if alpha<=1e-4 then return end
 local position=o.AbsolutePosition
 list[#list+1]={x=position.X,y=position.Y,w=size.X,h=size.Y,r=radius(o,size),angle=math.rad(o.AbsoluteRotation),color=o.BackgroundColor3,alpha=alpha,rank=rank,z=z,order=order}
end
local function collect(list,gui,stop,rank,note)
 local order=0
 local cut=nil
 local function walk(parent)
  for _,child in ipairs(parent:GetChildren())do
   if child:IsA('GuiObject')then
    order+=1
    if child==stop then cut={z=child.ZIndex,order=order}
    elseif child:GetAttribute('CssEffectAux')then
    elseif not child.Visible then
    else
     push(list,child,rank,child.ZIndex,order,note)
     walk(child)
    end
   elseif child:IsA('Folder')then walk(child)end
  end
 end
 walk(gui)
 return cut
end
function C.rank(scope)return C.ranks[scope or 'document']or 1 end
function C.world(color)
 if color then return color end
 local lighting=game:GetService('Lighting')
 return lighting.OutdoorAmbient:Lerp(lighting.Ambient,.5)
end
function C.plan(object,scope,color)
 local note={}
 local items={}
 local base=nil
 local rank=C.rank(scope)
 local gui=object and layerRoot(object)
 if rank>=2 then
  if gui then
   local cut=collect(items,gui,object,2,note)
   if cut then
    local kept={}
    for _,item in ipairs(items)do
     if item.z<cut.z or(item.z==cut.z and item.order<cut.order)then kept[#kept+1]=item end
    end
    items=kept
   end
  else note.detached=true end
 end
 if rank>=3 and gui and gui.Parent then
  local order=gui:IsA('ScreenGui')and gui.DisplayOrder or 0
  for _,sibling in ipairs(gui.Parent:GetChildren())do
   if sibling~=gui and sibling:IsA('LayerCollector')and sibling.Enabled then
    local siblingOrder=sibling:IsA('ScreenGui')and sibling.DisplayOrder or 0
    if siblingOrder<=order then collect(items,sibling,nil,3,note)end
   end
  end
 end
 if rank>=4 then base=C.world(color)end
 table.sort(items,function(a,b)
  local ba,bb=a.rank==3 and 0 or 1,b.rank==3 and 0 or 1
  if ba~=bb then return ba<bb end
  if a.z~=b.z then return a.z<b.z end
  return a.order<b.order
 end)
 if #items>C.MAX_OBJECTS then
  local kept={}
  for index=#items-C.MAX_OBJECTS+1,#items do kept[#kept+1]=items[index]end
  items=kept;note.truncated=true
 end
 Cost.cap('instances',#items,'Captura de backdrop nativo')
 return {items=items,base=base,note=note,scope=scope or 'document'}
end
function C.sampler(plan,origin,state)
 local items=plan.items
 return function(gx,gy)
  local rank=C.rank(state and state.scope)
  if rank<2 then return Color3.new(),0 end
  local x,y=origin.X+gx,origin.Y+gy
  local color,alpha=Color3.new(),0
  if rank>=4 and plan.base then color,alpha=plan.base,1 end
  for _,item in ipairs(items)do
   if item.rank<=rank and inside(item,x,y)then color,alpha=P.over(color,alpha,item.color,item.alpha)end
  end
  return color,alpha
 end
end
function C.describe(plan,scope)
 local parts={string.format('escopo %s com %d fundos nativos amostrados',scope or plan.scope,#plan.items)}
 if plan.base then parts[#parts+1]='cor base aproximada do mundo 3D, sem leitura do render 3D'end
 if plan.note.image then parts[#parts+1]='pixels de imagens nativas não são lidos'end
 if plan.note.text then parts[#parts+1]='glifos nativos fora desta árvore não são lidos'end
 if plan.note.gradient then parts[#parts+1]='UIGradient nativo não é amostrado'end
 if plan.note.truncated then parts[#parts+1]='captura limitada a '..C.MAX_OBJECTS..' objetos'end
 if plan.note.detached then parts[#parts+1]='árvore sem LayerCollector: nada externo a capturar'end
 return table.concat(parts,'; ')
end
return C
