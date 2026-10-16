shader_type canvas_item;
render_mode unshaded;

// Každý kámen má svůj materiál. Instanční uniformy by v renderu Compatibility
// stačily jen na pár stovek objektů a další by dostaly cizí barvy.

// Stejný posun výšky jako tree_layer.gdshader. Kámen v ruce je ve výšce těla, na zemi je 0.
uniform float height_m = 0.0;
// Kámen zasazený do šipky na okraji kotliny posouvá stejně jako okraj: posun se počítá od
// středu kotliny, který je o anchor_offset pixelů světa za kamenem. Ostatní kameny mají 0.
uniform vec2 anchor_offset = vec2(0.0);
global uniform vec2 camera_position;
uniform float parallax = 0.016;
global uniform float camera_zoom;

// R textury je světlost fasety, G semínko odlesku (jas = fáze bliknutí), B okraj.
// Alfa je krytí, ne další kanál. Semínko je kolečko, hvězdičku kreslí glint_star.
uniform vec3 gem_color : source_color = vec3(0.77, 0.13, 0.19);
uniform vec3 glint_color : source_color = vec3(1.0, 0.91, 0.88);
uniform float sparkle = 0.65;
uniform float phase = 0.0;
// Odlesky předpočítané ze semínek v G (tools/gen_glints.py): RG vektor od středu semínka
// k texelu, B jas semínka (fáze bliknutí), 0 bez semínka.
uniform sampler2D glint_map : filter_nearest, hint_default_black;
// Třpyt z nastavení hry, 0 ho vypne úplně.
global uniform float sparkle_on;
// Poloprůhledný kámen nad hlavou vesničana. COLOR se tu přepisuje, modulate by se ztratil.
uniform float alpha = 1.0;

// Míry mapy odlesků, stejné jako v tools/gen_glints.py.
const float GLINT_REACH = 8.0;
const float GLINT_THRESHOLD = 0.045;

// Odlesk jako při focení proti slunci: malé jádro a šest tenkých paprsků.
// p je v pixelech textury, směr paprsků je vůči obrazovce.
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

// Délka zůstává na kameni, paprsky drží směr objektivu a netočejí se s kamenem.
// texel je TEXTURE_PIXEL_SIZE. Vestavěné hodnoty jsou jen ve fragment(), ne ve vlastní funkci.
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
		vec2 axis_x = (MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy;
		vec2 axis_y = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
		vec2 anchor = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy - anchor_offset;
		vec2 world_shift = (anchor - camera_position) * height_m * parallax * camera_zoom;
		float det = axis_x.x * axis_y.y - axis_y.x * axis_x.y;
		vec2 local_shift = vec2(
			world_shift.x * axis_y.y - world_shift.y * axis_y.x,
			axis_x.x * world_shift.y - axis_x.y * world_shift.x
		) / det;
		VERTEX += local_shift;
	}
}

void fragment() {
	vec4 weight = texture(TEXTURE, UV);
	float shade = mix(0.32, 1.18, weight.r);
	vec3 body = gem_color * shade + gem_color * weight.b * 0.22;
	vec2 duv_dx = dFdx(UV);
	vec2 duv_dy = dFdy(UV);
	float flash = 0.0;
	if (weight.a > 0.004 && sparkle * sparkle_on > 0.001) {
		vec3 glint = textureLod(glint_map, UV, 0.0).rgb;
		float wave = sin(TIME * 2.4 + phase + glint.b * 6.2831853);
		if (glint.b >= GLINT_THRESHOLD && wave > 0.0) {
			// Vektor je od středu texelu, pixel leží uvnitř texelu jinde.
			vec2 from_seed = (glint.rg * 255.0 - 127.5) / 127.5 * GLINT_REACH + fract(UV / TEXTURE_PIXEL_SIZE) - 0.5;
			flash = pow(wave, 14.0) * glint_star(glint_aim(from_seed, duv_dx, duv_dy, TEXTURE_PIXEL_SIZE)) * sparkle;
		}
	}
	COLOR = vec4(body + glint_color * flash, weight.a * alpha);
}
