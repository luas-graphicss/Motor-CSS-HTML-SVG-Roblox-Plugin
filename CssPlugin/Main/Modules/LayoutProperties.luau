local U=require(script.Parent.Util)
local P={}
P.supported={}
for word in ('aspect-ratio column-span table-layout border-collapse border-spacing caption-side empty-cells shape-outside shape-margin shape-image-threshold initial-letter orphans widows page-break-before page-break-after page-break-inside'):gmatch('%S+')do P.supported[word]=true end
for word in ('grid-template-rows grid-template-areas grid-auto-rows grid-auto-columns grid-auto-flow grid-column-start grid-column-end grid-row-start grid-row-end grid-column grid-row grid-area justify-items justify-self place-items place-self place-content order column-count column-width column-fill column-rule column-rule-width column-rule-style column-rule-color columns float clear inset break-before break-after break-inside'):gmatch('%S+')do P.supported[word]=true end
P.shorthands={
 ['page-break-before']={'break-before'},['page-break-after']={'break-after'},['page-break-inside']={'break-inside'},
 ['grid-column']={'grid-column-start','grid-column-end'},['grid-row']={'grid-row-start','grid-row-end'},
 ['grid-area']={'grid-row-start','grid-column-start','grid-row-end','grid-column-end'},
 ['place-items']={'align-items','justify-items'},['place-self']={'align-self','justify-self'},['place-content']={'align-content','justify-content'},
 inset={'top','right','bottom','left'},columns={'column-width','column-count'},
 ['column-rule']={'column-rule-width','column-rule-style','column-rule-color'},
}
local ruleStyles={none=true,hidden=true,solid=true,dashed=true,dotted=true,double=true}
local function ident(s)return s and s~='auto'and s~='span'and s:match('^[%a_%-][%w_%-]*$')~=nil end
function P.expand(name,value)
 local keys=assert(P.shorthands[name]);local out={}
 if name:sub(1,11)=='page-break-'then out[keys[1]]=value=='always'and'page'or value;return out end
 if name=='grid-area'or name=='grid-row'or name=='grid-column'then
  local t=U.split(value,'/');assert(#t>=1 and #t<=#keys,'Posicionamento grid inválido: '..value)
  if name=='grid-area'then
   t[2]=t[2]or(ident(t[1])and t[1]or'auto');t[3]=t[3]or(ident(t[1])and t[1]or'auto');t[4]=t[4]or(ident(t[2])and t[2]or'auto')
  else t[2]=t[2]or(ident(t[1])and t[1]or'auto')end
  for i,k in ipairs(keys)do out[k]=t[i]end
 elseif name=='inset'then
  local t=U.split(value,' ');assert(#t>=1 and #t<=4,'inset aceita 1 a 4 valores.')
  out.top=t[1];out.right=t[2]or t[1];out.bottom=t[3]or t[1];out.left=t[4]or t[2]or t[1]
 elseif name=='columns'then
  out['column-width']='auto';out['column-count']='auto';local seen={};local t=U.split(value,' ')
  assert(#t>=1 and #t<=2,'columns aceita largura e/ou contagem.')
  for _,v in ipairs(t)do if v~='auto'then
   local k=v:match('^%d+$')and'column-count'or'column-width';assert(not seen[k],'columns repetido.');seen[k]=true;out[k]=v
  end end
 elseif name=='column-rule'then
  out['column-rule-width']='medium';out['column-rule-style']='none';out['column-rule-color']='currentcolor'
  local seen={};local t=U.split(value,' ');assert(#t>=1 and #t<=3,'column-rule inválido.')
  for _,v in ipairs(t)do
   local k=ruleStyles[v]and'column-rule-style'or(v=='thin'or v=='medium'or v=='thick'or v:match('^[%d%.]')or v:match('^calc%(')or v:match('^clamp%('))and'column-rule-width'or'column-rule-color'
   assert(not seen[k],'column-rule repetido.');seen[k]=true;out[k]=v
  end
 else
  local t=U.split(value,' ');assert(#t>=1 and #t<=2,name..' aceita 1 ou 2 valores.')
  out[keys[1]]=t[1];out[keys[2]]=t[2]or t[1]
 end
 return out
end
function P.ratio(value)
 if type(value)~='string'then return nil end
 local text=value:lower():gsub('%s+',' '):match('^%s*(.-)%s*$')
 if text==''or text=='auto'then return nil end
 text=text:gsub('^auto ',''):gsub(' auto$','')
 local a,b=text:match('^([%d%.]+)%s*/%s*([%d%.]+)$')
 if not a then a=text:match('^([%d%.]+)$');b='1'end
 assert(a,'aspect-ratio aceita auto, <numero> ou <numero> / <numero>.')
 local num,den=tonumber(a),tonumber(b)
 assert(num and den and num>0 and den>0,'aspect-ratio exige numeros positivos.')
 return num/den
end
function P.isAuto(value)return value==nil or value=='auto'end
function P.hasPercent(value)
 if type(value)=='string'then return value:find('%%')~=nil end
 if type(value)=='table'then
  if value.unit=='%'then return true end
  for _,v in pairs(value)do if type(v)=='table'and P.hasPercent(v)then return true end end
 end
 return false
end
function P.ordered(list,styles)
 local out=table.clone(list);local rank={}
 for i,node in ipairs(list)do rank[node]=i end
 table.sort(out,function(a,b)local aa=tonumber(styles[a.key].order)or 0;local bb=tonumber(styles[b.key].order)or 0;return aa==bb and rank[a]<rank[b]or aa<bb end)
 return out
end
return P
