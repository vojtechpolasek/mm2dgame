extends RefCounted

## Řeka čtverce. Pramení kousek od kraje čtverce a teče do největší vody na čtverci.
## Čtverec bez vody řeku nemá. Trasu hledá A* po dlaždicích: skály, doly, továrna, domy
## a sklady jsou neprůchodné, jiná voda taky, šum v ceně řeku vlní. Na části čtverců vede
## řeka schválně přes cestu (BRIDGE_CHANCE) a přes cestu je most. Z dlaždic se vezme
## každá několikátá a proloží se křivkou, řeka proto není hranatá. U pramene je úzká,
## k ústí se rozšiřuje na WIDTH_MOUTH.
##
## Ramena (lines): první je hlavní řeka, k jejímu začátku se připojí 0 až 2 zdrojnice
## (BRANCH_WEIGHTS). Každé rameno začíná prameništěm (gen_spring.py), skalou, kterou řeka
## postaví do rocks. Typ prameniště je ze seznamu springs povrchu, na kterém pramen leží.
##
## Kreslí ji jedna síť (pásy trojúhelníků podél ramen) se shaderem river.gdshader, dvakrát:
## nejdřív písčité břehy všech ramen, pak voda všech ramen. Voda tak v soutoku překryje
## břeh druhého ramene. Most přes cestu je sprite. Shader dostane masku vody čtverce
## (water_mask): nad jezerem řeka nekreslí písčitý břeh a voda řeky se kousek za břehem
## jezera ztratí v jeho mělčině. Ústí tak navazuje přímo na břeh a k jezeru se rozšíří
## do nálevky. Postava i příšery řekou projdou, ale zpomalí (water_at), most je cesta
## a nezpomalí.
##
## Průběh: plan ve vlákně (nesahá na scénu), spawn na hlavním.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapData := preload("res://scripts/map_data.gd")
const Town := preload("res://scripts/town.gd")
const Rocks := preload("res://scripts/rocks.gd")

