// Společné uniformy a funkce terénu. Předpéká je terrain_bake (souš a břehy do textur chunků)
// a terrain_water (animovaná voda nad předpečenou texturou). Vzhled vody (vlny, odlesky,
// textura vody ve světě) z něj bere i řeka (river.gdshader), ať vypadá jako jezero.
uniform sampler2DArray terrains : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D corner_map : filter_nearest, repeat_disable;
uniform sampler2D variant_map : filter_nearest, repeat_disable;
uniform float map_size = 64.0;
uniform float tile_size = 64.0;
uniform float atlas_columns = 4.0;
uniform float variant_count = 16.0;
uniform int water_index = 3;
uniform float shore_style[16];

uniform vec3 sand_color : source_color = vec3(0.769, 0.643, 0.376);
uniform vec3 sand_wet_color : source_color = vec3(0.651, 0.518, 0.282);
uniform vec3 shallow_color : source_color = vec3(0.494, 0.749, 0.855);
uniform vec3 ice_color : source_color = vec3(0.906, 0.965, 0.980);
uniform float sand_solid = 0.34;
uniform float sand_solid_wobble = 0.05;
uniform float sand_land_fade = 0.40;
uniform float sand_land_fray = 0.24;
uniform float sand_water = 0.58;
uniform float sand_water_shift = 0.36;
uniform float sand_strength = 1.0;
uniform float shallow_from = 0.5;
uniform float shallow_to = 1.0;
uniform float shallow_strength = 0.5;
uniform float ice_from = 0.02;
uniform float ice_to = 0.30;
uniform float ice_strength = 0.48;

uniform vec3 deep_color : source_color = vec3(0.141, 0.369, 0.471);
uniform vec3 highlight_color : source_color = vec3(0.290, 0.557, 0.667);
uniform float wave_speed = 0.5;
uniform float wave_scale = 14.0;
uniform float wave_swell = 0.03;
uniform float wave_tint = 0.18;
// Směry tří vln. Počítá je katalog z úhlu ve surfaces.json, ať se nepočítají v každém pixelu.
uniform vec2 wave_dir_a = vec2(-0.5, 0.866);
uniform vec2 wave_dir_b = vec2(-0.995, -0.103);
uniform vec2 wave_dir_c = vec2(-0.218, -0.976);
uniform float mask_start = 0.7;
// Odlesky na hladině: protáhlé světlé skvrny dlouhé asi glint_scale px, síla glint_strength.
// Na jezeře plují pomalu s vlnou, na řece s proudem.
uniform float glint_scale = 36.0;
uniform float glint_strength = 0.4;
// Předpočítaný šum odlesků a pěny (tools/gen_water_noise.py), opakovatelné textury. Odlesky
// mají GLINT_CELLS buněk šumu na stranu, pěna texel na pixel světa a FOAM_SIDE px na stranu.
uniform sampler2D glint_noise : filter_linear, repeat_enable;
uniform sampler2D foam_noise : filter_nearest, repeat_enable;
const float GLINT_CELLS = 32.0;
const float FOAM_SIDE = 400.0;


// Hash bez sinu (Dave Hoskins). sin velkého čísla ztrácí přesnost na velkých mapách.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 fraction = fract(p);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, fraction.x), mix(c, d, fraction.x), fraction.y);
}

float hump(float share, float start, float end_share) {
	if (share <= start || share >= end_share) {
		return 0.0;
	}
	float t = (share - start) / (end_share - start);
	return 4.0 * t * (1.0 - t);
}

float style_of(float id) {
	return shore_style[clamp(int(id), 0, 15)];
}

// lod dostává zvenku. Předpečení kreslí 1:1, takže je 0; zmenšení při oddálení obstarají mipmapy
// textury chunku.
vec3 sample_layer(float layer, float variant, vec2 uv, float lod) {
	float column = mod(variant, atlas_columns);
	float row = floor(variant / atlas_columns);
	vec2 atlas_texels = vec2(atlas_columns * tile_size);
	vec2 raw = uv * tile_size;
	// Otisk filtru nesmí přetéct do sousední varianty atlasu.
	float inset = min(0.5 * exp2(lod), tile_size * 0.5 - 0.5);
	vec2 local = clamp(raw, vec2(inset), vec2(tile_size - inset));
	vec2 atlas_uv = (vec2(column, row) * tile_size + local) / atlas_texels;
	return textureLod(terrains, vec3(atlas_uv, layer), lod).rgb;
}

