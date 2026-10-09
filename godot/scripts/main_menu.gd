extends Control

const Benchmark := preload("res://scripts/benchmark.gd")

@onready var play: Button = $Center/Panel/Column/Play


func _ready() -> void:
	if Benchmark.requested() and not get_tree().root.has_node("Benchmark"):
		var benchmark := Benchmark.new()
		benchmark.name = "Benchmark"
		get_tree().root.add_child.call_deferred(benchmark)
		return
	Sound.play_menu_music()
	play.pressed.connect(_on_play)
	$Center/Panel/Column/About.pressed.connect(_on_about)
	$Center/Panel/Column/Quit.pressed.connect(_on_quit)
	play.grab_focus()


func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/game_mode_menu.tscn")


func _on_about() -> void:
	get_tree().change_scene_to_file("res://scenes/about_menu.tscn")


func _on_quit() -> void:
	get_tree().quit()
