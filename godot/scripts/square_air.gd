extends Node2D

## Vzduch nad jedním čtvercem světa: mlha nad močálem, padající sníh nad sněhem a jemně
## růžový jedovatý nádech nad čtvercem levelu, dokud továrna level nesplní.
##
## Jed je jen průhledný obdélník přes čtverec bez shaderu, pomalu pulzuje. Mlhu a sníh kreslí
## shader air.gdshader, a to jen kusy po CHUNK dlaždicích, kde nějaké jsou: jinde neběží nic.
## Textura kusů je maska terénu, dlaždice na pixel: R mlha, G sníh (klíče fog a snowfall
## v surfaces.json). Šum mlhy a vločky jsou předpočítané textury (_noise, _flakes), shader
## z nich jen čte.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapData := preload("res://scripts/map_data.gd")

const SHADER := "res://shaders/air.gdshader"
## Nad všemi objekty, stromy i střechami.
const Z := 8
## Za kolik sekund jed po splnění levelu vybledne.
const CLEAR_TIME := 4.0
## Strana kusu mlhy a sněhu v dlaždicích.
const CHUNK := 8
## Jed: barva, krytí a o kolik krytí kolísá, za kolik sekund.
const POISON_COLOR := Color(1.0, 0.58, 0.78)
const POISON_ALPHA := 0.1
const POISON_PULSE := 0.025
const POISON_PERIOD := 6.0
## Předpočítané textury: strana šumu mlhy a vloček v pixelech, počet vloček.
const NOISE_SIDE := 256
const FLAKES_SIDE := 512
const FLAKE_COUNT := 16

## Sdílené všemi čtverci, vzniknou při prvním použití.
static var _material: ShaderMaterial

var _poison := 0.0
var _poison_rect: ColorRect
var _pulse: Tween


## Maska terénu a seznam kusů s mlhou nebo sněhem, smí běžet ve vlákně. Okraje oblastí se
## rozmažou o dlaždici, ať mlha nemá schody po dlaždicích. Bez mlhy i sněhu je obraz prázdný.
static func mask(map: MapData) -> Dictionary:
	var empty := {"image": Image.new(), "chunks": PackedVector2Array()}
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
		return empty
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
		return empty
	var bytes := PackedByteArray()
	bytes.resize(size * size * 4)
	var side := ceili(float(size) / CHUNK)
	var used := PackedByteArray()
	used.resize(side * side)
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
			if bytes[at] > 0 or bytes[at + 1] > 0:
				used[(y / CHUNK) * side + x / CHUNK] = 1
	var chunks := PackedVector2Array()
	for i in used.size():
		if used[i] > 0:
			chunks.append(Vector2(i % side, i / side))
	return {"image": Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes), "chunks": chunks}


## Kusy mlhy a sněhu a jed přes čtverec. air z mask(), poisoned zapne jed.
func setup(air: Dictionary, size: int, origin: Vector2, poisoned: bool) -> void:
	position = origin
	z_index = Z
	var tile := float(TerrainCatalog.TILE_SIZE)
	var chunks: PackedVector2Array = air["chunks"]
	if not chunks.is_empty():
		var texture := ImageTexture.create_from_image(air["image"])
		for chunk in chunks:
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_rect = Rect2(chunk * CHUNK, Vector2.ONE * CHUNK).intersection(Rect2(0, 0, size, size))
			sprite.position = chunk * CHUNK * tile
			sprite.scale = Vector2.ONE * tile
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			sprite.material = _shared_material()
			add_child(sprite)
	_poison_rect = ColorRect.new()
	_poison_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_poison_rect.size = Vector2.ONE * size * tile
	add_child(_poison_rect)
	_set_poison(1.0 if poisoned else 0.0)


## Továrna vyrobila vzduch: jed pomalu vybledne.
func clear_poison() -> void:
	if _poison <= 0.0:
		return
	var tween := create_tween()
	tween.tween_method(_set_poison, _poison, 0.0, CLEAR_TIME)


func _set_poison(value: float) -> void:
	_poison = value
	_poison_rect.color = Color(POISON_COLOR, POISON_ALPHA * value)
	_poison_rect.visible = value > 0.0
	# Pulz kolísá krytím celého obdélníku (modulate), barva nese sílu jedu.
	if value > 0.0 and _pulse == null:
		_pulse = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(_poison_rect, "modulate:a", 1.0 - POISON_PULSE / POISON_ALPHA, POISON_PERIOD * 0.5)
		_pulse.tween_property(_poison_rect, "modulate:a", 1.0, POISON_PERIOD * 0.5)
	elif value <= 0.0 and _pulse != null:
		_pulse.kill()
		_pulse = null


static func _shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER)
		_material.set_shader_parameter("fog_noise", _noise())
		_material.set_shader_parameter("flakes", _flakes())
	return _material


## Opakovatelný šum mlhy (fraktální hodnotový šum, tři oktávy).
static func _noise() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise.frequency = 8.0 / NOISE_SIDE
	noise.fractal_octaves = 3
	noise.seed = 7
	var image := noise.get_seamless_image(NOISE_SIDE, NOISE_SIDE)
	image.convert(Image.FORMAT_L8)
	return ImageTexture.create_from_image(image)


## Opakovatelná textura vloček: měkké bílé tečky, přes kraj navazují.
static func _flakes() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bytes := PackedByteArray()
	bytes.resize(FLAKES_SIDE * FLAKES_SIDE)
	for i in FLAKE_COUNT:
		var center := Vector2(rng.randf(), rng.randf()) * FLAKES_SIDE
		var radius := rng.randf_range(3.2, 4.8)
		var reach := ceili(radius)
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var px := Vector2(floorf(center.x) + dx, floorf(center.y) + dy)
				var d := (px + Vector2(0.5, 0.5)).distance_to(center)
				var value := int(clampf(smoothstep(radius, radius * 0.35, d), 0.0, 1.0) * 255.0)
				var at := posmod(int(px.y), FLAKES_SIDE) * FLAKES_SIDE + posmod(int(px.x), FLAKES_SIDE)
				bytes[at] = maxi(bytes[at], value)
	var image := Image.create_from_data(FLAKES_SIDE, FLAKES_SIDE, false, Image.FORMAT_L8, bytes)
	return ImageTexture.create_from_image(image)
