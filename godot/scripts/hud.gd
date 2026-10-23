extends Control

## Údaje hry v horních rozích a okno na konci hry. Sám nic nepočítá, svět mu říká, co ukázat.
## Vlevo mapa objeveného světa (MiniMap), vždy vidět. Vpravo obzor se sluncem nebo měsícem
## (SkyDial, vždy vidět), level, kolik kamenů je v zásobnících továrny a malým písmem čas hry,
## vedle logo „MM“, tlačítko menu. Pod nimi co nese každý hráč (kroužek v barvě jeho trika).
## Panely mají styl panelů menu. Okno konce hry běží i v pauze, zbytek stojí se hrou.

const Crystal := preload("res://scripts/crystal.gd")
const PauseMenu := preload("res://scripts/pause_menu.gd")
const THEME := preload("res://themes/menu.tres")
const MENU_ICON := preload("res://graphics/menu/logo_mm.png")
const MaterialTitle := preload("res://scripts/material_title.gd")
const MiniMap := preload("res://scripts/minimap.gd")
const DayNight := preload("res://scripts/day_night.gd")
const SuitSaves := preload("res://scripts/suit_saves.gd")

## Šipka k továrně drží od kraje obrazovky tolik pixelů. Nahoře drží ARROW_BELOW pod
## panely v rozích, nejméně ARROW_TOP.
const ARROW_EDGE := 44.0
const ARROW_TOP := 96.0
const ARROW_BELOW := 24.0
## Panel mapy je MAP_SHARE šířky panelu levelu. Než se panel levelu rozměří, počítá se
## s šířkou MAP_WIDTH.
const MAP_WIDTH := 200.0
const MAP_SHARE := 0.8
const MAP_MARGIN := 6.0
## Blikání šipky u kraje čtverce za sekundu, výrazné je rychlejší.
const BLINK_HZ := 2.0
const BLINK_STRONG_HZ := 4.5
const EDGE := 20.0
## Výška horní lišty: panel nesených kamenů, panel postupu i čtvercové tlačítko menu.
const BAR_HEIGHT := 52.0
## Kroužek s neseným kamenem a měřítko kamene v něm.
const SLOT := 38.0
const GEM_SCALE := 1.0
const TEXT := Color(0.95, 0.93, 0.88)
const DIM := Color(0.95, 0.93, 0.88, 0.55)
const ACCENT := Color(0.86, 0.66, 0.3)
## Tabulka výkonů v okně konce ukáže tolik řádků, další se posouvají.
const RECORDS_VISIBLE := 8
## Šířky sloupců tabulky výkonů: pořadí, jméno, body, chyceno, datum.
const RECORD_COLUMNS: Array[float] = [36.0, 220.0, 56.0, 76.0, 190.0]
## Výrazně blikající šipka je červená.
const ALARM_COLOR := Color(0.94, 0.4, 0.32)

signal menu_pressed
## Tlačítko Menu nebo Esc / Start. Otevření pauzy řeší svět.
signal pause_requested
## Pauza se zavřela (Pokračovat, Esc, B, Start nebo klepnutí mimo panel).
signal pause_closed
## Pauza chce zpátky na hlavní menu.
signal main_menu_pressed
## Okno konce Chytej příšery: hrát znovu se stejnými hráči.
signal again_pressed
## Okno konce Chytej příšery: jméno k zápisu výkonu, oříznuté a nikdy prázdné.
signal name_entered(name: String)

var _crystal: Crystal
var _held_rows: GridContainer
## Podle hráče: kámen, kroužek a body neseného kamene.
var _gems: Array[Sprite2D] = []
var _slots: Array[GemSlot] = []
var _held_points: Array[Label] = []
var _held_names: Array[Label] = []
## Posun obrázku kamene na střed jeho viditelné části, podle textury.
var _gem_offsets := {}
## Víc hráčů než tolik: víceslovný název kamene se zkrátí (Lávový k.), ať je panel úzký.
const SHORT_NAMES_FROM := 4
var _level: Label
var _score: Label
var _unit: Label
var _bar: ProgressBar
var _time: Label
var _target := 1
var _shown_seconds := -1
var _arrow: FactoryArrow
var _notice: PanelContainer
var _notice_text: Label
var _notice_left := 0.0
## U kraje čtverce šipka na továrnu bliká: 1 bliká, 2 bliká rychle, větší a červeně.
var _blink := 0
var _blink_age := 0.0
var _result: Control
var _result_title: MaterialTitle
var _result_note: Label
## Mezi řádkem note a tlačítky: pole se jménem nebo tabulka výkonů.
var _result_body: VBoxContainer
var _result_buttons: VBoxContainer
## Panely v horních rozích a nahoře uprostřed. Volný pohyb je skryje.
var _corners: Array[Control] = []
var _menu_button: Button
var _held_panel: PanelContainer
## Pravý horní roh: panel postupu a vedle něj tlačítko menu, pod nimi nesené kameny.
var _right_column: VBoxContainer
var _right: HBoxContainer
var _score_panel: PanelContainer
var _sky: SkyDial
var _map_panel: PanelContainer
var minimap: MiniMap
var _pause: PauseMenu


