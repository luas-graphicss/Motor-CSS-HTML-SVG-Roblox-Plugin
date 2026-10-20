return {
{
 name="t01_box_model",
 code=[=[<!DOCTYPE html>
<html><head><style>
#outer{width:400px;height:200px;padding:10px;border:5px solid #000;box-sizing:border-box;background:#f0f0f0}
#inner{width:50%;height:100px;margin:10px 0 0 20px;background:rgb(200,30,30)}
#sib{width:100px;height:40px;margin-top:30px;background:#0a0}
</style></head>
<body><div id="outer"><div id="inner"></div></div><div id="sib"></div></body></html>]=],
 result="OK",
},
{
 name="t02_flex_basics",
 code=[=[<!DOCTYPE html>
<html><head><style>
body{margin:0}
#row{display:flex;width:600px;height:100px;gap:10px;padding:5px;background:#eee}
#a{flex:1;background:#c33}
#b{flex:2;background:#3c3}
#c{width:80px;flex:none;background:#33c}
#col{display:flex;flex-direction:column;width:200px;height:300px;justify-content:space-between;align-items:center}
#d{width:50px;height:40px;background:#f90}
#e{width:120px;height:60px;background:#09f}
#f{align-self:flex-end;width:30px;height:30px;background:#909}
#wrap{display:flex;flex-wrap:wrap;width:250px;align-content:flex-start}
#wrap div{width:100px;height:40px;margin:5px;background:#666}
</style></head>
<body>
<div id="row"><div id="a"></div><div id="b"></div><div id="c"></div></div>
<div id="col"><div id="d"></div><div id="e"></div><div id="f"></div></div>
<div id="wrap"><div id="w1"></div><div id="w2"></div><div id="w3"></div><div id="w4"></div><div id="w5"></div></div>
</body></html>]=],
 result="OK",
},
{
 name="t03_grid_basics",
 code=[=[<!DOCTYPE html>
<html><head><style>
body{margin:0}
#g{display:grid;grid-template-columns:100px 1fr 2fr;grid-template-rows:50px auto;gap:8px 12px;width:600px;background:#ddd;padding:4px}
#g1{background:#a00;height:30px}
#g2{background:#0a0;grid-column:2/4}
#g3{background:#00a;grid-row:2;grid-column:1/3;height:70px}
#g4{background:#aa0}
#ar{display:grid;grid-template-areas:"h h" "s m" "f f";grid-template-columns:120px 1fr;grid-template-rows:40px 100px 30px;width:400px}
#h{grid-area:h;background:#123}
#s{grid-area:s;background:#456}
#m{grid-area:m;background:#789}
#ft{grid-area:f;background:#abc}
#auto{display:grid;grid-template-columns:repeat(auto-fill,minmax(90px,1fr));width:380px;gap:5px}
#auto div{height:20px;background:#333}
</style></head>
<body>
<div id="g"><div id="g1"></div><div id="g2"></div><div id="g3"></div><div id="g4"></div></div>
<div id="ar"><div id="h"></div><div id="s"></div><div id="m"></div><div id="ft"></div></div>
<div id="auto"><div id="au1"></div><div id="au2"></div><div id="au3"></div><div id="au4"></div><div id="au5"></div><div id="au6"></div></div>
</body></html>]=],
 result="OK",
},
{
 name="t04_positioning",
 code=[=[<!DOCTYPE html>
<html><head><style>
body{margin:0}
#rel{position:relative;width:400px;height:300px;margin:20px;background:#eee}
#abs1{position:absolute;top:10px;left:20px;width:50px;height:50px;background:#c00}
#abs2{position:absolute;right:0;bottom:0;width:80px;height:40px;background:#0c0}
#abs3{position:absolute;inset:100px 50px 50px 100px;background:#00c}
#shift{position:relative;top:15px;left:25px;width:60px;height:60px;background:#f0f}
#fix{position:fixed;top:5px;right:5px;width:40px;height:40px;background:#0ff}
#stick{position:sticky;top:0;width:100px;height:20px;background:#ff0}
#neg{position:absolute;top:-10px;left:-10px;width:30px;height:30px;background:#000}
#zz{position:absolute;top:0;left:0;width:100px;height:100px;background:#888;z-index:5}
</style></head>
<body>
<div id="fix"></div>
<div id="rel"><div id="abs1"></div><div id="abs2"></div><div id="abs3"></div><div id="shift"></div><div id="neg"></div><div id="zz"></div></div>
<div id="stick"></div>
</body></html>]=],
 result="OK",
},
{
 name="t05_text_layout",
 code=[=[<!DOCTYPE html>
<!-- props: font-size,font-weight,line-height,text-align,color,display,white-space -->
<!-- tol: 2 -->
<html><head><style>
body{margin:0;font-family:Code;font-size:16px;line-height:20px}
#p1{width:300px;font-size:16px;line-height:20px}
#h1{font-size:32px;line-height:40px;margin:0;font-weight:700}
#c{text-align:center;width:300px;line-height:24px}
#r{text-align:right;width:300px;line-height:24px}
#pre{white-space:pre;line-height:18px;font-size:14px}
#nowrap{white-space:nowrap;width:100px;overflow:hidden;line-height:20px}
#lh{line-height:2;font-size:20px;width:200px}
#sp{display:inline-block;width:80px;height:30px;background:#ccc}
#up{text-transform:uppercase;letter-spacing:2px;line-height:20px}
</style></head>
<body>
<h1 id="h1">Titulo Grande</h1>
<p id="p1">Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua</p>
<div id="c">Centro</div>
<div id="r">Direita</div>
<pre id="pre">linha 1
  linha 2 indentada
linha 3</pre>
<div id="nowrap">texto longo sem quebra aqui</div>
<div id="lh">Altura de linha dupla em duas linhas aqui</div>
<div><span id="sp"></span> depois</div>
<div id="up">maiusculas</div>
</body></html>]=],
 result="OK",
},
{
 name="t06_colors_modern",
 code=[=[<!DOCTYPE html>
<!-- props: background-color,color,opacity,border-top-color -->
<html><head><style>
body{margin:0}
div{width:40px;height:20px}
#c1{background:#ff8800}
#c2{background:#f80c}
#c3{background:rgb(10 20 30 / 50%)}
#c4{background:hsl(120 50% 40%)}
#c5{background:hsla(200,80%,50%,0.25)}
#c6{background:hwb(60 10% 20%)}
#c7{background:lab(50% 40 -30)}
#c8{background:lch(60% 50 200)}
#c9{background:oklab(0.6 0.1 -0.1)}
#c10{background:oklch(70% 0.15 150)}
#c11{background:color(display-p3 1 0 0)}
#c12{background:color-mix(in srgb,red 30%,blue)}
#c13{background:rebeccapurple}
#c14{background:transparent;border-top:3px solid currentColor;color:teal}
#c15{background:color(srgb 0.2 0.4 0.6)}
#c16{background:rgb(300 -20 128)}
#c17{background-color:hsl(400deg 120% 50%)}
#c18{background:color-mix(in oklch,#ff0000,#0000ff 25%)}
#c19{opacity:0.35;background:#000}
#c20{background:color(srgb-linear 0.5 0.5 0.5)}
</style></head>
<body>
<div id="c1"></div><div id="c2"></div><div id="c3"></div><div id="c4"></div><div id="c5"></div><div id="c6"></div><div id="c7"></div><div id="c8"></div><div id="c9"></div><div id="c10"></div><div id="c11"></div><div id="c12"></div><div id="c13"></div><div id="c14"></div><div id="c15"></div><div id="c16"></div><div id="c17"></div><div id="c18"></div><div id="c19"></div><div id="c20"></div>
</body></html>]=],
 result="OK",
},
{
 name="t07_transforms",
 code=[=[<!DOCTYPE html>
<!-- props: opacity -->
<html><head><style>
body{margin:0}
.b{width:100px;height:50px;background:#c33;margin:30px}
#t1{transform:translate(20px,10px)}
#t2{transform:rotate(45deg)}
#t3{transform:scale(1.5,0.5)}
#t4{transform:translateX(10%) rotate(10deg) scale(1.2)}
#t5{transform:skew(10deg,5deg)}
#t6{transform:matrix(1,0.2,0.3,1,15,5)}
#t7{transform:rotate(90deg);transform-origin:0 0}
#t8{transform:translate(-50%,-50%)}
#t9{transform:rotateX(60deg)}
#t10{transform:perspective(200px) rotateY(45deg)}
</style></head>
<body>
<div class="b" id="t1"></div><div class="b" id="t2"></div><div class="b" id="t3"></div><div class="b" id="t4"></div><div class="b" id="t5"></div><div class="b" id="t6"></div><div class="b" id="t7"></div><div class="b" id="t8"></div><div class="b" id="t9"></div><div class="b" id="t10"></div>
</body></html>]=],
 result="OK",
},
{
 name="t08_pre_lines",
 code=[=[<!DOCTYPE html>
<!-- props: line-height,font-size,white-space -->
<html><head><style>
body{margin:0;font-family:Code;font-size:14px;line-height:18px}
pre{margin:0}
</style></head>
<body>
<pre id="p1">a
b
c</pre>
<pre id="p2">
lead newline stripped
x</pre>
<pre id="p3">tab	here</pre>
<div id="w" style="white-space:pre-wrap;width:100px">aaaa bbbb cccc dddd eeee</div>
<div id="pl" style="white-space:pre-line;width:300px">um
dois   tres</div>
<div id="bs" style="white-space:break-spaces;width:60px">a          b</div>
</body></html>]=],
 result="OK",
},
}
