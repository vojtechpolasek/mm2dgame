extends Node

## Hry na čas v otevřeném světě: Chytej příšery a Sbírání materiálů (GameSession.mode). Před
## hráči se objevují příšery, hráči za SECONDS sekund sbírají společné body. Výkony se
## zapisují podle počtu hráčů, každý režim do své tabulky.
##
## Chytej příšery: příšery utíkají a hráči je chytají dotykem.
## Sbírání materiálů: místo příšery se objeví kámen a jeho příšera kolem něj krouží ve
## vzdálenosti GUARD_RING metrů (Monster.guard_at). Kámen má nápis s materiálem a body, body
## jsou body druhu krát násobitel materiálu jako u příšery v Chytej příšery. Dotek kámen
## sebere: hráči dostanou body, postava ho nese v ruce a příšera ji začne honit rychlostí úprku
## o CHASE_BONUS m/s vyšší (laciné příšery jsou pomalejší než postava, drahé rychlejší). Když ji
## dohoní, body se odečtou, kámen spadne pod příšeru a ta kolem něj zase krouží. Kámen pak
## ROB_CALM sekund nejde sebrat. Když je postava dál než GIVE_UP_M metrů nebo sebere jiný kámen,
## příšera honičky nechá a kámen si hráči nechají. Příšera, která honí, nezmizí. Kámen leží
## tam, kam hráč dojde: na souši, u vodního druhu na mělčině, kolem které vodní příšera krouží
## ve vodě (kde je voda úzká, na menším kruhu).
##
## Každou sekundu se zapíše, kde je střed kamery (ukazuje všechny hráče). Příšera se objeví,
## když se kamera za posledních MOVED_SECONDS sekund posunula aspoň o MOVED_M metrů: tím
## směrem AHEAD_M metrů za okrajem obrazovky, náhodně posunutá do strany nejvýš o SIDE_SPREAD
## šířky obrazovky napříč. Další přijde za SPAWN_MIN až SPAWN_MAX sekund. Když se nepovede
## (hráči stojí, místo je ve vodě, v překážce nebo na čtverci, který ještě není hotový),
## zkusí se znovu za RETRY sekund.
## Losuje se ve dvou krocích podle hunt.json. Nejdřív druh: váha je váha druhu pro povrch pod
## místem krát váha pro denní dobu (day, night), na vodě jen létající. Pak materiál stejně podle
## vah materiálu, kromě materiálů, které má druh zakázané (forbidden). Chybějící povrch má váhu 0,
## chybějící denní doba 1. Body jsou body druhu krát násobitel materiálu. Úprk druhu je flee
## [od, do] v m/s, materiál ho posune o speedup (0 až 1) mezi od a do. Jméno je jméno druhu
## a přídavné jméno materiálu v rodě druhu (adjective je kmen: „pískovcov“ + ý, á, é).
## Vodní druh ("aquatic" v katalogu, aligátor) žije jen v brodítelné vodě (Walker.swims). Pro něj
## se kolem místa hledá nejbližší taková voda nejdál SWIM_REACH metrů, široká aspoň dvakrát
## SWIM_WIDTH, mimo obrazovku. Čtverce bez vody se přeskočí (WorldBoard.may_swim_near). Jeho váha se počítá z povrchu té vody a objeví se v ní.
## Živých je nejvýš MAX_ALIVE: když
## je plno, nová vytlačí nejstarší, která není na obrazovce. Denní doba se kontroluje jen při
## losování, objevená příšera zůstane i po změně dne a noci.
## Jednou za sekundu se uklidí příšera, která je od všech postav dál, než je delší strana
## obrazovky. Příšery se toulají bez mřížky cest a utíkají kamkoli (Monster.hunt).
## Chycená příšera dobíhá, za SHRINK sekund zpomalí na nulu a zmenší se zhruba na velikost
## kamene (Monster.shrink). Pak je na jejím místě kámen jejího materiálu. Počítá se jako chycená
## hned, body dostanou hráči až za sebrání kamene dotykem. Tehdy nad kamenem vystoupá nápis
## jako u příšery a pozvolna zmizí (FLOAT_TIME). Kámen leží, dokud se hráči nevzdálí jako od
## příšer (_forget). Nad toulající se příšerou je nápis
## s jejím jménem a body (tags), jen když k ní některý hráč míří (výseč čelovky), a při úprku
## zmizí po TAG_FLEE_KEEP sekundách.
##
## Ať se hra při objevení příšery necukne: příšery se nestaví, berou se ze zásoby schovaných
## (_pool, od každého druhu jedna postavená při startu, další přibude, když je zásoba druhu
## prázdná). Při vyjmutí dostane příšera barvy a rychlost vylosovaného materiálu (Monster.repaint).
## Uklizená i chycená příšera se do zásoby vrací. Výběr místa a objevení jsou
## v různých snímcích (_pending). Shadery příšer se při startu jednou vykreslí mimo obrazovku
## (_warm), ať se nepřekládají až u první příšery.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const Crystal := preload("res://scripts/crystal.gd")
const Monster := preload("res://scripts/monster.gd")
const Monsters := preload("res://scripts/monsters.gd")
const Walker := preload("res://scripts/walker.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const Person := preload("res://scripts/person.gd")
const Crowd := preload("res://scripts/crowd.gd")
const DayNight := preload("res://scripts/day_night.gd")
const Benchmark := preload("res://scripts/benchmark.gd")

const CATALOG := "res://graphics/characters/monsters/hunt.json"
const RECORDS := "user://hunt_records.cfg"
const COLLECT_RECORDS := "user://collect_records.cfg"
## Výkonů se pro každý počet hráčů drží tolik. Sekce NAMES drží poslední jména.
const RECORDS_KEPT := 30
const NAMES := "names"
## Délka hry v sekundách.
const SECONDS := 540.0
const SPAWN_MIN := 3.0
const SPAWN_MAX := 5.0
const RETRY := 1.0
const MOVED_SECONDS := 3
const MOVED_M := 6.0
const AHEAD_M := 3.0
const SIDE_SPREAD := 0.3
## Když místo nejde (voda, nehotový čtverec, překážka), zkusí se jiný posun, nejvýš tolikrát.
const SPAWN_TRIES := 4
const SWIM_REACH := 5.0
const SWIM_STEP := 0.75
## Na každém kruhu hledání vody nejvýš tolik bodů.
const SWIM_AROUND := 32
const SWIM_WIDTH := 0.3
## Obrazovka zvětšená o tolik metrů na každou stranu: tam se nikdo neobjeví.
const HIDDEN_M := 1.0
const MAX_ALIVE := 6
## Chycená příšera se zmenší na kámen za tolik sekund.
const SHRINK := 0.5
## Zmenšená příšera je asi takhle krát větší než kámen, pak ho vystřídá.
const SHRINK_TO_STONE := 1.3
## Nápis po sebrání kamene vystoupá o FLOAT_RISE pixelů obrazovky a za FLOAT_TIME sekund zmizí.
const FLOAT_TIME := 1.6
const FLOAT_RISE := 36.0
## Kámen nad vodou nebo v překážce (létající, vodní příšera) se posune na nejbližší místo,
## kam postava dojde, nejdál tolik metrů po STONE_STEP metrech.
const STONE_REACH := 4.0
const STONE_STEP := 0.25
## Vykreslení shaderů při startu (_warm) se uklidí po tolika snímcích.
const WARM_FRAMES := 3
## Sbírání materiálů: příšera krouží kolem kamene ve vzdálenosti GUARD_RING metrů (od středu
## ke středu). Honí rychlostí úprku plus CHASE_BONUS m/s a nechá toho, kdo je dál
## než GIVE_UP_M metrů. Kámen, který příšera vzala zpátky, ROB_CALM sekund nejde sebrat.
const GUARD_RING := 7.0
const CHASE_BONUS := 0.5
const GIVE_UP_M := 10.0
const ROB_CALM := 1.0
## Hledání místa pro příšeru na kruhu kolem kamene: tolik pootočení.
const GUARD_TRIES := 8
## Nápis o ztrátě kamene je červený.
const LOSS_COLOR := Color(1.0, 0.42, 0.36)

signal scored(points: int, caught: int)
signal finished(points: int, caught: int)

## Nápis nad toulající se příšerou: velikost písma a obrysu na obrazovce, šířka a výška
## řádku a o kolik pixelů obrazovky je nad tělem.
const TAG_FONT := 13
const TAG_OUTLINE := 4
const TAG_WIDTH := 260.0
const TAG_LINE := 19.0
## Barva jména a mezera mezi jménem a body v pixelech obrazovky.
const TAG_COLOR := Color(0.98, 0.93, 0.8)
const TAG_GAP := 5
## Barva bodů podle jejich počtu: do TAG_POINTS[0] první barva, do TAG_POINTS[1] druhá, víc třetí.
const TAG_POINTS: Array[int] = [50, 100]
const TAG_POINT_COLORS: Array[Color] = [Color(0.62, 0.9, 0.42), Color(1.0, 0.82, 0.25), Color(0.92, 0.55, 1.0)]
const TAG_LIFT_PX := 8.0
## Po začátku úprku zůstane nápis vidět ještě tolik sekund, ať hráč stihne přečíst, co honí.
const TAG_FLEE_KEEP := 2.5
## Úprk a viditelnost nápisů se kontrolují jen po tolika sekundách. Pozice viditelných nápisů
## se posouvá každý snímek, ať nápis za příšerou neposkakuje.
const TAG_CHECK := 0.5
## Tolik stoupajících nápisů se při startu připraví navíc k nápisům živých příšer. Nový držák
## s Labely stojí asi ms, ve hře by zadrhl snímek sebrání kamene.
const SPARE_FLOATS := 3

class Prey:
	var monster: Monster
	var creature: Dictionary
	## Nápis „jméno +body“, držák s Labelem pod tags.
	var tag: Node2D
	## Jak dlouho už příšera utíká, v sekundách. Při toulání 0.
	var fleeing_for := 0.0
	## Sbírání materiálů: kámen, který příšera hlídá, null když ho hráč sebral.
	var stone: Stone
	## Sbírání materiálů: sebraný kámen, kvůli kterému příšera honí. null, když nehoní.
	var carried: Stone


## Kámen na zemi, čeká na sebrání: po chycené příšeře, nebo hlídaný (Sbírání materiálů).
class Stone:
	var sprite: Sprite2D
	var title: String
	var points := 0
	var material := -1
	## Kolik sekund ještě nejde sebrat (po návratu k příšeře).
	var calm := 0.0


## Nápis nad sebraným kamenem, stoupá a mizí.
class Rising:
	var tag: Node2D
	var at: Vector2
	var age := 0.0


var points := 0
var caught_count := 0
var time_left := SECONDS
## Druhy podle hunt.json: kind, title, gender, points, flee (Vector2 od, do v m/s), surfaces,
## day, night, forbidden (množina čísel materiálů), flying, aquatic, body (px) a chase (m/s, honička druhu,
## Monster bere rychlost jako její násobek).
var _species: Array[Dictionary] = []
## Materiály podle hunt.json: material (číslo), adjective, points (násobitel), speedup,
## surfaces, day, night.
var _materials: Array[Dictionary] = []
## Těla chodících příšer v pixelech. Hranice skal pro ně počítá vlákno s tvorbou čtverce
## (Rocks.prepare_bounds), na hlavním vlákně by výpočet zasekl hru.
var bodies := PackedFloat64Array()
var _crystal: Crystal
var _board
var _camera: MapCamera
var _persons: Array[Person] = []
var _host: Node2D
var crowd: Crowd
## Staví příšery. Sám je ve scéně nedrží, příšery jsou v _host.
var _maker: Monsters
## Chodec všech příšer přes celý svět.
var _walker: Walker
var _alive: Array[Prey] = []
var _stones: Array[Stone] = []
var _floats: Array[Rising] = []
## Schované příšery podle druhu: kind -> Array[Monster].
var _pool := {}
## Vybrané místo, příšera se objeví v dalším snímku: spot, creature (vylosovaná kombinace,
## viz _draw) a monster, když už je vzatá ze zásoby. Prázdné nic.
var _pending := {}
## Místo kamene příšery, která se právě objevuje (Sbírání materiálů).
var _pending_stone := Vector2.ZERO
## Střed kamery po sekundách, nejvýš MOVED_SECONDS + 1 posledních.
var _track := PackedVector2Array()
var _track_left := 0.0
var _spawn_left := SPAWN_MIN
var _day := true
var _rng := RandomNumberGenerator.new()
var _over := false
## Sbírání materiálů (GameSession.COLLECT), jinak Chytej příšery.
var _collect := false
## Nápisy nad toulajícími se příšerami (Sbírání materiálů: nad hlídanými kameny). Jsou na
## obrazovce ve vrstvě HUD, ne ve světě, ať jsou ostré i při nižším rozlišení světa. Do vrstvy
## je přidá WorldBoard. Utíkající příšera nápis po chvíli schová. Ukázané se posouvají každý snímek těsně před
## kreslením, až po kameře, je jich nejvýš MAX_ALIVE. Držáky se po uklizení příšery vrací
## do _spare_tags.
var tags := Node2D.new()
var _spare_tags: Array[Node2D] = []
var _tag_check_left := 0.0


## Přečte hunt.json a načte vzhled příšer dopředu. Volá se před tvorbou prvního čtverce,
## bodies pak smí číst vlákna.
func load_catalog(crystal: Crystal) -> void:
	_crystal = crystal
	_collect = GameSession.mode == GameSession.COLLECT
	# V benchmarku se příšery objevují pokaždé stejně.
	Benchmark.seed_rng(_rng, 3)
	_maker = Monsters.new()
	_maker.name = "Maker"
	add_child(_maker)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG)) if FileAccess.file_exists(CATALOG) else null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst tabulku příšer (hunt.json).")
		return
	var index := {}
	for i in crystal.count():
		index[crystal.name_of(i)] = i
	var listed: Dictionary = (parsed as Dictionary).get("materials", {})
	for key: String in listed:
		if not index.has(key):
			push_warning("Tabulka příšer chce materiál %s, ten chybí." % key)
			continue
		var entry: Dictionary = listed[key]
		var time: Dictionary = entry.get("time", {})
		_materials.append({
			"material": int(index[key]),
			"adjective": str(entry.get("adjective", key)),
			"points": float(entry.get("points", 1.0)),
			"speedup": clampf(float(entry.get("speedup", 0.0)), 0.0, 1.0),
			"surfaces": entry.get("surfaces", {}),
			"day": float(time.get("day", 1.0)),
			"night": float(time.get("night", 1.0)),
		})
	listed = (parsed as Dictionary).get("species", {})
	for kind: String in listed:
		var info := _maker.species_info(kind)
		if info.is_empty():
			continue
		var entry: Dictionary = listed[kind]
		var forbidden := {}
		for key: Variant in entry.get("forbidden", []):
			if index.has(str(key)):
				forbidden[int(index[str(key)])] = true
		var flee: Array = entry.get("flee", [3.0, 4.0])
		var time: Dictionary = entry.get("time", {})
		_maker.preload_looks(kind)
		var body := float(info.get("body_meters", 0.4)) * float(TerrainCatalog.TILE_SIZE)
		if not bool(info.get("flying", false)) and not bodies.has(body):
			bodies.append(body)
		_species.append({
			"kind": kind,
			"title": str(entry.get("title", kind)),
			"gender": str(entry.get("gender", "m")),
			"points": float(entry.get("points", 10)),
			"flee": Vector2(float(flee[0]), float(flee[1])),
			"surfaces": entry.get("surfaces", {}),
			"day": float(time.get("day", 1.0)),
			"night": float(time.get("night", 1.0)),
			"forbidden": forbidden,
			"flying": bool(info.get("flying", false)),
			"aquatic": bool(info.get("aquatic", false)),
			"body": body,
			"chase": maxf(float(info.get("chase_meters", 5.0)), 0.1),
		})


