shader_type canvas_item;
render_mode unshaded;

// Stejný posun výšky jako person_layer.gdshader. Všechny příšery sdílejí jeden materiál,
// výška a barvy jsou instanční. Výška 0 drží nohy na zemi.
instance uniform float height_m = 0.0;
global uniform vec2 camera_position;
uniform float parallax = 0.016;
uniform float scale_per_meter = 0.01;
global uniform float camera_zoom;

// Masky z tools/gen_monsters.py: R světlost, G podíl kresby, B oči, alfa krytí.
// tělo = barva * mix(shade), kresba = akcent * mix(accent_shade), oči přes obojí.
uniform vec2 shade = vec2(0.35, 1.15);
uniform vec2 accent_shade = vec2(0.6, 1.1);
instance uniform vec3 body_color : source_color = vec3(0.5);
instance uniform vec3 accent_color : source_color = vec3(0.8);
instance uniform vec3 eye_color : source_color = vec3(1.0, 0.3, 0.2);
// Stínová vrstva létající příšery: černá s tímto krytím. 0 je běžná vrstva.
instance uniform float shadow_alpha = 0.0;

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
		COLOR = vec4(mix(skin, eye_color, mask.b), mask.a);
	}
}
