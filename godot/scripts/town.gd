extends Node

## Továrna uprostřed mapy, cesta od jejího výstupku ve tvaru T a domy kolem cesty.
## Nožka T vede od výstupku, příčka jde napříč na obě strany. Obojí je křivka přes vybočené body,
## takže T není rovné. Do vody cesta nevede: rameno se ohne, a když to nestačí, zkrátí se.
## Továrna a domy jsou neprůchodné pro postavy i příšery. Na vyšlapaném středu cesty postava
## běží rychleji (Person.ROAD_BOOST). Stromy, skály a jezírka se cestě, továrně a domům vyhnou.
##
## Průběh jako u skal: load_assets na hlavním vlákně, plan ve vlákně (nesahá na scénu),
## spawn zase na hlavním.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const MapData := preload("res://scripts/map_data.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const Crystal := preload("res://scripts/crystal.gd")
const Factory := preload("res://scripts/factory.gd")

## Kámen dojel v továrně pod mezikruží a započítal se. pos je místo ve světě.
signal settled(mat: int, pos: Vector2)

const FACTORY_CATALOG := "res://graphics/objects/factory/tovarna.json"
const PATH_CATALOG := "res://graphics/paths/paths.json"
const HOUSE_CATALOG := "res://graphics/objects/houses/houses.json"

## Nožka T a půlka příčky na každou stranu, v metrech.
const STEM_M := 20.0
const ARM_M := 10.0
## Body křivky asi po tolika metrech, do strany vybočené nejvýš o WOBBLE_M. První bod ramene
## vybočí jen o čtvrtinu, ať cesta vyjde z výstupku a z křižovatky rovně.
const KNOT_M := 4.0
const WOBBLE_M := 1.1
## Cesta začíná o tolik metrů pod koncem výstupku, ať na něj navazuje.
const DOCK_TUCK_M := 0.25
## Ohnutí ramene ve stupních, když rovně vede do vody. Ohyb přibývá k jeho konci.
const BENDS: Array[float] = [0.0, 14.0, -14.0, 28.0, -28.0, 42.0, -42.0]
## Tolik natočení továrny se zkusí, když cesta vyjde kratší.
const TURN_TRIES := 6
## Cesta drží od kraje mapy EDGE_M metrů a domy HOUSE_EDGE_M, ať nevedou do stěny skal.
## Řada a rozházené skály před stěnou se cestě a domům vyhnou samy.
const EDGE_M := 7.0
const HOUSE_EDGE_M := 5.5
## Bod křivky po tolika pixelech.
const SAMPLE_PX := 16.0
## Konce příčky a konec nožky v příčce zprůhlední na tolika metrech.
const FADE_M := 1.4
## Stromy, skály a jezírka drží od středu cesty půlku plné cesty a tolik metrů navíc.
const ROAD_CLEAR_M := 0.35
## Od továrny a domů drží tolik metrů.
const SOLID_CLEAR_M := 1.2
## Domů je HOUSES_MIN až HOUSES_MAX. Stěna je HOUSE_GAP_M metrů od kraje cesty, dveřmi k cestě,
## natočená od kolmice nejvýš o HOUSE_TILT radiánů. Domy mezi sebou drží HOUSE_APART_M.
const HOUSES_MIN := 4
const HOUSES_MAX := 8
const HOUSE_GAP_M := Vector2(1.0, 4.0)
const HOUSE_TILT := 0.14
const HOUSE_APART_M := 1.6
const HOUSE_TRIES := 30
## Barva vesnice se vylosuje z palet v houses.json a trochu pohne. Každý dům se od ní odchýlí
## v odstínu, sytosti a jasu nejvýš o tolik.
const HOUSE_HUE := 0.03
const HOUSE_SAT := 0.15
const HOUSE_VAL := 0.1
## Postava odevzdá kámen, když je blíž než o tolik pixelů od obrysu továrny.
const TOUCH_PX := 2.0
## Buňka mřížky úseků cesty v pixelech.
const SEG_CELL := 128.0

