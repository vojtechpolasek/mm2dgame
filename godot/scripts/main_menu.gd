extends Control

const Benchmark := preload("res://scripts/benchmark.gd")
const ButtonGem := preload("res://scripts/button_gem.gd")

@onready var hunt: Button = $Center/Panel/Column/Hunt


func _ready() -> void:
	if Benchmark.requested() and not get_tree().root.has_node("Benchmark"):
		var benchmark := Benchmark.new()
		benchmark.name = "Benchmark"
		get_tree().root.add_child.call_deferred(benchmark)
		return
	Sound.play_menu_music()
	hunt.pressed.connect(_on_hunt)
	$Center/Panel/Column/Play.pressed.connect(_on_play)
	$Center/Panel/Column/Evolve.pressed.connect(_on_evolve)
	$Center/Panel/Column/FreeRoam.pressed.connect(_on_free_roam)
	$Center/Panel/Column/Settings.pressed.connect(_on_settings)
	$Center/Panel/Column/About.pressed.connect(_on_about)
	$Center/Panel/Column/Quit.pressed.connect(_on_quit)
	ButtonGem.add(hunt, ButtonGem.HUNT)
	ButtonGem.add($Center/Panel/Column/Play, ButtonGem.COLLECT)
	ButtonGem.add($Center/Panel/Column/Evolve, ButtonGem.EVOLVE)
	ButtonGem.add($Center/Panel/Column/FreeRoam, ButtonGem.ROAM)
	ButtonGem.add($Center/Panel/Column/Settings, ButtonGem.SETTINGS)
	ButtonGem.add($Center/Panel/Column/About, ButtonGem.INFO)
	ButtonGem.add($Center/Panel/Column/Quit, ButtonGem.BACK)
	hunt.grab_focus()


## Sbírání materiálů: kameny hlídané příšerami, čas a body.
func _on_play() -> void:
	_start(GameSession.COLLECT)


## Evoluce: hráč je příšera a mění se, až se stane diamantovým ptakoještěrem. Měří se čas.
func _on_evolve() -> void:
	_start(GameSession.EVOLVE)


## Volný pohyb: rovnou výběr hráčů, pak pokaždé nový svět bez ukládání.
func _on_free_roam() -> void:
	_start(GameSession.ROAM)


## Chytej příšery: příšery utíkají, čas a body.
func _on_hunt() -> void:
	_start(GameSession.HUNT)


## Každý režim začíná výběrem hráčů a novým světem.
func _start(mode: String) -> void:
	GameSession.mode = mode
	get_tree().change_scene_to_file("res://scenes/character_menu.tscn")


func _on_settings() -> void:
	get_tree().change_scene_to_file("res://scenes/settings_menu.tscn")


func _on_about() -> void:
	get_tree().change_scene_to_file("res://scenes/about_menu.tscn")


func _on_quit() -> void:
	get_tree().quit()
