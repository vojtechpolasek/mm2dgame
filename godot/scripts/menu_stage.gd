extends CanvasLayer

## Živá krajina pod obrazovkami menu. Drží se mezi nimi, do hry se schová a uvolní.
## Svět je ve vlastním pohledu, ať kamera neposouvá tlačítka. Než se složí první čtverec,
## zůstane statický obrázek.

const GAME := "res://scenes/world.tscn"
const FALLBACK := preload("res://graphics/menu/background.png")
const Benchmark := preload("res://scripts/benchmark.gd")
const MenuFlyover := preload("res://scripts/menu_flyover.gd")

var _fallback: TextureRect
var _shade: TextureRect
var _view: SubViewportContainer
var _viewport: SubViewport
var _flyover: Node2D


func _ready() -> void:
	# Pod menu. Tlačítka jsou ve scéně na vrstvě 0.
	layer = -1
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_chrome()
	get_tree().node_added.connect(_on_node_added)
	_sync.call_deferred()


func _on_node_added(node: Node) -> void:
	if node == get_tree().current_scene:
		_sync()


func _sync() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if Benchmark.requested() or scene.scene_file_path == GAME:
		_stop()
	else:
		_ensure()


func _ensure() -> void:
	Controls.set_menu_cursor(true)
	visible = true
	if _view != null:
		return
	_fallback.visible = true
	_view = SubViewportContainer.new()
	_view.name = "View"
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.stretch = true
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.visible = false
	add_child(_view)
	move_child(_view, _shade.get_index())
	_viewport = SubViewport.new()
	_viewport.name = "World"
	_viewport.gui_disable_input = true
	_viewport.handle_input_locally = false
	_viewport.disable_3d = true
	_viewport.audio_listener_enable_2d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = Vector2i(1280, 720)
	_view.add_child(_viewport)
	_view.resized.connect(_fit)
	_fit.call_deferred()
	var flyover: MenuFlyover = MenuFlyover.new()
	flyover.name = "Flyover"
	flyover.revealed.connect(_on_revealed)
	_viewport.add_child(flyover)
	_flyover = flyover


func _on_revealed() -> void:
	if _view != null:
		_view.visible = true
	if _fallback != null:
		_fallback.visible = false


func _fit() -> void:
	if _view == null or _viewport == null:
		return
	var size := Vector2i(_view.size)
	if size.x < 2 or size.y < 2:
		return
	if _viewport.size != size:
		_viewport.size = size


func _stop() -> void:
	Controls.set_menu_cursor(false)
	visible = false
	if _fallback != null:
		_fallback.visible = true
	if _flyover != null:
		var flyover := _flyover
		_flyover = null
		flyover.call("shutdown")
	if _view != null:
		var view := _view
		_view = null
		_viewport = null
		view.queue_free()


func _build_chrome() -> void:
	_fallback = TextureRect.new()
	_fallback.name = "Fallback"
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback.texture = FALLBACK
	_fallback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fallback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_fallback)
	_shade = TextureRect.new()
	_shade.name = "Shade"
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.texture = _left_shade()
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_shade)


## Ztmavení vlevo, ať panel s tlačítky čte i nad světlou krajinou.
func _left_shade() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.04, 0.035, 0.03, 0.62),
		Color(0.04, 0.035, 0.03, 0.22),
		Color(0.04, 0.035, 0.03, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.34, 0.72])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 4
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0, 0.5)
	texture.fill_to = Vector2(1, 0.5)
	return texture
