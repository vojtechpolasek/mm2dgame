extends SceneTree

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapGenerator := preload("res://scripts/map_generator.gd")


func _init() -> void:
	var catalog = TerrainCatalog.new()
	catalog.load_assets()
	print("terrains ", catalog.names)
	if catalog.names.size() < 2:
		push_error("expected terrains")
		quit(1)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var size := 32
	var started := Time.get_ticks_msec()
	var grown: Dictionary = MapGenerator.grow(size, catalog.names, rng)
	var layer := TileMapLayer.new()
	layer.tile_set = catalog.tile_set
	var root_node := Node2D.new()
	root.add_child(root_node)
	root_node.add_child(layer)
	MapGenerator.paint(layer, catalog, size, grown["terrain"], grown["cost"], rng)
	var filled := 0
	var kinds := {}
	for y in size:
		for x in size:
			var index := y * size + x
			var name: String = grown["terrain"][index]
			kinds[name] = int(kinds.get(name, 0)) + 1
			if layer.get_cell_source_id(Vector2i(x, y)) >= 0:
				filled += 1
	print("filled ", filled, "/", size * size, " kinds ", kinds, " ms ", Time.get_ticks_msec() - started)
	rng.seed = 7
	var big := 128
	started = Time.get_ticks_msec()
	var big_grown: Dictionary = MapGenerator.grow(big, catalog.names, rng)
	var big_layer := TileMapLayer.new()
	big_layer.tile_set = catalog.tile_set
	root_node.add_child(big_layer)
	MapGenerator.paint(big_layer, catalog, big, big_grown["terrain"], big_grown["cost"], rng)
	var big_filled := 0
	for y in big:
		for x in big:
			if big_layer.get_cell_source_id(Vector2i(x, y)) >= 0:
				big_filled += 1
	print("big filled ", big_filled, "/", big * big, " ms ", Time.get_ticks_msec() - started)
	if filled != size * size or big_filled != big * big or kinds.size() < 2:
		push_error("map incomplete")
		quit(1)
		return
	call_deferred("_save_preview", layer, size)


func _save_preview(layer: TileMapLayer, size: int) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size * 64, size * 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.transparent_bg = false
	var host := Node2D.new()
	layer.reparent(host)
	viewport.add_child(host)
	root.add_child(viewport)
	for frame in 3:
		await process_frame
	var image := viewport.get_texture().get_image()
	var path := "C:/projects/mm2dgame/tools/preview/generated_map.png"
	var err := image.save_png(path)
	print("preview ", err, " ", image.get_width(), "x", image.get_height(), " ", path)
	quit(0)
