local gui=script:FindFirstAncestorWhichIsA('ScreenGui')
local runtime=require(gui:WaitForChild('_CssRuntime'):WaitForChild('Runtime')).attach(gui)
local launch,toggle,status,input=runtime:get('launch'),runtime:get('toggle'),runtime:get('status'),runtime:get('playerName')
if not (launch and toggle and status and input) then return end
local count=0
launch.Activated:Connect(function()
 count+=1
 local name=input.Text:gsub('^%s+',''):gsub('%s+$','')
 status.Text=(name~='' and ('Olá, '..name..'! ') or '')..'Cliques nesta sessão: '..count..'. A UI está rodando sem o plugin.'
end)
toggle.Activated:Connect(function()
 local disabled=not (launch:GetAttribute('CssDisabled')==true)
 runtime:setDisabled('launch',disabled)
 toggle.Text=disabled and 'Habilitar' or 'Desabilitar'
 status.Text=disabled and 'Botão desabilitado de verdade, não apenas recolorido.' or 'Pronto para receber cliques novamente.'
end)
