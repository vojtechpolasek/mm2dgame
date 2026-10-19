shader_type canvas_item;
render_mode unshaded;

// Vzduch nad čtvercem (square_air.gd): mlha nad močálem, padající sníh nad sněhem a růžový
// jedovatý nádech nad čtvercem nesplněného levelu. TEXTURE je maska terénu, dlaždice na texel:
// R kde je mlha, G kde sněží. Šum a vločky jedou ve světových souřadnicích, přes kraj čtverce
// proto navazují.

uniform float poison = 0.0;
uniform vec3 fog_color : source_color = vec3(0.80, 0.85, 0.78);
uniform vec3 poison_color : source_color = vec3(1.0, 0.58, 0.78);
uniform float fog_strength = 0.5;
uniform float poison_strength = 0.13;
// Vločky ve třech vrstvách: velikost buňky v pixelech, nejbližší vrstva první.
uniform vec3 flake_cells = vec3(150.0, 105.0, 72.0);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Hash bez sinu (Dave Hoskins), stejný jako u terénu.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.03 + 17.0) * 0.3 + noise(p * 4.1 + 41.0) * 0.15;
}

// Přes dosavadní barvu (předem vynásobenou průhledností) položí vrstvu.
void layer(inout vec4 acc, vec3 color, float alpha) {
	acc.rgb = acc.rgb * (1.0 - alpha) + color * alpha;
	acc.a = acc.a * (1.0 - alpha) + alpha;
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	vec2 m = world / 64.0;
	vec4 acc = vec4(0.0);
	if (mask.r > 0.01) {
		// Dvě vrstvy chuchvalců jedou pomalu proti sobě, mezi nimi prosvítá zem.
		float slow = fbm(m * 0.16 + vec2(TIME * 0.045, TIME * 0.018));
		float fast = fbm(m * 0.34 - vec2(TIME * 0.03, -TIME * 0.012));
		float cloud = smoothstep(0.32, 0.8, slow * 0.65 + fast * 0.35);
		layer(acc, fog_color, mask.r * cloud * fog_strength);
	}
	if (poison > 0.001) {
		// Jemné vlny přes celý čtverec, místy sytější.
		float wave = 0.5 + 0.5 * sin(m.x * 0.33 + TIME * 0.55 + 1.7 * sin(m.y * 0.24 + TIME * 0.37));
		float drift = noise(m * 0.09 + vec2(TIME * 0.035, -TIME * 0.02));
		layer(acc, poison_color, poison * poison_strength * (0.45 + 0.55 * wave * (0.6 + 0.8 * drift)));
	}
	if (mask.g > 0.01) {
		// Bílá vločka nad bílým sněhem by zmizela. Pod každou je proto modrošedý stín
		// posunutý dolů doprava, tím je vločka vidět nad sněhem i nad stromy.
		float flakes = 0.0;
		float shadows = 0.0;
		for (int i = 0; i < 3; i++) {
			float size = flake_cells[i];
			float fi = float(i);
			// Bližší vrstva padá rychleji. Vítr táhne vločky šikmo a lehce s nimi kývá.
			vec2 drift = vec2(TIME * (22.0 + 9.0 * fi) + sin(TIME * 0.7 + fi * 2.1) * 18.0, TIME * (38.0 - 8.0 * fi));
			vec2 p = (world - drift) / size;
			vec2 cell = floor(p);
			vec2 f = fract(p);
			if (hash(cell + fi * 13.7) > 0.5) {
				continue;
			}
			vec2 center = vec2(hash(cell + 3.1 + fi), hash(cell + 7.9 + fi)) * 0.6 + 0.2;
			float radius = (4.6 - 0.9 * fi) / size;
			float d = length(f - center);
			float shadow_d = length(f - center - vec2(4.0, 6.0) * (1.0 - 0.25 * fi) / size);
			flakes += smoothstep(radius, radius * 0.35, d) * (1.0 - 0.15 * fi);
			shadows += smoothstep(radius * 1.3, radius * 0.4, shadow_d) * (1.0 - 0.25 * fi);
		}
		layer(acc, vec3(0.42, 0.48, 0.6), clamp(shadows, 0.0, 1.0) * 0.4 * mask.g);
		layer(acc, vec3(1.0), clamp(flakes, 0.0, 1.0) * 0.95 * mask.g);
	}
	COLOR = acc.a > 0.0001 ? vec4(acc.rgb / acc.a, acc.a) : vec4(0.0);
}
