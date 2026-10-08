extends RefCounted

## Generátor nesahá na strom scény, běží ve vlákně. Povrch dlaždice je index do names.

const MapData := preload("res://scripts/map_data.gd")

const UNCLAIMED := 2147483647
## Šířka přihrádky fronty v jednotkách ceny. Cena 1000 je jedna dlaždice.
const COST_BUCKET := 250
## Posun hranice šumem, v násobcích šířky oblasti.
const WARP := 0.5
## Voda nemá počátek blíž ke středu mapy než tohle: podíl strany mapy, nejméně CENTER_DRY_MIN
## dlaždic. Kotlina stojí u středu a jezero by k ní zatarasilo cestu.
const CENTER_DRY_SHARE := 0.2
const CENTER_DRY_MIN := 12.0
## Pojistka: voda, která k středu přesto doroste z dálky, se v tomto poloměru v dlaždicích
## změní na sousední souš.
const CENTER_CLEAR := 8.0
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const AROUND: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


## Rozdělí mapu mezi náhodné počátky. Každý bere okolní dlaždice, dokud ho nepředběhne jiný terén.
## Hranice uhýbá o kus oblasti podle šumu. max_distance omezí terén kolem jeho počátku, v dlaždicích.
## max_share je nejvyšší podíl plochy mapy, který smí daný terén zabrat.
static func grow(
	size: int,
	terrain_names: PackedStringArray,
	rng: RandomNumberGenerator,
	max_distance: Dictionary = {},
	max_share: Dictionary = {},
) -> MapData:
	var cell_count := size * size
	var terrain := PackedByteArray()
	terrain.resize(cell_count)
	terrain.fill(MapData.UNCLAIMED_TERRAIN)
	var cost := PackedInt32Array()
	cost.resize(cell_count)
	cost.fill(UNCLAIMED)
	var limits := PackedFloat32Array()
	limits.resize(terrain_names.size())
	limits.fill(-1.0)
	for id in terrain_names.size():
		limits[id] = float(max_distance.get(terrain_names[id], -1.0))

	var seeds := _place_seeds(size, terrain_names, rng)
	# Vlnová délka je zlomek oblasti, ať je ohyb vidět i při maximálním oddálení.
	var region := float(size) / sqrt(float(maxi(seeds.size(), 1)))
	var amp := region * WARP
	var lobe := _noise_field(size, rng.randi(), 2.0 / region)
	var border := _noise_field(size, rng.randi(), 3.4 / region)
	var origin := PackedInt32Array()
	origin.resize(cell_count)
	origin.fill(-1)
	# Fronta po přihrádkách ceny (Dialův algoritmus): přihrádka je široká COST_BUCKET.
	# V přihrádce je spojový seznam: bucket_head drží první záznam, entry_next další.
	# Cena je vzdálenost po posunu šumem, nejvýš úhlopříčka mapy plus ten posun.
	var max_cost := int((float(size) * 1.42 + amp * 3.0) * 1000.0) + COST_BUCKET
	var bucket_count := max_cost / COST_BUCKET + 2
	var bucket_head := PackedInt32Array()
	bucket_head.resize(bucket_count)
	bucket_head.fill(-1)
	var entry_cell := PackedInt32Array()
	var entry_cost := PackedInt32Array()
	var entry_next := PackedInt32Array()
	for seed in seeds:
		var index := seed.y * size + seed.x
		terrain[index] = seed.z
		cost[index] = 0
		origin[index] = index
		entry_next.append(bucket_head[0])
		bucket_head[0] = entry_cell.size()
		entry_cell.append(index)
		entry_cost.append(0)

	var current := 0
	while current < bucket_count:
		var entry := bucket_head[current]
		if entry < 0:
			current += 1
			continue
		bucket_head[current] = entry_next[entry]
		var index := entry_cell[entry]
		if entry_cost[entry] != cost[index]:
			continue
		var x := index % size
		var y := index / size
		var owner := terrain[index]
		var limit := limits[owner]
		var seed_index := origin[index]
		var seed_x := seed_index % size
		var seed_y := seed_index / size
		var seed_pos := Vector2(float(seed_x), float(seed_y))
		for neighbor in AROUND:
			var nx := x + neighbor.x
			var ny := y + neighbor.y
			if nx < 0 or ny < 0 or nx >= size or ny >= size:
				continue
			var next_index := ny * size + nx
			if limit >= 0.0:
				var dx := float(nx - seed_x)
				var dy := float(ny - seed_y)
				if dx * dx + dy * dy > limit * limit:
					continue
			var warped := Vector2(
				float(nx) + lobe[next_index] * amp,
				float(ny) + border[next_index] * amp,
			)
			var next_cost := int(warped.distance_to(seed_pos) * 1000.0)
			if next_cost < cost[next_index]:
				cost[next_index] = next_cost
				terrain[next_index] = owner
				origin[next_index] = seed_index
				# Bližší než právě zpracovaná přihrádka jde na řadu hned v ní.
				var bucket := clampi(next_cost / COST_BUCKET, current, bucket_count - 1)
				entry_next.append(bucket_head[bucket])
				bucket_head[bucket] = entry_cell.size()
				entry_cell.append(next_index)
				entry_cost.append(next_cost)

	_remove_specks(terrain, cost, size)
	_fill_gaps(terrain, cost, size, limits, terrain_names.find("grass"))
	_limit_shares(terrain, cost, size, limits, terrain_names, max_share)
	_clear_center(terrain, cost, size, terrain_names.find("water"), terrain_names.find("grass"))
	var map := MapData.new()
	map.size = size
	map.names = terrain_names
	map.terrain = terrain
	map.cost = cost
	return map


