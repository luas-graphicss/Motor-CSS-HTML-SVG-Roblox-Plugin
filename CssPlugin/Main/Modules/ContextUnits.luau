local Queries=require(script.Parent.ResponsiveQueries)
local Anchors=require(script.Parent.CssAnchors)
local Logical=require(script.Parent.LogicalProperties)
local C={VERSION=3}
function C.needed(styles,rules)
 if Queries.hasContainers(rules)then return true end
 for _,style in pairs(styles)do
  if style._usesContainer or style._usesAnchor or style['container-type']=='size'then return true end
 end
 return false
end
local function contextMap(styles,sequence,parents,boxes,vw,vh)
 local result={}
 for _,node in ipairs(sequence)do
  local width,height,inline,block
  local parent=parents[node.key]
  while parent and(width==nil or height==nil or inline==nil or block==nil)do
   local style=styles[parent.key]
   local kind=style and style['container-type']or 'normal'
   local vertical=style and Logical.axes(style).vertical
   local x=kind=='size'or(kind=='inline-size'and not vertical)
   local y=kind=='size'or(kind=='inline-size'and vertical)
   local box=boxes and boxes[parent.key]
   local cw=box and math.max(0,box.w-(box.p[2]or 0)-(box.p[4]or 0))or vw
   local ch=box and math.max(0,box.h-(box.p[1]or 0)-(box.p[3]or 0))or vh
   if (kind=='size'or kind=='inline-size')and inline==nil then inline=vertical and ch or cw end
   if kind=='size'and block==nil then block=vertical and cw or ch end
   if x and width==nil then width=box and math.max(0,box.w-(box.p[2]or 0)-(box.p[4]or 0))or vw end
   if y and height==nil then height=box and math.max(0,box.h-(box.p[1]or 0)-(box.p[3]or 0))or vh end
   parent=parents[parent.key]
  end
  local ownVertical=Logical.axes(styles[node.key]).vertical
  result[node.key]={containerWidth=width or vw,containerHeight=height or vh,containerInline=inline or(ownVertical and vh or vw),containerBlock=block or(ownVertical and vw or vh),containersResolved=true}
 end
 return Anchors.enrich(result,styles,sequence,parents,boxes,vw,vh)
end
local function same(a,b)
 for key,value in pairs(a)do
  local other=b[key]
  if not other or value.anchorKey~=other.anchorKey or math.abs(value.containerWidth-other.containerWidth)>0.00001 or math.abs(value.containerHeight-other.containerHeight)>0.00001 or math.abs((value.containerInline or 0)-(other.containerInline or 0))>0.00001 or math.abs((value.containerBlock or 0)-(other.containerBlock or 0))>0.00001 then return false end
 end
 for key in pairs(b)do if not a[key]then return false end end
 return true
end
local function containment(styles)
 local out=styles
 for key,style in pairs(styles)do
  if style['container-type']=='size'or style['container-type']=='inline-size'then
   local vertical=Logical.axes(style).vertical
   local containHeight=style['container-type']=='size'or vertical
   if containHeight and(style.height==nil or style.height=='auto')then
    if out==styles then out=table.clone(styles)end
    local copy=table.clone(style);copy.height=0;out[key]=copy
   end
  end
 end
 return out
end
function C.solve(doc,styles,sequence,parents,stateNeeds,visualRoot,width,height,state,objects,work,compute,layout,previousBoxes)
 local contexts=contextMap(styles,sequence,parents,previousBoxes,width,height)
 local options=table.clone(work or {});options.unitContexts=contexts
 local hasQueries=Queries.hasContainers(doc.rules)
 if hasQueries then options.querySnapshot={styles=styles,boxes=previousBoxes}end
 local passes=math.min(44,#sequence+3)
 for pass=1,passes do
  if options.checkpoint then options.checkpoint()end
  styles,sequence,parents,stateNeeds,visualRoot=compute(doc.root,doc.rules,state,width,height,doc.stylePlan,options)
  local boxes=layout(visualRoot or doc.root,containment(styles),width,height,objects,{checkpoint=options.checkpoint,hyphenation=doc.stylePlan and doc.stylePlan.hyphenation,segmentation=doc.stylePlan and doc.stylePlan.segmentation,doc=doc})
  local nextContexts=contextMap(styles,sequence,parents,boxes,width,height)
  local nextSnapshot=hasQueries and {styles=styles,boxes=boxes}or nil
  local queriesStable=not hasQueries or Queries.truthKey(doc.rules,sequence,parents,options.querySnapshot,width,height,options.mediaEnvironment,options.checkpoint)==Queries.truthKey(doc.rules,sequence,parents,nextSnapshot,width,height,options.mediaEnvironment,options.checkpoint)
  if same(contexts,nextContexts)and queriesStable then
   boxes[doc.root.key].containerPasses=pass
   boxes[doc.root.key].containerQueryPasses=hasQueries and pass or nil
   return styles,sequence,parents,stateNeeds,visualRoot,boxes
  end
  contexts=nextContexts;options.unitContexts=contexts;options.querySnapshot=nextSnapshot
 end
 error('Unidades/queries/âncoras não convergiram. Defina tamanhos explícitos ou container-type:size; dependência cíclica de layout.',0)
end
C.contexts=contextMap
return C
