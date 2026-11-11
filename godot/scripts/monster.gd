extends Node2D

## Jedna příšera v otevřeném světě (chodec s world_board). Řídí ji Hunt.
## Chytej příšery: toulá se kolem svého místa, a když se postava přiblíží na FLEE_NEAR metrů,
## utíká před ní kamkoli, i do jiných čtverců.
## Sbírání materiálů (guard_at): krouží kolem svého kamene ve vzdálenosti ring, nikomu se
## nevyhýbá. Na pokyn (chase) honí jednu postavu rychlostí honičky, dokud ji Hunt neodvolá.
## Toulání a kroužení jdou po úsecích ověřených dopředu (_way_open), bez srážek v každém
## snímku. Úprk a honička se srážejí jako postava, obchází překážky a nechodí přes jiné tvory.
## Létající letí nad vším. Druh s jump_meters přeskočí překážky a tvory do té výšky jako postava.
## Atlas je nakreslený směrem na sever, ostatní směry otáčí tenhle uzel.
## Vodní druh ("aquatic" v katalogu, aligátor) se drží brodítelné vody (Walker.swims): mělčiny
## u břehu a řeky. Voda ho nezpomalí a neskáče.
## Evoluce: o úprku a honičce rozhoduje Evolve (rule, flee_from, chase, roam), ne vzdálenost
## postavy. Příšera hráče je loutka (puppet): sama se nehýbe, pohyb jí dává postava (puppet_step).

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const Shadows := preload("res://scripts/shadows.gd")
const Walker := preload("res://scripts/walker.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const Person := preload("res://scripts/person.gd")
const Splashes := preload("res://scripts/splashes.gd")

## Dosah chňapnutí v metrech navíc k tělům. Postava přitisknutá k překážce jinak nejde dosáhnout.
const BITE := 0.6
## Toulání: cíl WANDER_NEAR až WANDER_FAR metrů od místa, kde příšera stojí.
const WANDER_NEAR := 4.0
const WANDER_FAR := 14.0
## Po neúspěšném losování směru (nebo u cíle) vždy tolik sekund postojí.
const HUNT_REST := 1.5
## Kroužení kolem kamene: úsek je oblouk o tolik radiánů. Když úsek nejde, otočí se. Když
## nejde ani druhým směrem, postojí HUNT_REST a zkusí to znovu.
const ARC_STEP := 0.6
## Na cestu k cíli má TRIP_SLACK krát víc času, než by trvala, a TRIP_EXTRA sekund navíc.
## Pak si vybere jiný cíl, ať došel, nebo ne.
const TRIP_SLACK := 2.0
const TRIP_EXTRA := 2.0
## Zaseknutí se pozná podle toho, kam se tvor za okno dostal, ne kolik ušel: klouzání podél
## překážky tam a zpátky je taky zaseknutí. Za okno se musí posunout aspoň o STUCK_SHARE
## dráhy, kterou by ušel. Toulání má okno WANDER_WATCH sekund, honička CHASE_WATCH.
const STUCK_SHARE := 0.25
const WANDER_WATCH := 1.2
const CHASE_WATCH := 0.6
## Honička jde přímo na postavu. Zasekne-li se, uhne na chvíli do strany pod úhlem, každý
## další neúspěch zkusí druhou stranu a větší úhel.
const DETOUR_MIN := 1.0
const DETOUR_MAX := 2.5
const DETOUR_ANGLES: Array[float] = [1.2, 1.7, 2.3]
## Natáčení za směrem pohybu v radiánech za sekundu.
const TURN_SPEED := 7.0
## Skok jako u postavy: první polovina snímků chůze, uprostřed skoku zvětšení o JUMP_GROW.
## Ve skoku běží stejně rychle jako po terénu, odkud skáče. Než skočí, najde místo přistání
## za překážkou, nejdál JUMP_REACH metrů. Když je za ním volno, doskočí dál, ať skok trvá aspoň
## JUMP_TIME sekund. Kratší skok trvá kratší dobu, rychlost zůstane.
const JUMP_TIME := 0.7
const JUMP_GROW := 0.15
const JUMP_REACH := 10.0
const JUMP_STEP := 0.25
## Hledání místa přistání prochází až desítky bodů. Když skok nevyšel, další pokus až za tolik
## sekund, ne v každém snímku klouzání podél překážky.
const JUMP_RETRY := 0.2
## Hlasitost kroků podle druhu v dB. Chodící dupne dvakrát za cyklus, létající mávne jednou.
const STEP_DB := {"had": -12.0, "pavouk": -10.0, "vlk": -6.0, "kocour": -9.0, "tyranosaurus": 0.0, "ptakojester": -5.0, "orel": -7.0, "nestvura": -4.0, "brouk": -14.0, "aligator": -10.0, "koule": -8.0}
const STEP_VARIANTS := 3
## Úprk (hunt): začne, když je postava blíž než FLEE_NEAR metrů, skončí dál než FLEE_FAR.
## Po FLEE_EVERY sekundách volí směr: od nejbližší postavy, cíl je od ní dvakrát dál než
## příšera, tedy za příšerou ve stejné vzdálenosti, nejméně FLEE_MIN a ověřený nejdál
## FLEE_LOOK metrů. Když tam něco stojí, zkusí směry pootočené o FLEE_TURNS.
const FLEE_NEAR := 4.8
const FLEE_FAR := 8.0
## Nejbližší postava se hledá jen po tolika sekundách, ne každý snímek.
const FLEE_CHECK := 0.15
const FLEE_EVERY := 0.33
const FLEE_MIN := 3.0
const FLEE_LOOK := 4.0
const FLEE_TURNS: Array[float] = [0.0, 0.52, -0.52, 1.05, -1.05, 1.57, -1.57, 2.09, -2.09]
## Směrů úprku se za snímek zkusí nejvýš tolik, mezitím běží dosavadním směrem.
const FLEE_TURNS_PER_FRAME := 3
## Toulání v hunt zkusí nejvýš tolik směrů, jeden za snímek. Každý stojí až 14 kontrol místa.
const WAY_TRIES := 2
## Vodní druh v úzké vodě: rovná čára dál skoro vždy vede na břeh. Úprk proto ověřuje jen
## SWIM_LOOK metrů, toulání míří jen SWIM_WANDER metrů daleko a zkusí víc směrů.
const SWIM_LOOK := 1.5
const SWIM_WANDER := Vector2(1.5, 4.0)
const SWIM_WAY_TRIES := 6
## Za úprku řve po ROAR_MIN až ROAR_MAX sekundách, jen když je vidět.
const ROAR_MIN := 1.0
const ROAR_MAX := 3.0
## Vysunutí z překážky jako u postavy, v metrech a pixelech.
const ESCAPE_METERS := 4.0
const ESCAPE_REACH := 10.0
const ESCAPE_STEP := 8.0
## Jak často se kontroluje, jestli příšera nestojí v překážce nebo ve vodě. Krok pohybu ji
## z překážky stejně vytlačí, kontrola je pojistka pro vodu a zaklínění.
const BLOCK_CHECK := 0.2
## Toulání dál než tolik metrů za okrajem obrazovky se neanimuje, nikdo ho nevidí.
const OFF_SCREEN_M := 4.0

## Materiál příšery.
var material_index := -1
## Zvuky příšery (pavouk, vlk, ...): podle nich zní kroky a zařvání. Obvykle je to druh,
## katalog ho může přepsat klíčem sound. Nastaví správce příšer.
var kind_name := ""
## Číslo mezi tvory, kteří nechodí přes sebe. Nastaví správce příšer.
var crowd_id := -1
## Evoluce: úprk a honičku řídí Evolve, příšera sama nehledá nejbližší postavu.
var _ruled := false
## Evoluce: příšera po chycení hráče utíká od místa _away, dokud není dál než _away_px.
## Vector2.INF neodbíhá.
var _away := Vector2.INF
var _away_px := 0.0

var _walker: Walker
var _persons: Array[Person] = []
## Postava, kterou příšera honí (Sbírání materiálů), jinak null.
var _prey: Node2D
## Hlídá kámen: krouží kolem _home ve vzdálenosti _ring px, směr kroužení _turn_dir.
var _guard := false
var _home := Vector2.ZERO
var _ring := 0.0
var _turn_dir := 1.0
var _camera: MapCamera
var _rng: RandomNumberGenerator
var _flying := false
var _aquatic := false
var _wander_px := 64.0
var _chase_px := 320.0
## Rychlost honičky druhu bez násobku materiálu, v px za sekundu.
var _chase_unit := 320.0
var _body := 24.0
var _touch := 40.0
var _cycle_px := 64.0
var _frames := 8
var _sprites: Array[Sprite2D] = []
var _heights := PackedFloat32Array()
var _target := Vector2.ZERO
var _resting := false
var _rest_left := 0.0
## Kolik sekund ještě zbývá na cestu k _target.
var _trip_left := 0.0
## Hlídání zaseknutí: kde tvor stál na začátku okna a kolik okna zbývá.
var _watch_from := Vector2.ZERO
var _watch_left := 0.0
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
var _jump_retry_left := 0.0
var _block_check_left := 0.0
## Rychlost z posledního snímku chůze v pixelech za sekundu (hunt). Chycená příšera s ní dobíhá.
var _velocity := Vector2.ZERO
var _step_travel := 0.0
## Která noha teď došlápla (cákání ve vodě).
var _left_foot := false
## Zařvala už v téhle honičce? Zařve, až je honící příšera poprvé na obrazovce.
var _roared := false
## Úprk (hunt): utíká, směr, za kolik sekund volí další a za kolik zase zařve.
var _fleeing := false
var _flee_dir := Vector2.ZERO
var _flee_left := 0.0
var _roar_left := 0.0
var _near: Person
var _near_left := 0.0
## Hledání směru úprku (_flee_search): další pootočení z FLEE_TURNS, -1 nehledá. Směr od
## postavy a dosah kontroly platí, jak byly na začátku hledání.
var _flee_turn := -1
var _flee_away := Vector2.ZERO
var _flee_reach := 0.0
## Toulání (hunt): kolik směrů ještě zkusí, jeden za snímek (_pick_way).
var _ways_left := 0


## info je druh z monsters.json, textures vrstvy podle pořadí klíčů, colors klíče body, accent, eye.
## Kamenná příšera má v colors navíc glint a sparkle materiálu a glint_maps, atlasy
## předpočítaných odlesků podle pořadí vrstev.
## speed násobí rychlost honičky druhu, dražší materiál má rychlejší příšeru.
func setup(
	info: Dictionary,
	textures: Array[Texture2D],
	shared: ShaderMaterial,
	colors: Dictionary,
	speed: float,
	shadow_alpha: float,
	walker: Walker,
	persons: Array[Person],
	camera: MapCamera,
	rng: RandomNumberGenerator,
	at: Vector2,
) -> void:
	_walker = walker
	_persons = persons
	_camera = camera
	_rng = rng
	var tile := float(TerrainCatalog.TILE_SIZE)
	_flying = bool(info.get("flying", false))
	_aquatic = bool(info.get("aquatic", false))
	_wander_px = float(info.get("wander_meters", 1.0)) * tile
	_chase_unit = float(info.get("chase_meters", 5.0)) * tile
	_chase_px = _chase_unit * speed
	_body = float(info.get("body_meters", 0.4)) * tile
	_touch = _body + Person.BODY + BITE * tile
	_cycle_px = maxf(float(info.get("cycle_meters", 1.0)) * tile, 1.0)
	_frames = maxi(int(info.get("frames", 8)), 1)
	_height = float(info.get("height_meters", 1.0))
	_jump_clear = float(info.get("jump_meters", 0.0))
	# Chodící mezi postavou a vysokými skalami, létající nad vším.
	z_index = 4 if _flying else 1
	var columns := maxi(int(info.get("atlas_columns", _frames)), 1)
	# Stejná fáze pro obě vrstvy, ať odlesk na zadečku a na nohou patří k jedné příšeře.
	var sparkle_phase := _rng.randf() * TAU
	var listed: Dictionary = info.get("layers", {})
	var keys: Array = listed.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	var casters: Array = []
	var cast_heights: Array = []
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
		if colors.has("sparkle"):
			material.set_shader_parameter("glint_color", colors["glint"])
			material.set_shader_parameter("sparkle", colors["sparkle"])
			material.set_shader_parameter("phase", sparkle_phase)
			var maps: Array = colors.get("glint_maps", [])
			if i < maps.size() and maps[i] != null:
				material.set_shader_parameter("glint_map", maps[i])
		if bool(layer.get("shadow", false)):
			material.set_shader_parameter("shadow_alpha", shadow_alpha)
			# Stín leží na zemi pod postavou, i když tvor letí nad vším.
			sprite.z_as_relative = false
			sprite.z_index = 0
			# Se slunci tvor vrhá stín ze svých vrstev (Shadows), vlastní stín pod sebou nepotřebuje.
			sprite.visible = Shadows.current == null
		else:
			casters.append(sprite)
			cast_heights.append(height)
		add_child(sprite)
		_sprites.append(sprite)
		_heights.append(height)
	position = at
	rotation = _rng.randf() * TAU
	# Létající tvor je od země odtržený, jeho stín taky.
	if Shadows.current != null:
		Shadows.current.follow(casters, cast_heights, not _flying)
	_pick_target()
	camera.view_changed.connect(_on_view_changed)
	_fit(camera.get_viewport_rect().size)
	_active = true


func _process(delta: float) -> void:
	if not _active:
		return
	_jump_retry_left = maxf(_jump_retry_left - delta, 0.0)
	_block_check_left -= delta
	if _guard:
		_patrol(delta)
	else:
		_hunt(delta)


## Sbírání materiálů: honička, nebo kroužení kolem kamene.
func _patrol(delta: float) -> void:
	if _jumping:
		_step_jump(delta)
		return
	if _prey != null and not is_instance_valid(_prey):
		stop_chase()
	if _prey != null:
		_pursue(delta)
		return
	var before := position
	_wander(delta)
	_velocity = (position - before) / delta if delta > 0.0 else Vector2.ZERO
	if _on_screen(OFF_SCREEN_M * float(TerrainCatalog.TILE_SIZE)):
		_animate(delta, position - before)


## Honička jedné postavy (_prey), zařve, až je poprvé vidět.
func _pursue(delta: float) -> void:
	var before := position
	if not _roared and _on_screen():
		_roared = true
		Sound.at("monsters/%s_roar" % kind_name, global_position, 2.0)
	_chase(delta)
	_velocity = (position - before) / delta if delta > 0.0 else Vector2.ZERO
	_animate(delta, position - before)


func _chase(delta: float) -> void:
	_resting = false
	var to := _prey.position - position
	if to.length() > 0.001:
		var step := minf(_chase_px * _pace() * delta, to.length())
		var dir := to.normalized()
		if _detour_left > 0.0:
			_detour_left -= delta
			dir = dir.rotated(_detour_side * DETOUR_ANGLES[mini(_detour_tries, DETOUR_ANGLES.size() - 1)])
		_move(dir * step)
		if not _jumping:
			# U kořisti se jen dotahuje, tam pomalý postup zaseknutí není.
			_track_chase(delta, position.distance_to(_prey.position) <= _touch * 2.0)


## Chytej příšery: toulání, a když je postava blízko, úprk. Toulání je dekorace: bez
## plných srážek a mimo obrazovku bez animace.
func _hunt(delta: float) -> void:
	if _jumping:
		_step_jump(delta)
		return
	var tile := float(TerrainCatalog.TILE_SIZE)
	if _ruled:
		if _away != Vector2.INF:
			if position.distance_squared_to(_away) >= _away_px * _away_px:
				_away = Vector2.INF
				_fleeing = false
				_pick_target()
			else:
				var from_pos := position
				_flee(delta, _away)
				_velocity = (position - from_pos) / delta if delta > 0.0 else Vector2.ZERO
				_animate(delta, position - from_pos)
				return
		if _prey != null and not is_instance_valid(_prey):
			roam()
		if _prey != null:
			_pursue(delta)
			return
		if _near != null and not is_instance_valid(_near):
			roam()
	_near_left -= delta
	if not _ruled and (_near_left <= 0.0 or (_near != null and not is_instance_valid(_near))):
		_near_left = FLEE_CHECK
		_near = null
		var best := INF
		for person in _persons:
			if not is_instance_valid(person):
				continue
			var dist := position.distance_squared_to(person.position)
			if dist < best:
				best = dist
				_near = person
		var near_dist := sqrt(best)
		if not _fleeing and near_dist < FLEE_NEAR * tile:
			_fleeing = true
			_resting = false
			_flee_left = 0.0
			_flee_turn = -1
			_roar_left = 0.0
			_watch_reset(CHASE_WATCH)
		elif _fleeing and near_dist > FLEE_FAR * tile:
			_fleeing = false
			_pick_target()
	var before := position
	if _fleeing and _near != null:
		_flee(delta, _near.position)
		_velocity = (position - before) / delta
		_animate(delta, position - before)
		return
	_wander(delta)
	_velocity = (position - before) / delta if delta > 0.0 else Vector2.ZERO
	# Mimo obrazovku toulání nikdo nevidí: bez animace a kroků.
	if _on_screen(OFF_SCREEN_M * tile):
		_animate(delta, position - before)


func _flee(delta: float, from: Vector2) -> void:
	_roar_left -= delta
	if _roar_left <= 0.0:
		_roar_left = _rng.randf_range(ROAR_MIN, ROAR_MAX)
		if _on_screen():
			Sound.at("monsters/%s_roar" % kind_name, global_position, 2.0)
	_flee_left -= delta
	if _flee_left <= 0.0 and _flee_turn < 0:
		_flee_left = FLEE_EVERY
		var tile := float(TerrainCatalog.TILE_SIZE)
		var away := position - from
		var dist := away.length()
		_flee_away = away / dist if dist > 0.01 else Vector2.from_angle(_rng.randf() * TAU)
		_flee_reach = SWIM_LOOK * tile if _aquatic else clampf(dist, FLEE_MIN * tile, FLEE_LOOK * tile)
		_flee_turn = 0
	if _flee_turn >= 0:
		_flee_search()
	_move(_flee_dir * _chase_px * _pace() * delta)


## Směr úprku od postavy: rovně pryč, nebo první pootočený směr, kde nic nestojí. Zkouší
## nejvýš FLEE_TURNS_PER_FRAME směrů, další v příštím snímku. Když nejde žádný, dosavadní
## směr: příšera klouže podél překážky a dá se chytit.
func _flee_search() -> void:
	for _try in FLEE_TURNS_PER_FRAME:
		if _flee_turn >= FLEE_TURNS.size():
			if _flee_dir == Vector2.ZERO:
				_flee_dir = _flee_away
			_flee_turn = -1
			return
		var way := _flee_away.rotated(FLEE_TURNS[_flee_turn])
		_flee_turn += 1
		if _way_open(way, _flee_reach):
			_flee_dir = way
			_flee_turn = -1
			return


## Dá se jít směrem way na reach pixelů? Po metrech: na zemi a mimo překážky (skokan jen
## mimo vyšší, než přeskočí). Létající jen nad hotovými čtverci.
func _way_open(way: Vector2, reach: float) -> bool:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var steps := maxi(ceili(reach / tile), 1)
	var clear := _jump_clear if _jump_clear > 0.0 else -1.0
	for i in range(1, steps + 1):
		var spot := position + way * reach * float(i) / float(steps)
		if _flying:
			if _walker.world_board != null and not _walker.world_board.has_ground(spot):
				return false
			continue
		if _aquatic:
			if not _walker.swims(spot):
				return false
		elif not _walker.stands(spot, _body):
			return false
		if _walker.place(spot, _body, clear, crowd_id).distance_squared_to(spot) > 0.25:
			return false
	return true


## Utíká právě (hunt)?
func is_fleeing() -> bool:
	return _fleeing


## Sbírání materiálů: hlídá kámen na center, krouží kolem něj ve vzdálenosti ring px.
## Přestane přitom honit.
func guard_at(center: Vector2, ring: float) -> void:
	_guard = true
	_home = center
	_ring = ring
	_prey = null
	_fleeing = false
	_detour_left = 0.0
	_pick_target()


## Sbírání materiálů: honí postavu person, dokud ji Hunt neodvolá (stop_chase, guard_at).
## Evoluce: honí, dokud Evolve nerozhodne jinak (flee_from, roam).
func chase(person: Node2D) -> void:
	if _prey == person:
		return
	_prey = person
	_fleeing = false
	_away = Vector2.INF
	_roared = false
	_resting = false
	_detour_left = 0.0
	_detour_tries = 0
	_watch_reset(CHASE_WATCH)


## Evoluce: úprk a honičku od teď řídí Evolve. Platí i po návratu ze zásoby.
func rule() -> void:
	_ruled = true


## Evoluce: utíká před postavou person, dokud Evolve nerozhodne jinak.
func flee_from(person: Person) -> void:
	if _fleeing and _near == person:
		return
	_prey = null
	_away = Vector2.INF
	_near = person
	_fleeing = true
	_resting = false
	_flee_left = 0.0
	_flee_turn = -1
	_roar_left = 0.0
	_detour_left = 0.0
	_watch_reset(CHASE_WATCH)


## Evoluce: odbíhá od místa from, dokud není dál než meters metrů. Pak se toulá.
func retreat(from: Vector2, meters: float) -> void:
	_prey = null
	_near = null
	_away = from
	_away_px = meters * float(TerrainCatalog.TILE_SIZE)
	_fleeing = true
	_resting = false
	_flee_left = 0.0
	_flee_turn = -1
	_roar_left = 0.0
	_detour_left = 0.0
	_watch_reset(CHASE_WATCH)


## Evoluce: postava, před kterou příšera utíká (flee_from), jinak null.
func fleeing_from() -> Node2D:
	return _near if _fleeing and _away == Vector2.INF else null


## Evoluce: odbíhá právě po chycení hráče (retreat)?
func is_retreating() -> bool:
	return _away != Vector2.INF


## Evoluce: nikoho nehoní a před nikým neutíká, toulá se.
func roam() -> void:
	if not _fleeing and _prey == null:
		return
	_away = Vector2.INF
	_fleeing = false
	_prey = null
	_near = null
	_pick_target()


## Přestane honit a vrátí se ke kroužení kolem kamene, který hlídala.
func stop_chase() -> void:
	_prey = null
	_pick_target()


## Dosah dotyku postavy v pixelech: těla obou a BITE.
func touch() -> float:
	return _touch


## Schová se do zásoby. Nic nedělá, dokud ji reuse znovu nevyvolá.
func park() -> void:
	_active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


## Příšera ze zásoby dostane materiál mat. colors jako v setup (bez glint_maps,
## druh zůstává), speed násobí rychlost honičky druhu.
func repaint(mat: int, colors: Dictionary, speed: float) -> void:
	material_index = mat
	_chase_px = _chase_unit * speed
	for sprite in _sprites:
		var material := sprite.material as ShaderMaterial
		material.set_shader_parameter("body_color", colors["body"])
		material.set_shader_parameter("accent_color", colors["accent"])
		material.set_shader_parameter("eye_color", colors["eye"])
		if colors.has("sparkle"):
			material.set_shader_parameter("glint_color", colors["glint"])
			material.set_shader_parameter("sparkle", colors["sparkle"])


## Příšera ze zásoby vyjde na at, jako by se tam právě objevila. Toulá se jako v Chytej
## příšery, dokud jí Hunt nedá kámen (guard_at).
func reuse(at: Vector2) -> void:
	position = at
	rotation = _rng.randf() * TAU
	scale = Vector2.ONE
	_set_opacity(1.0)
	_guard = false
	_prey = null
	_away = Vector2.INF
	_fleeing = false
	_flee_dir = Vector2.ZERO
	_flee_left = 0.0
	_flee_turn = -1
	_roar_left = 0.0
	_near = null
	_near_left = 0.0
	_jumping = false
	_jump_retry_left = 0.0
	_escaping = false
	_block_check_left = 0.0
	_velocity = Vector2.ZERO
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_active = true
	_pick_target()


## Chycená za seconds sekund dobíhá, rovnoměrně zpomalí na nulu a zmenší se na
## end_scale. Pak zavolá done. Překážky ji zastaví jako při chůzi, létající letí volně.
func shrink(seconds: float, end_scale: float, done: Callable) -> void:
	_active = false
	_fleeing = false
	_prey = null
	var tween := create_tween()
	tween.tween_method(_shrink_step.bind(position, _velocity, seconds, end_scale), 0.0, 1.0, seconds)
	tween.tween_callback(done)


## Podíl t z dobíhání. Rychlost klesá rovnoměrně, dráha je v · T · (t − t²/2).
func _shrink_step(t: float, from: Vector2, velocity: Vector2, seconds: float, end_scale: float) -> void:
	var next := from + velocity * seconds * (t - t * t * 0.5)
	# Kolize s plným tělem, ne zmenšeným: skály mají hranice spočítané předem jen pro těla
	# příšer. Pro jinou velikost by je počítaly na hlavním vlákně, asi 100 ms každý snímek.
	if not _flying and not _aquatic and _walker != null:
		next = _walker.allowed(position, next, _body, -1.0)
	var step := next - position
	position = next
	scale = Vector2.ONE * lerpf(1.0, end_scale, t)
	# Nohy dobíhají s ní, natočení zůstane.
	_animate(0.0, step)


## Evoluce: příšera jako vzhled hráče, dítě jeho postavy. Sama se nehýbe ani neotáčí (otáčí
## se postava), schovaná, dokud ji postava neukáže. Snímky a kroky jí dává puppet_step.
func puppet() -> void:
	_active = false
	process_mode = Node.PROCESS_MODE_DISABLED
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	# Vůči postavě: chodící na její úrovni, létající nad vším jako létající příšery.
	z_index = 3 if _flying else 0
	visible = false


## Loutka: postava ušla step (px) za delta sekund. Snímek chůze a kroky jako u příšery.
func puppet_step(delta: float, step: Vector2) -> void:
	_animate(delta, step, false)


## Loutka ve skoku postavy: phase 0 až 1, první polovina snímků jako skok příšery.
func puppet_jump(phase: float) -> void:
	var half := maxi(_frames / 2, 1)
	var frame := mini(int(phase * float(half)), half - 1)
	for sprite: Sprite2D in _sprites:
		sprite.frame = clampi(frame, 0, sprite.hframes * sprite.vframes - 1)


## Průhlednost všech vrstev, 1 plná (blikání hráče v klidu).
func fade(opacity: float) -> void:
	_set_opacity(opacity)


## Výška skoku druhu v metrech, 0 neskáče.
func jump_height() -> float:
	return _jump_clear


func _set_opacity(opacity: float) -> void:
	for sprite in _sprites:
		(sprite.material as ShaderMaterial).set_shader_parameter("opacity", opacity)


## Zasekne-li se honička, začne objížďka. Když se zasekne i objížďka, zkusí druhou stranu
## a větší úhel. Po okně, ve kterém se posunula, se počítání neúspěchů vynuluje.
func _track_chase(delta: float, near: bool) -> void:
	if _flying:
		return
	if near:
		_watch_reset(CHASE_WATCH)
		return
	var state := _watch(delta, _chase_px, CHASE_WATCH)
	if state < 0:
		return
	if state == 0:
		if _detour_left <= 0.0:
			_detour_tries = 0
		return
	if _detour_left > 0.0:
		_detour_tries += 1
		_detour_side = -_detour_side
	else:
		_detour_side = -1.0 if _rng.randf() < 0.5 else 1.0
	_detour_left = _rng.randf_range(DETOUR_MIN, DETOUR_MAX)


## Hlídání zaseknutí od teď na window sekund.
func _watch_reset(window: float) -> void:
	_watch_from = position
	_watch_left = window


## Konec okna? -1 okno běží, 0 tvor se posunul, 1 je zaseknutý: za okno se dostal méně než
## o STUCK_SHARE dráhy, kterou by rychlostí speed (px/s) ušel. Pak začne další okno.
func _watch(delta: float, speed: float, window: float) -> int:
	_watch_left -= delta
	if _watch_left > 0.0:
		return -1
	var stuck := position.distance_to(_watch_from) < speed * window * STUCK_SHARE
	_watch_reset(window)
	return 1 if stuck else 0


func _wander(delta: float) -> void:
	if _resting:
		if _ways_left > 0:
			_try_way()
			return
		_rest_left -= delta
		if _rest_left <= 0.0:
			_pick_target()
		return
	_trip_left -= delta
	if _trip_left <= 0.0:
		_pick_target()
		return
	# Cíl už ověřil _way_open, povrch a srážky by jen stály CPU.
	var to := _target - position
	var step := _wander_px * delta
	if to.length() <= step:
		position += to
		# Kroužení navazuje hned dalším obloukem, toulání u cíle postojí.
		if _guard or _flying:
			_pick_target()
		else:
			_rest()
		return
	position += to.limit_length(step)
	if _watch(delta, _wander_px, WANDER_WATCH) == 1:
		if _guard:
			_turn_dir = -_turn_dir
		_pick_target()


## Posun o offset. Vrátí, kolik pixelů příšera opravdu ušla.
## Násobek rychlosti podle povrchu. Létající příšeru močál nezdrží, vodní voda.
func _pace() -> float:
	return 1.0 if _flying or _aquatic or _walker == null else _walker.pace(position)


func _move(offset: Vector2) -> float:
	var before := position
	if _flying:
		# Chodec světa mapu nemá, létající jen nevyletí nad čtverec, který ještě není hotový.
		if _walker.world_board.has_ground(position + offset):
			position += offset
	elif _escaping or _blocked_now():
		_escape()
	elif _aquatic:
		position = _walker.allowed_swim(position, position + offset, _body, crowd_id)
	else:
		position = _walker.allowed(position, position + offset, _body, -1.0, crowd_id)
		# Klouzání podél překážky do strany se za postup nepočítá. Překážku přes kterou
		# vede cesta, je potřeba přeskočit.
		var forward := (position - before).dot(offset.normalized())
		if forward < offset.length() * 0.5 and _try_jump(offset.normalized()):
			position = before
			return 0.0
	return position.distance_to(before)


## Stojí příšera v překážce nebo ve vodě? Kontroluje se jen po BLOCK_CHECK sekundách.
func _blocked_now() -> bool:
	if _block_check_left > 0.0:
		return false
	_block_check_left = BLOCK_CHECK
	if _aquatic:
		return not _walker.swims(position)
	return _walker.blocked(position, _body, crowd_id)


## Skok přes nízkou překážku nebo malého tvora ve směru dir. Skočí, jen když za překážkou najde
## místo přistání a cestou není nic vyššího, voda ani okraj mapy.
func _try_jump(dir: Vector2) -> bool:
	if _jump_clear <= 0.0 or _flying or dir == Vector2.ZERO or _jump_retry_left > 0.0:
		return false
	# Platí pro každý konec bez skoku. Když skok vyjde, nic nevadí, ve skoku se nehledá.
	_jump_retry_left = JUMP_RETRY
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
			var speed := (_chase_px if _prey != null or _fleeing else _wander_px) * _pace()
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
		_watch_reset(CHASE_WATCH if _prey != null or _fleeing else WANDER_WATCH)


## Příšera skončila v překážce nebo ve vodě. Vysune se na nejbližší volné místo.
func _escape() -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	if _aquatic:
		if not _escaping or not _walker.swims(_escape_to):
			var water := _walker.free_swim(position, ESCAPE_REACH * tile, ESCAPE_STEP)
			if water == Vector2.INF:
				return
			_escape_to = water
			_escaping = true
	elif not _escaping or _walker.blocked(_escape_to, _body, crowd_id):
		var spot := _walker.free_spot(position, _body, ESCAPE_REACH * tile, ESCAPE_STEP, crowd_id)
		# Hluboko v houští nemusí být volno blízko. Hledá dál, hrubším krokem.
		if spot == Vector2.INF:
			spot = _walker.free_spot(position, _body, ESCAPE_REACH * 3.0 * tile, ESCAPE_STEP * 3.0, crowd_id)
		if spot == Vector2.INF:
			return
		_escape_to = spot
		_escaping = true
	position = position.move_toward(_escape_to, ESCAPE_METERS * tile * get_process_delta_time())
	if position.distance_squared_to(_escape_to) < 0.01:
		position = _escape_to
		_escaping = false


## Další cíl: oblouk kolem kamene (hlídání), jinak toulání náhodným směrem.
func _pick_target() -> void:
	_resting = false
	if _guard:
		_next_arc()
	else:
		_pick_way()


## Další oblouk kroužení: bod na kruhu kolem kamene o ARC_STEP dál ve směru _turn_dir od
## místa, kde příšera stojí. Když tam nejde dojít, zkusí druhý směr, pak postojí.
func _next_arc() -> void:
	var angle := (position - _home).angle()
	for _attempt in 2:
		var spot := _home + Vector2.from_angle(angle + _turn_dir * ARC_STEP) * _ring
		var way := spot - position
		if way.length() < 1.0 or _way_open(way.normalized(), way.length()):
			_target = spot
			_start_trip()
			return
		_turn_dir = -_turn_dir
	_rest()


## Chytej příšery: cíl toulání rovně náhodným směrem, kam se dá dojít (_way_open). Směry
## zkouší _try_way po jednom za snímek (nejvýš WAY_TRIES), mezitím příšera stojí. Když
## nic nevyjde, odpočinek HUNT_REST. Ať se při objevení nedělá všechno v jednom snímku.
func _pick_way() -> void:
	_ways_left = SWIM_WAY_TRIES if _aquatic else WAY_TRIES
	_resting = true
	_rest_left = 0.0


## Jeden směr toulání. Když nejde ani poslední, odpočívá.
func _try_way() -> void:
	_ways_left -= 1
	var tile := float(TerrainCatalog.TILE_SIZE)
	var way := Vector2.from_angle(_rng.randf() * TAU)
	var reach := _rng.randf_range(WANDER_NEAR, WANDER_FAR) * tile
	if _aquatic:
		reach = _rng.randf_range(SWIM_WANDER.x, SWIM_WANDER.y) * tile
	if _way_open(way, reach):
		_ways_left = 0
		_resting = false
		_target = position + way * reach
		_start_trip()
	elif _ways_left <= 0:
		_rest()


## Vyrazí rovně k _target. Času má podle délky cesty.
func _start_trip() -> void:
	_trip_left = position.distance_to(_target) / maxf(_wander_px, 1.0) * TRIP_SLACK + TRIP_EXTRA
	_watch_reset(WANDER_WATCH)


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
	_rest_left = HUNT_REST


## Natočí se za pohybem a krokuje podle ušlé dráhy, ať nohy neklouzají. Stojící má první snímek.
## turn false nechá natočení být (loutku otáčí postava).
func _animate(delta: float, step: Vector2, turn := true) -> void:
	var dist := step.length()
	if turn and dist > 0.01:
		rotation = rotate_toward(rotation, step.angle() + PI * 0.5, TURN_SPEED * delta)
	_travel += dist
	_footstep(dist)
	var frame := int(fposmod(_travel / _cycle_px, 1.0) * float(_frames))
	if dist <= 0.01 and not _flying:
		frame = 0
	for sprite: Sprite2D in _sprites:
		sprite.frame = clampi(frame, 0, sprite.hframes * sprite.vframes - 1)


## Krok podle druhu: chodící dvakrát za cyklus animace, létající jedno mávnutí za cyklus.
## Chodící ve vodě cákne od nohy (Splashes), střídavě vlevo a vpravo, a ke kroku šplouchne,
## větší příšera hlouběji a hlasitěji. Létající ne.
func _footstep(moved: float) -> void:
	_step_travel += moved
	var stride := _cycle_px if _flying else _cycle_px * 0.5
	if _step_travel < stride:
		return
	_step_travel = fmod(_step_travel, stride)
	if not _flying and not _jumping and Splashes.current != null and Splashes.current.wet(global_position):
		_left_foot = not _left_foot
		var forward := Vector2.from_angle(global_rotation - PI * 0.5)
		var side := forward.orthogonal() * _body * (0.4 if _left_foot else -0.4)
		var size := clampf(_body / Person.BODY, 0.7, 2.0)
		Splashes.current.splash(global_position + side + forward * _body * 0.3, forward, size)
		Sound.at("%s_%d" % [Person.WADE_SOUND, randi_range(1, 4)], global_position, Person.STEP_DB + 3.0 * (size - 1.0), clampf(1.0 / size, 0.6, 1.3) * randf_range(0.94, 1.06))
	Sound.at_variant("monsters/%s_step" % kind_name, STEP_VARIANTS, global_position, float(STEP_DB.get(kind_name, -6.0)))


func is_chasing() -> bool:
	return _prey != null


## Postava, kterou příšera honí, jinak null.
func prey() -> Node2D:
	return _prey


## Létá nad vším? Do skupiny tvorů (crowd) nepatří.
func is_flying() -> bool:
	return _flying


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