## Rohy dlaždic pro shader terénu (RGBA = levý horní, pravý horní, levý dolní, pravý dolní)
## a náhodná varianta textury každé dlaždice.
static func corner_data(map: MapData, rng: RandomNumberGenerator, variant_count: int) -> Dictionary:
	var size := map.size
	var span := size + 1
	# Vrchol patří dlaždici s nejnižší cenou růstu, tedy té blíž svému počátku.
	var vertex := PackedByteArray()
	vertex.resize(span * span)
	for vy in span:
		for vx in span:
			var best_cost := UNCLAIMED
			var best := 0
			for cy in range(maxi(vy - 1, 0), mini(vy, size - 1) + 1):
				for cx in range(maxi(vx - 1, 0), mini(vx, size - 1) + 1):
					var index := cy * size + cx
					if map.cost[index] < best_cost:
						best_cost = map.cost[index]
						best = map.terrain[index]
			vertex[vy * span + vx] = best
	var corners := PackedByteArray()
	corners.resize(size * size * 4)
	var variants := PackedByteArray()
	variants.resize(size * size)
	for y in size:
		for x in size:
			var cell := y * size + x
			var top := y * span + x
			corners[cell * 4] = vertex[top]
			corners[cell * 4 + 1] = vertex[top + 1]
			corners[cell * 4 + 2] = vertex[top + span]
			corners[cell * 4 + 3] = vertex[top + span + 1]
			variants[cell] = rng.randi_range(0, variant_count - 1)
	return {"corners": corners, "variants": variants}


static func _noise_field(size: int, seed: int, frequency: float) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	var field := PackedFloat32Array()
	field.resize(size * size)
	for y in size:
		for x in size:
			field[y * size + x] = noise.get_noise_2d(float(x), float(y))
	return field


## Osamocená dlaždice uprostřed jiného terénu se přebarví. Jinak by šum dělal tečky.
static func _remove_specks(terrain: PackedByteArray, cost: PackedInt32Array, size: int) -> void:
	var around := PackedInt32Array()
	around.resize(4)
	var around_cost := PackedInt32Array()
	around_cost.resize(4)
	for _pass in 2:
		var next_terrain := terrain.duplicate()
		var next_cost := cost.duplicate()
		for y in size:
			for x in size:
				var index := y * size + x
				var own := terrain[index]
				var count := 0
				var lonely := true
				for side in SIDES:
					var nx := x + side.x
					var ny := y + side.y
					if nx < 0 or ny < 0 or nx >= size or ny >= size:
						continue
					var nindex := ny * size + nx
					if terrain[nindex] == own:
						lonely = false
						break
					around[count] = terrain[nindex]
					around_cost[count] = cost[nindex]
					count += 1
				if not lonely or count == 0:
					continue
				# Nejčastější soused. Při shodě vyhraje ten, kdo byl první.
				var best := 0
				var best_count := 0
				for i in count:
					var same := 0
					for j in count:
						if around[j] == around[i]:
							same += 1
					if same > best_count:
						best_count = same
						best = i
				next_terrain[index] = around[best]
				next_cost[index] = around_cost[best]
		terrain.clear()
		terrain.append_array(next_terrain)
		cost.clear()
		cost.append_array(next_cost)


