local U=require(script.Parent.Util)
local B={VERSION=2}
local atomicDisplays=table.freeze({['inline-block']=true,['inline-table']=true,['inline-flex']=true,['inline-grid']=true})
local innerDisplays=table.freeze({['inline-flex']='flex',['inline-grid']='grid',['inline-table']='table',['inline-block']='block'})
local replacedTags=table.freeze({img=true,svg=true,canvas=true,video=true,audio=true,iframe=true,object=true,embed=true,picture=true,progress=true,meter=true,input=true,textarea=true,select=true})
local alignments=table.freeze({baseline=true,sub=true,super=true,['text-top']=true,['text-bottom']=true,middle=true,center=true,top=true,bottom=true})
local nativeAlign=table.freeze({top=Enum.TextYAlignment.Top,bottom=Enum.TextYAlignment.Bottom,middle=Enum.TextYAlignment.Center,center=Enum.TextYAlignment.Center,baseline=Enum.TextYAlignment.Top,sub=Enum.TextYAlignment.Top,super=Enum.TextYAlignment.Top,['text-top']=Enum.TextYAlignment.Top,['text-bottom']=Enum.TextYAlignment.Bottom})
local lineRelative=table.freeze({top=true,bottom=true})
B.atomicDisplays=atomicDisplays
B.alignments=alignments
function B.innerDisplay(style)
 local display=style and style.display or 'inline'
 return innerDisplays[display] or display
end
function B.atomicDisplay(display)return atomicDisplays[display]==true end
function B.replaced(tag)return replacedTags[tag]==true end
function B.isAtomic(node,style)
 if not style or style.display=='none'or style.position=='absolute'then return false end
 if style.float and style.float~='none'then return false end
 if atomicDisplays[style.display]then return true end
 return style.display=='inline'and replacedTags[node.tag]==true
end
function B.align(style,fs,lineHeight)
 local raw=style and style['vertical-align']
 if raw==nil or raw==''then return 'baseline',0 end
 if(raw=='middle'or raw=='center')and not style._alignSet then return 'baseline',0 end
 if alignments[raw]then return raw,0 end
 local ok,value=pcall(U.length,raw,lineHeight,nil,nil,fs)
 assert(ok and value,'vertical-align aceita baseline, sub, super, text-top, text-bottom, middle, top, bottom, comprimento ou porcentagem.')
 return 'length',value
end
function B.native(value)
 local mapped=nativeAlign[value or 'middle']
 if mapped then return mapped end
 local ok,length=pcall(U.length,value,16,1280,720,16)
 assert(ok and length,'vertical-align não suportado: '..tostring(value))
 return Enum.TextYAlignment.Top
end
function B.lineRelative(mode)return lineRelative[mode]==true end
function B.atomicMetrics(c,style)
 local top=c.m[1]or 0;local bottom=c.m[3]or 0
 local height=math.max(0,c.h+top+bottom)
 local overflow=style and style.overflow
 local baseline=c.baseline
 if baseline==nil or(overflow~=nil and overflow~='visible')then return height,0,height end
 local above=math.clamp(top+baseline,0,height)
 return above,height-above,height
end
function B.raise(mode,length,item,parent)
 if mode=='baseline'then return 0 end
 if mode=='length'then return length end
 if mode=='sub'then return -parent.fs*.2 end
 if mode=='super'then return parent.fs*.33 end
 if mode=='middle'or mode=='center'then return item.height/2+parent.xHeight/2-item.sizeAbove end
 if mode=='text-top'then return parent.textAbove-item.sizeAbove end
 if mode=='text-bottom'then return item.sizeBelow-parent.textBelow end
 return 0
end
function B.resolve(items,strut,parent)
 local above=strut.above;local below=strut.below
 local topMax,bottomMax=0,0
 for _,item in ipairs(items)do
  if lineRelative[item.mode]then
   if item.mode=='top'then topMax=math.max(topMax,item.height)else bottomMax=math.max(bottomMax,item.height)end
  else
   item.raise=(item.baseRaise or 0)+B.raise(item.mode,item.length or 0,item,item.metrics or parent)
   above=math.max(above,item.sizeAbove+item.raise);below=math.max(below,item.sizeBelow-item.raise)
  end
 end
 if topMax>above+below then below=topMax-above end
 if bottomMax>above+below then above=bottomMax-below end
 local height=above+below
 for _,item in ipairs(items)do
  if item.mode=='top'then item.top=0
  elseif item.mode=='bottom'then item.top=height-item.height
  else item.top=above-item.drawAbove-(item.raise or 0)end
 end
 return above,height
