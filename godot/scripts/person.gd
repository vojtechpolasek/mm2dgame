extends Node2D

## Běh postavy ve středu pohledu. Atlas je cyklus běhu směrem na sever a za ním snímek stání,
## ostatní směry otáčí tenhle uzel.
## Nohy, tělo a hlava jsou tři vrstvy se stejným posunem výšky jako stromy a skály.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const Rocks := preload("res://scripts/rocks.gd")
const Crystal := preload("res://scripts/crystal.gd")
const Forest := preload("res://scripts/forest.gd")
const Town := preload("res://scripts/town.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const MapData := preload("res://scripts/map_data.gd")
const Walker := preload("res://scripts/walker.gd")
const Party := preload("res://scripts/party.gd")
const Figure := preload("res://scripts/figure.gd")

## Co postava drží. -1 je prázdná ruka.
signal held_changed(mat: int)
## Postava vzala kámen mat z jezírka slot.
signal took_gem(slot: int, mat: int)
## Postava hodila kámen do továrny.
signal threw_gem
## Postava se dotkla továrny, ať nese cokoli.
signal touched_factory

## Běh, v metrech za sekundu. Dlaždice je jeden metr.
const RUN_METERS := 4.5
## Na vyšlapaném středu cesty běží postava o tolik rychleji. Příšer se to netýká.
const ROAD_BOOST := 1.2
## Skok je o něco pomalejší než běh a přehraje jen první polovinu snímků.
const JUMP_METERS := RUN_METERS * 0.9
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
const THROW_TIME := 0.45
## Ukradený kámen odletí za tolik sekund zpátky do jezírka, ze kterého ho postava vzala.
const RETURN_TIME := 0.7
## Dotek jezírka vymění kámen hned. Když postava u jezírka zůstane, vymění znovu po tolika
## sekundách, dokud neodejde.
const SWAP_REPEAT := 1.0
const RETURN_ARC := 48.0
## Krok zazní dvakrát za cyklus chůze, při každém dosednutí nohy. Povrchy se zvukem kroků.
const STEP_SURFACES: PackedStringArray = ["grass", "dirt", "desert", "snow"]
const STEP_VARIANTS := 4
const STEP_DB := -6.0
const THROW_ARC := 36.0
## Skafandr ležící na výstupku továrny se vezme, když je střed těla blíž než tolik px navíc.
const SUIT_REACH := 30.0
## Skafandr v ruce je trochu menší než na zemi.
const SUIT_SCALE := 0.8

## Typ hry Skafandry: ukradený kámen zmizí, neletí zpátky do dolu. Kámen ze skladu se ale
## vrátí na svou plochu. Nastaví svět.
var stolen_vanish := false
## Typ hry Skafandry: zavolá se s polohou postavy, která nese skafandr. Vrátí true, když ho
## u dveří domu převzal vesničan. Nastaví svět.
var deliver_suit: Callable

var _rocks: Rocks
var _forest: Forest
var _town: Town
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
var _figure := Figure.new()
var _active := false
var _fitted := Vector2.ZERO
var _crystal: Crystal
var _rng := RandomNumberGenerator.new()
var _hand_height := 1.2
var _held: Sprite2D
var _held_mat := -1
## Jezírko, ze kterého je kámen v ruce. Tam se vrátí, když ho příšera ukradne.
var _held_slot := -1
## Plocha skladu (Town.store_bay), ze které je kámen v ruce, nebo -1. Tam se vrátí po krádeži.
var _held_bay := -1
## Jezírko, kterého se postava právě dotýká, a za kolik sekund u něj vymění znovu.
var _touch_slot := -1
var _touch_left := 0.0
## Plocha skladu, které se postava právě dotýká. Odpočet sdílí s jezírkem.
var _touch_bay := -1
var _flyer: Sprite2D
var _fly_from := Vector2.ZERO
var _fly_to := Vector2.ZERO
var _fly_rot := 0.0
var _fly_spin := 0.0
var _fly_age := 0.0
var _fly_height := 0.0
## Výška, kam kámen dopadne: plošina továrny.
var _fly_floor := 0.0
var _fly_mat := -1
## Zásobník továrny Skafandrů, kam kámen letí, -1 obyčejný pás.
var _fly_lane := -1
## Kámen se do továrny nikam nevejde, po dopadu se rozplyne.
var _fly_discard := false
## Prázdný skafandr v ruce.
var _suit: Sprite2D
## Továrna, do které kámen letí. Přechod na jiný čtverec ji nezmění.
var _fly_town: Town
## Čtverec, ve kterém postava bere a odkládá kameny. Nula znamená jednu mapu bez světa.
var _square_origin := Vector2.ZERO
var _square_span := 0.0
## Dotýkala se postava v minulém snímku továrny? Dotyk se ohlásí jen na začátku.
var _at_factory := false


func setup(rocks: Rocks, forest: Forest, town: Town, camera: MapCamera, map: MapData, crystal: Crystal, player: int = 0) -> void:
	player_index = player
	_device = int(GameSession.player_colors(player).get("device", 0))
	_rocks = rocks
	_forest = forest
	_town = town
	_camera = camera
	_crystal = crystal
	_rng.randomize()
	walker = Walker.new(rocks, forest, town, map)
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
	if not _jumping and Controls.jump_pressed(_device):
		_begin_jump(direction)
	if _jumping:
		_step_jump(delta)
	elif _escaping or _stuck_now(direction, delta):
		_step_escape(delta)
	else:
		_step_run(delta, direction)
	if _flyer != null:
		_advance_throw(delta)
	_carry(delta)
	var touching := _town != null and _town.touches_factory(position, BODY)
	if touching and not _at_factory:
		touched_factory.emit()
	_at_factory = touching


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


## První polovina snímků, jeden krok, pomalejší než běh. Nízké skály a keře se přeskočí.
func _step_jump(delta: float) -> void:
	_jump_time += delta
	var phase := clampf(_jump_time / JUMP_TIME, 0.0, 1.0)
	var half := maxi(_figure.frames / 2, 1)
	_figure.set_frame(mini(int(phase * float(half)), half - 1))
	var speed := JUMP_METERS * float(TerrainCatalog.TILE_SIZE)
	var next := _leashed(walker.allowed(position, position + _jump_dir * speed * delta, BODY, JUMP_CLEAR, crowd_id))
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


func _step_run(delta: float, direction: Vector2) -> void:
	var max_speed := RUN_METERS * float(TerrainCatalog.TILE_SIZE)
	if _town != null and _town.on_road(position):
		max_speed *= ROAD_BOOST
	if direction != Vector2.ZERO:
		_velocity += direction * ACCELERATION * delta
		if _velocity.length() > max_speed:
			_velocity = _velocity.limit_length(max_speed)
	else:
		_velocity = _velocity.move_toward(Vector2.ZERO, STOP_SPEED * delta)
	# Stojící postava zůstane, kde je. Krok by ji jen znovu prověřil proti všem překážkám.
	var next := position
	if _velocity != Vector2.ZERO:
		next = _leashed(walker.allowed(position, position + _velocity * delta, BODY, -1.0, crowd_id))
	var step := next - position
	position = next
	# Sever v atlasu je záporné Y. Kladné otočení uzlu jde po směru hodin.
	var facing := step if step.length_squared() > 0.25 else direction
	if facing.length_squared() > 0.0001:
		rotation = facing.angle() + PI * 0.5
	if direction == Vector2.ZERO and _velocity.length_squared() < 1.0:
		_travel = 0.0
		_figure.set_frame(_figure.idle_frame)
	else:
		_travel += step.length()
		_figure.set_travel(_travel)
		_footstep(step.length())


## Krok podle povrchu pod postavou, dvakrát za cyklus chůze.
func _footstep(moved: float) -> void:
	_step_travel += moved
	if _step_travel < _figure.cycle_px * 0.5:
		return
	_step_travel = fmod(_step_travel, _figure.cycle_px * 0.5)
	var ground := walker.surface(position)
	if STEP_SURFACES.has(ground):
		Sound.at_variant("steps/" + ground, STEP_VARIANTS, global_position, STEP_DB)


## Krok oříznutý vodítkem skupiny, ať se všichni vejdou na obrazovku. Kdyby oříznutí postavu
## posadilo do překážky, zůstane stát.
func _leashed(next: Vector2) -> Vector2:
	if party == null:
		return next
	var held := party.leash(self, next)
	if held.distance_squared_to(next) < 0.01:
		return next
	return position if walker.blocked(held, BODY, crowd_id) else held


## Stojí postava uvnitř překážky nebo na vodě? Překážka by ji posunula, voda neunese.
func _stuck() -> bool:
	return _blocked(position)


## Stuck pro každý snímek pohybu. Stojící postava se ptá jen po IDLE_CHECK sekundách.
func _stuck_now(direction: Vector2, delta: float) -> bool:
	if direction != Vector2.ZERO or _velocity != Vector2.ZERO:
		_idle_check_left = 0.0
		return _stuck()
	_idle_check_left -= delta
	if _idle_check_left > 0.0:
		return false
	_idle_check_left = IDLE_CHECK
	return _stuck()


func _blocked(pos: Vector2) -> bool:
	return walker.blocked(pos, BODY, crowd_id)


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


## Nejbližší místo, kde postava nikde nezavazí a stojí na souši. Když nic není,
## zkusí místo, kam by se objevila na začátku.
func _free_spot(from: Vector2) -> Vector2:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var spot := walker.free_spot(from, BODY, ESCAPE_REACH * tile, ESCAPE_STEP, crowd_id)
	return _spawn_at() if spot == Vector2.INF else spot


## Nejbližší suché místo k začátku (před továrnou), které není v překážce ani ve vodě.
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
	if _flyer != null:
		_pad_gem(_flyer, _fly_height)
	if _suit != null and view != Vector2.ZERO:
		ObjectLayers.fit_sprite(_suit, _suit.material as ShaderMaterial, _hand_height, view, true)


func _attach_hand() -> void:
	if _crystal == null or _crystal.count() == 0:
		return
	_held = _crystal.make_sprite()
	_held.visible = false
	_held.position = PALM
	add_child(_held)


## Továrna vezme nesený kámen. Jezírko ho vymění za svůj nejdražší kámen, prázdné jezírko si ho
## nechá a ruka zůstane prázdná. Hned při doteku a potom každých SWAP_REPEAT sekund, dokud
## postava u jezírka stojí, takže u prázdného jezírka se kámen střídavě odloží a vezme.
func _carry(delta: float) -> void:
	if _flyer != null or _crystal == null or _crystal.count() == 0 or _held == null:
		return
	if not _inside_square():
		return
	if _suit != null:
		if deliver_suit.is_valid() and deliver_suit.call(position):
			_drop_suit()
		elif _town != null and _town.suit_factory() != null and _town.suit_factory().cleared() and _town.suit_factory().at_dock(position, BODY):
			# Vzduch je čistý, skafandr patří zpátky na výstupek.
			_town.suit_factory().store_suit()
			_drop_suit()
		return
	if _held_mat < 0 and _town != null and _town.suit_factory() != null and _town.suit_factory().take_suit(position, BODY + SUIT_REACH):
		_take_suit()
		return
	if _held_mat >= 0 and _town != null and _town.touches_factory(position, BODY):
		_touch_slot = -1
		if _town.suit_factory() == null:
			_throw()
			return
		# Zásobník na straně, u které postava stojí. Když tu kámen nikdo nechce, zůstane v ruce,
		# ať ho postava donese na správnou stranu. Když ho nechce nikdo v celé továrně, odletí
		# na nejbližší zásobník a rozplyne se.
		var lane := _town.claim_lane(position, _held_mat)
		if lane >= 0:
			_throw(lane)
		elif not _town.suit_factory().wanted(_held_mat):
			_throw(_town.suit_factory().nearest_lane(position), true)
		return
	if _touch_store(delta):
		return
	var slot := _rocks.pond_at(position, BODY, _held_mat >= 0)
	if slot < 0:
		_touch_slot = -1
		return
	if slot == _touch_slot:
		_touch_left -= delta
		if _touch_left > 0.0:
			return
	_touch_slot = slot
	_touch_left = SWAP_REPEAT
	var held := _held_mat
	var mat := _rocks.swap_gem(slot, held)
	if mat >= 0:
		_take(slot, mat)
	elif held >= 0:
		_put_down()


## Plocha skladu se chová jako jezírko, jen drží jediný kámen. Vrátí true, když se postava
## nějaké plochy dotýká.
func _touch_store(delta: float) -> bool:
	var bay := _town.store_bay(position, BODY) if _town != null else -1
	if bay < 0:
		_touch_bay = -1
		return false
	_touch_slot = -1
	if bay == _touch_bay:
		_touch_left -= delta
		if _touch_left > 0.0:
			return true
	_touch_bay = bay
	_touch_left = SWAP_REPEAT
	var held := _held_mat
	var mat := _town.swap_store(bay, held)
	if mat >= 0:
		_take(-1, mat)
		_held_bay = bay
	elif held >= 0:
		_put_down()
	return true


## Nese prázdný skafandr?
func carries_suit() -> bool:
	return _suit != null


## Stav k uložení: kde stojí a co nese. Kámen v letu už patří továrně.
func snapshot() -> Dictionary:
	return {"pos": position, "rot": rotation, "held": _held_mat, "bay": _held_bay, "suit": _suit != null}


## Obnoví stav ze snapshot.
func restore(data: Dictionary) -> void:
	position = data.get("pos", position)
	rotation = float(data.get("rot", rotation))
	var held := int(data.get("held", -1))
	if held >= 0:
		_take(-1, held)
		_held_bay = int(data.get("bay", -1))
	if bool(data.get("suit", false)) and _suit == null:
		_take_suit()


## Dýchací přístroj na zádech postavy.
func wear_gear(on: bool) -> void:
	_figure.set_gear(on)
	_fit(_fitted)


## V ruce je prázdný skafandr. Příšery ho nekradou, carried() je pořád -1.
func _take_suit() -> void:
	_suit = Figure.gear_item(_hand_height)
	if _suit == null:
		return
	_suit.position = PALM + Vector2(-4.0, -6.0)
	_suit.scale = Vector2.ONE * SUIT_SCALE
	add_child(_suit)
	_set_hold(true)
	Sound.at("sfx/pickup", global_position, -3.0)


## Skafandr si vzal vesničan, ruka je prázdná.
func _drop_suit() -> void:
	_suit.queue_free()
	_suit = null
	_set_hold(false)
	Sound.at("sfx/pickup", global_position, -3.0)


## Kámen zůstal v prázdném jezírku, ruka je prázdná.
func _put_down() -> void:
	_held.visible = false
	_held_mat = -1
	_held_slot = -1
	_held_bay = -1
	_set_hold(false)
	held_changed.emit(-1)
	Sound.at("sfx/pickup", global_position, -3.0)


## Pro crowd: postava je kruh o poloměru trupu, ve skoku přeskočí tvory do JUMP_CLEAR metrů.
func crowd_body() -> float:
	return BODY


func crowd_height() -> float:
	return HEIGHT


func crowd_clearance() -> float:
	return JUMP_CLEAR if _jumping else -1.0


func crowd_flying() -> bool:
	return false


## Materiál v ruce, -1 je prázdná ruka.
func carried() -> int:
	return _held_mat


## Příšera kámen sebrala. Odletí zpátky do svého jezírka, ruka je prázdná.
func drop_held() -> void:
	if _held_mat < 0:
		return
	Sound.at("sfx/steal", global_position)
	if stolen_vanish and _held_bay < 0:
		_held.visible = false
		_held_mat = -1
		_held_slot = -1
		_held_bay = -1
		_set_hold(false)
		held_changed.emit(-1)
		return
	_send_back()


## Kámen z ruky odletí obloukem do jezírka nebo na plochu skladu, odkud ho postava vzala.
## Až dopadne, jezírku přibude, plocha ho zase drží.
func _send_back() -> void:
	var mat := _held_mat
	var slot := _held_slot
	var bay := _held_bay
	var town := _town
	var start := _held.global_position
	_held.visible = false
	_held_mat = -1
	_held_slot = -1
	_held_bay = -1
	_set_hold(false)
	held_changed.emit(-1)
	var host := get_parent() as Node2D
	if host == null or (slot < 0 and bay < 0):
		_land_home(null, slot, mat, bay, town)
		return
	var gem := _crystal.make_sprite()
	host.add_child(gem)
	gem.global_position = start
	gem.z_index = 3
	_crystal.paint(gem, mat, _hand_height, 0.0)
	_pad_gem(gem, _hand_height)
	var spin := (-1.0 if _rng.randf() < 0.5 else 1.0) * TAU * _rng.randf_range(0.75, 1.6)
	var tween := gem.create_tween()
	var home := town.bay_home(bay) if bay >= 0 else _rocks.gem_home(slot)
	tween.tween_method(_fly_home.bind(gem, gem.position, home, spin), 0.0, 1.0, RETURN_TIME)
	tween.tween_callback(_land_home.bind(gem, slot, mat, bay, town))


func _fly_home(t: float, gem: Sprite2D, from: Vector2, to: Vector2, spin: float) -> void:
	var eased := 1.0 - pow(1.0 - t, 2.0)
	var way := to - from
	var pos := from.lerp(to, eased)
	if way.length_squared() > 1.0:
		pos += way.orthogonal().normalized() * sin(t * PI) * signf(spin) * minf(RETURN_ARC, way.length() * 0.25)
	gem.position = pos
	gem.rotation = spin * eased
	_pad_gem(gem, lerpf(_hand_height, 0.0, eased))


func _land_home(gem: Sprite2D, slot: int, mat: int, bay: int, town: Town) -> void:
	if gem != null:
		gem.queue_free()
	if bay >= 0 and town != null:
		town.store_gem(bay, mat)
	else:
		_rocks.return_gem(slot, mat)


## V ruce je kámen mat z jezírka slot. Stejný kámen jako předtím jen změní jezírko, kam se
## vrátí po krádeži, a nezazní.
func _take(slot: int, mat: int) -> void:
	_held_slot = slot
	_held_bay = -1
	if mat == _held_mat:
		return
	_held_mat = mat
	_held.position = PALM
	_held.rotation = 0.0
	_held.visible = true
	_crystal.paint(_held, mat, _hand_height, 0.4)
	_set_hold(true)
	held_changed.emit(mat)
	Sound.at("sfx/pickup", global_position, -3.0)
	if slot >= 0:
		took_gem.emit(slot, mat)


func leave_square() -> void:
	if _held_mat >= 0 and _held_bay >= 0 and _town != null:
		_town.store_gem(_held_bay, _held_mat)
	elif _held_mat >= 0 and _rocks != null:
		_rocks.return_gem(_held_slot, _held_mat)
	if _held_mat >= 0:
		if _held != null:
			_held.visible = false
		_held_mat = -1
		_held_slot = -1
		_held_bay = -1
		_set_hold(false)
		held_changed.emit(-1)
	_touch_slot = -1
	_touch_bay = -1
	_touch_left = 0.0


## Jezírka a továrna čtverce, na který postava právě přišla.
func use_square(rocks: Rocks, town: Town, origin: Vector2, span: float) -> void:
	_rocks = rocks
	_town = town
	_square_origin = origin
	_square_span = span


func _inside_square() -> bool:
	if _square_span <= 0.0:
		return true
	var local := position - _square_origin
	return local.x >= 0.0 and local.y >= 0.0 and local.x < _square_span and local.y < _square_span


## lane je zásobník továrny Skafandrů, -1 obyčejný pás.
func _throw(lane: int = -1, discard: bool = false) -> void:
	var host := get_parent() as Node2D
	if host == null or _held == null or _held_mat < 0 or _town == null or _town.center() == Vector2.INF:
		return
	var mat := _held_mat
	var start := _held.global_position
	var rot := _held.global_rotation
	_held.visible = false
	_held_mat = -1
	_held_slot = -1
	_held_bay = -1
	_set_hold(false)
	held_changed.emit(-1)
	var flyer := _crystal.make_sprite()
	host.add_child(flyer)
	flyer.global_position = start
	flyer.global_rotation = rot
	flyer.z_index = 3
	_crystal.paint(flyer, mat, _hand_height, rot)
	var sign := -1.0 if _rng.randf() < 0.5 else 1.0
	_flyer = flyer
	_fly_from = flyer.position
	_fly_town = _town
	_fly_lane = lane
	_fly_discard = discard
	_fly_to = _fly_town.lane_drop(lane, _rng) if lane >= 0 else _fly_town.drop_spot(position, _rng)
	_fly_rot = flyer.rotation
	_fly_spin = sign * TAU * _rng.randf_range(0.75, 1.6)
	_fly_age = 0.0
	_fly_height = _hand_height
	_fly_floor = _town.deck_height()
	_fly_mat = mat
	_pad_gem(flyer, _hand_height)
	threw_gem.emit()


func _advance_throw(delta: float) -> void:
	_fly_age += delta
	var t := clampf(_fly_age / THROW_TIME, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 3.0)
	var pos := _fly_from.lerp(_fly_to, eased)
	var delta_pos := _fly_to - _fly_from
	if delta_pos.length_squared() > 1.0:
		var bend := 1.0 if _fly_spin >= 0.0 else -1.0
		pos += delta_pos.orthogonal().normalized() * sin(t * PI) * bend * minf(THROW_ARC, delta_pos.length() * 0.22)
	_flyer.position = pos
	_flyer.rotation = _fly_rot + _fly_spin * eased
	_fly_height = lerpf(_hand_height, _fly_floor, eased)
	_pad_gem(_flyer, _fly_height)
	if t < 1.0:
		return
	var mat := _fly_mat
	var rot := _flyer.rotation
	var landed := _fly_to
	_flyer.visible = false
	_flyer.queue_free()
	_flyer = null
	var town := _fly_town if _fly_town != null else _town
	if town != null and _fly_discard:
		town.discard(mat, landed, rot)
	elif town != null:
		town.receive(mat, landed, rot, _fly_lane)


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
