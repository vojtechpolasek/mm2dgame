shader_type texture_blit;

// Předpečení chunku terénu: souš, přechody a břehy jednou do textury. Pixel textury je pixel
// světa. Vodu nad tím rozvlní terrain_water.gdshader.

#include "res://shaders/terrain_common.gdshaderinc"

// Levý horní roh chunku ve světě a velikost jeho textury v pixelech.
uniform vec2 chunk_origin = vec2(0.0);
uniform float chunk_px = 512.0;

void blit() {
	vec2 world_pos = chunk_origin + UV * chunk_px;
	vec2 tile = floor(world_pos / tile_size);
	vec2 local_uv = (world_pos - tile * tile_size) / tile_size;
	vec2 data_uv = (tile + 0.5) / map_size;
	vec4 packed_ids = texture(corner_map, data_uv);
	float variant = round(texture(variant_map, data_uv).r * 255.0);

	vec3 surface;
	float share;
	float shore_kind;
	evaluate(local_uv, variant, 0.0, packed_ids, surface, share, shore_kind);
	COLOR0 = vec4(apply_shore(surface, share, shore_kind, world_pos), 1.0);
}
