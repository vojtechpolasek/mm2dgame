shader_type canvas_item;
render_mode unshaded;

// Obrázek stínů od slunce a měsíce roztažený přes svět (shadows.gd). Kde svítí čelovka,
// stín slábne až zmizí: v jejím světle stín od měsíce vidět není. Ve stínu od čelovky
// (lamp_light) měsíční stín zůstane.

#include "res://shaders/lamp_light.gdshaderinc"

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
	if (lamp_on > 0.001) {
		vec2 uv = view_uv(world);
		float beam = in_view(uv) ? shaded_beams_at(uv) : beams_at(world);
		COLOR.a *= 1.0 - clamp((beam + glows_at(world)) * lamp_on, 0.0, 1.0);
	}
}
