local U=require(script.Parent.Util)
local Fonts=require(script.Parent.FontFaces)
local Type=require(script.Parent.Typography)
local TS=require(script.Parent.TypographyStyle)
local N=require(script.Parent.TextUnicode)
local Wrap=require(script.Parent.TextWrap)
local Bidi=require(script.Parent.TextBidi)
local Writing=require(script.Parent.LogicalProperties)
local Boxes=require(script.Parent.InlineBoxes)
local TextService=game:GetService('TextService')
local T={VERSION=3};local serial=0
local textTags={p=true,span=true,text=true,label=true,h1=true,h2=true,h3=true,b=true,strong=true,i=true,em=true,u=true,s=true,small=true,button=true,ruby=true,rt=true,rp=true,rb=true,rtc=true,bdi=true,bdo=true}
local metricCache,metricKeys={},{};local cursor=0;local metricHits,metricMisses=0,0
local function metric(text,style)
 local fs=style._fontPx or tonumber(style['font-size'])or 16
 local face=Fonts.face(style);local key=face.Family..':'..face.Weight.Value..':'..face.Style.Value..':'..fs..':'..(style._openTypeFeatures or '')..':'..#text..':'..text
 local value=metricCache[key];if value then metricHits+=1;return value end
 metricMisses+=1
 value=Type.bounds(style,text,fs)
 if not value and(style._customFont or style._fontEffectiveWeight or style._fontEffectiveSlant or style['font-style']=='italic'or style['font-style']=='oblique')then
  local params=Instance.new('GetTextBoundsParams')
  local ok,result=pcall(function()params.Font=face;params.Text=text;params.Size=fs;params.Width=100000;return TextService:GetTextBoundsAsync(params)end)
  params:Destroy();if ok then value=result end
 end
 value=value or TextService:GetTextSize(text,fs,Fonts.fallback(style),Vector2.new(100000,100000))
 cursor=cursor%2048+1;local old=metricKeys[cursor];if old then metricCache[old]=nil end
 metricKeys[cursor]=key;metricCache[key]=value;return value
