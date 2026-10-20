local Compiler=require(script.Parent.Compiler)
local Runtime=require(script.Parent.Runtime)
local Corpus=require(script.Parent.ConformanceCorpus)
local Goldens=require(script.Parent.ConformanceGoldens)
local Baseline=require(script.Parent.ChromiumBaseline)
local Coverage=require(script.Parent.CssCoverage)
local Supports=require(script.Parent.FeatureSupports)
local H={VERSION=1,GRID=16}
function H.wrap(markup)
 assert(type(markup)=='string'and #markup>0,'Caso sem markup.')
 if markup:match('^%s*<ui')then return markup end
 return '<ui>'..markup..'</ui>'
end
function H.resolve(case)
 if type(case)=='string' then
  local found=Corpus.byId(case)
  assert(found,'Caso desconhecido: '..case)
  return found
 end
 assert(type(case)=='table'and case.id,'Caso invalido.')
 return case
end
function H.ids(case)
 local expect=case.expect or {}
 local seen,out={},{}
 for _,section in ipairs({expect.geometry or {},expect.computed or {}})do
  for id in pairs(section)do
   if not seen[id]then seen[id]=true;out[#out+1]=id end
  end
 end
 table.sort(out)
 return out
end
function H.measure(case,options)
 case=H.resolve(case)
 options=options or {}
 local width=options.width or case.width or 800
 local height=options.height or case.height or 600
 local built=Compiler.build(H.wrap(case.markup),case.css,'Conformance_'..case.id,{width=width,height=height})
 local controller,actual
 local ok,err=xpcall(function()
  controller=Runtime.attach(built.gui,{manual=true,width=width,height=height})
  controller:refresh(width,height)
  actual={id=case.id,module=case.module,width=width,height=height,geometry={},computed={}}
  local expect=case.expect or {}
  for _,id in ipairs(H.ids(case))do
   local key=controller.ids[id]
   local box=key and controller.boxes[key]
   if box then actual.geometry[id]={x=box.x,y=box.y,w=box.w,h=box.h}end
   local wanted=expect.computed and expect.computed[id]
   local style=key and controller.styles[key]
   if wanted and style then
    local values={}
    for property in pairs(wanted)do values[property]=style[property]end
    actual.computed[id]=values
   end
  end
  if options.pixels~=false then
   local order={}
   for _,node in ipairs(controller.sequence or {})do order[#order+1]=node.key end
   local painted=Baseline.paint({width=width,height=height,boxes=controller.boxes,styles=controller.styles,order=order},{grid=options.grid or H.GRID,background=options.background})
   actual.grid=painted
   actual.pixels=painted.pixels
  end
  actual.stats=controller.renderStats
  actual.nodes=#(controller.sequence or {})
 end,debug.traceback)
 if controller then pcall(function()controller:destroy()end)end
 built.gui:Destroy()
 if not ok then error(err,0)end
 return actual
end
function H.case(case,options)
 case=H.resolve(case)
 options=options or {}
 local started=os.clock()
 local ok,actual=pcall(H.measure,case,options)
 if not ok then
  Coverage.case(case,false)
  return {id=case.id,module=case.module,title=case.title,ok=false,error=tostring(actual),sections={},failures={{kind='motor',field='erro',expected='render',actual=tostring(actual)}},checked=0,duration=os.clock()-started,properties=case.properties}
 end
 local golden,origin
 if options.stored~=false then golden=Goldens.load(case.id)end
 if golden then origin='golden' else golden=Goldens.fromCase(case);origin='spec' end
 local valid,hash=Goldens.verify(golden)
 local comparison=Goldens.compare(golden,actual,options)
 local baseline=Baseline.compare(case,actual,options)
 local passed=comparison.ok and valid and baseline.ok~=false
 Coverage.case(case,passed)
 local failures={}
 for _,failure in ipairs(comparison.failures)do failures[#failures+1]=failure end
 for _,failure in ipairs(baseline.failures or {})do failure.source='chromium';failures[#failures+1]=failure end
 return {id=case.id,module=case.module,title=case.title,ok=passed,origin=origin,goldenHash=golden.hash,goldenValid=valid,hash=hash,sections=comparison.sections,failures=failures,checked=comparison.checked+(baseline.checked or 0),baseline=baseline,actual=actual,duration=os.clock()-started,properties=case.properties}
end
function H.select(options)
 options=options or {}
 if options.ids then
  local out={}
  for _,id in ipairs(options.ids)do out[#out+1]=H.resolve(id)end
  return out
 end
 if options.module then return Corpus.byModule(options.module)end
 return Corpus.cases
end
function H.run(options)
 options=options or {}
 if options.coverage~=false then Coverage.attach(Supports)end
 local started=os.clock()
 local results,passed,failed,errors,baselines={},0,0,0,0
 for _,case in ipairs(H.select(options))do
  local result=H.case(case,options)
  results[#results+1]=result
  if result.ok then passed+=1 else failed+=1 end
  if result.error then errors+=1 end
  if result.baseline and result.baseline.missing==false then baselines+=1 end
 end
 local modules={}
 for _,result in ipairs(results)do
  local entry=modules[result.module]or{total=0,passed=0}
  entry.total+=1
  if result.ok then entry.passed+=1 end
  modules[result.module]=entry
 end
 return {version=H.VERSION,total=#results,passed=passed,failed=failed,errors=errors,baselines=baselines,results=results,modules=modules,ratio=#results>0 and passed/#results or 0,duration=os.clock()-started,coverage=Coverage.summary()}
end
function H.record(options)
 options=options or {}
 local stored={}
 for _,case in ipairs(H.select(options))do
  local actual=H.measure(case,options)
  local golden=Goldens.record(case,actual,{source=options.source or 'engine'})
  if options.store~=false then Goldens.store(golden)end
  stored[#stored+1]=golden
 end
 return stored
end
function H.baseline(payload)
 return Baseline.store(Baseline.capture(payload))
end
function H.report(run,limit)
 run=run or H.run()
 local lines={string.format('Conformidade | %d/%d casos (%.1f%%) | %d erro(s) de motor | %d captura(s) headless | %.0f ms',run.passed,run.total,run.ratio*100,run.errors,run.baselines,run.duration*1000)}
 local names={}
 for name in pairs(run.modules)do names[#names+1]=name end
 table.sort(names)
 for _,name in ipairs(names)do
  local entry=run.modules[name]
  lines[#lines+1]=string.format('  %-18s %d/%d',name,entry.passed,entry.total)
 end
 local shown=0
 for _,result in ipairs(run.results)do
  if not result.ok then
   shown+=1
   if limit and shown>limit then break end
   lines[#lines+1]=string.format('  %s (%s): %s',result.id,tostring(result.module),result.error or string.format('%d divergencia(s)',#result.failures))
   for index,failure in ipairs(result.failures)do
    if index>3 then break end
    lines[#lines+1]=string.format('    %s %s.%s esperado %s obtido %s',tostring(failure.kind),tostring(failure.id or '-'),tostring(failure.field),tostring(failure.expected),tostring(failure.actual))
   end
  end
 end
 return table.concat(lines,'\n')
end
function H.coverage(limit)
 return Coverage.report(limit)
end
function H.guide()
 return Coverage.guide()
end
return H
