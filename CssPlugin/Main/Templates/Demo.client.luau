local gui=script:FindFirstAncestorWhichIsA('ScreenGui')
local runtime=require(gui:WaitForChild('_CssRuntime'):WaitForChild('Runtime')).attach(gui)
local add,remove,pause=runtime:get('wrapAdd'),runtime:get('wrapRemove'),runtime:get('motionPause')
if not(add and remove and pause)then return end
local stats,status=runtime:get('wrapStats'),runtime:get('motionStatus')
local items={};local serial=0;local paused=false
local labels={'Poção de energia','Espada rara','Item lendário','Novo desafio','Cristais','Missão diária'}
local function updateStats()
 local listKey=runtime.ids.tagList;local box=runtime.boxes and runtime.boxes[listKey]
 local node=runtime.nodes[listKey]
 if box and node then
  local text=string.format('%d itens · %d linhas · largura útil: %d px',#node.children,box.lineCount or 0,math.floor(box.w-box.p[2]-box.p[4]))
  if stats.Text~=text then stats.Text=text end
 end
end
runtime.LayoutChanged:Connect(updateStats)
add.Activated:Connect(function()
 if #items>=24 then status.Text='Limite de 24 itens extras nesta demonstração. Remova alguns para continuar.';return end
 serial+=1;local id='extraChip'..serial
 local item=runtime:cloneItem('chipTemplate',id,'tagList')
 item.Text=labels[(serial-1)%#labels+1]..' '..serial
 table.insert(items,id);runtime:setDisabled('wrapRemove',false);runtime:setDisabled('wrapAdd',#items>=24)
 status.Text='Item criado em tempo de jogo. As linhas e a altura da lista são recalculadas.'
end)
remove.Activated:Connect(function()
 local id=table.remove(items);if not id then return end
 runtime:removeItem(id);runtime:setDisabled('wrapRemove',#items==0);runtime:setDisabled('wrapAdd',false)
 status.Text='Item removido. O espaço da linha é redistribuído sem deixar buracos.'
end)
pause.Activated:Connect(function()
 paused=not paused;runtime:setClass('pulseBadge',paused and 'pulse paused'or 'pulse')
 pause.Text=paused and 'Retomar animação'or 'Pausar animação'
 status.Text=paused and 'Keyframes pausados na posição atual. O hover dos botões continua funcionando.'or 'Keyframes retomados sem reiniciar a animação.'
end)
updateStats()
