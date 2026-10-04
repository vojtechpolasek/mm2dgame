extends RefCounted

const ROOT := "res://graphics/terrain"
const TILE_SIZE := 64

var tile_set := TileSet.new()
var names := PackedStringArray()
var _pure: Dictionary = {}
var _transitions: Dictionary = {}


func load_assets() -> void:
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var root := DirAccess.open(ROOT)
	if root == null:
		push_error("Chybí složka terénu %s." % ROOT)
		return
	for entry in root.get_directories():
		if entry != "transitions" and not entry.begins_with("."):
			names.append(entry)
	names.sort()
	for terrain_name in names:
		_load_folder("%s/%s" % [ROOT, terrain_name], terrain_name, true)
	_load_folder("%s/transitions" % ROOT, "", false)


func pick_pure(terrain_name: String, rng: RandomNumberGenerator) -> int:
	return _pick(_pure, terrain_name, rng)


func pick_transition(key: String, rng: RandomNumberGenerator) -> int:
	return _pick(_transitions, key, rng)


func _load_folder(path: String, pure_name: String, is_pure: bool) -> void:
	var folder := DirAccess.open(path)
	if folder == null:
		if not is_pure:
			push_error("Chybí složka přechodů %s." % path)
		return
	var files := PackedStringArray()
	for entry in folder.get_files():
		if entry.ends_with(".png"):
			files.append(entry)
	files.sort()
	for file_name in files:
		var texture := load("%s/%s" % [path, file_name]) as Texture2D
		if texture == null:
			push_error("Nelze načíst %s/%s." % [path, file_name])
			continue
		if texture.get_width() != TILE_SIZE or texture.get_height() != TILE_SIZE:
			push_error("%s nemá stranu %d px." % [file_name, TILE_SIZE])
			continue
		var source := TileSetAtlasSource.new()
		source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
		source.use_texture_padding = false
		source.texture = texture
		var source_id := tile_set.add_source(source)
		source.create_tile(Vector2i.ZERO)
		var key := pure_name
		if not is_pure:
			var stem := file_name.get_basename()
			var split := stem.rfind("_")
			key = stem.substr(0, split)
		var bucket: Array = (_pure if is_pure else _transitions).get(key, [])
		bucket.append(source_id)
		if is_pure:
			_pure[key] = bucket
		else:
			_transitions[key] = bucket


func _pick(table: Dictionary, key: String, rng: RandomNumberGenerator) -> int:
	var bucket: Array = table.get(key, [])
	if bucket.is_empty():
		return -1
	return bucket[rng.randi_range(0, bucket.size() - 1)]
