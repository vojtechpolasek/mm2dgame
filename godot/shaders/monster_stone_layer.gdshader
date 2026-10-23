shader_type canvas_item;
// Bez unshaded, ať svět obarví CanvasModulate (jed, tma).
render_mode blend_mix;

// Vrstva kamenné příšery (v monsters.json shader "stone"). Posun výšky je stejný jako
// v monster_layer.gdshader, odlesky jako v crystal.gdshader. Každá vrstva má svůj materiál.
uniform float height_m = 0.0;
global uniform vec2 camera_position;
uniform float parallax = 0.016;
uniform float scale_per_meter = 0.01;
global uniform float camera_zoom;

// Masky z tools/gen_monsters.py jako v monster_layer.gdshader: R světlost, G podíl kresby,
// B oči, alfa krytí. Odlesk se přičte navrch.
uniform vec2 shade = vec2(0.35, 1.15);
uniform vec2 accent_shade = vec2(0.6, 1.1);
uniform vec3 body_color : source_color = vec3(0.5);
uniform vec3 accent_color : source_color = vec3(0.8);
uniform vec3 eye_color : source_color = vec3(1.0, 0.3, 0.2);
// Odlesky předpočítané ze semínek (tools/gen_glints.py) se stejným rozložením jako vrstva:
// RG vektor od středu semínka k texelu, B jas semínka (fáze bliknutí), 0 bez semínka.
uniform sampler2D glint_map : filter_nearest, hint_default_black;
// Barva a síla odlesku podle materiálu (glint, sparkle). 0 je matný kámen.
uniform vec3 glint_color : source_color = vec3(1.0);
uniform float sparkle = 0.0;
// Posun bliknutí, ať příšery stejného materiálu neblikají naráz.
uniform float phase = 0.0;
// Třpyt z nastavení hry, 0 ho vypne úplně.
global uniform float sparkle_on;
// Stínová vrstva létající příšery: černá s tímto krytím. 0 je běžná vrstva.
uniform float shadow_alpha = 0.0;

// Míry mapy odlesků, stejné jako v tools/gen_glints.py.
const float GLINT_REACH = 8.0;
const float GLINT_THRESHOLD = 0.045;

// Odlesk jako při focení proti slunci: malé jádro a šest tenkých paprsků. p je v px textury.
float glint_star(vec2 p) {
	float radius = length(p);
	float core = exp(-radius * radius * 2.2);
	float halo = exp(-radius * radius * 0.45) * 0.18;
	float rays = 0.0;
	for (int i = 0; i < 6; i++) {
		float ang = float(i) * 1.0471975512;
		vec2 dir = vec2(cos(ang), sin(ang));
		float along = dot(p, dir);
		float across = abs(dot(p, vec2(-dir.y, dir.x)));
		float arm = exp(-across * across * 5.5) * exp(-max(along, 0.0) * 0.55);
		arm *= smoothstep(0.25, 0.85, along);
		rays = max(rays, arm);
	}
	return core + halo + rays * 1.15;
}

// Délka zůstává na příšeře, paprsky drží směr obrazovky a netočejí se s ní.
vec2 glint_aim(vec2 from_seed, vec2 duv_dx, vec2 duv_dy, vec2 texel) {
	float span = length(from_seed);
	float det = duv_dx.x * duv_dy.y - duv_dy.x * duv_dx.y;
	if (span < 0.001 || abs(det) < 0.0000001) {
		return from_seed;
	}
	vec2 uv_delta = from_seed * texel;
	vec2 screen = vec2(
		(uv_delta.x * duv_dy.y - uv_delta.y * duv_dy.x) / det,
		(duv_dx.x * uv_delta.y - duv_dx.y * uv_delta.x) / det
	);
	return screen * (span / max(length(screen), 0.0001));
}

void vertex() {
	if (height_m > 0.0) {
		float growth = 1.0 + height_m * scale_per_meter;
		vec2 axis_x = (MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy;
		vec2 axis_y = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
		vec2 anchor = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
		vec2 world_shift = (anchor - camera_position) * height_m * parallax * camera_zoom;
		float det = axis_x.x * axis_y.y - axis_y.x * axis_x.y;
		vec2 local_shift = vec2(
			world_shift.x * axis_y.y - world_shift.y * axis_y.x,
			axis_x.x * world_shift.y - axis_x.y * world_shift.x
		) / det;
		VERTEX = VERTEX * growth + local_shift;
	}
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	// Derivace mimo větvení, uvnitř podmínky nejsou definované.
	vec2 duv_dx = dFdx(UV);
	vec2 duv_dy = dFdy(UV);
	if (shadow_alpha > 0.0) {
		COLOR = vec4(0.0, 0.0, 0.0, mask.a * shadow_alpha);
	} else {
		vec3 body = body_color * mix(shade.x, shade.y, mask.r);
		vec3 skin = mix(body, accent_color * mix(accent_shade.x, accent_shade.y, mask.r), mask.g);
		vec3 lit = mix(skin, eye_color, mask.b);
		float flash = 0.0;
		if (mask.a > 0.004 && sparkle * sparkle_on > 0.001) {
			vec3 glint = textureLod(glint_map, UV, 0.0).rgb;
			float wave = sin(TIME * 2.4 + phase + glint.b * 6.2831853);
			if (glint.b >= GLINT_THRESHOLD && wave > 0.0) {
				// Vektor je od středu texelu, pixel leží uvnitř texelu jinde.
				vec2 from_seed = (glint.rg * 255.0 - 127.5) / 127.5 * GLINT_REACH + fract(UV / TEXTURE_PIXEL_SIZE) - 0.5;
				flash = pow(wave, 14.0) * glint_star(glint_aim(from_seed, duv_dx, duv_dy, TEXTURE_PIXEL_SIZE)) * sparkle;
			}
		}
		COLOR = vec4(lit + glint_color * flash, mask.a);
	}
}
