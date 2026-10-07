extends RefCounted

const ROOT := "res://graphics/terrain"
const TILE_SIZE := 64
const ATLAS_COLUMNS := 4
const _GROUND_SHADER := "res://shaders/terrain_ground.gdshader"
const _SHORE_COLORS := {
	"sand": "sand_color",
	"sand_wet": "sand_wet_color",
	"shallow": "shallow_color",
	"ice": "ice_color",
}
const _SHORE_FLOATS := [
	"shallow_from", "shallow_to", "shallow_strength",
	"sand_solid", "sand_solid_wobble", "sand_land_fade", "sand_land_fray",
	"sand_water", "sand_water_shift", "sand_strength",
	"ice_from", "ice_to", "ice_strength",
]

var tile_set := TileSet.new()
var names := PackedStringArray()
var surfaces := {}
var shore := {}
var max_distance := {}
var material: ShaderMaterial
var source_id := -1
var variant_count := 16

var _index := {}
var _corners: Image
var _variants: Image
var _corner_tex: ImageTexture
var _variant_tex: ImageTexture


func load_assets() -> void:
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	_load_surface_info()
	var root := DirAccess.open(ROOT)
	if root == null:
		push_error("Chybí složka terénu %s." % ROOT)
		return
	for entry in root.get_directories():
		if entry != "transitions" and not entry.begins_with("."):
			names.append(entry)
	names.sort()
	var images: Array[Image] = []
	for terrain_name in names:
		var path := "%s/%s/atlas.png" % [ROOT, terrain_name]
		var texture := load(path) as Texture2D
		if texture == null:
			push_error("Nelze načíst %s." % path)
			names = PackedStringArray()
			return
		var image := texture.get_image()
		if image == null or image.is_empty():
			push_error("Atlas %s nemá obraz." % path)
			names = PackedStringArray()
			return
		image = image.duplicate()
		image.convert(Image.FORMAT_RGB8)
		if image.has_mipmaps():
			image.clear_mipmaps()
		image.generate_mipmaps()
		images.append(image)
		_index[terrain_name] = images.size() - 1
	var terrains := Texture2DArray.new()
	if terrains.create_from_images(images) != OK:
		push_error("Nelze složit atlas terénů.")
		names = PackedStringArray()
		return
	_add_placeholder()
	_build_material(terrains)


func is_walkable(terrain_name: String) -> bool:
	var info: Dictionary = surfaces.get(terrain_name, {})
	return bool(info.get("walkable", true))


func index_of(terrain_name: String) -> int:
	return int(_index.get(terrain_name, -1))


func begin_map(size: int) -> void:
	_corners = Image.create(size, size, false, Image.FORMAT_RGBA8)
	_variants = Image.create(size, size, false, Image.FORMAT_R8)
	_corners.fill(Color(0, 0, 0, 1))
	_variants.fill(Color(0, 0, 0, 1))
	if material != null:
		material.set_shader_parameter("map_size", float(size))


func write_cell(x: int, y: int, top_left: int, top_right: int, bottom_left: int, bottom_right: int, variant: int) -> void:
	_corners.set_pixel(x, y, Color(top_left / 255.0, top_right / 255.0, bottom_left / 255.0, bottom_right / 255.0))
	_variants.set_pixel(x, y, Color(variant / 255.0, 0, 0, 1))


func finish_map() -> void:
	if _corner_tex == null or _corner_tex.get_width() != _corners.get_width():
		_corner_tex = ImageTexture.create_from_image(_corners)
		_variant_tex = ImageTexture.create_from_image(_variants)
	else:
		_corner_tex.update(_corners)
		_variant_tex.update(_variants)
	material.set_shader_parameter("corner_map", _corner_tex)
	material.set_shader_parameter("variant_map", _variant_tex)


func apply(layer: CanvasItem) -> void:
	layer.material = material


func _load_surface_info() -> void:
	surfaces.clear()
	shore.clear()
	max_distance.clear()
	var path := "%s/surfaces.json" % ROOT
	if not FileAccess.file_exists(path):
		push_warning("Chybí %s." % path)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst %s." % path)
		return
	variant_count = int(parsed.get("variants", 16))
	var listed_shore = parsed.get("shore", {})
	if typeof(listed_shore) == TYPE_DICTIONARY:
		shore = listed_shore
	var listed: Dictionary = parsed.get("surfaces", {})
	for terrain_name in listed:
		var info: Dictionary = listed[terrain_name]
		surfaces[terrain_name] = info
		if info.has("max_distance"):
			max_distance[terrain_name] = float(info["max_distance"])


func _add_placeholder() -> void:
	var image := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGB8)
	image.fill(Color(0.2, 0.45, 0.55))
	var source := TileSetAtlasSource.new()
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	source.use_texture_padding = false
	source.texture = ImageTexture.create_from_image(image)
	source_id = tile_set.add_source(source)
	if not source.has_tile(Vector2i.ZERO):
		source.create_tile(Vector2i.ZERO)


func _build_material(terrains: Texture2DArray) -> void:
	material = ShaderMaterial.new()
	material.shader = load(_GROUND_SHADER)
	material.set_shader_parameter("terrains", terrains)
	material.set_shader_parameter("tile_size", float(TILE_SIZE))
	material.set_shader_parameter("atlas_columns", float(ATLAS_COLUMNS))
	var styles := PackedFloat32Array()
	styles.resize(16)
	styles.fill(0.0)
	var liquid := -1
	for terrain_name in names:
		var index := index_of(terrain_name)
		var info: Dictionary = surfaces.get(terrain_name, {})
		var kind := str(info.get("shore", ""))
		if kind == "sand":
			styles[index] = 1.0
		elif kind == "ice":
			styles[index] = 2.0
		if info.has("wave"):
			liquid = index
	material.set_shader_parameter("shore_style", styles)
	material.set_shader_parameter("water_index", liquid)
	_apply_shore(shore)
	if liquid >= 0:
		_apply_wave(surfaces[names[liquid]].get("wave", {}))


func _apply_shore(shore: Dictionary) -> void:
	for key in _SHORE_COLORS:
		if shore.has(key):
			material.set_shader_parameter(_SHORE_COLORS[key], Color.html(str(shore[key])))
	for key in _SHORE_FLOATS:
		if shore.has(key):
			material.set_shader_parameter(key, float(shore[key]))


func _apply_wave(wave: Dictionary) -> void:
	material.set_shader_parameter("deep_color", Color.html(str(wave.get("deep", "245E78"))))
	material.set_shader_parameter("highlight_color", Color.html(str(wave.get("highlight", "4A8EAA"))))
	material.set_shader_parameter("wave_speed", float(wave.get("speed", 0.5)))
	material.set_shader_parameter("wave_scale", float(wave.get("scale", 14.0)))
	material.set_shader_parameter("wave_swell", float(wave.get("swell", 0.03)))
	material.set_shader_parameter("wave_tint", float(wave.get("tint", 0.18)))
	material.set_shader_parameter("wave_angle", float(wave.get("angle", 30.0)))
	material.set_shader_parameter("mask_start", float(wave.get("mask_start", 0.7)))