## Kapsy, kam voda nepustí ostatní terény, doplní souší. Jinak by dlaždice zůstala prázdná.
static func _fill_gaps(
	terrain: PackedByteArray,
	cost: PackedInt32Array,
	size: int,
	limits: PackedFloat32Array,
	preferred: int,
) -> void:
	var fallback := preferred if preferred >= 0 and limits[preferred] < 0.0 else -1
	for id in limits.size():
		if fallback >= 0:
			break
		if limits[id] < 0.0:
			fallback = id
	if fallback < 0:
		return
	var pending := PackedInt32Array()
	for index in terrain.size():
		if cost[index] == UNCLAIMED:
			pending.append(index)
	while not pending.is_empty():
		var next := PackedInt32Array()
		for index in pending:
			if cost[index] != UNCLAIMED:
				continue
			var x := index % size
			var y := index / size
			var donor := -1
			var donor_cost := UNCLAIMED
			for side in SIDES:
				var nx := x + side.x
				var ny := y + side.y
				if nx < 0 or ny < 0 or nx >= size or ny >= size:
					continue
				var nindex := ny * size + nx
				if cost[nindex] == UNCLAIMED or limits[terrain[nindex]] >= 0.0:
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
		if cost[index] == UNCLAIMED:
			terrain[index] = fallback
			cost[index] = 0


## Terén z max_share nesmí zabrat víc než daný podíl dlaždic.
## Přebytek se ubírá od břehu. Větší jezero přijde na řadu dřív než malé.
static func _limit_shares(
	terrain: PackedByteArray,
	cost: PackedInt32Array,
	size: int,
	limits: PackedFloat32Array,
	terrain_names: PackedStringArray,
	max_share: Dictionary,
) -> void:
	for terrain_name in max_share:
		var id := terrain_names.find(str(terrain_name))
		if id < 0:
			continue
		var share := float(max_share[terrain_name])
		if share < 0.0 or share >= 1.0:
			continue
		_shrink_to_share(terrain, cost, size, limits, id, share, terrain_names.find("grass"))


static func _shrink_to_share(
	terrain: PackedByteArray,
	cost: PackedInt32Array,
	size: int,
	limits: PackedFloat32Array,
	id: int,
	share: float,
	preferred: int,
) -> void:
	var cell_count := size * size
	var budget := floori(float(cell_count) * share)
	var count := 0
	var shore := PackedInt32Array()
	for y in size:
		for x in size:
			var index := y * size + x
			if terrain[index] != id:
				continue
			count += 1
			if _touches_land(terrain, size, index, id):
				shore.append(index)
	if count <= budget:
		return

	var heap: Array[Vector2i] = []
	for index in shore:
		_heap_push(heap, Vector2i(cost[index], index))

	var unresolved := PackedInt32Array()
	var fallback := _land_fallback(limits, preferred, id)
	while count > budget and not heap.is_empty():
		var index := _heap_pop(heap).y
		if terrain[index] != id:
			continue
		if _give_to_land(terrain, cost, size, index, id):
			unresolved.append(index)
		count -= 1
		var x := index % size
		var y := index / size
		for side in SIDES:
			var nx := x + side.x
			var ny := y + side.y
			if nx < 0 or ny < 0 or nx >= size or ny >= size:
				continue
			var nindex := ny * size + nx
			if terrain[nindex] == id:
				_heap_push(heap, Vector2i(cost[nindex], nindex))
	# Voda oddělená od souše jen rohem by v haldě nebyla. I ta musí pod strop.
	if count > budget:
		for index in cell_count:
			if count <= budget:
				break
			if terrain[index] != id:
				continue
			if _give_to_land(terrain, cost, size, index, id):
				unresolved.append(index)
			count -= 1
	_resolve_unclaimed(terrain, cost, size, unresolved, id, fallback)


## Okraj mapy se počítá jako břeh, odtud se voda taky smí ubírat.
## Voda blíž ke středu než CENTER_CLEAR převezme terén sousední souše, od kraje kruhu dovnitř.
## Kde souš v dosahu není, zůstane tráva.
static func _clear_center(terrain: PackedByteArray, cost: PackedInt32Array, size: int, liquid: int, fallback: int) -> void:
	if liquid < 0:
		return
	var center := Vector2(float(size), float(size)) * 0.5
	var lo := maxi(int(center.x - CENTER_CLEAR) - 1, 0)
	var hi := mini(int(center.x + CENTER_CLEAR) + 1, size - 1)
	var pending := PackedInt32Array()
	for y in range(lo, hi + 1):
		for x in range(lo, hi + 1):
			var index := y * size + x
			if terrain[index] != liquid:
				continue
			if Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center) >= CENTER_CLEAR:
				continue
			terrain[index] = MapData.UNCLAIMED_TERRAIN
			pending.append(index)
	if not pending.is_empty():
		_resolve_unclaimed(terrain, cost, size, pending, liquid, fallback)


static func _touches_land(terrain: PackedByteArray, size: int, index: int, liquid: int) -> bool:
	var x := index % size
	var y := index / size
	if x == 0 or y == 0 or x == size - 1 or y == size - 1:
		return true
	for side in SIDES:
		var nx := x + side.x
		var ny := y + side.y
		if terrain[ny * size + nx] != liquid:
			return true
	return false