## surfaces: katalog povrchů (MapData.surfaces), z něj rychlost chůze příšer. Postaví zásobu
## příšer a jednou vykreslí jejich shadery.
func start(board, camera: MapCamera, persons: Array[Person], host: Node2D, phase: float, surfaces: Dictionary) -> void:
	_board = board
	_camera = camera
	_persons = persons
	_host = host
	_day = phase < 0.5
	_walker = Walker.new()
	_walker.world_board = board
	_walker.crowd = crowd
	_walker.use_surfaces(surfaces)
	RenderingServer.frame_pre_draw.connect(_follow_tags)
	if _materials.is_empty():
		push_error("Tabulka příšer nemá žádný materiál.")
		return
	for species in _species:
		var creature := _creature(species, _materials[0])
		var monster := _build(creature)
		if monster != null:
			_park(monster, str(creature["kind"]))
	for i in MAX_ALIVE + SPARE_FLOATS:
		var holder := _make_tag()
		holder.visible = false
		_spare_tags.append(holder)
	_warm()


func tick(delta: float, phase: float) -> void:
	if _over:
		return
	time_left = maxf(time_left - delta, 0.0)
	_day = phase < 0.5
	if _collect:
		_take_guarded(delta)
		_follow_chases()
	else:
		_catch()
	_pick_stones()
	_place_tags(delta)
	_age_floats(delta)
	_track_left -= delta
	if _track_left <= 0.0:
		_track_left = 1.0
		_follow()
		_forget()
	if not _pending.is_empty():
		_advance()
	else:
		_spawn_left -= delta
		if _spawn_left <= 0.0:
			if _room() and _spawn():
				_spawn_left = _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
			else:
				_spawn_left = RETRY
	if time_left <= 0.0:
		_over = true
		finished.emit(points, caught_count)


