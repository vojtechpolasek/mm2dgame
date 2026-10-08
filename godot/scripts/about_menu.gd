extends Control


func _ready() -> void:
	Sound.play_menu_music()
	$Center/Panel/Column/Back.pressed.connect(_back)
	$Center/Panel/Column/Back.grab_focus()


func _back() -> void:
	Sound.ui("back")
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()
