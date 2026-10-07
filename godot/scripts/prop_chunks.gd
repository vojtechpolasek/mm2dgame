extends Node

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")

## Neviditelné přihrádky pro stromy a skály. Rozložení se nelosuje znovu:
## objekt zůstane, kde vyrostl, a přihrádka ho jen schová, když není v záběru.
const TILES := 32

var _camera: Camera2D
var _chunk_px := 2048.0
var _margin := 0.0
var _cells := {}
var _shown := {}
var _min_cell := Vector2i.ZERO
var _max_cell := Vector2i.ZERO
var _has_range := false


func setup(camera: Camera2D) -> void:
	_camera = camera
	_chunk_px = float(TILES * TerrainCatalog.TILE_SIZE)
	# Až po kameře, ať přihrádky vidí nový střed.
	process_priority = 10


## Koruna přesahuje střed. Větší přesah ze stromů a skal se pamatuje.
func grow_margin(extra: float) -> void:
	var next := maxf(_margin, extra)
	if next == _margin:
		return
	_margin = next
	_has_range = false


func adopt(node: Node2D) -> void:
	var key := _cell(node.position)
	if not _cells.has(key):
		_cells[key] = []
	(_cells[key] as Array).append(node)
	node.visible = _shown.has(key)


func refresh() -> void:
	if _camera == null or _chunk_px <= 0.0:
		return
	var view := _camera.get_viewport_rect().size / _camera.zoom
	var center := _camera.get_screen_center_position()
	var rect := Rect2(center - view * 0.5, view).grow(_margin)
	var min_cell := _cell(rect.position)
	var end := rect.end - Vector2(0.001, 0.001)
	var max_cell := _cell(end)
	if _has_range and min_cell == _min_cell and max_cell == _max_cell:
		return
	var previous: Dictionary = _shown
	var next := {}
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var key := Vector2i(x, y)
			next[key] = true
			if not previous.has(key):
				_set_visible(key, true)
	for key in previous:
		if not next.has(key):
			_set_visible(key, false)
	_shown = next
	_min_cell = min_cell
	_max_cell = max_cell
	_has_range = true


func _set_visible(key: Vector2i, on: bool) -> void:
	var listed: Array = _cells.get(key, [])
	for node in listed:
		(node as CanvasItem).visible = on


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / _chunk_px), floori(pos.y / _chunk_px))


func _process(_delta: float) -> void:
	refresh()