## Hraje hudba honičky? Když některá příšera honí, nebo na obrazovce utíká.
func any_chase() -> bool:
	var view := _view(0.0)
	for prey in _alive:
		if prey.monster.is_chasing():
			return true
		if prey.monster.is_fleeing() and view.has_point(prey.monster.position):
			return true
	return false


## Zapíše střed kamery, ať je vidět, kam se hráči posouvají.
func _follow() -> void:
	_track.append(_camera.get_screen_center_position())
	if _track.size() > MOVED_SECONDS + 1:
		_track.remove_at(0)


## Uklidí příšery dál od všech postav, než je delší strana obrazovky. Ty už nikdo nevidí.
func _forget() -> void:
	var size := _view(0.0).size
	var far := maxf(size.x, size.y)
	for i in range(_alive.size() - 1, -1, -1):
		var prey := _alive[i]
		if prey.monster.is_chasing():
			continue
		var at := prey.stone.sprite.position if prey.stone != null else prey.monster.position
		if _nearest(at) > far and _nearest(prey.monster.position) > far:
			_release(prey)
	for i in range(_stones.size() - 1, -1, -1):
		if _nearest(_stones[i].sprite.position) > far:
			_stones[i].sprite.queue_free()
			_stones.remove_at(i)


## Je místo na další příšeru? Když je plno, uklidí nejstarší, která není na obrazovce
## a nehoní (ani její kámen není vidět).
func _room() -> bool:
	if _alive.size() < MAX_ALIVE:
		return true
	var view := _view(HIDDEN_M * float(TerrainCatalog.TILE_SIZE))
	for prey in _alive:
		if prey.monster.is_chasing():
			continue
		if prey.stone != null and view.has_point(prey.stone.sprite.position):
			continue
		if not view.has_point(prey.monster.position):
			_release(prey)
			return true
	return false


