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
## dveřmi a běží (RUN_METERS) na místo HELP_SHARE cesty od příšery k honěné postavě. Ruku má
## nataženou. Příšera přes něj neprojde, musí ho obejít. Po honičce jde domů.
## Grafika je hráčova, chodí atlasem chůze s kratším krokem, při pomoci běží atlasem běhu.
## Typ hry Skafandry: venku je jedovatý vzduch. Vesničan bez skafandru (needs_suit) zůstává
## doma a nepomáhá. Když mu hráč donese skafandr (dress), vyjde v něm ven a dělá všechno
## jako jindy. Když je vzduch čistý (return_suit), dojde skafandr odložit k výstupku továrny.
## Ve Skafandrech ukazuje na důl nejlevnějšího materiálu, který továrně ještě chybí, ten nejblíž
## k továrně. Hráč, který se ho dotkne, si ho vezme s sebou (sledování): vesničan běží za ním
## a cíl přepočítá po FOLLOW_CHECK sekundách. Když hráč vezme kámen z dolu, vesničan dojde
## ke stejnému dolu a vezme si stejný materiál. Když se hráč dotkne továrny (i bez kamene),
## vesničan s kamenem dojde ke stejné straně a hodí ho tam, kam se vejde (jinde, když tam ne).
## Pak a také když kámen ztratí, přestane sledovat a jde domů. Vesničan bez kamene přestane
## sledovat, když hráč do továrny hodí. Vesničan s kamenem je pro příšery jako
## hráč. Při sledování nepomáhá.

## Vesničan odložil skafandr u výstupku.
signal suit_returned

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
const SuitFactory := preload("res://scripts/suit_factory.gd")

## Chůze je poloviční rychlost běhu hráče.
const WALK_METERS := Person.RUN_METERS * 0.5
## Běh vesničana (při pomoci i při sledování hráče) je o pětinu pomalejší než běh hráče.
const RUN_METERS := Person.RUN_METERS * 0.8
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
## Pomoc při honičce: cílové místo je tenhle díl cesty od příšery k honěné postavě. Místo se
## přepočítá po HELP_SIGHT sekundách, ať vesničan nereaguje na každý úkrok příšery. Zároveň se
## ověří přímá cesta k němu, když nevede, běží po mřížce. U cíle stojí a dívá se na příšeru.
const HELP_SHARE := 0.2
const HELP_SIGHT := 0.5
const HELP_ARRIVE_PX := 6.0
## Bod cesty mřížky je při pomoci dosažený na tolik dlaždic.
const HELP_REACH := 0.6
## Barvy kůže. Triko, kalhoty a vlasy jsou ze vzorníku menu postavy.
const SKINS: PackedStringArray = ["F6CDB0", "EDBE98", "D9A27A", "B07850", "8A5A3C"]
## Sledování hráče: dotyk těl s rezervou TOUCH_PX, běží rychlostí RUN_METERS,
## zastaví se FOLLOW_NEAR metrů od hráče. Kam běžet, se přepočítá po FOLLOW_CHECK sekundách.
const TOUCH_PX := 6.0
const FOLLOW_NEAR := 1.5
const FOLLOW_CHECK := 0.5
## Vůdce stojí a vesničan u něj s prázdnou rukou: po tolika sekundách ukáže k dolu.
const REST_POINT := 1.0
## Hod kamene do továrny trvá tolik sekund.
const THROW_TIME := 0.45
## Oblečený vesničan vyjde z domu, až žádný hráč není blíž ke dveřím než tolik metrů.
## Jinak by se hned dotkl hráče, který mu skafandr přinesl. Znovu se podívá po DOOR_RECHECK s.
const DOOR_CLEAR := 2.0
const DOOR_RECHECK := 0.3

enum State { INSIDE, WALKING, WAITING, DOORWAY, HELPING, FOLLOWING }
## Při sledování: jen za hráčem, pro kámen do dolu, nebo s kamenem k továrně.
enum Task { NONE, MINE, FACTORY }
enum Then { ENTER, WAIT, DROP }

