local U=require(script.Parent.Util)
local Cascade=require(script.Parent.CssCascade)
local Cost=require(script.Parent.CostModel)
local X={VERSION=1}
local function list(text)
 local values=U.split(text,',');assert(#values>0,'Lista CSS vazia.')
 local depth,q,escaped,start=0,nil,false,1
 for i=1,#text do
  local c=text:sub(i,i)
  if escaped then escaped=false
  elseif c==string.char(92)then escaped=true
  elseif q then if c==q then q=nil end
  elseif c=='"'or c=="'"then q=c
  elseif c=='('or c=='['then depth+=1
  elseif c==')'or c==']'then depth-=1
  elseif c==','and depth==0 then assert(U.trim(text:sub(start,i-1))~='','Membro vazio na lista CSS.');start=i+1 end
 end
 assert(U.trim(text:sub(start))~='','Membro vazio na lista CSS.')
 return values
end
local function replaceAmp(text,reference)
 local out,q,escaped,bracket,found={},nil,false,0,false
 for i=1,#text do
  local c=text:sub(i,i)
  if escaped then out[#out+1]=c;escaped=false
  elseif c==string.char(92)then out[#out+1]=c;escaped=true
  elseif q then out[#out+1]=c;if c==q then q=nil end
  elseif c=='"'or c=="'"then q=c;out[#out+1]=c
  elseif c=='['then bracket+=1;out[#out+1]=c
  elseif c==']'then bracket-=1;out[#out+1]=c
  elseif c=='&'and bracket==0 then
   assert(not text:sub(i+1,i+1):match('[%w_%-]'),'Nesting CSS não aceita concatenação Sass &-nome.')
   out[#out+1]=reference;found=true
  else out[#out+1]=c end
 end
 return table.concat(out),found
end
local SCOPE_REFERENCE=':where(:scope)'
function X.scopeNest(header)
 local out={}
 for _,s in ipairs(list(header))do
  local expanded,has=replaceAmp(s,SCOPE_REFERENCE)
  if has or s:find(':scope',1,true)then out[#out+1]=expanded
  else out[#out+1]=SCOPE_REFERENCE..' '..s end
 end
 return out
end
function X.scopeRootNest(header)
 local out={}
 for _,s in ipairs(list(header))do
  local expanded=replaceAmp(s,SCOPE_REFERENCE)
  out[#out+1]=expanded
 end
 return out
end
function X.nest(header,parents)
 local selectors=list(header)
 if not parents then
  for _,s in ipairs(selectors)do local _,has=replaceAmp(s,':scope');assert(not has,'& exige uma regra pai.')end
  return selectors
 end
 if parents.scoped then return X.scopeNest(header)end
 local reference=':is('..table.concat(parents,', ')..')';local out={}
 for _,s in ipairs(selectors)do
  local expanded,has=replaceAmp(s,reference)
  out[#out+1]=has and expanded or reference..' '..s
 end
 return out
end
local function item(text,p,checkpoint)
 local start=p;local round,square,q,escaped=0,0,nil,false
 while p<=#text do
  if checkpoint and(p-start)%1024==0 then checkpoint(8)end
  local c=text:sub(p,p)
  if escaped then escaped=false
  elseif c==string.char(92)then escaped=true
  elseif q then if c==q then q=nil end
  elseif c=='"'or c=="'"then q=c
  elseif c=='('then round+=1
  elseif c==')'then round-=1;assert(round>=0,'Parêntese CSS inesperado.')
  elseif c=='['then square+=1
  elseif c==']'then square-=1;assert(square>=0,'Colchete CSS inesperado.')
  elseif round==0 and square==0 then
   if c==';'then return U.trim(text:sub(start,p-1)),nil,p+1,true end
   if c=='{'then
    local header=U.trim(text:sub(start,p-1));local opening=p;local depth=1;p+=1
    q=nil;escaped=false
    while p<=#text and depth>0 do
     if checkpoint and(p-opening)%1024==0 then checkpoint(8)end
     local ch=text:sub(p,p)
     if escaped then escaped=false
     elseif ch==string.char(92)then escaped=true
     elseif q then if ch==q then q=nil end
     elseif ch=='"'or ch=="'"then q=ch
     elseif ch=='{'then depth+=1
     elseif ch=='}'then depth-=1 end
     p+=1
    end
    assert(depth==0,'Bloco CSS não fechado: '..header)
    return header,text:sub(opening+1,p-2),p,false
   end
   assert(c~='}','Chave CSS inesperada.')
  end
  p+=1
 end
 assert(not q and round==0 and square==0,'Valor CSS não fechado.')
 return U.trim(text:sub(start)),nil,p,false
end
function X.parse(css,hooks,options)
 options=options or {};local checkpoint=options.checkpoint
 local rules,keyframes,fontFaces={},{},{};local registry=Cascade.layers();local order=0;local layerEvents={};local positionTry={};local counterStyles={}
 local imports,namespaces,namespaceList,pages,fontFeatureValues,scopes={},{},{},{},{},{}
 local diagnostics=options.diagnostics or {}
 local recover=options.recover==true
 local importDepth=0
 local activeScope,activeStarting=nil,false
 local function selectorOf(piece)
  return hooks.selector(piece,0,false,{n=0,namespaces=next(namespaces)~=nil and namespaces or nil})
 end
 local function report(scope,source,message)
  diagnostics[#diagnostics+1]={scope=scope,source=type(source)=='string'and source:sub(1,120)or nil,message=tostring(message)}
 end
 local function declare(parent,name,conditions,minWidth,maxWidth)
  local layer=Cascade.layer(registry,parent,name)
  assert(#layerEvents<1024,'Máximo de 1024 declarações @layer.')
  layerEvents[#layerEvents+1]={path=table.clone(layer.path),conditions=conditions,minWidth=minWidth,maxWidth=maxWidth}
  return layer
 end
 local properties,viewTransitions={},{}
 local walk
 walk=function(text,parents,layer,conditions,minWidth,maxWidth,depth)
  assert(depth<=64,'Nesting CSS excede 64 níveis.')
  local pending={}
  local function flush()
   if #pending==0 then return end
   assert(parents,'Declaração fora de regra CSS.')
   local declarations=hooks.declarations(table.concat(pending,';'));table.clear(pending)
   if #declarations==0 then return end
   for _,sel in ipairs(parents)do
    order+=1;Cost.cap('selectors',order,'Seletores CSS')
    rules[#rules+1]={selector=selectorOf(sel),declarations=declarations,order=order,layer=layer and table.clone(layer.path)or nil,conditions=conditions,minWidth=minWidth,maxWidth=maxWidth,scope=activeScope,startingStyle=activeStarting or nil}
   end
  end
  local function handle(header,body,semicolon)
   assert(header~='','Regra CSS vazia.')
   local at=header:match('^@([%a%-]+)');local name=at and at:lower();local expression=at and U.trim(header:sub(#at+2))
   if at then
    flush()
    if name=='charset'then
     assert(semicolon and not body,'@charset exige ponto e vírgula.')
    elseif name=='import'then
     assert(semicolon and not body,'@import exige ponto e vírgula.')
     assert(not parents,'@import deve ficar no nível superior.')
     assert(#imports<32,'Máximo de 32 regras @import.')
     local entry=X.importSpec(expression)
     entry.layer=layer and table.clone(layer.path)or nil
     entry.conditions=conditions;entry.minWidth=minWidth;entry.maxWidth=maxWidth
     imports[#imports+1]=entry
     local source=hooks.import and hooks.import(entry)or nil
     if source~=nil then
      assert(type(source)=='string','Resolvedor de @import deve devolver texto CSS.')
      assert(importDepth<8,'@import excede 8 níveis.')
      local allowed=true
      if entry.supports~=nil then
       local condition=entry.supports
       local lowered=condition:lower()
       if condition:sub(1,1)~='('and not lowered:match('^not%s')and not lowered:match('^selector%s*%(')then condition='('..condition..')'end
       local okSupports,supported=pcall(function()return hooks.supports~=nil and hooks.supports(condition)==true end)
       allowed=okSupports and supported==true
       if not okSupports then report('import-supports',entry.supports,supported)end
      end
      if allowed then
       local nestedLayer=layer
       if entry.layerName then nestedLayer=declare(layer,entry.layerName,conditions,minWidth,maxWidth)
       elseif entry.anonymousLayer then nestedLayer=declare(layer,'import-'..#imports,conditions,minWidth,maxWidth)end
       local lo,hi,nextConditions=minWidth,maxWidth,conditions
       if entry.media then
        local Q=hooks.queries
        local condition={kind='media',query=Q.parse(entry.media,'media')}
        local a,b=Q.widthBounds(condition.query)
        if a then lo=math.max(lo or 0,a)end
        if b then hi=math.min(hi or math.huge,b)end
        nextConditions=Q.append(conditions,condition)
       end
       importDepth+=1
       local okImport,errImport=pcall(walk,source,parents,nestedLayer,nextConditions,lo,hi,depth+1)
       importDepth-=1
       if not okImport then error(errImport,0)end
      end
     end
    elseif name=='namespace'then
     assert(semicolon and not body,'@namespace exige ponto e vírgula.')
     assert(not parents,'@namespace deve ficar no nível superior.')
     assert(#namespaceList<32,'Máximo de 32 regras @namespace.')
     local prefix,uri=X.namespaceSpec(expression)
     namespaceList[#namespaceList+1]={prefix=prefix,uri=uri}
     if prefix then namespaces[prefix]=uri else namespaces['']=uri end
    elseif name=='layer'then
     if body then
      assert(not expression:find(',',1,true),'Bloco @layer aceita um único nome.')
      local nested=declare(layer,expression,conditions,minWidth,maxWidth)
      walk(body,parents,nested,conditions,minWidth,maxWidth,depth+1)
     else
      assert(semicolon and expression~='','Declaração @layer exige nomes e ponto e vírgula.')
      for _,part in ipairs(list(expression))do declare(layer,part,conditions,minWidth,maxWidth)end
     end
    elseif name=='supports'then
     assert(body,'@supports exige bloco.')
     if hooks.supports(expression)then walk(body,parents,layer,conditions,minWidth,maxWidth,depth+1)end
    elseif name=='media'or name=='container'then
     assert(body,'Regra condicional exige bloco.')
     local Q=hooks.queries
     local condition=name=='media'and {kind='media',query=Q.parse(expression,'media')}or Q.container(expression)
     local lo,hi=minWidth,maxWidth
     if name=='media'then local a,b=Q.widthBounds(condition.query);if a then lo=math.max(lo or 0,a)end;if b then hi=math.min(hi or math.huge,b)end end
     walk(body,parents,layer,Q.append(conditions,condition),lo,hi,depth+1)
    elseif name=='keyframes'then
     assert(body and not parents,'@keyframes deve estar fora de uma regra de estilo.')
     assert(not hooks.queries.hasContainer({conditions=conditions}),'@keyframes em @container não é suportado; condicione animation-name.')
     local animation=assert(expression:match('^([%a_][%w_%-]*)$'),'Nome @keyframes inválido.')
     assert(#keyframes<32,'Máximo de 32 definições @keyframes.')
     local definition=hooks.keyframes(animation,body,minWidth,maxWidth,#keyframes+1)
     definition.conditions=conditions;definition.layer=layer and table.clone(layer.path)or nil;keyframes[#keyframes+1]=definition
    elseif name=='font-face'then
     assert(body and expression==''and not parents and not hooks.queries.hasContainer({conditions=conditions}),'@font-face fora de contexto.')
     assert(#fontFaces<32,'Máximo de 32 @font-face.')
     local face=hooks.fontFace(body);face.minWidth=minWidth;face.maxWidth=maxWidth;face.conditions=conditions;face.layer=layer and table.clone(layer.path)or nil;fontFaces[#fontFaces+1]=face
    elseif name=='position-try'then
     assert(body and not parents,'@position-try deve estar fora de uma regra de estilo.')
     assert(not hooks.queries.hasContainer({conditions=conditions}),'@position-try em @container nao e suportado; condicione position-try-fallbacks.')
     local tryName=assert(expression:match('^(%-%-[%w_%-]+)$'),'@position-try exige um nome --ident.')
     assert(#positionTry<32,'Máximo de 32 blocos @position-try.')
     positionTry[#positionTry+1]={name=tryName,declarations=hooks.declarations(body)}
    elseif name=='property'then
     assert(body and not parents and not conditions,'@property deve ficar no nível superior, fora de @media/@container.')
     assert(hooks.property,'@property não é suportado por este parser.')
     assert(#properties<64,'Máximo de 64 registros @property.')
     local registration=hooks.property(expression,body);registration.layer=layer and table.clone(layer.path)or nil
     properties[#properties+1]=registration
    elseif name=='view-transition'then
     assert(body and expression==''and not parents and not conditions,'@view-transition deve ficar no nível superior, sem prelúdio.')
     assert(hooks.viewTransition,'@view-transition não é suportado por este parser.')
     assert(#viewTransitions<8,'Máximo de 8 regras @view-transition.')
     local transition=hooks.viewTransition(body);transition.layer=layer and table.clone(layer.path)or nil
     viewTransitions[#viewTransitions+1]=transition
    elseif name=='counter-style'then
     assert(body and expression~=''and not parents,'@counter-style deve estar fora de uma regra de estilo.')
     assert(not hooks.queries.hasContainer({conditions=conditions}),'@counter-style em @container nao e suportado; condicione list-style-type.')
     assert(#counterStyles<64,'Máximo de 64 definições @counter-style.')
     local factory=assert(hooks.counterStyle,'@counter-style não configurado.')
     local definition=factory(expression,body)
     definition.minWidth=minWidth;definition.maxWidth=maxWidth;definition.conditions=conditions;definition.layer=layer and table.clone(layer.path)or nil
     counterStyles[#counterStyles+1]=definition
    elseif name=='scope'then
     assert(body,'@scope exige bloco.')
     local spec=X.scopeSpec(expression)
     local saved=activeScope
     local level=(saved and saved.depth or 0)+1
     assert(level<=8,'@scope excede 8 níveis.')
     local record={root=spec.root,limit=spec.limit,depth=level,index=#scopes+1,parent=saved}
     local outer=parents and not parents.scoped and parents or nil
     local rootPieces
     if spec.root then
      if saved then rootPieces=X.scopeRootNest(spec.root)
      else rootPieces=outer and X.nest(spec.root,outer)or list(spec.root)end
     elseif outer then rootPieces=table.clone(outer)end
     if rootPieces then
      record.rootSelectors={}
      for _,piece in ipairs(rootPieces)do
       local sel=selectorOf(piece)
       assert(not sel.pseudoElement,'@scope não aceita pseudo-elemento como raiz.')
       record.rootSelectors[#record.rootSelectors+1]=sel
      end
     end
     if spec.limit then
      record.limitSelectors={}
      for _,piece in ipairs(X.scopeNest(spec.limit))do
       local sel=selectorOf(piece)
       assert(not sel.pseudoElement,'@scope não aceita pseudo-elemento como limite.')
       record.limitSelectors[#record.limitSelectors+1]=sel
      end
     end
     scopes[#scopes+1]=record
     local nestedParents={SCOPE_REFERENCE,scoped=true}
     activeScope=record
     local okScope,errScope=pcall(walk,body,nestedParents,layer,conditions,minWidth,maxWidth,depth+1)
     activeScope=saved
     if not okScope then error(errScope,0)end
    elseif name=='starting-style'then
     assert(body,'@starting-style exige bloco.')
     local saved=activeStarting
     activeStarting=true
     local okStart,errStart=pcall(walk,body,parents,layer,conditions,minWidth,maxWidth,depth+1)
     activeStarting=saved
     if not okStart then error(errStart,0)end
    elseif name=='page'then
     assert(body and not parents,'@page deve estar fora de uma regra de estilo.')
     assert(#pages<32,'Máximo de 32 regras @page.')
     local selectors=expression==''and{''}or list(expression)
     local pagePseudos={first=true,left=true,right=true,blank=true}
     for _,piece in ipairs(selectors)do
      if piece~=''then
       local pageName,pagePseudo=piece:match('^([%a_][%w_%-]*):([%a][%w%-]*)$')
       if not pageName then pagePseudo=piece:match('^:([%a][%w%-]*)$')end
       if not pageName and not pagePseudo then pageName=piece:match('^([%a_][%w_%-]*)$')end
       assert(pageName~=nil or pagePseudo~=nil,'Seletor @page inválido: '..piece)
       assert(pagePseudo==nil or pagePseudos[pagePseudo:lower()]==true,'Pseudoclasse @page inválida: '..piece)
      end
     end
     local buffer,marginRules={},{}
     local q=1
     while q<=#body do
      local innerHeader,innerBody,nextQ=item(body,q,checkpoint);q=nextQ
      if innerHeader~=''then
       local marginAt=innerHeader:match('^@([%a%-]+)')
       if marginAt then
        assert(innerBody,'Regra de margem @page exige bloco.')
        local okMargin,parsedMargin=pcall(hooks.page or hooks.declarations,innerBody)
        marginRules[#marginRules+1]={name=marginAt:lower(),declarations=okMargin and parsedMargin or {},source=U.trim(innerBody)}
        if not okMargin then report('page-margin',innerBody,parsedMargin)end
       elseif innerBody then error('@page não aceita regras aninhadas: '..innerHeader,0)
       else buffer[#buffer+1]=innerHeader end
      end
     end
     local raw=table.concat(buffer,';')
     local okPage,parsedPage=pcall(hooks.page or hooks.declarations,raw)
     if not okPage then report('page',raw,parsedPage)end
     pages[#pages+1]={selectors=selectors,declarations=okPage and parsedPage or {},source=raw,margins=marginRules,layer=layer and table.clone(layer.path)or nil,conditions=conditions,minWidth=minWidth,maxWidth=maxWidth}
    elseif name=='font-feature-values'then
     assert(body and expression~=''and not parents,'@font-feature-values exige famílias e bloco.')
     assert(#fontFeatureValues<32,'Máximo de 32 regras @font-feature-values.')
     local families={}
     for _,family in ipairs(list(expression))do
      local clean=U.trim(family)
      local head=clean:sub(1,1)
      if head=='"'or head=="'"then clean=clean:sub(2,#clean-1)end
      assert(clean~='','Família inválida em @font-feature-values.')
      families[#families+1]=clean
     end
     local groups={}
     local q=1
     while q<=#body do
      local innerHeader,innerBody,nextQ=item(body,q,checkpoint);q=nextQ
      if innerHeader~=''then
       local groupName=innerHeader:match('^@([%a%-]+)')
       assert(groupName and innerBody,'@font-feature-values aceita apenas grupos @nome { }.')
       local values={}
       for _,line in ipairs(U.split(innerBody,';'))do
        local key,raw=line:match('^%s*([%a_][%w_%-]*)%s*:%s*(.-)%s*$')
        assert(key and raw and raw~='','Valor inválido em @'..groupName..': '..line)
        local indexes={}
        for token in raw:gmatch('%S+')do
         local number=tonumber(token)
         assert(number and number>=0 and number==math.floor(number),'@'..groupName..' aceita apenas inteiros.')
         indexes[#indexes+1]=number
        end
        assert(#indexes>0,'@'..groupName..' exige ao menos um índice.')
        values[key:lower()]=indexes
       end
       groups[groupName:lower()]=values
      end
     end
     fontFeatureValues[#fontFeatureValues+1]={families=families,groups=groups,layer=layer and table.clone(layer.path)or nil,conditions=conditions}
    else error('Regra @ não suportada: '..header,0)end
   elseif body then
    flush();walk(body,X.nest(header,parents),layer,conditions,minWidth,maxWidth,depth+1)
   else
    assert(parents and header:match('^[%w_%-]+%s*:'),'Regra CSS sem bloco: '..header)
    pending[#pending+1]=header
   end
  end
  local p=1
  while p<=#text do
   if checkpoint then checkpoint()end
   local okItem,header,body,nextPos,semicolon=pcall(item,text,p,checkpoint)
   if not okItem then
    if not recover then error(header,0)end
    report('block',text:sub(p,math.min(#text,p+96)),header);break
   end
   p=nextPos
   if header==''and not body then continue end
   local mark=#rules
   local okRule,errRule=pcall(handle,header,body,semicolon)
   if not okRule then
    for index=#rules,mark+1,-1 do rules[index]=nil end
    if not recover then error(errRule,0)end
    report('rule',header,errRule)
   end
  end
  flush()
 end
 walk(css,nil,nil,nil,nil,nil,0)
 if #positionTry>0 and rules[1]then rules[1].positionTry=positionTry end
 if #counterStyles>0 and rules[1]then rules[1].counterStyles=counterStyles end
 if #layerEvents>0 then
  if rules[1]then rules[1].layerEvents=layerEvents end
  if keyframes[1]then keyframes[1].layerEvents=layerEvents end
  if fontFaces[1]then fontFaces[1].layerEvents=layerEvents end
 end
 local meta={imports=imports,namespaces=namespaces,namespaceList=namespaceList,pages=pages,fontFeatureValues=fontFeatureValues,scopes=scopes,counterStyles=counterStyles,diagnostics=diagnostics}
 if rules[1]then rules[1].meta=meta;rules[1].namespaces=namespaces end
 return rules,keyframes,fontFaces,properties,viewTransitions,meta
end
function X.importSpec(text)
 local rest=U.trim(text or '')
 local entry={}
 local urlWhole=rest:match('^url%s*%b()')
 local href
 if urlWhole then
  href=U.trim(urlWhole:match('^url%s*%((.*)%)$'))
  rest=U.trim(rest:sub(#urlWhole+1))
 else
  local quote=rest:sub(1,1)
  assert(quote=='"'or quote=="'",'@import exige url() ou string.')
  local close=rest:find(quote,2,true)
  assert(close,'String de @import não fechada.')
  href=rest:sub(2,close-1)
  rest=U.trim(rest:sub(close+1))
 end
 local head=href:sub(1,1)
 if head=='"'or head=="'"then href=href:sub(2,#href-1)end
 href=U.trim(href)
 assert(href~='','@import exige um alvo.')
 entry.href=href
 local layerWhole=rest:match('^layer%s*%b()')
 if layerWhole then
  entry.layerName=U.trim(layerWhole:match('^layer%s*%((.*)%)$'))
  assert(entry.layerName~='','layer() de @import exige um nome.')
  rest=U.trim(rest:sub(#layerWhole+1))
 elseif rest=='layer'or rest:match('^layer%s')then
  entry.anonymousLayer=true
  rest=U.trim(rest:sub(6))
 end
 local supportsWhole=rest:match('^supports%s*%b()')
 if supportsWhole then
  entry.supports=U.trim(supportsWhole:match('^supports%s*%((.*)%)$'))
  assert(entry.supports~='','supports() de @import exige uma condição.')
  rest=U.trim(rest:sub(#supportsWhole+1))
 end
 if rest~=''then entry.media=rest end
 return entry
end
function X.namespaceSpec(text)
 local rest=U.trim(text or '')
 local prefix
 local ident=rest:match('^([%a_][%w_%-]*)%s')
 if ident and not rest:match('^url%s*%b()')then
  prefix=ident
  rest=U.trim(rest:sub(#ident+1))
 end
 local uri
 local urlWhole=rest:match('^url%s*%b()')
 if urlWhole then uri=U.trim(urlWhole:match('^url%s*%((.*)%)$'))
 else
  local quote=rest:sub(1,1)
  assert(quote=='"'or quote=="'",'@namespace exige url() ou string.')
  local close=rest:find(quote,2,true)
  assert(close,'String de @namespace não fechada.')
  uri=rest:sub(2,close-1)
  rest=U.trim(rest:sub(close+1))
  assert(rest=='','Préludio @namespace inválido: '..text)
 end
 local head=uri:sub(1,1)
 if head=='"'or head=="'"then uri=uri:sub(2,#uri-1)end
 uri=U.trim(uri)
 assert(uri~='','@namespace exige um URI.')
 return prefix,uri
end
function X.scopeSpec(text)
 local rest=U.trim(text or '')
 local spec={}
 if rest==''then return spec end
 local root=rest:match('^%b()')
 if root then
  spec.root=U.trim(root:sub(2,#root-1))
  assert(spec.root~='','@scope exige um seletor raiz.')
  rest=U.trim(rest:sub(#root+1))
 end
 if rest~=''then
  local keyword=rest:match('^%a+')
  assert(keyword and keyword:lower()=='to','Préludio @scope inválido: '..text)
  rest=U.trim(rest:sub(#keyword+1))
  local limit=rest:match('^%b()')
  assert(limit,'@scope to exige (seletor).')
  spec.limit=U.trim(limit:sub(2,#limit-1))
  assert(spec.limit~='','@scope to exige um seletor.')
  assert(U.trim(rest:sub(#limit+1))=='','Préludio @scope inválido: '..text)
 end
 return spec
end
X.list=list
return X