float land_pair_power(float id_a, float id_b, float id_c, float id_d, int count) {
	float ids[4] = float[4](id_a, id_b, id_c, id_d);
	float best = 1.0;
	bool saw = false;
	for (int i = 0; i < 4; i++) {
		if (i >= count || ids[i] == float(water_index)) {
			continue;
		}
		for (int j = i + 1; j < 4; j++) {
			if (j >= count || ids[j] == float(water_index)) {
				continue;
			}
			saw = true;
			float pair = (style_of(ids[i]) == 1.0 && style_of(ids[j]) == 1.0) ? 1.0 : 2.0;
			best = max(best, pair);
		}
	}
	return saw ? best : 1.0;
}

void evaluate(vec2 uv, float variant, float lod, vec4 packed_ids, out vec3 color, out float water_share, out float shore_kind) {
	float cid[4] = float[4](
		round(packed_ids.r * 255.0),
		round(packed_ids.g * 255.0),
		round(packed_ids.b * 255.0),
		round(packed_ids.a * 255.0)
	);
	float raw[4] = float[4](
		(1.0 - uv.x) * (1.0 - uv.y),
		uv.x * (1.0 - uv.y),
		(1.0 - uv.x) * uv.y,
		uv.x * uv.y
	);
	shore_kind = 0.0;
	if (cid[0] == cid[1] && cid[1] == cid[2] && cid[2] == cid[3]) {
		color = sample_layer(cid[0], variant, uv, lod);
		water_share = cid[0] == float(water_index) ? 1.0 : 0.0;
		if (water_share < 1.0) {
			shore_kind = style_of(cid[0]);
		}
		return;
	}

	float uid[4] = float[4](0.0, 0.0, 0.0, 0.0);
	float uw[4] = float[4](0.0, 0.0, 0.0, 0.0);
	int count = 0;
	for (int corner = 0; corner < 4; corner++) {
		bool found = false;
		for (int slot = 0; slot < 4; slot++) {
			if (slot >= count) {
				break;
			}
			if (uid[slot] == cid[corner]) {
				uw[slot] += raw[corner];
				found = true;
				break;
			}
		}
		if (!found) {
			uid[count] = cid[corner];
			uw[count] = raw[corner];
			count++;
		}
	}

	float water_mass = 0.0;
	float land_mass = 0.0;
	for (int slot = 0; slot < 4; slot++) {
		if (slot >= count) {
			break;
		}
		if (uid[slot] == float(water_index)) {
			water_mass += uw[slot];
		} else {
			land_mass += uw[slot];
		}
	}

	float final_w[4] = float[4](0.0, 0.0, 0.0, 0.0);
	if (water_mass <= 0.0 || land_mass <= 0.0) {
		float power = water_mass > 0.0 ? 2.0 : land_pair_power(uid[0], uid[1], uid[2], uid[3], count);
		float raised_sum = 0.0;
		float raised[4];
		for (int slot = 0; slot < 4; slot++) {
			raised[slot] = 0.0;
			if (slot >= count) {
				continue;
			}
			raised[slot] = pow(max(uw[slot], 0.0001), power);
			raised_sum += raised[slot];
		}
		for (int slot = 0; slot < 4; slot++) {
			if (slot < count && raised_sum > 0.0) {
				final_w[slot] = raised[slot] / raised_sum;
			}
		}
		water_share = water_mass > 0.0 ? 1.0 : 0.0;
	} else {
		float pair = land_pair_power(uid[0], uid[1], uid[2], uid[3], count);
		float soft_sum = 0.0;
		float soft[4];
		for (int slot = 0; slot < 4; slot++) {
			soft[slot] = 0.0;
			if (slot >= count || uid[slot] == float(water_index)) {
				continue;
			}
			soft[slot] = pow(max(uw[slot] / land_mass, 0.0001), pair);
			soft_sum += soft[slot];
		}
		float sharp_land = pow(land_mass, 2.0);
		float sharp_water = pow(water_mass, 2.0);
		water_share = sharp_water / (sharp_land + sharp_water);
		for (int slot = 0; slot < 4; slot++) {
			if (slot >= count) {
				break;
			}
			if (uid[slot] == float(water_index)) {
				final_w[slot] = water_share;
			} else if (soft_sum > 0.0) {
				final_w[slot] = (soft[slot] / soft_sum) * (1.0 - water_share);
			}
		}
	}

	color = vec3(0.0);
	float best_land = -1.0;
	float best_weight = -1.0;
	for (int slot = 0; slot < 4; slot++) {
		if (slot >= count || final_w[slot] <= 0.0) {
			continue;
		}
		color += sample_layer(uid[slot], variant, uv, lod) * final_w[slot];
		if (uid[slot] != float(water_index) && final_w[slot] > best_weight) {
			best_weight = final_w[slot];
			best_land = uid[slot];
		}
	}
	if (best_land >= 0.0) {
		shore_kind = style_of(best_land);
	}
}

