local C={VERSION=2}
local Catalog=require(script.Parent.CssPropertyCatalog)
C.ORIGIN=Catalog.ORIGIN
local AUTHOR=Catalog.ORIGIN.author
local function trim(v)return (v:gsub('^%s+',''):gsub('%s+$',''))end
function C.layers()
 return {root={children={},count=0,path={}},anonymous=0}
end
function C.layer(registry,parent,name)
 local cursor=parent or registry.root
 local anonymous=not name or trim(name)==''
 if anonymous then
  registry.anonymous+=1;name=':anonymous:'..registry.anonymous
 else
  name=trim(name)
  assert(not name:find('%.%.')and name:sub(1,1)~='.'and name:sub(-1)~='.','Nome @layer inválido.')
 end
 assert(#name<=2048,'Nome @layer excede 2048 bytes.')
 for part in name:gmatch('[^.]+')do
  assert(#cursor.path<64,'Máximo de 64 níveis de layers.')
  assert(anonymous or part:match('^[%a_%-][%w_%-]*$')and not ({initial=true,inherit=true,unset=true,revert=true,['revert-layer']=true})[part:lower()],'Nome @layer inválido: '..part)
  local child=cursor.children[part]
  if not child then
   registry.total=(registry.total or 0)+1;assert(registry.total<=1024,'Máximo de 1024 layers por documento.')
   cursor.count+=1;local path=table.clone(cursor.path);path[#path+1]=cursor.count
   child={children={},count=0,path=path,name=part};cursor.children[part]=child
  end
  cursor=child
 end
 return cursor
end
function C.order(events,width,height,environment)
 if not events or #events==0 then return nil,''end
 local Queries=require(script.Parent.ResponsiveQueries)
 local resolved,counts,stamp={},{},{}
 for _,event in ipairs(events)do
  if Queries.mediaActive(event,width or 1280,height or 720,environment)then
   local prefix,rank={},{}
   for _,identity in ipairs(event.path)do
    local parent=table.concat(prefix,'.');prefix[#prefix+1]=identity;local key=table.concat(prefix,'.')
    local existing=resolved[key]
    if existing then rank=existing
    else
     counts[parent]=(counts[parent]or 0)+1;rank=table.clone(rank);rank[#rank+1]=counts[parent];resolved[key]=rank
     stamp[#stamp+1]=key..'='..table.concat(rank,'.')
    end
   end
  end
 end
 return resolved,table.concat(stamp,';')
end
function C.path(path,order)
 return path and order and order[table.concat(path,'.')]or path
end
function C.layerCompare(a,b,important,order)
 a=C.path(a,order)or {};b=C.path(b,order)or {}
 for i=1,math.max(#a,#b)do
  local x,y=a[i]or math.huge,b[i]or math.huge
  if x~=y then local result=x>y and 1 or -1;return important and -result or result end
 end
 return 0
end
function C.better(a,b)
 if not b then return true end
 if a.important~=b.important then return a.important end
 local ao,bo=a.origin or AUTHOR,b.origin or AUTHOR
 if ao~=bo then if a.important then return ao<bo end;return ao>bo end
 if a.inline~=b.inline then return a.inline end
 local layer=C.layerCompare(a.layer,b.layer,a.important)
 if layer~=0 then return layer>0 end
 if a.specificity~=b.specificity then return a.specificity>b.specificity end
 local ap,bp=a.proximity or math.huge,b.proximity or math.huge
 if ap~=bp then return ap<bp end
 if a.order~=b.order then return a.order>b.order end
 return (a.index or 0)>=(b.index or 0)
end
local function bucket(d)
 return tostring(d.origin or AUTHOR)..'|'..(d.inline and '@inline'or table.concat(d.layer or {},'.'))
end
function C.apply(winners,decls,specificity,order,layer,inline,layerOrder,origin,proximity)
 layer=C.path(layer,layerOrder)
 origin=Catalog.origin(origin or AUTHOR)
 for index,d in ipairs(decls)do
  local candidate={value=d.value,important=d.important==true,inline=inline==true,specificity=specificity or 0,order=order or 0,index=d.index or index,layer=layer,shorthand=d.shorthand,origin=d.origin and Catalog.origin(d.origin)or origin,proximity=proximity}
  local old=winners[d.key]
  if old then
   local stack=old._stack
   if not stack then stack={old};old._stack=stack end
   stack[#stack+1]=candidate
   if C.better(candidate,old)then candidate._stack=stack;winners[d.key]=candidate end
  else winners[d.key]=candidate end
 end
end
function C.clone(winners)
 local out={}
 for key,winner in pairs(winners)do
  local copy=table.clone(winner)
  if winner._stack then copy._stack=table.clone(winner._stack)end
  out[key]=copy
 end
 return out
end
function C.finish(winners)
 for key,winner in pairs(winners)do
  local value=type(winner.value)=='string'and trim(winner.value):lower()or ''
  if value=='revert-layer'or value=='revert'then
   local stack=winner._stack or {winner}
   table.sort(stack,function(a,b)if a==b then return false end;return C.better(a,b)and not C.better(b,a)end)
   local excluded={};local resolved;local floor
   for _,d in ipairs(stack)do
    local origin=d.origin or AUTHOR
    if not(floor and origin>=floor)and not excluded[bucket(d)]then
     local token=type(d.value)=='string'and trim(d.value):lower()or ''
     if token=='revert'then floor=floor and math.min(floor,origin)or origin
     elseif token=='revert-layer'then excluded[bucket(d)]=true
     else resolved=d;break end
    end
   end
   winner=resolved;winners[key]=resolved
  end
  if winner then winner._stack=nil end
 end
 return winners
end
function C.wide(value,key,parent,defaults,inherited,catalog)
 if type(value)~='string'then return value end
 local token=trim(value):lower()
 local entry=catalog and Catalog.entry(catalog,key)or nil
 local function initial()
  if defaults[key]~=nil then return defaults[key]end
  return entry and entry.initial or nil
 end
 if token=='inherit'then return parent and parent[key]or initial()
 elseif token=='initial'then return initial()
 elseif token=='revert'or token=='revert-layer'then return initial()
 elseif token=='unset'then
  local inherits=entry~=nil and entry.inherits==true
  if not entry then
   for _,name in ipairs(inherited)do if name==key then inherits=true;break end end
  end
  if inherits then return parent and parent[key]or initial()end
  return initial()
 end
 return value
end
return C
