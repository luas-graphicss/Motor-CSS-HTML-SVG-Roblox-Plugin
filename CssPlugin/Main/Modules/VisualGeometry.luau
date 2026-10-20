local U=require(script.Parent.Util)
local Math=require(script.Parent.MathLength)
local G={}
local keys={'border-top-left-radius','border-top-right-radius','border-bottom-right-radius','border-bottom-left-radius'}
function G.length(value,base,context)
 if value==nil then return nil end
 if type(value)=='number'then return value end
 context=context or {};local c=table.clone(context);c.base=base;c.vw=c.vw or 1280;c.vh=c.vh or 720;c.font=c.font or c.fs or 16;c.rootFont=c.rootFont or 16
 if type(value)=='string'then value=({thin='1px',medium='3px',thick='5px'})[value]or value end
 local result=Math.evaluate(type(value)=='table'and value or Math.parse(value),c)
 assert(result==result and math.abs(result)<1e7,'Comprimento visual fora do limite.');return result
end
function G.context(style,vw,vh)
 local c=style._unitContext and table.clone(style._unitContext)or {};c.vw=vw or c.vw or 1280;c.vh=vh or c.vh or 720;c.font=style._fontPx or c.font or 16;c.fs=c.font;c.rootFont=style._rootFontPx or c.rootFont or 16;return c
end
local horizontal={left=true,right=true};local vertical={top=true,bottom=true}
local function axis(token,extent,image,context,edgeOffset)
 if token=='left'or token=='top'then return 0 elseif token=='right'or token=='bottom'then return extent-image elseif token=='center'then return (extent-image)/2 end
 return assert(G.length(token,edgeOffset and extent or(extent-image),context),'Posição inválida.')
