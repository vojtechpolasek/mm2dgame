shader_type canvas_item;
// Bez unshaded, ať svět obarví CanvasModulate (jed, tma).
render_mode blend_mix;

// Spodek a mezikruží továrny. Posun výšky je stejný jako v house_layer.gdshader,
// mezikruží se navíc otáčí, proto se posun přepočítá do souřadnic uzlu.
uniform float height_m = 0.0;
global uniform vec2 camera_position;
uniform float parallax = 0.016;
global uniform float camera_zoom;

// Váhy z tools/gen_factory.py: součet vah / krytí = shade_floor + (1 - shade_floor) * světlost.
// Import proto nesmí mít fix_alpha_border.
uniform vec3 color_r : source_color = vec3(0.69, 0.643, 0.549);
uniform vec3 color_g : source_color = vec3(0.4, 0.416, 0.439);
uniform vec3 color_b : source_color = vec3(0.839, 0.729, 0.471);
uniform vec2 shade = vec2(0.42, 1.1);
uniform float shade_floor = 0.2;
uniform vec2 sheen = vec2(0.16, 0.7);

// Příčky pásů kreslí shader, maska má jen holý pás. Pás k leží ve směru k * 45°,
// jižní (k = 2) je výstupek. belt_shift posouvá příčky ke středu, když po pásu jede kámen.
// Míry jsou v px od středu obrázku, cell_px je strana obrázku.
// lanes 2 jsou dva zásobníky na straně (typ hry Skafandry), osy lane_offset px od osy strany
// a poloviční šířka belt_half. Posun zásobníku je belt_shift[k * 2 + z], z 0 na záporné
// kolmici (-sin, cos), 1 na kladné. S jedním pásem je posun belt_shift[k].
uniform bool belts = false;
uniform float cell_px = 580.0;
uniform float belt_inner = 115.0;
uniform float belt_outer = 199.0;
uniform float belt_half = 19.2;
uniform float belt_rail = 3.1;
uniform float belt_pitch = 12.3;
uniform float belt_slat = 2.4;
uniform float slat_gain = 2.33;
uniform float drum_at = 171.0;
uniform float drum_half = 4.5;
uniform float belt_shift[16];
uniform int lanes = 1;
uniform float lane_offset = 0.0;
// Pás středem výstupku (k = 2) na skafandry, posun belt_shift[4]. Nula znamená bez pásu.
uniform float dock_outer = 0.0;
uniform float dock_drum = 0.0;

void vertex() {
	if (height_m > 0.0) {
		vec2 axis_x = (MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy;
		vec2 axis_y = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
		vec2 anchor = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
		vec2 world_shift = (anchor - camera_position) * height_m * parallax * camera_zoom;
		float det = axis_x.x * axis_y.y - axis_y.x * axis_x.y;
		vec2 local_shift = vec2(
			world_shift.x * axis_y.y - world_shift.y * axis_y.x,
			axis_x.x * world_shift.y - axis_x.y * world_shift.x
		) / det;
		VERTEX += local_shift;
	}
}

float slat_light(vec2 p) {
	float step_angle = 0.785398;
	int k = int(mod(floor(atan(p.y, p.x) / step_angle + 0.5) + 8.0, 8.0));
	float angle = float(k) * step_angle;
	vec2 n = vec2(cos(angle), sin(angle));
	float along = dot(p, n);
	float across = dot(p, vec2(-n.y, n.x));
	int index = k;
	float outer = belt_outer;
	float drum = drum_at;
	if (k == 2) {
		if (dock_outer <= 0.0) {
			return 1.0;
		}
		index = 4;
		outer = dock_outer;
		drum = dock_drum;
	} else if (lanes == 2) {
		int lane = across > 0.0 ? 1 : 0;
		across -= lane == 1 ? lane_offset : -lane_offset;
		index = k * 2 + lane;
	}
	float side = abs(across);
	if (along < belt_inner || along > outer || side > belt_half - belt_rail || abs(along - drum) <= drum_half) {
		return 1.0;
	}
	float phase = mod(along + belt_shift[index], belt_pitch);
	float soft = 0.6;
	float on = smoothstep(-soft, soft, phase) * (1.0 - smoothstep(belt_slat - soft, belt_slat + soft, phase));
	on = max(on, smoothstep(belt_pitch - soft, belt_pitch + soft, phase));
	return mix(1.0, slat_gain, on);
}

void fragment() {
	vec4 weight = texture(TEXTURE, UV);
	vec3 mixed = color_r * weight.r + color_g * weight.g + color_b * weight.b;
	float total = weight.r + weight.g + weight.b;
	vec3 base = mixed / max(total, 0.001);
	float light = clamp((total / max(weight.a, 0.001) - shade_floor) / (1.0 - shade_floor), 0.0, 1.0);
	if (belts) {
		light = min(light * slat_light((UV - 0.5) * cell_px), 1.0);
	}
	vec3 lit = base * mix(shade.x, shade.y, light);
	lit += sheen.x * (1.0 - dot(base, vec3(0.299, 0.587, 0.114))) * smoothstep(sheen.y, 1.0, light);
	COLOR = vec4(lit, weight.a);
}
