local U=require(script.Parent.Util)
local P={VERSION=1}
P.properties={'page'}
P.pageContext={size=true,marks=true,bleed=true,['page-orientation']=true}
P.marginBoxes={['top-left-corner']=true,['top-left']=true,['top-center']=true,['top-right']=true,['top-right-corner']=true,['bottom-left-corner']=true,['bottom-left']=true,['bottom-center']=true,['bottom-right']=true,['bottom-right-corner']=true,['left-top']=true,['left-middle']=true,['left-bottom']=true,['right-top']=true,['right-middle']=true,['right-bottom']=true}
local MM=96/25.4
local sizes={a3={297,420},a4={210,297},a5={148,210},b4={250,353},b5={176,250},['jis-b4']={257,364},['jis-b5']={182,257},letter={215.9,279.4},legal={215.9,355.6},ledger={279.4,431.8}}
local absolute={px=1,mm=MM,cm=MM*10,q=MM/4,['in']=96,pt=96/72,pc=16}
local function absoluteLength(token)
 local n,unit=token:match('^([%d%.]+)(%a*)$')
 n=n and tonumber(n)
 if not n then return nil end
 if unit==''then return n==0 and 0 or nil end
 local factor=absolute[unit:lower()]
 return factor and n*factor or nil
end
P.absoluteLength=absoluteLength
function P.size(value)
 value=U.trim((value or 'auto'):lower())
 if value==''or value=='auto'then return nil end
 local orientation,dims
 for _,w in ipairs(U.split(value,' '))do
  if w=='portrait'or w=='landscape'then assert(not orientation,'size aceita uma orientação.');orientation=w
  elseif sizes[w]then assert(not dims,'size aceita um único nome de página.');dims={sizes[w][1]*MM,sizes[w][2]*MM,named=true}
  else
   local px=absoluteLength(w);assert(px and px>0,'size inválido: '..w)
   dims=dims or {};assert(not dims.named and #dims<2,'size aceita até dois comprimentos.');dims[#dims+1]=px
  end
 end
 if dims and #dims==1 then dims[2]=dims[1]end
 if dims and orientation then
  local w,h=dims[1],dims[2]
  if(orientation=='landscape')~=(w>h)then dims[1],dims[2]=h,w end
 end
 return dims and {width=dims[1],height=dims[2],orientation=orientation}or nil
end
local function stripImportant(v)
 local important=v:match('%s*![iI][mM][pP][oO][rR][tT][aA][nN][tT]%s*$')~=nil
 return U.trim(v:gsub('%s*![iI][mM][pP][oO][rR][tT][aA][nN][tT]%s*$','')),important
end
function P.declarations(body,base)
 local out,rest={},{}
 for _,line in ipairs(U.split(body,';'))do
  local k,v=line:match('^%s*([%w_%-]+)%s*:%s*(.-)%s*$')
  if k and P.pageContext[k:lower()]then
   local key=k:lower();local important;v,important=stripImportant(v)
   if key=='size'then P.size(v)
   elseif key=='marks'then for _,w in ipairs(U.split(v:lower(),' '))do assert(w=='none'or w=='crop'or w=='cross','marks aceita none, crop e/ou cross.')end
   elseif key=='bleed'then assert(v=='auto'or absoluteLength(v),'bleed aceita auto ou comprimento absoluto.')
   elseif key=='page-orientation'then assert(({upright=true,['rotate-left']=true,['rotate-right']=true})[v:lower()],'page-orientation inválido.')end
   out[#out+1]={key=key,value=v,important=important}
  elseif U.trim(line)~=''then rest[#rest+1]=line end
 end
 if #rest>0 then for _,d in ipairs(base(table.concat(rest,';')))do out[#out+1]=d end end
 return out
end
local pseudoWeights={first=10,blank=10,left=1,right=1}
local function selectorMatches(piece,ctx)
 piece=U.trim(piece)
 if piece==''then return true,0 end
 local name,pseudo=piece:match('^([%a_][%w_%-]*):([%a][%w%-]*)$')
 if not name then pseudo=piece:match('^:([%a][%w%-]*)$')end
 if not name and not pseudo then name=piece end
 local weight=0
 if name then
  if not ctx.name or ctx.name:lower()~=name:lower()then return false end
  weight+=100
 end
 if pseudo then
  pseudo=pseudo:lower()
  if pseudo=='first'then if not ctx.first then return false end
  elseif pseudo=='blank'then if not ctx.blank then return false end
  elseif pseudo=='left'or pseudo=='right'then if(ctx.side or 'right')~=pseudo then return false end
  else return false end
  weight+=pseudoWeights[pseudo]
 end
 return true,weight
end
local function better(a,b)
 if not b then return true end
 if a.important~=b.important then return a.important end
 if a.weight~=b.weight then return a.weight>b.weight end
 return a.order>=b.order
end
function P.resolve(pages,ctx)
 ctx=ctx or {}
 local winners,boxes,order={},{},0
 for _,page in ipairs(pages or {})do
  if not ctx.active or ctx.active(page)then
   local best
   for _,piece in ipairs(page.selectors or {''})do
    local ok,weight=selectorMatches(piece,ctx)
    if ok and(not best or weight>best)then best=weight end
   end
   if best then
    order+=1
    for _,d in ipairs(page.declarations or {})do
     local candidate={value=d.value,important=d.important==true,weight=best,order=order}
     if better(candidate,winners[d.key])then winners[d.key]=candidate end
    end
    for _,margin in ipairs(page.margins or {})do
     local box=boxes[margin.name]or {}
     boxes[margin.name]=box
     for _,d in ipairs(margin.declarations or {})do
      local candidate={value=d.value,important=d.important==true,weight=best,order=order,shorthand=d.shorthand}
      if better(candidate,box[d.key])then box[d.key]=candidate end
     end
    end
   end
  end
 end
 local values={};for k,w in pairs(winners)do values[k]=w.value end
 local marginBoxes,marginDeclarations={},nil
 for name,box in pairs(boxes)do
  local flat,list={},{}
  for k,w in pairs(box)do flat[k]=w.value;list[#list+1]={key=k,value=w.value,shorthand=w.shorthand,important=w.important}end
  table.sort(list,function(a,b)return a.key<b.key end)
  marginBoxes[name]=flat
  if #list>0 then marginDeclarations=marginDeclarations or {};marginDeclarations[name]=list end
 end
 return {values=values,size=P.size(values.size),marks=values.marks,bleed=values.bleed,orientation=values['page-orientation'],marginBoxes=marginBoxes,marginDeclarations=marginDeclarations,matched=order}
end
local sides={'top','right','bottom','left'}
function P.applyRoot(style,pages,ctx,toPx)
 if not pages or not pages[1]then return nil end
 local name=style.page
 if name==nil or name=='auto'then name=nil end
 ctx=ctx or {};ctx.name=name
 if ctx.first==nil then ctx.first=true end
 local page=P.resolve(pages,ctx)
 if page.matched==0 then return nil end
 local margins={}
 for _,side in ipairs(sides)do
  local raw=page.values['margin-'..side]
  local px=raw and toPx(raw)or 0
  margins[side]=px
  local key='padding-'..side
  local current=style[key]
  if type(current)=='number'then style[key]=current+px
  elseif px>0 then local ok,base=pcall(toPx,current);style[key]=(ok and type(base)=='number'and base or 0)+px end
 end
 page.margins=margins
 if page.size then
  page.width=page.size.width;page.height=page.size.height
  style.width=page.width..'px';style.height=page.height..'px'
 end
 if page.bleed and page.bleed~='auto'then page.bleedPx=absoluteLength(page.bleed)or 0
 elseif page.marks and page.marks~='none'then page.bleedPx=6*MM else page.bleedPx=0 end
 style._page=page
 return page
end
return P
