extends Control

## Nastavení: hudba a zvuky zvlášť, rozlišení a třpyt kamenů. Hudba a zvuky se ve hře přepínají
## i klávesami (Controls), tady se popisky tlačítek drží podle Sound a Graphics.

@onready var music: Button = $Center/Panel/Column/Music
@onready var sounds: Button = $Center/Panel/Column/Sounds
@onready var resolution: Button = $Center/Panel/Column/Resolution
@onready var sparkle: Button = $Center/Panel/Column/Sparkle


func _ready() -> void:
	Sound.play_menu_music()
	music.pressed.connect(func() -> void: Sound.set_music_on(not Sound.music_on()))
	sounds.pressed.connect(func() -> void: Sound.set_sounds_on(not Sound.sounds_on()))
	resolution.pressed.connect(func() -> void: Graphics.set_reduced(not Graphics.reduced()))
	sparkle.pressed.connect(func() -> void: Graphics.set_sparkle(not Graphics.sparkle_on()))
	$Center/Panel/Column/Back.pressed.connect(_back)
	Sound.settings_changed.connect(_label)
	Graphics.changed.connect(_label)
	_label()
	music.grab_focus()


func _label() -> void:
	music.text = "Hudba: %s" % ("zapnutá" if Sound.music_on() else "vypnutá")
	sounds.text = "Zvuky: %s" % ("zapnuté" if Sound.sounds_on() else "vypnuté")
	resolution.text = "Rozlišení: %s" % ("úsporné (720p)" if Graphics.reduced() else "plné")
	sparkle.text = "Třpyt kamenů: %s" % ("zapnutý" if Graphics.sparkle_on() else "vypnutý")


func _back() -> void:
	Sound.ui("back")
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()
