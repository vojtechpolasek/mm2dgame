extends "res://scripts/world_board.gd"

## Typ hry Skafandry jako otevřený svět. Čtverce mají stranu GameSession.SUIT_MAP a navazují
## terénem jako ve Světě. Level se hraje na čtverci s továrnou a vesnicí, ostatní čtverce jsou
## jen krajina (stromy a skály, bez vesnice, továrny a dolů). Kolem se dotváří, jak se hráči blíží
## ke kraji, ať za ním není prázdno.
## Během levelu hráči čtverec levelu neopustí: kraj je zastaví FENCE_M metrů před sebou. Šipka
## ukazuje na továrnu, BLINK_M metrů od kraje bliká a od ALARM_M výrazně.
## Po splnění levelu vznikne další čtverec s továrnou na nejbližším místě, kde ještě nic není
## (při shodě náhodně), a šipka ukáže na něj. Hráči mezitím chodí kamkoli. Až se kdokoli
## přiblíží k nové továrně na LOCK_M metrů, kdo je v jejím čtverci, už z něj nevyjde.
## Tvorové jsou jen na čtverci hráče a na jeho sousedech, dál zmizí (WorldBoard._actors).
## Po patnáctém levelu hra končí.
## Čtverec s továrnou má tři sklady (Town.plan_stores), kam si hráči můžou kameny odložit.
## Hra se ukládá sama (SuitSaves): každých SAVE_EVERY sekund, po splnění levelu a při odchodu.
## Uloží se mapy všech hotových čtverců, kameny ve skladech všech čtverců a přesný stav levelu:
## postavy a co nesou, zásobníky továrny, vesničané a příšery jeho čtverce. Po načtení se hraje
## tam, kde hra skončila.

const SuitGame := preload("res://scripts/suit_game.gd")
const SuitSaves := preload("res://scripts/suit_saves.gd")

const FENCE_M := 1.0
const BLINK_M := 12.0
const ALARM_M := 7.0
const LOCK_M := 20.0
## Hláška po splnění levelu svítí tolik sekund.
const LEVEL_NOTICE := 7.0
## Vesnice čtverce s továrnou: T s domy jako v jednom levelu.
const TOWN_LAYOUT := "large"
const SAVE_EVERY := 60.0
## Příšery uložené hry si po načtení tolik sekund nikoho nevšímají.
const LOAD_CALM := 3.0

## Level, který se právě hraje, a jeho čtverec.
var _level := 1
var _active := Vector2i.ZERO
## Hráči jsou zavření ve čtverci levelu. Po splnění levelu až do příchodu k nové továrně ne.
var _locked := true
## Čtverce s továrnou: souřadnice -> level.
var _levels := {}
## Úkol každého čtverce s továrnou podle souřadnic.
var _games := {}
## Splněné čtverce: souřadnice -> kolik skafandrů leží na výstupku (z uložené hry, než
## čtverec vznikne).
var _done := {}
## Kde hráči začínají. U uložené hry čtverec, kde stál první hráč.
var _start := Vector2i.ZERO
## Celkový čas hry a čas právě hraného levelu v sekundách.
var _time := 0.0
var _level_time := 0.0
## Jak daleko od kraje drží ohrada postavu, podle postavy. Postava, která do čtverce levelu
## teprve vešla, má ohradu tam, kde stojí, a ta se rozšíří až na FENCE_M.
var _insets := {}
var _finished := false
var _save_left := SAVE_EVERY
## Hra už je uložená při zavírání okna.
var _closed_saved := false
## Stav uložené hry, který čeká, až vzniknou postavy a tvorové a továrna čtverce levelu.
var _pending := {}
## Kameny ve skladech uložené hry podle souřadnic čtverce, dokud čtverec nevznikne.
var _stores := {}


func start(host) -> void:
	_side = GameSession.SUIT_MAP
	super.start(host)


func _begin() -> void:
	if GameSession.suit_resume.is_empty():
		_levels[Vector2i.ZERO] = 1
		_enqueue(Vector2i.ZERO)
		return
	_load(GameSession.suit_resume)


