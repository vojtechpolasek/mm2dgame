extends Control

## Mapa v levém horním rohu: objevený svět kolem středu kamery, sever nahoře, dlaždice je
## jeden pixel obrazovky. Objevené je to, co bylo někdy v záběru kamery bez jeho rohů
## (zaoblené o REVEAL_ROUND kratší strany), zbytek je tmavý.
## Obrázek čtverce (chart, pixel na dlaždici) se počítá ve vlákně tvorby čtverce, okno
## ho jen ukáže přes masku objevených dlaždic. Továrny, sklady a hráči jsou značky navrch.
## Obrázek zůstane, i když se čtverec uvolní, objevené místo z mapy nezmizí.

const MapData := preload("res://scripts/map_data.gd")
const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")

## Zaoblení rohů mapy v pixelech rozhraní.
const CORNER := 6
## Záběr kamery odkrývá mapu bez rohů: zaoblení je tento podíl kratší strany záběru.
const REVEAL_ROUND := 0.4
## Maska objevených dlaždic se do textury přenáší nejvýš jednou za tolik sekund.
const FLUSH := 0.1
const UNSEEN := Color(0.05, 0.05, 0.06, 0.9)
## Barvy obrázku čtverce. Les dlaždici ztmaví, za každý strom o TREE_SHADE, nejvýš TREE_MAX.
const ROAD := Color(0.78, 0.7, 0.54)
const HOUSE := Color(0.54, 0.35, 0.24)
const FACTORY := Color(0.72, 0.69, 0.63)
const STORE := Color(0.63, 0.54, 0.38)
const TREE_SHADE := 0.18
const TREE_MAX := 0.5
## Značky navrch: továrna, sklad a hráč.
const FACTORY_MARK := Color(0.95, 0.75, 0.3)
const STORE_MARK := Color(0.86, 0.66, 0.3)
const OUTLINE := Color(0.08, 0.06, 0.05)
const MASK_SHADER := """
shader_type canvas_item;
uniform sampler2D mask : filter_nearest;
void fragment() {
	COLOR = texture(TEXTURE, UV);
	COLOR.a *= texture(mask, UV).r;
}
"""

var _camera: Camera2D
var _persons: Array = []
var _colors: Array[Color] = []
## Objevené dlaždice čtverců: souřadnice -> PackedByteArray side * side, 255 objevená.
## Patří světu (ukládá se), mapa do něj jen zapisuje.
var _seen := {}
var _side := 128
var _tile := float(TerrainCatalog.TILE_SIZE)
var _shader: Shader
## Ukázané čtverce: souřadnice -> {node, origin, mask (Image), texture (ImageTexture), dirty}.
var _views := {}
## Značky čtverců: souřadnice -> Array dvojic [poloha ve světě, továrna (true) / sklad].
var _marks := {}
var _canvas: Control
var _overlay: Control
var _last_rect := Rect2i()
var _flush_left := 0.0
var _center := Vector2.ZERO
## Pixely rozhraní na dlaždici: jeden pixel obrazovky podle zvětšení rozhraní.
var _tile_px := 1.0
var _back: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Obsah se ořízne podle zaobleného podkladu.
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_back = StyleBoxFlat.new()
	_back.bg_color = UNSEEN
	_back.set_corner_radius_all(CORNER)
	_back.anti_aliasing = true
	_shader = Shader.new()
	_shader.code = MASK_SHADER
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## seen je slovník objevených dlaždic ze světa (viz _seen), persons postavy hráčů.
func setup(camera: Camera2D, persons: Array, seen: Dictionary, side: int) -> void:
	_camera = camera
	_persons = persons
	_seen = seen
	_side = side
	_colors.clear()
	for person: Node in persons:
		var player: Dictionary = GameSession.player_colors(int(person.get("player_index")))
		_colors.append(Color.html(str(player.get("shirt", "E8E2D2"))))


