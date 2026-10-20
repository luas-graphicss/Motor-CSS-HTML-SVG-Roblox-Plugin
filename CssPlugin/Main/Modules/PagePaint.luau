local RenderOptimizer=require(script.Parent.RenderOptimizer)
local U=require(script.Parent.Util)
local P={VERSION=1}
local MM=96/25.4
local NAME='__PageMarks'
local function make(class,name,parent)
 local o=RenderOptimizer.acquire(class);RenderOptimizer.properties(o,{Name=name});RenderOptimizer.attributes(o,{CssOwned=true})
 if o:IsA('GuiObject')then RenderOptimizer.properties(o,{BorderSizePixel=0})end
 o.Parent=parent;RenderOptimizer.remember(parent,name,o)
 return o
end
local function line(parent,index,x,y,w,h,color,alpha,z)
 local o=make('Frame','Mark'..index,parent)
 RenderOptimizer.properties(o,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(math.max(1,w),math.max(1,h)),BackgroundColor3=color,BackgroundTransparency=1-alpha,ZIndex=z})
end
function P.active(s)
 local page=s and s._page
 if not page then return false end
 local marks=page.marks
 return marks~=nil and marks~='none' and(marks:find('crop',1,true)~=nil or marks:find('cross',1,true)~=nil)
end
function P.signature(s)
 local page=s and s._page
 if not page then return ''end
 return tostring(page.marks or '')..'|'..tostring(page.bleedPx or 0)
end
function P.clear(object)
 local old=RenderOptimizer.child(object,NAME)
 if old then RenderOptimizer.release(old);RenderOptimizer.remember(object,NAME,nil)end
end
function P.apply(object,s,box,opacity)
 P.clear(object)
 if not P.active(s)then return end
 local page=s._page;local marks=page.marks
 local bleed=page.bleedPx or 0
 local gap=2*MM;local len=6*MM;local thickness=1
 local color,alpha=U.color(s.color or '#000000')
 alpha=alpha*opacity
 local holder=make('Frame',NAME,object)
 RenderOptimizer.properties(holder,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=object.ZIndex+50})
 local w,h=box.w,box.h
 local index=0
 local function put(x,y,lw,lh)index+=1;line(holder,index,x,y,lw,lh,color,alpha,holder.ZIndex)end
 if marks:find('crop',1,true)then
  local off=bleed+gap
  put(-off-len,0,len,thickness);put(-off-len,h-thickness,len,thickness)
  put(w+off,0,len,thickness);put(w+off,h-thickness,len,thickness)
  put(0,-off-len,thickness,len);put(w-thickness,-off-len,thickness,len)
  put(0,h+off,thickness,len);put(w-thickness,h+off,thickness,len)
 end
 if marks:find('cross',1,true)then
  local half=len/2;local center=bleed+gap+half
  local function cross(cx,cy)put(cx-half,cy-thickness/2,len,thickness);put(cx-thickness/2,cy-half,thickness,len)end
  cross(w/2,-center);cross(w/2,h+center);cross(-center,h/2);cross(w+center,h/2)
 end
end
return P