## Pokračování uložené hry. Čtverce se staví z uložených map, nejdřív ty nejblíž hráčům.
func _load(data: Dictionary) -> void:
	_status.text = "Načítá se uložená hra…"
	_level = int(data.get("level", 1))
	_time = float(data.get("time", 0.0))
	_level_time = float(data.get("level_time", 0.0))
	_active = data.get("active", Vector2i.ZERO)
	_locked = bool(data.get("locked", true))
	_levels = data.get("levels", {Vector2i.ZERO: 1})
	_done = data.get("done", {})
	_world_rng.state = int(data.get("rng", _world_rng.state))
	_pending = data.get("state", {})
	_stores = data.get("stores", {})
	var persons: Array = _pending.get("persons", [])
	var first: Vector2 = _origin_of(_active) + Vector2(_span(), _span()) * 0.5
	if not persons.is_empty():
		first = (persons[0] as Dictionary).get("pos", first)
	_start = _coord(first)
	_camera.position = first
	var squares: Array = data.get("squares", [])
	squares.sort_custom(_nearer_start)
	for entry: Dictionary in squares:
		var blob: PackedByteArray = entry["data"]
		var record: Variant = bytes_to_var(blob.decompress(int(entry["size"]), FileAccess.COMPRESSION_ZSTD))
		if typeof(record) != TYPE_DICTIONARY:
			push_warning("Čtverec %s uložené hry nejde přečíst." % entry["coord"])
			continue
		var coord: Vector2i = entry["coord"]
		_enqueue(coord, record)
		var sq := _square(coord)
		if sq != null:
			sq.blob = blob
			sq.blob_size = int(entry["size"])
	# Čtverec levelu ani čtverec hráčů nemusí být uložený, když se zrovna tvořil.
	_enqueue(_start)
	_enqueue(_active)
	# Mapy už jsou ve čtvercích, velký slovník se nemusí držet.
	GameSession.suit_resume = {}


func _nearer_start(a: Dictionary, b: Dictionary) -> bool:
	var to_a: Vector2i = a["coord"] - _start
	var to_b: Vector2i = b["coord"] - _start
	return Vector2(to_a).length_squared() < Vector2(to_b).length_squared()


func tick(delta: float) -> void:
	super.tick(delta)
	if not _opened or _closing or _finished:
		return
	_time += delta
	_level_time += delta
	_hud.set_time(_time)
	_check_lock()
	_update_fence()
	_save_left -= delta
	if _save_left <= 0.0:
		_save()


func shutdown() -> void:
	super.shutdown()
	if not _closed_saved:
		_save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _closed_saved:
		_save()
		_closed_saved = true


# --- Čtverce ---

func _plan_square(sq: Square) -> void:
	sq.level = int(_levels.get(sq.coord, 0))
	sq.layout = TOWN_LAYOUT if sq.level > 0 else "empty"


## Čtverec s továrnou: doly materiálů levelu v úzkých pásech kolem továrny a zásobníky
## podle levelu. Ostatní čtverce nemají doly ani továrnu.
func _configure(sq: Square) -> void:
	if sq.level <= 0:
		sq.rocks.bottomless = false
		sq.rocks.set_available(0)
		return
	sq.town.stores = true
	sq.rocks.bottomless = true
	sq.rocks.set_available(GameSession.mode_materials(sq.level))
	var order: PackedInt32Array = sq.rocks.by_points()
	var need := {}
	var plan: Array = []
	for pair: Array in GameSession.suit_lanes(sq.level):
		var at := mini(int(pair[0]), order.size() - 1)
		need[at] = int(need.get(at, 0)) + int(pair[1])
		plan.append([order[at], int(pair[1])])
	# Každý materiál má svůj důl, ten, kterého zásobníky chtějí tři a víc, dva.
	var mines := PackedInt32Array()
	for at in mini(GameSession.mode_materials(sq.level), order.size()):
		mines.append(2 if int(need.get(at, 0)) >= 3 else 1)
	sq.rocks.mine_plan = mines
	sq.rocks.band_max = GameSession.SUIT_BAND_M
	sq.town.suit_plan = plan
	sq.town.suit_recipe = order.slice(0, mini(GameSession.SUIT_RECIPE, order.size()))


