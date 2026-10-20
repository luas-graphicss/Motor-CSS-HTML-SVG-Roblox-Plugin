local U=require(script.Parent.Util)
local Math=require(script.Parent.MathLength)
local G={VERSION=1}
function G.length(value,base,style,width,height)
 if not value or value=='auto'then return 0 end
 local n=Math.evaluate(Math.parse(value),{base=base,vw=width or 1280,vh=height or 720,font=style._fontPx or 16,rootFont=style._rootFontPx or 16,ch=style._chPx,ex=style._exPx,lineHeight=style._lineHeight})
 assert(n==n and math.abs(n)<1e8,'Comprimento de scroll fora do limite.');return n
end
function G.axis(style,name)
 local mode=style['writing-mode']or'horizontal-tb'
 local a=style._writingAxes
 local vertical=a and a.vertical or(mode~='horizontal-tb')
 local axis=name=='x'and'x'or name=='y'and'y'or(name=='inline'and(vertical and'y'or'x')or(vertical and'x'or'y'))
 local reverse
 if a then reverse=name=='inline'and a.inlineReverse or name=='block'and a.blockReverse or false
 else reverse=(name=='inline'and((style.direction=='rtl')~=(mode=='sideways-lr')))or(name=='block'and vertical and mode:sub(-2)=='rl')end
 return axis,reverse==true
end
function G.sides(style,base,w,h,vw,vh)
 local out={}
 for i,side in ipairs({'top','right','bottom','left'})do out[i]=G.length(style[base..'-'..side],(i==1 or i==3)and h or w,style,vw,vh)end
 for _,name in ipairs({'block','inline'})do
  local axis,reverse=G.axis(style,name);local first,last=axis=='x'and 4 or 1,axis=='x'and 2 or 3
  if reverse then first,last=last,first end
  local a,b=style[base..'-'..name..'-start'],style[base..'-'..name..'-end'];local size=axis=='x'and w or h
  if a then out[first]=G.length(a,size,style,vw,vh)end;if b then out[last]=G.length(b,size,style,vw,vh)end
 end
 if base=='scroll-padding'then for _,v in ipairs(out)do assert(v>=0,'scroll-padding não aceita comprimentos negativos.')end end
 return out
end
function G.scroller(c,node,kind)
 local at=kind=='self'and node or c.parents[node.key];local found
 while at do
  local o=c.objects[at.key]
  if o and o:IsA('ScrollingFrame')then found=at;if kind~='root'then return found end end
  if kind=='self'then return nil end;at=c.parents[at.key]
 end
 return found
end
function G.coordinate(c,node,stop)
 local x,y=0,0
 while node and node~=stop do
  local b=c.boxes[node.key];if b then x+=b.x;y+=b.y end
  node=c.parents[node.key]
  if node and node~=stop then local o=c.objects[node.key];if o and o:IsA('ScrollingFrame')then x-=o.CanvasPosition.X;y-=o.CanvasPosition.Y end end
 end
 return x,y
end
function G.port(c,node)
 local b=c.boxes[node.key];local o=c.objects[node.key]
 local native=o and o.AbsoluteWindowSize
 local w=native and native.X>0 and native.X or b.w;local h=native and native.Y>0 and native.Y or b.h
 local cw=math.max(w,b.contentW or w);local ch=math.max(h,b.contentH or h)
 return w,h,math.max(0,cw-w),math.max(0,ch-h)
end
function G.snap(c,record,axis,current,from,force)
 local style=c.styles[record.node.key];local spec=U.split(style['scroll-snap-type']or'none',' ')
 if spec[1]=='none'then return current,nil end
 if spec[1]~='both'and G.axis(style,spec[1])~=axis then return current,nil end
 local w,h,mx,my=G.port(c,record.node);local size=axis=='x'and w or h;local limit=axis=='x'and mx or my
 local pad=G.sides(style,'scroll-padding',w,h,c.width,c.height);local first,last=axis=='x'and 4 or 1,axis=='x'and 2 or 3
 local p0,p1=pad[first],size-pad[last];local nearest,dist,key,barrier,barrierKey=nil,math.huge,nil,nil,nil
 for _,node in ipairs(record.targets or{})do
  local s,b=c.styles[node.key],c.boxes[node.key]
  if not b or b.hidden then continue end
  local align=U.split(s['scroll-snap-align']or'none',' ');local block=G.axis(style,'block');local a=align[axis==block and 1 or 2]or align[1]
  if a=='none'then continue end
  local x,y=G.coordinate(c,node,record.node);local margin=G.sides(s,'scroll-margin',b.w,b.h,c.width,c.height)
  local lo=(axis=='x'and x or y)-margin[first];local hi=(axis=='x'and x+b.w or y+b.h)+margin[last]
  local logical=axis==block and'block'or'inline';local _,reverse=G.axis(style,logical)
  if reverse then if a=='start'then a='end'elseif a=='end'then a='start'end end
  local at=a=='start'and(lo-p0)or a=='end'and(hi-p1)or(lo+hi-p0-p1)/2
  if hi-lo>p1-p0 and current>=lo-p0 and current<=hi-p1 then at=current end
  at=math.clamp(at,0,limit);local d=math.abs(at-current)
  if d<dist then nearest,dist,key=at,d,node.key end
  if from and s['scroll-snap-stop']=='always'and((current>from and at>from+.5 and at<current)or(current<from and at<from-.5 and at>current))then
   if not barrier or math.abs(at-from)<math.abs(barrier-from)then barrier,barrierKey=at,node.key end
  end
 end
 if barrier then return barrier,barrierKey end
 if not nearest or(not force and spec[2]=='proximity'and dist>math.min(100,size*.3))then return current,nil end
 return nearest,key
end
function G.delta(position,delta,limit,behavior)
 local nextPosition=math.clamp(position+delta,0,math.max(0,limit));local rest=delta-(nextPosition-position)
 return nextPosition,behavior=='auto'and rest or 0
end
function G.viewRanges(position,extent,viewport,insetStart,insetEnd)
 local start=position-viewport+insetEnd;local finish=position+extent-insetStart
 local a=position-insetStart;local b=position+extent-viewport+insetEnd
 return {cover={start,finish},contain={math.min(a,b),math.max(a,b)},entry={start,math.min(a,b)},exit={math.max(a,b),finish},['entry-crossing']={start,a},['exit-crossing']={b,finish}}
end
return G
