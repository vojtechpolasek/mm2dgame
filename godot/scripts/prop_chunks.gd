extends Node

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapCamera := preload("res://scripts/map_camera.gd")

## Přihrádky pro stromy a skály. Rozložení se nelosuje znovu: objekt zůstane, kde vyrostl.
## Přihrádka si pamatuje jen čísla objektů. Uzly si od majitele (acquire) bere, až je v záběru,
## a po skrytí mu je vrací (release) do zásobníku.
const TILES := 32

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
	for key: Vector2i in wanted:
		if not _live.has(key):
			_show(key)
	_min_cell = min_cell
	_max_cell = max_cell
	_has_range = true


func _show(key: Vector2i) -> void:
	_live[key] = {}
	var holders: Dictionary = _cells.get(key, {})
	for holder: Object in holders:
		var live := _live_of(key, holder)
		for index: int in holders[holder]:
			(live[0] as Array).append(index)
			(live[1] as Array).append(holder.acquire(index))


func _hide(key: Vector2i) -> void:
	var holders: Dictionary = _live[key]
	for holder: Object in holders:
		var indices: Array = holders[holder][0]
		var nodes: Array = holders[holder][1]
		for i in indices.size():
			holder.release(indices[i], nodes[i])
	_live.erase(key)


func _live_of(key: Vector2i, holder: Object) -> Array:
	var holders: Dictionary = _live[key]
	if not holders.has(holder):
		holders[holder] = [[], []]
	return holders[holder]


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / _chunk_px), floori(pos.y / _chunk_px))