func _built_square(sq: Square) -> void:
	if sq.level <= 0 or sq.town.suit_factory() == null:
		return
	if _stores.has(sq.coord):
		sq.town.restore_stores(_stores[sq.coord])
		_stores.erase(sq.coord)
	var game := SuitGame.new()
	game.name = "Suits_%d_%d" % [sq.coord.x, sq.coord.y]
	add_child(game)
	if not game.setup(sq.town, _host._persons):
		game.queue_free()
		return
	_games[sq.coord] = game
	game.factory().point_mines(sq.rocks)
	game.progressed.connect(_on_progress.bind(sq.coord))
	game.completed.connect(_on_completed.bind(sq.coord))
	if _done.has(sq.coord):
		game.factory().restore({"done": true, "suits": int(_done[sq.coord])})
		game.mark_done()
	elif sq.coord == _active and _pending.has("factory"):
		game.factory().restore(_pending["factory"])
		_pending.erase("factory")
	if sq.coord == _active and _hud != null:
		_hud.set_goal(_title(), game.target())


func _opens_at(sq: Square) -> bool:
	return sq.coord == _start


func _woke(sq: Square) -> void:
	var game: SuitGame = _games.get(sq.coord)
	if game == null:
		return
	game.attach(sq.villagers, sq.monsters)
	if sq.coord != _active:
		return
	if _pending.has("villagers"):
		sq.villagers.restore(_pending["villagers"], _host._persons)
		_pending.erase("villagers")
	if _pending.has("monsters"):
		sq.monsters.restore(_pending["monsters"], LOAD_CALM)
		_pending.erase("monsters")
	if _pending.has("stored"):
		game.restore(int(_pending["stored"]))
		_pending.erase("stored")
		if _hud != null:
			_hud.set_progress(game.stored())


## Uložená hra: stejní vesničané čtverce levelu jako při uložení.
func _saved_villagers(sq: Square) -> Array:
	return _pending.get("villagers", []) if sq.coord == _active else []


func _sleep(sq: Square) -> void:
	super._sleep(sq)
	var game: SuitGame = _games.get(sq.coord)
	if game != null:
		game.detach()


# --- Hráči ---

## Uložená hra: postavy stojí, kde stály, a nesou, co nesly. Každá používá doly a továrnu
## čtverce, na kterém stojí.
func _place_persons(sq: Square) -> void:
	var saved: Array = _pending.get("persons", [])
	_pending.erase("persons")
	if saved.is_empty():
		super._place_persons(sq)
		return
	for i in _host._persons.size():
		var person: Person = _host._persons[i]
		if i >= saved.size():
			person.position = person._free_spot(_host._persons[0].position)
			continue
		person.restore(saved[i])
		var coord := _coord(person.position)
		_where[person] = coord
		var here := _square(coord)
		if here != null and here.ready:
			person.use_square(here.rocks, here.town, here.origin, _span())


func _setup_hud(_sq: Square) -> void:
	var game: SuitGame = _games.get(_active)
	var target := game.target() if game != null else 1
	_hud.setup(_crystal, _level, "suits", target, false, GameSession.players)
	_hud.set_goal(_title(), target)
	if game != null:
		_hud.set_progress(game.stored())
	_hud.set_time(_time)
	_hud.menu_pressed.connect(_host._to_menu)


## Dýchací přístroj, ukradený kámen zmizí. Co postava udělá, se hlásí vesničanům čtverce,
## na kterém stojí: kdo ji sleduje, jde za ní.
func _dress(person: Person) -> void:
	person.wear_gear(true)
	person.stolen_vanish = true
	person.deliver_suit = _deliver
	person.took_gem.connect(_on_took.bind(person))
	person.threw_gem.connect(_on_threw.bind(person))
	person.touched_factory.connect(_on_touched.bind(person))
	_hud.set_held(person.carried(), person.player_index)


func _villagers_of(person: Person) -> Villagers:
	var sq := _square(_where.get(person, _coord(person.position)))
	return sq.villagers if sq != null and sq.awake else null


func _on_took(slot: int, mat: int, person: Person) -> void:
	var villagers := _villagers_of(person)
	if villagers != null:
		villagers.leader_took(slot, mat, person)


