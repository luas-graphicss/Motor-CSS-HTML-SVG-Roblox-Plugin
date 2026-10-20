local U=require(script.Parent.Util)
local InlineText=require(script.Parent.InlineText)
local Grid=require(script.Parent.LayoutGrid)
local Subgrid=require(script.Parent.RuntimeManifest).optional('LayoutSubgrid')
local Tables=require(script.Parent.RuntimeManifest).optional('LayoutTable')
local Shapes=require(script.Parent.CssShapes)
local Flow=require(script.Parent.LayoutFlow)
local Flex=require(script.Parent.LayoutFlex)
local Position=require(script.Parent.LayoutPosition)
local Containment=require(script.Parent.CssContainment)
local Properties=require(script.Parent.LayoutProperties)
local Writing=require(script.Parent.WritingLayout)
local Ua=require(script.Parent.UserAgentStyles)
local Boxes=require(script.Parent.InlineBoxes)
local Overflow=require(script.Parent.Overflow)
local Bars=require(script.Parent.Scrollbars)
local L={VERSION=2}
local TextService=game:GetService('TextService')
local clear=table.clear
local paddingKeys=table.freeze({'padding-top','padding-right','padding-bottom','padding-left'})
local marginKeys=table.freeze({'margin-top','margin-right','margin-bottom','margin-left'})
local minKeys=table.freeze({width='min-width',height='min-height'})
local maxKeys=table.freeze({width='max-width',height='max-height'})
local directions=table.freeze({row=true,column=true,['row-reverse']=true,['column-reverse']=true})
local displays=table.freeze({block=true,flex=true,grid=true,inline=true,['inline-block']=true,['list-item']=true,table=true,['inline-table']=true,['table-row']=true,['table-cell']=true,['table-row-group']=true,['table-header-group']=true,['table-footer-group']=true,['table-caption']=true,['table-column']=true,['table-column-group']=true,ruby=true,['ruby-base']=true,['ruby-text']=true,['ruby-base-container']=true,['ruby-text-container']=true})
local positions=table.freeze({relative=true,absolute=true,static=true,sticky=true,fixed=true})
local arrayPool={}
local function takeArray()
 local n=#arrayPool;if n==0 then return {}end
 local a=arrayPool[n];arrayPool[n]=nil;return a
end
local function releaseArray(a)
 local count=#a;clear(a)
 if count<=512 and #arrayPool<96 then arrayPool[#arrayPool+1]=a end
end
local function releaseLines(lines)
 for _,line in ipairs(lines)do releaseArray(line.items)end
 releaseArray(lines)
end
local function repeatColumn(n,col)
 n=tonumber(n);assert(n>=1 and n<=12,'Grid: repeat entre 1 e 12.');return string.rep(col..' ',n)
