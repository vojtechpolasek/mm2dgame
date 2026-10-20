extends Control

## Pauza ve hře. Hudba a zvuky, návrat do hlavního menu a pokračování.
## Běží i když je strom pozastavený. Myš, klávesnice i gamepad.

signal closed
signal main_menu

var _music: Button
var _sounds: Button
var _continue: Button
## Zavření klávesou až od dalšího snímku, ať Esc, kterým se menu otevřelo, hned nezavře.
var _ready_for_close := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.018, 0.015, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(_on_shade)
	add_child(shade)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var title := Label.new()
	title.text = "Menu"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	column.add_child(gap)
	_continue = _button("Pokračovat", _close)
	column.add_child(_continue)
	_music = _button("Hudba: zapnutá", _toggle_music)
	column.add_child(_music)
	_sounds = _button("Zvuky: zapnuté", _toggle_sounds)
	column.add_child(_sounds)
	var leave := _button("Hlavní menu", func() -> void: main_menu.emit())
	column.add_child(leave)
	var hint := Label.new()
	hint.text = "Esc, B nebo Start zavře. M / LB hudba, N / RB zvuky."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(420, 0)
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.78, 0.74, 0.66))
	column.add_child(hint)
	Sound.settings_changed.connect(_label)


func open() -> void:
	_ready_for_close = false
	_label()
	visible = true
	_continue.grab_focus()
	_arm_close.call_deferred()


func _arm_close() -> void:
	if visible:
		_ready_for_close = true


func close() -> void:
	if not visible:
		return
	visible = false
	get_viewport().gui_release_focus()


func _close() -> void:
	closed.emit()


func _toggle_music() -> void:
	Sound.set_music_on(not Sound.music_on())


func _toggle_sounds() -> void:
	Sound.set_sounds_on(not Sound.sounds_on())


func _label() -> void:
	if _music == null:
		return
	_music.text = "Hudba: %s" % ("zapnutá" if Sound.music_on() else "vypnutá")
	_sounds.text = "Zvuky: %s" % ("zapnuté" if Sound.sounds_on() else "vypnuté")


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 52)
	button.pressed.connect(action)
	return button


func _on_shade(event: InputEvent) -> void:
	if not _ready_for_close:
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	Sound.ui("back")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _ready_for_close:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("game_menu"):
		get_viewport().set_input_as_handled()
		Sound.ui("back")
		closed.emit()
