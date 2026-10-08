extends Control

## Výběr hráčů. Na začátku je jedno prázdné místo. Šipka nahoru na kterémkoli nepřipojeném
## ovladači (šipky, WASD, gamepady) ho obsadí a objeví se další prázdné místo, až do šesti hráčů.
## Připojený hráč svým ovladačem vybírá řádek (nahoru, dolů) a barvu (doleva, doprava),
## podržením skoku se odpojí. Enter nebo Start na gamepadu spustí hru, Esc nebo B vrátí zpět.

const PersonPreview := preload("res://scripts/person_preview.gd")

## Jak dlouho podržet skok, než se hráč odpojí, v sekundách.
const LEAVE_HOLD := 1.0
const PREVIEW_SCALE := 1.8
const SWATCH := 18.0
const TEXT := Color(0.95, 0.93, 0.88)
const DIM := Color(0.95, 0.93, 0.88, 0.55)
const ACCENT := Color(0.86, 0.66, 0.3)

@onready var _slots: GridContainer = $Center/Column/Slots

## U každého hráče vybraný řádek a jak dlouho drží skok.
var _rows := PackedInt32Array()
var _holds := PackedFloat32Array()
## Prvky karet podle hráče: náhled, popisky řádků a čtverečky barev.
var _previews: Array[PersonPreview] = []
var _row_labels: Array = []
var _swatches: Array = []


func _ready() -> void:
	Sound.play_menu_music()
	GameSession.players.clear()
	$Center/Column/Buttons/Back.pressed.connect(_back)
	$Center/Column/Buttons/Start.pressed.connect(_start)
	_rebuild()


