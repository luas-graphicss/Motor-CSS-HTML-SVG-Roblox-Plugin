local U=require(script.Parent.Util)
local Ua=require(script.Parent.UserAgentStyles)
local Lp=require(script.Parent.LogicalProperties)
local T={VERSION=4}
local keywordW={['min-content']=true,['max-content']=true,['fit-content']=true}
local groups={['table-row-group']=true,['table-header-group']=true,['table-footer-group']=true}
local EMPTY=table.freeze({})
local sides={'top','right','bottom','left'}
local borderRank={hidden=100,double=9,solid=8,dashed=7,dotted=6,ridge=5,outset=4,groove=3,inset=2,none=0}
local tiers={cell=6,row=5,group=4,column=3,colgroup=2,table=1}
local captionTop={top=true,['block-start']=true,['inline-start']=true}
local captionBottom={bottom=true,['block-end']=true,['inline-end']=true}
local rank={['table-header-group']=0,['table-row-group']=1,['table-footer-group']=2}
function T.container(s)return s.display=='table'or s.display=='inline-table'end
function T.active(s)return T.container(s)or s.display=='table-row'or groups[s.display]==true or s.display=='table-column-group'end
function T.orphan(s,ps)return s.display=='table-cell'and not(ps and(ps.display=='table-row'or groups[ps.display]or T.container(ps)))end
function T.wrapped(s,ps)
 local d=s.display;if not(d=='table-row'or groups[d]or d=='table-cell')then return false end
 return not(ps and(ps.display=='table-row'or groups[ps.display]or T.container(ps)))
end
function T.shrinks(s,ps)
 if T.container(s)then return s.width==nil or s.width=='auto'end
 if not T.wrapped(s,ps)then return false end
 return s.display~='table-cell'or s.width==nil or s.width=='auto'
end
function T.related(s)local d=s.display;return type(d)=='string'and d:sub(1,5)=='table'end
local function sum(a,first,last)local n=0;for i=first or 1,last or#a do n+=a[i]or 0 end;return n end
local function distribute(a,first,last,wanted,weights)
 local missing=wanted-sum(a,first,last);if missing<=0 then return end
 local total=0;for i=first,last do total+=math.max(0,weights and weights[i]or 0)end
 for i=first,last do local share=total>0 and math.max(0,weights[i])/total or 1/(last-first+1);a[i]=(a[i]or 0)+missing*share end
end
local function span(node,key,allowZero,limit)
 local value=node.attrs and node.attrs[key];if value==nil or value==''then return 1 end
 local n=tonumber(value);assert(n and n%1==0 and n>=0,key..' deve ser um inteiro não negativo.')
 if n==0 then return allowZero and 0 or 1 end;return math.min(n,limit)
end
local function box(w,h,fs)return{w=w,h=h,fs=fs,p={0,0,0,0},m={0,0,0,0},definiteH=true}end
local function percent(value)
 if type(value)=='table'then if value.op=='value'and value.unit=='%'and type(value.value)=='number'and value.value>=0 then return value.value/100 end;return nil end
 if type(value)=='string'then local n=tonumber(value:match('^%s*(%-?[%d%.]+)%%%s*$'));if n and n>=0 then return n/100 end end
end
local function blank(child)return child.anonymousText==true and(child.text or''):match('^%s*$')~=nil end
local function skipped(cs)return cs.display=='none'or cs.position=='absolute'or cs.position=='fixed'end
local function collapsed(cs)return cs.visibility=='collapse'end
local function edge(style,index,length,base,fs,tier,order)
 local side=sides[index];local mode=style['border-'..side..'-style']or style['border-style']or'none'
 local width=style._borderWidths and style._borderWidths[index]or length(style['border-'..side..'-width']or style['border-width'],base,fs)or 0
 if mode=='none'or mode=='hidden'then width=0 end
 return{width=math.max(0,width),style=mode,color=style['border-'..side..'-color']or style['border-color']or style.color or'black',rank=borderRank[mode]or 1,tier=tier,order=order}
end
local function winner(a,b)
 if not a then return b elseif not b then return a end
 if a.style=='hidden'then return a elseif b.style=='hidden'then return b end
 if a.style=='none'and b.style~='none'then return b elseif b.style=='none'and a.style~='none'then return a end
 if a.width~=b.width then return a.width>b.width and a or b end
 if a.rank~=b.rank then return a.rank>b.rank and a or b end
 if a.tier~=b.tier then return a.tier>b.tier and a or b end
 return a.order<=b.order and a or b
