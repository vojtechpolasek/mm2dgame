shader_type canvas_item;
// Bez unshaded, ať svět obarví CanvasModulate (jed, tma).
render_mode blend_mix;

// Stejný posun výšky jako tree_layer.gdshader, bez zvětšení. Střecha má zůstat
// stejně velká jako ve středu záběru, jinak by přerostla stěnu. Stěna má výšku 0.
// Každý dům má své materiály. Instanční uniformy by se ve světě s mnoha čtverci
// nevešly do bufferu a domy by dostaly cizí barvy.
uniform float height_m = 0.0;
global uniform vec2 camera_position;
uniform float parallax = 0.016;
global uniform float camera_zoom;

// 0 střecha (R krytina, G dřevo, B otvor), 1 stěna (R stěna, G dřevo, B sklo).
// Alfa je krytí. Váhy jsou z tools/gen_houses.py vynásobené krytím a světlostí:
// součet vah / krytí = shade_floor + (1 - shade_floor) * světlost.
// Import proto nesmí mít fix_alpha_border.
uniform float slot = 0.0;
uniform vec2 shade = vec2(0.42, 1.1);
uniform float shade_floor = 0.2;
uniform vec2 sheen = vec2(0.16, 0.7);
uniform vec3 roof_color : source_color = vec3(0.769, 0.580, 0.282);
uniform vec3 wall_color : source_color = vec3(0.769, 0.722, 0.635);
uniform vec3 wood_color : source_color = vec3(0.424, 0.282, 0.157);
uniform vec3 glass_color : source_color = vec3(0.588, 0.769, 0.808);
uniform vec3 opening_color : source_color = vec3(0.141, 0.118, 0.102);

void vertex() {
	if (height_m > 0.0) {
		vec2 axis_x = (MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy;
		vec2 axis_y = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
		vec2 anchor = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
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
	vec3 mixed = roof_color * weight.r + wood_color * weight.g + opening_color * weight.b;
	if (slot >= 0.5) {
		mixed = wall_color * weight.r + wood_color * weight.g + glass_color * weight.b;
	}
	float total = weight.r + weight.g + weight.b;
	vec3 base = mixed / max(total, 0.001);
	float light = clamp((total / max(weight.a, 0.001) - shade_floor) / (1.0 - shade_floor), 0.0, 1.0);
	vec3 lit = base * mix(shade.x, shade.y, light);
	lit += sheen.x * (1.0 - dot(base, vec3(0.299, 0.587, 0.114))) * smoothstep(sheen.y, 1.0, light);
	COLOR = vec4(lit, weight.a);
}
