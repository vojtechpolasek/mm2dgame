extends Node

## Měření výkonu, spouští se parametrem: ./hra -- --benchmark
## Volitelně --benchmark-seed=N (jiný svět) a --benchmark-out=cesta.json (kam zapsat výsledek).
## --benchmark-probe jen vypíše cíle trasy a otisk světa a skončí (výběr semínka).
##
## Hra Skafandry na pevném semínku, takže je svět pokaždé stejný: vesnice, továrna, příšery,
## vesničané a řeka (úvodní čtverec benchmarku smí mít vodu, viz WorldBoard._generate).
## Nic se neukládá a nastavení grafiky se mění jen po dobu měření.
##
## Průběh (asi 50 s po vzniku mapy):
## 1. Trasa ve dne: stání, les, k vodě, brodění, vesnice. Úsek začne LEG_M metrů před cílem
##    (každý běh na stejném místě) a postavu vede po NavGrid stejnými akcemi jako hráč. Končí
##    v cíli nebo po svém limitu.
## 2. Noc: stání a brodění se zapnutými čelovkami. Ve složkách noci jdou zvlášť vypnout i stíny
##    čelovek (kužel pak svítí celý).
## 3. Složky: postava stojí u vody a postupně se vypínají části scény (stíny, jen stíny
##    objektů bez stínů břehů, terén, voda jezer, řeka, porost, objekty, tvorové, HUD, jen
##    minimapa, mlha, noční závoj) a mění rozlišení světa (Graphics.SCALES, ve dne i v noci).
##    Rozdíl proti „vse“ je cena té části.
## Výsledek je JSON vedle spustitelného souboru ve složce benchmark (v editoru
## user://benchmark), cesta se vypíše na konec. Pak se hra ukončí.
## Vsync je při měření vypnutý, doba snímku je skutečná práce procesoru a grafiky.

const Shadows := preload("res://scripts/shadows.gd")

## Semínko světa benchmarku. Úvodní čtverec má les, řeku i vesnici.
const DEFAULT_SEED := 2
## Denní doba (DayNight.phase): dopoledne a noc s měsícem vysoko.
const DAY_PHASE := 0.15
const NIGHT_PHASE := 0.72
## Začátek každé fáze se nepočítá, ať se přepnutí neprojeví ve výsledku.
const SETTLE := 0.4
const STILL := 2.0
## Cíl je dosažen na tolik metrů.
const REACH_M := 1.5
## Postava se zasekla, když za STUCK_TIME neušla STUCK_M metrů. Pak skočí a cestu přepočítá.
const STUCK_TIME := 0.8
const STUCK_M := 0.4
## Od kraje čtverce drží cíle tolik metrů, ať je nezastaví ohrada levelu.
const EDGE_M := 4.0
## Úsek trasy začíná na cestě tolik metrů před cílem, každý běh na stejném místě.
const LEG_M := 15.0
## Poslední a první _process ve snímku. Čas mezi nimi jsou skripty všech uzlů.
const LAST := 1000000
const STEER: PackedStringArray = ["left", "right", "up", "down"]

## Fáze: jméno, skupina, co dělá, délka (u chůze nejvýš), cíl chůze, denní doba a vypnutá část.
var _plan: Array[Dictionary] = []
var _index := -1
var _phase_t := 0.0
var _samples := {}
var _results: Array = []
var _last_usec := 0
var _world: Node
var _board: Node
var _person: Node2D
var _nav: RefCounted
var _path := PackedVector2Array()
var _goal := Vector2.INF
var _stuck_t := 0.0
var _stuck_from := Vector2.ZERO
var _walked := 0.0
var _last_pos := Vector2.ZERO
var _tile := 64.0
var _spots := {}
var _settings := {}
var _start_usec := 0
var _vsync := DisplayServer.VSYNC_ENABLED
## Začátek skriptů snímku, zapíše ho _FrameStart.
var frame_start_usec := 0


## Uzel, který ve snímku běží první a zapíše začátek skriptů.
class _FrameStart extends Node:
	var owner_bench: Node

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -LAST

	func _process(_delta: float) -> void:
		owner_bench.frame_start_usec = Time.get_ticks_usec()