func _on_threw(person: Person) -> void:
	var villagers := _villagers_of(person)
	if villagers != null:
		villagers.leader_threw(person)


func _on_touched(person: Person) -> void:
	var villagers := _villagers_of(person)
	if villagers != null:
		villagers.leader_touched(person)


## Skafandr převezme vesničan u dveří domu na čtverci levelu.
func _deliver(pos: Vector2) -> bool:
	var game: SuitGame = _games.get(_active)
	return game != null and _coord(pos) == _active and game.deliver(pos)


## Ohrada: postava ve čtverci levelu z něj nevyjde. Kraj ji zastaví FENCE_M metrů před sebou.
## Kdo do čtverce teprve vešel, má ohradu tam, kde stojí, a ta se s každým krokem dovnitř
## posune, až je FENCE_M od kraje.
func _update_fence() -> void:
	var rect := Rect2(_origin_of(_active), Vector2(_span(), _span()))
	var full := FENCE_M * float(TerrainCatalog.TILE_SIZE)
	for person: Person in _host._persons:
		if not _locked or not rect.has_point(person.position):
			person.walker.fence = Rect2()
			_insets.erase(person)
			continue
		var local := person.position - rect.position
		var edge := minf(minf(local.x, local.y), minf(rect.size.x - local.x, rect.size.y - local.y))
		var inset := clampf(edge, float(_insets.get(person, 0.0)), full)
		_insets[person] = inset
		person.walker.fence = rect.grow(-inset)


## Po splnění levelu: kdo se přiblíží k nové továrně na LOCK_M metrů, zavře hráče v jejím čtverci.
func _check_lock() -> void:
	if _locked:
		return
	var sq := _square(_active)
	if sq == null or not sq.ready or sq.town.center() == Vector2.INF:
		return
	var reach := LOCK_M * float(TerrainCatalog.TILE_SIZE)
	for person: Person in _host._persons:
		if person.position.distance_to(sq.town.center()) <= reach:
			_locked = true
			return


# --- Úkol ---

func _title() -> String:
	return "Level %d / %d" % [_level, GameSession.mode_last_level()]


## Šipka ukazuje na továrnu levelu. Než je její čtverec hotový, na jeho střed.
func _show_task() -> void:
	if _hud == null or _host._persons.is_empty():
		return
	var sq := _square(_active)
	var aim := _origin_of(_active) + Vector2(_span(), _span()) * 0.5
	if sq != null and sq.ready and sq.town.center() != Vector2.INF:
		aim = sq.town.center()
	var to_screen := (_host.get_viewport() as Viewport).get_canvas_transform()
	_hud.point_factory(to_screen * _camera.get_screen_center_position(), to_screen * aim)
	_hud.set_edge_alarm(_alarm())


## Jak moc šipka bliká: podle postavy nejblíž kraji čtverce levelu.
func _alarm() -> int:
	if not _locked:
		return 0
	var rect := Rect2(_origin_of(_active), Vector2(_span(), _span()))
	var nearest := INF
	for person: Person in _host._persons:
		if rect.has_point(person.position):
			nearest = minf(nearest, _edge_meters(person.position))
	if nearest <= ALARM_M:
		return 2
	return 1 if nearest <= BLINK_M else 0


func _on_progress(done: int, coord: Vector2i) -> void:
	if coord == _active and _hud != null:
		_hud.set_progress(done)


func _on_completed(coord: Vector2i) -> void:
	if coord != _active or _finished:
		return
	_done[coord] = 0
	var took := _level_time
	if _level >= GameSession.mode_last_level():
		_finish_game()
		return
	var finished := _level
	_level += 1
	_level_time = 0.0
	_active = _next_square(coord)
	_levels[_active] = _level
	_locked = false
	_enqueue(_active)
	Sound.ui("win")
	_hud.set_goal(_title(), 1)
	_hud.show_notice("Level %d splněn za %s. Šipka ukazuje k nové továrně." % [finished, GameSession.clock(took)], LEVEL_NOTICE)
	_save()


