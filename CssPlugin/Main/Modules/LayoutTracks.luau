local U=require(script.Parent.Util)
local T={LIMIT=512}
local keywords={auto=true,['min-content']=true,['max-content']=true}
local function bound(value,normalize,allowFr)
 if keywords[value]then return value end
 local fr=tonumber(value:match('^([%d%.]+)fr$'))
 if fr then assert(allowFr and fr>=0,'fr inválido na medida mínima.');return {fr=fr}end
 return normalize(value)
end
function T.parse(value,normalize,depth)
 normalize=normalize or function(v)return v end;depth=depth or 0
 assert(depth<=12,'Grid: repeat profundo demais.');value=value or'none'
 if value=='none'then return {}end
 if value:match('^subgrid%f[%W]')or value=='subgrid'then
  assert(depth==0,'subgrid não pode estar dentro de repeat().');local names={}
  local rest=U.trim(value:sub(8))
  for _,token in ipairs(U.split(rest:gsub('%[',' ['):gsub('%]','] '),' '))do
   local body=assert(token:match('^%[(.*)%]$'),'Após subgrid use apenas grupos [nomes-de-linha].');local list=U.split(body,' ')
   for _,name in ipairs(list)do assert(name:match('^[%a_%-][%w_%-]*$')and name~='auto'and name~='span','Nome de linha subgrid inválido.')end
   names[#names+1]=list;assert(#names<=T.LIMIT+1,'Muitas linhas subgrid.')
  end
  return {{kind='subgrid',names=names}}
 end
 local tokens=U.split(value:gsub('%[',' ['):gsub('%]','] '),' ');local out={}
 for _,token in ipairs(tokens)do
  local names=token:match('^%[(.*)%]$')
  if names then
   local list=U.split(names,' ');for _,name in ipairs(list)do assert(name:match('^[%a_%-][%w_%-]*$')and name~='auto'and name~='span','Nome de linha grid inválido.')end
   out[#out+1]={kind='line',names=list}
  else
   local fn,body=token:match('^([%a%-]+)%((.*)%)$')
   if fn=='repeat'then
    local args=U.split(body,',');assert(#args==2,'repeat aceita contagem e tracks.')
    local n=tonumber(args[1]);assert((n and n%1==0 and n>=1 and n<=T.LIMIT)or args[1]=='auto-fill'or args[1]=='auto-fit','Contagem repeat inválida.')
    local items=T.parse(args[2],normalize,depth+1);local hasTrack=false
    for _,entry in ipairs(items)do if entry.kind~='line'then hasTrack=true;break end end
    assert(hasTrack,'repeat precisa conter pelo menos um track.')
    out[#out+1]={kind='repeat',count=n or args[1],items=items}
   elseif fn=='minmax'then
    local args=U.split(body,',');assert(#args==2,'minmax aceita mínimo e máximo.')
    out[#out+1]={kind='track',min=bound(args[1],normalize,false),max=bound(args[2],normalize,true)}
   elseif fn=='fit-content'then
    local args=U.split(body,',');assert(#args==1 and not keywords[args[1]],'fit-content exige um limite de comprimento.')
    out[#out+1]={kind='track',min='auto',max='max-content',fit=normalize(args[1])}
   else
    local b=bound(token,normalize,true)
    if type(b)=='table'and b.fr then out[#out+1]={kind='track',min='auto',max=b,fr=b.fr}
    else out[#out+1]={kind='track',min=b,max=b,length=not keywords[b]and b or nil}end
   end
  end
 end
 return out
end
local function numeric(value,length)
 if type(value)=='string'and keywords[value]or type(value)=='table'and value.fr~=nil then return nil end
 if value==nil then return nil end
 local number=length(value);assert(type(number)=='number','Medida de track inválida.');return math.max(0,number)
end
local function fixedBreadth(track,length)
 local lo,hi=numeric(track.min,length),numeric(track.max,length)
 return hi and math.max(lo or 0,hi)or lo
end
function T.expand(syntax,available,gap,length)
 if syntax[1]and syntax[1].kind=='subgrid'then return {},{}end
 local automatic=nil;local fixedCount,fixedSize=0,0
 local function scan(list,mult)
  for _,entry in ipairs(list)do
   if entry.kind=='track'then fixedCount+=mult;assert(fixedCount<=T.LIMIT,'Grid excede 512 tracks.');fixedSize+=mult*(fixedBreadth(entry,length)or 0)
   elseif entry.kind=='repeat'then
    if type(entry.count)=='number'then scan(entry.items,mult*entry.count)
    else assert(not automatic and mult==1,'Apenas um auto-repeat por eixo.');automatic=entry end
   end
  end
 end
 scan(syntax,1);local repetitions=1
 if automatic then
  local count,size=0,0
  for _,entry in ipairs(automatic.items)do
   assert(entry.kind~='repeat','auto-repeat não aceita repeat aninhado.')
   if entry.kind=='track'then count+=1;local breadth=fixedBreadth(entry,length);assert(breadth,'auto-repeat exige uma medida fixa em cada track/minmax.');size+=math.max(1,breadth)end
  end
  assert(count>0,'auto-repeat sem tracks.')
  if available then repetitions=math.max(1,math.floor((available-fixedSize-gap*(fixedCount-1))/(size+count*gap)))end
  assert(fixedCount+count*repetitions<=T.LIMIT,'Grid excede 512 tracks; aumente o tamanho mínimo.')
 end
 local tracks,lines={},{ };local work=0
 local function append(list,fit)
  for _,entry in ipairs(list)do
   work+=1+(entry.names and #entry.names or 0);assert(work<=65536,'Grid excede o orçamento de expansão de linhas nomeadas.')
   if entry.kind=='line'then
    for _,name in ipairs(entry.names)do
     local indices=lines[name];if not indices then indices={};lines[name]=indices end
     local at=#tracks+1;if indices[#indices]~=at then indices[#indices+1]=at end
    end
   elseif entry.kind=='repeat'then
    local n=type(entry.count)=='number'and entry.count or repetitions
    for _=1,n do append(entry.items,fit or entry.count=='auto-fit')end
   else
    assert(#tracks<T.LIMIT,'Grid excede 512 tracks.');local copy=table.clone(entry);copy.autoFit=fit==true;tracks[#tracks+1]=copy
   end
  end
 end
 append(syntax,false);return tracks,lines
end
function T.areas(value)
 if not value or value=='none'then return {},0,0 end
 local rows=U.split(value,' ');local areas,columns={},nil
 for r,quoted in ipairs(rows)do
  local q=quoted:sub(1,1);assert((q=='"'or q=="'")and quoted:sub(-1)==q,'grid-template-areas exige linhas entre aspas.')
  local names=U.split(quoted:sub(2,-2),' ');columns=columns or #names
  assert(#names==columns and columns>0,'grid-template-areas precisa ter linhas da mesma largura.')
  for c,name in ipairs(names)do
   if not name:match('^%.+$')then
    assert(name:match('^[%a_%-][%w_%-]*$'),'Nome de área grid inválido.')
    local area=areas[name];if not area then area={r1=r,r2=r+1,c1=c,c2=c+1,cells=0};areas[name]=area end
    area.r1=math.min(area.r1,r);area.r2=math.max(area.r2,r+1);area.c1=math.min(area.c1,c);area.c2=math.max(area.c2,c+1);area.cells+=1
   end
  end
 end
 for _,area in pairs(areas)do assert(area.cells==(area.r2-area.r1)*(area.c2-area.c1),'Área grid deve ser retangular e contínua.')end
 return areas,#rows,columns or 0
end
function T.pack(value,free,count,gap)
 free=math.max(0,free);local offset=0;value=value or'normal'
 if value=='center'then offset=free/2 elseif value=='end'or value=='flex-end'then offset=free
 elseif value=='space-between'and count>1 then gap+=free/(count-1)
 elseif value=='space-around'and count>0 then offset=free/(2*count);gap+=free/count
 elseif value=='space-evenly'and count>0 then offset=free/(count+1);gap+=offset
 else assert(value=='start'or value=='flex-start'or value=='normal'or value=='stretch'or value=='space-between'or value=='space-around'or value=='space-evenly','Alinhamento grid inválido: '..value)end
 return offset,gap
end
function T.size(defs,contributions,available,gap,length,alignment,intrinsic)
 local bases,caps,goals,weights,intrinsic,stretch,collapsed={},{},{},{},{},{},{}
 for i,def in ipairs(defs)do
  local lo,hi=numeric(def.min,length),numeric(def.max,length)
  bases[i]=lo or 0;weights[i]=type(def.max)=='table'and def.max.fr or 0
  caps[i]=hi and math.max(bases[i],hi)or math.huge;goals[i]=bases[i];intrinsic[i]=lo==nil;stretch[i]=def.max=='auto';collapsed[i]=def.collapsed==true
  if collapsed[i]then bases[i]=0;caps[i]=0;goals[i]=0;weights[i]=0;intrinsic[i]=false;stretch[i]=false end
 end
 local function gutters(a,b)
  local total=0;for i=a,b-1 do if not collapsed[i]and not collapsed[i+1]then total+=gap end end;return total
 end
 local function distribute(array,first,last,need,eligible,limit)
  local used=gutters(first,last);for i=first,last do used+=array[i]end
  local deficit=math.max(0,need-used)
  for _=first,last do
   if deficit<0.0001 then break end
   local count=0;for i=first,last do if eligible(i)and array[i]<(limit(i)or math.huge)-0.0001 then count+=1 end end
   if count==0 then break end
   local added=0
   for i=first,last do if eligible(i)then local delta=math.min(deficit/count,math.max(0,(limit(i)or math.huge)-array[i]));array[i]+=delta;added+=delta end end
   if added<0.0001 then break end;deficit-=added
  end
 end
 table.sort(contributions,function(a,b)return a.last-a.first<b.last-b.first end)
 for _,item in ipairs(contributions)do
  local function eligible(i)return intrinsic[i]and not collapsed[i]end
  local requirement=item.min
  if item.first==item.last and defs[item.first].min=='max-content'then requirement=item.max end
  distribute(bases,item.first,item.last,requirement,eligible,function(i)return caps[i]end)
 end
 for i=1,#defs do goals[i]=collapsed[i]and 0 or math.max(bases[i],numeric(defs[i].max,length)or bases[i])end
 for _,item in ipairs(contributions)do
  distribute(goals,item.first,item.last,item.max,function(i)return not collapsed[i]and numeric(defs[i].max,length)==nil end,function(i)
   local fit=defs[i].fit and numeric(defs[i].fit,length)
   return fit and math.max(bases[i],fit)or caps[i]
  end)
 end
 for i,def in ipairs(defs)do
  if def.max=='min-content'then goals[i]=bases[i]end
  if def.fit then goals[i]=math.max(bases[i],math.min(goals[i],numeric(def.fit,length)))end
 end
 local gapTotal=gutters(1,#defs);local space=available and math.max(0,available-gapTotal)
 if not space then
   
  if intrinsic~='min-content'then
   local unit=0;for i=1,#defs do if weights[i]>0 then unit=math.max(unit,goals[i]/weights[i])else bases[i]=goals[i]end end
   for i=1,#defs do if weights[i]>0 then bases[i]=math.max(bases[i],weights[i]*unit)end end
  end
 else
  local total=0;for _,v in ipairs(bases)do total+=v end
  local free=math.max(0,space-total)
  for _=1,#defs do
   local count=0;for i=1,#defs do if weights[i]==0 and bases[i]<goals[i]-0.0001 then count+=1 end end
   if count==0 or free<0.0001 then break end
   local used=0;for i=1,#defs do if weights[i]==0 then local add=math.min(free/count,math.max(0,goals[i]-bases[i]));bases[i]+=add;used+=add end end
   free-=used
  end
  local frozen={}
  for _=1,#defs+1 do
   local fixed,sum=0,0
   for i=1,#defs do if weights[i]>0 and not frozen[i]then sum+=weights[i]else fixed+=bases[i]end end
   if sum==0 then break end
   local unit=math.max(0,space-fixed)/math.max(1,sum);local changed=false
   for i=1,#defs do if weights[i]>0 and not frozen[i]and bases[i]>unit*weights[i]+0.0001 then frozen[i]=true;changed=true end end
   if not changed then for i=1,#defs do if weights[i]>0 and not frozen[i]then bases[i]=unit*weights[i]end end;break end
  end
  total=0;local count=0;for i,v in ipairs(bases)do total+=v;if stretch[i]then count+=1 end end
  free=math.max(0,space-total)
  if (alignment=='normal'or alignment=='stretch')and count>0 then for i=1,#defs do if stretch[i]then bases[i]+=free/count end end end
 end
 local total=gapTotal;local active=0;for i,v in ipairs(bases)do total+=v;if not collapsed[i]then active+=1 end end
 local offset,packed=T.pack(alignment,(available or total)-total,active,gap)
 local starts,ends={},{};local cursor=offset
 for i,v in ipairs(bases)do starts[i]=cursor;ends[i]=cursor+v;cursor+=v;if i<#defs and not collapsed[i]and not collapsed[i+1]then cursor+=packed end end
 return {sizes=bases,starts=starts,ends=ends,total=math.max(total,cursor),count=#defs}
end
return T