## Váha druhu nebo materiálu entry na povrchu terrain v nynější denní době.
func _weight(entry: Dictionary, terrain: String) -> float:
	var surfaces: Dictionary = entry["surfaces"]
	return maxf(float(surfaces.get(terrain, 0.0)), 0.0) * maxf(float(entry["day" if _day else "night"]), 0.0)


## Položka z items podle vah weights. Prázdná, když jsou všechny váhy nulové.
func _pick(items: Array[Dictionary], weights: PackedFloat32Array) -> Dictionary:
	var total := 0.0
	for weight in weights:
		total += weight
	if total <= 0.0:
		return {}
	var roll := _rng.randf() * total
	for i in items.size():
		roll -= weights[i]
		if roll < 0.0 and weights[i] > 0.0:
			return items[i]
	for i in range(items.size() - 1, -1, -1):
		if weights[i] > 0.0:
			return items[i]
	return {}


## Příšera druhu species z materiálu material: kind, material, title, points, speed (násobek
## honičky druhu: úprk, ve Sbírání materiálů o CHASE_BONUS m/s rychlejší), flying,
## aquatic a body.
func _creature(species: Dictionary, material: Dictionary) -> Dictionary:
	var flee: Vector2 = species["flee"]
	var meters := flee.x + (flee.y - flee.x) * float(material["speedup"])
	var ending := {"f": "á", "n": "é"}.get(str(species["gender"]), "ý") as String
	return {
		"kind": species["kind"],
		"material": material["material"],
		"title": "%s %s%s" % [species["title"], material["adjective"], ending],
		"points": roundi(float(species["points"]) * float(material["points"])),
		"speed": (meters + (CHASE_BONUS if _collect else 0.0)) / float(species["chase"]),
		"flying": species["flying"],
		"aquatic": species["aquatic"],
		"body": species["body"],
	}


## Místo před hráči ve směru, kam se kamera posunula, a příšera pro něj. Objeví se až
## v dalších snímcích (_advance). false, když se místo nenašlo.
func _spawn() -> bool:
	if _track.size() <= MOVED_SECONDS:
		return false
	var moved := _track[_track.size() - 1] - _track[0]
	var tile := float(TerrainCatalog.TILE_SIZE)
	if moved.length() < MOVED_M * tile:
		return false
	var view := _view(0.0)
	var center := view.get_center()
	var half := view.size * 0.5
	var dir := moved.normalized()
	# Kde paprsek ze středu směrem dir opouští obrazovku.
	var edge := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var side := dir.orthogonal()
	var across := absf(side.x) * view.size.x + absf(side.y) * view.size.y
	var hidden := view.grow(HIDDEN_M * tile)
	for attempt in SPAWN_TRIES:
		var spot := center + dir * (edge + AHEAD_M * tile) + side * _rng.randf_range(-SIDE_SPREAD, SIDE_SPREAD) * across
		if hidden.has_point(spot) or not _board.has_ground(spot):
			continue
		var creature := _draw(spot, _swim_spot(spot, hidden))
		if creature.is_empty():
			continue
		if _collect:
			var stone: Vector2 = creature["spot"]
			var guard := _guard_spot(stone, creature)
			if guard == Vector2.INF:
				continue
			_pending = {"spot": guard, "stone": stone, "creature": creature}
		else:
			_pending = {"spot": creature["spot"], "creature": creature}
		return true
	return false


