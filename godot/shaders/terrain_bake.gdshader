shader_type texture_blit;
render_mode blend_disabled;

// Předpečení chunku terénu: souš, přechody a břehy jednou do textury. Pixel textury je pixel
// světa. Vodu nad tím rozvlní terrain_water.gdshader. Kolem jezera je svah dolů k hladině
// podle terénu (lake_bank). Břehy řeky ze stejného pečení (river_bank, pole z river.gd).
// Stín břehu přidá terrain_water (u vody) a terrain_chunk (souš u řeky).
// Hluboká voda (od DEEP_BAKE) dostane rovnou texturu vody, jak ji kreslí terrain_water, ať ji
// voda v každém snímku nepočítá. Do alfy jde výška břehu (jezero i řeka, 1 souš, 0 hladina).
// Chunk se kreslí s alfou 1 (terrain_chunk.gdshader).

#include "res://shaders/terrain_common.gdshaderinc"

// Levý horní roh chunku ve čtverci a velikost jeho textury v pixelech.
uniform vec2 chunk_origin = vec2(0.0);
// Levý horní roh čtverce ve světě. Textura vody má varianty podle dlaždic světa.
uniform vec2 map_origin = vec2(0.0);
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
	float mass = water_mass_at(world_pos);
	if (mass > 0.0 && mass < 1.0) {
		surface = lake_bank(surface, mass, world_pos, 0.0);
	}
	surface = river_bank(surface, world_pos, 0.0);
	if (share >= DEEP_BAKE) {
		surface = water_texture(map_origin + world_pos, 0.0);
	}
	COLOR0 = vec4(surface, min(lake_height(world_pos), river_height(world_pos)));
}
