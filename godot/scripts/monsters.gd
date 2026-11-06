extends Node

## Staví příšery pro Hunt: druh z monsters.json, barvy podle materiálu z katalogu krystalu.
## Sám je ve scéně nedrží. Textury a materiály vrstev načte jednou a sdílí je.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const Crystal := preload("res://scripts/crystal.gd")
const Walker := preload("res://scripts/walker.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const Person := preload("res://scripts/person.gd")
const Monster := preload("res://scripts/monster.gd")

const CATALOG := "res://graphics/characters/monsters/monsters.json"
const SHADER := "res://shaders/monster_layer.gdshader"
## Druhy s "shader": "stone" v katalogu: kamenné příšery s odlesky podle materiálu.
const STONE_SHADER := "res://shaders/monster_stone_layer.gdshader"

var _textures := {}
var _catalog := {}
## Společné materiály vrstev podle druhu shaderu (_shared_material).
var _materials := {}


func _read_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG):
		push_error("Chybí katalog příšer.")
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst katalog příšer.")
		return {}
	return parsed


## Druh kind z monsters.json. Prázdný, když v katalogu chybí.
func species_info(kind: String) -> Dictionary:
	if _catalog.is_empty():
		_catalog = _read_catalog()
	var species: Dictionary = _catalog.get("species", {})
	if not species.has(kind):
		push_warning("Příšera %s v katalogu chybí." % kind)
		return {}
	return species[kind]


## Barvy příšery druhu info v materiálu mat pro Monster.setup a Monster.repaint: tělo, kresba
## a oči, u kamenné navíc odlesk a třpyt materiálu.
func colors_of(crystal: Crystal, mat: int, info: Dictionary) -> Dictionary:
	var eye: Dictionary = info.get("colors", {})
	var colors := {
		"body": crystal.color_of(mat),
		"accent": crystal.monster_accent(mat),
		"eye": Color.html(str(eye.get("eye", "FFFFFF"))),
	}
	if str(info.get("shader", "")) == "stone":
		colors["glint"] = crystal.glint_of(mat)
		colors["sparkle"] = crystal.sparkle_of(mat)
	return colors


## Načte textury a materiál druhu kind dopředu, ať je make nenačítá uprostřed hry.
func preload_looks(kind: String) -> void:
	var info := species_info(kind)
	if info.is_empty():
		return
	_layer_textures(CATALOG.get_base_dir(), info)
	var stone := str(info.get("shader", "")) == "stone"
	if stone:
		_glint_textures(CATALOG.get_base_dir(), info)
	_shared_material(stone)


## Vrstvy druhu kind jako prosté sprity s jeho shaderem a texturami, k jednomu vykreslení
## při startu (shader se přeloží dopředu). Bez druhu prázdné.
func sample_layers(kind: String) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	var info := species_info(kind)
	if info.is_empty():
		return out
	var shared := _shared_material(str(info.get("shader", "")) == "stone")
	for texture in _layer_textures(CATALOG.get_base_dir(), info):
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.hframes = maxi(int(info.get("atlas_columns", info.get("frames", 8))), 1)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.material = shared
		out.append(sprite)
	return out


## Jedna příšera druhu kind v materiálu mat na místě at, pod host. speed násobí rychlost
## honičky druhu. Bez druhu v katalogu nebo bez textur null.
func make(
	kind: String,
	mat: int,
	crystal: Crystal,
	walker: Walker,
	persons: Array[Person],
	camera: MapCamera,
	host: Node2D,
	rng: RandomNumberGenerator,
	at: Vector2,
	speed: float,
) -> Monster:
	var info := species_info(kind)
	if info.is_empty():
		return null
	var textures := _layer_textures(CATALOG.get_base_dir(), info)
	if textures.is_empty():
		return null
	var colors := colors_of(crystal, mat, info)
	var layer_material := _shared_material(str(info.get("shader", "")) == "stone")
	if layer_material == null:
		return null
	if colors.has("sparkle"):
		colors["glint_maps"] = _glint_textures(CATALOG.get_base_dir(), info)
	var flying := bool(info.get("flying", false))
	var monster := Monster.new()
	monster.name = "Monster_%s_%d" % [kind, mat]
	monster.material_index = mat
	# Zvuky druhu, druh v katalogu je může půjčit od jiného ("sound").
	monster.kind_name = str(info.get("sound", kind))
	host.add_child(monster)
	monster.setup(info, textures, layer_material, colors, speed, float(_catalog.get("shadow_alpha", 0.35)), walker, persons, camera, rng, at)
	if not flying and walker.crowd != null:
		monster.crowd_id = walker.crowd.join(monster)
	return monster


## Společný materiál vrstev, z něj si každá vrstva udělá kopii. stone: kamenné příšery
## s odlesky (druhy s "shader": "stone").
func _shared_material(stone: bool) -> ShaderMaterial:
	var key := "stone" if stone else "plain"
	if _materials.has(key):
		return _materials[key]
	var shader := load(STONE_SHADER if stone else SHADER) as Shader
	if shader == null:
		push_error("Chybí shader příšer.")
		return null
	var shade: Array = _catalog.get("shade", [0.35, 1.15])
	var accent_shade: Array = _catalog.get("accent_shade", [0.6, 1.1])
	var shared := ShaderMaterial.new()
	shared.shader = shader
	shared.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
	shared.set_shader_parameter("shade", Vector2(float(shade[0]), float(shade[1])))
	shared.set_shader_parameter("accent_shade", Vector2(float(accent_shade[0]), float(accent_shade[1])))
	_materials[key] = shared
	return shared


func _layer_textures(root: String, info: Dictionary) -> Array[Texture2D]:
	var listed: Dictionary = info.get("layers", {})
	var keys: Array = listed.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	var out: Array[Texture2D] = []
	for key: Variant in keys:
		var path := "%s/%s" % [root, str((listed[key] as Dictionary).get("file", ""))]
		var texture := _texture_from(path)
		if texture == null:
			push_error("Chybí vrstva příšery %s." % path)
			return []
		out.append(texture)
	return out


## Atlasy předpočítaných odlesků podle pořadí vrstev, null u vrstvy bez glint_file.
func _glint_textures(root: String, info: Dictionary) -> Array:
	var listed: Dictionary = info.get("layers", {})
	var keys: Array = listed.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	var out: Array = []
	for key: Variant in keys:
		var file := str((listed[key] as Dictionary).get("glint_file", ""))
		out.append(null if file.is_empty() else _texture_from("%s/%s" % [root, file]))
	return out


## Importovaný soubor má mipmapy z importu. Soubor, který editor ještě nenaimportoval, se dopočítá.
func _texture_from(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var texture: Texture2D
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			texture = ObjectLayers.texture_with_mipmaps(image)
	_textures[path] = texture
	return texture