// --- Voda: jezero (terrain_water) i řeka (river) ---

// Fáze tří vln jezera v bodě světa.
vec3 wave_phases(vec2 world) {
	float wavelength = max(wave_scale, 1.0);
	return vec3(
		dot(world, wave_dir_a) * 6.2831853 / wavelength - TIME * wave_speed,
		dot(world, wave_dir_b) * 6.2831853 / (wavelength * 0.72) - TIME * wave_speed * 1.17,
		dot(world, wave_dir_c) * 6.2831853 / (wavelength * 1.35) - TIME * wave_speed * 0.83
	);
}

// Výška vlny z fází, -1 až 1.
float wave_height(vec3 phases) {
	return (sin(phases.x) + sin(phases.y) * 0.65 + sin(phases.z) * 0.4) / 2.05;
}

// Barva vlny: v údolí tmavá, na hřebeni světlá.
vec3 wave_band(float height) {
	return mix(deep_color, highlight_color, height * 0.5 + 0.5);
}

// Odlesky 0 až 1. p je bod v px, osa x je směr, kterým jsou skvrny protažené.
float water_glints(vec2 p) {
	vec2 at = p / vec2(glint_scale, glint_scale * 0.4);
	return smoothstep(0.62, 0.85, texture(glint_noise, at / GLINT_CELLS).r);
}

// Krajka pěny 0 až 1 v bodě foam_pos (celé pixely).
float foam_lace(vec2 foam_pos) {
	return smoothstep(0.22, 0.78, texture(foam_noise, (foam_pos + 0.5) / FOAM_SIDE).r);
}

// Textura vody z atlasu terénů v bodě světa: každá dlaždice světa má svou variantu.
// lod podle velikosti pixelu obrazovky ve světě, ať se textura při oddálení nemihotá.
vec3 water_texture(vec2 world, float lod) {
	vec2 tile = floor(world / tile_size);
	float variant = floor(hash(tile + vec2(71.0, 13.0)) * variant_count);
	return sample_layer(float(water_index), min(variant, variant_count - 1.0), world / tile_size - tile, lod);
}


// --- Břeh: svah dolů k hladině u řeky (river) i jezera (terrain_bake, terrain_water) ---

// Svah podle terénu (TerrainCatalog.bank_look): pro každý terén (index jako v corner_map)
// vrstva textury půdy a náplavy, podíl štěrku a bahna. gravel_layer je textura štěrku (suť).
uniform float bank_soil[16];
uniform float bank_bar[16];
uniform float bank_gravel[16];
uniform float bank_mud[16];
uniform int gravel_layer = -1;
const vec3 MUD = vec3(0.24, 0.19, 0.13);
const vec3 EARTH = vec3(0.43, 0.33, 0.22);
const vec3 STONE = vec3(0.5, 0.5, 0.48);
// Stín břehu na svah a hladinu: hloubka koryta v metrech (posun stínu je sun_shadow na metr)
// a síla vůči stínům objektů (shadow_opacity).
const float BANK_SHADOW_DEPTH = 0.9;
const float BANK_SHADOW = 0.9;
// Hladina řeky i jezera je WATER_DEPTH m pod terénem. Při pohybu kamery se posouvá jako vrstva
// v záporné výšce (tree_layer.gdshader, PARALLAX jako ObjectLayers.PARALLAX): ke středu
// obrazovky, na vzdálené straně se odkryje víc svahu, bližší svah zakryje voda.
const float WATER_DEPTH = 1.0;
const float WATER_PARALLAX = 0.016;

// O kolik dál od středu záběru (camera) leží bod hladiny, který je vidět v bodě at.
vec2 water_parallax(vec2 at, vec2 camera, float zoom) {
	return (at - camera) * WATER_DEPTH * WATER_PARALLAX * zoom;
}

// Textura vrstvy terénu v bodě at (px), každá dlaždice svou variantou.
vec3 layer_texture(int layer, vec3 fallback, vec2 at, float lod) {
	if (layer < 0) {
		return fallback;
	}
	vec2 tile = floor(at / tile_size);
	float variant = floor(hash(tile + vec2(23.0, 61.0)) * variant_count);
	return sample_layer(float(layer), min(variant, variant_count - 1.0), at / tile_size - tile, lod);
}

