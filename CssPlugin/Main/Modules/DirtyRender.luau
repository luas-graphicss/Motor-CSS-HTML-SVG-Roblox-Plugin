local Styles=require(script.Parent.Styles)
local Layout=require(script.Parent.Layout)
local ContextUnits=require(script.Parent.ContextUnits)
local Queries=require(script.Parent.ResponsiveQueries)
local Optimizer=require(script.Parent.RenderOptimizer)
local PseudoElements=require(script.Parent.PseudoElements)
local Regions=require(script.Parent.DirtyRegions)
local releaseAdapter={releaseTree=Optimizer.release}
local P=require(script.Parent.Performance)
local D={};local contexts=setmetatable({},{__mode='k'})
local visual={background=true,['background-color']=true,color=true,opacity=true,transform=true,['z-index']=true,['box-shadow']=true,['border-color']=true,['border-radius']=true,['border-top-left-radius']=true,['border-top-right-radius']=true,['border-bottom-left-radius']=true,['border-bottom-right-radius']=true,['text-align']=true,['vertical-align']=true,['text-overflow']=true}
for _,key in ipairs(require(script.Parent.VisualEffectsStyle).keys)do visual[key]=true end
for _,key in ipairs({'background-image','background-size','background-position','background-repeat','background-attachment','background-origin','background-clip','background-blend-mode','border-top-color','border-right-color','border-bottom-color','border-left-color'})do visual[key]=true end
for _,key in ipairs({'transform-origin','perspective','perspective-origin','backface-visibility'})do visual[key]=true end
local geometryKeys=setmetatable({},{__mode='k'})
function D.isVisual(key)return visual[key]==true end
local function overlayStyles(styles,overlay)
 if not overlay or next(overlay)==nil then return styles,styles end
 local out=table.clone(styles)
 for key,props in pairs(overlay)do
  local style=out[key]
  if style and next(props)~=nil then
   local copy=table.clone(style)
   for k,v in pairs(props)do copy[k]=v end
   out[key]=copy
  end
 end
 return out,styles
