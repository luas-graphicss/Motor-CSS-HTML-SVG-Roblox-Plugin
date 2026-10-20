local D={VERSION=1}
D.ELEMENT='element'
D.TEXT='text'
D.COMMENT='comment'
D.DOCUMENT='document'
D.FRAGMENT='fragment'
D.voidTags=table.freeze({area=true,base=true,br=true,col=true,embed=true,hr=true,img=true,input=true,link=true,meta=true,param=true,source=true,track=true,wbr=true})
local Node={}
Node.__index=Node
D.Node=Node
local function make(kind,tag)
 return setmetatable({kind=kind,tag=tag,children={},attrs={}},Node)
end
function D.document()
 local node=make(D.DOCUMENT,'#document')
 node.styleSheets={}
 return node
end
function D.fragment()return make(D.FRAGMENT,'#fragment')end
function D.element(tag,attrs,namespace)
 local node=make(D.ELEMENT,string.lower(tostring(tag)))
 node.ns=namespace or 'html'
 if attrs then for key,value in pairs(attrs)do node.attrs[key]=value end end
 return node
end
function D.text(data)
 local node=make(D.TEXT,'#text')
 node.data=data or ''
 return node
end
function D.comment(data)
 local node=make(D.COMMENT,'#comment')
 node.data=data or ''
 return node
end
function D.isElement(node)return type(node)=='table'and node.kind==D.ELEMENT end
function D.isText(node)return type(node)=='table'and node.kind==D.TEXT end
function Node:indexOf(child)
 for index,value in ipairs(self.children)do if value==child then return index end end
 return nil
end
function Node:remove()
 local parent=self.parent
 if parent then
  local index=parent:indexOf(self)
  if index then table.remove(parent.children,index)end
  self.parent=nil
 end
 return self
end
function Node:contains(other)
 local cursor=other
 while cursor do
  if cursor==self then return true end
  cursor=cursor.parent
 end
 return false
end
function Node:appendChild(child)
 assert(child~=self,'Um no nao pode conter a si mesmo.')
 assert(not child:contains(self),'Ciclo detectado na arvore DOM.')
 child:remove()
 child.parent=self
 table.insert(self.children,child)
 return child
end
function Node:insertBefore(child,reference)
 if reference==nil or reference==child then return self:appendChild(child)end
 assert(not child:contains(self),'Ciclo detectado na arvore DOM.')
 child:remove()
 local index=assert(self:indexOf(reference),'Referencia nao pertence a este no.')
 child.parent=self
 table.insert(self.children,index,child)
 return child
end
function Node:replaceChild(child,old)
 local index=assert(self:indexOf(old),'No antigo nao pertence a este pai.')
 old.parent=nil
 table.remove(self.children,index)
 child:remove()
 child.parent=self
 table.insert(self.children,index,child)
 return child
end
function Node:appendAll(nodes)
 for _,child in ipairs(nodes)do self:appendChild(child)end
 return self
end
function Node:firstChild()return self.children[1]end
function Node:lastChild()return self.children[#self.children]end
function Node:previousSibling()
 local parent=self.parent
 if not parent then return nil end
 local index=parent:indexOf(self)
 return index and parent.children[index-1]or nil
end
function Node:nextSibling()
 local parent=self.parent
 if not parent then return nil end
 local index=parent:indexOf(self)
 return index and parent.children[index+1]or nil
end
function Node:elements()
 local out={}
 for _,child in ipairs(self.children)do if child.kind==D.ELEMENT then out[#out+1]=child end end
 return out
end
function Node:setAttribute(name,value)
 self.attrs[string.lower(tostring(name))]=tostring(value)
 return self
end
function Node:getAttribute(name)return self.attrs[string.lower(tostring(name))]end
function Node:hasAttribute(name)return self.attrs[string.lower(tostring(name))]~=nil end
function Node:removeAttribute(name)
 self.attrs[string.lower(tostring(name))]=nil
 return self
end
function Node:classList()
 local out={}
 for word in tostring(self.attrs.class or ''):gmatch('%S+')do out[#out+1]=word end
 return out
end
function Node:hasClass(name)
 for _,value in ipairs(self:classList())do if value==name then return true end end
 return false
end
function Node:textContent()
 if self.kind==D.TEXT then return self.data end
 if self.kind==D.COMMENT then return ''end
 local parts={}
 for _,child in ipairs(self.children)do parts[#parts+1]=child:textContent()end
 return table.concat(parts)
end
function Node:walk(visit,depth)
 depth=depth or 1
 if visit(self,depth)==false then return false end
 for _,child in ipairs(table.clone(self.children))do
  if child:walk(visit,depth+1)==false then return false end
 end
 return true
end
function Node:descendants()
 local out={}
 self:walk(function(node)if node~=self then out[#out+1]=node end end)
 return out
end
function Node:findFirst(predicate)
 local found
 self:walk(function(node)
  if node~=self and predicate(node)then found=node;return false end
  return true
 end)
 return found
end
function Node:findAll(predicate)
 local out={}
 self:walk(function(node)if node~=self and predicate(node)then out[#out+1]=node end end)
 return out
end
function Node:byTag(tag)
 return self:findAll(function(node)return node.kind==D.ELEMENT and node.tag==tag end)
end
function Node:byId(id)
 return self:findFirst(function(node)return node.kind==D.ELEMENT and node.attrs.id==id end)
end
function Node:closest(tag)
 local cursor=self.parent
 while cursor do
  if cursor.tag==tag then return cursor end
  cursor=cursor.parent
 end
 return nil
end
function Node:depth()
 local total=0
 local cursor=self.parent
 while cursor do total+=1;cursor=cursor.parent end
 return total
end
function Node:clone(deep)
 local copy
 if self.kind==D.ELEMENT then copy=D.element(self.tag,self.attrs,self.ns)
 elseif self.kind==D.TEXT then copy=D.text(self.data)
 elseif self.kind==D.COMMENT then copy=D.comment(self.data)
 else copy=make(self.kind,self.tag)end
 copy.anonymous=self.anonymous
 copy.implicit=self.implicit
 if deep then for _,child in ipairs(self.children)do copy:appendChild(child:clone(true))end end
 return copy
end
local function escapeText(text)
 return(text:gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'))
end
local function escapeAttribute(text)
 return(text:gsub('&','&amp;'):gsub('"','&quot;'))
end
function Node:serialize()
 if self.kind==D.TEXT then return escapeText(self.data)end
 if self.kind==D.COMMENT then return '<!--'..self.data..'-->'end
 local parts={}
 if self.kind==D.ELEMENT then
  local names={}
  for key in pairs(self.attrs)do names[#names+1]=key end
  table.sort(names)
  local attributes={}
  for _,key in ipairs(names)do attributes[#attributes+1]=' '..key..'="'..escapeAttribute(tostring(self.attrs[key]))..'"'end
  parts[#parts+1]='<'..self.tag..table.concat(attributes)..'>'
 end
 for _,child in ipairs(self.children)do parts[#parts+1]=child:serialize()end
 if self.kind==D.ELEMENT and not D.voidTags[self.tag]then parts[#parts+1]='</'..self.tag..'>'end
 return table.concat(parts)
end
function D.count(node)
 local total=0
 node:walk(function()total+=1 end)
 return total
end
function D.elementCount(node)
 local total=0
 node:walk(function(current)if current.kind==D.ELEMENT then total+=1 end end)
 return total
end
return D
