extends Control

## Obrázek ovladače místo jeho jména: šipky nebo WASD se Shiftem (skok) vedle nich, nebo gamepad.
## Velikost určuje strana jedné klávesy v pixelech.

const CAP := Color(0.227, 0.212, 0.192)
const EDGE := Color(0.431, 0.404, 0.361)
const INK := Color(0.95, 0.93, 0.88)
## Mezera mezi klávesami a zaoblení rohů, v podílu strany klávesy.
const GAP := 0.1
const ROUND := 0.18
## Shift vlevo od kláves, svisle uprostřed, a mezera mezi ním a klávesami. V klávesách.
const SHIFT_WIDTH := 1.6
const SHIFT_GAP := 0.3
## Velikost obrázku v klávesách. Nejvyšší je gamepad, MAX_HEIGHT drží řádky se všemi stejně vysoké.
const KEYS_SIZE := Vector2(SHIFT_WIDTH + SHIFT_GAP + 3.0, 2.0)
const PAD_SIZE := Vector2(3.6, 2.2)
const MAX_HEIGHT := 2.2

var device := 0
var key := 20.0


func setup(for_device: int, key_px: float) -> Control:
	device = for_device
	key = key_px
	custom_minimum_size = _size_in_keys() * key
	queue_redraw()
	return self


func _size_in_keys() -> Vector2:
	if device == Controls.ARROWS or device == Controls.WASD:
		return KEYS_SIZE
	return PAD_SIZE


func _draw() -> void:
	# Výřez je uprostřed vlastního obdélníku, kontejner ho může roztáhnout.
	draw_set_transform((size - custom_minimum_size) * 0.5)
	var keys := SHIFT_WIDTH + SHIFT_GAP
	if device == Controls.ARROWS:
		_shift(Rect2(0.0, 0.5, SHIFT_WIDTH, 1.0))
		_arrow_key(Vector2(keys + 1.0, 0.0), 0.0)
		_arrow_key(Vector2(keys, 1.0), -PI * 0.5)
		_arrow_key(Vector2(keys + 1.0, 1.0), PI)
		_arrow_key(Vector2(keys + 2.0, 1.0), PI * 0.5)
	elif device == Controls.WASD:
		_shift(Rect2(0.0, 0.5, SHIFT_WIDTH, 1.0))
		_letter_key(Vector2(keys + 1.0, 0.0), "W")
		_letter_key(Vector2(keys, 1.0), "A")
		_letter_key(Vector2(keys + 1.0, 1.0), "S")
		_letter_key(Vector2(keys + 2.0, 1.0), "D")
	else:
		_pad(device - Controls.FIRST_PAD + 1)


## Klávesa v jednotkách kláves. Vrátí její obdélník v pixelech.
func _cap(units: Rect2) -> Rect2:
	var rect := Rect2(units.position * key, units.size * key).grow(-GAP * key * 0.5)
	var box := StyleBoxFlat.new()
	box.bg_color = CAP
	box.border_color = EDGE
	box.set_border_width_all(maxi(int(key * 0.08), 1))
	box.set_corner_radius_all(int(key * ROUND))
	draw_style_box(box, rect)
	return rect


func _letter_key(at: Vector2, letter: String) -> void:
	_text(_cap(Rect2(at, Vector2.ONE)).get_center(), letter, INK)


## Trojúhelník šipky. angle 0 míří nahoru.
func _arrow_key(at: Vector2, angle: float) -> void:
	var center := _cap(Rect2(at, Vector2.ONE)).get_center()
	var tip := key * 0.2
	var points := PackedVector2Array()
	for corner: Vector2 in [Vector2(0.0, -1.0), Vector2(0.9, 0.65), Vector2(-0.9, 0.65)]:
		points.append(center + corner.rotated(angle) * tip)
	draw_colored_polygon(points, INK)


## Shift se značkou ⇧: obrys šipky nahoru, jako bývá na klávesnici.
func _shift(units: Rect2) -> void:
	var center := _cap(units).get_center()
	var s := key * 0.24
	var outline := PackedVector2Array()
	for p: Vector2 in [
		Vector2(0.0, -1.0), Vector2(0.9, 0.05), Vector2(0.42, 0.05), Vector2(0.42, 0.9),
		Vector2(-0.42, 0.9), Vector2(-0.42, 0.05), Vector2(-0.9, 0.05), Vector2(0.0, -1.0),
	]:
		outline.append(center + p * s)
	draw_polyline(outline, INK, maxf(key * 0.07, 1.0), true)


## Gamepad shora: tělo s rukojetěmi, křížový ovladač, dvě páčky a čtyři tlačítka. Uprostřed je
## číslo gamepadu.
func _pad(number: int) -> void:
	var body := _pad_body()
	draw_colored_polygon(body, CAP)
	var closed := body.duplicate()
	closed.append(body[0])
	draw_polyline(closed, EDGE, maxf(key * 0.08, 1.0), true)
	# Křížový ovladač.
	var dpad := Vector2(0.95, 0.85) * key
	var arm := key * 0.3
	var width := key * 0.17
	draw_rect(Rect2(dpad - Vector2(arm, width * 0.5), Vector2(arm * 2.0, width)), INK)
	draw_rect(Rect2(dpad - Vector2(width * 0.5, arm), Vector2(width, arm * 2.0)), INK)
	# Páčky.
	for stick: Vector2 in [Vector2(1.5, 1.35), Vector2(2.1, 1.35)]:
		draw_arc(stick * key, key * 0.19, 0.0, TAU, 24, INK, maxf(key * 0.06, 1.0), true)
	# Tlačítka v kosočtverci, A dole.
	var face := Vector2(2.65, 0.85) * key
	var spread := key * 0.29
	var radius := key * 0.13
	for offset: Vector2 in [Vector2(0.0, -1.0), Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)]:
		draw_circle(face + offset * spread, radius, INK)
	_text(Vector2(1.8, 0.62) * key, str(number), INK, 0.45)


## Obrys těla gamepadu: zaoblený obdélník a dvě kulaté rukojeti spojené do jednoho mnohoúhelníku.
func _pad_body() -> PackedVector2Array:
	var shape := _rounded_rect(Rect2(Vector2(0.25, 0.25), Vector2(3.1, 1.15)), 0.5)
	for grip: Vector2 in [Vector2(0.85, 1.5), Vector2(2.75, 1.5)]:
		var merged := Geometry2D.merge_polygons(shape, _circle(grip, 0.62))
		if not merged.is_empty():
			shape = merged[0]
	var out := PackedVector2Array()
	for p in shape:
		out.append(p * key)
	return out


func _rounded_rect(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(rect.size.x - radius, radius), -PI * 0.5],
		[rect.end - Vector2(radius, radius), 0.0],
		[rect.position + Vector2(radius, rect.size.y - radius), PI * 0.5],
		[rect.position + Vector2(radius, radius), PI],
	]
	for corner: Array in corners:
		for i in 7:
			points.append((corner[0] as Vector2) + Vector2.from_angle(float(corner[1]) + PI * 0.5 * i / 6.0) * radius)
	return points


func _circle(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 24:
		points.append(center + Vector2.from_angle(TAU * i / 24.0) * radius)
	return points


func _text(center: Vector2, text: String, color: Color, height: float = 0.5) -> void:
	var font := get_theme_default_font()
	var font_size := maxi(int(key * height), 8)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(center.x - width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
