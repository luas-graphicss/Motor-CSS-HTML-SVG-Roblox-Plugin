local gui=script:FindFirstAncestorWhichIsA('ScreenGui')
if not gui then return end
local ok,err=pcall(function() require(script.Parent.Runtime).attach(gui,{svgImages=gui:GetAttribute('CssSvgImages')==true}) end)
if not ok then
 gui:SetAttribute('CssRuntimeReady',false)
 if gui:GetAttribute('CssDevelopment')==true then warn('[CssPlugin] Falha ao iniciar a UI: '..tostring(err))end
end
gui=nil;err=nil
