shader_type canvas_item;

// Řeka (river.gd): pásy ramen podél křivek. UV.x je vzdálenost od pramene ramene v pixelech,
// UV.y jde napříč od 0 do 1. Barva vrcholu nese šířku pásu (g, podíl WIDTH_MAX) a hlavní
// řeku (b = 1). Uprostřed hlubší voda, k okrajům mělčina a pruh mokrého písku, kraj se
// rozplyne do trávy. Vlnky tečou k ústí. Barvy jsou jako u jezer v surfaces.json.
// Kreslí se dvakrát: part 0 jsou písčité břehy všech ramen, part 1 jejich voda. Voda pak
// v soutoku překryje břeh druhého ramene. Rameno se objeví na prvních start_fade px pod
// tůňkou prameniště, v ústí se ztrácí jen hlavní řeka.
// water_mask je voda čtverce po dlaždicích. Nad jezerem se písčitý břeh nekreslí a voda
// řeky přejde do mělčiny a kousek za břehem zmizí. Ústí tak navazuje přímo na břeh.

uniform vec3 deep_color : source_color = vec3(0.141, 0.369, 0.471);
uniform vec3 water_color : source_color = vec3(0.173, 0.431, 0.541);
uniform vec3 highlight_color : source_color = vec3(0.290, 0.557, 0.667);
uniform vec3 shallow_color : source_color = vec3(0.494, 0.749, 0.855);
uniform vec3 sand_color : source_color = vec3(0.769, 0.643, 0.376);
uniform vec3 sand_wet_color : source_color = vec3(0.651, 0.518, 0.282);
// Rychlost proudu v pixelech za sekundu.
uniform float flow = 34.0;
// Podíl šířky, který je voda. Zbytek je břeh.
uniform float water_share = 0.78;
// 0 písčité břehy, 1 voda.
uniform int part = 1;
uniform float start_fade = 16.0;
// Šířka, ke které je g barvy vrcholu (river.gd WIDTH_MAX).
const float WIDTH_MAX = 192.0;
uniform sampler2D water_mask : filter_linear, repeat_disable, hint_default_black;
// Texelů masky na stranu a kde texel leží: 0.5 na rohu dlaždice, 0 na jejím středu.
uniform float mask_size = 129.0;
uniform float mask_shift = 0.5;
const float TILE_PX = 64.0;
// Délka osy v px. Posledních end_fade px se řeka ztratí, i kdyby jezero nezačalo.
uniform float length_px = 100000.0;
uniform float end_fade = 48.0;

varying float width_share;
varying float main_line;
varying vec2 local;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x), mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	width_share = COLOR.g;
	main_line = COLOR.b;
	local = VERTEX;
}

void fragment() {
	float width = max(width_share * WIDTH_MAX, 1.0);
	float across = abs(UV.y * 2.0 - 1.0);
	// Kraj břehu kolísá podle šumu, ať není jako pravítko.
	float wobble = (noise(vec2(UV.x / 26.0, UV.y > 0.5 ? 3.0 : 9.0)) - 0.5) * 0.12;
	float edge = across + wobble;
	if (edge > 1.0) {
		discard;
	}
	float bank = smoothstep(water_share - 0.04, water_share + 0.04, edge);
	float alpha = 1.0 - smoothstep(0.86, 1.0, edge);
	alpha *= smoothstep(0.0, start_fade, UV.x);
	if (main_line > 0.5) {
		alpha *= smoothstep(0.0, end_fade, length_px - UV.x);
	}
	// Jezero pod řekou: maska po dlaždicích má rovné hrany, proto je zprůměrovaná z pěti
	// vzorků a okraj zvlní šum. 0.5 je zhruba břeh. Písek se ztratí kolem břehu, voda řeky
	// přejde do barvy jezera a asi do dlaždice za břehem zmizí.
	vec2 at = (local / TILE_PX + mask_shift) / mask_size;
	float tile = 0.6 / mask_size;
	float lake = texture(water_mask, at).r * 0.4;
	lake += texture(water_mask, at + vec2(tile, 0.0)).r * 0.15;
	lake += texture(water_mask, at - vec2(tile, 0.0)).r * 0.15;
	lake += texture(water_mask, at + vec2(0.0, tile)).r * 0.15;
	lake += texture(water_mask, at - vec2(0.0, tile)).r * 0.15;
	lake += (noise(local / 40.0) - 0.5) * 0.3;
	if (part == 0) {
		// Písek přes celou šířku: mokrý u vody, suchý dál. Voda ho z druhé vrstvy překryje.
		vec3 sand = mix(sand_wet_color, sand_color, smoothstep(water_share, 1.0, edge));
		alpha *= 1.0 - smoothstep(0.25, 0.55, lake);
		COLOR = vec4(sand, alpha);
	} else {
		// Proud: protáhlé vlnky jedou podél řeky k ústí.
		vec2 stream = vec2((UV.x - TIME * flow) / 30.0, UV.y * width / 12.0);
		float ripple = noise(stream) * 0.6 + noise(stream * vec2(2.3, 1.7) + 11.0) * 0.4;
		float depth = 1.0 - smoothstep(0.0, water_share, edge);
		vec3 water = mix(water_color, deep_color, depth * 0.8);
		water = mix(water, shallow_color, smoothstep(water_share * 0.6, water_share, edge) * 0.45);
		water = mix(water, highlight_color, smoothstep(0.62, 0.85, ripple) * 0.55 * (0.4 + 0.6 * depth));
		water = mix(water, water_color, smoothstep(0.3, 0.75, lake));
		alpha *= (1.0 - bank) * (1.0 - smoothstep(0.45, 0.9, lake));
		COLOR = vec4(water, alpha);
	}
}