func _ready() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_right()
	_build_held()
	_build_map()
	_arrow = FactoryArrow.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.visible = false
	add_child(_arrow)
	_build_notice()
	_build_result()
	_build_pause()


## players jsou záznamy z GameSession.players. Každý dostane kroužek v barvě trika.
## Nadpis a cíl vpravo nahoře nastaví set_goal.
func setup(crystal: Crystal, players: Array[Dictionary]) -> void:
	_crystal = crystal
	# Vždy v jedné řadě, ať je panel stejně vysoký jako zbytek lišty. Šest hráčů se vejde
	# i do nejužšího okna (1280), viz GameSession.MAX_PLAYERS.
	_held_rows.columns = clampi(players.size(), 1, GameSession.MAX_PLAYERS)
	for player: Dictionary in players:
		_add_held_row(Color.html(str(player.get("shirt", "E8E2D2"))))
	_unit.text = "kamenů"
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
	_center_gem(_gems[player])
	_gems[player].visible = true
	_held_points[player].text = "+%d" % _crystal.points_of(mat)
	_held_names[player].text = _short(_crystal.title_of(mat)) if _gems.size() >= SHORT_NAMES_FROM else _crystal.title_of(mat)
	_pop(_held_points[player])


## Postup k cíli: kolik kamenů je v zásobnících.
func set_progress(done: int) -> void:
	_score.text = "%d / %d" % [done, _target]
	_bar.value = mini(done, _target)
	if done > 0:
		_pop(_score)


## Den a noc: phase jako DayNight.phase, 0 východ slunce, 0.5 východ měsíce. moon je pořadí
## fáze měsíce v DayNight.MOON_PHASES (0 úplněk, 4 nov).
func set_sky(phase: float, moon: int) -> void:
	_sky.set_phase(phase, moon)


## Uběhlý čas hry.
func set_time(seconds: float) -> void:
	var whole := maxi(floori(seconds), 0)
	if whole == _shown_seconds:
		return
	_shown_seconds = whole
	_time.text = "%d:%02d" % [whole / 60, whole % 60]


## Šipka na kraji obrazovky na spojnici postava (from) – továrna (to), obojí v souřadnicích
## obrazovky. Když je střed továrny vidět, šipka zmizí.
func point_factory(from: Vector2, to: Vector2) -> void:
	var view := Rect2(Vector2.ZERO, size)
	if to == Vector2.INF or view.has_point(to) or from.distance_squared_to(to) < 1.0:
		_arrow.visible = false
		return
	var top := maxf(ARROW_TOP, maxf(_map_panel.get_rect().end.y, _right_column.get_rect().end.y) + ARROW_BELOW)
	var inner := Rect2(Vector2(ARROW_EDGE, top), size - Vector2(ARROW_EDGE * 2.0, top + ARROW_EDGE))
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


## Volný pohyb: bez nesených kamenů, času, levelu a šipky. Zůstanou mapa a hlášky.
func free_roam() -> void:
	for panel in _corners:
		panel.visible = false
	_arrow.visible = false


## Chytej příšery: bez nesených kamenů a šipky. Vpravo nahoře zbývající čas ze seconds
## a body, pruh ukazuje zbývající čas.
func hunt(seconds: float) -> void:
	_held_panel.visible = false
	_arrow.visible = false
	_level.text = "Chytej příšery"
	_unit.text = "bodů"
	_score.text = "0"
	_bar.max_value = seconds
	set_countdown(seconds, seconds)


