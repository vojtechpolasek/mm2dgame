extends Node2D

## Jedna příšera. Pomalu se toulá po mapě, a když některá postava nese materiál příšery, honí
## odkudkoli rychlostí honičky tu nejbližší. Dotek kámen sebere a příšera se vrátí k toulání.
## Chodící obchází překážky stejně jako postava a nechodí přes jiné tvory. Létající letí nad vším
## a z mapy nevyletí. Druh s jump_meters přeskočí překážky a tvory do té výšky jako postava.
## Atlas je nakreslený směrem na sever, ostatní směry otáčí tenhle uzel.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const Walker := preload("res://scripts/walker.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const Person := preload("res://scripts/person.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")

## Dosah chňapnutí v metrech navíc k tělům. Postava přitisknutá k překážce jinak nejde dosáhnout.
const BITE := 0.6
## Po krádeži si příšera tolik sekund postavy nevšímá, ať ji hned znovu nehoní.
const CALM_SECONDS := 3.0
## Toulání: další cíl je tak daleko v metrech, u něj chvíli postojí.
const WANDER_NEAR := 4.0
const WANDER_FAR := 14.0
const REST_MIN := 1.0
const REST_MAX := 3.5
## Když toulání tolik sekund skoro nepostupuje (překážka, voda), zkusí jiný cíl.
const STALL_SECONDS := 1.2
## Honička jde přímo na postavu, dokud mezi nimi v mřížce cest nic nestojí. Viditelnost se
## ověřuje po SIGHT_EVERY sekundách. Když něco stojí, příšera jde po cestě kolem překážek
## a přepočítává ji po PATH_REPLAN sekundách. Zasekne-li se na cestě, přeskočí bod a cestu
## přepočítá. Když cesta není, uhne na chvíli do strany pod úhlem, každý další neúspěch
## zkusí druhou stranu a větší úhel.
const SIGHT_EVERY := 0.5
const PATH_REPLAN := 1.0
## Na kolik dlaždic se příšera přiblíží k bodu cesty, než jde k dalšímu.
const PATH_REACH := 0.6
## Kolik bodů cesty dopředu se hledá ten nejbližší.
const PATH_LOOKAHEAD := 16
const DETOUR_STALL := 0.5
const DETOUR_MIN := 1.0
const DETOUR_MAX := 2.5
const DETOUR_ANGLES: Array[float] = [1.2, 1.7, 2.3]
## Létající drží od okraje mapy aspoň tolik metrů.
const FLY_MARGIN := 4.0
## Natáčení za směrem pohybu v radiánech za sekundu.
const TURN_SPEED := 7.0
## Skok jako u postavy: první polovina snímků chůze, uprostřed skoku zvětšení o JUMP_GROW.
## Ve skoku je příšera JUMP_BOOST krát rychlejší než právě běží. Než skočí, najde místo přistání
## za překážkou, nejdál JUMP_REACH metrů. Když je za ním volno, doskočí dál, ať skok trvá aspoň
## JUMP_TIME sekund. Kratší skok trvá kratší dobu, rychlost zůstane.
const JUMP_TIME := 0.7
const JUMP_BOOST := 1.1
const JUMP_GROW := 0.15
const JUMP_REACH := 10.0
const JUMP_STEP := 0.25
## Hlasitost kroků podle druhu v dB. Chodící dupne dvakrát za cyklus, létající mávne jednou.
const STEP_DB := {"had": -12.0, "pavouk": -10.0, "vlk": -6.0, "tyranosaurus": 0.0, "ptakojester": -5.0}
const STEP_VARIANTS := 3
## Hudba při honičce začne se zařváním, až je honící příšera na obrazovce. Pak hraje, dokud je
## příšera vidět nebo nejdál CHASE_KEEP metrů za okrajem, ať hudba u okraje nepřeskakuje.
const CHASE_KEEP := 3.0
## Vysunutí z překážky jako u postavy, v metrech a pixelech.
const ESCAPE_METERS := 4.0
const ESCAPE_REACH := 10.0
const ESCAPE_STEP := 8.0

## Materiál příšery. Honí postavu, která ho nese.
var material_index := -1
## Druh příšery (pavouk, vlk, ...), podle něj zní kroky a zařvání. Nastaví správce příšer.
var kind_name := ""
## Číslo mezi tvory, kteří nechodí přes sebe. Nastaví správce příšer.
var crowd_id := -1