func _process(delta: float) -> void:
	for device in Controls.COUNT:
		var slot := _slot_of(device)
		if slot < 0:
			if Controls.pressed(device, "up") and GameSession.players.size() < GameSession.MAX_PLAYERS:
				_join(device)
			continue
		if Controls.jump_held(device):
			_holds[slot] += delta
			if _holds[slot] >= LEAVE_HOLD:
				_leave(slot)
				return
		else:
			_holds[slot] = 0.0
		var parts := GameSession.PARTS.size()
		if Controls.pressed(device, "up"):
			_rows[slot] = (_rows[slot] + parts - 1) % parts
			_refresh(slot)
			Sound.ui("move")
		if Controls.pressed(device, "down"):
			_rows[slot] = (_rows[slot] + 1) % parts
			_refresh(slot)
			Sound.ui("move")
		if Controls.pressed(device, "left"):
			_shift_color(slot, -1)
		if Controls.pressed(device, "right"):
			_shift_color(slot, 1)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var button := event as InputEventJoypadButton
	# Vstup se označí za zpracovaný dřív, než se změní scéna, potom už menu ve stromu není.
	if key != null and key.pressed and not key.echo and (key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		_start()
	elif button != null and button.pressed and button.button_index == JOY_BUTTON_START:
		get_viewport().set_input_as_handled()
		_start()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()


func _slot_of(device: int) -> int:
	for i in GameSession.players.size():
		if int(GameSession.players[i].get("device", -1)) == device:
			return i
	return -1


func _join(device: int) -> void:
	var player := GameSession.free_outfit()
	player["device"] = device
	GameSession.players.append(player)
	_rows.append(1)
	_holds.append(0.0)
	_rebuild()
	Sound.ui("join")


func _leave(slot: int) -> void:
	GameSession.players.remove_at(slot)
	_rows.remove_at(slot)
	_holds.remove_at(slot)
	_rebuild()
	Sound.ui("leave")


func _shift_color(slot: int, step: int) -> void:
	var part := GameSession.PARTS[_rows[slot]]
	var listed: Array = GameSession.SWATCHES[part]
	var at := listed.find(str(GameSession.players[slot].get(part, "")))
	# Triko je shora nejvíc vidět. Barvu, kterou už má jiný hráč, přeskočí.
	for _try in listed.size():
		at = posmod(at + step, listed.size()) if at >= 0 else 0
		if part != "shirt" or not _shirt_taken(str(listed[at]), slot):
			break
	GameSession.players[slot][part] = str(listed[at])
	_previews[slot].apply(GameSession.players[slot])
	_refresh(slot)
	Sound.ui("move")


func _shirt_taken(hex: String, slot: int) -> bool:
	for i in GameSession.players.size():
		if i != slot and str(GameSession.players[i].get("shirt", "")) == hex:
			return true
	return false


func _start() -> void:
	if GameSession.players.is_empty():
		return
	Sound.ui("start")
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _back() -> void:
	Sound.ui("back")
	get_tree().change_scene_to_file("res://scenes/new_game_menu.tscn")


# --- Karty ---

func _rebuild() -> void:
	for child in _slots.get_children():
		child.queue_free()
	_previews.clear()
	_row_labels.clear()
	_swatches.clear()
	for i in GameSession.players.size():
		_slots.add_child(_player_card(i))
		# Náhled se postaví v _ready, až je karta ve stromu. Teprve pak jde zvětšit a obarvit.
		var preview := _previews[i]
		preview.scale = Vector2.ONE * PREVIEW_SCALE
		preview.position = (preview.get_parent() as Control).custom_minimum_size * 0.5 + Vector2(0.0, 6.0)
		preview.apply(GameSession.players[i])
		_refresh(i)
	if GameSession.players.size() < GameSession.MAX_PLAYERS:
		_slots.add_child(_empty_card())
	$Center/Column/Buttons/Start.disabled = GameSession.players.is_empty()


func _player_card(slot: int) -> PanelContainer:
	var player: Dictionary = GameSession.players[slot]
	var card := _card()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var title := _label("Hráč %d · %s" % [slot + 1, Controls.device_name(int(player["device"]))], 18, TEXT)
	column.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	var host := Control.new()
	host.custom_minimum_size = Vector2(110, 150)
	row.add_child(host)
	var preview := PersonPreview.new()
	host.add_child(preview)
	_previews.append(preview)
	var parts := VBoxContainer.new()
	parts.add_theme_constant_override("separation", 4)
	row.add_child(parts)
	var labels: Array[Label] = []
	var boxes: Array = []
	for part: String in GameSession.PARTS:
		var name_label := _label(str(GameSession.PART_TITLES.get(part, part)), 15, DIM)
		parts.add_child(name_label)
		labels.append(name_label)
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 3)
		parts.add_child(strip)
		var part_boxes: Array[Panel] = []
		for hex: Variant in GameSession.SWATCHES[part]:
			var box := Panel.new()
			box.custom_minimum_size = Vector2(SWATCH, SWATCH)
			box.set_meta("hex", str(hex))
			strip.add_child(box)
			part_boxes.append(box)
		boxes.append(part_boxes)
	_row_labels.append(labels)
	_swatches.append(boxes)
	return card


func _empty_card() -> PanelContainer:
	var card := _card()
	var label := _label("Stiskni ↑\npro připojení\n\nšipky · WASD · gamepad", 20, DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(label)
	return card


## Zvýrazní vybraný řádek a vybrané barvy hráče.
func _refresh(slot: int) -> void:
	if slot >= _row_labels.size():
		return
	var player: Dictionary = GameSession.players[slot]
	for p in GameSession.PARTS.size():
		var part := GameSession.PARTS[p]
		var label: Label = _row_labels[slot][p]
		var on_row := p == _rows[slot]
		label.text = ("▶ " if on_row else "") + str(GameSession.PART_TITLES.get(part, part))
		label.add_theme_color_override("font_color", ACCENT if on_row else DIM)
		for box: Panel in _swatches[slot][p]:
			var hex := str(box.get_meta("hex"))
			box.add_theme_stylebox_override("panel", _swatch_box(Color.html(hex), hex == str(player.get(part, ""))))


func _card() -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 214)
	return card


func _swatch_box(color: Color, on: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(2)
	box.set_border_width_all(3 if on else 1)
	if on:
		box.border_color = Color(0.12, 0.1, 0.08) if color.get_luminance() > 0.72 else Color(0.96, 0.93, 0.86)
	else:
		box.border_color = Color(0, 0, 0, 0.3)
	return box


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
