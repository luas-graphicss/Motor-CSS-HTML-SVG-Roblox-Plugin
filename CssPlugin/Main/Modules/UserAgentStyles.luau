local UA={VERSION=1}
local EMPTY=table.freeze({})
local PROFILES=table.freeze({legacy=true,web=true})
local SIZING=table.freeze({['content-box']=true,['border-box']=true})
local INITIAL=table.freeze({legacy=table.freeze({position='relative',['box-sizing']='border-box',['flex-direction']='column',['vertical-align']='middle',color='#eaf0fa'}),web=table.freeze({position='static',['box-sizing']='content-box',['flex-direction']='row',['vertical-align']='baseline',color='#000000'})})
local profile='legacy'
local listeners={}
UA.sizingValues=SIZING
local WEB={}
local function put(tag,declarations)
 local entry=WEB[tag]
 if not entry then entry={};WEB[tag]=entry end
 for key,value in pairs(declarations)do entry[key]=value end
end
local function each(list,declarations)
 for tag in list:gmatch('%S+')do put(tag,declarations)end
end
each('html body div p section article aside header footer main nav figure figcaption address form fieldset legend details summary dialog hgroup menu dl dt dd blockquote pre hr h1 h2 h3 h4 h5 h6 ul ol',{display='block'})
each('span a b strong i em u s small code label abbr cite q sub sup kbd samp var mark time bdi bdo del ins br',{display='inline'})
each('button input select textarea progress meter img canvas video audio iframe',{display='inline-block'})
each('head title meta link base style script template noscript',{display='none'})
put('body',{['margin-top']='8px',['margin-right']='8px',['margin-bottom']='8px',['margin-left']='8px'})
local HEADINGS={h1={'2em','0.67em'},h2={'1.5em','0.83em'},h3={'1.17em','1em'},h4={'1em','1.33em'},h5={'0.83em','1.67em'},h6={'0.67em','2.33em'}}
for tag,spec in pairs(HEADINGS)do put(tag,{['font-size']=spec[1],['font-weight']='700',['margin-top']=spec[2],['margin-bottom']=spec[2]})end
put('p',{['margin-top']='1em',['margin-bottom']='1em'})
put('ul',{['margin-top']='1em',['margin-bottom']='1em',['padding-left']='40px',['list-style-type']='disc'})
put('ol',{['margin-top']='1em',['margin-bottom']='1em',['padding-left']='40px',['list-style-type']='decimal'})
put('li',{display='list-item'})
put('dl',{['margin-top']='1em',['margin-bottom']='1em'})
put('dd',{['margin-left']='40px'})
put('blockquote',{['margin-top']='1em',['margin-bottom']='1em',['margin-left']='40px',['margin-right']='40px'})
put('figure',{['margin-top']='1em',['margin-bottom']='1em',['margin-left']='40px',['margin-right']='40px'})
put('pre',{['margin-top']='1em',['margin-bottom']='1em',['white-space']='pre',['text-wrap-mode']='nowrap'})
put('hr',{['margin-top']='0.5em',['margin-bottom']='0.5em',height='1px'})
put('table',{display='table',['border-collapse']='separate',['border-spacing']='2px',['box-sizing']='border-box'})
put('caption',{display='table-caption',['text-align']='center'})
put('th',{display='table-cell',['font-weight']='700',['text-align']='center',['vertical-align']='middle',['padding-top']='1px',['padding-right']='1px',['padding-bottom']='1px',['padding-left']='1px'})
put('td',{display='table-cell',['vertical-align']='middle',['padding-top']='1px',['padding-right']='1px',['padding-bottom']='1px',['padding-left']='1px'})
each('button input select textarea',{height='auto',['box-sizing']='border-box',['padding-top']='2px',['padding-bottom']='2px',['padding-left']='6px',['padding-right']='6px'})
put('button',{['text-align']='center'})
put('input',{['text-align']='left'})
put('select',{['text-align']='left'})
put('textarea',{['text-align']='left',['white-space']='pre-wrap',['text-wrap-mode']='wrap'})
put('fieldset',{['padding-top']='6px',['padding-right']='8px',['padding-bottom']='6px',['padding-left']='8px',['margin-left']='2px',['margin-right']='2px'})
put('legend',{['padding-left']='2px',['padding-right']='2px'})
for tag,declarations in pairs(WEB)do WEB[tag]=table.freeze(declarations)end
table.freeze(WEB)
function UA.profiles()
 local out={}
 for name in pairs(PROFILES)do out[#out+1]=name end
 table.sort(out)
 return out
end
function UA.profile()return profile end
function UA.resolve(doctype,explicit)
 if explicit~=nil then
  local name=string.lower(tostring(explicit))
  assert(PROFILES[name],'perfil compat aceita web ou legacy.')
  return name
 end
 if type(doctype)=='string'and string.lower(doctype)=='html'then return 'web'end
 return 'legacy'
end
function UA.web()return profile=='web'end
function UA.onChange(listener)
 assert(type(listener)=='function','onChange espera uma funcao.')
 listeners[#listeners+1]=listener
 return listener
end
function UA.setProfile(name)
 name=string.lower(tostring(name or ''))
 assert(PROFILES[name],'perfil compat aceita web ou legacy.')
 if name~=profile then
  profile=name
  for _,listener in ipairs(listeners)do listener(profile)end
 end
 return profile
end
function UA.initial()return INITIAL[profile]end
function UA.base(tag)
 if profile~='web'then return EMPTY end
 return WEB[tag]or EMPTY
end
function UA.sheet()
 if profile~='web'then return EMPTY end
 return WEB
end
function UA.sizing(style)
 local value=style and style['box-sizing']or 'border-box'
 assert(SIZING[value],'box-sizing aceita content-box ou border-box.')
 return value
end
function UA.sizingExtra(style,p)
 if not p or UA.sizing(style)~='content-box'then return 0,0 end
 return p[2]+p[4],p[1]+p[3]
end
function UA.axisExtra(style,p,horizontal)
 local x,y=UA.sizingExtra(style,p)
 if horizontal then return x end
 return y
end
function UA.collapse(...)
 local positive,negative=0,0
 for index=1,select('#',...)do
  local value=select(index,...)
  if type(value)=='number'then
   if value>positive then positive=value elseif value<negative then negative=value end
  end
 end
 return positive+negative
end
function UA.collapsing(style,gap,blocked)
 if profile~='web'or blocked then return false end
 if gap and gap>0.001 then return false end
 local display=style and style.display
 return display~='flex'and display~='grid'
end
function UA.selfCollapsing(box)
 return box~=nil and (box.h or 0)<=0.001
end
function UA.flowRuns(runs)
 local offsets={}
 local cursor,previous,leading=0,nil,nil
 for index,run in ipairs(runs)do
  local top=run.top or 0
  local position=previous==nil and top or cursor+UA.collapse(previous,top)
  offsets[index]=position
  if run.empty then previous=UA.collapse(previous,top,run.bottom or 0)
  else
   if leading==nil then leading=position end
   cursor=position+(run.h or 0);previous=run.bottom or 0
  end
 end
 local extent=cursor+(previous or 0)
 if leading==nil then return offsets,extent,extent,0,true end
 return offsets,extent,leading,previous or 0,false
end
function UA.flowOffsets(runs)
 local offsets,extent=UA.flowRuns(runs)
 return offsets,extent
end
function UA.flowExtent(runs)
 local _,extent=UA.flowOffsets(runs)
 return extent
end
local function words(list)
 local out={}
 for word in list:gmatch('%S+')do out[word]=true end
 return table.freeze(out)
end
local EXTRA={}
local function extra(list,declarations)
 local frozen=table.freeze(declarations)
 for tag in list:gmatch('%S+')do EXTRA[tag]=frozen end
end
extra('tr',{display='table-row'})
extra('thead',{display='table-header-group'})
extra('tbody',{display='table-row-group'})
extra('tfoot',{display='table-footer-group'})
extra('col',{display='table-column'})
extra('colgroup',{display='table-column-group'})
extra('ui',{display='block',width='100%',height='100%'})
extra('frame scroll svg center dir search',{display='block'})
extra('plaintext xmp listing',{display='block',['white-space']='pre',['text-wrap-mode']='nowrap'})
extra('text data output picture map big tt strike font nobr dfn wbr',{display='inline'})
extra('ruby',{display='ruby'})
extra('rb',{display='ruby-base'})
extra('rt',{display='ruby-text',['font-size']='50%',['line-height']='normal',['white-space']='nowrap'})
extra('rtc',{display='ruby-text-container'})
extra('rp',{display='none'})
extra('object applet marquee embed',{display='inline-block'})
extra('datalist area param source track basefont bgsound noframes',{display='none'})
extra('option optgroup',{display='block'})
table.freeze(EXTRA)
local STRUCTURAL_KEYS=table.freeze({'display','white-space','text-wrap-mode','list-style-type'})
local STRUCTURAL={}
local LEGACY_DISPLAY={}
local function legacy(list,value)
 for tag in list:gmatch('%S+')do LEGACY_DISPLAY[tag]=value end
end
legacy('ui div frame main section article header footer nav label text p h1 h2 h3 h4 h5 h6 button input textarea img scroll svg form ul ol li','block')
legacy('span b strong i em u s small br','inline')
legacy('table','table')
legacy('thead','table-header-group')
legacy('tbody','table-row-group')
legacy('tfoot','table-footer-group')
legacy('tr','table-row')
legacy('td th','table-cell')
legacy('caption','table-caption')
legacy('col','table-column')
legacy('colgroup','table-column-group')
table.freeze(LEGACY_DISPLAY)
UA.legacyDisplays=LEGACY_DISPLAY
local TEXTUAL=words('p span label text h1 h2 h3 h4 h5 h6 li td th caption a b strong i em u s small code pre kbd samp var sub sup mark time abbr cite q del ins bdi bdo dfn big tt strike font nobr legend summary option output dt figcaption')
local WHITESPACE=words('pre textarea plaintext xmp listing')
local VOID=words('area base br col embed hr img input link meta param source track wbr')
local METADATA=words('head title meta link base style script template noscript')
UA.textualTags=TEXTUAL
UA.voidTags=VOID
UA.metadataTags=METADATA
local function structural(tag)
 local cacheKey=profile..'|'..tag
 local cached=STRUCTURAL[cacheKey]
 if cached then return cached end
 local entry={}
 local web=WEB[tag]
 local more=EXTRA[tag]
 if web then for _,key in ipairs(STRUCTURAL_KEYS)do if web[key]~=nil then entry[key]=web[key]end end end
 if more then for _,key in ipairs(STRUCTURAL_KEYS)do if more[key]~=nil then entry[key]=more[key]end end end
 if entry.display==nil then entry.display='inline'end
 if profile~='web'and LEGACY_DISPLAY[tag]then entry={display=LEGACY_DISPLAY[tag]}end
 entry=table.freeze(entry)
 STRUCTURAL[cacheKey]=entry
 return entry
end
function UA.declarations(tag)return structural(string.lower(tostring(tag)))end
function UA.display(tag,attrs)
 local name=string.lower(tostring(tag))
 if attrs then
  local hidden=attrs.hidden
  if hidden~=nil and hidden~=false and hidden~='false'then return 'none'end
  if name=='input'and string.lower(tostring(attrs.type or''))=='hidden'then return 'none'end
 end
 return structural(name).display
end
function UA.isInline(tag,display)
 display=display or UA.display(tag)
 return display=='inline'or display=='inline-block'or display=='inline-flex'or display=='inline-grid'or display=='inline-table'
end
function UA.textual(tag,display)
 local name=string.lower(tostring(tag))
 if TEXTUAL[name]then return true end
 display=display or UA.display(name)
 return display=='list-item'or display=='table-cell'or display=='table-caption'
end
function UA.preservesWhitespace(tag,style)
 local value=style and style['white-space']
 if value then return value=='pre'or value=='pre-wrap'or value=='break-spaces'or value=='pre-line'end
 return WHITESPACE[string.lower(tostring(tag))]==true
end
function UA.isVoid(tag)return VOID[string.lower(tostring(tag))]==true end
function UA.isMetadata(tag)return METADATA[string.lower(tostring(tag))]==true end
function UA.base(tag)
 if profile~='web'then return EMPTY end
 local name=string.lower(tostring(tag))
 return WEB[name]or EXTRA[name]or EMPTY
end
return UA