## Zbývající čas Chytej příšery. Celé sekundy se zaokrouhlují nahoru, 0:00 je až konec.
func set_countdown(left: float, total: float) -> void:
	_bar.max_value = total
	_bar.value = left
	set_time(ceilf(left))


## Body Chytej příšery. caught je počet chycených, ukazují se body.
func set_hunt_score(points: int, _caught: int) -> void:
	_score.text = str(points)
	_pop(_score)


## Okno konce hry: nadpis title, pod ním řádek note a návrat do menu. again přidá
## tlačítko Hrát znovu (again_pressed).
func show_result(title: String, note: String, again := false) -> void:
	_open_result(title, note)
	if again:
		_result_button("Hrát znovu", again_pressed).grab_focus()
		_result_button("Návrat do menu", menu_pressed)
	else:
		_result_button("Návrat do menu", menu_pressed).grab_focus()


## Okno konce Chytej příšery, než se výkon zapíše: pole s předvyplněným jménem name
## a tlačítko Uložit (name_entered).
func ask_name(title: String, note: String, name: String) -> void:
	_open_result(title, note)
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(320, 52)
	edit.max_length = 32
	edit.placeholder_text = "Jméno"
	edit.text = name
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_body.add_child(edit)
	var save := Button.new()
	save.text = "Uložit"
	save.custom_minimum_size = Vector2(320, 52)
	_result_buttons.add_child(save)
	var submit := func(_text: String) -> void:
		if save.disabled:
			return
		save.disabled = true
		var entered := edit.text.strip_edges()
		name_entered.emit(entered if not entered.is_empty() else "Hráči")
	edit.text_submitted.connect(submit)
	save.pressed.connect(submit.bind(""))
	edit.grab_focus()
	edit.caret_column = edit.text.length()


## Okno konce Chytej příšery po zápisu: tabulka výkonů rows (Hunt.records), řádek mark
## (od 0, -1 žádný) je zvýrazněný a posune se do výhledu. Pod ní Hrát znovu a menu.
func show_records(title: String, note: String, rows: Array[Dictionary], mark: int) -> void:
	show_result(title, note, true)
	if rows.is_empty():
		return
	# Záhlaví leží nad posuvnou částí, sloupce obou mřížek drží stejné šířky.
	var head := _records_grid()
	_result_body.add_child(head)
	for caption in ["", "Jméno", "Body", "Chyceno", "Datum"]:
		head.add_child(_record_cell(caption, DIM, head.get_child_count()))
	var grid := _records_grid()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, mini(rows.size(), RECORDS_VISIBLE) * 27)
	scroll.add_child(grid)
	_result_body.add_child(scroll)
	var marked: Control
	for i in rows.size():
		var row := rows[i]
		var color := ACCENT if i == mark else TEXT
		var name := str(row["name"])
		var cells := ["%d." % (i + 1), name if not name.is_empty() else "Bez jména", str(row["points"]),
			str(row["caught"]), SuitSaves.date_text(int(row["date"]))]
		for column in cells.size():
			var dim := column == 0 or column == 4
			var cell := _record_cell(cells[column], color if i == mark or not dim else DIM, column)
			grid.add_child(cell)
			if i == mark and column == 0:
				marked = cell
	if marked != null:
		# Až se tabulka rozměří, ať je zapsaný výkon vidět i dole v delší tabulce.
		_reveal(scroll, marked)