end
T.metric=metric
function T.stats()return {hits=metricHits,misses=metricMisses,entries=#metricKeys}end
function T.enabled(node,styles)
 local style=styles[node.key]
 if not style or style.display=='none'or node.tag=='input'or node.tag=='textarea'or node.tag=='svg'then return false end
 if #node.children==0 then
  return textTags[node.tag]and(TS.advanced(style)or(node.text or ''):find(utf8.char(0xad),1,true)~=nil or(node.text or ''):find(utf8.char(0x200b),1,true)~=nil or style['white-space']=='pre'or style['white-space']=='pre-wrap'or style['white-space']=='pre-line'or style['white-space']=='break-spaces')or false
 end
 if style.display=='flex'or style.display=='grid'then return false end
 local any=false
 local function inline(child)
  local cs=styles[child.key]
  if not cs then return false end
  if cs.display=='none'or cs.position=='absolute'then return true end
  if cs.float and cs.float~='none'then return false end
  if Boxes.isAtomic(child,cs)then any=true;return true end
  if child.tag~='br'and not child.anonymousText and cs.display~='inline'and cs.display:sub(1,4)~='ruby'then return false end
  if not textTags[child.tag]and child.tag~='br'then return false end
  any=true
  for _,desc in ipairs(child.children)do if not inline(desc)then return false end end
  return true
 end
 for _,child in ipairs(node.children)do if not inline(child)then return false end end
 return any
end
function T.source(node,objects,style)
 local object=objects and objects[node.textOwnerKey or node.key]
 local value=object and(object:IsA('TextLabel')or object:IsA('TextButton')or object:IsA('TextBox'))and object.Text or node.text or ''
 if node.rawText and value==node.text and(style['white-space']=='pre'or style['white-space']=='pre-wrap'or style['white-space']=='pre-line'or style['white-space']=='break-spaces')then return node.rawText end
 return value
end
local function decorated(style)
 local background=style.background or style['background-color']or style['background-image']
 if background and background~='none'and background~='transparent'then return true end
 local mode=style['border-style']
 if mode and mode~='none'and mode~='hidden'then return true end
 local shadow=style['box-shadow']
 return shadow~=nil and shadow~='none'
end
local function build(stamp,root,styles,objects,width,height,vw,vh,checkpoint,hyphenation,segmentation,intrinsicMode,env,firstLineStyle,firstLetterStyle,firstLineAtoms)
 local plan={stamp=stamp,records={},lines={},atomics={},w=0,h=0,fragments=0,firstLineAtoms=0,rubies={}}
 local rs=styles[root.key];local axes=Writing.axes(rs);local vertical=axes.vertical
 local limit=math.max(1,vertical and height or width)
 local nowrap=Wrap.nowrap(rs)
 local rootScope=Bidi.root(rs.direction)
 local paragraphBase=rs.direction or 'ltr';local consecutiveHyphens=0
 local rootFs=rs._fontPx or 16
 local rootHeight=rs._lineHeight or rootFs*1.25
 local rootDrawH=math.max(rootFs,metric('Mg',rs).Y)
 local strut=Boxes.strut(rootHeight,rootDrawH)
 local parentMetrics=Boxes.parentMetrics(rootFs,rootHeight,rootDrawH)
 local tokens={};local word={};local total=0;local wordStart=true;local order={};local initial=nil;local rubyStack={}
 local merges={}
 local function styleWith(base,pseudoStyle,allowed)
  if not pseudoStyle then return base end
  local cache=merges[pseudoStyle];if not cache then cache={};merges[pseudoStyle]=cache end
  local hit=cache[base];if hit==nil then hit=Boxes.merge(base,pseudoStyle,allowed);cache[base]=hit end
  return hit
 end
 local function flushWord()if #word>0 then tokens[#tokens+1]={kind='word',atoms=word};word={}end end
 local function edgeMetrics(style)
  local fs=style._fontPx or 16
  local widths=style._borderWidths
  if not widths then
   local mode=style['border-style']
   local value=(mode and mode~='none'and mode~='hidden')and(U.length(style['border-width'],limit,vw,vh,fs)or 0)or 0
   widths={value,value,value,value}
  end
  local function len(value)
   if value==nil or value=='auto'then return 0 end
   return U.length(value,limit,vw,vh,fs)or 0
  end
  local left=len(style['padding-left'])+(widths[4]or 0)+math.max(0,len(style['margin-left']))
  local right=len(style['padding-right'])+(widths[2]or 0)+math.max(0,len(style['margin-right']))
  local top=len(style['padding-top'])+(widths[1]or 0)
  local bottom=len(style['padding-bottom'])+(widths[3]or 0)
  if left<=0 and right<=0 and top<=0 and bottom<=0 and not decorated(style)then return nil end
  local rtl=style.direction=='rtl'
  return {start=rtl and right or left,finish=rtl and left or right,left=left,right=right,top=top,bottom=bottom,rtl=rtl,widths=widths,clone=Boxes.clone(style)}
 end
 local function logicalAtomic(c)
  if not vertical then return c end
  local l=table.clone(c);l.w,l.h=c.h,c.w
  local m,p=c.m or {0,0,0,0},c.p or {0,0,0,0}
  l.m={m[4]or 0,m[1]or 0,m[2]or 0,m[3]or 0};l.p={p[4]or 0,p[1]or 0,p[2]or 0,p[3]or 0}
  return l
 end
 local function measureAtomic(node,style)
  if env.measure then return env.measure(node,limit)end
  local fs=style._fontPx or 16
  local function len(value)
   if value==nil or value=='auto'then return 0 end
   return U.length(value,limit,vw,vh,fs)or 0
  end
  return {w=len(style.width),h=len(style.height),p={0,0,0,0},m={0,0,0,0},fs=fs}
 end
 local function pushText(node,style,decorations,scope)
  local source=T.source(node,objects,style);local chars=N.graphemes(source)
  local dictionary=Wrap.dictionaryBreaks(chars,style._language,segmentation)
  local controls={current=scope}
  for index,raw in ipairs(chars)do
   if Bidi.consume(raw,controls,table.concat(chars,'',index+1))then flushWord();continue end
   if dictionary[index-1]and style['word-break']~='manual'then flushWord()end
   total+=1;assert(total<=8192,'Contexto inline excede 8192 grafemas; divida em parágrafos.')
   if checkpoint and total%48==0 then checkpoint(4)end
   local ws=style['white-space']or 'normal';local preserve=ws=='pre'or ws=='pre-wrap'or ws=='break-spaces'
   local newline=(raw=='\n'or raw=='\r\n'or raw=='\r')and(preserve or ws=='pre-line')
   local whitespace=raw:match('^[ \t\r\n\f]+$')~=nil
   local g=N.transform(raw,style['text-transform'],wordStart)
   local applied=style
   if firstLineStyle and firstLineAtoms and #order<firstLineAtoms then applied=styleWith(style,firstLineStyle,Boxes.firstLineProperties)end
   local atom={text=g,raw=raw,node=node,key=node.key,style=applied,base=style,decorations=decorations,direction=Bidi.direction(g),bidi=controls.current,soft=raw==utf8.char(0xad),zero=raw==utf8.char(0x200b),ruby=rubyStack[#rubyStack]}
   order[#order+1]=atom;atom.index=#order
   if newline then flushWord();tokens[#tokens+1]={kind='break',atom=atom};wordStart=true
   elseif whitespace then
    flushWord();wordStart=true;atom.text=' ';atom.direction=nil
    local previous=tokens[#tokens]
    if preserve or not previous or previous.kind~='space'then
     local count=raw=='\t'and preserve and 4 or 1
     for _=1,count do tokens[#tokens+1]={kind='space',atoms={atom},preserve=preserve}end
    end
   else
    if N.isLetter(raw)or raw:match('%d')then wordStart=false elseif raw~="'"and raw~='’'and not atom.soft and not atom.zero then wordStart=true end
    local previous=word[#word]
    if previous and not atom.soft and not previous.soft and(style['text-combine-upright']or 'none')~='all'and Wrap.boundary(previous.text,g,style)then flushWord()end
    word[#word+1]=atom
    if atom.zero then flushWord()end
   end
  end
 end
 local function inlineAlign(style,metrics)
  local fs=style._fontPx or rootFs
  local lh=style._lineHeight or fs*1.25
  local drawH=math.max(fs,metric('Mg',style).Y)
  local half=(lh-drawH)/2
  local mode,length=Boxes.align(style,fs,lh)
  local box={height=lh,sizeAbove=drawH*.8+half,sizeBelow=drawH*.2+half,drawAbove=drawH*.8}
  local raise=Boxes.lineRelative(mode)and 0 or Boxes.raise(mode,length or 0,box,metrics)
  return raise,Boxes.parentMetrics(fs,lh,drawH)
 end
 local function collect(node,parent,decos,hidden,parentScope,chainRaise,chainMetrics)
  local style=styles[node.key];hidden=hidden or style.display=='none'
  local scope=Bidi.scope(style,parentScope or rootScope,T.source(node,objects,style))
  local baseRaise=chainRaise or 0;local ownerMetrics=chainMetrics or parentMetrics
  local record={node=node,parent=parent,fragments={},hidden=hidden,style=style,parentRaise=baseRaise,metrics=ownerMetrics,raise=baseRaise};plan.records[node.key]=record
  if not hidden and node~=root and(style.display=='ruby-text'or style.display=='ruby-text-container')then
   local group=rubyStack[#rubyStack]
   local function annotate(n,s)
    if s.display=='none'then return end
    if s.display=='ruby-text-container'then for _,c in ipairs(n.children)do annotate(c,styles[c.key])end;return end
    local parts={}
    if not n.hasGeneratedText then parts[#parts+1]=T.source(n,objects,s)end
    for _,c in ipairs(n.children)do local cs=styles[c.key];if cs.display~='none'then parts[#parts+1]=T.source(c,objects,cs)end end
    local text=table.concat(parts)
    if group and text~=''then local size=metric(text,s);group.annotations[#group.annotations+1]={key=n.key,style=s,text=text,w=math.max(.1,size.X),h=math.max(s._fontPx or 8,size.Y),decorations=decos,direction=Bidi.direction(text)}end
   end
   annotate(node,style)
   local function mark(n)for _,c in ipairs(n.children)do plan.records[c.key]={node=c,parent=n,fragments={},hidden=true,style=styles[c.key],parentRaise=baseRaise,metrics=ownerMetrics,raise=baseRaise};mark(c)end end
   mark(node)
   return
  end
  local group
  if not hidden and node~=root and style.display=='ruby'then
   group={key=node.key,style=style,annotations={},position=style['ruby-position']or 'over',align=style['ruby-align']or 'space-around',spans={}}
   plan.rubies[#plan.rubies+1]=group;rubyStack[#rubyStack+1]=group
   local baseText,annotationText,annotationStyle={},{},nil
   local function gather(n)
    local s=styles[n.key];if s.display=='none'then return end
    if s.display=='ruby-text'then annotationStyle=annotationStyle or s;if not n.hasGeneratedText then annotationText[#annotationText+1]=T.source(n,objects,s)end
    elseif s.display~='ruby-text-container'and not n.hasGeneratedText then baseText[#baseText+1]=T.source(n,objects,s)end
    for _,c in ipairs(n.children)do gather(c)end
   end
   gather(node)
   local annotationW=annotationStyle and metric(table.concat(annotationText),annotationStyle).X or 0
   local baseW=metric(table.concat(baseText),style).X
   group.pad=math.max(0,(annotationW-baseW)/2)
   if group.pad>0 then flushWord();tokens[#tokens+1]={kind='edge',key=node.key,style=style,side='start',width=group.pad,ruby=group}end
  end
  if not hidden and node~=root and Boxes.isAtomic(node,style)then
   record.atomic=true
   local measured=measureAtomic(node,style)
   if measured then
    flushWord()
    tokens[#tokens+1]={kind='atomic',node=node,style=style,c=measured,lc=logicalAtomic(measured)}
    wordStart=true
   end
   return
  end
  local childMetrics=ownerMetrics
  if not hidden and node~=root then
   local own,metrics=inlineAlign(style,ownerMetrics)
   record.raise=baseRaise+own;childMetrics=metrics
  end
  local decorations=decos
  if(style['text-decoration-line']or 'none')~='none'then decorations=table.clone(decos);decorations[#decorations+1]=style end
  local edge=(not hidden and node~=root)and edgeMetrics(style)or nil
  if edge then record.edge=edge;record.lineRects={}end
  if edge and edge.start>0 then flushWord();tokens[#tokens+1]={kind='edge',key=node.key,style=style,side='start',width=edge.start}end
  if not hidden and node.tag=='br'then flushWord();tokens[#tokens+1]={kind='break',atom={style=style}};wordStart=true end
  if not hidden and not node.hasGeneratedText and node.tag~='br'then pushText(node,style,decorations,scope)end
  for _,child in ipairs(node.children)do if styles[child.key].position~='absolute'then collect(child,node,decorations,hidden,scope,record.raise,childMetrics)end end
  if edge and edge.finish>0 then flushWord();tokens[#tokens+1]={kind='edge',key=node.key,style=style,side='end',width=edge.finish}end
  if group then
   if group.pad>0 then flushWord();tokens[#tokens+1]={kind='edge',key=node.key,style=style,side='end',width=group.pad,ruby=group}end
   table.remove(rubyStack)
  end
 end
 collect(root,nil,{},false,rootScope);flushWord()
 if firstLetterStyle then
  local first,last=Boxes.firstLetter(order)
  if first then
   local base=order[first].base or order[first].style
   local letterStyle=styleWith(base,firstLetterStyle,Boxes.firstLetterProperties)
   for index=first,last do order[index].style=letterStyle end
   local spec=Boxes.initialLetter(letterStyle)
   if spec and not vertical then
    local text={}
    for index=first,last do local atom=order[index];if not atom.soft and not atom.zero then text[#text+1]=atom.text end end
    text=table.concat(text)
    if text~=''then
     local probe=metric(text,letterStyle)
     local size,target=Boxes.initialFont(spec,rootHeight,math.max(1,probe.Y),letterStyle._fontPx or rootFs)
     local scaled=table.clone(letterStyle);scaled._fontPx=size;scaled['font-size']=tostring(size)..'px';scaled._lineHeight=target
     local bounds=metric(text,scaled)
     for index=first,last do order[index].dropped=true end
     initial={text=text,style=scaled,key=order[first].key,decorations=order[first].decorations,direction=order[first].direction,
      drawW=math.max(.1,bounds.X),drawH=math.max(size,bounds.Y),width=math.max(.1,bounds.X),sink=math.max(1,math.min(10,math.floor(spec.sink)))}
    end
   end
  end
 end
 local paragraph={}
 local function annotateParagraph()
  local parts={};for _,token in ipairs(paragraph)do for _,atom in ipairs(token.atoms or {})do parts[#parts+1]=atom.text end end
  local base=rs['unicode-bidi']=='plaintext'and Bidi.firstStrong(table.concat(parts),rs.direction)or rs.direction or 'ltr'
  if vertical and rs['text-orientation']=='upright'then base='ltr'end
  for _,token in ipairs(paragraph)do token.paragraphBase=base end;paragraph={}
 end
 for _,token in ipairs(tokens)do paragraph[#paragraph+1]=token;if token.kind=='break'then annotateParagraph()end end;annotateParagraph()
 local function segments(atoms,first,last,hyphen)
  local out={};local current
  local function emit(atom,text)
   local style=atom.style;local spacing=tonumber(style['letter-spacing'])or 0
   local upright=vertical and axes.mode:sub(1,8)~='sideways'and(style['text-orientation']=='upright'or style['text-orientation']~='sideways'and Wrap.cjk(text))
   local combine=vertical and((style['text-combine-upright']or 'none')=='all'or(style._combineDigits~=nil and text:match('^%d$')~=nil))or false
   local separate=(spacing~=0 or upright or text==utf8.char(0xa0)or text==' ')and not combine
   if current and combine and current.combine and current.key==atom.key and current.style==style and current.ruby==atom.ruby and(style._combineDigits==nil or utf8.len(current.text)<style._combineDigits)then current.text..=text
   elseif current and not combine and not current.combine and not separate and not current.separate and current.key==atom.key and current.style==style and current.direction==atom.direction and current.bidi==atom.bidi and current.ruby==atom.ruby then current.text..=text
   else current={text=text,key=atom.key,style=style,decorations=atom.decorations,direction=atom.direction,bidi=atom.bidi,separate=separate,upright=upright or combine,combine=combine,ruby=atom.ruby};out[#out+1]=current end
  end
  for i=first or 1,last or #atoms do local atom=atoms[i];if not atom.soft and not atom.zero and not atom.dropped then emit(atom,atom.text)end end
  if hyphen then local index=last or #atoms;local atom=atoms[index];while atom and(atom.soft or atom.zero or atom.dropped)do index-=1;atom=atoms[index]end;if atom then emit(atom,atom.style._hyphenateCharacter or '-')end end
  local w=0
  for _,segment in ipairs(out)do
   local size=metric(segment.text,segment.style);local fs=segment.style._fontPx or 16
   if segment.combine and size.X>fs then local scaled=table.clone(segment.style);scaled._fontPx=math.max(1,fs*fs/size.X);scaled['font-size']=tostring(scaled._fontPx)..'px';segment.style=scaled;size=metric(segment.text,scaled)end
   segment.drawW=math.max(0.1,size.X);segment.drawH=math.max(fs,size.Y)
   segment.advance=math.max(0.1,segment.upright and fs or size.X)
   if segment.separate then segment.advance=math.max(0.1,segment.advance+(tonumber(segment.style['letter-spacing'])or 0))end
   if segment.text==' 'or segment.text==utf8.char(0xa0)then segment.advance=math.max(0,segment.advance+(tonumber(segment.style['word-spacing'])or 0))end
   segment.lh=segment.style._lineHeight or fs*1.25;w+=segment.advance
  end
  return out,w
 end
 local blockY=0;local line;local endedWithBreak=false;local pendingIndex=0
 local function bandAt(top,probe)
  local left,right,nextY=0,limit,nil
  if env.band and not intrinsicMode then
   local a,b,n=env.band(top,probe)
   if a then left=math.clamp(a,0,limit);right=math.clamp(b,left,limit);nextY=n end
  end
  if initial and #plan.lines<initial.sink then
   if paragraphBase=='rtl'then right=math.max(left,right-initial.width)else left=math.min(right,left+initial.width)end
  end
  return left,right,nextY
 end
 local function newLine()
  local left,right,nextY=bandAt(blockY,strut.height)
  return {items={},width=0,height=strut.height,ascent=strut.above,descent=strut.below,base=paragraphBase,offset=left,limit=math.max(1,right-left),top=blockY,nextBand=nextY,shrunk=right-left<limit-0.01}
 end
 line=newLine()
 local function pushDown(required)
  if #line.items>0 or not line.shrunk or not required or required<=0 then return false end
  local target=math.min(required,limit);local moved=false
  for _=1,64 do
   if line.limit+0.01>=target then break end
   local nextY=line.nextBand
   if not nextY or nextY<=blockY then break end
   blockY=nextY;line=newLine();moved=true
  end
  return moved
 end
 local function finish(explicit)
  while line.items[#line.items]and line.items[#line.items].collapsible do local removed=table.remove(line.items);line.width-=removed.advance end
  if line.hyphenated then consecutiveHyphens+=1 else consecutiveHyphens=0 end
  line.explicit=explicit
  if vertical then
   line.height=math.max(line.height,strut.height);line.ascent=line.height*.8;line.descent=line.height-line.ascent
  else
   local above,total2=Boxes.resolve(line.items,strut,parentMetrics)
   line.ascent=above;line.height=math.max(strut.height,total2);line.descent=line.height-above
  end
  plan.lines[#plan.lines+1]=line;blockY+=line.height
  line=newLine();endedWithBreak=explicit==true
 end
 local function record(part)
  line.items[#line.items+1]=part;line.width+=part.advance
  if #plan.lines==0 then plan.firstLineAtoms=math.max(plan.firstLineAtoms,pendingIndex)end
  endedWithBreak=false
 end
 local function add(parts,space)
  for _,part in ipairs(parts)do
   part.collapsible=space=='collapse';part.space=space~=nil
   local fs=part.style._fontPx or 16
   part.mode,part.length=Boxes.align(part.style,fs,part.lh)
   local owner=plan.records[part.key]
   part.baseRaise=owner and owner.parentRaise or 0;part.metrics=owner and owner.metrics or parentMetrics
   local half=(part.lh-part.drawH)/2
   part.sizeAbove=part.drawH*.8+half;part.sizeBelow=part.drawH*.2+half
   if part.ruby and #part.ruby.annotations>0 then
    local h=0;for _,a in ipairs(part.ruby.annotations)do h=math.max(h,a.h)end;part.rubyH=h
    if part.ruby.position=='under'then part.sizeBelow+=h else part.sizeAbove+=h end
   end
   part.drawAbove=part.drawH*.8;part.height=part.sizeAbove+part.sizeBelow
   if vertical then line.height=math.max(line.height,part.lh+(part.rubyH or 0))end
   record(part)
  end
 end
 local function addAtomic(token)
  local style=token.style;local c=token.lc or token.c
  local owner=plan.records[token.node.key]
  local metrics=owner and owner.metrics or parentMetrics
  local mode,length=Boxes.align(style,style._fontPx or rootFs,style._lineHeight or metrics.lineHeight or rootHeight)
  local above,below,total2=Boxes.atomicMetrics(c,style)
  local part={atomic=true,node=token.node,key=token.node.key,style=style,c=token.c,lc=c,advance=math.max(0,c.w+(c.m[2]or 0)+(c.m[4]or 0)),
   baseRaise=owner and owner.parentRaise or 0,metrics=metrics,
   drawW=c.w,drawH=c.h,lh=total2,mode=mode,length=length,sizeAbove=above,sizeBelow=below,drawAbove=above,height=total2}
  if vertical then line.height=math.max(line.height,total2)end
  record(part)
 end
 local function addEdge(token)
  local style=token.style;local fs=style._fontPx or rootFs
  local lh=style._lineHeight or fs*1.25
  local drawH=math.max(fs,metric('Mg',style).Y)
  local half=(lh-drawH)/2
  local owner=plan.records[token.key]
  local mode,length=Boxes.align(style,fs,lh)
  record({edge=token.side,key=token.key,style=style,advance=token.width,drawW=0,drawH=0,lh=lh,mode=mode,length=length,
   baseRaise=owner and owner.parentRaise or 0,metrics=owner and owner.metrics or parentMetrics,
   sizeAbove=drawH*.8+half,sizeBelow=drawH*.2+half,drawAbove=drawH*.8,height=drawH+half*2})
 end
 local function breakPoints(atoms)
  local points={};local first=atoms[1];local mode=first.style.hyphens or 'manual'
  for i,atom in ipairs(atoms)do if atom.soft and mode~='none'then points[i]=true end end
  if mode=='auto'then
   local chars,indices={},{}
   for i,atom in ipairs(atoms)do if not atom.soft and not atom.zero then chars[#chars+1]=atom.text;indices[#indices+1]=i end end
   local limits=first.style._hyphenChars or {6,2,2}
   if #chars>=limits[1]then for index in pairs(N.hyphens(chars,first.style._language,hyphenation))do if indices[index]and index>=limits[2]and #chars-index>=limits[3]then points[indices[index]]=true end end end
  end
  return points
 end
 local optimized=(env.band or initial)and{}or Wrap.optimize(tokens,limit,segments,rs,checkpoint)
 for tokenIndex,token in ipairs(tokens)do
  if checkpoint then checkpoint()end
  paragraphBase=token.paragraphBase or paragraphBase;if #line.items==0 then line.base=paragraphBase end
  if optimized[tokenIndex]and #line.items>0 then finish(false);line.base=paragraphBase end
  if token.kind=='break'then pendingIndex=token.atom and token.atom.index or pendingIndex;finish(true)
  elseif token.kind=='edge'then addEdge(token)
  elseif token.kind=='atomic'then
   local lc=token.lc or token.c
   local advance=math.max(0,lc.w+(lc.m[2]or 0)+(lc.m[4]or 0))
   if not nowrap and #line.items>0 and line.width+advance>line.limit+0.01 then finish(false)end
   if not nowrap then pushDown(advance)end
   addAtomic(token)
  elseif token.kind=='space'then
   pendingIndex=token.atoms[1].index or pendingIndex
   if #line.items>0 or token.preserve then
    local parts,w=segments(token.atoms)
    if not nowrap and line.width+w>line.limit and #line.items>0 then finish(false);if token.preserve then add(parts,'preserve')end
    else add(parts,token.preserve and 'preserve'or 'collapse')end
   end
  else
   local atoms=token.atoms;local first=1;local points=breakPoints(atoms)
   while first<=#atoms do
    if checkpoint then checkpoint()end
    local parts,w=segments(atoms,first,#atoms)
    pendingIndex=atoms[#atoms].index or pendingIndex
    if not nowrap then pushDown(w)end
    if nowrap or line.width+w<=line.limit+0.01 then add(parts);break end
    local available=line.limit-line.width;local lo,hi,fit=first,#atoms,first-1
    while lo<=hi do
     local mid=math.floor((lo+hi)/2);local _,prefix=segments(atoms,first,mid)
     if prefix<=available then fit=mid;lo=mid+1 else hi=mid-1 end
    end
    local split,hyphen
    local style=atoms[first].style
    local zone=U.length(style._hyphenZone or 0,line.limit,vw,vh,style._fontPx,style._unitContext)or 0;assert(zone>=0,'hyphenate-limit-zone não pode ser negativo.')
    if consecutiveHyphens<(style._hyphenLines or math.huge)and(#line.items==0 or available>=zone)then
     for i=math.min(fit,#atoms-1),first,-1 do if points[i]then local _,prefix=segments(atoms,first,i,true);if prefix<=available then split=i;hyphen=true;break end end end
    end
    local breakAll=style['word-break']=='break-all'or style['line-break']=='anywhere'
    local emergency=style['overflow-wrap']=='anywhere'or intrinsicMode~='min-content'and(style['overflow-wrap']=='break-word'or style['word-break']=='break-word')
    if not split and(breakAll or(emergency and #line.items==0))then split=math.max(first,fit)end
    if split then
     local prefix=segments(atoms,first,split,hyphen);pendingIndex=atoms[split].index or pendingIndex;add(prefix);line.hyphenated=hyphen==true;first=split+1;finish(false)
    elseif #line.items>0 then finish(false)
    else add(parts);break end
   end
  end
 end
 if #line.items>0 or endedWithBreak then finish(false)end
 local block=0;local maxInline=0
 for _,ln in ipairs(plan.lines)do maxInline=math.max(maxInline,ln.width+(ln.offset or 0));block+=ln.height end
 plan.w=vertical and block or maxInline;plan.h=vertical and maxInline or block
 if not vertical and #plan.lines>0 then
  local aboveLines=0
  for index=1,#plan.lines-1 do aboveLines+=plan.lines[index].height end
  plan.lastBaseline=aboveLines+(plan.lines[#plan.lines].ascent or 0)
 end
 local cy=0
 for lineIndex,ln in ipairs(plan.lines)do
  local base=ln.base or rs.direction or 'ltr'
  local ordered=Bidi.visualOrder(ln.items,base);local align=rs['text-align']or 'start'
  local lastLine=lineIndex==#plan.lines or ln.explicit==true;local alignLast=rs['text-align-last']or 'auto'
  if lastLine then if alignLast~='auto'then align=alignLast elseif align=='justify'then align='start'end end
  local gaps=0;if align=='justify'then for _,part in ipairs(ordered)do if part.space then gaps+=1 end end;if gaps==0 then align='start'end end
  if align=='start'then align=base=='rtl'and 'right'or 'left'elseif align=='end'then align=base=='rtl'and 'left'or 'right'end
  local spare=math.max(0,ln.limit-ln.width);local x=(ln.offset or 0)+(align=='right'and spare or align=='center'and spare/2 or 0)
  local rects={}
  local function grow(key,fx,fy,fw,fh)
   local current=plan.records[key]
   while current do
    local b=current.bounds
    if not b then current.bounds={x=fx,y=fy,r=fx+fw,b=fy+fh}
    else b.x=math.min(b.x,fx);b.y=math.min(b.y,fy);b.r=math.max(b.r,fx+fw);b.b=math.max(b.b,fy+fh)end
    current=current.parent and plan.records[current.parent.key]or nil
   end
  end
  local function touch(key,x0,x1,side)
   local current=plan.records[key]
   while current do
    if current.edge then
     local acc=rects[current]
     if not acc then
      local style=current.style
      local draw=math.max(style._fontPx or rootFs,metric('Mg',style).Y)
      acc={line=lineIndex,x0=x0,x1=x1,y=cy+ln.ascent-(current.raise or 0)-draw*.8-current.edge.top,h=draw+current.edge.top+current.edge.bottom,startEdge=false,endEdge=false}
      rects[current]=acc;current.lineRects[#current.lineRects+1]=acc
     else acc.x0=math.min(acc.x0,x0);acc.x1=math.max(acc.x1,x1)end
     if side=='start'and current.node.key==key then rects[current].startEdge=true elseif side=='end'and current.node.key==key then rects[current].endEdge=true end
    end
    current=current.parent and plan.records[current.parent.key]or nil
   end
  end
  for _,part in ipairs(ordered)do
   local startX=x
   if part.edge then
    x+=part.advance;touch(part.key,startX,x,part.edge)
   elseif part.atomic then
    if vertical then
     local lc=part.lc or part.c;local c=part.c
     local blockPos=cy+math.max(0,(ln.height-lc.h)/2)
     local inlinePos=axes.mode=='sideways-lr'and limit-x-part.advance or x
     local px=axes.blockReverse and width-blockPos-lc.h or blockPos
     plan.atomics[#plan.atomics+1]={node=part.node,key=part.key,c=c,x=px+(c.m[4]or 0),y=inlinePos+(c.m[1]or 0),line=lineIndex}
     x+=part.advance
     grow(part.key,px,inlinePos,lc.h,part.advance);touch(part.key,startX,x)
    else
     local top=cy+(part.top or(ln.ascent-(part.drawAbove or 0)))
     plan.atomics[#plan.atomics+1]={node=part.node,key=part.key,c=part.c,x=x+(part.c.m[4]or 0),y=top+(part.c.m[1]or 0),line=lineIndex}
     x+=part.advance
     grow(part.key,startX,top,part.advance,part.height or 0);touch(part.key,startX,x)
    end
   else
    local leading=vertical and(ln.height-part.drawH)/2 or(part.top or(ln.ascent-part.drawH*.8));local bY=cy+leading
    local f={text=part.text,style=part.style,decorations=part.decorations,direction=part.direction or base,bidiOverride=part.bidiOverride,line=lineIndex,drawW=part.drawW,drawH=part.drawH,advance=part.advance,vertical=vertical,upright=part.upright,space=part.space}
    if vertical then
     local center=axes.blockReverse and width-(cy+ln.height/2)or cy+ln.height/2
     f.cx=center;f.cy=axes.mode=='sideways-lr'and limit-x-part.advance/2 or x+part.advance/2;f.rotation=part.upright and 0 or axes.mode=='sideways-lr'and -90 or 90
     local pw=part.upright and part.drawW or part.drawH;local ph=part.upright and part.drawH or part.drawW
     f.x=center-pw/2;f.y=f.cy-ph/2;f.w=pw;f.h=ph
    else f.cx=x+part.drawW/2;f.cy=bY+part.drawH/2;f.rotation=0;f.x=x;f.y=bY;f.w=part.advance;f.h=part.drawH end
    if part.ruby then
     local span=part.ruby.spans[lineIndex]
     local extent=(part.upright and part.drawW or part.drawH)/2
     if not span then span={x0=startX,x1=startX+part.advance,above=bY,below=bY+part.drawH,half=extent};part.ruby.spans[lineIndex]=span
     else span.x0=math.min(span.x0,startX);span.x1=math.max(span.x1,startX+part.advance);span.above=math.min(span.above,bY);span.below=math.max(span.below,bY+part.drawH);span.half=math.max(span.half,extent)end
    end
    local owner=plan.records[part.key];owner.fragments[#owner.fragments+1]=f;plan.fragments+=1
    assert(plan.fragments<=4096,'Mais de 4096 fragmentos inline; reduza texto ou letter-spacing.')
    grow(part.key,f.x,f.y,f.w,f.h);touch(part.key,startX,startX+part.advance)
    x+=part.advance;if part.space and gaps>0 then x+=spare/gaps end
   end
  end
  for _,group in ipairs(plan.rubies)do
   local span=group.spans[lineIndex]
   if span and #group.annotations>0 then
    local total=0;local h=0
    for _,a in ipairs(group.annotations)do total+=a.w;h=math.max(h,a.h)end
    local spanW=span.x1-span.x0;local start=span.x0;local gap=0
    if group.align=='start'then start=span.x0
    elseif group.align=='space-between'and #group.annotations>1 and spanW>total then gap=(spanW-total)/(#group.annotations-1)
    elseif spanW>total then start=span.x0+(spanW-total)/2 end
    local under=group.position=='under'
    local ax=start
    for _,a in ipairs(group.annotations)do
     local f={text=a.text,style=a.style,decorations=a.decorations,direction=a.direction or base,line=lineIndex,drawW=a.w,drawH=a.h,advance=a.w,vertical=vertical,upright=false,ruby=true,space=false}
     if vertical then
      local center=axes.blockReverse and width-(cy+ln.height/2)or cy+ln.height/2
      local side=(axes.mode=='sideways-lr')~=under and -1 or 1
      f.cx=center+side*(span.half+a.h/2);f.cy=axes.mode=='sideways-lr'and limit-ax-a.w/2 or ax+a.w/2;f.rotation=axes.mode=='sideways-lr'and -90 or 90
      f.w=a.h;f.h=a.w;f.x=f.cx-f.w/2;f.y=f.cy-f.h/2
     else
      f.rotation=0;f.x=ax;f.y=under and span.below or span.above-a.h;f.w=a.w;f.h=a.h;f.cx=f.x+a.w/2;f.cy=f.y+a.h/2
     end
     local owner=plan.records[a.key]
     if owner then owner.fragments[#owner.fragments+1]=f;plan.fragments+=1;grow(a.key,f.x,f.y,f.w,f.h)end
     ax+=a.w+gap
    end
   end
  end
  cy+=ln.height
 end
 if initial and plan.lines[1]then
  local sink=math.min(initial.sink,#plan.lines);local top=0
  for index=1,sink-1 do top+=plan.lines[index].height end
  local baseline=top+plan.lines[sink].ascent
  local ln=plan.lines[1]
  local x=paragraphBase=='rtl'and(ln.offset+ln.limit)or math.max(0,ln.offset-initial.width)
  local f={text=initial.text,style=initial.style,decorations=initial.decorations,direction=initial.direction or paragraphBase,line=1,
   drawW=initial.drawW,drawH=initial.drawH,advance=initial.width,vertical=false,upright=false,rotation=0,
   x=x,y=baseline-initial.drawH*.8,w=initial.drawW,h=initial.drawH}
  f.cx=f.x+f.drawW/2;f.cy=f.y+f.drawH/2
  local owner=plan.records[initial.key]
  if owner then
   owner.fragments[#owner.fragments+1]=f;plan.fragments+=1
   local current=owner
   while current do
    local b=current.bounds
    if not b then current.bounds={x=f.x,y=f.y,r=f.x+f.w,b=f.y+f.h}
    else b.x=math.min(b.x,f.x);b.y=math.min(b.y,f.y);b.r=math.max(b.r,f.x+f.w);b.b=math.max(b.b,f.y+f.h)end
    current=current.parent and plan.records[current.parent.key]or nil
   end
   plan.initialLetter={x=f.x,y=f.y,w=f.w,h=f.h,sink=sink}
  end
 end
 for _,item in pairs(plan.records)do
  if item.lineRects then
   for _,rect in ipairs(item.lineRects)do
    if vertical and not rect.physical then
     local x0,x1,y,h=rect.x0,rect.x1,rect.y,rect.h
     local py=axes.mode=='sideways-lr'and limit-x1 or x0
     local px=axes.blockReverse and width-y-h or y
     rect.x0=px;rect.x1=px+h;rect.y=py;rect.h=x1-x0;rect.physical=true
    end
    local b=item.bounds
    if not b then item.bounds={x=rect.x0,y=rect.y,r=rect.x1,b=rect.y+rect.h}
    else b.x=math.min(b.x,rect.x0);b.y=math.min(b.y,rect.y);b.r=math.max(b.r,rect.x1);b.b=math.max(b.b,rect.y+rect.h)end
   end
  end
 end
 return plan
end
function T.layout(root,styles,objects,width,height,vw,vh,checkpoint,hyphenation,segmentation,intrinsicMode,env)
 env=env or {}
 serial+=1;local stamp=serial
 local pseudo=root.linePseudo
 local firstLineStyle=pseudo and pseudo['first-line']or nil
 local firstLetterStyle=pseudo and pseudo['first-letter']or nil
 local plan=build(stamp,root,styles,objects,width,height,vw,vh,checkpoint,hyphenation,segmentation,intrinsicMode,env,firstLineStyle,firstLetterStyle,nil)
 if firstLineStyle then
  local applied=nil
  for _=1,2 do
   local count=plan.firstLineAtoms or 0
   if count<=0 or count==applied then break end
   applied=count
   plan=build(stamp,root,styles,objects,width,height,vw,vh,checkpoint,hyphenation,segmentation,intrinsicMode,env,firstLineStyle,firstLetterStyle,count)
  end
 end
 return plan
end
function T.install(plan,root,styles,boxes,rootBox)
 local p=rootBox.p;local contentH=math.max(0,rootBox.h-p[1]-p[3]);local align=styles[root.key]['vertical-align']or 'middle'
 local offset=0
 if styles[root.key]['writing-mode']=='horizontal-tb'and contentH>plan.h then
  if align=='middle'or align=='center'then offset=(contentH-plan.h)/2 elseif align=='bottom'then offset=contentH-plan.h end
 end
 plan.offsetY=offset
 if plan.lastBaseline then rootBox.inlineBaseline=plan.lastBaseline+p[1]+offset end
 local function assign(node,parentOrigin)
  local item=plan.records[node.key];if not item or item.atomic then return end
  local b=item.bounds or {x=0,y=0,r=0,b=0};local origin={x=b.x+p[4],y=b.y+p[1]+offset}
  local box
  if node==root then box=rootBox;origin={x=0,y=0}
  else
   box={x=origin.x-parentOrigin.x,y=origin.y-parentOrigin.y,w=math.max(0,b.r-b.x),h=math.max(0,b.b-b.y),fs=styles[node.key]._fontPx or rootBox.fs,p={0,0,0,0},hidden=item.hidden,contentW=math.max(0,b.r-b.x),contentH=math.max(0,b.b-b.y)}
   boxes[node.key]=box
  end
  box.inlineManaged=true;box.inlineStamp=plan.stamp;box.inlineFragments={};box.inlineRoot=root.key;box.lineCount=#plan.lines
  for _,f in ipairs(item.fragments)do
   local copy=table.clone(f);copy.x=f.x+p[4]-origin.x;copy.y=f.y+p[1]+offset-origin.y;copy.cx=f.cx+p[4]-origin.x;copy.cy=f.cy+p[1]+offset-origin.y
   box.inlineFragments[#box.inlineFragments+1]=copy
  end
  if item.lineRects and #item.lineRects>0 then
   local rects={};local count=#item.lineRects;local clone=item.edge and item.edge.clone or false;local rtl=item.edge and item.edge.rtl or false
   for index,rect in ipairs(item.lineRects)do
    local startEdge,endEdge=Boxes.edges(count,index,clone,rtl)
    rects[#rects+1]={x=rect.x0+p[4]-origin.x,y=rect.y+p[1]+offset-origin.y,w=math.max(0,rect.x1-rect.x0),h=rect.h,line=rect.line,
     startEdge=clone or rect.startEdge or startEdge,endEdge=clone or rect.endEdge or endEdge,widths=item.edge and item.edge.widths or nil,rtl=rtl}
   end
   box.inlineFragmentRects=rects;box.inlineSplit=count
  end
  for _,child in ipairs(node.children)do assign(child,origin)end
 end
 assign(root,{x=0,y=0})
 rootBox.contentW=math.max(rootBox.contentW,plan.w+p[2]+p[4]);rootBox.contentH=math.max(rootBox.contentH,plan.h+p[1]+p[3])
end
return T
