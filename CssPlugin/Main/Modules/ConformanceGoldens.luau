local Http=game:GetService('HttpService')
local Storage=game:GetService('ServerStorage')
local Manifest=require(script.Parent.ReleaseManifest)
local G={VERSION=1,FOLDER='CssConformanceGoldens',OWNER='CssPlugin'}
G.tolerance={geometry=0.5,computed=0,pixel=2,depth=255,coverage=0.02}
G.rationale={geometry='Chromium resolve layout em 1/64 px e o compositor do plugin arredonda para pixel inteiro; 0.5 px absorve o arredondamento sem esconder erro de formatacao.',computed='Valor computado e texto canonico; qualquer divergencia indica serializacao errada, por isso a comparacao e exata apos normalizacao de cor e espacos.',pixel='Canais de 8 bits com blend em ponto flutuante produzem ate 2/255 de diferenca por gamma e arredondamento.',coverage='Ate 2%% dos pixels podem divergir por antialiasing de borda antes de reprovar o caso.'}
function G.normalizeColor(text)
 local value=tostring(text):lower():gsub('%s+','')
 local hex=value:match('^#(%x%x%x%x%x%x)$')
 if hex then return string.format('rgb(%d, %d, %d)',tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16))end
 local short=value:match('^#(%x%x%x)$')
 if short then
  local r,g,b=short:sub(1,1),short:sub(2,2),short:sub(3,3)
  return string.format('rgb(%d, %d, %d)',tonumber(r..r,16),tonumber(g..g,16),tonumber(b..b,16))
 end
 local r,g,b,a=value:match('^rgba?%((%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),?([%d%.]*)%)$')
 if r then
  local red,green,blue=math.floor(tonumber(r)+0.5),math.floor(tonumber(g)+0.5),math.floor(tonumber(b)+0.5)
  if a==''or a=='1'then return string.format('rgb(%d, %d, %d)',red,green,blue)end
  return string.format('rgba(%d, %d, %d, %s)',red,green,blue,a)
 end
 return value
end
function G.normalize(property,value)
 if value==nil then return nil end
 local text=tostring(value)
 if property and (tostring(property):find('color')or property=='fill'or property=='stroke')then return G.normalizeColor(text)end
 text=text:gsub('^%s+',''):gsub('%s+$','')
 return (text:gsub('%s+',' '))
end
function G.near(a,b,tolerance)
 a=tonumber(a);b=tonumber(b)
 if not a or not b then return false end
 return math.abs(a-b)<=(tolerance or G.tolerance.geometry)
