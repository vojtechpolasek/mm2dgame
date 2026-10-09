extends Control

## Údaje hry v horních rozích a okno s výsledkem levelu. Sám nic nepočítá, svět mu říká, co ukázat.
## Vlevo co nese každý hráč (ruka v barvě jeho trika), uprostřed zbývající čas (bez limitu
## uběhlý), vpravo level a postup k cíli: body nebo donesené kameny. Okno výsledku
## běží i v pauze, zbytek stojí se hrou.

const Crystal := preload("res://scripts/crystal.gd")
const THEME := preload("res://themes/menu.tres")

## Šipka ke kotlině drží od kraje obrazovky tolik pixelů. Nahoře víc, jsou tam panely.
const ARROW_EDGE := 44.0
const ARROW_TOP := 120.0
## Pod tolik sekund zčervená čas.
const HURRY := 10.0
const EDGE := 20.0
const GEM_SCALE := 2.2
const TEXT := Color(0.95, 0.93, 0.88)
const DIM := Color(0.95, 0.93, 0.88, 0.55)
const ACCENT := Color(0.86, 0.66, 0.3)
const HURRY_COLOR := Color(0.94, 0.4, 0.32)
## Jednotka postupu vpravo nahoře podle cíle typu hry.
const UNITS := {"points": "bodů", "ponds": "kamenů"}

signal retry_pressed
signal menu_pressed
signal next_pressed

var _crystal: Crystal
var _held_rows: GridContainer
## Podle hráče: kámen, kroužek a body neseného kamene.
var _gems: Array[Sprite2D] = []
var _slots: Array[GemSlot] = []
var _held_points: Array[Label] = []
var _held_names: Array[Label] = []
## Víc hráčů než tolik: víceslovný název kamene se zkrátí (Lávový k.), ať je panel úzký.
const SHORT_NAMES_FROM := 4
var _level: Label
var _score: Label
var _unit: Label
var _bar: ProgressBar
var _time: Label
## Rekord levelu pod stopkami, jen bez limitu a když rekord je.
var _record: Label
var _timed := true
var _target := 1
var _shown_seconds := -1
var _arrow: BasinArrow
var _notice: PanelContainer
var _notice_text: Label
var _notice_left := 0.0
var _result: Control
var _result_title: Label
var _result_note: Label
var _result_buttons: VBoxContainer


func _ready() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_held()
	_build_time()
	_build_score()
	_arrow = BasinArrow.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.visible = false
	add_child(_arrow)
	_build_notice()
	_build_result()


## players jsou záznamy z GameSession.players. Každý dostane řádek s rukou v barvě trika.
## goal je cíl typu hry (points, ponds), target kolik ho je potřeba. timed říká, jestli čas
## odpočítává limit.
func setup(crystal: Crystal, level: int, goal: String, target: int, timed: bool, players: Array[Dictionary]) -> void:
	_crystal = crystal
	_timed = timed
	# Po třech vedle sebe, ať panel zůstane nízký a postavy pod ním jsou vidět.
	_held_rows.columns = clampi(players.size(), 1, 3)
	for player: Dictionary in players:
		_add_held_row(Color.html(str(player.get("shirt", "E8E2D2"))))
	_target = maxi(target, 1)
	_level.text = "Level %d" % level
	_unit.text = str(UNITS.get(goal, ""))
	_bar.max_value = _target
	set_progress(0)
	for i in _gems.size():
		set_held(-1, i)


## mat je číslo materiálu, -1 prázdná ruka. player je pořadí hráče.
func set_held(mat: int, player: int = 0) -> void:
	if player < 0 or player >= _gems.size():
		return
	_slots[player].queue_redraw()
	if mat < 0 or _crystal == null or _crystal.count() == 0:
		_gems[player].visible = false
		_held_points[player].text = ""
		_held_names[player].text = ""
		return
	_crystal.paint(_gems[player], mat, 0.0, 0.0)
	_gems[player].visible = true
	_held_points[player].text = "+%d" % _crystal.points_of(mat)
	_held_names[player].text = _short(_crystal.title_of(mat)) if _gems.size() >= SHORT_NAMES_FROM else _crystal.title_of(mat)
	_pop(_held_points[player])


