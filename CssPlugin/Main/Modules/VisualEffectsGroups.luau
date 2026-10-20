local E=require(script.Parent.VisualEffectsStyle)
local G={VERSION=1}
local geometry={'Position','Size','AnchorPoint','Rotation','ZIndex','Visible'}
local function get(object)
 local canvas=object.Parent
 if canvas and canvas:IsA('CanvasGroup')and canvas:GetAttribute('CssEffectCanvas')and canvas:GetAttribute('CssEffectOwner')==object:GetAttribute('CssNodeKey')then
  local host=canvas.Parent;if host and host:GetAttribute('CssEffectHost')then return host,canvas end
 end
end
G.get=get
function G.root(object)local host=get(object);return host or object end
function G.begin(object)
 local host,canvas=get(object);if not host then return end
 for _,name in ipairs(geometry)do object[name]=host[name]end
 local scale=host:FindFirstChild('__CssScale');if scale then scale.Parent=object end
 host:SetAttribute('CssEffectPrepared',true)
end
local function owned(class,name)
 local o=Instance.new(class);o.Name=name;o:SetAttribute('CssOwned',true);o:SetAttribute('CssNoPool',true)
 if o:IsA('GuiObject')then o.BackgroundTransparency=1;o.BorderSizePixel=0;o.Active=false;o.Selectable=false end;return o
end
function G.finish(object,style,box,entry,bounds)
 local opacity=math.clamp(tonumber(style.opacity)or 1,0,1)
 local needed=opacity<1 or E.active(style)or(entry and entry.motionOpacityPotential==true)
 local host,canvas=get(object)
 if not needed then
  if host then
   if not host:GetAttribute('CssEffectPrepared')then G.begin(object)end
   local parent=host.Parent;object.Parent=parent;host:Destroy()
  end
  if entry then entry.effectHost=nil end;return object
 end
 if not host then
  local parent=object.Parent;host=owned('Frame','__CssEffectHost');canvas=owned('CanvasGroup','__CssEffectCanvas')
  host:SetAttribute('CssEffectHost',true);host:SetAttribute('CssEffectOwner',object:GetAttribute('CssNodeKey'))
  canvas:SetAttribute('CssEffectCanvas',true);canvas:SetAttribute('CssEffectOwner',object:GetAttribute('CssNodeKey'))
  canvas.Parent=host;host.Parent=parent;object.Parent=canvas;host:SetAttribute('CssEffectPrepared',true)
 end
 if host:GetAttribute('CssEffectPrepared')then for _,name in ipairs(geometry)do host[name]=object[name]end end
 local minX,minY,maxX,maxY=0,0,box.w,box.h
 if bounds then minX=math.min(minX,bounds.x or 0);minY=math.min(minY,bounds.y or 0);maxX=math.max(maxX,bounds.right or box.w);maxY=math.max(maxY,bounds.bottom or box.h)end
 canvas.Position=UDim2.fromOffset(minX,minY);canvas.Size=UDim2.fromOffset(math.max(1,maxX-minX),math.max(1,maxY-minY));canvas.AnchorPoint=Vector2.zero
 canvas.ZIndex=object.ZIndex;canvas.GroupTransparency=1-opacity;canvas.GroupColor3=Color3.new(1,1,1);canvas.ClipsDescendants=true
 object.Position=UDim2.fromOffset(-minX,-minY);object.Size=UDim2.fromOffset(box.w,box.h);object.AnchorPoint=Vector2.zero;object.Rotation=0
 local scale=object:FindFirstChild('__CssScale');if scale then scale.Parent=host end
 host:SetAttribute('CssEffectPrepared',nil);host:SetAttribute('CssEffectOpacity',opacity);host:SetAttribute('CssEffectIsolation',style.isolation or 'auto')
 if entry then entry.effectHost=host end;return host
end
function G.configure(container)
 if not container or not container:IsA('ScreenGui')then return end
 local found=false;for _,o in ipairs(container:GetDescendants())do if o:GetAttribute('CssEffectCanvas')then found=true;break end end
 if found then container.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;container:SetAttribute('CssNativeGroupOpacity',true)
 elseif container:GetAttribute('CssNativeGroupOpacity')then container.ZIndexBehavior=Enum.ZIndexBehavior.Global;container:SetAttribute('CssNativeGroupOpacity',nil)end
end
function G.dispose(object)
 local host=get(object);if host then host:Destroy()else object:Destroy()end
end
return G
