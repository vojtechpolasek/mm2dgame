extends CanvasLayer

## Logo přes celé menu, dokud se pod ním neskládá krajina. Obrázek a barva jsou stejné
## jako úvodní obrazovka Godotu (project.godot), takže na ni naváže bez bliknutí.
## Pod logem se vlní řada drahokamů, ať je vidět, že se něco děje. Jsou to kameny ze hry:
## stejný obrázek i shader s odlesky.

const SPLASH := preload("res://graphics/menu/splash.png")
const Crystal := preload("res://scripts/crystal.gd")
## Stejná jako boot_splash/bg_color a pozadí v tools/gen_logo.py.
const BACKGROUND := Color8(18, 20, 17)
## Rozměr obrázku a kde na něm leží ukazatel, v pixelech obrázku.
const IMAGE := Vector2(1920, 1080)
const LOADER_Y := 842.0
## Velikost kamene v pixelech obrázku a rozestup kamenů.
const GEM := 30.0
const GEM_GAP := 40.0
const GEMS: PackedStringArray = ["smaragd", "zlato", "rubin", "safir", "diamant"]
## Jak rychle se ukazatel objeví a jak dlouho trvá rozplynutí opony, v sekundách.
const LOADER_FADE := 0.5
## Barvy drahokamů stažené k šedi jako materiály v logu (SATURATION v gen_logo.py).
const SATURATION := 0.62
const LIFT := 0.45

var _cover: Control
var _time := 0.0
var _lifting := false
var _crystal: Crystal
var _stones: Array[Sprite2D] = []
## Barva kamene stažená k šedi, podle pořadí v GEMS.
var _colors := PackedColorArray()


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cover = Control.new()
	_cover.name = "Cover"
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.draw.connect(_draw_cover)
	add_child(_cover)
	_build_stones()


func _build_stones() -> void:
	_crystal = Crystal.new()
	if not _crystal.load_catalog():
		return
	for gem_name: String in GEMS:
		for index in _crystal.count():
			if _crystal.name_of(index) != gem_name:
				continue
			var stone := _crystal.make_sprite()
			_crystal.paint(stone, index, 0.0, float(_stones.size()) * 1.3)
			var color := _crystal.color_of(index)
			var gray := color.get_luminance()
			_colors.append(Color(gray, gray, gray).lerp(color, SATURATION))
			stone.visible = false
			_cover.add_child(stone)
			_stones.append(stone)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _lifting:
		_cover.modulate.a = maxf(_cover.modulate.a - delta / LIFT, 0.0)
		if _cover.modulate.a <= 0.0:
			_lifting = false
			visible = false
	_place_stones()
	_cover.queue_redraw()


## Opona hned plně zakryje obrazovku.
func drop() -> void:
	_lifting = false
	_time = 0.0
	_cover.modulate.a = 1.0
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true


## Opona se rozplyne. Myš už propustí, menu pod ní je hned k ovládání.
func lift(immediately := false) -> void:
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if immediately:
		_lifting = false
		visible = false
		return
	_lifting = visible


func _draw_cover() -> void:
	var view := _cover.size
	_cover.draw_rect(Rect2(Vector2.ZERO, view), BACKGROUND)
	# Jako boot_splash/stretch_mode Keep: celý obrázek, poměr stran zůstane.
	var scale := minf(view.x / IMAGE.x, view.y / IMAGE.y)
	var origin := (view - IMAGE * scale) * 0.5
	_cover.draw_texture_rect(SPLASH, Rect2(origin, IMAGE * scale), false)


## Kameny jsou uzly pod oponou. Shader kamene přepisuje barvu, průhlednost opony
## a ztmavení se mu proto předávají jako parametry.
func _place_stones() -> void:
	var view := _cover.size
	var scale := minf(view.x / IMAGE.x, view.y / IMAGE.y)
	var origin := (view - IMAGE * scale) * 0.5
	var center := origin + Vector2(IMAGE.x * 0.5, LOADER_Y) * scale
	var shown := clampf(_time / LOADER_FADE, 0.0, 1.0) * _cover.modulate.a
	var count := _stones.size()
	for i in count:
		var stone := _stones[i]
		stone.visible = shown > 0.0
		# Vlna jde zleva doprava, rozsvícený kámen povyskočí.
		var wave := 0.5 + 0.5 * sin(_time * 5.0 - float(i) * 0.9)
		var lit := pow(wave, 3.0)
		stone.position = center + Vector2((float(i) - float(count - 1) * 0.5) * GEM_GAP, -lit * 6.0) * scale
		var side := GEM * scale * (0.8 + 0.3 * lit) / float(stone.texture.get_width())
		stone.scale = Vector2(side, side)
		Crystal.tune(stone, &"gem_color", _colors[i].darkened(0.55 * (1.0 - lit)))
		Crystal.tune(stone, &"alpha", shown)