## Postup k cíli: body, nebo počet donesených kamenů.
func set_progress(done: int) -> void:
	_score.text = "%d / %d" % [done, _target]
	_bar.value = mini(done, _target)
	if done > 0:
		_pop(_score)


## S limitem zbývající čas, bez limitu uběhlý.
func set_time(seconds: float) -> void:
	var whole := maxi(ceili(seconds) if _timed else floori(seconds), 0)
	if whole == _shown_seconds:
		return
	_shown_seconds = whole
	_time.text = "%d:%02d" % [whole / 60, whole % 60]
	var hurry := _timed and seconds <= HURRY
	_time.add_theme_color_override("font_color", HURRY_COLOR if hurry else TEXT)
	if hurry and whole > 0:
		_pop(_time)


## Šipka na kraji obrazovky na spojnici postava (from) – kotlina (to), obojí v souřadnicích
## obrazovky. Když je střed kotliny vidět, šipka zmizí.
func point_basin(from: Vector2, to: Vector2) -> void:
	var view := Rect2(Vector2.ZERO, size)
	if to == Vector2.INF or view.has_point(to) or from.distance_squared_to(to) < 1.0:
		_arrow.visible = false
		return
	var inner := Rect2(Vector2(ARROW_EDGE, ARROW_TOP), size - Vector2(ARROW_EDGE * 2.0, ARROW_TOP + ARROW_EDGE))
	var start := Vector2(clampf(from.x, inner.position.x, inner.end.x), clampf(from.y, inner.position.y, inner.end.y))
	var dir := (to - start).normalized()
	var reach := INF
	if dir.x > 0.0001:
		reach = minf(reach, (inner.end.x - start.x) / dir.x)
	elif dir.x < -0.0001:
		reach = minf(reach, (inner.position.x - start.x) / dir.x)
	if dir.y > 0.0001:
		reach = minf(reach, (inner.end.y - start.y) / dir.y)
	elif dir.y < -0.0001:
		reach = minf(reach, (inner.position.y - start.y) / dir.y)
	if reach == INF:
		_arrow.visible = false
		return
	_arrow.position = start + dir * reach
	_arrow.rotation = dir.angle()
	_arrow.visible = true


## note je řádek pod nadpisem, skládá ho svět podle typu hry. last je poslední level hry,
## po jeho splnění už další level není. replay nabídne i po výhře hrát level znovu (o rekord).
func show_result(won: bool, note: String, last: bool, replay: bool) -> void:
	for child in _result_buttons.get_children():
		child.queue_free()
	_result_title.text = "Výborně" if won else "Nesplnil jsi cíl"
	_result_note.text = note
	if won and last:
		_result_button("Návrat do menu", menu_pressed).grab_focus()
		if replay:
			_result_button("Hrát znovu", retry_pressed)
	elif won:
		_result_button("Další level", next_pressed).grab_focus()
		if replay:
			_result_button("Hrát znovu", retry_pressed)
		_result_button("Návrat do menu", menu_pressed)
	else:
		_result_button("Hrát znovu", retry_pressed).grab_focus()
		_result_button("Návrat do menu", menu_pressed)
	_arrow.visible = false
	hide_notice()
	_result.visible = true


# --- Stavba ---

func _build_held() -> void:
	var panel := _corner_panel(Control.PRESET_TOP_LEFT, Control.GROW_DIRECTION_END)
	_held_rows = GridContainer.new()
	_held_rows.add_theme_constant_override("h_separation", 14)
	_held_rows.add_theme_constant_override("v_separation", 2)
	panel.add_child(_held_rows)


