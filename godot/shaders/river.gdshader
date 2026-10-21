shader_type canvas_item;

// Řeka (river.gd): pásy ramen podél křivek. UV.x je proud v pixelech (roste po proudu a na
// kraji čtverce navazuje na souseda), UV.y jde napříč od 0 do 1. Barva vrcholu nese
// průhlednost konců (r: rameno se objeví pod tůňkou prameniště, řeka se ztratí v ústí)
// a šířku pásu (g, podíl WIDTH_MAX).
// Vypadá jako jezero: barvy, textura vody, vlny a odlesky jsou z terrain_common a parametry
// jí předá katalog terénu (River.spawn). Navíc teče: odlesky a pěna u břehu jedou po proudu,
// stojaté vlny jezera jsou slabší. Uprostřed hlubší voda, k okrajům mělčina, pěna a pruh
// mokrého písku, kraj se rozplyne do trávy.
// Kreslí se dvakrát: part 0 jsou písčité břehy všech ramen, part 1 jejich voda. Voda pak
// v soutoku překryje břeh druhého ramene.
// water_mask je voda čtverce po dlaždicích. Nad jezerem se písčitý břeh nekreslí a voda
// řeky přejde do jezera a kousek za břehem zmizí. Ústí tak navazuje přímo na břeh.

#include "res://shaders/terrain_common.gdshaderinc"

// Rychlost proudu v pixelech za sekundu.
uniform float flow = 34.0;
// Podíl šířky, který je voda. Zbytek je břeh.
uniform float water_part = 0.78;
// Stojaté vlny jezera jsou na řece slabší o tento podíl.
uniform float still_waves = 0.5;
// 0 písčité břehy, 1 voda.
uniform int part = 1;
// Šířka, ke které je g barvy vrcholu (river.gd WIDTH_MAX).
const float WIDTH_MAX = 192.0;
uniform sampler2D water_mask : filter_linear, repeat_disable, hint_default_black;
// Texelů masky na stranu a kde texel leží: 0.5 na rohu dlaždice, 0 na jejím středu.
uniform float mask_size = 129.0;
uniform float mask_shift = 0.5;
varying float width_share;
varying float fade;
varying vec2 local;
varying vec2 world;

void vertex() {
	width_share = COLOR.g;
	fade = COLOR.r;
	local = VERTEX;
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float width = max(width_share * WIDTH_MAX, 1.0);
	float across = abs(UV.y * 2.0 - 1.0);
	// Kraj břehu kolísá podle šumu, ať není jako pravítko.
	float wobble = (value_noise(vec2(UV.x / 26.0, UV.y > 0.5 ? 3.0 : 9.0)) - 0.5) * 0.12;
	float edge = across + wobble;
	if (edge > 1.0) {
		discard;
	}
	float bank = smoothstep(water_part - 0.04, water_part + 0.04, edge);
	float alpha = 1.0 - smoothstep(0.86, 1.0, edge);
	alpha *= fade;
	// Jezero pod řekou: maska po dlaždicích má rovné hrany, proto je zprůměrovaná z pěti
	// vzorků a okraj zvlní šum. 0.5 je zhruba břeh. Písek se ztratí kolem břehu, voda řeky
	// přejde do jezera a asi do dlaždice za břehem zmizí.
	vec2 at = (local / tile_size + mask_shift) / mask_size;
	float step_uv = 0.6 / mask_size;
	float lake = texture(water_mask, at).r * 0.4;
	lake += texture(water_mask, at + vec2(step_uv, 0.0)).r * 0.15;
	lake += texture(water_mask, at - vec2(step_uv, 0.0)).r * 0.15;
	lake += texture(water_mask, at + vec2(0.0, step_uv)).r * 0.15;
	lake += texture(water_mask, at - vec2(0.0, step_uv)).r * 0.15;
	lake += (value_noise(local / 40.0) - 0.5) * 0.3;
	if (part == 0) {
		// Písek přes celou šířku: mokrý u vody, suchý dál. Voda ho z druhé vrstvy překryje.
		vec3 sand = mix(sand_wet_color, sand_color, smoothstep(water_part, 1.0, edge));
		alpha *= 1.0 - smoothstep(0.25, 0.55, lake);
		COLOR = vec4(sand, alpha);
	} else {
		float depth = 1.0 - smoothstep(0.0, water_part, edge);
		// Textura vody jako u jezera, ve světě, ať navazuje přes kraj čtverce i do ústí.
		float lod = max(log2(max(length(dFdx(world)), length(dFdy(world)))), 0.0);
		vec3 surface = water_texture(world, lod);
		vec3 water = mix(surface, deep_color, depth * 0.3);
		water = mix(water, shallow_color, smoothstep(water_part * 0.55, water_part, edge) * shallow_strength);
		// Stojaté vlny jezera, slabší.
		float height = wave_height(wave_phases(world));
		water = mix(water, wave_band(height), wave_tint * still_waves * depth);
		// Proud: odlesky protažené podél řeky jedou k ústí.
		vec2 stream = vec2(UV.x - TIME * flow, UV.y * width);
		water = mix(water, highlight_color, water_glints(stream) * glint_strength * 1.3 * (0.4 + 0.6 * depth));
		// Pěna u břehu jako na jezeře, krajky jedou s proudem.
		float shore = smoothstep(water_part - 0.2, water_part - 0.05, edge);
		vec2 foam_pos = floor(vec2((UV.x - TIME * flow) * 0.5, UV.y * width));
		float lace = smoothstep(0.22, 0.78, value_noise(foam_pos * 0.11) * 0.6 + value_noise(foam_pos * 0.35) * 0.4);
		vec3 foam_color = mix(highlight_color, vec3(0.92, 0.97, 0.98), 0.62);
		water = mix(water, foam_color, clamp(shore * mix(0.2, 0.8, lace), 0.0, 0.28));
		// Nad jezerem přejde do vody jezera.
		water = mix(water, mix(surface, wave_band(height), wave_tint), smoothstep(0.3, 0.75, lake));
		alpha *= (1.0 - bank) * (1.0 - smoothstep(0.45, 0.9, lake));
		COLOR = vec4(water, alpha);
	}
}