static func requested() -> bool:
	return OS.get_cmdline_user_args().has("--benchmark")


static func world_seed() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--benchmark-seed="):
			return int(arg.get_slice("=", 1))
	return DEFAULT_SEED


## Náhoda hry: v benchmarku pevná podle semínka světa a salt, jinak náhodná.
static func seed_rng(rng: RandomNumberGenerator, salt: int) -> void:
	if requested():
		rng.seed = hash([world_seed(), salt])
	else:
		rng.randomize()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Poslední ve snímku: po světě (denní doba, řízení) a pro změření skriptů všech uzlů.
	process_priority = LAST
	var start := _FrameStart.new()
	start.owner_bench = self
	add_child(start)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# Bez vsync je doba snímku skutečná práce, ne čekání na obnovení displeje.
	_vsync = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("Benchmark: semínko %d, %s" % [world_seed(), RenderingServer.get_video_adapter_name()])
	# I globální náhoda (zvuky, pořadí vesničanů) je pevná.
	seed(hash([world_seed(), "global"]))
	_settings = {"scale": Graphics.world_scale(), "shadows": Graphics.shadows_on(), "sparkle": Graphics.sparkle_on()}
	# Bez id se hra neukládá, uložené hry hráče zůstanou, jak byly.
	GameSession.free_roam = false
	GameSession.suit_id = ""
	GameSession.suit_resume = {}
	GameSession.suit_outfits = []
	if GameSession.players.is_empty():
		GameSession.players = [GameSession.default_player()]
	_start_usec = Time.get_ticks_usec()
	get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")


func _process(delta: float) -> void:
	if _index < 0:
		_world = get_tree().current_scene
		if _world == null or not _world.get("_map_ready"):
			return
		_begin()
		return
	if _index >= _plan.size():
		return
	var phase := _plan[_index]
	_hold_time(phase)
	_phase_t += delta
	var done := _phase_t >= float(phase["time"])
	if phase.has("goal"):
		done = done or _drive(delta)
	if _phase_t >= SETTLE:
		_sample()
	if done:
		_close_phase()
		_next()


func _begin() -> void:
	_board = _world.get_node("Board")
	_person = (_world.get("_persons") as Array)[0]
	_tile = float(load("res://scripts/terrain_catalog.gd").TILE_SIZE)
	var load_s := float(Time.get_ticks_usec() - _start_usec) / 1e6
	_spots = _find_spots()
	_spots["load_s"] = load_s
	print("Benchmark: mapa za %.1f s, otisk %s, cíle %s" % [load_s, _spots["otisk"], ", ".join(_spots.keys().filter(func(k: String) -> bool: return _spots[k] is Vector2))])
	if OS.get_cmdline_user_args().has("--benchmark-probe"):
		get_tree().quit()
		return
	_build_plan()
	_next()


