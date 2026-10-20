local U=require(script.Parent.Util)
local Cost=require(script.Parent.CostModel)
local Variables=require(script.Parent.CssVariables)
local Selectors=require(script.Parent.Selectors)
local Queries=require(script.Parent.ResponsiveQueries)
local Cascade=require(script.Parent.CssCascade)
local S={VERSION=1}
S.inherited={'fill','fill-opacity','fill-rule','stroke','stroke-width','stroke-opacity','stroke-linecap','stroke-linejoin','stroke-miterlimit','stroke-dasharray','stroke-dashoffset','marker-start','marker-mid','marker-end','clip-rule','paint-order','shape-rendering','color-interpolation','color-interpolation-filters','visibility','font-family','font-size','font-weight','font-style','font-stretch','font-variant','text-anchor','dominant-baseline','letter-spacing','word-spacing','direction','writing-mode','text-rendering','image-rendering','pointer-events'}
S.defaults={fill='#000000',['fill-opacity']='1',['fill-rule']='nonzero',stroke='none',['stroke-width']='1',['stroke-opacity']='1',['stroke-linecap']='butt',['stroke-linejoin']='miter',['stroke-miterlimit']='4',['stroke-dasharray']='none',['stroke-dashoffset']='0',['marker-start']='none',['marker-mid']='none',['marker-end']='none',['clip-rule']='nonzero',['paint-order']='normal',['vector-effect']='none',['shape-rendering']='auto',['color-interpolation']='sRGB',['color-interpolation-filters']='linearRGB',visibility='visible',['stop-color']='#000000',['stop-opacity']='1',['flood-color']='#000000',['lighting-color']='#ffffff',['flood-opacity']='1',['mask-type']='luminance',filter='none',['clip-path']='none',mask='none',opacity='1',display='inline',color='currentColor',transform='none',['font-family']='sans-serif',['font-size']='16',['font-weight']='400',['font-style']='normal',['font-stretch']='normal',['font-variant']='normal',['text-anchor']='start',['dominant-baseline']='auto',['letter-spacing']='normal',['word-spacing']='normal',direction='ltr',['writing-mode']='horizontal-tb',['text-rendering']='auto',['image-rendering']='auto',['pointer-events']='visiblePainted',overflow='hidden'}
S.properties={};for k in pairs(S.defaults)do S.properties[k]=true end
S.properties['mask-image']=true;S.properties.marker=true
local inherited={color=true};for _,k in ipairs(S.inherited)do inherited[k]=true end
local timed={animate=true,animatetransform=true,animatemotion=true,set=true,mpath=true}
S.timed=timed
function S.register(supported,shorthands)
 for k in pairs(S.properties)do supported[k]=true end
 if shorthands then shorthands.marker={'marker-start','marker-mid','marker-end'}end
end
function S.expand(name,value)
 if name=='marker'then return {['marker-start']=value,['marker-mid']=value,['marker-end']=value}end