## Hotový čtverec: jeho obrázek a značky (továrna, sklady) ve světě.
func add_square(coord: Vector2i, origin: Vector2, chart: Image, marks: Array) -> void:
	if chart == null or _views.has(coord):
		return
	var bytes: PackedByteArray = _seen.get(coord, PackedByteArray())
	if bytes.size() != _side * _side:
		bytes = PackedByteArray()
		bytes.resize(_side * _side)
		_seen[coord] = bytes
	var mask := Image.create_from_data(_side, _side, false, Image.FORMAT_L8, bytes)
	var mask_texture := ImageTexture.create_from_image(mask)
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("mask", mask_texture)
	var node := TextureRect.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.texture = ImageTexture.create_from_image(chart)
	node.material = material
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	_canvas.add_child(node)
	_views[coord] = {"node": node, "origin": origin, "mask": mask, "texture": mask_texture, "dirty": false}
	_marks[coord] = marks
	# Co bylo v záběru dřív, než čtverec vznikl, se dopočítá při příštím pohybu.
	_last_rect = Rect2i()


func _process(delta: float) -> void:
	if _camera == null:
		return
	_center = _camera.get_screen_center_position()
	var view := _camera.get_viewport_rect().size / _camera.zoom
	var start := ((_center - view * 0.5) / _tile).floor()
	var end := ((_center + view * 0.5) / _tile).floor()
	var rect := Rect2i(Vector2i(start), Vector2i(end - start) + Vector2i.ONE)
	if rect != _last_rect:
		var area := Rect2((_center - view * 0.5) / _tile, view / _tile)
		_reveal(rect, area, minf(area.size.x, area.size.y) * REVEAL_ROUND)
		_last_rect = rect
	_flush_left -= delta
	if _flush_left <= 0.0:
		_flush_left = FLUSH
		_flush()
	# Posun po celých pixelech obrazovky, ať se dlaždice nechvějí ani nerozmazávají.
	var screen := get_viewport().get_final_transform().get_scale().x
	_tile_px = 1.0 / maxf(screen, 0.01)
	# Vrstva čtverců je v dlaždicích, čtverce stojí na celých číslech. Sousední tak mají
	# společný okraj přesně na stejném místě a mezi nimi nevznikne mezera.
	_canvas.scale = Vector2.ONE * _tile_px
	var window := Rect2(Vector2.ZERO, size / _tile_px)
	var square := Vector2.ONE * float(_side)
	var middle := (size * 0.5 / _tile_px).floor()
	for coord: Vector2i in _views:
		var view_info: Dictionary = _views[coord]
		var node: Control = view_info["node"]
		var at := middle + (((view_info["origin"] as Vector2) - _center) / _tile).round()
		node.visible = window.intersects(Rect2(at, square))
		if node.visible:
			node.position = at
			node.size = square
	_overlay.queue_redraw()


## Dlaždice v rect (souřadnice dlaždic světa) jsou objevené, kromě rohů: střed dlaždice
## musí ležet v area (záběr v dlaždicích) zaobleném o bend.
func _reveal(rect: Rect2i, area: Rect2, bend: float) -> void:
	var core := area.grow(-bend)
	for coord: Vector2i in _views:
		var view_info: Dictionary = _views[coord]
		var first := Vector2i(roundi((view_info["origin"] as Vector2).x / _tile), roundi((view_info["origin"] as Vector2).y / _tile))
		var part := rect.intersection(Rect2i(first, Vector2i(_side, _side)))
		if part.size.x <= 0 or part.size.y <= 0:
			continue
		var bytes: PackedByteArray = _seen[coord]
		var changed := false
		for y in range(part.position.y - first.y, part.end.y - first.y):
			var row := y * _side
			var cy := float(first.y + y) + 0.5
			var dy := maxf(maxf(core.position.y - cy, cy - core.end.y), 0.0)
			for x in range(part.position.x - first.x, part.end.x - first.x):
				if bytes[row + x] != 0:
					continue
				var cx := float(first.x + x) + 0.5
				var dx := maxf(maxf(core.position.x - cx, cx - core.end.x), 0.0)
				if dx * dx + dy * dy > bend * bend:
					continue
				bytes[row + x] = 255
				changed = true
		if changed:
			_seen[coord] = bytes
			view_info["dirty"] = true


func _flush() -> void:
	for coord: Vector2i in _views:
		var view_info: Dictionary = _views[coord]
		if not view_info["dirty"]:
			continue
		view_info["dirty"] = false
		var mask: Image = view_info["mask"]
		mask.set_data(_side, _side, false, Image.FORMAT_L8, _seen[coord])
		(view_info["texture"] as ImageTexture).update(mask)