## Číslo mezi tvory, kteří nechodí přes sebe. Nastaví správce vesničanů.
var crowd_id := -1
## Materiál, na který vesničan ukazuje.
var material_index := -1
## Barvy oblečení a kůže, ať jde vesničan uložit.
var clothes := {}
## Bez skafandru nesmí ven. Nastaví správce vesničanů v typu hry Skafandry.
var needs_suit := false
var _suited := false
## Jde odložit skafandr na _drop_at.
var _returning := false
var _drop_at := Vector2.ZERO
## Právě dostal skafandr a vyjde ven, jakmile mu nikdo nestojí ve dveřích.
var _go_out := false
## Továrna Skafandrů. Jen s ní vesničan ukazuje na chybějící materiál a dá se vzít s sebou.
var suits: SuitFactory
## Kdo nese kámen, pro příšery. Pole sdílí správce příšer.
var carriers: Array = []
var _leader: Person
var _task := Task.NONE
var _task_slot := -1
var _task_mat := -1
var _task_lane := -1
## Kámen se do továrny nikam nevejde. Vesničan ho donese k nejbližšímu zásobníku a tam
## se rozplyne.
var _discard := false
## Kámen v ruce při sledování, -1 nic.
var _carry_mat := -1
var _carry: Sprite2D
var _follow_left := 0.0
var _follow_aim := Vector2.ZERO
var _follow_path := PackedVector2Array()
var _follow_i := 0
## Jak dlouho vesničan stojí u vůdce, který se nehýbe, a kde vůdce stál minule.
var _rest := 0.0
var _leader_last := Vector2.ZERO

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
var _help_goal := Vector2.ZERO
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
	clothes = colors
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
		Crystal.tune(_gem, &"alpha", GEM_ALPHA)
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


## Kámen nad hlavou visí v hostiteli, ne ve vesničanovi. Zmizí s ním, jinak by ve světě
## s mnoha čtverci zabral instanční uniformy, kterých je na celou hru jen pár tisíc.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_gem):
		_gem.queue_free()


func _process(delta: float) -> void:
	if _returning and _state != State.DOORWAY:
		_step_return(delta)
		return
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
	if _state == State.FOLLOWING:
		_step_follow(delta)
		return
	if _touched():
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
	if _go_out:
		if _door_crowded():
			_timer = DOOR_RECHECK
			return
		_leave(_out_to_road)
		return
	if needs_suit and not _suited:
		_timer = _rng.randf_range(WAIT.x, WAIT.y)
		return
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
	if _then == Then.DROP:
		_take_off()
		return
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


## Ve dveřích se přidělit nedá, za chvíli je venku nebo uvnitř. Bez skafandru ven nesmí
## a kdo nese skafandr k výstupku, nepomáhá.
func can_help() -> bool:
	return _state != State.DOORWAY and _state != State.FOLLOWING and not (needs_suit and not _suited) and not _returning


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
	_help_sight -= delta
	if _help_sight <= 0.0:
		_help_sight = HELP_SIGHT
		_help_goal = _helping.position.lerp(_helping.prey().position, HELP_SHARE)
		_help_on_path = false
		if _nav != null and not _nav.clear_line(position, _help_goal):
			_help_path = _nav.path(position, _help_goal)
			_help_i = 0
			_help_on_path = not _help_path.is_empty()
	var aim := _help_goal
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
	var stride := minf(RUN_METERS * tile * delta, left)
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


# --- Skafandr ---

## Je doma v domě house a čeká na skafandr?
func waits_in(house: int) -> bool:
	return needs_suit and not _suited and _state == State.INSIDE and _home == house


## Hráč donesl skafandr ke dveřím. Vesničan si ho obleče a vyjde ven na cestu.
func dress() -> void:
	_suited = true
	_figure.set_gear(true)
	_fit(_fitted)
	_go_out = true
	_timer = 0.0


