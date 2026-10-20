local Seg=require(script.Parent.UnicodeSegmentation)
local Bidi=require(script.Parent.TextBidiUax9)
local N={VERSION=2,UAX29=Seg.UAX29}
N.graphemes=Seg.graphemes
N.words=Seg.words
local upperSpecial={[0xff]=0x178,[0x131]=0x49,[0x17f]=0x53,[0x3c2]=0x3a3,[0x3ac]=0x386,[0x3ad]=0x388,[0x3ae]=0x389,[0x3af]=0x38a,[0x3cc]=0x38c,[0x3cd]=0x38e,[0x3ce]=0x38f}
local lowerSpecial={};for a,b in pairs(upperSpecial)do if a~=0x131 and a~=0x17f and a~=0x3c2 then lowerSpecial[b]=a end end
local function casePoint(cp,upper)
 local special=upper and upperSpecial or lowerSpecial;if special[cp]then return utf8.char(special[cp])end
 if upper and cp==0xdf then return 'SS'end
 if not upper and cp==0x130 then return 'i'..utf8.char(0x307)end
 if (cp>=0x41 and cp<=0x5a)or(cp>=0xc0 and cp<=0xd6)or(cp>=0xd8 and cp<=0xde)or(cp>=0x391 and cp<=0x3a1)or(cp>=0x3a3 and cp<=0x3ab)or(cp>=0x410 and cp<=0x42f)then
  return utf8.char(upper and cp or cp+32)
 end
 if (cp>=0x61 and cp<=0x7a)or(cp>=0xe0 and cp<=0xf6)or(cp>=0xf8 and cp<=0xfe)or(cp>=0x3b1 and cp<=0x3c1)or(cp>=0x3c3 and cp<=0x3cb)or(cp>=0x430 and cp<=0x44f)then
  return utf8.char(upper and cp-32 or cp)
 end
 if cp>=0x400 and cp<=0x40f then return utf8.char(upper and cp or cp+80)end
 if cp>=0x450 and cp<=0x45f then return utf8.char(upper and cp-80 or cp)end
 if cp>=0x100 and cp<=0x12f or cp>=0x132 and cp<=0x137 or cp>=0x14a and cp<=0x177 or cp>=0x1e00 and cp<=0x1e95 then
  return utf8.char(upper and(cp%2==1 and cp-1 or cp)or(cp%2==0 and cp+1 or cp))
 end
 return utf8.char(cp)
end
function N.case(text,upper)
 local out={};for _,cp in utf8.codes(text)do out[#out+1]=casePoint(cp,upper)end;return table.concat(out)
end
function N.isLetter(g)
 local cp=utf8.codepoint(g)
 return cp>=65 and cp<=90 or cp>=97 and cp<=122 or cp>=0xc0 and cp<=0x2af or cp>=0x370 and cp<=0x52f or cp>=0x590 and cp<=0x8ff
end
function N.transform(g,mode,wordStart)
 if mode=='uppercase'then return N.case(g,true)elseif mode=='lowercase'then return N.case(g,false)
 elseif mode=='capitalize'and wordStart and N.isLetter(g)then return N.case(g,true)end
 return g
end
function N.cjk(g)
 local cp=utf8.codepoint(g)
 return cp>=0x2e80 and cp<=0x9fff or cp>=0xac00 and cp<=0xd7af or cp>=0xf900 and cp<=0xfaff or cp>=0x20000 and cp<=0x3134f
end
function N.direction(text)
 for _,cp in utf8.codes(text)do
  local c=Bidi.class(cp)
  if c=='R'or c=='AL'then return 'rtl'end
  if c=='L'or c=='EN'or c=='AN'then return 'ltr'end
 end
 return nil
end
function N.visualOrder(items,base)
 local out={};for i,item in ipairs(items)do out[i]=item end
 local previous=base
 for i,item in ipairs(out)do
  local dir=item.direction
  if not dir then
   local following=base;for j=i+1,#out do if out[j].direction then following=out[j].direction;break end end
   dir=previous==following and previous or base
  else previous=dir end
  item.level=dir=='rtl'and 1 or(base=='rtl'and 2 or 0)
 end
 for level=2,1,-1 do
  local i=1
  while i<=#out do
   if out[i].level>=level then
    local j=i;while j<#out and out[j+1].level>=level do j+=1 end
    local a,b=i,j;while a<b do out[a],out[b]=out[b],out[a];a+=1;b-=1 end;i=j+1
   else i+=1 end
  end
 end
 return out
end
local exceptions={
 ['pt']={'ti-po-gra-fia','pa-rá-gra-fo','res-pon-si-vi-da-de','au-to-ma-ti-ca-men-te','in-ter-na-cio-na-li-za-ção','de-sen-vol-vi-men-to','com-pa-ti-bi-li-da-de','con-fi-gu-ra-ção','ex-tra-or-di-ná-rio'},
 ['en']={'ty-pog-ra-phy','in-ter-na-tion-al-iza-tion','au-to-mat-i-cal-ly','de-vel-op-ment','com-pat-i-bil-i-ty','ex-traor-di-nary','hy-phen-ation'},
}
local dictionaries={}
for lang,words in pairs(exceptions)do
 local dictionary={};dictionaries[lang]=dictionary
 for _,word in ipairs(words)do local plain=word:gsub('%-','');local points={};local n=0
  for _,g in ipairs(N.graphemes(word))do if g=='-'then points[n]=true else n+=1 end end;dictionary[plain]=points
 end
end
local vowels={a=true,e=true,i=true,o=true,u=true,['á']=true,['à']=true,['â']=true,['ã']=true,['é']=true,['ê']=true,['í']=true,['ó']=true,['ô']=true,['õ']=true,['ú']=true,['ü']=true}
local diphthongs={ai=true,ei=true,oi=true,ui=true,au=true,eu=true,ou=true,['ão']=true,['ãe']=true,['õe']=true}
local joined={br=true,cr=true,dr=true,fr=true,gr=true,pr=true,tr=true,vr=true,bl=true,cl=true,fl=true,gl=true,pl=true,lh=true,nh=true,ch=true,qu=true,gu=true}
function N.hyphens(chars,language,custom)
 local lang=(language or ''):lower():match('^[a-z]+')or ''
 local text=N.case(table.concat(chars),false);local dictionary=custom and(custom[language]or custom[lang])
 local pattern=dictionary and dictionary[text]
 if pattern then
  assert(pattern:gsub('%-','')==text,'Padrão de hifenização não corresponde à palavra.')
  local points={};local n=0;for _,g in ipairs(N.graphemes(pattern))do if g=='-'then points[n]=true else n+=1 end end;return points
 end
 if dictionaries[lang]and dictionaries[lang][text]then return dictionaries[lang][text]end
 local out={};if lang~='pt'then return out end
 local gs=N.graphemes(text);local previous
 for i,g in ipairs(gs)do if vowels[g]then
  if previous then
   local gap=i-previous-1;local at
   if gap==0 then if not diphthongs[gs[previous]..g]then at=previous end
   elseif gap==1 then at=previous
   else local pair=gs[i-2]..gs[i-1];at=joined[pair]and i-3 or i-2 end
   if at and at>=2 and at<=#gs-2 then out[at]=true end
  end
  previous=i
 end end
 return out
end
return N
