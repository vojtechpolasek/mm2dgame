extends Node

## Společný základ stromů a skal: katalog vrstev, rozmístění s rozestupy a sprity s posunem výšky.
## Potomek určí katalog, klíč šancí v surfaces.json a vlastní pravidla rozestupů.
##
## Průběh: load_catalog na hlavním vlákně, plant potomka smí běžet ve vlákně (nesahá na scénu),
## spawn zase na hlavním. Uzly vznikají až pro viditelné přihrádky a po skrytí se vrací do zásobníku.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const MapData := preload("res://scripts/map_data.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const PropChunks := preload("res://scripts/prop_chunks.gd")
const _SHADER_PATH := "res://shaders/tree_layer.gdshader"

var _camera: MapCamera
var _chunks: PropChunks
var _host: Node2D
var _shader: Shader
## Druhy objektů. Index v těchto polích je číslo druhu.
var _names := PackedStringArray()
var _kinds: Array[Dictionary] = []
var _kind_of := {}
## Rozestup dvojice druhů v pixelech na indexu a * počet druhů + b. Druhé dvě tabulky jsou čtverce
## pro běžné sázení a pro zvláštní pravidlo potomka (hlína u stromů).
var _gaps := PackedFloat32Array()
var _gap_sq := PackedFloat32Array()
var _gap_sq_special := PackedFloat32Array()
## Podle čísla povrchu: šance každého druhu, jestli tam roste aspoň něco, a jestli je schůdný.
var _chances: Array[PackedFloat32Array] = []
var _grows := PackedByteArray()
var _walkable := PackedByteArray()
## Rozmístěné objekty. Číslo objektu je index do všech čtyř polí.
var _pos := PackedVector2Array()
var _kind := PackedInt32Array()
var _variant := PackedInt32Array()
var _turn := PackedFloat32Array()
var _grid: Grid
## Pro každou dlaždici právě sázené mapy: roste tu něco?
var _grow_map := PackedByteArray()
var _pools: Array[Array] = []
## Uzel v záběru -> číslo druhu.
var _active := {}
var _material_for_height := {}
var _tallest := 0.0
var _reach := 8.0
var _shader_on := true
var _fitted_view := Vector2.ZERO


# --- Co určuje potomek ---

func _catalog_path() -> String:
	return ""


## Klíč seznamu objektů v katalogu.
func _catalog_key() -> String:
	return ""


## Klíč šancí objektů u povrchu v surfaces.json.
func _surface_key() -> String:
	return ""


func _read_catalog(_parsed: Dictionary) -> void:
	pass


func _pair_gap(left: int, _right: int) -> float:
	return float(_kinds[left]["spacing"]) * float(TerrainCatalog.TILE_SIZE)


## Rozestup pro zvláštní pravidlo potomka, v pixelech.
func _special_gap(left: int, right: int) -> float:
	return _gaps[left * _kinds.size() + right]


func _fits(pos: Vector2, kind: int, _map: MapData) -> bool:
	return not _crowded(pos, kind, false)


func _load_entry(kind_name: String, info: Dictionary, columns: int) -> Dictionary:
	var variants := maxi(int(info.get("variants", 9)), 1)
	var listed: Dictionary = info.get("layers", {})
	var layers: Array[Dictionary] = []
	for key: Variant in _sorted_keys(listed):
		var layer_info: Dictionary = listed[key]
		var texture := _texture_from("%s/%s/layer_%s.png" % [_root(), kind_name, str(key)])
		if texture == null:
			push_error("Chybí vrstva %s objektu %s." % [str(key), kind_name])
			return {}
		layers.append(_layer(texture, float(layer_info.get("height", 0.0))))
	if layers.is_empty():
		push_error("Objekt %s nemá vrstvy." % kind_name)
		return {}
	return {
		"columns": columns,
		"rows": ceili(float(variants) / float(columns)),
		"variants": variants,
		"spacing": float(info.get("spacing", 1.0)),
		"layers": layers,
	}


# --- Společný průběh ---

