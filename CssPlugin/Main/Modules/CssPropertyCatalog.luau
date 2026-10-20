local P={VERSION=1}
local ORIGIN=table.freeze({ua=1,user=2,author=3})
P.ORIGIN=ORIGIN
P.ORIGIN_NAME=table.freeze({'ua','user','author'})
P.WIDE=table.freeze({initial=true,inherit=true,unset=true,revert=true,['revert-layer']=true})
P.EXCLUDED_FROM_ALL=table.freeze({all=true,direction=true,['unicode-bidi']=true})
local INITIALS=table.freeze({
 all='initial',['aspect-ratio']='auto',['align-content']='normal',['align-items']='normal',['align-self']='auto',
 animation='none',['animation-delay']='0s',['animation-direction']='normal',['animation-duration']='0s',
 ['animation-fill-mode']='none',['animation-iteration-count']='1',['animation-name']='none',
 ['animation-play-state']='running',['animation-timing-function']='ease',['backdrop-filter']='none',
 ['backface-visibility']='visible',background='transparent',['background-attachment']='scroll',
 ['background-blend-mode']='normal',['background-clip']='border-box',['background-color']='transparent',
 ['background-image']='none',['background-origin']='padding-box',['background-position']='0% 0%',
 ['background-repeat']='repeat',['background-size']='auto',bottom='auto',['box-shadow']='none',
 ['box-sizing']='content-box',['clip-path']='none',contain='none',['container-name']='none',
 ['container-type']='normal',content='normal',['content-visibility']='visible',['counter-increment']='none',
 ['counter-reset']='none',['counter-set']='none',filter='none',flex='0 1 auto',['flex-basis']='auto',
 ['flex-direction']='row',['flex-grow']='0',['flex-shrink']='1',['flex-wrap']='nowrap',
 ['grid-auto-flow']='row',['grid-template-areas']='none',['grid-template-columns']='none',
 ['grid-template-rows']='none',height='auto',inset='auto',isolation='auto',['justify-content']='normal',
 ['justify-items']='legacy',['justify-self']='auto',left='auto',['max-height']='none',['max-width']='none',
 ['min-height']='auto',['min-width']='auto',['mix-blend-mode']='normal',opacity='1',order='0',
 overflow='visible',['overflow-x']='visible',['overflow-y']='visible',['overflow-block']='visible',
 ['overflow-inline']='visible',['overflow-clip-margin']='0px',['scrollbar-gutter']='auto',
 ['scroll-behavior']='auto',['box-decoration-break']='slice',perspective='none',
 ['perspective-origin']='50% 50%',position='static',right='auto',top='auto',transform='none',
 ['transform-origin']='50% 50%',transition='none',['transition-delay']='0s',['transition-duration']='0s',
 ['transition-property']='all',['transition-timing-function']='ease',visibility='visible',
 ['white-space']='normal',width='auto',['will-change']='auto',['z-index']='auto',
})
local NUMERIC=table.freeze({opacity=true,['flex-grow']=true,['flex-shrink']=true,order=true,['z-index']=true,['line-height']=true,orphans=true,widows=true,['column-count']=true,['animation-iteration-count']=true,['font-weight']=true,['fill-opacity']=true,['stroke-opacity']=true,scale=true,zoom=true,['tab-size']=true})
local COLORISH=table.freeze({color=true,fill=true,stroke=true,['caret-color']=true,['accent-color']=true})
local LENGTHS=table.freeze({'^width$','^height$','^min%-','^max%-','^padding','^margin','^inset','^gap$','%-gap$','%-width$','%-radius$','^top$','^left$','^right$','^bottom$','%-spacing$','%-indent$','%-thickness$','%-offset$','^perspective$','%-size$','^flex%-basis$','^column%-width$','^stroke%-dashoffset$','^translate$'})
local function classify(name)
 if name:sub(1,2)=='--'then return 'custom','custom'end
 if name=='background'then return 'background','background'end
 if COLORISH[name]or name:match('%-color$')then return 'color','color'end
 if NUMERIC[name]then return 'number','number'end
 if name:match('%-duration$')or name:match('%-delay$')then return 'time','time'end
 if name:match('%-image$')then return 'image','image'end
 if name:match('%-timing%-function$')then return 'easing','easing'end
 if name:match('%-shadow$')then return 'shadow','shadow'end
 if name=='transform'then return 'transform-list','transform-list'end
 if name=='content'then return 'content-list','content-list'end
 if name=='font-family'then return 'font-family','font-family'end
 if name=='quotes'then return 'quote-pairs','quote-pairs'end
 for _,pattern in ipairs(LENGTHS)do if name:match(pattern)then return 'length-percentage','length'end end
 return 'keyword','keyword'