func _draw() -> void:
	draw_style_box(_back, Rect2(Vector2.ZERO, size))


func _draw_overlay() -> void:
	if _camera == null:
		return
	for coord: Vector2i in _marks:
		for mark: Array in _marks[coord]:
			var pos: Vector2 = mark[0]
			if not _is_seen(coord, pos):
				continue
			var at := _to_map(pos)
			if mark[1]:
				_square_mark(at, 4.0, FACTORY_MARK)
			else:
				_square_mark(at, 2.5, STORE_MARK)
	for i in _persons.size():
		var person: Node2D = _persons[i]
		if not is_instance_valid(person):
			continue
		var at := _to_map(person.position)
		_overlay.draw_circle(at, 3.2, OUTLINE)
		_overlay.draw_circle(at, 2.2, _colors[i] if i < _colors.size() else Color.WHITE)


func _square_mark(at: Vector2, half: float, color: Color) -> void:
	_overlay.draw_rect(Rect2(at - Vector2.ONE * (half + 1.0), Vector2.ONE * (half + 1.0) * 2.0), OUTLINE)
	_overlay.draw_rect(Rect2(at - Vector2.ONE * half, Vector2.ONE * half * 2.0), color)


func _to_map(world: Vector2) -> Vector2:
	return _middle() + (world - _center) / _tile * _tile_px


## Střed okna na celém pixelu obrazovky.
func _middle() -> Vector2:
	return (size * 0.5 / _tile_px).floor() * _tile_px


func _is_seen(coord: Vector2i, world: Vector2) -> bool:
	var view_info: Dictionary = _views.get(coord, {})
	if view_info.is_empty():
		return false
	var local := ((world - (view_info["origin"] as Vector2)) / _tile).floor()
	if local.x < 0 or local.y < 0 or local.x >= _side or local.y >= _side:
		return false
	return (_seen[coord] as PackedByteArray)[int(local.y) * _side + int(local.x)] != 0


## Obrázek čtverce, pixel na dlaždici: terén (mírně zrnitý), les ho ztmaví, řeka, cesta,
## domy, továrna, sklady a skály. Volá se ve vlákně tvorby čtverce, polohy jsou bez posunu.
static func chart(map: MapData, rocks: Node, forest: Node, town: Node, river: RefCounted) -> Image:
	var side := map.size
	var tile := float(TerrainCatalog.TILE_SIZE)
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var base: Array[Color] = []
	for id in map.names.size():
		base.append(Color.html(str(map.info_of(id).get("base", "808080"))))
	var water := map.names.find("water")
	var water_color := base[water] if water >= 0 else Color(0.17, 0.43, 0.54)
	var trees := PackedByteArray()
	trees.resize(side * side)
	for pos: Vector2 in forest.spot_positions():
		var x := int(pos.x / tile)
		var y := int(pos.y / tile)
		if x >= 0 and y >= 0 and x < side and y < side:
			trees[y * side + x] = mini(trees[y * side + x] + 1, 250)
	var has_river: bool = river != null and river.exists()
	var has_town: bool = town != null and town.center() != Vector2.INF
	for y in side:
		for x in side:
			var cell := y * side + x
			var id := map.terrain[cell]
			var color := base[id] if id < base.size() else Color.GRAY
			var grain := 0.95 + 0.1 * float(absi(hash(Vector2i(x, y))) % 1000) / 1000.0
			color = Color(color.r * grain, color.g * grain, color.b * grain)
			if trees[cell] > 0:
				color = color.darkened(minf(TREE_SHADE * trees[cell], TREE_MAX))
			var center := Vector2(x + 0.5, y + 0.5) * tile
			if has_river and river.water_at(center):
				color = water_color
			elif has_town:
				if town.touches_factory(center, 0.0):
					color = FACTORY
				elif town.store_bay(center, 0.0) >= 0:
					color = STORE
				elif town.building_near(center, 0.0):
					color = HOUSE
				elif town.on_road(center):
					color = ROAD
			image.set_pixel(x, y, color)
	rocks.paint_chart(image)
	return image
