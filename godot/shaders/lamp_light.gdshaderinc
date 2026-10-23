// Světlo čelovek, společné pro noční závoj (night_veil.gdshader), obrázek světla čelovek
// (lamp_shade.gdshader) a obrázek stínů od slunce a měsíce (shadow_shown.gdshader).
// Parametry nastavuje DayNight všem třem stejně.

// 0 až 1: jak moc čelovky svítí (za soumraku se rozsvítí).
uniform float lamp_on = 0.0;
uniform int lamp_count = 0;
// Čelovky: x, y poloha ve světě, z, w směr pohledu (jednotkový).
uniform vec4 lamps[6];
// Obdélník světa, který pokrývají obrázky překážek a stínů čelovek (shadows.gd).
uniform vec2 view_origin;
uniform vec2 view_size = vec2(1.0);
// Světlo čelovek ve čtvrtinovém rozlišení (lamp_shade.gdshader): R kužely (se stíny, když
// jsou zapnuté), G záře kolem postav. Jen tady se počítá smyčka přes čelovky, závoj a obrázek
// stínů už jen čtou. Smyčka v celoobrazovkovém průchodu je na slabé grafice drahá.
uniform sampler2D lamp_light : filter_linear, repeat_disable, hint_default_black;
// 1 kužely se stíny, 0 bez stínů (stíny vypnuté). Čte ho lamp_shade.gdshader.
uniform float lamp_shadows = 1.0;

// Dosah kuželu v px (8 m), polovina úhlu kuželu (45°) a měkký okraj.
// Stejná čísla má day_night.gd (obdélník kolem kuželu).
const float LAMP_RANGE = 512.0;
const float LAMP_HALF_ANGLE = 0.785;
const float LAMP_SOFT_ANGLE = 0.14;
// Záře kolem postavy: poloměr v px (1,5 m) a síla.
const float GLOW_RADIUS = 96.0;
const float GLOW = 0.35;

// Bod světa v obrázcích překážek a stínů čelovek. Mimo obrázek je souřadnice mimo 0 až 1.
vec2 view_uv(vec2 at) {
	return (at - view_origin) / view_size;
}

bool in_view(vec2 uv) {
	return uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0;
}

// Kužel čelovky lamp v bodě at, bez stínů. 1 uprostřed blízko, ke kraji a do dálky slábne.
float lamp_beam(vec2 at, vec4 lamp) {
	vec2 to = at - lamp.xy;
	float dist = length(to);
	if (dist > LAMP_RANGE) {
		return 0.0;
	}
	float facing = dot(to / max(dist, 1.0), lamp.zw);
	float cone = smoothstep(cos(LAMP_HALF_ANGLE + LAMP_SOFT_ANGLE), cos(LAMP_HALF_ANGLE - LAMP_SOFT_ANGLE), facing);
	return cone * (1.0 - smoothstep(LAMP_RANGE * 0.55, LAMP_RANGE, dist));
}

float lamp_glow(vec2 at, vec4 lamp) {
	return GLOW * (1.0 - smoothstep(GLOW_RADIUS * 0.3, GLOW_RADIUS, distance(at, lamp.xy)));
}

// Světlo čelovek z obrázku lamp_light (x kužely, y záře), rozmazané. Čtení na rohu mezi
// texely vrátí průměr čtyř texelů, dvě čtení přes úhlopříčku tak pokryjí skoro 4 x 4 pixely
// obrázku. Okraj stínu je pak měkký a zrno z trasování paprsků zmizí.
vec2 lamp_light_at(vec2 uv) {
	vec2 texel = 1.0 / vec2(textureSize(lamp_light, 0));
	vec2 sum = texture(lamp_light, uv + texel * vec2(-1.0, -1.0)).rg;
	sum += texture(lamp_light, uv + texel * vec2(1.0, 1.0)).rg;
	return sum * 0.5;
}
