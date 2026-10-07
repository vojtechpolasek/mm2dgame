extends RefCounted

const UNCLAIMED := 2147483647


## Rozdělí mapu mezi náhodné počátky. Každý bere okolní dlaždice, dokud ho nepředběhne jiný terén.
## Hranice se lámou posunem souřadnic šumem. max_distance omezí terén kolem jeho počátku, v dlaždicích.
static func grow(
	size: int,
	terrain_names: PackedStringArray,
	rng: RandomNumberGenerator,
	max_distance: Dictionary = {},
) -> Dictionary:
	var cell_count := size * size
	var terrain := PackedStringArray()
	terrain.resize(cell_count)
	var cost := PackedInt32Array()
	cost.resize(cell_count)
	cost.fill(UNCLAIMED)

	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.09
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	var border_noise := FastNoiseLite.new()
	border_noise.seed = rng.randi()
	border_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	border_noise.frequency = 0.12
	border_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	border_noise.fractal_octaves = 2
	var lobe := PackedFloat32Array()
	var border := PackedFloat32Array()
	lobe.resize(cell_count)
	border.resize(cell_count)
	for y in size:
		for x in size:
			var cell := y * size + x
			lobe[cell] = noise.get_noise_2d(float(x), float(y))
			border[cell] = border_noise.get_noise_2d(float(x), float(y))

	var shore_noise := FastNoiseLite.new()
	shore_noise.seed = rng.randi()
	shore_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shore_noise.frequency = 0.18
	shore_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	shore_noise.fractal_octaves = 2
	var neighbors: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var origin := PackedInt32Array()
	origin.resize(cell_count)
	origin.fill(-1)
	var heap: Array[Vector2i] = []
	for seed in _place_seeds(size, terrain_names, rng):
		var index := seed.y * size + seed.x
		terrain[index] = terrain_names[seed.z]
		cost[index] = 0
		origin[index] = index
		_push(heap, 0, index)

	while not heap.is_empty():
		var claim := _pop(heap)
		var index := claim.y
		if claim.x != cost[index]:
			continue
		var x := index % size
		var y := index / size
		var owner: String = terrain[index]
		var limit := float(max_distance.get(owner, -1.0))
		var seed_index := origin[index]
		var seed_x := seed_index % size
		var seed_y := seed_index / size
		for neighbor in neighbors:
			var nx := x + neighbor.x
			var ny := y + neighbor.y
			if nx < 0 or ny < 0 or nx >= size or ny >= size:
				continue
			if limit >= 0.0:
				var dx := float(nx - seed_x)
				var dy := float(ny - seed_y)
				var angle := atan2(dy, dx)
				var phase := float(seed_x * 13 + seed_y * 7) * 0.17
				var shaped := sin(angle * 1.3 + phase) * 0.4
				shaped += sin(angle * 2.3 - phase * 0.7) * 0.32
				shaped += sin(angle * 3.7 - phase * 1.6) * 0.22
				shaped += sin(angle * 5.1 + phase * 0.7) * 0.14
				var wobble := clampf(shaped * 0.5 + 0.5, 0.0, 1.0)
				var reach := limit * lerpf(0.22, 1.0, wobble)
				var dist := sqrt(dx * dx + dy * dy)
				if dist > reach:
					continue
				var carve := shore_noise.get_noise_2d(float(nx), float(ny))
				var edge := 0.48 + 0.52 * (carve * 0.5 + 0.5)
				if dist / reach > edge:
					continue
			var next_index := ny * size + nx
			var warped := Vector2(
				float(nx) + lobe[next_index] * 7.0,
				float(ny) + border[next_index] * 7.0,
			)
			var next_cost := int(warped.distance_to(Vector2(float(seed_x), float(seed_y))) * 1000.0)
			next_cost += rng.randi_range(0, 40)
			if next_cost < cost[next_index]:
				cost[next_index] = next_cost
				terrain[next_index] = owner
				origin[next_index] = seed_index
				_push(heap, next_cost, next_index)

	_remove_specks(terrain, cost, size)
	_fill_gaps(terrain, cost, size, terrain_names, max_distance)
	return {"terrain": terrain, "cost": cost}


