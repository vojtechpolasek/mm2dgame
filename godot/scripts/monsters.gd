extends Node

## Příšery levelu: jedna za každý materiál, který má na mapě jezírka. Druh a barvy určuje
## materiál v katalogu krystalu, vzhled a pohyb druhu jsou v monsters.json.
## Objeví se náhodně v mezikruží kolem středu mapy: u okraje, uvnitř stěny skal, ale nejdál
## SPAWN_REACH metrů od středu, ať na velké mapě nezačínají stovky metrů daleko.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const Crystal := preload("res://scripts/crystal.gd")
const Walker := preload("res://scripts/walker.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const Person := preload("res://scripts/person.gd")
const Monster := preload("res://scripts/monster.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")
const Rocks := preload("res://scripts/rocks.gd")
const Forest := preload("res://scripts/forest.gd")
const Crowd := preload("res://scripts/crowd.gd")

const CATALOG := "res://graphics/characters/monsters/monsters.json"
const SHADER := "res://shaders/monster_layer.gdshader"
## Druhy s "shader": "stone" v katalogu: kamenné příšery s odlesky podle materiálu.
const STONE_SHADER := "res://shaders/monster_stone_layer.gdshader"
## Kde se příšery objeví: mezikruží kolem středu mapy. Vnější okraj je SPAWN_NEAR metrů od okraje
## mapy (stěna skal končí asi 7 m od okraje), ale nejdál SPAWN_REACH metrů od středu. Mezikruží
## je široké SPAWN_FAR - SPAWN_NEAR metrů. Chodící musí mít z místa cestu ke středu mapy, ať
## nezačne v kapse mezi skalami.
const SPAWN_NEAR := 9.0
const SPAWN_FAR := 20.0
const SPAWN_REACH := 50.0
const SPAWN_TRIES := 80
## Mřížka cest se počítá pro tělo zaokrouhlené nahoru na tolik pixelů. Podobně velké příšery
## sdílejí jednu.
const NAV_BUCKET := 8.0

var _textures := {}
## Všechny příšery levelu.
var members: Array[Monster] = []
## Vesničané, kteří nesou kámen. Příšery je honí jako hráče, pole sdílejí všechny.
var carriers: Array = []
var _navs := {}
var _catalog := {}


## Příprava, která nesahá na scénu a smí běžet ve vlákně s generováním mapy: načte katalog,
## postaví mřížky cest a hranice skal pro těla příšer. spawn je pak už jen použije.
func prepare(materials: PackedInt32Array, crystal: Crystal, walker: Walker, rocks: Rocks, forest: Forest) -> void:
	_catalog = _read_catalog()
	var species: Dictionary = _catalog.get("species", {})
	for mat in materials:
		var info: Dictionary = species.get(crystal.monster_of(mat), {})
		if info.is_empty() or bool(info.get("flying", false)):
			continue
		var body := float(info.get("body_meters", 0.4)) * float(TerrainCatalog.TILE_SIZE)
		_nav_for(body, float(info.get("jump_meters", 0.0)), walker, rocks, forest)
		rocks.prepare_bounds(body)


func _read_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG):
		push_error("Chybí katalog příšer.")
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Nelze přečíst katalog příšer.")
		return {}
	return parsed