## Načte katalog a textury a připraví tabulky podle čísla povrchu. Běží na hlavním vlákně.
func load_catalog(terrain_names: PackedStringArray, surfaces: Dictionary) -> bool:
	_shader = load(_SHADER_PATH)
	if _shader == null:
		push_error("Chybí shader vrstev %s." % _SHADER_PATH)
		return false
	var path := _catalog_path()
	if not FileAccess.file_exists(path):
		push_error("Chybí %s." % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst %s." % path)
		return false
	_read_catalog(parsed)
	var columns := int(parsed.get("atlas_columns", 3))
	var listed: Dictionary = parsed.get(_catalog_key(), {})
	for kind_name: String in listed:
		var built := _load_entry(str(kind_name), listed[kind_name], columns)
		if built.is_empty():
			continue
		_kind_of[str(kind_name)] = _kinds.size()
		_names.append(str(kind_name))
		_kinds.append(built)
	if _kinds.is_empty():
		push_error("V katalogu %s není žádný objekt s atlasem." % path)
		return false
	var count := _kinds.size()
	_gaps.resize(count * count)
	for left in count:
		for right in count:
			_gaps[left * count + right] = _pair_gap(left, right)
	_gap_sq.resize(count * count)
	_gap_sq_special.resize(count * count)
	for left in count:
		for right in count:
			var cell := left * count + right
			_gap_sq[cell] = _gaps[cell] * _gaps[cell]
			var special := _special_gap(left, right)
			_gap_sq_special[cell] = special * special
	_index_surfaces(terrain_names, surfaces)
	return true


## Pozice objektů a rozestup každého od druhů stejného typu. Stromy podle toho obcházejí skály.
func spot_positions() -> PackedVector2Array:
	return _pos


func spot_gaps() -> PackedFloat32Array:
	var gaps := PackedFloat32Array()
	gaps.resize(_kind.size())
	var count := _kinds.size()
	for index in _kind.size():
		gaps[index] = _gaps[_kind[index] * (count + 1)]
	return gaps


## Vytvoří přihrádky a napojí se na kameru. Uzly vzniknou pod host, až bude přihrádka v záběru.
func spawn(camera: MapCamera, host: Node2D, chunks: PropChunks) -> void:
	_camera = camera
	_chunks = chunks
	_host = host
	if _kinds.is_empty():
		return
	var view := _camera.get_viewport_rect().size
	_measure(view)
	_shader_on = ObjectLayers.shader_needed(view, _camera.zoom.x, _tallest)
	_fitted_view = view
	_pools.clear()
	for kind in _kinds.size():
		_pools.append([])
	chunks.grow_margin(_reach)
	for index in _pos.size():
		chunks.register(self, index, _pos[index])
	camera.view_changed.connect(_on_view_changed)


## Uzel pro objekt číslo index. Bere se ze zásobníku, nový vzniká, jen když je zásobník prázdný.
func acquire(index: int) -> Node2D:
	var kind := _kind[index]
	var pool: Array = _pools[kind]
	var node: Node2D
	if pool.is_empty():
		node = _build(kind)
		_host.add_child(node)
	else:
		node = pool.pop_back()
	node.position = _pos[index]
	node.rotation = _turn[index]
	for child in node.get_children():
		var sprite := child as Sprite2D
		if sprite == null:
			continue
		sprite.frame = clampi(_variant[index], 0, sprite.hframes * sprite.vframes - 1)
	_fit(node, kind)
	node.visible = true
	_active[node] = kind
	return node


func release(index: int, node: Node2D) -> void:
	node.visible = false
	_active.erase(node)
	_pools[_kind[index]].append(node)


func _index_surfaces(terrain_names: PackedStringArray, surfaces: Dictionary) -> void:
	var count := terrain_names.size()
	_chances.resize(count)
	_grows.resize(count)
	_walkable.resize(count)
	for id in count:
		var info: Dictionary = surfaces.get(terrain_names[id], {})
		var listed: Variant = info.get(_surface_key(), {})
		if typeof(listed) != TYPE_DICTIONARY:
			listed = {}
		var chances := PackedFloat32Array()
		chances.resize(_kinds.size())
		for kind_name: String in listed:
			if not _kind_of.has(kind_name):
				push_warning("Terén %s chce %s, v %s chybí." % [terrain_names[id], kind_name, _catalog_path()])
				continue
			chances[_kind_of[kind_name]] = float(listed[kind_name])
		_chances[id] = chances
		_grows[id] = 1 if not (listed as Dictionary).is_empty() else 0
		_walkable[id] = 1 if bool(info.get("walkable", true)) else 0


## Vyprázdní rozmístění a připraví mřížku sousedů pro novou mapu.
func _begin_plant(map: MapData) -> void:
	_pos.clear()
	_kind.clear()
	_variant.clear()
	_turn.clear()
	_grid = Grid.new(float(map.size * TerrainCatalog.TILE_SIZE), _max_gap())
	_grow_map.resize(map.terrain.size())
	for index in map.terrain.size():
		_grow_map[index] = _grows[map.terrain[index]]


func _keep(kind: int, pos: Vector2, rng: RandomNumberGenerator) -> void:
	var variant := rng.randi_range(0, int(_kinds[kind]["variants"]) - 1)
	_keep_shaped(kind, pos, variant, rng.randf() * TAU)


## Objekt s už vylosovanou variantou a natočením. Potomek je potřebuje znát před kontrolou místa.
func _keep_shaped(kind: int, pos: Vector2, variant: int, turn: float) -> void:
	_grid.add(_pos.size(), pos)
	_pos.append(pos)
	_kind.append(kind)
	_variant.append(variant)
	_turn.append(turn)


## Druh, který potřebuje víc místa, se sází dřív, ať menší objekty zaplní mezery.
## Šance v terénu je počet pokusů na dlaždici. Každý druh prochází jen dlaždice, kde roste.
## Na kraji porostu se objekt drží středu dlaždice, ať nepřečuhuje do cizího terénu.
func _scatter(map: MapData, rng: RandomNumberGenerator) -> void:
	var size := map.size
	var terrain := map.terrain
	var grows := _grow_map
	var tile := float(TerrainCatalog.TILE_SIZE)
	for kind in _kind_order():
		if not _scatter_kind(kind):
			continue
		var weight_of := PackedFloat32Array()
		weight_of.resize(_chances.size())
		for id in _chances.size():
			weight_of[id] = _chances[id][kind]
		var order := PackedInt32Array()
		for index in terrain.size():
			if weight_of[terrain[index]] > 0.0:
				order.append(index)
		_shuffle(order, rng)
		for index in order:
			var weight := weight_of[terrain[index]]
			var attempts := int(weight)
			if rng.randf() < weight - float(attempts):
				attempts += 1
			if attempts == 0:
				continue
			var x := index % size
			var y := index / size
			var min_x := 0.0 if x > 0 and grows[index - 1] == 1 else 0.45
			var max_x := 1.0 if x < size - 1 and grows[index + 1] == 1 else 0.55
			var min_y := 0.0 if y > 0 and grows[index - size] == 1 else 0.45
			var max_y := 1.0 if y < size - 1 and grows[index + size] == 1 else 0.55
			for _attempt in attempts:
				var pos := Vector2(
					(float(x) + rng.randf_range(min_x, max_x)) * tile,
					(float(y) + rng.randf_range(min_y, max_y)) * tile,
				)
				if _fits(pos, kind, map):
					_keep(kind, pos, rng)


## Stojí v rozestupu od pos jiný objekt? Prohledá buňku mřížky a osm sousedních.
func _crowded(pos: Vector2, kind: int, special: bool) -> bool:
	var grid := _grid
	var head := grid.head
	var next := grid.next
	var positions := _pos
	var kinds := _kind
	var table := _gap_sq_special if special else _gap_sq
	var row := kind * _kinds.size()
	var side := grid.side
	var gx := clampi(int(pos.x / grid.cell), 0, side - 1)
	var gy := clampi(int(pos.y / grid.cell), 0, side - 1)
	for cy in range(maxi(gy - 1, 0), mini(gy + 1, side - 1) + 1):
		for cx in range(maxi(gx - 1, 0), mini(gx + 1, side - 1) + 1):
			var item := head[cy * side + cx]
			while item >= 0:
				if pos.distance_squared_to(positions[item]) < table[row + kinds[item]]:
					return true
				item = next[item]
	return false


## Střed kamery dostávají shadery z globální uniformy. Tady jen zapnutí shaderu a okraje spritů.
func _on_view_changed() -> void:
	var view := _camera.get_viewport_rect().size
	var want := ObjectLayers.shader_needed(view, _camera.zoom.x, _tallest)
	if want == _shader_on and view == _fitted_view:
		return
	_shader_on = want
	_fitted_view = view
	_measure(view)
	_chunks.grow_margin(_reach)
	# Uzly v zásobníku se doladí, až je acquire znovu vezme.
	for node: Node2D in _active:
		_fit(node, _active[node])


func _root() -> String:
	return _catalog_path().get_base_dir()


## Import dává mipmapy i vyčištěné okraje. Soubor, který editor ještě nenaimportoval, se dopočítá tady.
func _texture_from(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return ObjectLayers.texture_with_mipmaps(image)


func _build(kind: int) -> Node2D:
	var entry := _kinds[kind]
	var columns := int(entry["columns"])
	var rows := int(entry["rows"])
	var node := Node2D.new()
	for layer: Dictionary in entry["layers"]:
		var info: Dictionary = layer
		var sprite := Sprite2D.new()
		sprite.texture = info["texture"]
		sprite.hframes = columns
		sprite.vframes = rows
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		node.add_child(sprite)
	return node


## Sprity uzlu jdou ve stejném pořadí jako vrstvy druhu. Uzel, který není sprite, se přeskočí.
func _fit(node: Node2D, kind: int) -> void:
	var layers: Array = _kinds[kind]["layers"]
	var layer_i := 0
	for child in node.get_children():
		var sprite := child as Sprite2D
		if sprite == null:
			continue
		if layer_i >= layers.size():
			break
		var info: Dictionary = layers[layer_i]
		ObjectLayers.fit_sprite(sprite, info["material"], info["height"], _fitted_view, _shader_on)
		layer_i += 1


## Potomek může druh ze sázení podle povrchu vynechat. Jezírko má vlastní počet.
func _scatter_kind(_kind: int) -> bool:
	return true


func _measure(view: Vector2) -> void:
	_tallest = 0.0
	_reach = 8.0
	for entry in _kinds:
		var columns := maxi(int(entry["columns"]), 1)
		var rows := maxi(int(entry["rows"]), 1)
		for layer: Dictionary in entry["layers"]:
			var info: Dictionary = layer
			var texture: Texture2D = info["texture"]
			var height := float(info["height"])
			_tallest = maxf(_tallest, height)
			var frame := maxf(texture.get_width() / float(columns), texture.get_height() / float(rows))
			_reach = maxf(_reach, ObjectLayers.sprite_reach(frame, view, height))


## Vrstva katalogu. Materiál nese výšku vrstvy, vrstvy stejné výšky ho sdílejí.
func _layer(texture: Texture2D, height: float) -> Dictionary:
	var key := snappedf(height, 0.001)
	if not _material_for_height.has(key):
		var material := ShaderMaterial.new()
		material.shader = _shader
		material.set_shader_parameter("height_m", height)
		material.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
		_material_for_height[key] = material
	return {"texture": texture, "height": height, "material": _material_for_height[key]}


func _kind_order() -> Array[int]:
	var order: Array[int] = []
	for kind in _kinds.size():
		order.append(kind)
	var count := _kinds.size()
	order.sort_custom(func(a: int, b: int) -> bool:
		return _gaps[a * count + a] > _gaps[b * count + b]
	)
	return order


## Největší rozestup ze všech pravidel. Podle něj je velká buňka mřížky sousedů.
func _max_gap() -> float:
	var gap_sq := float(TerrainCatalog.TILE_SIZE * TerrainCatalog.TILE_SIZE)
	for value in _gap_sq:
		gap_sq = maxf(gap_sq, value)
	for value in _gap_sq_special:
		gap_sq = maxf(gap_sq, value)
	return sqrt(gap_sq)


static func _sorted_keys(listed: Dictionary) -> Array:
	var keys: Array = listed.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	return keys


static func _shuffle(order: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	var count := order.size()
	for index in count:
		var swap := rng.randi_range(index, count - 1)
		var saved := order[index]
		order[index] = order[swap]
		order[swap] = saved


## Mřížka pro hledání sousedů. head drží první objekt v buňce, next další objekt ve stejné buňce.
## Buňka je velká jako největší rozestup, takže stačí prohledat ji a osm sousedních.
class Grid:
	var cell := 64.0
	var side := 1
	var head := PackedInt32Array()
	var next := PackedInt32Array()

	func _init(world: float, cell_px: float) -> void:
		cell = cell_px
		side = ceili(world / cell_px) + 1
		head.resize(side * side)
		head.fill(-1)

	func add(index: int, pos: Vector2) -> void:
		var key := clampi(int(pos.y / cell), 0, side - 1) * side + clampi(int(pos.x / cell), 0, side - 1)
		if index >= next.size():
			next.resize(index + 1)
		next[index] = head[key]
		head[key] = index
