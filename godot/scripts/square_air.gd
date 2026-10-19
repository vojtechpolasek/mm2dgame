extends Sprite2D

## Vzduch nad jedním čtvercem světa: mlha nad močálem, padající sníh nad sněhem a jemně
## růžový jedovatý nádech nad čtvercem levelu, dokud továrna level nesplní. Celé to kreslí
## jeden sprite přes čtverec se shaderem air.gdshader. Textura je maska terénu, dlaždice na
## pixel: R mlha, G sníh (klíče fog a snowfall v surfaces.json). Čtverec bez mlhy, sněhu
## i jedu je skrytý a shader na něm neběží.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapData := preload("res://scripts/map_data.gd")

const SHADER := "res://shaders/air.gdshader"
## Nad všemi objekty, stromy i střechami.
const Z := 8
## Za kolik sekund jed po splnění levelu vybledne.
const CLEAR_TIME := 4.0

var _poison := 0.0
var _weather := false


## Maska terénu, smí běžet ve vlákně. Okraje oblastí se rozmažou o dlaždici, ať mlha
## nemá schody po dlaždicích. Bez mlhy i sněhu vrací prázdný obraz.
static func mask(map: MapData) -> Image:
	var size := map.size
	var fog := PackedFloat32Array()
	var snow := PackedFloat32Array()
	fog.resize(map.names.size())
	snow.resize(map.names.size())
	var any := false
	for id in map.names.size():
		var info := map.info_of(id)
		fog[id] = clampf(float(info.get("fog", 0.0)), 0.0, 1.0)
		snow[id] = clampf(float(info.get("snowfall", 0.0)), 0.0, 1.0)
		any = any or fog[id] > 0.0 or snow[id] > 0.0
	if not any:
		return Image.new()
	var raw_fog := PackedFloat32Array()
	var raw_snow := PackedFloat32Array()
	raw_fog.resize(size * size)
	raw_snow.resize(size * size)
	var found := false
	for cell in size * size:
		raw_fog[cell] = fog[map.terrain[cell]]
		raw_snow[cell] = snow[map.terrain[cell]]
		found = found or raw_fog[cell] > 0.0 or raw_snow[cell] > 0.0
	if not found:
		return Image.new()
	var bytes := PackedByteArray()
	bytes.resize(size * size * 4)
	for y in size:
		for x in size:
			var sum_fog := 0.0
			var sum_snow := 0.0
			var count := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := clampi(x + dx, 0, size - 1)
					var ny := clampi(y + dy, 0, size - 1)
					sum_fog += raw_fog[ny * size + nx]
					sum_snow += raw_snow[ny * size + nx]
					count += 1.0
			var at := (y * size + x) * 4
			bytes[at] = int(sum_fog / count * 255.0)
			bytes[at + 1] = int(sum_snow / count * 255.0)
			bytes[at + 3] = 255
	return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes)


## Sprite přes čtverec. map_mask z mask(), poisoned zapne jed.
func setup(map_mask: Image, size: int, origin: Vector2, poisoned: bool) -> void:
	_weather = not map_mask.is_empty()
	var image := map_mask
	if not _weather:
		image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	texture = ImageTexture.create_from_image(image)
	centered = false
	position = origin
	scale = Vector2.ONE * float(TerrainCatalog.TILE_SIZE)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	z_index = Z
	var shade := ShaderMaterial.new()
	shade.shader = load(SHADER)
	material = shade
	_set_poison(1.0 if poisoned else 0.0)


## Továrna vyrobila vzduch: jed pomalu vybledne.
func clear_poison() -> void:
	if _poison <= 0.0:
		return
	var tween := create_tween()
	tween.tween_method(_set_poison, _poison, 0.0, CLEAR_TIME)


func _set_poison(value: float) -> void:
	_poison = value
	(material as ShaderMaterial).set_shader_parameter("poison", value)
	visible = _weather or value > 0.0
