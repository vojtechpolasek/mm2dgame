extends RefCounted

## Průchozí porost: trsy trávy, květy, kapradí, houby, rákos, vřes. Leží na zemi, nemá výšku
## ani kolizi. Co roste na kterém povrchu, říká klíč decor v surfaces.json (počet na dlaždici),
## vzhled druhů je v graphics/objects/decor (tools/gen_decor.py).
##
## Kreslí ho MultiMesh po kusech CHUNK × CHUNK dlaždic: jeden uzel a jeden draw call na kus,
## žádný uzel pro jednotlivý trs. Buňku atlasu vybírá shader podle vlastních dat instance.
## Druhy se shlukují podle šumu ve světových souřadnicích, louka proto pokračuje přes kraj čtverce.
##
## Průběh: load_kit jednou na hlavním vlákně, plant ve vlákně (nesahá na scénu), spawn na hlavním.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapData := preload("res://scripts/map_data.gd")
const Town := preload("res://scripts/town.gd")

const ROOT := "res://graphics/objects/decor"
const SHADER := "res://shaders/decor.gdshader"
## Strana kusu v dlaždicích.
const CHUNK := 16
## Od cesty, továrny a domů drží porost tolik pixelů.
const TOWN_GAP := 10.0
## Vlnová délka shluků v dlaždicích.
const PATCH_TILES := 9.0
## Floatů na instanci v bufferu MultiMesh: 8 transformace 2D a 4 vlastní data.
const STRIDE := 12

## Klíč kusu -> buffer instancí, souřadnice od rohu kusu.
var _buffers := {}


## Atlas, mřížka, sítě a co roste na kterém povrchu. Jednou pro celý svět.
static func load_kit(terrain_names: PackedStringArray, surfaces: Dictionary) -> Dictionary:
	var path := ROOT + "/decor.json"
	if not FileAccess.file_exists(path):
		push_warning("Chybí %s, porost nebude." % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst %s." % path)
		return {}
	var texture := load(ROOT + "/decor.png") as Texture2D
	if texture == null:
		push_error("Chybí atlas porostu.")
		return {}
	var cell := float(parsed.get("cell", 48))
	var columns := int(parsed.get("columns", 8))
	var rows := int(parsed.get("rows", 1))
	# Druh: buňky atlasu jako (sloupec, řádek), shlukování a rozsah zvětšení.
	var kinds: Array[Dictionary] = []
	var kind_of := {}
	var listed: Dictionary = parsed.get("decor", {})
	for kind_name: String in listed:
		var info: Dictionary = listed[kind_name]
		var cells := PackedVector2Array()
		for index: Variant in info.get("cells", []):
			cells.append(Vector2(int(index) % columns, int(index) / columns))
		if cells.is_empty():
			continue
		var scale: Array = info.get("scale", [1.0, 1.0])
		var noise := FastNoiseLite.new()
		noise.seed = kind_name.hash()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 1.0 / PATCH_TILES
		kind_of[kind_name] = kinds.size()
		kinds.append({
			"cells": cells,
			"patch": float(info.get("patch", 0.0)),
			"scale": Vector2(float(scale[0]), float(scale[1])),
			"noise": noise,
		})
	# Podle čísla povrchu: dvojice (druh, počet na dlaždici).
	var growth: Array = []
	for terrain_name in terrain_names:
		var info: Dictionary = surfaces.get(terrain_name, {})
		var wanted: Variant = info.get("decor", {})
		var pairs: Array = []
		if typeof(wanted) == TYPE_DICTIONARY:
			for kind_name: String in wanted:
				if not kind_of.has(kind_name):
					push_warning("Povrch %s chce porost %s, v atlasu chybí." % [terrain_name, kind_name])
					continue
				pairs.append(Vector2(kind_of[kind_name], float(wanted[kind_name])))
		growth.append(pairs)
	var material := ShaderMaterial.new()
	material.shader = load(SHADER)
	material.set_shader_parameter("cell_uv", Vector2(cell / texture.get_width(), cell / texture.get_height()))
	return {
		"texture": texture,
		"material": material,
		"mesh": _quad(cell),
		"kinds": kinds,
		"growth": growth,
		"cell": cell,
		"columns": columns,
		"rows": rows,
	}


## Čtverec o straně cell se středem v nule, UV přes celou buňku.
static func _quad(cell: float) -> ArrayMesh:
	var half := cell * 0.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half),
		Vector2(-half, -half), Vector2(half, half), Vector2(-half, half),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1),
		Vector2(0, 0), Vector2(1, 1), Vector2(0, 1),
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Rozmístí porost. corners jsou rohy dlaždic z MapGenerator.corner_data: dlaždice, která má
## v rohu vodu, zůstane holá, je na ní břeh. tile_origin je poloha mapy ve světě v dlaždicích,
## podle ní se berou shluky. seed drží rozmístění stejné i po načtení hry.
func plant(kit: Dictionary, map: MapData, corners: PackedByteArray, town: Town, water: int, tile_origin: Vector2i, seed: int) -> void:
	_buffers.clear()
	if kit.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tile := float(TerrainCatalog.TILE_SIZE)
	var chunk_px := float(CHUNK) * tile
	var kinds: Array[Dictionary] = kit["kinds"]
	var growth: Array = kit["growth"]
	var size := map.size
	for y in size:
		for x in size:
			var cell := y * size + x
			var pairs: Array = growth[map.terrain[cell]]
			if pairs.is_empty():
				continue
			var at := cell * 4
			if water >= 0 and (corners[at] == water or corners[at + 1] == water or corners[at + 2] == water or corners[at + 3] == water):
				continue
			var key := Vector2i(x / CHUNK, y / CHUNK)
			var corner := Vector2(key) * chunk_px
			for pair: Vector2 in pairs:
				var kind: Dictionary = kinds[int(pair.x)]
				var amount := pair.y * _patch(kind, float(tile_origin.x + x) + 0.5, float(tile_origin.y + y) + 0.5)
				var count := int(amount)
				if rng.randf() < amount - float(count):
					count += 1
				for _i in count:
					var pos := Vector2((float(x) + rng.randf()) * tile, (float(y) + rng.randf()) * tile)
					if town != null and town.blocks(pos, TOWN_GAP):
						continue
					var cells: PackedVector2Array = kind["cells"]
					var span: Vector2 = kind["scale"]
					_add(key, pos - corner, rng.randf() * TAU, rng.randf_range(span.x, span.y), cells[rng.randi_range(0, cells.size() - 1)])