end
function S.inline(text)
 local result={}
 for _,part in ipairs(U.split(Variables.stripComments(text or ''),';'))do
  local k,v=part:match('^%s*([%w_%-]+)%s*:%s*(.-)%s*$')
  if not k or v=='' then continue end
  if k:sub(1,2)~='--'then k=k:lower()end
  if not(S.properties[k]or k:sub(1,2)=='--')then continue end
  local important=v:match('%s*![iI][mM][pP][oO][rR][tT][aA][nN][tT]%s*$')~=nil
  v=U.trim(v:gsub('%s*![iI][mM][pP][oO][rR][tT][aA][nN][tT]%s*$',''))
  result[#result+1]={key=k,value=v,important=important}
 end;return result
end
function S.prepare(svg,key,parse)
 local serial,ids=0,{};parse=parse or S.inline
 local function visit(node,isRoot)
  serial+=1;Cost.cap('nodes',serial,'Nós SVG')
  local copy={tag=node.tag,attrs=U.copy(node.attrs),text=node.text or '',children={},key=isRoot and key or key..':svg:'..serial,order=serial,content=node.content}
  local id=copy.attrs.id
  if id then assert(not ids[id],'ID SVG duplicado: '..id);ids[id]=true end
  if copy.attrs.style then copy.inline=parse(copy.attrs.style)end
  for _,child in ipairs(node.children or {})do copy.children[#copy.children+1]=visit(child,false)end
  return copy
 end
 return visit(svg,true)
end
local function colorText(c)return string.format('rgb(%.9g,%.9g,%.9g)',c.R*255,c.G*255,c.B*255)end
function S.signature(node)
 local out={'svg-style-1'}
 local function add(v)v=tostring(v);out[#out+1]=#v..':'..v end
 local function walk(n)
  add(n.tag);local keys={};for k in pairs(n.attrs or {})do keys[#keys+1]=k end;table.sort(keys)
  for _,k in ipairs(keys)do add(k);add(n.attrs[k])end;add('/')
  for _,child in ipairs(n.children or {})do walk(child)end;add('end')
 end;walk(node);return table.concat(out)
end
function S.legacyTree(root)
 local simple={svg=true,g=true,path=true,rect=true,circle=true,ellipse=true,line=true,polyline=true,polygon=true,title=true,desc=true}
 local paint={fill=true,stroke=true,['stroke-width']=true,['fill-rule']=true,['fill-opacity']=true,['stroke-opacity']=true,['stroke-linecap']=true,['stroke-linejoin']=true,['stroke-miterlimit']=true,['stroke-dasharray']=true,['stroke-dashoffset']=true,color=true,opacity=true,transform=true}
 local function walk(n)
  local a=n.attrs;if not simple[n.tag]or a.pathlength or a.display=='none'or(a.visibility and a.visibility~='visible')then return nil end
  for _,k in ipairs({'filter','clip-path','mask','mask-image','marker-start','marker-mid','marker-end'})do if a[k]and a[k]~='none'then return nil end end
  if(a.fill and a.fill:find('url%('))or(a.stroke and a.stroke:find('url%('))or(n.tag=='g'and a.opacity and tonumber(a.opacity)~=1)then return nil end
  local d=a['stroke-dasharray'];if d and d~='none'and(d:find('%%')or d:match('%f[%d]0%f[^%d%.]')or d:find('px',1,true))then return nil end
  if a['stroke-width']and not tonumber(a['stroke-width'])then return nil end
  if(a['vector-effect']and a['vector-effect']~='none')or(a['paint-order']and a['paint-order']~='normal')then return nil end
  if a.requiredfeatures or a.requiredextensions or a.systemlanguage or a['data-viewport']then return nil end
  local out={tag=n.tag,attrs=U.copy(a),children={},text=n.text,key=n.key}
  for k in pairs(S.properties)do if not paint[k]then out.attrs[k]=nil end end
  if out.attrs.transform=='none'then out.attrs.transform=nil end
  for _,child in ipairs(n.children)do if child.tag=='svg'then return nil end;local copy=walk(child);if not copy then return nil end;out.children[#out.children+1]=copy end
  return out
 end
 return walk(root)
end
function S.context(doc,styles,state,width,height,boxes,work)
 local parents,sequence,roots,classes={},{},{},{}
 local function copy(node,parent)
  local source=doc.svgSources and doc.svgSources[node.key]
  local n=table.clone(source or node);n.attrs=U.copy(n.attrs);n.children={}
  if source then for k,v in pairs(node.attrs)do n.attrs[k]=v end;n.inline=node.inline or source.inline;roots[node.key]=n end
  if source or(parent and parent.ns=='svg')then n.ns='svg'end
  parents[n.key]=parent;sequence[#sequence+1]=n;classes[n.key]={}
  for word in (n.attrs.class or ''):gmatch('%S+')do classes[n.key][word]=true end
  for _,child in ipairs((source or node).children or {})do n.children[#n.children+1]=copy(child,n)end
  return n
 end
 copy(doc.root,nil)
 local rules=doc.svgRules or doc.rules or {};local active={}
 local environment=work and work.mediaEnvironment or nil
 for i,rule in ipairs(rules)do active[i]=Queries.mediaActive(rule,width,height,environment)end
 local queryParents={}
 for _,n in ipairs(sequence)do local p=parents[n.key];while p and boxes and not boxes[p.key]do p=parents[p.key]end;queryParents[n.key]=p end
 local needs=Selectors.statePlan({scope={rules=rules},sequence=sequence,classes=classes,active=active})
 return {parents=parents,queryParents=queryParents,sequence=sequence,roots=roots,classes=classes,rules=rules,active=active,state=state or {},styles=styles,runtime=true,width=width,height=height,environment=environment,snapshot={styles=styles,boxes=boxes}},needs
end
function S.resolve(root,currentColor,env)
 env=env or {};currentColor=currentColor or Color3.new(0,0,0)
 local parents=env.parents or {};local rules=env.rules or {};local styles={}
 local layerOrder=Cascade.order(rules[1]and rules[1].layerEvents,env.width,env.height,env.environment)
 local function walk(node,parentStyle,isRoot)
  local st={};for k,v in pairs(S.defaults)do st[k]=(inherited[k]and parentStyle and parentStyle[k])or v end
  local winners={}
  local function put(k,v,meta)
   if not(S.properties[k]or k:sub(1,2)=='--')then return end
   if k=='marker'then for _,p in ipairs({'marker-start','marker-mid','marker-end'})do put(p,v,meta)end;return end
   if k=='mask-image'then k='mask'end
   meta=meta or {specificity=-1,order=-1,layer={-1000000}}
   Cascade.apply(winners,{{key=k,value=v,important=meta.important}},meta.specificity,meta.order,meta.layer,meta.inline,layerOrder)
  end
  for k,v in pairs(node.attrs or {})do if S.properties[k]then put(k,v)end end
  for i,rule in ipairs(rules)do
   if (not env.active or env.active[i])and(not env.runtime or Queries.matches(rule,env.width,env.height,env.environment,node,env.queryParents,env.snapshot))and not rule.selector.pseudoElement and Selectors.matches(rule.selector,node,env.state,parents,env.classes)then
    for _,d in ipairs(rule.declarations)do
     if not(isRoot and env.runtime and(d.key=='transform'or d.key=='opacity'))then
      if not d.shorthand or d.shorthand=='marker'or(d.shorthand=='mask'and d.key=='mask-image')then
       put(d.key,d.value,{important=d.important,specificity=rule.selector.specificity,order=rule.order,layer=rule.layer})
      end
     end
    end
   end
  end
  for _,d in ipairs(node.inline or S.inline(node.attrs.style))do
   if not(isRoot and env.runtime and(d.key=='transform'or d.key=='opacity'))then
    if not d.shorthand or d.shorthand=='marker'or(d.shorthand=='mask'and d.key=='mask-image')then put(d.key,d.value,{important=d.important,specificity=0,order=501,inline=true})end
   end
  end
  Cascade.finish(winners)
  local vars=Variables.compute(parentStyle and parentStyle._vars,winners);st._vars=vars
  for k,d in pairs(winners)do if k:sub(1,2)~='--'then
   local v=Variables.resolve(d.value,vars)
   if v=='inherit'or(v=='unset'and inherited[k])then v=parentStyle and parentStyle[k]or S.defaults[k]
   elseif v=='initial'or v=='unset'then v=S.defaults[k]end
   st[k]=v
  end end
  if not st.color or st.color:lower()=='currentcolor'then st.color=parentStyle and parentStyle.color or colorText(currentColor)end
  if isRoot and env.runtime then
   st.opacity='1'
   st.transform=node.attrs.transform or 'none'
   for _,property in ipairs({'filter','clip-path','mask'})do
    if st[property]and st[property]~='none'and not st[property]:match('^%s*url')then st[property]='none'end
   end
  end
  local animated=env.animated and env.animated(node.key,st,node.attrs)or nil
  if animated then for k,v in pairs(animated)do if S.properties[k]then st[k]=v end end end
  styles[node.key]=st
  local out={tag=node.tag,attrs=U.copy(node.attrs),children={},key=node.key,text=node.text,content=node.content}
  out.attrs.style=nil
  for k in pairs(S.properties)do out.attrs[k]=nil end
  for k,v in pairs(st)do if k~='_vars'and k~='marker'and k~='mask-image'then out.attrs[k]=v end end
  if animated then for k,v in pairs(animated)do if not S.properties[k]then out.attrs[k]=v end end end
  for _,child in ipairs(node.children or {})do
   if not timed[child.tag]then
    if not env.parents then parents[child.key]=node end
    out.children[#out.children+1]=walk(child,st,false)
   end
  end
  return out
 end
 local parent=parents[root.key];local host=parent and env.styles and env.styles[parent.key]
 local result=walk(root,host,true);result._svgResolved=true;return result,styles
end
function S.htmlStyle(style)
 local copy
 for _,k in ipairs({'filter','clip-path','mask','mask-image'})do
  local v=style[k]
  if v and v:match('^%s*url%s*%(%s*[\"\']?#')then copy=copy or U.copy(style);copy[k]='none'end
 end
 return copy or style
end
function S.isAdvanced(root)
 if root._svgResolved then return true end
 local advanced={defs=true,lineargradient=true,radialgradient=true,stop=true,filter=true,fegaussianblur=true,fedropshadow=true,clippath=true,mask=true,marker=true,use=true,symbol=true,pattern=true,image=true,text=true,tspan=true,textpath=true,switch=true,foreignobject=true}
 local function visit(n)
  if advanced[n.tag]then return true end
  local a=n.attrs or {}
  if a['marker-start']or a['marker-mid']or a['marker-end']or a['clip-rule']or a['clip-path']or a.mask or a.filter or a.pathlength then return true end
  if a.requiredfeatures or a.requiredextensions or a.systemlanguage then return true end
  if(a['vector-effect']and a['vector-effect']~='none')or(a['paint-order']and a['paint-order']~='normal')then return true end
  if a.style and(a.style:find('url%(')or a.style:find('marker',1,true)or a.style:find('clip-rule',1,true))then return true end
  if(a.fill and a.fill:find('url%('))or(a.stroke and a.stroke:find('url%('))then return true end
  if(n.tag=='g'or n.tag=='svg')and a.opacity and tonumber(a.opacity)~=1 then return true end
  if a['stroke-dasharray']and(a['stroke-dasharray']:find('%%')or a['stroke-dasharray']:match('%f[%d]0%f[^%d%.]'))then return true end
  for _,c in ipairs(n.children or {})do if c.tag=='svg'or visit(c)then return true end end
  return false
 end;return visit(root)
end
return S