func _reveal(scroll: ScrollContainer, marked: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(marked):
		scroll.ensure_control_visible(marked)


func _open_result(title: String, note: String) -> void:
	for child in _result_buttons.get_children():
		child.queue_free()
	for child in _result_body.get_children():
		child.queue_free()
	_result_title.title = title
	_result_note.text = note
	_menu_button.visible = false
	_arrow.visible = false
	hide_notice()
	_result.visible = true


func _records_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = RECORD_COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	return grid


## Buňka tabulky výkonů ve sloupci column. Dlouhé jméno se zkrátí třemi tečkami.
func _record_cell(text: String, color: Color, column: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	label.custom_minimum_size.x = RECORD_COLUMNS[column]
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


# --- Stavba ---

func _build_held() -> void:
	var panel := _panel()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_right_column.add_child(panel)
	_corners.append(panel)
	_held_panel = panel
	_held_rows = GridContainer.new()
	_held_rows.add_theme_constant_override("h_separation", 14)
	_held_rows.add_theme_constant_override("v_separation", 2)
	_held_rows.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_child(_held_rows)


## Řádek hráče: kroužek v barvě trika s neseným kamenem a jeho body.
func _add_held_row(shirt: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	_held_rows.add_child(row)
	var slot := GemSlot.new()
	slot.custom_minimum_size = Vector2(SLOT, SLOT)
	# Řádek je vyšší než kroužek (dva řádky textu), kroužek se nesmí natáhnout.
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.color = shirt.lightened(0.1)
	row.add_child(slot)
	var gem: Sprite2D
	if _crystal != null and _crystal.count() > 0:
		gem = _crystal.make_sprite()
	else:
		gem = Sprite2D.new()
	gem.position = slot.custom_minimum_size * 0.5
	gem.scale = Vector2(GEM_SCALE, GEM_SCALE)
	gem.visible = false
	slot.add_child(gem)
	slot.gem = gem
	# Body a pod nimi malým písmem název kamene.
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -3)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var points := _label(17, ACCENT)
	points.custom_minimum_size = Vector2(36, 0)
	text.add_child(points)
	# Malé písmo má jen jemný stín, větší by slil spodní části písmen.
	var name := _label(13, Color(0.95, 0.93, 0.88, 0.7))
	name.add_theme_constant_override("shadow_offset_y", 1)
	name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	text.add_child(name)
	_gems.append(gem)
	_slots.append(slot)
	_held_points.append(points)
	_held_names.append(name)


## Kámen na střed kroužku podle jeho viditelné části. Obrázek kamene není v buňce přesně
## uprostřed a kroužek by ho jinak ukázal posunutý.
func _center_gem(gem: Sprite2D) -> void:
	var texture := gem.texture
	if texture == null:
		return
	if not _gem_offsets.has(texture):
		var image := texture.get_image()
		if image == null:
			return
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		_gem_offsets[texture] = Vector2(image.get_size()) * 0.5 - (Vector2(used.position) + Vector2(used.size) * 0.5)
	gem.offset = _gem_offsets[texture]


## Víceslovný název zkrátí na první slovo a počáteční písmeno druhého: Lávový kámen → Lávový k.
static func _short(title: String) -> String:
	var words := title.split(" ", false)
	if words.size() < 2:
		return title
	return "%s %s." % [words[0], words[1].left(1)]


func _build_right() -> void:
	_right_column = VBoxContainer.new()
	_right_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_column.add_theme_constant_override("separation", 10)
	add_child(_right_column)
	_right_column.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(EDGE))
	_right_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_right = HBoxContainer.new()
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_theme_constant_override("separation", 10)
	_right.size_flags_horizontal = Control.SIZE_SHRINK_END
	_right_column.add_child(_right)
	var sky_panel := _panel()
	_sky = SkyDial.new()
	_sky.custom_minimum_size = Vector2(84, BAR_HEIGHT - 10.0)
	_sky.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sky_panel.add_child(_sky)
	_right.add_child(sky_panel)
	_score_panel = _panel()
	_right.add_child(_score_panel)
	_corners.append(_score_panel)
	_build_score(_score_panel)
	_build_menu_button()


## Čtvercová mapa vlevo nahoře, o pětinu užší než panel levelu. Volný pohyb ji neskryje.
func _build_map() -> void:
	_map_panel = PanelContainer.new()
	_map_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_panel.add_theme_stylebox_override("panel", _panel_box(MAP_MARGIN, MAP_MARGIN))
	add_child(_map_panel)
	_map_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, int(EDGE))
	minimap = MiniMap.new()
	minimap.custom_minimum_size = Vector2.ONE * roundf(MAP_WIDTH * MAP_SHARE - MAP_MARGIN * 2.0)
	_map_panel.add_child(minimap)
	_score_panel.resized.connect(_fit_map)


func _fit_map() -> void:
	var width := _score_panel.size.x if _score_panel.size.x > 0.0 else MAP_WIDTH
	minimap.custom_minimum_size = Vector2.ONE * roundf(width * MAP_SHARE - MAP_MARGIN * 2.0)


## Nahoře level a malý čas hry, pod nimi kameny v zásobnících a tenký pruh postupu.
func _build_score(panel: PanelContainer) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -2)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 5)
	column.add_child(top)
	_level = _label(12, DIM)
	_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_level)
	# Čas je vedlejší údaj, jen malým písmem vedle levelu.
	var clock := ClockIcon.new()
	clock.custom_minimum_size = Vector2(11, 11)
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(clock)
	_time = _label(12, DIM)
	_time.text = "0:00"
	top.add_child(_time)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 5)
	column.add_child(row)
	_score = _label(18, TEXT)
	row.add_child(_score)
	_unit = _label(12, DIM)
	_unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_unit)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(170, 3)
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