## true, když dlaždice ještě nemá sousední souš a doplní se až v dalším kroku.
static func _give_to_land(
	terrain: PackedByteArray,
	cost: PackedInt32Array,
	size: int,
	index: int,
	liquid: int,
) -> bool:
	var donor := _land_donor(terrain, cost, size, index, liquid)
	if donor >= 0:
		terrain[index] = terrain[donor]
		cost[index] = cost[donor]
		return false
	terrain[index] = MapData.UNCLAIMED_TERRAIN
	return true


## Halda podle ceny růstu, nejvyšší navrchu. Vector2i.x je cena, y je dlaždice.
static func _heap_push(heap: Array[Vector2i], item: Vector2i) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if heap[parent].x >= heap[i].x:
			break
		var saved := heap[parent]
		heap[parent] = heap[i]
		heap[i] = saved
		i = parent


static func _heap_pop(heap: Array[Vector2i]) -> Vector2i:
	var top := heap[0]
	var last := heap[heap.size() - 1]
	heap.remove_at(heap.size() - 1)
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var left := i * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var best := left
		if right < heap.size() and heap[right].x > heap[left].x:
			best = right
		if heap[i].x >= heap[best].x:
			break
		var saved := heap[i]
		heap[i] = heap[best]
		heap[best] = saved
		i = best
	return top


## Sousední souš s nejnižší cenou růstu. Voda ani nevyplněná dlaždice se nepočítá.
static func _land_donor(
	terrain: PackedByteArray,
	cost: PackedInt32Array,
	size: int,
	index: int,
	liquid: int,
) -> int:
	var x := index % size
	var y := index / size
	var donor := -1
	var donor_cost := UNCLAIMED
	for side in AROUND:
		var nx := x + side.x
		var ny := y + side.y
		if nx < 0 or ny < 0 or nx >= size or ny >= size:
			continue
		var nindex := ny * size + nx
		var kind := terrain[nindex]
		if kind == liquid or kind == MapData.UNCLAIMED_TERRAIN:
			continue
		if cost[nindex] < donor_cost:
			donor = nindex
			donor_cost = cost[nindex]
	return donor


static func _land_fallback(limits: PackedFloat32Array, preferred: int, avoid: int) -> int:
	if preferred >= 0 and preferred != avoid and preferred < limits.size() and limits[preferred] < 0.0:
		return preferred
	for id in limits.size():
		if id != avoid and limits[id] < 0.0:
			return id
	for id in limits.size():
		if id != avoid:
			return id
	return -1


## Dlaždice sloupnuté od břehu, které ještě nemají sousední souš, převezmou terén, až k nim dojde.
static func _resolve_unclaimed(
	terrain: PackedByteArray,
	cost: PackedInt32Array,
	size: int,
	pending: PackedInt32Array,
	liquid: int,
	fallback: int,
) -> void:
	while not pending.is_empty():
		var next := PackedInt32Array()
		for index in pending:
			if terrain[index] != MapData.UNCLAIMED_TERRAIN:
				continue
			var donor := _land_donor(terrain, cost, size, index, liquid)
			if donor >= 0:
				terrain[index] = terrain[donor]
				cost[index] = cost[donor]
			else:
				next.append(index)
		if next.size() == pending.size():
			break
		pending = next
	if fallback < 0:
		return
	for index in pending:
		if terrain[index] == MapData.UNCLAIMED_TERRAIN:
			terrain[index] = fallback
			cost[index] = 0


static func _place_seeds(size: int, terrain_names: PackedStringArray, rng: RandomNumberGenerator) -> Array[Vector3i]:
	var count := mini(maxi(int(round(float(size) / 6.0)), terrain_names.size()), size * size)
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

	_dry_center(points, assignment, size, terrain_names)
	var seeds: Array[Vector3i] = []
	for index in points.size():
		seeds.append(Vector3i(points[index].x, points[index].y, assignment[index]))
	return seeds


## Počátek vody u středu si prohodí terén s počátkem souše dál od středu. Podíly terénů zůstanou.
## Když žádná taková souš není, stane se z vody tráva.
static func _dry_center(points: Array[Vector2i], assignment: Array[int], size: int, terrain_names: PackedStringArray) -> void:
	var water := terrain_names.find("water")
	if water < 0:
		return
	var center := Vector2(float(size), float(size)) * 0.5
	var dry := maxf(CENTER_DRY_MIN, float(size) * CENTER_DRY_SHARE)
	for index in points.size():
		if assignment[index] != water or Vector2(points[index]).distance_to(center) >= dry:
			continue
		var swapped := false
		for other in points.size():
			if assignment[other] == water or Vector2(points[other]).distance_to(center) < dry:
				continue
			assignment[index] = assignment[other]
			assignment[other] = water
			swapped = true
			break
		if not swapped:
			assignment[index] = maxi(terrain_names.find("grass"), 0)