end
function G.geometry(expected,actual,options)
 local tolerance=(options and options.tolerance)or G.tolerance.geometry
 local failures,checked={},0
 for id,box in pairs(expected or {})do
  local found=actual and actual[id]
  if not found then failures[#failures+1]={id=id,field='presenca',expected='caixa',actual='ausente'}
  else
   for _,field in ipairs({'x','y','w','h'})do
    if box[field]~=nil then
     checked+=1
     if not G.near(box[field],found[field],tolerance)then failures[#failures+1]={id=id,field=field,expected=box[field],actual=found[field],delta=(tonumber(found[field])or 0)-box[field]}end
    end
   end
  end
 end
 return {ok=#failures==0,failures=failures,checked=checked,tolerance=tolerance,kind='geometry'}
end
function G.computed(expected,actual)
 local failures,checked={},0
 for id,properties in pairs(expected or {})do
  local found=(actual and actual[id])or {}
  for property,value in pairs(properties)do
   checked+=1
   local want=G.normalize(property,value)
   local got=G.normalize(property,found[property])
   if want~=got then failures[#failures+1]={id=id,field=property,expected=want,actual=got or 'ausente'}end
  end
 end
 return {ok=#failures==0,failures=failures,checked=checked,tolerance=0,kind='computed'}
end
function G.pixels(expected,actual,options)
 options=options or {}
 local tolerance=options.tolerance or G.tolerance.pixel
 local coverage=options.coverage or G.tolerance.coverage
 if type(expected)~='table'or type(actual)~='table'then
  return {ok=false,kind='pixel',failures={{field='formato',expected='tabela',actual=typeof(actual)}},checked=0,tolerance=tolerance,coverage=coverage,ratio=1,maxDelta=255}
 end
 local count=math.min(#expected,#actual)
 local diff,maxDelta,worst=0,0,nil
 for index=1,count do
  local delta=math.abs((tonumber(expected[index])or 0)-(tonumber(actual[index])or 0))
  if delta>maxDelta then maxDelta=delta;worst=index end
  if delta>tolerance then diff+=1 end
 end
 local ratio=count>0 and diff/count or 0
 local failures={}
 if #expected~=#actual then failures[#failures+1]={field='tamanho',expected=#expected,actual=#actual}end
 if ratio>coverage then failures[#failures+1]={field='cobertura',expected=coverage,actual=ratio,delta=maxDelta,index=worst}end
 return {ok=#failures==0,failures=failures,checked=count,tolerance=tolerance,coverage=coverage,ratio=ratio,maxDelta=maxDelta,kind='pixel'}
end
function G.compare(golden,actual,options)
 golden=golden or {};actual=actual or {}
 local sections={}
 if golden.geometry then sections[#sections+1]=G.geometry(golden.geometry,actual.geometry,options)end
 if golden.computed then sections[#sections+1]=G.computed(golden.computed,actual.computed)end
 if golden.pixels then sections[#sections+1]=G.pixels(golden.pixels,actual.pixels,options)end
 local ok,checked,failures=true,0,{}
 for _,section in ipairs(sections)do
  checked+=section.checked
  if not section.ok then ok=false end
  for _,failure in ipairs(section.failures)do failure.kind=section.kind;failures[#failures+1]=failure end
 end
 return {ok=ok,id=golden.id,module=golden.module,sections=sections,failures=failures,checked=checked}
end
function G.signature(golden)
 return Manifest.hash(Http:JSONEncode({golden.geometry or {},golden.computed or {},golden.pixels or {}}))
end
local function copy(value)
 if type(value)~='table' then return value end
 local out={}
 for key,item in pairs(value)do out[key]=copy(item)end
 return out
end
function G.record(case,actual,options)
 assert(type(case)=='table'and case.id,'Golden exige um caso com id.')
 actual=actual or {}
 local golden={id=case.id,module=case.module,version=G.VERSION,created=os.date('!%Y-%m-%dT%H:%M:%SZ'),source=(options and options.source)or 'engine',tolerance=table.clone(G.tolerance),geometry=copy(actual.geometry),computed=copy(actual.computed),pixels=copy(actual.pixels)}
 golden.hash=G.signature(golden)
 return golden
end
function G.fromCase(case)
 assert(type(case)=='table'and case.id,'Caso invalido.')
 local expect=case.expect or {}
 local golden={id=case.id,module=case.module,version=G.VERSION,created=case.created or 'spec',source='spec',tolerance=table.clone(G.tolerance),geometry=copy(expect.geometry),computed=copy(expect.computed),pixels=copy(expect.pixels)}
 golden.hash=G.signature(golden)
 return golden
end
local function folder(create)
 local existing=Storage:FindFirstChild(G.FOLDER)
 if existing then
  assert(existing:IsA('Folder')and existing:GetAttribute('CssOwner')==G.OWNER,'ServerStorage.'..G.FOLDER..' pertence a outro sistema.')
  return existing
 end
 if not create then return nil end
 local created=Instance.new('Folder')
 created.Name=G.FOLDER
 created:SetAttribute('CssOwner',G.OWNER)
 created.Parent=Storage
 return created
end
function G.store(golden)
 assert(type(golden)=='table'and golden.id,'store exige um golden com id.')
 assert(golden.id:match('^[%a_][%w_%-%.]*$')and #golden.id<=64,'Id de golden invalido.')
 local root=folder(true)
 local value=root:FindFirstChild(golden.id)
 if not value then value=Instance.new('StringValue');value.Name=golden.id;value.Parent=root end
 assert(value:IsA('StringValue'),'Golden existente nao e StringValue.')
 golden.hash=golden.hash or G.signature(golden)
 value.Value=Http:JSONEncode(golden)
 value:SetAttribute('CssGoldenHash',golden.hash)
 value:SetAttribute('CssGoldenVersion',golden.version or G.VERSION)
 value:SetAttribute('CssGoldenSource',tostring(golden.source))
 return value
end
function G.load(id)
 local root=folder(false)
 local value=root and root:FindFirstChild(tostring(id))
 if not value then return nil end
 assert(value:IsA('StringValue'),'Golden invalido: '..tostring(id))
 local ok,decoded=pcall(function()return Http:JSONDecode(value.Value)end)
 assert(ok and type(decoded)=='table','Golden corrompido: '..tostring(id))
 return decoded
end
function G.list()
 local root=folder(false)
 local out={}
 if not root then return out end
 for _,item in ipairs(root:GetChildren())do
  if item:IsA('StringValue')then out[#out+1]={id=item.Name,hash=item:GetAttribute('CssGoldenHash'),version=item:GetAttribute('CssGoldenVersion'),source=item:GetAttribute('CssGoldenSource')}end
 end
 table.sort(out,function(a,b)return a.id<b.id end)
 return out
end
function G.remove(id)
 local root=folder(false)
 local value=root and root:FindFirstChild(tostring(id))
 if not value then return false end
 value:Destroy()
 return true
end
function G.verify(golden)
 if type(golden)~='table'then return false,'golden ausente' end
 local hash=G.signature(golden)
 if golden.hash and golden.hash~=hash then return false,'hash divergente: '..tostring(golden.hash)..' -> '..hash end
 if (golden.version or G.VERSION)~=G.VERSION then return false,'versao de golden incompativel' end
 return true,hash
end
function G.report(result)
 if not result then return 'sem resultado' end
 local lines={string.format('Golden %s | %s | %d verificacoes',tostring(result.id),result.ok and 'conforme' or 'divergente',result.checked or 0)}
 for _,section in ipairs(result.sections or {})do
  lines[#lines+1]=string.format('  %-8s %s (%d checagens, tolerancia %s)',section.kind,section.ok and 'ok' or 'falhou',section.checked,tostring(section.tolerance))
 end
 for _,failure in ipairs(result.failures or {})do
  lines[#lines+1]=string.format('  %s %s.%s esperado %s obtido %s',tostring(failure.kind),tostring(failure.id or '-'),tostring(failure.field),tostring(failure.expected),tostring(failure.actual))
 end
 return table.concat(lines,'\n')
end
return G