end
P.classify=classify
function P.build(sources)
 assert(type(sources)=='table','Catalogo de propriedades exige fontes.')
 local supported=sources.supported or {}
 local shorthands=sources.shorthands or {}
 local deferred=sources.deferred or {}
 local defaults=sources.defaults or {}
 local inherited={}
 for key,value in pairs(sources.inherited or {})do
  if type(value)=='string'then inherited[value]=true
  elseif value==true and type(key)=='string'then inherited[key]=true end
 end
 local entries={}
 local function ensure(name)
  assert(type(name)=='string'and name~='','Nome de propriedade invalido no catalogo.')
  local record=entries[name]
  if not record then
   local computed,used=classify(name)
   local seed=defaults[name]
   if seed==nil then seed=INITIALS[name]end
   if P.WIDE[tostring(seed):lower()]then seed=nil end
   record={name=name,kind='longhand',inherits=inherited[name]==true,computed=computed,used=used,initial=seed}
   entries[name]=record
  end
  return record
 end
 for name in pairs(supported)do ensure(name)end
 for name in pairs(defaults)do ensure(name)end
 for name in pairs(inherited)do ensure(name)end
 local function link(name,list)
  local record=ensure(name);record.kind='shorthand'
  local seen,out={},{}
  for _,sub in ipairs(record.longhands or {})do if not seen[sub]then seen[sub]=true;out[#out+1]=sub end end
  for _,sub in ipairs(list)do
   if type(sub)=='string'and not seen[sub]then
    seen[sub]=true;out[#out+1]=sub
    local child=ensure(sub);child.shorthands=child.shorthands or {};child.shorthands[#child.shorthands+1]=name
   end
  end
  record.longhands=out
 end
 for name,list in pairs(shorthands)do if type(list)=='table'then link(name,list)end end
 for name,list in pairs(deferred)do if type(list)=='table'then link(name,list)end end
 local allEntry=ensure('all');allEntry.kind='shorthand';allEntry.computed='keyword';allEntry.used='keyword';allEntry.inherits=false
 local names,longhands={},{}
 for name,record in pairs(entries)do
  names[#names+1]=name
  if record.kind=='longhand'then longhands[#longhands+1]=name end
 end
 table.sort(names);table.sort(longhands)
 local resettable={}
 for _,name in ipairs(longhands)do if not P.EXCLUDED_FROM_ALL[name]and name:sub(1,2)~='--'then resettable[#resettable+1]=name end end
 allEntry.longhands=resettable
 return {version=P.VERSION,entries=entries,names=names,longhands=longhands,resettable=resettable,count=#names}
end
function P.entry(catalog,name)
 if type(catalog)~='table'or type(name)~='string'then return nil end
 return catalog.entries and catalog.entries[name]or nil
end
function P.has(catalog,name)return P.entry(catalog,name)~=nil end
function P.isShorthand(catalog,name)local e=P.entry(catalog,name);return e~=nil and e.kind=='shorthand'end
function P.longhandsOf(catalog,name)local e=P.entry(catalog,name);return e and e.longhands or nil end
function P.initial(catalog,name)local e=P.entry(catalog,name);return e and e.initial or nil end
function P.inherits(catalog,name)local e=P.entry(catalog,name);return e~=nil and e.inherits==true end
function P.computed(catalog,name)local e=P.entry(catalog,name);return e and e.computed or nil end
function P.used(catalog,name)local e=P.entry(catalog,name);return e and e.used or nil end
function P.wide(value)
 if type(value)~='string'then return nil end
 local token=value:gsub('^%s+',''):gsub('%s+$',''):lower()
 return P.WIDE[token]and token or nil
end
function P.expandAll(catalog,value)
 local token=assert(P.wide(value),'all aceita apenas initial, inherit, unset, revert ou revert-layer.')
 local out={}
 for _,name in ipairs(catalog and catalog.resettable or {})do out[name]=token end
 return out
end
function P.describe(catalog)
 local out={}
 for _,name in ipairs(catalog and catalog.names or {})do
  local e=catalog.entries[name]
  out[#out+1]={name=name,kind=e.kind,initial=e.initial,inherits=e.inherits==true,computed=e.computed,used=e.used,longhands=e.longhands and table.clone(e.longhands)or nil}
 end
 return out
end
function P.origin(name)
 if type(name)=='number'then return name end
 return ORIGIN[tostring(name):lower()]or ORIGIN.author
end
return P
