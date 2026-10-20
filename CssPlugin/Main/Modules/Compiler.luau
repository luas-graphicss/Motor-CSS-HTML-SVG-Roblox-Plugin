local U=require(script.Parent.Util)
local Cost=require(script.Parent.CostModel)
local Styles=require(script.Parent.Styles)
local TableHints=require(script.Parent.TableHints)
local FontFaces=require(script.Parent.FontFaces)
local FontFeatures=require(script.Parent.FontFeatures)
local Form=require(script.Parent.FormState)
local Svg=require(script.Parent.Svg)
local Runtime=require(script.Parent.Runtime)
local Paint=require(script.Parent.Paint)
local RenderOptimizer=require(script.Parent.RenderOptimizer)
local Performance=require(script.Parent.Performance)
local Assets=require(script.Parent.Assets)
local BackgroundImages=require(script.Parent.BackgroundImages)
local DirtyRender=require(script.Parent.DirtyRender)
local PropertyRegistry=require(script.Parent.PropertyRegistry)
local ViewTransitions=require(script.Parent.ViewTransitions)
local Environment=require(script.Parent.ResponsiveEnvironment)
local Env=require(script.Parent.CssEnvironment)
local Http=game:GetService('HttpService')
local Html=require(script.Parent.HtmlParser)
local Ua=require(script.Parent.UserAgentStyles)
local Presentation=require(script.Parent.Presentation)
local Manifest=require(script.Parent.RuntimeManifest)
local Release=require(script.Parent.ReleaseManifest)
local Coverage=require(script.Parent.CssCoverage)
Coverage.attach(require(script.Parent.FeatureSupports))
local C={VERSION=Manifest.VERSION}
C.coverage=Coverage
C.release=Release
function C.releaseHash()
 local ok,manifest=pcall(Release.current)
 return ok and manifest.aggregate or nil