## Stojí některý hráč u dveří domu?
func _door_crowded() -> bool:
	var door := _town.door(_home, BODY)
	var reach := DOOR_CLEAR * float(TerrainCatalog.TILE_SIZE) + Person.BODY
	for person in _persons:
		if is_instance_valid(person) and person.position.distance_squared_to(door) < reach * reach:
			return true
	return false


func _out_to_road() -> void:
	_go_out = false
	_head_to(_town.road_point(_rng), Then.WAIT)


func suited() -> bool:
	return _suited


## Vzduch je čistý. Ve skafandru ho dojde odložit před výstupek továrny, bez něj může hned ven.
func return_suit() -> void:
	if _state == State.FOLLOWING:
		_stop_follow()
	needs_suit = false
	if not _suited:
		if _state == State.INSIDE:
			_timer = minf(_timer, _rng.randf_range(0.2, 2.0))
		return
	_returning = true
	_drop_at = _town.dock_spot(BODY, _rng)
	_timer = 0.0


## Cesta k výstupku. Z domu vyjde dveřmi, odjinud rovnou, cokoli dělal předtím.
func _step_return(delta: float) -> void:
	if _state == State.INSIDE:
		_timer -= delta
		if _timer <= 0.0:
			_timer = 0.5
			_leave(_go_drop)
		return
	if _state != State.WALKING or _then != Then.DROP:
		_go_drop()
	_walk(delta)


func _go_drop() -> void:
	_stop_pointing()
	_helping = null
	_figure.set_run(false)
	_figure.set_hold(false)
	_head_to(_drop_at, Then.DROP)


func _take_off() -> void:
	_suited = false
	_returning = false
	_figure.set_gear(false)
	_fit(_fitted)
	Sound.at("sfx/pickup", global_position, -3.0)
	_state = State.WAITING
	_then = Then.WAIT
	_timer = _rng.randf_range(WAIT.x, WAIT.y)
	_travel = 0.0
	_figure.set_frame(_figure.idle_frame)
	suit_returned.emit()


# --- Uložení ---

## Dům, materiál a barvy: s nimi se vesničan po načtení objeví znovu.
func origin() -> Dictionary:
	return {"home": _home, "mat": material_index, "colors": clothes}


## Stav k uložení. Ve dveřích se počítá jako venku přede dveřmi. persons jsou postavy hráčů,
## vůdce se ukládá jako pořadí mezi nimi.
func snapshot(persons: Array[Person]) -> Dictionary:
	var place := "outside"
	if _state == State.INSIDE:
		place = "inside"
	elif _state == State.FOLLOWING:
		place = "follow"
	var pos := _town.door(_home, BODY) if _state == State.DOORWAY else global_position
	var out := origin()
	out.merge({
		"suited": _suited,
		"go_out": _go_out,
		"returning": _returning,
		"place": place,
		"pos": pos,
		"rot": global_rotation,
		"leader": persons.find(_leader) if is_instance_valid(_leader) else -1,
		"carry": _carry_mat,
		"task": int(_task),
		"task_slot": _task_slot,
		"task_mat": _task_mat,
	})
	return out