end
function B.initialLetter(style)
 local raw=style and style['initial-letter']
 if raw==nil or raw=='normal'or raw=='none'then return nil end
 local parts=U.split(tostring(raw),' ')
 assert(#parts>=1 and #parts<=2,'initial-letter aceita <tamanho> [<afundamento>].')
 local size=tonumber(parts[1])
 assert(size and size>=1 and size<=10,'initial-letter: tamanho entre 1 e 10 linhas.')
 local sink=parts[2]and tonumber(parts[2])or math.floor(size)
 assert(sink and sink%1==0 and sink>=1 and sink<=10,'initial-letter: afundamento inteiro entre 1 e 10.')
 return {size=size,sink=math.min(sink,10)}
end
function B.clone(style)
 local value=style and style['box-decoration-break']
 assert(value==nil or value=='slice'or value=='clone','box-decoration-break aceita slice ou clone.')
 return value=='clone'
end
function B.edges(count,index,clone,rtl)
 if clone then return true,true end
 local first=index<=1;local last=index>=count
 if rtl then return last,first end
 return first,last
end
function B.maskRadii(radii,startEdge,endEdge,rtl)
 local out={radii[1],radii[2],radii[3],radii[4]}
 local cutLeft=not(rtl and endEdge or not rtl and startEdge)
 local cutRight=not(rtl and startEdge or not rtl and endEdge)
 if cutLeft then out[1]=0;out[4]=0 end
 if cutRight then out[2]=0;out[3]=0 end
 return out
end
function B.maskWidths(widths,startEdge,endEdge,rtl)
 local out={widths[1]or 0,widths[2]or 0,widths[3]or 0,widths[4]or 0}
 local keepLeft=rtl and endEdge or not rtl and startEdge
 local keepRight=rtl and startEdge or not rtl and endEdge
 if not keepLeft then out[4]=0 end
 if not keepRight then out[2]=0 end
 return out
end
local openPunctuation=table.freeze({['(']=true,['[']=true,['{']=true,['"']=true,["'"]=true,['«']=true,['‹']=true,['¿']=true,['¡']=true,['‘']=true,['“']=true,['„']=true,['‚']=true})
local closePunctuation=table.freeze({[')']=true,[']']=true,['}']=true,['"']=true,["'"]=true,['»']=true,['›']=true,['’']=true,['”']=true,['.']=true,[',']=true,[';']=true,[':']=true,['!']=true,['?']=true,['…']=true})
local firstLineProperties=table.freeze({color=true,background=true,['background-color']=true,['background-image']=true,['background-clip']=true,['font-size']=true,['font-family']=true,['font-weight']=true,['font-style']=true,['font-variant']=true,['font-stretch']=true,['line-height']=true,['letter-spacing']=true,['word-spacing']=true,['text-transform']=true,['text-shadow']=true,['text-decoration']=true,['text-decoration-line']=true,['text-decoration-color']=true,['text-decoration-style']=true,['text-decoration-thickness']=true,['vertical-align']=true,opacity=true})
local firstLetterProperties={['initial-letter']=true,['margin-left']=true,['margin-right']=true,['margin-top']=true,['margin-bottom']=true,['padding-left']=true,['padding-right']=true,['padding-top']=true,['padding-bottom']=true,['border-width']=true,['border-style']=true,['border-color']=true,['border-radius']=true,float=true}
for property in pairs(firstLineProperties)do firstLetterProperties[property]=true end
firstLetterProperties=table.freeze(firstLetterProperties)
B.firstLineProperties=firstLineProperties
B.firstLetterProperties=firstLetterProperties
function B.strut(lineHeight,drawHeight)
 local draw=math.max(1,drawHeight or lineHeight or 1)
 local height=math.max(0,lineHeight or draw)
 local above=draw*.8+(height-draw)/2
 return {above=above,below=height-above,height=height,draw=draw}
end
function B.parentMetrics(fs,lineHeight,drawHeight)
 local size=fs or 16;local draw=math.max(1,drawHeight or size)
 return {fs=size,xHeight=size*.5,textAbove=draw*.8,textBelow=draw*.2,lineHeight=lineHeight or draw}
end
function B.merge(base,pseudo,allowed)
 if not base or not pseudo then return base end
 local declared=pseudo._declared
 if not declared then return base end
 local out,typography
 for property in pairs(declared)do
  if allowed[property]then
   out=out or table.clone(base)
   out[property]=pseudo[property]
   if property=='vertical-align'then out._alignSet=true end
   if property=='font'or property=='font-size'or property=='font-family'or property=='font-weight'or property=='font-style'or property=='font-variant'or property=='font-stretch'or property=='line-height'or property=='letter-spacing'then typography=true end
  end
 end
 if not out then return base end
 if typography then
  for key,value in pairs(pseudo)do if type(key)=='string'and key:sub(1,1)=='_'then out[key]=value end end
 elseif declared['text-shadow']then out._textShadows=pseudo._textShadows end
 out._declared=nil
 out._pseudoLine=true
 return out
end
function B.firstLetter(atoms)
 local first
 for index=1,#atoms do
  local atom=atoms[index]
  local raw=atom.raw or atom.text or ''
  if atom.soft or atom.zero then
   if first then break end
  elseif raw:match('^[ \t\r\n\f]+$')then
   if first then break end
  elseif openPunctuation[raw]then
   if first and atoms[first].key~=atom.key then break end
   first=first or index
  else
   if first and atoms[first].key~=atom.key then break end
   first=first or index
   local last=index
   for j=index+1,math.min(#atoms,index+8)do
    local candidate=atoms[j];local text=candidate.raw or candidate.text or ''
    if candidate.key~=atom.key or not closePunctuation[text]then break end
    last=j
   end
   return first,last
  end
 end
 return nil
end
function B.initialFont(spec,lineHeight,probeHeight,fs)
 local target=math.max(1,(spec.size or 1)*math.max(1,lineHeight))
 local scale=target/math.max(1,probeHeight)
 return math.clamp((fs or 16)*scale,1,400),target
end
return B
