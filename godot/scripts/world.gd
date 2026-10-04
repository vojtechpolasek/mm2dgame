extends Node2D

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapGenerator := preload("res://scripts/map_generator.gd")

@onready var ground: TileMapLayer = $Ground
@onready var camera = $Camera
@onready var status: Label = $Hint/Hud/Status


func _ready() -> void:
	await get_tree().process_frame
	var catalog = TerrainCatalog.new()
	catalog.load_assets()
	if catalog.names.is_empty():
		status.text = "Chybí terén."
		push_error("Ve složce terénu nejsou žádné povrchy.")
		return
	var size := maxi(GameSession.map_size, 2)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var grown: Dictionary = MapGenerator.grow(size, catalog.names, rng)
	ground.tile_set = catalog.tile_set
	MapGenerator.paint(ground, catalog, size, grown["terrain"], grown["cost"], rng)
	var pixels := float(size * TerrainCatalog.TILE_SIZE)
	camera.setup(Vector2(pixels, pixels))
	status.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
