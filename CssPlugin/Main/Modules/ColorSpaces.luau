local S={VERSION=1}
local abs,sign=math.abs,math.sign
local function mul(m,v)return {m[1]*v[1]+m[2]*v[2]+m[3]*v[3],m[4]*v[1]+m[5]*v[2]+m[6]*v[3],m[7]*v[1]+m[8]*v[2]+m[9]*v[3]}end
local function map(v,f)return {f(v[1]),f(v[2]),f(v[3])}end
local function inverse(m)
 local a,b,c,d,e,f,g,h,i=table.unpack(m);local det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
 return {(e*i-f*h)/det,(c*h-b*i)/det,(b*f-c*e)/det,(f*g-d*i)/det,(a*i-c*g)/det,(c*d-a*f)/det,(d*h-e*g)/det,(b*g-a*h)/det,(a*e-b*d)/det}
end
local function srgbDecode(x)local a=abs(x);return sign(x)*(a<=0.04045 and a/12.92 or ((a+0.055)/1.055)^2.4)end
local function srgbEncode(x)local a=abs(x);return sign(x)*(a<=0.0031308 and a*12.92 or 1.055*a^(1/2.4)-0.055)end
local identity=function(x)return x end
local matrices={
 ['srgb']={0.4123907992659595,0.357584339383878,0.1804807884018343,0.2126390058715104,0.715168678767756,0.0721923153607337,0.0193308187155918,0.1191947797946259,0.9505321522496607},
 ['display-p3']={0.4865709486482162,0.2656676931690931,0.1982172852343625,0.2289745640697488,0.6917385218365064,0.079286914093745,0,0.0451133818589026,1.043944368900976},
 ['a98-rgb']={0.5766690429101305,0.1855582379065463,0.1882286462349947,0.2973449752505361,0.6273635662554661,0.0752914584939979,0.0270313613864123,0.0706888525358272,0.9913375368376388},
 ['prophoto-rgb']={0.7977666449006423,0.1351812974005331,0.0313477341283922,0.2880748288194013,0.711835234241873,0.0000899369387256,0,0,0.8251046025104601},
 ['rec2020']={0.6369580483012914,0.1446169035862083,0.1688809751641721,0.2627002120112671,0.6779980715188708,0.059301716469862,0,0.0280726930490874,1.060985057710791},
}
matrices['srgb-linear']=matrices.srgb
local inverses={};for k,m in pairs(matrices)do inverses[k]=inverse(m)end
local d65to50={1.0479297925449969,0.0229468706016097,-0.0501922662892052,0.0296278087700558,0.9904344267538799,-0.0170737990634188,-0.0092430406462045,0.0150551914902982,0.7518742814281371}
local d50to65=inverse(d65to50)
local decode={srgb=srgbDecode,['display-p3']=srgbDecode,['srgb-linear']=identity,
 ['a98-rgb']=function(x)return sign(x)*abs(x)^(563/256)end,
 ['prophoto-rgb']=function(x)return abs(x)<=16/512 and x/16 or sign(x)*abs(x)^1.8 end,
 ['rec2020']=function(x)local a=abs(x);return sign(x)*(a<0.0812428582986315 and a/4.5 or ((a+0.09929682680944)/1.09929682680944)^(1/0.45))end}
local encode={srgb=srgbEncode,['display-p3']=srgbEncode,['srgb-linear']=identity,
 ['a98-rgb']=function(x)return sign(x)*abs(x)^(256/563)end,
 ['prophoto-rgb']=function(x)return abs(x)<=1/512 and x*16 or sign(x)*abs(x)^(1/1.8)end,
 ['rec2020']=function(x)local a=abs(x);return sign(x)*(a<0.018053968510807 and a*4.5 or 1.09929682680944*a^0.45-0.09929682680944)end}
local white50={0.9642956764295677,1,0.8251046025104601}
local epsilon,kappa=216/24389,24389/27
local function labToXYZ(v)
 local fy=(v[1]+16)/116;local fx=fy+v[2]/500;local fz=fy-v[3]/200
 local function f(t)return t^3>epsilon and t^3 or (116*t-16)/kappa end
 return {f(fx)*white50[1],f(fy),f(fz)*white50[3]}
end
local function xyzToLab(v)
 local function f(t)return t>epsilon and t^(1/3)or(kappa*t+16)/116 end
 local x,y,z=f(v[1]/white50[1]),f(v[2]),f(v[3]/white50[3])
 return {116*y-16,500*(x-y),200*(y-z)}
end
local function polar(v)return {v[1],math.sqrt(v[2]^2+v[3]^2),math.deg(math.atan2(v[3],v[2]))%360}end
local function rectangular(v)local h=math.rad(v[3]);return {v[1],v[2]*math.cos(h),v[2]*math.sin(h)}end
local function cube(x)return sign(x)*abs(x)^(1/3)end
local function linearToOK(v)
 local l=cube(.4122214708*v[1]+.5363325363*v[2]+.0514459929*v[3])
 local m=cube(.2119034982*v[1]+.6806995451*v[2]+.1073969566*v[3])
 local s=cube(.0883024619*v[1]+.2817188376*v[2]+.6299787005*v[3])
 return {.2104542553*l+.793617785*m-.0040720468*s,1.9779984951*l-2.428592205*m+.4505937099*s,.0259040371*l+.7827717662*m-.808675766*s}
