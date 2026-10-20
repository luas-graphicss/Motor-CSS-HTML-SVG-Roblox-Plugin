local U=require(script.Parent.Util)
local Units=require(script.Parent.StyleUnits)
local Variables=require(script.Parent.CssVariables)
local Optimizer=require(script.Parent.StyleOptimizer)
local Queries=require(script.Parent.ResponsiveQueries)
local ColorTheme=require(script.Parent.ColorTheme)
local Cascade=require(script.Parent.CssCascade)
local P={VERSION=3}
local Typography=require(script.Parent.TypographyStyle)
local Logical=require(script.Parent.LogicalProperties)
local FontFaces=require(script.Parent.FontFaces)
local Generated=require(script.Parent.GeneratedContent)
local Counters=require(script.Parent.CssCounters)
local Containment=require(script.Parent.CssContainment)
local Selectors=require(script.Parent.Selectors)
local inherited=Optimizer.inherited
local textTags={label=true,text=true,p=true,span=true,h1=true,h2=true,h3=true,button=true,input=true,textarea=true,li=true}
local ORDER={marker=0.004,before=0.01,['file-selector-button']=0.02,after=0.99}
local boxKinds=table.freeze({marker=true,before=true,['file-selector-button']=true,after=true})
local interfaceKinds=table.freeze({placeholder=true,selection=true})
local lineKinds=table.freeze({['first-line']=true,['first-letter']=true})
P.boxKinds=boxKinds
P.interfaceKinds=interfaceKinds
P.lineKinds=lineKinds
function P.content(value,attrs)
 if value==nil then return nil end
 local text,image=Generated.text(value,attrs or {})
 if text==nil or(image and text=='')then return nil end
 return text