end
local function geometry(style)
 local cached=geometryKeys[style];if cached then return cached end
 local keys={}
 for key in pairs(style)do
  if key:sub(1,1)~='_'and not visual[key]and key:sub(1,10)~='animation-'and key:sub(1,11)~='transition-'then keys[#keys+1]=key end
 end
 table.sort(keys);local parts={}
 for _,key in ipairs(keys)do
  local item=style[key];local value=type(item)=='table'and Optimizer.signature(item)or tostring(item)
  parts[#parts+1]=key..':'..#value..':'..value
 end
 if style._gridColumns then parts[#parts+1]=Optimizer.signature(style._gridColumns)end
 if style._gridTracks then parts[#parts+1]=Optimizer.signature(style._gridTracks)end
 parts[#parts+1]=Optimizer.signature({fontSource=style._fontSource,ch=style._chPx,ex=style._exPx,lineHeight=style._lineHeight,parentWriting=style._parentWritingKey,fontFeatures=style._openTypeFeatures,fontAxes=style._fontAxes})
 cached=table.concat(parts,'|');geometryKeys[style]=cached;return cached
end
function D.reset(cache)contexts[cache]=nil end
function D.sameBox(a,b)
 if a==b then return true end;if not a or not b then return false end
 if a.inlineStamp~=b.inlineStamp or a.inlineManaged~=b.inlineManaged then return false end
 if a.fragmentSignature~=b.fragmentSignature or a.columnSignature~=b.columnSignature or a.tableSignature~=b.tableSignature or a.collapsedCell~=b.collapsedCell then return false end
 if a.x~=b.x or a.y~=b.y or a.w~=b.w or a.h~=b.h or a.fs~=b.fs or a.hidden~=b.hidden or a.contentW~=b.contentW or a.contentH~=b.contentH then return false end
 if a.viewportX~=b.viewportX or a.viewportY~=b.viewportY or a.clipMargin~=b.clipMargin or a.clipRelaxed~=b.clipRelaxed then return false end
 for i=1,4 do
  if a.p[i]~=b.p[i]then return false end
  if (a.textPadding and a.textPadding[i])~=(b.textPadding and b.textPadding[i])then return false end
 end
 return true
end
function D.plan(doc,objects,width,height,state,cache,work)
 work=work or {};local before=contexts[cache]
 local mediaKey=Queries.environmentKey(work.mediaEnvironment)..'|'..tostring(work.environmentKey or '')
 local viewport=not before or before.width~=width or before.height~=height
 local styles,sequence,parents,stateNeeds,visualRoot
 if work.textOnly and before and not viewport and not work.full and before.rules==doc.rules and before.mediaKey==mediaKey then
  styles,sequence,parents,stateNeeds,visualRoot=before.baseStyles or before.styles,before.sequence,before.parents,before.stateNeeds,before.visualRoot
 else
  styles,sequence,parents,stateNeeds,visualRoot=Styles.compute(doc.root,doc.rules,state,width,height,doc.stylePlan,work)
  styles=Optimizer.internStyles(styles)
 end
 local containerBoxes
 if ContextUnits.needed(styles,doc.rules)then
  styles,sequence,parents,stateNeeds,visualRoot,containerBoxes=ContextUnits.solve(doc,styles,sequence,parents,stateNeeds,visualRoot,width,height,state,objects,work,Styles.compute,Layout.solve,before and before.boxes)
  styles=Optimizer.internStyles(styles)
 end
 local baseStyles
 styles,baseStyles=overlayStyles(styles,work.motionOverlay)
 local structural=not before or #before.sequence~=#sequence
 if not structural then
  for i,node in ipairs(sequence)do
   local previous=before.sequence[i];local parent=parents[node.key];local previousParent=before.parents[node.key]
   if node.key~=previous.key or node.tag~=previous.tag or (parent and parent.key)~=(previousParent and previousParent.key)then structural=true;break end
  end
 end
 PseudoElements.reconcile(objects,cache,sequence,releaseAdapter)
 Optimizer.ensure(doc,styles,sequence,objects,state,cache,work.checkpoint)
 local hints=work.dirtyKeys
 local hintStyle,hintLayout,hintPaint
 if hints then
  if hints.full then work.full=true
  else hintStyle,hintLayout,hintPaint=hints.style,hints.layout,hints.paint end
 end
 local full=viewport or structural or work.full==true
 if full then hintStyle,hintLayout,hintPaint=nil,nil,nil end
 if hintPaint and next(hintPaint)then
  local force=work.forcePaint
  if force~=true then
   if type(force)~='table'then force={}end
   for key in pairs(hintPaint)do force[key]=true end
   work.forcePaint=force
  end
 end
 local dirty,texts,keys,changedStyles={},{},{},{}
 local count,changed=0,0
 for _,node in ipairs(sequence)do
  local key=node.key;local object=objects[key]
  local entry=cache[key];if not entry then entry={};cache[key]=entry end
  if entry.metaObject~=object then
   entry.metaObject=object;entry.isText=object and(object:IsA('TextLabel')or object:IsA('TextButton')or object:IsA('TextBox'))or false
   entry.isInteractive=object and(object:IsA('GuiButton')or object:IsA('TextBox'))or false
  end
  texts[key]=node.textOwnerKey and objects[node.textOwnerKey]and objects[node.textOwnerKey].Text or entry.isText and object.Text or node.text or ''
  keys[key]=geometry(styles[key])
  if full or keys[key]~=before.geometry[key]or texts[key]~=before.texts[key]or(hintLayout~=nil and hintLayout[key]==true)then dirty[key]=true;count+=1 end
  if not before or styles[key]~=before.styles[key]or(hintStyle~=nil and hintStyle[key]==true)then
   changedStyles[key]=true;changed+=1
   if before and before.boxes[key]and before.boxes[key].inlineManaged and not dirty[key]then dirty[key]=true;count+=1 end
  end
  if work.checkpoint then work.checkpoint()end
 end
 for _,node in ipairs(sequence)do if changedStyles[node.key]and styles[node.key].display=='table-cell'then
  local ancestor=parents[node.key];while ancestor do local d=styles[ancestor.key].display;if d=='table'or d=='inline-table'then dirty[ancestor.key]=true;count+=1;break end;ancestor=parents[ancestor.key]end
 end end
 local roots={};for key in pairs(dirty)do roots[#roots+1]=key end
 for _,key in ipairs(roots)do local parent=parents[key];while parent do dirty[parent.key]=true;parent=parents[parent.key]end end
 local memo=full and {}or before.memo
 local boxes=before and before.boxes
 local relayout=full or count>0 or containerBoxes~=nil
 if containerBoxes then boxes=containerBoxes;memo={}
 elseif relayout then boxes=Layout.solve(visualRoot or doc.root,styles,width,height,objects,{memo=memo,dirty=dirty,previous=not full and boxes or nil,checkpoint=work.checkpoint,skipped=work.contentVisibility,hyphenation=doc.stylePlan and doc.stylePlan.hyphenation,segmentation=doc.stylePlan and doc.stylePlan.segmentation,doc=doc})end
 for _,node in ipairs(sequence)do
  if node.textSlotKey then
   local box=table.clone(boxes[node.key]);local slot=boxes[node.textSlotKey]
   box.textSlot=slot;box.textPadding={slot.y,math.max(0,box.w-slot.x-slot.w),math.max(0,box.h-slot.y-slot.h),slot.x}
   boxes[node.key]=box
  end
 end
 local regions=Regions.new({viewport={w=width,h=height},limit=work.regionLimit})
 if full then regions:markFull(viewport and 'viewport'or'estrutura')
 else
  local previous=before and before.boxes
  for key in pairs(dirty)do
   if previous then regions:addBox(previous[key])end
   regions:addBox(boxes and boxes[key])
  end
  for key in pairs(changedStyles)do regions:addBox(boxes and boxes[key])end
  local force=work.forcePaint
  if force==true then regions:markFull('paint')
  elseif type(force)=='table'then for key in pairs(force)do regions:addBox(boxes and boxes[key])end end
 end
 local painted=regions:flush()
 work.regions=painted
 local result={styles=styles,baseStyles=baseStyles,sequence=sequence,parents=parents,stateNeeds=stateNeeds,boxes=boxes,changedStyles=changedStyles,relayout=relayout,viewportChanged=viewport,full=full,work=work,regions=painted,
  stats={styleChanges=changed,layoutDirty=count,relayout=relayout,measurements=relayout and(boxes[doc.root.key].measureCount or 0)or 0,painted=0,regions=painted.full and-1 or #painted.rects,coverage=painted.ratio or 0,hinted=hints~=nil}}
 contexts[cache]={styles=styles,baseStyles=baseStyles,sequence=sequence,parents=parents,stateNeeds=stateNeeds,visualRoot=visualRoot,boxes=boxes,geometry=keys,texts=texts,width=width,height=height,memo=memo,rules=doc.rules,mediaKey=mediaKey}
 return result
end
function D.paintNeeded(plan,key,entry,object,style,box,opacity)
 local force=plan.work.forcePaint
 return plan.viewportChanged or force==true or(type(force)=='table'and force[key])or entry.renderObject~=object or entry.renderStyle~=style or entry.renderOpacity~=opacity or not D.sameBox(entry.renderBox,box)
end
function D.painted(plan,entry,object,style,box,opacity)
 entry.renderObject=object;entry.renderStyle=style;entry.renderBox=box;entry.renderOpacity=opacity
 plan.stats.painted+=1
end
return D
