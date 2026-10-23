extends Node

## Příšery čtverce: jedna za každý materiál, který má na mapě důl. Druh a barvy určuje
## materiál v katalogu krystalu, vzhled a pohyb druhu jsou v monsters.json.
## Každá příšera se toulá v mezikruží kolem dolu svého materiálu (Crystal.monster_range) a tam
## se i objeví. Bez dolu nebo oblasti se objeví v mezikruží kolem středu mapy, nejdál
## SPAWN_REACH metrů od středu.

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
## Kde se příšera bez oblasti objeví: mezikruží kolem středu mapy. Vnější okraj je SPAWN_NEAR
## metrů od okraje mapy, ale nejdál SPAWN_REACH metrů od středu. Mezikruží je široké
## SPAWN_FAR - SPAWN_NEAR metrů. Chodící musí mít z místa cestu ke středu mapy, ať nezačne
## v kapse mezi skalami. Stejně se ověřuje i místo v oblasti kolem dolu.
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
## Společné materiály vrstev podle druhu shaderu (_shared_material).
var _materials := {}


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
	var tile := float(TerrainCatalog.TILE_SIZE)
	for mat in materials:
		var info := info_of(crystal, mat)
		if info.is_empty():
			continue
		var flying := bool(info.get("flying", false))
		var body := float(info.get("body_meters", 0.4)) * tile
		var nav: NavGrid = null if flying else nav_of(info, walker, rocks, forest)
		var area := crystal.monster_range(mat) * tile
		var home := _mine_of(rocks, mat, walker.home())
		if home == Vector2.INF or area.y <= 0.0:
			home = Vector2.INF
			area = Vector2.ZERO
		var at := _area_point(walker, nav, body, flying, home, area, rng) if area.y > 0.0 else Vector2.INF
		if at == Vector2.INF:
			at = _spawn_point(walker, nav, body, flying, rng)
		var monster := make(mat, crystal, walker, nav, persons, camera, host, rng, at, home, area, crystal.monster_speed(mat))
		if monster != null:
			members.append(monster)


## Druh příšery materiálu mat z monsters.json. Prázdný, když v katalogu chybí.
func info_of(crystal: Crystal, mat: int) -> Dictionary:
	if _catalog.is_empty():
		_catalog = _read_catalog()
	var species: Dictionary = _catalog.get("species", {})
	var kind := crystal.monster_of(mat)
	if not species.has(kind):
		push_warning("Materiál %d chce příšeru %s, v katalogu chybí." % [mat, kind])
		return {}
	return species[kind]


## Načte textury a materiál příšery materiálu mat dopředu, ať je make nenačítá uprostřed hry.
func preload_looks(crystal: Crystal, mat: int) -> void:
	var info := info_of(crystal, mat)
	if info.is_empty():
		return
	_layer_textures(CATALOG.get_base_dir(), info)
	var stone := str(info.get("shader", "")) == "stone"
	if stone:
		_glint_textures(CATALOG.get_base_dir(), info)
	_shared_material(stone)


## Vrstvy příšery materiálu mat jako prosté sprity s jejím shaderem a texturami, k jednomu
## vykreslení při startu (shader se přeloží dopředu). Bez druhu prázdné.
func sample_layers(crystal: Crystal, mat: int) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	var info := info_of(crystal, mat)
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


## Mřížka cest pro druh info. Létající žádnou nepotřebuje, vrátí null.
func nav_of(info: Dictionary, walker: Walker, rocks: Rocks, forest: Forest) -> NavGrid:
	if bool(info.get("flying", false)):
		return null
	var body := float(info.get("body_meters", 0.4)) * float(TerrainCatalog.TILE_SIZE)
	return _nav_for(body, float(info.get("jump_meters", 0.0)), walker, rocks, forest)


## Jedna příšera materiálu mat na místě at, toulá se v mezikruží area (px) kolem home.
## speed násobí rychlost honičky druhu. hunt: místo honičky utíká před postavami (Hunt).
## Bez druhu v katalogu nebo bez textur null.
func make(
	mat: int,
	crystal: Crystal,
	walker: Walker,
	nav: NavGrid,
	persons: Array[Person],
	camera: MapCamera,
	host: Node2D,
	rng: RandomNumberGenerator,
	at: Vector2,
	home: Vector2,
	area: Vector2,
	speed: float,
	hunt := false,
) -> Monster:
	var info := info_of(crystal, mat)
	if info.is_empty():
		return null
	var textures := _layer_textures(CATALOG.get_base_dir(), info)
	if textures.is_empty():
		return null
	var eye: Dictionary = info.get("colors", {})
	var colors := {
		"body": crystal.color_of(mat),
		"accent": crystal.monster_accent(mat),
		"eye": Color.html(str(eye.get("eye", "FFFFFF"))),
	}
	var layer_material := _shared_material(str(info.get("shader", "")) == "stone")
	if layer_material == null:
		return null
	if str(info.get("shader", "")) == "stone":
		colors["glint"] = crystal.glint_of(mat)
		colors["sparkle"] = crystal.sparkle_of(mat)
		colors["glint_maps"] = _glint_textures(CATALOG.get_base_dir(), info)
	var flying := bool(info.get("flying", false))
	var kind := crystal.monster_of(mat)
	var monster := Monster.new()
	monster.name = "Monster_%s_%d" % [kind, mat]
	monster.material_index = mat
	monster.hunt = hunt
	# Zvuky druhu, druh v katalogu je může půjčit od jiného ("sound").
	monster.kind_name = str(info.get("sound", kind))
	host.add_child(monster)
	if home != Vector2.INF and area.y > 0.0:
		monster.home = home
		monster.home_range = area
	monster.setup(info, textures, layer_material, colors, speed, float(_catalog.get("shadow_alpha", 0.35)), walker, nav, persons, camera, rng, at)
	monster.carriers = carriers
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
## Důl materiálu mat nejblíž k near. Bez dolu Vector2.INF.
static func _mine_of(rocks: Rocks, mat: int, near: Vector2) -> Vector2:
	var best := Vector2.INF
	for slot in rocks.ponds_holding(mat):
		var center := rocks.pond_center(slot)
		if best == Vector2.INF or near.distance_squared_to(center) < near.distance_squared_to(best):
			best = center
	return best


## Volné místo v mezikruží area (px) kolem dolu home, na čtverci. Nenajde-li, Vector2.INF.
func _area_point(walker: Walker, nav: NavGrid, body: float, flying: bool, home: Vector2, area: Vector2, rng: RandomNumberGenerator) -> Vector2:
	for _try in SPAWN_TRIES:
		var radius := sqrt(rng.randf_range(area.x * area.x, area.y * area.y))
		var spot := home + Vector2.from_angle(rng.randf() * TAU) * radius
		if not walker.contains(spot, Walker.EDGE_M * float(TerrainCatalog.TILE_SIZE)):
			continue
		if flying:
			return spot
		if not walker.blocked(spot, body) and (nav == null or nav.reaches(spot, walker.home())):
			return spot
	return Vector2.INF


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
