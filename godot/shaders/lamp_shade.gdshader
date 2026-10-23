shader_type canvas_item;
render_mode unshaded;

// Kužely čelovek se stíny (shadows.gd, obrázek ve čtvrtinovém rozlišení přes záběr, kreslí se
// jen kolem čelovek). Noční závoj (night_veil.gdshader) obrázek rozmaže a přidá do světla,
// stíny jsou pak měkké.
// Stíny: paprsek z místa ke čelovce (ve výšce LAMP_HEIGHT) jde přes obrázek výšek překážek.
// Když cestou narazí na vyšší překážku, než kudy paprsek letí, místo je ve stínu a kužel tam
// nesvítí. Místo na překážce (vršek skály) začíná paprsek v její výšce, ať překážka nestíní
// sama sobě. Bez stínů (lamp_shadows 0) svítí kužel celý. Do kanálu R jde součet kuželů,
// do G záře kolem postav (0 až 1).

#include "res://shaders/lamp_light.gdshaderinc"

uniform sampler2D occluders : filter_linear, repeat_disable, hint_default_black;

// Stejná čísla má shadows.gd (LAMP_HEIGHT, HEIGHT_RANGE).
const float LAMP_HEIGHT = 1.5;
const float HEIGHT_RANGE = 16.0;
// Krok paprsku v px světa a nejvíc kroků. Delší krok by tenkou překážku přeskočil.
const float STEP_PX = 14.0;
const int STEPS_MAX = 40;
// Kolik světla kuželu projde do stínu.
const float SHADE_LEFT = 0.12;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float height_at(vec2 at) {
	vec2 uv = view_uv(at);
	if (!in_view(uv)) {
		return 0.0;
	}
	return texture(occluders, uv).r * HEIGHT_RANGE;
}

// 1 když na čelovku z místa vidí, SHADE_LEFT když jí něco stíní. Kroky jsou posunuté podle
// pravidelného šumu (jitter 0 až 1), po rozmazání je okraj stínu hladký.
float lit_from(vec2 lamp, float jitter) {
	float start = height_at(world);
	int steps = int(clamp(distance(world, lamp) / STEP_PX, 4.0, float(STEPS_MAX)));
	for (int i = 1; i < steps; i++) {
		float t = (float(i) - jitter * 0.9) / float(steps);
		float ray = mix(start, LAMP_HEIGHT, t);
		if (height_at(mix(world, lamp, t)) > ray + 0.05) {
			return SHADE_LEFT;
		}
	}
	return 1.0;
}

void fragment() {
	// Šum s rovnoměrně rozprostřenými hodnotami (interleaved gradient noise).
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float beam = 0.0;
	float glow = 0.0;
	for (int i = 0; i < lamp_count; i++) {
		float one = lamp_beam(world, lamps[i]);
		if (one > 0.001) {
			beam += lamp_shadows > 0.5 ? one * lit_from(lamps[i].xy, jitter) : one;
		}
		glow += lamp_glow(world, lamps[i]);
	}
	COLOR = vec4(min(beam, 1.0), min(glow, 1.0), 0.0, 1.0);
}
