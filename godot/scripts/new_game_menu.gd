extends Control

const MenuStyle := preload("res://scripts/menu_style.gd")


func _ready() -> void:
	MenuStyle.apply(self)
	$Center/Panel/Small.pressed.connect(_start.bind(32))
	$Center/Panel/Medium.pressed.connect(_start.bind(64))
	$Center/Panel/Large.pressed.connect(_start.bind(128))
	$Center/Panel/Back.pressed.connect(_back)
	$Center/Panel/Small.grab_focus()


func _start(size: int) -> void:
	GameSession.map_size = size
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
