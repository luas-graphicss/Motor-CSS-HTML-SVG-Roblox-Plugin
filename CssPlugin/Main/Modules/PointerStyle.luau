local U=require(script.Parent.Util)
local P={VERSION=1}
P.properties=table.freeze({'cursor','pointer-events','user-select'})
P.inherited=table.freeze({'cursor','pointer-events','user-select'})
P.initial=table.freeze({cursor='auto',['pointer-events']='auto',['user-select']='auto'})
local CURSORS=table.freeze({
 auto='',default='',none='none',['context-menu']='',help='',pointer='rbxasset://SystemCursors/PointingHand',
 progress='rbxasset://SystemCursors/Busy',wait='rbxasset://SystemCursors/Wait',cell='rbxasset://SystemCursors/Cross',
 crosshair='rbxasset://SystemCursors/Cross',text='rbxasset://SystemCursors/IBeam',['vertical-text']='rbxasset://SystemCursors/IBeam',
 alias='rbxasset://SystemCursors/PointingHand',copy='rbxasset://SystemCursors/PointingHand',move='rbxasset://SystemCursors/SizeAll',
 ['no-drop']='rbxasset://SystemCursors/Forbidden',['not-allowed']='rbxasset://SystemCursors/Forbidden',
 grab='rbxasset://SystemCursors/OpenHand',grabbing='rbxasset://SystemCursors/ClosedHand',
 ['e-resize']='rbxasset://SystemCursors/SizeEW',['w-resize']='rbxasset://SystemCursors/SizeEW',['ew-resize']='rbxasset://SystemCursors/SizeEW',['col-resize']='rbxasset://SystemCursors/SplitEW',
 ['n-resize']='rbxasset://SystemCursors/SizeNS',['s-resize']='rbxasset://SystemCursors/SizeNS',['ns-resize']='rbxasset://SystemCursors/SizeNS',['row-resize']='rbxasset://SystemCursors/SplitNS',
 ['ne-resize']='rbxasset://SystemCursors/SizeNESW',['sw-resize']='rbxasset://SystemCursors/SizeNESW',['nesw-resize']='rbxasset://SystemCursors/SizeNESW',
 ['nw-resize']='rbxasset://SystemCursors/SizeNWSE',['se-resize']='rbxasset://SystemCursors/SizeNWSE',['nwse-resize']='rbxasset://SystemCursors/SizeNWSE',
 ['all-scroll']='rbxasset://SystemCursors/SizeAll',['zoom-in']='rbxasset://SystemCursors/Cross',['zoom-out']='rbxasset://SystemCursors/Cross',
})
P.cursors=CURSORS
local POINTER=table.freeze({auto=true,none=true,all=true,visiblepainted=true,visiblefill=true,visiblestroke=true,visible=true,painted=true,fill=true,stroke=true,['bounding-box']=true})
local SELECT=table.freeze({auto=true,text=true,none=true,contain=true,all=true})
local function keyword(value)return type(value)=='string'and U.trim(value):lower()or nil end
P.keyword=keyword
local function splitTop(text)
 local parts={};local depth=0;local start=1
 for i=1,#text do
  local ch=text:sub(i,i)
  if ch=='('then depth+=1 elseif ch==')'then depth-=1 elseif ch==','and depth==0 then parts[#parts+1]=U.trim(text:sub(start,i-1));start=i+1 end
 end
 parts[#parts+1]=U.trim(text:sub(start))
 return parts
end
function P.parseCursor(value)
 local text=type(value)=='string'and U.trim(value)or nil
 if not text or text==''then return nil end
 local parts=splitTop(text)
 local images={};local fallback=nil
 for index,part in ipairs(parts)do
  local url=part:match('^url%(%s*["\']?(.-)["\']?%s*%)')
  if url then
   local rest=part:match('^url%b()%s*(.*)$')or''
   local hx,hy=rest:match('^(%-?[%d%.]+)%s+(%-?[%d%.]+)$')
   if rest~=''and not hx then return nil end
   if not url:match('^rbxasset')and not url:match('^rbxassetid://%d+$')then return nil end
   images[#images+1]={url=url,x=tonumber(hx)or 0,y=tonumber(hy)or 0}
  else
   if index~=#parts then return nil end
   local k=part:lower()
   if CURSORS[k]==nil then return nil end
   fallback=k
  end
 end
 if fallback==nil then return nil end
 return {images=images,keyword=fallback}
end
function P.validate(name,value)
 if name=='cursor'then return P.parseCursor(value)~=nil end
 local v=keyword(value)
 if not v then return false end
 if name=='pointer-events'then return POINTER[v]==true end
 if name=='user-select'then return SELECT[v]==true end
 return false
end
function P.check(style)
 for _,name in ipairs(P.properties)do
  local value=style[name]
  if value~=nil then
   assert(P.validate(name,value),name..' inválido: '..tostring(value))
   if name~='cursor'then style[name]=keyword(value)end
  end
 end
 return style
end
function P.register(supported,shorthandKeys)
 for _,name in ipairs(P.properties)do supported[name]=true end
 return supported,shorthandKeys
end
function P.install(supports)
 for _,name in ipairs(P.properties)do supports.register(name,function(value)return P.validate(name,value)end)end
end
function P.receives(style)
 local value=style and keyword(style['pointer-events'])or'auto'
 return value~='none'
end
function P.selectable(style)
 local value=style and keyword(style['user-select'])or'auto'
 return value~='none'
end
function P.icon(value)
 local parsed=type(value)=='table'and value or P.parseCursor(value)
 if not parsed then return''end
 if parsed.images[1]then return parsed.images[1].url,parsed.images[1].x,parsed.images[1].y end
 return CURSORS[parsed.keyword]or''
end
function P.native(style,object,disabled)
 local receives=P.receives(style)
 local out={}
 if object:IsA('GuiButton')or object:IsA('TextBox')then out.Interactable=receives and not disabled end
 if not receives then out.Active=false end
 if object:IsA('ScrollingFrame')and not receives then out.ScrollingEnabled=false end
 return out,receives
end
return P
