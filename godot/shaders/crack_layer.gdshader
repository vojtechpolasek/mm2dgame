shader_type canvas_item;
render_mode unshaded;

// Vrstva lávové pukliny z gen_crack.py. Textura nese skutečné barvy.
// Záporná výška je pod zemí a posouvá se opačně než skály, puklina tak vypadá hluboká.
// Žár pulzuje: glow říká, jak moc vrstva svítí (okraj málo, láva nejvíc). Fázi bere
// z polohy pukliny, ať nepulzují všechny naráz. Posun vrstvy je nejvýš max_shift px textury,
// o tolik hlubší vrstvy sahají pod kůru.
// Hlubší vrstvy (masked) kreslí jen nad dírou: mask má stejné rozložení atlasu a nese díru
// bez posunu, čte se tedy na místě, kde pixel leží před posunem.

uniform float height_m = 0.0;
global uniform vec2 camera_position;
uniform float parallax = 0.016;
uniform float max_shift = 22.0;
uniform bool masked = false;
uniform sampler2D mask : filter_linear_mipmap;
global uniform float camera_zoom;

uniform float glow = 0.0;
uniform vec3 heat_color : source_color = vec3(1.0, 0.55, 0.16);

varying float seed;
varying vec2 shift;

void vertex() {
	vec2 anchor = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	seed = fract(sin(dot(floor(anchor), vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
	shift = vec2(0.0);
	if (height_m != 0.0) {
		vec2 axis_x = (MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy;
		vec2 axis_y = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
		vec2 world_shift = (anchor - camera_position) * height_m * parallax * camera_zoom;
		float det = axis_x.x * axis_y.y - axis_y.x * axis_x.y;
		vec2 local_shift = vec2(
			world_shift.x * axis_y.y - world_shift.y * axis_y.x,
			axis_x.x * world_shift.y - axis_x.y * world_shift.x
		) / det;
		float shift_length = length(local_shift);
		if (shift_length > max_shift) {
			local_shift *= max_shift / shift_length;
		}
		VERTEX += local_shift;
		shift = local_shift;
	}
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (masked) {
		tex.a *= texture(mask, UV + shift * TEXTURE_PIXEL_SIZE).r;
	}
	// Pomalý nádech a výdech, přes něj drobné mihotání.
	float pulse = 0.5 + 0.5 * sin(TIME * 1.1 + seed);
	pulse = pulse * 0.8 + 0.2 * (0.5 + 0.5 * sin(TIME * 3.7 + seed * 2.3));
	// Jasné (žhavé) pixely pulzují víc než tmavá kůra.
	float hot = max(tex.r - tex.b, 0.0);
	vec3 color = tex.rgb * (1.0 + glow * (pulse - 0.45) * 0.5 * hot);
	color += heat_color * glow * pulse * hot * 0.12;
	COLOR = vec4(color, tex.a * (1.0 + glow * (pulse - 0.5) * 0.3 * (1.0 - step(0.99, tex.a))));
}