## Sbírání materiálů: místo pro příšeru na kruhu kolem kamene na stone, kde stojí na zemi
## (létající nad hotovým čtvercem, vodní ve vodě). Kruh je GUARD_RING, vodní druh zkusí i jeho
## polovinu. Vector2.INF, když se nenašlo, nebo když kámen nejde sebrat (postava tam nedojde).
func _guard_spot(stone: Vector2, creature: Dictionary) -> Vector2:
	if not _walker.stands(stone, Person.BODY) or _walker.blocked(stone, Person.BODY):
		return Vector2.INF
	var ring := guard_ring(creature)
	var start := _rng.randf() * TAU
	for i in GUARD_TRIES:
		var spot := stone + Vector2.from_angle(start + TAU * float(i) / float(GUARD_TRIES)) * ring
		if not _board.has_ground(spot):
			continue
		if bool(creature["flying"]):
			return spot
		if bool(creature["aquatic"]):
			if _walker.swims(spot):
				return spot
		elif not _walker.blocked(spot, float(creature["body"])):
			return spot
	if bool(creature["aquatic"]) and not creature.has("narrow"):
		creature["narrow"] = true
		return _guard_spot(stone, creature)
	return Vector2.INF


## Poloměr kroužení příšery creature kolem kamene v px. Vodní druh v úzké vodě má poloviční.
static func guard_ring(creature: Dictionary) -> float:
	var ring := GUARD_RING * float(TerrainCatalog.TILE_SIZE)
	return ring * 0.5 if creature.has("narrow") else ring


## Nejbližší brodítelná voda kolem spot pro vodní druh, mimo hidden. Vector2.INF, když žádná
## není nebo hra vodní druh nemá.
func _swim_spot(spot: Vector2, hidden: Rect2) -> Vector2:
	var any := false
	for species in _species:
		any = any or bool(species["aquatic"])
	var tile := float(TerrainCatalog.TILE_SIZE)
	if not any or not _board.may_swim_near(spot, SWIM_REACH * tile):
		return Vector2.INF
	var step := SWIM_STEP * tile
	var radius := 0.0
	while radius <= SWIM_REACH * tile:
		var around := 1 if radius == 0.0 else clampi(int(TAU * radius / step), 8, SWIM_AROUND)
		for i in around:
			var at := spot + Vector2.from_angle(TAU * float(i) / float(around)) * radius
			if _swims_wide(at) and not hidden.has_point(at) and _board.has_ground(at):
				return at
		radius += step
	return Vector2.INF


## Je v at brodítelná voda aspoň SWIM_WIDTH metrů na každou stranu?
func _swims_wide(at: Vector2) -> bool:
	if not _walker.swims(at):
		return false
	var reach := SWIM_WIDTH * float(TerrainCatalog.TILE_SIZE)
	for probe in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		if not _walker.swims(at + probe * reach):
			return false
	return true


## Vylosuje druh a pak materiál pro spot (viz popis třídy). wet je voda pro vodní druh
## (_swim_spot), bez ní vodní druh nepadne. Výsledek má i spot, kde se příšera objeví.
## Prázdné, když se žádný druh nebo materiál nehodí nebo chodící nemá kde stát.
func _draw(spot: Vector2, wet := Vector2.INF) -> Dictionary:
	var terrain := _walker.surface(spot)
	var wet_terrain := _walker.surface(wet) if wet != Vector2.INF else ""
	var dry := _walker.dry(spot)
	var weights := PackedFloat32Array()
	for entry in _species:
		if bool(entry["aquatic"]):
			weights.append(_weight(entry, wet_terrain) if wet != Vector2.INF else 0.0)
		elif _collect:
			# Kámen leží tam, kam postava dojde, i když jeho příšera létá.
			weights.append(_weight(entry, terrain) if dry else 0.0)
		else:
			weights.append(_weight(entry, terrain) if dry or bool(entry["flying"]) else 0.0)
	var species := _pick(_species, weights)
	if species.is_empty():
		return {}
	if bool(species["aquatic"]):
		spot = wet
		terrain = wet_terrain
	var forbidden: Dictionary = species["forbidden"]
	weights.clear()
	for entry in _materials:
		weights.append(0.0 if forbidden.has(entry["material"]) else _weight(entry, terrain))
	var material := _pick(_materials, weights)
	if material.is_empty():
		return {}
	if not _collect and not bool(species["flying"]) and not bool(species["aquatic"]) and _walker.blocked(spot, float(species["body"])):
		return {}
	var creature := _creature(species, material)
	creature["spot"] = spot
	return creature


## Další krok objevení vybrané příšery, jeden za snímek: vzít ji ze zásoby (prázdná
## zásoba druhu ji postaví), pak ji ukázat na místě.
func _advance() -> void:
	var creature: Dictionary = _pending["creature"]
	if not _pending.has("monster"):
		var stock: Array = _pool.get(str(creature["kind"]), [])
		var monster: Monster = stock.pop_back() if not stock.is_empty() else _build(creature)
		if monster == null:
			_pending = {}
			return
		var mat := int(creature["material"])
		monster.repaint(mat, _maker.colors_of(_crystal, mat, _maker.species_info(str(creature["kind"]))), float(creature["speed"]))
		_pending["monster"] = monster
		return
	var monster: Monster = _pending["monster"]
	var spot: Vector2 = _pending["spot"]
	_pending_stone = _pending.get("stone", spot)
	_pending = {}
	monster.reuse(spot)
	if crowd != null and not monster.is_flying():
		monster.crowd_id = crowd.join(monster)
	var prey := Prey.new()
	prey.monster = monster
	prey.creature = creature
	if _collect:
		var mat := int(creature["material"])
		prey.stone = _lay_stone(_pending_stone, mat, _crystal.title_of(mat), int(creature["points"]))
		monster.guard_at(prey.stone.sprite.position, guard_ring(creature))
		prey.tag = _take_tag(prey.stone.title, prey.stone.points)
	else:
		prey.tag = _take_tag(str(creature["title"]), int(creature["points"]))
	# Nový nápis se ukáže hned, ne až při další kontrole.
	prey.tag.visible = _watched(_tag_anchor(prey))
	_put_tag(prey)
	_alive.append(prey)