end
function G.position(value,w,h,iw,ih,context)
 local t=U.split(value or '0% 0%',' ');assert(#t>=1 and #t<=4,'Posição CSS aceita 1 a 4 componentes.')
 if #t<=2 then
  local x,y=t[1],t[2]
  if #t==1 then if vertical[x]then x,y='center',x else y='center'end
  elseif vertical[x]or horizontal[y]then
   assert((horizontal[x]or vertical[x]or x=='center')and(horizontal[y]or vertical[y]or y=='center'),'Posição com comprimento exige ordem horizontal vertical.')
   x,y=y,x
  end
  assert(not vertical[x]and not horizontal[y],'Eixos repetidos em background-position.')
  return axis(x,w,iw,context),axis(y,h,ih,context)
 end
 local x,y,i=nil,nil,1;local explicitX,explicitY=false,false
 for _,word in ipairs(t)do explicitX=explicitX or horizontal[word]or false;explicitY=explicitY or vertical[word]or false end
 while i<=#t do
  local key=t[i];local offset=t[i+1];local hasOffset=offset and not horizontal[offset]and not vertical[offset]and offset~='center'
  if horizontal[key]then
   assert(x==nil,'Eixo X repetido.');local n=hasOffset and G.length(offset,w-iw,context)or 0;x=key=='left'and n or(w-iw-n)
  elseif vertical[key]then
   assert(y==nil,'Eixo Y repetido.');local n=hasOffset and G.length(offset,h-ih,context)or 0;y=key=='top'and n or(h-ih-n)
  elseif key=='center'then if not explicitX and x==nil then x=(w-iw)/2 elseif not explicitY and y==nil then y=(h-ih)/2 else error('Centro repetido.',0)end;hasOffset=false
  else error('Posição de 3/4 componentes exige bordas (left/right/top/bottom).',0)end
  i+=hasOffset and 2 or 1
 end
 return x or(w-iw)/2,y or(h-ih)/2
end
function G.size(value,w,h,intrinsicW,intrinsicH,context)
 local t=U.split(value or 'auto auto',' ');assert(#t>=1 and #t<=2,'background-size aceita 1 ou 2 tamanhos.')
 local iw,ih=intrinsicW,intrinsicH
 if iw and(iw<=0 or not ih or ih<=0)then iw,ih=nil,nil end
 if t[1]=='cover'or t[1]=='contain'then
  assert(#t==1,'cover/contain devem aparecer sozinhos.')
  if not iw then return w,h end
  local ratio=t[1]=='cover'and math.max(w/iw,h/ih)or math.min(w/iw,h/ih);return iw*ratio,ih*ratio
 end
 local a,b=t[1],t[2]or 'auto';local x=a~='auto'and G.length(a,w,context)or nil;local y=b~='auto'and G.length(b,h,context)or nil
 if not x and not y then return iw or w,ih or h end
 if not x then x=iw and y*iw/ih or w end;if not y then y=iw and x*ih/iw or h end
 assert(x>=0 and y>=0,'background-size não aceita tamanhos negativos.');return x,y
end
function G.repeatModes(value)
 local t=U.split(value or 'repeat',' ')
 if t[1]=='repeat-x'then assert(#t==1,'repeat-x não aceita segundo eixo.');return 'repeat','no-repeat'end
 if t[1]=='repeat-y'then assert(#t==1,'repeat-y não aceita segundo eixo.');return 'no-repeat','repeat'end
 assert(#t>=1 and #t<=2,'background-repeat aceita 1 ou 2 modos.')
 local allowed={['repeat']=true,['no-repeat']=true,space=true,round=true}
 assert(allowed[t[1]]and(not t[2]or allowed[t[2]]),'background-repeat inválido.');return t[1],t[2]or t[1]
end
function G.tiles(extent,tile,position,mode,minBound,maxBound)
 if tile<=0 or extent<=0 then return {},tile end
 local gap=0
 if mode=='round'then local count=math.max(1,math.floor(extent/tile+0.5));tile=extent/count
 elseif mode=='space'then local count=math.floor(extent/tile);if count>=2 then gap=(extent-count*tile)/(count-1);position=0 else mode='no-repeat'end end
 if mode=='no-repeat'then return {{start=position,size=tile}},tile end
 minBound,maxBound=minBound or 0,maxBound or extent
 local step=tile+gap;local first=math.floor((minBound-position)/step);local last=math.ceil((maxBound-position)/step)-1
 if mode=='space'then first=math.max(0,first);last=math.min(math.floor(extent/tile)-1,last)end
 assert(last-first<2048,'Repetição excede 2048 tiles por eixo; aumente background-size.')
 local out={};for i=first,last do out[#out+1]={start=position+i*step,size=tile}end;return out,tile
end
function G.radii(style,w,h,context)
 local out={}
 for i,key in ipairs(keys)do
  local v=style[key]or 0;local a,b
  if type(v)=='table'and v._cssRadius then a,b=v.x,v.y
  elseif type(v)=='string'then local t=U.split(v,' ');assert(#t==1 or #t==2,'Raio de canto aceita rx ry.');a,b=t[1],t[2]or t[1]
  else a,b=v,v end
  local x,y=G.length(a,w,context)or 0,G.length(b,h,context)or 0
  assert(x>=0 and y>=0,'border-radius não aceita raio negativo.')
  if x==0 or y==0 then x,y=0,0 end;out[i]={x=x,y=y}
 end
 local f=1
 for _,pair in ipairs({{w,out[1].x+out[2].x},{w,out[4].x+out[3].x},{h,out[1].y+out[4].y},{h,out[2].y+out[3].y}})do if pair[2]>0 then f=math.min(f,pair[1]/pair[2])end end
 for _,r in ipairs(out)do r.x*=f;r.y*=f end;return out
end
function G.insetRadii(r,left,top,right,bottom)
 local out={};for i,c in ipairs(r)do local dx=(i==1 or i==4)and left or right;local dy=(i<=2)and top or bottom;out[i]={x=math.max(0,c.x-dx),y=math.max(0,c.y-dy)}end;return out
end
local function curve(rx,ry,d)
 if rx<=0 or ry<=0 or d>=ry then return 0 end
 return rx*(1-math.sqrt(math.max(0,1-(1-math.max(d,0)/ry)^2)))
end
function G.bounds(r,w,h,y)
 if y<0 or y>h then return 0,0 end
 return math.max(curve(r[1].x,r[1].y,y),curve(r[4].x,r[4].y,h-y)),w-math.max(curve(r[2].x,r[2].y,y),curve(r[3].x,r[3].y,h-y))
end
function G.inside(r,w,h,x,y)
 if y<0 or y>=h then return false end;local l,rr=G.bounds(r,w,h,y);return x>=l and x<rr
end
function G.rect(style,box,kind,context)
 local border=math.max(0,G.length(style['border-width']or 0,box.w,context)or 0)
 if style['border-style']=='none'or style['border-style']=='hidden'then border=0 end
 local l,t,rr,b=0,0,0,0
 local widths=style._borderWidths or {border,border,border,border}
 if kind~='border-box'then l,t,rr,b=widths[4],widths[1],widths[2],widths[3]end
 if kind=='content-box'then l,t,rr,b=box.p[4],box.p[1],box.p[2],box.p[3]end
 local radii=G.insetRadii(G.radii(style,box.w,box.h,context),l,t,rr,b)
 return {x=l,y=t,w=math.max(0,box.w-l-rr),h=math.max(0,box.h-t-b),r=radii}
end
return G