## Obnoví stav ze snapshot. Kdo byl venku, stojí na svém místě a za chvíli jde domů. Kdo
## sledoval hráče, sleduje ho dál a nese, co nesl. Volá se po lock_inside.
func restore(data: Dictionary, persons: Array[Person]) -> void:
	if bool(data.get("suited", false)):
		_suited = true
		_figure.set_gear(true)
		_fit(_fitted)
	_go_out = bool(data.get("go_out", false))
	if _go_out:
		_timer = 0.0
	var place := str(data.get("place", "inside"))
	if place != "inside":
		visible = true
		position = data.get("pos", position)
		rotation = float(data.get("rot", rotation))
		_state = State.WAITING
		_then = Then.WAIT
		_timer = _rng.randf_range(0.5, WAIT.x)
		_figure.set_frame(_figure.idle_frame)
	if bool(data.get("returning", false)):
		_returning = true
		_drop_at = _town.dock_spot(BODY, _rng)
		_timer = 0.0
		return
	var leader := int(data.get("leader", -1))
	if place != "follow" or suits == null or leader < 0 or leader >= persons.size():
		return
	_start_follow(persons[leader])
	var carry := int(data.get("carry", -1))
	if carry >= 0:
		_task_mat = carry
		_take_stone()
	var task := int(data.get("task", Task.NONE))
	if task == Task.MINE and carry < 0:
		_task = Task.MINE
		_task_slot = int(data.get("task_slot", -1))
		_task_mat = int(data.get("task_mat", -1))
	elif task == Task.FACTORY and carry >= 0:
		_task = Task.FACTORY
		_task_lane = -1
		_pick_lane(position)


# --- Sledování hráče ---

## Dotkl se ho hráč? Pak ho začne sledovat. Jen venku, ve skafandru a ve Skafandrech.
func _touched() -> bool:
	if suits == null or suits.cleared() or not _suited or _returning or _helping != null:
		return false
	var reach := BODY + Person.BODY + TOUCH_PX
	for person in _persons:
		if is_instance_valid(person) and position.distance_squared_to(person.position) <= reach * reach:
			_start_follow(person)
			return true
	return false


func _start_follow(person: Person) -> void:
	_leader = person
	_leader_last = person.position
	_rest = 0.0
	_state = State.FOLLOWING
	_task = Task.NONE
	_follow_left = 0.0
	_stop_pointing()
	_figure.set_run(true)
	_figure.set_hold(false)


## Kdo nese kámen. Příšery to čtou u hráčů i vesničanů.
func carried() -> int:
	return _carry_mat


## Vůdce vzal kámen z dolu slot. Kdo kámen nemá a nic jiného nedělá, dojde si pro stejný.
func leader_took(slot: int, mat: int, person: Person) -> void:
	if _state != State.FOLLOWING or _leader != person or _carry_mat >= 0 or _task != Task.NONE:
		return
	_task = Task.MINE
	_task_slot = slot
	_task_mat = mat
	_follow_left = 0.0


## Vůdce hodil kámen do továrny. Bez kamene vesničan přestane sledovat, s kamenem jde
## k továrně (to už spustil dotyk továrny).
func leader_threw(person: Person) -> void:
	if _state != State.FOLLOWING or _leader != person:
		return
	if _carry_mat < 0:
		_stop_follow()
		return
	leader_touched(person)


## Vůdce se dotkl továrny. Vesničan s kamenem jde ke stejné straně a hodí ho tam.
func leader_touched(person: Person) -> void:
	if _state != State.FOLLOWING or _leader != person or _carry_mat < 0 or _task == Task.FACTORY:
		return
	_task_lane = -1
	_pick_lane(person.position)
	_task = Task.FACTORY
	_follow_left = 0.0


## Zásobník, kam vesničan nese kámen: dosavadní, dokud ho chce, jinak kterýkoli, kam se
## vejde, nejblíž k near. Když se nevejde nikam, nejbližší zásobník a kámen se tam rozplyne.
func _pick_lane(near: Vector2) -> void:
	if _task_lane >= 0 and suits.accepts(_task_lane, _carry_mat):
		_discard = false
		return
	var lane := suits.lane_for_carrier(near, _carry_mat)
	_discard = lane < 0
	_task_lane = lane if lane >= 0 else suits.nearest_lane(near)


## Příšera kámen sebrala. Zmizí a vesničan přestane sledovat.
func drop_held() -> void:
	if _carry_mat < 0:
		return
	Sound.at("sfx/steal", global_position)
	_stop_follow()


