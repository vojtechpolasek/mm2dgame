shader_type canvas_item;
render_mode unshaded;

// Animovaná voda. Kreslí se jen přes dlaždice, které mají v rohu vodu, nad předpečenou texturou
// chunku (TEXTURE). Souš pod hladinou se při vlnění bere z té samé textury, posunutá po vlně.
// Svah břehu je předpečený (lake_bank), stín břehu od slunce a měsíce se přidá tady na svah
// i hladinu (lake_shadow). Hladina je pod terénem (water_parallax): voda se kreslí podle
// podílu vody v bodě hladiny posunutém od středu záběru, i s předpečeným dnem pod ní. Kde
// v posunutém bodě voda není, je vidět svah. Za horní hranu svahu voda nepřeteče.

#include "res://shaders/terrain_common.gdshaderinc"

// Strana textury chunku v pixelech. Posun vlny ve světě se jí přepočte na UV.
uniform float chunk_px = 512.0;
// Levý horní roh mapy ve světě. Rohová mapa je v dlaždicích od něj, vlny jedou dál ve světě.
uniform vec2 map_origin = vec2(0.0);
global uniform vec2 sun_shadow;
global uniform float shadow_opacity;
global uniform vec2 camera_position;
global uniform float camera_zoom;

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

// Podíl vody (jako share_at) v bodě at (px ve čtverci), z jeho vlastní dlaždice.
float share_here(vec2 at) {
	vec2 uv;
	ivec2 cell = bank_cell(at, uv);
	return share_at(uv, texelFetch(corner_map, cell, 0));
}

void fragment() {
	vec2 ground = world_pos - map_origin;
	vec2 shift = water_parallax(world_pos, camera_position, camera_zoom);
	// Bod hladiny, který je tady vidět, a dno pod ním z předpečení.
	vec2 surface_pos = world_pos + shift;
	vec2 tile = floor((surface_pos - map_origin) / tile_size);
	vec2 local_uv = (surface_pos - map_origin - tile * tile_size) / tile_size;
	vec4 packed_ids = texelFetch(corner_map, clamp(ivec2(tile), ivec2(0), ivec2(int(map_size) - 1)), 0);
	float share = share_at(local_uv, packed_ids);
	// Za horní hranou svahu je terén, voda pod ním nepřeteče.
	float ground_mass = water_mass_at(ground);
	if (ground_mass <= 0.0 || lake_rel(ground, ground_mass) > 0.85) {
		share = min(share, share_here(ground));
	}
	vec2 surface_uv = clamp(UV + shift / chunk_px, vec2(0.0), vec2(1.0));
	vec3 surface = texture(TEXTURE, surface_uv).rgb;
	// Vlny začínají od mask_start, pěna nejníž od 0.57. Svah břehu zůstane z předpečení.
	if (share < min(mask_start, 0.57)) {
		float shadow = lake_shadow(ground, sun_shadow, shadow_opacity);
		COLOR = vec4(texture(TEXTURE, UV).rgb * (1.0 - shadow), 1.0);
	} else {
		float shadow = lake_shadow(surface_pos - map_origin, sun_shadow, shadow_opacity);
		float amount = smoothstep(mask_start, 1.0, share);
		vec3 phases = wave_phases(surface_pos);
		float height = wave_height(phases);
		float shift = cos(phases.x) * wave_swell * amount;
		if (amount > 0.001) {
			vec2 shifted_uv = clamp(local_uv + wave_dir_a * shift, vec2(0.001), vec2(0.999));
			vec2 chunk_uv = clamp(surface_uv + (shifted_uv - local_uv) * tile_size / chunk_px, vec2(0.0), vec2(1.0));
			vec3 shifted = texture(TEXTURE, chunk_uv).rgb;
			surface = mix(surface, shifted, smoothstep(mask_start, 1.0, share_at(shifted_uv, packed_ids)));
		}
		// Voda sama, dno (předpečený svah) pod ní prosvítá jen u kraje jako mělčina.
		float lod = max(log2(max(length(dFdx(world_pos)), 1.0)), 0.0);
		vec3 body = mix(water_texture(surface_pos, lod), shallow_color, (1.0 - smoothstep(0.57, 0.85, share)) * shallow_strength);
		surface = mix(surface, body, 0.55 + 0.45 * smoothstep(0.6, 0.9, share));
		vec3 color = mix(surface, wave_band(height), wave_tint * amount);
		// Odlesky protažené podél hřebene, plují pomalu s první vlnou.
		vec2 ridge = vec2(dot(surface_pos, vec2(wave_dir_a.y, -wave_dir_a.x)), dot(surface_pos, wave_dir_a) - TIME * wave_speed * 6.0);
		color = mix(color, highlight_color, water_glints(ridge) * glint_strength * amount * (0.5 + 0.5 * height));
		float crest = smoothstep(0.35, 0.9, 1.0 - (height * 0.5 + 0.5));
		float center = mix(0.74, 0.66, crest);
		float half_width = mix(0.035, 0.09, crest);
		float shore = smoothstep(center - half_width, center - half_width * 0.25, share);
		shore *= 1.0 - smoothstep(center + half_width * 0.15, center + half_width, share);
		vec2 foam_pos = floor(surface_pos);
		float patches = value_noise(foam_pos * 0.11);
		float grains = value_noise(foam_pos * 0.35);
		float lace = smoothstep(0.22, 0.78, patches * 0.6 + grains * 0.4);
		float foam = shore * mix(0.35, 1.0, lace) * mix(0.12, 0.85, crest);
		vec3 foam_color = mix(highlight_color, vec3(0.92, 0.97, 0.98), 0.62);
		COLOR = vec4(mix(color, foam_color, clamp(foam, 0.0, 0.28)) * (1.0 - shadow), 1.0);
	}
}