var _factory_info := {}
var _factory_base: Texture2D
var _factory_ring: Texture2D
var _factory_shader: Shader
## Vzory cest: textura a šířka plné cesty v px.
var _patterns: Array[Dictionary] = []
var _road_width := 160.0
## Druhy domů: textury a výšky vrstev, půdorys v px, kulatá jurta.
var _house_kinds: Array[Dictionary] = []
var _palettes: Array[Dictionary] = []
var _house_shader: Shader

var _center := Vector2.INF
var _turn := 0.0
var _pattern := 0
var _core_half := 0.0
var _clear_half := 0.0
var _stem := PackedVector2Array()
var _bar := PackedVector2Array()
var _houses: Array[Dictionary] = []
## Neprůchodné půdorysy. Továrna (osmiúhelník a výstupek) je na prvních _factory_parts místech.
var _solids: Array[Solid] = []
var _factory_parts := 0
var _solid_rect := Rect2()
var _keep_rect := Rect2()
var _seg_a := PackedVector2Array()
var _seg_b := PackedVector2Array()
var _seg_cells := {}

var _camera: MapCamera
var _crystal: Crystal
var _factory: Factory
var _roofs: Array[Sprite2D] = []


# --- Načtení ---

func load_assets() -> bool:
	_factory_info = _read_json(FACTORY_CATALOG)
	if _factory_info.is_empty():
		return false
	var layers: Dictionary = _factory_info.get("layers", {})
	var root := FACTORY_CATALOG.get_base_dir()
	_factory_base = _texture("%s/%s" % [root, str((layers.get("base", {}) as Dictionary).get("file", "base.png"))])
	_factory_ring = _texture("%s/%s" % [root, str((layers.get("ring", {}) as Dictionary).get("file", "ring.png"))])
	_factory_shader = load(str(_factory_info.get("shader", ""))) as Shader
	if _factory_base == null or _factory_ring == null or _factory_shader == null:
		push_error("Chybí grafika továrny.")
		_factory_info = {}
		return false
	_load_paths()
	_load_houses()
	return true


func _load_paths() -> void:
	var parsed := _read_json(PATH_CATALOG)
	var tile := float(TerrainCatalog.TILE_SIZE)
	_road_width = float(parsed.get("across_px", 160.0))
	var listed: Dictionary = parsed.get("patterns", {})
	var root := PATH_CATALOG.get_base_dir()
	for pattern_name: String in listed:
		var info: Dictionary = listed[pattern_name]
		var texture := _texture("%s/%s" % [root, str(info.get("file", ""))])
		if texture == null:
			push_error("Chybí vzor cesty %s." % pattern_name)
			continue
		_patterns.append({"name": pattern_name, "texture": texture, "core": float(info.get("core_m", 1.8)) * tile})


func _load_houses() -> void:
	var parsed := _read_json(HOUSE_CATALOG)
	_house_shader = load(str(parsed.get("shader", ""))) as Shader
	if _house_shader == null:
		push_error("Chybí shader domů.")
		return
	var tile := float(TerrainCatalog.TILE_SIZE)
	var colors: Dictionary = parsed.get("colors", {})
	for palette_name: String in colors:
		var palette: Dictionary = colors[palette_name]
		var entry := {}
		for part: String in ["roof", "wall", "wood", "glass", "opening"]:
			entry[part] = Color.html(str(palette.get(part, "808080")))
		_palettes.append(entry)
	var listed: Dictionary = parsed.get("houses", {})
	var root := HOUSE_CATALOG.get_base_dir()
	for house_name: String in listed:
		var info: Dictionary = listed[house_name]
		var parts: Dictionary = info.get("layers", {})
		var wall_info: Dictionary = parts.get("wall", {})
		var roof_info: Dictionary = parts.get("roof", {})
		var wall := _texture("%s/%s/%s" % [root, house_name, str(wall_info.get("file", "wall.png"))])
		var roof := _texture("%s/%s/%s" % [root, house_name, str(roof_info.get("file", "roof.png"))])
		if wall == null or roof == null:
			push_error("Chybí grafika domu %s." % house_name)
			continue
		_house_kinds.append({
			"wall": wall,
			"roof": roof,
			"wall_height": float(wall_info.get("height", 0.0)),
			"roof_height": float(roof_info.get("height", 4.0)),
			"width": float(info.get("width_m", 5.0)) * tile,
			"depth": float(info.get("depth_m", 4.0)) * tile,
			"round": str(info.get("kind", "")) == "jurta",
		})


