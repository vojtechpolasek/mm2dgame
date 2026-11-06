extends Control

## Nastavení: hudba a zvuky zvlášť, rozlišení, třpyt kamenů, stíny, stíny břehů a FPS. Hudba a zvuky se ve hře přepínají
## i klávesami (Controls), tady se tlačítka drží podle Sound a Graphics. Stav přepínače
## ukazuje kámen v tlačítku (zelený zapnuto, červený vypnuto), rozlišení číslo místo kamene.
## Stejná scéna je i v pauze hry (in_game): tam je uprostřed, běží při pozastavené hře,
## nepouští hudbu menu a Zpět jen pošle closed. Grafika se mění hned, i za hry.

const ButtonGem := preload("res://scripts/button_gem.gd")

signal closed

## Nastavení v pauze hry. Nastaví se před přidáním do stromu.
var in_game := false

@onready var music: Button = $Center/Panel/Column/Music
@onready var sounds: Button = $Center/Panel/Column/Sounds
@onready var resolution: Button = $Center/Panel/Column/Resolution
@onready var sparkle: Button = $Center/Panel/Column/Sparkle
@onready var shadows: Button = $Center/Panel/Column/Shadows
@onready var bank_shadows: Button = $Center/Panel/Column/BankShadows
@onready var fps: Button = $Center/Panel/Column/Fps


func _ready() -> void:
	if in_game:
		process_mode = Node.PROCESS_MODE_ALWAYS
		visible = false
		var panel := $Center/Panel as Control
		panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		Sound.play_menu_music()
	music.pressed.connect(func() -> void: Sound.set_music_on(not Sound.music_on()))
	sounds.pressed.connect(func() -> void: Sound.set_sounds_on(not Sound.sounds_on()))
	resolution.pressed.connect(func() -> void: Graphics.set_world_scale(Graphics.next_world_scale(Graphics.world_scale())))
	sparkle.pressed.connect(func() -> void: Graphics.set_sparkle(not Graphics.sparkle_on()))
	shadows.pressed.connect(func() -> void: Graphics.set_shadows(not Graphics.shadows_on()))
	bank_shadows.pressed.connect(func() -> void: Graphics.set_bank_shadows(not Graphics.bank_shadows_on()))
	fps.pressed.connect(func() -> void: Graphics.set_fps(not Graphics.fps_on()))
	$Center/Panel/Column/Back.pressed.connect(_back)
	ButtonGem.add($Center/Panel/Column/Back, ButtonGem.BACK)
	Sound.settings_changed.connect(_label)
	Graphics.changed.connect(_label)
	_label()
	if not in_game:
		music.grab_focus()


## Ukáže nastavení v pauze hry.
func open() -> void:
	_label()
	visible = true
	music.grab_focus()


func _label() -> void:
	ButtonGem.set_on(music, Sound.music_on())
	ButtonGem.set_on(sounds, Sound.sounds_on())
	ButtonGem.set_value(resolution, "%d %%" % roundi(Graphics.world_scale() * 100.0))
	ButtonGem.set_on(sparkle, Graphics.sparkle_on())
	ButtonGem.set_on(shadows, Graphics.shadows_on())
	ButtonGem.set_on(bank_shadows, Graphics.bank_shadows_on())
	ButtonGem.set_on(fps, Graphics.fps_on())


func _back() -> void:
	Sound.ui("back")
	if in_game:
		visible = false
		closed.emit()
		return
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## Ve hře zavírá i Esc nebo Start (game_menu), jako pauzu. Nastavení je v pauze až za
## jejím panelem, takže vstup dostane dřív a pauza už ne.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or (in_game and event.is_action_pressed("game_menu")):
		get_viewport().set_input_as_handled()
		_back()
