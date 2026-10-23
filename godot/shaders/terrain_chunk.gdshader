shader_type canvas_item;
// Bez unshaded, ať svět obarví CanvasModulate (jed, tma).
render_mode blend_mix;

// Předpečený chunk terénu (terrain_chunks.gd). Alfa textury nese výšku břehu pro stín ve vodě
// (terrain_bake.gdshader), chunk se proto kreslí neprůhledně jen barvou.

void fragment() {
	COLOR = vec4(texture(TEXTURE, UV).rgb, 1.0);
}
