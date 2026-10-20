local C={VERSION=1}
C.modules={'css-box','css-flexbox','css-grid','css-position','css-text','css-values','css-color','css-backgrounds','css-cascade','css-variables','css-transforms','css-contain'}
C.cases={
 {id='box_01_border_box',module='css-box',title='box-sizing border-box com padding e borda',width=800,height=600,
  properties={'width','height','padding','border','box-sizing'},
  markup='<div id="outer"><div id="inner"></div></div>',
  css='#outer{width:400px;height:200px;padding:10px;border:5px solid #000000;box-sizing:border-box}#inner{width:50%;height:100px}',
  expect={geometry={outer={x=0,y=0,w=400,h=200},inner={x=15,y=15,w=185,h=100}},computed={outer={['box-sizing']='border-box'}}}},
 {id='box_02_margin_collapse',module='css-box',title='colapso de margens entre irmaos',width=800,height=600,
  properties={'margin-top','margin-bottom','height','width'},
  markup='<div id="parent"><div id="a"></div><div id="b"></div></div>',
  css='#parent{width:300px}#a{height:50px;margin-bottom:30px}#b{height:40px;margin-top:20px}',
  expect={geometry={a={x=0,y=0,w=300,h=50},b={x=0,y=80,w=300,h=40},parent={x=0,y=0,w=300,h=120}}}},
 {id='flex_01_space_between',module='css-flexbox',title='justify-content space-between',width=800,height=600,
  properties={'display','justify-content','width','height'},
  markup='<div id="row"><div id="i1"></div><div id="i2"></div><div id="i3"></div></div>',
  css='#row{display:flex;width:300px;height:50px;justify-content:space-between}#i1,#i2,#i3{width:60px;height:50px}',
  expect={geometry={i1={x=0,y=0,w=60,h=50},i2={x=120,y=0,w=60,h=50},i3={x=240,y=0,w=60,h=50}},computed={row={display='flex'}}}},
 {id='flex_02_grow',module='css-flexbox',title='distribuicao por flex-grow',width=800,height=600,
  properties={'display','flex','flex-grow','flex-basis'},
  markup='<div id="row"><div id="a"></div><div id="b"></div></div>',
  css='#row{display:flex;width:300px;height:20px}#a{flex:1 1 0;height:20px}#b{flex:2 1 0;height:20px}',
  expect={geometry={a={x=0,y=0,w=100,h=20},b={x=100,y=0,w=200,h=20}}}},
 {id='grid_01_fr_gap',module='css-grid',title='colunas fracionarias com gap',width=800,height=600,
  properties={'display','grid-template-columns','gap'},
  markup='<div id="g"><div id="a"></div><div id="b"></div></div>',
  css='#g{display:grid;grid-template-columns:1fr 2fr;gap:10px;width:310px}#a{height:30px}#b{height:30px}',
  expect={geometry={a={x=0,y=0,w=100,h=30},b={x=110,y=0,w=200,h=30}}}},
 {id='grid_02_placement',module='css-grid',title='posicionamento explicito em linha e coluna',width=800,height=600,
  properties={'display','grid-template-columns','grid-auto-rows','grid-column','grid-row'},
  markup='<div id="g"><div id="a"></div><div id="b"></div></div>',
  css='#g{display:grid;grid-template-columns:repeat(2,100px);grid-auto-rows:50px;width:200px}#b{grid-column:2;grid-row:2}',
  expect={geometry={a={x=0,y=0,w=100,h=50},b={x=100,y=50,w=100,h=50}}}},
 {id='pos_01_absolute',module='css-position',title='absoluto dentro de contexto relativo',width=800,height=600,
  properties={'position','top','left','width','height'},
  markup='<div id="rel"><div id="abs"></div></div>',
  css='#rel{position:relative;width:200px;height:100px}#abs{position:absolute;top:10px;left:20px;width:50px;height:30px}',
  expect={geometry={abs={x=20,y=10,w=50,h=30}},computed={abs={position='absolute'}}}},
 {id='text_01_line_height',module='css-text',title='altura de linha e alinhamento central',width=800,height=600,
  properties={'font-size','line-height','text-align'},
  markup='<div id="t">Texto</div>',
  css='#t{width:200px;font-size:16px;line-height:2;text-align:center}',
  expect={geometry={t={x=0,y=0,w=200,h=32}},computed={t={['text-align']='center'}}}},
 {id='text_02_logical',module='css-text',title='margem logica em escrita horizontal ltr',width=800,height=600,
  properties={'margin-inline-start','writing-mode','direction'},
  markup='<div id="l"></div>',
  css='#l{margin-inline-start:20px;width:100px;height:20px}',
  expect={geometry={l={x=20,y=0,w=100,h=20}}}},
 {id='values_01_calc',module='css-values',title='calc com rem, porcentagem e em',width=800,height=600,
  properties={'calc','rem','em','width','height','font-size'},
  markup='<div id="box"><div id="u"></div></div>',
  css='#box{width:400px}#u{font-size:20px;width:calc(10rem + 10%);height:2em}',
  expect={geometry={u={x=0,y=0,w=200,h=40}}}},
 {id='color_01_mix',module='css-color',title='hsl e color-mix em srgb',width=800,height=600,
  properties={'color','background-color','color-mix','hsl'},
  markup='<div id="c">cor</div>',
  css='#c{width:50px;height:20px;color:hsl(0 100% 50%);background-color:color-mix(in srgb,#ffffff 50%,#000000)}',
  expect={computed={c={color='rgb(255, 0, 0)',['background-color']='rgb(128, 128, 128)'}}}},
 {id='background_01_radius',module='css-backgrounds',title='border-radius abreviado e cor de fundo',width=800,height=600,
  properties={'background-color','border-radius'},
  markup='<div id="b"></div>',
  css='#b{background-color:#336699;border-radius:8px 4px;width:100px;height:50px}',
  expect={geometry={b={x=0,y=0,w=100,h=50}},computed={b={['background-color']='rgb(51, 102, 153)',['border-top-left-radius']='8px',['border-top-right-radius']='4px'}}}},
 {id='cascade_01_layers',module='css-cascade',title='important sem camada vence camada nomeada',width=800,height=600,
  properties={'@layer','!important','specificity','width'},
  markup='<div id="x" class="a"></div>',
  css='@layer base,theme;@layer base{#x{width:100px;height:10px}}@layer theme{div{width:200px}}.a{width:300px !important}',
  expect={geometry={x={x=0,y=0,w=300,h=10}}}},
 {id='variables_01_fallback',module='css-variables',title='var com fallback e calc',width=800,height=600,
  properties={'--custom','var','calc'},
  markup='<div id="v"></div>',
  css='#v{--pad:12px;width:calc(100px + var(--pad));height:var(--missing,24px)}',
  expect={geometry={v={x=0,y=0,w=112,h=24}}}},
 {id='transform_01_matrix',module='css-transforms',title='translate e scale serializados em matriz',width=800,height=600,
  properties={'transform','translateX','scale'},
  markup='<div id="tr"></div>',
  css='#tr{width:100px;height:50px;transform:translateX(20px) scale(2)}',
  expect={geometry={tr={x=0,y=0,w=100,h=50}},computed={tr={transform='matrix(2, 0, 0, 2, 20, 0)'}}}},
 {id='contain_01_container_query',module='css-contain',title='container query por inline-size',width=800,height=600,
  properties={'container-type','@container','width'},
  markup='<div id="wrap"><div id="card"></div></div>',
  css='#wrap{container-type:inline-size;width:400px}#card{width:50px;height:20px}@container (min-width:300px){#card{width:120px}}',
  expect={geometry={card={x=0,y=0,w=120,h=20}}}},
}
function C.ids()
 local out={}
 for _,case in ipairs(C.cases)do out[#out+1]=case.id end
 return out
end
function C.count() return #C.cases end
function C.byId(id)
 for _,case in ipairs(C.cases)do if case.id==id then return case end end
 return nil
end
function C.byModule(name)
 local out={}
 for _,case in ipairs(C.cases)do if case.module==name then out[#out+1]=case end end
 return out
end
function C.moduleCounts()
 local out={}
 for _,case in ipairs(C.cases)do out[case.module]=(out[case.module]or 0)+1 end
 return out
end
function C.properties()
 local seen,out={},{}
 for _,case in ipairs(C.cases)do
  for _,property in ipairs(case.properties or {})do
   if not seen[property]then seen[property]=true;out[#out+1]=property end
  end
 end
 table.sort(out)
 return out
end
function C.validate()
 local problems={}
 local seen={}
 local known={}
 for _,name in ipairs(C.modules)do known[name]=true end
 for index,case in ipairs(C.cases)do
  local label=tostring(case.id or index)
  if type(case.id)~='string'or not case.id:match('^[%a_][%w_%-%.]*$')then problems[#problems+1]=label..': id invalido' end
  if seen[case.id]then problems[#problems+1]=label..': id duplicado' end
  seen[case.id]=true
  if not known[case.module]then problems[#problems+1]=label..': modulo fora da lista' end
  if type(case.markup)~='string'or #case.markup==0 then problems[#problems+1]=label..': markup ausente' end
  if type(case.css)~='string'or #case.css==0 then problems[#problems+1]=label..': css ausente' end
  local expect=case.expect or {}
  if not expect.geometry and not expect.computed and not expect.pixels then problems[#problems+1]=label..': caso sem expectativa' end
  if (case.properties==nil)or #case.properties==0 then problems[#problems+1]=label..': sem propriedades declaradas' end
 end
 local counts=C.moduleCounts()
 for _,name in ipairs(C.modules)do
  if not counts[name]then problems[#problems+1]='modulo sem caso: '..name end
 end
 return {ok=#problems==0,problems=problems,cases=#C.cases,modules=#C.modules}
end
function C.describe()
 local counts=C.moduleCounts()
 local lines={string.format('Corpus de conformidade | %d casos | %d modulos',#C.cases,#C.modules)}
 for _,name in ipairs(C.modules)do lines[#lines+1]=string.format('  %-18s %d caso(s)',name,counts[name]or 0)end
 return table.concat(lines,'\n')
end
return C
