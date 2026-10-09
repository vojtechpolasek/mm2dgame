extends Node2D

## Šipky vytesané do okraje kotliny, ke každému jezírku jedna. Leží na horní vrstvě kotliny mezi
## středem, kam padají kameny, a vnějším okrajem. Šipka míří od středu kotliny k jezírku a u paty
## má kulatou prohlubeň s kamenem materiálu. Vybrané jezírko nechá prázdnou prohlubeň.
## Vytesání je tmavší dno a stěny nasvícené zleva shora jako skály: stěna blíž ke světlu je ve
## stínu, protější svítí. Šipky, které by se překryly, se rozestoupí vedle sebe. Uzel je potomkem
## kotliny, otočení kotliny mu ruší Rocks, takže úhly platí ve světě.

const Crystal := preload("res://scripts/crystal.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const SHADER := preload("res://shaders/compass_layer.gdshader")

## Vzdálenosti od středu kotliny v pixelech. Ústí kotliny (kam padají kameny) má poloměr asi
## 113 px, horní vrstva končí na 174 px.
const SOCKET_AT := 133.0
const SOCKET_RADIUS := 13.0
const NECK_AT := 156.0
const TIP_AT := 172.0
const SHAFT_WIDTH := 10.0
const HEAD_WIDTH := 24.0
## Kámen v prohlubni, poloměr v pixelech.
const GEM_RADIUS := 9.5
## Nejmenší rozestup sousedních šipek, v pixelech na poloměru prohlubně.
const SPREAD_PX := 29.0
## Šířka stěny vytesání v pixelech.
const WALL := 2.5
## Směr ke světlu na obrazovce (zleva shora), jako u skal v tools/gen_rocks.py.
const LIGHT := Vector2(-0.63, -0.77)
## Barva povrchu kotliny z rocks.json. Dno, stín a světlo stěn jsou její násobky. Kotlina je
## ve hře vystínovaná tmavší než tahle barva, dno proto musí být hodně tmavé, aby bylo znát.
const STONE := Color("3E3B36")
const FLOOR_DARK := 0.55
const WALL_SHADOW := 0.3
const WALL_LIGHT := 1.75
const CIRCLE_POINTS := 20

var _crystal: Crystal
var _height := 0.0
## Zobrazené šipky: [úhel, materiál, kámen je v prohlubni].
var _arrows := []
## Obrys šipky mířící doprava (úhel 0), po směru hodin. Ostatní jsou otočené.
var _shape := PackedVector2Array()
var _gems: Array[Sprite2D] = []


## height je výška horní vrstvy kotliny v metrech, posun podle ní drží šipky s okrajem.
func setup(height: float, crystal: Crystal) -> void:
	_height = height
	_crystal = crystal
	var shift := ShaderMaterial.new()
	shift.shader = SHADER
	shift.set_shader_parameter("height_m", height)
	shift.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
	material = shift
	_shape = _arrow_shape()
	# Posun výšky vrcholy vystrčí z obdélníku uzlu, bez většího obdélníku by šipky u kraje
	# obrazovky zmizely.
	var reach := TIP_AT + ObjectLayers.vertex_pad(Vector2(3840, 2160), height)
	RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, Rect2(-reach, -reach, reach * 2.0, reach * 2.0))


## targets jsou trojice [úhel ve světě, materiál, plné] z Rocks.compass_targets.
func show_targets(targets: Array) -> void:
	_arrows = targets.duplicate(true)
	_arrows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	_spread()
	_place_gems()
	queue_redraw()


## Rozestoupí šipky, které jsou si blíž než SPREAD_PX: každá dvojice se odsune od sebe na
## polovinu chybějícího kusu. Pár kol stačí, šipek je nejvýš pár desítek.
func _spread() -> void:
	var count := _arrows.size()
	if count < 2:
		return
	var least := minf(SPREAD_PX / SOCKET_AT, TAU / float(count))
	for _round in 24:
		var moved := false
		for i in count:
			var next := (i + 1) % count
			var gap := wrapf(float(_arrows[next][0]) - float(_arrows[i][0]), 0.0, TAU)
			if gap >= least - 0.0001:
				continue
			var push := (least - gap) * 0.5
			_arrows[i][0] = float(_arrows[i][0]) - push
			_arrows[next][0] = float(_arrows[next][0]) + push
			moved = true
		if not moved:
			return


