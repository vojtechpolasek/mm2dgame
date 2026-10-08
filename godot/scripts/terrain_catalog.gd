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

var names := PackedStringArray()
var surfaces := {}
var shore := {}
var max_distance := {}
var max_share := {}
var material: ShaderMaterial
var variant_count := 16

var _index := {}


func load_assets() -> void:
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
	_build_material(terrains)


func index_of(terrain_name: String) -> int:
	return int(_index.get(terrain_name, -1))


## Data z MapGenerator.corner_data: čtyři bajty rohů a jeden bajt varianty na dlaždici.
func set_map(size: int, corners: PackedByteArray, variants: PackedByteArray) -> void:
	var corner_image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, corners)
	var variant_image := Image.create_from_data(size, size, false, Image.FORMAT_R8, variants)
	material.set_shader_parameter("map_size", float(size))
	material.set_shader_parameter("corner_map", ImageTexture.create_from_image(corner_image))
	material.set_shader_parameter("variant_map", ImageTexture.create_from_image(variant_image))


func apply(layer: CanvasItem) -> void:
	layer.material = material


func _load_surface_info() -> void:
	surfaces.clear()
	shore.clear()
	max_distance.clear()
	max_share.clear()
	var path := "%s/surfaces.json" % ROOT
	if not FileAccess.file_exists(path):
		push_warning("Chybí %s." % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst %s." % path)
		return
	variant_count = int(parsed.get("variants", 16))
	var listed_shore: Variant = parsed.get("shore", {})
	if typeof(listed_shore) == TYPE_DICTIONARY:
		shore = listed_shore
	var listed: Dictionary = parsed.get("surfaces", {})
	for terrain_name: String in listed:
		var info: Dictionary = listed[terrain_name]
		surfaces[terrain_name] = info
		if info.has("max_distance"):
			max_distance[terrain_name] = float(info["max_distance"])
		if info.has("max_share"):
			max_share[terrain_name] = float(info["max_share"])


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
	for key: String in _SHORE_COLORS:
		if shore.has(key):
			material.set_shader_parameter(_SHORE_COLORS[key], Color.html(str(shore[key])))
	for key: String in _SHORE_FLOATS:
		if shore.has(key):
			material.set_shader_parameter(key, float(shore[key]))


func _apply_wave(wave: Dictionary) -> void:
	material.set_shader_parameter("deep_color", Color.html(str(wave.get("deep", "245E78"))))
	material.set_shader_parameter("highlight_color", Color.html(str(wave.get("highlight", "4A8EAA"))))
	material.set_shader_parameter("wave_speed", float(wave.get("speed", 0.5)))
	material.set_shader_parameter("wave_scale", float(wave.get("scale", 14.0)))
	material.set_shader_parameter("wave_swell", float(wave.get("swell", 0.03)))
	material.set_shader_parameter("wave_tint", float(wave.get("tint", 0.18)))
	# Tři vlny jdou pod různými úhly. Směr je kolmice k hřebeni.
	var angle := deg_to_rad(float(wave.get("angle", 30.0)))
	material.set_shader_parameter("wave_dir_a", Vector2(-sin(angle), cos(angle)))
	material.set_shader_parameter("wave_dir_b", Vector2(-sin(angle + 1.15), cos(angle + 1.15)))
	material.set_shader_parameter("wave_dir_c", Vector2(-sin(angle + 2.4), cos(angle + 2.4)))
	material.set_shader_parameter("mask_start", float(wave.get("mask_start", 0.7)))
