extends Control

## Menu hry. Hraje se vždy od prvního levelu a hra se ukládá sama (SuitSaves).
## Pokračovat načte naposledy hranou hru, Nová hra se zeptá, kdo hraje, Uložené hry ukážou
## všechny rozehrané hry (jde je načíst i smazat) a Výkony tabulku podle počtu hráčů.
## Rozehranou hru musí dohrát stejný počet hráčů, kolik ji začalo. Esc nebo B vrací zpět.

const SuitSaves := preload("res://scripts/suit_saves.gd")
const LOGO := preload("res://graphics/menu/logo.png")
const MaterialTitle := preload("res://scripts/material_title.gd")

## Stejná šířka, výška tlačítek a logo jako v hlavním menu, ať přechod z něj neskáče.
const WIDE := 420.0
const ROW_SIZE := Vector2(WIDE, 56)
const LOGO_SIZE := Vector2(420, 157)
## Výkonů se ukáže nejvýš tolik.
const RESULTS_SHOWN := 10
## Kolik řádků uložených her a výkonů je vidět naráz, další se posunou. S logem nahoře
## by delší seznam vyjel z obrazovky.
const SAVED_VISIBLE := 4
const RESULTS_VISIBLE := 6
const SAVED_ROW := 68.0
const DIM := Color(0.78, 0.74, 0.66)
const ACCENT := Color(0.86, 0.66, 0.3)

@onready var _column: VBoxContainer = $Center/Panel/Column

## Stránka menu: main, name, saved, results. Esc z vnořené stránky vrací na main.
var _page := "main"
var _name_edit: LineEdit
## Výkony pro tolik hráčů.
var _result_players := 1
## Uložená hra, kterou chce hráč smazat. Druhý stisk ji smaže.
var _delete_armed := ""
## Řada tlačítek s počtem hráčů na stránce výkonů.
var _counts: HBoxContainer


func _ready() -> void:
	Sound.play_menu_music()
	_result_players = maxi(GameSession.players.size(), 1)
	_show_main()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	Sound.ui("back")
	if _page == "main":
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	else:
		_show_main()


# --- Stránky ---

