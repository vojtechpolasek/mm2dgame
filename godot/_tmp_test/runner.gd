extends Node

func _ready() -> void:
	var level := int(OS.get_cmdline_user_args()[0])
	GameSession.suit_id = ""
	GameSession.suit_outfits = []
	GameSession.suit_resume = {"level": level, "levels": {Vector2i.ZERO: level}}
	GameSession.players.clear()
	GameSession.players.append(GameSession.default_player())
	var probe := Node.new()
	probe.set_script(load("res://_tmp_test/probe.gd"))
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")
