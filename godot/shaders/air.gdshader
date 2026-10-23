shader_type canvas_item;
// Bez unshaded, ať svět obarví CanvasModulate (jed, tma).
render_mode blend_mix;

// Mlha nad močálem a padající sníh nad sněhem (square_air.gd). Kreslí se jen kusy čtverce,
// kde mlha nebo sníh jsou. TEXTURE je maska terénu, dlaždice na texel: R kde je mlha, G kde
// sněží. Šum mlhy a vločky jsou předpočítané opakovatelné textury, jedou ve světových
// souřadnicích, přes kraj kusu i čtverce proto navazují.

uniform sampler2D fog_noise : filter_linear, repeat_enable;
uniform sampler2D flakes : filter_linear, repeat_enable;
uniform vec3 fog_color : source_color = vec3(0.80, 0.85, 0.78);
uniform float fog_strength = 0.5;
// Kolik pixelů světa zabere jedna textura šumu: pomalá a rychlá vrstva chuchvalců.
uniform vec2 fog_spans = vec2(3200.0, 1500.0);
// Kolik pixelů světa zabere jedna textura vloček: bližší a vzdálenější vrstva.
uniform vec2 flake_spans = vec2(512.0, 360.0);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Přes dosavadní barvu (předem vynásobenou průhledností) položí vrstvu.
void layer(inout vec4 acc, vec3 color, float alpha) {
	acc.rgb = acc.rgb * (1.0 - alpha) + color * alpha;
	acc.a = acc.a * (1.0 - alpha) + alpha;
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	vec4 acc = vec4(0.0);
	if (mask.r > 0.01) {
		// Dvě vrstvy chuchvalců jedou pomalu proti sobě, mezi nimi prosvítá zem.
		float slow = texture(fog_noise, world / fog_spans.x + vec2(TIME * 0.0056, TIME * 0.0023)).r;
		float fast = texture(fog_noise, world / fog_spans.y + vec2(0.37 - TIME * 0.0038, 0.61 + TIME * 0.0015)).r;
		float cloud = smoothstep(0.32, 0.8, slow * 0.65 + fast * 0.35);
		layer(acc, fog_color, mask.r * cloud * fog_strength);
	}
	if (mask.g > 0.01) {
		// Bližší vrstva padá rychleji. Vítr táhne vločky šikmo a lehce s nimi kývá.
		vec2 near = vec2(TIME * 22.0 + sin(TIME * 0.7) * 18.0, TIME * 38.0);
		vec2 far = vec2(TIME * 31.0 + sin(TIME * 0.7 + 2.1) * 18.0, TIME * 30.0);
		float flake = texture(flakes, (world - near) / flake_spans.x).r;
		flake = max(flake, texture(flakes, (world - far) / flake_spans.y + vec2(0.43, 0.27)).r * 0.85);
		layer(acc, vec3(1.0), flake * 0.95 * mask.g);
	}
	COLOR = acc.a > 0.0001 ? vec4(acc.rgb / acc.a, acc.a) : vec4(0.0);
}
