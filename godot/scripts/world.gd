extends Node2D

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
const Monsters := preload("res://scripts/monsters.gd")
const Crowd := preload("res://scripts/crowd.gd")
const Party := preload("res://scripts/party.gd")
const Walker := preload("res://scripts/walker.gd")
const PondLabels := preload("res://scripts/pond_labels.gd")

## Další hráči se objeví v kruhu kolem prvního, tak daleko v metrech.
const SPAWN_RING := 1.5
## Šumění vody: mapa vzdálenosti k vodě po buňkách tolika dlaždic. Do WATER_HEAR metrů od vody
## šumí, u vody nejvíc.
const WATER_CELL := 4
const WATER_HEAR := 14.0
## Odchod do menu chce dva stisky Esc nebo Startu do tolika sekund, ať se neodejde omylem.
const LEAVE_WINDOW := 3.0
## Body za kámen vystoupají od místa dopadu o tolik pixelů obrazovky a za tolik sekund zmizí.
const POINTS_RISE := 70.0
const POINTS_TIME := 1.1
## Posledních tolik sekund limitu tiká.
const TICK_FROM := 10
## Hudba při honičce hraje, když je honící příšera vidět nebo do CHASE_MARGIN metrů za okrajem
## obrazovky. Když zmizí, normální hudba se vrátí až po CHASE_HOLD sekundách. Je to déle než
## klid příšery po krádeži (Monster.CALM_SECONDS), jinak by hudba přeskočila na normální
## a hned zpátky, když příšera honí dalšího hráče se stejným kamenem.
const CHASE_MARGIN := 3.0
const CHASE_HOLD := 6.0

## Jeden obdélník přes celou mapu. Povrch dlaždic kreslí shader z corner_map katalogu.
@onready var ground: Polygon2D = $Ground
@onready var camera: MapCamera = $Camera
@onready var status: Label = $Hint/Hud/Status
## Snímky za sekundu vpravo dole. Engine je přepočítává jednou za sekundu.
@onready var fps: Label = $Hint/Hud/Fps

## Vygenerovaná mapa. Zůstává i po vygenerování, hra z ní čte povrch dlaždic.
var map: MapData

var _map_ready := false
var _task := -1
var _painted := {}
var _crystal: Crystal
var _hud: Hud
## Level a jeho cíl. Čas běží, až je mapa hotová. Body jsou součet kamenů v kotlině.
var _level := 1
var _target := 0
var _time_left := 0.0
var _score := 0
var _playing := false
var _rocks: Rocks
var _persons: Array[Person] = []
var _party: Party
var _monsters: Monsters
## Vzdálenost k vodě v buňkách WATER_CELL dlaždic, po řádcích. Bez vody je pole prázdné.
var _water_far := PackedInt32Array()
var _water_side := 0
var _ticked := -1
var _chase_hold := 0.0
## Kolik sekund ještě druhý stisk Esc nebo Startu opustí hru. 0 je bez prvního stisku.
var _leave_left := 0.0


func _ready() -> void:
	# Kamera na skupinu hráčů až po tom, co se postavy v tomhle snímku pohnuly.
	process_priority = 10
	await get_tree().process_frame
	var catalog := TerrainCatalog.new()
	catalog.load_assets()
	if catalog.names.is_empty():
		status.text = "Chybí terén."
		push_error("Ve složce terénu nejsou žádné povrchy.")
		return
	var rocks := Rocks.new()
	rocks.name = "Rocks"
	add_child(rocks)
	var forest := Forest.new()
	forest.name = "Trees"
	add_child(forest)
	# Textury se načítají tady, generování pak běží ve vlákně a hra mezitím nestojí.
	rocks.load_catalog(catalog.names, catalog.surfaces)
	forest.load_catalog(catalog.names, catalog.surfaces)
	var crystal := Crystal.new()
	if not crystal.load_catalog():
		push_error("Chybí materiály krystalu.")
	rocks.bind_crystal(crystal)
	_level = maxi(GameSession.level, 1)
	_target = GameSession.level_target(_level, GameSession.players.size())
	_time_left = float(GameSession.level_time(_level))
	_crystal = crystal
	rocks.set_available(GameSession.level_materials(_level))
	var size := maxi(GameSession.level_size(_level), 2)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Příšery: mřížky cest a hranice skal se připraví ve vlákně s mapou, samotné příšery
	# vzniknou až potom.
	var monsters := Monsters.new()
	monsters.name = "Monsters"
	add_child(monsters)
	_monsters = monsters
	_task = WorkerThreadPool.add_task(_generate.bind(size, catalog, rng, rocks, forest, crystal, monsters), true, "Generování mapy")
	while not WorkerThreadPool.is_task_completed(_task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1

	var pixels := float(size * TerrainCatalog.TILE_SIZE)
	ground.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(pixels, 0.0), Vector2(pixels, pixels), Vector2(0.0, pixels),
	])
	catalog.set_map(size, _painted["corners"], _painted["variants"])
	catalog.apply(ground)
	_painted.clear()
	var props := Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true
	add_child(props)
	move_child(props, ground.get_index() + 1)
	camera.setup(Vector2(pixels, pixels))
	var chunks := PropChunks.new()
	chunks.name = "PropChunks"
	chunks.setup(camera)
	add_child(chunks)
	rocks.spawn(camera, props, chunks)
	forest.spawn(camera, props, chunks)
	chunks.refresh()
	_spawn_players(rocks, forest, crystal, props)
	var monster_rng := RandomNumberGenerator.new()
	monster_rng.randomize()
	monsters.spawn(rocks.pond_materials(), crystal, _persons[0].walker, rocks, forest, _persons, camera, props, monster_rng)
	var labels := PondLabels.new()
	labels.name = "PondLabels"
	add_child(labels)
	labels.setup(rocks.pond_spots(), crystal, _persons, camera)
	status.visible = false
	var music_rng := RandomNumberGenerator.new()
	music_rng.randomize()
	Sound.play_level_music(music_rng)
	_start_level(rocks)
	_map_ready = true


