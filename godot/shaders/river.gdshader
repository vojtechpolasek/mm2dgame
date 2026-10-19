shader_type canvas_item;

// Řeka (river.gd): pás podél křivky. UV.x je vzdálenost od pramene v pixelech, UV.y jde
// napříč od 0 do 1. Barva vrcholu nese poměr délky (r) a šířku pásu (g, poměr k ústí).
// Uprostřed hlubší voda, k okrajům mělčina a pruh mokrého písku, kraj se rozplyne do
// trávy. Vlnky tečou k ústí. V ústí se pás ztratí pod hladinou jezera, u pramene se
// pomalu objeví. Barvy jsou jako u jezer v surfaces.json.

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

varying float along_share;
varying float width_share;

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
	along_share = COLOR.r;
	width_share = COLOR.g;
}

void fragment() {
	float width = max(width_share * 128.0, 1.0);
	float across = abs(UV.y * 2.0 - 1.0);
	// Kraj břehu kolísá podle šumu, ať není jako pravítko.
	float wobble = (noise(vec2(UV.x / 26.0, UV.y > 0.5 ? 3.0 : 9.0)) - 0.5) * 0.12;
	float edge = across + wobble;
	if (edge > 1.0) {
		discard;
	}
	// Proud: protáhlé vlnky jedou podél řeky k ústí.
	vec2 stream = vec2((UV.x - TIME * flow) / 30.0, UV.y * width / 12.0);
	float ripple = noise(stream) * 0.6 + noise(stream * vec2(2.3, 1.7) + 11.0) * 0.4;
	float depth = 1.0 - smoothstep(0.0, water_share, edge);
	vec3 water = mix(water_color, deep_color, depth * 0.8);
	water = mix(water, shallow_color, smoothstep(water_share * 0.6, water_share, edge) * 0.45);
	water = mix(water, highlight_color, smoothstep(0.62, 0.85, ripple) * 0.55 * (0.4 + 0.6 * depth));
	// Břeh: mokrý písek u vody, suchý dál, kraj se rozplyne.
	float bank = smoothstep(water_share - 0.04, water_share + 0.04, edge);
	vec3 sand = mix(sand_wet_color, sand_color, smoothstep(water_share, 1.0, edge));
	vec3 color = mix(water, sand, bank);
	float alpha = 1.0 - smoothstep(0.86, 1.0, edge);
	// U pramene se řeka objeví, v ústí se ztratí pod hladinou jezera.
	alpha *= smoothstep(0.0, 0.03, along_share);
	alpha *= 1.0 - smoothstep(0.93, 1.0, along_share);
	COLOR = vec4(color, alpha);
}
