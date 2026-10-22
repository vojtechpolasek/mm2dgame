extends RefCounted

## Řeky čtverce. Tečou do největší vody na čtverci, jedna nebo dvě (RIVER_WEIGHTS), ústí od
## sebe aspoň MOUTH_GAP. Řeka pramení kousek od kraje čtverce, nebo (EDGE_CHANCE) přitéká
## přes kraj od souseda, který ještě nemá mapu. Na kraji pak zůstane vtok (exits) a soused,
## až vznikne, k němu dovede řeku od vlastního pramene (inlets). Řeka tak vede nejvýš přes dva
## čtverce, soused ji dál neposílá. Trasu hledá A* po dlaždicích: skály a místo pro vesnici
## (reserve) jsou neprůchodné, voda taky (do jezera řeka vteče z dlaždice na břehu), šum
## v ceně řeku vlní. Z dlaždic se vezme každá několikátá a proloží se křivkou, řeka proto
## není hranatá. U pramene je úzká, k ústí se rozšiřuje na WIDTH_MOUTH.
##
## Řeka vzniká po přírodních skalách a před vesnicí. Domy, sklady a doly se řece a jejím
## prameništím vyhnou (near), cesta ji přejde kdekoli a na přechodu je most (place_bridges).
##
## Ramena (lines): řeky a jejich přítoky. Ke každé řece se kdekoli po proudu připojí 0 až 3
## přítoky (BRANCH_WEIGHTS), pramení ve čtverci, nebo přitékají přes kraj od souseda stejně
## jako řeka. Rameno od pramene začíná prameništěm (gen_spring.py), skalou, kterou řeka
## postaví do rocks. Typ prameniště je ze seznamu springs povrchu, na kterém pramen leží.
##
## Přes kraj vede rameno posledních EDGE_STRAIGHT dlaždic kolmo, bez záhybů, a na kraji má
## šířku vtoku. Síť každého čtverce končí přesně na kraji a UV.x (proud) na kraji je u obou
## čtverců FLOW_BASE, takže voda i břeh navazují.
##
## Kreslí je jedna síť (pásy trojúhelníků podél ramen) se shaderem river.gdshader, dvakrát:
## nejdřív břehy (svah dolů k hladině) všech ramen, pak voda všech ramen. Pás sítě je o svah
## (BANK_PAD * BANK_REACH) širší než rameno a nese zakřivení osy: na vnitřní straně zákruty
## je náplava, na vnější vymletý břeh. Voda tak v soutoku překryje
## břeh druhého ramene. Most přes cestu je sprite. Shader dostane masku vody čtverce
## (water_mask): nad jezerem řeka nekreslí písčitý břeh a voda řeky se kousek za břehem
## jezera ztratí v jeho mělčině. Ústí tak navazuje přímo na břeh a k jezeru se rozšíří
## do nálevky. Postava i příšery řekou projdou, ale zpomalí (water_at), most je cesta
## a nezpomalí.
##
## Průběh: plan a place_bridges ve vlákně (nesahá na scénu), spawn na hlavním.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapData := preload("res://scripts/map_data.gd")
const Town := preload("res://scripts/town.gd")
const Rocks := preload("res://scripts/rocks.gd")

