extends Node

const SECONDS := 60.0
var _t := 0.0
var _ready_at := -1.0
var _next := 0.0
var _samples := {}

func _process(delta: float) -> void:
	_t += delta
	var world := get_tree().current_scene
	if world == null or not world.get("_map_ready"):
		return
	if _ready_at < 0.0:
		_ready_at = _t
	var since := _t - _ready_at
	var board = world.get_node("Board")
	var sq = board._squares.get(board._active)
	if since >= _next:
		_next += 1.0
		var tile := 64.0
		for monster in sq.monsters.members:
			if not is_instance_valid(monster):
				continue
			var mat: int = monster.material_index
			var best := INF
			for slot in sq.rocks.ponds_holding(mat):
				best = minf(best, monster.global_position.distance_to(sq.rocks.pond_center(slot)))
			var list: Array = _samples.get(mat, [])
			list.append(best / tile)
			_samples[mat] = list
	if since > SECONDS:
		var crystal = board._crystal
		var keys := _samples.keys()
		keys.sort()
		for mat in keys:
			var list: Array = _samples[mat]
			list.sort()
			print("%2d %-10s min %5.1f  med %5.1f  max %5.1f  (n=%d)" % [mat, crystal.name_of(mat), list[0], list[list.size() / 2], list[list.size() - 1], list.size()])
		get_tree().quit()