## Řádek hráče: ruka v barvě trika, kroužek s neseným kamenem a jeho body.
func _add_held_row(shirt: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_held_rows.add_child(row)
	var hand := HandIcon.new()
	hand.custom_minimum_size = Vector2(30, 34)
	hand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hand.modulate = shirt.lightened(0.15)
	row.add_child(hand)
	var slot := GemSlot.new()
	slot.custom_minimum_size = Vector2(44, 44)
	row.add_child(slot)
	var gem: Sprite2D
	if _crystal != null and _crystal.count() > 0:
		gem = _crystal.make_sprite()
	else:
		gem = Sprite2D.new()
	gem.position = slot.custom_minimum_size * 0.5
	gem.scale = Vector2(GEM_SCALE, GEM_SCALE) * 0.9
	gem.visible = false
	slot.add_child(gem)
	slot.gem = gem
	# Body a pod nimi malým písmem název kamene.
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -6)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var points := _label(22, ACCENT)
	points.custom_minimum_size = Vector2(44, 0)
	text.add_child(points)
	var name := _label(13, DIM)
	text.add_child(name)
	_gems.append(gem)
	_slots.append(slot)
	_held_points.append(points)
	_held_names.append(name)


## Víceslovný název zkrátí na první slovo a počáteční písmeno druhého: Lávový kámen → Lávový k.
static func _short(title: String) -> String:
	var words := title.split(" ", false)
	if words.size() < 2:
		return title
	return "%s %s." % [words[0], words[1].left(1)]


func _build_time() -> void:
	var panel := _corner_panel(Control.PRESET_CENTER_TOP, Control.GROW_DIRECTION_BOTH)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -4)
	panel.add_child(column)
	var caption := _label(14, DIM)
	caption.text = "ČAS"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption)
	_time = _label(34, TEXT)
	_time.custom_minimum_size = Vector2(110, 0)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_time)
	_record = _label(14, DIM)
	_record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_record.visible = false
	column.add_child(_record)


## Rekord levelu pro tolik hráčů, kolik jich hraje. Záporný (rekord není) řádek skryje.
func show_record(seconds: float) -> void:
	_record.visible = seconds >= 0.0
	if _record.visible:
		_record.text = "rekord %s" % GameSession.clock(seconds)


func _build_score() -> void:
	var panel := _corner_panel(Control.PRESET_TOP_RIGHT, Control.GROW_DIRECTION_BEGIN)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	_level = _label(16, DIM)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_level)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	_score = _label(28, TEXT)
	row.add_child(_score)
	_unit = _label(16, DIM)
	_unit.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_unit)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(190, 6)
	_bar.add_theme_stylebox_override("background", _flat(Color(0, 0, 0, 0.45)))
	_bar.add_theme_stylebox_override("fill", _flat(ACCENT))
	column.add_child(_bar)


## Hláška uprostřed dole, zmizí sama po seconds sekundách.
func show_notice(text: String, seconds: float) -> void:
	_notice_text.text = text
	_notice.visible = true
	_notice_left = seconds


func hide_notice() -> void:
	_notice.visible = false
	_notice_left = 0.0


func _process(delta: float) -> void:
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice.visible = false


func _build_notice() -> void:
	_notice = PanelContainer.new()
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.092, 0.082, 0.85)
	box.border_color = ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(2)
	box.content_margin_left = 20.0
	box.content_margin_right = 20.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	_notice.add_theme_stylebox_override("panel", box)
	_notice_text = _label(20, TEXT)
	_notice_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_child(_notice_text)
	_notice.visible = false
	add_child(_notice)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 90)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _build_result() -> void:
	_result = Control.new()
	_result.process_mode = Node.PROCESS_MODE_ALWAYS
	_result.visible = false
	add_child(_result)
	_result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	_result.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_result.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	_result_title = _label(40, TEXT)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_title)
	_result_note = _label(18, DIM)
	_result_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_note)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	column.add_child(gap)
	_result_buttons = VBoxContainer.new()
	_result_buttons.add_theme_constant_override("separation", 12)
	column.add_child(_result_buttons)


