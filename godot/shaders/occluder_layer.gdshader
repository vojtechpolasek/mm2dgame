shader_type canvas_item;
render_mode unshaded;

// Překážka pro světlo čelovky (shadows.gd): kde vrstva je (krytí přes polovinu), zapíše
// do kanálu R svou výšku jako podíl HEIGHT_RANGE. Posunutá jako vrstva ve hře
// (tree_layer.gdshader), ať překážka sedí na tom, co je vidět.

uniform float height_m = 0.0;
uniform float parallax = 0.016;
global uniform vec2 camera_position;
global uniform float camera_zoom;
// Stejné číslo má shadows.gd (HEIGHT_RANGE) a night_veil.gdshader.
const float HEIGHT_RANGE = 16.0;

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
	COLOR = vec4(height_m / HEIGHT_RANGE, 0.0, 0.0, 1.0);
}