## Postava za každého hráče. První stojí u středu mapy, další v kruhu kolem ní. Postavy
## a chodící příšery nechodí přes sebe a skupina drží všechny na obrazovce.
func _spawn_players(rocks: Rocks, forest: Forest, crystal: Crystal, props: Node2D) -> void:
	var crowd := Crowd.new()
	_party = Party.new(camera)
	for i in maxi(GameSession.players.size(), 1):
		var person := Person.new()
		person.name = "Person%d" % (i + 1)
		props.add_child(person)
		person.setup(rocks, forest, camera, map, crystal, i)
		person.walker.crowd = crowd
		person.crowd_id = crowd.join(person)
		person.party = _party
		_persons.append(person)
		_party.members.append(person)
	var first := _persons[0].position
	var tile := float(TerrainCatalog.TILE_SIZE)
	for i in range(1, _persons.size()):
		var angle := TAU * float(i - 1) / float(maxi(_persons.size() - 1, 1))
		_persons[i].position = _persons[i]._free_spot(first + Vector2.from_angle(angle) * SPAWN_RING * tile)
	_party.frame()


func _start_level(rocks: Rocks) -> void:
	_rocks = rocks
	_hud = Hud.new()
	_hud.name = "Game"
	$Hint.add_child(_hud)
	_hud.setup(_crystal, _level, _target, GameSession.players)
	_hud.set_time(_time_left)
	_hud.retry_pressed.connect(_restart)
	_hud.menu_pressed.connect(_to_menu)
	_hud.next_pressed.connect(_next_level)
	for person in _persons:
		person.held_changed.connect(_hud.set_held.bind(person.player_index))
	rocks.settled.connect(_on_settled)
	_score = 0
	_playing = true


func _process(delta: float) -> void:
	fps.text = "%d FPS" % Engine.get_frames_per_second()
	_leave_left = maxf(_leave_left - delta, 0.0)
	if _party != null:
		_party.frame()
	if not _playing:
		return
	_point_basin()
	_update_sound(delta)
	_time_left -= delta
	_hud.set_time(_time_left)
	var whole := ceili(_time_left)
	if whole <= TICK_FROM and whole > 0 and whole != _ticked:
		_ticked = whole
		Sound.ui("tick")
	if _time_left <= 0.0:
		_finish(false)


## Šipka v HUD ze středu pohledu ke kotlině, v souřadnicích obrazovky.
## Honící příšera na obrazovce přepne hudbu, blízkost vody řídí šumění.
func _update_sound(delta: float) -> void:
	var margin := CHASE_MARGIN * float(TerrainCatalog.TILE_SIZE)
	if _monsters != null and _monsters.any_chasing_in_view(margin):
		_chase_hold = CHASE_HOLD
	else:
		_chase_hold = maxf(_chase_hold - delta, 0.0)
	Sound.set_chase(_chase_hold > 0.0)
	if _water_far.is_empty():
		Sound.set_water(0.0)
		return
	var center := camera.get_screen_center_position()
	var tile := float(TerrainCatalog.TILE_SIZE)
	var cx := clampi(int(center.x / tile) / WATER_CELL, 0, _water_side - 1)
	var cy := clampi(int(center.y / tile) / WATER_CELL, 0, _water_side - 1)
	var meters := float(_water_far[cy * _water_side + cx] * WATER_CELL)
	Sound.set_water(1.0 - meters / WATER_HEAR)


