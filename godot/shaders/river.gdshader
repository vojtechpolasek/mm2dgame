shader_type canvas_item;

// Řeka (river.gd): pásy ramen podél křivek. UV.x je proud v pixelech (roste po proudu a na
// kraji čtverce navazuje na souseda), UV.y je vzdálenost od osy napříč v pixelech (vlevo
// záporná). Barva vrcholu nese průhlednost konců (r: rameno se objeví pod tůňkou
// prameniště, řeka se ztratí v ústí), šířku ramene (g, podíl WIDTH_MAX) a zakřivení
// (b: 0.5 rovně, víc ohyb ke středu vlevo, míň vpravo). CUSTOM0.xy je směr napříč, kterým
// UV.y roste, z a w kam pás sahá vlevo a vpravo v px. Pás je o svah širší než rameno, na
// vnitřní straně ostré zákruty užší (síť se nepřehne) a svah se pak vejde dovnitř.
//
// Hladina je pod okolním terénem, k vodě vede svah (břeh). Břeh je nepravidelný: šířka se po
// proudu mění (šum ve dvou měřítkách, každá strana jiný), čára hladiny i horní hrana jsou
// roztřepené. Na vnitřní straně zákruty je široká pozvolná náplava, na vnější je břeh vymletý,
// úzký a tmavší. Svah je podle terénu pod ním (corner_map čtverce, bank v surfaces.json):
// nahoře je terén sám, níž jeho půda (bank_soil, třeba hlína pod trávou, písek v poušti),
// místy štěrk (bank_gravel), bahno (bank_mud) a kameny, náplava z bank_bar. Kde se terén
// mění, mění se plynule i svah. Dole je vlhký a tmavý, přes horní hranu přerůstá terén.
// Stín břehu: posun stínu je global sun_shadow (DayNight), síla shadow_opacity (Shadows).
// Místo je ve stínu, když je směrem ke slunci terén výš než ono.
// Hladina je pod terénem (water_parallax): voda se kreslí podle tvaru koryta v bodě
// posunutém od středu záběru, svah je na místě. Voda nesahá za horní hranu svahu.
//
// Voda vypadá jako jezero: barvy, textura vody, vlny a odlesky jsou z terrain_common
// a parametry jí předá katalog terénu (River.spawn). Navíc teče: odlesky a pěna u břehu jedou
// po proudu, stojaté vlny jezera jsou slabší. Uprostřed hlubší, u břehů mělčina, nad
// náplavou široká.
// Kreslí se dvakrát: part 0 jsou břehy všech ramen, part 1 jejich voda. Voda pak v soutoku
// překryje břeh druhého ramene.
// water_mask je voda čtverce po dlaždicích. Nad jezerem se břeh nekreslí a voda řeky přejde
// do jezera a kousek za břehem zmizí. Ústí tak navazuje přímo na břeh.

#include "res://shaders/terrain_common.gdshaderinc"

// Rychlost proudu v pixelech za sekundu.
uniform float flow = 34.0;
// Podíl šířky ramene, který je voda (river.gd WATER_SHARE). Kolem je svah.
uniform float water_part = 0.78;
// Stojaté vlny jezera jsou na řece slabší o tento podíl.
uniform float still_waves = 0.5;
// 0 břehy, 1 voda.
uniform int part = 1;
// ground_on 0: mapa terénu chybí, svah je jen barva.
uniform float ground_on = 0.0;
global uniform vec2 sun_shadow;
global uniform float shadow_opacity;
global uniform vec2 camera_position;
global uniform float camera_zoom;
// Šířka, ke které je g barvy vrcholu (river.gd WIDTH_MAX), a pás svahu (river.gd BANK_PAD,
// BANK_REACH).
const float WIDTH_MAX = 192.0;
const float BANK_PAD = 40.0;
const float BANK_REACH = 1.6;
uniform sampler2D water_mask : filter_linear, repeat_disable, hint_default_black;
// Texelů masky na stranu a kde texel leží: 0.5 na rohu dlaždice, 0 na jejím středu.
uniform float mask_size = 129.0;
uniform float mask_shift = 0.5;
varying float width_share;
varying float fade;
varying float bend;
varying vec2 across_dir;
varying vec2 strip;
varying vec2 local;
varying vec2 world;

