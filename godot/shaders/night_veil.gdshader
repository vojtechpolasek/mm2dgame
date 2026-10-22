shader_type canvas_item;
render_mode blend_mul, unshaded;

// Světlo světa (day_night.gd): závoj přes celý záběr, kterým se svět vynásobí. Okolní světlo
// (ambient) je ve dne bílé, u obzoru teplé a v noci modré podle fáze měsíce. V noci k němu
// čelovky hráčů přidají kužel před postavou a slabou záři kolem ní.
// Stíny od čelovek počítá lamp_shade.gdshader do obrázku v polovičním rozlišení (lamp_light),
// závoj ho rozmaže, okraje stínů jsou měkké. Bez stínů (vypnuté v nastavení) svítí kužel celý.
// Koruny stromů jsou nad čelovkou: kde je v obrázku překážek maska koruny (kanál G), čelovka
// nesvítí a koruna zůstane tmavá. Stín kmene je tak jen na zemi kolem koruny.

#include "res://shaders/lamp_light.gdshaderinc"

uniform vec3 ambient : source_color = vec3(1.0);
uniform sampler2D occluders : filter_linear, repeat_disable, hint_default_black;
// 1 bere kužely se stíny z lamp_light, 0 kužely bez stínů (stíny vypnuté v nastavení).
uniform float lamp_shadows = 1.0;

const vec3 LAMP_COLOR = vec3(1.0, 0.94, 0.8);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec3 light = ambient;
	vec2 uv = view_uv(world);
	// Pod korunou stromu (kanál G obrázku překážek) čelovka nesvítí.
	float open_sky = in_view(uv) ? 1.0 - min(texture(occluders, uv).g, 1.0) : 1.0;
	if (lamp_on * open_sky > 0.001) {
		float beam = lamp_shadows > 0.5 && in_view(uv) ? shaded_beams_at(uv) : beams_at(world);
		light += LAMP_COLOR * max(beam, glows_at(world)) * lamp_on * open_sky;
	}
	COLOR = vec4(min(light, vec3(1.0)), 1.0);
}
