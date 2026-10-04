extends Node

## Parametry právě zakládané hry. Další volby z menu nové hry patří sem.
var map_size: int = 64


func _ready() -> void:
	_bind_key("move_left", KEY_LEFT)
	_bind_key("move_right", KEY_RIGHT)
	_bind_key("move_up", KEY_UP)
	_bind_key("move_down", KEY_DOWN)


func _bind_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == key:
			return
	var key_event := InputEventKey.new()
	key_event.physical_keycode = key
	InputMap.action_add_event(action, key_event)