void vertex() {
	width_share = COLOR.g;
	fade = COLOR.r;
	bend = COLOR.b * 2.0 - 1.0;
	across_dir = CUSTOM0.xy;
	strip = CUSTOM0.zw;
	local = VERTEX;
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Břeh jedné strany ramene v místě along (proud v px) a at (bod světa): x půl šířky vody v px,
// y šířka svahu v px, z vnitřní strana zákruty 0 až 1 (náplava), w vnější strana (vymletý
// břeh).
// Pomalé změny jdou po proudu, drobné podle světa: na vnitřní straně zákruty je proud
// stlačený a drobný šum by tam dělal paprsky.
vec4 bank_at(float width, float along, vec2 at, float signed_across, float jag) {
	float side = signed_across > 0.0 ? 1.0 : 0.0;
	// bend > 0: střed zakřivení je vlevo, tedy na straně záporného signed_across.
	float toward = signed_across > 0.0 ? -bend : bend;
	float inner = clamp(toward, 0.0, 1.0);
	float outer = clamp(-toward, 0.0, 1.0);
	float low = value_noise(vec2(along / 140.0, side * 7.3));
	float mid = value_noise(at / 38.0 + side * 37.0);
	float base = min(BANK_PAD, 10.0 + width * 0.4);
	float slope = base * (0.45 + 0.9 * low + 0.35 * (mid - 0.5)) * (1.0 + 1.3 * inner) * (1.0 - 0.5 * outer);
	slope = clamp(slope, 3.0, BANK_PAD * BANK_REACH - 6.0);
	float swell = value_noise(vec2(along / 90.0, side * 5.1 + 11.0));
	float water = width * 0.5 * water_part * (0.88 + 0.24 * swell) - inner * width * 0.1 + outer * width * 0.03;
	water += (jag - 0.5) * min(8.0, width * 0.15);
	water = max(water, 1.5);
	// Horní hrana (až 1.25 svahu) musí zůstat v pásu.
	float room = signed_across > 0.0 ? strip.y : strip.x;
	slope = clamp(min(slope, (room - water - 2.0) / 1.25), 3.0, BANK_PAD * BANK_REACH - 6.0);
	return vec4(water, slope, inner, outer);
}

// Podíl svahu: záporný ve vodě, 0 u hladiny, 1 na horní hraně, víc za ní.
float bank_rel(vec4 bank, float across) {
	return (across - bank.x) / bank.y;
}

// Výška terénu 0 (hladina) až 1 (horní hrana). Vymletý břeh strmě, náplava pozvolna.
float bank_height(vec4 bank, float rel) {
	return slope_height(rel, bank.z, bank.w);
}

// Šum čáry vody a hran v bodě světa.
float bank_jag(vec2 at) {
	return value_noise(at / 14.0) * 0.6 + value_noise(at / 40.0) * 0.4;
}

// Stín břehu v místě (along, at, signed_across) s výškou height: kus směrem ke slunci napříč
// ramenem je terén výš.
float bank_shadow(float width, float along, vec2 at, float signed_across, float jag, float height) {
	if (shadow_opacity <= 0.001 || dot(across_dir, across_dir) <= 0.0) {
		return 0.0;
	}
	float back = signed_across - dot(sun_shadow * BANK_SHADOW_DEPTH, normalize(across_dir));
	vec4 back_bank = bank_at(width, along, at, back, jag);
	float back_height = bank_height(back_bank, bank_rel(back_bank, abs(back)));
	return clamp((back_height - height) * 1.6, 0.0, 1.0) * shadow_opacity * BANK_SHADOW;
}

// Míra jezera pod řekou v bodě at (px ve čtverci). Maska po dlaždicích má rovné hrany, proto
// je zprůměrovaná z pěti vzorků a okraj zvlní šum. 0.5 je zhruba břeh.
float lake_under(vec2 at) {
	vec2 uv = (at / tile_size + mask_shift) / mask_size;
	float step_uv = 0.6 / mask_size;
	float lake = texture(water_mask, uv).r * 0.4;
	lake += texture(water_mask, uv + vec2(step_uv, 0.0)).r * 0.15;
	lake += texture(water_mask, uv - vec2(step_uv, 0.0)).r * 0.15;
	lake += texture(water_mask, uv + vec2(0.0, step_uv)).r * 0.15;
	lake += texture(water_mask, uv - vec2(0.0, step_uv)).r * 0.15;
	return lake + (value_noise(at / 40.0) - 0.5) * 0.3;
}

void fragment() {
	float width = max(width_share * WIDTH_MAX, 1.0);
	float signed_across = UV.y;
	float across = abs(signed_across);
	float jag = bank_jag(world);
	vec4 bank = bank_at(width, UV.x, world, signed_across, jag);
	float rel = bank_rel(bank, across);
	// Horní hrana roztřepená, přes ni přerůstají trsy trávy (je vidět terén pod řekou).
	float lip = bank_lip(world);
	float tufts = bank_tufts(world, jag, rel);
	float land_alpha = (1.0 - smoothstep(lip - 0.12, lip + 0.05, rel)) * (1.0 - tufts);
	if (land_alpha <= 0.0 && rel > 0.0) {
		discard;
	}
	float lod = max(log2(max(length(dFdx(world)), length(dFdy(world)))), 0.0);
	if (part == 0) {
		// Břeh se ztratí kolem břehu jezera.
		float lake = lake_under(local);
		float height = bank_height(bank, rel);
		float shadow = bank_shadow(width, UV.x, world, signed_across, jag, height);
		// Svah podle terénu (bank_slope), na vnitřní straně zákruty náplava.
		float side = signed_across > 0.0 ? 1.0 : 0.0;
		float bar = clamp(bank.z * 1.4, 0.0, 1.0) * smoothstep(0.3, 0.5, value_noise(world / 40.0) + 0.2);
		vec3 soil = EARTH;
		vec3 bar_color = sand_color;
		vec2 amounts = vec2(0.5);
		vec3 top = EARTH;
		if (ground_on > 0.5) {
			vec3 land;
			bank_ground(local, world, lod, bar > 0.0, soil, bar_color, amounts, land);
			vec2 uv;
			ivec2 cell = bank_cell(local, uv);
			float variant = round(texelFetch(variant_map, cell, 0).r * 255.0);
			float water_share;
			float shore_kind;
			evaluate(uv, variant, lod, texelFetch(corner_map, cell, 0), top, water_share, shore_kind);
		}
		vec3 color = bank_slope(soil, bar_color, amounts, top, world, lod, rel, height, bar, bank.w, side);
		color *= 1.0 - shadow;
		float alpha = land_alpha * fade * (1.0 - smoothstep(0.25, 0.55, lake));
		COLOR = vec4(color, alpha);
	} else {
		// Hladina pod terénem: tvar koryta v bodě hladiny, který je tady vidět (water_parallax).
		vec2 shift = water_parallax(world, camera_position, camera_zoom);
		vec2 along_dir = vec2(across_dir.y, -across_dir.x);
		float ground_rel = rel;
		float ground_lip = lip;
		vec2 surface_world = world + shift;
		vec2 surface_local = local + shift;
		signed_across += dot(shift, across_dir);
		float along = UV.x + dot(shift, along_dir);
		across = abs(signed_across);
		jag = bank_jag(surface_world);
		bank = bank_at(width, along, surface_world, signed_across, jag);
		// Voda řeky přejde do jezera a asi do dlaždice za břehem zmizí.
		float lake = lake_under(surface_local);
		float shadow = bank_shadow(width, along, surface_world, signed_across, jag, 0.0);
		// Podíl jako u jezera: voda do water_part, okraj vody na water_part.
		float edge = across / bank.x * water_part;
		float depth = 1.0 - smoothstep(0.0, water_part, edge);
		// Textura vody jako u jezera, ve světě, ať navazuje přes kraj čtverce i do ústí.
		vec3 surface = water_texture(surface_world, lod);
		vec3 water = mix(surface, deep_color, depth * 0.3);
		float shallow = smoothstep(water_part * (0.55 - 0.3 * bank.z), water_part, edge);
		water = mix(water, shallow_color, shallow * shallow_strength * (1.0 + 0.6 * bank.z));
		// Stojaté vlny jezera, slabší.
		float wave = wave_height(wave_phases(surface_world));
		water = mix(water, wave_band(wave), wave_tint * still_waves * depth);
		// Proud: odlesky protažené podél řeky jedou k ústí.
		vec2 stream = vec2(along - TIME * flow, signed_across);
		water = mix(water, highlight_color, water_glints(stream) * glint_strength * 1.3 * (0.4 + 0.6 * depth));
		// Pěna u břehu jako na jezeře, krajky jedou s proudem.
		float shore = smoothstep(water_part - 0.2, water_part - 0.05, edge);
		vec2 foam_pos = floor(vec2((along - TIME * flow) * 0.5, signed_across));
		float lace = foam_lace(foam_pos);
		vec3 foam_color = mix(highlight_color, vec3(0.92, 0.97, 0.98), 0.62);
		water = mix(water, foam_color, clamp(shore * mix(0.2, 0.8, lace), 0.0, 0.28));
		// Hladina u svahu tmavší, svah nad ní stíní.
		water *= 1.0 - 0.22 * smoothstep(-6.0, 0.0, across - bank.x);
		water *= 1.0 - shadow;
		// Nad jezerem přejde do vody jezera.
		water = mix(water, mix(surface, wave_band(wave), wave_tint), smoothstep(0.3, 0.75, lake));
		float pixel = max(length(dFdx(world)), 1.0);
		float alpha = 1.0 - smoothstep(-0.5 * pixel, 0.5 * pixel, across - bank.x);
		// Za horní hranou svahu je terén, voda pod ním nepřeteče.
		alpha *= 1.0 - smoothstep(ground_lip - 0.25, ground_lip - 0.1, ground_rel);
		alpha *= fade * (1.0 - smoothstep(0.45, 0.9, lake));
		COLOR = vec4(water, alpha);
	}
}
