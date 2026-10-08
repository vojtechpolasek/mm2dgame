// Společné uniformy a funkce terénu. Předpéká je terrain_bake (souš a břehy do textur chunků)
// a terrain_water (animovaná voda nad předpečenou texturou).
uniform sampler2DArray terrains : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D corner_map : filter_nearest, repeat_disable;
uniform sampler2D variant_map : filter_nearest, repeat_disable;
uniform float map_size = 64.0;
uniform float tile_size = 64.0;
uniform float atlas_columns = 4.0;
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

vec3 apply_shore(vec3 color, float share, float shore_kind, vec2 world_pos) {
	if (share <= 0.0 || share >= 1.0 || shore_kind <= 0.0) {
		return color;
	}
	float coarse = value_noise(world_pos / 16.0);
	float fine = value_noise(world_pos / 7.0 + vec2(3.0, 11.0));
	float noise = coarse * 0.65 + fine * 0.35;
	float detail = value_noise(world_pos / 12.8 + vec2(17.0, 47.0));
	if (shore_kind < 1.5) {
		color = mix(color, shallow_color, hump(share, shallow_from, shallow_to) * shallow_strength);
		float solid = sand_solid + (detail - 0.5) * sand_solid_wobble;
		float fade = sand_land_fade + (detail - 0.5) * sand_land_fray;
		float land_edge = solid - max(fade, 0.04);
		float fade_in = smoothstep(land_edge, solid, share);
		float span_in = max(solid - land_edge, 0.001);
		float linear = clamp((share - land_edge) / span_in, 0.0, 1.0);
		fade_in = fade_in * 0.35 + linear * 0.65;
		float water_edge = max(sand_water + (noise - 0.5) * sand_water_shift, solid + 0.1);
		float fade_out = 1.0 - smoothstep(water_edge - 0.08, water_edge + 0.06, share);
		float span = max(water_edge - land_edge, 0.001);
		float wetness = clamp((share - land_edge) / span, 0.0, 1.0);
		wetness = wetness * wetness * 0.55;
		vec3 sand = mix(sand_color, sand_wet_color, wetness);
		return mix(color, sand, fade_in * fade_out * sand_strength);
	}
	float shift = (noise - 0.5) * 0.06;
	float start = ice_from + shift;
	float end_share = ice_to + shift * 1.4;
	float gate = 0.3 + 0.7 * noise;
	return mix(color, ice_color, hump(share, start, end_share) * ice_strength * gate);
}
