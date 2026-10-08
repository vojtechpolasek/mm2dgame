shader_type canvas_item;
render_mode unshaded;

// Stejný posun výšky jako tree_layer.gdshader. Výška 0 drží nohy na zemi.
uniform float height_m = 0.0;
global uniform vec2 camera_position;
uniform float parallax = 0.016;
uniform float scale_per_meter = 0.01;
global uniform float camera_zoom;

// 0 hlava (R kůže, G vlasy, B oči), 1 tělo (R triko, G kůže), 2 nohy (R kalhoty, G boty, B tkaničky).
// Alfa textury je krytí, ne další materiál. Váhy jsou z tools/gen_person.py vynásobené
// krytím a světlostí: součet vah / krytí = shade_floor + (1 - shade_floor) * světlost.
// Import proto nesmí mít fix_alpha_border, ten by průhledným okrajům přidal barvu.
instance uniform float slot = 0.0;
uniform vec2 shade = vec2(0.42, 1.1);
uniform float shade_floor = 0.2;
// Lesk ve světlé části objemu: síla a odkud začíná. Působí hlavně na tmavé barvy,
// černé triko by jinak bylo bez tvaru.
uniform vec2 sheen = vec2(0.16, 0.7);
instance uniform vec3 skin_color : source_color = vec3(0.965, 0.804, 0.690);
instance uniform vec3 hair_color : source_color = vec3(0.361, 0.227, 0.157);
instance uniform vec3 eye_color : source_color = vec3(0.141, 0.110, 0.102);
instance uniform vec3 shirt_color : source_color = vec3(0.125, 0.102, 0.094);
instance uniform vec3 pants_color : source_color = vec3(0.784, 0.294, 0.471);
instance uniform vec3 shoe_color : source_color = vec3(0.125, 0.110, 0.118);
instance uniform vec3 lace_color : source_color = vec3(0.690, 0.675, 0.682);

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
	vec4 weight = texture(TEXTURE, UV);
	vec3 mixed = skin_color * weight.r + hair_color * weight.g + eye_color * weight.b;
	if (slot > 0.5 && slot < 1.5) {
		mixed = shirt_color * weight.r + skin_color * weight.g;
	} else if (slot >= 1.5) {
		mixed = pants_color * weight.r + shoe_color * weight.g + lace_color * weight.b;
	}
	float total = weight.r + weight.g + weight.b;
	vec3 base = mixed / max(total, 0.001);
	float light = clamp((total / max(weight.a, 0.001) - shade_floor) / (1.0 - shade_floor), 0.0, 1.0);
	vec3 lit = base * mix(shade.x, shade.y, light);
	lit += sheen.x * (1.0 - dot(base, vec3(0.299, 0.587, 0.114))) * smoothstep(sheen.y, 1.0, light);
	COLOR = vec4(lit, weight.a);
}
