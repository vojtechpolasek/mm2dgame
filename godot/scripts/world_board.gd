extends Node

## Hra jako otevřený svět ze čtverců SQUARE × SQUARE m, které navazují terénem. Kolem se
## dotváří, jak se hráči blíží ke kraji, ať za ním není prázdno. Nový čtverec převezme krajní
## řady hotových sousedů, takže svět závisí na pořadí, v jakém hráči čtverce otevřou.
## Čtverec dál než PARK_AT od čtverců hráčů se uvolní ze scény a zůstane jen jeho mapa
## (_parked). Po návratu se z ní postaví stejně.
## Režim hry je GameSession.mode. Ve volném pohybu nejsou příšery, čas ani cíl. Chytej příšery
## a Sbírání materiálů řídí Hunt: kde a jaké příšery a kameny se objeví, čas a body. Čtverce pro
## něj nic nepřipravují. Nic se neukládá, kromě výkonů.
## Průlet v menu (start_flyover): stejná krajina, bez postavy. Kamera jede stálou rychlostí
## šikmo nahoru doprava a podle ní se otevírají další čtverce.
## Den a noc (DayNight): slunce a měsíc obíhají, objekty vrhají stíny (Shadows) a v noci
## se svět ztmaví.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapGenerator := preload("res://scripts/map_generator.gd")
const MapData := preload("res://scripts/map_data.gd")
const Forest := preload("res://scripts/forest.gd")
const Rocks := preload("res://scripts/rocks.gd")
const PropChunks := preload("res://scripts/prop_chunks.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const Person := preload("res://scripts/person.gd")
const Crystal := preload("res://scripts/crystal.gd")
const Hud := preload("res://scripts/hud.gd")
const Crowd := preload("res://scripts/crowd.gd")
const Party := preload("res://scripts/party.gd")
const Walker := preload("res://scripts/walker.gd")
const TerrainChunks := preload("res://scripts/terrain_chunks.gd")
const GroundDecor := preload("res://scripts/ground_decor.gd")
const SquareAir := preload("res://scripts/square_air.gd")
const River := preload("res://scripts/river.gd")
const Splashes := preload("res://scripts/splashes.gd")
const MiniMap := preload("res://scripts/minimap.gd")
const Shadows := preload("res://scripts/shadows.gd")
const DayNight := preload("res://scripts/day_night.gd")
const Benchmark := preload("res://scripts/benchmark.gd")
const Hunt := preload("res://scripts/hunt.gd")

## Strana čtverce v metrech.
const SQUARE := 128
## Kolik terénů si nový čtverec vybere (MapGenerator.pick_terrains). Víc by mapu rozdrobilo.
const TERRAINS_PER_SQUARE := 3
## Terény, které úvodní čtverec nikdy nemá: bažina by hned na začátku zpomalila, voda
## překážela. Bez vody nemá úvodní čtverec ani řeku (River teče do jezera).
const START_BANNED: PackedStringArray = ["swamp", "water"]
## Od kraje, kde se na pozadí začne tvořit soused. Roh otevře i šikmý čtverec.
const APPROACH := 32.0
const WATER_CELL := 4
const WATER_HEAR := 14.0
## Další hráči stojí v kruhu tolik metrů kolem prvního.
const SPAWN_RING := 1.5
## Čtverec aspoň tolik čtverců od každého hráče se uvolní. Nový čtverec vzniká
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
## Svah břehu řek podle terénu (River.spawn, bank v surfaces.json).
var _bank_look := {}
var _crystal: Crystal
## Řeky a mosty všech čtverců, nad cestou a pod porostem.
var _rivers: Node2D
## Cákání vody od nohou (Splashes), nad vodou a pod postavami.
var _splashes: Node2D
## Průchozí porost všech čtverců, mezi řekou a objekty.
var _decor: Node2D
var _decor_kit := {}
var _props: Node2D
## Stíny objektů mezi porostem a objekty, a den s nocí.
var _shadows: Shadows
var _day: DayNight
var _chunks: PropChunks
var _hud: Hud
var _party: Party
var _crowd: Crowd
var _squares := {}
## Čtverce, které čekají, až se dotvoří jejich sousedé. Navazují pak na jejich kraje.
var _waiting: Array[Vector2i] = []
## Čtverce hotové z vlákna, které se po částech přidávají do scény (_finish_step).
var _finishing: Array[Vector2i] = []
## Objevené dlaždice mapy v rohu: souřadnice čtverce -> PackedByteArray, 255 objevená.
## Drží i čtverce, které se mezitím uvolnily.
var _seen := {}
var _world_rng := RandomNumberGenerator.new()
var _opened := false
var _closing := false
## Strana čtverce v dlaždicích.
var _side := SQUARE
## Průlet v menu. Krajina jako volný pohyb, kamera jede sama a postava se nespawnuje.
var _flyover := false
## Uvolněné čtverce: souřadnice -> mapa (_record).
var _parked := {}
## Chytej příšery a Sbírání materiálů, jinak null.
var _hunt: Hunt


class Square:
	var coord := Vector2i.ZERO
	var origin := Vector2.ZERO
	var task := -1
	## Kolik částí _finish_step už do scény přidal.
	var stage := 0
	var ready := false
	var awake := false
	var map
	var painted := {}
	var rocks
	var forest
	var walker
	var river
	var decor
	## Vzduch nad čtvercem (mlha, sníh) a jeho maska terénu z vlákna.
	var air
	var air_mask: Dictionary
	## Obrázek čtverce pro mapu v rohu, pixel na dlaždici (MiniMap.chart).
	var chart: Image
	var rng: RandomNumberGenerator
	## Stav rng po nakreslení terénu. Odtud se sází skály a stromy, takže čtverec
	## jde z uložené mapy postavit znovu stejně.
	var plan_state := 0
	## Řeky přes kraj (River.plan): open, bity stran bez mapy souseda, a inlets, vtoky
	## hotových sousedů. Platí, jak byly při tvoření, ukládají se s mapou.
	var river_links := {}
	## Mapa uvolněného čtverce (_record), ze které se po návratu staví místo tvoření.
	var saved := {}
	var water_far := PackedInt32Array()
	var water_side := 0
	## Terén čtverce ve scéně.
	var ground
	## Dlaždice s vodou pro terén, spočítané ve vlákně (TerrainChunks.find_water).
	var water: Array = []
	## Výřezy pole koryta řeky po chuncích terénu (River.field_tiles).
	var river_tiles := {}


## Krajina pod menu. Volá se místo start().
func start_flyover(host) -> void:
	_flyover = true
	start(host)


func start(host) -> void:
	_host = host
	_camera = host.camera
	_ground = host.ground
	_status = host.status
	_catalog = TerrainCatalog.new()
	_catalog.load_assets()
	if _catalog.names.is_empty():
		_status.text = "Chybí terén."
		_status.visible = true
		if _host.has_method("lift_curtain"):
			_host.lift_curtain()
		push_error("Ve složce terénu nejsou žádné povrchy.")
		return
	_crystal = Crystal.new()
	if not _crystal.load_catalog():
		push_error("Chybí materiály krystalu.")
	if GameSession.timed() and not _flyover:
		_hunt = Hunt.new()
		_hunt.name = "Hunt"
		add_child(_hunt)
		_hunt.load_catalog(_crystal)
	Benchmark.seed_rng(_world_rng, 0)
	_camera.position = Vector2(_span(), _span()) * 0.5
	_camera.roam()
	_rivers = Node2D.new()
	_rivers.name = "Rivers"
	_host.add_child(_rivers)
	_host.move_child(_rivers, _ground.get_index() + 1)
	_decor = Node2D.new()
	_decor.name = "Decor"
	_host.add_child(_decor)
	_host.move_child(_decor, _rivers.get_index() + 1)
	_decor_kit = GroundDecor.load_kit(_catalog.names, _catalog.surfaces)
	_bank_look = _catalog.bank_look()
	_props = Node2D.new()
	_props.name = "Props"
	_props.y_sort_enabled = true
	_host.add_child(_props)
	_host.move_child(_props, _decor.get_index() + 1)
	_shadows = Shadows.new()
	_shadows.name = "Shadows"
	_host.add_child(_shadows)
	_host.move_child(_shadows, _props.get_index())
	_splashes = Splashes.new()
	_splashes.name = "Splashes"
	_splashes.board = self
	_host.add_child(_splashes)
	_host.move_child(_splashes, _props.get_index())
	_shadows.setup(_camera)
	_day = DayNight.new()
	_day.name = "DayNight"
	_day.full_moon_only = _flyover
	_host.add_child(_day)
	_day.setup(_camera, _shadows, _host._persons)
	_chunks = PropChunks.new()
	_chunks.name = "PropChunks"
	_chunks.setup(_camera)
	_host.add_child(_chunks)
	_enqueue(Vector2i.ZERO)


func tick(delta: float) -> void:
	if _closing:
		return
	_poll()
	_dispatch()
	if not _opened:
		return
	_day.advance(delta)
	if _hud != null:
		_hud.set_sky(_day.phase, _day.moon_index())
	if _flyover:
		_drift(delta)
		_consider(_camera.position)
		_park_far()
		_sound(delta)
		return
	for person in _host._persons:
		_consider(person.position)
	if _hunt != null:
		_hunt.tick(delta, _day.phase)
		_hud.set_countdown(_hunt.time_left, Hunt.SECONDS)
	_sound(delta)
	_park_far()


func shutdown() -> void:
	_closing = true
	for key in _squares.keys():
		var sq: Square = _squares[key]
		if sq.task >= 0:
			WorkerThreadPool.wait_for_task_completion(sq.task)
			sq.task = -1


func is_dry(pos: Vector2) -> bool:
	var sq := _ready_at(pos)
	if sq == null:
		return false
	var ground: int = sq.walker.ground(pos)
	if ground != Walker.EDGE_WATER:
		return ground == Walker.LAND or ground == Walker.SHALLOW
	# Voda u kraje čtverce je mělčina, když je souš u souseda nejdál Walker.SHORE_TILES dlaždic.
	var tile := float(TerrainCatalog.TILE_SIZE)
	var center := (pos / tile).floor() * tile + Vector2(tile, tile) * 0.5
	for dy in range(-Walker.SHORE_TILES, Walker.SHORE_TILES + 1):
		for dx in range(-Walker.SHORE_TILES, Walker.SHORE_TILES + 1):
			var near := center + Vector2(dx, dy) * tile
			var other := _ready_at(near)
			if other != null and other != sq and other.walker.ground(near) == Walker.LAND:
				return true
	return false


## Může být brodítelná voda do reach pixelů od pos? Ptá se čtverců v rozích čtverce kolem pos.
## Čtverce jsou větší než reach, víc jich to být nemůže.
func may_swim_near(pos: Vector2, reach: float) -> bool:
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var sq := _ready_at(pos + corner * reach)
		if sq != null and sq.walker.may_swim():
			return true
	return false


## Brodítelná voda v bodě světa pro vodní příšeru (Walker.swims). Voda u kraje čtverce se bere
## jako mělčina, když je za krajem souš (stejně jako is_dry).
func swims(pos: Vector2) -> bool:
	var sq := _ready_at(pos)
	if sq == null:
		return false
	if sq.walker.ground(pos) == Walker.EDGE_WATER:
		return is_dry(pos)
	return sq.walker.swims_here(pos)


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


## Skály a stromy jen ze čtverců, které na tělo dosáhnou. Ostatní by bod neposunuly a jejich
## mřížky by se procházely zbytečně. Rezerva je dvojnásobná, bod se mezi průchody posouvá.
func move_body(pos: Vector2, body: float, clearance: float) -> Vector2:
	var around: Array[Square] = []
	var props: Array[bool] = []
	var coord := _coord(pos)
	var span := Vector2.ONE * _span()
	for y in range(-1, 2):
		for x in range(-1, 2):
			var sq := _square(coord + Vector2i(x, y))
			if sq == null or not sq.ready:
				continue
			var near := (maxf(sq.rocks.reach(), sq.forest.reach()) + body) * 2.0
			around.append(sq)
			props.append(Rect2(_origin_of(sq.coord), span).grow(near).has_point(pos))
	for _pass in 2:
		for i in around.size():
			var sq := around[i]
			if props[i]:
				pos = sq.rocks.avoid(pos, body, clearance)
				pos = sq.forest.avoid(pos, body, clearance)
	return pos


func _poll() -> void:
	for key in _squares.keys():
		var sq: Square = _squares[key]
		if sq.task < 0 or not WorkerThreadPool.is_task_completed(sq.task):
			continue
		WorkerThreadPool.wait_for_task_completion(sq.task)
		sq.task = -1
		if _closing:
			continue
		if sq.map == null or sq.walker == null:
			push_error("Čtverec %s se nepodařilo vytvořit." % sq.coord)
			continue
		_finishing.append(sq.coord)
	_finish_step()


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
	else:
		sq.plan_state = int(saved["plan_state"])
		sq.river_links = saved.get("river", {})
		sq.saved = saved
	sq.rocks = Rocks.new()
	sq.forest = Forest.new()
	sq.rocks.name = "Rocks"
	sq.forest.name = "Trees"
	_squares[coord] = sq
	_waiting.append(coord)
	_dispatch()


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
		sq.river_links = _river_links(coord)
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


## Řeky přes kraje čtverce: strany, za kterými ještě není mapa (rameno odtud smí přitékat,
## soused ho pak dovede od pramene), a vtoky hotových sousedů na společných krajích.
func _river_links(coord: Vector2i) -> Dictionary:
	var open := 0
	var inlets: Array = []
	for side in River.SIDES.size():
		var at: Vector2i = coord + River.SIDES[side]
		var other := _built(at)
		if other != null:
			for exit: Dictionary in other.river.exits:
				if River.SIDES[int(exit["side"])] == -River.SIDES[side]:
					inlets.append({"side": side, "at": exit["at"], "width": exit["width"]})
			continue
		var known := _square(at)
		if _parked.has(at) or (known != null and not known.saved.is_empty()):
			continue
		open |= 1 << side
	return {"open": open, "inlets": inlets}


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


## Katalogy skal a stromů. Ve vlákně čtverce, na hlavním by čtení katalogů zaseklo
## hru při přechodu do dalšího čtverce (na Raspberry Pi desítky ms).
func _load_catalogs(sq: Square) -> void:
	sq.rocks.load_catalog(_catalog.names, _catalog.surfaces)
	sq.forest.load_catalog(_catalog.names, _catalog.surfaces)


func _generate(sq: Square, ring: PackedByteArray, fixed: PackedByteArray) -> void:
	_load_catalogs(sq)
	# Benchmark chce vodu hned u startu, jeho čtverec ji proto smí mít.
	var banned := START_BANNED if sq.coord == Vector2i.ZERO and not Benchmark.requested() else PackedStringArray()
	var pool := MapGenerator.pick_terrains(_catalog.names, _catalog.surfaces, sq.rng, TERRAINS_PER_SQUARE, ring, banned)
	var map := MapGenerator.grow(_side, _catalog.names, sq.rng, _catalog.max_distance, _catalog.max_share, ring, pool)
	map.surfaces = _catalog.surfaces
	# U vtoku řeky od souseda je souš, jinak by řeka skončila na kraji.
	var tile := float(TerrainCatalog.TILE_SIZE)
	for spot in River.clear_spots(sq.river_links.get("inlets", []), _side):
		MapGenerator.clear_circle(map, Vector2(spot.x, spot.y) / tile, spot.z / tile)
	sq.painted = MapGenerator.corner_data(map, sq.rng, _catalog.variant_count, fixed)
	sq.plan_state = sq.rng.state
	_furnish(sq, map)


## Čtverec z uložené mapy. Rohy dlaždic se dopočítají z vrcholů, objekty se sází od
## uloženého stavu rng, takže stojí tam, kde stály.
func _rebuild(sq: Square) -> void:
	_load_catalogs(sq)
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


## Mapa uvolněného čtverce. Stačí terén, vrcholy, varianty dlaždic a okolí od sousedů.
func _record(sq: Square) -> Dictionary:
	return {
		"plan_state": sq.plan_state,
		"terrain": sq.map.terrain,
		"vertex": sq.painted["vertex"],
		"variants": sq.painted["variants"],
		"halo": [sq.map.halo_w, sq.map.halo_e, sq.map.halo_n, sq.map.halo_s],
		"river": sq.river_links,
	}


## Čtverec po terénu, jako by rostl: přírodní skály, řeky mezi nimi, nakonec stromy a porost.
func _furnish(sq: Square, map: MapData) -> void:
	var inlets: Array = sq.river_links.get("inlets", [])
	sq.rocks.keep_clear = River.clear_spots(inlets, map.size)
	sq.rocks.plant(map, sq.rng)
	# Řeka má vlastní náhodu, ať nemění, co se losuje po ní.
	sq.river = River.new()
	var open := int(sq.river_links.get("open", 0))
	sq.river.plan(map, sq.rocks, hash(sq.plan_state) + 1, sq.painted["vertex"], open, inlets)
	sq.rocks.river = sq.river
	sq.forest.river = sq.river
	sq.forest.plant(map, sq.rng, sq.rocks)
	# Porost má vlastní náhodu, ať nemění, co se losuje po něm.
	sq.decor = GroundDecor.new()
	sq.decor.plant(_decor_kit, map, sq.painted["corners"], _catalog.water_index, sq.coord * _side, hash(sq.plan_state), sq.river)
	sq.air_mask = SquareAir.mask(map)
	sq.walker = Walker.new(sq.rocks, sq.forest, map)
	sq.walker.river = sq.river
	# Hranice skal pro těla příšer a postavy tady ve vlákně, na hlavním by výpočet zasekl hru.
	if _hunt != null:
		for body in _hunt.bodies:
			sq.rocks.prepare_bounds(body)
	sq.rocks.prepare_bounds(Person.BODY)
	# Textury tady ve vlákně, na hlavním by načtení zaseklo hru.
	sq.rocks.load_used_textures()
	sq.forest.load_used_textures()
	var water := _water_map(map)
	sq.water_side = int(water["side"])
	sq.water_far = water["far"]
	# Menu mapu v rohu nemá.
	if not _flyover:
		sq.chart = MiniMap.chart(map, sq.rocks, sq.forest, sq.river)
	# Co jde, se připraví tady, ať dokončení čtverce na hlavním vlákně nezasekne hru.
	sq.water = TerrainChunks.find_water(map.size, sq.painted["corners"], _catalog.water_index)
	sq.river.prepare_mesh()
	sq.river_tiles = sq.river.field_tiles(TerrainChunks.TILES * TerrainCatalog.TILE_SIZE)
	sq.map = map


## Hotový čtverec z vlákna přichází do scény po částech, jedna za snímek, ať se hra
## nezasekne. Dokud není ready, hra ho nepoužívá.
func _finish_step() -> void:
	if _finishing.is_empty():
		return
	var sq := _square(_finishing[0])
	if sq == null:
		_finishing.remove_at(0)
		return
	match sq.stage:
		0:
			sq.origin = _origin_of(sq.coord)
			sq.rocks.relocate(sq.origin)
			sq.forest.relocate(sq.origin)
			sq.river.relocate(sq.origin)
			sq.walker.set_space(sq.origin)
			_show_terrain(sq)
		1:
			add_child(sq.rocks)
			sq.rocks.spawn(_camera, _props, _chunks)
		2:
			add_child(sq.forest)
			sq.forest.spawn(_camera, _props, _chunks)
		3:
			sq.river.spawn(_rivers, sq.origin, _catalog.water_material, _bank_look, sq.painted)
		4:
			sq.decor.spawn(_decor_kit, _decor, sq.origin)
		_:
			_finishing.remove_at(0)
			_finish(sq)
			return
	sq.stage += 1


func _finish(sq: Square) -> void:
	sq.air = SquareAir.new()
	sq.air.name = "Air_%d_%d" % [sq.coord.x, sq.coord.y]
	_host.add_child(sq.air)
	sq.air.setup(sq.air_mask, _side, sq.origin)
	sq.air_mask = {}
	_chunks.refresh()
	sq.ready = true
	_chart(sq)
	if not _opened and sq.coord == Vector2i.ZERO:
		_open_play(sq)


## Čtverec do mapy v rohu.
func _chart(sq: Square) -> void:
	if _hud == null or sq.chart == null:
		return
	_hud.minimap.add_square(sq.coord, sq.origin, sq.chart)


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
		person.setup(sq.rocks, sq.forest, _camera, sq.map, _crystal, i)
		person.walker.world_board = self
		person.walker.crowd = _crowd
		person.crowd_id = _crowd.join(person)
		person.party = _party
		_host._persons.append(person)
		_party.members.append(person)
	_ring_persons()
	_hud = Hud.new()
	_hud.name = "Game"
	_host.get_node("Hint").add_child(_hud)
	_setup_hud()
	_host._hud = _hud
	_hud.minimap.setup(_camera, _host._persons, _seen, _side)
	for key in _squares:
		var built: Square = _squares[key]
		if built.ready:
			_chart(built)
	for person in _host._persons:
		person.held_changed.connect(_hud.set_held.bind(person.player_index))
	var music := RandomNumberGenerator.new()
	Benchmark.seed_rng(music, 1)
	Sound.play_level_music(music)
	_status.visible = false
	_host.lift_curtain()
	_host._map_ready = true
	_opened = true
	sq.walker.crowd = _crowd
	_party.frame()
	if _hunt != null:
		_hunt.crowd = _crowd
		_hunt.start(self, _camera, _host._persons, _props, _day.phase, sq.map.surfaces)
		_hunt.tags.name = "HuntTags"
		_add_screen_labels(_hunt.tags)
		_hunt.scored.connect(_hud.set_hunt_score)
		_hunt.finished.connect(_finish_hunt)


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


## První postava stojí uprostřed úvodního čtverce, další v kruhu kolem ní.
func _ring_persons() -> void:
	var first: Vector2 = _host._persons[0].position
	var tile := float(TerrainCatalog.TILE_SIZE)
	for i in range(1, _host._persons.size()):
		var angle := TAU * float(i - 1) / float(maxi(_host._persons.size() - 1, 1))
		var person: Person = _host._persons[i]
		person.position = person._free_spot(first + Vector2.from_angle(angle) * SPAWN_RING * tile)


func _setup_hud() -> void:
	_hud.setup(_crystal, GameSession.players)
	if _hunt != null:
		_hud.hunt(Hunt.title(), Hunt.SECONDS, GameSession.mode == GameSession.COLLECT)
	else:
		_hud.free_roam()
	_hud.menu_pressed.connect(_host._to_menu)
	_hud.pause_requested.connect(_host._open_pause)
	_hud.pause_closed.connect(_host._close_pause)
	_hud.main_menu_pressed.connect(_host._to_main_menu)
	_hud.again_pressed.connect(_host._play_again)


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
	chunks.water_tiles = sq.water
	var water := mats["water"] as ShaderMaterial
	water.set_shader_parameter("map_origin", sq.origin)
	var bake := mats["bake"] as ShaderMaterial
	bake.set_shader_parameter("map_origin", sq.origin)
	# Břehy řeky do pečení terénu (jako jezera). Výřezy pole vznikly ve vlákně (_furnish).
	bake.set_shader_parameter("river_field_step", float(River.FIELD_STEP))
	chunks.river_tiles = sq.river_tiles
	chunks.setup(
		_catalog,
		sq.map.size,
		sq.painted["corners"],
		_camera,
		bake,
		water,
	)


## Nápisy nad příšerami a kameny jsou na obrazovce ve vrstvě HUD (Hint), pod HUD a pauzou. Ve
## světě by se při nižším rozlišení kreslily zmenšené a rozmazané.
func _add_screen_labels(labels: Node) -> void:
	var layer: Node = _host.get_node("Hint")
	layer.add_child(labels)
	layer.move_child(labels, 0)


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


## Hraje hudba honičky? Když na obrazovce některá příšera utíká nebo honí (Hunt).
func _chase_music() -> bool:
	return _hunt != null and _hunt.any_chase()


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


## Uvolní čtverce daleko od hráčů. Čtverec, vedle kterého se ještě něco tvoří,
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
	for node: Node in [sq.rocks, sq.forest]:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()


## Je pod bodem hotový čtverec? Létající příšera při úprku nad jiný nevyletí.
func has_ground(pos: Vector2) -> bool:
	return _ready_at(pos) != null


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


# --- Konec hry ---


## Čas vypršel. Hra stojí. Vejde-li se výkon do tabulky, nabídne se jméno
## (předvyplněné posledním pro tolik hráčů), pak se zapíše a ukáže tabulka.
func _finish_hunt(points: int, caught: int) -> void:
	Sound.duck_music()
	Sound.stop_ambient()
	Sound.ui("win")
	get_tree().paused = true
	var players := GameSession.players.size()
	var note := "%d bodů · %s" % [points, Hunt.count_text(caught)]
	if not Hunt.qualifies(players, points):
		_hud.show_records("Čas vypršel", note + "\nDo tabulky %s se výkon nevešel." % _players_of(players),
			Hunt.records(players), -1, Hunt.count_caption())
		return
	_hud.name_entered.connect(_save_hunt.bind(points, caught, note), CONNECT_ONE_SHOT)
	_hud.ask_name("Čas vypršel", note, Hunt.last_name(players))


func _save_hunt(name: String, points: int, caught: int, note: String) -> void:
	var players := GameSession.players.size()
	var rank := Hunt.record(players, points, caught, name)
	if rank == 1:
		note += "\nNový rekord %s!" % _players_of(players)
	elif rank > 0:
		note += "\n%d. místo %s" % [rank, _players_of(players)]
	_hud.show_records("Čas vypršel", note, Hunt.records(players), rank - 1, Hunt.count_caption())


## „pro 1 hráče“, „pro 3 hráče“.
static func _players_of(count: int) -> String:
	return "pro %d hráče" % count if count <= 4 else "pro %d hráčů" % count