## Cíle trasy v úvodním čtverci: start, nejhustší les, nejbližší brod, kus dál po vodě, továrna.
func _find_spots() -> Dictionary:
	var sq = (_board.get("_squares") as Dictionary)[Vector2i.ZERO]
	_nav = load("res://scripts/nav_grid.gd").new()
	_nav.build(sq.walker, sq.rocks, sq.forest, float(load("res://scripts/person.gd").BODY))
	_nav.set_space(sq.origin)
	var start := _person.position
	var area := Rect2(sq.origin, Vector2.ONE * float(_board.call("_span"))).grow(-EDGE_M * _tile)
	var spots := {"start": start}
	# Les: strom s nejvíc sousedy do 8 m.
	var trees: PackedVector2Array = sq.forest.get("_pos")
	var best := -1
	for i in range(0, trees.size(), maxi(trees.size() / 400, 1)):
		var at := trees[i]
		if not area.has_point(at) or not _nav.reaches(start, at):
			continue
		var count := 0
		for other in trees:
			if at.distance_squared_to(other) < pow(8.0 * _tile, 2.0):
				count += 1
		if count > best:
			best = count
			spots["les"] = at
	var from: Vector2 = spots.get("les", start)
	# Brod: suchá nebo mělká dlaždice, kde řeka zpomalí chůzi.
	var wet := PackedVector2Array()
	var side := int(float(_board.call("_span")) / _tile)
	for y in range(0, side, 2):
		for x in range(0, side, 2):
			var at: Vector2 = sq.origin + (Vector2(x, y) + Vector2.ONE * 0.5) * _tile
			if area.has_point(at) and _board.is_dry(at) and _board.river_pace(at) < 1.0:
				wet.append(at)
	var nearest := INF
	for at in wet:
		var d := from.distance_squared_to(at)
		if d < nearest and _nav.reaches(from, at):
			nearest = d
			spots["voda"] = at
	if spots.has("voda"):
		# Kus dál po vodě: bod 10 až 18 m od brodu, úsečka k němu co nejvíc ve vodě.
		var ford: Vector2 = spots["voda"]
		var wettest := -1
		for at in wet:
			var d := ford.distance_to(at) / _tile
			if d < 10.0 or d > 18.0:
				continue
			var inside := 0
			for k in 9:
				var p := ford.lerp(at, float(k) / 8.0)
				if _board.river_pace(p) < 1.0:
					inside += 1
			if inside > wettest:
				wettest = inside
				spots["brod"] = at
	var town_center: Vector2 = sq.town.center()
	if town_center != Vector2.INF:
		spots["vesnice"] = town_center
	spots["stromu"] = trees.size()
	# Otisk světa: stejné semínko musí dát stejný otisk, jinak běhy nejde porovnat.
	var rocks: PackedVector2Array = sq.rocks.get("_pos")
	spots["otisk"] = "%08x" % (hash([sq.map.terrain, trees, rocks, wet, town_center]) & 0xffffffff)
	spots["voda_dlazdic"] = wet.size() * 4
	return spots


func _build_plan() -> void:
	_plan.clear()
	_add("stani", "trasa_den", STILL, {})
	var from: Vector2 = _spots["start"]
	for leg in ["les", "voda", "brod", "vesnice"]:
		if _spots.has(leg):
			_add("chuze_" + leg, "trasa_den", 5.0, {"goal": _spots[leg], "from": from})
			from = _spots[leg]
	# Noc a složky stojí u vody (bez vody u startu), tam je nejvíc věcí najednou.
	var view: Vector2 = _spots.get("voda", _spots["start"])
	_add("noc_stani", "noc", STILL, {"night": true, "teleport": view})
	if _spots.has("brod"):
		_add("noc_brodeni", "noc", 5.0, {"night": true, "goal": _spots["brod"], "from": view})
	_add("vse", "slozky_den", STILL, {"teleport": view})
	for part in ["bez_stinu", "bez_stinu_objektu", "bez_terenu", "bez_vody", "bez_reky", "bez_porostu",
			"bez_objektu", "bez_tvoru", "bez_hud", "bez_minimapy", "bez_mlhy"]:
		_add(part, "slozky_den", STILL, {"off": part})
	_add("noc_vse", "slozky_noc", STILL, {"night": true})
	_add("noc_bez_zavoje", "slozky_noc", STILL, {"night": true, "off": "bez_zavoje"})
	_add("noc_bez_stinu", "slozky_noc", STILL, {"night": true, "off": "bez_stinu"})
	_add("noc_bez_stinu_objektu", "slozky_noc", STILL, {"night": true, "off": "bez_stinu_objektu"})
	_add("noc_bez_stinu_celovek", "slozky_noc", STILL, {"night": true, "off": "bez_stinu_celovek"})
	for scale in Graphics.SCALES:
		_add("rozliseni_%d" % roundi(scale * 100.0), "rozliseni", STILL, {"scale": scale})
	for scale in Graphics.SCALES:
		_add("noc_rozliseni_%d" % roundi(scale * 100.0), "rozliseni_noc", STILL, {"night": true, "scale": scale})


