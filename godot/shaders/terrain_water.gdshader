shader_type canvas_item;
// Bez unshaded, ať svět obarví CanvasModulate (jed, tma).
render_mode blend_mix;

// Animovaná voda. Kreslí se jen přes dlaždice, které mají v rohu vodu, nad předpečenou texturou
// chunku (TEXTURE). Souš pod hladinou se při vlnění bere z té samé textury, posunutá po vlně.
// Svah břehu je předpečený (lake_bank), stín břehu od slunce a měsíce se přidá tady na svah
// i hladinu. Výšku břehu bere z alfy předpečené textury (terrain_bake), jen bod mimo chunk
// spočítá znovu (lake_height). Hladina je pod terénem (water_parallax): voda se kreslí podle
// podílu vody v bodě hladiny posunutém od středu záběru, i s předpečeným dnem pod ní. Kde
// v posunutém bodě voda není, je vidět svah. Za horní hranu svahu voda nepřeteče.

#include "res://shaders/terrain_common.gdshaderinc"

// Strana textury chunku v pixelech. Posun vlny ve světě se jí přepočte na UV.
uniform float chunk_px = 512.0;
// Levý horní roh mapy ve světě. Rohová mapa je v dlaždicích od něj, vlny jedou dál ve světě.
uniform vec2 map_origin = vec2(0.0);
global uniform vec2 sun_shadow;
global uniform float shadow_opacity;
// Stíny břehů v nastavení (Graphics), 0 vypnuté.
global uniform float bank_shadows;
global uniform vec2 camera_position;
global uniform float camera_zoom;

varying vec2 world_pos;
// Lineární v bodě světa, proto se počítají ve vrcholech a pixel textury čte rovnou z nich (na
// slabé grafice levnější): bod hladiny (world_pos posunutý o water_parallax), UV dna pod ním,
// fáze dvou vln a souřadnice odlesků.
varying vec2 surface_world;
varying vec2 surface_uv_raw;
varying vec2 wave_phase;
varying vec2 glint_uv;

// Výška svahu jezera, nad kterou voda nepřeteče: slope_height(0.85, 0, 0).
const float SLOPE_TOP = 0.907;

// Výška vlny jezera z fází prvních dvou vln (wave_phases), -1 až 1. Třetí vlna jezero nemá,
// je na každém pixelu vody drahá a skoro není vidět. Řeka má dál tři.
float lake_wave(vec2 phases) {
	return (sin(phases.x) + sin(phases.y) * 0.65) / 1.65;
}

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
	vec2 shift = water_parallax(world_pos, camera_position, camera_zoom);
	surface_world = world_pos + shift;
	surface_uv_raw = UV + shift / chunk_px;
	wave_phase = wave_phases(surface_world).xy;
	// Odlesky protažené podél hřebene, plují pomalu s první vlnou (jako water_glints).
	vec2 ridge = vec2(dot(surface_world, vec2(wave_dir_a.y, -wave_dir_a.x)), dot(surface_world, wave_dir_a) - TIME * wave_speed * 6.0);
	glint_uv = ridge / vec2(glint_scale, glint_scale * 0.4) / GLINT_CELLS;
}

// Výška břehu (lake_height) v bodě at (px ve čtverci). Bod ground je tenhle pixel, uv jeho
// místo v textuře chunku. V chunku se čte z alfy, mimo něj se spočítá.
float height_at(sampler2D chunk, vec2 at, vec2 ground, vec2 uv) {
	vec2 at_uv = uv + (at - ground) / chunk_px;
	if (at_uv.x < 0.0 || at_uv.y < 0.0 || at_uv.x > 1.0 || at_uv.y > 1.0) {
		return lake_height(at);
	}
	return texture(chunk, at_uv).a;
}

// Stín břehu jezera v bodě at s výškou here: kus směrem ke slunci (sun_shadow) je břeh výš.
float bank_shadow(sampler2D chunk, vec2 at, float here, vec2 ground, vec2 uv) {
	if (shadow_opacity <= 0.001 || bank_shadows < 0.5) {
		return 0.0;
	}
	float back = height_at(chunk, at - sun_shadow * BANK_SHADOW_DEPTH, ground, uv);
	return clamp((back - here) * 1.6, 0.0, 1.0) * shadow_opacity * BANK_SHADOW;
}

// Podíl vody (jako share_at) v bodě at (px ve čtverci), z jeho vlastní dlaždice.
float share_here(vec2 at) {
	vec2 uv;
	ivec2 cell = bank_cell(at, uv);
	return share_at(uv, texelFetch(corner_map, cell, 0));
}

// Odlesky 0 až 1 jako water_glints, souřadnice z vrcholů.
float glints() {
	return smoothstep(0.62, 0.85, texture(glint_noise, glint_uv).r);
}

