extends Node2D

## Nápis nad jezírkem: co v něm leží, od nejdražšího, každý materiál na řádku s počtem a body,
## když je některá postava blízko. Plynule se objeví a zmizí, text se mění s výměnami. Velikost
## drží stejnou na obrazovce i při oddálení kamery.

const Crystal := preload("res://scripts/crystal.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const Rocks := preload("res://scripts/rocks.gd")

## Postava blíž ke středu jezírka než tolik metrů nápis ukáže. Jezírko má poloměr asi 1 m.
const NEAR_METERS := 3.0
## Spodní řádek nápisu je nad středem jezírka o tolik pixelů obrazovky, další řádky nad ním.
const LIFT_PX := 58.0
const LINE_PX := 28.0
const LABEL_WIDTH := 300.0
## Jak často se hledají blízká jezírka, v sekundách.
const CHECK_EVERY := 0.1
## Rychlost objevení a zmizení, v podílu za sekundu.
const FADE_SPEED := 5.0

var _spots: Array = []
var _crystal: Crystal
var _persons: Array = []
var _camera: MapCamera
var _rocks: Rocks
var _labels := {}
var _near := {}
var _check_left := 0.0


## spots jsou trojice [pos, mat, slot] z Rocks.pond_spots. Prázdné jezírko nápis nemá.
func setup(spots: Array, crystal: Crystal, persons: Array, camera: MapCamera, rocks: Rocks) -> void:
	_spots = spots
	_rocks = rocks
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
		if _rocks != null and _rocks.pond_left(int(_spots[slot][2])) <= 0:
			continue
		var pos: Vector2 = _spots[slot][0]
		for person: Node2D in _persons:
			if person.position.distance_squared_to(pos) < reach * reach:
				_near[slot] = true
				if not _labels.has(slot):
					_labels[slot] = _make_label(slot)
				_fill(_labels[slot], slot)
				break


## Řádek za každý materiál v jezírku: „Diamant ×2 · 90 b“. Bezedné jezírko svůj materiál bez počtu.
func _fill(label: Label, slot: int) -> void:
	var lines := PackedStringArray()
	for entry: Array in _rocks.pond_summary(int(_spots[slot][2])):
		var mat: int = entry[0]
		var count: int = entry[1]
		var many := " ×%d" % count if count > 1 else ""
		lines.append("%s%s · %d b" % [_crystal.title_of(mat), many, _crystal.points_of(mat)])
	var text := "\n".join(lines)
	if label.text == text:
		return
	label.text = text
	label.size = Vector2(LABEL_WIDTH, LINE_PX * float(maxi(lines.size(), 1)) + 8.0)
	label.position = Vector2(-LABEL_WIDTH * 0.5, -label.size.y + LINE_PX * 0.5 + 4.0)


func _make_label(_slot: int) -> Label:
	var holder := Node2D.new()
	add_child(holder)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.98, 0.93, 0.8))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	label.add_theme_constant_override("outline_size", 7)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.modulate.a = 0.0
	holder.add_child(label)
	return label
