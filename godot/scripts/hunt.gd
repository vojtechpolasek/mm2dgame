extends Node

## Chytej příšery. Volný pohyb, ve kterém se před hráči objevují příšery. Hráči je za SECONDS
## sekund chytají dotykem a sbírají společné body. Výkony se zapisují podle počtu hráčů.
##
## Každou sekundu se zapíše, kde je střed kamery (ukazuje všechny hráče). Příšera se objeví,
## když se kamera za posledních MOVED_SECONDS sekund posunula aspoň o MOVED_M metrů: tím
## směrem AHEAD_M metrů za okrajem obrazovky, náhodně posunutá do strany nejvýš o SIDE_SPREAD
## šířky obrazovky napříč. Další přijde za SPAWN_MIN až SPAWN_MAX sekund. Když se nepovede
## (hráči stojí, místo je ve vodě, v překážce nebo na čtverci, který ještě není hotový),
## zkusí se znovu za RETRY sekund.
## Vylosuje se z hunt.json: z těch, které povolují terén pod místem a denní dobu,
## s pravděpodobností podle váhy. Na vodě jen létající. Živých je nejvýš MAX_ALIVE: když
## je plno, nová vytlačí nejstarší, která není na obrazovce. Denní doba se kontroluje jen při
## losování, objevená příšera zůstane i po změně dne a noci.
## Jednou za sekundu se uklidí příšera, která je od všech postav dál, než je delší strana
## obrazovky. Příšery se toulají bez mřížky cest a utíkají kamkoli (Monster.hunt).
## Chycená příšera pozvolna zprůhlední (Monster.fade).
##
## Ať se hra při objevení příšery necukne: příšery se nestaví, berou se ze zásoby schovaných
## (_pool, od každého druhu jedna postavená při startu, další přibude, když je zásoba druhu
## prázdná). Uklizená i chycená příšera se do zásoby vrací. Výběr místa a objevení jsou
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

const CATALOG := "res://graphics/characters/monsters/hunt.json"
const RECORDS := "user://hunt_records.cfg"
## Výkonů se pro každý počet hráčů drží tolik. Sekce NAMES drží poslední jména.
const RECORDS_KEPT := 30
const NAMES := "names"
## Délka hry v sekundách.
const SECONDS := 540.0
const SPAWN_MIN := 5.0
const SPAWN_MAX := 9.0
const RETRY := 1.0
const MOVED_SECONDS := 3
const MOVED_M := 6.0
const AHEAD_M := 3.0
const SIDE_SPREAD := 0.3
## Když místo nejde (voda, nehotový čtverec, překážka), zkusí se jiný posun, nejvýš tolikrát.
const SPAWN_TRIES := 4
## Obrazovka zvětšená o tolik metrů na každou stranu: tam se nikdo neobjeví.
const HIDDEN_M := 1.0
const MAX_ALIVE := 6
## Chycená příšera zprůhlední za tolik sekund.
const FADE := 1.0
## Hláška po chycení svítí tolik sekund.
const CATCH_NOTICE := 2.0
## Vykreslení shaderů při startu (_warm) se uklidí po tolika snímcích.
const WARM_FRAMES := 3

signal scored(points: int, caught: int)
signal finished(points: int, caught: int)

class Prey:
	var monster: Monster
	var creature: Dictionary


var points := 0
var caught_count := 0
var time_left := SECONDS
## Příšery podle hunt.json: material (číslo), title, weight, points, time, terrains (množina),
## flying, body (px) a speed (úprk flee v m/s jako násobek rychlosti honičky druhu).
var _creatures: Array[Dictionary] = []
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
## Schované příšery podle materiálu: material -> Array[Monster].
var _pool := {}
## Vybrané místo, příšera se objeví v dalším snímku: spot, creature a monster, když už je
## vzatá ze zásoby. Prázdné nic.
var _pending := {}
## Střed kamery po sekundách, nejvýš MOVED_SECONDS + 1 posledních.
var _track := PackedVector2Array()
var _track_left := 0.0
var _spawn_left := SPAWN_MIN
var _day := true
var _rng := RandomNumberGenerator.new()
var _over := false


