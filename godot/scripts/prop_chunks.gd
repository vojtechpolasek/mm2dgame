extends Node

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapCamera := preload("res://scripts/map_camera.gd")

## Přihrádky pro stromy a skály. Rozložení se nelosuje znovu: objekt zůstane, kde vyrostl.
## Přihrádka si pamatuje jen čísla objektů. Uzly si od majitele (acquire) bere, až je v záběru,
## a po skrytí mu je vrací (release) do zásobníku.
## Přihrádka je velká a bere desítky uzlů. Nová přihrádka proto uzly nebere najednou, ale
## v _process postupně, nejvýš SHOW_BUDGET_US za snímek, nejbližší ke středu záběru první.
## Do přihrádky se vstupuje už s okrajem _margin, uzly dojdou dřív, než je objekt v záběru.
## Poprvé se ukáže všechno hned.
const TILES := 32
const SHOW_BUDGET_US := 2000

var _camera: MapCamera
var _chunk_px := 2048.0
var _margin := 0.0
## Klíč přihrádky -> {majitel: Array čísel objektů}
var _cells := {}
## Klíč zobrazené přihrádky -> {majitel: [Array čísel, Array uzlů]}
var _live := {}
var _min_cell := Vector2i.ZERO
var _max_cell := Vector2i.ZERO
var _has_range := false
## Objekty čekající na uzel: [klíč přihrádky, majitel, číslo], od konce se berou nejbližší.
var _pending: Array = []


func setup(camera: MapCamera) -> void:
	_camera = camera
	_chunk_px = float(TILES * TerrainCatalog.TILE_SIZE)
	camera.view_changed.connect(refresh)


## Koruna přesahuje střed. Větší přesah ze stromů a skal se pamatuje.
func grow_margin(extra: float) -> void:
	var next := maxf(_margin, extra)
	if next == _margin:
		return
	_margin = next
	_has_range = false
	refresh()


func register(holder: Object, index: int, pos: Vector2) -> void:
	var key := _cell(pos)
	if not _cells.has(key):
		_cells[key] = {}
	var holders: Dictionary = _cells[key]
	if not holders.has(holder):
		holders[holder] = []
	(holders[holder] as Array).append(index)
	if _live.has(key):
		var live := _live_of(key, holder)
		(live[0] as Array).append(index)
		(live[1] as Array).append(holder.acquire(index))


## Zapomene objekty majitele: zobrazené mu vrátí (release) a dál je nebude chtít.
func forget(holder: Object) -> void:
	for key: Vector2i in _live:
		var holders: Dictionary = _live[key]
		if not holders.has(holder):
			continue
		var indices: Array = holders[holder][0]
		var nodes: Array = holders[holder][1]
		for i in indices.size():
			holder.release(indices[i], nodes[i])
		holders.erase(holder)
	_pending = _pending.filter(func(item: Array) -> bool: return item[1] != holder)
	for key: Vector2i in _cells.keys():
		var holders: Dictionary = _cells[key]
		holders.erase(holder)
		if holders.is_empty():
			_cells.erase(key)


func refresh() -> void:
	if _camera == null or _chunk_px <= 0.0:
		return
	var view := _camera.get_viewport_rect().size / _camera.zoom
	var center := _camera.get_screen_center_position()
	var rect := Rect2(center - view * 0.5, view).grow(_margin)
	var min_cell := _cell(rect.position)
	var max_cell := _cell(rect.end - Vector2(0.001, 0.001))
	if _has_range and min_cell == _min_cell and max_cell == _max_cell:
		return
	var wanted := {}
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			wanted[Vector2i(x, y)] = true
	# Nejdřív vrátit uzly skrytých přihrádek, ať je nové vezmou ze zásobníku.
	for key: Vector2i in _live.keys():
		if not wanted.has(key):
			_hide(key)
	var added: Array[Vector2i] = []
	for key: Vector2i in wanted:
		if not _live.has(key):
			added.append(key)
	# Nejvzdálenější dopředu, z fronty se bere od konce.
	added.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _cell_center(a).distance_squared_to(center) > _cell_center(b).distance_squared_to(center))
	var queued: Array = []
	for key in added:
		_live[key] = {}
		var holders: Dictionary = _cells.get(key, {})
		for holder: Object in holders:
			for index: int in holders[holder]:
				queued.append([key, holder, index])
	_pending = queued + _pending
	if not _has_range:
		_take(INF)
	_min_cell = min_cell
	_max_cell = max_cell
	_has_range = true


func _process(_delta: float) -> void:
	if not _pending.is_empty():
		_take(SHOW_BUDGET_US)


## Vezme uzly čekajícím objektům, dokud nevyprší budget mikrosekund.
func _take(budget: float) -> void:
	var start := Time.get_ticks_usec()
	while not _pending.is_empty() and Time.get_ticks_usec() - start < budget:
		var item: Array = _pending.pop_back()
		var live := _live_of(item[0], item[1])
		(live[0] as Array).append(item[2])
		(live[1] as Array).append((item[1] as Object).acquire(item[2]))


func _cell_center(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(0.5, 0.5)) * _chunk_px


func _hide(key: Vector2i) -> void:
	var holders: Dictionary = _live[key]
	for holder: Object in holders:
		var indices: Array = holders[holder][0]
		var nodes: Array = holders[holder][1]
		for i in indices.size():
			holder.release(indices[i], nodes[i])
	_live.erase(key)
	_pending = _pending.filter(func(item: Array) -> bool: return item[0] != key)


func _live_of(key: Vector2i, holder: Object) -> Array:
	var holders: Dictionary = _live[key]
	if not holders.has(holder):
		holders[holder] = [[], []]
	return holders[holder]


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / _chunk_px), floori(pos.y / _chunk_px))