const SHADER := "res://shaders/river.gdshader"
const BRIDGE := "res://graphics/objects/bridge/most.png"
## Strany čtverce. Index je strana ve vtocích (exits, inlets), vektor míří k sousedovi.
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
## Šance na jednu a dvě řeky do jezera.
const RIVER_WEIGHTS: Array[float] = [0.55, 0.45]
## Ústí řek od sebe aspoň tolik dlaždic.
const MOUTH_GAP := 12.0
## Šířka řeky v pixelech u pramene a v ústí, i s břehem. Přítok začíná na BRANCH_SPRING
## a do soutoku dojde na BRANCH_JOIN_WIDTH šířky řeky.
const WIDTH_SPRING := 8.0
const WIDTH_MOUTH := 128.0
const BRANCH_SPRING := 5.0
const BRANCH_JOIN_WIDTH := 0.6
## Šance na 0, 1, 2 a 3 přítoky. Soutok je aspoň BRANCH_JOIN_FROM dlaždic po řece od jejího
## začátku a ne v posledních BRANCH_JOIN_END dlaždicích. Pramen přítoku je BRANCH_LENGTH
## dlaždic od soutoku, proti proudu do stran.
const BRANCH_WEIGHTS: Array[float] = [0.15, 0.35, 0.3, 0.2]
const BRANCH_JOIN_FROM := 4
const BRANCH_JOIN_END := 6
const BRANCH_LENGTH := Vector2(6.0, 20.0)
## Jen posledních tolik dlaždic trasy přítoku smí vést vedle jiného ramene.
const BRANCH_APPROACH := 3
## Ramena jsou pro trasy dalších drahá, ať nevedou podél nich.
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
## Řeka přitéká přes kraj od souseda s šancí EDGE_CHANCE, přítok s BRANCH_EDGE_CHANCE, jen
## přes kraj, za kterým ještě není mapa. Vtok je aspoň EDGE_MARGIN dlaždic od rohu a EDGE_GAP
## od jiného vtoku. Šířka řeky na kraji je EDGE_WIDTH, přítoku BRANCH_EDGE_WIDTH (nejvýš
## BRANCH_EDGE_SHARE šířky v soutoku). Trasa přítoku od kraje má nejvýš BRANCH_EDGE_CELLS dlaždic.
const EDGE_CHANCE := 0.45
const BRANCH_EDGE_CHANCE := 0.3
const EDGE_MARGIN := 16
const EDGE_GAP := 12.0
const EDGE_WIDTH := Vector2(44.0, 72.0)
const BRANCH_EDGE_WIDTH := Vector2(22.0, 36.0)
const BRANCH_EDGE_SHARE := 0.7
const BRANCH_EDGE_CELLS := 48
## Od kraje vede rameno tolik dlaždic rovně, kolmo na kraj. Záhyby začnou až za EDGE_CALM px.
const EDGE_STRAIGHT := 5
const EDGE_CALM := 128.0
## UV.x (proud ve shaderu) na kraji čtverce. Rameno od kraje odtud roste, rameno ke kraji
## sem dojde. Víc, než je délka ramene ve čtverci.
const FLOW_BASE := 20000.0
## Pokračování řeky od souseda: pramen INLET_SPRING dlaždic od vtoku. Když se nikam nevejde,
## pramen je INLET_NEAR dlaždic rovně od kraje. V kruhu se středem INLET_CLEAR.x dlaždic od
## kraje a poloměrem INLET_CLEAR.y dlaždic není voda (svět ji vysuší) ani pata skály, takže
## tahle nouzová cesta projde vždycky.
const INLET_SPRING := Vector2(14.0, 40.0)
const INLET_NEAR := 7
const INLET_CLEAR := Vector2(4.0, 5.0)
## Šum v ceně dlaždice, řeka se vlní.
const MEANDER := 3.0
## Meandry přidané k hotové křivce (_meander): u pramene záhyby až BEND_TILES dlaždic do
## strany s vlnou BEND_WAVE.x dlaždic, po proudu slábnou a vlna se prodlužuje k BEND_WAVE.y.
## U řeky do jezera zmizí po BEND_REACH délky, řeka ke kraji a přítok se kroutí celé a ke
## konci slábnou. Záhyb je nejvýš třetina vlny, ať se řeka nesmyčkuje.
const BEND_TILES := 2.5
const BRANCH_BEND_TILES := 1.4
const BEND_WAVE := Vector2(6.0, 12.0)
const BEND_REACH := 0.4
## První BEND_START px od začátku se záhyb rozbíhá, osa vychází z prameniště rovně.
const BEND_START := 64.0
## Záhyb, který by vedl na neprůchodnou dlaždici nebo na cestu, se zmenší po krocích.
const BEND_SHRINK: Array[float] = [1.0, 0.66, 0.33, 0.0]
## Rameno se záhybem nepřiblíží k jinému rameni na méně než BEND_GAP dlaždic, kromě
## posledních BEND_JOIN dlaždic před koncem.
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
## Svah břehu za šířkou ramene v px: BANK_MIN + šířka * BANK_SHARE, nejvýš BANK_PAD. Shader
## ho po proudu mění, na náplavě až BANK_REACH krát. Stejná čísla má river.gdshader.
const BANK_PAD := 40.0
const BANK_MIN := 10.0
const BANK_SHARE := 0.4
const BANK_REACH := 1.6
## Zakřivení osy, které je v barvě vrcholu naplno (náplava), v 1/px. Měří se přes
## BEND_SPAN bodů na každou stranu.
const BEND_FULL := 0.011
const BEND_SPAN := 3
## Pás na vnitřní straně zákruty sahá nejvýš na takový podíl jejího poloměru.
const FOLD_ROOM := 0.85
## Délka mostu navíc k šířce řeky, v pixelech. Šikmý most se prodlouží, nejvýš jako most
## pod úhlem asin(BRIDGE_SKEW).
const BRIDGE_OVERHANG := 72.0
const BRIDGE_SKEW := 0.2

## Ramena: {points, widths, length (px), spring (druh prameniště, "" u ramene od kraje),
## mouth (končí v jezeře), main (řeka, ne přítok), flow (UV.x prvního bodu)}.
var lines: Array[Dictionary] = []
## Vtoky na krajích, kudy přitéká rameno od souseda bez mapy: {side (index do SIDES),
## at (dlaždice podél kraje), width (šířka na kraji v px)}. Soused je dostane jako inlets.
var exits: Array[Dictionary] = []
## Mosty: střed, natočení a délka v pixelech.
var bridges: Array[Dictionary] = []
## Prameniště ramen: střed x, y a dosah paty v px.
var _spring_rocks := PackedVector3Array()
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

# Jen během plan.
var _map: MapData
var _rocks: Rocks
var _grid: AStarGrid2D
var _rng: RandomNumberGenerator
## Největší voda, dlaždice jejího břehu (-> dlaždice vody vedle) a ústí řek do ní.
var _lake := PackedVector2Array()
var _shore := {}
var _mouths: Array[Vector2i] = []
## Dlaždice tras všech ramen a prameny v px.
var _taken := {}
var _spring_spots: Array[Vector2] = []


func exists() -> bool:
	return not lines.is_empty()


