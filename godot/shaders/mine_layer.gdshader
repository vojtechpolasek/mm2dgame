shader_type canvas_item;
render_mode unshaded;

// Vrstva dolu z gen_mine.py. Textura nese masky, ne barvy:
// R světlost (skutečná je R * VALUE_SCALE), G maska kamene materiálu,
// B u kamene materiálu semínko odlesku, jinde plamen lucerny.
// Materiál se sdílí pro každou dvojici vrstva × materiál dolu, mihotání bere fázi z polohy dolu.

// Záporná výška je pod zemí a posouvá se opačně než střechy, díra tak vypadá hluboká.
uniform float height_m = 0.0;
global uniform vec2 camera_position;
uniform float parallax = 0.016;
global uniform float camera_zoom;

uniform vec3 rock_color : source_color = vec3(0.43, 0.41, 0.38);
uniform vec3 ore_color : source_color = vec3(0.77, 0.13, 0.19);
uniform vec3 glint_color : source_color = vec3(1.0, 0.91, 0.88);
uniform float sparkle = 0.5;
// Třpyt z nastavení hry, 0 ho vypne úplně.
global uniform float sparkle_on;
// Hloubka dna v metrech. Podle ní svítí lucerna na hlubší vrstvy víc.
uniform float pit_depth = 1.8;
uniform vec3 lamp_color : source_color = vec3(1.0, 0.7, 0.36);
// Dosah záře lucerny v px na okraji a na dně.
uniform float lamp_reach_top = 60.0;
uniform float lamp_reach_floor = 34.0;

const float VALUE_SCALE = 1.5;

varying vec2 local_pos;
varying float seed;

void vertex() {
	local_pos = VERTEX;
	vec2 anchor = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	seed = fract(sin(dot(floor(anchor), vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
	if (height_m != 0.0) {
		vec2 axis_x = (MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy;
		vec2 axis_y = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
		vec2 world_shift = (anchor - camera_position) * height_m * parallax * camera_zoom;
		float det = axis_x.x * axis_y.y - axis_y.x * axis_x.y;
		vec2 local_shift = vec2(
			world_shift.x * axis_y.y - world_shift.y * axis_y.x,
			axis_x.x * world_shift.y - axis_x.y * world_shift.x
		) / det;
		VERTEX += local_shift;
	}
}

// Plamen kmitá rychle a nepravidelně, občas krátce pohasne.
float flicker(float t, float s) {
	float f = 0.78;
	f += 0.13 * sin(t * 7.9 + s);
	f += 0.09 * sin(t * 13.7 + s * 2.1);
	f += 0.06 * sin(t * 23.3 + s * 4.7);
	f -= 0.3 * pow(max(sin(t * 1.3 + s * 3.3), 0.0), 16.0);
	return max(f, 0.2);
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	float deep = clamp(-height_m / max(pit_depth, 0.01), 0.0, 1.0);
	float value = mask.r * VALUE_SCALE;
	float ore = mask.g;
	vec3 rock = rock_color * value;
	vec3 stone = ore_color * mix(0.35, 1.3, mask.r);
	vec3 body = mix(rock, stone, ore);

	float f = flicker(TIME, seed);
	float reach = mix(lamp_reach_top, lamp_reach_floor, deep);
	float glow = mix(0.2, 1.5, deep) * exp(-dot(local_pos, local_pos) / (reach * reach)) * f;
	// Kámen materiálu je lesklý a světlo lucerny chytá víc než hlína.
	body *= vec3(1.0) + lamp_color * glow * mix(1.3, 1.9, ore);
	body += lamp_color * glow * 0.06;

	if (ore > 0.5 && mask.b > 0.04 && sparkle * sparkle_on > 0.001) {
		float wave = sin(TIME * 2.4 + seed + mask.b * 37.0);
		float flash = pow(max(wave, 0.0), 14.0) * sparkle * (0.6 + 0.8 * glow);
		body += glint_color * flash * 1.4;
	} else if (ore < 0.5 && mask.b > 0.04) {
		// Plamen lucerny.
		body = mix(body, vec3(1.0, 0.93, 0.7) * (0.85 + 0.25 * f), mask.b);
	}
	COLOR = vec4(body, mask.a);
}