## Osamocená dlaždice uprostřed jiného terénu se přebarví. Jinak by šum dělal tečky.
static func _remove_specks(terrain: PackedStringArray, cost: PackedInt32Array, size: int) -> void:
	var neighbors: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for _pass in 2:
		var next_terrain := terrain.duplicate()
		var next_cost := cost.duplicate()
		for index in terrain.size():
			var x := index % size
			var y := index / size
			var same := 0
			var counts := {}
			var best_name := terrain[index]
			var best_count := 0
			var best_cost := cost[index]
			for neighbor in neighbors:
				var nx := x + neighbor.x
				var ny := y + neighbor.y
				if nx < 0 or ny < 0 or nx >= size or ny >= size:
					continue
				var nindex := ny * size + nx
				var name: String = terrain[nindex]
				if name == terrain[index]:
					same += 1
				var total := int(counts.get(name, 0)) + 1
				counts[name] = total
				if total > best_count:
					best_count = total
					best_name = name
					best_cost = cost[nindex]
			if same == 0 and best_name != terrain[index]:
				next_terrain[index] = best_name
				next_cost[index] = best_cost
		for index in terrain.size():
			terrain[index] = next_terrain[index]
			cost[index] = next_cost[index]


## Kapsy, kam voda nepustí ostatní terény, doplní souší. Jinak by dlaždice zůstala prázdná.
static func _fill_gaps(
	terrain: PackedStringArray,
	cost: PackedInt32Array,
	size: int,
	terrain_names: PackedStringArray,
	max_distance: Dictionary,
) -> void:
	var walkable: PackedStringArray = PackedStringArray()
	for name in terrain_names:
		if not max_distance.has(name):
			walkable.append(name)
	if walkable.is_empty():
		return
	var fallback := walkable[0]
	if walkable.has("grass"):
		fallback = "grass"
	var neighbors: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var pending: Array[int] = []
	for index in terrain.size():
		if cost[index] == UNCLAIMED:
			pending.append(index)
	var guard := 0
	while not pending.is_empty() and guard < terrain.size():
		guard += 1
		var next: Array[int] = []
		for index in pending:
			if cost[index] != UNCLAIMED:
				continue
			var x := index % size
			var y := index / size
			var donor := -1
			var donor_cost := UNCLAIMED
			for neighbor in neighbors:
				var nx := x + neighbor.x
				var ny := y + neighbor.y
				if nx < 0 or ny < 0 or nx >= size or ny >= size:
					continue
				var nindex := ny * size + nx
				if cost[nindex] == UNCLAIMED or not walkable.has(terrain[nindex]):
					continue
				if cost[nindex] < donor_cost:
					donor = nindex
					donor_cost = cost[nindex]
			if donor >= 0:
				terrain[index] = terrain[donor]
				cost[index] = 0
			else:
				next.append(index)
		if next.size() == pending.size():
			break
		pending = next
	for index in pending:
		if cost[index] != UNCLAIMED:
			continue
		terrain[index] = fallback
		cost[index] = 0


static func paint(
	layer: TileMapLayer,
	catalog,
	size: int,
	terrain: PackedStringArray,
	cost: PackedInt32Array,
	rng: RandomNumberGenerator,
) -> void:
	catalog.begin_map(size)
	for y in size:
		for x in size:
			var top_left := _corner_terrain(terrain, cost, size, x, y)
			var top_right := _corner_terrain(terrain, cost, size, x + 1, y)
			var bottom_left := _corner_terrain(terrain, cost, size, x, y + 1)
			var bottom_right := _corner_terrain(terrain, cost, size, x + 1, y + 1)
			catalog.write_cell(
				x,
				y,
				catalog.index_of(top_left),
				catalog.index_of(top_right),
				catalog.index_of(bottom_left),
				catalog.index_of(bottom_right),
				rng.randi_range(0, catalog.variant_count - 1),
			)
			layer.set_cell(Vector2i(x, y), catalog.source_id, Vector2i.ZERO)
	catalog.finish_map()


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
	var cells: Array[Vector2i] = [
		Vector2i(vx - 1, vy - 1), Vector2i(vx, vy - 1), Vector2i(vx - 1, vy), Vector2i(vx, vy),
	]
	for cell in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= size or cell.y >= size:
			continue
		var index: int = cell.y * size + cell.x
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
	var top: Vector2i = heap[0]
	var last: Vector2i = heap.pop_back()
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