var _walker: Walker
var _nav: NavGrid
var _path := PackedVector2Array()
var _path_i := 0
var _on_path := false
var _replan_left := 0.0
var _sight_left := 0.0
var _persons: Array[Person] = []
## Další, kdo může nést kámen (vesničané, kteří sledují hráče). Pole sdílí správce příšer,
## každý v něm má carried(), drop_held() a position jako postava.
var carriers: Array = []
## Kdo nese materiál příšery a ta ho právě honí: postava, nebo kdo z carriers. null, když
## materiál nikdo nenese.
var _prey: Node2D
var _camera: MapCamera
var _rng: RandomNumberGenerator
var _flying := false
var _wander_px := 64.0
var _chase_px := 320.0
var _body := 24.0
var _touch := 40.0
var _cycle_px := 64.0
var _frames := 8
var _sprites: Array[Sprite2D] = []
var _heights := PackedFloat32Array()
var _target := Vector2.ZERO
var _resting := false
var _rest_left := 0.0
var _calm_left := 0.0
var _stall_time := 0.0
var _chase_stall := 0.0
var _detour_left := 0.0
var _detour_side := 1.0
var _detour_tries := 0
var _travel := 0.0
var _escaping := false
var _escape_to := Vector2.ZERO
var _fitted := Vector2.ZERO
var _active := false
var _height := 1.0
var _jump_clear := 0.0
var _jumping := false
var _jump_from := Vector2.ZERO
var _jump_to := Vector2.ZERO
var _jump_t := 0.0
var _jump_dur := 0.0
var _step_travel := 0.0
## Zařvala už v téhle honičce? Zařve, až je honící příšera poprvé na obrazovce.
var _roared := false
## Patří honička k hudbě? Zapne se se zařváním, vypne, když příšera přestane honit nebo odejde z obrazovky.
var _in_view := false


## info je druh z monsters.json, textures vrstvy podle pořadí klíčů, colors klíče body, accent, eye.
## speed násobí rychlost honičky druhu, dražší materiál má rychlejší příšeru.
func setup(
	info: Dictionary,
	textures: Array[Texture2D],
	shared: ShaderMaterial,
	colors: Dictionary,
	speed: float,
	shadow_alpha: float,
	walker: Walker,
	nav: NavGrid,
	persons: Array[Person],
	camera: MapCamera,
	rng: RandomNumberGenerator,
	at: Vector2,
) -> void:
	_walker = walker
	_nav = nav
	_persons = persons
	_camera = camera
	_rng = rng
	var tile := float(TerrainCatalog.TILE_SIZE)
	_flying = bool(info.get("flying", false))
	_wander_px = float(info.get("wander_meters", 1.0)) * tile
	_chase_px = float(info.get("chase_meters", 5.0)) * tile * speed
	_body = float(info.get("body_meters", 0.4)) * tile
	_touch = _body + Person.BODY + BITE * tile
	_cycle_px = maxf(float(info.get("cycle_meters", 1.0)) * tile, 1.0)
	_frames = maxi(int(info.get("frames", 8)), 1)
	_height = float(info.get("height_meters", 1.0))
	_jump_clear = float(info.get("jump_meters", 0.0))
	# Chodící mezi postavou a vysokými skalami, létající nad vším.
	z_index = 4 if _flying else 1
	var columns := maxi(int(info.get("atlas_columns", _frames)), 1)
	var listed: Dictionary = info.get("layers", {})
	var keys: Array = listed.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for i in keys.size():
		var layer: Dictionary = listed[keys[i]]
		var sprite := Sprite2D.new()
		sprite.texture = textures[i]
		sprite.hframes = columns
		sprite.vframes = maxi(ceili(float(_frames) / float(columns)), 1)
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# Vlastní materiál: instanční uniformy stačí v renderu Compatibility jen na pár stovek objektů.
		var material := shared.duplicate() as ShaderMaterial
		sprite.material = material
		var height := float(layer.get("height", 0.0))
		material.set_shader_parameter("height_m", height)
		material.set_shader_parameter("body_color", colors["body"])
		material.set_shader_parameter("accent_color", colors["accent"])
		material.set_shader_parameter("eye_color", colors["eye"])
		if bool(layer.get("shadow", false)):
			material.set_shader_parameter("shadow_alpha", shadow_alpha)
			# Stín leží na zemi pod postavou, i když tvor letí nad vším.
			sprite.z_as_relative = false
			sprite.z_index = 0
		add_child(sprite)
		_sprites.append(sprite)
		_heights.append(height)
	position = at
	rotation = _rng.randf() * TAU
	_pick_target()
	camera.view_changed.connect(_on_view_changed)
	_fit(camera.get_viewport_rect().size)
	_active = true


