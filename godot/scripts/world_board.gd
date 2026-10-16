extends Node

## Otevřený svět. Čtverce 96 m navazují terénem, každý má vlastní úkol a tvory.
## Daleko od hráčů tvorové zmizí, krajina a obsah jezírek i továrny zůstanou.
## Nový čtverec převezme krajní řady hotových sousedů, takže svět závisí na pořadí, v jakém
## hráči čtverce otevřou. Ukládání proto bude muset uložit hotové mapy, ne jen semínko.

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

## Strana čtverce v metrech. Pořád stejná, level světa mění jen materiály.
const SQUARE := 96
## Od kraje, kde se na pozadí začne tvořit soused. Roh otevře i šikmý čtverec.
const APPROACH := 32.0
## Od kraje, kde šipka na továrnu tohoto čtverce bliká.
const BLINK := 5.0
## Kolem továrny se voda vysuší, ať nestojí v jezeře. Kraj čtverce to nemění.
const CLEAR := 12.0
## Střed jezírka neblíž ke kraji než tolik metrů. Ústí jezírka zůstane na mapě.
const EDGE := 2.0
const WATER_CELL := 4
const WATER_HEAR := 14.0
const SPAWN_RING := 1.5
const NOTICE_SECONDS := 4.5
## Váha vesnice: žádná dvakrát, ostatní jednou. Úvodní čtverec je vždy malá.
const LAYOUTS: PackedStringArray = ["none", "none", "small", "medium", "large", "huge", "empty"]

var _host
var _camera: MapCamera
var _ground: TerrainChunks
var _status: Label
var _catalog: TerrainCatalog
var _crystal: Crystal
var _road: Node2D
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
var _next_level := 1
var _opened := false
var _closing := false
## Strana čtverce v dlaždicích. Typ hry Skafandry má větší.
var _side := SQUARE


class Square:
	var coord := Vector2i.ZERO
	var origin := Vector2.ZERO
	var layout := ""
	var level := 1
	var task := -1
	var ready := false
	var awake := false
	var done := false
	var delivered := 0
	var map
	var painted := {}
	var rocks
	var forest
	var town
	var monsters
	var villagers
	var walker
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
	_world_rng.randomize()
	_camera.position = Vector2(_span(), _span()) * 0.5
	_camera.roam()
	_road = Node2D.new()
	_road.name = "Road"
	_host.add_child(_road)
	_host.move_child(_road, _ground.get_index() + 1)
	_props = Node2D.new()
	_props.name = "Props"
	_props.y_sort_enabled = true
	_host.add_child(_props)
	_host.move_child(_props, _road.get_index() + 1)
	_chunks = PropChunks.new()
	_chunks.name = "PropChunks"
	_chunks.setup(_camera)
	_host.add_child(_chunks)
	_begin()


## První čtverce. Hra se otevře, až je hotový ten, kde hráči začínají (_opens_at).
func _begin() -> void:
	_enqueue(Vector2i.ZERO)


func tick(delta: float) -> void:
	if _closing:
		return
	_poll()
	_dispatch()
	if not _opened:
		return
	for person in _host._persons:
		_consider(person.position)
	_follow()
	_actors()
	_show_task()
	_sound(delta)


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
	return sq.walker.dry(pos)


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
	sq.rocks.draw_rim = false
	sq.rocks.edge_guard = EDGE
	_configure(sq)
	_squares[coord] = sq
	_waiting.append(coord)
	_dispatch()


## Vesnice a level nového čtverce.
func _plan_square(sq: Square) -> void:
	sq.layout = _layout(sq.coord, sq.rng)
	sq.level = 0 if sq.layout == "empty" else _next_level


## Jezírka čtverce podle levelu. Typ hry Skafandry tu chystá doly a zásobníky továrny.
func _configure(sq: Square) -> void:
	sq.rocks.bottomless = false
	sq.rocks.set_available(0 if sq.layout == "empty" else GameSession.level_materials(sq.level))


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
	var map := MapGenerator.grow(_side, _catalog.names, sq.rng, _catalog.max_distance, _catalog.max_share, ring)
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
	sq.forest.plant(map, sq.rng, sq.rocks)
	sq.walker = Walker.new(sq.rocks, sq.forest, sq.town, map)
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
	_chunks.refresh()
	_built_square(sq)
	sq.ready = true
	if not _opened and _opens_at(sq):
		_open_play(sq)
	elif _opened and sq.layout != "empty":
		_add_labels(sq)


## Hotový čtverec je ve scéně. Svět počítá kameny donesené do jeho továrny.
func _built_square(sq: Square) -> void:
	if sq.town.center() != Vector2.INF:
		sq.town.settled.connect(_count_gem.bind(sq))