## Nový cíl: nadpis vpravo nahoře a kolik je potřeba. Postup začne od nuly.
func set_goal(title: String, target: int) -> void:
	_level.text = title
	_target = maxi(target, 1)
	_bar.max_value = _target
	set_progress(0)


## 0 šipka nebliká, 1 bliká, 2 bliká výrazně: rychleji, je větší a červená.
func set_edge_alarm(level: int) -> void:
	_blink = level


func _process(delta: float) -> void:
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice.visible = false
	if _arrow == null:
		return
	if _blink > 0 and _arrow.visible:
		var strong := _blink >= 2
		_blink_age += delta
		var wave := 0.5 + 0.5 * sin(_blink_age * TAU * (BLINK_STRONG_HZ if strong else BLINK_HZ))
		_arrow.modulate = ALARM_COLOR if strong else Color.WHITE
		_arrow.modulate.a = lerpf(0.1 if strong else 0.25, 1.0, wave)
		_arrow.scale = Vector2.ONE * (lerpf(1.2, 1.6, wave) if strong else 1.0)
	else:
		_arrow.modulate = Color.WHITE
		_arrow.scale = Vector2.ONE


func _build_notice() -> void:
	_notice = PanelContainer.new()
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.add_theme_stylebox_override("panel", _panel_box(20.0, 10.0))
	_notice_text = _label(20, TEXT)
	_notice_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_child(_notice_text)
	_notice.visible = false
	add_child(_notice)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 90)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.grow_vertical = Control.GROW_DIRECTION_BEGIN


func pause_open() -> bool:
	return _pause != null and _pause.visible


func result_open() -> bool:
	return _result != null and _result.visible


func open_pause() -> void:
	if result_open() or pause_open():
		return
	_menu_button.visible = false
	_pause.open()


func close_pause() -> void:
	if not pause_open():
		return
	_pause.close()
	_menu_button.visible = not result_open()


func _on_pause_closed() -> void:
	close_pause()
	pause_closed.emit()


## Logo „MM“ jako tlačítko. Rámeček je stejný jako u tlačítek menu, jen s malým okrajem.
func _build_menu_button() -> void:
	_menu_button = Button.new()
	_menu_button.icon = MENU_ICON
	_menu_button.expand_icon = true
	_menu_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_button.tooltip_text = "Menu (Esc)"
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.custom_minimum_size = Vector2(BAR_HEIGHT, BAR_HEIGHT)
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		var box := THEME.get_stylebox(state, &"Button").duplicate() as StyleBoxFlat
		box.content_margin_left = 5.0
		box.content_margin_right = 5.0
		box.content_margin_top = 5.0
		box.content_margin_bottom = 5.0
		_menu_button.add_theme_stylebox_override(state, box)
	_menu_button.pressed.connect(func() -> void: pause_requested.emit())
	_right.add_child(_menu_button)


func _build_pause() -> void:
	_pause = PauseMenu.new()
	_pause.name = "Pause"
	_pause.closed.connect(_on_pause_closed)
	_pause.main_menu.connect(func() -> void: main_menu_pressed.emit())
	add_child(_pause)


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
	_result_title = MaterialTitle.new()
	_result_title.font_size = 40
	column.add_child(_result_title)
	_result_note = _label(18, DIM)
	_result_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_note)
	_result_body = VBoxContainer.new()
	_result_body.add_theme_constant_override("separation", 12)
	column.add_child(_result_body)
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


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_box(14.0, 4.0))
	# Všechny ostrůvky lišty jsou stejně vysoké jako tlačítko menu.
	panel.custom_minimum_size.y = BAR_HEIGHT
	return panel


## Panel menu (zlatý pruh vlevo, tmavé pozadí) s menšími okraji a stínem, ať se do rohu vejde.
func _panel_box(side: float, top: float) -> StyleBoxFlat:
	var box := THEME.get_stylebox(&"panel", &"PanelContainer").duplicate() as StyleBoxFlat
	box.content_margin_left = side
	box.content_margin_right = side
	box.content_margin_top = top
	box.content_margin_bottom = top
	box.set_corner_radius_all(8)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 3)
	return box


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


