extends VBoxContainer

## Softwarová klávesnice pro zadání jména ovladačem (bez fyzické klávesnice).
## Velká písmena, čísla, mezera, mazání a potvrzení. Fyzická klávesnice funguje stejně.

signal submitted(text: String)

## Řádky písmen a číslic. Poslední řádek je kratší, tlačítka jdou zleva.
const ROWS: Array[PackedStringArray] = [
	["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
	["K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"],
	["U", "V", "W", "X", "Y", "Z"],
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
]
const KEY := Vector2(34, 36)
const WIDE_KEY := Vector2(156, 40)
const PLACEHOLDER := "Jméno"
const TEXT := Color(0.95, 0.93, 0.88)
const DIM := Color(0.95, 0.93, 0.88, 0.55)

var _display: Label
var _text := ""
var _max_length := 32
var _done := false
var _first_key: Button
var _confirm: Button


## initial je předvyplněné jméno, confirm_caption text tlačítka potvrzení (Uložit, …).
func setup(initial: String, confirm_caption: String, max_length: int = 32) -> Control:
	_max_length = max_length
	_text = initial.substr(0, _max_length)
	add_theme_constant_override("separation", 6)
	_display = Label.new()
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_display.custom_minimum_size = Vector2(0, 40)
	_display.add_theme_font_size_override("font_size", 22)
	add_child(_display)
	_paint()
	for row in ROWS:
		add_child(_key_row(row))
	add_child(_action_row())
	_confirm = Button.new()
	_confirm.text = confirm_caption
	_confirm.custom_minimum_size = Vector2(0, 48)
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.pressed.connect(_submit)
	add_child(_confirm)
	return self


## Fokus na první písmeno, ať jde hned psát gamepadem.
func focus_start() -> void:
	if _first_key != null:
		_first_key.grab_focus()


func text() -> String:
	return _text


func _key_row(chars: PackedStringArray) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	for ch in chars:
		var button := _key(ch, KEY)
		button.pressed.connect(_append.bind(ch))
		row.add_child(button)
		if _first_key == null:
			_first_key = button
	return row


func _action_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var space := _key("Mezera", WIDE_KEY)
	space.pressed.connect(_append.bind(" "))
	row.add_child(space)
	var erase := _key("Smazat", WIDE_KEY)
	erase.pressed.connect(_erase)
	row.add_child(erase)
	return row


func _key(caption: String, size: Vector2) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = size
	button.add_theme_font_size_override("font_size", 18)
	return button


func _append(ch: String) -> void:
	if _done or _text.length() >= _max_length:
		return
	_text += ch
	_paint()
	Sound.ui("move")


func _erase() -> void:
	if _done or _text.is_empty():
		return
	_text = _text.substr(0, _text.length() - 1)
	_paint()
	Sound.ui("move")


func _submit() -> void:
	if _done:
		return
	_done = true
	_confirm.disabled = true
	submitted.emit(_text)


func _paint() -> void:
	if _text.is_empty():
		_display.text = PLACEHOLDER
		_display.add_theme_color_override("font_color", DIM)
	else:
		_display.text = _text
		_display.add_theme_color_override("font_color", TEXT)


## Fyzická klávesnice: písmena, čísla, mezera a Backspace. Potvrzení jen tlačítkem
## (šipkami na něj a A / klik), žádná zkratka Enter. Bere se v _input, ať mezera
## neaktivuje právě fokusované tlačítko klávesnice.
func _input(event: InputEvent) -> void:
	if _done or not is_visible_in_tree():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not is_ancestor_of(focus):
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_BACKSPACE:
		_erase()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_SPACE:
		_append(" ")
		get_viewport().set_input_as_handled()
		return
	var ch := String.chr(key.unicode).to_upper()
	if ch.length() == 1 and ((ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")):
		_append(ch)
		get_viewport().set_input_as_handled()