end
local function okToLinear(v)
 local l=(v[1]+.3963377774*v[2]+.2158037573*v[3])^3
 local m=(v[1]-.1055613458*v[2]-.0638541728*v[3])^3
 local s=(v[1]-.0894841775*v[2]-1.291485548*v[3])^3
 return {4.0767416621*l-3.3077115913*m+.2309699292*s,-1.2684380046*l+2.6097574011*m-.3413193965*s,-.0041960863*l-.7034186147*m+1.707614701*s}
end
local function hslToRGB(v)
 local h,s,l=v[1]%360,v[2]/100,v[3]/100;local a=s*math.min(l,1-l)
 local function f(n)local k=(n+h/30)%12;return l-a*math.max(-1,math.min(k-3,9-k,1))end
 return {f(0),f(8),f(4)}
end
local function rgbToHSL(v)
 local r,g,b=table.unpack(v);local hi,lo=math.max(r,g,b),math.min(r,g,b);local d=hi-lo;local l=(hi+lo)/2;local h,s=0,0
 if d>1e-12 then
  s=(l==0 or l==1)and 0 or d/(1-abs(2*l-1))
  if hi==r then h=(g-b)/d%6 elseif hi==g then h=(b-r)/d+2 else h=(r-g)/d+4 end;h*=60
  if s<0 then h=(h+180)%360;s=-s end
 end
 return {h,s*100,l*100}
end
local function hwbToRGB(v)
 local w,b=v[2]/100,v[3]/100
 if w+b>=1 then return {w/(w+b),w/(w+b),w/(w+b)}end
 local rgb=hslToRGB({v[1],100,50});return {rgb[1]*(1-w-b)+w,rgb[2]*(1-w-b)+w,rgb[3]*(1-w-b)+w}
end
local function rgbToHWB(v)return {rgbToHSL(v)[1],math.min(table.unpack(v))*100,(1-math.max(table.unpack(v)))*100}end
S.hue={hsl=1,hwb=1,lch=3,oklch=3}
S.spaces={srgb=true,['srgb-linear']=true,['display-p3']=true,['a98-rgb']=true,['prophoto-rgb']=true,rec2020=true,xyz=true,['xyz-d50']=true,['xyz-d65']=true,lab=true,lch=true,oklab=true,oklch=true,hsl=true,hwb=true}
function S.toXYZ(space,v)
 if space=='xyz'or space=='xyz-d65'then return table.clone(v)end
 if space=='xyz-d50'then return mul(d50to65,v)end
 if space=='lab'or space=='lch'then return mul(d50to65,labToXYZ(space=='lch'and rectangular(v)or v))end
 if space=='oklab'or space=='oklch'then return mul(matrices.srgb,okToLinear(space=='oklch'and rectangular(v)or v))end
 if space=='hsl'or space=='hwb'then v=space=='hsl'and hslToRGB(v)or hwbToRGB(v);space='srgb'end
 assert(matrices[space],'Espaço de cor não suportado: '..tostring(space))
 local xyz=mul(matrices[space],map(v,decode[space]));return space=='prophoto-rgb'and mul(d50to65,xyz)or xyz
end
function S.fromXYZ(space,v)
 if space=='xyz'or space=='xyz-d65'then return table.clone(v)end
 if space=='xyz-d50'then return mul(d65to50,v)end
 if space=='lab'or space=='lch'then local lab=xyzToLab(mul(d65to50,v));return space=='lch'and polar(lab)or lab end
 if space=='oklab'or space=='oklch'then local lab=linearToOK(mul(inverses.srgb,v));return space=='oklch'and polar(lab)or lab end
 if space=='hsl'or space=='hwb'then local rgb=map(mul(inverses.srgb,v),srgbEncode);return space=='hsl'and rgbToHSL(rgb)or rgbToHWB(rgb)end
 assert(inverses[space],'Espaço de cor não suportado: '..tostring(space))
 return map(mul(inverses[space],space=='prophoto-rgb'and mul(d65to50,v)or v),encode[space])
end
function S.convert(v,from,to)if from==to or (from=='xyz'and to=='xyz-d65')or(from=='xyz-d65'and to=='xyz')then return table.clone(v)end;return S.fromXYZ(to,S.toXYZ(from,v))end
local groups={lab={'L','a','b'},oklab={'L','a','b'},lch={'L','C','H'},oklch={'L','C','H'},hsl={'H','C','L'},hwb={'H','W','B'}}
function S.groups(space)return groups[space]or{'RX','GY','BZ'}end
function S.powerless(space,v)
 if space=='hsl'then return abs(v[2])<1e-7 or v[3]<=0 or v[3]>=100 end
 if space=='hwb'then return v[2]+v[3]>=100-1e-7 end
 if space=='lch'then return abs(v[2])<1e-4 end
 if space=='oklch'then return abs(v[2])<1e-7 end
 return false
end
function S.native(color)
 local rgb=S.convert(color.v,color.space,'srgb')
 return Color3.new(math.clamp(rgb[1],0,1),math.clamp(rgb[2],0,1),math.clamp(rgb[3],0,1)),math.clamp(color.alpha or 0,0,1)
end
S.mul=mul
return S