// Dlaždice čtverce pod bodem at_local (px ve čtverci) a bod v ní 0 až 1.
ivec2 bank_cell(vec2 at_local, out vec2 uv) {
	vec2 tile_pos = at_local / tile_size;
	ivec2 cell = clamp(ivec2(floor(tile_pos)), ivec2(0), ivec2(int(map_size) - 1));
	uv = clamp(tile_pos - vec2(cell), 0.0, 1.0);
	return cell;
}

// Podíl vody v bodě at_local z rohů dlaždice, lineárně (bez zaostření jako v evaluate).
// 0.5 je zhruba čára vody jezera.
float water_mass_at(vec2 at_local) {
	vec2 uv;
	ivec2 cell = bank_cell(at_local, uv);
	vec4 ids = round(texelFetch(corner_map, cell, 0) * 255.0);
	vec4 raw = vec4((1.0 - uv.x) * (1.0 - uv.y), uv.x * (1.0 - uv.y), (1.0 - uv.x) * uv.y, uv.x * uv.y);
	return dot(raw, vec4(equal(ids, vec4(float(water_index)))));
}

// Půda svahu, náplava, podíl štěrku a bahna a samotná souš (rohy dlaždice bez vody, jejich
// varianta) podle terénu v bodě at_local. at_tex je bod pro textury půdy.
void bank_ground(vec2 at_local, vec2 at_tex, float lod, bool want_bar, out vec3 soil, out vec3 bar, out vec2 amounts, out vec3 land) {
	vec2 uv;
	ivec2 cell = bank_cell(at_local, uv);
	vec4 packed = texelFetch(corner_map, cell, 0);
	float variant = round(texelFetch(variant_map, cell, 0).r * 255.0);
	float ids[4] = float[4](round(packed.r * 255.0), round(packed.g * 255.0), round(packed.b * 255.0), round(packed.a * 255.0));
	float weights[4] = float[4]((1.0 - uv.x) * (1.0 - uv.y), uv.x * (1.0 - uv.y), (1.0 - uv.x) * uv.y, uv.x * uv.y);
	soil = vec3(0.0);
	bar = vec3(0.0);
	amounts = vec2(0.0);
	land = vec3(0.0);
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		if (ids[i] != float(water_index)) {
			total += weights[i];
		}
	}
	if (total <= 0.0) {
		// Samá voda (ústí řeky): půda prvního rohu.
		int only = clamp(int(ids[0]), 0, 15);
		soil = layer_texture(int(bank_soil[only]), EARTH, at_tex, lod);
		bar = layer_texture(int(bank_bar[only]), sand_color, at_tex, lod);
		amounts = vec2(bank_gravel[only], bank_mud[only]);
		land = soil;
		return;
	}
	for (int i = 0; i < 4; i++) {
		if (weights[i] <= 0.0 || ids[i] == float(water_index)) {
			continue;
		}
		// Stejný terén v dalších rozích se přičte k prvnímu, textura se čte jednou.
		bool seen = false;
		for (int k = 0; k < i; k++) {
			if (ids[k] == ids[i] && weights[k] > 0.0) {
				seen = true;
			}
		}
		if (seen) {
			continue;
		}
		float w = 0.0;
		for (int k = i; k < 4; k++) {
			if (ids[k] == ids[i]) {
				w += weights[k];
			}
		}
		w /= total;
		int id = clamp(int(ids[i]), 0, 15);
		soil += layer_texture(int(bank_soil[id]), EARTH, at_tex, lod) * w;
		if (want_bar) {
			bar += layer_texture(int(bank_bar[id]), sand_color, at_tex, lod) * w;
		}
		amounts += vec2(bank_gravel[id], bank_mud[id]) * w;
		land += sample_layer(ids[i], variant, uv, lod) * w;
	}
}

// Výška svahu 0 (hladina) až 1 (horní hrana) z podílu rel. Vymletý břeh (outer) strmě,
// náplava (inner) pozvolna.
float slope_height(float rel, float inner, float outer) {
	return pow(clamp(rel, 0.0, 1.0), 0.6 + 0.9 * inner - 0.3 * outer);
}

// Horní hrana svahu: kolem 1, roztřepená.
float bank_lip(vec2 at) {
	return 1.0 + (value_noise(at / 10.0) - 0.5) * 0.4 + (value_noise(at / 3.0) - 0.5) * 0.12;
}