func _result_button(text: String, chosen: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 52)
	button.pressed.connect(func() -> void: chosen.emit())
	_result_buttons.add_child(button)
	return button


## Ostrůvek ukotvený k horní hraně. Roste od kotvy, ať při delším textu nevyjede z obrazovky.
func _corner_panel(preset: Control.LayoutPreset, grow: Control.GrowDirection) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.092, 0.082, 0.78)
	box.border_color = Color(0.431, 0.404, 0.361, 0.85)
	box.set_border_width_all(2)
	box.set_corner_radius_all(2)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 10.0
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, int(EDGE))
	panel.grow_horizontal = grow
	return panel


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(1)
	return box


## Krátké poskočení, když se údaj změní.
func _pop(control: Control) -> void:
	control.pivot_offset = control.size * 0.5
	var tween := control.create_tween()
	control.scale = Vector2(1.18, 1.18)
	tween.tween_property(control, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Šipka ke kotlině. Hrot míří po ose x, uzel natáčí HUD. Jemně pulzuje ve směru hrotu.
class BasinArrow:
	extends Control

	const LENGTH := 30.0
	const WIDTH := 26.0
	const PULSE := 5.0

	var _time := 0.0

	func _process(delta: float) -> void:
		if not visible:
			return
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var shift := sin(_time * 5.0) * PULSE
		var tip := Vector2(LENGTH * 0.5 + shift, 0.0)
		var back := Vector2(-LENGTH * 0.5 + shift, 0.0)
		var points := PackedVector2Array([tip, back + Vector2(0.0, -WIDTH * 0.5), back + Vector2(LENGTH * 0.25, 0.0), back + Vector2(0.0, WIDTH * 0.5)])
		var outline := PackedVector2Array(points)
		outline.append(points[0])
		draw_colored_polygon(points, Color(0.86, 0.66, 0.3, 0.95))
		draw_polyline(outline, Color(0.1, 0.092, 0.082, 0.9), 3.0, true)


## Dlaň s prsty, kreslená. Žádný obrázek není potřeba.
class HandIcon:
	extends Control

	func _draw() -> void:
		var color := Color(0.95, 0.93, 0.88, 0.85)
		var w := size.x
		var h := size.y
		var palm := Rect2(w * 0.16, h * 0.42, w * 0.68, h * 0.5)
		draw_rect(palm, color)
		draw_circle(Vector2(palm.position.x + palm.size.x * 0.5, palm.end.y - 1.0), palm.size.x * 0.5, color)
		var finger := w * 0.15
		var tops := [0.18, 0.06, 0.08, 0.2]
		for i in 4:
			var x := palm.position.x + finger * 0.5 + (palm.size.x - finger) * float(i) / 3.0
			var top := h * float(tops[i]) + finger * 0.5
			draw_line(Vector2(x, palm.position.y + 2.0), Vector2(x, top), color, finger)
			draw_circle(Vector2(x, top), finger * 0.5, color)
		var thumb_from := Vector2(palm.position.x + 2.0, palm.position.y + palm.size.y * 0.55)
		var thumb_to := Vector2(w * 0.02 + finger * 0.5, h * 0.4)
		draw_line(thumb_from, thumb_to, color, finger)
		draw_circle(thumb_to, finger * 0.5, color)


## Kroužek, do kterého se kreslí nesený kámen. Prázdný je jen obrys.
class GemSlot:
	extends Control

	var gem: Sprite2D

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(center, radius, Color(0, 0, 0, 0.35))
		var empty := gem == null or not gem.visible
		draw_arc(center, radius, 0.0, TAU, 40, Color(0.95, 0.93, 0.88, 0.25 if empty else 0.5), 2.0, true)