## Nová příšera pro zásobu. Ve skupině tvorů (crowd) není, přidá se až při objevení.
func _build(creature: Dictionary) -> Monster:
	_walker.crowd = null
	var at := _camera.get_screen_center_position()
	var monster: Monster = _maker.make(str(creature["kind"]), int(creature["material"]), _crystal, _walker, _persons,
		_camera, _host, _rng, at, float(creature["speed"]))
	_walker.crowd = crowd
	if monster != null:
		monster.park()
	return monster


## Vrátí příšeru do zásoby jejího druhu.
func _park(monster: Monster, kind: String) -> void:
	monster.park()
	if not _pool.has(kind):
		_pool[kind] = []
	(_pool[kind] as Array).append(monster)


## Jednou vykreslí vrstvy všech příšer do malého obrázku mimo obrazovku. Shadery a textury
## se tak připraví hned při startu, ne až u první příšery každého druhu.
func _warm() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(64, 64)
	view.disable_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	for species in _species:
		for sprite in _maker.sample_layers(str(species["kind"])):
			sprite.position = Vector2(32, 32)
			view.add_child(sprite)
	for frame in WARM_FRAMES:
		await get_tree().process_frame
	view.queue_free()


## Dotkla se postava příšery? Pak je chycená.
func _catch() -> void:
	for i in range(_alive.size() - 1, -1, -1):
		var prey := _alive[i]
		var reach := prey.monster.touch()
		for person in _persons:
			if is_instance_valid(person) and person.position.distance_squared_to(prey.monster.position) <= reach * reach:
				_caught(prey)
				break


## Chycená příšera dobíhá a zmenšuje se, pak ji vystřídá kámen. Body až za kámen.
func _caught(prey: Prey) -> void:
	var monster := prey.monster
	_alive.erase(prey)
	_drop_tag(prey)
	_leave_crowd(monster)
	# Obrázek příšery je asi dvakrát širší než její tělo.
	var end := clampf(_crystal.radius() * SHRINK_TO_STONE / (monster.crowd_body() * 2.0), 0.03, 0.6)
	monster.shrink(SHRINK, end, _to_stone.bind(prey))
	caught_count += 1
	scored.emit(points, caught_count)


## Zmenšenou příšeru vystřídá na zemi kámen jejího materiálu, příšera jde do zásoby.
func _to_stone(prey: Prey) -> void:
	var monster := prey.monster
	var stone := _lay_stone(_stone_spot(monster.global_position), int(prey.creature["material"]),
		str(prey.creature["title"]), int(prey.creature["points"]))
	_stones.append(stone)
	_park(monster, str(prey.creature["kind"]))
	Sound.at("sfx/land", stone.sprite.position, 2.0)


## Kámen materiálu mat na zemi v at, s názvem title a body points pro nápis.
func _lay_stone(at: Vector2, mat: int, title: String, points: int) -> Stone:
	var stone := Stone.new()
	stone.title = title
	stone.points = points
	stone.material = mat
	stone.sprite = _crystal.make_sprite()
	stone.sprite.z_index = 3
	_host.add_child(stone.sprite)
	stone.sprite.global_position = at
	stone.sprite.rotation = _rng.randf() * TAU
	_crystal.paint(stone.sprite, mat, 0.0, _rng.randf() * TAU)
	return stone


## Místo pro kámen: at, nebo nejbližší, kde postava stojí, když at leží ve vodě nebo v překážce.
func _stone_spot(at: Vector2) -> Vector2:
	if not _walker.blocked(at, Person.BODY):
		return at
	var tile := float(TerrainCatalog.TILE_SIZE)
	var spot := _walker.free_spot(at, Person.BODY, STONE_REACH * tile, STONE_STEP * tile)
	return at if spot == Vector2.INF else spot


## Kámen, kterého se dotkne postava, zmizí a hráči dostanou jeho body.
func _pick_stones() -> void:
	var reach := Person.BODY + _crystal.radius()
	for i in range(_stones.size() - 1, -1, -1):
		var stone := _stones[i]
		var at := stone.sprite.position
		for person in _persons:
			if is_instance_valid(person) and person.position.distance_squared_to(at) <= reach * reach:
				_stones.remove_at(i)
				stone.sprite.queue_free()
				points += stone.points
				scored.emit(points, caught_count)
				Sound.at("sfx/pickup", at, 2.0)
				_float_tag(stone.title, stone.points, at)
				break


## Sbírání materiálů: kámen, kterého se dotkne postava, je její. Hráči dostanou body, postava
## ho nese v ruce a příšera, která ho hlídala, ji začne honit. Kdo postavu honil dřív, přestane.
func _take_guarded(delta: float) -> void:
	var reach := Person.BODY + _crystal.radius()
	for prey in _alive:
		var stone := prey.stone
		if stone == null:
			continue
		if stone.calm > 0.0:
			stone.calm -= delta
			continue
		var at := stone.sprite.position
		for person in _persons:
			if is_instance_valid(person) and person.position.distance_squared_to(at) <= reach * reach:
				_take(prey, person)
				break


func _take(prey: Prey, person: Person) -> void:
	var stone := prey.stone
	prey.stone = null
	prey.tag.visible = false
	stone.sprite.queue_free()
	points += stone.points
	caught_count += 1
	scored.emit(points, caught_count)
	Sound.at("sfx/pickup", stone.sprite.position, 2.0)
	_float_tag(stone.title, stone.points, stone.sprite.position)
	for other in _alive:
		if other.monster.prey() == person:
			_call_off(other)
	person.hold(stone.material, stone.points)
	prey.carried = stone
	prey.monster.chase(person)


## Honička skončila a kámen si hráči nechají. Příšera se vrátí kroužit tam, kde kámen ležel.
func _call_off(prey: Prey) -> void:
	prey.carried = null
	prey.monster.stop_chase()


## Honící příšery: dohnaná postava kámen ztratí, vzdálená si ho nechá.
func _follow_chases() -> void:
	var far := GIVE_UP_M * float(TerrainCatalog.TILE_SIZE)
	for prey in _alive:
		var person := prey.monster.prey() as Person
		if person == null or prey.carried == null:
			continue
		var dist := person.position.distance_to(prey.monster.position)
		if dist <= prey.monster.touch():
			_robbed(prey, person)
		elif dist > far:
			var mat := prey.carried.material
			_call_off(prey)
			if person.carried() == mat:
				person.drop_held()


