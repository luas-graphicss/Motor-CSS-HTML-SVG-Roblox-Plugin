local P={VERSION=1}
local function trim(s)return(s:gsub('^%s+',''):gsub('%s+$',''))end
P.trim=trim
P.features=table.freeze({
 ['prefers-color-scheme']=table.freeze({light=true,dark=true}),
 ['prefers-reduced-motion']=table.freeze({['no-preference']=true,reduce=true}),
 ['prefers-contrast']=table.freeze({['no-preference']=true,more=true,less=true,custom=true}),
 ['prefers-reduced-transparency']=table.freeze({['no-preference']=true,reduce=true}),
 ['prefers-reduced-data']=table.freeze({['no-preference']=true,reduce=true}),
 ['forced-colors']=table.freeze({none=true,active=true}),
 ['inverted-colors']=table.freeze({none=true,inverted=true}),
})
P.neutral=table.freeze({
 ['prefers-reduced-motion']='no-preference',['prefers-contrast']='no-preference',
 ['prefers-reduced-transparency']='no-preference',['prefers-reduced-data']='no-preference',
 ['forced-colors']='none',['inverted-colors']='none',
})
P.fields=table.freeze({contrast='prefers-contrast',reducedTransparency='prefers-reduced-transparency',
 reducedData='prefers-reduced-data',forcedColors='forced-colors',invertedColors='inverted-colors'})
P.featureField=table.freeze({['prefers-contrast']='contrast',['prefers-reduced-transparency']='reducedTransparency',
 ['prefers-reduced-data']='reducedData',['forced-colors']='forcedColors',['inverted-colors']='invertedColors'})
P.defaults=table.freeze({contrast='no-preference',reducedTransparency='no-preference',
 reducedData='no-preference',forcedColors='none',invertedColors='none'})
P.order=table.freeze({'contrast','reducedTransparency','reducedData','forcedColors','invertedColors'})
function P.keywords(feature)
 local list={};for k in pairs(assert(P.features[feature],'Feature desconhecida: '..tostring(feature)))do list[#list+1]=k end
 table.sort(list);return table.concat(list,'/')
end
function P.validate(field,value)
 local feature=P.fields[field];assert(feature,'Preferência desconhecida: '..tostring(field))
 assert(type(value)=='string'and P.features[feature][value],feature..' aceita '..P.keywords(feature)..'.')
 return value
end
function P.overrides(input)
 assert(input==nil or type(input)=='table','Preferências exigem uma tabela.')
 local out={};for field,value in pairs(input or {})do out[field]=P.validate(field,value)end;return out
end
function P.environment(input)
 local out=P.overrides(input)
 for field,default in pairs(P.defaults)do if out[field]==nil then out[field]=default end end
 return out
end
function P.key(environment)
 local parts={};for _,field in ipairs(P.order)do parts[#parts+1]=(environment and environment[field])or P.defaults[field]end
 return table.concat(parts,'|')
end
function P.value(feature,context)
 context=context or {}
 if feature=='prefers-color-scheme'then return context.colorScheme or'light'end
 if feature=='prefers-reduced-motion'then
  local v=context.reducedMotion
  if type(v)=='boolean'then return v and'reduce'or'no-preference'end
  return v or'no-preference'
 end
 local field=P.featureField[feature];if not field then return nil end
 return context[field]or P.defaults[field]
end
function P.evaluate(feature,wanted,context)
 local actual=P.value(feature,context);if actual==nil then return nil end
 return actual==wanted
end
function P.boolean(feature,context)
 if feature=='prefers-color-scheme'then return true end
 local neutral=P.neutral[feature];if not neutral then return nil end
 return P.value(feature,context)~=neutral
end
P.adjust=table.freeze({auto=true,none=true,['preserve-parent-color']=true})
local dark=table.freeze({canvas='#000000',canvastext='#ffffff',linktext='#ffff00',visitedtext='#a0a0ff',
 activetext='#00ffff',buttonface='#000000',buttontext='#ffffff',buttonborder='#ffffff',field='#000000',
 fieldtext='#ffffff',highlight='#1aebff',highlighttext='#000000',graytext='#3ff23f',mark='#ffff00',
 marktext='#000000',accentcolor='#1aebff',accentcolortext='#000000'})
local light=table.freeze({canvas='#ffffff',canvastext='#000000',linktext='#0000ee',visitedtext='#551a8b',
 activetext='#ee0000',buttonface='#ffffff',buttontext='#000000',buttonborder='#000000',field='#ffffff',
 fieldtext='#000000',highlight='#0000ff',highlighttext='#ffffff',graytext='#600000',mark='#ffff00',
 marktext='#000000',accentcolor='#0000ff',accentcolortext='#ffffff'})
P.palettes=table.freeze({dark=dark,light=light})
function P.palette(scheme)return scheme=='dark'and dark or light end
local slots={color='canvastext',background='canvas',['background-color']='canvas',
 ['border-color']='buttonborder',['outline-color']='buttonborder',['column-rule-color']='buttonborder',
 ['text-decoration-color']='canvastext',['text-emphasis-color']='canvastext',['caret-color']='canvastext',
 fill='canvastext',stroke='canvastext',['scrollbar-color']=false}
for _,side in ipairs({'top','right','bottom','left'})do slots['border-'..side..'-color']='buttonborder'end
P.slots=table.freeze(slots)
function P.active(environment)
 return environment~=nil and environment.forcedColors=='active'
end
function P.adjustment(style,parent)
 local value=style and style['forced-color-adjust']
 if value==nil or value=='initial'then return 'auto'end
 value=trim(tostring(value)):lower()
 if value=='inherit'or value=='unset'then return (parent and P.adjustment(parent))or'auto'end
 assert(P.adjust[value],'forced-color-adjust aceita auto/none/preserve-parent-color.')
 return value
end
function P.install(supports)
 supports.register('forced-color-adjust',function(value)return P.adjust[trim(value):lower()]==true end)
end
return P
