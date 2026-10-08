extends Node2D

## Nápis nad jezírkem: název materiálu a jeho body, když je některá postava blízko. Plynule se
## objeví a zmizí. Velikost drží stejnou na obrazovce i při oddálení kamery.

const Crystal := preload("res://scripts/crystal.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")

## Postava blíž ke středu jezírka než tolik metrů nápis ukáže. Jezírko má poloměr asi 1 m.
const NEAR_METERS := 3.0
## Nápis je nad středem jezírka o tolik pixelů obrazovky.
const LIFT_PX := 58.0
## Jak často se hledají blízká jezírka, v sekundách.
const CHECK_EVERY := 0.1
## Rychlost objevení a zmizení, v podílu za sekundu.
const FADE_SPEED := 5.0

var _spots: Array = []
var _crystal: Crystal
var _persons: Array = []
var _camera: MapCamera
var _labels := {}
var _near := {}
var _check_left := 0.0


func setup(spots: Array, crystal: Crystal, persons: Array, camera: MapCamera) -> void:
	_spots = spots
	_crystal = crystal
	_persons = persons
	_camera = camera
	z_index = 20


func _process(delta: float) -> void:
	if _crystal == null:
		return
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_EVERY
		_find_near()
	var zoom := _camera.zoom.x
	for slot: int in _labels.keys():
		var label: Label = _labels[slot]
		var target := 1.0 if _near.has(slot) else 0.0
		label.modulate.a = move_toward(label.modulate.a, target, FADE_SPEED * delta)
		if label.modulate.a <= 0.0 and target == 0.0:
			label.queue_free()
			_labels.erase(slot)
			continue
		var holder := label.get_parent() as Node2D
		holder.scale = Vector2.ONE / zoom
		holder.position = (_spots[slot][0] as Vector2) - Vector2(0.0, LIFT_PX / zoom)


func _find_near() -> void:
	_near.clear()
	var reach := NEAR_METERS * float(TerrainCatalog.TILE_SIZE)
	for slot in _spots.size():
		var pos: Vector2 = _spots[slot][0]
		for person: Node2D in _persons:
			if person.position.distance_squared_to(pos) < reach * reach:
				_near[slot] = true
				if not _labels.has(slot):
					_labels[slot] = _make_label(slot)
				break


func _make_label(slot: int) -> Label:
	var mat: int = _spots[slot][1]
	var holder := Node2D.new()
	add_child(holder)
	var label := Label.new()
	label.text = "%s · %d b" % [_crystal.title_of(mat), _crystal.points_of(mat)]
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.98, 0.93, 0.8))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	label.add_theme_constant_override("outline_size", 7)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(260, 36)
	label.position = -label.size * 0.5
	label.modulate.a = 0.0
	holder.add_child(label)
	return label
