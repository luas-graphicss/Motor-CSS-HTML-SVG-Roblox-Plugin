local V={VERSION=1,units={}}
local physical={px=1,pt=96/72,pc=16,['in']=96,cm=96/2.54,mm=96/25.4,q=96/101.6}
for u in pairs(physical)do V.units[u]=true end
for word in ('% em rem ex rex ch rch ic ric cap rcap lh rlh vw vh vi vb vmin vmax svw svh svi svb svmin svmax lvw lvh lvi lvb lvmin lvmax dvw dvh dvi dvb dvmin dvmax cqw cqh cqi cqb cqmin cqmax deg rad grad turn s ms hz khz dpi dpcm dppx'):gmatch('%S+')do V.units[word]=true end
table.freeze(V.units)
V.canonical={[0]='',[1]='px',angle='rad',time='s',frequency='hz',resolution='dppx'}
function V.vertical(context)return context.vertical==true or context.writingMode and context.writingMode~='horizontal-tb'end
function V.literal(n,u,c)
 if u==''then return n,0 end
 if physical[u]then return n*physical[u],1 end
 local base=c.base or c.percentBase or 0
 local font=c.font or c.fontSize or 16;local root=c.rootFont or c.rootFontSize or 16
 local actualW=c.vw or c.viewportWidth or base;local actualH=c.vh or c.viewportHeight or base
 local smallW=c.smallViewportWidth or c.svw or actualW;local smallH=c.smallViewportHeight or c.svh or actualH
 local largeW=c.largeViewportWidth or c.lvw or actualW;local largeH=c.largeViewportHeight or c.lvh or actualH
 local dynamicW=c.dynamicViewportWidth or c.dvw or actualW;local dynamicH=c.dynamicViewportHeight or c.dvh or actualH
 if u=='%'then return n*base/100,c.percentDimension==0 and 0 or 1 end
 local metrics={em=font,rem=root,ex=c.ex or c.xHeight or font*0.5,rex=c.rootEx or root*0.5,ch=c.ch or c.chWidth or font*0.5,rch=c.rootCh or root*0.5,ic=c.ic or font,ric=c.rootIc or root,cap=c.cap or font*0.7,rcap=c.rootCap or root*0.7,lh=c.lineHeight or font*1.25,rlh=c.rootLineHeight or root*1.25}
 if metrics[u]then return n*metrics[u],1 end
 if u=='deg'then return math.rad(n),'angle'elseif u=='rad'then return n,'angle'elseif u=='grad'then return n*math.pi/200,'angle'elseif u=='turn'then return n*2*math.pi,'angle'
 elseif u=='s'then return n,'time'elseif u=='ms'then return n/1000,'time'
 elseif u=='hz'then return n,'frequency'elseif u=='khz'then return n*1000,'frequency'
 elseif u=='dppx'then return n,'resolution'elseif u=='dpi'then return n/96,'resolution'elseif u=='dpcm'then return n*2.54/96,'resolution'end
 if u:sub(1,1)=='v'or u:match('^[sld]v')then
  local w,h,axis=largeW,largeH,u:sub(2)
  if u:sub(1,2)=='sv'then w,h,axis=smallW,smallH,u:sub(3)
  elseif u:sub(1,2)=='lv'then axis=u:sub(3)
  elseif u:sub(1,2)=='dv'then w,h,axis=dynamicW,dynamicH,u:sub(3)end
  local vertical=V.vertical(c)
  local factor=axis=='w'and w or axis=='h'and h or axis=='i'and(vertical and h or w)or axis=='b'and(vertical and w or h)or axis=='min'and math.min(w,h)or axis=='max'and math.max(w,h)
  assert(factor,'Unidade viewport inválida: '..u);return n*factor/100,1
 end
 if u:sub(1,2)=='cq'then
  local w=c.containerWidth or c.parentWidth or smallW;local h=c.containerHeight or c.parentHeight or smallH
  local vertical=c.containerVertical;if vertical==nil then vertical=V.vertical(c)end
  local inline=c.containerInline or(vertical and h or w);local block=c.containerBlock or(vertical and w or h)
  local factor=u=='cqw'and w or u=='cqh'and h or u=='cqi'and inline or u=='cqb'and block or u=='cqmin'and math.min(inline,block)or u=='cqmax'and math.max(inline,block)
  assert(factor,'Unidade container inválida: '..u);return n*factor/100,1
 end
 error('Unidade CSS não suportada: '..u,0)
end
local function logicalStart(axis,vertical,mode,direction)
 if axis=='x'then
  if vertical then return mode and mode:sub(-2)=='lr'and 'left'or 'right'end
  return direction=='rtl'and 'right'or 'left'
 end
 if not vertical then return 'top'end
 return direction=='rtl'and 'bottom'or 'top'
end
function V.anchor(node,c)
 if c.anchorPending or node.pending then return 0 end
 if c.anchorInvalid then return nil,'anchor exige posicionamento absoluto.'end
 local name=node.name or c.positionAnchor
 local rect=c.anchors and name and c.anchors[name]or c.anchorRect
 if not rect then return nil,'Âncora não encontrada: '..tostring(name or 'auto')end
 if node.op=='anchor-size'then
  local axis=node.side
  if not axis then local p=c.property or '';axis=(p:find('height',1,true)or p=='top'or p=='bottom'or p=='margin-top'or p=='margin-bottom')and 'height'or 'width'end
  local vertical=rect.vertical
  if axis:sub(1,5)=='self-'then vertical=V.vertical(c)end
  if axis=='inline'or axis=='self-inline'then axis=vertical and 'height'or 'width'
  elseif axis=='block'or axis=='self-block'then axis=vertical and 'width'or 'height'end
  return axis=='width'and rect.width or rect.height
 end
 local property=c.property or(c.axis=='y'and 'top'or 'left')
 local x=property=='left'or property=='right';local y=property=='top'or property=='bottom'
 if not x and not y then return nil,'anchor() só é válido em propriedades de inset.'end
 local side=node.side;local axis=x and 'x'or 'y';local start=x and rect.x or rect.y;local size=x and rect.width or rect.height
 local coordinate
 if node.percent~=nil then coordinate=start+size*node.percent/100
 elseif side=='center'then coordinate=start+size/2
 else
  if side=='start'or side=='end'or side=='self-start'or side=='self-end'then
   local self=side:sub(1,5)=='self-';local vertical=c.containingVertical
   if self then vertical=V.vertical(c)end
   local first=logicalStart(axis,vertical,self and c.writingMode or c.containingWritingMode,self and c.direction or c.containingDirection)
   local opposite={left='right',right='left',top='bottom',bottom='top'}
   side=side:sub(-3)=='end'and opposite[first]or first
  end
  if x and(side~='left'and side~='right')or y and(side~='top'and side~='bottom')then return nil,'Lado de anchor incompatível com o eixo de '..property end
  coordinate=(side=='right'or side=='bottom')and start+size or start
 end
 if property=='right'then coordinate=(c.containingWidth or c.base or 0)-coordinate
 elseif property=='bottom'then coordinate=(c.containingHeight or c.base or 0)-coordinate end
 return coordinate
end
return V
