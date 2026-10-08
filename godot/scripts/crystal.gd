extends RefCounted

## Vzory krystalu a oblázku a sada materiálů. R G B jsou masky, barvu dodá shader.
## Body 1 jsou nejběžnější, body 100 nejvzácnější.

const ObjectLayers := preload("res://scripts/object_layers.gd")
const CATALOG := "res://graphics/objects/crystal/crystal.json"

var _textures: Array[Texture2D] = []
var _material: ShaderMaterial
var _radius := 0.0
var _shape := PackedInt32Array()
var _points := PackedInt32Array()
var _color := PackedColorArray()
var _glint := PackedColorArray()
var _sparkle := PackedFloat32Array()
## Příšera materiálu: druh z monsters.json, barva kresby a zvětšení. Tělo má barvu materiálu.
var _names := PackedStringArray()
## Název pro hráče (Pískovec, Lávový kámen, ...). Bez title v katalogu je to klíč materiálu.
var _titles := PackedStringArray()
var _monster := PackedStringArray()
var _monster_accent := PackedColorArray()
var _monster_scale := PackedFloat32Array()


func load_catalog() -> bool:
	if not FileAccess.file_exists(CATALOG):
		push_error("Chybí katalog krystalu.")
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst katalog krystalu.")
		return false
	var info: Dictionary = parsed
	var shader := load(str(info.get("shader", ""))) as Shader
	if shader == null:
		push_error("Chybí shader krystalu.")
		return false
	var shapes: Variant = info.get("shapes", {})
	if typeof(shapes) != TYPE_DICTIONARY or (shapes as Dictionary).is_empty():
		push_error("Krystal nemá vzory.")
		return false
	var shape_of := {}
	var root := CATALOG.get_base_dir()
	for shape_name: String in shapes:
		var shape: Dictionary = shapes[shape_name]
		var texture := _texture_from("%s/%s" % [root, str(shape.get("file", ""))])
		if texture == null:
			push_error("Chybí vzor %s." % shape_name)
			return false
		shape_of[shape_name] = _textures.size()
		_textures.append(texture)
		_radius = maxf(_radius, float(shape.get("radius", float(texture.get_width()) * 0.35)))
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
	var listed: Variant = info.get("materials", {})
	if typeof(listed) != TYPE_DICTIONARY:
		push_error("Krystal nemá materiály.")
		return false
	for mat_name: String in listed:
		var mat: Dictionary = listed[mat_name]
		var shape_name := str(mat.get("shape", "crystal"))
		_shape.append(int(shape_of.get(shape_name, 0)))
		_points.append(clampi(int(mat.get("points", 50)), 1, 100))
		_color.append(Color.html(str(mat.get("color", "888888"))))
		_glint.append(Color.html(str(mat.get("glint", "FFFFFF"))))
		_sparkle.append(float(mat.get("sparkle", 0.0)))
		_names.append(mat_name)
		_titles.append(str(mat.get("title", mat_name)))
		_monster.append(str(mat.get("monster", "")))
		_monster_accent.append(Color.html(str(mat.get("monster_accent", mat.get("glint", "FFFFFF")))))
		_monster_scale.append(float(mat.get("monster_scale", 1.0)))
	if _color.is_empty():
		push_error("Krystal nemá materiály.")
		return false
	return true


func count() -> int:
	return _color.size()


func radius() -> float:
	return _radius


func points_of(index: int) -> int:
	return _points[index]


func color_of(index: int) -> Color:
	return _color[index]


## Jméno materiálu z katalogu (piskovec, diamant, ...).
func name_of(index: int) -> String:
	return _names[index]


func title_of(index: int) -> String:
	return _titles[index]


func monster_of(index: int) -> String:
	return _monster[index]


func monster_accent(index: int) -> Color:
	return _monster_accent[index]


func monster_scale(index: int) -> float:
	return _monster_scale[index]


func make_sprite() -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _textures[0]
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.material = _material
	return sprite


## phase rozhoduje, kdy kámen blikne, ať neblikají všechny naráz.
func paint(sprite: Sprite2D, index: int, height: float, phase: float) -> void:
	sprite.texture = _textures[_shape[index]]
	sprite.set_instance_shader_parameter("gem_color", _color[index])
	sprite.set_instance_shader_parameter("glint_color", _glint[index])
	sprite.set_instance_shader_parameter("sparkle", _sparkle[index])
	sprite.set_instance_shader_parameter("height_m", height)
	sprite.set_instance_shader_parameter("phase", phase)


func _texture_from(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return ObjectLayers.texture_with_mipmaps(image)
