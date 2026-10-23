shader_type canvas_item;
render_mode unshaded;

// Předpečený chunk terénu (terrain_chunks.gd). Alfa textury nese výšku břehu pro stín ve vodě
// (terrain_bake.gdshader), chunk se proto kreslí neprůhledně jen barvou.

void fragment() {
	COLOR = vec4(texture(TEXTURE, UV).rgb, 1.0);
}
