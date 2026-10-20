local U=require(script.Parent.Util)
local T=require(script.Parent.LayoutTracks)
local P=require(script.Parent.LayoutProperties)
local Subgrid=require(script.Parent.RuntimeManifest).optional('LayoutSubgrid')
local G={}
local function integer(s)
 local n=tonumber(s);assert(n and n%1==0 and n~=0 and math.abs(n)<=T.LIMIT,'Linha grid deve ser inteira, não zero, entre -512 e 512.');return n
end
local function lineSpec(value)
 if value==nil or value=='auto'then return {}end
 local out={};for _,token in ipairs(U.split(tostring(value),' '))do
  if token=='span'then assert(not out.span,'span repetido.');out.span=true
  elseif tonumber(token)then assert(not out.number,'Linha grid repetida.');out.number=integer(token)
  else assert(not out.name and token:match('^[%a_%-][%w_%-]*$'),'Nome de linha grid inválido.');out.name=token end
 end
 assert(out.name or out.number,'Linha grid incompleta.')
 if out.span then assert(not out.number or out.number>0,'span precisa de inteiro positivo.')end
 return out
end
local function findNamed(name,n,maps,explicit)
 local list=maps[name]or {};n=n or 1
 if n>0 then return list[n]or explicit+1+math.max(0,n-#list)end
 return list[#list+n+1]or 1+math.min(0,n+#list)
end
local function resolved(spec,maps,explicit,edge)
 if spec.span then return nil end
 if spec.name then
  local name=spec.name
  if not maps[name]and maps[name..'-'..edge]then name=name..'-'..edge end
  return findNamed(name,spec.number,maps,explicit)
 end
 if spec.number then return spec.number>0 and spec.number or explicit+2+spec.number end
 return nil
end
local function spanEnd(start,spec,maps,explicit,direction)
 local count=spec.number or 1
 if not spec.name then return start+direction*count end
 local list=maps[spec.name]or {};local at=start
 for _=1,T.LIMIT*2 do
  at+=direction;local match=at<1 or at>explicit+1
  if not match then for _,v in ipairs(list)do if v==at then match=true;break end end end
  if match then count-=1;if count==0 then return at end end
 end
 error('span nomeado excede o limite de tracks.',0)
end
local function axis(startValue,endValue,maps,explicit)
 local a,b=lineSpec(startValue),lineSpec(endValue)
 if a.span and b.span then b={}end
 local start,finish=resolved(a,maps,explicit,'start'),resolved(b,maps,explicit,'end')
 if start and finish then
  if start==finish then finish=start+1 elseif start>finish then start,finish=finish,start end
 elseif start then finish=b.span and spanEnd(start,b,maps,explicit,1)or start+1
 elseif finish then start=a.span and spanEnd(finish,a,maps,explicit,-1)or finish-1 end
 return start,start and finish-start or(a.span and a.number or b.span and b.number or 1)
end
local function lineAliases(maps,name,a,b)
 maps[name..'-start']=maps[name..'-start']or{a};maps[name..'-end']=maps[name..'-end']or{b}
end
function G.plan(node,flow,cw,ch,definiteH,ctx)
 local s=ctx.styles[node.key];local fs=select(2,ctx.info(node,cw,ch))
 local function lx(v)return ctx.length(v,cw,fs)end
 local function ly(v)return ctx.length(v,ch,fs)end
 local gx=math.max(0,lx(s['column-gap'])or 0);local gy=math.max(0,lx(s['row-gap'])or 0)
 local ast=s._gridTracks or{}
  
 local intrinsic=ctx.intrinsic;if intrinsic~='min-content'and intrinsic~='max-content'and intrinsic~='fit-content'then intrinsic=nil end
 local availableW=if intrinsic then nil else cw
 local colDefs,colNames=T.expand(ast.columns or T.parse(s['grid-template-columns']or'none'),availableW,gx,lx)
 local rowDefs,rowNames=T.expand(ast.rows or T.parse(s['grid-template-rows']or'none'),definiteH and ch or nil,gy,ly)
 local shared=ctx.subgridBindings and ctx.subgridBindings[node.key]
 local _,_,padding=ctx.info(node,cw,ch)
 local sharedColumns=shared and shared.columns;local sharedRows=shared and shared.rows
 if sharedColumns then colDefs,colNames,gx=Subgrid.definitions(ast.columns,sharedColumns,gx,s._important and s._important['column-gap']~=nil and s['column-gap']~='normal',padding[4],padding[2])end
 if sharedRows then rowDefs,rowNames,gy=Subgrid.definitions(ast.rows,sharedRows,gy,s._important and s._important['row-gap']~=nil and s['row-gap']~='normal',padding[1],padding[3])end
 local areas,areaRows,areaCols=T.areas(s['grid-template-areas'])
 local autoCol=T.expand(ast.autoColumns or T.parse(s['grid-auto-columns']or'auto'),availableW,gx,lx)
 local autoRow=T.expand(ast.autoRows or T.parse(s['grid-auto-rows']or'auto'),definiteH and ch or nil,gy,ly)
 assert(#autoCol>0 and #autoRow>0,'grid-auto-rows/columns precisam de tracks.')
 local function fill(defs,n,pattern)
  while #defs<n do defs[#defs+1]=table.clone(pattern[(#defs)%#pattern+1])end
 end
 if not sharedColumns then fill(colDefs,areaCols,autoCol)end;if not sharedRows then fill(rowDefs,areaRows,autoRow)end
 for name,a in pairs(areas)do lineAliases(colNames,name,a.c1,a.c2);lineAliases(rowNames,name,a.r1,a.r2)end
 local explicitCols,explicitRows=#colDefs,#rowDefs
 local mode=s['grid-auto-flow']or'row';local direction,dense='row',false;local seen={}
 for _,word in ipairs(U.split(mode,' '))do
  assert((word=='row'or word=='column'or word=='dense')and not seen[word],'grid-auto-flow inválido.')
  if word=='dense'then dense=true else assert(not seen.axis,'grid-auto-flow tem dois eixos.');direction=word;seen.axis=true end;seen[word]=true
 end
 local items={};local minRow,minCol,maxRow,maxCol=1,1,math.max(1,#rowDefs),math.max(1,#colDefs)
 for _,child in ipairs(P.ordered(flow,ctx.styles))do
  local cs=ctx.styles[child.key];local c,csn=axis(cs['grid-column-start'],cs['grid-column-end'],colNames,explicitCols)
  local r,rsn=axis(cs['grid-row-start'],cs['grid-row-end'],rowNames,explicitRows)
  if sharedColumns then csn=math.min(csn,#colDefs);if c then c=math.clamp(c,1,#colDefs);csn=math.min(csn,#colDefs-c+1)end end
  if sharedRows then rsn=math.min(rsn,#rowDefs);if r then r=math.clamp(r,1,#rowDefs);rsn=math.min(rsn,#rowDefs-r+1)end end
  assert(csn<=T.LIMIT and rsn<=T.LIMIT,'Span grid excede 512 tracks.')
  items[#items+1]={node=child,col=c,row=r,colSpan=csn,rowSpan=rsn}
  if c then minCol=math.min(minCol,c);maxCol=math.max(maxCol,c+csn-1)else maxCol=math.max(maxCol,minCol+csn-1)end
  if r then minRow=math.min(minRow,r);maxRow=math.max(maxRow,r+rsn-1)else maxRow=math.max(maxRow,minRow+rsn-1)end
 end
 local occupied={};local attempts=0
 local function vacant(item,r,c)
  attempts+=1;assert(attempts<=262144,'Grid: orçamento de posicionamento excedido.')
  if ctx.checkpoint and attempts%64==0 then ctx.checkpoint()end
  for y=r,r+item.rowSpan-1 do local row=occupied[y];if row then for x=c,c+item.colSpan-1 do if row[x]then return false end end end end
  return true
 end
 local function occupy(item,r,c)
  if sharedColumns then c=math.clamp(c,1,#colDefs-item.colSpan+1)end
  if sharedRows then r=math.clamp(r,1,#rowDefs-item.rowSpan+1)end
  item.row,item.col,item.placed=r,c,true
  minRow=math.min(minRow,r);minCol=math.min(minCol,c);maxRow=math.max(maxRow,r+item.rowSpan-1);maxCol=math.max(maxCol,c+item.colSpan-1)
  assert(maxRow-minRow+1<=T.LIMIT and maxCol-minCol+1<=T.LIMIT,'Grid implícito excede 512 tracks.')
  for y=r,r+item.rowSpan-1 do occupied[y]=occupied[y]or{};for x=c,c+item.colSpan-1 do occupied[y][x]=true end end
 end
 for _,item in ipairs(items)do if item.row and item.col then occupy(item,item.row,item.col)end end
 local column=direction=='column'
 local function major(item)if column then return item.col else return item.row end end
 local function minor(item)if column then return item.row else return item.col end end
 local function coords(a,b)return column and b or a,column and a or b end
 local function minimumMinor()return column and minRow or minCol end
 local function maximumMinor()return column and maxRow or maxCol end
 local function minorSpan(item)return column and item.rowSpan or item.colSpan end
 local lockedCursors={}
 for _,item in ipairs(items)do if not item.placed and major(item)then
  local a=major(item);local b=dense and minimumMinor()or lockedCursors[a]or minimumMinor()
  while true do local r,c=coords(a,b);if vacant(item,r,c)then occupy(item,r,c);lockedCursors[a]=b+minorSpan(item);break end;b+=1 end
 end end
 local cursorA=column and minCol or minRow;local cursorB=minimumMinor()
 for _,item in ipairs(items)do if not item.placed then
  local a=dense and(column and minCol or minRow)or cursorA;local b=dense and minimumMinor()or cursorB
  local fixed=minor(item)
  if fixed then if not dense and fixed<b then a+=1 end;b=fixed end
  while true do
   if not fixed and b+minorSpan(item)-1>maximumMinor()then b=minimumMinor();a+=1 end
   local r,c=coords(a,b)
   if vacant(item,r,c)or(sharedRows and r>#rowDefs)or(sharedColumns and c>#colDefs)then occupy(item,r,c);cursorA=a;cursorB=b+minorSpan(item);break end
   if fixed then a+=1 else b+=1 end
  end
 end end
 local function extend(defs,lo,hi,pattern)
  local out={}
  for coordinate=lo,hi do
   local def=defs[coordinate]
   if not def then local index=coordinate<1 and((coordinate-1)%#pattern+1)or((coordinate-#defs-1)%#pattern+1);def=pattern[index]end
   out[#out+1]=table.clone(def)
  end
  return out
 end
 colDefs=extend(colDefs,minCol,maxCol,autoCol);rowDefs=extend(rowDefs,minRow,maxRow,autoRow)
 for _,item in ipairs(items)do item.col=item.col-minCol+1;item.row=item.row-minRow+1 end
 local function collapse(defs,isColumn)
  for i,def in ipairs(defs)do if def.autoFit then
   local used=false;for _,item in ipairs(items)do local first=isColumn and item.col or item.row;local span=isColumn and item.colSpan or item.rowSpan;if i>=first and i<first+span then used=true;break end end
   def.collapsed=not used
  end end
 end
 collapse(colDefs,true);collapse(rowDefs,false)
 local widthContributions={}
 for _,item in ipairs(items)do
  if ctx.bindSubgrid then ctx.bindSubgrid(item.node,Subgrid.binding(item,ctx.styles,nil,nil,colNames,rowNames,minCol,minRow,gx,gy))end
  local small=ctx.measure(item.node,cw,ch,nil,nil,'min-content',ctx.depth+1)
  local large=ctx.measure(item.node,cw,ch,nil,nil,'max-content',ctx.depth+1)
  local contributions=ctx.subgridContributions and ctx.subgridContributions[item.node.key]
  if Subgrid.is(ctx.styles[item.node.key],'columns')and contributions then
   Subgrid.contribute(widthContributions,contributions.columns,item.col,item.colSpan,small.p[4]+small.m[4],small.p[2]+small.m[2])
  else widthContributions[#widthContributions+1]={first=item.col,last=item.col+item.colSpan-1,min=small.w+small.m[2]+small.m[4],max=large.w+large.m[2]+large.m[4]}end
 end
 local justify=s['justify-content'];if not s._important or s._important['justify-content']==nil then justify='normal'end
 local cols=T.size(colDefs,widthContributions,availableW,gx,lx,justify,intrinsic)
 local rowContributions={}
 for _,item in ipairs(items)do
  if ctx.bindSubgrid then ctx.bindSubgrid(item.node,Subgrid.binding(item,ctx.styles,cols,nil,colNames,rowNames,minCol,minRow,gx,gy))end
  local cs=ctx.styles[item.node.key];local width=cols.ends[item.col+item.colSpan-1]-cols.starts[item.col]
  local _,_,_,m=ctx.info(item.node,width,ch)
  local align=cs['justify-self'];if not align or align=='auto'then align=s['justify-items']or'stretch'end
  local force=P.isAuto(cs.width)and(align=='stretch'or align=='normal')and math.max(0,width-m[2]-m[4])or nil
  local c=ctx.measure(item.node,width,ch,force,nil,force==nil,ctx.depth+1)
  item.measured=c;item.areaWidth=width
  local contributions=ctx.subgridContributions and ctx.subgridContributions[item.node.key]
  if Subgrid.is(cs,'rows')and contributions then
   Subgrid.contribute(rowContributions,contributions.rows,item.row,item.rowSpan,c.p[1]+c.m[1],c.p[3]+c.m[3])
  else rowContributions[#rowContributions+1]={first=item.row,last=item.row+item.rowSpan-1,min=c.h+c.m[1]+c.m[3],max=c.h+c.m[1]+c.m[3]}end
 end
 local rows=T.size(rowDefs,rowContributions,definiteH and ch or nil,gy,ly,s['align-content']or'normal')
 local function alignOffset(value,free,beforeAuto,afterAuto)
  free=math.max(0,free)
  if beforeAuto or afterAuto then return beforeAuto and free/(afterAuto and 2 or 1)or 0 end
  if value=='center'then return free/2 elseif value=='end'or value=='flex-end'or value=='self-end'then return free end
  assert(value=='stretch'or value=='normal'or value=='start'or value=='flex-start'or value=='self-start','Alinhamento de item grid inválido: '..tostring(value));return 0
 end
 for _,item in ipairs(items)do
  local cs=ctx.styles[item.node.key];local c=item.measured
  local width=item.areaWidth;local height=rows.ends[item.row+item.rowSpan-1]-rows.starts[item.row]
  local ax=cs['justify-self'];if not ax or ax=='auto'then ax=s['justify-items']or'stretch'end
  local ay=cs['align-self'];if not ay or ay=='auto'then ay=s['align-items']or'stretch'end
  local fw=P.isAuto(cs.width)and(ax=='stretch'or ax=='normal')and cs['margin-left']~='auto'and cs['margin-right']~='auto'and math.max(0,width-c.m[2]-c.m[4])or nil
  local fh=P.isAuto(cs.height)and(ay=='stretch'or ay=='normal')and cs['margin-top']~='auto'and cs['margin-bottom']~='auto'and math.max(0,height-c.m[1]-c.m[3])or nil
  if ctx.bindSubgrid then ctx.bindSubgrid(item.node,Subgrid.binding(item,ctx.styles,cols,rows,colNames,rowNames,minCol,minRow,gx,gy))end
  c=ctx.measure(item.node,width,height,fw,fh,fw==nil,ctx.depth+1)
  item.c=c;item.x=cols.starts[item.col]+c.m[4]+alignOffset(ax,width-c.w-c.m[2]-c.m[4],cs['margin-left']=='auto',cs['margin-right']=='auto')
  item.y=rows.starts[item.row]+c.m[1]+alignOffset(ay,height-c.h-c.m[1]-c.m[3],cs['margin-top']=='auto',cs['margin-bottom']=='auto')
 end
 if ctx.subgridContributions then ctx.subgridContributions[node.key]={columns=widthContributions,rows=rowContributions}end
 return {items=items,usedW=cols.total,usedH=rows.total,columns=cols,rows=rows,columnNames=colNames,rowNames=rowNames,minCol=minCol,minRow=minRow,areas=areas,subgridColumns=sharedColumns~=nil,subgridRows=sharedRows~=nil}
end
return G
