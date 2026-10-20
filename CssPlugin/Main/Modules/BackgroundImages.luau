local B={};local sizes,slots={},{};local cursor,version=0,0
function B.version()return version end
function B.remember(source,w,h)
 if type(source)~='string'or source==''or type(w)~='number'or type(h)~='number'or w~=w or h~=h or w<=0 or h<=0 or w>32768 or h>32768 then return false end
 local old=sizes[source];if old and old.w==w and old.h==h then return false end
 if not old then cursor=cursor%256+1;local previous=slots[cursor];if previous then sizes[previous]=nil end;slots[cursor]=source end
 sizes[source]={w=w,h=h};version+=1;return true
end
function B.size(source)local s=sizes[source];return s and s.w,s and s.h end
function B.register(data)for source,size in pairs(data or {})do B.remember(source,size.w,size.h)end end
function B.probe(label)
 if not(label:IsA('ImageLabel')or label:IsA('ImageButton'))or label.Image==''then return false end
 local ok,size=pcall(function()return label.ContentImageSize end)
 if ok and size.X>0 and size.Y>0 then
  local changed=B.remember(label.Image,size.X,size.Y)
  label:SetAttribute('CssImageIntrinsicWidth',size.X);label:SetAttribute('CssImageIntrinsicHeight',size.Y);return changed
 end
 local w,h=label:GetAttribute('CssImageIntrinsicWidth'),label:GetAttribute('CssImageIntrinsicHeight')
 return w and h and B.remember(label.Image,w,h)or false
end
function B.collect(objects)
 local result={};local seen={}
 local function visit(o)
  if seen[o]then return end;seen[o]=true
  if o:IsA('ImageLabel')or o:IsA('ImageButton')then
   B.probe(o);local w,h=B.size(o.Image);if w then result[o.Image]={w=w,h=h}end
  end
 end
 for _,object in pairs(objects)do visit(object);local paint=object:FindFirstChild('__Paint');if paint then for _,o in ipairs(paint:GetDescendants())do visit(o)end end end
 return result
end
function B.count()local n=0;for _ in pairs(sizes)do n+=1 end;return n end
return B