// Trsy terénu přes horní hranu (0 až 1).
float bank_tufts(vec2 at, float jag, float rel) {
	return smoothstep(0.64, 0.74, value_noise(at / 9.0 + 17.0) * 0.7 + jag * 0.3) * smoothstep(0.55, 0.85, rel);
}

// Barva svahu: nahoře terén (top), níž půda se štěrkem, bahnem a kameny, na náplavě (bar 0 až
// 1) její materiál, dole vlhký a tmavý. side odliší úseky na dvou březích řeky.
vec3 bank_slope(vec3 soil, vec3 bar_color, vec2 amounts, vec3 top, vec2 at, float lod, float rel, float height, float bar, float outer, float side) {
	float grain = value_noise(at / 3.0);
	float m = value_noise(at / 110.0 + side * 53.0) * 0.6 + value_noise(at / 40.0) * 0.4;
	vec3 color = soil * 0.85 * (0.85 + 0.3 * grain);
	vec3 gravel = layer_texture(gravel_layer, STONE, at, lod) * (0.8 + 0.3 * grain);
	color = mix(color, gravel, smoothstep(0.5, 0.6, m) * amounts.x);
	color = mix(color, MUD * (0.8 + 0.4 * grain), smoothstep(0.42, 0.32, m) * amounts.y);
	float rocks = smoothstep(0.74, 0.8, value_noise(at / 9.0 + 5.0) * 0.5 + value_noise(at / 4.0 + 9.0) * 0.5) * smoothstep(0.6, 0.75, m) * amounts.x;
	color = mix(color, STONE * (0.7 + 0.5 * value_noise(at / 2.0)), rocks);
	color = mix(color, bar_color * 0.92, bar);
	// Horní část svahu je terén sám, s roztřepeným přechodem.
	float crest = smoothstep(0.55, 0.9, rel + (value_noise(at / 7.0 + 31.0) - 0.5) * 0.3);
	color = mix(color, top, crest * (1.0 - bar));
	color *= 0.55 + 0.5 * height - 0.18 * outer;
	float wet = smoothstep(0.25, 0.0, rel) * (0.6 + 0.4 * value_noise(at / 18.0 + 3.0));
	return mix(color, color * 0.6, wet);
}

// Jezero: podíl svahu v bodě at (px ve čtverci) s podílem vody f (water_mass_at). Čára vody
// je kolem f 0.6, kde začínají vlny (terrain_water), horní hrana o šířku svahu dál od vody.
// Obojí podle šumu kolísá.
float lake_rel(vec2 at, float f) {
	float jag = value_noise(at / 14.0) * 0.6 + value_noise(at / 40.0) * 0.4;
	float low = value_noise(at / 140.0 + 7.0);
	float mid = value_noise(at / 38.0 + 37.0);
	float span = 0.6 * (0.45 + 0.9 * low + 0.35 * (mid - 0.5));
	float water_line = 0.6 + (jag - 0.5) * 0.1;
	float top = max(water_line - span, 0.04);
	return (water_line - f) / (water_line - top);
}

// Výška břehu jezera v bodě at: 1 na souši, 0 na hladině.
float lake_height(vec2 at) {
	float f = water_mass_at(at);
	if (f <= 0.0) {
		return 1.0;
	}
	return slope_height(lake_rel(at, f), 0.0, 0.0);
}

// Břeh jezera v předpečení: surface je terén (evaluate), f podíl vody, at bod ve čtverci.
vec3 lake_bank(vec3 surface, float f, vec2 at, float lod) {
	float rel = lake_rel(at, f);
	float jag = value_noise(at / 14.0) * 0.6 + value_noise(at / 40.0) * 0.4;
	float land = max(smoothstep(bank_lip(at) - 0.12, bank_lip(at) + 0.05, rel), bank_tufts(at, jag, rel));
	if (land >= 1.0) {
		return surface;
	}
	vec3 soil;
	vec3 bar_color;
	vec2 amounts;
	vec3 top;
	bank_ground(at, at, lod, false, soil, bar_color, amounts, top);
	vec3 color = bank_slope(soil, bar_color, amounts, top, at, lod, rel, slope_height(rel, 0.0, 0.0), 0.0, 0.0, 0.0);
	if (rel < 0.0) {
		// Pod hladinou svah pokračuje, ať je vidět, když hladina při pohybu kamery odhalí kus
		// stěny (water_parallax). Hloub zmizí ve vodě. Vodu nad ním kreslí terrain_water.
		color = mix(mix(color, shallow_color, 0.3 * shallow_strength), surface, smoothstep(0.4, 1.4, -rel));
	}
	return mix(color, surface, land);
}
