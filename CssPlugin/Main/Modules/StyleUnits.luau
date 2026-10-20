local Cost=require(script.Parent.CostModel)
local Math=require(script.Parent.MathLength)
local U=require(script.Parent.Util)
local Tracks=require(script.Parent.LayoutTracks)
local Variables=require(script.Parent.CssVariables)
local FontMetrics=require(script.Parent.FontUnitMetrics)
local Logical=require(script.Parent.LogicalProperties)
local ValueUnits=require(script.Parent.CssValueUnits)
local Anchors=require(script.Parent.CssAnchors)
local VStyle=require(script.Parent.VisualStyle)
local Containment=require(script.Parent.CssContainment)
local PositionTry=require(script.Parent.CssPositionTry)
local N={}
local nonLengths={initial=true,unset=true,revert=true,['revert-layer']=true,auto=true,none=true,inherit=true,content=true,['min-content']=true,['max-content']=true,['fit-content']=true,normal=true,thin=true,medium=true,thick=true}
local trackKeys={['grid-template-columns']='columns',['grid-template-rows']='rows',['grid-auto-columns']='autoColumns',['grid-auto-rows']='autoRows'}
local keys={width=true,height=true,left=true,right=true,top=true,bottom=true,['font-size']=true,['border-width']=true,['flex-basis']=true,['row-gap']=true,['column-gap']=true}
keys['column-width']=true;keys['column-rule-width']=true;keys['shape-margin']=true
keys['contain-intrinsic-width']=true;keys['contain-intrinsic-height']=true
keys['outline-width']=true;keys['outline-offset']=true
for _,side in ipairs({'top','right','bottom','left'})do keys['border-'..side..'-width']=true end
for _,axis in ipairs({'width','height'})do keys['min-'..axis]=true;keys['max-'..axis]=true end
for _,base in ipairs({'padding','margin'})do for _,side in ipairs({'top','right','bottom','left'})do keys[base..'-'..side]=true end end
for _,corner in ipairs({'top-left','top-right','bottom-left','bottom-right'})do keys['border-'..corner..'-radius']=true end
local relative={['%']=true,cqw=true,cqh=true,cqi=true,cqb=true,cqmin=true,cqmax=true}
local function freeze(node)
 for _,v in pairs(node)do if type(v)=='table'and not table.isfrozen(v)then freeze(v)end end
 return table.isfrozen(node)and node or table.freeze(node)
end
local function ast(value,prepared)return prepared and prepared[value]or Math.parse(value)end
local function program(value,prepared)
 if type(value)~='string'or nonLengths[value] then return nil end
 if Variables.has(value)then return nil end
 return ast(value,prepared)
end
local function folded(node,context)
 if node.op=='none'or node.op=='nonfinite'then return table.clone(node),false end
 local out={op=node.op,strategy=node.strategy};local depends=false
 if node.op=='value'then
  if relative[node.unit]and(node.unit=='%'or not context.containersResolved)then out.value=node.value;out.unit=node.unit;out.ratio=node.value/100;depends=true
  else local number,dimension=Math.evaluate(node,context);out.value=number;out.unit=assert(Math.unitForDimension[dimension],'Dimensão inválida ao normalizar CSS.')end
 elseif node.op=='anchor'or node.op=='anchor-size'then
  if not context.anchorsResolved then
   out=table.clone(node);out.pending=true;depends=true
   if node.fallback then out.fallback=folded(node.fallback,context)end
  else
   local number,reason=ValueUnits.anchor(node,context)
   if number==nil and node.fallback then return folded(node.fallback,context)end
   assert(number~=nil,reason);out={op='value',value=number,unit='px'}
  end
 elseif node.op=='unary'then out.sign=node.sign;out.child,depends=folded(node.child,context)
 elseif node.args then
  out.args={}
  for i,child in ipairs(node.args)do local part,dynamic=folded(child,context);out.args[i]=part;depends=depends or dynamic end
 else
  local left,ld=folded(node.left,context);local right,rd=folded(node.right,context)
  out.left=left;out.right=right;depends=ld or rd
 end
 return out,depends
end
local function normalize(value,context,prepared)
 if type(value)~='string'or nonLengths[value]then return value end
 local result,dynamic=folded(ast(value,prepared),context)
 if not dynamic then
  local number,dimension=Math.evaluate(result,context)
  assert(dimension==0 or dimension==1,'Esperado comprimento, não '..tostring(dimension)..'.');return number
 end
 result._cssLength=true;return freeze(result)