func _stop_follow() -> void:
	_end_rest()
	_drop_carry()
	_leader = null
	_task = Task.NONE
	_figure.set_run(false)
	_figure.set_hold(false)
	_head_to_house(_home)


func _drop_carry() -> void:
	_carry_mat = -1
	carriers.erase(self)
	if _carry != null:
		_carry.visible = false


func _step_follow(delta: float) -> void:
	if not is_instance_valid(_leader) or suits.cleared():
		_stop_follow()
		return
	_follow_left -= delta
	if _follow_left <= 0.0:
		_follow_left = FOLLOW_CHECK
		_aim_follow()
		if _state != State.FOLLOWING:
			return
	if _task == Task.MINE and _rocks.pond_at(position, BODY) == _task_slot:
		_take_stone()
		return
	if _task == Task.FACTORY and _town.touches_factory(position, BODY):
		_throw_stone()
		return
	var tile := float(TerrainCatalog.TILE_SIZE)
	var goal := _follow_aim if _task != Task.NONE else _leader.position
	if _task == Task.NONE and position.distance_to(goal) <= FOLLOW_NEAR * tile:
		if _rest_point(delta):
			return
		_face(goal - position, delta)
		_figure.set_frame(_figure.idle_frame)
		return
	_end_rest()
	var aim := goal
	while _follow_i < _follow_path.size() and position.distance_to(_follow_path[_follow_i]) < HELP_REACH * tile:
		_follow_i += 1
	if _follow_i < _follow_path.size():
		aim = _follow_path[_follow_i]
	# U dolu už rovnou k němu, okraj ho zastaví a dotkne se ho.
	if _task == Task.MINE and position.distance_to(goal) < FOLLOW_NEAR * tile:
		aim = _rocks.pond_center(_task_slot)
	var to := aim - position
	var left := to.length()
	if left < 0.5:
		return
	var stride := minf(RUN_METERS * tile * delta, left)
	var next := _walker.allowed(position, position + to / left * stride, BODY, -1.0, crowd_id)
	var moved := next.distance_to(position)
	position = next
	_face(to, delta)
	if moved < stride * 0.2:
		_figure.set_frame(_figure.idle_frame)
		return
	_travel += moved
	_figure.set_travel(_travel)
	_footstep(moved)


## Vůdce stojí a vesničan je u něj s prázdnou rukou. Po REST_POINT sekundách ukáže k dolu
## jako vesničan, který nikoho nesleduje. true, dokud ukazuje.
func _rest_point(delta: float) -> bool:
	var still := _leader.position.distance_squared_to(_leader_last) < 0.01
	_leader_last = _leader.position
	if not still or _carry_mat >= 0:
		_end_rest()
		return false
	_rest += delta
	if _rest < REST_POINT:
		return false
	if not _pointing:
		_pointing = true
		_point_at = _leader
		_pick_pond()
	_point(delta)
	return true


## Vůdce se pohnul nebo je třeba jít: vesničan přestane ukazovat.
func _end_rest() -> void:
	_rest = 0.0
	if _pointing:
		_stop_pointing()


## Kam teď: za vůdcem, k dolu, nebo před zásobník. Cesta po mřížce, když na cíl není vidět.
func _aim_follow() -> void:
	match _task:
		Task.MINE:
			_follow_aim = _rocks.pond_edge(_task_slot, position, BODY)
		Task.FACTORY:
			_pick_lane(position)
			_follow_aim = suits.lane_front(_task_lane, BODY)
		_:
			_follow_aim = _leader.position
	_follow_path = PackedVector2Array()
	_follow_i = 0
	if _nav != null and not _nav.clear_line(position, _follow_aim):
		_follow_path = _nav.path(position, _follow_aim)


func _take_stone() -> void:
	_carry_mat = _task_mat
	_task = Task.NONE
	_follow_left = 0.0
	if _carry == null and _crystal != null:
		_carry = _crystal.make_sprite()
		_carry.position = Person.PALM
		add_child(_carry)
	if _carry != null:
		_crystal.paint(_carry, _carry_mat, 0.0, 0.4)
		_carry.visible = true
	_figure.set_hold(true)
	if not carriers.has(self):
		carriers.append(self)
	Sound.at("sfx/pickup", global_position, -3.0)