## Vzdálenost k vodě po hrubých buňkách: vlna z buněk s vodou do okolí. Jednou při startu,
## ve vlákně s generováním mapy.
func _build_water_map(grown: MapData) -> void:
	var water := grown.names.find("water")
	if water < 0:
		return
	_water_side = ceili(float(grown.size) / float(WATER_CELL))
	_water_far.resize(_water_side * _water_side)
	_water_far.fill(-1)
	var queue := PackedInt32Array()
	for index in grown.terrain.size():
		if grown.terrain[index] != water:
			continue
		var cell := (index / grown.size) / WATER_CELL * _water_side + (index % grown.size) / WATER_CELL
		if _water_far[cell] < 0:
			_water_far[cell] = 0
			queue.append(cell)
	if queue.is_empty():
		_water_far = PackedInt32Array()
		return
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var x := cell % _water_side
		var y := cell / _water_side
		for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + side.x
			var ny := y + side.y
			if nx < 0 or ny < 0 or nx >= _water_side or ny >= _water_side:
				continue
			var next := ny * _water_side + nx
			if _water_far[next] < 0:
				_water_far[next] = _water_far[cell] + 1
				queue.append(next)


func _point_basin() -> void:
	var basin := _rocks.basin_position()
	if basin == Vector2.INF:
		_hud.point_basin(Vector2.ZERO, Vector2.INF)
		return
	var to_screen := get_viewport().get_canvas_transform()
	_hud.point_basin(to_screen * camera.get_screen_center_position(), to_screen * basin)


func _on_settled(mat: int, pos: Vector2) -> void:
	if not _playing or _crystal == null:
		return
	_float_points(_crystal.points_of(mat), pos)
	_score += _crystal.points_of(mat)
	_hud.set_score(_score)
	if _score >= _target:
		_finish(true)


## „+N“ u místa dopadu: vystoupá a zmizí. Velikost drží stejnou na obrazovce i při oddálení
## a dohraje i pod oknem výsledku, když tímhle kamenem level skončil.
func _float_points(points: int, pos: Vector2) -> void:
	var holder := Node2D.new()
	holder.position = pos
	holder.z_index = 20
	holder.process_mode = Node.PROCESS_MODE_ALWAYS
	var zoom := camera.zoom.x
	holder.scale = Vector2.ONE / zoom
	var label := Label.new()
	label.text = "+%d" % points
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(0.98, 0.82, 0.4))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	label.add_theme_constant_override("outline_size", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(160, 44)
	label.position = -label.size * 0.5
	holder.add_child(label)
	add_child(holder)
	var tween := holder.create_tween()
	tween.set_parallel(true)
	tween.tween_property(holder, "position:y", pos.y - POINTS_RISE / zoom, POINTS_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(holder, "modulate:a", 0.0, POINTS_TIME * 0.6).set_delay(POINTS_TIME * 0.4)
	tween.chain().tween_callback(holder.queue_free)


## Hra stojí, běží jen okno s výsledkem.
func _finish(won: bool) -> void:
	_playing = false
	get_tree().paused = true
	Sound.duck_music()
	Sound.stop_ambient()
	Sound.ui("win" if won else "lose")
	if won:
		GameSession.unlock(_level + 1)
	_hud.show_result(won, _level, _score, _level >= GameSession.last_level())


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _next_level() -> void:
	GameSession.level = _level + 1
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## Běží ve vlákně. Nesahá na strom scény, jen počítá data.
func _generate(
	size: int,
	catalog: TerrainCatalog,
	rng: RandomNumberGenerator,
	rocks: Rocks,
	forest: Forest,
	crystal: Crystal,
	monsters: Monsters,
) -> void:
	var grown := MapGenerator.grow(size, catalog.names, rng, catalog.max_distance, catalog.max_share)
	grown.surfaces = catalog.surfaces
	_painted = MapGenerator.corner_data(grown, rng, catalog.variant_count)
	rocks.plant(grown, rng)
	forest.plant(grown, rng, rocks)
	# Mřížky cest, hranice skal a mapa vody by jinak zasekly hru na konci načítání.
	var walker := Walker.new(rocks, forest, grown)
	monsters.prepare(rocks.pond_materials(), crystal, walker, rocks, forest)
	rocks.prepare_bounds(Person.BODY)
	_build_water_map(grown)
	map = grown


func _exit_tree() -> void:
	get_tree().paused = false
	Sound.stop_ambient()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Esc nebo Start: první stisk ukáže hlášku, druhý do LEAVE_WINDOW sekund odejde do menu.
func _unhandled_input(event: InputEvent) -> void:
	if not _map_ready or not event.is_action_pressed("game_menu"):
		return
	get_viewport().set_input_as_handled()
	if _leave_left > 0.0:
		Sound.ui("back")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	_leave_left = LEAVE_WINDOW
	if _hud != null:
		_hud.show_notice("Stiskni znovu Esc / Start pro opuštění hry", LEAVE_WINDOW)
