extends Node2D

## Krajina pod menu. Stejný svět jako volný pohyb, bez postavy. Kamera jede v WorldBoard.

const TerrainChunks := preload("res://scripts/terrain_chunks.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const WorldBoard := preload("res://scripts/world_board.gd")
const Person := preload("res://scripts/person.gd")

## První čtverec je ve scéně a jde ho ukázat.
signal revealed

var camera: MapCamera
var ground: TerrainChunks
var status: Label
var _persons: Array[Person] = []
var _party: Node = null
var _hud: Node = null
var _map_ready := false
var _board: WorldBoard
var _announced := false


func _ready() -> void:
	# Posun kamery dřív, než si ji kamera v _process zveřejní shaderům.
	process_priority = -1
	ground = TerrainChunks.new()
	ground.name = "Ground"
	add_child(ground)
	camera = MapCamera.new()
	camera.name = "Camera"
	add_child(camera)
	status = Label.new()
	status.name = "Status"
	status.visible = false
	add_child(status)
	_board = WorldBoard.new()
	_board.name = "Board"
	add_child(_board)
	_board.start_flyover(self)


func _process(delta: float) -> void:
	if _board == null:
		return
	_board.tick(delta)
	if _map_ready and not _announced:
		_announced = true
		revealed.emit()


func shutdown() -> void:
	if _board == null:
		return
	var board := _board
	_board = null
	board.shutdown()
	Sound.stop_ambient()
