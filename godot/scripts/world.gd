extends Node2D

## Scéna hry. Svět ze čtverců staví a řídí WorldBoard, tady je jen terén prvního čtverce,
## kamera, nápisy a pauza.

const TerrainChunks := preload("res://scripts/terrain_chunks.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const Person := preload("res://scripts/person.gd")
const Hud := preload("res://scripts/hud.gd")
const Party := preload("res://scripts/party.gd")
const WorldBoard := preload("res://scripts/world_board.gd")

## Terén po chuncích předpečených z corner_map katalogu, voda se vlní nad nimi.
@onready var ground: TerrainChunks = $Ground
@onready var camera: MapCamera = $Camera
@onready var status: Label = $Hint/Hud/Status
## Snímky za sekundu vpravo dole. Engine je přepočítává jednou za sekundu.
@onready var fps: Label = $Hint/Hud/Fps

## Svět je hotový a hraje se. Nastaví WorldBoard.
var _map_ready := false
var _hud: Hud
var _persons: Array[Person] = []
var _party: Party
var _board: WorldBoard
var _fps_shown := -1.0


func _ready() -> void:
	# Kamera na skupinu hráčů až po tom, co se postavy v tomhle snímku pohnuly.
	process_priority = 10
	# Při nižším rozlišení světa se svět kreslí zmenšeně, HUD zůstane ostrý.
	Graphics.attach_world(self)
	Sound.settings_changed.connect(_on_sound_settings)
	await get_tree().process_frame
	_board = WorldBoard.new()
	_board.name = "Board"
	add_child(_board)
	_board.start(self)


func _process(delta: float) -> void:
	# Engine počítá snímky jednou za sekundu. Nový text jen při změně, ať se popisek nepřepočítává.
	var rate := Engine.get_frames_per_second()
	if rate != _fps_shown:
		_fps_shown = rate
		fps.text = "%d FPS" % rate
	if _party != null:
		_party.frame()
	if _board != null:
		_board.tick(delta)


func _to_menu() -> void:
	_close_pause()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn" if GameSession.free_roam else "res://scenes/suit_menu.tscn")


func _to_main_menu() -> void:
	_close_pause()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _open_pause() -> void:
	if _hud == null or _hud.pause_open() or _hud.result_open():
		return
	get_tree().paused = true
	Controls.set_menu_cursor(true)
	_hud.open_pause()


func _close_pause() -> void:
	if _hud != null:
		_hud.close_pause()
	get_tree().paused = false
	Controls.set_menu_cursor(false)


func _exit_tree() -> void:
	get_tree().paused = false
	Graphics.attach_world(null)
	Sound.stop_ambient()
	if _board != null:
		_board.shutdown()


## Hudba nebo zvuky se přepnuly (M, N, LB, RB). Hláška řekne, jak jsou teď. V pauze to říkají tlačítka.
func _on_sound_settings() -> void:
	if _hud == null or _hud.pause_open():
		return
	var music := "zapnutá" if Sound.music_on() else "vypnutá"
	var sounds := "zapnuté" if Sound.sounds_on() else "vypnuté"
	_hud.show_notice("Hudba %s · zvuky %s" % [music, sounds], 2.5)


## Esc nebo Start otevře pauzu. Zavření si řeší samo menu, tohle běží jen když se hraje.
func _unhandled_input(event: InputEvent) -> void:
	if not _map_ready or _hud == null or not event.is_action_pressed("game_menu"):
		return
	if _hud.pause_open() or _hud.result_open():
		return
	get_viewport().set_input_as_handled()
	_open_pause()
