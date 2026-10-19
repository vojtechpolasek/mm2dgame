extends RefCounted

## Řeka čtverce. Pramení u skály kousek od kraje čtverce a teče do největší vody na čtverci.
## Čtverec bez vody řeku nemá. Trasu hledá A* po dlaždicích: skály, doly, továrna, domy
## a sklady jsou neprůchodné, jiná voda taky, šum v ceně řeku vlní. Na části čtverců vede
## řeka schválně přes cestu (BRIDGE_CHANCE) a přes cestu je most. Z dlaždic se vezme každá několikátá a proloží se křivkou,
## řeka proto není hranatá. U pramene je úzká, k ústí se rozšiřuje na WIDTH_MOUTH.
##
## Kreslí ji jedna síť (pás trojúhelníků podél křivky) se shaderem river.gdshader, most
## přes cestu je sprite. Postava i příšery řekou projdou, ale zpomalí (water_at), most
## je cesta a nezpomalí.
##
## Průběh: plan ve vlákně (nesahá na scénu), spawn na hlavním.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapData := preload("res://scripts/map_data.gd")
const Town := preload("res://scripts/town.gd")
const Rocks := preload("res://scripts/rocks.gd")

const SHADER := "res://shaders/river.gdshader"
const BRIDGE := "res://graphics/objects/bridge/most.png"
## Šířka řeky v pixelech u pramene a v ústí, i s břehem.
const WIDTH_SPRING := 18.0
const WIDTH_MOUTH := 128.0
## Pramen leží tolik dlaždic od kraje čtverce. Blíž ke kraji by ho mohl uříznout soused.
const SPRING_BAND := Vector2(6.0, 16.0)
## Pramen je od cílové vody aspoň tolik dlaždic, ať řeka není jen pahýl.
const SPRING_FAR := 24.0
const SPRING_NEAR := 12.0
## Kraj čtverce je pro trasu drahý, řeka se ho drží daleko.
const EDGE_TILES := 3
const EDGE_WEIGHT := 40.0
## Cesta je drahá: mimo schválený přechod se jí řeka vyhne.
const ROAD_WEIGHT := 30.0
## Na takovém podílu čtverců vede řeka přes cestu. Přechod je kolmo, CROSS_PX od osy cesty
## na obě strany. Tolik krajních bodů ramen se nepočítá, tam je křižovatka, výstupek a konec cesty.
const BRIDGE_CHANCE := 0.5
const CROSS_PX := 200.0
const CROSS_SKIP := 12
## Šum v ceně dlaždice, řeka se vlní.
const MEANDER := 3.0
## Z cesty po dlaždicích se bere každý tolikátý bod jako opěrný bod křivky.
const KNOT_STEP := 3
## Krok křivky v pixelech.
const SAMPLE_PX := 12.0
## Ústí sahá tolik dlaždic do vody, ať je přechod schovaný pod hladinou.
const MOUTH_TILES := 1.6
## Voda je vnitřní část šířky, zbytek je břeh. Zpomaluje jen voda.
const WATER_SHARE := 0.78
## Délka mostu navíc k šířce řeky, v pixelech.
const BRIDGE_OVERHANG := 72.0

## Osa řeky ve čtverci (od pramene k ústí) a šířka v každém bodě.
var points := PackedVector2Array()
var widths := PackedFloat32Array()
## Mosty: střed, natočení a délka v pixelech.
var bridges: Array[Dictionary] = []
## Dlaždice -> úseky osy, které jí vedou (index prvního bodu úseku).
var _cells := {}
var _size := 0
## Posun čtverce ve světě. Dotazy berou světové souřadnice.
var _origin := Vector2.ZERO
## Uzly ve scéně (síť a mosty), pro despawn.
var _nodes: Array[Node] = []


func exists() -> bool:
	return points.size() >= 2


## Najde trasu. rocks a town už stojí. seed drží řeku stejnou i po načtení hry.
func plan(map: MapData, rocks: Rocks, town: Town, seed: int) -> void:
	points = PackedVector2Array()
	widths = PackedFloat32Array()
	bridges.clear()
	_cells.clear()
	_size = map.size
	var water := map.names.find("water")
	if water < 0:
		return
	var lake := _largest_water(map, water)
	if lake.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var grid := _grid(map, rocks, town, water, lake, rng)
	var path: Array[Vector2i] = []
	var crossing := town != null and rng.randf() < BRIDGE_CHANCE
	for spring in _springs(map, rocks, grid, lake, rng):
		if crossing:
			path = _via_road(grid, spring, lake, town)
		if path.is_empty():
			path = grid.get_id_path(spring, _nearest(lake, spring))
		if path.size() >= 8:
			break
		path = []
	if path.is_empty():
		return
	_shape(path)
	_index()
	if town != null:
		_place_bridges(town)


