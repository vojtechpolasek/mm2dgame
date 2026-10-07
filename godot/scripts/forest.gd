extends Node2D

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")

const ROOT := "res://graphics/objects/trees"
const INFO_PATH := ROOT + "/trees.json"
const _SHADER_PATH := "res://shaders/tree_layer.gdshader"
## Na hlíně smí strom stát blíž jinému stromu, ať je jich asi dvakrát víc. Keře se nemění.
const DIRT_TREE_GAP := 0.66

var _camera: Camera2D
var _shader: Shader
var _species := {}
var _spacing := {}
var _materials: Array[ShaderMaterial] = []
var _material_for_height := {}
var _sprites: Array[Sprite2D] = []
var _tallest := 0.0
var _reach := 8.0
var _shader_on := true
var _fitted_view := Vector2.ZERO


func _ready() -> void:
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Kamera se pohne ve svém _process. Tohle má běžet až potom, ať vrstvy vidí nový střed.
	process_priority = 10


func _process(_delta: float) -> void:
	_follow_camera()


## Šance v terénu je počet pokusů na dlaždici. Rozestup je v metrech a dlaždice je jeden metr.
## Druh, který potřebuje víc místa, se sází dřív, ať keře zaplní mezery mezi stromy.
func plant(
	terrain: PackedStringArray,
	size: int,
	surfaces: Dictionary,
	rng: RandomNumberGenerator,
	camera: Camera2D,
	host: Node2D = null,
	chunks: Node = null,
	blockers: Array = [],
) -> void:
	_camera = camera
	if not _load_catalog():
		return
	_warn_unknown(surfaces)
	_measure()
	var view := _camera.get_viewport_rect().size
	_shader_on = ObjectLayers.shader_needed(view, _camera.zoom.x, _tallest)
	_fitted_view = view
	if chunks != null:
		chunks.grow_margin(_reach)
	var reach := _max_gap()
	for spot in _scatter(terrain, size, surfaces, rng, _bucket_blockers(blockers, reach), reach):
		_spawn(spot, host if host != null else self, chunks)
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
		push_error("Chybí shader vrstev stromu.")
		return false
	if not FileAccess.file_exists(INFO_PATH):
		push_error("Chybí %s." % INFO_PATH)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(INFO_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst %s." % INFO_PATH)
		return false
	var columns := int(parsed.get("atlas_columns", 3))
	var listed_spacing = parsed.get("spacing", {})
	if typeof(listed_spacing) == TYPE_DICTIONARY:
		_spacing = listed_spacing
	var listed: Dictionary = parsed.get("trees", {})
	for species_name in listed:
		var built := _load_species(str(species_name), listed[species_name], columns)
		if not built.is_empty():
			_species[species_name] = built
	if _species.is_empty():
		push_error("V katalogu stromů není žádný strom s atlasem.")
		return false
	return true


func _load_species(species_name: String, info: Dictionary, columns: int) -> Dictionary:
	var variants := maxi(int(info.get("variants", 9)), 1)
	var stump_info: Dictionary = info.get("stump", {})
	var stump := _texture_from("%s/%s/stump.png" % [ROOT, species_name])
	if stump == null:
		push_error("Chybí pařez stromu %s." % species_name)
		return {}
	var listed: Dictionary = info.get("layers", {})
	var keys: Array = listed.keys()
	keys.sort_custom(func(a, b) -> bool: return int(a) < int(b))
	var layers: Array[Dictionary] = []
	for key in keys:
		var layer_info: Dictionary = listed[key]
		var texture := _texture_from("%s/%s/layer_%s.png" % [ROOT, species_name, str(key)])
		if texture == null:
			push_error("Chybí vrstva %s stromu %s." % [str(key), species_name])
			return {}
		layers.append({
			"height": float(layer_info.get("height", 0.0)),
			"texture": texture,
		})
	return {
		"columns": columns,
		"rows": ceili(float(variants) / float(columns)),
		"variants": variants,
		"spacing": float(info.get("spacing", 1.0)),
		"stump_height": float(stump_info.get("height", 0.0)),
		"stump": stump,
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
		for species_name in _forest_of(str(terrain_name), surfaces):
			if not _species.has(species_name):
				push_warning("Terén %s chce strom %s, ten nemá atlas." % [terrain_name, species_name])


func _scatter(
	terrain: PackedStringArray,
	size: int,
	surfaces: Dictionary,
	rng: RandomNumberGenerator,
	blocked: Dictionary,
	reach: float,
) -> Array[Spot]:
	var spots: Array[Spot] = []
	var buckets := {}
	for species_name in _species_order():
		for index in _shuffled_indices(size * size, rng):
			var forest := _forest_of(terrain[index], surfaces)
			if not forest.has(species_name):
				continue
			var weight := float(forest[species_name])
			if weight <= 0.0:
				continue
			var x := index % size
			var y := index / size
			for _attempt in _attempts(weight, rng):
				var pos := _point(x, y, size, terrain, surfaces, rng)
				if not _has_room(pos, species_name, terrain, size, spots, buckets, blocked, reach):
					continue
				var spot := Spot.new()
				spot.species = species_name
				spot.position = pos
				spot.variant = rng.randi_range(0, int(_species[species_name]["variants"]) - 1)
				spot.rotation = rng.randf() * TAU
				spots.append(spot)
				_remember(pos, spots.size() - 1, buckets, reach)
	return spots


func _spawn(spot: Spot, host: Node2D, chunks: Node) -> void:
	var species: Dictionary = _species[spot.species]
	var columns := int(species["columns"])
	var rows := int(species["rows"])
	var tree := Node2D.new()
	tree.position = spot.position
	tree.rotation = spot.rotation
	tree.visible = false
	_add_layer(tree, species["stump"], float(species["stump_height"]), spot.variant, columns, rows)
	for layer in species["layers"]:
		var info: Dictionary = layer
		_add_layer(tree, info["texture"], float(info["height"]), spot.variant, columns, rows)
	host.add_child(tree)
	if chunks != null:
		chunks.adopt(tree)
	_fit_tree(tree)


func _add_layer(
	tree: Node2D,
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
	tree.add_child(sprite)


func _fit_tree(tree: Node2D) -> void:
	if _camera == null:
		return
	var view := _camera.get_viewport_rect().size
	for child in tree.get_children():
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
	for species_name in _species:
		var species: Dictionary = _species[species_name]
		var columns := maxi(int(species["columns"]), 1)
		var rows := maxi(int(species["rows"]), 1)
		_account(species["stump"], float(species["stump_height"]), columns, rows)
		for layer in species["layers"]:
			var info: Dictionary = layer
			_account(info["texture"], float(info["height"]), columns, rows)


func _account(texture: Texture2D, height: float, columns: int, rows: int) -> void:
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


func _species_order() -> PackedStringArray:
	var names: Array[String] = []
	for species_name in _species:
		names.append(str(species_name))
	names.sort_custom(func(a: String, b: String) -> bool:
		return _pair_gap(a, a) > _pair_gap(b, b)
	)
	var ordered := PackedStringArray()
	for species_name in names:
		ordered.append(species_name)
	return ordered


func _is_tree(species_name: String) -> bool:
	return float(_species[species_name]["spacing"]) > 3.0


func _ground_at(pos: Vector2, terrain: PackedStringArray, size: int) -> String:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var x := clampi(int(floor(pos.x / tile)), 0, size - 1)
	var y := clampi(int(floor(pos.y / tile)), 0, size - 1)
	return terrain[y * size + x]


func _pair_gap(left: String, right: String) -> float:
	var meters := float(_species[left]["spacing"])
	var row = _spacing.get(left, {})
	if typeof(row) == TYPE_DICTIONARY and row.has(right):
		meters = float(row[right])
	return meters * float(TerrainCatalog.TILE_SIZE)


func _max_gap() -> float:
	var gap := float(TerrainCatalog.TILE_SIZE)
	for left in _species:
		for right in _species:
			gap = maxf(gap, _pair_gap(str(left), str(right)))
	return gap


func _has_room(
	pos: Vector2,
	species_name: String,
	terrain: PackedStringArray,
	size: int,
	spots: Array[Spot],
	buckets: Dictionary,
	blocked: Dictionary,
	reach: float,
) -> bool:
	var here := _bucket(pos, reach)
	var on_dirt := _ground_at(pos, terrain, size) == "dirt"
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var listed = buckets.get(here + Vector2i(ox, oy), null)
			if listed == null:
				continue
			for index in listed:
				var other: Spot = spots[index]
				var gap := _pair_gap(species_name, other.species)
				if on_dirt and _is_tree(species_name) and _is_tree(other.species):
					gap *= DIRT_TREE_GAP
				if pos.distance_squared_to(other.position) < gap * gap:
					return false
	return not _hits_blocker(pos, species_name, blocked, reach)


func _bucket_blockers(blockers: Array, reach: float) -> Dictionary:
	var buckets := {}
	for block in blockers:
		if typeof(block) != TYPE_DICTIONARY:
			continue
		var key := _bucket(block["position"], reach)
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(block)
	return buckets


func _hits_blocker(pos: Vector2, species_name: String, blocked: Dictionary, reach: float) -> bool:
	var here := _bucket(pos, reach)
	var own := _pair_gap(species_name, species_name)
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var listed = blocked.get(here + Vector2i(ox, oy), null)
			if listed == null:
				continue
			for block in listed:
				var gap := maxf(own, float(block["gap"]))
				if pos.distance_squared_to(block["position"]) < gap * gap:
					return true
	return false


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


func _grows_at(
	x: int,
	y: int,
	size: int,
	terrain: PackedStringArray,
	surfaces: Dictionary,
) -> bool:
	if x < 0 or y < 0 or x >= size or y >= size:
		return false
	return not _forest_of(terrain[y * size + x], surfaces).is_empty()


func _forest_of(terrain_name: String, surfaces: Dictionary) -> Dictionary:
	var info: Dictionary = surfaces.get(terrain_name, {})
	var forest = info.get("forest", {})
	if typeof(forest) != TYPE_DICTIONARY:
		return {}
	return forest


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
	var species: String
	var position: Vector2
	var variant: int
	var rotation: float