## Najde trasy. Přírodní skály (rocks) už stojí, vesnice ještě ne: reserve je kruh pro ni
## (střed x, y a poloměr v px, poloměr 0 bez vesnice), tam řeka nevede. seed drží řeky stejné
## i po načtení hry. vertex je terén rohů dlaždic ((size + 1)², viz MapGenerator.corner_data).
## Z něj je maska vody pro shader, ať ústí sedí na břeh, jak ho kreslí terén.
## open: bity stran (1 << index v SIDES), za kterými ještě není mapa, odtud smí rameno
## přitékat. inlets: vtoky hotových sousedů na krajích tohoto čtverce ({side, at, width}
## jako exits, side je strana tohoto čtverce), k nim se dovede řeka od pramene.
func plan(
	map: MapData,
	rocks: Rocks,
	reserve: Vector3,
	seed: int,
	vertex := PackedByteArray(),
	open := 0,
	inlets: Array = [],
) -> void:
	lines.clear()
	exits.clear()
	bridges.clear()
	_spring_rocks = PackedVector3Array()
	_cells.clear()
	_size = map.size
	var water := map.names.find("water")
	_lake = _largest_water(map, water) if water >= 0 else PackedVector2Array()
	if _lake.is_empty() and inlets.is_empty():
		return
	_map = map
	_rocks = rocks
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed
	_grid = _make_grid(water, reserve)
	_taken = {}
	_spring_spots.clear()
	_mouths.clear()
	# Vtoky od sousedů první, jejich místo je dané. Rovné úseky u kraje si zaberou předem,
	# ať trasa k jednomu vtoku nevede přes jiný.
	var entries: Array = []
	for inlet in inlets:
		var straight := _straight(int(inlet["side"]), int(inlet["at"]))
		if straight.is_empty():
			continue
		entries.append([inlet, straight])
		for cell in straight:
			_taken[cell] = true
	for entry: Array in entries:
		var inlet: Dictionary = entry[0]
		_add_inlet(int(inlet["side"]), int(inlet["at"]), float(inlet["width"]), entry[1])
	if not _lake.is_empty():
		_shore = _shore_of(_lake)
		var count := 1 + _rng.rand_weighted(PackedFloat32Array(RIVER_WEIGHTS))
		for _river in count:
			_add_river(open)
	if exists():
		_water_mask = _mask(map, water, vertex)
		_mask_shift = 0.5 if _water_mask.get_width() > map.size else 0.0
		_index()
		if rocks != null:
			_place_springs()
	_map = null
	_rocks = null
	_grid = null
	_shore = {}
	_taken = {}


## Kde u vtoků inlets (viz plan) nesmí stát skála, ať k nim řeka projde: kruhy (střed x, y
## a poloměr v px) pro Rocks.keep_clear. size je strana čtverce v dlaždicích.
static func clear_spots(inlets: Array, size: int) -> PackedVector3Array:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var out := PackedVector3Array()
	for inlet in inlets:
		var side := int(inlet["side"])
		var pos := _edge_point(side, int(inlet["at"]), size) - Vector2(SIDES[side]) * INLET_CLEAR.x * tile
		out.append(Vector3(pos.x, pos.y, INLET_CLEAR.y * tile))
	return out


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


## Je bod blíž než margin px k řece i se svahem břehu, nebo k prameništi? Pro sázení stromů,
## porostu, domů, skladů a dolů.
func near(pos: Vector2, margin: float) -> bool:
	var local := pos - _origin
	for spring in _spring_rocks:
		var reach := spring.z + margin
		if local.distance_squared_to(Vector2(spring.x, spring.y)) < reach * reach:
			return true
	return _reach_at(local, margin, 1.0, true)


## Obvyklá šířka svahu břehu za ramenem šířky width v px.
static func bank_width(width: float) -> float:
	return minf(BANK_PAD, BANK_MIN + width * BANK_SHARE)


## Přechody cesty přes řeku. road jsou body osy cesty (ve čtverci, před relocate). Za každý
## souvislý úsek cesty nad řekou Vector2(|sin| úhlu mezi cestou a řekou, 1 je kolmo, šířka
## řeky v px).
func crossings(road: PackedVector2Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var first := -1
	for i in road.size() + 1:
		var wet := i < road.size() and _reach_at(road[i], 0.0, 1.0)
		if wet and first < 0:
			first = i
		if wet or first < 0:
			continue
		var middle := (first + i - 1) / 2
		first = -1
		var code := _segment_at(road[middle])
		if code < 0:
			continue
		var line := lines[code / LINE_STRIDE]
		var at := code % LINE_STRIDE
		var line_points: PackedVector2Array = line["points"]
		var flow := (line_points[at + 1] - line_points[at]).normalized()
		var heading := (road[mini(middle + 1, road.size() - 1)] - road[maxi(middle - 1, 0)]).normalized()
		out.append(Vector2(absf(heading.cross(flow)), (line["widths"] as PackedFloat32Array)[at]))
	return out


## Úsek ramene (kód jako v _cells) nejblíž bodu local, -1 když u bodu řeka není.
func _segment_at(local: Vector2) -> int:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var list: Variant = _cells.get(Vector2i(floori(local.x / tile), floori(local.y / tile)))
	if list == null:
		return -1
	var best := INF
	var found := -1
	for code: int in list:
		var line_points: PackedVector2Array = lines[code / LINE_STRIDE]["points"]
		var at := code % LINE_STRIDE
		var d := local.distance_squared_to(Geometry2D.get_closest_point_to_segment(local, line_points[at], line_points[at + 1]))
		if d < best:
			best = d
			found = code
	return found


## Leží local blíž než share šířky ramene a margin od osy? with_bank přidá svah břehu.
func _reach_at(local: Vector2, margin: float, share: float, with_bank := false) -> bool:
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
		var width := lerpf(line_widths[at], line_widths[at + 1], t)
		var half := width * 0.5 * share + margin
		if with_bank:
			half += bank_width(width)
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


## Mřížka pro A*: cena dlaždice s vlněním, neprůchodné skály, místo pro vesnici a všechna voda.
func _make_grid(water: int, reserve: Vector3) -> AStarGrid2D:
	var size := _size
	var tile := float(TerrainCatalog.TILE_SIZE)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, size, size)
	grid.cell_size = Vector2(tile, tile)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 7.0
	for y in size:
		for x in size:
			var at := Vector2i(x, y)
			if _map.terrain[y * size + x] == water:
				grid.set_point_solid(at)
				continue
			if reserve.z > 0.0 and _center(at).distance_to(Vector2(reserve.x, reserve.y)) < reserve.z:
				grid.set_point_solid(at)
				continue
			var weight := 1.0 + MEANDER * (noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5)
			if _edge_distance(at) < EDGE_TILES:
				weight += EDGE_WEIGHT
			grid.set_point_weight_scale(at, weight)
	if _rocks != null:
		_rocks.block_cells(grid, tile * 0.6, 0.0)
	return grid


