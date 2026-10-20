local Dom=require(script.Parent.Dom)
local Tokenizer=require(script.Parent.HtmlTokenizer)
local Cost=require(script.Parent.CostModel)
local B={VERSION=1}
local function set(list)
 local out={}
 for word in list:gmatch('%S+')do out[word]=true end
 return table.freeze(out)
end
local closesParagraph=set('address article aside blockquote center details dialog dir div dl fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hgroup hr listing main menu nav ol p pre search section summary table ul xmp')
local headTags=set('base basefont bgsound link meta noframes noscript script style template title')
local headVoid=set('base basefont bgsound link meta')
local formattingTags=set('a b big code em font i nobr s small strike strong tt u')
local headings=set('h1 h2 h3 h4 h5 h6')
local tableTags=set('caption col colgroup tbody td tfoot th thead tr')
local sections=set('tbody tfoot thead')
local cells=set('td th')
local impliedTags=set('dd dt li optgroup option p rb rp rt rtc')
local baseScope=set('applet caption html marquee object table td th template')
local buttonScope=set('button')
local listScope=set('ol ul')
local tableScopeOnly=set('html table template')
local fosterTargets=set('table tbody tfoot thead tr')
local special=set('address applet area article aside base basefont bgsound blockquote body br button caption center col colgroup dd details dir div dl dt embed fieldset figcaption figure footer form frame frameset h1 h2 h3 h4 h5 h6 head header hgroup hr html iframe img input keygen li link listing main marquee menu meta nav noembed noframes noscript object ol p param plaintext pre script search section select source style summary table tbody td template textarea tfoot th thead title tr track ul wbr xmp')
local voidTags=Dom.voidTags
B.closesParagraph=closesParagraph
B.formattingTags=formattingTags
local function construct(tokens,options)
 options=options or {}
 local checkpoint=options.checkpoint
 local diagnostics=options.diagnostics
 local function note(message,token)
  if diagnostics and #diagnostics<64 then diagnostics[#diagnostics+1]={kind='tree',message=message,offset=token and token.offset}end
 end
 local doc=Dom.document()
 local open={}
 local formattingList={}
 local context=options.context
 local mode='initial'
 local htmlElement,head,body,contextElement
 local nodes=0
 local maxDepth=Cost.limits().depth or 64
 local skipNewline=false
 local function budget()
  nodes+=1
  Cost.cap('nodes',nodes,'Nos do documento')
 end
 local function current()return open[#open]end
 local function pushOpen(element)
  open[#open+1]=element
  assert(#open<=maxDepth+8,'Arvore profunda demais.')
 end
 local function popOpen()
  local element=open[#open]
  open[#open]=nil
  return element
 end
 local function isOpen(element)
  for _,value in ipairs(open)do if value==element then return true end end
  return false
 end
 local function insertionPoint(foster)
  local target=current()
  if foster and target and fosterTargets[target.tag]then
   for index=#open,1,-1 do
    if open[index].tag=='table'then
     local tableElement=open[index]
     if tableElement.parent then return tableElement.parent,tableElement end
     return open[index-1]or doc,nil
    end
   end
  end
  return target or doc,nil
 end
 local function insertNode(node,foster)
  local parent,reference=insertionPoint(foster)
  if reference then parent:insertBefore(node,reference)else parent:appendChild(node)end
  return node
 end
 local function insertText(text)
  if text==''then return end
  local parent,reference=insertionPoint(true)
  local index=reference and parent:indexOf(reference)or #parent.children+1
  local previous=parent.children[index-1]
  if previous and previous.kind==Dom.TEXT then
   previous.data..=text
   return
  end
  budget()
  local node=Dom.text(text)
  if reference then parent:insertBefore(node,reference)else parent:appendChild(node)end
 end
 local function createElement(name,attrs)
  assert(name~='foreignobject','foreignObject nao e aceito nesta arvore.')
  if name=='script'then note('Script inerte: o conteudo nunca executa.')end
  budget()
  return Dom.element(name,attrs)
 end
 local function insertElement(token,keepOpen)
  local element=createElement(token.name,token.attrs)
  insertNode(element,not tableTags[token.name])
  if keepOpen~=false then pushOpen(element)end
  return element
 end
 local function inScope(tag,extra)
  for index=#open,1,-1 do
   local element=open[index]
   if element.tag==tag then return true end
   if baseScope[element.tag]or(extra and extra[element.tag])then return false end
  end
  return false
 end
 local function inTableScope(tag)
  for index=#open,1,-1 do
   local element=open[index]
   if element.tag==tag then return true end
   if tableScopeOnly[element.tag]then return false end
  end
  return false
 end
 local function generateImplied(except)
  while #open>0 do
   local tag=current().tag
   if impliedTags[tag]and tag~=except then popOpen()else break end
  end
 end
 local function popUntil(tag)
  for index=#open,1,-1 do
   if open[index].tag==tag then
    for position=#open,index,-1 do open[position]=nil end
    return true
   end
  end
  return false
 end
 local function closeTag(tag)
  generateImplied(tag)
  return popUntil(tag)
 end
 local function addMarker()formattingList[#formattingList+1]='marker'end
 local function clearToMarker()
  while #formattingList>0 do
   local entry=formattingList[#formattingList]
   formattingList[#formattingList]=nil
   if entry=='marker'then break end
  end
 end
 local function removeFormatting(element)
  for index=#formattingList,1,-1 do
   if formattingList[index]==element then
    table.remove(formattingList,index)
    return
   end
  end
 end
 local function formattingEntry(tag)
  for index=#formattingList,1,-1 do
   local entry=formattingList[index]
   if entry=='marker'then return nil end
   if entry.tag==tag then return entry,index end
  end
  return nil
 end
 local function reconstructFormatting()
  local count=#formattingList
  if count==0 then return end
  local last=formattingList[count]
  if last=='marker'or isOpen(last)then return end
  local index=count
  while index>1 do
   local entry=formattingList[index-1]
   if entry=='marker'or isOpen(entry)then break end
   index-=1
  end
  for position=index,count do
   local entry=formattingList[position]
   if entry~='marker'then
    local clone=createElement(entry.tag,entry.attrs)
    insertNode(clone,true)
    pushOpen(clone)
    formattingList[position]=clone
   end
  end
 end
 local function stackIndexOf(element)
  for index=#open,1,-1 do
   if open[index]==element then return index end
  end
  return nil
 end
 local function formattingIndexOf(element)
  for index=#formattingList,1,-1 do
   if formattingList[index]==element then return index end
  end
  return nil
 end
 local function placeInto(parent,child)
  if fosterTargets[parent.tag]then
   for index=#open,1,-1 do
    if open[index].tag=='table'then
     local tableElement=open[index]
     if tableElement.parent then tableElement.parent:insertBefore(child,tableElement)return end
     break
    end
   end
  end
  parent:appendChild(child)
 end
 local function adoption(tag)
  local bottom=current()
  if bottom and bottom.tag==tag and not formattingIndexOf(bottom)then
   popOpen()
   return true
  end
  if not formattingEntry(tag)then return false end
  for _=1,8 do
   local entry,listIndex=formattingEntry(tag)
   if not entry then return true end
   local entryIndex=stackIndexOf(entry)
   if not entryIndex then
    table.remove(formattingList,listIndex)
    return true
   end
   if not inScope(tag)then return true end
   local furthestIndex=nil
   for index=entryIndex+1,#open do
    if special[open[index].tag]then furthestIndex=index break end
   end
   if not furthestIndex then
    for index=#open,entryIndex,-1 do open[index]=nil end
    table.remove(formattingList,listIndex)
    return true
   end
   local furthest=open[furthestIndex]
   local ancestor=open[entryIndex-1]
   local bookmark=listIndex
   local lastNode=furthest
   local cursor=furthestIndex
   local inner=0
   while true do
    inner+=1
    cursor-=1
    local walking=open[cursor]
    if walking==nil or walking==entry then break end
    local walkingList=formattingIndexOf(walking)
    if inner>3 and walkingList then
     table.remove(formattingList,walkingList)
     if walkingList<bookmark then bookmark-=1 end
     walkingList=nil
    end
    if not walkingList then
     table.remove(open,cursor)
     furthestIndex-=1
    else
     local clone=createElement(walking.tag,walking.attrs)
     formattingList[walkingList]=clone
     open[cursor]=clone
     clone:appendChild(lastNode)
     lastNode=clone
    end
   end
   placeInto(ancestor or doc,lastNode)
   local replacement=createElement(entry.tag,entry.attrs)
   for _,child in ipairs(table.clone(furthest.children))do replacement:appendChild(child)end
   furthest:appendChild(replacement)
   local removedAt=formattingIndexOf(entry)
   if removedAt then
    table.remove(formattingList,removedAt)
    if removedAt<bookmark then bookmark-=1 end
   end
   table.insert(formattingList,math.clamp(bookmark,1,#formattingList+1),replacement)
   local oldIndex=stackIndexOf(entry)
   if oldIndex then table.remove(open,oldIndex)end
   local furthestPosition=stackIndexOf(furthest)
   table.insert(open,(furthestPosition or #open)+1,replacement)
  end
  return true
 end
 local function resetMode()
  for index=#open,1,-1 do
   local tag=open[index].tag
   if cells[tag]then mode='inCell'return end
   if tag=='tr'then mode='inRow'return end
   if sections[tag]then mode='inTableBody'return end
   if tag=='caption'then mode='inCaption'return end
   if tag=='colgroup'then mode='inColumnGroup'return end
   if tag=='table'then mode='inTable'return end
   if tag=='select'then mode='inSelect'return end
   if tag=='body'then mode='inBody'return end
  end
  mode='inBody'
 end
 local handlers={}
 local function process(token)
  handlers[mode](token)
 end
 local function ensureHtml(token)
  if htmlElement then return end
  htmlElement=createElement('html',token and token.name=='html'and token.attrs or nil)
  doc:appendChild(htmlElement)
  pushOpen(htmlElement)
  doc.documentElement=htmlElement
 end
 local function ensureHead()
  ensureHtml()
  if head then return end
  head=createElement('head')
  htmlElement:appendChild(head)
  doc.head=head
 end
 local function ensureBody()
  ensureHead()
  if not body then
   body=createElement('body')
   htmlElement:appendChild(body)
   doc.body=body
  end
  if not isOpen(body)then pushOpen(body)end
 end
 local function whitespaceOnly(text)return text:match('^%s*$')~=nil end
 handlers.initial=function(token)
  if token.type=='doctype'then
   doc.doctype=token.name
   mode='beforeHtml'
   return
  end
  if token.type=='character'and whitespaceOnly(token.data)then return end
  if token.type=='comment'then return end
  if token.type=='eof'then return end
  mode='beforeHtml'
  process(token)
 end
 handlers.beforeHtml=function(token)
  if token.type=='character'and whitespaceOnly(token.data)then return end
  if token.type=='comment'then return end
  if token.type=='eof'then return end
  if token.type=='startTag'and token.name=='html'then
   ensureHtml(token)
   mode='beforeHead'
   return
  end
  ensureHtml()
  mode='beforeHead'
  process(token)
 end
 handlers.beforeHead=function(token)
  if token.type=='character'and whitespaceOnly(token.data)then return end
  if token.type=='comment'then return end
  if token.type=='doctype'then return end
  if token.type=='startTag'and token.name=='html'then
   for key,value in pairs(token.attrs or{})do if htmlElement.attrs[key]==nil then htmlElement.attrs[key]=value end end
   return
  end
  if token.type=='startTag'and token.name=='head'then
   head=insertElement(token)
   doc.head=head
   mode='inHead'
   return
  end
  if token.type=='eof'then
   ensureBody()
   mode='inBody'
   return
  end
  ensureHead()
  pushOpen(head)
  mode='inHead'
  process(token)
 end
 handlers.inHead=function(token)
  if token.type=='character'then
   local tag=current()and current().tag
   if tag=='style'or tag=='title'or tag=='noframes'or tag=='noscript'or tag=='script'or tag=='template'then insertText(token.data)return end
   if whitespaceOnly(token.data)then return end
   popUntil('head')
   mode='afterHead'
   process(token)
   return
  end
  if token.type=='comment'then
   budget()
   insertNode(Dom.comment(token.data))
   return
  end
  if token.type=='doctype'then return end
  if token.type=='startTag'then
   if token.name=='head'then return end
   if headTags[token.name]then
    local element=insertElement(token,not headVoid[token.name])
    if headVoid[token.name]then return end
    if token.selfClosing then popOpen()end
    return
   end
   popUntil('head')
   mode='afterHead'
   process(token)
   return
  end
  if token.type=='endTag'then
   if token.name=='head'then
    popUntil('head')
    mode='afterHead'
    return
   end
   if headTags[token.name]then
    popUntil(token.name)
    return
   end
   popUntil('head')
   mode='afterHead'
   process(token)
   return
  end
  popUntil('head')
  mode='afterHead'
  process(token)
 end
 handlers.afterHead=function(token)
  if token.type=='character'and whitespaceOnly(token.data)then return end
  if token.type=='comment'then return end
  if token.type=='doctype'then return end
  if token.type=='startTag'and token.name=='body'then
   body=insertElement(token)
   doc.body=body
   mode='inBody'
   return
  end
  if token.type=='startTag'and headTags[token.name]then
   pushOpen(head)
   mode='inHead'
   process(token)
   return
  end
  if token.type=='eof'then
   ensureBody()
   mode='inBody'
   return
  end
  ensureBody()
  mode='inBody'
  process(token)
 end
 local handleInBody,handleInTable
 local function closeParagraph()
  if inScope('p',buttonScope)then closeTag('p')end
 end
 handleInBody=function(token)
  if token.type=='character'then
   local data=token.data
   if skipNewline then
    skipNewline=false
    if data:sub(1,1)=='\n'then data=data:sub(2)end
   end
   if data==''then return end
   reconstructFormatting()
   insertText(data)
   return
  end
  if token.type=='comment'then
   budget()
   insertNode(Dom.comment(token.data))
   return
  end
  if token.type=='doctype'then return end
  if token.type=='eof'then return end
  local name=token.name
  if token.type=='startTag'then
   if name=='html'then
    for key,value in pairs(token.attrs or{})do if htmlElement.attrs[key]==nil then htmlElement.attrs[key]=value end end
    return
   end
   if name=='body'then
    if body then for key,value in pairs(token.attrs or{})do if body.attrs[key]==nil then body.attrs[key]=value end end end
    return
   end
   if name=='head'then return end
   if headTags[name]and name~='title'then
    local element=insertElement(token,not headVoid[name])
    if not headVoid[name]and token.selfClosing then popOpen()end
    return
   end
   if name=='table'then
    closeParagraph()
    insertElement(token)
    mode='inTable'
    return
   end
   if tableTags[name]then
    note('Tag de tabela fora de <table> ignorada: <'..name..'>',token)
    return
   end
   if name=='li'then
    if inScope('li',listScope)then closeTag('li')end
    closeParagraph()
    insertElement(token)
    return
   end
   if name=='dd'or name=='dt'then
    if inScope('dd')then closeTag('dd')end
    if inScope('dt')then closeTag('dt')end
    closeParagraph()
    insertElement(token)
    return
   end
   if headings[name]then
    closeParagraph()
    if current()and headings[current().tag]then popOpen()end
    insertElement(token)
    return
   end
   if name=='pre'or name=='listing'then
    closeParagraph()
    insertElement(token)
    skipNewline=true
    return
   end
   if name=='textarea'then
    insertElement(token)
    skipNewline=true
    return
   end
   if name=='form'then
    closeParagraph()
    insertElement(token)
    return
   end
   if name=='button'then
    if inScope('button')then closeTag('button')end
    reconstructFormatting()
    insertElement(token)
    return
   end
   if name=='select'then
    reconstructFormatting()
    insertElement(token)
    mode='inSelect'
    return
   end
   if name=='option'or name=='optgroup'then
    if current()and current().tag=='option'then popOpen()end
    if name=='optgroup'and current()and current().tag=='optgroup'then popOpen()end
    insertElement(token)
    return
   end
   if name=='a'then
    if formattingEntry('a')then adoption('a')end
    reconstructFormatting()
    local element=insertElement(token)
    formattingList[#formattingList+1]=element
    return
   end
   if formattingTags[name]then
    if name=='nobr'and inScope('nobr')then adoption('nobr')end
    reconstructFormatting()
    local element=insertElement(token)
    formattingList[#formattingList+1]=element
    return
   end
   if name=='applet'or name=='marquee'or name=='object'then
    reconstructFormatting()
    insertElement(token)
    addMarker()
    return
   end
   if name=='hr'then
    closeParagraph()
    insertElement(token,false)
    return
   end
   if voidTags[name]then
    reconstructFormatting()
    insertElement(token,false)
    return
   end
   if closesParagraph[name]then closeParagraph()end
   reconstructFormatting()
   insertElement(token,not token.selfClosing)
   return
  end
  if token.type=='endTag'then
   if name=='body'or name=='html'then
    mode='afterBody'
    return
   end
   if name=='p'then
    if inScope('p',buttonScope)then closeTag('p')else note('</p> sem paragrafo aberto.',token)end
    return
   end
   if formattingTags[name]then
    if adoption(name)then return end
    if inScope(name)then closeTag(name)else note('Fechamento sem abertura: </'..name..'>',token)end
    return
   end
   if headings[name]then
    for tag in pairs(headings)do
     if inScope(tag)then closeTag(tag)return end
    end
    note('Fechamento sem abertura: </'..name..'>',token)
    return
   end
   if inScope(name)then
    closeTag(name)
   else
    note('Fechamento sem abertura: </'..name..'>',token)
   end
   return
  end
 end
 local function clearToTable()
  while #open>0 do
   local tag=current().tag
   if tag=='table'or tag=='html'then break end
   popOpen()
  end
 end
 local function clearToSection()
  while #open>0 do
   local tag=current().tag
   if sections[tag]or tag=='table'or tag=='html'then break end
   popOpen()
  end
 end
 local function clearToRow()
  while #open>0 do
   local tag=current().tag
   if tag=='tr'or tag=='table'or tag=='html'then break end
   popOpen()
  end
 end
 handleInTable=function(token)
  if token.type=='character'then
   if whitespaceOnly(token.data)and current()then
    budget()
    local last=current().children[#current().children]
    if last and last.kind==Dom.TEXT then last.data..=token.data else current():appendChild(Dom.text(token.data))end
    return
   end
   handleInBody(token)
   return
  end
  if token.type=='startTag'then
   local name=token.name
   if name=='caption'then
    clearToTable()
    addMarker()
    insertElement(token)
    mode='inCaption'
    return
   end
   if name=='colgroup'then
    clearToTable()
    insertElement(token)
    mode='inColumnGroup'
    return
   end
   if name=='col'then
    clearToTable()
    insertElement({type='startTag',name='colgroup',attrs={}})
    current().implicit=true
    mode='inColumnGroup'
    process(token)
    return
   end
   if sections[name]then
    clearToTable()
    insertElement(token)
    mode='inTableBody'
    return
   end
   if name=='tr'or cells[name]then
    clearToTable()
    insertElement({type='startTag',name='tbody',attrs={}})
    current().implicit=true
    mode='inTableBody'
    process(token)
    return
   end
   if name=='table'then
    popUntil('table')
    resetMode()
    process(token)
    return
   end
  end
  if token.type=='endTag'then
   local name=token.name
   if name=='table'then
    popUntil('table')
    resetMode()
    return
   end
   if tableTags[name]or name=='body'or name=='html'then
    note('Fechamento invalido em tabela: </'..name..'>',token)
    return
   end
  end
  handleInBody(token)
 end
 handlers.inBody=handleInBody
 handlers.inTable=handleInTable
 handlers.inTableBody=function(token)
  if token.type=='startTag'then
   local name=token.name
   if name=='tr'then
    clearToSection()
    insertElement(token)
    mode='inRow'
    return
   end
   if cells[name]then
    clearToSection()
    insertElement({type='startTag',name='tr',attrs={}})
    current().implicit=true
    mode='inRow'
    process(token)
    return
   end
   if name=='caption'or name=='col'or name=='colgroup'or sections[name]then
    clearToSection()
    popOpen()
    mode='inTable'
    process(token)
    return
   end
  end
  if token.type=='endTag'then
   local name=token.name
   if sections[name]then
    if inTableScope(name)then
     clearToSection()
     popOpen()
     mode='inTable'
    end
    return
   end
   if name=='table'then
    clearToSection()
    popOpen()
    mode='inTable'
    process(token)
    return
   end
  end
  handleInTable(token)
 end
 handlers.inRow=function(token)
  if token.type=='startTag'then
   local name=token.name
   if cells[name]then
    clearToRow()
    insertElement(token)
    addMarker()
    mode='inCell'
    return
   end
   if name=='tr'or name=='caption'or name=='col'or name=='colgroup'or sections[name]then
    clearToRow()
    popOpen()
    mode='inTableBody'
    process(token)
    return
   end
  end
  if token.type=='endTag'then
   local name=token.name
   if name=='tr'then
    if inTableScope('tr')then
     clearToRow()
     popOpen()
     mode='inTableBody'
    end
    return
   end
   if name=='table'or sections[name]then
    clearToRow()
    popOpen()
    mode='inTableBody'
    process(token)
    return
   end
  end
  handleInTable(token)
 end
 handlers.inCell=function(token)
  if token.type=='endTag'then
   local name=token.name
   if cells[name]then
    if inTableScope(name)then
     closeTag(name)
     clearToMarker()
     mode='inRow'
    end
    return
   end
   if name=='table'or name=='tr'or sections[name]then
    for tag in pairs(cells)do
     if inTableScope(tag)then closeTag(tag)break end
    end
    clearToMarker()
    mode='inRow'
    process(token)
    return
   end
  end
  if token.type=='startTag'and(cells[token.name]or token.name=='tr'or sections[token.name]or token.name=='caption'or token.name=='col'or token.name=='colgroup')then
   for tag in pairs(cells)do
    if inTableScope(tag)then closeTag(tag)break end
   end
   clearToMarker()
   mode='inRow'
   process(token)
   return
  end
  handleInBody(token)
 end
 handlers.inCaption=function(token)
  if token.type=='endTag'and token.name=='caption'then
   closeTag('caption')
   clearToMarker()
   mode='inTable'
   return
  end
  if(token.type=='startTag'and tableTags[token.name])or(token.type=='endTag'and token.name=='table')then
   closeTag('caption')
   clearToMarker()
   mode='inTable'
   process(token)
   return
  end
  handleInBody(token)
 end
 handlers.inColumnGroup=function(token)
  if token.type=='startTag'and token.name=='col'then
   insertElement(token,false)
   return
  end
  if token.type=='endTag'and token.name=='colgroup'then
   popUntil('colgroup')
   mode='inTable'
   return
  end
  if token.type=='character'and whitespaceOnly(token.data)then return end
  popUntil('colgroup')
  mode='inTable'
  process(token)
 end
 handlers.inSelect=function(token)
  if token.type=='character'then
   insertText(token.data)
   return
  end
  if token.type=='startTag'then
   local name=token.name
   if name=='option'then
    if current()and current().tag=='option'then popOpen()end
    insertElement(token)
    return
   end
   if name=='optgroup'then
    if current()and current().tag=='option'then popOpen()end
    if current()and current().tag=='optgroup'then popOpen()end
    insertElement(token)
    return
   end
   if name=='select'then
    popUntil('select')
    resetMode()
    return
   end
   if name=='input'or name=='textarea'or name=='button'then
    popUntil('select')
    resetMode()
    process(token)
    return
   end
   note('Tag ignorada dentro de <select>: <'..name..'>',token)
   return
  end
  if token.type=='endTag'then
   local name=token.name
   if name=='option'then
    if current()and current().tag=='option'then popOpen()end
    return
   end
   if name=='optgroup'then
    if current()and current().tag=='option'then popOpen()end
    if current()and current().tag=='optgroup'then popOpen()end
    return
   end
   if name=='select'then
    popUntil('select')
    resetMode()
    return
   end
  end
  if token.type=='eof'then return end
  handleInBody(token)
 end
 handlers.afterBody=function(token)
  if token.type=='eof'then return end
  if token.type=='comment'then return end
  if token.type=='character'and whitespaceOnly(token.data)then return end
  if token.type=='endTag'and token.name=='html'then return end
  mode='inBody'
  if not isOpen(body)and body then pushOpen(body)end
  process(token)
 end
 if context then
  ensureHtml()
  contextElement=createElement(context,options.contextAttrs)
  htmlElement:appendChild(contextElement)
  pushOpen(contextElement)
  body=contextElement
  doc.body=contextElement
  resetMode()
  if context=='html'then mode='inBody'end
 end
 for _,token in ipairs(tokens)do
  if checkpoint then checkpoint()end
  process(token)
 end
 if not context then
  ensureBody()
 end
 doc.nodeCount=nodes
 return doc,contextElement
end
function B.parse(source,options)
 local tokens=Tokenizer.tokenize(source,options)
 local doc=construct(tokens,options)
 return doc
end
function B.fragment(source,context,options)
 options=options or {}
 local tokens=Tokenizer.tokenize(source,options)
 local settings=table.clone(options)
 settings.context=context or 'body'
 local _,contextElement=construct(tokens,settings)
 local fragment=Dom.fragment()
 for _,child in ipairs(table.clone(contextElement.children))do fragment:appendChild(child)end
 return fragment
end
B.construct=construct
return B
