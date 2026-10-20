local M={VERSION=1}
M.weights={nodes=1,instances=0.24,svgs=6,layers=1.5,shadows=2,selectors=0.4,bytes=1/256,bands=0.05,pixels=1/32768,animations=1.5,filters=0.5,glyphs=0.75,surfaces=4}
M.reference={nodes=300,instances=14000,svgs=24,layers=8,shadows=4,selectors=500,bytes=120000,bands=8000,animations=128}
M.shares={nodes=0.85,instances=0.85,svgs=0.55,layers=0.45,shadows=0.45,selectors=0.65,bytes=0.45,bands=0.65,pixels=0.65,animations=0.65,filters=0.45,glyphs=0.45,surfaces=0.35}
M.profiles={minimal={label='minimal',scale=0.6,depth=40},baseline={label='baseline',scale=1,depth=40},desktop={label='desktop',scale=3,depth=64},studio={label='studio',scale=4,depth=96}}
local active='baseline'
local reservations=setmetatable({},{__mode='k'})
local reserved=0
local limitCache={}
local function profileOf(name)
 if type(name)=='table' then return name end
 local profile=M.profiles[name or active]
 assert(profile,'Perfil de custo desconhecido: '..tostring(name))
 return profile
end
function M.profile(name) return profileOf(name) end
function M.select(name)
 profileOf(name);active=(type(name)=='string' and name) or 'baseline';table.clear(limitCache);return M.profiles[active]
end
function M.classify(options)
 options=options or {}
 if options.profile then return profileOf(options.profile) end
 local pixels=(tonumber(options.width) or 0)*(tonumber(options.height) or 0)
 if pixels>0 and pixels<=480*854 then return M.profiles.minimal end
 if pixels>=1920*1080 then return M.profiles.desktop end
 return profileOf()
end
function M.referenceCost()
 local total=0
 for kind,count in pairs(M.reference) do total+=count*(M.weights[kind] or 0) end
 return total
end
function M.budget(name) return M.referenceCost()*profileOf(name).scale end
function M.limits(name)
 local profile=profileOf(name)
 local cached=limitCache[profile.label]
 if cached then return cached end
 local budget=M.budget(profile);local out={depth=profile.depth}
 for kind,weight in pairs(M.weights) do out[kind]=math.max(1,math.floor(budget*(M.shares[kind] or 0.5)/weight)) end
 limitCache[profile.label]=out
 return out
end
function M.invalidate() table.clear(limitCache) end
function M.cap(kind,count,label,profile)
 local limit=M.limits(profile)[kind]
 assert(limit,'Dimensao de custo desconhecida: '..tostring(kind))
 local value=tonumber(count) or 0
 if value>limit then
  error(string.format('%s: %s=%d acima do teto de custo %d (perfil %s).',tostring(label or 'Preflight'),tostring(kind),math.floor(value),limit,M.profile(profile).label),0)
 end
 return limit
end
function M.cost(request)
 local total=0;local parts={}
 for kind,count in pairs(request or {}) do
  local weight=M.weights[kind]
  if weight and type(count)=='number' and count>0 then
   local value=count*weight;total+=value;parts[#parts+1]={kind=kind,count=count,cost=value}
  end
 end
 table.sort(parts,function(a,b) if a.cost==b.cost then return a.kind<b.kind end return a.cost>b.cost end)
 return total,parts
end
function M.preflight(request,options)
 options=options or {}
 local profile=M.classify(options)
 local budget=M.budget(profile)*math.clamp(options.fraction or 1,0.05,1)
 local limits=M.limits(profile)
 local total,parts=M.cost(request)
 local reasons={}
 for _,part in ipairs(parts) do
  part.share=budget>0 and part.cost/budget or 0
  local cap=limits[part.kind]
  if cap and part.count>cap then reasons[#reasons+1]=part.kind..'='..math.floor(part.count)..' acima do teto derivado '..cap end
 end
 local depth=tonumber(request and request.depth) or 0
 if depth>limits.depth then reasons[#reasons+1]='depth='..math.floor(depth)..' acima de '..limits.depth end
 local available=math.max(0,budget-(options.ignoreReserved==true and 0 or reserved))
 if total>available then reasons[#reasons+1]=string.format('custo %.1f acima do disponivel %.1f',total,available) end
 return {ok=#reasons==0,cost=total,budget=budget,available=available,reserved=reserved,profile=profile.label,parts=parts,limits=limits,reasons=reasons,request=request}
end
function M.message(report)
 local dominant=report.parts[1]
 local text='Orcamento de custo excedido ('..report.profile..'): '..table.concat(report.reasons,'; ')
 if dominant then text=text..string.format('. Dimensao dominante: %s (%.0f de %.0f).',dominant.kind,dominant.cost,report.budget) end
 return text
end
function M.check(request,options)
 local report=M.preflight(request,options)
 assert(report.ok,M.message(report))
 return report
end
function M.fits(request,options) return M.preflight(request,options).ok end
function M.reserve(owner,request,options)
 assert(owner~=nil,'Reserva de custo exige dono.')
 assert(reservations[owner]==nil,'Dono ja possui reserva de custo.')
 local report=M.check(request,options)
 reservations[owner]=report.cost;reserved+=report.cost
 return {cost=report.cost,report=report,release=function() return M.release(owner) end}
end
function M.release(owner)
 local cost=reservations[owner]
 if not cost then return false end
 reservations[owner]=nil;reserved=math.max(0,reserved-cost);return true
end
function M.usage(name)
 local profile=profileOf(name);local owners=0
 for _ in pairs(reservations) do owners+=1 end
 return {reserved=reserved,budget=M.budget(profile),owners=owners,profile=profile.label,headroom=math.max(0,M.budget(profile)-reserved)}
end
function M.legacy(name)
 local limits=M.limits(name)
 local out={}
 for kind,value in pairs(M.reference) do out[kind]={legacy=value,derived=limits[kind],regression=limits[kind]<value} end
 out.depth={legacy=40,derived=limits.depth,regression=limits.depth<40}
 return out
end
function M.report(request,options)
 local report=M.preflight(request,options)
 local lines={string.format('Preflight %s | custo %.1f de %.1f | %s',report.profile,report.cost,report.budget,report.ok and 'aprovado' or 'recusado')}
 for _,part in ipairs(report.parts) do
  lines[#lines+1]=string.format('  %-11s %8.0f -> %8.1f (%.0f%% do orcamento, teto %s)',part.kind,part.count,part.cost,part.share*100,tostring(report.limits[part.kind]))
 end
 for _,reason in ipairs(report.reasons) do lines[#lines+1]='  recusa: '..reason end
 return table.concat(lines,'\n'),report
end
function M.reset() table.clear(reservations);table.clear(limitCache);reserved=0;active='baseline' end
return M
