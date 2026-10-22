shader_type canvas_item;
render_mode unshaded, blend_add;

// Maska korun stromů pro čelovky (shadows.gd): kde koruna je (krytí přes polovinu), přičte
// do kanálu G obrázku překážek jedničku. Výšky překážek v kanálu R zůstanou, jak byly.
// Noční závoj (night_veil.gdshader) na koruně čelovku nepřidá, koruna nad čelovkou zůstane
// tmavá. Posunutá jako vrstva ve hře (occluder_layer.gdshader).

uniform float height_m = 0.0;
uniform float parallax = 0.016;
global uniform vec2 camera_position;
global uniform float camera_zoom;

void vertex() {
	vec2 axis_x = (MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy;
	vec2 axis_y = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
	vec2 anchor = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	vec2 world_shift = (anchor - camera_position) * height_m * parallax * camera_zoom;
	float det = axis_x.x * axis_y.y - axis_y.x * axis_x.y;
	VERTEX += vec2(
		world_shift.x * axis_y.y - world_shift.y * axis_y.x,
		axis_x.x * world_shift.y - axis_x.y * world_shift.x
	) / det;
}

void fragment() {
	if (texture(TEXTURE, UV).a < 0.5) {
		discard;
	}
	COLOR = vec4(0.0, 1.0, 0.0, 1.0);
}