## Na tomhle čtverci hra začne, až je hotový.
func _opens_at(sq: Square) -> bool:
	return sq.coord == Vector2i.ZERO


func _open_play(sq: Square) -> void:
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


## První postava stojí u továrny, další v kruhu kolem ní.
func _place_persons(_sq: Square) -> void:
	var first: Vector2 = _host._persons[0].position
	var tile := float(TerrainCatalog.TILE_SIZE)
	for i in range(1, _host._persons.size()):
		var angle := TAU * float(i - 1) / float(maxi(_host._persons.size() - 1, 1))
		var person: Person = _host._persons[i]
		person.position = person._free_spot(first + Vector2.from_angle(angle) * SPAWN_RING * tile)


func _setup_hud(sq: Square) -> void:
	_hud.setup(_crystal, sq.level, "ponds", maxi(sq.rocks.gem_total(), 1), false, GameSession.players)
	_hud.hide_clock()


## Postava je ve scéně a má HUD. Typ hry Skafandry jí dá dýchací přístroj.
func _dress(_person: Person) -> void:
	pass


func _show_terrain(sq: Square) -> void:
	var mats: Dictionary = _catalog.fork_map(sq.map.size, sq.painted["corners"], sq.painted["variants"])
	var chunks: TerrainChunks
	if sq.coord == Vector2i.ZERO:
		chunks = _ground
	else:
		chunks = TerrainChunks.new()
		chunks.name = "Ground_%d_%d" % [sq.coord.x, sq.coord.y]
		chunks.position = sq.origin
		chunks.z_index = -1
		_host.add_child(chunks)
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
	labels.setup(spots, _crystal, _host._persons, _camera, sq.rocks)


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


## Vesničané uložené hry pro čtverec (Villager.origin), prázdné pole vytvoří nové.
func _saved_villagers(_sq: Square) -> Array:
	return []


## Tvorové čtverce se právě objevili.
func _woke(_sq: Square) -> void:
	pass


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


func _show_task() -> void:
	if _hud == null or _host._persons.is_empty():
		return
	var person: Person = _host._persons[0]
	var sq := _square(_where.get(person, _coord(person.position)))
	if sq == null or sq.town.center() == Vector2.INF:
		_hud.show_square("Svět", 0, 0)
		_hud.point_factory(Vector2.ZERO, Vector2.INF)
		_hud.set_edge_blink(false)
		return
	var total := int(sq.rocks.gem_total())
	if total <= 0:
		_hud.show_square("Svět", 0, 0)
	else:
		_hud.show_square("Level %d" % sq.level, sq.delivered, total)
	var to_screen := (_host.get_viewport() as Viewport).get_canvas_transform()
	_hud.point_factory(to_screen * _camera.get_screen_center_position(), to_screen * sq.town.center())
	_hud.set_edge_blink(_edge_meters(person.position) <= BLINK)


## Hraje hudba při honičce? Dokud kdokoli nese kámen: hráč nebo vesničan na probuzeném čtverci.
func _chase_music() -> bool:
	if Monsters.anyone_carrying(_host._persons, []):
		return true
	for key in _squares:
		var sq: Square = _squares[key]
		if sq.awake and not sq.monsters.carriers.is_empty():
			return true
	return false


func _count_gem(_mat: int, _pos: Vector2, sq: Square) -> void:
	sq.delivered += 1
	if sq.done or sq.rocks.gem_total() <= 0 or sq.delivered < sq.rocks.gem_total():
		return
	sq.done = true
	_next_level += 1
	if _hud != null:
		_hud.show_notice("Továrna je hotová. Další čtverce jsou level %d." % _next_level, NOTICE_SECONDS)


func _sound(_delta: float) -> void:
	Sound.set_chase(_chase_music())
	if _host._persons.is_empty():
		Sound.set_water(0.0)
		return
	var person: Person = _host._persons[0]
	var sq := _square(_where.get(person, _coord(person.position)))
	if sq == null or sq.water_far.is_empty():
		Sound.set_water(0.0)
		return
	var tile := float(TerrainCatalog.TILE_SIZE)
	var local := person.position - sq.origin
	var cx := clampi(floori(local.x / tile) / WATER_CELL, 0, sq.water_side - 1)
	var cy := clampi(floori(local.y / tile) / WATER_CELL, 0, sq.water_side - 1)
	var meters := float(sq.water_far[cy * sq.water_side + cx] * WATER_CELL)
	Sound.set_water(1.0 - meters / WATER_HEAR)


func _layout(coord: Vector2i, rng: RandomNumberGenerator) -> String:
	if coord == Vector2i.ZERO:
		return "small"
	return LAYOUTS[rng.randi_range(0, LAYOUTS.size() - 1)]


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
