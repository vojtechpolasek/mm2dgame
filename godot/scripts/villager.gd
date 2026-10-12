extends Node2D

## Vesničan. Bydlí v domech u cesty a střídá činnosti se stejnou šancí:
##   zůstane v domě, přejde do jiného domu, zajde na cestu, nebo k výstupku továrny.
## Na cestě a u výstupku postojí WAIT sekund a vrátí se do domu, ze kterého vyšel. Po každém
## vstupu do domu v něm zůstane HOUSE_PAUSE sekund, teprve pak losuje. Zůstat v domě je dalších
## WAIT sekund. V domě ho není vidět a nikomu nepřekáží.
## Když je některý hráč blíž než POINT_NEAR metrů, zastaví se a nataženou rukou ukáže na nejbližší
## jezírko, kde leží jeho materiál (u bezedných jezírek na náhodné z nich). Nad hlavou mu visí
## poloprůhledný kámen toho materiálu. Když jeho materiál už nikde neleží, jen se k hráči otočí.
## Až jsou všichni hráči dál než POINT_FAR, pokračuje v tom, co dělal.
## Grafika je hráčova, chodí atlasem chůze s kratším krokem.

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
## Kámen nad hlavou: kolik metrů nad zemí a kolik pixelů k hornímu okraji obrazovky, ať hlavu
## nezakryje. Pomalu se houpe o BOB_PX.
const GEM_HEIGHT := 2.2
const GEM_LIFT := 30.0
const GEM_ALPHA := 0.65
const GEM_SCALE := 0.8
const BOB_PX := 3.0
const BOB_SPEED := 2.4
const STEP_SURFACES: PackedStringArray = ["grass", "dirt", "desert", "snow"]
const STEP_VARIANTS := 4
const STEP_DB := -14.0
## Barvy kůže. Triko, kalhoty a vlasy jsou ze vzorníku menu postavy.
const SKINS: PackedStringArray = ["F6CDB0", "EDBE98", "D9A27A", "B07850", "8A5A3C"]

enum State { INSIDE, WALKING, WAITING }
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
var _bob := 0.0
var _fitted := Vector2.ZERO


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
	material_index = mat
	_speed = WALK_METERS * float(TerrainCatalog.TILE_SIZE)
	if not _figure.build(self, true, 1.6):
		return false
	_figure.tint(colors)
	_figure.set_frame(_figure.idle_frame)
	# Nad malými objekty, pod velkými, jako hráč.
	z_index = 1
	if crystal != null and mat >= 0:
		_gem = crystal.make_sprite()
		_gem.visible = false
		_gem.z_index = 3
		_gem.scale = Vector2.ONE * GEM_SCALE
		host.add_child(_gem)
		crystal.paint(_gem, mat, GEM_HEIGHT, rng.randf() * TAU)
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
			elif _leave():
				_head_to_house(other)
		2:
			if _leave():
				_head_to(_town.road_point(_rng), Then.WAIT)
		_:
			if _leave():
				_head_to(_town.dock_spot(BODY, _rng), Then.WAIT)


func _other_house() -> int:
	var count := _town.house_count()
	if count < 2:
		return -1
	var other := _rng.randi() % (count - 1)
	return other + 1 if other >= _home else other


## Vyjde ze dveří. Když tam někdo stojí, zkusí to za chvíli znovu.
func _leave() -> bool:
	var door := _town.door(_home, BODY)
	if _walker.blocked(door, BODY, crowd_id):
		_timer = 0.5
		return false
	position = door
	rotation = _town.door_facing(_home) + PI * 0.5
	visible = true
	_travel = 0.0
	return true


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
	var ground := _walker.surface(position)
	if STEP_SURFACES.has(ground):
		Sound.at_variant("steps/" + ground, STEP_VARIANTS, global_position, STEP_DB)


## margin obrazovku zvětší o tolik pixelů světa na každou stranu.
func _on_screen(margin: float) -> bool:
	var view := _camera.get_viewport_rect().size / _camera.zoom
	return Rect2(_camera.get_screen_center_position() - view * 0.5, view).grow(margin).has_point(global_position)


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
		if _point_slot >= 0 and not _rocks.ponds_holding(material_index).has(_point_slot):
			_pick_pond()
	var aim := (_rocks.pond_center(_point_slot) if _point_slot >= 0 else _point_at.position) - position
	_face(aim, delta)
	_figure.set_frame(_figure.idle_frame)
	_show_gem(delta)
	return true


## Nejbližší jezírko s materiálem vesničana. Bezedná mají materiál pořád, tam náhodné.
func _pick_pond() -> void:
	_point_check = POINT_CHECK
	var slots := _rocks.ponds_holding(material_index) if material_index >= 0 else PackedInt32Array()
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
	if _gem != null:
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
	_gem.global_position = global_position + Vector2(0.0, -GEM_LIFT - BOB_PX * sin(_bob))


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


func crowd_small() -> bool:
	return false


func crowd_airborne() -> bool:
	return false


func crowd_flying() -> bool:
	return false
