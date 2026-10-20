local ContentProvider=game:GetService('ContentProvider')
local TextService=game:GetService('TextService')
local A={};local ready={};local readyCount=0
local function remember(key)
 if ready[key]then return end
 if readyCount>=512 then table.clear(ready);readyCount=0 end
 ready[key]=true;readyCount+=1
end
local function preloadFont(font)
 local params=Instance.new('GetTextBoundsParams')
 local ok,err=pcall(function()
  params.Font=font;params.Text='M';params.Size=16;params.Width=1000
  return TextService:GetTextBoundsAsync(params)
 end)
 params:Destroy();return ok,err
end
function A.preload(objects,options,checkpoint)
 options=options or {};local assets,seen={},{}
 local function add(id,font)
  if type(id)~='string'or id==''then return end
  local key=font and('font:'..#id..':'..id..':'..font.Weight.Value..':'..font.Style.Value)or('image:'..id)
  if not seen[key]and(not ready[key]or options.preloader)then
   seen[key]=true;assets[#assets+1]={id=id,key=key,font=font}
  end
 end
 for _,object in pairs(objects)do
  if object:IsA('ImageLabel')or object:IsA('ImageButton')then add(object.Image)end
  local paint=object:FindFirstChild('__Paint')
  if paint then for _,image in ipairs(paint:GetDescendants())do if image:IsA('ImageLabel')and image:GetAttribute('CssBackgroundAsset')then add(image.Image)end end end
  if object:IsA('TextLabel')or object:IsA('TextButton')or object:IsA('TextBox')then
   local font=object.FontFace;add(font.Family,font)
  end
  if checkpoint then checkpoint()end
 end
 table.sort(assets,function(a,b)return a.key<b.key end)
 local result={requested=#assets,loaded=0,failed=0,warnings={}}
 if options.preload==false then result.skipped=true;return result end
 local size=math.clamp(options.assetBatchSize or 16,1,64)
 for start=1,#assets,size do
  if checkpoint then checkpoint()end
  local batch={};for i=start,math.min(#assets,start+size-1)do batch[#batch+1]=assets[i]end
  local statuses,reasons={},{}
  if options.preloader then
   local ids,fetched={},{};for _,asset in ipairs(batch)do ids[#ids+1]=asset.id end
   local ok,err=pcall(options.preloader,ids,function(id,status)
    if fetched[id]~=false then fetched[id]=status==Enum.AssetFetchStatus.Success end
   end)
   for _,asset in ipairs(batch)do
    statuses[asset.key]=ok and fetched[asset.id]==true
    if not ok then reasons[asset.key]=tostring(err)end
   end
  else
   local imageIds,imageAssets={},{}
   for _,asset in ipairs(batch)do
    if asset.font then
     if checkpoint then checkpoint()end
     local ok,err=preloadFont(asset.font);statuses[asset.key]=ok
     if not ok then reasons[asset.key]=tostring(err)end
    else
     imageIds[#imageIds+1]=asset.id;imageAssets[#imageAssets+1]=asset
    end
   end
   if #imageIds>0 then
    local fetched={}
    local ok,err=pcall(function()
     ContentProvider:PreloadAsync(imageIds,function(id,status)
      if fetched[id]~=false then fetched[id]=status==Enum.AssetFetchStatus.Success end
     end)
    end)
    for _,asset in ipairs(imageAssets)do
     if ok and fetched[asset.id]==nil then
      local checked,status=pcall(ContentProvider.GetAssetFetchStatus,ContentProvider,asset.id)
      fetched[asset.id]=checked and status==Enum.AssetFetchStatus.Success
     end
     statuses[asset.key]=ok and fetched[asset.id]==true
     if not ok then reasons[asset.key]=tostring(err)end
    end
   end
  end
  for _,asset in ipairs(batch)do
   if statuses[asset.key]then
    result.loaded+=1;if not options.preloader then remember(asset.key)end
   else
    result.failed+=1
    local reason=reasons[asset.key]
    result.warnings[#result.warnings+1]='Asset não carregado: '..asset.id..(reason and(' ('..reason..')')or '')
   end
  end
  if checkpoint then checkpoint()end
 end
 if options.requireAssets and result.failed>0 then error(table.concat(result.warnings,'\n'),0)end
 return result
end
function A.clearCache()table.clear(ready);readyCount=0 end
return A
