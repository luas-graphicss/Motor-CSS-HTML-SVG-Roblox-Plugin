local Cost=require(script.Parent.CostModel)
local G={VERSION=2,MAX_TAPS=128,MAX_RINGS=12,MAX_LEVELS=255,MAX_CELL=16,MIN_ALPHA=1/255}
function G.sigma(filter)
 if not filter then return 0 end
 if filter.name=='blur' then return math.max(0,filter.value or 0)end
 if filter.name=='drop-shadow' then return math.max(0,filter.blur or 0)end
 return 0
end
local function annulus(inner,outer,sigma)
 local d=2*sigma*sigma
 return math.exp(-(inner*inner)/d)-math.exp(-(outer*outer)/d)
end
function G.kernel(sigma,maxTaps)
 sigma=math.max(0,sigma or 0)
 maxTaps=math.clamp(math.floor(maxTaps or G.MAX_TAPS),1,G.MAX_TAPS)
 if sigma<=1e-3 or maxTaps<=1 then return {{dx=0,dy=0,w=1}}end
 local rings=math.clamp(math.floor(math.sqrt(maxTaps)),1,G.MAX_RINGS)
 local step=sigma*3/rings
 local taps={{dx=0,dy=0,w=1-math.exp(-(step*step*.25)/(2*sigma*sigma))}}
 local total=taps[1].w
 for i=1,rings do
  local radius=i*step
  local weight=annulus(math.max(0,radius-step*.5),radius+step*.5,sigma)
  local room=maxTaps-#taps
  if weight>1e-5 and room>0 then
   local count=math.clamp(math.floor(2*math.pi*radius/math.max(step,1e-3)+.5),4,16)
   count=math.min(count,room)
   local share=weight/count
   for k=0,count-1 do
    local angle=(k+(i%2)*.5)*2*math.pi/count
    taps[#taps+1]={dx=math.cos(angle)*radius,dy=math.sin(angle)*radius,w=share}
    total+=share
   end
  end
  if #taps>=maxTaps then break end
 end
 for _,tap in ipairs(taps)do tap.w=tap.w/total end
 Cost.cap('glyphs',#taps,'Amostras de blur sobre glifos')
 return taps
end
function G.stack(taps,alpha)
 alpha=math.clamp(alpha or 1,0,1)
 if alpha<=0 or #taps==0 then return {},0 end
 local function reached(scale)
  local keep=1
  for _,tap in ipairs(taps)do keep*=1-math.min(.995,alpha*tap.w*scale)end
  return 1-keep
 end
 local low,high=1,1
 while high<4096 and reached(high)<alpha-1e-4 do high*=2 end
 for _=1,32 do
  local mid=(low+high)*.5
  if reached(mid)<alpha then low=mid else high=mid end
 end
 local scale=(low+high)*.5
 local out={}
 for _,tap in ipairs(taps)do
  local a=math.min(.995,alpha*tap.w*scale)
  if a>=G.MIN_ALPHA then out[#out+1]={dx=tap.dx,dy=tap.dy,alpha=a,w=tap.w}end
 end
 return out,reached(scale)
end
local function key(level,color)
 if not color then return tostring(level)end
 return level..':'..math.floor(color.R*255+.5)..','..math.floor(color.G*255+.5)..','..math.floor(color.B*255+.5)
end
function G.strips(width,height,options,sample,checkpoint)
 options=options or {}
 local levels=math.clamp(math.floor(options.levels or G.MAX_LEVELS),1,G.MAX_LEVELS)
 local maxRects=math.max(1,math.floor(options.maxRects or 4096))
 local maxCells=math.max(16,math.floor(options.maxCells or 65536))
 local super=math.clamp(math.floor(options.supersample or 2),1,4)
 local wants=options.colors and true or false
 local w,h=math.max(1,math.ceil(width)),math.max(1,math.ceil(height))
 local base=math.clamp(math.max(options.cell or 1,math.sqrt(w*h/maxCells)),1,G.MAX_CELL)
 local cols,rows=math.max(1,math.ceil(w/base)),math.max(1,math.ceil(h/base))
 local cw,ch=w/cols,h/rows
 local work=cols*rows*super*super*math.max(1,options.cost or 1)
 Cost.cap('pixels',(options.spent or 0)+work,'Amostragem de máscara/blend de texto')
 local grid,tints=table.create(rows),wants and table.create(rows)or nil
 local inv=1/(super*super)
 for y=0,rows-1 do
  if checkpoint and y%8==0 then checkpoint(32)end
  local row=table.create(cols);local tint=wants and table.create(cols)or nil
  for x=0,cols-1 do
   local alpha,r,g,b=0,0,0,0
   for sy=0,super-1 do
    for sx=0,super-1 do
     local a,color=sample((x+(sx+.5)/super)*cw,(y+(sy+.5)/super)*ch)
     alpha+=a or 0
     if wants and color then r+=color.R;g+=color.G;b+=color.B end
    end
   end
   row[x+1]=alpha*inv
   if wants then tint[x+1]=Color3.new(math.clamp(r*inv,0,1),math.clamp(g*inv,0,1),math.clamp(b*inv,0,1))end
  end
  grid[y+1]=row;if wants then tints[y+1]=tint end
 end
 local function build(block)
  local rects,previous={},{}
  local gcols,grows=math.ceil(cols/block),math.ceil(rows/block)
  for gy=0,grows-1 do
   local current={}
   local levelRow,tintRow=table.create(gcols),wants and table.create(gcols)or nil
   for gx=0,gcols-1 do
    local sum,count,r,g,b=0,0,0,0,0
    for y=gy*block,math.min(rows-1,gy*block+block-1)do
     local row=grid[y+1];local tint=wants and tints[y+1]or nil
     for x=gx*block,math.min(cols-1,gx*block+block-1)do
      sum+=row[x+1];count+=1
      if wants then local c=tint[x+1];r+=c.R;g+=c.G;b+=c.B end
     end
    end
    count=math.max(1,count)
    levelRow[gx+1]=math.floor(math.clamp(sum/count,0,1)*levels+.5)
    if wants then tintRow[gx+1]=Color3.new(math.clamp(r/count,0,1),math.clamp(g/count,0,1),math.clamp(b/count,0,1))end
   end
   local y0=math.min(h,gy*block*ch);local y1=math.min(h,(gy+1)*block*ch)
   local gx=0
   while gx<gcols do
    local level=levelRow[gx+1];local tint=wants and tintRow[gx+1]or nil
    local id=key(level,tint);local start=gx;gx+=1
    while gx<gcols and key(levelRow[gx+1],wants and tintRow[gx+1]or nil)==id do gx+=1 end
    if level>0 then
     local slot=start..'|'..gx..'|'..id;local rect=previous[slot]
     if rect then rect.h=y1-rect.y else
      local x0=math.min(w,start*block*cw);local x1=math.min(w,gx*block*cw)
      rect={x=x0,y=y0,w=x1-x0,h=y1-y0,a=level/levels,color=tint}
      rects[#rects+1]=rect
      if #rects>maxRects then return nil end
     end
     current[slot]=rect
    end
   end
   previous=current
  end
  return rects,gcols,grows
 end
 local block=1
 local rects,gcols,grows=build(block)
 while not rects and block<G.MAX_CELL do block*=2;rects,gcols,grows=build(block)end
 assert(rects,'Máscara de texto excede o orçamento de bandas nativas.')
 return {rects=rects,cols=gcols,rows=grows,cellWidth=cw*block,cellHeight=ch*block,levels=levels,block=block,work=work}
end
return G