## Příšera dohnala postavu: body za kámen se odečtou a kámen spadne pod ni. Příšera kolem
## něj zase krouží a chvíli ho nejde sebrat.
func _robbed(prey: Prey, person: Person) -> void:
	var lost := prey.carried
	prey.carried = null
	points -= lost.points
	caught_count -= 1
	scored.emit(points, caught_count)
	person.drop_held()
	var at := _stone_spot(prey.monster.global_position)
	Sound.at("sfx/steal", at, 2.0)
	_float_tag(lost.title, lost.points, person.position, true)
	prey.stone = _lay_stone(at, lost.material, lost.title, lost.points)
	prey.stone.calm = ROB_CALM
	prey.monster.guard_at(at, guard_ring(prey.creature))


## Nápis „jméno +body“ nad místem at, stejný jako u příšery. Vystoupá a zmizí. lost ukáže
## ztrátu: „jméno −body“ červeně.
func _float_tag(title: String, gained: int, at: Vector2, lost := false) -> void:
	var rising := Rising.new()
	rising.tag = _take_tag(title, gained)
	if lost:
		var score := rising.tag.get_child(0).get_child(1) as Label
		score.text = "−%d" % gained
		score.add_theme_color_override("font_color", LOSS_COLOR)
	rising.tag.visible = true
	rising.at = at
	_floats.append(rising)
	_put_float(rising)


func _age_floats(delta: float) -> void:
	for i in range(_floats.size() - 1, -1, -1):
		var rising := _floats[i]
		rising.age += delta
		var t := rising.age / FLOAT_TIME
		if t >= 1.0:
			rising.tag.visible = false
			rising.tag.modulate.a = 1.0
			_spare_tags.append(rising.tag)
			_floats.remove_at(i)
			continue
		# Nejdřív chvíli plný, pak mizí.
		rising.tag.modulate.a = clampf((1.0 - t) / 0.6, 0.0, 1.0)


func _put_float(rising: Rising) -> void:
	var view := tags.get_viewport().canvas_transform
	var rise := FLOAT_RISE * (1.0 - pow(1.0 - rising.age / FLOAT_TIME, 2.0))
	rising.tag.position = view * rising.at - Vector2(0.0, TAG_LIFT_PX + rise)


## Uklidí příšeru do zásoby, s ní i kámen, který hlídá.
func _release(prey: Prey) -> void:
	_alive.erase(prey)
	_drop_tag(prey)
	if prey.stone != null:
		prey.stone.sprite.queue_free()
		prey.stone = null
	_leave_crowd(prey.monster)
	_park(prey.monster, str(prey.creature["kind"]))


func _leave_crowd(monster: Monster) -> void:
	if crowd != null and monster.crowd_id >= 0:
		crowd.leave(monster.crowd_id)
	monster.crowd_id = -1


## Posune nápisy nad příšery. Velikost drží na obrazovce stejnou. Nápis je vidět, když k příšeře
## míří některý hráč (_watched), utíkající ho schová, až utíká déle než TAG_FLEE_KEEP sekund.
## Obojí se kontroluje po TAG_CHECK sekundách.
func _place_tags(delta: float) -> void:
	_tag_check_left -= delta
	var check := _tag_check_left <= 0.0
	if check:
		_tag_check_left = TAG_CHECK
	for prey in _alive:
		if check and _collect:
			prey.tag.visible = prey.stone != null and _watched(prey.stone.sprite.position)
		elif check:
			prey.fleeing_for = prey.fleeing_for + TAG_CHECK if prey.monster.is_fleeing() else 0.0
			# První kontrola úprku počítá celé TAG_CHECK, i když začal těsně před ní. Nápis
			# proto zmizí až po TAG_FLEE_KEEP až TAG_FLEE_KEEP + TAG_CHECK sekundách.
			prey.tag.visible = prey.fleeing_for <= TAG_FLEE_KEEP and _watched(prey.monster.position)


## Ukázané nápisy nad své příšery a sebrané kameny, podle záběru, který se právě nakreslí.
func _follow_tags() -> void:
	for prey in _alive:
		if prey.tag.visible:
			_put_tag(prey)
	for rising in _floats:
		_put_float(rising)


## Míří některý hráč k bodu at? Ve výseči jako kužel čelovky (DayNight.LAMP_HALF i s měkkým
## okrajem) kolem směru, kam postava jde nebo naposledy šla. Na vzdálenost nezáleží, těsně
## u postavy vždy.
func _watched(at: Vector2) -> bool:
	var cone := cos(DayNight.LAMP_HALF)
	for person in _persons:
		if not is_instance_valid(person):
			continue
		var to := at - person.position
		if to.length_squared() < 1.0:
			return true
		var forward := Vector2.from_angle(person.rotation - PI * 0.5)
		if forward.dot(to.normalized()) >= cone:
			return true
	return false


## Nápis nad tělem příšery (nad kamenem). Je na obrazovce, poloha je místo v záběru kamery.
func _put_tag(prey: Prey) -> void:
	var view := tags.get_viewport().canvas_transform
	var top := _tag_anchor(prey)
	if _collect:
		top -= Vector2(0.0, _crystal.radius())
	else:
		top -= Vector2(0.0, prey.monster.crowd_body())
	prey.tag.position = view * top - Vector2(0.0, TAG_LIFT_PX)


## Kde nápis příšery visí: nad hlídaným kamenem, v Chytej příšery nad příšerou.
func _tag_anchor(prey: Prey) -> Vector2:
	if _collect and prey.stone != null:
		return prey.stone.sprite.global_position
	return prey.monster.global_position


