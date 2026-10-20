local Cost=require(script.Parent.CostModel)
local B={VERSION=1}
B.BYTES_PER_PIXEL=16
B.PRESENT_BYTES_PER_PIXEL=4
B.FALLBACK_BYTES=224
B.BASE_BYTES=12*1024*1024
B.MIN_BYTES=512*1024
B.MIN_TILE=8
B.MAX_TILE=256
B.legacyCaps={effectSide=64,surfaceSide=128,bands=8000}
local capability=nil
local function probe(side)
 local image=nil
 local ok=pcall(function()
  image=game:GetService('AssetService'):CreateEditableImage({Size=Vector2.new(side,side)})
 end)
 local made=ok and image~=nil
 if image then pcall(function() image:Destroy() end) end
 return made
end
function B.capability(refresh)
 if capability and not refresh then return capability end
 local best=0
 for _,side in ipairs({1024,512,256,128,64}) do
  if probe(side) then best=side;break end
 end
 capability={editable=best>0,maxSide=best,bytesPerPixel=B.PRESENT_BYTES_PER_PIXEL}
 return capability
end
function B.forget() capability=nil;return B end
function B.assume(maxSide)
 local side=math.max(0,math.floor(tonumber(maxSide) or 0))
 capability={editable=side>0,maxSide=side,bytesPerPixel=B.PRESENT_BYTES_PER_PIXEL,assumed=true}
 return capability
end
function B.new(options)
 options=options or {}
 local profile=Cost.classify(options)
 local base=math.max(B.MIN_BYTES,math.floor(tonumber(options.bytes) or B.BASE_BYTES))
 local fraction=math.clamp(tonumber(options.fraction) or 1,0.05,1)
 local limit=math.max(B.MIN_BYTES,math.floor(base*(profile.scale or 1)*fraction))
 local self={limit=limit,used=0,peak=0,profile=profile.label,rejects=0,counts={surfaces=0,tiles=0,scratch=0,present=0,fallback=0,refunds=0}}
 function self:fits(bytes) return self.used+math.max(0,math.floor(tonumber(bytes) or 0))<=self.limit end
 function self:headroom() return math.max(0,self.limit-self.used) end
 function self:pixels(bytesPerPixel) return math.floor(self:headroom()/math.max(1,bytesPerPixel or B.BYTES_PER_PIXEL)) end
 function self:side(bytesPerPixel) return math.floor(math.sqrt(self:pixels(bytesPerPixel))) end
 function self:spend(bytes,label,kind)
  bytes=math.max(0,math.floor(tonumber(bytes) or 0))
  if self.used+bytes>self.limit then
   self.rejects+=1
   error(string.format('%s: orcamento de bytes do render core excedido (%d usados + %d pedidos > %d, perfil %s).',tostring(label or 'RenderCore'),self.used,bytes,self.limit,self.profile),0)
  end
  self.used+=bytes
  if self.used>self.peak then self.peak=self.used end
  if kind then self.counts[kind]=(self.counts[kind] or 0)+1 end
  return bytes
 end
 function self:refund(bytes)
  self.used=math.max(0,self.used-math.max(0,math.floor(tonumber(bytes) or 0)))
  self.counts.refunds+=1
  return self.used
 end
 function self:reset()
  self.used=0
  self.rejects=0
  for key in pairs(self.counts) do self.counts[key]=0 end
  return self
 end
 function self:report()
  return {limit=self.limit,used=self.used,peak=self.peak,profile=self.profile,rejects=self.rejects,headroom=self:headroom(),counts=table.clone(self.counts)}
 end
 return self
end
function B.plan(width,height,options)
 options=options or {}
 local budget=options.budget or B.new(options)
 local cap=options.capability or B.capability()
 local w=math.max(1,math.floor(tonumber(width) or 1))
 local h=math.max(1,math.floor(tonumber(height) or 1))
 local tile=math.clamp(math.floor(tonumber(options.tile) or 64),B.MIN_TILE,B.MAX_TILE)
 if cap.maxSide>0 and cap.maxSide<tile then tile=cap.maxSide end
 local span=tile
 if cap.maxSide>0 then span=math.max(tile,math.floor(cap.maxSide/tile)*tile) end
 local cols=math.ceil(w/tile)
 local rows=math.ceil(h/tile)
 local tileBytes=tile*tile*B.BYTES_PER_PIXEL
 local worst=cols*rows*tileBytes
 return {budget=budget,capability=cap,tile=tile,span=span,cols=cols,rows=rows,width=w,height=h,tileBytes=tileBytes,worstBytes=worst,fits=budget:fits(worst),affordableTiles=math.floor(budget:pixels(B.BYTES_PER_PIXEL)/(tile*tile)),backend=cap.editable and 'EditableImageTiles' or 'NativeGradientBands'}
end
function B.legacy(options)
 options=options or {}
 local plan=B.plan(options.width or 1280,options.height or 720,options)
 local side=plan.budget:side(B.BYTES_PER_PIXEL)
 local bands=math.floor(plan.budget:headroom()/B.FALLBACK_BYTES)
 return {
  effectSide={legacy=B.legacyCaps.effectSide,derived=side,better=side>B.legacyCaps.effectSide},
  surfaceSide={legacy=B.legacyCaps.surfaceSide,derived=side,better=side>B.legacyCaps.surfaceSide},
  bands={legacy=B.legacyCaps.bands,derived=bands,better=bands>B.legacyCaps.bands},
  plan=plan,
 }
end
function B.describe(plan)
 return string.format('perfil %s | bytes %d de %d | tile %dpx | apresentacao %s',plan.budget.profile,plan.budget.used,plan.budget.limit,plan.tile,plan.backend)
end
return B
