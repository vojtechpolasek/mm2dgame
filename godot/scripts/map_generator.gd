extends RefCounted

const STEP_STRAIGHT := 1000
const STEP_DIAGONAL := 1414
const UNCLAIMED := 2147483647


## Rozdělí mapu mezi náhodné počátky. Každý bere okolní dlaždice, dokud ho nepředběhne jiný terén.
static func grow(size: int, terrain_names: PackedStringArray, rng: RandomNumberGenerator) -> Dictionary:
	var cell_count := size * size
	var terrain := PackedStringArray()
	terrain.resize(cell_count)
	var cost := PackedInt32Array()
	cost.resize(cell_count)
	cost.fill(UNCLAIMED)

	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.06
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	var lobe := PackedFloat32Array()
	lobe.resize(cell_count)
	for y in size:
		for x in size:
			lobe[y * size + x] = noise.get_noise_2d(float(x), float(y))

	var neighbors: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var heap: Array[Vector2i] = []
	for seed in _place_seeds(size, terrain_names, rng):
		var index := seed.y * size + seed.x
		terrain[index] = terrain_names[seed.z]
		cost[index] = 0
		_push(heap, 0, index)

	while not heap.is_empty():
		var claim := _pop(heap)
		var index := claim.y
		if claim.x != cost[index]:
			continue
		var x := index % size
		var y := index / size
		var owner: String = terrain[index]
		for neighbor in neighbors:
			var nx := x + neighbor.x
			var ny := y + neighbor.y
			if nx < 0 or ny < 0 or nx >= size or ny >= size:
				continue
			var next_index := ny * size + nx
			var step := STEP_DIAGONAL if neighbor.x != 0 and neighbor.y != 0 else STEP_STRAIGHT
			step += rng.randi_range(0, 480)
			step += int(lobe[next_index] * 420.0)
			var next_cost := cost[index] + step
			if next_cost < cost[next_index]:
				cost[next_index] = next_cost
				terrain[next_index] = owner
				_push(heap, next_cost, next_index)

	return {"terrain": terrain, "cost": cost}


static func paint(
	layer: TileMapLayer,
	catalog,
	size: int,
	terrain: PackedStringArray,
	cost: PackedInt32Array,
	rng: RandomNumberGenerator,
) -> void:
	var missing := {}
	for y in size:
		for x in size:
			var top_left := _corner_terrain(terrain, cost, size, x, y)
			var top_right := _corner_terrain(terrain, cost, size, x + 1, y)
			var bottom_left := _corner_terrain(terrain, cost, size, x, y + 1)
			var bottom_right := _corner_terrain(terrain, cost, size, x + 1, y + 1)
			var source_id := -1
			if top_left == top_right and top_right == bottom_left and bottom_left == bottom_right:
				source_id = catalog.pick_pure(top_left, rng)
			else:
				var key := "%s-%s-%s-%s" % [top_left, top_right, bottom_left, bottom_right]
				source_id = catalog.pick_transition(key, rng)
				if source_id < 0:
					source_id = catalog.pick_pure(terrain[y * size + x], rng)
					if not missing.has(key):
						missing[key] = true
						push_warning("Chybí přechod %s." % key)
			if source_id < 0:
				continue
			layer.set_cell(Vector2i(x, y), source_id, Vector2i.ZERO)


static func _place_seeds(size: int, terrain_names: PackedStringArray, rng: RandomNumberGenerator) -> Array[Vector3i]:
	var count := clampi(int(round(float(size) / 6.0)), terrain_names.size(), 24)
	var spacing := maxi(4, int(float(size) / sqrt(float(count)) * 0.55))
	var spacing_sq := spacing * spacing
	var points: Array[Vector2i] = []
	var occupied := {}
	var guard := 0
	while points.size() < count and guard < count * 80:
		guard += 1
		var point := Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
		if occupied.has(point):
			continue
		var clear := true
		for existing in points:
			var delta := existing - point
			if delta.length_squared() < spacing_sq:
				clear = false
				break
		if clear:
			points.append(point)
			occupied[point] = true
	guard = 0
	while points.size() < count and guard < size * size:
		guard += 1
		var point := Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
		if occupied.has(point):
			continue
		points.append(point)
		occupied[point] = true

	var assignment: Array[int] = []
	for index in terrain_names.size():
		assignment.append(index)
	while assignment.size() < points.size():
		assignment.append(rng.randi_range(0, terrain_names.size() - 1))
	for index in assignment.size():
		var swap := rng.randi_range(index, assignment.size() - 1)
		var saved := assignment[index]
		assignment[index] = assignment[swap]
		assignment[swap] = saved

	var seeds: Array[Vector3i] = []
	for index in points.size():
		seeds.append(Vector3i(points[index].x, points[index].y, assignment[index]))
	return seeds


## Vrchol patří dlaždici s nejnižší cenou růstu, tedy té blíž svému počátku.
static func _corner_terrain(
	terrain: PackedStringArray,
	cost: PackedInt32Array,
	size: int,
	vx: int,
	vy: int,
) -> String:
	var best_cost := UNCLAIMED
	var best := ""
	for cell in [Vector2i(vx - 1, vy - 1), Vector2i(vx, vy - 1), Vector2i(vx - 1, vy), Vector2i(vx, vy)]:
		if cell.x < 0 or cell.y < 0 or cell.x >= size or cell.y >= size:
			continue
		var index := cell.y * size + cell.x
		if cost[index] < best_cost:
			best_cost = cost[index]
			best = terrain[index]
	return best


static func _push(heap: Array[Vector2i], claim_cost: int, index: int) -> void:
	heap.append(Vector2i(claim_cost, index))
	var item := heap.size() - 1
	while item > 0:
		var parent := (item - 1) >> 1
		if heap[parent].x <= heap[item].x:
			break
		var swap := heap[parent]
		heap[parent] = heap[item]
		heap[item] = swap
		item = parent


static func _pop(heap: Array[Vector2i]) -> Vector2i:
	var top := heap[0]
	var last := heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var item := 0
	var count := heap.size()
	while true:
		var left := item * 2 + 1
		if left >= count:
			break
		var right := left + 1
		var smallest := left
		if right < count and heap[right].x < heap[left].x:
			smallest = right
		if heap[item].x <= heap[smallest].x:
			break
		var swap := heap[item]
		heap[item] = heap[smallest]
		heap[smallest] = swap
		item = smallest
	return top