## Volné dlaždice u jezera -> dlaždice jezera vedle. Odtud řeka vteče do vody.
func _shore_of(lake: PackedVector2Array) -> Dictionary:
	var shore := {}
	for spot in lake:
		var cell := Vector2i(spot)
		for side in SIDES:
			var land := cell + side
			if _grid.is_in_boundsv(land) and not _grid.is_point_solid(land) and not shore.has(land):
				shore[land] = cell
	return shore


## Trasa od from do jezera: k nejbližší dlaždici břehu, která není u jiného ústí, a do vody.
## Prázdná, když nejde.
func _to_lake(from: Vector2i) -> Array[Vector2i]:
	var best := INF
	var target := Vector2i(-1, -1)
	for cell: Vector2i in _shore:
		var d := Vector2(from).distance_squared_to(Vector2(cell))
		if d >= best:
			continue
		var crowded := false
		for mouth in _mouths:
			if Vector2(mouth).distance_to(Vector2(cell)) < MOUTH_GAP:
				crowded = true
				break
		if not crowded:
			best = d
			target = cell
	if target.x < 0:
		return []
	var path := _grid.get_id_path(from, target)
	if path.is_empty():
		return []
	path.append(_shore[target])
	return path


## Řeka do jezera: přes kraj od souseda, nebo od pramene ve čtverci. Pak její přítoky.
func _add_river(open: int) -> void:
	if open != 0 and _rng.randf() < EDGE_CHANCE:
		for start in _edge_starts(open, 8):
			var path := _straight(start.x, start.y)
			if path.is_empty() or _distance(_lake, path[0]) < SPRING_NEAR:
				continue
			var rest := _to_lake(path[path.size() - 1])
			if rest.is_empty():
				continue
			path.append_array(rest.slice(1))
			if _crosses(path, 0):
				continue
			var width := _rng.randf_range(EDGE_WIDTH.x, EDGE_WIDTH.y)
			var line := _shape(path, width, WIDTH_MOUTH, "mouth", _edge_point(start.x, start.y, _size))
			exits.append({"side": start.x, "at": start.y, "width": width})
			_keep(line, path, true)
			_add_branches(lines.size() - 1, path, open)
			return
	for spring in _springs():
		var kind := _spring_kind(spring)
		if _crowded_spring(spring) or (_rocks != null and not _rocks.spring_room(kind, _center(spring))):
			continue
		var path := _to_lake(spring)
		if path.size() < 8 or _crosses(path, 0):
			continue
		var line := _shape(path, WIDTH_SPRING, WIDTH_MOUTH, "mouth")
		line["spring"] = kind
		_keep(line, path, true)
		_add_branches(lines.size() - 1, path, open)
		return


## Pokračování řeky od souseda: od pramene ve čtverci k vtoku na straně side, poslední
## úsek je straight (_straight, v _taken zabraný předem). Přítoky má jen ze čtverce, dál přes
## kraj řeka nevede.
func _add_inlet(side: int, at: int, width: float, straight: Array[Vector2i]) -> void:
	for cell in straight:
		_taken.erase(cell)
	var inner := straight[straight.size() - 1]
	var tries: Array[Vector2i] = []
	for _try in 60:
		if tries.size() >= 8:
			break
		var cell := Vector2i(_rng.randi_range(0, _size - 1), _rng.randi_range(0, _size - 1))
		var far := Vector2(cell).distance_to(Vector2(inner))
		if far < INLET_SPRING.x or far > INLET_SPRING.y or _edge_distance(cell) < EDGE_TILES + 3:
			continue
		if not _grid.is_point_solid(cell):
			tries.append(cell)
	var near := inner - SIDES[side] * (INLET_NEAR - EDGE_STRAIGHT + 1)
	tries.append(near)
	for spring in tries:
		if not _grid.is_in_boundsv(spring) or _grid.is_point_solid(spring):
			continue
		var kind := _spring_kind(spring)
		var path: Array[Vector2i] = []
		if spring == near:
			# Nouzově rovně. Když se nevejde prameniště, rameno se jen objeví (START_FADE).
			path = Geometry2D.bresenham_line(spring, inner)
		else:
			if _crowded_spring(spring) or (_rocks != null and not _rocks.spring_room(kind, _center(spring))):
				continue
			path = _grid.get_id_path(spring, inner)
			if path.size() < 2 or _crosses(path, 0):
				continue
		for i in range(straight.size() - 2, -1, -1):
			path.append(straight[i])
		var line := _shape(path, WIDTH_SPRING, width, "edge", Vector2.INF, _edge_point(side, at, _size))
		line["spring"] = kind
		_keep(line, path, true)
		if width >= EDGE_WIDTH.x:
			_add_branches(lines.size() - 1, path, 0)
		return


## Uloží rameno a jeho trasu. Dlaždice trasy a okolí jsou pro další trasy drahé, pod
## prameništěm taky.
func _keep(line: Dictionary, path: Array[Vector2i], main: bool) -> void:
	line["main"] = main
	lines.append(line)
	for cell in path:
		_taken[cell] = true
	for cell in path:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var near := cell + Vector2i(dx, dy)
				if _grid.is_in_boundsv(near) and not _grid.is_point_solid(near):
					_grid.set_point_weight_scale(near, MAIN_WEIGHT)
	if bool(line["mouth"]):
		_mouths.append(path[path.size() - 1])
	var spring := str(line["spring"])
	if spring != "":
		var pos: Vector2 = (line["points"] as PackedVector2Array)[0]
		_spring_spots.append(pos)
		if _rocks != null:
			var reach := _rocks.spring_reach(spring)
			_spring_rocks.append(Vector3(pos.x, pos.y, reach))
			_avoid_spring(_grid, pos, reach)