# --- Rozvržení, ve vlákně ---

## Továrna u středu mapy s náhodným natočením, cesta, domy. Střed je souš, tu tam drží
## generátor mapy (MapGenerator.CENTER_CLEAR). Kdyby přesto byla voda, bere nejbližší souš.
func plan(map: MapData, rng: RandomNumberGenerator) -> void:
	_center = Vector2.INF
	_stem = PackedVector2Array()
	_bar = PackedVector2Array()
	_houses.clear()
	_solids.clear()
	_seg_a = PackedVector2Array()
	_seg_b = PackedVector2Array()
	_seg_cells.clear()
	if _factory_info.is_empty():
		return
	var tile := float(TerrainCatalog.TILE_SIZE)
	var center := Vector2(map.size, map.size) * tile * 0.5
	if not _land(map, center):
		center = _nearest_land(map, center)
		if center == Vector2.INF:
			return
	_center = center
	if not _patterns.is_empty():
		_pattern = rng.randi() % _patterns.size()
		_core_half = float(_patterns[_pattern]["core"]) * 0.5
		_clear_half = _core_half + ROAD_CLEAR_M * tile
	var full := (STEM_M + ARM_M * 2.0) * tile
	var best := -1.0
	for _try in TURN_TRIES:
		var turn := rng.randf() * TAU
		var road := _lay_road(map, turn, rng) if not _patterns.is_empty() else [PackedVector2Array(), PackedVector2Array(), 0.0]
		if float(road[2]) > best:
			best = float(road[2])
			_turn = turn
			_stem = road[0]
			_bar = road[1]
		if best >= full * 0.97:
			break
	_add_factory_solids()
	_index_road()
	_place_houses(map, rng)
	_measure()


func _lay_road(map: MapData, turn: float, rng: RandomNumberGenerator) -> Array:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var dock: Dictionary = _factory_info.get("dock_px", {})
	var down := Vector2.DOWN.rotated(turn)
	var start := _center + down * (float(dock.get("to", 290.0)) - DOCK_TUCK_M * tile)
	var stem := _arm(map, start, down, STEM_M * tile, rng, false)
	if stem.size() < 2:
		return [PackedVector2Array(), PackedVector2Array(), 0.0]
	var junction := stem[stem.size() - 1]
	var back := stem[maxi(stem.size() - 1 - int(KNOT_M * tile / SAMPLE_PX), 0)]
	var across := (junction - back).normalized().orthogonal()
	var left := _arm(map, junction, -across, ARM_M * tile, rng, true)
	var right := _arm(map, junction, across, ARM_M * tile, rng, true)
	var bar := PackedVector2Array()
	for i in range(left.size() - 1, -1, -1):
		bar.append(left[i])
	for i in range(1, right.size()):
		bar.append(right[i])
	if bar.size() < 2:
		bar = PackedVector2Array()
	return [stem, bar, _length(stem) + _length(bar)]


## Rameno z origin směrem dir. Vybočení bodů se losuje jednou, ohyby z BENDS je jen stáčejí.
## Vrátí body křivky od origin po první místo, kde by cesta vjela do vody nebo ke kraji mapy,
## z ohybu, který dojde nejdál.
func _arm(map: MapData, origin: Vector2, dir: Vector2, length: float, rng: RandomNumberGenerator, avoid_factory: bool) -> PackedVector2Array:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var count := maxi(roundi(length / (KNOT_M * tile)), 2)
	var step := length / float(count)
	var offsets := PackedFloat32Array()
	for i in count:
		offsets.append(rng.randf_range(-1.0, 1.0) * WOBBLE_M * tile * (0.25 if i == 0 else 1.0))
	var best := PackedVector2Array([origin])
	var best_length := 0.0
	for bend in BENDS:
		var knots := PackedVector2Array([origin])
		var axis := origin
		for i in count:
			var heading := dir.rotated(deg_to_rad(bend) * float(i + 1) / float(count))
			axis += heading * step
			knots.append(axis + heading.orthogonal() * offsets[i])
		var curve := _spline(knots)
		var kept := PackedVector2Array()
		for point in curve:
			if not _road_spot(map, point, avoid_factory):
				break
			kept.append(point)
		var kept_length := _length(kept)
		if kept_length > best_length + 1.0:
			best = kept
			best_length = kept_length
		if kept.size() == curve.size():
			break
	return best


