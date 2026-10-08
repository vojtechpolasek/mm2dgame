shader_type canvas_item;
render_mode unshaded;

// Animovaná voda. Kreslí se jen přes dlaždice, které mají v rohu vodu, nad předpečenou texturou
// chunku (TEXTURE). Souš pod hladinou se při vlnění bere z té samé textury, posunutá po vlně.

#include "res://shaders/terrain_common.gdshaderinc"

// Strana textury chunku v pixelech. Posun vlny ve světě se jí přepočte na UV.
uniform float chunk_px = 512.0;

varying vec2 world_pos;

// Podíl vody v bodě dlaždice. Stejný výpočet jako water_share v evaluate(), jen bez barev.
float share_at(vec2 uv, vec4 packed_ids) {
	vec4 ids = round(packed_ids * 255.0);
	vec4 raw = vec4(
		(1.0 - uv.x) * (1.0 - uv.y),
		uv.x * (1.0 - uv.y),
		(1.0 - uv.x) * uv.y,
		uv.x * uv.y
	);
	float water_mass = dot(raw, vec4(equal(ids, vec4(float(water_index)))));
	float land_mass = 1.0 - water_mass;
	if (water_mass <= 0.0) {
		return 0.0;
	}
	if (land_mass <= 0.0) {
		return 1.0;
	}
	float sharp_water = water_mass * water_mass;
	return sharp_water / (land_mass * land_mass + sharp_water);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 tile = floor(world_pos / tile_size);
	vec2 local_uv = (world_pos - tile * tile_size) / tile_size;
	vec4 packed_ids = texture(corner_map, (tile + 0.5) / map_size);
	float share = share_at(local_uv, packed_ids);
	vec3 surface = texture(TEXTURE, UV).rgb;
	// Vlny začínají od mask_start, pěna nejníž od 0.57. Pás písku zůstane z předpečení.
	if (share < min(mask_start, 0.57)) {
		COLOR = vec4(surface, 1.0);
	} else {
		float amount = smoothstep(mask_start, 1.0, share);
		float wavelength = max(wave_scale, 1.0);
		float phase = dot(world_pos, wave_dir_a) * 6.2831853 / wavelength - TIME * wave_speed;
		float phase_b = dot(world_pos, wave_dir_b) * 6.2831853 / (wavelength * 0.72) - TIME * wave_speed * 1.17;
		float phase_c = dot(world_pos, wave_dir_c) * 6.2831853 / (wavelength * 1.35) - TIME * wave_speed * 0.83;
		float height = (sin(phase) + sin(phase_b) * 0.65 + sin(phase_c) * 0.4) / 2.05;
		float shift = cos(phase) * wave_swell * amount;
		if (amount > 0.001) {
			vec2 shifted_uv = clamp(local_uv + wave_dir_a * shift, vec2(0.001), vec2(0.999));
			vec2 chunk_uv = clamp(UV + (shifted_uv - local_uv) * tile_size / chunk_px, vec2(0.0), vec2(1.0));
			vec3 shifted = texture(TEXTURE, chunk_uv).rgb;
			surface = mix(surface, shifted, smoothstep(mask_start, 1.0, share_at(shifted_uv, packed_ids)));
		}
		vec3 band = mix(deep_color, highlight_color, height * 0.5 + 0.5);
		vec3 color = mix(surface, band, wave_tint * amount);
		float crest = smoothstep(0.35, 0.9, 1.0 - (height * 0.5 + 0.5));
		float center = mix(0.74, 0.66, crest);
		float half_width = mix(0.035, 0.09, crest);
		float shore = smoothstep(center - half_width, center - half_width * 0.25, share);
		shore *= 1.0 - smoothstep(center + half_width * 0.15, center + half_width, share);
		vec2 foam_pos = floor(world_pos);
		float patches = value_noise(foam_pos * 0.11);
		float grains = value_noise(foam_pos * 0.35);
		float lace = smoothstep(0.22, 0.78, patches * 0.6 + grains * 0.4);
		float foam = shore * mix(0.35, 1.0, lace) * mix(0.12, 0.85, crest);
		vec3 foam_color = mix(highlight_color, vec3(0.92, 0.97, 0.98), 0.62);
		COLOR = vec4(mix(color, foam_color, clamp(foam, 0.0, 0.28)), 1.0);
	}
}
