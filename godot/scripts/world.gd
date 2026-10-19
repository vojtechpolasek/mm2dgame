extends Node2D

## Scéna hry. Svět ze čtverců staví a řídí WorldBoard, tady je jen terén prvního čtverce,
## kamera, nápisy a odchod do menu.

const TerrainChunks := preload("res://scripts/terrain_chunks.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const Person := preload("res://scripts/person.gd")
const Hud := preload("res://scripts/hud.gd")
const Party := preload("res://scripts/party.gd")
const WorldBoard := preload("res://scripts/world_board.gd")

## Odchod do menu chce dva stisky Esc nebo Startu do tolika sekund, ať se neodejde omylem.
const LEAVE_WINDOW := 3.0

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
## Kolik sekund ještě druhý stisk Esc nebo Startu opustí hru. 0 je bez prvního stisku.
var _leave_left := 0.0
var _board: WorldBoard
var _fps_shown := -1.0


func _ready() -> void:
	# Kamera na skupinu hráčů až po tom, co se postavy v tomhle snímku pohnuly.
	process_priority = 10
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
	_leave_left = maxf(_leave_left - delta, 0.0)
	if _party != null:
		_party.frame()
	if _board != null:
		_board.tick(delta)


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn" if GameSession.free_roam else "res://scenes/suit_menu.tscn")


func _exit_tree() -> void:
	get_tree().paused = false
	Sound.stop_ambient()
	if _board != null:
		_board.shutdown()


## Hudba nebo zvuky se přepnuly (M, N, LB, RB). Hláška řekne, jak jsou teď.
func _on_sound_settings() -> void:
	if _hud == null:
		return
	var music := "zapnutá" if Sound.music_on() else "vypnutá"
	var sounds := "zapnuté" if Sound.sounds_on() else "vypnuté"
	_hud.show_notice("Hudba %s · zvuky %s" % [music, sounds], 2.5)


## Esc nebo Start: první stisk ukáže hlášku, druhý do LEAVE_WINDOW sekund odejde do menu.
func _unhandled_input(event: InputEvent) -> void:
	if not _map_ready or not event.is_action_pressed("game_menu"):
		return
	get_viewport().set_input_as_handled()
	if _leave_left > 0.0:
		Sound.ui("back")
		_to_menu()
		return
	_leave_left = LEAVE_WINDOW
	if _hud != null:
		_hud.show_notice("Stiskni znovu Esc / Start pro opuštění hry", LEAVE_WINDOW)