end
function P.expand(root,rules,state,width,height,styles,sequence,parents,match,resolve,expand,newStyle,session,prepared)
 local layerOrder=session and session.layerOrder or Cascade.order(rules[1]and rules[1].layerEvents,width,height,session and session.mediaEnvironment)
 local byKind={marker={},before={},['file-selector-button']={},after={},placeholder={},selection={},['first-line']={},['first-letter']={}}
 local pseudoRules=0
 for _,rule in ipairs(rules)do
  local kind=rule.selector.pseudoElement
  if kind and byKind[kind]and Queries.mediaActive(rule,width,height,session and session.mediaEnvironment)then
   local bucket=byKind[kind];bucket[#bucket+1]=rule;pseudoRules+=1
  end
 end
 state=state or {}
 local custom=Counters.registry(prepared and prepared.counterStyles,width)
 local needsCounters=false
 for _,node in ipairs(sequence)do
  local style=styles[node.key]
  if style and(node.tag=='li'or style.display=='list-item'or style['counter-reset']or style['counter-increment']or style['counter-set'])then needsCounters=true;break end
 end
 local rootStyle=styles[root.key]
 if pseudoRules==0 and not needsCounters and not(rootStyle and rootStyle._page and rootStyle._page.marginDeclarations)then return styles,sequence,parents,root end
 local scope=Counters.scope()
 local quoteCache={}
 local function quotesFor(style)
  local value=style and style.quotes or 'auto'
  local cached=quoteCache[value]
  if cached==nil then cached=Counters.quotes(value)or false;quoteCache[value]=cached end
  return cached or nil
 end
 local visualSequence,visualParents={},{}
 local total=0
 local function append(node,parent)
  visualSequence[#visualSequence+1]=node;visualParents[node.key]=parent
 end
 local finishStyle
 local function computeStyle(owner,kind,ownerStyle,requireContent)
  local key=owner.key..'::'..kind
  local pseudo={key=key,tag='span',attrs={},children={},text='',order=owner.order+(ORDER[kind]or 0.5),pseudoElement=kind,generated=true,ownerKey=owner.key}
  local cascade
  if session then
   session.cascadeKeys[key]='_pseudo:'..kind..':'..session.cascadeKeys[owner.key]
   cascade=Optimizer.getCascade(session,pseudo)
  end
  local winners=cascade and cascade.winners or {}
  if not cascade then
   local candidates=session and Optimizer.candidates(session,owner)or byKind[kind]
   for _,candidate in ipairs(candidates)do
    local rule=session and rules[candidate]or candidate;local sel=rule.selector
    if sel.pseudoElement==kind and(session and Optimizer.ruleActive(session,owner,candidate)or not session and Queries.matches(rule,width,height,nil,owner,parents,nil))then
     local matched,proximity
     if rule.scope then matched,proximity=Selectors.scoped(rule.scope,sel.ownerSelector,owner,state,parents,session and session.classes)
     else matched=match(sel.ownerSelector,owner,state,parents,session and session.classes) end
     if matched then Cascade.apply(winners,rule.declarations,sel.specificity,rule.order,rule.layer,false,layerOrder,rule.origin,proximity)end
    end
   end
   Cascade.finish(winners)
   if session then cascade=Optimizer.putCascade(session,pseudo,winners)end
  end
  local styled=next(winners)~=nil
  if requireContent and not winners.content then return nil end
  if(interfaceKinds[kind]or lineKinds[kind])and not styled then return nil end
  local computedKey=session and Optimizer.computedKey(session,pseudo,ownerStyle,cascade)
  local style=finishStyle(pseudo,key,winners,ownerStyle,kind,computedKey)
  return pseudo,style,styled
 end
 finishStyle=function(pseudo,key,winners,ownerStyle,kind,computedKey)
  local style=computedKey and Optimizer.getComputed(session,computedKey)
  if not style then
  local vars=Variables.compute(ownerStyle._vars,winners)
  style=newStyle(pseudo,ownerStyle);style._vars=vars;style._important={};style._mediaEnvironment=ownerStyle._mediaEnvironment
  for property,d in pairs(winners)do if property:sub(1,2)~='--'then
   local value=resolve(d.value,vars)
   if d.shorthand then value=expand(d.shorthand,value)[property]end
   style[property]=Logical.supported[property]and value or Cascade.wide(value,property,ownerStyle,Optimizer.defaults,inherited);style._important[property]=d.important==true
   if property=='vertical-align'then style._alignSet=true end
  end end
  for _,property in ipairs(inherited)do if style[property]=='inherit'then style[property]=ownerStyle[property]end end
  if kind and lineKinds[kind]then
   local declared={}
   for property in pairs(winners)do if property:sub(1,2)~='--'then declared[property]=true end end
   style._declared=declared
  end
  Logical.resolve(style,winners,ownerStyle)
  ColorTheme.normalize(style,ownerStyle,style._mediaEnvironment)
  require(script.Parent.AdvancedCssSupport).validate(style)
  Typography.prepare(style,ownerStyle)
  FontFaces.compute(style,prepared and prepared.fontFaces,width,height,prepared and prepared.fontVariants)
  Units.normalize(style,ownerStyle,width,height,prepared and prepared.units,false,session and session.unitContexts and session.unitContexts[key],session and session.viewport)
  Logical.finish(style)
  Typography.normalize(style,ownerStyle,width,height)
  if computedKey then Optimizer.putComputed(session,computedKey,style)end
  end
  return style
 end
 local function place(node,pseudo,style,text,image,alt)
  if style.display=='none'then return nil end
  pseudo.text=text or ''
  if image then
   style=table.clone(style)
   style['background-image']='url('..image..')'
   style['background-repeat']='no-repeat'
   style['background-size']='contain'
   pseudo.generatedImage=image;pseudo.altText=alt;pseudo.text=''
  end
  styles[pseudo.key]=style
  total+=1;assert(total<=600,'Maximo de 600 pseudo-elementos por interface.')
  node.children[#node.children+1]=pseudo;append(pseudo,node)
  return pseudo
 end
 local function contentOf(style,owner,ownerStyle)
  local parsed=Generated.parse(style.content)
  if parsed.mode~='list'then return nil,nil,parsed.mode,nil end
  local text,image,alt=Generated.resolve(parsed,{attrs=owner.attrs,scope=scope,styles=custom,quotes=quotesFor(ownerStyle),dpr=ownerStyle._mediaEnvironment and ownerStyle._mediaEnvironment.devicePixelRatio or 1})
  return text,image,'list',alt
 end
 local marginDefaults={
  ['top-left-corner']={'right','bottom'},['top-left']={'left','bottom'},['top-center']={'center','bottom'},['top-right']={'right','bottom'},['top-right-corner']={'left','bottom'},
  ['bottom-left-corner']={'right','top'},['bottom-left']={'left','top'},['bottom-center']={'center','top'},['bottom-right']={'right','top'},['bottom-right-corner']={'left','top'},
  ['left-top']={'center','top'},['left-middle']={'center','middle'},['left-bottom']={'center','bottom'},
  ['right-top']={'center','top'},['right-middle']={'center','middle'},['right-bottom']={'center','bottom'}}
 local function distribute(a,b,c,S,field)
  local wa,wb,wc=0,0,0
  if b then
   wb=math.min(b[field],S);wa=(S-wb)/2;wc=wa
  elseif a and c then
   local t=a[field]+c[field]
   if t<=0 then wa=S/2;wc=S/2 else wa=math.clamp(S*a[field]/t,0,S);wc=S-wa end
  elseif a then wa=S elseif c then wc=S end
  return wa,wb,wc
 end
 local function pageMargins(node,owner,ownerStyle)
  local page=ownerStyle._page;local declarations=page.marginDeclarations
  if not declarations or next(declarations)==nil then return end
  local m=page.margins or {}
  local W,H=page.width or width,page.height or height
  local ml,mr,mt,mb=m.left or 0,m.right or 0,m.top or 0,m.bottom or 0
  scope:reset('page',1);scope:reset('pages',1)
  local entries={}
  for name,list in pairs(declarations)do
   if marginDefaults[name]then
    local pseudo={key=owner.key..'::page-'..name,tag='span',attrs={},children={},text='',order=owner.order+0.995,pseudoElement='page-margin',pageMargin=name,generated=true,ownerKey=owner.key}
    local winners={}
    Cascade.apply(winners,list,0,0,nil,false,layerOrder)
    Cascade.finish(winners)
    local style=finishStyle(pseudo,pseudo.key,winners,ownerStyle,nil,nil)
    if style.content and style.content~='normal'and style.content~='none'and style.display~='none'then
     local text,image,mode,alt=contentOf(style,owner,ownerStyle)
     if mode=='list'and((text and text~='')or image)then
      local defaults=marginDefaults[name]
      if not winners['text-align']then style['text-align']=defaults[1]end
      if not winners['vertical-align']then style['vertical-align']=defaults[2]end
      local fs=tonumber(style._fontPx)or tonumber(style['font-size'])or 16
      local w,h=0,fs*1.2
      if text and text~=''then
       local ok,size=pcall(function()return game:GetService('TextService'):GetTextSize(text,math.clamp(fs,1,100),U.font(style),Vector2.new(100000,100000))end)
       if ok and size then w,h=size.X,size.Y else w=utf8.len(text)*fs*0.55 end
      end
      entries[name]={pseudo=pseudo,style=style,text=text,image=image,alt=alt,w=w,h=h}
     end
    end
   end
  end
  if next(entries)==nil then return end
  local function put(entry,x,y,w,h)
   if not entry or w<=0 or h<=0 then return end
   local style=entry.style
   style.display='block';style.position='absolute'
   style.left=x..'px';style.top=y..'px';style.width=w..'px';style.height=h..'px'
   style['margin-top']='0';style['margin-right']='0';style['margin-bottom']='0';style['margin-left']='0'
   style['white-space']=style['white-space']or 'nowrap'
   place(node,entry.pseudo,style,entry.text,entry.image,entry.alt)
  end
  put(entries['top-left-corner'],0,0,ml,mt);put(entries['top-right-corner'],W-mr,0,mr,mt)
  put(entries['bottom-left-corner'],0,H-mb,ml,mb);put(entries['bottom-right-corner'],W-mr,H-mb,mr,mb)
  local S=W-ml-mr
  local wa,wb,wc=distribute(entries['top-left'],entries['top-center'],entries['top-right'],S,'w')
  put(entries['top-left'],ml,0,wa,mt);put(entries['top-center'],ml+(S-wb)/2,0,wb,mt);put(entries['top-right'],ml+S-wc,0,wc,mt)
  wa,wb,wc=distribute(entries['bottom-left'],entries['bottom-center'],entries['bottom-right'],S,'w')
  put(entries['bottom-left'],ml,H-mb,wa,mb);put(entries['bottom-center'],ml+(S-wb)/2,H-mb,wb,mb);put(entries['bottom-right'],ml+S-wc,H-mb,wc,mb)
  S=H-mt-mb
  wa,wb,wc=distribute(entries['left-top'],entries['left-middle'],entries['left-bottom'],S,'h')
  put(entries['left-top'],0,mt,ml,wa);put(entries['left-middle'],0,mt+(S-wb)/2,ml,wb);put(entries['left-bottom'],0,mt+S-wc,ml,wc)
  wa,wb,wc=distribute(entries['right-top'],entries['right-middle'],entries['right-bottom'],S,'h')
  put(entries['right-top'],W-mr,mt,mr,wa);put(entries['right-middle'],W-mr,mt+(S-wb)/2,mr,wb);put(entries['right-bottom'],W-mr,mt+S-wc,mr,wc)
 end
 local function walk(owner,parent)
  local node=U.copy(owner);node.children={};append(node,parent)
  local ownerStyle=styles[owner.key]
  local real=ownerStyle~=nil and not owner.anonymousText and not owner.generated
  local listItem=real and(ownerStyle.display=='list-item'or(owner.tag=='li'and ownerStyle.display~='none'and ownerStyle.display~='inline'))
  if real then
   local counterStyle=ownerStyle
   if listItem and ownerStyle.display~='list-item'then counterStyle=table.clone(ownerStyle);counterStyle.display='list-item'end
   local containFlags=Containment.state(ownerStyle,false)
   Counters.enter(scope,counterStyle,owner,containFlags~=nil and containFlags.style==true)
  end
  local marker,markerStyle,before,beforeStyle,after,afterStyle,button,buttonStyle
  if real then
   if listItem then marker,markerStyle=computeStyle(owner,'marker',ownerStyle,false)end
   if #byKind.before>0 then before,beforeStyle=computeStyle(owner,'before',ownerStyle,true)end
   if #byKind.after>0 then after,afterStyle=computeStyle(owner,'after',ownerStyle,true)end
   if owner.tag=='input'and owner.attrs.type=='file'then button,buttonStyle=computeStyle(owner,'file-selector-button',ownerStyle,false)end
   for kind in pairs(interfaceKinds)do
    if #byKind[kind]>0 then
     local _,style,styled=computeStyle(owner,kind,ownerStyle,false)
     if styled and style then node.interfacePseudo=node.interfacePseudo or {};node.interfacePseudo[kind]=style end
    end
   end
   for kind in pairs(lineKinds)do
    if #byKind[kind]>0 then
     local _,style,styled=computeStyle(owner,kind,ownerStyle,false)
     if styled and style and style.display~='none'then node.linePseudo=node.linePseudo or {};node.linePseudo[kind]=style end
    end
   end
  end
  if marker then
   local text,image,alt
   if markerStyle.content and markerStyle.content~='normal'then
    local t,img,mode,label=contentOf(markerStyle,owner,ownerStyle)
    if mode=='list'then text,image,alt=t,img,label end
   end
   if text==nil and image==nil then text,image=Counters.marker(ownerStyle,custom,scope:value('list-item'))end
   if(text~=nil and text~='')or image then place(node,marker,markerStyle,text,image,alt)end
  end
  if before then
   local text,image,mode,alt=contentOf(beforeStyle,owner,ownerStyle)
   if mode=='list'then place(node,before,beforeStyle,text,image,alt)end
  end
  if button then
   local text,image,alt
   if buttonStyle.content and buttonStyle.content~='normal'then
    local t,img,mode,label=contentOf(buttonStyle,owner,ownerStyle)
    if mode=='list'then text,image,alt=t,img,label end
   end
   if text==nil and image==nil then text=owner.attrs['data-button-label']or'Escolher arquivo'end
   place(node,button,buttonStyle,text,image,alt)
  end
  if(marker or before or after or button)and textTags[owner.tag]and not owner.mixedInline and ownerStyle then
   local slot={key=owner.key..'::text',tag='span',attrs={},children={},text=owner.text,order=owner.order+0.5,pseudoText=true,textOwnerKey=owner.key,generated=true,ownerKey=owner.key}
   local slotStyle=newStyle(slot,ownerStyle);slotStyle._vars=ownerStyle._vars;slotStyle._important={};slotStyle._mediaEnvironment=ownerStyle._mediaEnvironment
   ColorTheme.normalize(slotStyle,ownerStyle,slotStyle._mediaEnvironment)
   Logical.resolve(slotStyle,{},ownerStyle)
   Typography.prepare(slotStyle,ownerStyle)
   FontFaces.compute(slotStyle,prepared and prepared.fontFaces,width,height,prepared and prepared.fontVariants)
   Units.normalize(slotStyle,ownerStyle,width,height,prepared and prepared.units,false,session and session.unitContexts and session.unitContexts[slot.key],session and session.viewport)
   Logical.finish(slotStyle)
   Typography.normalize(slotStyle,ownerStyle,width,height)
   styles[slot.key]=slotStyle;node.hasGeneratedText=true;node.textSlotKey=slot.key
   node.children[#node.children+1]=slot;append(slot,node)
  end
  for _,child in ipairs(owner.children)do node.children[#node.children+1]=walk(child,node)end
  if after then
   local text,image,mode,alt=contentOf(afterStyle,owner,ownerStyle)
   if mode=='list'then place(node,after,afterStyle,text,image,alt)end
  end
  if real and owner==root and ownerStyle._page then pageMargins(node,owner,ownerStyle)end
  if real then Counters.exit(scope)end
  return node
 end
 local visualRoot=walk(root,nil)
 return styles,visualSequence,visualParents,visualRoot
end
function P.reconcile(objects,cache,sequence,pool)
 local active={};for _,node in ipairs(sequence)do active[node.key]=true end
 for key,object in pairs(objects)do
  if not active[key]and object:GetAttribute('CssPseudoElement')then
   pool.releaseTree(object);objects[key]=nil;cache[key]=nil
  end
 end
end
function P.removeOwner(ownerKey,objects,cache,pool,motion)
 local prefix=ownerKey..'::'
 for key,object in pairs(objects)do
  if key:sub(1,#prefix)==prefix then
   if motion then motion:remove(key)end
   pool.releaseTree(object);objects[key]=nil;cache[key]=nil
  end
 end
end
return P