end
local function gridTokens(value)
 local expanded=value:gsub('repeat%(%s*(%d+)%s*,%s*([^%)]+)%)',function(n,column)
  n=tonumber(n);assert(n>=1 and n<=12,'Grid: repeat entre 1 e 12.');return string.rep(column..' ',n)
 end)
 local tokens=U.split(expanded,' ');assert(#tokens>=1 and #tokens<=12,'Grid aceita 1 a 12 colunas.');return tokens
end
function N.prepare(root,rules)
 local prepared={}
 local function add(value)
  if prepared[value]==nil then local p=program(value);if p then prepared[value]=p end end
 end
 local function declarations(list)
  for _,d in ipairs(list or {})do
   if keys[d.key]and not d.shorthand then
    if d.key:match('^border%-.+%-radius$')and not Variables.has(d.value)then for _,part in ipairs(U.split(d.value,' '))do add(part)end else add(d.value)end
   elseif d.key=='box-shadow'and d.value~='none'and not Variables.has(d.value)then
    for _,shadow in ipairs(U.split(d.value,','))do
     local ok,parsed=pcall(VStyle.shadow,shadow)
     if ok then for _,token in ipairs(parsed.lengths)do add(token)end end
    end
   elseif trackKeys[d.key]and not d.shorthand and not Variables.has(d.value)then
    Tracks.parse(d.value,function(token)add(token);return token end)
   end
  end
 end
 for _,rule in ipairs(rules)do declarations(rule.declarations)end
 local function walk(node)declarations(node.inline);for _,child in ipairs(node.children or {})do walk(child)end end
 walk(root);return prepared
end
function N.normalize(style,parent,width,height,prepared,isRoot,unitContext,viewport)
 local parentFont=parent and parent._fontPx or 16
 local rootFont=parent and parent._rootFontPx or 16
 local parentLine=parent and parent._lineHeight or 20
 local rootLine=parent and parent._rootLineHeight or 20
 local context=unitContext and table.clone(unitContext)or {}
 context.base=parentFont;context.vw=width or 1280;context.vh=height or 720
 local vp=viewport or context.viewport
 if vp then
  context.viewport=vp
  context.smallViewportWidth=vp.smallWidth or context.vw;context.smallViewportHeight=vp.smallHeight or context.vh
  context.largeViewportWidth=vp.largeWidth or context.vw;context.largeViewportHeight=vp.largeHeight or context.vh
  context.dynamicViewportWidth=vp.dynamicWidth or context.vw;context.dynamicViewportHeight=vp.dynamicHeight or context.vh
 end
 context.font=parentFont;context.rootFont=rootFont;context.lineHeight=parentLine;context.rootLineHeight=rootLine
 context.ch=parent and parent._chPx or parentFont*0.5;context.ex=parent and parent._exPx or parentFont*0.5
 context.ic=parent and parent._icPx or parentFont;context.cap=parent and parent._capPx or parentFont*0.7
 context.rootCh=parent and parent._rootChPx or 8;context.rootEx=parent and parent._rootExPx or 8
 context.rootIc=parent and parent._rootIcPx or 16;context.rootCap=parent and parent._rootCapPx or 11.2
 context.vertical=Logical.axes(style).vertical;context.writingMode=style['writing-mode'];context.direction=style.direction
 context.positionAnchor=style['position-anchor'];if context.positionAnchor=='auto'then context.positionAnchor=nil end
 context.anchorPending=not context.anchorsResolved;context.anchorInvalid=style.position~='absolute'
 Anchors.validate(style)
 Containment.normalize(style)
 local area=style['position-area']
 if area~=nil then
  local lower=U.trim(tostring(area)):lower()
  if lower=='none'then style['position-area']=nil;style._positionArea=nil
  else
   style['position-area']=lower
   style._positionArea=assert(PositionTry.area(lower,context.vertical,style.direction=='rtl',false),'position-area inválido: '..lower)
  end
 end
 if style['position-try-fallbacks']~=nil then
  local lower=U.trim(tostring(style['position-try-fallbacks'])):lower()
  style['position-try-fallbacks']=lower;style._positionTry=PositionTry.fallbacks(lower)
 end
 if style['position-try-order']~=nil then style['position-try-order']=PositionTry.order(style['position-try-order'])end
 if style['position-visibility']~=nil then style['position-visibility']=PositionTry.visibility(style['position-visibility'])end
 local blockAnchor,blockContainer=false,false
 if style._positionTry and prepared and prepared.positionTry then
  for _,item in ipairs(style._positionTry)do
   local block=item.name and prepared.positionTry[item.name]
   if block then
    local usesAnchor,usesContainer=PositionTry.blockUsage(block)
    blockAnchor=blockAnchor or usesAnchor;blockContainer=blockContainer or usesContainer
   end
  end
 end
 style._usesAnchor=Anchors.uses(style)or style._positionArea~=nil or blockAnchor
 style._usesContainer=blockContainer
 for key,value in pairs(style)do
  if key:sub(1,1)~='_'and type(value)=='string'and value:lower():match('[%d%.]cq[%a]+')then style._usesContainer=true end
 end
 local containerType=style['container-type']or 'normal'
 assert(containerType=='normal'or containerType=='size'or containerType=='inline-size','container-type aceita normal, size ou inline-size.')
 style['container-type']=containerType
 local font=style['font-size']
 context.property='font-size'
 if type(font)=='string'or type(font)=='table'then font=Math.length(type(font)=='string'and ast(font,prepared)or font,context.base,context.vw,context.vh,context.font,context)end
 font=math.clamp(font or parentFont,1,160)
 if isRoot then rootFont=font end
 style['font-size']=font;style._fontPx=font;style._rootFontPx=rootFont
 context.font=font;context.rootFont=rootFont;context.base=font
 context.ch,context.ex=FontMetrics.measure(style,font)
 context.ic,context.cap=FontMetrics.modern(style,font)
 style._chPx=context.ch;style._exPx=context.ex;style._icPx=context.ic;style._capPx=context.cap
 if isRoot then context.rootCh=context.ch;context.rootEx=context.ex;context.rootIc=context.ic;context.rootCap=context.cap end
 style._rootChPx=context.rootCh;style._rootExPx=context.rootEx;style._rootIcPx=context.rootIc;style._rootCapPx=context.rootCap
 context.property='line-height'
 local line=style['line-height']or 'normal'
 local linePx
 if line=='normal'then linePx=font*1.25
 else
  local number,dimension
  if type(line)=='number'then number=line;dimension=0
  else number,dimension=Math.evaluate(type(line)=='table'and line or ast(line,prepared),context)end
  assert(dimension==0 or dimension==1,'line-height exige número ou comprimento.')
  assert(number>=0,'line-height não pode ser negativo.')
  linePx=dimension==0 and number*font or number
  style['line-height']=dimension==0 and tostring(number)or tostring(linePx)..'px'
 end
 assert(linePx<=3200,'line-height fora do limite.')
 style._lineHeight=linePx;if isRoot then rootLine=linePx end
 style._rootLineHeight=rootLine;context.lineHeight=linePx;context.rootLineHeight=rootLine
 context.property=nil
 style._unitContext=freeze(table.clone(context))
 for key in pairs(keys)do if key~='font-size'and style[key]~=nil then
  context.property=key
  local value=style[key]
  if key:match('^border%-.+%-radius$')and type(value)=='string'then
   local words=U.split(value,' ');assert(#words>=1 and #words<=2,'Raio de canto aceita rx ry.')
   style[key]=#words==2 and freeze({_cssRadius=true,x=normalize(words[1],context,prepared),y=normalize(words[2],context,prepared)})or normalize(value,context,prepared)
  elseif key=='border-width'or key=='outline-width'or key:match('^border%-.+%-width$')then style[key]=normalize(({thin='1px',medium='3px',thick='5px'})[value]or value,context,prepared)
  else style[key]=normalize(value,context,prepared)end
 end end
 context.property=nil
 for _,key in ipairs({'opacity','flex-grow','flex-shrink','order','z-index','fill-opacity','stroke-opacity','stop-opacity','flood-opacity'})do
  local value=style[key]
  if type(value)=='string'and value~='auto'and(value:find('(',1,true)or value:find('%',1,true))then
   local scalarContext=table.clone(context);scalarContext.base=1;scalarContext.percentDimension=0;scalarContext.property=key
   local number,dimension=Math.evaluate(ast(value,prepared),scalarContext);assert(dimension==0,key..' exige número sem unidade.')
   style[key]=string.format('%.17g',number)
  end
 end
 local grid
 for key,name in pairs(trackKeys)do if style[key]then
  grid=grid or {};grid[name]=Tracks.parse(style[key],function(token)return normalize(token,context,prepared)end)
 end end
 if grid then
  style._gridTracks=freeze(grid)
  if grid.columns then
   local simple=true;for _,track in ipairs(grid.columns)do if track.kind~='track'or(track.fr==nil and track.length==nil)then simple=false;break end end
   if simple then style._gridColumns=grid.columns else style._gridColumns=nil end
  end
 end
 if style['box-shadow']and style['box-shadow']~='none'then
  local shadows={}
  for _,item in ipairs(VStyle.shadows(style['box-shadow']))do
   local entry={color=item.color,inset=item.inset==true,lengths={}}
   for i,token in ipairs(item.lengths)do entry.lengths[i]=normalize(token,context,prepared)end
   shadows[#shadows+1]=entry
  end
  Cost.cap('shadows',#shadows,'Sombras por elemento');style._shadows=freeze(shadows)
 end
 return style
end
N.normalizeValue=normalize
N.context=function(style,vw,vh,base)
 local context=style._unitContext and table.clone(style._unitContext)or {}
 context.vw=vw or context.vw;context.vh=vh or context.vh;context.base=base or context.base
 return context
end
return N