func _process(delta: float) -> void:
	if not _active:
		return
	_calm_left = maxf(_calm_left - delta, 0.0)
	_prey = _carrier() if _calm_left <= 0.0 else null
	if _prey == null:
		_roared = false
	elif not _roared and _on_screen():
		_roared = true
		Sound.at("monsters/%s_roar" % kind_name, global_position, 2.0)
	var keep := CHASE_KEEP * float(TerrainCatalog.TILE_SIZE) if _in_view else 0.0
	_in_view = _roared and _on_screen(keep)
	if _jumping:
		_step_jump(delta)
		if _prey != null:
			_bite()
		return
	var before := position
	if _prey != null:
		_chase(delta)
	else:
		_on_path = false
		_wander(delta)
	_animate(delta, position - before)


func _chase(delta: float) -> void:
	_resting = false
	var aim := _prey.position
	if _nav != null:
		_sight_left -= delta
		if _sight_left <= 0.0:
			_sight_left = SIGHT_EVERY
			var open := _nav.clear_line(position, _prey.position)
			if open:
				_on_path = false
			elif not _on_path:
				_plan()
				_on_path = not _path.is_empty()
		if _on_path:
			_replan_left -= delta
			if _replan_left <= 0.0:
				_plan()
			aim = _path_aim()
	var to := aim - position
	if to.length() > 0.001:
		var step := minf(_chase_px * delta, to.length())
		var dir := to.normalized()
		if _detour_left > 0.0:
			_detour_left -= delta
			dir = dir.rotated(_detour_side * DETOUR_ANGLES[mini(_detour_tries, DETOUR_ANGLES.size() - 1)])
		var moved := _move(dir * step)
		if not _jumping:
			_track_chase(delta, moved, step)
	_bite()


## Nejbližší postava nebo vesničan, kdo nese materiál příšery. Když nikdo, null.
func _carrier() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for group: Array in [_persons, carriers]:
		for holder: Variant in group:
			if not is_instance_valid(holder):
				continue
			var body := holder as Node2D
			if holder.carried() != material_index:
				continue
			if _walker != null and not _walker.contains(body.position):
				continue
			var dist := position.distance_squared_to(body.position)
			if dist < best_dist:
				best_dist = dist
				best = body
	return best


func _bite() -> void:
	if _walker != null and not _walker.contains(_prey.position):
		return
	if position.distance_to(_prey.position) <= _touch:
		var holder: Variant = _prey
		holder.drop_held()
		_calm_left = CALM_SECONDS
		_pick_target()


## Zasekne-li se honička, začne objížďka. Když se zasekne i objížďka, zkusí druhou stranu
## a větší úhel. Po úspěšném kusu cesty se počítání neúspěchů vynuluje.
func _track_chase(delta: float, moved: float, step: float) -> void:
	if _flying:
		return
	if moved >= step * 0.3:
		_chase_stall = 0.0
		if _detour_left <= 0.0:
			_detour_tries = 0
		return
	_chase_stall += delta
	if _chase_stall < DETOUR_STALL:
		return
	_chase_stall = 0.0
	if _nav != null and _detour_left <= 0.0:
		if _on_path and _path_i < _path.size():
			# Bod cesty je za překážkou, na kterou mřížka nestačí. Další bod a nová cesta.
			_path_i += 1
			_replan_left = 0.0
			_detour_tries += 1
			if _detour_tries < 3:
				return
		elif not _on_path:
			_plan()
			_on_path = not _path.is_empty()
			if _on_path:
				return
	if _detour_left > 0.0:
		_detour_tries += 1
		_detour_side = -_detour_side
	else:
		_detour_side = -1.0 if _rng.randf() < 0.5 else 1.0
	_detour_left = _rng.randf_range(DETOUR_MIN, DETOUR_MAX)


func _plan() -> void:
	_path = _nav.path(position, _prey.position) if _nav != null else PackedVector2Array()
	_path_i = 0
	_replan_left = PATH_REPLAN


