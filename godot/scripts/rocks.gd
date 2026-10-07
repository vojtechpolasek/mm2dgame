extends Node2D

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")

const ROOT := "res://graphics/objects/rocks"
const INFO_PATH := ROOT + "/rocks.json"
const _SHADER_PATH := "res://shaders/tree_layer.gdshader"

## Pás kolem mapy. Šířka je v metrech a mění se podle úhlu, ať to není rovná řada.
const RIM_NEAR := 3.0
const RIM_FAR := 12.0
## Kolikrát se v jednom dlaždici okraje zkusí skála, ať v pásu nezůstanou díry.
const RIM_TRIES := 6
## Středy na okraji jsou blíž než součet poloměrů, takže se paty dotýkají a lehce překrývají.
const RIM_TOUCH := 0.78
const RIM_WEIGHTS := {
	"skala15": 0.2,
	"skala2": 0.22,
	"skala10": 0.18,
	"skala1": 0.24,
	"balvan1": 0.16,
}

var _camera: Camera2D
var _shader: Shader
var _species := {}
var _materials: Array[ShaderMaterial] = []
var _material_for_height := {}
var _sprites: Array[Sprite2D] = []
var _tallest := 0.0
var _reach := 8.0
var _shader_on := true
var _fitted_view := Vector2.ZERO
var _blockers: Array[Dictionary] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	process_priority = 10


func _process(_delta: float) -> void:
	_follow_camera()


func blockers() -> Array[Dictionary]:
	return _blockers


## Nejdřív pás kolem mapy, potom skály podle povrchu. Stromy se sází až potom.
func plant(
	terrain: PackedStringArray,
	size: int,
	surfaces: Dictionary,
	rng: RandomNumberGenerator,
	camera: Camera2D,
	host: Node2D = null,
	chunks: Node = null,
) -> void:
	_camera = camera
	_blockers = []
	if not _load_catalog():
		return
	_warn_unknown(surfaces)
	_measure()
	var view := _camera.get_viewport_rect().size
	_shader_on = ObjectLayers.shader_needed(view, _camera.zoom.x, _tallest)
	_fitted_view = view
	if chunks != null:
		chunks.grow_margin(_reach)
	var parent := host if host != null else self
	var spots: Array[Spot] = []
	var buckets := {}
	var reach := _max_gap()
	_place_rim(terrain, size, surfaces, rng, spots, buckets, reach)
	_scatter(terrain, size, surfaces, rng, spots, buckets, reach)
	for spot in spots:
		_spawn(spot, parent, chunks)
	_follow_camera()


func _follow_camera() -> void:
	if _camera == null:
		return
	var center := _camera.get_screen_center_position()
	var zoom := _camera.zoom.x
	var view := _camera.get_viewport_rect().size
	var want := ObjectLayers.shader_needed(view, zoom, _tallest)
	if want != _shader_on or view != _fitted_view:
		_shader_on = want
		_fitted_view = view
		_refit_sprites()
	if not _shader_on:
		return
	for material in _materials:
		material.set_shader_parameter("camera_position", center)
		material.set_shader_parameter("camera_zoom", zoom)


