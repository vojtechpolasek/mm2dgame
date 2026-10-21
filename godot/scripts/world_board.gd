extends Node

## Hra jako otevřený svět ze čtverců SQUARE × SQUARE m, které navazují terénem. Level se hraje
## na čtverci s továrnou a vesnicí, ostatní čtverce jsou jen krajina (stromy a skály, bez vesnice,
## továrny a dolů). Kolem se dotváří, jak se hráči blíží ke kraji, ať za ním není prázdno.
## Nový čtverec převezme krajní řady hotových sousedů, takže svět závisí na pořadí, v jakém
## hráči čtverce otevřou. Ukládá se proto celá hotová mapa, ne jen semínko.
## Během levelu hráči čtverec levelu neopustí: kraj je zastaví FENCE_M metrů před sebou. Šipka
## ukazuje na továrnu, BLINK_M metrů od kraje bliká a od ALARM_M výrazně.
## Po splnění levelu vznikne další čtverec s továrnou na nejbližším místě, kde ještě nic není
## (při shodě náhodně), a šipka ukáže na něj. Hráči mezitím chodí kamkoli. Až se kdokoli
## přiblíží k nové továrně na LOCK_M metrů, kdo je v jejím čtverci, už z něj nevyjde.
## Tvorové jsou jen na čtverci hráče a na jeho sousedech, dál zmizí (_actors).
## Po patnáctém levelu hra končí.
## Čtverec s továrnou má tři sklady (Town.plan_stores), kam si hráči můžou kameny odložit.
## Volný pohyb (GameSession.free_roam): všechny čtverce jsou krajina bez továren, vesnic, dolů
## a příšer. Není level, čas, šipka ani ohrada, nic se neukládá. Čtverec dál než PARK_AT od
## čtverců hráčů se uvolní ze scény a zůstane jen jeho mapa (_parked). Po návratu se z ní
## postaví stejně, jako když se načítá uložená hra.
## Průlet v menu (start_flyover): stejná krajina, bez postavy. Kamera jede stálou rychlostí
## šikmo nahoru doprava a podle ní se otevírají další čtverce. Nic se neukládá.
## Hra se ukládá sama (SuitSaves): každých SAVE_EVERY sekund, po splnění levelu a při odchodu.
## Uloží se mapy všech hotových čtverců, kameny ve skladech všech čtverců a přesný stav levelu:
## postavy a co nesou, zásobníky továrny, vesničané a příšery jeho čtverce. Po načtení se hraje
## tam, kde hra skončila.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapGenerator := preload("res://scripts/map_generator.gd")
const MapData := preload("res://scripts/map_data.gd")
const Forest := preload("res://scripts/forest.gd")
const Rocks := preload("res://scripts/rocks.gd")
const Town := preload("res://scripts/town.gd")
const PropChunks := preload("res://scripts/prop_chunks.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const Person := preload("res://scripts/person.gd")
const Crystal := preload("res://scripts/crystal.gd")
const Hud := preload("res://scripts/hud.gd")
const Monsters := preload("res://scripts/monsters.gd")
const Villagers := preload("res://scripts/villagers.gd")
const Crowd := preload("res://scripts/crowd.gd")
const Party := preload("res://scripts/party.gd")
const Walker := preload("res://scripts/walker.gd")
const TerrainChunks := preload("res://scripts/terrain_chunks.gd")
const PondLabels := preload("res://scripts/pond_labels.gd")
const SuitGame := preload("res://scripts/suit_game.gd")
const SuitSaves := preload("res://scripts/suit_saves.gd")
const GroundDecor := preload("res://scripts/ground_decor.gd")
const SquareAir := preload("res://scripts/square_air.gd")
const River := preload("res://scripts/river.gd")

## Strana čtverce v metrech.
const SQUARE := 128
## Kolik terénů si nový čtverec vybere (MapGenerator.pick_terrains). Víc by mapu rozdrobilo.
const TERRAINS_PER_SQUARE := 3
## Terény, které úvodní čtverec nikdy nemá: bažina by hned na začátku zpomalila, voda
## překážela. Bez vody nemá úvodní čtverec ani řeku (River teče do jezera).
const START_BANNED: PackedStringArray = ["swamp", "water"]
## Od kraje, kde se na pozadí začne tvořit soused. Roh otevře i šikmý čtverec.
const APPROACH := 32.0
## Kolem továrny se voda vysuší, ať nestojí v jezeře. Kraj čtverce to nemění.
const CLEAR := 12.0
## Střed dolu neblíž ke kraji než tolik metrů. Ústí dolu zůstane na mapě.
const EDGE := 2.0
const WATER_CELL := 4
const WATER_HEAR := 14.0
const SPAWN_RING := 1.5
const FENCE_M := Walker.EDGE_M
const BLINK_M := 12.0
const ALARM_M := 7.0
const LOCK_M := 20.0
## Hláška po splnění levelu svítí tolik sekund.
const LEVEL_NOTICE := 7.0
## Vesnice čtverce s továrnou: T s domy jako v jednom levelu.
const TOWN_LAYOUT := "large"
const SAVE_EVERY := 60.0
## Příšery uložené hry si po načtení tolik sekund nikoho nevšímají.
const LOAD_CALM := 3.0
## Volný pohyb: čtverec aspoň tolik čtverců od každého hráče se uvolní. Nový čtverec vzniká
## nejvýš o jeden dál než hráč a navazuje na sousedy, ty jsou tedy pořád ve scéně.
const PARK_AT := 3
## Průlet menu: pixely za sekundu. Směr je šikmo nahoru doprava, nahoru je ve světě záporné y.
const FLY_SPEED := 52.0
const FLY_DIR := Vector2(0.70710678118, -0.70710678118)

var _host
var _camera: MapCamera
var _ground: TerrainChunks
var _status: Label
var _catalog: TerrainCatalog
var _crystal: Crystal
var _road: Node2D
## Řeky a mosty všech čtverců, nad cestou a pod porostem.
var _rivers: Node2D
## Průchozí porost všech čtverců, mezi řekou a objekty.
var _decor: Node2D
var _decor_kit := {}
var _props: Node2D
var _chunks: PropChunks
var _hud: Hud
var _party: Party
var _crowd: Crowd
var _squares := {}
## Čtverce, které čekají, až se dotvoří jejich sousedé. Navazují pak na jejich kraje.
var _waiting: Array[Vector2i] = []
var _where := {}
var _world_rng := RandomNumberGenerator.new()
var _opened := false
var _closing := false
## Strana čtverce v dlaždicích.
var _side := SQUARE
## Level, který se právě hraje, a jeho čtverec.
var _level := 1
var _active := Vector2i.ZERO
## Hráči jsou zavření ve čtverci levelu. Po splnění levelu až do příchodu k nové továrně ne.
var _locked := true
## Čtverce s továrnou: souřadnice -> level.
var _levels := {}
## Úkol každého čtverce s továrnou podle souřadnic.
var _games := {}
## Splněné čtverce: souřadnice -> kolik skafandrů leží na výstupku (z uložené hry, než
## čtverec vznikne).
var _done := {}
## Kde hráči začínají. U uložené hry čtverec, kde stál první hráč.
var _start := Vector2i.ZERO
## Celkový čas hry a čas právě hraného levelu v sekundách.
var _time := 0.0
var _level_time := 0.0
## Jak daleko od kraje drží ohrada postavu, podle postavy. Postava, která do čtverce levelu
## teprve vešla, má ohradu tam, kde stojí, a ta se rozšíří až na FENCE_M.
var _insets := {}
var _finished := false
var _save_left := SAVE_EVERY
## Hra už je uložená při zavírání okna.
var _closed_saved := false
## Stav uložené hry, který čeká, až vzniknou postavy a tvorové a továrna čtverce levelu.
var _pending := {}
## Kameny ve skladech uložené hry podle souřadnic čtverce, dokud čtverec nevznikne.
var _stores := {}
## Volný pohyb.
var _free := false
## Průlet v menu. Krajina jako volný pohyb, kamera jede sama a postava se nespawnuje.
var _flyover := false
## Uvolněné čtverce volného pohybu: souřadnice -> mapa (_record).
var _parked := {}


class Square:
	var coord := Vector2i.ZERO
	var origin := Vector2.ZERO
	var layout := ""
	var level := 1
	var task := -1
	var ready := false
	var awake := false
	var map
	var painted := {}
	var rocks
	var forest
	var town
	var monsters
	var villagers
	var walker
	var river
	var decor
	## Vzduch nad čtvercem (mlha, sníh, jed) a jeho maska terénu z vlákna.
	var air
	var air_mask: Image
	var rng: RandomNumberGenerator
	## Stav rng po nakreslení terénu. Odtud se sází továrna, skály a stromy, takže čtverec
	## jde z uložené mapy postavit znovu stejně.
	var plan_state := 0
	## Uložená mapa (_record), ze které se čtverec staví místo tvoření.
	var saved := {}
	## _record zabalený pro soubor uložení a jeho délka před zabalením. Mapa se po vytvoření
	## nemění, balí se jednou.
	var blob := PackedByteArray()
	var blob_size := 0
	var water_far := PackedInt32Array()
	var water_side := 0
	## Terén čtverce ve scéně.
	var ground


## Krajina pod menu. Volá se místo start().
func start_flyover(host) -> void:
	_flyover = true
	start(host)


func start(host) -> void:
	_host = host
	_camera = host.camera
	_ground = host.ground
	_status = host.status
	_status.text = "Tvoří se první čtverec…"
	_catalog = TerrainCatalog.new()
	_catalog.load_assets()
	if _catalog.names.is_empty():
		_status.text = "Chybí terén."
		push_error("Ve složce terénu nejsou žádné povrchy.")
		return
	_crystal = Crystal.new()
	if not _crystal.load_catalog():
		push_error("Chybí materiály krystalu.")
	_free = _flyover or GameSession.free_roam
	_world_rng.randomize()
	_camera.position = Vector2(_span(), _span()) * 0.5
	_camera.roam()
	_road = Node2D.new()
	_road.name = "Road"
	_host.add_child(_road)
	_host.move_child(_road, _ground.get_index() + 1)
	_rivers = Node2D.new()
	_rivers.name = "Rivers"
	_host.add_child(_rivers)
	_host.move_child(_rivers, _road.get_index() + 1)
	_decor = Node2D.new()
	_decor.name = "Decor"
	_host.add_child(_decor)
	_host.move_child(_decor, _rivers.get_index() + 1)
	_decor_kit = GroundDecor.load_kit(_catalog.names, _catalog.surfaces)
	_props = Node2D.new()
	_props.name = "Props"
	_props.y_sort_enabled = true
	_host.add_child(_props)
	_host.move_child(_props, _decor.get_index() + 1)
	_chunks = PropChunks.new()
	_chunks.name = "PropChunks"
	_chunks.setup(_camera)
	_host.add_child(_chunks)
	_begin()


func _begin() -> void:
	if _free:
		_enqueue(Vector2i.ZERO)
		return
	if GameSession.suit_resume.is_empty():
		_levels[Vector2i.ZERO] = 1
		_enqueue(Vector2i.ZERO)
		return
	_load(GameSession.suit_resume)


func tick(delta: float) -> void:
	if _closing:
		return
	_poll()
	_dispatch()
	if not _opened:
		return
	if _flyover:
		_drift(delta)
		_consider(_camera.position)
		_park_far()
		_sound(delta)
		return
	for person in _host._persons:
		_consider(person.position)
	_follow()
	_actors()
	if _free:
		_sound(delta)
		_park_far()
		return
	_show_task()
	_sound(delta)
	if _finished:
		return
	_time += delta
	_level_time += delta
	_hud.set_time(_time)
	_check_lock()
	_update_fence()
	_save_left -= delta
	if _save_left <= 0.0:
		_save()


func shutdown() -> void:
	_closing = true
	for key in _squares.keys():
		var sq: Square = _squares[key]
		if sq.task >= 0:
			WorkerThreadPool.wait_for_task_completion(sq.task)
			sq.task = -1
	if not _closed_saved:
		_save()


func is_dry(pos: Vector2) -> bool:
	var sq := _ready_at(pos)
	if sq == null:
		return false
	return sq.walker.dry(pos)


## Násobek rychlosti od řeky v bodě světa: ve vodě řeky zpomalí, na mostě ne.
func river_pace(pos: Vector2) -> float:
	var sq := _ready_at(pos)
	if sq == null:
		return 1.0
	return sq.walker.river_pace(pos)


func surface_at(pos: Vector2) -> String:
	var sq := _ready_at(pos)
	if sq == null:
		return ""
	return sq.walker.surface(pos)


func move_body(pos: Vector2, body: float, clearance: float) -> Vector2:
	var around: Array[Square] = []
	var coord := _coord(pos)
	for y in range(-1, 2):
		for x in range(-1, 2):
			var sq := _square(coord + Vector2i(x, y))
			if sq != null and sq.ready:
				around.append(sq)
	for _pass in 2:
		for sq in around:
			pos = sq.rocks.avoid(pos, body, clearance)
			pos = sq.forest.avoid(pos, body, clearance)
			pos = sq.town.avoid(pos, body)
	return pos


func _poll() -> void:
	for key in _squares.keys():
		var sq: Square = _squares[key]
		if sq.task < 0 or not WorkerThreadPool.is_task_completed(sq.task):
			continue
		WorkerThreadPool.wait_for_task_completion(sq.task)
		sq.task = -1
		if not _closing:
			_finish(sq)


## Nový čtverec. Se saved se postaví z uložené mapy, jinak se vytvoří a naváže na sousedy.
func _enqueue(coord: Vector2i, saved: Dictionary = {}) -> void:
	if _closing or _squares.has(coord):
		return
	if saved.is_empty() and _parked.has(coord):
		saved = _parked[coord]
		_parked.erase(coord)
	var sq := Square.new()
	sq.coord = coord
	sq.rng = RandomNumberGenerator.new()
	if saved.is_empty():
		sq.rng.seed = _world_rng.randi()
		_plan_square(sq)
	else:
		sq.layout = str(saved["layout"])
		sq.level = int(saved["level"])
		sq.plan_state = int(saved["plan_state"])
		sq.saved = saved
	sq.rocks = Rocks.new()
	sq.forest = Forest.new()
	sq.town = Town.new()
	sq.monsters = Monsters.new()
	sq.villagers = Villagers.new()
	sq.rocks.name = "Rocks"
	sq.forest.name = "Trees"
	sq.town.name = "Town"
	sq.rocks.load_catalog(_catalog.names, _catalog.surfaces)
	sq.forest.load_catalog(_catalog.names, _catalog.surfaces)
	if sq.town.load_assets():
		sq.rocks.town = sq.town
		sq.forest.town = sq.town
	sq.rocks.bind_crystal(_crystal)
	sq.rocks.edge_guard = EDGE
	_configure(sq)
	_squares[coord] = sq
	_waiting.append(coord)
	_dispatch()


func _plan_square(sq: Square) -> void:
	sq.level = int(_levels.get(sq.coord, 0))
	sq.layout = TOWN_LAYOUT if sq.level > 0 else "empty"


## Čtverec s továrnou: doly materiálů ze zásobníků v úzkých pásech kolem továrny a zásobníky
## podle levelu. Ostatní čtverce nemají doly ani továrnu.
func _configure(sq: Square) -> void:
	if sq.level <= 0:
		sq.rocks.set_available(0)
		return
	sq.town.stores = true
	sq.rocks.set_available(GameSession.material_window(sq.level))
	var order: PackedInt32Array = sq.rocks.by_points()
	var plan: Array = []
	for pair: Array in GameSession.suit_lanes(sq.level):
		plan.append([order[mini(int(pair[0]), order.size() - 1)], int(pair[1])])
	# Každý materiál ze zásobníků má jeden důl, materiál, který továrna nechce, žádný.
	var used := GameSession.suit_orders(sq.level)
	var mines := PackedInt32Array()
	mines.resize(mini(GameSession.material_window(sq.level), order.size()))
	var recipe := PackedInt32Array()
	for at in used:
		if at >= mines.size():
			continue
		mines[at] = 1
		if recipe.size() < GameSession.SUIT_RECIPE:
			recipe.append(order[at])
	sq.rocks.mine_plan = mines
	sq.rocks.band_max = GameSession.SUIT_BAND_M
	sq.town.suit_plan = plan
	sq.town.suit_recipe = recipe


## Čtverec se začne tvořit, až žádný z osmi sousedů není rozpracovaný. Hotové sousedy
## pak zná celé a naváže na ně. Dva sousední čtverce se tak nikdy netvoří naráz.
func _dispatch() -> void:
	if _closing:
		return
	var i := 0
	while i < _waiting.size():
		var coord := _waiting[i]
		# Uložený čtverec na sousedy nečeká, mapu už má.
		if _square(coord).saved.is_empty() and _neighbor_busy(coord):
			i += 1
			continue
		_waiting.remove_at(i)
		var sq := _square(coord)
		if not sq.saved.is_empty():
			sq.task = WorkerThreadPool.add_task(_rebuild.bind(sq), true, "Čtverec")
			continue
		var ring := _ring_of(coord)
		var fixed := _fixed_vertices(coord)
		sq.task = WorkerThreadPool.add_task(_generate.bind(sq, ring, fixed), true, "Čtverec")


func _neighbor_busy(coord: Vector2i) -> bool:
	for y in range(-1, 2):
		for x in range(-1, 2):
			var other := _square(coord + Vector2i(x, y))
			if other != null and other != _square(coord) and other.task >= 0:
				return true
	return false


## Soused, jehož mapa je hotová. Rozpracovaný nebo čekající čtverec se nepočítá.
func _built(coord: Vector2i) -> Square:
	var sq := _square(coord)
	if sq == null or sq.task >= 0 or sq.map == null:
		return null
	return sq


## Krajní řady hotových sousedů kolem čtverce, viz MapGenerator.ring_index.
func _ring_of(coord: Vector2i) -> PackedByteArray:
	var ring := MapGenerator.empty_ring(_side)
	var last := _side - 1
	for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var other := _built(coord + side)
		if other == null:
			continue
		for i in _side:
			# Dlaždice souseda u společného kraje a kam patří v okolí tohoto čtverce.
			var from := Vector2i(last if side.x < 0 else 0, i) if side.x != 0 else Vector2i(i, last if side.y < 0 else 0)
			var to := Vector2i(-1 if side.x < 0 else _side, i) if side.x != 0 else Vector2i(i, -1 if side.y < 0 else _side)
			ring[MapGenerator.ring_index(_side, to.x, to.y)] = other.map.terrain[from.y * _side + from.x]
	for corner: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var other := _built(coord + corner)
		if other == null:
			continue
		var from := Vector2i(last if corner.x < 0 else 0, last if corner.y < 0 else 0)
		var to := Vector2i(-1 if corner.x < 0 else _side, -1 if corner.y < 0 else _side)
		ring[MapGenerator.ring_index(_side, to.x, to.y)] = other.map.terrain[from.y * _side + from.x]
	return ring


## Vrcholy terénu na krajích, které už nakreslil soused. Převezmou se beze změny, jinak by
## každá strana kreslila přechod jinak a na kraji by byl vidět řez.
func _fixed_vertices(coord: Vector2i) -> PackedByteArray:
	var span := _side + 1
	var fixed := PackedByteArray()
	fixed.resize(span * span)
	fixed.fill(MapData.UNCLAIMED_TERRAIN)
	for y in range(-1, 2):
		for x in range(-1, 2):
			var other := _built(coord + Vector2i(x, y))
			if other == null or (x == 0 and y == 0):
				continue
			var theirs: PackedByteArray = other.painted["vertex"]
			# Společné vrcholy: tady sloupec 0 je u souseda poslední sloupec a naopak.
			for vy in range(maxi(y * _side, 0), mini(y * _side + _side, _side) + 1):
				for vx in range(maxi(x * _side, 0), mini(x * _side + _side, _side) + 1):
					fixed[vy * span + vx] = theirs[(vy - y * _side) * span + (vx - x * _side)]
	return fixed


func _generate(sq: Square, ring: PackedByteArray, fixed: PackedByteArray) -> void:
	var banned := START_BANNED if sq.coord == Vector2i.ZERO else PackedStringArray()
	var pool := MapGenerator.pick_terrains(_catalog.names, _catalog.surfaces, sq.rng, TERRAINS_PER_SQUARE, ring, banned)
	var map := MapGenerator.grow(_side, _catalog.names, sq.rng, _catalog.max_distance, _catalog.max_share, ring, pool)
	map.surfaces = _catalog.surfaces
	if sq.layout != "empty":
		MapGenerator.clear_disk(map, CLEAR)
	sq.painted = MapGenerator.corner_data(map, sq.rng, _catalog.variant_count, fixed)
	sq.plan_state = sq.rng.state
	_furnish(sq, map)


## Čtverec z uložené mapy. Rohy dlaždic se dopočítají z vrcholů, objekty se sází od
## uloženého stavu rng, takže stojí tam, kde stály.
func _rebuild(sq: Square) -> void:
	var map := MapData.new()
	map.size = _side
	map.names = _catalog.names
	map.surfaces = _catalog.surfaces
	map.terrain = sq.saved["terrain"]
	var halo: Array = sq.saved["halo"]
	map.halo_w = halo[0]
	map.halo_e = halo[1]
	map.halo_n = halo[2]
	map.halo_s = halo[3]
	var vertex: PackedByteArray = sq.saved["vertex"]
	var span := _side + 1
	var corners := PackedByteArray()
	corners.resize(_side * _side * 4)
	for y in _side:
		for x in _side:
			var cell := y * _side + x
			var top := y * span + x
			corners[cell * 4] = vertex[top]
			corners[cell * 4 + 1] = vertex[top + 1]
			corners[cell * 4 + 2] = vertex[top + span]
			corners[cell * 4 + 3] = vertex[top + span + 1]
	sq.painted = {"corners": corners, "variants": sq.saved["variants"], "vertex": vertex}
	sq.rng.state = sq.plan_state
	_furnish(sq, map)


## Mapa čtverce k uložení. Stačí terén, vrcholy, varianty dlaždic a okolí od sousedů.
func _record(sq: Square) -> Dictionary:
	return {
		"layout": sq.layout,
		"level": sq.level,
		"plan_state": sq.plan_state,
		"terrain": sq.map.terrain,
		"vertex": sq.painted["vertex"],
		"variants": sq.painted["variants"],
		"halo": [sq.map.halo_w, sq.map.halo_e, sq.map.halo_n, sq.map.halo_s],
	}


func _furnish(sq: Square, map: MapData) -> void:
	sq.town.plan(map, sq.rng, sq.layout)
	sq.rocks.plant(map, sq.rng)
	# Řeka po skalách (pramení u nich) a před stromy, ty ji obejdou. Vlastní náhoda, ať
	# nemění, co se losuje po ní.
	sq.river = River.new()
	sq.river.plan(map, sq.rocks, sq.town, hash(sq.plan_state) + 1)
	sq.forest.river = sq.river
	sq.forest.plant(map, sq.rng, sq.rocks)
	# Porost má vlastní náhodu, ať nemění, co se losuje po něm.
	sq.decor = GroundDecor.new()
	sq.decor.plant(_decor_kit, map, sq.painted["corners"], sq.town, _catalog.water_index, sq.coord * _side, hash(sq.plan_state), sq.river)
	sq.air_mask = SquareAir.mask(map)
	sq.walker = Walker.new(sq.rocks, sq.forest, sq.town, map)
	sq.walker.river = sq.river
	sq.monsters.prepare(sq.rocks.pond_materials(), _crystal, sq.walker, sq.rocks, sq.forest)
	sq.villagers.prepare(sq.walker, sq.rocks, sq.forest)
	sq.rocks.prepare_bounds(Person.BODY)
	var water := _water_map(map)
	sq.water_side = int(water["side"])
	sq.water_far = water["far"]
	sq.map = map


func _finish(sq: Square) -> void:
	if sq.map == null or sq.walker == null:
		push_error("Čtverec %s se nepodařilo vytvořit." % sq.coord)
		return
	sq.origin = _origin_of(sq.coord)
	sq.rocks.relocate(sq.origin)
	sq.forest.relocate(sq.origin)
	sq.town.relocate(sq.origin)
	sq.river.relocate(sq.origin)
	sq.walker.set_space(sq.origin)
	sq.monsters.set_space(sq.origin)
	sq.villagers.set_space(sq.origin)
	add_child(sq.rocks)
	add_child(sq.forest)
	add_child(sq.town)
	add_child(sq.monsters)
	_show_terrain(sq)
	sq.town.spawn(_camera, _road, _props, _crystal)
	sq.rocks.spawn(_camera, _props, _chunks)
	sq.forest.spawn(_camera, _props, _chunks)
	sq.river.spawn(_rivers, sq.origin)
	sq.decor.spawn(_decor_kit, _decor, sq.origin)
	# Nad čtvercem levelu visí jed, dokud továrna level nesplní.
	sq.air = SquareAir.new()
	sq.air.name = "Air_%d_%d" % [sq.coord.x, sq.coord.y]
	_host.add_child(sq.air)
	sq.air.setup(sq.air_mask, _side, sq.origin, sq.level > 0 and not _done.has(sq.coord))
	sq.air_mask = null
	_chunks.refresh()
	_built_square(sq)
	sq.ready = true
	if not _opened and _opens_at(sq):
		_open_play(sq)
	elif _opened and sq.layout != "empty":
		_add_labels(sq)


func _built_square(sq: Square) -> void:
	if sq.level <= 0 or sq.town.suit_factory() == null:
		return
	if _stores.has(sq.coord):
		sq.town.restore_stores(_stores[sq.coord])
		_stores.erase(sq.coord)
	var game := SuitGame.new()
	game.name = "Suits_%d_%d" % [sq.coord.x, sq.coord.y]
	add_child(game)
	if not game.setup(sq.town):
		game.queue_free()
		return
	_games[sq.coord] = game
	game.factory().point_mines(sq.rocks)
	game.progressed.connect(_on_progress.bind(sq.coord))
	game.completed.connect(_on_completed.bind(sq.coord))
	if _done.has(sq.coord):
		game.factory().restore({"done": true, "suits": int(_done[sq.coord])})
		game.mark_done()
	elif sq.coord == _active and _pending.has("factory"):
		game.factory().restore(_pending["factory"])
		_pending.erase("factory")
	if sq.coord == _active and _hud != null:
		_hud.set_goal(_title(), game.target())


func _opens_at(sq: Square) -> bool:
	return sq.coord == _start


func _open_play(sq: Square) -> void:
	if _flyover:
		_open_flyover(sq)
		return
	_crowd = Crowd.new()
	_party = Party.new(_camera)
	_host._party = _party
	for i in maxi(GameSession.players.size(), 1):
		var person := Person.new()
		person.name = "Person%d" % (i + 1)
		_props.add_child(person)
		person.setup(sq.rocks, sq.forest, sq.town, _camera, sq.map, _crystal, i)
		person.walker.world_board = self
		person.walker.crowd = _crowd
		person.crowd_id = _crowd.join(person)
		person.party = _party
		person.use_square(sq.rocks, sq.town, sq.origin, _span())
		_host._persons.append(person)
		_party.members.append(person)
		_where[person] = sq.coord
	_place_persons(sq)
	_add_labels(sq)
	_hud = Hud.new()
	_hud.name = "Game"
	_host.get_node("Hint").add_child(_hud)
	_setup_hud(sq)
	_host._hud = _hud
	for person in _host._persons:
		person.held_changed.connect(_hud.set_held.bind(person.player_index))
		_dress(person)
	var music := RandomNumberGenerator.new()
	music.randomize()
	Sound.play_level_music(music)
	_status.visible = false
	_host._map_ready = true
	_opened = true
	sq.walker.crowd = _crowd
	_wake(sq)
	_party.frame()
	_show_task()


## Menu: žádná postava a žádné hlášení. Sousedé ve směru jízdy se začnou tvořit hned,
## ať kamera nedojede k prázdnému kraji.
func _open_flyover(sq: Square) -> void:
	_status.visible = false
	_host._map_ready = true
	_opened = true
	_enqueue(sq.coord + Vector2i.RIGHT)
	_enqueue(sq.coord + Vector2i.UP)
	_enqueue(sq.coord + Vector2i.UP + Vector2i.RIGHT)


func _drift(delta: float) -> void:
	_camera.position += FLY_DIR * FLY_SPEED * delta


## Uložená hra: postavy stojí, kde stály, a nesou, co nesly. Každá používá doly a továrnu
## čtverce, na kterém stojí.
func _place_persons(sq: Square) -> void:
	var saved: Array = _pending.get("persons", [])
	_pending.erase("persons")
	if saved.is_empty():
		_ring_persons()
		return
	for i in _host._persons.size():
		var person: Person = _host._persons[i]
		if i >= saved.size():
			person.position = person._free_spot(_host._persons[0].position)
			continue
		person.restore(saved[i])
		var coord := _coord(person.position)
		_where[person] = coord
		var here := _square(coord)
		if here != null and here.ready:
			person.use_square(here.rocks, here.town, here.origin, _span())


## Nová hra: první postava stojí u továrny, další v kruhu kolem ní.
func _ring_persons() -> void:
	var first: Vector2 = _host._persons[0].position
	var tile := float(TerrainCatalog.TILE_SIZE)
	for i in range(1, _host._persons.size()):
		var angle := TAU * float(i - 1) / float(maxi(_host._persons.size() - 1, 1))
		var person: Person = _host._persons[i]
		person.position = person._free_spot(first + Vector2.from_angle(angle) * SPAWN_RING * tile)


func _setup_hud(_sq: Square) -> void:
	if _free:
		_hud.setup(_crystal, GameSession.players)
		_hud.free_roam()
	else:
		var game: SuitGame = _games.get(_active)
		var target := game.target() if game != null else 1
		_hud.setup(_crystal, GameSession.players)
		_hud.set_goal(_title(), target)
		if game != null:
			_hud.set_progress(game.stored())
		_hud.set_time(_time)
	_hud.menu_pressed.connect(_host._to_menu)
	_hud.pause_requested.connect(_host._open_pause)
	_hud.pause_closed.connect(_host._close_pause)
	_hud.main_menu_pressed.connect(_host._to_main_menu)


## Dýchací přístroj, ukradený kámen zmizí. Co postava udělá, se hlásí vesničanům čtverce,
## na kterém stojí: kdo ji sleduje, jde za ní.
func _dress(person: Person) -> void:
	# Ve volném pohybu není jed, dýchací přístroj netřeba.
	person.wear_gear(not _free)
	person.used_store.connect(_on_used_store.bind(person))
	person.took_gem.connect(_on_took.bind(person))
	person.threw_gem.connect(_on_threw.bind(person))
	person.touched_factory.connect(_on_touched.bind(person))
	_hud.set_held(person.carried(), person.player_index)


func _show_terrain(sq: Square) -> void:
	var mats: Dictionary = _catalog.fork_map(sq.map.size, sq.painted["corners"], sq.painted["variants"])
	var chunks: TerrainChunks
	if sq.coord == Vector2i.ZERO:
		chunks = _ground
		sq.ground = chunks
	else:
		chunks = TerrainChunks.new()
		chunks.name = "Ground_%d_%d" % [sq.coord.x, sq.coord.y]
		chunks.position = sq.origin
		chunks.z_index = -1
		chunks.share_spare(_ground)
		_host.add_child(chunks)
		sq.ground = chunks
	var water := mats["water"] as ShaderMaterial
	water.set_shader_parameter("map_origin", sq.origin)
	chunks.setup(
		_catalog,
		sq.map.size,
		sq.painted["corners"],
		_camera,
		mats["bake"] as ShaderMaterial,
		water,
	)


func _add_labels(sq: Square) -> void:
	var spots: Array = sq.rocks.pond_spots()
	if spots.is_empty():
		return
	var labels := PondLabels.new()
	labels.name = "Ponds_%d_%d" % [sq.coord.x, sq.coord.y]
	_host.add_child(labels)
	labels.setup(spots, _crystal, _host._persons, _camera)


func _wake(sq: Square) -> void:
	if sq.awake or sq.layout == "empty":
		return
	sq.walker.crowd = _crowd
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	sq.monsters.spawn(sq.rocks.pond_materials(), _crystal, sq.walker, sq.rocks, sq.forest, _host._persons, _camera, _props, rng)
	rng.randomize()
	sq.villagers.spawn(sq.town, sq.rocks, _crystal, sq.walker, _host._persons, _camera, _props, sq.monsters, rng, _saved_villagers(sq))
	if not sq.villagers.members.is_empty() and sq.villagers.get_parent() == null:
		add_child(sq.villagers)
	sq.awake = true
	_woke(sq)


## Uložená hra: stejní vesničané čtverce levelu jako při uložení.
func _saved_villagers(sq: Square) -> Array:
	return _pending.get("villagers", []) if sq.coord == _active else []


func _woke(sq: Square) -> void:
	var game: SuitGame = _games.get(sq.coord)
	if game == null:
		return
	game.attach(sq.villagers, sq.monsters)
	if sq.coord != _active:
		return
	if _pending.has("villagers"):
		sq.villagers.restore(_pending["villagers"], _host._persons)
		_pending.erase("villagers")
	if _pending.has("monsters"):
		sq.monsters.restore(_pending["monsters"], LOAD_CALM)
		_pending.erase("monsters")
	if _pending.has("stored"):
		game.restore(int(_pending["stored"]))
		_pending.erase("stored")
		if _hud != null:
			_hud.set_progress(game.stored())


func _sleep(sq: Square) -> void:
	for monster in sq.monsters.members:
		_release(monster)
	sq.monsters.members.clear()
	for villager in sq.villagers.members:
		_release(villager)
	sq.villagers.members.clear()
	if sq.villagers.get_parent() != null:
		sq.villagers.get_parent().remove_child(sq.villagers)
	sq.awake = false
	var game: SuitGame = _games.get(sq.coord)
	if game != null:
		game.detach()


func _release(member: Node) -> void:
	if not is_instance_valid(member):
		return
	member.visible = false
	member.process_mode = Node.PROCESS_MODE_DISABLED
	member.queue_free()


func _actors() -> void:
	var near := {}
	for person in _host._persons:
		var coord: Vector2i = _where.get(person, _coord(person.position))
		for y in range(-1, 2):
			for x in range(-1, 2):
				near[coord + Vector2i(x, y)] = true
	for key in _squares:
		var sq: Square = _squares[key]
		if not sq.ready:
			continue
		var keep := bool(near.has(sq.coord)) and sq.layout != "empty"
		if keep and not sq.awake:
			_wake(sq)
		elif sq.awake and not keep:
			_sleep(sq)


func _follow() -> void:
	for person in _host._persons:
		var coord := _coord(person.position)
		var prev: Vector2i = _where.get(person, coord)
		if prev == coord:
			_where[person] = coord
			continue
		var sq := _square(coord)
		if sq == null or not sq.ready:
			continue
		person.leave_square()
		person.use_square(sq.rocks, sq.town, sq.origin, _span())
		_where[person] = coord


func _consider(pos: Vector2) -> void:
	var span := _span()
	var coord := _coord(pos)
	var local := pos - _origin_of(coord)
	var reach := APPROACH * float(TerrainCatalog.TILE_SIZE)
	var west := local.x <= reach
	var east := span - local.x <= reach
	var north := local.y <= reach
	var south := span - local.y <= reach
	if west:
		_enqueue(coord + Vector2i.LEFT)
	if east:
		_enqueue(coord + Vector2i.RIGHT)
	if north:
		_enqueue(coord + Vector2i.UP)
	if south:
		_enqueue(coord + Vector2i.DOWN)
	if west and north:
		_enqueue(coord + Vector2i(-1, -1))
	if west and south:
		_enqueue(coord + Vector2i(-1, 1))
	if east and north:
		_enqueue(coord + Vector2i(1, -1))
	if east and south:
		_enqueue(coord + Vector2i(1, 1))


## Šipka ukazuje na továrnu levelu. Než je její čtverec hotový, na jeho střed.
func _show_task() -> void:
	if _free or _hud == null or _host._persons.is_empty():
		return
	var sq := _square(_active)
	var aim := _origin_of(_active) + Vector2(_span(), _span()) * 0.5
	if sq != null and sq.ready and sq.town.center() != Vector2.INF:
		aim = sq.town.center()
	var to_screen := (_host.get_viewport() as Viewport).get_canvas_transform()
	_hud.point_factory(to_screen * _camera.get_screen_center_position(), to_screen * aim)
	_hud.set_edge_alarm(_alarm())


## Hraje hudba při honičce? Dokud kdokoli nese kámen: hráč nebo vesničan na probuzeném čtverci.
func _chase_music() -> bool:
	if Monsters.anyone_carrying(_host._persons, []):
		return true
	for key in _squares:
		var sq: Square = _squares[key]
		if sq.awake and not sq.monsters.carriers.is_empty():
			return true
	return false


func _sound(_delta: float) -> void:
	if _flyover:
		Sound.set_chase(false)
		Sound.set_water(_water_near(_camera.position))
		return
	Sound.set_chase(_chase_music())
	if _host._persons.is_empty():
		Sound.set_water(0.0)
		return
	var person: Person = _host._persons[0]
	Sound.set_water(_water_near(person.position))


## 0 až 1, jak blízko je voda v bodě světa. Dál než WATER_HEAR je 0 a míň.
func _water_near(pos: Vector2) -> float:
	var sq := _square(_coord(pos))
	if sq == null or sq.water_far.is_empty():
		return 0.0
	var tile := float(TerrainCatalog.TILE_SIZE)
	var local := pos - sq.origin
	var cx := clampi(floori(local.x / tile) / WATER_CELL, 0, sq.water_side - 1)
	var cy := clampi(floori(local.y / tile) / WATER_CELL, 0, sq.water_side - 1)
	var meters := float(sq.water_far[cy * sq.water_side + cx] * WATER_CELL)
	return 1.0 - meters / WATER_HEAR


## Volný pohyb: uvolní čtverce daleko od hráčů. Čtverec, vedle kterého se ještě něco tvoří,
## zůstane, nový soused z něj bere kraj. Čtverec (0, 0) má terén ve scéně hry, zůstane taky.
func _park_far() -> void:
	var homes: Array[Vector2i] = []
	if _host._persons.is_empty():
		homes.append(_coord(_camera.position))
	else:
		for person in _host._persons:
			homes.append(_coord(person.position))
	for key: Vector2i in _squares.keys():
		if key == Vector2i.ZERO:
			continue
		var sq: Square = _squares[key]
		if not sq.ready or sq.task >= 0:
			continue
		var far := true
		for home in homes:
			if maxi(absi(key.x - home.x), absi(key.y - home.y)) < PARK_AT:
				far = false
				break
		if far and not _near_unready(key):
			_park(sq)


func _near_unready(coord: Vector2i) -> bool:
	for y in range(-1, 2):
		for x in range(-1, 2):
			var other := _square(coord + Vector2i(x, y))
			if other != null and not other.ready:
				return true
	return false


## Uvolní čtverec ze scény. Zůstane jen jeho mapa, z ní se po návratu postaví stejně.
func _park(sq: Square) -> void:
	_parked[sq.coord] = sq.saved if not sq.saved.is_empty() else _record(sq)
	_squares.erase(sq.coord)
	_chunks.forget(sq.rocks)
	_chunks.forget(sq.forest)
	sq.rocks.despawn()
	sq.forest.despawn()
	sq.river.despawn()
	sq.decor.despawn()
	if sq.ground != null and sq.ground != _ground:
		sq.ground.detach()
		sq.ground.queue_free()
	if sq.air != null:
		sq.air.queue_free()
	for node: Node in [sq.rocks, sq.forest, sq.town, sq.monsters, sq.villagers]:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()


func _ready_at(pos: Vector2) -> Square:
	return _square(_coord(pos)) if _has_ready(_coord(pos)) else null


func _has_ready(coord: Vector2i) -> bool:
	var sq := _square(coord)
	return sq != null and sq.ready


func _square(coord: Vector2i) -> Square:
	return _squares.get(coord) as Square


func _coord(pos: Vector2) -> Vector2i:
	var span := _span()
	return Vector2i(floori(pos.x / span), floori(pos.y / span))


func _origin_of(coord: Vector2i) -> Vector2:
	return Vector2(coord) * _span()


func _span() -> float:
	return float(_side * TerrainCatalog.TILE_SIZE)


func _edge_meters(pos: Vector2) -> float:
	var span := _span()
	var local := pos - _origin_of(_coord(pos))
	var edge := minf(minf(local.x, local.y), minf(span - local.x, span - local.y))
	return edge / float(TerrainCatalog.TILE_SIZE)


func _water_map(map: MapData) -> Dictionary:
	var empty := {"side": 0, "far": PackedInt32Array()}
	var water := map.names.find("water")
	if water < 0:
		return empty
	var side := ceili(float(map.size) / float(WATER_CELL))
	var far := PackedInt32Array()
	far.resize(side * side)
	far.fill(-1)
	var queue := PackedInt32Array()
	for index in map.terrain.size():
		if map.terrain[index] != water:
			continue
		var cell := (index / map.size) / WATER_CELL * side + (index % map.size) / WATER_CELL
		if far[cell] < 0:
			far[cell] = 0
			queue.append(cell)
	if queue.is_empty():
		return empty
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var x := cell % side
		var y := cell / side
		for side_step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var nx := x + side_step.x
			var ny := y + side_step.y
			if nx < 0 or ny < 0 or nx >= side or ny >= side:
				continue
			var next := ny * side + nx
			if far[next] < 0:
				far[next] = far[cell] + 1
				queue.append(next)
	return {"side": side, "far": far}


## Pokračování uložené hry. Čtverce se staví z uložených map, nejdřív ty nejblíž hráčům.
func _load(data: Dictionary) -> void:
	_status.text = "Načítá se uložená hra…"
	_level = int(data.get("level", 1))
	_time = float(data.get("time", 0.0))
	_level_time = float(data.get("level_time", 0.0))
	_active = data.get("active", Vector2i.ZERO)
	_locked = bool(data.get("locked", true))
	_levels = data.get("levels", {Vector2i.ZERO: 1})
	_done = data.get("done", {})
	_world_rng.state = int(data.get("rng", _world_rng.state))
	_pending = data.get("state", {})
	_stores = data.get("stores", {})
	var persons: Array = _pending.get("persons", [])
	var first: Vector2 = _origin_of(_active) + Vector2(_span(), _span()) * 0.5
	if not persons.is_empty():
		first = (persons[0] as Dictionary).get("pos", first)
	_start = _coord(first)
	_camera.position = first
	var squares: Array = data.get("squares", [])
	squares.sort_custom(_nearer_start)
	var remap := _terrain_remap(data.get("terrains", PackedStringArray()))
	for entry: Dictionary in squares:
		var blob: PackedByteArray = entry["data"]
		var record: Variant = bytes_to_var(blob.decompress(int(entry["size"]), FileAccess.COMPRESSION_ZSTD))
		if typeof(record) != TYPE_DICTIONARY:
			push_warning("Čtverec %s uložené hry nejde přečíst." % entry["coord"])
			continue
		var coord: Vector2i = entry["coord"]
		if not remap.is_empty():
			_remap_record(record, remap)
		_enqueue(coord, record)
		var sq := _square(coord)
		# Přemapovaný čtverec se při dalším uložení zabalí znovu.
		if sq != null and remap.is_empty():
			sq.blob = blob
			sq.blob_size = int(entry["size"])
	# Čtverec levelu ani čtverec hráčů nemusí být uložený, když se zrovna tvořil.
	_enqueue(_start)
	_enqueue(_active)
	# Mapy už jsou ve čtvercích, velký slovník se nemusí držet.
	GameSession.suit_resume = {}


## Uložená hra drží terén jako čísla do seznamu jmen v době uložení. Když se seznam od té
## doby změnil (přibyl terén), vrátí převod starého čísla na nové. Prázdný, když se nezměnil.
## Terén, který už v katalogu není, se změní na trávu.
func _terrain_remap(saved_names: PackedStringArray) -> PackedByteArray:
	if saved_names == _catalog.names:
		return PackedByteArray()
	var remap := PackedByteArray()
	remap.resize(256)
	for id in 256:
		remap[id] = id
	var fallback := maxi(_catalog.names.find("grass"), 0)
	for id in saved_names.size():
		var now := _catalog.names.find(saved_names[id])
		remap[id] = now if now >= 0 else fallback
	return remap


func _remap_record(record: Dictionary, remap: PackedByteArray) -> void:
	for key in ["terrain", "vertex"]:
		record[key] = _remapped(record[key], remap)
	var halo: Array = record["halo"]
	for i in halo.size():
		halo[i] = _remapped(halo[i], remap)


## MapData.UNCLAIMED_TERRAIN zůstane, jak je.
func _remapped(bytes: PackedByteArray, remap: PackedByteArray) -> PackedByteArray:
	var out := bytes.duplicate()
	for i in out.size():
		if out[i] != MapData.UNCLAIMED_TERRAIN:
			out[i] = remap[out[i]]
	return out


func _nearer_start(a: Dictionary, b: Dictionary) -> bool:
	var to_a: Vector2i = a["coord"] - _start
	var to_b: Vector2i = b["coord"] - _start
	return Vector2(to_a).length_squared() < Vector2(to_b).length_squared()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _closed_saved:
		_save()
		_closed_saved = true


func _villagers_of(person: Person) -> Villagers:
	var sq := _square(_where.get(person, _coord(person.position)))
	return sq.villagers if sq != null and sq.awake else null


func _on_took(slot: int, mat: int, person: Person) -> void:
	var villagers := _villagers_of(person)
	if villagers != null:
		villagers.leader_took(slot, mat, person)


func _on_threw(person: Person) -> void:
	var villagers := _villagers_of(person)
	if villagers != null:
		villagers.leader_threw(person)


func _on_used_store(bay: int, left: int, took: int, person: Person) -> void:
	var villagers := _villagers_of(person)
	if villagers != null:
		villagers.leader_used_store(bay, left, took, person)


func _on_touched(person: Person) -> void:
	var villagers := _villagers_of(person)
	if villagers != null:
		villagers.leader_touched(person)


## Ohrada: postava ve čtverci levelu z něj nevyjde. Kraj ji zastaví FENCE_M metrů před sebou.
## Kdo do čtverce teprve vešel, má ohradu tam, kde stojí, a ta se s každým krokem dovnitř
## posune, až je FENCE_M od kraje.
func _update_fence() -> void:
	var rect := Rect2(_origin_of(_active), Vector2(_span(), _span()))
	var full := FENCE_M * float(TerrainCatalog.TILE_SIZE)
	for person: Person in _host._persons:
		if not _locked or not rect.has_point(person.position):
			person.walker.fence = Rect2()
			_insets.erase(person)
			continue
		var local := person.position - rect.position
		var edge := minf(minf(local.x, local.y), minf(rect.size.x - local.x, rect.size.y - local.y))
		var inset := clampf(edge, float(_insets.get(person, 0.0)), full)
		_insets[person] = inset
		person.walker.fence = rect.grow(-inset)


## Po splnění levelu: kdo se přiblíží k nové továrně na LOCK_M metrů, zavře hráče v jejím čtverci.
func _check_lock() -> void:
	if _locked:
		return
	var sq := _square(_active)
	if sq == null or not sq.ready or sq.town.center() == Vector2.INF:
		return
	var reach := LOCK_M * float(TerrainCatalog.TILE_SIZE)
	for person: Person in _host._persons:
		if person.position.distance_to(sq.town.center()) <= reach:
			_locked = true
			return


# --- Úkol ---

func _title() -> String:
	return "Level %d / %d" % [_level, GameSession.last_level()]


## Jak moc šipka bliká: podle postavy nejblíž kraji čtverce levelu.
func _alarm() -> int:
	if not _locked:
		return 0
	var rect := Rect2(_origin_of(_active), Vector2(_span(), _span()))
	var nearest := INF
	for person: Person in _host._persons:
		if rect.has_point(person.position):
			nearest = minf(nearest, _edge_meters(person.position))
	if nearest <= ALARM_M:
		return 2
	return 1 if nearest <= BLINK_M else 0


func _on_progress(done: int, coord: Vector2i) -> void:
	if coord == _active and _hud != null:
		_hud.set_progress(done)


func _on_completed(coord: Vector2i) -> void:
	if coord != _active or _finished:
		return
	_done[coord] = 0
	var cleared := _square(coord)
	if cleared != null and cleared.air != null:
		cleared.air.clear_poison()
	var took := _level_time
	if _level >= GameSession.last_level():
		_finish_game()
		return
	var finished := _level
	_level += 1
	_level_time = 0.0
	_active = _next_square(coord)
	_levels[_active] = _level
	_locked = false
	_enqueue(_active)
	Sound.ui("win")
	_hud.set_goal(_title(), 1)
	_hud.show_notice("Level %d splněn za %s. Šipka ukazuje k nové továrně." % [finished, GameSession.clock(took)], LEVEL_NOTICE)
	_save()


## Nejbližší čtverec od from, kde ještě nic není. Z několika stejně blízkých náhodně.
func _next_square(from: Vector2i) -> Vector2i:
	var radius := 1
	var best := INF
	var picks: Array[Vector2i] = []
	while true:
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var coord := from + Vector2i(x, y)
				if _squares.has(coord):
					continue
				var dist := Vector2(x, y).length()
				if dist < best - 0.001:
					best = dist
					picks.clear()
				if dist <= best + 0.001:
					picks.append(coord)
		# Šikmé místo na tomhle kruhu může být dál než rovné na dalším. Hledá se tedy, dokud
		# nejbližší nalezené není nejvýš tak daleko jako další kruh.
		if not picks.is_empty() and best <= float(radius + 1):
			return picks[_world_rng.randi_range(0, picks.size() - 1)]
		radius += 1
	return from


func _finish_game() -> void:
	_finished = true
	Sound.duck_music()
	Sound.stop_ambient()
	Sound.ui("win")
	get_tree().paused = true
	SuitSaves.finish_game(_header())
	var note := "Všech %d levelů splněno · čas %s" % [GameSession.last_level(), GameSession.clock(_time)]
	var rank := _rank()
	if rank > 0:
		note += " · %d. místo ve výkonech" % rank
	_hud.show_result("Konec hry", note)


## Kolikátá je tahle hra ve výkonech pro stejný počet hráčů. 0 když tam není.
func _rank() -> int:
	var rows := SuitSaves.results(GameSession.players.size())
	for i in rows.size():
		if str(rows[i]["id"]) == GameSession.suit_id:
			return i + 1
	return 0


# --- Uložení ---

func _save() -> void:
	_save_left = SAVE_EVERY
	# Průlet v menu nesmí přepsat uloženou hru, i když v relaci ještě je její id.
	if _flyover or not _opened or _finished or GameSession.suit_id.is_empty():
		return
	SuitSaves.save_game(_header(), _snapshot())


func _header() -> Dictionary:
	return {
		"id": GameSession.suit_id,
		"name": GameSession.suit_name,
		"players": SuitSaves.outfits(GameSession.players),
		"level": _level,
		"time": _time,
	}


## Celá hra k uložení. Rozpracované čtverce se neukládají, po načtení se vytvoří znovu.
func _snapshot() -> Dictionary:
	var squares: Array = []
	for coord: Vector2i in _squares:
		var sq: Square = _squares[coord]
		if sq.map == null or sq.task >= 0:
			continue
		if sq.blob.is_empty():
			var raw := var_to_bytes(_record(sq))
			sq.blob = raw.compress(FileAccess.COMPRESSION_ZSTD)
			sq.blob_size = raw.size()
		squares.append({"coord": coord, "size": sq.blob_size, "data": sq.blob})
	var done := {}
	for coord: Vector2i in _done:
		var finished: SuitGame = _games.get(coord)
		done[coord] = int(finished.factory().snapshot()["suits"]) if finished != null else int(_done[coord])
	# Sklady čtverců, které po načtení ještě nevznikly, se uloží znovu, jak byly.
	var stores := _stores.duplicate()
	for coord: Vector2i in _squares:
		var built: Square = _squares[coord]
		if built.ready and built.town.store_count() > 0:
			stores[coord] = built.town.store_snapshot()
	var persons: Array = []
	for person: Person in _host._persons:
		persons.append(person.snapshot())
	# Co z uložené hry ještě nedošlo na řadu, se uloží znovu, jak bylo.
	var state := _pending.duplicate()
	state["persons"] = persons
	var game: SuitGame = _games.get(_active)
	if game != null:
		state["factory"] = game.factory().snapshot()
		# Dokud vesničané čtverce po načtení nevznikli, postup čeká v _pending.
		if not _pending.has("stored"):
			state["stored"] = game.stored()
	var sq := _square(_active)
	if sq != null and sq.awake:
		state["villagers"] = sq.villagers.snapshot(_host._persons)
		state["monsters"] = sq.monsters.snapshot()
	return {
		"level": _level,
		"time": _time,
		"level_time": _level_time,
		"active": _active,
		"locked": _locked,
		"levels": _levels,
		"done": done,
		"rng": _world_rng.state,
		"terrains": _catalog.names,
		"squares": squares,
		"stores": stores,
		"state": state,
	}