func relocate(delta: Vector2) -> void:
	_origin = delta


## Je bod (ve světě) ve vodě řeky? Most přes cestu tu nepočítá, ten hlídá chodec.
func water_at(pos: Vector2) -> bool:
	return _reach_at(pos - _origin, 0.0, WATER_SHARE)


## Je bod blíž než margin px k mostu? Most je obdélník podél cesty, bere se jako kruh.
func near_bridge(pos: Vector2, margin: float) -> bool:
	var local := pos - _origin
	for bridge in bridges:
		if local.distance_to(bridge["pos"]) < float(bridge["length"]) * 0.5 + margin:
			return true
	return false


## Je bod blíž než margin px k řece i s břehem? Pro sázení stromů a porostu.
func near(pos: Vector2, margin: float) -> bool:
	return _reach_at(pos - _origin, margin, 1.0)


func _reach_at(local: Vector2, margin: float, share: float) -> bool:
	if not exists():
		return false
	var tile := float(TerrainCatalog.TILE_SIZE)
	var key := Vector2i(floori(local.x / tile), floori(local.y / tile))
	var list: Variant = _cells.get(key)
	if list == null:
		return false
	for at: int in list:
		var a := points[at]
		var b := points[at + 1]
		var ab := b - a
		var t := clampf((local - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var half := lerpf(widths[at], widths[at + 1], t) * 0.5 * share + margin
		if local.distance_squared_to(a + ab * t) < half * half:
			return true
	return false


# --- Trasa ---

## Dlaždice největší souvislé vody na čtverci.
func _largest_water(map: MapData, water: int) -> PackedVector2Array:
	var size := map.size
	var seen := PackedByteArray()
	seen.resize(size * size)
	var best := PackedVector2Array()
	for start in size * size:
		if seen[start] == 1 or map.terrain[start] != water:
			continue
		var body := PackedVector2Array()
		var queue := PackedInt32Array([start])
		seen[start] = 1
		var head := 0
		while head < queue.size():
			var cell := queue[head]
			head += 1
			var x := cell % size
			var y := cell / size
			body.append(Vector2(x, y))
			for side: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				var nx := x + side.x
				var ny := y + side.y
				if nx < 0 or ny < 0 or nx >= size or ny >= size:
					continue
				var next := ny * size + nx
				if seen[next] == 0 and map.terrain[next] == water:
					seen[next] = 1
					queue.append(next)
		if body.size() > best.size():
			best = body
	return best


## Mřížka pro A*: cena dlaždice s vlněním, neprůchodné překážky a cizí voda.
func _grid(map: MapData, rocks: Rocks, town: Town, water: int, lake: PackedVector2Array, rng: RandomNumberGenerator) -> AStarGrid2D:
	var size := map.size
	var tile := float(TerrainCatalog.TILE_SIZE)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, size, size)
	grid.cell_size = Vector2(tile, tile)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var own := {}
	for cell in lake:
		own[Vector2i(cell)] = true
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 7.0
	for y in size:
		for x in size:
			var at := Vector2i(x, y)
			if map.terrain[y * size + x] == water and not own.has(at):
				grid.set_point_solid(at)
				continue
			var weight := 1.0 + MEANDER * (noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5)
			if mini(mini(x, y), mini(size - 1 - x, size - 1 - y)) < EDGE_TILES:
				weight += EDGE_WEIGHT
			var center := Vector2((float(x) + 0.5) * tile, (float(y) + 0.5) * tile)
			if town != null:
				if town.building_near(center, tile):
					grid.set_point_solid(at)
					continue
				if town.road_near(center, tile * 0.5):
					weight += ROAD_WEIGHT
			grid.set_point_weight_scale(at, weight)
	if rocks != null:
		rocks.block_cells(grid, tile * 0.6, 0.0)
	return grid


## Kandidáti na pramen, nejlepší první: u skal v pásu u kraje, daleko od vody. Když skála
## není, náhodná místa v pásu. Bod je volná dlaždice mřížky.
func _springs(map: MapData, rocks: Rocks, grid: AStarGrid2D, lake: PackedVector2Array, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var size := map.size
	var tile := float(TerrainCatalog.TILE_SIZE)
	var out: Array[Vector2i] = []
	for far in [SPRING_FAR, SPRING_NEAR]:
		var near_rocks: Array[Vector2i] = []
		if rocks != null:
			for pos in rocks.spot_positions():
				var cell := Vector2i(floori(pos.x / tile), floori(pos.y / tile))
				var free := _free_near(grid, cell)
				if free.x >= 0 and _in_band(free, size) and _distance(lake, free) >= far:
					near_rocks.append(free)
		_shuffle(near_rocks, rng)
		out.append_array(near_rocks.slice(0, 4))
		for _try in 40:
			if out.size() >= 8:
				break
			var cell := Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
			if _in_band(cell, size) and not grid.is_point_solid(cell) and _distance(lake, cell) >= far:
				out.append(cell)
	return out


## Trasa od pramene k vodě kolmo přes cestu: k dlaždici na straně pramene, rovně přes cestu
## a od protější dlaždice k vodě. Bere přechod s nejkratší cestou. Prázdná, když nejde.
func _via_road(grid: AStarGrid2D, spring: Vector2i, lake: PackedVector2Array, town: Town) -> Array[Vector2i]:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var best := INF
	var ends: Array[Vector2i] = []
	for line in town.road_lines():
		for i in range(CROSS_SKIP, line.size() - CROSS_SKIP):
			var normal := (line[i + 1] - line[i - 1]).orthogonal().normalized()
			var a := Vector2i((line[i] - normal * CROSS_PX) / tile)
			var b := Vector2i((line[i] + normal * CROSS_PX) / tile)
			if not _clear_line(grid, a, b):
				continue
			if Vector2(spring).distance_to(Vector2(b)) < Vector2(spring).distance_to(Vector2(a)):
				var swap := a
				a = b
				b = swap
			var cost := Vector2(spring).distance_to(Vector2(a)) + _distance(lake, b)
			if cost < best:
				best = cost
				ends = [a, b]
	if ends.is_empty():
		return []
	var path := grid.get_id_path(spring, ends[0])
	var rest := grid.get_id_path(ends[1], _nearest(lake, ends[1]))
	if path.is_empty() or rest.is_empty():
		return []
	# Přes cestu rovně, A* by ji obešel kolem konce.
	var across := Geometry2D.bresenham_line(ends[0], ends[1])
	path.append_array(across.slice(1, across.size() - 1))
	path.append_array(rest)
	return path


## Vede přímka mezi dlaždicemi jen přes volné dlaždice uvnitř mapy?
static func _clear_line(grid: AStarGrid2D, a: Vector2i, b: Vector2i) -> bool:
	for cell in Geometry2D.bresenham_line(a, b):
		if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell):
			return false
	return true


func _in_band(cell: Vector2i, size: int) -> bool:
	var edge := float(mini(mini(cell.x, cell.y), mini(size - 1 - cell.x, size - 1 - cell.y)))
	return edge >= SPRING_BAND.x and edge <= SPRING_BAND.y


## Volná dlaždice vedle skály, nejbližší první.
func _free_near(grid: AStarGrid2D, cell: Vector2i) -> Vector2i:
	for ring in range(1, 5):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var near := cell + Vector2i(dx, dy)
				if grid.is_in_boundsv(near) and not grid.is_point_solid(near):
					return near
	return Vector2i(-1, -1)


func _distance(lake: PackedVector2Array, cell: Vector2i) -> float:
	return Vector2(cell).distance_to(Vector2(_nearest(lake, cell)))


func _nearest(lake: PackedVector2Array, cell: Vector2i) -> Vector2i:
	var best := INF
	var at := Vector2i.ZERO
	var from := Vector2(cell)
	for spot in lake:
		var d := from.distance_squared_to(spot)
		if d < best:
			best = d
			at = Vector2i(spot)
	return at


static func _shuffle(list: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for index in list.size():
		var swap := rng.randi_range(index, list.size() - 1)
		var saved := list[index]
		list[index] = list[swap]
		list[swap] = saved


## Z dlaždic cesty křivka a šířky. Ústí se protáhne do vody.
func _shape(path: Array[Vector2i]) -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var knots := PackedVector2Array()
	for index in path.size():
		if index % KNOT_STEP == 0 or index == path.size() - 1:
			knots.append((Vector2(path[index]) + Vector2(0.5, 0.5)) * tile)
	if knots.size() >= 2:
		var last := knots[knots.size() - 1]
		var dir := (last - knots[knots.size() - 2]).normalized()
		knots.append(last + dir * MOUTH_TILES * tile)
	points = _spline(knots)
	var length := 0.0
	var along := PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		length += points[i].distance_to(points[i - 1])
		along.append(length)
	widths.resize(points.size())
	for i in points.size():
		var t := along[i] / maxf(length, 1.0)
		var wobble := 1.0 + 0.08 * sin(along[i] / 90.0)
		widths[i] = lerpf(WIDTH_SPRING, WIDTH_MOUTH, pow(t, 0.85)) * wobble


## Catmull-Rom přes opěrné body, krok SAMPLE_PX.
static func _spline(knots: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if knots.size() < 2:
		return knots
	for i in knots.size() - 1:
		var p0 := knots[maxi(i - 1, 0)]
		var p1 := knots[i]
		var p2 := knots[i + 1]
		var p3 := knots[mini(i + 2, knots.size() - 1)]
		var steps := maxi(1, ceili(p1.distance_to(p2) / SAMPLE_PX))
		for s in steps:
			var t := float(s) / float(steps)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	out.append(knots[knots.size() - 1])
	return out


## Každý úsek osy do dlaždic, kterých se dotkne i se šířkou.
func _index() -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	for i in points.size() - 1:
		var half := maxf(widths[i], widths[i + 1]) * 0.5 + tile
		var low := points[i].min(points[i + 1]) - Vector2(half, half)
		var high := points[i].max(points[i + 1]) + Vector2(half, half)
		for cy in range(floori(low.y / tile), floori(high.y / tile) + 1):
			for cx in range(floori(low.x / tile), floori(high.x / tile) + 1):
				var key := Vector2i(cx, cy)
				var list: PackedInt32Array = _cells.get(key, PackedInt32Array())
				list.append(i)
				_cells[key] = list


## Most tam, kde řeka překročí cestu: kolmo přes řeku podél cesty, dlouhý jako řeka a kus navíc.
func _place_bridges(town: Town) -> void:
	var inside := false
	var first := 0
	for i in points.size():
		var on := town.on_road(points[i])
		if on and not inside:
			first = i
		if inside and (not on or i == points.size() - 1):
			var middle := (first + i) / 2
			var heading := town.road_heading(points[middle])
			var across := absf(sin(heading - (points[mini(middle + 1, points.size() - 1)] - points[maxi(middle - 1, 0)]).angle()))
			var span := widths[middle] / maxf(across, 0.5) + BRIDGE_OVERHANG
			bridges.append({"pos": points[middle], "turn": heading, "length": span})
		inside = on


# --- Scéna ---

## Síť řeky a mosty pod host. origin je levý horní roh čtverce ve světě.
func spawn(host: Node2D, origin: Vector2) -> void:
	if not exists():
		return
	var node := MeshInstance2D.new()
	node.mesh = _mesh()
	node.position = origin
	var material := ShaderMaterial.new()
	material.shader = load(SHADER)
	node.material = material
	host.add_child(node)
	_nodes.append(node)
	var texture := load(BRIDGE) as Texture2D
	if texture == null:
		return
	for bridge in bridges:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.position = origin + (bridge["pos"] as Vector2)
		sprite.rotation = float(bridge["turn"])
		sprite.scale = Vector2(float(bridge["length"]) / float(texture.get_width()), 1.0)
		host.add_child(sprite)
		_nodes.append(sprite)


func despawn() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()


## Pás trojúhelníků. UV.x je vzdálenost od pramene v px, UV.y napříč 0 až 1.
## Barva vrcholu nese poměr délky (r) a šířku v px (g, děleno WIDTH_MOUTH).
func _mesh() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var along := 0.0
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var dist := PackedFloat32Array()
	for i in points.size():
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, points.size() - 1)]
		var normal := (next - prev).normalized().orthogonal()
		left.append(points[i] + normal * widths[i] * 0.5)
		right.append(points[i] - normal * widths[i] * 0.5)
		if i > 0:
			along += points[i].distance_to(points[i - 1])
		dist.append(along)
	for i in points.size() - 1:
		var quad := [left[i], right[i], right[i + 1], left[i], right[i + 1], left[i + 1]]
		var quad_uv := [
			Vector2(dist[i], 0.0), Vector2(dist[i], 1.0), Vector2(dist[i + 1], 1.0),
			Vector2(dist[i], 0.0), Vector2(dist[i + 1], 1.0), Vector2(dist[i + 1], 0.0),
		]
		var ends := [i, i, i + 1, i, i + 1, i + 1]
		for k in 6:
			vertices.append(quad[k])
			uvs.append(quad_uv[k])
			var at: int = ends[k]
			colors.append(Color(dist[at] / maxf(total, 1.0), widths[at] / WIDTH_MOUTH, 0.0, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
