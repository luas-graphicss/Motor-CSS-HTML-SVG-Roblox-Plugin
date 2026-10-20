local U=require(script.Parent.Util)
local Theme=require(script.Parent.ColorTheme)
local Shapes=require(script.Parent.CssShapes)
local A={}
local enums={
 ['column-fill']='auto balance balance-all',['column-span']='none all',['table-layout']='auto fixed',['border-collapse']='separate collapse',['caption-side']='top bottom block-start block-end inline-start inline-end',['empty-cells']='show hide',
 ['break-before']='auto avoid always column page left right recto verso avoid-column avoid-page',['break-after']='auto avoid always column page left right recto verso avoid-column avoid-page',['break-inside']='auto avoid avoid-column avoid-page',
 float='none left right inline-start inline-end',clear='none left right both inline-start inline-end',
}
local function keyword(list,value)return(' '..list..' '):find(' '..value..' ',1,true)~=nil end
local lists=table.freeze({['transition-behavior']='normal allow-discrete',['animation-composition']='replace add accumulate'})
local ident='^%-?[%a_][%w_%-]*$'
local function keywordList(list,value)
 for _,part in ipairs(U.split(value,','))do
  local word=U.trim(part):lower()
  if word==''or not keyword(list,word)then return false end
 end
 return true
end
local function identifiers(value)
 local text=U.trim(value)
 if text==''then return false end
 if text:lower()=='none'then return true end
 local count=0
 for _,part in ipairs(U.split(text,' '))do
  local word=U.trim(part)
  if word~=''then
   if not word:match(ident)then return false end
   count+=1
  end
 end
 return count>0
end
function A.validate(style)
 for key,list in pairs(enums)do if style[key]~=nil then assert(keyword(list,tostring(style[key])),key..' inválido: '..tostring(style[key]))end end
 for _,key in ipairs({'orphans','widows'})do if style[key]~=nil then local n=tonumber(style[key]);assert(n and n%1==0 and n>=1 and n<=1024,key..' exige inteiro de 1 a 1024.')end end
 local threshold=style['shape-image-threshold'];if threshold then assert(tonumber(threshold),'shape-image-threshold exige um número.');style['shape-image-threshold']=tostring(math.clamp(tonumber(threshold),0,1))end
 for key,list in pairs(lists)do
  local value=style[key]
  if value~=nil and not tostring(value):find('%d')then assert(keywordList(list,tostring(value)),key..' inválido: '..tostring(value))end
 end
 local vtName=style['view-transition-name']
 if vtName~=nil then
  local text=U.trim(tostring(vtName))
  assert(text:lower()=='none'or text:match(ident),'view-transition-name inválido: '..text)
 end
 local vtClass=style['view-transition-class']
 if vtClass~=nil then assert(identifiers(tostring(vtClass)),'view-transition-class inválido: '..tostring(vtClass))end
 return style
end
function A.install(supports)
 supports.register('display',function(value)return keyword('none block inline inline-block flex grid table inline-table table-row table-cell table-row-group table-header-group table-footer-group table-caption table-column table-column-group ruby ruby-base ruby-text ruby-base-container ruby-text-container',value:lower())end)
 for key,list in pairs(enums)do local values=list;supports.register(key,function(value)return keyword(values,value:lower())end)end
 for _,key in ipairs({'orphans','widows'})do supports.register(key,function(value)local n=tonumber(value);return n~=nil and n%1==0 and n>=1 and n<=1024 end)end
 supports.register('column-count',function(value)local n=tonumber(value);return value=='auto'or n~=nil and n%1==0 and n>=1 and n<=64 end)
 supports.register('color-scheme',function(value)Theme.used(value,{colorScheme='light'});return true end)
 supports.register('shape-image-threshold',function(value)return tonumber(value)~=nil end)
 for key,list in pairs(lists)do local values=list;supports.register(key,function(value)return keywordList(values,value)end)end
 supports.register('view-transition-name',function(value)local text=U.trim(value);return text:lower()=='none'or text:match(ident)~=nil end)
 supports.register('view-transition-class',function(value)return identifiers(value)end)
 supports.register('shape-margin',function(value)local v=U.length(value,100,100,100,16);return v~=nil and v>=0 end)
 supports.register('border-spacing',function(value)local words=U.split(value,' ');if #words<1 or #words>2 then return false end;for _,word in ipairs(words)do local n=U.length(word,100,100,100,16);if not n or n<0 or word:find('%%')then return false end end;return true end)
 supports.register('shape-outside',function(value)
  if value=='none'then return true end
  Shapes.prepare({['shape-outside']=value},{w=100,h=100,p={0,0,0,0},m={0,0,0,0},fs=16},{length=function(v,base)return U.length(v,base,100,100,16)end},100);return true
 end)
end
return A
