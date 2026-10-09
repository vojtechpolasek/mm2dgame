extends Control

## Výběr typu hry. Každý typ má pevná pravidla (GameSession.MODES) a vlastní postup levely.
## Předvybraný je vždy první. Pod seznamem je popis typu, na kterém stojí výběr. Potvrzení
## pokračuje na výběr levelu, Esc nebo B vrací do hlavního menu.

const ROW_SIZE := Vector2(440, 56)

@onready var _list: VBoxContainer = $Center/Panel/Column/List
@onready var _about: Label = $Center/Panel/Column/About


func _ready() -> void:
	Sound.play_menu_music()
	for i in GameSession.MODES.size():
		var button := Button.new()
		button.text = str(GameSession.MODES[i]["title"])
		button.custom_minimum_size = ROW_SIZE
		button.pressed.connect(_choose.bind(i))
		button.focus_entered.connect(_describe.bind(i))
		_list.add_child(button)
	$Center/Panel/Column/Back.pressed.connect(_back)
	$Center/Panel/Column/Back.focus_entered.connect(_describe.bind(-1))
	(_list.get_child(0) as Button).grab_focus()


func _describe(index: int) -> void:
	_about.text = str(GameSession.MODES[index]["about"]) if index >= 0 else ""


func _choose(index: int) -> void:
	GameSession.mode = index
	get_tree().change_scene_to_file("res://scenes/new_game_menu.tscn")


func _back() -> void:
	Sound.ui("back")
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()
