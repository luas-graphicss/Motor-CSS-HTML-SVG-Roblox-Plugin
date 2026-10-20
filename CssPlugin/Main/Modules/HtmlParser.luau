local Dom=require(script.Parent.Dom)
local Tree=require(script.Parent.HtmlTree)
local Ua=require(script.Parent.UserAgentStyles)
local Cost=require(script.Parent.CostModel)
local P={VERSION=2}
local function set(list)
 local out={}
 for word in list:gmatch('%S+')do out[word]=true end
 return table.freeze(out)
end
local booleanAttributes=set('disabled checked readonly required multiple selected autofocus hidden indeterminate autofill open reversed default ismap loop muted novalidate playsinline controls async defer')
local metadataTags=set('head style link meta title base template script noscript')
local internalTable=set('table-row-group table-header-group table-footer-group table-row table-cell table-caption table-column table-column-group')
local rowGroups=set('table-row-group table-header-group table-footer-group')
local displayPairs=table.freeze({['block flow']='block',['inline flow']='inline',['block flow-root']='flow-root',['inline flow-root']='inline-block',['block flex']='flex',['inline flex']='inline-flex',['block grid']='grid',['inline grid']='inline-grid',['block table']='table',['inline table']='inline-table'})
P.booleanAttributes=booleanAttributes
P.metadataTags=metadataTags
P.internalTableDisplays=internalTable
local function inlineDisplay(element)
 local declaration=element.attrs and element.attrs.style
 if not declaration or not declaration:find('display',1,true)then return nil end
 local raw=nil
 for name,body in string.lower(declaration):gmatch('([%a%-]+)%s*:%s*([^;]*)')do
  if name=='display'then raw=body end
 end
 if not raw then return nil end
 raw=raw:gsub('!%s*important','')
 local words={}
 for word in raw:gmatch('[%a%-]+')do words[#words+1]=word end
 if #words==0 then return nil end
 for _,word in ipairs(words)do if word=='list-item'then return 'list-item'end end
 if #words>=2 then
  local alias=displayPairs[words[1]..' '..words[2]]
  if alias then return alias end
 end
 return words[1]
end
function P.displayOf(element)
 if element.kind~=Dom.ELEMENT then return 'inline'end
 if element.display then return element.display end
 local value=inlineDisplay(element)or Ua.display(element.tag,element.attrs)
 element.display=value
 return value
end
local function whitespaceText(node)
 return node.kind==Dom.TEXT and node.data:match('^%s*$')~=nil
end
local function displayFor(node)
 if node.kind==Dom.TEXT then
  if whitespaceText(node)then return nil end
  return 'inline'
 end
 if node.kind~=Dom.ELEMENT then return nil end
 local display=P.displayOf(node)
 if display=='none'then return nil end
 return display
end
local function allowed(node,accept)
 local display=displayFor(node)
 if display==nil then return true end
 return accept(display)
end
local function wrapRun(parent,startIndex,stopIndex,tag,display)
 local wrapper=Dom.element(tag)
 wrapper.anonymous=true
 wrapper.display=display
 parent:insertBefore(wrapper,parent.children[startIndex])
 for _=startIndex,stopIndex do
  wrapper:appendChild(parent.children[startIndex+1])
 end
 return wrapper
end
local function fixChildren(parent,accept,tag,display,budget)
 local index=1
 while index<=#parent.children do
  local child=parent.children[index]
  if allowed(child,accept)then
   index+=1
  else
   local stop=index
   while stop<#parent.children do
    local following=parent.children[stop+1]
    if following.kind==Dom.COMMENT then break end
    if allowed(following,accept)and not whitespaceText(following)then break end
    stop+=1
   end
   budget()
   wrapRun(parent,index,stop,tag,display)
   index+=1
  end
 end
end
local function notInternal(display)return internalTable[display]~=true end
local function tableChild(display)return internalTable[display]==true end
local function notCell(display)return display~='table-cell'end
local function notRow(display)return display~='table-row'end
local function rowOrCell(display)return display=='table-row'or display=='table-cell'end
local function onlyRow(display)return display=='table-row'end
local function onlyCell(display)return display=='table-cell'end
function P.anonymize(root,rootDisplay)
 local created=Dom.count(root)
 local function budget()
  created+=1
  Cost.cap('nodes',created,'Caixas anonimas')
 end
 root:walk(function(node)
  local display
  if node.kind==Dom.ELEMENT then display=P.displayOf(node)
  elseif node==root then display=rootDisplay or 'block'
  elseif node.kind==Dom.DOCUMENT or node.kind==Dom.FRAGMENT then display='block'
  else return true end
  if display=='none'then return true end
  if display=='table'or display=='inline-table'then
   fixChildren(node,tableChild,'td','table-cell',budget)
   fixChildren(node,notCell,'tr','table-row',budget)
   fixChildren(node,notRow,'tbody','table-row-group',budget)
  elseif rowGroups[display]then
   fixChildren(node,rowOrCell,'td','table-cell',budget)
   fixChildren(node,onlyRow,'tr','table-row',budget)
  elseif display=='table-row'then
   fixChildren(node,onlyCell,'td','table-cell',budget)
  elseif display=='table-column'or display=='table-column-group'then
   return true
  else
   fixChildren(node,notInternal,'table','table',budget)
  end
  return true
 end)
 return root
end
function P.collectStyleSheets(doc)
 local sheets=doc.styleSheets or{}
 for _,element in ipairs(doc:byTag('style'))do
  local media=element.attrs.media
  local text=element:textContent()
  if text and text:match('%S')then sheets[#sheets+1]={source=text,media=media}end
 end
 doc.styleSheets=sheets
 return sheets
end
function P.cssText(doc)
 local parts={}
 for _,sheet in ipairs(doc.styleSheets or{})do
  if sheet.media and sheet.media~=''then parts[#parts+1]='@media '..sheet.media..'{'..sheet.source..'}'
  else parts[#parts+1]=sheet.source end
 end
 return table.concat(parts,'\n')
end
local function projectAttributes(element)
 local attrs={}
 for key,value in pairs(element.attrs)do
  if value==''and booleanAttributes[key]then attrs[key]='true'else attrs[key]=value end
 end
 return attrs
end
local function projectElement(element)
 local node={tag=element.tag,attrs=projectAttributes(element),children={},text='',content={}}
 node.display=element.display
 if element.anonymous then node.anonymous=true end
 for _,child in ipairs(element.children)do
  if child.kind==Dom.TEXT then
   local data=child.data
   if data~=''then
    node.text..=data
    local last=#node.content
    if type(node.content[last])=='string'then node.content[last]..=data else node.content[last+1]=data end
   end
  elseif child.kind==Dom.ELEMENT and not metadataTags[child.tag]then
   node.children[#node.children+1]=projectElement(child)
   node.content[#node.content+1]=#node.children
  end
 end
 return node
end
function P.project(doc)
 local host=doc.body or doc.documentElement or doc
 local root=nil
 for _,child in ipairs(host.children)do
  if child.kind==Dom.ELEMENT and child.tag=='ui'then root=child break end
 end
 if not root then
  root=host:findFirst(function(node)return node.kind==Dom.ELEMENT and node.tag=='ui'end)
 end
 local projected
 if not root and type(doc.doctype)=='string'and string.lower(doc.doctype)=='html'and doc.documentElement and doc.body then
  projected=projectElement(doc.documentElement)
  projected.aliases={html=true}
 else
  projected=projectElement(root or host)
  if not root then projected.aliases={html=true,body=true}end
 end
 projected.tag='ui'
 projected.display='block'
 return projected
end
function P.parse(markup,options)
 assert(type(markup)=='string','O markup precisa ser texto.')
 Cost.cap('bytes',#markup,'Documento')
 local doc=Tree.parse(markup,options)
 P.collectStyleSheets(doc)
 P.anonymize(doc.body or doc,'block')
 return doc
end
function P.parseFragment(markup,context,options)
 assert(type(markup)=='string','O markup precisa ser texto.')
 Cost.cap('bytes',#markup,'Documento')
 local fragment=Tree.fragment(markup,context,options)
 P.anonymize(fragment,Ua.display(context or 'body'))
 return fragment
end
function P.compile(markup,options)
 options=options or{}
 local diagnostics=options.diagnostics or{}
 local settings=table.clone(options)
 settings.diagnostics=diagnostics
 local doc=P.parse(markup,settings)
 return{tree=P.project(doc),document=doc,styleSheets=doc.styleSheets,css=P.cssText(doc),diagnostics=diagnostics}
end
return P