## Násobek hustoty podle šumu: bez shlukování 1, se shlukováním skoro nic mimo ostrůvky
## a víc v nich, průměr zůstane podobný.
static func _patch(kind: Dictionary, x: float, y: float) -> float:
	var patch: float = kind["patch"]
	if patch <= 0.0:
		return 1.0
	var noise: FastNoiseLite = kind["noise"]
	var value := noise.get_noise_2d(x, y) * 0.5 + 0.5
	var floor_at := patch * 0.55
	return clampf((value - floor_at) / (1.0 - floor_at), 0.0, 1.0) * (1.0 + patch * 1.5)


func _add(key: Vector2i, pos: Vector2, turn: float, scale: float, cell: Vector2) -> void:
	var buffer: PackedFloat32Array = _buffers.get(key, PackedFloat32Array())
	var c := cos(turn) * scale
	var s := sin(turn) * scale
	# Pořadí bufferu 2D: x.x, y.x, 0, origin.x, x.y, y.y, 0, origin.y, pak vlastní data.
	buffer.append_array([c, -s, 0.0, pos.x, s, c, 0.0, pos.y, cell.x, cell.y, 0.0, 0.0])
	_buffers[key] = buffer


## Uzly kusů pod host. origin je levý horní roh mapy ve světě. Buffery se po předání uvolní.
func spawn(kit: Dictionary, host: Node2D, origin: Vector2) -> void:
	if kit.is_empty():
		return
	var chunk_px := float(CHUNK * TerrainCatalog.TILE_SIZE)
	var pad := float(kit["cell"])
	for key: Vector2i in _buffers:
		var buffer: PackedFloat32Array = _buffers[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_2D
		multimesh.use_custom_data = true
		multimesh.mesh = kit["mesh"]
		multimesh.instance_count = buffer.size() / STRIDE
		multimesh.buffer = buffer
		# Hranice kusu i s přesahem trsů, ať je engine nepočítá z instancí.
		multimesh.custom_aabb = AABB(Vector3(-pad, -pad, 0.0), Vector3(chunk_px + pad * 2.0, chunk_px + pad * 2.0, 0.0))
		var node := MultiMeshInstance2D.new()
		node.multimesh = multimesh
		node.texture = kit["texture"]
		node.material = kit["material"]
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		node.position = origin + Vector2(key) * chunk_px
		host.add_child(node)
	_buffers.clear()