func spawn(
	materials: PackedInt32Array,
	crystal: Crystal,
	walker: Walker,
	rocks: Rocks,
	forest: Forest,
	persons: Array[Person],
	camera: MapCamera,
	host: Node2D,
	rng: RandomNumberGenerator,
) -> void:
	if crystal == null or materials.is_empty():
		return
	if _catalog.is_empty():
		_catalog = _read_catalog()
	if _catalog.is_empty():
		return
	var catalog := _catalog
	var shader := load(SHADER) as Shader
	if shader == null:
		push_error("Chybí shader příšer.")
		return
	var shared := ShaderMaterial.new()
	shared.shader = shader
	shared.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
	var shade: Array = catalog.get("shade", [0.35, 1.15])
	var accent_shade: Array = catalog.get("accent_shade", [0.6, 1.1])
	shared.set_shader_parameter("shade", Vector2(float(shade[0]), float(shade[1])))
	shared.set_shader_parameter("accent_shade", Vector2(float(accent_shade[0]), float(accent_shade[1])))
	var shadow_alpha := float(catalog.get("shadow_alpha", 0.35))
	var stone_shared: ShaderMaterial = null
	var species: Dictionary = catalog.get("species", {})
	var root := CATALOG.get_base_dir()
	for mat in materials:
		var kind := crystal.monster_of(mat)
		if not species.has(kind):
			push_warning("Materiál %d chce příšeru %s, v katalogu chybí." % [mat, kind])
			continue
		var info: Dictionary = species[kind]
		var textures := _layer_textures(root, info)
		if textures.is_empty():
			continue
		var eye: Dictionary = info.get("colors", {})
		var colors := {
			"body": crystal.color_of(mat),
			"accent": crystal.monster_accent(mat),
			"eye": Color.html(str(eye.get("eye", "FFFFFF"))),
		}
		var layer_material := shared
		if str(info.get("shader", "")) == "stone":
			if stone_shared == null:
				stone_shared = ShaderMaterial.new()
				stone_shared.shader = load(STONE_SHADER) as Shader
				stone_shared.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
				stone_shared.set_shader_parameter("shade", Vector2(float(shade[0]), float(shade[1])))
				stone_shared.set_shader_parameter("accent_shade", Vector2(float(accent_shade[0]), float(accent_shade[1])))
			layer_material = stone_shared
			colors["glint"] = crystal.glint_of(mat)
			colors["sparkle"] = crystal.sparkle_of(mat)
			colors["glint_maps"] = _glint_textures(root, info)
		var speed := crystal.monster_speed(mat)
		var flying := bool(info.get("flying", false))
		var body := float(info.get("body_meters", 0.4)) * float(TerrainCatalog.TILE_SIZE)
		var monster := Monster.new()
		monster.name = "Monster_%s_%d" % [kind, mat]
		monster.material_index = mat
		# Zvuky druhu, druh v katalogu je může půjčit od jiného ("sound").
		monster.kind_name = str(info.get("sound", kind))
		host.add_child(monster)
		var jump := float(info.get("jump_meters", 0.0))
		var nav: NavGrid = null if flying else _nav_for(body, jump, walker, rocks, forest)
		var at := _spawn_point(walker, nav, body, flying, rng)
		monster.setup(info, textures, layer_material, colors, speed, shadow_alpha, walker, nav, persons, camera, rng, at)
		monster.carriers = carriers
		members.append(monster)
		if not flying and walker.crowd != null:
			monster.crowd_id = walker.crowd.join(monster)


## Stav k uložení: materiál a místo každé příšery.
func snapshot() -> Array:
	var out: Array = []
	for monster in members:
		if is_instance_valid(monster):
			out.append(monster.snapshot())
	return out


## Příšery z uložené hry stojí, kde stály. Páruje se podle materiálu. calm viz Monster.settle.
func restore(saved: Array, calm: float) -> void:
	var left := saved.duplicate()
	for monster in members:
		for i in left.size():
			var entry: Dictionary = left[i]
			if int(entry.get("mat", -1)) == monster.material_index:
				monster.settle(entry.get("pos", monster.position), calm)
				left.remove_at(i)
				break


## Honí teď nějaká příšera?
func any_chasing() -> bool:
	for monster in members:
		if monster.is_chasing():
			return true
	return false


## Nese někdo kámen? Hráč z persons, nebo vesničan z carriers. Podle toho hraje hudba při
## honičce, ať je příšera vidět, nebo ne.
static func anyone_carrying(persons: Array, carriers: Array) -> bool:
	if not carriers.is_empty():
		return true
	for person in persons:
		if is_instance_valid(person) and person.carried() >= 0:
			return true
	return false


## Mřížka cest pro tělo a výšku skoku. Létající příšera žádnou nepotřebuje.
func set_space(origin: Vector2) -> void:
	for key in _navs:
		(_navs[key] as NavGrid).set_space(origin)


func _nav_for(body: float, jump: float, walker: Walker, rocks: Rocks, forest: Forest) -> NavGrid:
	var bucket := ceilf(body / NAV_BUCKET) * NAV_BUCKET
	var key := "%d/%.2f" % [int(bucket), jump]
	if not _navs.has(key):
		var nav := NavGrid.new()
		nav.build(walker, rocks, forest, bucket, jump if jump > 0.0 else -1.0)
		_navs[key] = nav
	return _navs[key]


## Náhodné místo v pásu u okraje. Chodící musí stát na souši mimo překážky.
func _spawn_point(walker: Walker, nav: NavGrid, body: float, flying: bool, rng: RandomNumberGenerator) -> Vector2:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var world := walker.world()
	var center := walker.space_origin + world * 0.5
	var half := world.x * 0.5
	var outer := minf(half - SPAWN_NEAR * tile, SPAWN_REACH * tile)
	var inner := maxf(outer - (SPAWN_FAR - SPAWN_NEAR) * tile, tile)
	var far := (SPAWN_FAR - SPAWN_NEAR) * tile
	var spot := center
	for _try in SPAWN_TRIES:
		# Rovnoměrně po ploše mezikruží.
		var radius := sqrt(rng.randf_range(inner * inner, outer * outer))
		spot = center + Vector2.from_angle(rng.randf() * TAU) * radius
		if flying:
			return spot
		if not walker.blocked(spot, body) and (nav == null or nav.reaches(spot, walker.home())):
			return spot
	var free := walker.free_spot(spot, body, far, tile)
	return spot if free == Vector2.INF else free


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