func _load_catalog() -> bool:
	if not _species.is_empty():
		return true
	_shader = load(_SHADER_PATH)
	if _shader == null:
		push_error("Chybí shader vrstev skály.")
		return false
	if not FileAccess.file_exists(INFO_PATH):
		push_error("Chybí %s." % INFO_PATH)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(INFO_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst %s." % INFO_PATH)
		return false
	var columns := int(parsed.get("atlas_columns", 3))
	var listed: Dictionary = parsed.get("rocks", {})
	for rock_name in listed:
		var built := _load_rock(str(rock_name), listed[rock_name], columns)
		if not built.is_empty():
			_species[rock_name] = built
	if _species.is_empty():
		push_error("V katalogu skal není žádná skála s atlasem.")
		return false
	return true


func _load_rock(rock_name: String, info: Dictionary, columns: int) -> Dictionary:
	var variants := maxi(int(info.get("variants", 9)), 1)
	var listed: Dictionary = info.get("layers", {})
	var keys: Array = listed.keys()
	keys.sort_custom(func(a, b) -> bool: return int(a) < int(b))
	var layers: Array[Dictionary] = []
	for key in keys:
		var layer_info: Dictionary = listed[key]
		var texture := _texture_from("%s/%s/layer_%s.png" % [ROOT, rock_name, str(key)])
		if texture == null:
			push_error("Chybí vrstva %s skály %s." % [str(key), rock_name])
			return {}
		layers.append({
			"height": float(layer_info.get("height", 0.0)),
			"texture": texture,
		})
	if layers.is_empty():
		push_error("Skála %s nemá vrstvy." % rock_name)
		return {}
	var base_width := float(listed[keys[0]].get("width", 64.0))
	return {
		"columns": columns,
		"rows": ceili(float(variants) / float(columns)),
		"variants": variants,
		"spacing": float(info.get("spacing", 1.0)),
		"radius": base_width * 0.5,
		"layers": layers,
	}


func _texture_from(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		if imported != null:
			return ObjectLayers.with_mipmaps(imported)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return ObjectLayers.with_mipmaps(ImageTexture.create_from_image(image))


func _warn_unknown(surfaces: Dictionary) -> void:
	for terrain_name in surfaces:
		for rock_name in _rocks_of(str(terrain_name), surfaces):
			if not _species.has(rock_name):
				push_warning("Terén %s chce skálu %s, ta nemá atlas." % [terrain_name, rock_name])


func _place_rim(
	terrain: PackedStringArray,
	size: int,
	surfaces: Dictionary,
	rng: RandomNumberGenerator,
	spots: Array[Spot],
	buckets: Dictionary,
	reach: float,
) -> void:
	for index in _shuffled_indices(size * size, rng):
		var x := index % size
		var y := index / size
		if not _in_rim(x, y, size):
			continue
		if not _walkable(terrain[index], surfaces):
			continue
		var rock_name := _rim_kind(rng)
		if rock_name.is_empty():
			continue
		for _try in RIM_TRIES:
			var pos := _anywhere(x, y, rng)
			if not _has_room(pos, rock_name, spots, buckets, reach, true):
				continue
			_keep(spots, buckets, reach, rock_name, pos, rng)
			break


func _scatter(
	terrain: PackedStringArray,
	size: int,
	surfaces: Dictionary,
	rng: RandomNumberGenerator,
	spots: Array[Spot],
	buckets: Dictionary,
	reach: float,
) -> void:
	for rock_name in _species_order():
		for index in _shuffled_indices(size * size, rng):
			var rocks := _rocks_of(terrain[index], surfaces)
			if not rocks.has(rock_name):
				continue
			var weight := float(rocks[rock_name])
			if weight <= 0.0:
				continue
			var x := index % size
			var y := index / size
			for _attempt in _attempts(weight, rng):
				var pos := _point(x, y, size, terrain, surfaces, rng)
				if not _has_room(pos, rock_name, spots, buckets, reach):
					continue
				_keep(spots, buckets, reach, rock_name, pos, rng)


func _keep(
	spots: Array[Spot],
	buckets: Dictionary,
	reach: float,
	rock_name: String,
	pos: Vector2,
	rng: RandomNumberGenerator,
) -> void:
	var spot := Spot.new()
	spot.rock = rock_name
	spot.position = pos
	spot.variant = rng.randi_range(0, int(_species[rock_name]["variants"]) - 1)
	spot.rotation = rng.randf() * TAU
	spots.append(spot)
	_remember(pos, spots.size() - 1, buckets, reach)
	_blockers.append({"position": pos, "gap": _pair_gap(rock_name, rock_name)})


func _spawn(spot: Spot, host: Node2D, chunks: Node) -> void:
	var rock: Dictionary = _species[spot.rock]
	var columns := int(rock["columns"])
	var rows := int(rock["rows"])
	var node := Node2D.new()
	node.position = spot.position
	node.rotation = spot.rotation
	node.visible = false
	for layer in rock["layers"]:
		var info: Dictionary = layer
		_add_layer(node, info["texture"], float(info["height"]), spot.variant, columns, rows)
	host.add_child(node)
	if chunks != null:
		chunks.adopt(node)
	_fit_node(node)


func _add_layer(
	node: Node2D,
	texture: Texture2D,
	height: float,
	variant: int,
	columns: int,
	rows: int,
) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.hframes = columns
	sprite.vframes = rows
	sprite.frame = clampi(variant, 0, columns * rows - 1)
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.set_meta("layer_height", height)
	_sprites.append(sprite)
	node.add_child(sprite)


func _fit_node(node: Node2D) -> void:
	if _camera == null:
		return
	var view := _camera.get_viewport_rect().size
	for child in node.get_children():
		var sprite := child as Sprite2D
		var height := float(sprite.get_meta("layer_height"))
		ObjectLayers.fit_sprite(sprite, _material_for(height), view, _shader_on)


func _refit_sprites() -> void:
	for sprite in _sprites:
		var height := float(sprite.get_meta("layer_height"))
		ObjectLayers.fit_sprite(sprite, _material_for(height), _fitted_view, _shader_on)


func _measure() -> void:
	_tallest = 0.0
	_reach = 8.0
	for rock_name in _species:
		var rock: Dictionary = _species[rock_name]
		var columns := maxi(int(rock["columns"]), 1)
		var rows := maxi(int(rock["rows"]), 1)
		for layer in rock["layers"]:
			var info: Dictionary = layer
			var texture: Texture2D = info["texture"]
			var height := float(info["height"])
			_tallest = maxf(_tallest, height)
			var frame := maxf(texture.get_width() / float(columns), texture.get_height() / float(rows))
			var reach := frame * 0.5 + 8.0
			_reach = maxf(_reach, reach)


func _material_for(height: float) -> ShaderMaterial:
	var key := "%.3f" % height
	if _material_for_height.has(key):
		return _material_for_height[key]
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("height_m", height)
	material.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
	material.set_shader_parameter("camera_position", Vector2.ZERO)
	material.set_shader_parameter("camera_zoom", 1.0)
	_material_for_height[key] = material
	_materials.append(material)
	return material


func _in_rim(x: int, y: int, size: int) -> bool:
	var edge := mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
	var center := float(size) * 0.5
	var angle := atan2(float(y) - center, float(x) - center)
	var wave := sin(angle * 2.0) * 0.42 + sin(angle * 5.0 + 1.7) * 0.33 + sin(angle * 3.0 + 2.4) * 0.25
	var width := lerpf(RIM_NEAR, RIM_FAR, clampf(wave * 0.5 + 0.5, 0.0, 1.0))
	return float(edge) < width


func _rim_kind(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	var cursor := 0.0
	for rock_name in RIM_WEIGHTS:
		if not _species.has(rock_name):
			continue
		cursor += float(RIM_WEIGHTS[rock_name])
		if roll <= cursor:
			return str(rock_name)
	for rock_name in _species:
		return str(rock_name)
	return ""


func _species_order() -> PackedStringArray:
	var names: Array[String] = []
	for rock_name in _species:
		names.append(str(rock_name))
	names.sort_custom(func(a: String, b: String) -> bool:
		return _pair_gap(a, a) > _pair_gap(b, b)
	)
	var ordered := PackedStringArray()
	for rock_name in names:
		ordered.append(rock_name)
	return ordered


func _pair_gap(left: String, right: String) -> float:
	var meters := maxf(float(_species[left]["spacing"]), float(_species[right]["spacing"]))
	return meters * float(TerrainCatalog.TILE_SIZE)


## Okraj nehlídá katalogový rozestup. Paty se mají dotýkat.
func _touch_gap(left: String, right: String) -> float:
	var span := float(_species[left]["radius"]) + float(_species[right]["radius"])
	return span * RIM_TOUCH


func _max_gap() -> float:
	var gap := float(TerrainCatalog.TILE_SIZE)
	for left in _species:
		for right in _species:
			var pair := str(left)
			var other := str(right)
			gap = maxf(gap, _pair_gap(pair, other))
			gap = maxf(gap, _touch_gap(pair, other))
	return gap


func _has_room(
	pos: Vector2,
	rock_name: String,
	spots: Array[Spot],
	buckets: Dictionary,
	reach: float,
	tight: bool = false,
) -> bool:
	var here := _bucket(pos, reach)
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var listed = buckets.get(here + Vector2i(ox, oy), null)
			if listed == null:
				continue
			for index in listed:
				var other: Spot = spots[index]
				var gap := _touch_gap(rock_name, other.rock) if tight else _pair_gap(rock_name, other.rock)
				if pos.distance_squared_to(other.position) < gap * gap:
					return false
	return true


func _remember(pos: Vector2, index: int, buckets: Dictionary, reach: float) -> void:
	var key := _bucket(pos, reach)
	if not buckets.has(key):
		buckets[key] = []
	(buckets[key] as Array).append(index)


func _bucket(pos: Vector2, reach: float) -> Vector2i:
	return Vector2i(floori(pos.x / reach), floori(pos.y / reach))


func _point(
	x: int,
	y: int,
	size: int,
	terrain: PackedStringArray,
	surfaces: Dictionary,
	rng: RandomNumberGenerator,
) -> Vector2:
	var min_x := 0.0
	var max_x := 1.0
	var min_y := 0.0
	var max_y := 1.0
	if not _grows_at(x - 1, y, size, terrain, surfaces):
		min_x = 0.45
	if not _grows_at(x + 1, y, size, terrain, surfaces):
		max_x = 0.55
	if not _grows_at(x, y - 1, size, terrain, surfaces):
		min_y = 0.45
	if not _grows_at(x, y + 1, size, terrain, surfaces):
		max_y = 0.55
	var tile := float(TerrainCatalog.TILE_SIZE)
	return Vector2(
		(float(x) + rng.randf_range(min_x, max_x)) * tile,
		(float(y) + rng.randf_range(min_y, max_y)) * tile,
	)


func _anywhere(x: int, y: int, rng: RandomNumberGenerator) -> Vector2:
	var tile := float(TerrainCatalog.TILE_SIZE)
	return Vector2((float(x) + rng.randf()) * tile, (float(y) + rng.randf()) * tile)


func _grows_at(
	x: int,
	y: int,
	size: int,
	terrain: PackedStringArray,
	surfaces: Dictionary,
) -> bool:
	if x < 0 or y < 0 or x >= size or y >= size:
		return false
	return not _rocks_of(terrain[y * size + x], surfaces).is_empty()


func _rocks_of(terrain_name: String, surfaces: Dictionary) -> Dictionary:
	var info: Dictionary = surfaces.get(terrain_name, {})
	var rocks = info.get("rocks", {})
	if typeof(rocks) != TYPE_DICTIONARY:
		return {}
	return rocks


func _walkable(terrain_name: String, surfaces: Dictionary) -> bool:
	var info: Dictionary = surfaces.get(terrain_name, {})
	return bool(info.get("walkable", true))


func _attempts(weight: float, rng: RandomNumberGenerator) -> int:
	var count := int(weight)
	if rng.randf() < weight - float(count):
		count += 1
	return count


func _shuffled_indices(count: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var order := PackedInt32Array()
	order.resize(count)
	for index in count:
		order[index] = index
	for index in count:
		var swap := rng.randi_range(index, count - 1)
		var saved := order[index]
		order[index] = order[swap]
		order[swap] = saved
	return order


class Spot:
	var rock: String
	var position: Vector2
	var variant: int
	var rotation: float
