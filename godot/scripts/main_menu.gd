extends Control

const Benchmark := preload("res://scripts/benchmark.gd")

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
	$Center/Panel/Column/FreeRoam.pressed.connect(_on_free_roam)
	$Center/Panel/Column/Settings.pressed.connect(_on_settings)
	$Center/Panel/Column/About.pressed.connect(_on_about)
	$Center/Panel/Column/Quit.pressed.connect(_on_quit)
	hunt.grab_focus()


func _on_play() -> void:
	GameSession.free_roam = false
	GameSession.hunt = false
	get_tree().change_scene_to_file("res://scenes/suit_menu.tscn")


## Volný pohyb: rovnou výběr hráčů, pak pokaždé nový svět bez ukládání.
func _on_free_roam() -> void:
	_roam(false)


## Chytej příšery: volný pohyb s příšerami, časem a body.
func _on_hunt() -> void:
	_roam(true)


func _roam(hunt: bool) -> void:
	GameSession.free_roam = true
	GameSession.hunt = hunt
	GameSession.suit_id = ""
	GameSession.suit_name = ""
	GameSession.suit_resume = {}
	GameSession.suit_outfits = []
	get_tree().change_scene_to_file("res://scenes/character_menu.tscn")


func _on_settings() -> void:
	get_tree().change_scene_to_file("res://scenes/settings_menu.tscn")


func _on_about() -> void:
	get_tree().change_scene_to_file("res://scenes/about_menu.tscn")


func _on_quit() -> void:
	get_tree().quit()