## Hodí kámen do zásobníku, ke kterému šel. Když se tam už nevejde a nikam jinam taky ne,
## kámen zmizí. Když se vejde jinam, jde tam.
func _throw_stone() -> void:
	var was := _task_lane
	_pick_lane(position)
	if _task_lane != was and suits.lane_front(_task_lane, BODY).distance_to(position) > FOLLOW_NEAR * float(TerrainCatalog.TILE_SIZE):
		_follow_left = 0.0
		return
	var mat := _carry_mat
	var lane := _task_lane
	var discard := _discard
	if not discard:
		suits.claim(lane, mat)
	var flyer := _crystal.make_sprite()
	_host.add_child(flyer)
	flyer.global_position = _carry.global_position
	flyer.z_index = 3
	_crystal.paint(flyer, mat, 0.0, 0.4)
	var drop := _town.lane_drop(lane, _rng)
	var town := _town
	var tween := flyer.create_tween()
	tween.tween_property(flyer, "global_position", drop, THROW_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(flyer, "rotation", _rng.randf_range(2.0, 6.0), THROW_TIME)
	# Dopadne na plošinu továrny, ta je výš.
	tween.parallel().tween_method(func(height: float) -> void: Crystal.tune(flyer, &"height_m", height), 0.0, _town.deck_height(), THROW_TIME)
	tween.tween_callback(func() -> void:
		var rot := flyer.rotation
		flyer.queue_free()
		if discard:
			town.discard(mat, drop, rot)
		else:
			town.receive(mat, drop, rot, lane)
	)
	_stop_follow()


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
	_point(delta)
	return true


## Ukazuje: otočí se k jezírku (bez něj k hráči), nad hlavou kámen. Jezírko po POINT_CHECK
## sekundách vybere znovu.
func _point(delta: float) -> void:
	_point_check -= delta
	if _point_check <= 0.0:
		_point_check = POINT_CHECK
		if suits != null or not _rocks.bottomless or (_point_slot >= 0 and not _rocks.ponds_holding(material_index).has(_point_slot)):
			_pick_pond()
	var aim := (_rocks.pond_center(_point_slot) if _point_slot >= 0 else _point_at.position) - position
	_face(aim, delta)
	_figure.set_frame(_figure.idle_frame)
	_show_gem(delta)


## Nejbližší jezírko, kde leží aspoň jeden kámen. U bezedných jezírek náhodné jezírko
## s materiálem vesničana, ta ho mají pořád. Ve Skafandrech důl nejlevnějšího materiálu,
## který továrně chybí, ten nejblíž k továrně.
func _pick_pond() -> void:
	_point_check = POINT_CHECK
	var slots := PackedInt32Array()
	var wanted := -1
	if suits != null:
		var missing := suits.missing()
		if not missing.is_empty():
			wanted = missing[0]
			slots = _rocks.ponds_holding(wanted)
	elif not _rocks.bottomless:
		slots = _rocks.ponds_with_gems()
	elif material_index >= 0:
		slots = _rocks.ponds_holding(material_index)
	_point_slot = -1
	if slots.is_empty():
		_figure.set_hold(false)
		if _gem != null:
			_gem.visible = false
		return
	if suits != null:
		var best := INF
		for slot in slots:
			var dist := _town.center().distance_squared_to(_rocks.pond_center(slot))
			if dist < best:
				best = dist
				_point_slot = slot
	elif _rocks.bottomless:
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
		var mat := wanted if suits != null else material_index if _rocks.bottomless else _rocks.pond_best(_point_slot)
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
	Crystal.tune(_gem, &"height_m", GEM_HEIGHT if on else 0.0)
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