## Smí tu vést cesta? Celá šířka na souši, dost daleko od kraje mapy a od továrny.
func _road_spot(map: MapData, point: Vector2, avoid_factory: bool) -> bool:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var world := float(map.size) * tile
	var edge := EDGE_M * tile
	if point.x < edge or point.y < edge or point.x > world - edge or point.y > world - edge:
		return false
	var reach := _clear_half + tile * 0.25
	for probe: Vector2 in [Vector2.ZERO, Vector2(reach, 0.0), Vector2(-reach, 0.0), Vector2(0.0, reach), Vector2(0.0, -reach)]:
		if not _land(map, point + probe):
			return false
	if avoid_factory:
		var dock: Dictionary = _factory_info.get("dock_px", {})
		if point.distance_to(_center) < float(dock.get("to", 290.0)) + _clear_half:
			return false
	return true


## Catmull-Rom přes body, úsek po zhruba SAMPLE_PX.
static func _spline(knots: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([knots[0]])
	var last := knots.size() - 1
	for i in last:
		var p0 := knots[maxi(i - 1, 0)]
		var p1 := knots[i]
		var p2 := knots[i + 1]
		var p3 := knots[mini(i + 2, last)]
		var pieces := maxi(ceili(p1.distance_to(p2) / SAMPLE_PX), 1)
		for piece in range(1, pieces + 1):
			var t := float(piece) / float(pieces)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	return out


static func _length(line: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, line.size()):
		total += line[i - 1].distance_to(line[i])
	return total


## Osmiúhelník přes plochy a výstupek na jižní ploše, natočené s továrnou.
func _add_factory_solids() -> void:
	var apothem := float(_factory_info.get("apothem_px", 192.0))
	var corner := apothem / cos(PI / 8.0)
	var octagon := PackedVector2Array()
	for k in 8:
		octagon.append(_center + Vector2.from_angle((float(k) + 0.5) * PI * 0.25 + _turn) * corner)
	_solids.append(Solid.new(octagon))
	var dock: Dictionary = _factory_info.get("dock_px", {})
	var half := float(dock.get("half", 46.0))
	var from := float(dock.get("from", 182.0))
	var to := float(dock.get("to", 285.0))
	var box := PackedVector2Array()
	for corner_at: Vector2 in [Vector2(-half, from), Vector2(half, from), Vector2(half, to), Vector2(-half, to)]:
		box.append(_center + corner_at.rotated(_turn))
	_solids.append(Solid.new(box))
	_factory_parts = _solids.size()


## Úseky cesty do mřížky, ať dotaz na vzdálenost od cesty prochází jen pár úseků.
func _index_road() -> void:
	for line: PackedVector2Array in [_stem, _bar]:
		for i in range(1, line.size()):
			var at := _seg_a.size()
			_seg_a.append(line[i - 1])
			_seg_b.append(line[i])
			var low := line[i - 1].min(line[i])
			var high := line[i - 1].max(line[i])
			for cy in range(floori(low.y / SEG_CELL), floori(high.y / SEG_CELL) + 1):
				for cx in range(floori(low.x / SEG_CELL), floori(high.x / SEG_CELL) + 1):
					var key := Vector2i(cx, cy)
					if not _seg_cells.has(key):
						_seg_cells[key] = PackedInt32Array()
					var list: PackedInt32Array = _seg_cells[key]
					list.append(at)
					_seg_cells[key] = list


## Domy u cesty z obou stran. Dveře (záporné x obrázku) míří ke cestě.
func _place_houses(map: MapData, rng: RandomNumberGenerator) -> void:
	if _house_kinds.is_empty() or _palettes.is_empty():
		return
	var lines: Array[PackedVector2Array] = []
	var weights := PackedFloat32Array()
	for line: PackedVector2Array in [_stem, _bar]:
		if line.size() >= 2:
			lines.append(line)
			weights.append(_length(line))
	if lines.is_empty():
		return
	var tile := float(TerrainCatalog.TILE_SIZE)
	var village := _palettes[rng.randi() % _palettes.size()].duplicate()
	for part: String in ["roof", "wall", "wood"]:
		village[part] = _vary(village[part], rng, HOUSE_HUE, HOUSE_SAT, HOUSE_VAL)
	var want := rng.randi_range(HOUSES_MIN, HOUSES_MAX)
	var guard := want * HOUSE_TRIES
	while _houses.size() < want and guard > 0:
		guard -= 1
		var line := lines[rng.rand_weighted(weights)]
		var at := rng.randi_range(0, line.size() - 1)
		var tangent := (line[mini(at + 2, line.size() - 1)] - line[maxi(at - 2, 0)]).normalized()
		var normal := tangent.orthogonal() * (-1.0 if rng.randf() < 0.5 else 1.0)
		var gap := rng.randf_range(HOUSE_GAP_M.x, HOUSE_GAP_M.y) * tile
		var turn := normal.angle() + rng.randf_range(-HOUSE_TILT, HOUSE_TILT)
		# Na místo, kam se velký dům nevejde, se zkusí menší.
		var kinds := PackedInt32Array(range(_house_kinds.size()))
		_shuffle(kinds, rng)
		var kind := -1
		var pos := Vector2.ZERO
		var solid: Solid
		for candidate in kinds:
			var info := _house_kinds[candidate]
			pos = line[at] + normal * (_clear_half + gap + float(info["width"]) * 0.5)
			solid = _house_solid(info, pos, turn)
			if _house_fits(map, solid):
				kind = candidate
				break
		if kind < 0:
			continue
		_solids.append(solid)
		var colors := {}
		for part: String in ["roof", "wall", "wood"]:
			colors[part] = _vary(village[part], rng, HOUSE_HUE, HOUSE_SAT, HOUSE_VAL)
		colors["glass"] = village["glass"]
		colors["opening"] = village["opening"]
		_houses.append({"kind": kind, "pos": pos, "turn": turn, "colors": colors})


func _house_solid(info: Dictionary, pos: Vector2, turn: float) -> Solid:
	var points := PackedVector2Array()
	var half := Vector2(float(info["width"]), float(info["depth"])) * 0.5
	if bool(info["round"]):
		for k in 12:
			points.append(pos + Vector2.from_angle(float(k) * TAU / 12.0 + turn) * half.x)
	else:
		for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
			points.append(pos + corner.rotated(turn))
	return Solid.new(points)


## Celý dům na souši, dál od kraje mapy, od cesty, továrny a ostatních domů. Levné zkoušky první.
func _house_fits(map: MapData, solid: Solid) -> bool:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var world := float(map.size) * tile
	var edge := HOUSE_EDGE_M * tile
	var rect := solid.rect()
	if rect.position.x < edge or rect.position.y < edge or rect.end.x > world - edge or rect.end.y > world - edge:
		return false
	var apart := HOUSE_APART_M * tile
	var edge_points := solid.outline(tile * 0.5)
	for other in _solids:
		if other.center.distance_to(solid.center) > other.reach + solid.reach + apart:
			continue
		for point in edge_points:
			if other.signed(point) < apart:
				return false
		for point in other.outline(tile * 0.5):
			if solid.signed(point) < apart:
				return false
	var road := _clear_half + tile * 0.5
	for line: PackedVector2Array in [_stem, _bar]:
		for point in line:
			if point.distance_to(solid.center) < solid.reach + road and solid.signed(point) < road:
				return false
	var y := rect.position.y
	while y <= rect.end.y:
		var x := rect.position.x
		while x <= rect.end.x:
			var spot := Vector2(x, y)
			if solid.signed(spot) <= tile * 0.25 and not _land(map, spot):
				return false
			x += tile * 0.5
		y += tile * 0.5
	return true


static func _shuffle(order: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	for index in order.size():
		var swap := rng.randi_range(index, order.size() - 1)
		var saved := order[index]
		order[index] = order[swap]
		order[swap] = saved


static func _vary(color: Color, rng: RandomNumberGenerator, hue: float, sat: float, val: float) -> Color:
	return Color.from_hsv(
		fposmod(color.h + rng.randf_range(-hue, hue), 1.0),
		clampf(color.s * (1.0 + rng.randf_range(-sat, sat)), 0.0, 1.0),
		clampf(color.v * (1.0 + rng.randf_range(-val, val)), 0.0, 1.0),
	)


## Obdélníky, ve kterých má smysl hledat: půdorysy a cesta.
func _measure() -> void:
	_solid_rect = Rect2()
	for i in _solids.size():
		_solid_rect = _solids[i].rect() if i == 0 else _solid_rect.merge(_solids[i].rect())
	var tile := float(TerrainCatalog.TILE_SIZE)
	_keep_rect = _solid_rect.grow(SOLID_CLEAR_M * tile)
	for line: PackedVector2Array in [_stem, _bar]:
		for point in line:
			_keep_rect = _keep_rect.expand(point)
	_keep_rect = _keep_rect.grow(_clear_half)


func _land(map: MapData, pos: Vector2) -> bool:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var x := int(pos.x / tile)
	var y := int(pos.y / tile)
	if pos.x < 0.0 or pos.y < 0.0 or x >= map.size or y >= map.size:
		return false
	var info: Dictionary = map.surfaces.get(map.names[map.terrain[y * map.size + x]], {})
	return bool(info.get("walkable", true))


## Střed nejbližší schůdné dlaždice. Prochází čtvercové prstence kolem from.
func _nearest_land(map: MapData, from: Vector2) -> Vector2:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var cx := int(from.x / tile)
	var cy := int(from.y / tile)
	for radius in range(1, map.size):
		var best := Vector2.INF
		for y in range(cy - radius, cy + radius + 1):
			for x in range(cx - radius, cx + radius + 1):
				if maxi(absi(x - cx), absi(y - cy)) != radius:
					continue
				var spot := Vector2((float(x) + 0.5) * tile, (float(y) + 0.5) * tile)
				if _land(map, spot) and spot.distance_squared_to(from) < best.distance_squared_to(from):
					best = spot
		if best != Vector2.INF:
			return best
	return Vector2.INF


# --- Dotazy, smí běžet z vlákna po plan ---

## Střed továrny ve světě. Bez továrny Vector2.INF.
func center() -> Vector2:
	return _center


## Kde se objeví první postava: na cestě kousek před výstupkem.
func home() -> Vector2:
	if _center == Vector2.INF:
		return Vector2.INF
	var tile := float(TerrainCatalog.TILE_SIZE)
	if _stem.size() >= 2:
		return _stem[mini(int(2.5 * tile / SAMPLE_PX), _stem.size() - 1)]
	var dock: Dictionary = _factory_info.get("dock_px", {})
	return _center + Vector2.DOWN.rotated(_turn) * (float(dock.get("to", 290.0)) + 2.0 * tile)


## Smí tu stát strom, skála nebo jezírko o poloměru radius? Ne na cestě a ne u továrny a domů.
func blocks(pos: Vector2, radius: float) -> bool:
	if _center == Vector2.INF or not _keep_rect.grow(radius).has_point(pos):
		return false
	var clear := radius + SOLID_CLEAR_M * float(TerrainCatalog.TILE_SIZE)
	for solid in _solids:
		if pos.distance_to(solid.center) < solid.reach + clear and solid.signed(pos) < clear:
			return true
	return _road_distance(pos, radius + _clear_half) < radius + _clear_half


## Stojí bod na vyšlapaném středu cesty?
func on_road(pos: Vector2) -> bool:
	if _seg_a.is_empty() or not _keep_rect.has_point(pos):
		return false
	return _road_distance(pos, _core_half) < _core_half


## Posune střed těla ven z továrny a domů. Přes ně se nepřeskočí.
func avoid(pos: Vector2, body: float) -> Vector2:
	if _solids.is_empty() or not _solid_rect.grow(body).has_point(pos):
		return pos
	var result := pos
	for _pass in 2:
		for solid in _solids:
			result = solid.push(result, body)
	return result


## Dotýká se tělo továrny? Pak do ní postava odevzdá kámen.
func touches_factory(pos: Vector2, body: float) -> bool:
	for i in _factory_parts:
		if _solids[i].signed(pos) <= body + TOUCH_PX:
			return true
	return false


## Označí v mřížce buňky (dlaždice), jejichž střed je blíž k půdorysu než body plus margin.
func block_cells(grid: AStarGrid2D, body: float, margin: float) -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var region := grid.region
	var limit := body + margin
	for solid in _solids:
		var rect := solid.rect().grow(limit)
		var x0 := maxi(int(rect.position.x / tile), region.position.x)
		var x1 := mini(int(rect.end.x / tile), region.end.x - 1)
		var y0 := maxi(int(rect.position.y / tile), region.position.y)
		var y1 := mini(int(rect.end.y / tile), region.end.y - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if solid.signed(Vector2((float(x) + 0.5) * tile, (float(y) + 0.5) * tile)) < limit:
					grid.set_point_solid(Vector2i(x, y))


## Nejmenší vzdálenost od středu cesty mezi úseky v okolí reach. Dál nic není, vrátí INF.
func _road_distance(pos: Vector2, reach: float) -> float:
	var best := INF
	for cy in range(floori((pos.y - reach) / SEG_CELL), floori((pos.y + reach) / SEG_CELL) + 1):
		for cx in range(floori((pos.x - reach) / SEG_CELL), floori((pos.x + reach) / SEG_CELL) + 1):
			var list: Variant = _seg_cells.get(Vector2i(cx, cy))
			if list == null:
				continue
			for at: int in list:
				best = minf(best, pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, _seg_a[at], _seg_b[at])))
	return best


# --- Scéna ---

## road je vrstva hned nad terénem, props třídí objekty podle y.
func spawn(camera: MapCamera, road: Node2D, props: Node2D, crystal: Crystal) -> void:
	if _center == Vector2.INF:
		return
	_camera = camera
	_crystal = crystal
	if not _patterns.is_empty():
		var tile := float(TerrainCatalog.TILE_SIZE)
		if _stem.size() >= 2:
			road.add_child(_road_line(_stem, 0.0, FADE_M * tile))
		if _bar.size() >= 2:
			road.add_child(_road_line(_bar, FADE_M * tile, FADE_M * tile))
	_factory = Factory.new()
	_factory.name = "Factory"
	_factory.position = _center
	_factory.rotation = _turn
	props.add_child(_factory)
	_factory.setup(_factory_info, _factory_base, _factory_ring, _factory_shader, crystal, camera)
	_factory.counted.connect(func(mat: int, pos: Vector2) -> void: settled.emit(mat, pos))
	_spawn_houses(props)
	camera.view_changed.connect(_fit_roofs)
	_fit_roofs()


## Kam dopadne kámen hozený od from: na vnější konec nejbližšího pásu.
func drop_spot(from: Vector2, rng: RandomNumberGenerator) -> Vector2:
	if _factory == null:
		return _center
	return _factory.belt_drop(from, rng)


## Kámen dopadl na pás. Ozve se hned, započítá se, až dojede pod mezikruží.
func receive(mat: int, world: Vector2, rot: float) -> void:
	if _factory == null:
		settled.emit(mat, world)
		return
	if _crystal != null:
		Sound.at("basin/" + _crystal.name_of(mat), world)
	_factory.receive(mat, world, rot)


## Pás vzoru po křivce. Vzor se opakuje po délce, šířka obrázku jde napříč. Začátek a konec
## zprůhlední na fade_start a fade_end pixelech.
func _road_line(points: PackedVector2Array, fade_start: float, fade_end: float) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.width = _road_width
	line.texture = _patterns[_pattern]["texture"]
	line.texture_mode = Line2D.LINE_TEXTURE_TILE
	line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var length := maxf(_length(points), 1.0)
	var ramp := Gradient.new()
	var offsets := PackedFloat32Array([0.0])
	var colors := PackedColorArray([Color(1, 1, 1, 0.0 if fade_start > 0.0 else 1.0)])
	if fade_start > 0.0:
		offsets.append(minf(fade_start / length, 0.45))
		colors.append(Color.WHITE)
	if fade_end > 0.0:
		offsets.append(maxf(1.0 - fade_end / length, 0.55))
		colors.append(Color.WHITE)
	offsets.append(1.0)
	colors.append(Color(1, 1, 1, 0.0 if fade_end > 0.0 else 1.0))
	ramp.offsets = offsets
	ramp.colors = colors
	line.gradient = ramp
	return line


func _spawn_houses(props: Node2D) -> void:
	if _house_shader == null:
		return
	var material := ShaderMaterial.new()
	material.shader = _house_shader
	material.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
	for house in _houses:
		var info := _house_kinds[int(house["kind"])]
		var node := Node2D.new()
		node.name = "House%d" % props.get_child_count()
		node.position = house["pos"]
		node.rotation = house["turn"]
		# Dům je nad postavou jako koruna stromu.
		node.z_index = 2
		props.add_child(node)
		_house_sprite(node, info["wall"], material, 1.0, float(info["wall_height"]), house["colors"])
		_roofs.append(_house_sprite(node, info["roof"], material, 0.0, float(info["roof_height"]), house["colors"]))


func _house_sprite(node: Node2D, texture: Texture2D, material: ShaderMaterial, slot: float, height: float, colors: Dictionary) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.material = material
	node.add_child(sprite)
	sprite.set_instance_shader_parameter("slot", slot)
	sprite.set_instance_shader_parameter("height_m", height)
	for part: String in ["roof", "wall", "wood", "glass", "opening"]:
		sprite.set_instance_shader_parameter(part + "_color", colors[part])
	return sprite


## Střecha je vysoko a posun výšky ji vytáhne z obdélníku spritu.
func _fit_roofs() -> void:
	if _camera == null:
		return
	var view := _camera.get_viewport_rect().size
	for roof in _roofs:
		var height := float(roof.get_instance_shader_parameter("height_m"))
		RenderingServer.canvas_item_set_custom_rect(roof.get_canvas_item(), true, roof.get_rect().grow(ObjectLayers.vertex_pad(view, height)))


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Chybí %s." % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst %s." % path)
		return {}
	return parsed


