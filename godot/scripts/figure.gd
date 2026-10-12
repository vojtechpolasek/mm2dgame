extends RefCounted

## Postava ze tří vrstev person.json (nohy, tělo, hlava) na uzlu host. Hráč běží atlasem běhu,
## vesničan chodí atlasem chůze s kratším krokem. Atlas je nakreslený směrem na sever, ostatní
## směry otáčí host. Barvy jsou instance parametry, materiály vrstev sdílí všechny postavy.

const ObjectLayers := preload("res://scripts/object_layers.gd")
const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")

const CATALOG := "res://graphics/characters/person/person.json"
const TINTS: PackedStringArray = ["skin", "hair", "eye", "shirt", "pants", "shoe", "lace"]

static var _info := {}
static var _materials := {}

var frames := 16
var atlas_frames := 17
var idle_frame := 16
## Kolik pixelů ujde postava za jeden cyklus (dva kroky).
var cycle_px := 192.0
## Výška těla, v ní je dlaň a kámen v ruce.
var hand_height := 1.2
var _sprites: Array[Sprite2D] = []
var _heights := PackedFloat32Array()
var _layer_materials: Array[ShaderMaterial] = []
var _body: Sprite2D
var _walk_texture: Texture2D
var _hold_texture: Texture2D
var _fitted := Vector2.ZERO


## Vrstvy přidá do host. walk vezme atlasy chůze, cycle_m je délka cyklu běhu v metrech.
func build(host: Node2D, walk: bool, cycle_m: float) -> bool:
	var info := _catalog()
	if info.is_empty():
		return false
	frames = maxi(int(info.get("frames", 8)), 1)
	atlas_frames = maxi(int(info.get("atlas_frames", frames)), frames)
	idle_frame = clampi(int(info.get("idle_frame", 0)), 0, atlas_frames - 1)
	var walking: Dictionary = info.get("walk", {})
	var walk_layers: Dictionary = walking.get("layers", {}) if walk else {}
	if walk:
		cycle_m = float(walking.get("cycle_m", cycle_m))
	cycle_px = cycle_m * float(TerrainCatalog.TILE_SIZE)
	var columns := maxi(int(info.get("atlas_columns", frames)), 1)
	var root := CATALOG.get_base_dir()
	var listed: Dictionary = info.get("layers", {})
	var keys: Array = listed.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for key: Variant in keys:
		var layer: Dictionary = listed[key]
		var file := str((walk_layers.get(key, layer) as Dictionary).get("file", layer.get("file", "")))
		var texture := load("%s/%s" % [root, file]) as Texture2D
		if texture == null:
			push_error("Chybí vrstva postavy %s." % file)
			return false
		var height := float(layer.get("height", 0.0))
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.hframes = columns
		sprite.vframes = maxi(ceili(float(atlas_frames) / float(columns)), 1)
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var material := _material(info, str(key), height)
		sprite.material = material
		_layer_materials.append(material)
		sprite.set_instance_shader_parameter("slot", float(layer.get("slot", 0.0)))
		if is_equal_approx(float(layer.get("slot", -1.0)), 1.0):
			_body = sprite
			_walk_texture = texture
			hand_height = height
		host.add_child(sprite)
		_sprites.append(sprite)
		_heights.append(height)
	if _sprites.is_empty():
		push_error("Postava nemá vrstvy.")
		return false
	tint(info.get("colors", {}))
	var hold_info: Dictionary = info.get("hold", {})
	_hold_texture = load("%s/%s" % [root, str(hold_info.get("file", ""))]) as Texture2D
	if _hold_texture == null:
		push_error("Chybí úchop postavy.")
	return true


static func _catalog() -> Dictionary:
	if not _info.is_empty():
		return _info
	if not FileAccess.file_exists(CATALOG):
		push_error("Chybí postava.")
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst postavu.")
		return {}
	_info = parsed
	return _info


static func _material(info: Dictionary, key: String, height: float) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key]
	var shader := load(str(info.get("shader", ""))) as Shader
	if shader == null:
		push_error("Chybí shader postavy.")
		return null
	var shade: Array = info.get("shade", [0.42, 1.1])
	var sheen: Array = info.get("sheen", [0.16, 0.7])
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("height_m", height)
	material.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
	material.set_shader_parameter("shade", Vector2(float(shade[0]), float(shade[1])))
	material.set_shader_parameter("shade_floor", float(info.get("shade_floor", 0.2)))
	material.set_shader_parameter("sheen", Vector2(float(sheen[0]), float(sheen[1])))
	_materials[key] = material
	return material


## Barvy podle TINTS, hex bez mřížky. Chybějící zůstanou.
func tint(colors: Variant) -> void:
	if typeof(colors) != TYPE_DICTIONARY:
		return
	var listed: Dictionary = colors
	for tint_name: String in TINTS:
		var hex := str(listed.get(tint_name, ""))
		if hex.is_empty():
			continue
		var color := Color.html(hex)
		for sprite: Sprite2D in _sprites:
			sprite.set_instance_shader_parameter("%s_color" % tint_name, color)


func set_frame(index: int) -> void:
	var frame := clampi(index, 0, atlas_frames - 1)
	for sprite: Sprite2D in _sprites:
		sprite.frame = frame


## Snímek cyklu podle ušlé vzdálenosti v pixelech.
func set_travel(travel: float) -> void:
	set_frame(int(fposmod(travel / cycle_px, 1.0) * float(frames)))


## Pravá ruka natažená dopředu.
func set_hold(on: bool) -> void:
	if _body == null or _hold_texture == null or _walk_texture == null:
		return
	var texture := _hold_texture if on else _walk_texture
	if _body.texture == texture:
		return
	_body.texture = texture
	fit(_fitted)


func fit(view: Vector2) -> void:
	_fitted = view
	if view == Vector2.ZERO:
		return
	# Nohy jsou ve výšce 0 a shader potřebují kvůli barvě. fit_sprite by jim ho sebral.
	for i in _sprites.size():
		if _heights[i] <= 0.0:
			continue
		ObjectLayers.fit_sprite(_sprites[i], _layer_materials[i], _heights[i], view, true)