end
function L.solve(root,styles,vw,vh,objects,options)
 options=options or {};local checkpoint=options.checkpoint
 local shapeImage=options.shapeImage or(options.doc and Shapes.resolver(options.doc,checkpoint))
 local boxes=options.previous and U.copy(options.previous)or {}
 local metrics={};local measureCache=options.memo or {};local measureCount=0
 if options.memo then for key in pairs(options.dirty or {})do if measureCache[key]then clear(measureCache[key])end end end
 local flowCache,infoCache={},{}
 local parents,positionedSubtrees={},{}
 local function index(node,parent)
  parents[node.key]=parent;local placement=styles[node.key].position;local positioned=placement=='absolute'or placement=='fixed'
  for _,child in ipairs(node.children)do positioned=index(child,node)or positioned end
  positionedSubtrees[node.key]=positioned;return positioned
 end
 index(root,nil)
 local advancedPlans={grid={},flow={},table={}};local tableBindings={};local cellShifts={};local borderOverrides={}
 local function setBorders(node,widths)
  local old=borderOverrides[node.key]
  if old==nil and widths==nil then return end
  if old and widths and old[1]==widths[1]and old[2]==widths[2]and old[3]==widths[3]and old[4]==widths[4]then return end
  borderOverrides[node.key]=widths;infoCache[node.key]=nil
  if measureCache[node.key]then clear(measureCache[node.key])end
 end
 local function tableParent(node)local parent=parents[node.key];return parent and styles[parent.key]end
 local function tabular(node,s)return Tables.active(s)or Tables.orphan(s,tableParent(node))end
 local subgridBindings,subgridContributions={},{}
 local hasSubgrid,hasTables=false,false;for _,s in pairs(styles)do if Subgrid.is(s,'columns')or Subgrid.is(s,'rows')then hasSubgrid=true end;if Tables.related(s)then hasTables=true end end
 if hasSubgrid or hasTables then for _,memo in pairs(measureCache)do clear(memo)end end
 local inlineModes,inlinePlans={},{}
 local function inlineEnabled(node)
  if inlineModes[node.key]==nil then inlineModes[node.key]=InlineText.enabled(node,styles)end;return inlineModes[node.key]
 end
 local inlineBands={}
 local function setBand(key,fn)
  inlineBands[key]=fn
  if measureCache[key]then clear(measureCache[key])end
  inlinePlans[key]=nil
 end
 local function inlinePlan(node,w,h,intrinsic,env)
  local variants=inlinePlans[node.key];if not variants then variants={};inlinePlans[node.key]=variants end
  local key=tostring(w)..':'..tostring(h)..':'..tostring(intrinsic);local plan=variants[key]
  if not plan then plan=InlineText.layout(node,styles,objects,w,h,vw,vh,checkpoint,options.hyphenation,options.segmentation,intrinsic,env);variants[key]=plan end
  return plan
 end
 local nowrapPlans={};local nowrapDirect,nowrapCacheHits=0,0
 local function copyLines(lines)
  local out=takeArray()
  for i,line in ipairs(lines)do
   local copy=table.clone(line);copy.items=takeArray()
   for j,item in ipairs(line.items)do copy.items[j]=table.clone(item)end;out[i]=copy
  end
  return out
 end
 local function length(v,base,font)
  if v=='content'or v=='min-content'or v=='max-content'or v=='fit-content'or v=='normal'then return nil end
  return U.length(v,base,vw,vh,font)
 end
 local function info(node,pw,ph)
  local s=styles[node.key];local variants=infoCache[node.key]
  if not variants then variants={};infoCache[node.key]=variants end
  local key=tostring(pw)..':'..tostring(ph);local cached=variants[key];if cached then return s,cached[1],cached[2],cached[3]end
  local fs=math.clamp(length(s['font-size'],16,16) or 16,1,160)
  local parent=parents[node.key];local ps=parent and styles[parent.key]or s
  local base=Writing.axes(ps).vertical and ph or pw
  local border=math.max(0,length(s['border-width'],base,fs)or 0)
  if s['border-style']=='none'or s['border-style']=='hidden'then border=0 end
  local p,m=table.create(4),table.create(4)
  local override=borderOverrides[node.key];local collapsedTable=s['border-collapse']=='collapse'and Tables.container(s)
  for i=1,4 do p[i]=(collapsedTable and 0 or math.max(0,length(s[paddingKeys[i]],base,fs)or 0))+(override and override[i]or s._borderWidths and s._borderWidths[i]or border);m[i]=length(s[marginKeys[i]],base,fs)or 0 end
  if Overflow.container(s)then
   local gutterStart,gutterEnd=Bars.reserve(s,Bars.thickness(s))
   if gutterStart>0 or gutterEnd>0 then
    local axes=Writing.axes(s);local first,last=axes.vertical and 1 or 4,axes.vertical and 3 or 2
    if s.direction=='rtl'then first,last=last,first end
    p[first]+=gutterStart;p[last]+=gutterEnd
   end
  end
  variants[key]={fs,p,m};return s,fs,p,m
 end
 local function constrained(n,s,axis,base,fs,extra)
  extra=extra or 0
  local lo=(length(s[minKeys[axis]],base,fs) or 0)+extra;local hi=(length(s[maxKeys[axis]],base,fs)or 100000)+extra
  return math.max(0,lo,math.min(hi,n))
 end
 local function columns(s,width,gap,fs)
  local tokens=s._gridColumns
  if not tokens then
   local spec=(s['grid-template-columns']or '1fr'):gsub('repeat%(%s*(%d+)%s*,%s*([^%)]+)%)',repeatColumn)
   tokens=U.split(spec,' ')
  end
  assert(#tokens>=1 and #tokens<=12,'Grid aceita 1 a 12 colunas.')
  local sizes,fractions,total,weight=takeArray(),takeArray(),gap*(#tokens-1),0
  for i,token in ipairs(tokens)do
   local fr=type(token)=='table'and token.fr or(type(token)=='string'and tonumber(token:match('^([%d%.]+)fr$')))
   fractions[i]=fr or 0;sizes[i]=0
   if fr then assert(fr>0,'fr deve ser positivo.');weight+=fr
   else
    local size=length(type(token)=='table'and token.length or token,width,fs)
    assert(size,'Coluna inválida.');sizes[i]=math.max(0,size);total+=sizes[i]
   end
  end
  for i=1,#tokens do local fr=fractions[i];if fr>0 then sizes[i]=math.max(0,width-total)*fr/weight end end
  releaseArray(fractions);return sizes
 end
 local function textMeasure(node,s,fs,width)
  if node.hasGeneratedText then return 0,0 end
  local object=objects and objects[node.textOwnerKey or node.key]
  local text=object and (object:IsA('TextLabel') or object:IsA('TextButton') or object:IsA('TextBox')) and object.Text or node.text
  text=text or ''; if text=='' then return 0,0 end
  local wrap=not require(script.Parent.TextWrap).nowrap(s)
  if width==-1 and wrap then
   local maximum=0
   for word in text:gmatch('%S+')do maximum=math.max(maximum,InlineText.metric(word,s).X)end
   return math.ceil(maximum),math.ceil(s._lineHeight or fs*1.25)
  end
  local maxWidth=wrap and math.max(1,width) or 100000
  local widths=metrics[node.key];if not widths then widths={};metrics[node.key]=widths end
  local key=math.floor(maxWidth*10)
  local value=widths[key];if not value then value=TextService:GetTextSize(text,fs,U.font(s),Vector2.new(maxWidth,100000));widths[key]=value end
   
  local lines=math.max(1,math.floor(value.Y/math.max(fs,1)+0.5))
  return math.ceil(value.X),math.ceil(lines*(s._lineHeight or fs*1.25))
 end
 local function discardedText(child,node)
  if not child.anonymousText then return false end
  if inlineEnabled(node)and not Flow.active(styles[node.key],node.children,styles)then return false end
  return InlineText.source(child,objects,styles[child.key]):match('^%s*$')~=nil
 end
 local function flowChildren(node)
  local list=flowCache[node.key];if list then return list end
  list=takeArray();flowCache[node.key]=list
  for _,child in ipairs(node.children)do local s=styles[child.key];if s.position~='absolute'and s.position~='fixed'and s.display~='none'and not discardedText(child,node)then list[#list+1]=child end end;return list
 end
 local function packing(value,free,count,gap,stretch)
  free=math.max(0,free);local offset,extra=0,0
  if value=='center' then offset=free/2 elseif value=='flex-end' or value=='end' then offset=free
  elseif value=='space-between' then if count>1 then gap+=free/(count-1) end
  elseif value=='space-around' then if count>0 then offset=free/(count*2);gap+=free/count end
  elseif value=='space-evenly' then if count>0 then offset=free/(count+1);gap+=offset end
  elseif stretch and (value=='stretch' or value=='normal') then extra=count>0 and free/count or 0
  else assert(value=='flex-start' or value=='start' or value=='normal','Alinhamento não suportado: '..tostring(value)) end
  return offset,gap,extra
 end
 local measure,flexLines
 local function hasLineBoxes(node)
  if Boxes.replaced(node.tag)then return true end
  if node.text and node.text:match('%S')then return true end
  for _,descendant in ipairs(node.children)do
   local ds=styles[descendant.key]
   if not ds or(ds.display~='none'and hasLineBoxes(descendant))then return true end
  end
  return false
 end
 local function inlineBaseline(child,cs,c)
  if Boxes.replaced(child.tag)then return nil end
  if cs.overflow and cs.overflow~='visible'then return nil end
  if c.lastBaseline then return math.clamp(c.lastBaseline,0,c.h)end
   
  if not hasLineBoxes(child)then return nil end
  if not(InlineText.enabled(child,styles)or(child.text and child.text~=''))then return nil end
  local lh=cs._lineHeight or c.fs*1.25
  return math.max(0,c.h-c.p[3]-lh*.2)
 end
 local function inlineEnv(node,cw,ch,depth)
  return {
   band=inlineBands[node.key],
   measure=function(child,available)
    local cs=styles[child.key]
    local wanted=Properties.isAuto(cs.width)and 'fit-content'or false
    local c=measure(child,math.max(0,available or cw),ch,nil,nil,wanted,(depth or 0)+1)
    c.baseline=inlineBaseline(child,cs,c)
    return c
   end,
  }
 end
 local function bindSubgrid(node,binding)
  if not binding then return end
  local signature=Subgrid.signature(binding);local old=subgridBindings[node.key]
  if old and old.signature==signature then return end
  binding.signature=signature;subgridBindings[node.key]=binding
  local function invalidate(child)
   if measureCache[child.key]then clear(measureCache[child.key])end
   for _,cache in pairs(advancedPlans)do cache[child.key]=nil end
   local variants=nowrapPlans[child.key];if variants then for i=1,#variants,5 do releaseLines(variants[i+3])end;releaseArray(variants);nowrapPlans[child.key]=nil end
   for _,descendant in ipairs(child.children)do invalidate(descendant)end
  end
  invalidate(node)
 end
 local function advanced(kind,node,flow,cw,ch,definiteH,depth,intrinsic,forced)
  if kind=='table'and tableBindings[node.key]then return tableBindings[node.key]end
  local mode=kind=='table'and(forced and'forced'or intrinsic or false)or kind=='grid'and intrinsic or false
  local cache=advancedPlans[kind];local variants=cache[node.key]
  if not variants then variants={};cache[node.key]=variants end
  for _,entry in ipairs(variants)do if entry.w==cw and entry.h==ch and entry.definite==(definiteH==true)and entry.i==mode then if kind=='table'then Tables.bind(entry.plan,tableBindings)end;return entry.plan end end
  local ctx={styles=styles,objects=objects,measure=measure,info=info,length=length,depth=depth,checkpoint=checkpoint,subgridBindings=subgridBindings,subgridContributions=subgridContributions,bindSubgrid=bindSubgrid,tableBindings=tableBindings,setBorders=setBorders,shapeImage=shapeImage,setBand=setBand,inlineEnabled=inlineEnabled,intrinsic=if forced then false else mode,tableForcedWidth=forced==true}
  local definiteW=node==root or not Properties.isAuto(styles[node.key].width)
  local plan=Writing.plan(kind=='table'and Tables or kind=='grid'and Grid or Flow,node,flow,cw,ch,definiteH,ctx,definiteW)
  variants[#variants+1]={w=cw,h=ch,definite=definiteH==true,i=mode,plan=plan};return plan
 end
  
  
 local function flexIntrinsic(node,flow,cw,ch,depth,mode)
  local s=styles[node.key];local _,fs=info(node,cw,ch)
  local direction=s['flex-direction']or'column';local axes=Writing.axes(s)
  local logicalRow=direction:sub(1,3)=='row';local row=logicalRow~=axes.vertical
  local wrap=s['flex-wrap']or'nowrap'
  local gap=math.max(0,length(s[logicalRow and'column-gap'or'row-gap'],cw,fs)or 0)
  local sum,largest=0,0
  for _,child in ipairs(flow)do
   local cs=styles[child.key];local c=measure(child,cw,ch,nil,nil,mode,depth+1)
   local outer=c.w+c.m[2]+c.m[4]
   if row and Properties.isAuto(cs.width)then
    local basis=length(cs['flex-basis'],cw,c.fs)
    if basis and basis>0 and(mode~='min-content'or(tonumber(cs['flex-shrink'])or 1)==0)then outer=math.max(outer,basis+Ua.axisExtra(cs,c.p,true)+c.m[2]+c.m[4])end
   end
   sum+=outer;largest=math.max(largest,outer)
  end
  if not row or(mode=='min-content'and wrap~='nowrap')then return largest end
  return sum+gap*math.max(0,#flow-1)
 end
 flexLines=function(node,flow,cw,ch,definiteH,depth)
  local s=styles[node.key];local _,fs=info(node,cw,ch)
  local direction=s['flex-direction'] or 'column';assert(directions[direction],'flex-direction inválido.')
  local axes=Writing.axes(s);local logicalRow=direction:sub(1,3)=='row';local row=logicalRow~=axes.vertical;local wrap=s['flex-wrap'] or 'nowrap';assert(wrap=='nowrap' or wrap=='wrap' or wrap=='wrap-reverse','flex-wrap aceita nowrap, wrap e wrap-reverse.')
  local planVariants
  if wrap=='nowrap' then
   planVariants=nowrapPlans[node.key]
   if not planVariants then planVariants=takeArray();nowrapPlans[node.key]=planVariants end
   for i=1,#planVariants,5 do
    if planVariants[i]==cw and planVariants[i+1]==ch and planVariants[i+2]==(definiteH==true)then
     nowrapCacheHits+=1;return copyLines(planVariants[i+3]),table.clone(planVariants[i+4])
    end
   end
  end
  local gx=math.max(0,length(s['column-gap'],cw,fs) or 0);local gy=math.max(0,length(s['row-gap'],cw,fs) or 0)
  local gap=logicalRow and gx or gy;local crossGap=logicalRow and gy or gx
  local limit=row and cw or (definiteH and ch or math.huge)
  local axis=row and 'width' or 'height';local mainBase=row and cw or ch
  local lines=takeArray();local line={items=takeArray(),total=0,cross=0};table.insert(lines,line)
  for _,child in ipairs(Properties.ordered(flow,styles))do
   local cs=styles[child.key];local align=cs['align-self'];if not align or align=='auto' then align=s['align-items'] end
   local c=measure(child,cw,ch,nil,nil,row or align~='stretch',depth+1)
   local basisValue=cs['flex-basis'];local basis
   local sizing=Ua.axisExtra(cs,c.p,row)
   if basisValue=='content'or basisValue=='min-content'or basisValue=='max-content'then
    local natural=measure(child,cw,ch,not row and c.w or nil,nil,basisValue=='content'and'content'or basisValue,depth+1)
    basis=row and natural.w or natural.h
   elseif row or definiteH or not Properties.hasPercent(basisValue)then basis=length(basisValue,mainBase,c.fs);if basis then basis+=sizing end end
   if basis==nil then
    local specified=(row or definiteH or not Properties.hasPercent(cs[axis]))and length(cs[axis],mainBase,c.fs)or nil
    if specified then specified+=sizing end
    basis=specified or(row and c.w or c.h)
   end
   c.floor=row and c.p[2]+c.p[4]or c.p[1]+c.p[3];c.sizing=sizing
   c.base=math.max(0,basis);c.main=math.max(c.floor,constrained(c.base,cs,axis,mainBase,c.fs,sizing))
   c.before=row and c.m[4] or c.m[1];c.after=row and c.m[2] or c.m[3]
   c.crossBefore=row and c.m[1] or c.m[4];c.crossAfter=row and c.m[3] or c.m[2]
   c.autoBefore=cs[row and'margin-left'or'margin-top']=='auto';c.autoAfter=cs[row and'margin-right'or'margin-bottom']=='auto'
   c.crossAutoBefore=cs[row and'margin-top'or'margin-left']=='auto';c.crossAutoAfter=cs[row and'margin-bottom'or'margin-right']=='auto'
   c.grow=tonumber(cs['flex-grow'])or 0;c.shrink=tonumber(cs['flex-shrink'])or 1
   assert(c.grow>=0 and c.shrink>=0,'flex-grow/shrink não podem ser negativos.');c.node=child;c.align=align or 'stretch'
   local outer=c.main+c.before+c.after
   if wrap~='nowrap' and #line.items>0 and line.total+gap+outer>limit+0.001 then line={items=takeArray(),total=0,cross=0};table.insert(lines,line)end
   if #line.items>0 then line.total+=gap end;line.total+=outer;table.insert(line.items,c)
  end
  if #flow==0 then releaseArray(line.items);clear(lines)end
  local usedMain,usedCross=0,0
  for _,ln in ipairs(lines)do
   if limit<math.huge then
    local direct=Flex.resolve(ln.items,limit,gap,function(c,wanted)return math.max(c.floor,constrained(wanted,styles[c.node.key],axis,mainBase,c.fs,c.sizing or 0))end)
    if direct and wrap=='nowrap'then nowrapDirect+=1 end
   end
   ln.total=gap*math.max(0,#ln.items-1);ln.cross=0;local prefix=0
   for _,c in ipairs(ln.items)do
    local cs=styles[c.node.key];local re
    if row then re=measure(c.node,cw,ch,c.main,nil,false,depth+1)
    else
     local forced=Properties.isAuto(cs.width) and c.align=='stretch' and math.max(0,cw-c.crossBefore-c.crossAfter) or nil
     if wrap~='nowrap' then forced=nil end
     re=measure(c.node,cw,ch,forced,c.main,wrap~='nowrap' or c.align~='stretch',depth+1)
    end
    c.w,c.h=re.w,re.h;c.definiteH=not row and limit<math.huge or re.definiteH;c.main=row and c.w or c.h;c.cross=row and c.h or c.w
    c.prefix=prefix;prefix+=c.main+c.before+c.after
    ln.total+=c.main+c.before+c.after;ln.cross=math.max(ln.cross,c.cross+c.crossBefore+c.crossAfter)
   end
   usedMain=math.max(usedMain,ln.total);usedCross+=ln.cross
  end
  usedCross+=crossGap*math.max(0,#lines-1)
  local mainReverse=logicalRow and axes.inlineReverse or not logicalRow and axes.blockReverse
  local crossReverse=logicalRow and axes.blockReverse or not logicalRow and axes.inlineReverse
  local meta={row=row,reverse=(direction:find('reverse',1,true)~=nil)~=mainReverse,wrap=wrap,crossReverse=(wrap=='wrap-reverse')~=crossReverse,gap=gap,crossGap=crossGap,usedMain=usedMain,usedCross=usedCross,limit=limit}
  if planVariants then
   local at=#planVariants;planVariants[at+1]=cw;planVariants[at+2]=ch;planVariants[at+3]=definiteH==true
   planVariants[at+4]=copyLines(lines);planVariants[at+5]=table.clone(meta)
  end
  return lines,meta
 end
 local function throughMargins(node,s,p,autoHeight)
  if node==root or(s.display~='block'and s.display~='list-item')then return false,false end
  if s.position=='absolute'or s.position=='fixed'or(s.float~=nil and s.float~='none')then return false,false end
  local parent=parents[node.key];local ps=parent and styles[parent.key]
  if ps and(ps.display=='flex'or ps.display=='grid'or ps.display=='inline-flex'or ps.display=='inline-grid')then return false,false end
  local ox,oy=Overflow.axes(s)
  if(ox~='visible'and ox~='clip')or(oy~='visible'and oy~='clip')or Containment.isolates(s)then return false,false end
  local minH=s['min-height']
  local top=p[1]<=0.001
  local bottom=autoHeight and p[3]<=0.001 and(minH==nil or minH=='auto'or minH=='0'or minH=='0px'or minH=='none')
  return top,bottom
 end
 measure=function(node,pw,ph,fw,fh,intrinsic,depth)
  if checkpoint then checkpoint()end
  depth=depth or 0;assert(depth<=40,'Layout profundo demais.')
  local memo=measureCache[node.key]
  if not memo then memo=options.memo and {}or takeArray();measureCache[node.key]=memo end
  local mw,mh,mi=fw or false,fh or false,intrinsic or false
  for i=1,#memo,6 do
   if memo[i]==pw and memo[i+1]==ph and memo[i+2]==mw and memo[i+3]==mh and memo[i+4]==mi then return U.copy(memo[i+5])end
  end
  measureCount+=1;assert(measureCount<=30000,'Layout excedeu o orçamento de medição. Simplifique o aninhamento.')
  local s,fs,p,m=info(node,pw,ph)
  if s.display=='none' then return {w=0,h=0,p=p,m=m,fs=fs,hidden=true}end
  if s.width=='min-content'or s.width=='max-content'or s.width=='fit-content'then intrinsic=s.width end
  local contentOnly=intrinsic=='content';local axes=Writing.axes(s)
  if axes.vertical and(s.height=='min-content'or s.height=='max-content'or s.height=='fit-content')then intrinsic=s.height end
  local ex,ey=Ua.sizingExtra(s,p)
  local percentCell=(intrinsic=='min-content'or intrinsic=='max-content')and s.display=='table-cell'and Properties.hasPercent(s.width)
  local w=fw or(not contentOnly and not percentCell and length(s.width,pw,fs)or nil);local h=fh or(not contentOnly and length(s.height,ph,fs)or nil)
  if w and not fw then w+=ex end
  if h and not fh then h+=ey end
  local definiteH=h~=nil;local definiteW=w~=nil
  if not intrinsic then
   if axes.vertical then if not h then h=math.max(0,ph-m[1]-m[3]);definiteH=true end
   elseif not w then w=math.max(0,pw-m[2]-m[4]);definiteW=true end
  end
  local ratio=Properties.ratio(s['aspect-ratio'])
  if ratio and not intrinsic then
   local contentBox=Ua.sizing(s)=='content-box'
   if h==nil and w~=nil then
    h=contentBox and math.max(0,w-p[2]-p[4])/ratio+p[1]+p[3]or w/ratio;definiteH=true
   elseif w==nil and h~=nil then
    w=contentBox and math.max(0,h-p[1]-p[3])*ratio+p[2]+p[4]or h*ratio;definiteW=true
   end
  end
  if w then w=constrained(w,s,'width',pw,fs,ex)end;if h then h=constrained(h,s,'height',ph,fs,ey)end
  local cw=math.max(0,(w or pw)-p[2]-p[4]);local ch=math.max(0,(h or ph)-p[1]-p[3])
  local gx=math.max(0,length(s['column-gap'],cw,fs) or 0);local gy=math.max(0,length(s['row-gap'],cw,fs) or 0)
  local inline=not tabular(node,s)and inlineEnabled(node)and not Flow.active(s,flowChildren(node),styles);local usedW,usedH,lastBaseline
  if inline then
   local fixedInline=axes.vertical and h or not axes.vertical and w
   local available=axes.vertical and ch or cw
   local inlineLimit=intrinsic=='min-content'and not fixedInline and 1 or intrinsic and not fixedInline and 100000 or available
   local plan=inlinePlan(node,axes.vertical and cw or inlineLimit,axes.vertical and inlineLimit or ch,intrinsic,inlineEnv(node,cw,ch,depth));usedW,usedH=plan.w,plan.h
   if plan.lastBaseline then lastBaseline=plan.lastBaseline+p[1]end
  else usedW,usedH=textMeasure(node,s,fs,intrinsic=='min-content'and not w and -1 or intrinsic and not w and 100000 or cw)end
  local flow=flowChildren(node)
  local intrinsicMode=(w==nil and not axes.vertical and(intrinsic=='min-content'or intrinsic=='max-content'or intrinsic=='fit-content'))and intrinsic or nil
  if inline then
  elseif tabular(node,s)then
   local plan=advanced('table',node,flow,cw,ch,definiteH,depth,intrinsic);usedW=plan.usedW;usedH=plan.usedH
   if Tables.shrinks(s,tableParent(node))and not fw then
    local natural=usedW+p[2]+p[4];local target=constrained(natural,s,'width',pw,fs,ex)
    if target~=natural and not intrinsic then plan=advanced('table',node,flow,math.max(0,target-p[2]-p[4]),ch,definiteH,depth,nil,true);usedW=plan.usedW;usedH=plan.usedH end
    w=math.max(target,usedW+p[2]+p[4])
   elseif Tables.container(s)and w and not fw then w=math.max(w,usedW+p[2]+p[4])end
   if Tables.container(s)and h and not fh then h=math.max(h,usedH+p[1]+p[3])end
   if plan.baseline then lastBaseline=p[1]+plan.baseline end
  elseif s.display=='grid' then
   local plan=advanced('grid',node,flow,cw,ch,definiteH,depth,intrinsicMode);usedW=plan.usedW;usedH=plan.usedH
  elseif s.display=='flex' and #flow>0 then
   local flexW=cw
   if intrinsicMode then
    flexW=flexIntrinsic(node,flow,cw,ch,depth,intrinsicMode=='min-content'and'min-content'or'max-content')
    if intrinsicMode=='fit-content'then flexW=math.min(flexW,cw)end
   end
   local lines,f=flexLines(node,flow,flexW,ch,definiteH,depth);usedW=f.row and f.usedMain or f.usedCross;usedH=f.row and f.usedCross or f.usedMain;releaseLines(lines)
   if intrinsicMode then usedW=math.max(usedW,flexW)end
  elseif s.display~='flex'and Flow.active(s,flow,styles)then
   local plan=advanced('flow',node,flow,cw,ch,definiteH,depth);usedW=plan.usedW;usedH=plan.usedH
  elseif #flow>0 then
   usedW,usedH=0,0
   local runs=Ua.collapsing(s,gy,axes.vertical or axes.inlineReverse or axes.blockReverse)and{}or nil
   local lastFlow
   for _,child in ipairs(flow)do
    local c=measure(child,cw,ch,nil,nil,type(intrinsic)=='string'and intrinsic or false,depth+1)
    if axes.vertical then usedW+=c.w+c.m[2]+c.m[4];usedH=math.max(usedH,c.h+c.m[1]+c.m[3])
    elseif runs then usedW=math.max(usedW,c.w+c.m[2]+c.m[4]);runs[#runs+1]={h=c.h,top=c.m[1],bottom=c.m[3],empty=Ua.selfCollapsing(c)};lastFlow=c
    else usedW=math.max(usedW,c.w+c.m[2]+c.m[4]);usedH+=c.h+c.m[1]+c.m[3];lastFlow=c end
   end
   if runs then
    local offsets,extent,leading,trailing=Ua.flowRuns(runs)
    usedH=extent
    local throughTop,throughBottom=throughMargins(node,s,p,h==nil)
    local shift=0
    if throughTop and leading~=0 then m=table.clone(m);m[1]=Ua.collapse(m[1],leading);usedH-=leading;shift=leading end
    if throughBottom and trailing~=0 then m=table.clone(m);m[3]=Ua.collapse(m[3],trailing);usedH-=trailing end
    if lastFlow and lastFlow.lastBaseline then lastBaseline=p[1]+offsets[#offsets]-shift+lastFlow.lastBaseline end
   else
    if axes.vertical then usedW+=math.max(0,#flow-1)*gy else usedH+=math.max(0,#flow-1)*gy end
    if lastFlow and lastFlow.lastBaseline then lastBaseline=p[1]+math.max(0,usedH-(lastFlow.m[3]or 0)-lastFlow.h)+lastFlow.lastBaseline end
   end
  end
  local contain,skipContents=Containment.state(s,options.skipped~=nil and options.skipped[node.key]==true)
  if contain.size or contain.inlineSize or skipContents then
   local remembered=options.previous and options.previous[node.key]
   local function reserve(value)return length(value,cw,fs)end
   local rw=Containment.intrinsic(s,'width',reserve,remembered and remembered.w)
   local rh=Containment.intrinsic(s,'height',reserve,remembered and remembered.h)
   if contain.size or skipContents then usedW,usedH=rw,rh
   elseif axes.vertical then usedH=rh else usedW=rw end
  end
  if intrinsic=='fit-content'then usedW=math.min(usedW,cw)end
  w=w or constrained(usedW+p[2]+p[4],s,'width',pw,fs,ex);h=h or constrained(usedH+p[1]+p[3],s,'height',ph,fs,ey)
  w=math.max(w,p[2]+p[4]);h=math.max(h,p[1]+p[3])
  local result={w=w,h=h,p=p,m=m,fs=fs,definiteH=definiteH,definiteW=definiteW,lastBaseline=lastBaseline}
  if options.memo and #memo>=384 then clear(memo)end
  local at=#memo
  memo[at+1]=pw;memo[at+2]=ph;memo[at+3]=mw;memo[at+4]=mh;memo[at+5]=mi;memo[at+6]=result;return U.copy(result)
 end
 local place
 place=function(node,x,y,w,h,pw,ph,depth,definiteH)
  if checkpoint then checkpoint()end
  local previous=options.previous and options.previous[node.key]
  if previous and not hasSubgrid and not hasTables and not positionedSubtrees[node.key] and not(options.dirty and options.dirty[node.key])and previous.x==x and previous.y==y and previous.w==w and previous.h==h and previous._pw==pw and previous._ph==ph and previous._definiteH==definiteH then return end
  local s,fs,p=info(node,pw,ph);local shift=cellShifts[node.key];if shift then p=table.clone(p);p[1]+=shift end
  local box={x=x,y=y,w=w,h=h,p=p,fs=fs,hidden=s.display=='none',contentW=w,contentH=h,_pw=pw,_ph=ph,_definiteH=definiteH};boxes[node.key]=box
  if box.hidden then for _,child in ipairs(node.children)do place(child,0,0,0,0,0,0,depth+1,false)end;return end
  local clipMarginValue=s['overflow-clip-margin']
  if clipMarginValue~=nil and clipMarginValue~='0px'and Overflow.clips(s)then
   local reserved=Overflow.clipMargin(s,w,vw,vh,fs)
   if reserved>0 then box.clipMargin=reserved;box.overflowInsets={0,0,0,0}end
  end
  assert(displays[s.display],'display aceita block, inline, inline-block, list-item, flex, grid, table, ruby, none.')
  assert(positions[s.position],'position aceita relative, absolute, static, sticky, fixed.');assert(Ua.sizingValues[s['box-sizing']],'box-sizing aceita content-box ou border-box.')
  local cw=math.max(0,w-p[2]-p[4]);local ch=math.max(0,h-p[1]-p[3]);local gx=math.max(0,length(s['column-gap'],cw,fs) or 0);local gy=math.max(0,length(s['row-gap'],cw,fs) or 0)
  local _,skipContents=Containment.state(s,options.skipped~=nil and options.skipped[node.key]==true)
  if Containment.clips(s)then box.clipsContent=true end
  if skipContents then
   for _,child in ipairs(node.children)do
    place(child,0,0,0,0,cw,ch,depth+1,false)
    local hidden=boxes[child.key];if hidden then hidden.hidden=true end
   end
   return
  end
  local flow,absolute={},{}
  for _,child in ipairs(node.children)do local cs=styles[child.key]
   if discardedText(child,node)then
    place(child,0,0,0,0,cw,ch,depth+1,false)
    local hidden=table.clone(boxes[child.key]);hidden.hidden=true;hidden.w=0;hidden.h=0;hidden.contentW=0;hidden.contentH=0;boxes[child.key]=hidden
   elseif cs.display=='none'then place(child,0,0,0,0,cw,ch,depth+1,false)
   elseif cs.position=='absolute'or cs.position=='fixed'then table.insert(absolute,child)else table.insert(flow,child)end
  end
  local function childPlace(child,cx,cy,c,baseW,baseH)
   local cs=styles[child.key]
   if cs.position=='relative' then cx+=(length(cs.left,cw,c.fs) or -(length(cs.right,cw,c.fs) or 0));cy+=(length(cs.top,ch,c.fs) or -(length(cs.bottom,ch,c.fs) or 0))end
   place(child,cx,cy,c.w,c.h,baseW or cw,baseH or ch,depth+1,c.definiteH or length(cs.height,baseH or ch,c.fs)~=nil)
   if c.fragments then
    local childBox=table.clone(boxes[child.key]);boxes[child.key]=childBox;childBox.fragments=c.fragments;childBox.fragmentSignature=c.fragmentSignature
    childBox.inlineManaged=nil;childBox.inlineFragments=nil;childBox.inlineStamp=nil
    for _,fragment in ipairs(c.fragments)do box.contentW=math.max(box.contentW,cx+fragment.x+fragment.w+p[2]);box.contentH=math.max(box.contentH,cy+fragment.y+fragment.h+p[3])end
   end
   box.contentW=math.max(box.contentW,cx+c.w+p[2]);box.contentH=math.max(box.contentH,cy+c.h+p[3])
   local insets=box.overflowInsets
   if insets then
    insets[1]=math.max(insets[1],p[1]-cy);insets[2]=math.max(insets[2],cx+c.w-(w-p[2]))
    insets[3]=math.max(insets[3],cy+c.h-(h-p[3]));insets[4]=math.max(insets[4],p[4]-cx)
   end
  end
  if not tabular(node,s)and inlineEnabled(node)and not Flow.active(s,flow,styles)then
   local inline=inlinePlan(node,cw,ch,nil,inlineEnv(node,cw,ch,depth))
   InlineText.install(inline,node,styles,boxes,box)
   for _,item in ipairs(inline.atomics or {})do childPlace(item.node,p[4]+item.x,p[1]+item.y+(inline.offsetY or 0),item.c)end
  elseif tabular(node,s)then
   local plan=advanced('table',node,flow,cw,ch,definiteH,depth)
   if Tables.container(s)and Tables.shrinks(s,tableParent(node))and plan.usedW<cw-1e-3 then plan=advanced('table',node,flow,cw,ch,definiteH,depth,nil,true)end
   box.tableBorders=plan.tableBorders;
box.tableSignature=plan.tableSignature;box.tableBorderZ=plan.tableBorderZ;box.tableLayout=plan
   if Tables.container(s)then for _,side in ipairs({'Top','Bottom','Left','Right'})do local v=plan['caption'..side];box['caption'..side]=v and v>0 and v or nil end end
   if plan.tableCollapse and Tables.container(s)then box.collapsedBorders=true end
   local placed={}
   for _,item in ipairs(plan.items)do
    placed[item.node.key]=true;cellShifts[item.node.key]=item.shift and item.shift>0 and item.shift or nil
    childPlace(item.node,p[4]+item.x,p[1]+item.y,item.c,item.c.w,item.c.h)
    local b=boxes[item.node.key];b.collapsedCell=item.collapsedCell;b.collapsedBorders=item.collapsedBorders;if item.emptyCellHidden or item.hidden then b.hidden=true end
   end
   for _,child in ipairs(flow)do if not placed[child.key]then place(child,0,0,0,0,cw,ch,depth+1,false);boxes[child.key].hidden=true end end
   box.contentW=math.max(box.contentW,plan.usedW+p[2]+p[4]);box.contentH=math.max(box.contentH,plan.usedH+p[1]+p[3])
  elseif s.display=='grid' then
   local plan=advanced('grid',node,flow,cw,ch,definiteH,depth);box.grid=plan
   for _,item in ipairs(plan.items)do
    childPlace(item.node,p[4]+item.x,p[1]+item.y,item.c,item.physicalAreaW or item.areaWidth,item.physicalAreaH or(plan.rows.ends[item.row+item.rowSpan-1]-plan.rows.starts[item.row]))
    local b=boxes[item.node.key];b.gridColumn=item.col+plan.minCol-1;b.gridRow=item.row+plan.minRow-1;b.gridColumnSpan=item.colSpan;b.gridRowSpan=item.rowSpan
   end
   box.contentW=math.max(box.contentW,plan.usedW+p[2]+p[4]);box.contentH=math.max(box.contentH,plan.usedH+p[1]+p[3])
  elseif s.display=='flex' then
   local lines,f=flexLines(node,flow,cw,ch,definiteH or node==root,depth)
   box.lineCount=#lines
   local crossAvailable=f.row and ch or cw;local available=f.row and cw or ch
   if f.wrap=='nowrap' and lines[1] then lines[1].cross=math.max(lines[1].cross,crossAvailable);f.usedCross=lines[1].cross end
   local crossCursor,crossGap,stretch=packing(s['align-content'] or 'stretch',crossAvailable-f.usedCross,#lines,f.crossGap,true)
   for lineIndex,line in ipairs(lines)do
    local lineCross=line.cross+stretch;local cursor,gap=packing(s['justify-content'],available-line.total,#line.items,f.gap,false)
    local startOffset=cursor
    for itemIndex,c in ipairs(line.items)do
     if f.wrap=='nowrap' then cursor=startOffset+c.prefix+(itemIndex-1)*gap end
     local cs=styles[c.node.key];local autoCross=not cs[f.row and 'height' or 'width'] or cs[f.row and 'height' or 'width']=='auto'
     if c.align=='stretch' and autoCross and not c.crossAutoBefore and not c.crossAutoAfter then
      c.cross=constrained(math.max(0,lineCross-c.crossBefore-c.crossAfter),cs,f.row and 'height' or 'width',crossAvailable,c.fs,Ua.axisExtra(cs,c.p,not f.row))
      if f.row then c.h=c.cross;c.definiteH=true else c.w=c.cross end
     end
     local spare=math.max(0,lineCross-c.cross-c.crossBefore-c.crossAfter);local offset=0
     if c.crossAutoBefore or c.crossAutoAfter then offset=c.crossAutoBefore and spare/(c.crossAutoAfter and 2 or 1)or 0
     elseif c.align=='center' then offset=spare/2 elseif c.align=='flex-end' or c.align=='end' then offset=spare else assert(c.align=='stretch' or c.align=='flex-start' or c.align=='start','align-items não suportado: '..tostring(c.align))end
     local mainPos=f.reverse and available-cursor-c.after-c.main or cursor+c.before
     local crossPos
     if f.crossReverse then crossPos=crossAvailable-crossCursor-c.crossAfter-offset-c.cross else crossPos=crossCursor+c.crossBefore+offset end
     childPlace(c.node,p[4]+(f.row and mainPos or crossPos),p[1]+(f.row and crossPos or mainPos),c)
     boxes[c.node.key].flexLine=lineIndex
     cursor+=c.main+c.before+c.after+gap
    end
    crossCursor+=lineCross+crossGap
   end
   releaseLines(lines)
  elseif Flow.active(s,flow,styles)then
   local plan=advanced('flow',node,flow,cw,ch,definiteH,depth)
   for _,host in ipairs(plan.hosts or{})do
    local hs,hfs,hp=info(host,cw,ch)
    local hostBox={x=0,y=0,w=w,h=h,p=hp,fs=hfs,hidden=hs.display=='none',contentW=w,contentH=h,_pw=cw,_ph=ch,_definiteH=true,fragmentHost=true}
    local pieces=plan.hostFragments and plan.hostFragments[host.key]
    if pieces and #pieces>0 then
     local rects=table.create(#pieces)
     for index,piece in ipairs(pieces)do rects[index]={x=p[4]+piece.x,y=p[1]+piece.y,w=piece.w,h=piece.h,block=true,startEdge=piece.startEdge,endEdge=piece.endEdge}end
     hostBox.inlineFragmentRects=rects;hostBox.inlineStamp=(plan.columnSignature or'')..'#'..host.key..'#'..#rects
    end
    boxes[host.key]=hostBox
   end
   for _,item in ipairs(plan.items)do if item.x then childPlace(item.node,p[4]+item.x,p[1]+item.y,item.c,plan.columnWidth or cw,plan.columnHeight or ch)end end
   box.columnCount=plan.columnCount;box.columnRules=plan.columnRules;box.columnSignature=plan.columnSignature;box.columnSets=plan.columnSets;box.fragmentationRelaxed=plan.fragmentationRelaxed
   if plan.fragments then box.fragments=plan.fragments;box.fragmentSignature=plan.fragmentSignature end
   box.contentW=math.max(box.contentW,plan.usedW+p[2]+p[4]);box.contentH=math.max(box.contentH,plan.usedH+p[1]+p[3])
  elseif Ua.collapsing(s,gy,Writing.axes(s).vertical or Writing.axes(s).inlineReverse or Writing.axes(s).blockReverse)then
   local measured,runs={},{}
   for index,child in ipairs(flow)do
    local c=measure(child,cw,ch,nil,nil,false,depth+1);measured[index]=c
    runs[index]={h=c.h,top=c.m[1],bottom=c.m[3],empty=Ua.selfCollapsing(c)}
   end
   local offsets,_,leading=Ua.flowRuns(runs)
   local throughTop=throughMargins(node,s,p,false)
   local shift=throughTop and leading or 0
   for index,child in ipairs(flow)do
    local c=measured[index];local cs=styles[child.key]
    local free=math.max(0,cw-c.w-c.m[2]-c.m[4])
    local beforeAuto=cs['margin-left']=='auto';local afterAuto=cs['margin-right']=='auto'
    local offset=beforeAuto and free/(afterAuto and 2 or 1)or 0
    childPlace(child,p[4]+c.m[4]+offset,p[1]+offsets[index]-shift,c)
   end
  else
   local axes=Writing.axes(s);local cursor=0
   for _,child in ipairs(flow)do
    local c=measure(child,cw,ch,nil,nil,false,depth+1);local margins=Writing.spacing(axes,c.m);local cs=styles[child.key]
    local iw,bs=axes.vertical and c.h or c.w,axes.vertical and c.w or c.h
    local free=math.max(0,(axes.vertical and ch or cw)-iw-margins[2]-margins[4])
    local beforeAuto=cs['margin-'..axes.inlineStart]=='auto';local afterAuto=cs['margin-'..axes.inlineEnd]=='auto'
    local offset=beforeAuto and free/(afterAuto and 2 or 1)or 0
    local cx,cy=Writing.mapRect(axes,margins[4]+offset,cursor+margins[1],iw,bs,cw,ch)
    childPlace(child,p[4]+cx,p[1]+cy,c);cursor+=bs+margins[1]+margins[3]+gy
   end
  end
  for _,child in ipairs(absolute)do
   local positioning={root=root,styles=styles,boxes=boxes,parents=parents,measure=measure,info=info,length=length,depth=depth,vw=vw,vh=vh}
   local cx,cy,c,bw,bh
   if styles[child.key].position=='fixed'then cx,cy,c,bw,bh=Position.fixed(child,node,positioning)else cx,cy,c,bw,bh=Position.absolute(child,node,positioning)end
   local keepW,keepH=box.contentW,box.contentH
   childPlace(child,cx,cy,c,bw,bh)
   if c.fixed then
    box.contentW=keepW;box.contentH=keepH
    local anchoredBox=boxes[child.key]
    if anchoredBox then
     anchoredBox.fixed=true
     local ax,ay=0,0;local up=node
     while up do local b=boxes[up.key];if b then ax+=b.x;ay+=b.y end;up=parents[up.key]end
     anchoredBox.fixedHost=true;anchoredBox.viewportX=cx+ax;anchoredBox.viewportY=cy+ay
    end
   end
   if c.hidden then local hidden=boxes[child.key];if hidden then hidden.hidden=true end end
  end
  if box.overflowInsets then box.clipRelaxed=Overflow.relaxed(s,box.clipMargin or 0,box.overflowInsets)or nil end
 end
 local first=measure(root,vw,vh,vw,vh,false,0);place(root,0,0,first.w,first.h,vw,vh,0,true)
 boxes[root.key].measureCount=measureCount
 boxes[root.key].nowrapDirect=nowrapDirect;boxes[root.key].nowrapCacheHits=nowrapCacheHits
 for _,variants in pairs(nowrapPlans)do
  for i=1,#variants,5 do releaseLines(variants[i+3])end;releaseArray(variants)
 end
 clear(nowrapPlans)
 for _,a in pairs(flowCache)do releaseArray(a)end
 if not options.memo then for _,a in pairs(measureCache)do releaseArray(a)end;clear(measureCache)end
 clear(flowCache);clear(infoCache);clear(metrics)
 return boxes
end
return L
