shader_type canvas_item;
render_mode unshaded;

// Obrázek stínů od slunce a měsíce roztažený přes svět (shadows.gd). Kde svítí čelovka,
// stín slábne až zmizí: v jejím světle stín od měsíce vidět není. Ve stínu od čelovky
// (lamp_light) měsíční stín zůstane. Obrázek světla čelovek se čte jednou bez rozmazání,
// jde jen o to, jak moc stín zeslábne.

#include "res://shaders/lamp_light.gdshaderinc"

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
	vec2 uv = view_uv(world);
	if (lamp_on > 0.001 && in_view(uv)) {
		vec2 lamp = texture(lamp_light, uv).rg;
		COLOR.a *= 1.0 - clamp((lamp.x + lamp.y) * lamp_on, 0.0, 1.0);
	}
}
