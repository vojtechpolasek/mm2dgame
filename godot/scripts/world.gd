extends Node2D

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapGenerator := preload("res://scripts/map_generator.gd")
const Forest := preload("res://scripts/forest.gd")
const Rocks := preload("res://scripts/rocks.gd")
const PropChunks := preload("res://scripts/prop_chunks.gd")

@onready var ground: TileMapLayer = $Ground
@onready var camera = $Camera
@onready var status: Label = $Hint/Hud/Status

var _map_ready := false


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
	var grown: Dictionary = MapGenerator.grow(size, catalog.names, rng, catalog.max_distance)
	ground.tile_set = catalog.tile_set
	catalog.apply(ground)
	MapGenerator.paint(ground, catalog, size, grown["terrain"], grown["cost"], rng)
	var props := Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true
	add_child(props)
	move_child(props, ground.get_index() + 1)
	var rocks := Rocks.new()
	rocks.name = "Rocks"
	add_child(rocks)
	var forest := Forest.new()
	forest.name = "Trees"
	add_child(forest)
	var pixels := float(size * TerrainCatalog.TILE_SIZE)
	camera.setup(Vector2(pixels, pixels))
	var chunks = PropChunks.new()
	chunks.name = "PropChunks"
	chunks.setup(camera)
	add_child(chunks)
	rocks.plant(grown["terrain"], size, catalog.surfaces, rng, camera, props, chunks)
	forest.plant(grown["terrain"], size, catalog.surfaces, rng, camera, props, chunks, rocks.blockers())
	chunks.refresh()
	status.visible = false
	_map_ready = true


func _unhandled_input(event: InputEvent) -> void:
	if _map_ready and event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
