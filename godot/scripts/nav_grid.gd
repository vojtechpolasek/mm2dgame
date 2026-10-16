extends RefCounted

## Mřížka průchodnosti pro honičku. Buňka je jedna dlaždice. Neprůchodná je voda, paty skal
## a jezírek podle obrysu, keře a kmeny, továrna a domy, vše rozšířené o tělo příšery, ať cesta nevede
## škvírou, kterou neprojde. Příšera se podle ní řídí, když se přímá honička zasekne.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const Walker := preload("res://scripts/walker.gd")
const Rocks := preload("res://scripts/rocks.gd")
const Forest := preload("res://scripts/forest.gd")

## Rezerva navíc k tělu v pixelech. Cesta jde mezi středy buněk, ne jen po nich.
const MARGIN := 12.0
## Kolik buněk kolem se hledá volná, když začátek nebo cíl leží v neprůchodné buňce.
const NEAR_CELLS := 3
## Kolik buněk kolem nedosažitelného cíle se hledá buňka, kam se dojít dá. Cesta pak vede tam
## a A* nemusí projít celou oblast, aby zjistil, že k cíli nevede.
const NEAR_REACHABLE := 8

var _astar := AStarGrid2D.new()
var _size := 0
## Číslo souvislé oblasti průchodných buněk, -1 u neprůchodné. Stejné číslo = dá se dojít.
## Úhlopříčka vede jen mezi volnými sousedy, oblasti proto stačí po čtyřech směrech.
var _labels := PackedInt32Array()
var space_origin := Vector2.ZERO


## clearance je výška, kterou tělo přeskočí. Nižší překážky se neoznačí, cesta vede přes ně.
func build(walker: Walker, rocks: Rocks, forest: Forest, body: float, clearance: float = -1.0) -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	_size = int(walker.world().x / tile)
	_astar.region = Rect2i(0, 0, _size, _size)
	_astar.cell_size = Vector2(tile, tile)
	_astar.offset = Vector2(tile, tile) * 0.5
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	walker.block_water(_astar)
	rocks.block_cells(_astar, body, MARGIN, clearance)
	forest.block_cells(_astar, body, MARGIN, clearance)
	if walker.town != null:
		walker.town.block_cells(_astar, body, MARGIN)
	_label_regions()


## Cesta z from do to po středech buněk, bez první buňky. Když se k cíli dojít nedá (postava
## stojí v houští, kam se tělo nevejde), vede co nejblíž k němu. Neprůchodný začátek nebo cíl
## se nahradí nejbližší volnou buňkou. Prázdná, když z místa nevede nikam.
func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if _size == 0:
		return PackedVector2Array()
	var start := _free_cell(_cell(from))
	var goal := _free_cell(_cell(to))
	if start.x < 0 or goal.x < 0:
		return PackedVector2Array()
	if _label_of(goal) != _label_of(start):
		var near := _reachable_near(_cell(to), _label_of(start))
		if near.x >= 0:
			goal = near
	var points := _astar.get_point_path(start, goal, true)
	if points.size() > 1:
		points.remove_at(0)
	if space_origin != Vector2.ZERO:
		for i in points.size():
			points[i] += space_origin
	return points


## Nestojí mezi from a to v mřížce nic? Prochází úsečku po čtvrtinách dlaždice.
func clear_line(from: Vector2, to: Vector2) -> bool:
	if _size == 0:
		return true
	var tile := float(TerrainCatalog.TILE_SIZE)
	var steps := maxi(ceili(from.distance_to(to) / (tile * 0.25)), 1)
	# Buňky, kde stojí příšera a postava, se nepočítají. U překážky bývají neprůchodné
	# kvůli rezervě, a přitom tam obě stojí.
	var start := _cell(from)
	var goal := _cell(to)
	var last := start
	for i in range(1, steps):
		var cell := _cell(from.lerp(to, float(i) / float(steps)))
		if cell == last or cell == goal:
			continue
		last = cell
		if _astar.is_point_solid(cell):
			return false
	return true


## Vede z from do to cesta? Stejná buňka se počítá jako ano.
func reaches(from: Vector2, to: Vector2) -> bool:
	if _size == 0:
		return true
	var start := _free_cell(_cell(from))
	var goal := _free_cell(_cell(to))
	if start.x < 0 or goal.x < 0:
		return false
	return _label_of(start) == _label_of(goal)


func set_space(origin: Vector2) -> void:
	space_origin = origin


func _cell(pos: Vector2) -> Vector2i:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var local := pos - space_origin
	return Vector2i(clampi(floori(local.x / tile), 0, _size - 1), clampi(floori(local.y / tile), 0, _size - 1))


func _free_cell(cell: Vector2i) -> Vector2i:
	if not _astar.is_point_solid(cell):
		return cell
	for ring in range(1, NEAR_CELLS + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var near := cell + Vector2i(dx, dy)
				if _astar.is_in_boundsv(near) and not _astar.is_point_solid(near):
					return near
	return Vector2i(-1, -1)


func _label_of(cell: Vector2i) -> int:
	return _labels[cell.y * _size + cell.x]


## Nejbližší buňka oblasti label kolem cell, nejdál NEAR_REACHABLE buněk. (-1, -1), když není.
func _reachable_near(cell: Vector2i, label: int) -> Vector2i:
	for ring in range(1, NEAR_REACHABLE + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var near := cell + Vector2i(dx, dy)
				if near.x >= 0 and near.y >= 0 and near.x < _size and near.y < _size and _label_of(near) == label:
					return near
	return Vector2i(-1, -1)


## Očísluje souvislé oblasti vlnou z každé ještě neočíslované volné buňky. Jednou po build,
## smí běžet ve vlákně.
func _label_regions() -> void:
	var count := _size * _size
	var solid := PackedByteArray()
	solid.resize(count)
	for y in _size:
		for x in _size:
			if _astar.is_point_solid(Vector2i(x, y)):
				solid[y * _size + x] = 1
	_labels.resize(count)
	_labels.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(count)
	var label := 0
	for first in count:
		if solid[first] == 1 or _labels[first] >= 0:
			continue
		_labels[first] = label
		queue[0] = first
		var head := 0
		var tail := 1
		while head < tail:
			var cell := queue[head]
			head += 1
			var x := cell % _size
			# Čtyři sousedé rozepsaní, pole sousedů by vznikalo pro každou buňku.
			if x > 0 and solid[cell - 1] == 0 and _labels[cell - 1] < 0:
				_labels[cell - 1] = label
				queue[tail] = cell - 1
				tail += 1
			if x < _size - 1 and solid[cell + 1] == 0 and _labels[cell + 1] < 0:
				_labels[cell + 1] = label
				queue[tail] = cell + 1
				tail += 1
			if cell >= _size and solid[cell - _size] == 0 and _labels[cell - _size] < 0:
				_labels[cell - _size] = label
				queue[tail] = cell - _size
				tail += 1
			if cell < count - _size and solid[cell + _size] == 0 and _labels[cell + _size] < 0:
				_labels[cell + _size] = label
				queue[tail] = cell + _size
				tail += 1
		label += 1