end
local nodeKeys=setmetatable({},{__index=function(self,index)
 local key='n'..index
 rawset(self,index,key)
 return key
end})
local function owned(o) o:SetAttribute('CssOwned',true); for _,child in ipairs(o:GetDescendants()) do child:SetAttribute('CssOwned',true) end end
local function stringValue(name,value,parent) local s=Instance.new('StringValue'); s.Name=name; s.Value=value; s:SetAttribute('CssOwned',true); s.Parent=parent; return s end
C.VALUE_CHUNK=190000
local function chunkedValue(name,text,parent)
 local parts=math.max(1,math.ceil(#text/C.VALUE_CHUNK))
 local s=stringValue(name,text:sub(1,C.VALUE_CHUNK),parent)
 if parts>1 then
  s:SetAttribute('CssDocumentParts',parts)
  for i=2,parts do stringValue('Part'..i,text:sub((i-1)*C.VALUE_CHUNK+1,i*C.VALUE_CHUNK),s)end
 end
 return s
end
local function sourceHash(source)
 local h=5381;for i=1,#source do h=(h*33+source:byte(i))%4294967296 end;return h
end
function C.parse(markup,css,options)
 options=options or {};local diagnostics={};local checkpoint=options.checkpoint
 local parsed=Html.compile(markup,{recover=options.recover==true,diagnostics=diagnostics,checkpoint=checkpoint})
 local tree=parsed.tree
 local profile=Ua.resolve(parsed.document and parsed.document.doctype,options.profile)
 Ua.setProfile(profile)
 if checkpoint then
  local step=checkpoint
  checkpoint=function(...)step(...);Ua.setProfile(profile)end
  options=U.copy(options);options.checkpoint=checkpoint
 end
 if parsed.diagnostics and parsed.diagnostics~=diagnostics then for _,item in ipairs(parsed.diagnostics)do if #diagnostics<64 then diagnostics[#diagnostics+1]=item end end end
 if parsed.css and parsed.css~=''then css=(css or'')..'\n'..parsed.css end
 local svgs,ids={},{}; local count=0
 local function normalize(node,inlineParent)
  if checkpoint then checkpoint()end
  count+=1; Cost.cap('nodes',count,'Elementos semanticos')
  node.order=count; node.key=nodeKeys[count]
  node.display=node.display or Ua.display(node.tag,node.attrs)
  if node.attrs.id then assert(node.attrs.id:match('^[%a_][%w_%-]*$') and #node.attrs.id<=60,'ID inválido: '..node.attrs.id); assert(not ids[node.attrs.id],'ID duplicado: '..node.attrs.id); ids[node.attrs.id]=true end
  if node.attrs.style then node.inline=Styles.declarations(node.attrs.style) end
  TableHints.apply(node)
  if node.tag=='svg' then
   svgs[node.key]=require(script.Parent.SvgStyle).prepare(node,node.key,Styles.declarations)
   local attrs=node.attrs
   local function px(v)if v==nil then return nil end;v=tostring(v):gsub('^%s+',''):gsub('%s+$','');local n=tonumber(v);if n then return n..'px'end;if v:match('^%-?[%d%.]+%%$')or v:match('^%-?[%d%.]+[a-zA-Z]+$')then return v end;return nil end
   local w,h=px(attrs.width),px(attrs.height)
   local vw,vh
   local vb=attrs.viewbox or attrs.viewBox
   if vb then local _,_,c,d=tostring(vb):match('([%-%d%.eE]+)[%s,]+([%-%d%.eE]+)[%s,]+([%-%d%.eE]+)[%s,]+([%-%d%.eE]+)');vw,vh=tonumber(c),tonumber(d)end
   local hints=node.hints or {}
   local function hint(k,v)hints[#hints+1]={key=k,value=v}end
   if w then hint('width',w)end
   if h then hint('height',h)end
   if vw and vh and vw>0 and vh>0 then
    if not(w and h)then hint('aspect-ratio',string.format('%.6g / %.6g',vw,vh))end
    if not w and not h then hint('width','100%')end
   elseif not w and not h then hint('width','300px');hint('height','150px')
   elseif not w then hint('width','300px')
   elseif not h then hint('height','150px')end
   return {tag=node.tag,attrs=U.copy(node.attrs),children={},text='',order=node.order,key=node.key,inline=node.inline,display=node.display,ns='svg',hints=#hints>0 and hints or nil}
  end
  if node.attrs.dir then assert(node.attrs.dir=='ltr'or node.attrs.dir=='rtl','dir aceita ltr ou rtl.')end
  local className=Presentation.className(node)
  local textContainer=className=='TextLabel'or className=='TextButton'
  local hasInline=false;for _,child in ipairs(node.children)do if Ua.isInline(child.tag,child.display)then hasInline=true end end
  if node.tag=='input'or node.tag=='textarea'then assert(#node.children==0,'Campos editáveis não aceitam filhos HTML.')end
  node.rawText=node.text
  if node.tag=='input'then
   local kind=(node.attrs.type or 'text'):lower()
   if not Form.types[kind]then if #diagnostics<64 then diagnostics[#diagnostics+1]={kind='attribute',tag='input',message='Tipo de input nao suportado: '..kind}end;kind='text'end
   node.attrs.type=kind
   node.text=Form.isToggle(node)and(Form.flag(node.attrs.checked)and(node.attrs.type=='radio'and '●'or '✓')or '')or node.attrs.value or '';node.rawText=nil
  elseif not Ua.preservesWhitespace(node.tag)and not inlineParent then node.text=U.trim(node.text:gsub('%s+',' '))end
  for i,child in ipairs(node.children)do node.children[i]=normalize(child,textContainer or hasInline)end
  if #node.children==0 and node.text~=''and not textContainer and node.tag~='input'and node.tag~='textarea'then
   node.children={{tag='text',attrs={},children={},text=node.text,rawText=node.rawText,anonymousText=true,key=node.key..':text:1',order=node.order+0.0001}}
   node.text='';node.rawText=nil;node.mixedInline=false
  elseif #node.children>0 then
   local ordered={};local segments=0
   for _,part in ipairs(node.content or {})do
    if type(part)=='number'then ordered[#ordered+1]=node.children[part]
    elseif part~=''and(hasInline or textContainer or U.trim(part)~='')then
     segments+=1;ordered[#ordered+1]={tag='text',attrs={},children={},text=part,rawText=part,anonymousText=true,key=node.key..':text:'..segments,order=node.order+segments/10000}
    end
   end
   if node.content then node.children=ordered end
   node.text='';node.rawText=nil;node.mixedInline=textContainer or hasInline
  end
  node.content=nil
  return node
 end
 local root=normalize(tree)
 local rules,keyframes,fontFaces,registrations,viewTransitions,meta=Styles.parse(css,options)
 local svgRules=rules
 local transitionRules=ViewTransitions.collect(rules)
 local stylePlan;rules,stylePlan=Styles.prepare(root,rules,meta)
 stylePlan.fontFaces=FontFaces.prepare(fontFaces,options.fontAssets,diagnostics)
 local registered=PropertyRegistry.registry(registrations)
 stylePlan.registeredProperties=next(registered)and registered or nil
 stylePlan.hyphenation=options.hyphenation
 stylePlan.segmentation=options.segmentation
 stylePlan.fontVariants=FontFeatures.prepareVariants(options.fontVariants)
 stylePlan.fontFeatureValues=meta and meta.fontFeatureValues and meta.fontFeatureValues[1]and meta.fontFeatureValues or nil
 FontFeatures.diagnostics(root,rules,diagnostics,stylePlan.fontVariants,stylePlan.fontFeatureValues)
 return {version=2,profile=profile,root=root,rules=rules,stylePlan=stylePlan,keyframes=keyframes,meta=meta,width=1280,height=720,diagnostics=diagnostics,svgSources=next(svgs)and svgs or nil,svgRules=next(svgs)and svgRules or nil,viewTransitions=#viewTransitions>0 and viewTransitions or nil,viewTransitionRules=#transitionRules>0 and transitionRules or nil},svgs,count
end
function C.build(markup,css,name,options)
 options=options or {}; assert(name:match('^[%a_][%w_%-]*$') and #name<=48,'Nome: até 48 letras/números/_/-, começando com letra ou _.')
 local started=os.clock();local schedule=U.copy(options)
 if schedule.yield==nil then schedule.yield=true end
 local budget=Performance.budget(schedule)
 local profile=Ua.profile()
 local function checkpoint(units)budget:step(units);Ua.setProfile(profile)end
 local work={checkpoint=checkpoint,profile=options.profile,recover=options.recover==true,fontAssets=options.fontAssets,hyphenation=options.hyphenation,fontVariants=options.fontVariants,segmentation=options.segmentation}
 work.mediaEnvironment=Environment.read(nil,Environment.overrides(options),options.useStudioTheme==true)
 work.environment=Env.defaults()
 for key,value in pairs(Env.overrides(options.environment))do work.environment[key]=value end
 work.environmentKey=Env.key(work.environment)
 local doc,svgs,count=C.parse(markup,css,work);profile=doc.profile
 BackgroundImages.register(options.imageSizes)
 doc.effectImages=options.effectImages~=false
 doc.svgOptions={resolution=options.svgResolution,maxPrimitives=options.svgMaxPrimitives,decimation=options.svgDecimation==true,images=options.svgImages~=false,cache=options.svgCache~=false,pack=options.svgPack~=false}
 require(script.Parent.VisualEffectsAssets).register(doc,svgs)
 doc.width=math.clamp(options.width or 1280,240,7680); doc.height=math.clamp(options.height or 720,240,4320)
 local gui=Instance.new('ScreenGui'); gui.Name=name; gui.ResetOnSpawn=false; gui.DisplayOrder=10; gui.ZIndexBehavior=Enum.ZIndexBehavior.Global
 gui:SetAttribute('CssPluginVersion',C.VERSION); gui:SetAttribute('CssOwner','CssPlugin'); gui:SetAttribute('CssProject',name)
 pcall(function() gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets end)
 local objects,states,cache={},RenderOptimizer.initialStates(doc.root),{}
 doc.renderOptimizations=options.optimize~=false
 if options.svgImages~=nil then gui:SetAttribute('CssSvgImages',options.svgImages==true)end
 local result
 local ok,err=xpcall(function()
  local initialStyles,initialSequence,initialParents=Styles.compute(doc.root,doc.rules,states,doc.width,doc.height,doc.stylePlan,work)
  initialStyles=RenderOptimizer.internStyles(initialStyles)
  local plan=RenderOptimizer.plan(doc,initialStyles,initialSequence,initialParents,states,checkpoint)
  RenderOptimizer.allocate(plan,objects,checkpoint)
  local boxes,styles,sequence,parents=Runtime.render(doc,objects,doc.width,doc.height,states,cache,work)
  local primitives,icons=0,0
  for key,svg in pairs(svgs) do
   icons+=1; Cost.cap('svgs',icons,'SVGs por interface')
   local color=U.color(styles[key].color);local iconBox=boxes[key];local ancestorScale=1
   if not objects[key].Parent then
    local ancestor=parents[key]
    while ancestor do
     local parentObject=objects[ancestor.key];local scale=parentObject and parentObject:FindFirstChild('__CssScale')
     if scale and scale:IsA('UIScale')then ancestorScale*=math.abs(scale.Scale)end
     ancestor=parents[ancestor.key]
    end
   end
   local view=objects[key]:FindFirstChild('__Svg')
   if doc.svgSources and view then primitives+=view:GetAttribute('SvgPrimitives')or 0
   else primitives+=Svg.render(svg,objects[key],color,{width=iconBox.w,height=iconBox.h,pixelScale=ancestorScale,resolution=options.svgResolution,maxPrimitives=options.svgMaxPrimitives,decimation=options.svgDecimation==true,images=options.svgImages~=false,cache=options.svgCache~=false,pack=options.svgPack~=false,yield=schedule.yield~=false and function()checkpoint(48)end or nil})end
   Cost.cap('bands',primitives,'Faixas SVG')
  end
  for key in pairs(svgs)do RenderOptimizer.invalidate(objects[key])end
  work.forcePaint=svgs
  boxes,styles,sequence,parents=Runtime.render(doc,objects,doc.width,doc.height,states,cache,work)
  local assetStats=Assets.preload(objects,options,checkpoint);budget:check()
  local imageVersion=BackgroundImages.version();doc.imageSizes=BackgroundImages.collect(objects)
  if BackgroundImages.version()~=imageVersion then work.forcePaint=true;boxes,styles,sequence,parents=Runtime.render(doc,objects,doc.width,doc.height,states,cache,work)end
  RenderOptimizer.mount(doc.root,sequence,parents,objects,gui,checkpoint)
   
  for _,element in pairs(objects)do if element.Parent then Paint.inheritClipCorners(element)end end
  chunkedValue('_CssDocument',Http:JSONEncode(doc),gui)
  local runtime=Instance.new('Folder'); runtime.Name=Manifest.FOLDER; runtime.Parent=gui
  local manifest=Manifest.export(runtime,doc,script.Parent,script.Parent.Parent.Templates,checkpoint)
  stringValue(Manifest.VALUE,Http:JSONEncode(manifest),gui)
  gui:SetAttribute('CssRuntimeModules',manifest.count); gui:SetAttribute('CssRuntimeHash',manifest.aggregate); gui:SetAttribute('CssCapabilities',table.concat(manifest.enabled,' '))
  local releaseHash=C.releaseHash();if releaseHash then gui:SetAttribute('CssReleaseHash',releaseHash)end
  owned(runtime)
  local userCode=Instance.new('Folder'); userCode.Name='UserCode'; userCode.Parent=gui
  local flag=doc.root.attrs['data-demo'];local template=flag=='flex-motion'and script.Parent.Parent.Templates.Demo or flag=='counter'and(script.Parent.Parent.Templates:FindFirstChild('LegacyDemo')or script.Parent.Parent.Templates.Demo)
  if template then local demo=template:Clone();demo.Name='Demo';demo.Disabled=false;demo:SetAttribute('CssTemplateId','CssStudioDemo');demo:SetAttribute('CssTemplateHash',sourceHash(demo.Source));demo.Parent=userCode end
  local total=#gui:GetDescendants(); Cost.cap('instances',total,'Saida do documento')
  result={gui=gui,doc=doc,objects=objects,boxes=boxes,ids=plan.ids,manifest=manifest,stats={runtimeModules=manifest.count,runtimeBytes=manifest.bytes,capabilities=manifest.enabled,yields=budget.yields,assets=assetStats,diagnostics=doc.diagnostics,collapsedContainers=plan.collapsed,emptyTextSkipped=plan.emptyText,elements=count,icons=icons,svgPrimitives=primitives,instances=total,seconds=os.clock()-started,width=doc.width,height=doc.height}}
  gui:SetAttribute('CssSvgPrimitives',primitives); gui:SetAttribute('CssElements',count); gui:SetAttribute('CssSnapshotWidth',doc.width); gui:SetAttribute('CssSnapshotHeight',doc.height)
 end,debug.traceback)
 require(script.Parent.VisualEffects).release(cache,true)
 DirtyRender.reset(cache)
 if not ok then RenderOptimizer.dispose(objects);gui:Destroy();error(err,0)end
 return result
end
local function projectRoot()
 local storage=game:GetService('ServerStorage'); local root=storage:FindFirstChild('CssDocuments')
 if root then assert(root:IsA('Folder') and root:GetAttribute('CssOwner')=='CssPlugin','ServerStorage.CssDocuments já existe e pertence a outro sistema.')
 else root=Instance.new('Folder'); root.Name='CssDocuments'; root:SetAttribute('CssOwner','CssPlugin'); root.Parent=storage end
 return root
end
function C.load(name)
 local root=game:GetService('ServerStorage'):FindFirstChild('CssDocuments'); local project=root and root:FindFirstChild(name)
 if not project then return nil end
 assert(project:GetAttribute('CssOwner')=='CssPlugin','Documento de outro sistema.')
 return project.Markup.Value,project.CSS.Value
end
function C.save(name,markup,css,preparedDoc)
 assert(name:match('^[%a_][%w_%-]*$') and #name<=48,'Nome de projeto inválido.')
 Cost.cap('bytes',math.max(#markup,#css),'Codigo fonte')
 local compiled=preparedDoc or C.parse(markup,css)
 local compiledJSON=Http:JSONEncode(compiled)
 local root=projectRoot(); local folder=root:FindFirstChild(name)
 local created=folder==nil
 if folder then assert(folder:GetAttribute('CssOwner')=='CssPlugin','Projeto de outro sistema.')
 else folder=Instance.new('Folder'); folder.Name=name; folder:SetAttribute('CssOwner','CssPlugin') end
 local previous={}
 for _,pair in ipairs({{'Markup',markup},{'CSS',css},{'Compiled',compiledJSON}}) do local value=folder:FindFirstChild(pair[1]); previous[pair[1]]=value and {value=value,text=value.Value} or false end
 local savedAt=folder:GetAttribute('SavedAt')
 local function rollback()
  if created then folder:Destroy(); return end
  for key,entry in pairs(previous) do
   local value=folder:FindFirstChild(key)
   if entry then if value then value.Value=entry.text else entry.value.Parent=folder; entry.value.Value=entry.text end
   elseif value then value:Destroy() end
  end
  folder:SetAttribute('SavedAt',savedAt)
 end
 local ok,err=xpcall(function()
  for _,pair in ipairs({{'Markup',markup},{'CSS',css},{'Compiled',compiledJSON}}) do local entry=previous[pair[1]]; if entry then entry.value.Value=pair[2] else stringValue(pair[1],pair[2],folder) end end
  folder:SetAttribute('SavedAt',os.time())
  if created then folder.Parent=root end
 end,debug.traceback)
 if not ok then pcall(rollback); error(err,0) end
 return folder
end
function C.generate(markup,css,name,options)
 options=options or {}; assert(not game:GetService('RunService'):IsRunning(),'Pare o Play antes de gerar/salvar a interface.')
 local starter=game:GetService('StarterGui'); local old=starter:FindFirstChild(name)
 if old then
  assert(old:IsA('ScreenGui') and old:GetAttribute('CssOwner')=='CssPlugin' and old:GetAttribute('CssProject')==name,'Já existe uma UI com esse nome que não pertence ao plugin. Escolha outro nome.')
  local user=old:FindFirstChild('UserCode')
  for _,o in ipairs(old:GetDescendants()) do assert(o==user or (user and o:IsDescendantOf(user)) or o:GetAttribute('CssOwned')==true,'Objeto manual na saída: '..o.Name..'. Mova scripts pessoais para UserCode antes de regenerar.') end
 end
 local result=C.build(markup,css,name,options);local gui=result.gui
 if starter:FindFirstChild(name)~=old or(options.cancelled and options.cancelled())then gui:Destroy();error('Geração cancelada: o documento ou a saída mudou durante a compilação.',0)end
 if old and old:FindFirstChild('UserCode')then
  local freshDemo=gui.UserCode:FindFirstChild('Demo');if freshDemo then freshDemo.Parent=nil end
  gui.UserCode:Destroy();old.UserCode:Clone().Parent=gui
  if freshDemo then
   local previous=gui.UserCode:FindFirstChild('Demo');local legacy=script.Parent.Parent.Templates:FindFirstChild('LegacyDemo')
   local untouched=previous and previous:IsA('LocalScript')and((previous:GetAttribute('CssTemplateId')=='CssStudioDemo'and previous:GetAttribute('CssTemplateHash')==sourceHash(previous.Source))or(legacy and previous.Source==legacy.Source))
   if not previous or untouched then if previous then previous:Destroy()end;freshDemo.Parent=gui.UserCode else freshDemo:Destroy()end
  end
 end
 local history=game:GetService('ChangeHistoryService'); local recording
 if options.record~=false then
  recording=history:TryBeginRecording('CssPlugin.Generate','Gerar '..name)
  if not recording then gui:Destroy(); error('Não foi possível abrir o histórico. Finalize outra operação e tente novamente.',0) end
 end
 local ok,err=xpcall(function()
  C.save(name,markup,css,result.doc)
  if old then old.Parent=nil end
  gui.Parent=starter
  if old then old:Destroy() end
 end,debug.traceback)
 if recording then history:FinishRecording(recording,ok and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel) end
 if not ok then
  gui:Destroy()
  if old then pcall(function() old.Parent=starter end) end
  error(err,0)
 end
 return result
end
return C
