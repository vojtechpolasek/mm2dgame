extends Node

## Nastavení grafiky: rozlišení světa, třpyt kamenů a stíny. Ukládá se do stejného souboru
## jako zvuk, do vlastní sekce.
##
## Rozlišení světa je podíl rozlišení obrazovky (SCALES). Při 100 % se svět kreslí přímo do
## okna. Při nižším ho kreslí _view (SubViewport se stejným World2D jako okno) ve zmenšené
## velikosti a obrázek se roztáhne přes obrazovku pod HUD, bez vyhlazení (pixely jsou vidět).
## HUD a menu zůstanou ostré, svět je stejně velký, jen hrubší, a na slabé grafice je mnohem
## levnější. Hlavní okno svět
## přeskočí: uzel hry (attach_world) dostane vrstvu viditelnosti WORLD_LAYER, kterou okno
## nekreslí (canvas_cull_mask). Mimo hru (menu) se kreslí vždy přímo.
##
## Třpyt vypne odlesky kamenů, příšer a dolů přes globální uniformu sparkle_on.
## Stíny vypnou stíny od slunce, měsíce i čelovek (Shadows). Den, noc a světlo čelovek zůstanou.
## Bez persist se změna neuloží (benchmark přepíná jen na dobu měření).

signal changed

const SETTINGS := "user://settings.cfg"
const SECTION := "graphics"
## Úrovně rozlišení světa, podíl rozlišení obrazovky.
const SCALES: Array[float] = [1.0, 0.75, 0.5]
## Vrstva viditelnosti uzlu hry při zmenšeném rozlišení (bit 20), okno ji nekreslí.
const WORLD_LAYER := 1 << 19
const ALL_LAYERS := 0xFFFFF
## Obrázek světa leží v okně pod vším ostatním.
const VIEW_LAYER := -128

var _scale := 1.0
var _sparkle := true
var _shadows := true
## Uzel hry, jehož svět se kreslí zmenšeně (attach_world), null mimo hru.
var _world: CanvasItem
var _view: SubViewport
var _view_layer: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		_scale = float(config.get_value(SECTION, "scale", _scale))
		_sparkle = bool(config.get_value(SECTION, "sparkle", _sparkle))
		_shadows = bool(config.get_value(SECTION, "shadows", _shadows))
	if not SCALES.has(_scale):
		_scale = 1.0
	_apply()


## Rozlišení světa, podíl rozlišení obrazovky (jedna ze SCALES).
func world_scale() -> float:
	return _scale


## Další úroveň rozlišení světa po value, po nejnižší zase plné (tlačítko v nastavení).
func next_world_scale(value: float) -> float:
	return SCALES[(SCALES.find(value) + 1) % SCALES.size()]


func sparkle_on() -> bool:
	return _sparkle


func shadows_on() -> bool:
	return _shadows


func set_shadows(on: bool, persist := true) -> void:
	_shadows = on
	_apply()
	if persist:
		_save()


func set_world_scale(value: float, persist := true) -> void:
	_scale = value
	_apply()
	if persist:
		_save()


func set_sparkle(on: bool, persist := true) -> void:
	_sparkle = on
	_apply()
	if persist:
		_save()


## Uzel hry, jehož svět se při nižším rozlišení kreslí zmenšeně. null při odchodu ze hry.
func attach_world(world: CanvasItem) -> void:
	if _world != null and is_instance_valid(_world):
		_world.visibility_layer = 1
	_world = world
	_apply_view()


func _apply() -> void:
	RenderingServer.global_shader_parameter_set(&"sparkle_on", 1.0 if _sparkle else 0.0)
	_apply_view()
	changed.emit()


## Zapne nebo vypne zmenšené kreslení světa podle _scale a toho, jestli běží hra.
func _apply_view() -> void:
	var root := get_tree().root
	var scaled := _scale < 1.0 and _world != null and is_instance_valid(_world)
	if scaled and _view == null:
		_build_view()
	if _view != null:
		_view.world_2d = root.world_2d
		_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if scaled else SubViewport.UPDATE_DISABLED
		_view_layer.visible = scaled
		_fit_view()
	if _world != null and is_instance_valid(_world):
		_world.visibility_layer = WORLD_LAYER if scaled else 1
	root.canvas_cull_mask = ALL_LAYERS & ~WORLD_LAYER if scaled else ALL_LAYERS


func _build_view() -> void:
	var root := get_tree().root
	_view = SubViewport.new()
	_view.name = "WorldView"
	_view.disable_3d = true
	_view.canvas_item_default_texture_filter = root.canvas_item_default_texture_filter
	_view.canvas_item_default_texture_repeat = root.canvas_item_default_texture_repeat
	_view.snap_2d_transforms_to_pixel = root.snap_2d_transforms_to_pixel
	_view.snap_2d_vertices_to_pixel = root.snap_2d_vertices_to_pixel
	add_child(_view)
	_view_layer = CanvasLayer.new()
	_view_layer.layer = VIEW_LAYER
	add_child(_view_layer)
	var picture := TextureRect.new()
	picture.texture = _view.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	# Bez vyhlazení: pixely zmenšeného světa jsou vidět ostře.
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view_layer.add_child(picture)
	root.size_changed.connect(_fit_view)
	# Záběr se srovná s oknem těsně před kreslením, až po kameře.
	RenderingServer.frame_pre_draw.connect(_follow_view)


## Obrázek světa má podíl _scale z pixelů okna.
func _fit_view() -> void:
	var pixels := Vector2(get_tree().root.size) * _scale
	_view.size = Vector2i(maxi(roundi(pixels.x), 1), maxi(roundi(pixels.y), 1))


## Stejný záběr jako okno: kamera, roztažení okna na obrazovku a zmenšení na _scale.
func _follow_view() -> void:
	if not _view_layer.visible:
		return
	var root := get_tree().root
	_view.canvas_transform = (root.get_final_transform() * root.canvas_transform).scaled(Vector2.ONE * _scale)


## Soubor sdílí se zvukem. Načte se celý, ať se jeho sekce nepřepíše.
func _save() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value(SECTION, "scale", _scale)
	config.set_value(SECTION, "sparkle", _sparkle)
	config.set_value(SECTION, "shadows", _shadows)
	config.save(SETTINGS)
