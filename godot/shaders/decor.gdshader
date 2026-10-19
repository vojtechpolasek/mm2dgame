shader_type canvas_item;

// Průchozí porost z MultiMesh (ground_decor.gd). Každá instance nese ve vlastních datech
// sloupec a řádek buňky atlasu, UV čtverce se posune do té buňky.

// Velikost buňky atlasu v UV.
uniform vec2 cell_uv = vec2(0.125, 0.125);

void vertex() {
	UV = (INSTANCE_CUSTOM.xy + UV) * cell_uv;
}
