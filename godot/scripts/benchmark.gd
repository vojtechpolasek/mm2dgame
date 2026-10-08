extends Node

## Měření výkonu, spouští se parametrem: ./hra -- --benchmark
## Načte level, počká na mapu a po PHASE sekundách postupně vypíná části scény. Každá fáze
## vypíše medián, 95. percentil a maximum času snímku, GPU a draw-callů, pak se hra ukončí.

const PHASE := 5.0
## Začátek fáze se nepočítá, ať se přepnutí neprojeví ve výsledku.
const SETTLE := 0.5
const PHASES: PackedStringArray = ["vse", "bez_terenu", "bez_propu", "bez_terenu_propu", "bez_prisery", "pohyb"]
const KEYS: PackedStringArray = ["frame_ms", "cpu_render_ms", "gpu_ms", "draw_calls"]
const STEER: PackedStringArray = ["c0_right", "c0_down", "c0_left", "c0_up"]

var _t := 0.0
var _phase := -1
var _acc := {}
var _turn := 0.0


static func requested() -> bool:
	return OS.get_cmdline_user_args().has("--benchmark")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	print("Benchmark: %s, okno %s" % [RenderingServer.get_video_adapter_name(), DisplayServer.window_get_size()])
	get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")


func _process(delta: float) -> void:
	var world := get_tree().current_scene
	if world == null or not world.get("_map_ready"):
		return
	_t += delta
	var phase := int(_t / PHASE)
	if phase != _phase:
		_report()
		_phase = phase
		if _phase >= PHASES.size():
			get_tree().quit()
			return
		_apply(world, PHASES[_phase])
		_acc = {}
		return
	if PHASES[_phase] == "pohyb":
		_steer(delta)
	if fmod(_t, PHASE) < SETTLE:
		return
	var viewport := get_viewport().get_viewport_rid()
	_add("frame_ms", delta * 1000.0)
	_add("cpu_render_ms", RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu())
	_add("gpu_ms", RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	_add("draw_calls", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


## Běh dokola: dvě sousední šipky naráz, po 0,8 s se pootočí.
func _steer(delta: float) -> void:
	_turn += delta
	var now := int(_turn / 0.8) % STEER.size()
	for i in STEER.size():
		if i == now or i == (now + 1) % STEER.size():
			Input.action_press(STEER[i])
		else:
			Input.action_release(STEER[i])


func _add(key: String, value: float) -> void:
	var values: PackedFloat64Array = _acc.get(key, PackedFloat64Array())
	values.append(value)
	_acc[key] = values


func _report() -> void:
	if _phase < 0 or _acc.is_empty():
		return
	var line := "%-17s n=%d" % [PHASES[_phase], (_acc["frame_ms"] as PackedFloat64Array).size()]
	for key in KEYS:
		var values: PackedFloat64Array = _acc[key]
		values.sort()
		line += "  %s %.2f/%.2f/%.1f" % [key.trim_suffix("_ms"), values[values.size() / 2], values[int(values.size() * 0.95)], values[values.size() - 1]]
	print(line)


func _apply(world: Node, phase: String) -> void:
	var ground := world.get_node("Ground") as CanvasItem
	var props := world.get_node("Props") as CanvasItem
	var monsters: Array = world.get_node("Monsters").get("members")
	ground.visible = phase != "bez_terenu" and phase != "bez_terenu_propu"
	props.visible = phase != "bez_propu" and phase != "bez_terenu_propu"
	for monster: Node in monsters:
		monster.process_mode = Node.PROCESS_MODE_DISABLED if phase == "bez_prisery" else Node.PROCESS_MODE_INHERIT
