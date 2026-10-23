shader_type canvas_item;
render_mode blend_mul, unshaded;

// Světlo světa (day_night.gd): závoj přes celý záběr, kterým se svět vynásobí. Okolní světlo
// (ambient) je ve dne bílé, u obzoru teplé a v noci modré podle fáze měsíce. V noci k němu
// čelovky hráčů přidají kužel před postavou a slabou záři kolem ní.
// Kužely se stíny i záři čelovek počítá lamp_shade.gdshader do obrázku ve čtvrtinovém
// rozlišení (lamp_light), závoj ho jen rozmaže, okraje stínů jsou měkké. Kam čelovky
// nedosvítí, je v obrázku 0 a zbude okolní světlo. Svět obarvený jedem (canvas_tint,
// CanvasModulate obarví i závoj) se tu vyrovná, ať se nenásobí dvakrát.
// Koruny stromů jsou nad čelovkou: kde je v obrázku překážek maska koruny (kanál G), čelovka
// nesvítí a koruna zůstane tmavá. Stín kmene je tak jen na zemi kolem koruny.

#include "res://shaders/lamp_light.gdshaderinc"

uniform vec3 ambient : source_color = vec3(1.0);
uniform vec3 canvas_tint = vec3(1.0);
uniform sampler2D occluders : filter_linear, repeat_disable, hint_default_black;

const vec3 LAMP_COLOR = vec3(1.0, 0.94, 0.8);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec3 light = ambient;
	vec2 uv = view_uv(world);
	if (lamp_on > 0.001 && in_view(uv)) {
		vec2 lamp = lamp_light_at(uv);
		float strength = max(lamp.x, lamp.y);
		if (strength > 0.001) {
			// Pod korunou stromu (kanál G obrázku překážek) čelovka nesvítí.
			float open_sky = 1.0 - min(texture(occluders, uv).g, 1.0);
			light += LAMP_COLOR * strength * lamp_on * open_sky;
		}
	}
	COLOR = vec4(min(light / max(canvas_tint, vec3(0.01)), vec3(1.0)), 1.0);
}
