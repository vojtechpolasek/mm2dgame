extends RefCounted

## Mřížka průchodnosti pro honičku. Buňka je jedna dlaždice. Neprůchodná je voda, paty skal
## a jezírek podle obrysu a keře a kmeny, vše rozšířené o tělo příšery, ať cesta nevede
## škvírou, kterou neprojde. Příšera se podle ní řídí, když se přímá honička zasekne.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const Walker := preload("res://scripts/walker.gd")
const Rocks := preload("res://scripts/rocks.gd")
const Forest := preload("res://scripts/forest.gd")

## Rezerva navíc k tělu v pixelech. Cesta jde mezi středy buněk, ne jen po nich.
const MARGIN := 12.0
## Kolik buněk kolem se hledá volná, když začátek nebo cíl leží v neprůchodné buňce.
const NEAR_CELLS := 3

var _astar := AStarGrid2D.new()
var _size := 0


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
	var points := _astar.get_point_path(start, goal, true)
	if points.size() > 1:
		points.remove_at(0)
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
	return start == goal or not _astar.get_id_path(start, goal).is_empty()


func _cell(pos: Vector2) -> Vector2i:
	var tile := float(TerrainCatalog.TILE_SIZE)
	return Vector2i(clampi(int(pos.x / tile), 0, _size - 1), clampi(int(pos.y / tile), 0, _size - 1))


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