## Nápis „jméno +body“ ze zásoby, nebo nový. Body mají barvu podle počtu (TAG_POINT_COLORS).
func _take_tag(title: String, gained: int) -> Node2D:
	var holder: Node2D = _spare_tags.pop_back() if not _spare_tags.is_empty() else _make_tag()
	holder.modulate.a = 1.0
	var row := holder.get_child(0)
	(row.get_child(0) as Label).text = title
	var score := row.get_child(1) as Label
	score.text = "+%d" % gained
	var grade := 0
	while grade < TAG_POINTS.size() and gained > TAG_POINTS[grade]:
		grade += 1
	score.add_theme_color_override("font_color", TAG_POINT_COLORS[grade])
	holder.visible = false
	return holder


func _drop_tag(prey: Prey) -> void:
	if prey.tag == null:
		return
	prey.tag.visible = false
	_spare_tags.append(prey.tag)
	prey.tag = null


## Držák s řádkem jméno a body, spodní okraj textu leží na držáku. Řádek je vycentrovaný.
## Styl jako nápisy dolů, menší.
func _make_tag() -> Node2D:
	var holder := Node2D.new()
	tags.add_child(holder)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", TAG_GAP)
	row.size = Vector2(TAG_WIDTH, TAG_LINE)
	row.position = Vector2(-TAG_WIDTH * 0.5, -TAG_LINE)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(row)
	for part in 2:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", TAG_FONT)
		label.add_theme_color_override("font_color", TAG_COLOR)
		label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
		label.add_theme_constant_override("outline_size", TAG_OUTLINE)
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.size_flags_vertical = Control.SIZE_FILL
		row.add_child(label)
	return holder


## Vzdálenost od pos k nejbližší postavě v pixelech.
func _nearest(pos: Vector2) -> float:
	var best := INF
	for person in _persons:
		if is_instance_valid(person):
			best = minf(best, pos.distance_to(person.position))
	return best


## Obrazovka ve světě zvětšená o margin pixelů na každou stranu.
func _view(margin: float) -> Rect2:
	var view := _camera.get_viewport_rect().size / _camera.zoom
	return Rect2(_camera.get_screen_center_position() - view * 0.5, view).grow(margin)


# --- Výkony ---

## Zda se výkon score vejde mezi RECORDS_KEPT nejlepších pro tolik hráčů. Při shodě
## zůstává výš dřívější výkon, nový tedy musí mít víc bodů než poslední.
static func qualifies(players: int, score: int) -> bool:
	var rows := records(players)
	return rows.size() < RECORDS_KEPT or score > int(rows[-1]["points"])


## Zapíše výkon pod jménem name a vrátí jeho pořadí pro stejný počet hráčů (od 1), 0 když
## se mezi RECORDS_KEPT nejlepších nevešel. Horší výkony nad RECORDS_KEPT se smažou.
## Jméno se zapamatuje pro příští hru s tolika hráči.
static func record(players: int, score: int, caught: int, name: String) -> int:
	var config := ConfigFile.new()
	config.load(_records_path())
	var id := "%d_%d" % [Time.get_unix_time_from_system(), randi()]
	config.set_value(id, "players", players)
	config.set_value(id, "name", name)
	config.set_value(id, "points", score)
	config.set_value(id, "caught", caught)
	config.set_value(id, "date", int(Time.get_unix_time_from_system()))
	config.set_value(NAMES, str(players), name)
	var rows := _rows(config, players)
	var rank := 0
	for i in rows.size():
		if i >= RECORDS_KEPT:
			config.erase_section(str(rows[i]["id"]))
		elif str(rows[i]["id"]) == id:
			rank = i + 1
	config.save(_records_path())
	return rank


## Jméno naposledy zapsané pro tolik hráčů, nebo prázdné.
static func last_name(players: int) -> String:
	var config := ConfigFile.new()
	if config.load(_records_path()) != OK:
		return ""
	return str(config.get_value(NAMES, str(players), ""))


## Nejvýš RECORDS_KEPT výkonů pro tolik hráčů od nejvíc bodů. Při shodě dřív dosažený výš.
static func records(players: int) -> Array[Dictionary]:
	var config := ConfigFile.new()
	if config.load(_records_path()) != OK:
		return []
	var rows := _rows(config, players)
	rows.resize(mini(rows.size(), RECORDS_KEPT))
	return rows


static func _rows(config: ConfigFile, players: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in config.get_sections():
		if id == NAMES or int(config.get_value(id, "players", 0)) != players:
			continue
		out.append({
			"id": id,
			"name": str(config.get_value(id, "name", "")),
			"points": int(config.get_value(id, "points", 0)),
			"caught": int(config.get_value(id, "caught", 0)),
			"date": int(config.get_value(id, "date", 0)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["points"]) != int(b["points"]):
			return int(a["points"]) > int(b["points"])
		return int(a["date"]) < int(b["date"]))
	return out


## Tabulka výkonů režimu, který se hraje.
static func _records_path() -> String:
	return COLLECT_RECORDS if GameSession.mode == GameSession.COLLECT else RECORDS


## Název režimu pro HUD.
static func title() -> String:
	return "Sbírání materiálů" if GameSession.mode == GameSession.COLLECT else "Chytej příšery"


## Nadpis sloupce počtu v tabulce výkonů.
static func count_caption() -> String:
	return "Sebráno" if GameSession.mode == GameSession.COLLECT else "Chyceno"


## „chyceno 3 příšery“, „sebráno 5 kamenů“ podle režimu.
static func count_text(count: int) -> String:
	if GameSession.mode == GameSession.COLLECT:
		return "sebráno " + _counted(count, "kámen", "kameny", "kamenů")
	return "chyceno " + _counted(count, "příšera", "příšery", "příšer")


## „1 kámen“, „3 kameny“, „5 kamenů“.
static func _counted(count: int, one: String, few: String, many: String) -> String:
	if count == 1:
		return "1 " + one
	return "%d %s" % [count, few if count >= 2 and count <= 4 else many]