## Přečte hunt.json a načte vzhled příšer dopředu. Volá se před tvorbou prvního čtverce,
## bodies pak smí číst vlákna.
func load_catalog(crystal: Crystal) -> void:
	_crystal = crystal
	_rng.randomize()
	_maker = Monsters.new()
	_maker.name = "Maker"
	add_child(_maker)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG)) if FileAccess.file_exists(CATALOG) else null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst tabulku příšer pro Chytej příšery.")
		return
	var index := {}
	for i in crystal.count():
		index[crystal.name_of(i)] = i
	for entry: Dictionary in (parsed as Dictionary).get("creatures", []):
		var key := str(entry.get("material", ""))
		if not index.has(key):
			push_warning("Příšera %s chce materiál %s, ten chybí." % [entry.get("title", ""), key])
			continue
		var mat := int(index[key])
		var info := _maker.info_of(crystal, mat)
		if info.is_empty():
			continue
		var terrains := {}
		for terrain: Variant in entry.get("terrains", []):
			terrains[str(terrain)] = true
		_maker.preload_looks(crystal, mat)
		var body := float(info.get("body_meters", 0.4)) * float(TerrainCatalog.TILE_SIZE)
		if not bool(info.get("flying", false)) and not bodies.has(body):
			bodies.append(body)
		_creatures.append({
			"material": mat,
			"title": str(entry.get("title", key)),
			"weight": maxf(float(entry.get("weight", 1.0)), 0.0),
			"points": int(entry.get("points", 10)),
			"time": str(entry.get("time", "any")),
			"terrains": terrains,
			"flying": bool(info.get("flying", false)),
			"body": body,
			# Úprk v m/s z hunt.json (flee) jako násobek rychlosti honičky druhu, ten bere Monster.
			"speed": float(entry.get("flee", 3.0)) / maxf(float(info.get("chase_meters", 5.0)), 0.1),
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
	for creature in _creatures:
		var monster := _build(creature)
		if monster != null:
			_park(monster, int(creature["material"]))
	_warm()


func tick(delta: float, phase: float) -> void:
	if _over:
		return
	time_left = maxf(time_left - delta, 0.0)
	_day = phase < 0.5
	_catch()
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


## Utíká některá příšera na obrazovce? Pak hraje hudba honičky.
func any_fleeing() -> bool:
	var view := _view(0.0)
	for prey in _alive:
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
		if _nearest(_alive[i].monster.position) > far:
			_release(_alive[i])


## Je místo na další příšeru? Když je plno, uklidí nejstarší, která není na obrazovce.
func _room() -> bool:
	if _alive.size() < MAX_ALIVE:
		return true
	var view := _view(HIDDEN_M * float(TerrainCatalog.TILE_SIZE))
	for prey in _alive:
		if not view.has_point(prey.monster.position):
			_release(prey)
			return true
	return false


func _fits_time(creature: Dictionary) -> bool:
	var time := str(creature["time"])
	return time == "any" or (time == "day") == _day


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
		var creature := _draw(spot)
		if not creature.is_empty():
			_pending = {"spot": spot, "creature": creature}
			return true
	return false


## Vylosuje příšeru pro spot. Prázdné, když se žádná nehodí nebo chodící nemá kde stát.
func _draw(spot: Vector2) -> Dictionary:
	var terrain := _walker.surface(spot)
	var dry := _walker.dry(spot)
	var total := 0.0
	var fits: Array[Dictionary] = []
	for creature in _creatures:
		if not (creature["terrains"] as Dictionary).has(terrain) or not _fits_time(creature):
			continue
		if not dry and not bool(creature["flying"]):
			continue
		fits.append(creature)
		total += float(creature["weight"])
	if total <= 0.0:
		return {}
	var roll := _rng.randf() * total
	var chosen: Dictionary = fits[fits.size() - 1]
	for creature in fits:
		roll -= float(creature["weight"])
		if roll < 0.0:
			chosen = creature
			break
	if not bool(chosen["flying"]) and _walker.blocked(spot, float(chosen["body"])):
		return {}
	return chosen


## Další krok objevení vybrané příšery, jeden za snímek: vzít ji ze zásoby (prázdná
## zásoba druhu ji postaví), pak ji ukázat na místě.
func _advance() -> void:
	var creature: Dictionary = _pending["creature"]
	if not _pending.has("monster"):
		var stock: Array = _pool.get(int(creature["material"]), [])
		var monster: Monster = stock.pop_back() if not stock.is_empty() else _build(creature)
		if monster == null:
			_pending = {}
			return
		_pending["monster"] = monster
		return
	var monster: Monster = _pending["monster"]
	var spot: Vector2 = _pending["spot"]
	_pending = {}
	monster.reuse(spot)
	if crowd != null and not monster.is_flying():
		monster.crowd_id = crowd.join(monster)
	var prey := Prey.new()
	prey.monster = monster
	prey.creature = creature
	_alive.append(prey)


## Nová příšera pro zásobu. Ve skupině tvorů (crowd) není, přidá se až při objevení.
func _build(creature: Dictionary) -> Monster:
	_walker.crowd = null
	var at := _camera.get_screen_center_position()
	var monster: Monster = _maker.make(int(creature["material"]), _crystal, _walker, null, _persons, _camera, _host,
		_rng, at, Vector2.INF, Vector2.ZERO, float(creature["speed"]), true)
	_walker.crowd = crowd
	if monster != null:
		monster.park()
	return monster


## Vrátí příšeru do zásoby jejího materiálu.
func _park(monster: Monster, mat: int) -> void:
	monster.park()
	if not _pool.has(mat):
		_pool[mat] = []
	(_pool[mat] as Array).append(monster)


## Jednou vykreslí vrstvy všech příšer do malého obrázku mimo obrazovku. Shadery a textury
## se tak připraví hned při startu, ne až u první příšery každého druhu.
func _warm() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(64, 64)
	view.disable_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	for creature in _creatures:
		for sprite in _maker.sample_layers(_crystal, int(creature["material"])):
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


## Chycená příšera zůstane stát, zprůhlední a vrátí se do zásoby.
func _caught(prey: Prey) -> void:
	var monster := prey.monster
	_alive.erase(prey)
	_leave_crowd(monster)
	monster.fade(FADE, _park.bind(monster, int(prey.creature["material"])))
	Sound.at("sfx/pickup", monster.position, 2.0)
	var gained := int(prey.creature["points"])
	points += gained
	caught_count += 1
	scored.emit(points, caught_count)
	_board.hunt_notice("%s +%d" % [prey.creature["title"], gained], CATCH_NOTICE)


## Uklidí příšeru do zásoby.
func _release(prey: Prey) -> void:
	_alive.erase(prey)
	_leave_crowd(prey.monster)
	_park(prey.monster, int(prey.creature["material"]))


func _leave_crowd(monster: Monster) -> void:
	if crowd != null and monster.crowd_id >= 0:
		crowd.leave(monster.crowd_id)
	monster.crowd_id = -1


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
	config.load(RECORDS)
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
	config.save(RECORDS)
	return rank


## Jméno naposledy zapsané pro tolik hráčů, nebo prázdné.
static func last_name(players: int) -> String:
	var config := ConfigFile.new()
	if config.load(RECORDS) != OK:
		return ""
	return str(config.get_value(NAMES, str(players), ""))


## Nejvýš RECORDS_KEPT výkonů pro tolik hráčů od nejvíc bodů. Při shodě dřív dosažený výš.
static func records(players: int) -> Array[Dictionary]:
	var config := ConfigFile.new()
	if config.load(RECORDS) != OK:
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


## „1 příšera“, „3 příšery“, „5 příšer“.
static func creatures_text(count: int) -> String:
	if count == 1:
		return "1 příšera"
	return "%d příšery" % count if count >= 2 and count <= 4 else "%d příšer" % count
