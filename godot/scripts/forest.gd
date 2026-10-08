extends "res://scripts/layered_props.gd"

const LayeredProps := preload("res://scripts/layered_props.gd")

## Na hlíně smí strom stát blíž jinému stromu, ať je jich asi dvakrát víc. Keře se nemění.
const DIRT_TREE_GAP := 0.66
## Do této výšky je keř pod postavou. Strom je nad ní.
const LOW := 1.5

var _spacing := {}
var _tree := PackedByteArray()
## Neprůchodný poloměr v pixelech: u stromu pařez, u keře celá koruna. Výška je vrchol v metrech.
var _solid := PackedFloat32Array()
var _solid_height := PackedFloat32Array()
var _solid_reach := 0.0
var _dirt := -1
var _rock_pos := PackedVector2Array()
var _rock_gap := PackedFloat32Array()
var _rock_grid: Grid


## Rozestup je v metrech a dlaždice je jeden metr. Skály z rocks stromy obcházejí.
## Nesahá na scénu, smí běžet ve vlákně.
func plant(map: MapData, rng: RandomNumberGenerator, rocks: LayeredProps = null) -> void:
	if _kinds.is_empty():
		return
	_begin_plant(map)
	_dirt = map.names.find("dirt")
	_rock_pos = PackedVector2Array()
	_rock_gap = PackedFloat32Array()
	if rocks != null:
		_rock_pos = rocks.spot_positions()
		_rock_gap = rocks.spot_gaps()
	var cell := _grid.cell
	for gap in _rock_gap:
		cell = maxf(cell, gap)
	_rock_grid = Grid.new(float(map.size * TerrainCatalog.TILE_SIZE), cell)
	for index in _rock_pos.size():
		_rock_grid.add(index, _rock_pos[index])
	_scatter(map, rng)


func _catalog_path() -> String:
	return "res://graphics/objects/trees/trees.json"


func _catalog_key() -> String:
	return "trees"


## Keř je pod postavou, koruna stromu nad ní.
func _build(kind: int) -> Node2D:
	var node := super._build(kind)
	node.z_index = 0 if _solid_height[kind] <= LOW else 2
	return node


func _surface_key() -> String:
	return "forest"


func _read_catalog(parsed: Dictionary) -> void:
	var listed_spacing: Variant = parsed.get("spacing", {})
	if typeof(listed_spacing) == TYPE_DICTIONARY:
		_spacing = listed_spacing


## Pařez je nejspodnější vrstva.
func _load_entry(kind_name: String, info: Dictionary, columns: int) -> Dictionary:
	var entry := super._load_entry(kind_name, info, columns)
	if entry.is_empty():
		return entry
	var stump := _texture_from("%s/%s/stump.png" % [_root(), kind_name])
	if stump == null:
		push_error("Chybí pařez stromu %s." % kind_name)
		return {}
	var stump_info: Dictionary = info.get("stump", {})
	(entry["layers"] as Array).push_front(_layer(stump, float(stump_info.get("height", 0.0))))
	var trunk := float(entry["spacing"]) > 3.0
	var listed: Dictionary = info.get("layers", {})
	var top := 0.0
	var footprint := 0.0
	for key: Variant in _sorted_keys(listed):
		var layer_info: Dictionary = listed[key]
		top = maxf(top, float(layer_info.get("height", 0.0)))
		if footprint == 0.0:
			footprint = float(layer_info.get("width", 32.0)) * 0.5
	_tree.append(1 if trunk else 0)
	var radius := float(stump_info.get("radius", footprint)) if trunk else footprint
	_solid.append(radius)
	_solid_height.append(top)
	_solid_reach = maxf(_solid_reach, radius)
	return entry


func _pair_gap(left: int, right: int) -> float:
	var meters := float(_kinds[left]["spacing"])
	var row: Variant = _spacing.get(_names[left], {})
	if typeof(row) == TYPE_DICTIONARY and row.has(_names[right]):
		meters = float(row[_names[right]])
	return meters * float(TerrainCatalog.TILE_SIZE)