## Kandidáti na pramen řeky, nejlepší první: náhodná volná místa v pásu u kraje, daleko od
## vody, potom i blíž. Bod je volná dlaždice mřížky. Jestli se vejde prameniště, hlídá volající.
func _springs() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for far in [SPRING_FAR, SPRING_NEAR]:
		var found := 0
		for _try in 80:
			if found >= 8:
				break
			var cell := Vector2i(_rng.randi_range(0, _size - 1), _rng.randi_range(0, _size - 1))
			if _in_band(cell) and not _grid.is_point_solid(cell) and _distance(_lake, cell) >= far:
				out.append(cell)
				found += 1
	return out


## Je jiný pramen blíž než SPRING_GAP dlaždic?
func _crowded_spring(cell: Vector2i) -> bool:
	var pos := _center(cell)
	for other in _spring_spots:
		if other.distance_to(pos) < SPRING_GAP * float(TerrainCatalog.TILE_SIZE):
			return true
	return false


## Prameniště pro pramen na dlaždici cell: náhodné ze seznamu springs jejího povrchu.
func _spring_kind(cell: Vector2i) -> String:
	var info := _map.info_of(_map.terrain[cell.y * _map.size + cell.x])
	var list: Array = info.get("springs", [])
	if list.is_empty():
		return SPRING_DEFAULT
	return str(list[_rng.randi_range(0, list.size() - 1)])


static func _center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * float(TerrainCatalog.TILE_SIZE)


## Možné vtoky na stranách open (bity jako v plan): Vector2i(strana, dlaždice podél kraje),
## nejvýš count, každý dost daleko od rohu a od jiného vtoku. Jestli z něj vede rovný úsek,
## hlídá volající (_straight).
func _edge_starts(open: int, count: int) -> Array[Vector2i]:
	var sides := PackedInt32Array()
	for side in SIDES.size():
		if open & (1 << side):
			sides.append(side)
	var out: Array[Vector2i] = []
	for _try in count * 3:
		if out.size() >= count:
			break
		var side := sides[_rng.randi_range(0, sides.size() - 1)]
		var at := _rng.randi_range(EDGE_MARGIN, _size - 1 - EDGE_MARGIN)
		var cell := Vector2(_edge_cell(side, at, _size))
		var crowded := false
		for exit in exits:
			if cell.distance_to(Vector2(_edge_cell(int(exit["side"]), int(exit["at"]), _size))) < EDGE_GAP:
				crowded = true
				break
		if not crowded:
			out.append(Vector2i(side, at))
	return out