func _show_main() -> void:
	_clear("main")
	var last := SuitSaves.last_game()
	var focus: Button
	if not last.is_empty():
		focus = _button("Pokračovat", _resume.bind(last))
		_note(_game_line(last), 15)
	var fresh := _button("Nová hra", _show_name)
	if focus == null:
		focus = fresh
	var saved := _button("Uložené hry", _show_saved)
	saved.disabled = SuitSaves.games().is_empty()
	_button("Výkony", _show_results)
	_button("Zpět", func() -> void:
		Sound.ui("back")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	focus.grab_focus()


## Kdo hraje: jméno se uloží k výkonu. Nabídne se naposledy zadané.
func _show_name() -> void:
	_clear("name")
	_title("Nová hra")
	_note("Kdo hraje? Jméno se zapíše k výkonu.", 16)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = ROW_SIZE
	_name_edit.max_length = 32
	_name_edit.placeholder_text = "Jméno"
	_name_edit.text = SuitSaves.last_name()
	_name_edit.text_submitted.connect(func(_text: String) -> void: _start_new())
	_column.add_child(_name_edit)
	_button("Vybrat hráče", _start_new)
	_button("Zpět", _back_main)
	_name_edit.grab_focus()
	_name_edit.caret_column = _name_edit.text.length()


## Rozehrané hry od naposledy hrané. Každou jde načíst, nebo dvěma stisky smazat.
func _show_saved() -> void:
	_clear("saved")
	_delete_armed = ""
	_title("Uložené hry")
	var games := SuitSaves.games()
	if games.is_empty():
		_note("Žádná rozehraná hra není.", 16)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDE, mini(games.size(), SAVED_VISIBLE) * (SAVED_ROW + 8.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(list)
	_column.add_child(scroll)
	var first: Button
	for header in games:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		# Dva řádky: kdo a kam došel, pod tím kdy se naposledy hrálo.
		var open := Button.new()
		open.text = "%s\nNaposledy hráno %s" % [_game_title(header), SuitSaves.date_text(int(header.get("date", 0)))]
		open.custom_minimum_size = Vector2(WIDE - 104.0, SAVED_ROW)
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.add_theme_font_size_override("font_size", 15)
		open.clip_text = true
		open.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		open.pressed.connect(_resume.bind(header))
		row.add_child(open)
		var remove := Button.new()
		remove.text = "Smazat"
		remove.custom_minimum_size = Vector2(96, SAVED_ROW)
		remove.add_theme_font_size_override("font_size", 17)
		remove.pressed.connect(_delete.bind(str(header["id"]), remove))
		row.add_child(remove)
		if first == null:
			first = open
	var back := _button("Zpět", _back_main)
	(first if first != null else back).grab_focus()


## Výkony pro zvolený počet hráčů: nejdřív dohrané hry, pak podle levelu a času.
func _show_results() -> void:
	_clear("results")
	_title("Výkony")
	var counts := HBoxContainer.new()
	_counts = counts
	counts.alignment = BoxContainer.ALIGNMENT_CENTER
	counts.add_theme_constant_override("separation", 6)
	_column.add_child(counts)
	var chosen: Button
	for count in range(1, GameSession.MAX_PLAYERS + 1):
		var pick := Button.new()
		pick.text = str(count)
		pick.custom_minimum_size = Vector2(52, 44)
		pick.toggle_mode = true
		pick.button_pressed = count == _result_players
		pick.pressed.connect(_pick_players.bind(count))
		counts.add_child(pick)
		if count == _result_players:
			chosen = pick
	_note(GameSession.players_text(_result_players), 16)
	var rows := SuitSaves.results(_result_players)
	if rows.is_empty():
		_note("Zatím žádný výkon.", 16)
	else:
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 4)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(WIDE, (mini(rows.size(), RESULTS_VISIBLE) + 1) * 27)
		scroll.add_child(grid)
		_column.add_child(scroll)
		for caption in ["", "Jméno", "Level", "Čas", "Datum"]:
			grid.add_child(_cell(caption, DIM))
		for i in mini(rows.size(), RESULTS_SHOWN):
			var row: Dictionary = rows[i]
			var finished := bool(row["finished"])
			grid.add_child(_cell("%d." % (i + 1), DIM))
			grid.add_child(_cell(_name_of(row), ACCENT if finished else Color.WHITE))
			grid.add_child(_cell("dohráno" if finished else str(row["level"]), ACCENT if finished else Color.WHITE))
			grid.add_child(_cell(GameSession.clock(float(row["time"])), Color.WHITE))
			grid.add_child(_cell(SuitSaves.date_text(int(row["date"])), DIM))
	_button("Zpět", _back_main)
	chosen.grab_focus()


func _pick_players(count: int) -> void:
	_result_players = count
	Sound.ui("move")
	_show_results()
	# Fokus zůstane na zvoleném počtu, ať jde dál listovat šipkami.
	for child in _counts.get_children():
		if (child as Button).text == str(count):
			(child as Button).grab_focus()


# --- Akce ---

func _start_new() -> void:
	var name := _name_edit.text.strip_edges() if _name_edit != null else ""
	if name.is_empty():
		name = "Hráči"
	SuitSaves.remember_name(name)
	GameSession.suit_id = SuitSaves.new_id()
	GameSession.suit_name = name
	GameSession.suit_resume = {}
	GameSession.suit_outfits = []
	Sound.ui("select")
	get_tree().change_scene_to_file("res://scenes/character_menu.tscn")


## Pokračování: načte hru a hráči se připojí. Musí jich být tolik, kolik hru začalo.
func _resume(header: Dictionary) -> void:
	var id := str(header["id"])
	var data := SuitSaves.load_game(id)
	if data.is_empty():
		Sound.ui("back")
		_show_main()
		_note("Hru nejde načíst.", 16)
		return
	GameSession.suit_id = id
	GameSession.suit_name = str(header.get("name", ""))
	GameSession.suit_resume = data
	GameSession.suit_outfits = header.get("players", [])
	Sound.ui("select")
	get_tree().change_scene_to_file("res://scenes/character_menu.tscn")


func _delete(id: String, button: Button) -> void:
	if _delete_armed != id:
		_delete_armed = id
		button.text = "Opravdu?"
		Sound.ui("move")
		return
	SuitSaves.delete_game(id)
	Sound.ui("leave")
	if SuitSaves.games().is_empty():
		_show_main()
	else:
		_show_saved()


func _back_main() -> void:
	Sound.ui("back")
	_show_main()


# --- Stavba ---

## Smaže stránku. Logo nahoře zůstává na každé stránce.
func _clear(page: String) -> void:
	_page = page
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = LOGO_SIZE
	_column.add_child(logo)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	_column.add_child(gap)


func _title(text: String) -> void:
	var label := MaterialTitle.new()
	label.font_size = 36
	label.title = text
	_column.add_child(label)


func _note(text: String, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(WIDE, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", DIM)
	_column.add_child(label)


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = ROW_SIZE
	button.pressed.connect(action)
	_column.add_child(button)
	return button


func _cell(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	return label


## Řádek uložené hry: jméno, level, hráči a kdy se hrálo.
static func _game_line(header: Dictionary) -> String:
	return "%s · %s" % [_game_title(header), SuitSaves.date_text(int(header.get("date", 0)))]


## Jméno, level a hráči uložené hry, bez data.
static func _game_title(header: Dictionary) -> String:
	var players := (header.get("players", []) as Array).size()
	return "%s · level %d · %s" % [_name_of(header), int(header.get("level", 1)), GameSession.players_text(players)]


static func _name_of(row: Dictionary) -> String:
	var name := str(row.get("name", ""))
	return name if not name.is_empty() else "Bez jména"
