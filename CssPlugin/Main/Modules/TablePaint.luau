local U=require(script.Parent.Util)
local O=require(script.Parent.RenderOptimizer)
local T={}
function T.style(style,box)
 if not(box.collapsedCell or box.collapsedBorders)then return style end
 local out=table.clone(style);out['border-width']=0;out['border-style']='none';out['border-image-source']='none';out._borderWidths={0,0,0,0}
 for _,side in ipairs({'top','right','bottom','left'})do out['border-'..side..'-width']=0;out['border-'..side..'-style']='none'end
 return out
end
function T.draw(paint,box,opacity)
 local count=0
 for _,line in ipairs(box.tableBorders or{})do
  local edge=line.border;local color,alpha=U.color(edge.color);local horizontal=line.h==0;local thickness=edge.width;local length=horizontal and line.w or line.h
  local x=box.p[4]+line.x-(box.captionShiftX or 0)-(horizontal and 0 or thickness/2);local y=box.p[1]+line.y-(box.captionShift or 0)-(horizontal and thickness/2 or 0)
  local function segment(at,breadth,t,width,tint)
   if breadth<=0 or width<=0 then return end;count+=1;assert(count<=4096,'Bordas da tabela excedem 4096 segmentos.')
   local f=O.acquire('Frame');O.properties(f,{Name='TableBorder',BorderSizePixel=0,AnchorPoint=Vector2.zero,Position=UDim2.fromOffset(x+(horizontal and at or t),y+(horizontal and t or at)),Size=UDim2.fromOffset(horizontal and breadth or width,horizontal and width or breadth),BackgroundColor3=tint or color,BackgroundTransparency=1-alpha*opacity,ZIndex=box.tableBorderZ or paint.ZIndex+1})
   O.attributes(f,{CssOwned=true,CssBaseAlpha=alpha});f.Parent=paint
  end
  local shaded=edge.style=='groove'or edge.style=='ridge'or edge.style=='inset'or edge.style=='outset'
  if edge.style=='double'and thickness>=3 then segment(0,length,0,thickness/3);segment(0,length,thickness*2/3,thickness/3)
  elseif shaded and thickness>=2 then
   local dark=color:Lerp(Color3.new(0,0,0),0.4);local light=color:Lerp(Color3.new(1,1,1),0.4)
   local first,second=dark,light;if edge.style=='ridge'or edge.style=='outset'then first,second=light,dark end
   segment(0,length,0,thickness/2,first);segment(0,length,thickness/2,thickness/2,second)

  elseif edge.style=='dotted'or edge.style=='dashed'then local dash=thickness*(edge.style=='dotted'and 1 or 3);local at=0;while at<length do segment(at,math.min(dash,length-at),0,thickness);at+=dash+thickness end
  else segment(0,length,0,thickness)end
 end
end
return T