## Další bod cesty. Nejdřív najde nejbližší bod z pár následujících (po skoku může příšera
## stát za několika body), pak přeskočí ty, ke kterým už došla. Za koncem cesty míří na postavu.
func _path_aim() -> Vector2:
	var reach := maxf(PATH_REACH * float(TerrainCatalog.TILE_SIZE), _body)
	var nearest := _path_i
	for j in range(_path_i, mini(_path_i + PATH_LOOKAHEAD, _path.size())):
		if position.distance_squared_to(_path[j]) < position.distance_squared_to(_path[nearest]):
			nearest = j
	_path_i = nearest
	while _path_i < _path.size() and position.distance_to(_path[_path_i]) < reach:
		_path_i += 1
	return _path[_path_i] if _path_i < _path.size() else _prey.position


func _wander(delta: float) -> void:
	if _resting:
		_rest_left -= delta
		if _rest_left <= 0.0:
			_pick_target()
		return
	var to := _target - position
	var step := _wander_px * delta
	if to.length() <= step:
		_move(to)
		if _flying:
			_pick_target()
		else:
			_rest()
		return
	var moved := _move(to.limit_length(step))
	if moved < step * 0.3:
		_stall_time += delta
		if _stall_time > STALL_SECONDS:
			_pick_target()
	else:
		_stall_time = 0.0


## Posun o offset. Vrátí, kolik pixelů příšera opravdu ušla.
func _move(offset: Vector2) -> float:
	var before := position
	if _flying:
		var margin := FLY_MARGIN * float(TerrainCatalog.TILE_SIZE)
		position = _walker.fit(position + offset, margin)
	elif _escaping or _walker.blocked(position, _body, crowd_id):
		_escape()
	else:
		position = _walker.allowed(position, position + offset, _body, -1.0, crowd_id)
		# Klouzání podél překážky do strany se za postup nepočítá. Překážku přes kterou
		# vede cesta, je potřeba přeskočit.
		var forward := (position - before).dot(offset.normalized())
		if forward < offset.length() * 0.5 and _try_jump(offset.normalized()):
			position = before
			return 0.0
	return position.distance_to(before)


## Skok přes nízkou překážku nebo malého tvora ve směru dir. Skočí, jen když za překážkou najde
## místo přistání a cestou není nic vyššího, voda ani okraj mapy.
func _try_jump(dir: Vector2) -> bool:
	if _jump_clear <= 0.0 or _flying or dir == Vector2.ZERO:
		return false
	var tile := float(TerrainCatalog.TILE_SIZE)
	var step := JUMP_STEP * tile
	var along := step
	while along <= JUMP_REACH * tile:
		var spot := position + dir * along
		if not _walker.stands(spot, _body):
			return false
		if _walker.place(spot, _body, _jump_clear, crowd_id).distance_squared_to(spot) > 0.25:
			return false
		if along >= _body and not _walker.blocked(spot, _body, crowd_id):
			var speed := (_chase_px if _prey != null else _wander_px) * JUMP_BOOST
			var landing := along
			while landing + step <= speed * JUMP_TIME and _landing_free(position + dir * (landing + step)):
				landing += step
			_jumping = true
			_jump_from = position
			_jump_to = position + dir * landing
			_jump_t = 0.0
			_jump_dur = landing / speed
			rotation = dir.angle() + PI * 0.5
			return true
		along += step
	return false


## Dá se na spot doskočit? Stojí na zemi, nic vyššího než skok ani nikdo tam není.
func _landing_free(spot: Vector2) -> bool:
	return (
		_walker.stands(spot, _body)
		and _walker.place(spot, _body, _jump_clear, crowd_id).distance_squared_to(spot) <= 0.25
		and not _walker.blocked(spot, _body, crowd_id)
	)


func _step_jump(delta: float) -> void:
	_jump_t += delta
	var phase := clampf(_jump_t / _jump_dur, 0.0, 1.0)
	position = _jump_from.lerp(_jump_to, phase)
	scale = Vector2.ONE * (1.0 + JUMP_GROW * sin(phase * PI))
	var half := maxi(_frames / 2, 1)
	var frame := mini(int(phase * float(half)), half - 1)
	for sprite: Sprite2D in _sprites:
		sprite.frame = clampi(frame, 0, sprite.hframes * sprite.vframes - 1)
	if phase >= 1.0:
		_jumping = false
		scale = Vector2.ONE
		Sound.at_variant("monsters/%s_step" % kind_name, STEP_VARIANTS, global_position, 3.0)
		# Po dopadu je příšera jinde, cesta se přepočítá odsud.
		_replan_left = 0.0
		_sight_left = 0.0


