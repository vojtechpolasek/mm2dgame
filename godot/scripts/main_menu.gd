extends Control

const MenuStyle := preload("res://scripts/menu_style.gd")

@onready var new_game: Button = $Center/Panel/NewGame


func _ready() -> void:
	MenuStyle.apply(self)
	new_game.pressed.connect(_on_new_game)
	new_game.grab_focus()


func _on_new_game() -> void:
	get_tree().change_scene_to_file("res://scenes/new_game_menu.tscn")