func _add(phase_name: String, group: String, time: float, extra: Dictionary) -> void:
	var phase := {"name": phase_name, "group": group, "time": time}
	phase.merge(extra)
	_plan.append(phase)


func _next() -> void:
	_release_keys()
	_index += 1
	if _index >= _plan.size():
		_finish()
		return
	var phase := _plan[_index]
	_apply_off(str(phase.get("off", "")))
	Graphics.set_world_scale(float(phase.get("scale", _settings["scale"])), false)
	if phase.has("goal") and phase.has("from"):
		phase["teleport"] = _before(phase["from"], phase["goal"])
	if phase.has("teleport"):
		_person.position = phase["teleport"]
		_person.set("_velocity", Vector2.ZERO)
	_hold_time(phase)
	_phase_t = 0.0
	_samples = {}
	_walked = 0.0
	_last_pos = _person.position
	_path = PackedVector2Array()
	_goal = phase.get("goal", Vector2.INF)
	if _goal != Vector2.INF:
		_path = _nav.path(_person.position, _goal)
	_stuck_t = 0.0
	_stuck_from = _person.position
	_last_usec = 0


## Místo na cestě z from do goal LEG_M metrů před cílem (nebo from, je-li blíž).
func _before(from: Vector2, goal: Vector2) -> Vector2:
	var points: PackedVector2Array = _nav.path(from, goal)
	points.insert(0, from)
	var left := LEG_M * _tile
	for i in range(points.size() - 1, 0, -1):
		var step := points[i].distance_to(points[i - 1])
		if step >= left:
			return points[i].lerp(points[i - 1], left / step)
		left -= step
	return from


## Denní doba stojí: den běží dál o snímek, tady se vrátí zpátky.
func _hold_time(phase: Dictionary) -> void:
	var day = _board.get("_day")
	day.phase = NIGHT_PHASE if phase.get("night", false) else DAY_PHASE
	day.days = 0


## Krok k cíli šipkami jako hráč. Vrací true, když je postava v cíli.
func _drive(delta: float) -> bool:
	var pos := _person.position
	_walked += pos.distance_to(_last_pos)
	_last_pos = pos
	if pos.distance_to(_goal) < REACH_M * _tile:
		_release_keys()
		return true
	while not _path.is_empty() and pos.distance_to(_path[0]) < 0.5 * _tile:
		_path.remove_at(0)
	var aim := _goal if _path.is_empty() else _path[0]
	_steer((aim - pos).normalized())
	_stuck_t += delta
	if _stuck_t >= STUCK_TIME:
		if pos.distance_to(_stuck_from) < STUCK_M * _tile:
			Input.action_press(Controls.action(0, "jump"))
			_path = _nav.path(pos, _goal)
		else:
			Input.action_release(Controls.action(0, "jump"))
		_stuck_t = 0.0
		_stuck_from = pos
	return false


func _steer(dir: Vector2) -> void:
	var strength := [maxf(-dir.x, 0.0), maxf(dir.x, 0.0), maxf(-dir.y, 0.0), maxf(dir.y, 0.0)]
	for i in STEER.size():
		var action := Controls.action(0, STEER[i])
		if strength[i] > 0.01:
			Input.action_press(action, strength[i])
		else:
			Input.action_release(action)


func _release_keys() -> void:
	for what in ["left", "right", "up", "down", "jump"]:
		Input.action_release(Controls.action(0, what))


