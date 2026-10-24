shader_type canvas_item;
// Bez unshaded, ať svět obarví CanvasModulate (jed, tma).
render_mode blend_mix;

// Předpečený chunk terénu (terrain_chunks.gd). Alfa textury nese výšku břehu (terrain_bake):
// u jezera ji čte terrain_water, u břehů řeky na souši stín tady — jinak by pečený břeh
// řeky neměl stín (voda řeky nemá dlaždice s water meshem).

global uniform vec2 sun_shadow;
global uniform float shadow_opacity;

const float BANK_SHADOW_DEPTH = 0.9;
const float BANK_SHADOW = 0.9;
uniform float chunk_px = 512.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float shadow = 0.0;
	if (shadow_opacity > 0.001 && tex.a < 0.999) {
		vec2 back_uv = UV - sun_shadow * BANK_SHADOW_DEPTH / chunk_px;
		float back = texture(TEXTURE, clamp(back_uv, vec2(0.0), vec2(1.0))).a;
		shadow = clamp((back - tex.a) * 1.6, 0.0, 1.0) * shadow_opacity * BANK_SHADOW;
	}
	COLOR = vec4(tex.rgb * (1.0 - shadow), 1.0);
}