## Kameny v prohlubních plných šipek. Posun výšky počítají od středu kotliny jako okraj.
func _place_gems() -> void:
	var shown := 0
	for arrow: Array in _arrows:
		if not bool(arrow[2]) or _crystal == null or _crystal.count() == 0:
			continue
		if shown >= _gems.size():
			var sprite := _crystal.make_sprite()
			sprite.scale = Vector2.ONE * GEM_RADIUS / maxf(_crystal.radius(), 1.0)
			add_child(sprite)
			_gems.append(sprite)
		var gem := _gems[shown]
		var angle := float(arrow[0])
		gem.position = Vector2.from_angle(angle) * SOCKET_AT
		gem.rotation = angle
		gem.visible = true
		_crystal.paint(gem, int(arrow[1]), _height, angle)
		gem.set_instance_shader_parameter("anchor_offset", gem.position)
		shown += 1
	for i in range(shown, _gems.size()):
		_gems[i].visible = false


func _draw() -> void:
	for arrow: Array in _arrows:
		var turned := PackedVector2Array()
		for point in _shape:
			turned.append(point.rotated(float(arrow[0])))
		_carve(turned)


## Šipka doprava: kulatá prohlubeň u paty, dřík a hrot.
func _arrow_shape() -> PackedVector2Array:
	var socket := PackedVector2Array()
	for i in CIRCLE_POINTS:
		socket.append(Vector2(SOCKET_AT, 0.0) + Vector2.from_angle(TAU * float(i) / float(CIRCLE_POINTS)) * SOCKET_RADIUS)
	var arrow := PackedVector2Array([
		Vector2(SOCKET_AT, -SHAFT_WIDTH * 0.5),
		Vector2(NECK_AT, -SHAFT_WIDTH * 0.5),
		Vector2(NECK_AT, -HEAD_WIDTH * 0.5),
		Vector2(TIP_AT, 0.0),
		Vector2(NECK_AT, HEAD_WIDTH * 0.5),
		Vector2(NECK_AT, SHAFT_WIDTH * 0.5),
		Vector2(SOCKET_AT, SHAFT_WIDTH * 0.5),
	])
	var merged := Geometry2D.merge_polygons(socket, arrow)
	return merged[0] if not merged.is_empty() else socket


## Vytesání: tmavší dno a po obvodu stěna. Stěna má jas podle toho, jestli se dívá ke světlu.
func _carve(points: PackedVector2Array) -> void:
	var count := points.size()
	var normals := PackedVector2Array()
	for i in count:
		var along := (points[(i + 1) % count] - points[i]).normalized()
		normals.append(Vector2(along.y, -along.x))
	# Normála hrany má mířit ven ze šipky. Podle pořadí bodů může vyjít opačně, pak se otočí všechny.
	var middle := (points[0] + points[1]) * 0.5
	if Geometry2D.is_point_in_polygon(middle + normals[0] * 0.5, points):
		for i in count:
			normals[i] = -normals[i]
	# Vnitřní obrys stěny: každý bod posunutý dovnitř o WALL podél průměru sousedních normál.
	var inner := PackedVector2Array()
	for i in count:
		var before := normals[(i + count - 1) % count]
		var after := normals[i]
		var bend := maxf(1.0 + before.dot(after), 0.3)
		inner.append(points[i] - (before + after) * WALL / bend)
	draw_colored_polygon(points, _stone(FLOOR_DARK))
	for i in count:
		var next := (i + 1) % count
		# Stěna na straně ke světlu se dívá od něj, je ve stínu. Protější svítí.
		var lit := clampf(-normals[i].dot(LIGHT) * 0.5 + 0.5, 0.0, 1.0)
		var wall := _stone(lerpf(WALL_SHADOW, WALL_LIGHT, lit))
		draw_colored_polygon(PackedVector2Array([points[i], points[next], inner[next], inner[i]]), wall)


## Kámen kotliny ztmavený nebo zesvětlený tolikrát. Alfa zůstává plná.
static func _stone(tone: float) -> Color:
	return Color(STONE.r * tone, STONE.g * tone, STONE.b * tone)