## EDGE_STRAIGHT dlaždic od kraje side na dlaždici at rovně dovnitř, první na kraji.
## Prázdné, když je některá neprůchodná nebo u jiného ramene.
func _straight(side: int, at: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cell := _edge_cell(side, at, _size)
	for _i in EDGE_STRAIGHT:
		if not _grid.is_in_boundsv(cell) or _grid.is_point_solid(cell):
			return []
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if _taken.has(cell + Vector2i(dx, dy)):
					return []
		out.append(cell)
		cell -= SIDES[side]
	return out


## Dlaždice na kraji side, at dlaždic podél něj.
static func _edge_cell(side: int, at: int, size: int) -> Vector2i:
	var outward := SIDES[side]
	var x := at if outward.x == 0 else (0 if outward.x < 0 else size - 1)
	var y := at if outward.y == 0 else (0 if outward.y < 0 else size - 1)
	return Vector2i(x, y)


## Bod na kraji čtverce uprostřed dlaždice _edge_cell, v px.
static func _edge_point(side: int, at: int, size: int) -> Vector2:
	var half := float(TerrainCatalog.TILE_SIZE) * 0.5
	return _center(_edge_cell(side, at, size)) + Vector2(SIDES[side]) * half


## Přítoky řeky lines[index] s trasou path: soutok kdekoli po proudu, pramen ve čtverci
## proti proudu do strany, nebo vtok přes kraj na stranách open. Řeka a jiné přítoky jsou
## pro trasu drahé, ať nevede podél nich.
func _add_branches(index: int, path: Array[Vector2i], open: int) -> void:
	var count := _rng.rand_weighted(PackedFloat32Array(BRANCH_WEIGHTS))
	var last_join := path.size() - 1 - BRANCH_JOIN_END
	if count <= 0 or last_join < BRANCH_JOIN_FROM:
		return
	var river := lines[index]
	var water := _map.names.find("water")
	for _branch in count:
		var from_edge := open != 0 and _rng.randf() < BRANCH_EDGE_CHANCE
		for _try in 40:
			var join_at := _rng.randi_range(BRANCH_JOIN_FROM, last_join)
			var join := path[join_at]
			var route: Array[Vector2i] = []
			var kind := ""
			var edge := Vector2i(-1, -1)
			if from_edge:
				var starts := _edge_starts(open, 1)
				if starts.is_empty():
					continue
				edge = starts[0]
				route = _straight(edge.x, edge.y)
				if route.is_empty():
					continue
				var rest := _grid.get_id_path(route[route.size() - 1], join)
				if rest.size() < 4 or rest.size() > BRANCH_EDGE_CELLS:
					continue
				route.append_array(rest.slice(1))
			else:
				var upstream := Vector2(path[maxi(join_at - 3, 0)] - join)
				if upstream.length_squared() < 0.5:
					continue
				var angle := upstream.angle() + _rng.randf_range(-1.1, 1.1)
				var cell := join + Vector2i((Vector2.from_angle(angle) * _rng.randf_range(BRANCH_LENGTH.x, BRANCH_LENGTH.y)).round())
				if not _grid.is_in_boundsv(cell) or _grid.is_point_solid(cell) or _taken.has(cell):
					continue
				if _edge_distance(cell) < EDGE_TILES + 2 or _map.terrain[cell.y * _size + cell.x] == water:
					continue
				if _crowded_spring(cell):
					continue
				kind = _spring_kind(cell)
				if _rocks != null and not _rocks.spring_room(kind, _center(cell)):
					continue
				route = _grid.get_id_path(cell, join)
				if route.size() < 4:
					continue
			if _crosses(route, BRANCH_APPROACH):
				continue
			# Do soutoku musí přitékat po proudu, ne proti němu.
			var flow := Vector2(path[mini(join_at + 2, path.size() - 1)] - path[maxi(join_at - 2, 0)])
			var inflow := Vector2(route[route.size() - 1] - route[maxi(route.size() - 4, 0)])
			if inflow.dot(flow) < 0.0:
				continue
			var join_width := _width_near(river, _center(join)) * BRANCH_JOIN_WIDTH
			# Řeka má záhyby, soutok je na její skutečné ose, ne ve středu dlaždice.
			var into := _point_near(river, _center(join))
			var line: Dictionary
			if from_edge:
				var width := minf(_rng.randf_range(BRANCH_EDGE_WIDTH.x, BRANCH_EDGE_WIDTH.y), join_width * BRANCH_EDGE_SHARE)
				line = _shape(route, width, join_width, "join", _edge_point(edge.x, edge.y, _size), into)
				exits.append({"side": edge.x, "at": edge.y, "width": width})
			else:
				line = _shape(route, BRANCH_SPRING, join_width, "join", Vector2.INF, into)
				line["spring"] = kind
			_keep(line, route, false)
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


## Vede trasa přes jiné rameno, nebo těsně podél něj, jinde než na posledních approach
## dlaždicích (soutok přítoku)? Takový přítok by se k řece přimkl a stočil háčkem.
func _crosses(route: Array[Vector2i], approach: int) -> bool:
	for i in maxi(route.size() - approach, 0):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if _taken.has(route[i] + Vector2i(dx, dy)):
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


## Prameniště na začátek každého ramene od pramene, otočené po proudu. Když se nevejde,
## rameno se jen objeví (START_FADE).
func _place_springs() -> void:
	for line in lines:
		if str(line["spring"]) == "":
			continue
		var line_points: PackedVector2Array = line["points"]
		var ahead := line_points[mini(4, line_points.size() - 1)] - line_points[0]
		_rocks.place_spring(str(line["spring"]), line_points[0], ahead.angle(), _rng.randi())


## Dlaždic od nejbližšího kraje čtverce.
func _edge_distance(cell: Vector2i) -> int:
	return mini(mini(cell.x, cell.y), mini(_size - 1 - cell.x, _size - 1 - cell.y))


func _in_band(cell: Vector2i) -> bool:
	var edge := float(_edge_distance(cell))
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


## Z dlaždic cesty rameno: křivka s meandry a šířky od start do end. finish je konec ramene:
## "mouth" se protáhne do vody a k jezeru rozšíří do nálevky, "join" je soutok přítoku
## (end_at nahradí poslední bod trasy, bod na ose řeky), "edge" vede až na kraj čtverce
## v end_at. start_at je bod na kraji, odkud rameno přitéká od souseda.
func _shape(
	path: Array[Vector2i],
	start: float,
	end: float,
	finish: String,
	start_at := Vector2.INF,
	end_at := Vector2.INF,
) -> Dictionary:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var knots := PackedVector2Array()
	for index in path.size():
		if index % KNOT_STEP == 0 or index == path.size() - 1:
			knots.append(_center(path[index]))
	if start_at != Vector2.INF:
		knots.insert(0, start_at)
	if end_at != Vector2.INF:
		if finish == "join":
			knots[knots.size() - 1] = end_at
		else:
			knots.append(end_at)
	var mouth := finish == "mouth"
	if mouth and knots.size() >= 2:
		var last := knots[knots.size() - 1]
		var dir := (last - knots[knots.size() - 2]).normalized()
		knots.append(last + dir * MOUTH_TILES * tile)
	var line_points := _spline(knots)
	var calm := EDGE_CALM if start_at != Vector2.INF else 0.0
	if mouth:
		line_points = _meander(line_points, BEND_TILES, BEND_REACH, calm, _grid, _rng, lines)
	elif finish == "edge":
		line_points = _meander(line_points, BEND_TILES, 1.0, calm, _grid, _rng, lines)
	else:
		line_points = _meander(line_points, BRANCH_BEND_TILES, 1.0, calm, _grid, _rng, lines)
	var length := 0.0
	var along := PackedFloat32Array([0.0])
	for i in range(1, line_points.size()):
		length += line_points[i].distance_to(line_points[i - 1])
		along.append(length)
	# Proud na kraji čtverce je FLOW_BASE u obou sousedů.
	var flow := 0.0
	if start_at != Vector2.INF:
		flow = FLOW_BASE
	elif finish == "edge":
		flow = FLOW_BASE - length
	var line_widths := PackedFloat32Array()
	line_widths.resize(line_points.size())
	var flare_px := FLARE_TILES * tile
	for i in line_points.size():
		var t := along[i] / maxf(length, 1.0)
		var wobble := 1.0 + 0.08 * sin((flow + along[i]) / 90.0)
		var flare := 1.0
		if mouth:
			flare = 1.0 + FLARE * smoothstep(flare_px, 0.0, length - along[i])
		elif finish == "join":
			# Přítok se těsně před soutokem zúží, konec se schová ve vodě řeky.
			flare = lerpf(0.4, 1.0, smoothstep(0.0, end, length - along[i]))
		line_widths[i] = lerpf(start, end, pow(t, 0.85)) * wobble * flare
	return {
		"points": line_points,
		"widths": line_widths,
		"length": length,
		"spring": "",
		"mouth": mouth,
		"flow": flow,
	}


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


## Osa posunutá do stran vlnou se šumem. Záhyb je bend dlaždic u začátku a slábne do nuly
## na reach podílu délky. Prvních calm px záhyb není (rameno od kraje vede kolmo). Kde by
## bod vedl na neprůchodnou dlaždici nebo blíž než BEND_GAP k ramenům others, záhyb se
## zmenší a změna se rozleje do okolí, ať osa nemá zlom.
static func _meander(
	line_points: PackedVector2Array,
	bend: float,
	reach: float,
	calm: float,
	grid: AStarGrid2D,
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
		size *= smoothstep(calm, calm + BEND_START, along[i])
		offsets.append(size * (sin(phase) * 0.75 + noise.get_noise_1d(along[i]) * 0.5))
	# Kolik záhybu se vejde: pod posunutým bodem nesmí být neprůchodná dlaždice.
	var gap := BEND_GAP * tile
	var buckets := _buckets(others, gap)
	var fit := PackedFloat32Array()
	fit.resize(count)
	var total := along[count - 1]
	for i in count:
		fit[i] = 0.0
		var near_join := total - along[i] < BEND_JOIN * tile
		for share in BEND_SHRINK:
			var pos := line_points[i] + normals[i] * offsets[i] * share
			if not _bend_clear(pos, grid):
				continue
			if share > 0.0 and not near_join and _near_lines(pos, buckets, gap):
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


## Body os ramen lines po buňkách o straně gap: buňka -> body.
static func _buckets(lines_in: Array[Dictionary], gap: float) -> Dictionary:
	var out := {}
	for line in lines_in:
		for point: Vector2 in line["points"]:
			var key := Vector2i((point / gap).floor())
			var list: PackedVector2Array = out.get(key, PackedVector2Array())
			list.append(point)
			out[key] = list
	return out


## Leží pos blíž než gap k některému bodu z buckets (_buckets se stejným gap)?
static func _near_lines(pos: Vector2, buckets: Dictionary, gap: float) -> bool:
	var at := Vector2i((pos / gap).floor())
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var list: Variant = buckets.get(at + Vector2i(dx, dy))
			if list == null:
				continue
			for point: Vector2 in list:
				if pos.distance_squared_to(point) < gap * gap:
					return true
	return false


## Smí osa vést bodem pos? Ne přes neprůchodnou dlaždici.
static func _bend_clear(pos: Vector2, grid: AStarGrid2D) -> bool:
	var cell := Vector2i((pos / float(TerrainCatalog.TILE_SIZE)).floor())
	return grid != null and grid.is_in_boundsv(cell) and not grid.is_point_solid(cell)


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
			var half := maxf(line_widths[i], line_widths[i + 1]) * 0.5 + BANK_PAD + tile
			var low := line_points[i].min(line_points[i + 1]) - Vector2(half, half)
			var high := line_points[i].max(line_points[i + 1]) + Vector2(half, half)
			for cy in range(floori(low.y / tile), floori(high.y / tile) + 1):
				for cx in range(floori(low.x / tile), floori(high.x / tile) + 1):
					var key := Vector2i(cx, cy)
					var list: PackedInt32Array = _cells.get(key, PackedInt32Array())
					list.append(line_index * LINE_STRIDE + i)
					_cells[key] = list


## Mosty tam, kde řeka překročí cestu: podél cesty přes řeku, dlouhé jako řeka napříč cestou
## a kus navíc. Volá se po town.plan, před relocate.
func place_bridges(town: Town) -> void:
	bridges.clear()
	if town == null:
		return
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
				var span := line_widths[middle] / maxf(across, BRIDGE_SKEW) + BRIDGE_OVERHANG
				bridges.append({"pos": line_points[middle], "turn": heading, "length": span})
			inside = on


# --- Scéna ---

## Síť řeky a mosty pod host. origin je levý horní roh čtverce ve světě. look je materiál
## vody jezer z katalogu terénu, řeka si z něj vezme barvy, texturu vody a vlny.
## bank: svah břehu podle terénu (TerrainCatalog.bank_look). painted: rohy a varianty dlaždic čtverce
## (MapGenerator.corner_data), z nich shader pozná terén pod břehem.
func spawn(host: Node2D, origin: Vector2, look: ShaderMaterial = null, bank := {}, painted := {}) -> void:
	if not exists():
		return
	var shader := load(SHADER) as Shader
	var shared := {}
	if look != null:
		for uniform in shader.get_shader_uniform_list():
			var value: Variant = look.get_shader_parameter(uniform["name"])
			if value != null:
				shared[uniform["name"]] = value
	var mesh := _mesh()
	var mask := ImageTexture.create_from_image(_water_mask) if _water_mask != null else null
	var ground := {}
	if painted.has("corners") and painted.has("variants"):
		ground["ground_on"] = 1.0
		ground["map_size"] = float(_size)
		ground["corner_map"] = ImageTexture.create_from_image(Image.create_from_data(_size, _size, false, Image.FORMAT_RGBA8, painted["corners"]))
		ground["variant_map"] = ImageTexture.create_from_image(Image.create_from_data(_size, _size, false, Image.FORMAT_R8, painted["variants"]))
	ground.merge(bank)
	# Nejdřív břehy všech ramen, potom voda všech ramen.
	for part in 2:
		var node := MeshInstance2D.new()
		node.mesh = mesh
		node.position = origin
		var material := ShaderMaterial.new()
		material.shader = shader
		for key: String in shared:
			material.set_shader_parameter(key, shared[key])
		material.set_shader_parameter("part", part)
		for key: String in ground:
			material.set_shader_parameter(key, ground[key])
		if mask != null:
			material.set_shader_parameter("water_mask", mask)
			material.set_shader_parameter("mask_size", float(_water_mask.get_width()))
			material.set_shader_parameter("mask_shift", _mask_shift)
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


## Pásy trojúhelníků všech ramen, řeky poslední, o svah širší než rameno. UV.x je proud v px
## (flow ramene plus vzdálenost od jeho začátku), UV.y vzdálenost od osy napříč v px (záporná
## na levé straně, + orthogonal směru). Barva vrcholu nese průhlednost konců (r: rameno se
## objeví u pramene, řeka se ztratí v ústí), šířku ramene v px (g, děleno WIDTH_MAX)
## a zakřivení (b: 0.5 rovně, 1 ohyb naplno ke středu na levé straně, 0 na pravé).
## CUSTOM0.xy je směr napříč, kterým UV.y roste (pro stín břehu ve shaderu), z a w kam pás
## sahá vlevo a vpravo v px (u zúžené vnitřní strany zákruty se břeh vejde dovnitř).
## Na vnitřní straně ostré zákruty je pás užší než poloměr zákruty, ať se síť nepřehne.
func _mesh() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var customs := PackedFloat32Array()
	# Řeky poslední: jejich voda v soutoku překryje konec přítoku.
	var order: Array[int] = []
	for main in [false, true]:
		for line_index in lines.size():
			if bool(lines[line_index]["main"]) == main:
				order.append(line_index)
	for line_index in order:
		var line := lines[line_index]
		var line_points: PackedVector2Array = line["points"]
		var line_widths: PackedFloat32Array = line["widths"]
		var length := float(line["length"])
		var flow := float(line["flow"])
		var from_spring := str(line["spring"]) != ""
		var mouth := bool(line["mouth"])
		var along := 0.0
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var dist := PackedFloat32Array()
		var fade := PackedFloat32Array()
		var bends := _curvature(line_points, BEND_SPAN, 2)
		var tight := _curvature(line_points, 1, 0)
		var half_left := PackedFloat32Array()
		var half_right := PackedFloat32Array()
		var normals := PackedVector2Array()
		for i in line_points.size():
			var prev := line_points[maxi(i - 1, 0)]
			var next := line_points[mini(i + 1, line_points.size() - 1)]
			var normal := (next - prev).normalized().orthogonal()
			normals.append(normal)
			var half := line_widths[i] * 0.5 + BANK_PAD * BANK_REACH
			var bend := maxf(absf(tight[i]), absf(bends[i]))
			var room := maxf(FOLD_ROOM / maxf(bend, 0.0001), line_widths[i] * 0.5 + 4.0)
			# Kladné zakřivení: střed zákruty je vlevo (+ normal).
			var inside_left := tight[i] + bends[i] > 0.0
			half_left.append(minf(half, room) if inside_left else half)
			half_right.append(half if inside_left else minf(half, room))
			left.append(line_points[i] + normal * half_left[i])
			right.append(line_points[i] - normal * half_right[i])
			if i > 0:
				along += line_points[i].distance_to(line_points[i - 1])
			dist.append(along)
			var alpha := 1.0
			if from_spring:
				alpha *= smoothstep(0.0, START_FADE, along)
			if mouth:
				alpha *= smoothstep(0.0, END_FADE, length - along)
			fade.append(alpha)
		for i in line_points.size() - 1:
			var quad := [left[i], right[i], right[i + 1], left[i], right[i + 1], left[i + 1]]
			var quad_uv := [
				Vector2(flow + dist[i], -half_left[i]), Vector2(flow + dist[i], half_right[i]),
				Vector2(flow + dist[i + 1], half_right[i + 1]), Vector2(flow + dist[i], -half_left[i]),
				Vector2(flow + dist[i + 1], half_right[i + 1]), Vector2(flow + dist[i + 1], -half_left[i + 1]),
			]
			var ends := [i, i, i + 1, i, i + 1, i + 1]
			for k in 6:
				vertices.append(quad[k])
				uvs.append(quad_uv[k])
				var at: int = ends[k]
				var bend := 0.5 + 0.5 * clampf(bends[at] / BEND_FULL, -1.0, 1.0)
				colors.append(Color(fade[at], line_widths[at] / WIDTH_MAX, bend, 1.0))
				customs.append_array([-normals[at].x, -normals[at].y, half_left[at], half_right[at]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = customs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return mesh


## Zakřivení osy v každém bodě v 1/px, kladné, když je střed zákruty vlevo (+ orthogonal
## směru). Měří se odchylkou bodu od tětivy mezi sousedy span bodů daleko a vyhladí se
## průměrem přes smooth bodů na každou stranu.
static func _curvature(line_points: PackedVector2Array, span: int, smooth: int) -> PackedFloat32Array:
	var count := line_points.size()
	var raw := PackedFloat32Array()
	raw.resize(count)
	for i in count:
		var a := line_points[maxi(i - span, 0)]
		var b := line_points[mini(i + span, count - 1)]
		var chord := b - a
		var half := chord.length() * 0.5
		if half < 1.0:
			continue
		var normal := chord.normalized().orthogonal()
		# Bod vybočuje od tětivy na stranu -normal, střed zakřivení je pak na straně +normal.
		var bulge := (line_points[i] - (a + b) * 0.5).dot(normal)
		raw[i] = -2.0 * bulge / (half * half + bulge * bulge)
	if smooth <= 0:
		return raw
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var sum := 0.0
		var weight := 0.0
		for k in range(maxi(i - smooth, 0), mini(i + smooth, count - 1) + 1):
			sum += raw[k]
			weight += 1.0
		out[i] = sum / weight
	return out
