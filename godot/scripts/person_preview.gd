extends Node2D

## Chůze postavy v menu. Stejné vrstvy a shader jako ve hře, bez mapy a ovládání.

const ObjectLayers := preload("res://scripts/object_layers.gd")

const CATALOG := "res://graphics/characters/person/person.json"
const TINTS: PackedStringArray = ["skin", "hair", "eye", "shirt", "pants", "shoe", "lace"]
const SCALE := 4.0
## Jeden cyklus trvá stejně jako tři metry běhu při 4,5 m/s.
const CYCLE_TIME := 3.0 / 4.5

var _sprites: Array[Sprite2D] = []
var _heights := PackedFloat32Array()
var _materials: Array[ShaderMaterial] = []
var _frames := 16
var _time := 0.0


func _ready() -> void:
	scale = Vector2(SCALE, SCALE)
	_build()
	get_viewport().size_changed.connect(_fit)
	_fit()


func _process(delta: float) -> void:
	if _frames <= 1 or _sprites.is_empty():
		return
	_time = fmod(_time + delta, CYCLE_TIME)
	var frame := mini(int(_time / CYCLE_TIME * float(_frames)), _frames - 1)
	for sprite: Sprite2D in _sprites:
		sprite.frame = frame


func apply(colors: Dictionary) -> void:
	for tint_name: String in TINTS:
		var hex := str(colors.get(tint_name, ""))
		if hex.is_empty():
			continue
		var color := Color.html(hex)
		for sprite: Sprite2D in _sprites:
			sprite.set_instance_shader_parameter("%s_color" % tint_name, color)


func _build() -> void:
	if not FileAccess.file_exists(CATALOG):
		push_error("Chybí postava.")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst postavu.")
		return
	var info: Dictionary = parsed
	var shader := load(str(info.get("shader", ""))) as Shader
	if shader == null:
		push_error("Chybí shader postavy.")
		return
	_frames = maxi(int(info.get("frames", 8)), 1)
	var atlas_frames := maxi(int(info.get("atlas_frames", _frames)), _frames)
	var columns := maxi(int(info.get("atlas_columns", _frames)), 1)
	var shade: Array = info.get("shade", [0.42, 1.1])
	var sheen: Array = info.get("sheen", [0.16, 0.7])
	var root := CATALOG.get_base_dir()
	var listed: Dictionary = info.get("layers", {})
	var keys: Array = listed.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for key: Variant in keys:
		var layer: Dictionary = listed[key]
		var texture := load("%s/%s" % [root, str(layer.get("file", ""))]) as Texture2D
		if texture == null:
			push_error("Chybí vrstva postavy %s." % str(layer.get("file", "")))
			return
		var height := float(layer.get("height", 0.0))
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.hframes = columns
		sprite.vframes = maxi(ceili(float(atlas_frames) / float(columns)), 1)
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("height_m", height)
		material.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
		material.set_shader_parameter("shade", Vector2(float(shade[0]), float(shade[1])))
		material.set_shader_parameter("shade_floor", float(info.get("shade_floor", 0.2)))
		material.set_shader_parameter("sheen", Vector2(float(sheen[0]), float(sheen[1])))
		sprite.material = material
		sprite.set_instance_shader_parameter("slot", float(layer.get("slot", 0.0)))
		add_child(sprite)
		_sprites.append(sprite)
		_heights.append(height)
		_materials.append(material)
	var colors: Variant = info.get("colors", {})
	if typeof(colors) == TYPE_DICTIONARY:
		apply(colors)


func _fit() -> void:
	var view := get_viewport_rect().size
	if view == Vector2.ZERO:
		return
	RenderingServer.global_shader_parameter_set(&"camera_position", view * 0.5)
	RenderingServer.global_shader_parameter_set(&"camera_zoom", 1.0)
	for index in _sprites.size():
		if _heights[index] <= 0.0:
			_sprites[index].material = _materials[index]
			continue
		ObjectLayers.fit_sprite(_sprites[index], _materials[index], _heights[index], view, true)
