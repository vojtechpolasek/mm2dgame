shader_type canvas_item;
render_mode blend_mix;

// Hluboká voda jezera: dlaždice celé ve vodě, kolem kterých je jen voda (TerrainChunks). Břeh,
// stín břehu ani pěna sem nedosáhnou, proto stačí předpečená textura vody (terrain_bake), dvě
// vlny a odlesky. Fáze vln, souřadnice odlesků i posun hladiny (water_parallax) jsou lineární
// v bodě světa, spočítají se ve vrcholech a pixel jen čte textury rovnou z varyingů. Na slabé
// grafice (Raspberry Pi) je to mnohem levnější než terrain_water. Vlny i odlesky počítá stejně
// jako hluboká voda v terrain_water, ať na hranici není šev.

#include "res://shaders/terrain_common.gdshaderinc"

uniform float chunk_px = 512.0;
global uniform vec2 camera_position;
global uniform float camera_zoom;

varying vec2 wave_phase;
varying vec2 glint_uv;
varying vec2 surface_uv;

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vec2 shift = water_parallax(world, camera_position, camera_zoom);
	vec2 surface_pos = world + shift;
	wave_phase = wave_phases(surface_pos).xy;
	vec2 ridge = vec2(dot(surface_pos, vec2(wave_dir_a.y, -wave_dir_a.x)), dot(surface_pos, wave_dir_a) - TIME * wave_speed * 6.0);
	glint_uv = ridge / vec2(glint_scale, glint_scale * 0.4) / GLINT_CELLS;
	surface_uv = UV + shift / chunk_px;
}

void fragment() {
	float height = (sin(wave_phase.x) + sin(wave_phase.y) * 0.65) / 1.65;
	vec3 color = mix(texture(TEXTURE, surface_uv).rgb, wave_band(height), wave_tint);
	float glint = smoothstep(0.62, 0.85, texture(glint_noise, glint_uv).r);
	color = mix(color, highlight_color, glint * glint_strength * (0.5 + 0.5 * height));
	COLOR = vec4(color, 1.0);
}
