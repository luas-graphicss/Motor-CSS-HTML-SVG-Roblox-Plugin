local U=require(script.Parent.Util)
local F=require(script.Parent.FontFaces)
local Features=require(script.Parent.FontFeatures)
local Wrap=require(script.Parent.TextWrap)
local Cost=require(script.Parent.CostModel)
local T={VERSION=2}
T.inherited={'color','font-family','font-size','font-weight','font-style','text-align','white-space','line-height','letter-spacing','word-spacing','text-transform','text-shadow','word-break','overflow-wrap','hyphens','writing-mode','direction','text-orientation','text-combine-upright','ruby-position','ruby-align','text-align-last','_language'}
T.defaults={['font-style']='normal',['line-height']='normal',['letter-spacing']='normal',['word-spacing']='normal',['text-transform']='none',['text-decoration-line']='none',['text-decoration-style']='solid',['text-decoration-color']='currentcolor',['text-decoration-thickness']='auto',['text-shadow']='none',['word-break']='normal',['overflow-wrap']='normal',hyphens='manual',['writing-mode']='horizontal-tb',direction='ltr',['text-orientation']='mixed',_language=''}
T.properties={'font-style','line-height','letter-spacing','word-spacing','text-transform','text-decoration','text-decoration-line','text-decoration-style','text-decoration-color','text-decoration-thickness','text-shadow','word-break','overflow-wrap','hyphens','writing-mode','direction','text-orientation','text-combine-upright','ruby-position','ruby-align','text-align-last'}
T.defaults['text-combine-upright']='none';T.defaults['ruby-position']='over';T.defaults['ruby-align']='space-around';T.defaults['text-align-last']='auto'
for _,module in ipairs({Features,Wrap})do
 for _,key in ipairs(module.inherited)do T.inherited[#T.inherited+1]=key end
 for key,value in pairs(module.defaults)do T.defaults[key]=value end
 for _,key in ipairs(module.properties)do T.properties[#T.properties+1]=key end
end
T.prepare=Features.normalize
function T.register(supported,shorthands)
 for _,key in ipairs(T.properties)do supported[key]=true end
 shorthands['font-variant']=Features.variantKeys
 for key,values in pairs(Wrap.shorthands)do shorthands[key]=values end
end
function T.expandProperty(name,value)
 if name=='font-variant'then return Features.expand(value)end
 return Wrap.expand(name,value)
end
T.decorationKeys={'text-decoration-line','text-decoration-style','text-decoration-color','text-decoration-thickness'}
local lineNames={underline=true,['line-through']=true,overline=true,none=true}
local lineStyles={solid=true,double=true,dotted=true,dashed=true,wavy=true}
function T.expand(value)
 local out={['text-decoration-line']='none',['text-decoration-style']='solid',['text-decoration-color']='currentcolor',['text-decoration-thickness']='auto'}
 local lines={};local seen={}
 for _,token in ipairs(U.split(value,' '))do
  local lower=token:lower()
  if lineNames[lower]then assert(not seen[lower],'text-decoration repetida.');seen[lower]=true;lines[#lines+1]=lower
  elseif lineStyles[lower]then out['text-decoration-style']=lower
  elseif lower=='auto'or lower=='from-font'or lower:match('^[%d%.]+[a-z%%]+$')then out['text-decoration-thickness']=lower
  else if lower~='currentcolor'then U.color(token)end;out['text-decoration-color']=lower end
 end
 assert(not seen.none or #lines==1,'none não combina com outras decorações.')
 if #lines>0 then out['text-decoration-line']=table.concat(lines,' ')end
 return out
end
local enums={
 ['font-style']={normal=true,italic=true,oblique=true},
 ['text-transform']={none=true,uppercase=true,lowercase=true,capitalize=true},
 ['word-break']={normal=true,['break-all']=true,['keep-all']=true,['break-word']=true,manual=true,['auto-phrase']=true},
 ['overflow-wrap']={normal=true,['break-word']=true,anywhere=true},
 hyphens={none=true,manual=true,auto=true},
 ['writing-mode']={['horizontal-tb']=true,['vertical-rl']=true,['vertical-lr']=true,['sideways-rl']=true,['sideways-lr']=true},
 direction={ltr=true,rtl=true},['text-orientation']={mixed=true,upright=true,sideways=true},
 ['text-align-last']={auto=true,start=true,['end']=true,left=true,right=true,center=true,justify=true},
 ['ruby-position']={over=true,under=true,['inter-character']=true,alternate=true},['ruby-align']={start=true,center=true,['space-between']=true,['space-around']=true},
 ['white-space']={normal=true,nowrap=true,pre=true,['pre-wrap']=true,['pre-line']=true,['break-spaces']=true},
}
function T.normalize(style,parent,vw,vh)
 local fs=style._fontPx or tonumber(style['font-size'])or 16
 for key,allowed in pairs(enums)do if style[key]then assert(allowed[style[key]],key..' inválido: '..tostring(style[key]))end end
 if style['text-align']=='match-parent'then
  local inheritedAlign=parent and parent['text-align']or 'start';local parentDirection=parent and parent.direction or 'ltr'
  if inheritedAlign=='start'or inheritedAlign=='match-parent'then inheritedAlign=parentDirection=='rtl'and 'right'or 'left'elseif inheritedAlign=='end'then inheritedAlign=parentDirection=='rtl'and 'left'or 'right'end
  style['text-align']=inheritedAlign
 end
 local combine=style['text-combine-upright']or 'none'
 if combine~='none'and combine~='all'then local n=combine:match('^digits%s*(%d*)$');assert(n,'text-combine-upright aceita none, all ou digits <2-4>.');n=n==''and 2 or tonumber(n);assert(n>=2 and n<=4,'text-combine-upright digits aceita 2 a 4.');style._combineDigits=n else style._combineDigits=nil end
 F.weight(style['font-weight'])
 local function length(value,base)
  local context=style._unitContext or {rootFont=style._rootFontPx,lineHeight=style._lineHeight,ch=style._chPx,ex=style._exPx}
  return U.length(value,base or fs,vw or 1280,vh or 720,fs,context)
 end
 Wrap.normalize(style,parent,length)
 Features.finish(style)
 local lh=style['line-height']or 'normal'
 if lh=='normal'then style._lineHeight=fs*1.25
 elseif type(lh)=='string'and tonumber(lh)then local n=tonumber(lh);assert(n>=0 and n<=20,'line-height proporcional fora do limite.');style._lineHeight=n*fs
 else local pixels=assert(length(lh),'line-height inválido.');assert(pixels>=0 and pixels<=3200,'line-height fora do limite.');style._lineHeight=pixels;style['line-height']=tostring(pixels)..'px' end
 for _,key in ipairs({'letter-spacing','word-spacing'})do
  local value=style[key]or 'normal'
  if value~='normal'then
   assert(type(value)~='string'or not value:find('%%'),'Espaçamento usa comprimentos, não %.')
   value=assert(length(value),key..' inválido.');assert(math.abs(value)<=1000,key..' fora do limite.');style[key]=value
  end
 end
 local tracking=style._fontTracking or 0
 if math.abs(tracking)>0.001 then
  local base=style._letterSpacingBase
  if base==nil then base=tonumber(style['letter-spacing'])or 0;style._letterSpacingBase=base end
  style['letter-spacing']=math.clamp(base+tracking,-1000,1000)
 end
 local lines={};local raw=style['text-decoration-line']or 'none'
 for _,line in ipairs(U.split(raw,' '))do assert(lineNames[line],'text-decoration-line inválido.');lines[#lines+1]=line end
 assert(not raw:find('none',1,true)or #lines==1,'none não combina com decorações.')
 assert(lineStyles[style['text-decoration-style']or 'solid'],'text-decoration-style inválido.')
 local color=style['text-decoration-color']or 'currentcolor';if color:lower()~='currentcolor'then U.color(color)end
 local thickness=style['text-decoration-thickness']or 'auto'
 if thickness~='auto'and thickness~='from-font'then thickness=assert(length(thickness),'Espessura de decoração inválida.');assert(thickness>=0 and thickness<=1000,'Espessura inválida.');style['text-decoration-thickness']=thickness end
 local shadows={}
 if style['text-shadow']and style['text-shadow']~='none'then
  for _,rawShadow in ipairs(U.split(style['text-shadow'],','))do
   local lengths={};local ink='currentcolor';local colored=false
   for _,token in ipairs(U.split(rawShadow,' '))do
    local ok,colorValue=pcall(U.color,token)
    if token:lower()=='currentcolor'or ok then assert(not colored,'Uma cor por text-shadow.');ink=token;colored=true
    else lengths[#lengths+1]=assert(length(token),'text-shadow inválido.')end
   end
   assert(#lengths==2 or #lengths==3,'text-shadow: x y [blur] [cor].')
   local blur=lengths[3]or 0;assert(blur>=0 and blur<=64,'text-shadow: blur entre 0 e 64px.')
   shadows[#shadows+1]={x=lengths[1],y=lengths[2],blur=blur,color=ink}
  end
  Cost.cap('shadows',#shadows,'text-shadow')
 end
 style._textShadows=shadows
 return style
end
function T.advanced(style)
 return (style['line-height']or 'normal')~='normal'or (style['letter-spacing']or 'normal')~='normal'or (style['word-spacing']or 'normal')~='normal'
  or (style['text-transform']or 'none')~='none'or (style['text-decoration-line']or 'none')~='none'or (style['text-shadow']or 'none')~='none'
  or (style['word-break']or 'normal')~='normal'or (style['overflow-wrap']or 'normal')~='normal'or style.hyphens=='auto'
  or (style['writing-mode']or 'horizontal-tb')~='horizontal-tb'or style.direction=='rtl'or style['text-align']=='end'or style['text-align']=='justify'or(style['text-align-last']or 'auto')~='auto'
  or (style['font-style']or 'normal')~='normal'or style._customFont==true
  or (style['text-wrap-style']or 'auto')~='auto'or(style['line-break']or 'auto')~='auto'or(style['unicode-bidi']or 'normal')~='normal'
  or(style._openTypeFeatures or '')~=''or(style['font-variation-settings']or 'normal')~='normal'
  or(style['hyphenate-character']or 'auto')~='auto'
end
return T
