shader_type canvas_item;

// Nadpis z barev materiálů (material_title.gd). Barvu písmene dává text, shader ji jen
// nasvítí jako broušený kámen: horní část písmen je světlejší, pod hranou uprostřed tmavší.
// Svisle se počítá v pixelech nadpisu, horní a dolní hranu písmen posílá skript.

uniform float letter_top = 0.0;
uniform float letter_height = 32.0;

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	vec4 color = texture(TEXTURE, UV) * COLOR;
	float t = clamp((local_y - letter_top) / letter_height, 0.0, 1.0);
	// Horní ploška světlá, spodní tmavší, mezi nimi hrana jako u kamenů ve hře.
	float light = mix(1.3, 1.02, smoothstep(0.0, 0.46, t));
	light = mix(light, mix(0.92, 0.72, smoothstep(0.5, 1.0, t)), smoothstep(0.44, 0.52, t));
	color.rgb *= light;
	COLOR = color;
}