const SHADER := "res://shaders/river.gdshader"
const BRIDGE := "res://graphics/objects/bridge/most.png"
## Šířka řeky v pixelech u pramene a v ústí, i s břehem. Zdrojnice začíná na BRANCH_SPRING
## a do soutoku dojde na BRANCH_JOIN_WIDTH šířky hlavní řeky.
const WIDTH_SPRING := 8.0
const WIDTH_MOUTH := 128.0
const BRANCH_SPRING := 5.0
const BRANCH_JOIN_WIDTH := 0.8
## Šance na 0, 1 a 2 zdrojnice. Soutok je BRANCH_JOIN dlaždic po hlavní řece od pramene,
## pramen zdrojnice BRANCH_LENGTH dlaždic od soutoku, proti proudu do stran.
const BRANCH_WEIGHTS: Array[float] = [0.2, 0.45, 0.35]
const BRANCH_JOIN := Vector2(4.0, 16.0)
const BRANCH_LENGTH := Vector2(5.0, 11.0)
## Jen posledních tolik dlaždic trasy zdrojnice smí vést vedle jiného ramene.
const BRANCH_APPROACH := 3
## Hlavní řeka je pro trasu zdrojnice drahá, ať nevede podél ní.
const MAIN_WEIGHT := 60.0
## Prameny od sebe aspoň tolik dlaždic.
const SPRING_GAP := 4.0
## Prameniště, když povrch žádné nemá.
const SPRING_DEFAULT := "pramen_tun"
## Rameno se na prvních START_FADE px objeví, pod tůňkou prameniště.
const START_FADE := 16.0
## Index úseku v _cells: rameno * LINE_STRIDE + první bod úseku.
const LINE_STRIDE := 65536
## Posledních FLARE_TILES dlaždic před koncem se řeka rozšíří až o FLARE, nálevka do jezera.
const FLARE_TILES := 2.0
const FLARE := 0.4
## Šířka v barvě vrcholu je podíl WIDTH_MAX (barva má rozsah 0 až 1). Stejné číslo má shader.
const WIDTH_MAX := 192.0
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
## Meandry přidané k hotové křivce (_meander): u pramene záhyby až BEND_TILES dlaždic do
## strany s vlnou BEND_WAVE.x dlaždic, po proudu slábnou a vlna se prodlužuje k BEND_WAVE.y.
## U hlavní řeky zmizí po BEND_REACH délky, zdrojnice se kroutí celá a k soutoku slábne.
## Záhyb je nejvýš třetina vlny, ať se řeka nesmyčkuje.
const BEND_TILES := 2.5
const BRANCH_BEND_TILES := 1.4
const BEND_WAVE := Vector2(6.0, 12.0)
const BEND_REACH := 0.4
## První BEND_START px od pramene se záhyb rozbíhá, osa vychází z prameniště rovně.
const BEND_START := 64.0
## Záhyb, který by vedl na neprůchodnou dlaždici nebo na cestu, se zmenší po krocích.
const BEND_SHRINK: Array[float] = [1.0, 0.66, 0.33, 0.0]
## Zdrojnice se záhybem nepřiblíží k jinému rameni na méně než BEND_GAP dlaždic, kromě
## posledních BEND_JOIN dlaždic před soutokem.
const BEND_GAP := 1.2
const BEND_JOIN := 2.5
## Z cesty po dlaždicích se bere každý tolikátý bod jako opěrný bod křivky.
const KNOT_STEP := 3
## Krok křivky v pixelech.
const SAMPLE_PX := 12.0
## Trasa končí na první dlaždici vody, osa sahá ještě o tolik dlaždic dál. Za břehem se
## řeka ztratí v jezeře podle masky vody. Kdyby síť skončila dřív, posledních END_FADE px
## se ztratí samo, konec nikdy není useknutý.
const MOUTH_TILES := 2.0
const END_FADE := 48.0
## Voda je vnitřní část šířky, zbytek je břeh. Zpomaluje jen voda.
const WATER_SHARE := 0.78
## Délka mostu navíc k šířce řeky, v pixelech.
const BRIDGE_OVERHANG := 72.0

## Osa hlavní řeky ve čtverci (od pramene k ústí) a šířka v každém bodě.
var points := PackedVector2Array()
var widths := PackedFloat32Array()
## Ramena: {points, widths, length (px), spring (druh prameniště)}. První je hlavní řeka.
var lines: Array[Dictionary] = []
## Mosty: střed, natočení a délka v pixelech.
var bridges: Array[Dictionary] = []
## Dlaždice -> úseky ramen, které jí vedou (viz LINE_STRIDE).
var _cells := {}
var _size := 0
## Posun čtverce ve světě. Dotazy berou světové souřadnice.
var _origin := Vector2.ZERO
## Uzly ve scéně (síť a mosty), pro despawn.
var _nodes: Array[Node] = []
## Voda čtverce pro shader řeky (255 voda), vzniká ve vlákně v plan. Bere se z rohů
## dlaždic (vertex), podle nich terén kreslí břeh. Bez nich po dlaždicích.
var _water_mask: Image
## Texel masky i leží na rohu dlaždice i (posun 0.5), nebo na jejím středu (0).
var _mask_shift := 0.0


func exists() -> bool:
	return not lines.is_empty()