void fragment() {
	vec2 ground = world_pos - map_origin;
	// Bod hladiny, který je tady vidět, a dno pod ním z předpečení.
	vec2 surface_pos = surface_world;
	vec2 tile = floor((surface_pos - map_origin) / tile_size);
	vec2 local_uv = (surface_pos - map_origin - tile * tile_size) / tile_size;
	vec4 packed_ids = texelFetch(corner_map, clamp(ivec2(tile), ivec2(0), ivec2(int(map_size) - 1)), 0);
	float share = share_at(local_uv, packed_ids);
	// Předpečený terén tady: barva a v alfě výška břehu.
	vec4 baked = texture(TEXTURE, UV);
	// Za horní hranou svahu je terén, voda pod ním nepřeteče.
	if (baked.a > SLOPE_TOP) {
		share = min(share, share_here(ground));
	}
	vec2 surface_uv = clamp(surface_uv_raw, vec2(0.0), vec2(1.0));
	// Vlny začínají od mask_start, pěna nejníž od 0.57. Svah břehu zůstane z předpečení.
	if (share < min(mask_start, 0.57)) {
		// Svah: výšku i barvu tady už má baked.
		float shadow = bank_shadow(TEXTURE, ground, baked.a, ground, UV);
		COLOR = vec4(baked.rgb * (1.0 - shadow), 1.0);
	} else if (share >= DEEP_READ) {
		// Hluboká voda je předpečená (terrain_bake): textura vody, dno pod ní vidět není. Je daleko
		// od břehu, stín břehu ani pěna tu nejsou, vlny jsou v plné síle.
		float height = lake_wave(wave_phase);
		vec3 color = mix(texture(TEXTURE, surface_uv).rgb, wave_band(height), wave_tint);
		color = mix(color, highlight_color, glints() * glint_strength * (0.5 + 0.5 * height));
		COLOR = vec4(color, 1.0);
	} else {
		vec2 at = surface_pos - map_origin;
		// Bez stínů břehů se výška ani nečte.
		float shadow = bank_shadows > 0.5 ? bank_shadow(TEXTURE, at, height_at(TEXTURE, at, ground, UV), ground, UV) : 0.0;
		float amount = smoothstep(mask_start, 1.0, share);
		vec2 phases = wave_phase;
		float height = lake_wave(phases);
		// Voda sama, dno (předpečený svah) pod ní prosvítá jen u kraje jako mělčina.
		float lod = max(log2(max(length(dFdx(world_pos)), 1.0)), 0.0);
		vec3 body = mix(water_texture(surface_pos, lod), shallow_color, (1.0 - smoothstep(0.57, 0.85, share)) * shallow_strength);
		vec3 surface = body;
		// Kde voda dno úplně zakryje, nečte se.
		float deep = smoothstep(0.6, 0.9, share);
		if (deep < 1.0) {
			surface = texture(TEXTURE, surface_uv).rgb;
			float swell = cos(phases.x) * wave_swell * amount;
			if (amount > 0.001) {
				vec2 shifted_uv = clamp(local_uv + wave_dir_a * swell, vec2(0.001), vec2(0.999));
				vec2 chunk_uv = clamp(surface_uv + (shifted_uv - local_uv) * tile_size / chunk_px, vec2(0.0), vec2(1.0));
				vec3 shifted = texture(TEXTURE, chunk_uv).rgb;
				surface = mix(surface, shifted, smoothstep(mask_start, 1.0, share_at(shifted_uv, packed_ids)));
			}
			surface = mix(surface, body, 0.55 + 0.45 * deep);
		}
		vec3 color = mix(surface, wave_band(height), wave_tint * amount);
		color = mix(color, highlight_color, glints() * glint_strength * amount * (0.5 + 0.5 * height));
		float crest = smoothstep(0.35, 0.9, 1.0 - (height * 0.5 + 0.5));
		float center = mix(0.74, 0.66, crest);
		float half_width = mix(0.035, 0.09, crest);
		float shore = smoothstep(center - half_width, center - half_width * 0.25, share);
		shore *= 1.0 - smoothstep(center + half_width * 0.15, center + half_width, share);
		// Pěna jen v pásu u břehu, jinde je shore 0.
		if (shore > 0.0) {
			float foam = shore * mix(0.35, 1.0, foam_lace(floor(surface_pos))) * mix(0.12, 0.85, crest);
			vec3 foam_color = mix(highlight_color, vec3(0.92, 0.97, 0.98), 0.62);
			color = mix(color, foam_color, clamp(foam, 0.0, 0.28));
		}
		COLOR = vec4(color * (1.0 - shadow), 1.0);
	}
}
