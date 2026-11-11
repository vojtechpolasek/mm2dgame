extends Sprite2D

## Kámen materiálu jako ikona tlačítka. Barva říká, co tlačítko dělá: zelená dál, červená
## zpět, šedá nastavení a tak dál. Přepínač v nastavení má zelený kámen zapnutý a červený
## vypnutý (set_on), volba s více hodnotami má místo kamene hodnotu (set_value). Kámen se
## kreslí shaderem krystalu jako ve hře, i s třpytem. Tlačítko dostane prázdnou ikonu stejné
## velikosti, ať text uhne, a kámen nebo hodnota leží nad ní.

const Crystal := preload("res://scripts/crystal.gd")
const SELF := preload("res://scripts/button_gem.gd")

## Význam tlačítka: materiál z crystal.json.
const GO := "smaragd"
const BACK := "rubin"
const SETTINGS := "stribro"
const INFO := "safir"
const LOAD := "zlato"
const DELETE := "jantar"
const HUNT := "ametyst"
const COLLECT := "zlato"
const ROAM := "akvamarin"
const EVOLVE := "diamant"
## Stav přepínače.
const ON := "smaragd"
const OFF := "rubin"

## Strana prázdné ikony v pixelech. Kámen v textuře 32 px má průměr kolem 26 px.
const SIZE := 28.0
## Krytí kamene na vypnutém tlačítku.
const DISABLED_ALPHA := 0.35
## Šířka místa pro hodnotu (100 %) v pixelech.
const VALUE_WIDTH := 72.0
const VALUE_COLOR := Color(0.86, 0.66, 0.3)

## Katalog se načte jednou pro všechna menu.
static var _crystal: Crystal
static var _blank: Texture2D
static var _wide_blank: Texture2D
## Posun středu viditelné části kamene na střed textury, podle textury.
static var _offsets := {}

var _button: Button


## Dá tlačítku kámen materiálu role (GO, BACK, ...), už přidaný kámen přebarví. Bez katalogu
## nechá tlačítko bez ikony.
static func add(button: Button, role: String) -> void:
	var crystal := _catalog()
	if crystal == null:
		return
	var index := -1
	for i in crystal.count():
		if crystal.name_of(i) == role:
			index = i
			break
	if index < 0:
		push_error("Ikona tlačítka: chybí materiál %s." % role)
		return
	# Fáze třpytu podle tlačítka, ať kameny v menu neblikají naráz.
	var phase := float(button.get_instance_id() % 97)
	for child in button.get_children():
		if child.get_script() == SELF:
			crystal.paint(child as Sprite2D, index, 0.0, phase)
			return
	if _blank == null:
		_blank = _empty(SIZE)
	_reserve(button, _blank)
	var gem: Sprite2D = crystal.make_sprite()
	gem.set_script(SELF)
	crystal.paint(gem, index, 0.0, phase)
	gem.offset = _offset(gem.texture)
	gem.set(&"_button", button)
	button.add_child(gem)


## Přepínač: zelený kámen zapnutý, červený vypnutý.
static func set_on(button: Button, on: bool) -> void:
	add(button, ON if on else OFF)


## Hodnota volby (100 %) místo kamene, barvou zvýraznění a písmem tlačítka.
static func set_value(button: Button, text: String) -> void:
	var label := button.get_node_or_null(^"Value") as Label
	if label == null:
		if _wide_blank == null:
			_wide_blank = _empty(VALUE_WIDTH)
		_reserve(button, _wide_blank)
		label = Label.new()
		label.name = "Value"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", button.get_theme_font_size(&"font_size"))
		label.add_theme_color_override("font_color", VALUE_COLOR)
		var box := button.get_theme_stylebox(&"normal")
		var left := box.content_margin_left if box != null else 0.0
		label.anchor_bottom = 1.0
		label.offset_left = left
		label.offset_right = left + VALUE_WIDTH
		button.add_child(label)
	label.text = text


## Prázdná ikona: text tlačítka uhne o její šířku.
static func _reserve(button: Button, blank: Texture2D) -> void:
	button.icon = blank
	button.expand_icon = false
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT


static func _empty(width: float) -> Texture2D:
	return ImageTexture.create_from_image(Image.create_empty(int(width), int(SIZE), false, Image.FORMAT_RGBA8))


static func _catalog() -> Crystal:
	if _crystal == null:
		var crystal := Crystal.new()
		if not crystal.load_catalog() or crystal.count() == 0:
			return null
		_crystal = crystal
	return _crystal


## Střed viditelné části kamene. Obrázek kamene není v buňce přesně uprostřed.
static func _offset(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	if not _offsets.has(texture):
		var image := texture.get_image()
		if image == null:
			return Vector2.ZERO
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		_offsets[texture] = Vector2(image.get_size()) * 0.5 - (Vector2(used.position) + Vector2(used.size) * 0.5)
	return _offsets[texture]


func _ready() -> void:
	_button.resized.connect(_place)
	_place()


## Vypnuté tlačítko (Začít bez hráčů) má kámen vybledlý. Tlačítko o změně nedá vědět.
func _process(_delta: float) -> void:
	var alpha := DISABLED_ALPHA if _button.disabled else 1.0
	var shader := material as ShaderMaterial
	if shader.get_shader_parameter("alpha") != alpha:
		shader.set_shader_parameter("alpha", alpha)


## Na místo prázdné ikony: za levý okraj rámečku, svisle doprostřed.
func _place() -> void:
	var box := _button.get_theme_stylebox(&"normal")
	var left := box.content_margin_left if box != null else 0.0
	position = Vector2(left + SIZE * 0.5, _button.size.y * 0.5)