static func _texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## Konvexní neprůchodný půdorys ve světě. Normály hran míří ven.
class Solid:
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	var center := Vector2.ZERO
	var reach := 0.0

	func _init(corners: PackedVector2Array) -> void:
		points = corners
		for point in corners:
			center += point
		center /= float(maxi(corners.size(), 1))
		for i in corners.size():
			var a := corners[i]
			var b := corners[(i + 1) % corners.size()]
			reach = maxf(reach, a.distance_to(center))
			var normal := (b - a).orthogonal().normalized()
			if normal.dot(a - center) < 0.0:
				normal = -normal
			normals.append(normal)

	## Vzdálenost od obrysu, uvnitř záporná.
	func signed(pos: Vector2) -> float:
		var worst := -INF
		for i in points.size():
			worst = maxf(worst, normals[i].dot(pos - points[i]))
		if worst <= 0.0:
			return worst
		return pos.distance_to(closest(pos))

	func closest(pos: Vector2) -> Vector2:
		var best := points[0]
		var best_sq := INF
		for i in points.size():
			var near := Geometry2D.get_closest_point_to_segment(pos, points[i], points[(i + 1) % points.size()])
			var dist_sq := near.distance_squared_to(pos)
			if dist_sq < best_sq:
				best_sq = dist_sq
				best = near
		return best

	## Střed těla o poloměru body vystrčí za obrys.
	func push(pos: Vector2, body: float) -> Vector2:
		if pos.distance_squared_to(center) > (reach + body) * (reach + body):
			return pos
		var worst := -INF
		var worst_i := 0
		for i in points.size():
			var depth := normals[i].dot(pos - points[i])
			if depth > worst:
				worst = depth
				worst_i = i
		if worst <= 0.0:
			return pos + normals[worst_i] * (body - worst)
		var near := closest(pos)
		var delta := pos - near
		var dist := delta.length()
		if dist >= body:
			return pos
		if dist < 0.001:
			return near + normals[worst_i] * body
		return near + delta * (body / dist)

	func rect() -> Rect2:
		var box := Rect2(points[0], Vector2.ZERO)
		for point in points:
			box = box.expand(point)
		return box

	## Body po obvodu nejvýš step od sebe.
	func outline(step: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			var pieces := maxi(ceili(a.distance_to(b) / step), 1)
			for piece in pieces:
				out.append(a.lerp(b, float(piece) / float(pieces)))
		return out