## Na hlíně stojí stromy hustěji.
func _special_gap(left: int, right: int) -> float:
	var gap := _gaps[left * _kinds.size() + right]
	if _tree[left] == 1 and _tree[right] == 1:
		gap *= DIRT_TREE_GAP
	return gap


func _fits(pos: Vector2, kind: int, map: MapData) -> bool:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var x := clampi(int(pos.x / tile), 0, map.size - 1)
	var y := clampi(int(pos.y / tile), 0, map.size - 1)
	if _crowded(pos, kind, map.terrain[y * map.size + x] == _dirt):
		return false
	return not _hits_rock(pos, kind)


## Strom drží od skály větší z obou rozestupů.
func _hits_rock(pos: Vector2, kind: int) -> bool:
	var grid := _rock_grid
	var head := grid.head
	var next := grid.next
	var own := _gaps[kind * (_kinds.size() + 1)]
	var side := grid.side
	var gx := clampi(int(pos.x / grid.cell), 0, side - 1)
	var gy := clampi(int(pos.y / grid.cell), 0, side - 1)
	for cy in range(maxi(gy - 1, 0), mini(gy + 1, side - 1) + 1):
		for cx in range(maxi(gx - 1, 0), mini(gx + 1, side - 1) + 1):
			var item := head[cy * side + cx]
			while item >= 0:
				var gap := maxf(own, _rock_gap[item])
				if pos.distance_squared_to(_rock_pos[item]) < gap * gap:
					return true
				item = next[item]
	return false


## Posune bod ven z keře a z pařezu. clearance < 0 drží všechno. Nižší nebo rovné výšce jde přeskočit.
## Strom blokuje jen střed, keř celou korunu.
## Označí v mřížce buňky (dlaždice), jejichž střed je v keři nebo kmeni rozšířeném o body a margin.
func block_cells(grid: AStarGrid2D, body: float, margin: float, clearance: float = -1.0) -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var region := grid.region
	for item in _pos.size():
		if clearance >= 0.0 and _solid_height[_kind[item]] <= clearance:
			continue
		var center := _pos[item]
		var limit := _solid[_kind[item]] + body + margin
		var x0 := maxi(int((center.x - limit) / tile), region.position.x)
		var x1 := mini(int((center.x + limit) / tile), region.end.x - 1)
		var y0 := maxi(int((center.y - limit) / tile), region.position.y)
		var y1 := mini(int((center.y + limit) / tile), region.end.y - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var cell := Vector2((float(x) + 0.5) * tile, (float(y) + 0.5) * tile)
				if cell.distance_squared_to(center) < limit * limit:
					grid.set_point_solid(Vector2i(x, y))


func avoid(pos: Vector2, body: float, clearance: float = -1.0) -> Vector2:
	if _grid == null or _pos.is_empty():
		return pos
	var result := pos
	for _pass in 2:
		result = _push(result, body, clearance)
	return result


func _push(pos: Vector2, body: float, clearance: float) -> Vector2:
	var grid := _grid
	var reach := _solid_reach + body
	var span := maxi(ceili(reach / grid.cell), 1)
	var side := grid.side
	var gx := clampi(int(pos.x / grid.cell), 0, side - 1)
	var gy := clampi(int(pos.y / grid.cell), 0, side - 1)
	var result := pos
	for cy in range(maxi(gy - span, 0), mini(gy + span, side - 1) + 1):
		for cx in range(maxi(gx - span, 0), mini(gx + span, side - 1) + 1):
			var item := grid.head[cy * side + cx]
			while item >= 0:
				var kind := _kind[item]
				if clearance >= 0.0 and _solid_height[kind] <= clearance:
					item = grid.next[item]
					continue
				var limit := _solid[kind] + body
				var delta := result - _pos[item]
				var dist_sq := delta.length_squared()
				if dist_sq < limit * limit:
					if dist_sq < 0.0001:
						result = _pos[item] + Vector2(limit, 0.0)
					else:
						result = _pos[item] + delta * (limit / sqrt(dist_sq))
				item = grid.next[item]
	return result