## Nejbližší čtverec od from, kde ještě nic není. Z několika stejně blízkých náhodně.
func _next_square(from: Vector2i) -> Vector2i:
	var radius := 1
	var best := INF
	var picks: Array[Vector2i] = []
	while true:
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var coord := from + Vector2i(x, y)
				if _squares.has(coord):
					continue
				var dist := Vector2(x, y).length()
				if dist < best - 0.001:
					best = dist
					picks.clear()
				if dist <= best + 0.001:
					picks.append(coord)
		# Šikmé místo na tomhle kruhu může být dál než rovné na dalším. Hledá se tedy, dokud
		# nejbližší nalezené není nejvýš tak daleko jako další kruh.
		if not picks.is_empty() and best <= float(radius + 1):
			return picks[_world_rng.randi_range(0, picks.size() - 1)]
		radius += 1
	return from


func _finish_game() -> void:
	_finished = true
	Sound.duck_music()
	Sound.stop_ambient()
	Sound.ui("win")
	get_tree().paused = true
	SuitSaves.finish_game(_header())
	var note := "Všech %d levelů splněno · čas %s" % [GameSession.mode_last_level(), GameSession.clock(_time)]
	var rank := _rank()
	if rank > 0:
		note += " · %d. místo ve výkonech" % rank
	_hud.show_result(true, note, true, false, "Konec hry")


## Kolikátá je tahle hra ve výkonech pro stejný počet hráčů. 0 když tam není.
func _rank() -> int:
	var rows := SuitSaves.results(GameSession.players.size())
	for i in rows.size():
		if str(rows[i]["id"]) == GameSession.suit_id:
			return i + 1
	return 0


# --- Uložení ---

func _save() -> void:
	_save_left = SAVE_EVERY
	if not _opened or _finished or GameSession.suit_id.is_empty():
		return
	SuitSaves.save_game(_header(), _snapshot())


func _header() -> Dictionary:
	return {
		"id": GameSession.suit_id,
		"name": GameSession.suit_name,
		"players": SuitSaves.outfits(GameSession.players),
		"level": _level,
		"time": _time,
	}


## Celá hra k uložení. Rozpracované čtverce se neukládají, po načtení se vytvoří znovu.
func _snapshot() -> Dictionary:
	var squares: Array = []
	for coord: Vector2i in _squares:
		var sq: Square = _squares[coord]
		if sq.map == null or sq.task >= 0:
			continue
		if sq.blob.is_empty():
			var raw := var_to_bytes(_record(sq))
			sq.blob = raw.compress(FileAccess.COMPRESSION_ZSTD)
			sq.blob_size = raw.size()
		squares.append({"coord": coord, "size": sq.blob_size, "data": sq.blob})
	var done := {}
	for coord: Vector2i in _done:
		var finished: SuitGame = _games.get(coord)
		done[coord] = int(finished.factory().snapshot()["suits"]) if finished != null else int(_done[coord])
	# Sklady čtverců, které po načtení ještě nevznikly, se uloží znovu, jak byly.
	var stores := _stores.duplicate()
	for coord: Vector2i in _squares:
		var built: Square = _squares[coord]
		if built.ready and built.town.store_count() > 0:
			stores[coord] = built.town.store_snapshot()
	var persons: Array = []
	for person: Person in _host._persons:
		persons.append(person.snapshot())
	# Co z uložené hry ještě nedošlo na řadu, se uloží znovu, jak bylo.
	var state := _pending.duplicate()
	state["persons"] = persons
	var game: SuitGame = _games.get(_active)
	if game != null:
		state["factory"] = game.factory().snapshot()
		# Dokud vesničané čtverce po načtení nevznikli, postup čeká v _pending.
		if not _pending.has("stored"):
			state["stored"] = game.stored()
	var sq := _square(_active)
	if sq != null and sq.awake:
		state["villagers"] = sq.villagers.snapshot(_host._persons)
		state["monsters"] = sq.monsters.snapshot()
	return {
		"level": _level,
		"time": _time,
		"level_time": _level_time,
		"active": _active,
		"locked": _locked,
		"levels": _levels,
		"done": done,
		"rng": _world_rng.state,
		"squares": squares,
		"stores": stores,
		"state": state,
	}
