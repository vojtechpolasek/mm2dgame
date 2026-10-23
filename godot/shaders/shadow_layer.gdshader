shader_type canvas_item;
render_mode unshaded;

// Stín jedné vrstvy objektu na zemi (shadows.gd). Silueta vrstvy (krytí textury) černě,
// posunutá ve světě o sun_shadow * height_m: sun_shadow je posun v px na metr výšky, míří
// od slunce nebo měsíce a délku má podle jejich výšky nad obzorem (day_night.gd).
// Vrstva s sweep_m > 0 je spodek plného tělesa (skála, postava): stín se táhne od výšky
// height_m - sweep_m až k height_m, ať se při dlouhém stínu neodtrhne od paty. Obrázek se
// proto posouvá po kouscích a bere se největší krytí. Quad se natáhne o celý tah.
// Sprite je vždy na středu (centered, bez offsetu), rámeček atlasu je pak kolem UV středu.

uniform float height_m = 1.0;
uniform float sweep_m = 0.0;
global uniform vec2 sun_shadow;
// Krok vzorků tahu v px obrázku a nejvíc vzorků. Obrázek stínů je ve čtvrtinovém rozlišení,
// hustší vzorky by v něm nebyly vidět.
const float SWEEP_STEP = 16.0;
const int SWEEP_MAX = 12;

varying vec2 center_uv;
varying vec2 half_uv;
varying vec2 sweep_uv;

// Posun ve světě do souřadnic spritu (inverze natočení a měřítka uzlu).
vec2 to_local(vec2 world, mat4 model) {
	vec2 axis_x = (model * vec4(1.0, 0.0, 0.0, 0.0)).xy;
	vec2 axis_y = (model * vec4(0.0, 1.0, 0.0, 0.0)).xy;
	float det = axis_x.x * axis_y.y - axis_y.x * axis_x.y;
	return vec2(world.x * axis_y.y - world.y * axis_y.x, axis_x.x * world.y - axis_x.y * world.x) / det;
}

void vertex() {
	vec2 shift = to_local(sun_shadow * height_m, MODEL_MATRIX);
	vec2 back = to_local(sun_shadow * sweep_m, MODEL_MATRIX);
	center_uv = UV - VERTEX * TEXTURE_PIXEL_SIZE;
	half_uv = abs(VERTEX) * TEXTURE_PIXEL_SIZE;
	sweep_uv = back * TEXTURE_PIXEL_SIZE;
	// Rohy na straně k zemi (proti posunu) se natáhnou o tah, obrázek zůstane na místě.
	vec2 grow = -back * step(0.0, -dot(VERTEX, back));
	VERTEX += shift + grow;
	UV += grow * TEXTURE_PIXEL_SIZE;
}

void fragment() {
	float reach = length(sweep_uv / TEXTURE_PIXEL_SIZE);
	int count = int(clamp(reach / SWEEP_STEP, 0.0, float(SWEEP_MAX)));
	float alpha = 0.0;
	for (int i = 0; i <= count; i++) {
		vec2 at = UV + sweep_uv * (count > 0 ? float(i) / float(count) : 0.0);
		vec2 off = abs(at - center_uv);
		if (off.x < half_uv.x && off.y < half_uv.y) {
			alpha = max(alpha, texture(TEXTURE, at).a);
		}
	}
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