## Příšera skončila v překážce nebo ve vodě. Vysune se na nejbližší volné místo.
func _escape() -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	if not _escaping or _walker.blocked(_escape_to, _body, crowd_id):
		var spot := _walker.free_spot(position, _body, ESCAPE_REACH * tile, ESCAPE_STEP, crowd_id)
		if spot == Vector2.INF:
			return
		_escape_to = spot
		_escaping = true
	position = position.move_toward(_escape_to, ESCAPE_METERS * tile * get_process_delta_time())
	if position.distance_squared_to(_escape_to) < 0.01:
		position = _escape_to
		_escaping = false


func _pick_target() -> void:
	_resting = false
	_stall_time = 0.0
	var tile := float(TerrainCatalog.TILE_SIZE)
	# Mapa čtverce ve světě nezačíná v (0, 0), ale v space_origin.
	var low := _walker.space_origin
	var high := low + _walker.world()
	if _flying:
		var margin := FLY_MARGIN * tile
		_target = Vector2(_rng.randf_range(low.x + margin, high.x - margin), _rng.randf_range(low.y + margin, high.y - margin))
		return
	for _try in 12:
		var spot := position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(WANDER_NEAR, WANDER_FAR) * tile
		if not _walker.contains(spot):
			continue
		if not _walker.blocked(spot, _body, crowd_id):
			_target = spot
			return
	_rest()


## Pro crowd: kruh o poloměru těla a výšce height_meters. Ve skoku přeskočí tvory do
## jump_meters, létající se nepočítá.
func crowd_body() -> float:
	return _body


func crowd_height() -> float:
	return _height


func crowd_clearance() -> float:
	return _jump_clear if _jumping else -1.0


func crowd_flying() -> bool:
	return _flying


func _rest() -> void:
	_resting = true
	_rest_left = _rng.randf_range(REST_MIN, REST_MAX)


## Natočí se za pohybem a krokuje podle ušlé dráhy, ať nohy neklouzají. Stojící má první snímek.
func _animate(delta: float, step: Vector2) -> void:
	var dist := step.length()
	if dist > 0.01:
		rotation = rotate_toward(rotation, step.angle() + PI * 0.5, TURN_SPEED * delta)
	_travel += dist
	_footstep(dist)
	var frame := int(fposmod(_travel / _cycle_px, 1.0) * float(_frames))
	if dist <= 0.01 and not _flying:
		frame = 0
	for sprite: Sprite2D in _sprites:
		sprite.frame = clampi(frame, 0, sprite.hframes * sprite.vframes - 1)


## Krok podle druhu: chodící dvakrát za cyklus animace, létající jedno mávnutí za cyklus.
func _footstep(moved: float) -> void:
	_step_travel += moved
	var stride := _cycle_px if _flying else _cycle_px * 0.5
	if _step_travel < stride:
		return
	_step_travel = fmod(_step_travel, stride)
	Sound.at_variant("monsters/%s_step" % kind_name, STEP_VARIANTS, global_position, float(STEP_DB.get(kind_name, -6.0)))


func is_chasing() -> bool:
	return _prey != null


## Postava, kterou příšera honí, jinak null.
func prey() -> Node2D:
	return _prey


## Létá nad vším? Vesničan jí do cesty nevleze.
func is_flying() -> bool:
	return _flying


## Honí a hraje k tomu hudba: zařvala na obrazovce a od té doby nezmizela dál než CHASE_KEEP za okraj.
func is_chasing_in_view() -> bool:
	return _in_view


## Je příšera vidět na obrazovce? margin obrazovku zvětší o tolik pixelů světa na každou stranu.
func _on_screen(margin: float = 0.0) -> bool:
	var view := _camera.get_viewport_rect().size / _camera.zoom
	return Rect2(_camera.get_screen_center_position() - view * 0.5, view).grow(margin).has_point(global_position)


func _on_view_changed() -> void:
	var view := _camera.get_viewport_rect().size
	if view != _fitted:
		_fit(view)


## Vrstva ve výšce se posouvá mimo svůj obdélník. Materiál zůstává i u vrstvy na zemi kvůli barvě.
func _fit(view: Vector2) -> void:
	_fitted = view
	for i in _sprites.size():
		var sprite := _sprites[i]
		if _heights[i] <= 0.0:
			RenderingServer.canvas_item_set_custom_rect(sprite.get_canvas_item(), false, Rect2())
			continue
		var rect := sprite.get_rect().grow(ObjectLayers.vertex_pad(view, _heights[i]))
		RenderingServer.canvas_item_set_custom_rect(sprite.get_canvas_item(), true, rect)