end
function T.plan(node,flow,cw,ch,definiteH,ctx)
 local bound=ctx.tableBindings and ctx.tableBindings[node.key];if bound then return bound end
 local s,fs,pad=ctx.info(node,cw,ch);pad=pad or{0,0,0,0};local axes=Lp.axes(s)
 if s.display=='table-column-group'then return{items={},usedW=0,usedH=0,bindings={}}end
 local collapseValue=s['border-collapse']or'separate';assert(collapseValue=='collapse'or collapseValue=='separate','border-collapse aceita separate ou collapse.');local collapse=collapseValue=='collapse'
 local spacing=U.split(tostring(s['border-spacing']or'0px'),' ');assert(#spacing>=1 and #spacing<=2,'border-spacing exige um ou dois comprimentos.')
 local sx=ctx.length(spacing[1],cw,fs)or 0;local sy=ctx.length(spacing[2]or spacing[1],cw,fs)or 0
 assert(sx>=0 and sy>=0,'border-spacing não pode ser negativo.');if collapse then sx,sy=0,0 end
 local mode=s['table-layout']or'auto';assert(mode=='auto'or mode=='fixed','table-layout aceita auto ou fixed.')
 local intrinsic=ctx.intrinsic
 local rows,captions,columns,groupNodes,columnNodes={},{},{},{},{}
 local ordered=table.clone(flow);local order={};for i,child in ipairs(flow)do order[child]=i end
 table.sort(ordered,function(a,b)local aa=rank[ctx.styles[a.key].display]or 1;local bb=rank[ctx.styles[b.key].display]or 1;return aa==bb and order[a]<order[b]or aa<bb end)
 local loose
 local function anonymous(first)return{members={},style=EMPTY,key='anon:'..first.key}end
 local function push(cells,child,cs,holder)
  if cs.display=='table-cell'then cells[#cells+1]={node=child,style=cs};holder.anon=nil
  else if not holder.anon then holder.anon=anonymous(child);cells[#cells+1]=holder.anon end;holder.anon.members[#holder.anon.members+1]=child end
 end
 local function cellsOf(children)
  local cells,holder={},{}
  for _,child in ipairs(children)do local cs=ctx.styles[child.key];if not(skipped(cs)or blank(child))then push(cells,child,cs,holder)end end
  return cells
 end
 local function addColumn(n,cs,group)columns[#columns+1]={width=cs.width or'auto',node=n,group=group,style=cs}end
 local function collect(children,parent)
  for _,child in ipairs(children)do local cs=ctx.styles[child.key];local d=cs.display
   if skipped(cs)or blank(child)then
   elseif d=='table-caption'then captions[#captions+1]=child
   elseif groups[d]then groupNodes[#groupNodes+1]=child;loose=nil;collect(child.children,child);loose=nil
   elseif d=='table-row'then rows[#rows+1]={node=child,parent=parent,cells=cellsOf(child.children)};loose=nil
   elseif d=='table-column'then local first=#columns+1;for _=1,span(child,'span',false,1000)do addColumn(child,cs,nil)end;columnNodes[#columnNodes+1]={node=child,first=first,last=#columns,style=cs}
   elseif d=='table-column-group'then
    local first=#columns+1;local inner={}
    for _,col in ipairs(child.children)do local ccs=ctx.styles[col.key]
     if ccs.display=='table-column'and not skipped(ccs)then local f=#columns+1;for _=1,span(col,'span',false,1000)do addColumn(col,ccs,child)end;inner[#inner+1]={node=col,first=f,last=#columns,style=ccs}end
    end
    if #inner==0 then for _=1,span(child,'span',false,1000)do addColumn(child,cs,child)end end
    columnNodes[#columnNodes+1]={node=child,first=first,last=#columns,style=cs,group=true,inner=inner}
   else
    if not loose then loose={cells={},parent=parent};rows[#rows+1]=loose end
    push(loose.cells,child,cs,loose)
   end
  end
 end
 if s.display=='table-row'then rows[1]={cells=cellsOf(flow)}
 elseif s.display=='table-cell'then local cell=anonymous(node);for _,child in ipairs(flow)do cell.members[#cell.members+1]=child end;rows[1]={cells={cell}}
 else collect(ordered,node)end
 local occupied,cells={},{};local count=math.max(1,#columns)
 local function groupEnd(ri)local parent=rows[ri].parent;local last=ri;while rows[last+1]and rows[last+1].parent==parent do last+=1 end;return last end
 for ri,r in ipairs(rows)do
  occupied[ri]=occupied[ri]or{};local ci=1
  for _,cell in ipairs(r.cells)do
   while occupied[ri][ci]do ci+=1 end
   local n=cell.node;local csn=n and span(n,'colspan',false,1000)or 1;local rsn=n and span(n,'rowspan',true,65534)or 1
   local last=groupEnd(ri);if rsn==0 or ri+rsn-1>last then rsn=last-ri+1 end
   assert(ci+csn-1<=128,'Tabela excede 128 colunas.');count=math.max(count,ci+csn-1)
   local item={cell=cell,node=n,style=cell.style,row=ri,col=ci,colSpan=csn,rowSpan=rsn,owner=r};cells[#cells+1]=item
   for y=ri,ri+rsn-1 do occupied[y]=occupied[y]or{};for x=ci,ci+csn-1 do occupied[y][x]=item end end;ci+=csn
  end
 end
 local hiddenColumns,hiddenRows={},{}
 for i=1,count do local col=columns[i];if col and(collapsed(col.style)or(col.group and collapsed(ctx.styles[col.group.key])))then hiddenColumns[i]=true end end
 for i,r in ipairs(rows)do local rs=r.node and ctx.styles[r.node.key];if rs and collapsed(rs)or(r.parent and r.parent~=node and collapsed(ctx.styles[r.parent.key]))then hiddenRows[i]=true end end
 for _,item in ipairs(cells)do
  local hidden=hiddenRows[item.row];if not hidden then hidden=true;for i=item.col,item.col+item.colSpan-1 do if not hiddenColumns[i]then hidden=false end end end
  item.hidden=hidden
 end
 local resolved;local offT,offR,offB,offL=0,0,0,0
 local function edgeWidth(store,key)local e=store[key];if not e then return 0 end;local st=e.edge.style;return st~="none"and st~="hidden"and e.edge.width or 0 end
 if collapse and #rows>0 then
  local vertical,horizontal={},{}
  local function put(store,key,candidate)local old=store[key];local best=winner(old and old.edge,candidate);if not old or best~=old.edge then store[key]={edge=best}end end
  local function edges(style,tier,ordinal,r1,r2,c1,c2,efs)
   for ri=r1,r2 do put(vertical,ri..":"..c1,edge(style,4,ctx.length,cw,efs,tier,ordinal));put(vertical,ri..":"..(c2+1),edge(style,2,ctx.length,cw,efs,tier,ordinal))end
   for ci=c1,c2 do put(horizontal,r1..":"..ci,edge(style,1,ctx.length,cw,efs,tier,ordinal));put(horizontal,(r2+1)..":"..ci,edge(style,3,ctx.length,cw,efs,tier,ordinal))end
  end
  local ordinal=1;edges(s,tiers.table,ordinal,1,#rows,1,count,fs)
  for _,entry in ipairs(columnNodes)do if entry.last>=entry.first then
   ordinal+=1;edges(entry.style,entry.group and tiers.colgroup or tiers.column,ordinal,1,#rows,entry.first,entry.last,fs)
   for _,col in ipairs(entry.inner or EMPTY)do ordinal+=1;edges(col.style,tiers.column,ordinal,1,#rows,col.first,col.last,fs)end
  end end
  local groupRows={}
  for ri,r in ipairs(rows)do if r.parent and r.parent~=node then local g=groupRows[r.parent.key];if g then g.last=ri else groupRows[r.parent.key]={first=ri,last=ri}end end end
  for _,group in ipairs(groupNodes)do local g=groupRows[group.key];if g then ordinal+=1;edges(ctx.styles[group.key],tiers.group,ordinal,g.first,g.last,1,count,fs)end end
  for ri,r in ipairs(rows)do if r.node then ordinal+=1;edges(ctx.styles[r.node.key],tiers.row,ordinal,ri,ri,1,count,fs)end end
  for _,item in ipairs(cells)do if item.node and not item.hidden then local _,efs=ctx.info(item.node,cw,ch);ordinal+=1;edges(item.style,tiers.cell,ordinal,item.row,item.row+item.rowSpan-1,item.col,item.col+item.colSpan-1,efs)end end
  resolved={vertical=vertical,horizontal=horizontal}
  if ctx.setBorders then
   for _,item in ipairs(cells)do if item.node then
    local c1,c2,r1,r2=item.col,item.col+item.colSpan-1,item.row,item.row+item.rowSpan-1;local l,r,t,b=0,0,0,0
    for ri=r1,r2 do l=math.max(l,edgeWidth(vertical,ri..":"..c1));r=math.max(r,edgeWidth(vertical,ri..":"..(c2+1)))end
    for ci=c1,c2 do t=math.max(t,edgeWidth(horizontal,r1..":"..ci));b=math.max(b,edgeWidth(horizontal,(r2+1)..":"..ci))end
    ctx.setBorders(item.node,{t/2,r/2,b/2,l/2})
   end end
  end
  local l,r,t,b=0,0,0,0
  for ri=1,#rows do l=math.max(l,edgeWidth(vertical,ri..":1"));r=math.max(r,edgeWidth(vertical,ri..":"..(count+1)))end
  for ci=1,count do t=math.max(t,edgeWidth(horizontal,"1:"..ci));b=math.max(b,edgeWidth(horizontal,(#rows+1)..":"..ci))end
  local own={};for i=1,4 do own[i]=edge(s,i,ctx.length,cw,fs,tiers.table,0).width end
  offT,offR,offB,offL=t/2-own[1],r/2-own[2],b/2-own[3],l/2-own[4]
 end
 local function measureCell(item,w,fw,fh,kind)
  if item.node then return ctx.measure(item.node,w,ch,fw,fh,kind or false,ctx.depth+1)end
  local out={w=0,h=0,p={0,0,0,0},m={0,0,0,0},fs=fs,definiteH=fh~=nil,members={}}
  for _,member in ipairs(item.cell.members)do
   local c=ctx.measure(member,fw or w,ch,nil,nil,kind or false,ctx.depth+1);out.members[#out.members+1]=c
   out.w=math.max(out.w,c.w+c.m[2]+c.m[4])
   if c.lastBaseline then out.lastBaseline=out.h+c.m[1]+c.lastBaseline end
   out.h+=c.h+c.m[1]+c.m[3]
  end
  if fw then out.w=fw end;if fh then out.h=math.max(out.h,fh)end
  return out
 end
 local mins,maxs,pcts,specifiedW={},{},{},{}
 for i=1,count do mins[i]=0;maxs[i]=0 end
 local sideCaptions={};local sideStart,sideEnd=0,0
 for _,caption in ipairs(captions)do
  local cs=ctx.styles[caption.key];local side=cs['caption-side']
  if side=='inline-start'or side=='inline-end'then
   local auto=cs.width==nil or cs.width=='auto'
   local c=ctx.measure(caption,cw,ch,nil,nil,auto and 'max-content'or false,ctx.depth+1)
   local extent=c.w+c.m[2]+c.m[4]
   sideCaptions[#sideCaptions+1]={node=caption,c=c,side=side,offset=side=='inline-start'and sideStart or sideEnd}
   if side=='inline-start'then sideStart+=extent else sideEnd+=extent end
  end
 end
 offL+=sideStart;offR+=sideEnd
 local gutters=sx*(count+1);local available=math.max(0,cw-gutters-offL-offR)
 local forced=ctx.tableForcedWidth==true
 local definite=forced or((T.container(s)or s.display=='table-cell')and s.width~=nil and s.width~='auto'and not keywordW[s.width]);local fixed=mode=='fixed'and definite and not forced
 for i=1,count do local col=columns[i];local value=col and col.width
  if value and value~='auto'then local pct=percent(value)
   if pct then pcts[i]=math.max(pcts[i]or 0,pct)else local hint=ctx.length(value,available,fs);if hint then specifiedW[i]=math.max(specifiedW[i]or 0,hint)end end
  end
 end
 local spanning={}
 for _,item in ipairs(cells)do
  if ctx.checkpoint then ctx.checkpoint()end
  local cs=item.style;local first,last=item.col,item.col+item.colSpan-1;local cellGutters=sx*(item.colSpan-1)
  local pct=percent(cs.width);local specified
  if not pct and cs.width and cs.width~='auto'then specified=ctx.length(cs.width,available,fs);if specified and item.node then local _,_,p=ctx.info(item.node,available,ch);specified+=Ua.sizingExtra(cs,p)end end
  if fixed then
   if item.row==1 then
    if pct then local each=pct/item.colSpan;for i=first,last do if not(pcts[i]or specifiedW[i])then pcts[i]=each end end
    elseif specified then local each=math.max(0,specified-cellGutters)/item.colSpan;for i=first,last do if not(pcts[i]or specifiedW[i])then specifiedW[i]=each end end end
   end
  else
   local small=measureCell(item,available,nil,nil,'min-content');local large=measureCell(item,available,nil,nil,'max-content')
   if item.colSpan==1 then
    mins[first]=math.max(mins[first],small.w);maxs[first]=math.max(maxs[first],large.w)
    if pct then pcts[first]=math.max(pcts[first]or 0,pct)elseif specified then specifiedW[first]=math.max(specifiedW[first]or 0,specified)end
   else spanning[#spanning+1]={item=item,min=small.w-cellGutters,max=(specified and math.max(small.w,specified)or large.w)-cellGutters,pct=pct}end
  end
 end
 for i=1,count do local w=specifiedW[i];if w then mins[i]=math.max(mins[i],w);maxs[i]=math.max(mins[i],w)end end
 table.sort(spanning,function(a,b)return a.item.colSpan<b.item.colSpan end)
 for _,entry in ipairs(spanning)do local item=entry.item;local first,last=item.col,item.col+item.colSpan-1
  distribute(mins,first,last,entry.min,maxs);distribute(maxs,first,last,entry.max,maxs)
  if entry.pct then local covered,free=0,{};for i=first,last do if pcts[i]then covered+=pcts[i]else free[#free+1]=i end end;local rest=entry.pct-covered;if rest>0 and #free>0 then for _,i in ipairs(free)do pcts[i]=rest/#free end end end
 end
 for i=1,count do maxs[i]=math.max(maxs[i],mins[i])end
 local pctTotal=0;for i=1,count do if pcts[i]then pctTotal+=pcts[i]end end
 if pctTotal>1 then for i=1,count do if pcts[i]then pcts[i]/=pctTotal end end;pctTotal=1 end
 local captionMin,captionMax=0,0
 for _,caption in ipairs(captions)do
  local small=ctx.measure(caption,available,ch,nil,nil,'min-content',ctx.depth+1);local large=ctx.measure(caption,available,ch,nil,nil,'max-content',ctx.depth+1)
  captionMin=math.max(captionMin,small.w+small.m[2]+small.m[4]);captionMax=math.max(captionMax,large.w+large.m[2]+large.m[4])
 end
 local minSum,maxSum=sum(mins),sum(maxs);local wantMax=maxSum
 local nonPctMax=0;for i=1,count do if pcts[i]then if pcts[i]>0 then wantMax=math.max(wantMax,maxs[i]/pcts[i])end else nonPctMax+=maxs[i]end end
 if pctTotal>0 and pctTotal<1 then wantMax=math.max(wantMax,nonPctMax/(1-pctTotal))end
 local width
 if definite then width=available
 elseif intrinsic=='min-content'then width=math.max(minSum,captionMin-gutters)
 elseif intrinsic=='max-content'then width=math.max(wantMax,captionMax-gutters)
 else width=math.max(minSum,captionMin-gutters,math.min(available,math.max(wantMax,captionMax-gutters)))end
 local sizes={}
 if fixed then
  local used,unset=0,{}
  for i=1,count do if pcts[i]then sizes[i]=pcts[i]*width;used+=sizes[i]elseif specifiedW[i]then sizes[i]=specifiedW[i];used+=sizes[i]else sizes[i]=0;unset[#unset+1]=i end end
  local free=math.max(0,width-used)
  if #unset>0 then for _,i in ipairs(unset)do sizes[i]=free/#unset end
  elseif free>0 then local total=sum(sizes);for i=1,count do sizes[i]+=free*(total>0 and sizes[i]/total or 1/count)end end
 else
  for i=1,count do sizes[i]=mins[i]end
  local pctW,hasOther=0,false
  for i=1,count do if pcts[i]then sizes[i]=math.max(mins[i],pcts[i]*width);pctW+=sizes[i]else hasOther=true end end
  if not hasOther then local total=sum(sizes);if total>0 and width>total then for i=1,count do sizes[i]*=width/total end end
  else
   local remaining=width-pctW;local minRest,maxRest=0,0
   for i=1,count do if not pcts[i]then minRest+=mins[i];maxRest+=maxs[i]end end
   if remaining<minRest then
    local slack=0;for i=1,count do if pcts[i]then slack+=sizes[i]-mins[i]end end
    local take=math.min(slack,minRest-remaining)
    if take>0 then for i=1,count do if pcts[i]then sizes[i]-=take*(sizes[i]-mins[i])/slack end end end
   elseif remaining>=maxRest then
    for i=1,count do if not pcts[i]then sizes[i]=maxs[i]end end
    local extra=remaining-maxRest;local pool={}
    for i=1,count do if not pcts[i]and not specifiedW[i]then pool[#pool+1]=i end end
    if #pool==0 then for i=1,count do if not pcts[i]then pool[#pool+1]=i end end end
    local weight=0;for _,i in ipairs(pool)do weight+=maxs[i]end
    for _,i in ipairs(pool)do sizes[i]+=extra*(weight>0 and maxs[i]/weight or 1/#pool)end
   else
    local need=maxRest-minRest;local ratio=need>0 and(remaining-minRest)/need or 0
    for i=1,count do if not pcts[i]then sizes[i]=mins[i]+(maxs[i]-mins[i])*ratio end end
   end
  end
 end
 for i=1,count do if hiddenColumns[i]then sizes[i]=0 end end
 local starts,ends={},{};local at=sx
 for i,v in ipairs(sizes)do starts[i]=at;ends[i]=at+v;at+=v+(hiddenColumns[i]and 0 or sx)end
 local tableW=at;local outerW=tableW+offL+offR
 local rowHeights={}
 local rowPercents,rowFixed={},{}
 for i,r in ipairs(rows)do
  local rs=r.node and ctx.styles[r.node.key];local value=rs and rs.height;local pct=percent(value);rowHeights[i]=0
  if pct then rowPercents[i]=pct
  elseif value~=nil and value~='auto'then rowHeights[i]=ctx.length(value,ch,fs)or 0;rowFixed[i]=true end
  if hiddenRows[i]then rowHeights[i]=0 end
 end
 local rowSpanning,baselines={},{}
 local function hasText(n)
  if(n.text or''):match('%S')then return true end
  for _,child in ipairs(n.children or EMPTY)do if hasText(child)then return true end end
  return false
 end
 local function firstBaseline(item)
  local c=item.measured;local lh=item.style._lineHeight or c.fs*1.25;local textual=c.lastBaseline~=nil
  if not textual then if item.node then textual=hasText(item.node)else for _,member in ipairs(item.cell.members)do if hasText(member)then textual=true;break end end end end
  if textual then return math.min(c.h,c.p[1]+lh*.8)end
  return math.max(0,c.h-c.p[3])
 end
 for _,item in ipairs(cells)do
  local widthCell=ends[item.col+item.colSpan-1]-starts[item.col]
  item.measured=measureCell(item,widthCell,widthCell,nil)
  if not item.hidden then
   local va=item.style['vertical-align']
   if va==nil or va=='baseline'or va=='sub'or va=='super'or va=='text-top'or va=='text-bottom'then local b=firstBaseline(item);if b then item.baseline=b;local list=baselines[item.row];if not list then list={};baselines[item.row]=list end;list[#list+1]=item end end
   if item.rowSpan==1 then
    rowHeights[item.row]=math.max(rowHeights[item.row],item.measured.h)
    local pct=percent(item.style.height);if pct then rowPercents[item.row]=math.max(rowPercents[item.row]or 0,pct)end
   else rowSpanning[#rowSpanning+1]=item end
  end
 end
 for ri,list in pairs(baselines)do
  local rowBaseline=0;for _,item in ipairs(list)do rowBaseline=math.max(rowBaseline,item.baseline)end
  for _,item in ipairs(list)do item.shift=rowBaseline-item.baseline;if item.rowSpan==1 then rowHeights[ri]=math.max(rowHeights[ri],item.shift+item.measured.h)end end
 end
 table.sort(rowSpanning,function(a,b)return a.rowSpan<b.rowSpan end)
 for _,item in ipairs(rowSpanning)do distribute(rowHeights,item.row,item.row+item.rowSpan-1,item.measured.h+(item.shift or 0)-sy*(item.rowSpan-1),rowHeights)end
 local topCaptions,bottomCaptions={},{};local topH,bottomH=0,0
 for _,caption in ipairs(captions)do
  local cs=ctx.styles[caption.key];local side=cs['caption-side']or'top';assert(captionTop[side]or captionBottom[side],'caption-side aceita top, bottom, block-start, block-end, inline-start ou inline-end.')
  if side=='inline-start'or side=='inline-end'then continue end
  local wrapW=outerW+pad[2]+pad[4];local fixedW=cs.width==nil or cs.width=='auto'
  local c=ctx.measure(caption,wrapW,ch,fixedW and math.max(0,wrapW-(ctx.length(cs['margin-left'],wrapW,fs)or 0)-(ctx.length(cs['margin-right'],wrapW,fs)or 0))or nil,nil,false,ctx.depth+1)
  local free=math.max(0,wrapW-c.w-c.m[2]-c.m[4]);local autoLeft=cs['margin-left']=='auto';local autoRight=cs['margin-right']=='auto'
  local item={node=caption,c=c,x=c.m[4]+(autoLeft and free/(autoRight and 2 or 1)or 0)-pad[4]}
  if captionBottom[side]then item.y=bottomH+c.m[1];bottomH+=c.h+c.m[1]+c.m[3];bottomCaptions[#bottomCaptions+1]=item
  else item.y=topH+c.m[1]-pad[1];topH+=c.h+c.m[1]+c.m[3];topCaptions[#topCaptions+1]=item end
 end
 if definiteH and #rows>0 then
  local shown=0;for i=1,#rows do if not hiddenRows[i]then shown+=1 end end
  local target=ch-topH-bottomH-sy*(shown+1)-offT-offB
  for i,pct in pairs(rowPercents)do if not hiddenRows[i]then rowHeights[i]=math.max(rowHeights[i],pct*target)end end
  local extra=target-sum(rowHeights)
  if extra>0 then
   local pools={{},{},{}}
   for i=1,#rows do if not hiddenRows[i]then local pool=pools[rowPercents[i]and 2 or rowFixed[i]and 3 or 1];pool[#pool+1]=i end end
   for _,pool in ipairs(pools)do
    if #pool>0 then
     local weight=0;for _,i in ipairs(pool)do weight+=rowHeights[i]end
     for _,i in ipairs(pool)do rowHeights[i]+=extra*(weight>0 and rowHeights[i]/weight or 1/#pool)end
     break
    end
   end
  end
 end

 local rowStarts,rowEnds={},{};at=topH+sy+offT
 for i,h in ipairs(rowHeights)do rowStarts[i]=at;rowEnds[i]=at+h;at+=h+(hiddenRows[i]and 0 or sy)end
 local tableBottom=at+offB;local totalH=tableBottom+bottomH;local items={}
 local tableBaseline;if #rows>0 then local list=baselines[1];if list then local b=0;for _,item in ipairs(list)do b=math.max(b,item.baseline)end;tableBaseline=rowStarts[1]+b else tableBaseline=rowEnds[1]end end
 for _,item in ipairs(topCaptions)do items[#items+1]=item end
 local bindings,groupPlans,rowPlans={},{},{}
 for _,group in ipairs(groupNodes)do groupPlans[group.key]={items={},first=math.huge,last=0,node=group}end
 for ri,r in ipairs(rows)do
  local plan={items={},usedW=math.max(0,tableW-2*sx),usedH=rowHeights[ri]};rowPlans[ri]=plan
  if r.node then bindings[r.node.key]=plan end
  local group=r.parent and groupPlans[r.parent.key];if group then group.first=math.min(group.first,ri);group.last=math.max(group.last,ri)end
 end
 local gridTop,gridBottom=topH+sy,#rows>0 and rowEnds[#rows]or topH+sy
 if #rows>0 then
  for _,entry in ipairs(columnNodes)do
   if entry.last>=entry.first then
    local x=starts[entry.first];local w=ends[entry.last]-x
    local item={node=entry.node,c=box(w,gridBottom-gridTop,fs),x=x+offL,y=gridTop,collapsedBorders=collapse,hidden=collapsed(entry.style)}
    items[#items+1]=item
    if entry.group then
     local plan={items={},usedW=w,usedH=gridBottom-gridTop};bindings[entry.node.key]=plan
     for _,col in ipairs(entry.inner)do plan.items[#plan.items+1]={node=col.node,c=box(ends[col.last]-starts[col.first],gridBottom-gridTop,fs),x=starts[col.first]-x,y=0,collapsedBorders=collapse,hidden=item.hidden or collapsed(col.style)}end
    end
   end
  end
 end
 local function emit(item,list,baseX,baseY,c)
  if item.node then
   local cs=item.style;local empty=(item.node.text or''):match('^%s*$')~=nil and #item.node.children==0
   list[#list+1]={node=item.node,c=c,x=baseX,y=baseY,collapsedCell=collapse,emptyCellHidden=not collapse and empty and cs['empty-cells']=='hide',hidden=item.hidden,shift=item.shift}
  else
   local y=baseY+(item.shift or 0)
   for k,member in ipairs(item.cell.members)do local mc=c.members[k];list[#list+1]={node=member,c=mc,x=baseX+mc.m[4],y=y+mc.m[1],hidden=item.hidden};y+=mc.h+mc.m[1]+mc.m[3]end
  end
 end
 for _,item in ipairs(cells)do
  local ri=item.row;local widthCell=ends[item.col+item.colSpan-1]-starts[item.col];local heightCell=rowEnds[ri+item.rowSpan-1]-rowStarts[ri]
  local c=measureCell(item,widthCell,widthCell,heightCell)
  local va=item.style['vertical-align'];local shift
  if va=='middle'then shift=(heightCell-item.measured.h)/2 elseif va=='bottom'then shift=heightCell-item.measured.h elseif va=='top'then shift=0 else shift=item.shift or 0 end
  if item.node and #item.node.children==0 then shift=0 end
  item.shift=math.max(0,shift)
  if item.owner.node then emit(item,rowPlans[ri].items,starts[item.col]-sx,0,c)
  else local group=item.owner.parent and groupPlans[item.owner.parent.key];emit(item,group and group.items or items,starts[item.col]+(group and 0 or offL),rowStarts[ri]-(group and rowStarts[group.first]or 0),c)end
 end
 for ri,r in ipairs(rows)do if r.node then
  local item={node=r.node,c=box(math.max(0,tableW-2*sx),rowHeights[ri],fs),x=sx+offL,y=rowStarts[ri],collapsedBorders=collapse,hidden=hiddenRows[ri]}
  local group=r.parent and groupPlans[r.parent.key];if group then item.x=0;item.y-=rowStarts[group.first];group.items[#group.items+1]=item else items[#items+1]=item end
 end end
 for _,group in ipairs(groupNodes)do local plan=groupPlans[group.key];if plan.last>0 then
  local h=rowEnds[plan.last]-rowStarts[plan.first];plan.usedW=math.max(0,tableW-2*sx);plan.usedH=h;bindings[group.key]=plan
  items[#items+1]={node=group,c=box(plan.usedW,h,fs),x=sx+offL,y=rowStarts[plan.first],collapsedBorders=collapse,hidden=collapsed(ctx.styles[group.key])}
 end end
 for _,item in ipairs(bottomCaptions)do item.y+=tableBottom+pad[3];items[#items+1]=item end
 for _,entry in ipairs(sideCaptions)do
  local c=entry.c;local x=entry.side=='inline-start'and entry.offset+c.m[4]-pad[4]or outerW+pad[2]-sideEnd+entry.offset+c.m[4]
  items[#items+1]={node=entry.node,c=c,x=x,y=topH+c.m[1]-pad[1]}
 end
 local borders={}
 if resolved then
  local function key(k)local ri,ci=k:match("^(%d+):(%d+)$");return tonumber(ri),tonumber(ci)end
  for k,entry in pairs(resolved.vertical)do local ri,ci=key(k);local e=entry.edge
   if e.width>0 and e.style~="hidden"and e.style~="none"and not hiddenRows[ri]then borders[#borders+1]={x=(ci>count and ends[count]or starts[ci])+offL,y=rowStarts[ri],w=0,h=rowHeights[ri],border=e}end
  end
  for k,entry in pairs(resolved.horizontal)do local ri,ci=key(k);local e=entry.edge
   if e.width>0 and e.style~="hidden"and e.style~="none"and not hiddenColumns[ci]then borders[#borders+1]={x=starts[ci]+offL,y=ri>#rows and rowEnds[#rows]or rowStarts[ri],w=sizes[ci],h=0,border=e}end
  end
  table.sort(borders,function(a,b)if(a.h==0)~=(b.h==0)then return a.h==0 end;if a.h==0 then if a.y~=b.y then return a.y<b.y end;return a.x<b.x end;if a.x~=b.x then return a.x<b.x end;return a.y<b.y end)
  local merged={};local function same(a,b)return a.border.width==b.border.width and a.border.color==b.border.color and a.border.style==b.border.style end
  for _,seg in ipairs(borders)do local last=merged[#merged]
   if last and same(last,seg)and((seg.h==0 and last.h==0 and math.abs(last.y-seg.y)<1e-3 and math.abs(last.x+last.w-seg.x)<1e-3)or(seg.w==0 and last.w==0 and math.abs(last.x-seg.x)<1e-3 and math.abs(last.y+last.h-seg.y)<1e-3))then
    if seg.h==0 then last.w=seg.x+seg.w-last.x else last.h=seg.y+seg.h-last.y end
   else merged[#merged+1]=seg end
  end
  borders=merged
  table.sort(borders,function(a,b)if a.y~=b.y then return a.y<b.y end;if a.x~=b.x then return a.x<b.x end;return a.h<b.h end)
 end
 local signature={outerW,totalH,tostring(collapse),sx,sy};for _,border in ipairs(borders)do signature[#signature+1]=border.x..','..border.y..','..border.w..','..border.h..':'..border.border.width..':'..border.border.color..':'..border.border.style end
 local z=node.order or 0;for _,item in ipairs(cells)do if item.node then z=math.max(z,item.node.order or 0)else for _,member in ipairs(item.cell.members)do z=math.max(z,member.order or 0)end end end
 local result={items=items,usedW=outerW,usedH=totalH,tableBorders=borders,tableSignature=table.concat(signature,'|'),columnSizes=sizes,rowSizes=rowHeights,tableCollapse=collapse,bindings=bindings,tableBorderZ=z*100+1,columnCount=count,rowCount=#rows,captionTop=topH,captionBottom=bottomH,captionLeft=sideStart,captionRight=sideEnd,baseline=tableBaseline}
 T.bind(result,ctx.tableBindings);return result
end
function T.bind(plan,destination)if destination then for key,binding in pairs(plan.bindings or{})do destination[key]=binding end end end
return T
