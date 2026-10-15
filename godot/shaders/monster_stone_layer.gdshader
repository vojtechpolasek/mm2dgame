shader_type canvas_item;
render_mode unshaded;

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
// Atlas semínek odlesků se stejným rozložením jako vrstva: G je semínko (jas = fáze bliknutí).
uniform sampler2D sparkle_map : filter_nearest, hint_default_black;
// Barva a síla odlesku podle materiálu (glint, sparkle). 0 je matný kámen.
uniform vec3 glint_color : source_color = vec3(1.0);
uniform float sparkle = 0.0;
// Posun bliknutí, ať příšery stejného materiálu neblikají naráz.
uniform float phase = 0.0;
// Stínová vrstva létající příšery: černá s tímto krytím. 0 je běžná vrstva.
uniform float shadow_alpha = 0.0;

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
	if (shadow_alpha > 0.0) {
		COLOR = vec4(0.0, 0.0, 0.0, mask.a * shadow_alpha);
	} else {
		vec3 body = body_color * mix(shade.x, shade.y, mask.r);
		vec3 skin = mix(body, accent_color * mix(accent_shade.x, accent_shade.y, mask.r), mask.g);
		vec3 lit = mix(skin, eye_color, mask.b);
		float flash = 0.0;
		if (mask.a > 0.004 && sparkle > 0.001) {
			vec2 duv_dx = dFdx(UV);
			vec2 duv_dy = dFdy(UV);
			// Nejsilnější semínko v okolí 9 × 9 px, bližší má přednost.
			float best = -1.0;
			float peak_g = 0.0;
			vec2 peak_at = vec2(0.0);
			for (int y = -4; y <= 4; y++) {
				for (int x = -4; x <= 4; x++) {
					vec2 at = vec2(float(x), float(y));
					float seed = textureLod(sparkle_map, UV + at * TEXTURE_PIXEL_SIZE, 0.0).g;
					float score = seed * exp(-dot(at, at) * 0.10);
					if (score > best) {
						best = score;
						peak_g = seed;
						peak_at = at;
					}
				}
			}
			if (peak_g >= 0.045) {
				// Střed semínka přesněji než na pixel: těžiště jeho okolí.
				vec2 acc = vec2(0.0);
				float mass = 0.0;
				for (int y = -2; y <= 2; y++) {
					for (int x = -2; x <= 2; x++) {
						vec2 off = vec2(float(x), float(y));
						vec2 at = peak_at + off;
						float seed = textureLod(sparkle_map, UV + at * TEXTURE_PIXEL_SIZE, 0.0).g;
						float around = exp(-dot(off, off) * 0.35);
						acc += at * seed * around;
						mass += seed * around;
					}
				}
				vec2 from_seed = -acc / max(mass, 0.0001);
				float wave = sin(TIME * 2.4 + phase + peak_g * 6.2831853);
				flash = pow(max(wave, 0.0), 14.0) * glint_star(glint_aim(from_seed, duv_dx, duv_dy, TEXTURE_PIXEL_SIZE)) * sparkle;
			}
		}
		COLOR = vec4(lit + glint_color * flash, mask.a);
	}
}
