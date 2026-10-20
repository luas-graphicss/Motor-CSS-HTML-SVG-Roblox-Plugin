local Compiler=require(script.Parent.Compiler)
local Runtime=require(script.Parent.Runtime)
local Example=require(script.Parent.Example)
local Performance=require(script.Parent.Performance)
local SessionStore=require(script.Parent.SessionStore)
local Theme=require(script.Parent.EditorTheme)
local Kit=require(script.Parent.EditorKit)
local Syntax=require(script.Parent.EditorSyntax)
local E={}
local TextService=game:GetService('TextService')
local clear=table.clear
local CODE_SIZE=14
local LINE_HEIGHT=1.5
local PITCH=CODE_SIZE*LINE_HEIGHT
local BAND_OFFSET=math.floor((PITCH-CODE_SIZE)/2)
local GUTTER=56
local CODE_LEFT=14
local CODE_TOP=14
local CODE_BOTTOM=36
local HEADER=56
local PROJECT=56
local TABS=42
local CONSOLE=156
local MIN_HEIGHT=560
local GUIDE={
 steps={
  'HTML + SVG define a árvore. CSS define a aparência.',
  'Escolha um nome de projeto e clique em Gerar UI.',
  'A ScreenGui aparece em StarterGui com objetos reais.',
  'Salve o place (Ctrl+S). Isso grava a saída E os códigos em ServerStorage.CssDocuments.',
  'F5: a UI vai para PlayerGui; o runtime já acompanha a saída.',
  'Exemplo inclui botões, campo de texto e um contador local.',
 },
 sections={
  {title='ALTERAÇÕES E SEGURANÇA',body={
   'Salvar guarda os códigos no place sem regenerar a saída. Alterações no editor também ficam em um rascunho local do plugin; esse rascunho NÃO substitui salvar o place.',
   'Gerar substitui a árvore produzida pelo plugin. Sua lógica personalizada deve ficar na pasta UserCode da ScreenGui; ela é preservada. Use IDs HTML estáveis para reencontrar os objetos. A geração não substitui UIs de outros sistemas.',
  }},
  {title='SUBCONJUNTO, NÃO UM NAVEGADOR',body={
   'Seletores: tag, #id, .classe, descendente, >, + e ~, [atributo], :is/:where/:not/:has, nth-*, :hover, :active, :focus, :disabled e estados de formulário; variáveis e !important. At-rules aceitas: @media, @container, @keyframes e @font-face; as demais são recusadas com erro. Block, flex row/column com wrap, grid com px/%/fr/repeat, colunas, tabelas e sticky. Medidas px/%/em/rem/vw/vh e unidades de contêiner, min/max/clamp e calc. Bordas, raios, box-shadow, border-image, backgrounds em camadas e gradientes linear/radial/cônico/repetido. Cada recurso tem escopo limitado: o painel avisa o que não foi aplicado.',
   'SVG: path M L H V C S Q T A Z (também relativos), rect, circle, ellipse, polygon, polyline, line, grupos e transformações afins. Fill nonzero/evenodd, stroke, caps, joins e dash. Pintura aproximada em faixas nativas com antialiasing limitado. data-resolution="32" reduz custo; máximo 128. O painel informa quantas faixas foram geradas.',
   'SVG avançado é parcial: defs/use, gradientes, servidores de pintura, máscaras, marcadores e filtros são reconhecidos com escopo limitado e o painel avisa o que não foi aplicado. Não há DOM/JavaScript, CSS completo nem foreignObject. Filtros e backdrop-filter amostram apenas a própria interface CSS: não capturam o mundo 3D nem outras ScreenGuis. Use fill="currentColor" nos SVGs para acompanhar color do CSS. Opacity de contêiner usa composição isolada de grupo quando há efeito ativo; sem efeito, multiplica por elemento. Cantos não recortam descendentes como clip-path. Máscara e alpha são apresentação, nunca controle de acesso: valide ações importantes no servidor.',
  }},
  {title='TEXTO E INTERAÇÃO',body={
   'Texto nativo: Gotham, Arial, SourceSans e monospace. Activated funciona com mouse/toque/gamepad no cliente. Ações importantes do jogo devem ser validadas pelo servidor.',
  }},
  {title='PERSISTÊNCIA',body={
   'Não são usados rbxtemp, EditableImage/EditableMesh, conteúdo efêmero, bibliotecas de ícones de terceiros ou uploads. A aparência já fica nas propriedades das instâncias. Responsividade/estados do jogo precisam manter _CssRuntime e _CssDocument.',
   'A aparência salva reabre sem o plugin. Recompilar exige o plugin. Uma mudança de CSS não altera uma exportação antiga até clicar em Gerar UI.',
  }},
 },
}
local function codeExtent(text)
 local count,longest,start=1,0,1
 while start<=#text do
  local stop=string.find(text,'\n',start,true)
  if not stop then return count,math.max(longest,#text-start+1)end
  longest=math.max(longest,stop-start);count+=1;start=stop+1
 end
 return count,longest
end
local function yieldCompile()task.wait()end
local function plural(count,one,many)
 return tostring(count)..' '..(count==1 and one or many)
end
local function describeDiagnostics(list)
 if type(list)~='table'or #list==0 then return nil end
 local lines={}
 for _,d in ipairs(list)do
  if type(d)~='table'then lines[#lines+1]=tostring(d)
  else
   local where={}
   if d.tag~=nil then where[#where+1]='<'..tostring(d.tag)..'>'end
   if d.family~=nil then where[#where+1]='@font-face '..tostring(d.family)end
   if d.property~=nil then where[#where+1]=tostring(d.property)end
   if d.key~=nil then where[#where+1]='nó '..tostring(d.key)end
   if d.offset~=nil then where[#where+1]='caractere '..tostring(d.offset)end
   if d.code~=nil then where[#where+1]='['..tostring(d.code)..']'end
   local text=d.message~=nil and tostring(d.message)or(d.code~=nil and tostring(d.code)or 'aviso sem descrição')
   local prefix=d.kind~=nil and(tostring(d.kind)..': ')or ''
   lines[#lines+1]='• '..prefix..(#where>0 and(table.concat(where,', ')..': ')or '')..text
  end
 end
 return table.concat(lines,'\n')
end
local function savedProjects()
 local root=game:GetService('ServerStorage'):FindFirstChild('CssDocuments')
 local names={}
 if root and root:GetAttribute('CssOwner')=='CssPlugin' then
  for _,child in ipairs(root:GetChildren())do
   if child:FindFirstChild('Markup')then names[#names+1]=child.Name end
  end
 end
 table.sort(names)
 return names
end
local function readableError(err)
 local text=tostring(err)
 local first,rest=string.match(text,'^([^\n]*)\n?(.*)$')
 first=string.gsub(first or text,'^[%w%._]+:%d+: ','')
 return first,rest
end
function E.start(plugin,main)
 local connections={};local schedulers={};local alive,busy,dirty=true,false,false;local currentController;local confirmation
 local tab,refreshDirty,setConfirmation,saveDraft
 local function frame(callback)local s=Performance.coalesce(function()if alive then callback()end end);schedulers[#schedulers+1]=s;return s end
 local function connect(signal,fn)local c=signal:Connect(fn);table.insert(connections,c);return c end
 local theme=Theme.new()
 local kit=Kit.new(theme,connect)
 local make=kit.make
 local toolbar=plugin:CreateToolbar('CSS Studio')
 local iconOk,icon=pcall(function()return game:GetService('StudioService'):GetClassIcon('ScreenGui').Image end)
 local toggle=toolbar:CreateButton('CssStudio.Editor.v1','Escreva HTML, CSS e SVG; gere UI persistente.',iconOk and type(icon)=='string' and icon or '','Editor')
 toggle.ClickableWhenViewportHidden=true
 local info=DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right,false,false,560,760,480,540)
 local ok,widget=pcall(function()return plugin:CreateDockWidgetPluginGuiAsync('CssStudio.Editor.v1',info)end)
 if not ok then widget=plugin:CreateDockWidgetPluginGui('CssStudio.Editor.v1',info)end
 widget.Title='CSS Studio'
 widget.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
 local shell=make('ScrollingFrame',widget,{Name='ResponsiveShell',Size=UDim2.fromScale(1,1),BorderSizePixel=0,ScrollBarThickness=6,ScrollingDirection=Enum.ScrollingDirection.Y,CanvasSize=UDim2.fromOffset(0,MIN_HEIGHT)},{BackgroundColor3='canvas',ScrollBarImageColor3='scroll'})
 local root=make('Frame',shell,{Name='Editor',Size=UDim2.new(1,0,0,MIN_HEIGHT),BorderSizePixel=0},{BackgroundColor3='canvas'})
 local function fitDock()
  local available=shell.AbsoluteSize.Y
  local height=math.max(MIN_HEIGHT,available)
  local size=UDim2.new(1,height>available and -6 or 0,0,height);local canvas=UDim2.fromOffset(0,height)
  if root.Size~=size then root.Size=size end;if shell.CanvasSize~=canvas then shell.CanvasSize=canvas end
 end
 local dockResize=frame(fitDock)
 connect(shell:GetPropertyChangedSignal('AbsoluteSize'),function()dockResize:request()end);fitDock()
 local header=make('Frame',root,{Name='Header',Size=UDim2.new(1,0,0,HEADER),BorderSizePixel=0},{BackgroundColor3='surface'})
 kit.divider(header,'bottom')
 local mark=kit.mark(header,{position=UDim2.new(0,16,0.5,0),anchor=Vector2.new(0,0.5)})
 local brand=make('Frame',header,{Name='Brand',BackgroundTransparency=1,Position=UDim2.fromOffset(52,0),Size=UDim2.new(0,0,1,0),AutomaticSize=Enum.AutomaticSize.X})
 kit.list(brand,Enum.FillDirection.Horizontal,8)
 kit.text(brand,{Name='Title',Text='CSS Studio',FontFace=Theme.font('sans',Enum.FontWeight.Bold),TextSize=16,AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.fromScale(0,1),LayoutOrder=1},'ink')
 kit.chip(brand,2,'v'..tostring(Compiler.VERSION))
 local generate=kit.button(header,{name='Gerar UI',text='Gerar UI',variant='primary',position=UDim2.new(1,-16,0.5,0),anchor=Vector2.new(1,0.5),size=UDim2.fromOffset(112,34)})
 local projectBar=make('Frame',root,{Name='ProjectBar',Position=UDim2.fromOffset(0,HEADER),Size=UDim2.new(1,0,0,PROJECT),BorderSizePixel=0},{BackgroundColor3='surface'})
 kit.divider(projectBar,'bottom')
 local save=kit.button(projectBar,{name='Salvar',text='Salvar',position=UDim2.new(1,-16,0.5,0),anchor=Vector2.new(1,0.5),size=UDim2.fromOffset(96,34),pending=true})
 local load=kit.button(projectBar,{name='Carregar',text='Carregar',position=UDim2.new(1,-120,0.5,0),anchor=Vector2.new(1,0.5),size=UDim2.fromOffset(104,34)})
 local field=kit.field(projectBar,{name='ProjectName',prefix='StarterGui.',text='CssDemo',placeholder='NomeDaUI',position=UDim2.new(0,16,0.5,0),anchor=Vector2.new(0,0.5),size=UDim2.new(1,-248,0,34)})
 local project=field.box
 local tabBar=make('Frame',root,{Name='TabBar',Position=UDim2.fromOffset(0,HEADER+PROJECT),Size=UDim2.new(1,0,0,TABS),BorderSizePixel=0},{BackgroundColor3='surface'})
 kit.divider(tabBar,'bottom')
 local tabs=kit.tabs(tabBar,{{key='html',name='HTML + SVG',glyph='</>',text='HTML'},{key='css',name='CSS',glyph='{ }',text='CSS'},{key='help',name='Guia',glyph='?',text='Guia'}},function(key)tab(key)end)
 tabs.holder.Position=UDim2.fromOffset(4,0)
 local actions=make('Frame',tabBar,{Name='Actions',BackgroundTransparency=1,AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-10,0.5,0),Size=UDim2.fromOffset(0,30),AutomaticSize=Enum.AutomaticSize.X})
 kit.list(actions,Enum.FillDirection.Horizontal,2,Enum.HorizontalAlignment.Right)
 local example=kit.button(actions,{name='Exemplo',text='Exemplo',variant='quiet',height=30,pad=10,order=1})
 local importButton=kit.button(actions,{name='Importar',text='Importar',variant='quiet',height=30,pad=10,order=2})
 local body=make('Frame',root,{Name='Body',Position=UDim2.fromOffset(0,HEADER+PROJECT+TABS),Size=UDim2.new(1,0,1,-(HEADER+PROJECT+TABS+CONSOLE)),BorderSizePixel=0,ClipsDescendants=true},{BackgroundColor3='canvas'})
 local views={};local selected='html'
 local charWidth=CODE_SIZE*7/13
 local function codeView(name,initial,language,placeholder)
  local view=make('Frame',body,{Name=name,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false})
  local gutter=make('Frame',view,{Name='Gutter',Size=UDim2.new(0,GUTTER,1,0),BorderSizePixel=0,ClipsDescendants=true,ZIndex=2},{BackgroundColor3='canvas'})
  local numbers=kit.text(gutter,{Name='Lines',Text='1',FontFace=Theme.font('mono'),TextSize=CODE_SIZE,LineHeight=LINE_HEIGHT,TextXAlignment=Enum.TextXAlignment.Right,TextYAlignment=Enum.TextYAlignment.Top,Position=UDim2.fromOffset(0,CODE_TOP),Size=UDim2.new(1,-16,0,CODE_SIZE)},'faint')
  local activeNumber=make('TextLabel',gutter,{Name='ActiveLine',Text='',FontFace=Theme.font('mono',Enum.FontWeight.Medium),TextSize=CODE_SIZE,TextXAlignment=Enum.TextXAlignment.Right,TextYAlignment=Enum.TextYAlignment.Center,Size=UDim2.new(1,0,0,PITCH),BorderSizePixel=0,Visible=false,ZIndex=3},{TextColor3='ink',BackgroundColor3='band'})
  kit.pad(activeNumber,0,16,0,0)
  local scroll=make('ScrollingFrame',view,{Name='Scroll',Position=UDim2.fromOffset(GUTTER,0),Size=UDim2.new(1,-GUTTER,1,0),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=8,ScrollingDirection=Enum.ScrollingDirection.XY,CanvasSize=UDim2.new()},{ScrollBarImageColor3='scroll'})
  local band=make('Frame',scroll,{Name='CurrentLine',Size=UDim2.new(1,0,0,PITCH),BorderSizePixel=0,Visible=false},{BackgroundColor3='band'})
  local box=make('TextBox',scroll,{Name='Code',Position=UDim2.fromOffset(CODE_LEFT,CODE_TOP),Size=UDim2.fromOffset(400,400),Text=initial,PlaceholderText=placeholder,ClearTextOnFocus=false,MultiLine=true,TextEditable=true,TextWrapped=false,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,FontFace=Theme.font('mono'),TextSize=CODE_SIZE,LineHeight=LINE_HEIGHT,BackgroundTransparency=1,BorderSizePixel=0,ZIndex=2},{PlaceholderColor3='faint'})
  local paint=make('TextLabel',box,{Name='Highlight',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,RichText=true,Text='',TextWrapped=false,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,FontFace=Theme.font('mono'),TextSize=CODE_SIZE,LineHeight=LINE_HEIGHT,ZIndex=3},{TextColor3='ink'})
  local numbered,activeLine=-1,nil
  local needsLayout,needsPaint,needsCaret=true,true,false
  local cache={}
  local function layout()
   local count,longest=codeExtent(box.Text)
   if numbered~=count then
    for index=1,count do cache[index]=tostring(index)end
    numbers.Text=table.concat(cache,'\n',1,count);numbered=count;clear(cache)
   end
   local viewport=scroll.AbsoluteSize
   local textHeight=CODE_SIZE+(count-1)*PITCH
   local width=math.max(math.floor(viewport.X)-CODE_LEFT-16,math.ceil(longest*charWidth)+48)
   local height=math.max(math.floor(viewport.Y)-CODE_TOP,textHeight+CODE_BOTTOM)
   box.Size=UDim2.fromOffset(width,height)
   numbers.Size=UDim2.new(1,-16,0,textHeight)
   scroll.CanvasSize=UDim2.fromOffset(CODE_LEFT+width+16,CODE_TOP+height)
  end
  local function highlight()
   local text=box.Text
   if language and #text>0 and #text<=Syntax.LIMIT then
    local painted,rich=pcall(Syntax[language],text,theme.syntax)
    if painted then
     paint.Text=rich;paint.Visible=true;box.TextColor3=theme.colors.muted
     return
    end
   end
   paint.Visible=false;paint.Text='';box.TextColor3=theme.colors.ink
  end
  local function placeActive()
   if not activeLine then return end
   activeNumber.Position=UDim2.fromOffset(0,math.floor(CODE_TOP+(activeLine-1)*PITCH-BAND_OFFSET-scroll.CanvasPosition.Y))
  end
  local function caret()
   local position=box.CursorPosition
   if position<1 or not box:IsFocused() then
    activeLine=nil;band.Visible=false;activeNumber.Visible=false
    return
   end
   local text=box.Text
   local before=string.sub(text,1,position-1)
   local line,lineStart=1,1
   for index in string.gmatch(before,'()\n')do line+=1;lineStart=index+1 end
   local column=utf8.len(string.sub(before,lineStart)) or (#before-lineStart+1)
   activeLine=line
   local top=CODE_TOP+(line-1)*PITCH-BAND_OFFSET
   band.Position=UDim2.fromOffset(0,top);band.Visible=true
   activeNumber.Text=tostring(line);activeNumber.Visible=true
   local canvas=scroll.CanvasPosition
   local window=scroll.AbsoluteWindowSize
   local x=CODE_LEFT+column*charWidth
   local nextX,nextY=canvas.X,canvas.Y
   if top<canvas.Y then nextY=math.max(0,top-PITCH)
   elseif top+PITCH>canvas.Y+window.Y-12 then nextY=top+PITCH*2-window.Y end
   if x<canvas.X+8 then nextX=math.max(0,x-64)
   elseif x>canvas.X+window.X-24 then nextX=x-window.X+80 end
   if nextX~=canvas.X or nextY~=canvas.Y then scroll.CanvasPosition=Vector2.new(nextX,nextY)end
   placeActive()
  end
  local sync=frame(function()
   if needsLayout then needsLayout=false;layout()end
   if needsPaint then needsPaint=false;highlight()end
   if needsCaret then needsCaret=false;caret()end
  end)
  local function request(layoutFlag,paintFlag,caretFlag)
   if layoutFlag then needsLayout=true end
   if paintFlag then needsPaint=true end
   if caretFlag then needsCaret=true end
   sync:request()
  end
  connect(box:GetPropertyChangedSignal('Text'),function()
   request(true,true,true)
   refreshDirty()
   if confirmation then setConfirmation(nil)end
  end)
  connect(box:GetPropertyChangedSignal('CursorPosition'),function()request(false,false,true)end)
  connect(box.Focused,function()request(false,false,true)end)
  connect(box.FocusLost,function()request(false,false,true)end)
  connect(scroll:GetPropertyChangedSignal('AbsoluteSize'),function()request(true,false,true)end)
  connect(scroll:GetPropertyChangedSignal('CanvasPosition'),function()
   numbers.Position=UDim2.fromOffset(0,CODE_TOP-scroll.CanvasPosition.Y)
   placeActive()
  end)
  theme:changed(function()request(false,true,false)end)
  layout();highlight();needsLayout=false;needsPaint=false
  views[name]={frame=view,scroll=scroll,box=box,refresh=function()request(true,true,false)end}
  return box
 end
 local function guideView()
  local view=make('ScrollingFrame',body,{Name='help',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=8,ScrollingDirection=Enum.ScrollingDirection.Y,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),Visible=false},{ScrollBarImageColor3='scroll'})
  kit.pad(view,22,28,32,28)
  kit.list(view,Enum.FillDirection.Vertical,0,nil,Enum.VerticalAlignment.Top)
  local order=0
  local function nextOrder()order+=1;return order end
  local function gap(size)make('Frame',view,{Name='Gap',BackgroundTransparency=1,Size=UDim2.new(1,0,0,size),LayoutOrder=nextOrder()})end
  local function paragraph(text,token)
   return kit.text(view,{Name='Paragraph',Text=text,TextSize=14,LineHeight=1.45,TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,LayoutOrder=nextOrder()},token)
  end
  local function heading(text)
   gap(28)
   kit.text(view,{Name='Heading',Text=text,FontFace=Theme.font('mono',Enum.FontWeight.SemiBold),TextSize=13,Size=UDim2.new(1,0,0,18),LayoutOrder=nextOrder()},'accentText')
   gap(10)
  end
  kit.text(view,{Name='Title',Text='Guia rápido',FontFace=Theme.font('sans',Enum.FontWeight.Bold),TextSize=20,Size=UDim2.new(1,0,0,28),LayoutOrder=nextOrder()},'ink')
  gap(6)
  paragraph('CSS Studio '..tostring(Compiler.VERSION)..' transforma HTML, CSS e SVG em objetos reais no Explorer. O texto continua editável e os botões continuam interativos.','muted')
  heading('PRIMEIROS PASSOS')
  for index,step in ipairs(GUIDE.steps)do
   local row=make('Frame',view,{Name='Step',BackgroundTransparency=1,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,LayoutOrder=nextOrder()})
   kit.text(row,{Name='Index',Text=string.format('%02d',index),FontFace=Theme.font('mono',Enum.FontWeight.Medium),TextSize=13,TextYAlignment=Enum.TextYAlignment.Top,Position=UDim2.fromOffset(0,2),Size=UDim2.fromOffset(28,18)},'accentText')
   kit.text(row,{Name='Text',Text=step,TextSize=14,LineHeight=1.45,TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,Position=UDim2.fromOffset(34,0),Size=UDim2.new(1,-34,0,0),AutomaticSize=Enum.AutomaticSize.Y},'ink')
   gap(8)
  end
  for _,section in ipairs(GUIDE.sections)do
   heading(section.title)
   for index,text in ipairs(section.body)do
    if index>1 then gap(12)end
    paragraph(text,'muted')
   end
  end
  views.help={frame=view,refresh=function()end}
 end
 local html=codeView('html',Example.markup,'html','Escreva aqui o HTML + SVG da interface…')
 local css=codeView('css',Example.css,'css','Escreva aqui o CSS…')
 guideView()
 local console=make('Frame',root,{Name='Console',AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale(0,1),Size=UDim2.new(1,0,0,CONSOLE),BorderSizePixel=0},{BackgroundColor3='surface'})
 kit.divider(console,'top')
 local statusDot=kit.status(console,{position=UDim2.fromOffset(17,15)})
 local statusTitle=make('TextLabel',console,{Name='Title',Text='',BackgroundTransparency=1,BorderSizePixel=0,FontFace=Theme.font('sans',Enum.FontWeight.SemiBold),TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,Position=UDim2.fromOffset(38,0),Size=UDim2.new(1,-54,0,40)})
 local log=make('ScrollingFrame',console,{Name='Diagnostics',Position=UDim2.fromOffset(0,40),Size=UDim2.new(1,0,1,-40),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=6,ScrollingDirection=Enum.ScrollingDirection.Y,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new()},{ScrollBarImageColor3='scroll'})
 kit.pad(log,0,16,16,38)
 kit.list(log,Enum.FillDirection.Vertical,10,nil,Enum.VerticalAlignment.Top)
 local chipRow=make('Frame',log,{Name='Stats',BackgroundTransparency=1,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,LayoutOrder=1,Visible=false})
 local chipLayout=kit.list(chipRow,Enum.FillDirection.Horizontal,6)
 chipLayout.Wraps=true
 local chips={}
 for index=1,4 do chips[index]=kit.chip(chipRow,index)end
 local status=make('TextLabel',log,{Name='Message',Text='',RichText=true,BackgroundTransparency=1,BorderSizePixel=0,FontFace=Theme.font('sans'),TextSize=14,LineHeight=1.4,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,LayoutOrder=2})
 local STATES={idle={dot='faint',title='ink'},busy={dot='accent',title='ink'},success={dot='success',title='ink'},warning={dot='accent',title='ink'},error={dot='danger',title='danger'}}
 local current={state='idle',body='',details=nil}
 local function paintStatus()
  local c=theme.colors
  local spec=STATES[current.state]
  statusDot.set(spec.dot,current.state=='busy')
  statusTitle.TextColor3=c[spec.title]
  local text=Syntax.escape(current.body)
  if current.details and current.details~='' then
   text=text..'\n\n<font color="#'..c.faint:ToHex()..'">'..Syntax.escape(current.details)..'</font>'
  end
  status.Text=text
  status.TextColor3=current.state=='error' and c.ink or c.muted
 end
 local function report(state,title,bodyText,stats,details)
  current.state=STATES[state] and state or 'idle'
  current.body=string.sub(tostring(bodyText or ''),1,8000)
  current.details=details and string.sub(tostring(details),1,6000) or nil
  statusTitle.Text=title
  for index,chip in ipairs(chips)do chip.set(stats and stats[index] or nil)end
  chipRow.Visible=stats~=nil and #stats>0
  paintStatus()
  log.CanvasPosition=Vector2.zero
 end
 theme:changed(paintStatus)
 local pendingStats
 local function message(text,isError)
  pendingStats=nil
  if isError then
   local first,rest=readableError(text)
   report('error','Algo deu errado',first,nil,rest)
  else
   report('idle','Pronto',text)
  end
 end
 local function showStats()
  local s=pendingStats
  if not s then return end
  local warnings=describeDiagnostics(s.diagnostics)
  local lines={'StarterGui.'..s.name..' está pronta. Salve o place (Ctrl+S) e use F5 para testar o runtime. Regenerar preserva UserCode.'}
  if s.svgPrimitives>1500 then lines[#lines+1]='Atenção: muitos detalhes SVG. Reduza data-resolution e meça no cliente.'end
  if warnings then lines[#lines+1]='Avisos da compilação (revise o código):\n'..warnings end
  report(warnings and 'warning' or 'success',warnings and 'UI gerada com avisos' or 'UI gerada',table.concat(lines,'\n\n'),{plural(s.elements,'elemento','elementos'),plural(s.icons,'SVG','SVGs'),plural(s.svgPrimitives,'faixa SVG','faixas SVG'),plural(s.instances,'instância','instâncias')})
 end
 report('idle','Pronto','O exemplo já está no editor. Clique em Gerar UI para criar a ScreenGui em StarterGui e salve o place (Ctrl+S) para mantê-la.')
 function tab(name)
  selected=name
  for key,view in pairs(views)do view.frame.Visible=key==name end
  tabs.select(name)
 end
 tab('html')
 local clean={markup=Example.markup,style=Example.css,name='CssDemo'}
 function refreshDirty()
  dirty=html.Text~=clean.markup or css.Text~=clean.style or project.Text~=clean.name
  save.setPending(dirty)
 end
 local function markClean()
  clean.markup=html.Text;clean.style=css.Text;clean.name=project.Text
  refreshDirty()
 end
 local function validateName()
  local name=project.Text
  field.setInvalid(name~='' and not(string.match(name,'^[%a_][%w_%-]*$') and #name<=48))
 end
 local confirmTargets={Carregar=load,Exemplo=example}
 function setConfirmation(kind)
  confirmation=kind
  for key,button in pairs(confirmTargets)do
   button.setTone(key==kind and 'confirm' or nil)
   button.setText(key==kind and 'Confirmar' or key)
  end
 end
 local settingKey='CssStudioDraft_v1_'..game.PlaceId
 local draftStore=SessionStore.new(plugin,settingKey);local draftTicket=0;local draftPending=false
 local function persistDraft(force,ticket)
  if #html.Text>120000 or #css.Text>120000 then return end
  local snapshot={name=project.Text,markup=html.Text,css=css.Text}
  local budget=Performance.budget({chunkSize=2,frameBudget=0.004,yield=force~=true})
  local stored,err=pcall(function()
   draftStore:save(snapshot,{
    checkpoint=function()budget:step()end,
    cancelled=function()return not alive or ticket~=draftTicket end,
   })
  end)
  if not stored and alive and ticket==draftTicket then report('error','Rascunho não salvo','Não foi possível salvar o rascunho local: '..tostring(err))end
 end
 function saveDraft(force)
  if not alive then return end
  if force==true then draftTicket+=1;draftPending=false;persistDraft(true,draftTicket);return end
  if draftPending then return end;draftPending=true;draftTicket+=1;local ticket=draftTicket
  task.defer(function()if not alive or ticket~=draftTicket then return end;draftPending=false;persistDraft(false,ticket)end)
 end
 local restoredOk,draft=pcall(function()return draftStore:load()end)
 if restoredOk and type(draft)=='table' and type(draft.markup)=='string' and type(draft.css)=='string' then
  html.Text=draft.markup;css.Text=draft.css;project.Text=draft.name or 'CssDemo'
  report('idle','Rascunho recuperado','Suas últimas edições voltaram ao editor. Gerar UI aplica ao place; Ctrl+S salva o arquivo.')
 end
 draft=nil
 refreshDirty();validateName()
 local actionButtons={generate,save,load,example,importButton}
 local function setBusy(value)
  busy=value
  for _,button in ipairs(actionButtons)do button.setEnabled(not value)end
  mark.setBusy(value)
  if not value then generate.setText('Gerar UI')end
 end
 local function run(action)
  if busy or not alive then return end;setBusy(true)
  task.defer(function()
   if not alive then busy=false;return end
   local done,err=xpcall(action,debug.traceback)
   if not alive then busy=false;return end
   setBusy(false)
   if not done then message(err,true)end
  end)
 end
 local function confirm(kind)
  if not dirty then return true end
  if confirmation==kind then setConfirmation(nil);return true end
  setConfirmation(kind)
  report('warning','Edição não salva',(kind=='Carregar' and 'Carregar substitui o código do editor pelo projeto salvo.' or 'O exemplo substitui o código do editor.')..' Clique em Confirmar para continuar ou em Salvar para guardar sua edição antes.')
  return false
 end
 connect(generate.Activated,function()run(function()
  local camera=workspace.CurrentCamera;local size=camera and camera.ViewportSize or Vector2.new(1280,720)
  local markup,style,name=html.Text,css.Text,project.Text
  generate.setText('Gerando…')
  pendingStats=nil
  report('busy','Compilando','Validando HTML, CSS e SVG. A UI anterior é mantida em caso de erro.')
  local result=Compiler.generate(markup,style,name,{width=size.X,height=size.Y,recover=true,preload=true,requireAssets=true,yield=yieldCompile,cancelled=function()return not alive or html.Text~=markup or css.Text~=style or project.Text~=name end})
  if currentController then currentController:destroy()end
  currentController=Runtime.attach(result.gui)
  game:GetService('Selection'):Set({result.gui});markClean();saveDraft()
  local stats=result.stats
  pendingStats={name=name,elements=stats.elements,icons=stats.icons,svgPrimitives=stats.svgPrimitives,instances=stats.instances,diagnostics=stats.diagnostics}
  markup=nil;style=nil;result=nil;stats=nil;draft=nil;draftStore:clearBuffers()
  showStats()
 end)end)
 connect(save.Activated,function()run(function()
  assert(not game:GetService('RunService'):IsRunning(),'Pare o Play antes de salvar um projeto.')
  local history=game:GetService('ChangeHistoryService');local recording=history:TryBeginRecording('CssPlugin.Save','Salvar fonte CSS')
  assert(recording,'Outra operação mantém o histórico ocupado.')
  local stored,err=pcall(Compiler.save,project.Text,html.Text,css.Text)
  history:FinishRecording(recording,stored and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel)
  if not stored then error(err,0)end
  markClean();saveDraft()
  report('success','Fontes salvas','ServerStorage.CssDocuments.'..project.Text..' foi atualizado. A saída anterior não mudou: use Gerar UI para aplicar. Ctrl+S salva o place.')
 end)end)
 connect(load.Activated,function()run(function()
  if not confirm('Carregar')then return end
  local name=project.Text
  local markup,style=Compiler.load(name)
  if not markup then
   local saved=savedProjects()
   report('warning','Projeto não encontrado',#saved>0 and ('Não há "'..name..'" em ServerStorage.CssDocuments. Projetos salvos: '..table.concat(saved,', ')..'.') or 'Ainda não há projetos salvos em ServerStorage.CssDocuments. Use Salvar para guardar o projeto atual.')
   return
  end
  if currentController then currentController:destroy();currentController=nil end
  draftStore:clearBuffers();html.Text=markup;css.Text=style;markup=nil;style=nil;draft=nil
  markClean();saveDraft()
  report('success','Projeto carregado','"'..name..'" está no editor. Edite e clique em Gerar UI.')
 end)end)
 connect(example.Activated,function()run(function()
  if not confirm('Exemplo')then return end
  if currentController then currentController:destroy();currentController=nil end;draftStore:clearBuffers();draft=nil
  project.Text='CssDemo';html.Text=Example.markup;css.Text=Example.css;markClean();tab('html');saveDraft()
  report('idle','Exemplo carregado','Gerar UI cria a demonstração com lógica de clique em UserCode.')
 end)end)
 connect(importButton.Activated,function()run(function()
  local target=selected=='css' and 'css' or 'html'
  local file=game:GetService('StudioService'):PromptImportFileAsync(target=='css' and {'css','txt'} or {'html','xml','txt'})
  if not file then return end
  assert(file.Size<=120000,'Arquivo excede 120 KB.');local text=file:GetBinaryContents()
  if target=='css' then css.Text=text else html.Text=text;tab('html')end
  report('idle','Arquivo importado',tostring(file.Name)..' foi lido como código de autoria, não como asset temporário. Revise e gere a UI.')
  saveDraft()
 end)end)
 connect(html.FocusLost,function()saveDraft()end);connect(css.FocusLost,function()saveDraft()end);connect(project.FocusLost,function()saveDraft()end)
 connect(project:GetPropertyChangedSignal('Text'),function()
  refreshDirty();validateName()
  if confirmation then setConfirmation(nil)end
 end)
 task.spawn(function()
  local measured,bounds=pcall(function()
   local params=Instance.new('GetTextBoundsParams')
   params.Text=string.rep('0',64);params.Font=Theme.font('mono');params.Size=CODE_SIZE;params.Width=100000
   return TextService:GetTextBoundsAsync(params)
  end)
  if measured and alive and bounds.X>0 then
   charWidth=bounds.X/64
   for _,view in pairs(views)do view.refresh()end
  end
 end)
 connect(toggle.Click,function()widget.Enabled=not widget.Enabled end)
 connect(widget:GetPropertyChangedSignal('Enabled'),function()toggle:SetActive(widget.Enabled)end)
 widget:BindToClose(function()widget.Enabled=false;saveDraft(true)end)
 local function cleanup()
  if not alive then return end;saveDraft(true);alive=false
  for _,scheduler in ipairs(schedulers)do scheduler:destroy()end;table.clear(schedulers)
  if currentController then currentController:destroy();currentController=nil end
  draft=nil;pendingStats=nil;confirmation=nil;draftStore:destroy()
  mark.setBusy(false);statusDot.destroy()
  for _,c in ipairs(connections)do c:Disconnect()end;clear(connections)
  html.Text='';css.Text='';clear(views)
  theme:destroy()
  widget:Destroy();toolbar:Destroy()
 end
 connect(plugin.Unloading,cleanup)
 return {widget=widget,root=root,html=html,css=css,project=project,destroy=cleanup,message=message,report=report,draftStore=draftStore,schedulers=schedulers,theme=theme}
end
return E
