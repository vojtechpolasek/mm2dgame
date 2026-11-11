extends Node2D

## Běh postavy ve středu pohledu. Atlas je cyklus běhu směrem na sever a za ním snímek stání,
## ostatní směry otáčí tenhle uzel.
## Nohy, tělo a hlava jsou tři vrstvy se stejným posunem výšky jako stromy a skály.
## Evoluce: hráč je příšera (wear). Místo figurky se kreslí příšera-loutka (Monster.puppet),
## tělo, rychlost, skok a kroky jsou její. Létající letí nad vším, jen ne nad nehotový čtverec.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const Rocks := preload("res://scripts/rocks.gd")
const Crystal := preload("res://scripts/crystal.gd")
const Forest := preload("res://scripts/forest.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const MapData := preload("res://scripts/map_data.gd")
const Walker := preload("res://scripts/walker.gd")
const Party := preload("res://scripts/party.gd")
const Figure := preload("res://scripts/figure.gd")
const Splashes := preload("res://scripts/splashes.gd")
const Benchmark := preload("res://scripts/benchmark.gd")

## Co postava drží a kolik bodů za to hráči dostali. mat -1 je prázdná ruka.
signal held_changed(mat: int, points: int)

## Běh, v metrech za sekundu. Dlaždice je jeden metr.
const RUN_METERS := 4.5
## Skok je stejně rychlý jako běh po terénu pod postavou a přehraje jen první polovinu snímků.
const JUMP_TIME := 0.7
## Přes tohle se ve skoku přenese. Balvan má 1,1 m, keř 1,2 m. Skály od 6 m a stromy ne.
const JUMP_CLEAR := 1.5
## Výška postavy v metrech. Skákající tvor ji přeskočí, když skočí aspoň takhle vysoko.
const HEIGHT := 1.8
## Ve skoku se postava zvětší až o tolik, uprostřed skoku nejvíc. Vypadá to, že se odlepí od země.
const JUMP_GROW := 0.15
## Jak daleko postava uběhne za jeden cyklus běhu.
const CYCLE_METERS := 3.0
## Poloměr trupu. Do skály a do vody se počítá tělo, ne dosah kroku.
const BODY := 16.0
## Chodidlo od středu postavy v px: do strany a dopředu. Odtud cáká voda.
const FOOT_SIDE := 6.0
const FOOT_AHEAD := 6.0
const ACCELERATION := 2200.0
const STOP_SPEED := 3800.0
## Když postava skončí v překážce nebo ve vodě (dopad skoku, souběh dvou překážek), vysune se
## na nejbližší volné místo touto rychlostí v metrech za sekundu. Hledá nejdál ESCAPE_REACH metrů.
const ESCAPE_METERS := 6.0
const ESCAPE_REACH := 8.0
const ESCAPE_STEP := 6.0
## Stojící postava kontroluje, jestli nestojí v překážce, jen po tolika sekundách.
## Sama se nehýbe a ostatní tvorové se jí vyhýbají sami.
const IDLE_CHECK := 0.2
## Dlaň z tools/gen_person.py, HOLD_PALM. Záporné Y je dopředu, jako v atlasu.
const PALM := Vector2(16.0, -16.0)
## Ukázat nesený kámen v natažené ruce? Vypnuté: postava kámen nese neviditelně, bez natažené ruky,
## carried() a held_changed platí dál.
const SHOW_HELD := false
## Krok zazní dvakrát za cyklus chůze, při každém dosednutí nohy. Povrchy se zvukem kroků.
## Zvuk kroků podle povrchu. Nové povrchy si půjčují zvuk podobného.
const STEP_SOUNDS := {
	"grass": "grass", "dirt": "dirt", "desert": "desert", "snow": "snow",
	"heath": "heath", "swamp": "swamp", "scree": "scree", "ash": "ash",
}
## Ve vodě (brod v řece, mělčina) se místo kroku ozve šplouchnutí, o kousek hlasitější.
const WADE_SOUND := "steps/water"
const WADE_DB := 2.0
const STEP_VARIANTS := 4
const STEP_DB := -6.0

var _rocks: Rocks
var _forest: Forest
var _camera: MapCamera
var _jumping := false
var _jump_time := 0.0
var _jump_dir := Vector2.ZERO
## Překážky, voda a okraj mapy. Příšery chodí podle téhož.
var walker: Walker
## Číslo postavy mezi tvory, kteří nechodí přes sebe. Nastaví svět.
var crowd_id := -1
## Hráč z GameSession.players: barvy a ovladač.
var player_index := 0
## Skupina hráčů. Drží postavu tak, aby se všichni vešli na obrazovku. Nastaví svět.
var party: Party
var _device := 0
var _velocity := Vector2.ZERO
var _escaping := false
var _idle_check_left := 0.0
var _escape_to := Vector2.ZERO
var _travel := 0.0
var _step_travel := 0.0
## Která noha teď došlápla (cákání ve vodě).
var _left_foot := false
var _figure := Figure.new()
var _active := false
var _fitted := Vector2.ZERO
var _crystal: Crystal
var _rng := RandomNumberGenerator.new()
var _hand_height := 1.2
## Kámen v ruce (Sbírání materiálů) a jeho materiál, -1 prázdná ruka.
var _held: Sprite2D
var _held_mat := -1
## Evoluce: příšera, kterou hráč je (Monster, dítě postavy), a její rychlost v m/s. null je
## obyčejná postava.
var avatar: Node2D
var _avatar_meters := 0.0


func setup(rocks: Rocks, forest: Forest, camera: MapCamera, map: MapData, crystal: Crystal, player: int = 0) -> void:
	player_index = player
	_device = int(GameSession.player_colors(player).get("device", 0))
	_rocks = rocks
	_forest = forest
	_camera = camera
	_crystal = crystal
	Benchmark.seed_rng(_rng, 10 + player)
	walker = Walker.new(rocks, forest, map)
	if not _build():
		return
	_attach_hand()
	# Nad malými objekty, pod velkými. Záporné z by je schovalo pod terén.
	z_index = 1
	position = _spawn_at()
	camera.view_changed.connect(_on_view_changed)
	_fit(camera.get_viewport_rect().size)
	_active = true


func _process(delta: float) -> void:
	if not _active:
		return
	var direction := Controls.direction(_device)
	if not _jumping and Controls.jump_pressed(_device) and _jump_clear() > 0.0:
		_begin_jump(direction)
	if _jumping:
		_step_jump(delta)
	elif _escaping or _stuck_now(direction, delta):
		_step_escape(delta)
	else:
		_step_run(delta, direction)


func _begin_jump(direction: Vector2) -> void:
	var dir := direction
	if dir.length_squared() < 0.01:
		dir = _velocity
	if dir.length_squared() < 0.01:
		dir = Vector2.from_angle(rotation - PI * 0.5)
	_jump_dir = dir.normalized()
	_jumping = true
	_jump_time = 0.0
	Sound.at("sfx/jump", global_position, -4.0)


## První polovina snímků, jeden krok, rychlostí běhu. Nízké skály a keře se přeskočí.
func _step_jump(delta: float) -> void:
	_jump_time += delta
	var phase := clampf(_jump_time / JUMP_TIME, 0.0, 1.0)
	if avatar != null:
		avatar.puppet_jump(phase)
	else:
		var half := maxi(_figure.frames / 2, 1)
		_figure.set_frame(mini(int(phase * float(half)), half - 1))
	var speed := _run_speed()
	var next := _leashed(walker.allowed(position, position + _jump_dir * speed * delta, body(), _jump_clear(), crowd_id))
	position = next
	scale = Vector2.ONE * (1.0 + JUMP_GROW * sin(phase * PI))
	if _jump_dir.length_squared() > 0.0:
		rotation = _jump_dir.angle() + PI * 0.5
	if phase >= 1.0:
		_jumping = false
		scale = Vector2.ONE
		# Dopad do překážky se pozná hned, ne až po IDLE_CHECK.
		_idle_check_left = 0.0
		Sound.at("sfx/land", global_position, -3.0)


## Rychlost běhu v pixelech za sekundu na terénu pod postavou: močál a řeka zpomalí.
## Příšera běží svou rychlostí, létající terén nezdrží.
func _run_speed() -> float:
	var tile := float(TerrainCatalog.TILE_SIZE)
	if avatar == null:
		return RUN_METERS * tile * walker.pace(position)
	return _avatar_meters * tile * (1.0 if _flies() else walker.pace(position))


## Evoluce: hráč je příšera look, běží rychlostí meters m/s. Dosavadní příšera se schová.
func wear(look: Node2D, meters: float) -> void:
	if avatar != null and avatar != look:
		avatar.visible = false
	avatar = look
	_avatar_meters = meters
	_figure.set_visible(false)
	look.visible = true
	_escaping = false
	_idle_check_left = 0.0
	if _jumping and _jump_clear() <= 0.0:
		_jumping = false
		scale = Vector2.ONE


## Poloměr těla v px: postava, nebo příšera, kterou hráč je.
func body() -> float:
	return float(avatar.crowd_body()) if avatar != null else BODY


## Letí hráč (příšera, která létá)?
func _flies() -> bool:
	return avatar != null and avatar.is_flying()


## Výška skoku v metrech. Příšera skáče jen jako její druh, létající neskáče.
func _jump_clear() -> float:
	if avatar == null:
		return JUMP_CLEAR
	return 0.0 if _flies() else float(avatar.jump_height())


## Let z from k desired: jen nad hotovými čtverci, jinak podél jejich kraje.
func _fly(from: Vector2, desired: Vector2) -> Vector2:
	var board = walker.world_board
	if board == null:
		return desired
	for spot in [desired, Vector2(desired.x, from.y), Vector2(from.x, desired.y)]:
		if board.has_ground(spot):
			return spot
	return from


func _step_run(delta: float, direction: Vector2) -> void:
	var max_speed := _run_speed()
	if direction != Vector2.ZERO:
		_velocity += direction * ACCELERATION * delta
		if _velocity.length() > max_speed:
			_velocity = _velocity.limit_length(max_speed)
	else:
		_velocity = _velocity.move_toward(Vector2.ZERO, STOP_SPEED * delta)
	# Stojící postava zůstane, kde je. Krok by ji jen znovu prověřil proti všem překážkám.
	var next := position
	if _velocity != Vector2.ZERO and _flies():
		next = _leashed(_fly(position, position + _velocity * delta))
	elif _velocity != Vector2.ZERO:
		next = _leashed(walker.allowed(position, position + _velocity * delta, body(), -1.0, crowd_id))
	var step := next - position
	position = next
	# Sever v atlasu je záporné Y. Kladné otočení uzlu jde po směru hodin.
	var facing := step if step.length_squared() > 0.25 else direction
	if facing.length_squared() > 0.0001:
		rotation = facing.angle() + PI * 0.5
	if avatar != null:
		# Snímky a kroky příšery. Stojící má první snímek, létající mává dál.
		avatar.puppet_step(delta, step)
	elif direction == Vector2.ZERO and _velocity.length_squared() < 1.0:
		_travel = 0.0
		_figure.set_frame(_figure.idle_frame)
	else:
		_travel += step.length()
		_figure.set_travel(_travel)
		_footstep(step.length())


## Krok podle povrchu pod postavou, dvakrát za cyklus chůze. Ve vodě od chodidla cákne
## (Splashes), střídavě od levé a pravé nohy, a místo kroku šplouchne.
func _footstep(moved: float) -> void:
	_step_travel += moved
	if _step_travel < _figure.cycle_px * 0.5:
		return
	_step_travel = fmod(_step_travel, _figure.cycle_px * 0.5)
	_left_foot = not _left_foot
	if Splashes.current != null and Splashes.current.wet(global_position):
		var forward := Vector2.from_angle(rotation - PI * 0.5)
		var side := forward.orthogonal() * (FOOT_SIDE if _left_foot else -FOOT_SIDE)
		Splashes.current.splash(global_position + side + forward * FOOT_AHEAD, forward)
		Sound.at_variant(WADE_SOUND, STEP_VARIANTS, global_position, STEP_DB + WADE_DB)
		return
	var ground := walker.surface(position)
	if STEP_SOUNDS.has(ground):
		Sound.at_variant("steps/" + str(STEP_SOUNDS[ground]), STEP_VARIANTS, global_position, STEP_DB)


## Krok oříznutý vodítkem skupiny, ať se všichni vejdou na obrazovku. Kdyby oříznutí postavu
## posadilo do překážky, zůstane stát.
func _leashed(next: Vector2) -> Vector2:
	if party == null:
		return next
	var held := party.leash(self, next)
	if held.distance_squared_to(next) < 0.01:
		return next
	if _flies():
		return held
	return position if walker.blocked(held, body(), crowd_id) else held


## Stojí postava uvnitř překážky nebo na vodě? Překážka by ji posunula, voda neunese.
func _stuck() -> bool:
	return _blocked(position)


## Stuck pro každý snímek pohybu. Stojící postava se ptá jen po IDLE_CHECK sekundách.
func _stuck_now(direction: Vector2, delta: float) -> bool:
	if _flies():
		return false
	if direction != Vector2.ZERO or _velocity != Vector2.ZERO:
		_idle_check_left = 0.0
		return _stuck()
	_idle_check_left -= delta
	if _idle_check_left > 0.0:
		return false
	_idle_check_left = IDLE_CHECK
	return _stuck()


func _blocked(pos: Vector2) -> bool:
	return walker.blocked(pos, body(), crowd_id)


## Vysouvání ven. Cíl se hledá jednou a drží, dokud platí. Překážky ho cestou nezastaví,
## jinak by z nich postava nevyjela.
func _step_escape(delta: float) -> void:
	if not _escaping or _blocked(_escape_to):
		_escape_to = _free_spot(position)
		_escaping = true
	_velocity = Vector2.ZERO
	var step := ESCAPE_METERS * float(TerrainCatalog.TILE_SIZE) * delta
	position = position.move_toward(_escape_to, step)
	if position.distance_squared_to(_escape_to) < 0.01:
		position = _escape_to
		_escaping = false


## Nejbližší místo, kde postava nikde nezavazí a stojí na souši. Když nic není, hledá
## dál hrubším krokem (příšera, která přestala létat nad jezerem), pak zkusí místo, kam by se
## objevila na začátku.
func _free_spot(from: Vector2) -> Vector2:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var spot := walker.free_spot(from, body(), ESCAPE_REACH * tile, ESCAPE_STEP, crowd_id)
	if spot == Vector2.INF and avatar != null:
		spot = walker.free_spot(from, body(), ESCAPE_REACH * 5.0 * tile, ESCAPE_STEP * 4.0, crowd_id)
	return _spawn_at() if spot == Vector2.INF else spot


## Nejbližší suché místo k začátku (střed mapy), které není v překážce ani ve vodě.
func _spawn_at() -> Vector2:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var tiles := int(walker.world().x / tile)
	var home := walker.home()
	var hx := clampi(int(home.x / tile), 0, tiles - 1)
	var hy := clampi(int(home.y / tile), 0, tiles - 1)
	for radius in tiles:
		var y0 := maxi(hy - radius, 0)
		var y1 := mini(hy + radius, tiles - 1)
		var x0 := maxi(hx - radius, 0)
		var x1 := mini(hx + radius, tiles - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if radius > 0 and y != y0 and y != y1 and x != x0 and x != x1:
					continue
				var pos := home if radius == 0 else Vector2((float(x) + 0.5) * tile, (float(y) + 0.5) * tile)
				var landed := walker.place(pos, BODY)
				if walker.stands(landed, BODY):
					return landed
	return walker.place(Vector2(tile * 0.5, tile * 0.5), BODY)


func _build() -> bool:
	if not _figure.build(self, false, CYCLE_METERS):
		return false
	_hand_height = _figure.hand_height
	# Kalhoty, triko a vlasy z menu. Ostatní barvy zůstanou z katalogu.
	_figure.tint(GameSession.player_colors(player_index))
	return true


func _on_view_changed() -> void:
	var view := _camera.get_viewport_rect().size
	if view == _fitted:
		return
	_fit(view)


func _fit(view: Vector2) -> void:
	_fitted = view
	_figure.fit(view)
	if _held != null and _held.visible:
		_pad_gem(_held, _hand_height)


func _attach_hand() -> void:
	if _crystal == null or _crystal.count() == 0:
		return
	_held = _crystal.make_sprite()
	_held.visible = false
	_held.position = PALM
	add_child(_held)


## Pro crowd: postava je kruh o poloměru trupu, ve skoku přeskočí tvory do JUMP_CLEAR metrů.
func crowd_body() -> float:
	return body()


func crowd_height() -> float:
	return float(avatar.crowd_height()) if avatar != null else HEIGHT


func crowd_clearance() -> float:
	return _jump_clear() if _jumping else -1.0


func crowd_flying() -> bool:
	return _flies()


## Materiál v ruce, -1 je prázdná ruka.
func carried() -> int:
	return _held_mat


## Kámen materiálu mat do ruky, hráči za něj dostali points bodů.
func hold(mat: int, points: int) -> void:
	if _held == null:
		return
	_held_mat = mat
	if SHOW_HELD:
		_held.position = PALM
		_held.rotation = 0.0
		_held.visible = true
		_crystal.paint(_held, mat, _hand_height, 0.4)
		_set_hold(true)
	held_changed.emit(mat, points)


## Prázdná ruka: příšera kámen vzala, nebo už nehoní a kámen je hráčův.
func drop_held() -> void:
	if _held_mat < 0:
		return
	_held_mat = -1
	if SHOW_HELD:
		_held.visible = false
		_set_hold(false)
	held_changed.emit(-1, 0)


func _set_hold(on: bool) -> void:
	_figure.set_hold(on)
	_fit(_fitted)


func _pad_gem(sprite: Sprite2D, height: float) -> void:
	var on := height > 0.0 and _fitted != Vector2.ZERO and ObjectLayers.shader_needed(_fitted, _camera.zoom.x, height)
	Crystal.tune(sprite, &"height_m", height if on else 0.0)
	if on:
		var rect := sprite.get_rect()
		RenderingServer.canvas_item_set_custom_rect(sprite.get_canvas_item(), true, rect.grow(ObjectLayers.vertex_pad(_fitted, height)))
	else:
		RenderingServer.canvas_item_set_custom_rect(sprite.get_canvas_item(), false, Rect2())
