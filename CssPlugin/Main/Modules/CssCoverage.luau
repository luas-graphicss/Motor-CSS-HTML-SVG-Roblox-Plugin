local Coverage={VERSION=1,enabled=true}
local properties={}
local cases={}
local hooked=false
local function entry(name)
 name=tostring(name):lower()
 local record=properties[name]
 if not record then
  record={property=name,declared=false,supported=nil,queries=0,cases=0,passed=0,failed=0,modules={}}
  properties[name]=record
 end
 return record
end
Coverage.entry=entry
function Coverage.reset()
 table.clear(properties);table.clear(cases);hooked=false
end
function Coverage.declare(name,info)
 local record=entry(name)
 record.declared=true
 record.source=(info and info.source)or record.source or 'engine'
 if info and info.supported~=nil then record.supported=info.supported==true end
 return record
end
function Coverage.declareMany(list,info)
 if type(list)~='table'then return 0 end
 local count=0
 for key,value in pairs(list)do
  local name=type(key)=='string'and key or value
  if type(name)=='string'then Coverage.declare(name,info);count+=1 end
 end
 return count
end
function Coverage.query(name,value,supported)
 if not Coverage.enabled then return nil end
 local record=entry(name)
 record.queries+=1
 if supported~=nil then
  if supported==true then record.supported=true elseif record.supported==nil then record.supported=false end
 end
 if value~=nil and record.sample==nil then record.sample=tostring(value)end
 return record
end
function Coverage.case(case,ok)
 if not Coverage.enabled then return nil end
 local id=type(case)=='table'and tostring(case.id)or tostring(case)
 local moduleName=type(case)=='table'and case.module or nil
 local list=(type(case)=='table'and case.properties)or {}
 cases[id]={id=id,module=moduleName,ok=ok==true,properties=list}
 for _,name in ipairs(list)do
  local record=entry(name)
  record.cases+=1
  if ok then record.passed+=1 else record.failed+=1 end
  if moduleName then record.modules[moduleName]=(record.modules[moduleName]or 0)+1 end
 end
 return cases[id]
end
function Coverage.get(name)
 return properties[tostring(name):lower()]
end
function Coverage.all()
 local out={}
 for _,record in pairs(properties)do out[#out+1]=record end
 table.sort(out,function(a,b)return a.property<b.property end)
 return out
end
function Coverage.summary()
 local total,declared,tested,passing,queried=0,0,0,0,0
 for _,record in pairs(properties)do
  total+=1
  if record.declared then declared+=1 end
  if record.queries>0 then queried+=1 end
  if record.cases>0 then
   tested+=1
   if record.failed==0 then passing+=1 end
  end
 end
 local caseCount,casePassed=0,0
 for _,record in pairs(cases)do
  caseCount+=1
  if record.ok then casePassed+=1 end
 end
 return {properties=total,declared=declared,tested=tested,passing=passing,queried=queried,cases=caseCount,casesPassed=casePassed,testedRatio=total>0 and tested/total or 0,passRatio=tested>0 and passing/tested or 0,hooked=hooked}
end
function Coverage.untested(limit)
 local out={}
 for _,record in pairs(properties)do
  if record.cases==0 then out[#out+1]=record.property end
 end
 table.sort(out)
 if limit and #out>limit then
  local short={}
  for index=1,limit do short[index]=out[index]end
  return short,#out
 end
 return out,#out
end
function Coverage.failing()
 local out={}
 for _,record in pairs(properties)do
  if record.failed>0 then out[#out+1]={property=record.property,failed=record.failed,cases=record.cases}end
 end
 table.sort(out,function(a,b)return a.property<b.property end)
 return out
end
function Coverage.supports(name)
 local record=properties[tostring(name):lower()]
 if not record then return nil end
 if record.supported==false then return false end
 if record.cases>0 and record.failed>0 then return false end
 if record.declared then return true end
 return record.supported==true
end
function Coverage.observer()
 return function(kind,name,value,result)
  if kind=='declaration'then Coverage.query(name,value,result)
  elseif kind=='register'then Coverage.declare(name,{source='engine'})
  elseif kind=='property'then Coverage.query(name,value,result)end
 end
end
function Coverage.attach(supports)
 local Supports=supports or require(script.Parent.FeatureSupports)
 if hooked then return false end
 if type(Supports.observe)~='function'then return false end
 Supports.observe(Coverage.observer())
 if type(Supports.gate)=='function'then
  Supports.gate(function(name)
   local record=properties[tostring(name):lower()]
   if record and record.cases>0 and record.failed>0 then return false end
   return true
  end)
 end
 hooked=true
 if type(Supports.registered)=='function'then Coverage.declareMany(Supports.registered(),{source='engine'})end
 return true
end
function Coverage.hooked()
 return hooked
end
function Coverage.export()
 return {version=Coverage.VERSION,summary=Coverage.summary(),properties=Coverage.all(),cases=cases}
end
function Coverage.report(limit)
 local summary=Coverage.summary()
 local lines={string.format('Cobertura CSS | %d propriedades | %d testadas (%.1f%%) | %d aprovadas (%.1f%%) | %d casos (%d ok)',summary.properties,summary.tested,summary.testedRatio*100,summary.passing,summary.passRatio*100,summary.cases,summary.casesPassed)}
 local failing=Coverage.failing()
 if #failing>0 then
  lines[#lines+1]='  divergentes:'
  for index,record in ipairs(failing)do
   if limit and index>limit then break end
   lines[#lines+1]=string.format('   %-24s %d/%d casos falharam',record.property,record.failed,record.cases)
  end
 end
 local untested,total=Coverage.untested(limit or 12)
 if total>0 then
  lines[#lines+1]=string.format('  sem caso (%d): %s',total,table.concat(untested,', '))
 end
 return table.concat(lines,'\n')
end
function Coverage.guide()
 local summary=Coverage.summary()
 local lines={'# Cobertura por propriedade',string.format('Propriedades observadas: %d | com caso de conformidade: %d | aprovadas: %d',summary.properties,summary.tested,summary.passing)}
 for _,record in ipairs(Coverage.all())do
  local status='sem caso'
  if record.cases>0 then status=record.failed==0 and 'conforme' or 'divergente' end
  if record.supported==false then status='nao suportada' end
  lines[#lines+1]=string.format('- %s: %s (%d caso(s), %d consulta(s))',record.property,status,record.cases,record.queries)
 end
 return table.concat(lines,'\n')
end
return Coverage
