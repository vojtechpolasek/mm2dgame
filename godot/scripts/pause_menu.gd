extends Control

## Pauza ve hře. Pokračování, nastavení (stejná scéna jako v hlavním menu) a návrat do
## hlavního menu. Běží i když je strom pozastavený. Myš, klávesnice i gamepad.

const LOGO := preload("res://graphics/menu/logo.png")
const ButtonGem := preload("res://scripts/button_gem.gd")
const SETTINGS := preload("res://scenes/settings_menu.tscn")

signal closed
signal main_menu

var _continue: Button
var _settings_button: Button
## Panel pauzy. Při otevřeném nastavení je schovaný.
var _center: CenterContainer
var _settings: Control
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
	_center = CenterContainer.new()
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	var panel := PanelContainer.new()
	_center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	# Místo nadpisu logo hry, stejně jako v hlavním menu.
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(380, 139)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(logo)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	column.add_child(gap)
	_continue = _button("Pokračovat", ButtonGem.GO, _close)
	column.add_child(_continue)
	_settings_button = _button("Nastavení", ButtonGem.SETTINGS, _open_settings)
	column.add_child(_settings_button)
	var leave := _button("Hlavní menu", ButtonGem.BACK, func() -> void: main_menu.emit())
	column.add_child(leave)
	_settings = SETTINGS.instantiate()
	_settings.set(&"in_game", true)
	_settings.connect(&"closed", _settings_closed)
	add_child(_settings)


func open() -> void:
	_ready_for_close = false
	_center.visible = true
	_settings.visible = false
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


func _open_settings() -> void:
	_center.visible = false
	_settings.call(&"open")


func _settings_closed() -> void:
	_center.visible = true
	_settings_button.grab_focus()


## Tlačítko s kamenem role (ButtonGem).
func _button(text: String, role: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 52)
	button.pressed.connect(action)
	ButtonGem.add(button, role)
	return button


func _on_shade(event: InputEvent) -> void:
	if not _ready_for_close or _settings.visible:
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