## Šipka k továrně. Hrot míří po ose x, uzel natáčí HUD. Jemně pulzuje ve směru hrotu.
class FactoryArrow:
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


## Malé hodiny před časem hry.
class ClockIcon:
	extends Control

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 1.0
		var color := Color(0.95, 0.93, 0.88, 0.55)
		draw_arc(center, radius, 0.0, TAU, 24, color, 1.5, true)
		draw_line(center, center + Vector2(0, -radius * 0.65), color, 1.5, true)
		draw_line(center, center + Vector2(radius * 0.5, 0), color, 1.5, true)


## Náčrt obzoru: oblouk, po kterém jde ve dne slunce a v noci měsíc ve své fázi. Vychází
## vpravo, nahoře je poledne (půlnoc), zapadá vlevo a pomalu klesne pod obzor, kde zmizí.
## Kruh je stejný jako v DayNight, střed má o DayNight.HORIZON_DROP poloměru pod obzorem.
class SkyDial:
	extends Control

	const LINE := Color(0.95, 0.93, 0.88, 0.55)
	const PATH := Color(0.95, 0.93, 0.88, 0.22)
	const GROUND := Color(0.95, 0.93, 0.88, 0.08)
	## Slunce a fáze měsíce (tools/gen_sky.py): pruh buněk CELL px, slunce a pak měsíc v pořadí
	## DayNight.MOON_PHASES. Kreslí se ve velikosti DRAWN.
	const SKY := preload("res://graphics/hud/sky.png")
	const CELL := 48.0
	const DRAWN := 22.0

	var _phase := 0.0
	var _moon := 0

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	func set_phase(phase: float, moon: int) -> void:
		# Překreslí se, až se slunce posune aspoň o kus (asi o pixel oblouku) nebo se změní fáze.
		if absf(phase - _phase) < 0.0015 and moon == _moon:
			return
		_phase = phase
		_moon = moon
		queue_redraw()

	func _draw() -> void:
		var horizon := size.y - 6.0
		var drop := DayNight.HORIZON_DROP
		var radius := minf(size.x * 0.5 - 8.0, (horizon - 6.0) / (1.0 - drop))
		var center := Vector2(size.x * 0.5, horizon + radius * drop)
		draw_rect(Rect2(Vector2(2.0, horizon), Vector2(size.x - 4.0, size.y - horizon)), GROUND)
		var rise := asin(drop)
		draw_arc(center, radius, PI + rise, TAU - rise, 40, PATH, 1.5, true)
		draw_line(Vector2(2.0, horizon), Vector2(size.x - 2.0, horizon), LINE, 1.5, true)
		var sun := DayNight.angle_of(_phase)
		_draw_body(center + Vector2(cos(sun), -sin(sun)) * radius, 0, horizon)
		_draw_body(center + Vector2(cos(sun + PI), -sin(sun + PI)) * radius, 1 + _moon, horizon)

	## Slunce nebo měsíc (buňka cell) se středem at, jen část nad obzorem.
	func _draw_body(at: Vector2, cell: int, horizon: float) -> void:
		var top := at.y - DRAWN * 0.5
		var shown := minf(DRAWN, horizon - top)
		if shown <= 0.0:
			return
		var region := Rect2(CELL * float(cell), 0.0, CELL, CELL * shown / DRAWN)
		draw_texture_rect_region(SKY, Rect2(Vector2(at.x - DRAWN * 0.5, top), Vector2(DRAWN, shown)), region)


## Kroužek, do kterého se kreslí nesený kámen. Obrys má barvu trika hráče, prázdný je tlumenější.
class GemSlot:
	extends Control

	const RING := 3.0

	var gem: Sprite2D
	var color := Color.WHITE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and gem != null:
			gem.position = size * 0.5

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - RING * 0.5 - 1.0
		var empty := gem == null or not gem.visible
		draw_circle(center, radius, Color(0, 0, 0, 0.45))
		# Tmavý lem kolem barevného kroužku, ať je vidět i světlé triko.
		draw_arc(center, radius, 0.0, TAU, 48, Color(0, 0, 0, 0.5), RING + 2.0, true)
		var ring := color
		ring.a = 0.55 if empty else 1.0
		draw_arc(center, radius, 0.0, TAU, 48, ring, RING, true)
