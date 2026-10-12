extends Node2D

## Vesničan. Bydlí v domech u cesty a střídá činnosti se stejnou šancí:
##   zůstane v domě, přejde do jiného domu, zajde na cestu, nebo k výstupku továrny.
## Na cestě a u výstupku postojí WAIT sekund a vrátí se do domu, ze kterého vyšel. Po každém
## vstupu do domu v něm zůstane HOUSE_PAUSE sekund, teprve pak losuje. Zůstat v domě je dalších
## WAIT sekund. V domě ho není vidět a nikomu nepřekáží. Do domu vchází kolmo dveřmi: přes stěny,
## ale pod střechou, a zmizí, až je celý pod ní. Ven vychází stejnou cestou obráceně.
## Když je některý hráč blíž než POINT_NEAR metrů, zastaví se a nataženou rukou ukáže na nejbližší
## jezírko, kde leží aspoň jeden kámen. Nad hlavou mu visí poloprůhledný nejdražší kámen z toho
## jezírka, ten by si tam hráč vzal. U bezedných jezírek ukazuje na náhodné jezírko svého materiálu
## a nad hlavou má svůj materiál. Když není na co ukázat, jen se k hráči otočí.
## Až jsou všichni hráči dál než POINT_FAR, pokračuje v tom, co dělal.
## Při honičce ho správce vesničanů může poslat pomáhat (help): přeruší, co dělá, z domu vyjde
## dveřmi a běží jako hráč na místo HELP_SHARE cesty od příšery k honěné postavě. Ruku má
## nataženou. Příšera přes něj neprojde, musí ho obejít. Po honičce jde domů.
## Grafika je hráčova, chodí atlasem chůze s kratším krokem, při pomoci běží atlasem běhu.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const Figure := preload("res://scripts/figure.gd")
const Walker := preload("res://scripts/walker.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")
const Town := preload("res://scripts/town.gd")
const Rocks := preload("res://scripts/rocks.gd")
const Crystal := preload("res://scripts/crystal.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const Person := preload("res://scripts/person.gd")
const Monster := preload("res://scripts/monster.gd")

## Chůze je poloviční rychlost běhu hráče.
const WALK_METERS := Person.RUN_METERS * 0.5
const BODY := Person.BODY
const HOUSE_PAUSE := 2.0
const WAIT := Vector2(3.0, 5.0)
const POINT_NEAR := 3.0
const POINT_FAR := 3.5
## Jak často se při ukazování ověří, že v jezírku materiál pořád leží.
const POINT_CHECK := 0.5
## Natáčení v radiánech za sekundu.
const TURN_SPEED := 6.0
## Bod cesty je dosažený na tolik pixelů.
const REACH_PX := 6.0
## Když skoro nepostupuje tolik sekund (někdo stojí v cestě), cestu přepočítá. Po STALL_TRIES
## přepočtech to vzdá: na místo jen dojde v duchu, do domu vejde.
const STALL_SECONDS := 1.0
const STALL_TRIES := 4
## Dál než tolik metrů za okrajem obrazovky jde bez srážek a bez animace.
const OFF_SCREEN_M := 3.0
## Kámen přímo nad hlavou, ne u natažené ruky. HEAD_LOCAL je střed hlavy v atlasu
## (tools/gen_person.py), záporné Y je dopředu. GEM_LIFT ho zvedne k hornímu okraji
## obrazu, ať mine temeno i dlaň. GEM_HEIGHT je výška pro posun vrstev. Houpe se o BOB_PX.
const HEAD_LOCAL := Vector2(0.0, -4.0)
const GEM_HEIGHT := 2.2
const GEM_LIFT := 40.0
const GEM_ALPHA := 0.65
const GEM_SCALE := 0.8
const BOB_PX := 3.0
const BOB_SPEED := 2.4
const STEP_SURFACES: PackedStringArray = ["grass", "dirt", "desert", "snow"]
const STEP_VARIANTS := 4
const STEP_DB := -14.0
## Pomoc při honičce: cílové místo je tenhle díl cesty od příšery k honěné postavě. Přímá
## cesta k němu se ověřuje po HELP_SIGHT sekundách, když nevede, běží po mřížce. U cíle stojí
## a dívá se na příšeru.
const HELP_SHARE := 0.2
const HELP_SIGHT := 0.5
const HELP_ARRIVE_PX := 6.0
## Bod cesty mřížky je při pomoci dosažený na tolik dlaždic.
const HELP_REACH := 0.6
## Barvy kůže. Triko, kalhoty a vlasy jsou ze vzorníku menu postavy.
const SKINS: PackedStringArray = ["F6CDB0", "EDBE98", "D9A27A", "B07850", "8A5A3C"]

enum State { INSIDE, WALKING, WAITING, DOORWAY, HELPING }
enum Then { ENTER, WAIT }

## Číslo mezi tvory, kteří nechodí přes sebe. Nastaví správce vesničanů.
var crowd_id := -1
## Materiál, na který vesničan ukazuje.
var material_index := -1

var _figure := Figure.new()
var _walker: Walker
var _nav: NavGrid
var _town: Town
var _rocks: Rocks
var _crystal: Crystal
var _camera: MapCamera
var _persons: Array[Person] = []
var _rng: RandomNumberGenerator
var _speed := 144.0
var _state := State.INSIDE
var _then := Then.ENTER
var _home := 0
var _goal_house := 0
var _timer := 0.0
var _path := PackedVector2Array()
var _path_i := 0
## Cesta vede po mřížce. Bez ní jde vesničan rovnou k cíli a srážky hlídá i mimo obrazovku.
var _routed := false
var _target := Vector2.ZERO
var _stall := 0.0
var _stall_tries := 0
var _travel := 0.0
var _step_travel := 0.0
var _pointing := false
var _point_slot := -1
var _point_at: Person
var _point_check := 0.0
var _gem: Sprite2D
## Materiál kamene nad hlavou, -1 nenamalovaný.
var _gem_mat := -1
var _gem_phase := 0.0
var _bob := 0.0
## Příšera, které se staví do cesty. Nastaví a zruší správce vesničanů.
var _helping: Monster
var _help_path := PackedVector2Array()
var _help_i := 0
var _help_on_path := false
var _help_sight := 0.0
var _fitted := Vector2.ZERO
## Kam vesničan patří mimo dveře. Ve dveřích je dítětem domu mezi stěnami a střechou.
var _host: Node2D
var _door_from := Vector2.ZERO
var _door_to := Vector2.ZERO
var _door_t := 0.0
## Co udělá, až projde dveřmi.
var _after_door: Callable


func setup(
	walker: Walker,
	nav: NavGrid,
	town: Town,
	rocks: Rocks,
	crystal: Crystal,
	camera: MapCamera,
	persons: Array[Person],
	host: Node2D,
	home: int,
	mat: int,
	colors: Dictionary,
	rng: RandomNumberGenerator,
) -> bool:
	_walker = walker
	_nav = nav
	_town = town
	_rocks = rocks
	_crystal = crystal
	_camera = camera
	_persons = persons
	_rng = rng
	_home = home
	_host = host
	material_index = mat
	_speed = WALK_METERS * float(TerrainCatalog.TILE_SIZE)
	if not _figure.build(self, true, Person.CYCLE_METERS):
		return false
	_figure.tint(colors)
	_figure.set_frame(_figure.idle_frame)
	# Nad malými objekty, pod velkými, jako hráč.
	z_index = 1
	if crystal != null:
		_gem = crystal.make_sprite()
		_gem.visible = false
		_gem.z_index = 3
		_gem.scale = Vector2.ONE * GEM_SCALE
		host.add_child(_gem)
		_gem_phase = rng.randf() * TAU
		_gem.set_instance_shader_parameter("alpha", GEM_ALPHA)
	_bob = rng.randf() * TAU
	camera.view_changed.connect(_on_view_changed)
	_fit(camera.get_viewport_rect().size)
	# Všichni začínají v domě, každý jinak dlouho, ať nevyjdou naráz.
	position = town.door(home, BODY)
	_enter(home)
	_timer = rng.randf_range(0.0, HOUSE_PAUSE + WAIT.y)
	return true


## Náhodné barvy oblečení. Trika hráčů vynechá, ať jdou hráči poznat.
static func outfit(rng: RandomNumberGenerator, taken: PackedStringArray) -> Dictionary:
	var colors := {"skin": SKINS[rng.randi() % SKINS.size()]}
	for part: String in GameSession.PARTS:
		var listed: Array = GameSession.SWATCHES[part]
		var free: Array = listed.filter(func(hex: Variant) -> bool: return part != "shirt" or not taken.has(str(hex)))
		if free.is_empty():
			free = listed
		colors[part] = str(free[rng.randi() % free.size()])
	return colors


func _process(delta: float) -> void:
	if _state == State.INSIDE:
		_timer -= delta
		if _timer <= 0.0:
			_choose()
		return
	if _state == State.DOORWAY:
		_step_door(delta)
		return
	if _state == State.HELPING:
		_step_help(delta)
		return
	if _watch(delta):
		return
	if _state == State.WAITING:
		_timer -= delta
		if _timer <= 0.0:
			_head_to_house(_home)
		return
	_walk(delta)


# --- Činnosti ---

func _choose() -> void:
	match _rng.randi() % 4:
		0:
			_timer = _rng.randf_range(WAIT.x, WAIT.y)
		1:
			var other := _other_house()
			if other < 0:
				_timer = _rng.randf_range(WAIT.x, WAIT.y)
			else:
				_leave(_head_to_house.bind(other))
		2:
			_leave(func() -> void: _head_to(_town.road_point(_rng), Then.WAIT))
		_:
			_leave(func() -> void: _head_to(_town.dock_spot(BODY, _rng), Then.WAIT))


func _other_house() -> int:
	var count := _town.house_count()
	if count < 2:
		return -1
	var other := _rng.randi() % (count - 1)
	return other + 1 if other >= _home else other


## Vyjde zpod střechy kolmo ze dveří a pak udělá then. Když přede dveřmi někdo stojí, zkusí
## to za chvíli znovu.
func _leave(then: Callable) -> void:
	var door := _town.door(_home, BODY)
	if _walker.blocked(door, BODY, crowd_id):
		_timer = 0.5
		return
	visible = true
	_travel = 0.0
	if _through_door(_home, false, then):
		return
	position = door
	rotation = _town.door_facing(_home) + PI * 0.5
	then.call()


## Projde dveřmi dovnitř (going_in) nebo ven a pak udělá then. Mezitím je dítětem domu hned za
## stěnami, takže se kreslí nad nimi a pod střechou. false, když domy nejsou nakreslené.
func _through_door(house: int, going_in: bool, then: Callable) -> bool:
	var node := _town.house_node(house)
	if node == null:
		return false
	var inside := _town.inside(house, BODY)
	# Dovnitř jde odtud, kde u dveří stojí, ven zpod střechy ke dveřím.
	_door_from = global_position if going_in else inside
	_door_to = inside if going_in else _town.door(house, BODY)
	_door_t = 0.0
	_after_door = then
	_state = State.DOORWAY
	_stop_pointing()
	reparent(node)
	node.move_child(self, 1)
	# z_index je vůči domu, stejná vrstva jako stěny a střecha, pořadí dětí rozhodne.
	z_index = 0
	global_position = _door_from
	if not going_in:
		global_rotation = _town.door_facing(house) + PI * 0.5
	return true


func _step_door(delta: float) -> void:
	var stride := _speed * delta
	_door_t = minf(_door_t + stride / maxf(_door_from.distance_to(_door_to), 1.0), 1.0)
	global_position = _door_from.lerp(_door_to, _door_t)
	var target := (_door_to - _door_from).angle() + PI * 0.5
	global_rotation = rotate_toward(global_rotation, target, TURN_SPEED * delta)
	_travel += stride
	_figure.set_travel(_travel)
	_footstep(stride)
	if _door_t < 1.0:
		return
	reparent(_host)
	z_index = 1
	_after_door.call()


func _enter(house: int) -> void:
	_home = house
	_state = State.INSIDE
	_timer = HOUSE_PAUSE
	visible = false
	_stop_pointing()
	_figure.set_frame(_figure.idle_frame)


func _head_to_house(house: int) -> void:
	_goal_house = house
	_head_to(_town.door(house, BODY), Then.ENTER)


func _head_to(target: Vector2, then: Then) -> void:
	_target = target
	_then = then
	_state = State.WALKING
	_stall = 0.0
	_stall_tries = 0
	_plan_path()


func _arrive() -> void:
	if _then == Then.ENTER:
		# Kdo to vzdal daleko ode dveří, vejde jen v duchu.
		var near := position.distance_to(_town.door(_goal_house, BODY)) <= BODY * 2.0
		if not near or not _through_door(_goal_house, true, _enter.bind(_goal_house)):
			_enter(_goal_house)
		return
	_state = State.WAITING
	_timer = _rng.randf_range(WAIT.x, WAIT.y)
	_travel = 0.0
	_figure.set_frame(_figure.idle_frame)


# --- Chůze ---

## Cesta po mřížce, narovnaná: z každého bodu rovnou k nejvzdálenějšímu, na který je vidět.
func _plan_path() -> void:
	var raw := _nav.path(position, _target) if _nav != null else PackedVector2Array()
	_routed = not raw.is_empty()
	raw.append(_target)
	_path = PackedVector2Array()
	var from := position
	var i := 0
	while i < raw.size():
		var far := i
		while far + 1 < raw.size() and _nav != null and _nav.clear_line(from, raw[far + 1]):
			far += 1
		_path.append(raw[far])
		from = raw[far]
		i = far + 1
	_path_i = 0


func _walk(delta: float) -> void:
	if _path_i >= _path.size():
		_arrive()
		return
	var aim := _path[_path_i]
	var to := aim - position
	var left := to.length()
	if left <= REACH_PX:
		_path_i += 1
		if _path_i >= _path.size():
			_arrive()
		return
	var dir := to / left
	var stride := minf(_speed * delta, left)
	# Mimo obrazovku jde jen po cestě z mřížky, ta překážky obchází sama. Šetří procesor.
	if _routed and not _on_screen(OFF_SCREEN_M * float(TerrainCatalog.TILE_SIZE)):
		position += dir * stride
		rotation = dir.angle() + PI * 0.5
		_stall = 0.0
		return
	var next := _walker.allowed(position, position + dir * stride, BODY, -1.0, crowd_id)
	var moved := next.distance_to(position)
	position = next
	_face(dir, delta)
	_travel += moved
	_figure.set_travel(_travel)
	_footstep(moved)
	if moved < stride * 0.3:
		_stall += delta
	else:
		_stall = maxf(_stall - delta, 0.0)
	if _stall < STALL_SECONDS:
		return
	_stall = 0.0
	_stall_tries += 1
	if _stall_tries > STALL_TRIES:
		_arrive()
	else:
		_plan_path()


func _face(dir: Vector2, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	rotation = rotate_toward(rotation, dir.angle() + PI * 0.5, TURN_SPEED * delta)


func _footstep(moved: float) -> void:
	_step_travel += moved
	if _step_travel < _figure.cycle_px * 0.5:
		return
	_step_travel = fmod(_step_travel, _figure.cycle_px * 0.5)
	if not _on_screen(0.0):
		return
	var ground := _walker.surface(global_position)
	if STEP_SURFACES.has(ground):
		Sound.at_variant("steps/" + ground, STEP_VARIANTS, global_position, STEP_DB)


## margin obrazovku zvětší o tolik pixelů světa na každou stranu.
func _on_screen(margin: float) -> bool:
	var view := _camera.get_viewport_rect().size / _camera.zoom
	return Rect2(_camera.get_screen_center_position() - view * 0.5, view).grow(margin).has_point(global_position)


# --- Pomoc při honičce ---

## Příšera, které se vesničan staví do cesty, jinak null.
func helping() -> Monster:
	return _helping


## Ve dveřích se přidělit nedá, za chvíli je venku nebo uvnitř.
func can_help() -> bool:
	return _state != State.DOORWAY


## Odkud by k pomoci vyrážel: z domu ode dveří, jinak odtud, kde stojí.
func spot() -> Vector2:
	return _town.door(_home, BODY) if _state == State.INSIDE else position


## Přeruší, co dělá, a běží se postavit příšeře do cesty. Z domu nejdřív vyjde dveřmi.
func help(monster: Monster) -> void:
	_helping = monster
	_stop_pointing()
	if _state != State.INSIDE:
		_start_help()
		return
	visible = true
	_travel = 0.0
	if not _through_door(_home, false, _start_help):
		position = _town.door(_home, BODY)
		_start_help()


## Konec pomoci: zpátky k chůzi a domů.
func stop_helping() -> void:
	_helping = null
	if _state != State.HELPING:
		return
	_figure.set_run(false)
	_figure.set_hold(false)
	_head_to_house(_home)


func _start_help() -> void:
	if _helping == null:
		# Pomoc skončila dřív, než vyšel ze dveří.
		_head_to_house(_home)
		return
	_state = State.HELPING
	_help_on_path = false
	_help_sight = 0.0
	_figure.set_run(true)
	_figure.set_hold(true)


func _step_help(delta: float) -> void:
	if not is_instance_valid(_helping) or _helping.prey() == null:
		stop_helping()
		return
	var tile := float(TerrainCatalog.TILE_SIZE)
	var goal := _helping.position.lerp(_helping.prey().position, HELP_SHARE)
	var aim := goal
	if _nav != null:
		_help_sight -= delta
		if _help_sight <= 0.0:
			_help_sight = HELP_SIGHT
			_help_on_path = false
			if not _nav.clear_line(position, goal):
				_help_path = _nav.path(position, goal)
				_help_i = 0
				_help_on_path = not _help_path.is_empty()
		if _help_on_path:
			while _help_i < _help_path.size() and position.distance_to(_help_path[_help_i]) < HELP_REACH * tile:
				_help_i += 1
			if _help_i < _help_path.size():
				aim = _help_path[_help_i]
	var to := aim - position
	var left := to.length()
	if left <= HELP_ARRIVE_PX:
		_face(_helping.position - position, delta)
		_figure.set_frame(_figure.idle_frame)
		return
	var stride := minf(Person.RUN_METERS * tile * delta, left)
	var next := _walker.allowed(position, position + to / left * stride, BODY, -1.0, crowd_id)
	var moved := next.distance_to(position)
	position = next
	_face(to, delta)
	# Opřený o příšeru stojí, ať nezamrzne v půli kroku.
	if moved < stride * 0.2:
		_figure.set_frame(_figure.idle_frame)
		return
	_travel += moved
	_figure.set_travel(_travel)
	_footstep(moved)


# --- Ukazování ---

## Hlídá hráče v okolí. Vrátí true, dokud vesničan stojí a ukazuje.
func _watch(delta: float) -> bool:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var nearest: Person
	var best := INF
	for person in _persons:
		if not is_instance_valid(person):
			continue
		var dist := position.distance_squared_to(person.position)
		if dist < best:
			best = dist
			nearest = person
	var reach := (POINT_FAR if _pointing else POINT_NEAR) * tile
	if nearest == null or best > reach * reach:
		if _pointing:
			_stop_pointing()
		return false
	_point_at = nearest
	if not _pointing:
		_pointing = true
		_pick_pond()
	_point_check -= delta
	if _point_check <= 0.0:
		_point_check = POINT_CHECK
		if not _rocks.bottomless or (_point_slot >= 0 and not _rocks.ponds_holding(material_index).has(_point_slot)):
			_pick_pond()
	var aim := (_rocks.pond_center(_point_slot) if _point_slot >= 0 else _point_at.position) - position
	_face(aim, delta)
	_figure.set_frame(_figure.idle_frame)
	_show_gem(delta)
	return true


## Nejbližší jezírko, kde leží aspoň jeden kámen. U bezedných jezírek náhodné jezírko
## s materiálem vesničana, ta ho mají pořád.
func _pick_pond() -> void:
	_point_check = POINT_CHECK
	var slots := PackedInt32Array()
	if not _rocks.bottomless:
		slots = _rocks.ponds_with_gems()
	elif material_index >= 0:
		slots = _rocks.ponds_holding(material_index)
	_point_slot = -1
	if slots.is_empty():
		_figure.set_hold(false)
		if _gem != null:
			_gem.visible = false
		return
	if _rocks.bottomless:
		_point_slot = slots[_rng.randi() % slots.size()]
	else:
		var best := INF
		for slot in slots:
			var dist := position.distance_squared_to(_rocks.pond_center(slot))
			if dist < best:
				best = dist
				_point_slot = slot
	_figure.set_hold(true)
	if _gem != null and _crystal != null:
		var mat := material_index if _rocks.bottomless else _rocks.pond_best(_point_slot)
		if mat != _gem_mat:
			_gem_mat = mat
			_crystal.paint(_gem, mat, GEM_HEIGHT, _gem_phase)
		_gem.visible = true
		_pad_gem()


func _stop_pointing() -> void:
	_pointing = false
	_point_slot = -1
	_point_at = null
	_figure.set_hold(false)
	if _gem != null:
		_gem.visible = false


func _show_gem(delta: float) -> void:
	if _gem == null or not _gem.visible:
		return
	_bob = fposmod(_bob + BOB_SPEED * delta, TAU)
	var head := HEAD_LOCAL.rotated(rotation)
	_gem.global_position = global_position + head + Vector2(0.0, -GEM_LIFT - BOB_PX * sin(_bob))


# --- Kreslení ---

func _on_view_changed() -> void:
	var view := _camera.get_viewport_rect().size
	if view != _fitted:
		_fit(view)


func _fit(view: Vector2) -> void:
	_fitted = view
	_figure.fit(view)
	_pad_gem()


func _pad_gem() -> void:
	if _gem == null or _fitted == Vector2.ZERO:
		return
	var on := ObjectLayers.shader_needed(_fitted, _camera.zoom.x, GEM_HEIGHT)
	_gem.set_instance_shader_parameter("height_m", GEM_HEIGHT if on else 0.0)
	if on:
		RenderingServer.canvas_item_set_custom_rect(_gem.get_canvas_item(), true, _gem.get_rect().grow(ObjectLayers.vertex_pad(_fitted, GEM_HEIGHT)))
	else:
		RenderingServer.canvas_item_set_custom_rect(_gem.get_canvas_item(), false, Rect2())


# --- Crowd ---

func crowd_body() -> float:
	return BODY


func crowd_height() -> float:
	return Person.HEIGHT


func crowd_clearance() -> float:
	return -1.0


## Ve dveřích nikomu nepřekáží, jeho position je tou dobou vůči domu.
func crowd_flying() -> bool:
	return _state == State.DOORWAY
