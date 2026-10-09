extends Node2D

## Běh postavy ve středu pohledu. Atlas je cyklus běhu směrem na sever a za ním snímek stání,
## ostatní směry otáčí tenhle uzel.
## Nohy, tělo a hlava jsou tři vrstvy se stejným posunem výšky jako stromy a skály.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const Rocks := preload("res://scripts/rocks.gd")
const Crystal := preload("res://scripts/crystal.gd")
const Forest := preload("res://scripts/forest.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const MapData := preload("res://scripts/map_data.gd")
const Walker := preload("res://scripts/walker.gd")
const Party := preload("res://scripts/party.gd")

## Co postava drží. -1 je prázdná ruka.
signal held_changed(mat: int)

const CATALOG := "res://graphics/characters/person/person.json"
const TINTS: PackedStringArray = ["skin", "hair", "eye", "shirt", "pants", "shoe", "lace"]
## Běh, v metrech za sekundu. Dlaždice je jeden metr.
const RUN_METERS := 4.5
## Skok je o něco pomalejší než běh a přehraje jen první polovinu snímků.
const JUMP_METERS := RUN_METERS * 0.9
const JUMP_TIME := 0.7
## Přes tohle se ve skoku přenese. Balvan má 1,1 m, keř 1,2 m. Skály od 6 m a stromy ne.
const JUMP_CLEAR := 1.5
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
var _escape_to := Vector2.ZERO
var _travel := 0.0
var _step_travel := 0.0
var _frames := 16
var _atlas_frames := 16
var _idle_frame := 0
var _cycle_px := 64.0
var _active := false
var _fitted := Vector2.ZERO
var _sprites: Array[Sprite2D] = []
var _heights := PackedFloat32Array()
var _crystal: Crystal
var _rng := RandomNumberGenerator.new()
var _body: Sprite2D
var _walk_texture: Texture2D
var _hold_texture: Texture2D
var _hand_height := 1.2
var _held: Sprite2D
var _held_mat := -1
## Jezírko, ze kterého je kámen v ruce. Tam se vrátí, když ho příšera ukradne.
var _held_slot := -1
## Jezírko, kterého se postava právě dotýká, a za kolik sekund u něj vymění znovu.
var _touch_slot := -1
var _touch_left := 0.0
var _flyer: Sprite2D
var _fly_from := Vector2.ZERO
var _fly_to := Vector2.ZERO
var _fly_rot := 0.0
var _fly_spin := 0.0
var _fly_age := 0.0
var _fly_height := 0.0
var _fly_mat := -1


func setup(rocks: Rocks, forest: Forest, camera: MapCamera, map: MapData, crystal: Crystal, player: int = 0) -> void:
	player_index = player
	_device = int(GameSession.player_colors(player).get("device", 0))
	_rocks = rocks
	_forest = forest
	_camera = camera
	_crystal = crystal
	_rng.randomize()
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
	if not _jumping and Controls.jump_pressed(_device):
		_begin_jump(direction)
	if _jumping:
		_step_jump(delta)
	elif _stuck() or _escaping:
		_step_escape(delta)
	else:
		_step_run(delta, direction)
	if _flyer != null:
		_advance_throw(delta)
	_carry(delta)


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
	var half := maxi(_frames / 2, 1)
	_set_frame(mini(int(phase * float(half)), half - 1))
	var speed := JUMP_METERS * float(TerrainCatalog.TILE_SIZE)
	var next := _leashed(walker.allowed(position, position + _jump_dir * speed * delta, BODY, JUMP_CLEAR, crowd_id))
	position = next
	scale = Vector2.ONE * (1.0 + JUMP_GROW * sin(phase * PI))
	if _jump_dir.length_squared() > 0.0:
		rotation = _jump_dir.angle() + PI * 0.5
	if phase >= 1.0:
		_jumping = false
		scale = Vector2.ONE
		Sound.at("sfx/land", global_position, -3.0)


func _step_run(delta: float, direction: Vector2) -> void:
	var max_speed := RUN_METERS * float(TerrainCatalog.TILE_SIZE)
	if direction != Vector2.ZERO:
		_velocity += direction * ACCELERATION * delta
		if _velocity.length() > max_speed:
			_velocity = _velocity.limit_length(max_speed)
	else:
		_velocity = _velocity.move_toward(Vector2.ZERO, STOP_SPEED * delta)
	var next := _leashed(walker.allowed(position, position + _velocity * delta, BODY, -1.0, crowd_id))
	var step := next - position
	position = next
	# Sever v atlasu je záporné Y. Kladné otočení uzlu jde po směru hodin.
	var facing := step if step.length_squared() > 0.25 else direction
	if facing.length_squared() > 0.0001:
		rotation = facing.angle() + PI * 0.5
	if direction == Vector2.ZERO and _velocity.length_squared() < 1.0:
		_travel = 0.0
		_set_frame(_idle_frame)
	else:
		_travel += step.length()
		_set_frame(int(fposmod(_travel / _cycle_px, 1.0) * float(_frames)))
		_footstep(step.length())


## Krok podle povrchu pod postavou, dvakrát za cyklus chůze.
func _footstep(moved: float) -> void:
	_step_travel += moved
	if _step_travel < _cycle_px * 0.5:
		return
	_step_travel = fmod(_step_travel, _cycle_px * 0.5)
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


## Nejbližší suché místo ke středu mapy, které není ve skále ani ve vodě.
func _spawn_at() -> Vector2:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var tiles := int(walker.world().x / tile)
	var half := tiles / 2
	for radius in tiles:
		var y0 := maxi(half - radius, 0)
		var y1 := mini(half + radius, tiles - 1)
		var x0 := maxi(half - radius, 0)
		var x1 := mini(half + radius, tiles - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if radius > 0 and y != y0 and y != y1 and x != x0 and x != x1:
					continue
				var pos := Vector2((float(x) + 0.5) * tile, (float(y) + 0.5) * tile)
				var landed := walker.place(pos, BODY)
				if walker.stands(landed, BODY):
					return landed
	return walker.place(Vector2(tile * 0.5, tile * 0.5), BODY)


func _build() -> bool:
	if not FileAccess.file_exists(CATALOG):
		push_error("Chybí postava.")
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst postavu.")
		return false
	var info: Dictionary = parsed
	var shader := load(str(info.get("shader", ""))) as Shader
	if shader == null:
		push_error("Chybí shader postavy.")
		return false
	_frames = maxi(int(info.get("frames", 8)), 1)
	_atlas_frames = maxi(int(info.get("atlas_frames", _frames)), _frames)
	_idle_frame = clampi(int(info.get("idle_frame", 0)), 0, _atlas_frames - 1)
	_cycle_px = CYCLE_METERS * float(TerrainCatalog.TILE_SIZE)
	var columns := maxi(int(info.get("atlas_columns", _frames)), 1)
	var shade: Array = info.get("shade", [0.42, 1.1])
	var sheen: Array = info.get("sheen", [0.16, 0.7])
	var root := CATALOG.get_base_dir()
	var listed: Dictionary = info.get("layers", {})
	var keys: Array = listed.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for key: Variant in keys:
		var layer: Dictionary = listed[key]
		var texture := load("%s/%s" % [root, str(layer.get("file", ""))]) as Texture2D
		if texture == null:
			push_error("Chybí vrstva postavy %s." % str(layer.get("file", "")))
			return false
		var height := float(layer.get("height", 0.0))
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.hframes = columns
		sprite.vframes = maxi(ceili(float(_atlas_frames) / float(columns)), 1)
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("height_m", height)
		material.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
		material.set_shader_parameter("shade", Vector2(float(shade[0]), float(shade[1])))
		material.set_shader_parameter("shade_floor", float(info.get("shade_floor", 0.2)))
		material.set_shader_parameter("sheen", Vector2(float(sheen[0]), float(sheen[1])))
		sprite.material = material
		sprite.set_instance_shader_parameter("slot", float(layer.get("slot", 0.0)))
		if is_equal_approx(float(layer.get("slot", -1.0)), 1.0):
			_body = sprite
			_walk_texture = texture
			_hand_height = height
		add_child(sprite)
		_sprites.append(sprite)
		_heights.append(height)
	if _sprites.is_empty():
		push_error("Postava nemá vrstvy.")
		return false
	_tint(info.get("colors", {}))
	# Kalhoty, triko a vlasy z menu. Ostatní barvy zůstanou z katalogu.
	_tint(GameSession.player_colors(player_index))
	var hold_info: Dictionary = info.get("hold", {})
	_hold_texture = load("%s/%s" % [root, str(hold_info.get("file", ""))]) as Texture2D
	if _hold_texture == null:
		push_error("Chybí úchop postavy.")
	return true


func _tint(colors: Variant) -> void:
	if typeof(colors) != TYPE_DICTIONARY:
		return
	var listed: Dictionary = colors
	for tint_name: String in TINTS:
		var hex := str(listed.get(tint_name, ""))
		if hex.is_empty():
			continue
		var color := Color.html(hex)
		for sprite: Sprite2D in _sprites:
			sprite.set_instance_shader_parameter("%s_color" % tint_name, color)


func _set_frame(index: int) -> void:
	var frame := clampi(index, 0, _atlas_frames - 1)
	for sprite: Sprite2D in _sprites:
		sprite.frame = frame


func _on_view_changed() -> void:
	var view := _camera.get_viewport_rect().size
	if view == _fitted:
		return
	_fit(view)


func _fit(view: Vector2) -> void:
	_fitted = view
	# Nohy jsou ve výšce 0 a shader potřebují kvůli barvě. fit_sprite by jim ho sebral.
	for i in _sprites.size():
		if _heights[i] <= 0.0:
			continue
		var sprite := _sprites[i]
		ObjectLayers.fit_sprite(sprite, sprite.material as ShaderMaterial, _heights[i], view, true)
	if _held != null and _held.visible:
		_pad_gem(_held, _hand_height)
	if _flyer != null:
		_pad_gem(_flyer, _fly_height)


func _attach_hand() -> void:
	if _crystal == null or _crystal.count() == 0:
		return
	_held = _crystal.make_sprite()
	_held.visible = false
	_held.position = PALM
	add_child(_held)


## Kotlina vezme nesený kámen. Jezírko ho vymění za svůj nejdražší kámen, prázdné jezírko si ho
## nechá a ruka zůstane prázdná. Hned při doteku a potom každých SWAP_REPEAT sekund, dokud
## postava u jezírka stojí, takže u prázdného jezírka se kámen střídavě odloží a vezme.
func _carry(delta: float) -> void:
	if _flyer != null or _crystal == null or _crystal.count() == 0 or _held == null:
		return
	if _held_mat >= 0 and _rocks.touches_basin(position, BODY):
		_throw()
		_touch_slot = -1
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


## Kámen zůstal v prázdném jezírku, ruka je prázdná.
func _put_down() -> void:
	_held.visible = false
	_held_mat = -1
	_held_slot = -1
	_set_hold(false)
	held_changed.emit(-1)
	Sound.at("sfx/pickup", global_position, -3.0)


## Pro crowd: postava je kruh o poloměru trupu, není malá a ve skoku přeskočí malé tvory.
func crowd_body() -> float:
	return BODY


func crowd_small() -> bool:
	return false


func crowd_airborne() -> bool:
	return _jumping


func crowd_flying() -> bool:
	return false


## Materiál v ruce, -1 je prázdná ruka.
func carried() -> int:
	return _held_mat


## Příšera kámen sebrala. Odletí zpátky do svého jezírka, ruka je prázdná.
func drop_held() -> void:
	if _held_mat < 0:
		return
	_send_back()
	Sound.at("sfx/steal", global_position)


## Kámen z ruky odletí obloukem do jezírka, ze kterého ho postava vzala. Až dopadne, jezírku
## přibude.
func _send_back() -> void:
	var mat := _held_mat
	var slot := _held_slot
	var start := _held.global_position
	_held.visible = false
	_held_mat = -1
	_held_slot = -1
	_set_hold(false)
	held_changed.emit(-1)
	var host := get_parent() as Node2D
	if host == null or slot < 0:
		_rocks.return_gem(slot, mat)
		return
	var gem := _crystal.make_sprite()
	host.add_child(gem)
	gem.global_position = start
	gem.z_index = 3
	_crystal.paint(gem, mat, _hand_height, 0.0)
	_pad_gem(gem, _hand_height)
	var spin := (-1.0 if _rng.randf() < 0.5 else 1.0) * TAU * _rng.randf_range(0.75, 1.6)
	var tween := gem.create_tween()
	tween.tween_method(_fly_home.bind(gem, gem.position, _rocks.gem_home(slot), spin), 0.0, 1.0, RETURN_TIME)
	tween.tween_callback(_land_home.bind(gem, slot, mat))


func _fly_home(t: float, gem: Sprite2D, from: Vector2, to: Vector2, spin: float) -> void:
	var eased := 1.0 - pow(1.0 - t, 2.0)
	var way := to - from
	var pos := from.lerp(to, eased)
	if way.length_squared() > 1.0:
		pos += way.orthogonal().normalized() * sin(t * PI) * signf(spin) * minf(RETURN_ARC, way.length() * 0.25)
	gem.position = pos
	gem.rotation = spin * eased
	_pad_gem(gem, lerpf(_hand_height, 0.0, eased))


func _land_home(gem: Sprite2D, slot: int, mat: int) -> void:
	gem.queue_free()
	_rocks.return_gem(slot, mat)


## V ruce je kámen mat z jezírka slot. Stejný kámen jako předtím jen změní jezírko, kam se
## vrátí po krádeži, a nezazní.
func _take(slot: int, mat: int) -> void:
	_held_slot = slot
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


func _throw() -> void:
	var host := get_parent() as Node2D
	if host == null or _held == null or _held_mat < 0:
		return
	var mat := _held_mat
	var start := _held.global_position
	var rot := _held.global_rotation
	_held.visible = false
	_held_mat = -1
	_held_slot = -1
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
	_fly_to = _rocks.basin_spot(_crystal.radius(), _rng)
	_fly_rot = flyer.rotation
	_fly_spin = sign * TAU * _rng.randf_range(0.75, 1.6)
	_fly_age = 0.0
	_fly_height = _hand_height
	_fly_mat = mat
	_pad_gem(flyer, _hand_height)


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
	_fly_height = lerpf(_hand_height, 0.0, eased)
	_pad_gem(_flyer, _fly_height)
	if t < 1.0:
		return
	var mat := _fly_mat
	var rot := _flyer.rotation
	var landed := _fly_to
	_flyer.visible = false
	_flyer.queue_free()
	_flyer = null
	_rocks.settle(mat, landed, rot)


func _set_hold(on: bool) -> void:
	if _body == null or _hold_texture == null or _walk_texture == null:
		return
	_body.texture = _hold_texture if on else _walk_texture
	_fit(_fitted)


func _pad_gem(sprite: Sprite2D, height: float) -> void:
	var on := height > 0.0 and _fitted != Vector2.ZERO and ObjectLayers.shader_needed(_fitted, _camera.zoom.x, height)
	sprite.set_instance_shader_parameter("height_m", height if on else 0.0)
	if on:
		var rect := sprite.get_rect()
		RenderingServer.canvas_item_set_custom_rect(sprite.get_canvas_item(), true, rect.grow(ObjectLayers.vertex_pad(_fitted, height)))
	else:
		RenderingServer.canvas_item_set_custom_rect(sprite.get_canvas_item(), false, Rect2())