## Vypne jednu část scény (prázdné jméno vše zapne). Vypnutá část se nekreslí, tvorové ani
## nepočítají. Stíny a rozlišení jdou přes Graphics bez uložení.
func _apply_off(part: String) -> void:
	for child in _world.get_children():
		var item := child as CanvasItem
		if item == null:
			continue
		var key := str(child.name)
		if key.begins_with("Ground"):
			item.visible = part != "bez_terenu"
			# Vlnící se voda jezer: MeshInstance2D pod spritem každého chunku, jen když má mesh.
			for sprite in child.get_children():
				if sprite is Sprite2D and sprite.get_child_count() > 0:
					var water := sprite.get_child(0) as MeshInstance2D
					if water != null:
						water.visible = water.mesh != null and part != "bez_vody"
		elif key == "Rivers":
			item.visible = part != "bez_reky"
		elif key == "Decor":
			item.visible = part != "bez_porostu"
		elif key == "Props":
			item.visible = part != "bez_objektu"
		elif key.begins_with("Air_"):
			item.visible = part != "bez_mlhy"
		elif key == "DayNight":
			item.visible = part != "bez_zavoje"
	(_world.get_node("Hint") as CanvasLayer).visible = part != "bez_hud"
	var hud = _board.get("_hud")
	if hud != null and hud.minimap != null:
		hud.minimap.visible = part != "bez_minimapy"
	Graphics.set_shadows(bool(_settings["shadows"]) and part != "bez_stinu", false)
	# Jen stíny objektů (obrázek stínů), stíny břehů ve vodě zůstanou. set_shadows výše
	# obnoví obrázek, když se fáze mění.
	var shadows: Node2D = Shadows.current
	if shadows != null:
		shadows.set_lamp_shades(part != "bez_stinu_celovek")
		shadows.visible = part != "bez_stinu_objektu"
		if part == "bez_stinu_objektu":
			(shadows.get("_shadow_view") as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	for sq in (_board.get("_squares") as Dictionary).values():
		for group in [sq.monsters.members, sq.villagers.members]:
			for member: Node in group:
				if is_instance_valid(member):
					member.process_mode = Node.PROCESS_MODE_DISABLED if part == "bez_tvoru" else Node.PROCESS_MODE_INHERIT
					(member as CanvasItem).visible = part != "bez_tvoru"


func _sample() -> void:
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_add_sample("frame_ms", float(now - _last_usec) / 1000.0)
	_last_usec = now
	var viewport := get_viewport().get_viewport_rid()
	if frame_start_usec > 0:
		_add_sample("scripts_ms", float(now - frame_start_usec) / 1000.0)
	_add_sample("physics_ms", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_add_sample("render_cpu_ms", RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu())
	_add_sample("gpu_ms", RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	_add_sample("draw_calls", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_add_sample("objects", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_add_sample("primitives", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


func _add_sample(key: String, value: float) -> void:
	# Pole se kopíruje hodnotou, zpátky se proto musí uložit.
	var values: PackedFloat64Array = _samples.get(key, PackedFloat64Array())
	values.append(value)
	_samples[key] = values


func _close_phase() -> void:
	var phase := _plan[_index]
	var result := {"name": phase["name"], "group": phase["group"], "seconds": snappedf(_phase_t, 0.01)}
	if phase.has("goal"):
		result["reached"] = _person.position.distance_to(phase["goal"]) < REACH_M * _tile
		result["walked_m"] = snappedf(_walked / _tile, 0.1)
	for key in _samples:
		result[key] = _stats(_samples[key])
	var frames: Dictionary = result.get("frame_ms", {})
	result["fps"] = snappedf(1000.0 / float(frames["mean"]), 0.1) if frames.get("mean", 0.0) > 0.0 else 0.0
	_results.append(result)
	print("%-18s %5.1f fps  snímek %5.1f/%5.1f ms  skripty %5.2f  render cpu %5.2f  gpu %5.2f  draw %4d%s" % [
		result["name"], result["fps"], frames.get("p50", 0.0), frames.get("p95", 0.0),
		result.get("scripts_ms", {}).get("mean", 0.0), result.get("render_cpu_ms", {}).get("mean", 0.0),
		result.get("gpu_ms", {}).get("mean", 0.0), int(result.get("draw_calls", {}).get("mean", 0.0)),
		"" if not phase.has("goal") else "  %s %.0f m" % ["cíl" if result["reached"] else "nedošel", result["walked_m"]]])


static func _stats(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += v
	var at := func(q: float) -> float: return sorted[mini(int(q * float(sorted.size())), sorted.size() - 1)]
	return {
		"n": sorted.size(),
		"mean": snappedf(total / float(sorted.size()), 0.01),
		"p50": snappedf(at.call(0.5), 0.01),
		"p95": snappedf(at.call(0.95), 0.01),
		"max": snappedf(sorted[sorted.size() - 1], 0.01),
	}


## Cena části: o kolik ms je snímek s ní delší než bez ní (fáze „vse“ proti „bez_…“).
func _costs() -> Array:
	var by_name := {}
	for r: Dictionary in _results:
		by_name[r["name"]] = r
	var costs: Array = []
	for r: Dictionary in _results:
		var phase_name := str(r["name"])
		var base := ""
		if r["group"] == "slozky_den" and phase_name != "vse":
			base = "vse"
		elif r["group"] == "slozky_noc" and phase_name != "noc_vse":
			base = "noc_vse"
		if base.is_empty() or not by_name.has(base):
			continue
		var with_ms := float(by_name[base].get("frame_ms", {}).get("mean", 0.0))
		var without_ms := float(r.get("frame_ms", {}).get("mean", 0.0))
		if with_ms <= 0.0:
			continue
		costs.append({"part": phase_name.trim_prefix("noc_"), "when": "noc" if base == "noc_vse" else "den",
			"cost_ms": snappedf(with_ms - without_ms, 0.01), "share": snappedf((with_ms - without_ms) / with_ms, 0.001)})
	costs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["cost_ms"] > b["cost_ms"])
	return costs


func _finish() -> void:
	_apply_off("")
	Graphics.set_world_scale(float(_settings["scale"]), false)
	DisplayServer.window_set_vsync_mode(_vsync)
	var costs := _costs()
	print("Cena částí (ms snímku):")
	for c: Dictionary in costs:
		print("  %-14s %-4s %6.2f ms  %4.0f %%" % [c["part"], c["when"], c["cost_ms"], c["share"] * 100.0])
	var report := {
		"version": 1,
		"date": Time.get_datetime_string_from_system(),
		"seed": world_seed(),
		"system": _system(),
		"settings": _settings,
		"world": {"load_s": snappedf(float(_spots["load_s"]), 0.1), "trees_start_square": _spots["stromu"],
			"water_tiles": _spots["voda_dlazdic"], "fingerprint": _spots["otisk"], "route": _spots.keys().filter(func(k: String) -> bool: return _spots[k] is Vector2)},
		"memory": {
			"static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
			"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
			"texture_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		},
		"phases": _results,
		"costs": costs,
	}
	var path := _write(report)
	print("Benchmark hotový: %s" % path)
	get_tree().quit()


func _system() -> Dictionary:
	return {
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"distribution": OS.get_distribution_name(),
		"cpu": OS.get_processor_name(),
		"cores": OS.get_processor_count(),
		"arch": Engine.get_architecture_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"driver": "%s %s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_api_version()],
		"godot": Engine.get_version_info()["string"],
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"canvas_size": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"vsync": DisplayServer.window_get_vsync_mode(),
	}


## Vedle spustitelného souboru ve složce benchmark, v editoru (nebo když tam zapsat nejde)
## user://benchmark. Kromě souboru s časem se přepíše benchmark_latest.json.
func _write(report: Dictionary) -> String:
	var text := JSON.stringify(report, "  ")
	var target := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--benchmark-out="):
			target = arg.get_slice("=", 1)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var dirs: Array[String] = []
	if target.is_empty():
		if OS.has_feature("template"):
			dirs.append(OS.get_executable_path().get_base_dir().path_join("benchmark"))
		dirs.append(ProjectSettings.globalize_path("user://benchmark"))
	for dir in dirs:
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			continue
		var file := FileAccess.open(dir.path_join("benchmark_%s.json" % stamp), FileAccess.WRITE)
		if file == null:
			continue
		file.store_string(text)
		file.close()
		var latest := FileAccess.open(dir.path_join("benchmark_latest.json"), FileAccess.WRITE)
		if latest != null:
			latest.store_string(text)
			latest.close()
		return dir.path_join("benchmark_%s.json" % stamp)
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_error("Benchmark: nelze zapsat %s" % target)
		print(text)
		return ""
	file.store_string(text)
	file.close()
	return target