## Najde trasu. rocks a town už stojí. seed drží řeku stejnou i po načtení hry.
## vertex je terén rohů dlaždic ((size + 1)², viz MapGenerator.corner_data). Z něj je maska
## vody pro shader, ať ústí sedí na břeh, jak ho kreslí terén.
func plan(map: MapData, rocks: Rocks, town: Town, seed: int, vertex := PackedByteArray()) -> void:
	points = PackedVector2Array()
	widths = PackedFloat32Array()
	lines.clear()
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
	var spring_kind := ""
	var crossing := town != null and rng.randf() < BRIDGE_CHANCE
	for spring in _springs(map, grid, lake, rng):
		spring_kind = _spring_kind(map, spring, rng)
		if rocks != null and not rocks.spring_room(spring_kind, _center(spring)):
			continue
		if crossing:
			path = _via_road(grid, spring, lake, town)
		if path.is_empty():
			path = grid.get_id_path(spring, _nearest(lake, spring))
		if path.size() >= 8:
			break
		path = []
	if path.is_empty():
		return
	_water_mask = _mask(map, water, vertex)
	_mask_shift = 0.5 if _water_mask.get_width() > map.size else 0.0
	var main := _shape(path, WIDTH_SPRING, WIDTH_MOUTH, true, grid, town, rng)
	main["spring"] = spring_kind
	lines.append(main)
	points = main["points"]
	widths = main["widths"]
	_add_branches(map, rocks, town, grid, path, rng)
	_index()
	if rocks != null:
		_place_springs(rocks, rng)
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
	for code: int in list:
		var line := lines[code / LINE_STRIDE]
		var line_points: PackedVector2Array = line["points"]
		var line_widths: PackedFloat32Array = line["widths"]
		var at := code % LINE_STRIDE
		var a := line_points[at]
		var b := line_points[at + 1]
		var ab := b - a
		var t := clampf((local - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var half := lerpf(line_widths[at], line_widths[at + 1], t) * 0.5 * share + margin
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


## Kandidáti na pramen, nejlepší první: náhodná volná místa v pásu u kraje, daleko od vody,
## potom i blíž. Bod je volná dlaždice mřížky. Jestli se vejde prameniště, hlídá plan.
func _springs(map: MapData, grid: AStarGrid2D, lake: PackedVector2Array, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var size := map.size
	var out: Array[Vector2i] = []
	for far in [SPRING_FAR, SPRING_NEAR]:
		var found := 0
		for _try in 80:
			if found >= 8:
				break
			var cell := Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
			if _in_band(cell, size) and not grid.is_point_solid(cell) and _distance(lake, cell) >= far:
				out.append(cell)
				found += 1
	return out


## Prameniště pro pramen na dlaždici cell: náhodné ze seznamu springs jejího povrchu.
func _spring_kind(map: MapData, cell: Vector2i, rng: RandomNumberGenerator) -> String:
	var info := map.info_of(map.terrain[cell.y * map.size + cell.x])
	var list: Array = info.get("springs", [])
	if list.is_empty():
		return SPRING_DEFAULT
	return str(list[rng.randi_range(0, list.size() - 1)])


static func _center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * float(TerrainCatalog.TILE_SIZE)


## Zdrojnice: pramen proti proudu do strany od soutoku na začátku hlavní řeky (path),
## trasa A* do soutoku. Hlavní řeka je pro ni drahá, ať nevede podél ní.
func _add_branches(map: MapData, rocks: Rocks, town: Town, grid: AStarGrid2D, path: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	var count := rng.rand_weighted(PackedFloat32Array(BRANCH_WEIGHTS))
	var last_join := mini(int(BRANCH_JOIN.y), path.size() / 2)
	if count <= 0 or last_join < int(BRANCH_JOIN.x):
		return
	var main_cells := {}
	for cell in path:
		main_cells[cell] = true
		grid.set_point_weight_scale(cell, MAIN_WEIGHT)
	var tile := float(TerrainCatalog.TILE_SIZE)
	var water := map.names.find("water")
	var springs: Array[Vector2] = [(lines[0]["points"] as PackedVector2Array)[0]]
	if rocks != null:
		_avoid_spring(grid, springs[0], rocks.spring_reach(str(lines[0]["spring"])))
	for _branch in count:
		for _try in 40:
			var join_at := rng.randi_range(int(BRANCH_JOIN.x), last_join)
			var join := path[join_at]
			var upstream := Vector2(path[maxi(join_at - 3, 0)] - join)
			if upstream.length_squared() < 0.5:
				continue
			var angle := upstream.angle() + rng.randf_range(-1.1, 1.1)
			var cell := join + Vector2i((Vector2.from_angle(angle) * rng.randf_range(BRANCH_LENGTH.x, BRANCH_LENGTH.y)).round())
			if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell) or main_cells.has(cell):
				continue
			if mini(mini(cell.x, cell.y), mini(map.size - 1 - cell.x, map.size - 1 - cell.y)) < EDGE_TILES + 2:
				continue
			if map.terrain[cell.y * map.size + cell.x] == water:
				continue
			var pos := _center(cell)
			var crowded := false
			for other in springs:
				if other.distance_to(pos) < SPRING_GAP * tile:
					crowded = true
					break
			if crowded:
				continue
			var kind := _spring_kind(map, cell, rng)
			if rocks != null and not rocks.spring_room(kind, pos):
				continue
			var route := grid.get_id_path(cell, join)
			if route.size() < 4 or _crosses(route, main_cells):
				continue
			# Do soutoku musí přitékat po proudu, ne proti němu.
			var flow := Vector2(path[mini(join_at + 2, path.size() - 1)] - path[maxi(join_at - 2, 0)])
			var inflow := Vector2(route[route.size() - 1] - route[maxi(route.size() - 4, 0)])
			if inflow.dot(flow) < 0.0:
				continue
			var join_width := _width_near(lines[0], _center(join)) * BRANCH_JOIN_WIDTH
			# Hlavní řeka má záhyby, soutok je na její skutečné ose, ne ve středu dlaždice.
			var into := _point_near(lines[0], _center(join))
			var line := _shape(route, BRANCH_SPRING, join_width, false, grid, town, rng, into)
			line["spring"] = kind
			lines.append(line)
			springs.append(pos)
			# Další zdrojnice tudy nepovede, ramena se nekříží.
			for i in route.size() - 1:
				main_cells[route[i]] = true
				grid.set_point_weight_scale(route[i], MAIN_WEIGHT)
			if rocks != null:
				_avoid_spring(grid, pos, rocks.spring_reach(kind))
			break


## Prameniště stojí až po trasách. Dlaždice pod ním jsou pro další trasy drahé, ať pod skálou
## nevede jiné rameno. Neprůchodné nejsou, rameno z prameniště musí ven.
static func _avoid_spring(grid: AStarGrid2D, pos: Vector2, reach: float) -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var span := ceili(reach / tile)
	var at := Vector2i((pos / tile).floor())
	for y in range(at.y - span, at.y + span + 1):
		for x in range(at.x - span, at.x + span + 1):
			var cell := Vector2i(x, y)
			if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell) and _center(cell).distance_to(pos) <= reach:
				grid.set_point_weight_scale(cell, MAIN_WEIGHT)


## Vede trasa přes hlavní řeku nebo jinou zdrojnici, nebo těsně podél ní, jinde než u soutoku
## (poslední BRANCH_APPROACH dlaždice)? Taková zdrojnice by se k řece přimkla a stočila háčkem.
static func _crosses(route: Array[Vector2i], main_cells: Dictionary) -> bool:
	for i in maxi(route.size() - BRANCH_APPROACH, 0):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if main_cells.has(route[i] + Vector2i(dx, dy)):
					return true
	return false


## Bod osy ramene line nejblíž pos.
static func _point_near(line: Dictionary, pos: Vector2) -> Vector2:
	var best := INF
	var at := Vector2.ZERO
	for point: Vector2 in line["points"]:
		var d := point.distance_squared_to(pos)
		if d < best:
			best = d
			at = point
	return at


## Šířka ramene line v bodě osy nejblíž pos.
static func _width_near(line: Dictionary, pos: Vector2) -> float:
	var line_points: PackedVector2Array = line["points"]
	var best := INF
	var at := 0
	for i in line_points.size():
		var d := line_points[i].distance_squared_to(pos)
		if d < best:
			best = d
			at = i
	return (line["widths"] as PackedFloat32Array)[at]


## Prameniště na začátek každého ramene, otočené po proudu. Když se nevejde, rameno se jen
## objeví (START_FADE).
func _place_springs(rocks: Rocks, rng: RandomNumberGenerator) -> void:
	for line in lines:
		var line_points: PackedVector2Array = line["points"]
		var ahead := line_points[mini(4, line_points.size() - 1)] - line_points[0]
		rocks.place_spring(str(line["spring"]), line_points[0], ahead.angle(), rng.randi())


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


## Z dlaždic cesty rameno: křivka s meandry a šířky od start do end. Hlavní řeka (mouth) se
## protáhne do vody a k jezeru rozšíří do nálevky. end_at nahradí poslední bod trasy (soutok
## zdrojnice na ose hlavní řeky).
func _shape(
	path: Array[Vector2i],
	start: float,
	end: float,
	mouth: bool,
	grid: AStarGrid2D,
	town: Town,
	rng: RandomNumberGenerator,
	end_at := Vector2.INF,
) -> Dictionary:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var knots := PackedVector2Array()
	for index in path.size():
		if index % KNOT_STEP == 0 or index == path.size() - 1:
			knots.append(_center(path[index]))
	if end_at != Vector2.INF and not knots.is_empty():
		knots[knots.size() - 1] = end_at
	if mouth and knots.size() >= 2:
		var last := knots[knots.size() - 1]
		var dir := (last - knots[knots.size() - 2]).normalized()
		knots.append(last + dir * MOUTH_TILES * tile)
	var line_points := _spline(knots)
	if mouth:
		line_points = _meander(line_points, BEND_TILES, BEND_REACH, grid, town, rng, [])
	else:
		line_points = _meander(line_points, BRANCH_BEND_TILES, 1.0, grid, town, rng, lines)
	var length := 0.0
	var along := PackedFloat32Array([0.0])
	for i in range(1, line_points.size()):
		length += line_points[i].distance_to(line_points[i - 1])
		along.append(length)
	var line_widths := PackedFloat32Array()
	line_widths.resize(line_points.size())
	var flare_px := FLARE_TILES * tile
	for i in line_points.size():
		var t := along[i] / maxf(length, 1.0)
		var wobble := 1.0 + 0.08 * sin(along[i] / 90.0)
		var flare := 1.0 + FLARE * smoothstep(flare_px, 0.0, length - along[i]) if mouth else 1.0
		# Zdrojnice se těsně před soutokem zúží, konec se schová ve vodě hlavní řeky.
		if not mouth:
			flare = lerpf(0.4, 1.0, smoothstep(0.0, end, length - along[i]))
		line_widths[i] = lerpf(start, end, pow(t, 0.85)) * wobble * flare
	return {"points": line_points, "widths": line_widths, "length": length}


## Voda čtverce jako obrázek: pixel na roh dlaždice z vertex, bez něj pixel na dlaždici.
## Shader ho čte s vyhlazením, hranice je oblá.
static func _mask(map: MapData, water: int, vertex: PackedByteArray) -> Image:
	var corners := vertex.size() == (map.size + 1) * (map.size + 1)
	var span := map.size + 1 if corners else map.size
	var source := vertex if corners else map.terrain
	var bytes := PackedByteArray()
	bytes.resize(span * span)
	for cell in bytes.size():
		if source[cell] == water:
			bytes[cell] = 255
	return Image.create_from_data(span, span, false, Image.FORMAT_L8, bytes)


## Osa posunutá do stran vlnou se šumem. Záhyb je bend dlaždic u pramene a slábne do nuly
## na reach podílu délky. Kde by bod vedl na neprůchodnou dlaždici, na cestu nebo blíž než
## BEND_GAP k ramenům others, záhyb se zmenší a změna se rozleje do okolí, ať osa nemá zlom.
static func _meander(
	line_points: PackedVector2Array,
	bend: float,
	reach: float,
	grid: AStarGrid2D,
	town: Town,
	rng: RandomNumberGenerator,
	others: Array[Dictionary],
) -> PackedVector2Array:
	var count := line_points.size()
	if count < 3:
		return line_points
	var tile := float(TerrainCatalog.TILE_SIZE)
	var along := PackedFloat32Array([0.0])
	for i in range(1, count):
		along.append(along[i - 1] + line_points[i].distance_to(line_points[i - 1]))
	var span := maxf(along[count - 1] * reach, 1.0)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.0 / (BEND_WAVE.x * tile)
	var phase := rng.randf() * TAU
	var normals := PackedVector2Array()
	var offsets := PackedFloat32Array()
	for i in count:
		var ahead := line_points[mini(i + 1, count - 1)] - line_points[maxi(i - 1, 0)]
		normals.append(ahead.normalized().orthogonal())
		var t := clampf(along[i] / span, 0.0, 1.0)
		var wave := lerpf(BEND_WAVE.x, BEND_WAVE.y, t) * tile
		if i > 0:
			phase += TAU * (along[i] - along[i - 1]) / wave
		var size := minf(bend * tile, wave * 0.33) * pow(1.0 - t, 2.0)
		size *= smoothstep(0.0, BEND_START, along[i])
		offsets.append(size * (sin(phase) * 0.75 + noise.get_noise_1d(along[i]) * 0.5))
	# Kolik záhybu se vejde: neprůchodná dlaždice ani cesta pod posunutým bodem.
	var fit := PackedFloat32Array()
	fit.resize(count)
	var total := along[count - 1]
	for i in count:
		fit[i] = 0.0
		var near_join := total - along[i] < BEND_JOIN * tile
		for share in BEND_SHRINK:
			var pos := line_points[i] + normals[i] * offsets[i] * share
			if not _bend_clear(pos, line_points[i], grid, town):
				continue
			if share > 0.0 and not near_join and _near_lines(pos, others, BEND_GAP * tile):
				continue
			fit[i] = share
			break
	# Nejmenší v okolí, potom průměr, ať se záhyb kolem překážky zmenší plynule.
	var reach_px := 4
	var low := PackedFloat32Array()
	low.resize(count)
	for i in count:
		var least := 1.0
		for k in range(maxi(i - reach_px, 0), mini(i + reach_px, count - 1) + 1):
			least = minf(least, fit[k])
		low[i] = least
	var out := PackedVector2Array()
	for i in count:
		var sum := 0.0
		var n := 0
		for k in range(maxi(i - reach_px, 0), mini(i + reach_px, count - 1) + 1):
			sum += low[k]
			n += 1
		out.append(line_points[i] + normals[i] * offsets[i] * sum / float(n))
	return out


## Leží pos blíž než gap k ose některého z ramen?
static func _near_lines(pos: Vector2, others: Array[Dictionary], gap: float) -> bool:
	for line in others:
		for point: Vector2 in line["points"]:
			if pos.distance_squared_to(point) < gap * gap:
				return true
	return false


## Smí osa vést bodem pos? Ne přes neprůchodnou dlaždici a ne na cestu, pokud na ní už
## nebyl původní bod (přechod přes cestu s mostem zůstane, jak byl).
static func _bend_clear(pos: Vector2, from: Vector2, grid: AStarGrid2D, town: Town) -> bool:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var cell := Vector2i((pos / tile).floor())
	if grid == null or not grid.is_in_boundsv(cell) or grid.is_point_solid(cell):
		return false
	if town != null and town.road_near(pos, tile * 0.3) and not town.road_near(from, tile * 0.3):
		return false
	return true


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


## Každý úsek každého ramene do dlaždic, kterých se dotkne i se šířkou.
func _index() -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	for line_index in lines.size():
		var line_points: PackedVector2Array = lines[line_index]["points"]
		var line_widths: PackedFloat32Array = lines[line_index]["widths"]
		for i in line_points.size() - 1:
			var half := maxf(line_widths[i], line_widths[i + 1]) * 0.5 + tile
			var low := line_points[i].min(line_points[i + 1]) - Vector2(half, half)
			var high := line_points[i].max(line_points[i + 1]) + Vector2(half, half)
			for cy in range(floori(low.y / tile), floori(high.y / tile) + 1):
				for cx in range(floori(low.x / tile), floori(high.x / tile) + 1):
					var key := Vector2i(cx, cy)
					var list: PackedInt32Array = _cells.get(key, PackedInt32Array())
					list.append(line_index * LINE_STRIDE + i)
					_cells[key] = list


## Most tam, kde řeka překročí cestu: kolmo přes řeku podél cesty, dlouhý jako řeka a kus navíc.
func _place_bridges(town: Town) -> void:
	for line in lines:
		var line_points: PackedVector2Array = line["points"]
		var line_widths: PackedFloat32Array = line["widths"]
		var inside := false
		var first := 0
		for i in line_points.size():
			var on := town.on_road(line_points[i])
			if on and not inside:
				first = i
			if inside and (not on or i == line_points.size() - 1):
				var middle := (first + i) / 2
				var heading := town.road_heading(line_points[middle])
				var along := line_points[mini(middle + 1, line_points.size() - 1)] - line_points[maxi(middle - 1, 0)]
				var across := absf(sin(heading - along.angle()))
				var span := line_widths[middle] / maxf(across, 0.5) + BRIDGE_OVERHANG
				bridges.append({"pos": line_points[middle], "turn": heading, "length": span})
			inside = on


# --- Scéna ---

## Síť řeky a mosty pod host. origin je levý horní roh čtverce ve světě.
func spawn(host: Node2D, origin: Vector2) -> void:
	if not exists():
		return
	var mesh := _mesh()
	var mask := ImageTexture.create_from_image(_water_mask) if _water_mask != null else null
	# Nejdřív břehy všech ramen, potom voda všech ramen.
	for part in 2:
		var node := MeshInstance2D.new()
		node.mesh = mesh
		node.position = origin
		var material := ShaderMaterial.new()
		material.shader = load(SHADER)
		material.set_shader_parameter("part", part)
		if mask != null:
			material.set_shader_parameter("water_mask", mask)
			material.set_shader_parameter("mask_size", float(_water_mask.get_width()))
			material.set_shader_parameter("mask_shift", _mask_shift)
		material.set_shader_parameter("length_px", float(lines[0]["length"]))
		material.set_shader_parameter("end_fade", END_FADE)
		material.set_shader_parameter("start_fade", START_FADE)
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


## Pásy trojúhelníků všech ramen, hlavní řeka poslední. UV.x je vzdálenost od pramene
## ramene v px, UV.y napříč 0 až 1. Barva vrcholu nese šířku v px (g, děleno WIDTH_MAX)
## a hlavní řeku (b = 1), jen ta se v ústí ztrácí. Zdrojnice končí pod vodou hlavní řeky.
func _mesh() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	# Hlavní řeka poslední: její voda v soutoku překryje konec zdrojnice.
	var order: Array[int] = []
	for line_index in range(1, lines.size()):
		order.append(line_index)
	order.append(0)
	for line_index in order:
		var line_points: PackedVector2Array = lines[line_index]["points"]
		var line_widths: PackedFloat32Array = lines[line_index]["widths"]
		var main := 1.0 if line_index == 0 else 0.0
		var along := 0.0
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var dist := PackedFloat32Array()
		for i in line_points.size():
			var prev := line_points[maxi(i - 1, 0)]
			var next := line_points[mini(i + 1, line_points.size() - 1)]
			var normal := (next - prev).normalized().orthogonal()
			left.append(line_points[i] + normal * line_widths[i] * 0.5)
			right.append(line_points[i] - normal * line_widths[i] * 0.5)
			if i > 0:
				along += line_points[i].distance_to(line_points[i - 1])
			dist.append(along)
		for i in line_points.size() - 1:
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
				colors.append(Color(0.0, line_widths[at] / WIDTH_MAX, main, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
