extends Node

## Ovladače hráčů, oddělené od postav. Postava zná jen číslo ovladače a ptá se tady.
## Každý ovladač má v InputMap vlastní akce c<číslo>_left, _right, _up, _down a _jump, takže
## jdou později přemapovat. Šipky skáčou pravým Shiftem, WASD levým, gamepady tlačítkem A
## a chodí levou páčkou i křížovým ovladačem.
## Menu se ovládá stejně: k ui_* přibude WASD a oba Shifty potvrzují. game_menu (Esc, Start)
## opustí hru.

const ARROWS := 0
const WASD := 1
const FIRST_PAD := 2
const PADS := 4
const COUNT := FIRST_PAD + PADS
## Páčka gamepadu se počítá až od tohoto vychýlení.
const DEADZONE := 0.35
const NAMES: PackedStringArray = ["Šipky", "WASD", "Gamepad 1", "Gamepad 2", "Gamepad 3", "Gamepad 4"]
const DIRECTIONS: PackedStringArray = ["left", "right", "up", "down"]


func _ready() -> void:
	for device in COUNT:
		_bind_device(device)
	_bind_menu()


func action(device: int, what: String) -> StringName:
	return StringName("c%d_%s" % [device, what])


## Směr pohybu, délka nejvýš 1.
func direction(device: int) -> Vector2:
	return Input.get_vector(action(device, "left"), action(device, "right"), action(device, "up"), action(device, "down"))


func jump_pressed(device: int) -> bool:
	return Input.is_action_just_pressed(action(device, "jump"))


func jump_held(device: int) -> bool:
	return Input.is_action_pressed(action(device, "jump"))


## Šipka v daném směru právě stisknutá. what je left, right, up nebo down.
func pressed(device: int, what: String) -> bool:
	return Input.is_action_just_pressed(action(device, what))


func device_name(device: int) -> String:
	return NAMES[device] if device >= 0 and device < NAMES.size() else "?"


func _bind_device(device: int) -> void:
	if device == ARROWS:
		_keys(device, [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN], KEY_LOCATION_RIGHT)
	elif device == WASD:
		_keys(device, [KEY_A, KEY_D, KEY_W, KEY_S], KEY_LOCATION_LEFT)
	else:
		_pad(device, device - FIRST_PAD)


func _keys(device: int, keys: Array, shift_side: KeyLocation) -> void:
	for i in DIRECTIONS.size():
		var event := InputEventKey.new()
		event.physical_keycode = keys[i]
		_add(action(device, DIRECTIONS[i]), event)
	var jump := InputEventKey.new()
	jump.physical_keycode = KEY_SHIFT
	jump.location = shift_side
	_add(action(device, "jump"), jump)


func _pad(device: int, pad: int) -> void:
	var axes := [[JOY_AXIS_LEFT_X, -1.0], [JOY_AXIS_LEFT_X, 1.0], [JOY_AXIS_LEFT_Y, -1.0], [JOY_AXIS_LEFT_Y, 1.0]]
	var buttons := [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]
	for i in DIRECTIONS.size():
		var motion := InputEventJoypadMotion.new()
		motion.device = pad
		motion.axis = axes[i][0]
		motion.axis_value = axes[i][1]
		_add(action(device, DIRECTIONS[i]), motion)
		var button := InputEventJoypadButton.new()
		button.device = pad
		button.button_index = buttons[i]
		_add(action(device, DIRECTIONS[i]), button)
	var jump := InputEventJoypadButton.new()
	jump.device = pad
	jump.button_index = JOY_BUTTON_A
	_add(action(device, "jump"), jump)


## Menu: WASD jako šipky, Shift potvrzuje. U gamepadů se k ui_* přidá páčka i křížový
## ovladač všech zařízení, Godot sám nemusí mít páčku v menu.
func _bind_menu() -> void:
	var wasd := {"ui_left": KEY_A, "ui_right": KEY_D, "ui_up": KEY_W, "ui_down": KEY_S}
	for ui: String in wasd:
		var event := InputEventKey.new()
		event.physical_keycode = wasd[ui]
		_add(StringName(ui), event)
	var pad := {
		"ui_left": [JOY_AXIS_LEFT_X, -1.0, JOY_BUTTON_DPAD_LEFT], "ui_right": [JOY_AXIS_LEFT_X, 1.0, JOY_BUTTON_DPAD_RIGHT],
		"ui_up": [JOY_AXIS_LEFT_Y, -1.0, JOY_BUTTON_DPAD_UP], "ui_down": [JOY_AXIS_LEFT_Y, 1.0, JOY_BUTTON_DPAD_DOWN],
	}
	for ui: String in pad:
		var motion := InputEventJoypadMotion.new()
		motion.device = -1
		motion.axis = pad[ui][0]
		motion.axis_value = pad[ui][1]
		_add(StringName(ui), motion)
		var button := InputEventJoypadButton.new()
		button.device = -1
		button.button_index = pad[ui][2]
		_add(StringName(ui), button)
	var accept := InputEventJoypadButton.new()
	accept.device = -1
	accept.button_index = JOY_BUTTON_A
	_add(&"ui_accept", accept)
	var cancel := InputEventJoypadButton.new()
	cancel.device = -1
	cancel.button_index = JOY_BUTTON_B
	_add(&"ui_cancel", cancel)
	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	_add(&"ui_accept", shift)
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	_add(&"game_menu", escape)
	var start := InputEventJoypadButton.new()
	start.device = -1
	start.button_index = JOY_BUTTON_START
	_add(&"game_menu", start)


func _add(name: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, DEADZONE)
	InputMap.action_add_event(name, event)
