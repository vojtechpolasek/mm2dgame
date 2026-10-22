extends RefCounted

## Postava ze tří vrstev person.json (nohy, tělo, hlava) na uzlu host. Hráč běží atlasem běhu,
## vesničan chodí atlasem chůze s kratším krokem a když pomáhá, přepne na běh (set_run). Atlas je nakreslený směrem na sever, ostatní
## směry otáčí host. Barvy jsou instance parametry, materiály vrstev sdílí všechny postavy.

const ObjectLayers := preload("res://scripts/object_layers.gd")
const Shadows := preload("res://scripts/shadows.gd")
const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")

const CATALOG := "res://graphics/characters/person/person.json"
const TINTS: PackedStringArray = ["skin", "hair", "eye", "shirt", "pants", "shoe", "lace", "tank", "hose", "mouth"]
## Dýchací přístroj nasazuje hra (set_gear), postava ho na začátku nemá.
const GEAR_ON_START := false

static var _info := {}

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
## Atlasy vrstev podle pořadí _sprites. Atlasy chůze jsou jen u postavy postavené s walk.
var _run_textures: Array[Texture2D] = []
var _walk_textures: Array[Texture2D] = []
var _run_cycle_px := 192.0
var _walk_cycle_px := 192.0
var _running := true
var _holding := false
var _hold_texture: Texture2D
var _fitted := Vector2.ZERO
## Dýchací přístroj: překryvy hned nad vrstvou těla a hlavy, stejné snímky jako postava.
var _gear_sprites: Array[Sprite2D] = []
var _gear_heights := PackedFloat32Array()
var _gear_materials: Array[ShaderMaterial] = []
var _gear_run: Array[Texture2D] = []
var _gear_walk: Array[Texture2D] = []
var _gear_on := false


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
	_run_cycle_px = cycle_m * float(TerrainCatalog.TILE_SIZE)
	_walk_cycle_px = float(walking.get("cycle_m", cycle_m)) * float(TerrainCatalog.TILE_SIZE)
	_running = not walk
	cycle_px = _run_cycle_px if _running else _walk_cycle_px
	var columns := maxi(int(info.get("atlas_columns", frames)), 1)
	var root := CATALOG.get_base_dir()
	var listed: Dictionary = info.get("layers", {})
	var keys: Array = listed.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	var by_key := {}
	for key: Variant in keys:
		var layer: Dictionary = listed[key]
		var run_texture := _load_layer(root, str(layer.get("file", "")))
		if run_texture == null:
			return false
		var texture := run_texture
		if walk:
			texture = _load_layer(root, str((walk_layers.get(key, layer) as Dictionary).get("file", layer.get("file", ""))))
			if texture == null:
				return false
			_walk_textures.append(texture)
		_run_textures.append(run_texture)
		var height := float(layer.get("height", 0.0))
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.hframes = columns
		sprite.vframes = maxi(ceili(float(atlas_frames) / float(columns)), 1)
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var material := _material(info, height)
		material.set_shader_parameter("slot", float(layer.get("slot", 0.0)))
		sprite.material = material
		_layer_materials.append(material)
		if is_equal_approx(float(layer.get("slot", -1.0)), 1.0):
			_body = sprite
			hand_height = height
		host.add_child(sprite)
		_sprites.append(sprite)
		_heights.append(height)
		by_key[str(key)] = sprite
	if _sprites.is_empty():
		push_error("Postava nemá vrstvy.")
		return false
	_build_gear(host, info, walk, columns, root, by_key)
	tint(info.get("colors", {}))
	set_gear(GEAR_ON_START)
	# Lidé čelovku nesou, světlo jí nestíní.
	if Shadows.current != null:
		Shadows.current.follow(_sprites + _gear_sprites, Array(_heights + _gear_heights), true, false)
	var hold_info: Dictionary = info.get("hold", {})
	_hold_texture = load("%s/%s" % [root, str(hold_info.get("file", ""))]) as Texture2D
	if _hold_texture == null:
		push_error("Chybí úchop postavy.")
	return true


## Překryv přístroje leží v host hned za vrstvou, nad kterou patří: přikryje tělo a hlava
## přikryje jeho hadici. Bez přístroje v katalogu postava jen nejde obléct.
func _build_gear(host: Node2D, info: Dictionary, walk: bool, columns: int, root: String, by_key: Dictionary) -> void:
	var gear: Dictionary = info.get("gear", {})
	var listed: Dictionary = gear.get("layers", {})
	for key: Variant in listed:
		var layer: Dictionary = listed[key]
		var base: Sprite2D = by_key.get(str(key))
		if base == null:
			continue
		var run_texture := _load_layer(root, str(layer.get("file", "")))
		if run_texture == null:
			continue
		var texture := run_texture
		if walk:
			texture = _load_layer(root, str((layer.get("walk", {}) as Dictionary).get("file", layer.get("file", ""))))
			if texture == null:
				continue
		var height := float(layer.get("height", 0.0))
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.hframes = columns
		sprite.vframes = maxi(ceili(float(atlas_frames) / float(columns)), 1)
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.visible = false
		var material := _material(info, height)
		material.set_shader_parameter("slot", float(gear.get("slot", 3.0)))
		sprite.material = material
		host.add_child(sprite)
		host.move_child(sprite, base.get_index() + 1)
		_gear_sprites.append(sprite)
		_gear_heights.append(height)
		_gear_materials.append(material)
		_gear_run.append(run_texture)
		if walk:
			_gear_walk.append(texture)


## Dýchací přístroj na zádech a náústek před pusou.
func set_gear(on: bool) -> void:
	_gear_on = on and not _gear_sprites.is_empty()
	for sprite: Sprite2D in _gear_sprites:
		sprite.visible = _gear_on
		if _gear_on:
			sprite.frame = _sprites[0].frame


func has_gear() -> bool:
	return _gear_on


## Prázdný skafandr jako předmět (gear.item v person.json), barvy výbavy z katalogu.
## height je výška pro posun vrstev, nad nulou potřebuje volající sprite rozšířit (fit_sprite).
static func gear_item(height: float = 0.0) -> Sprite2D:
	var info := _catalog()
	var gear: Dictionary = info.get("gear", {})
	var item: Dictionary = gear.get("item", {})
	var texture := _load_layer(CATALOG.get_base_dir(), str(item.get("file", "")))
	if texture == null:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var material := _material(info, height)
	material.set_shader_parameter("slot", float(gear.get("slot", 3.0)))
	var colors: Dictionary = info.get("colors", {})
	for part: String in ["tank", "hose", "mouth"]:
		if colors.has(part):
			material.set_shader_parameter("%s_color" % part, Color.html(str(colors[part])))
	sprite.material = material
	return sprite


static func _load_layer(root: String, file: String) -> Texture2D:
	var texture := load("%s/%s" % [root, file]) as Texture2D
	if texture == null:
		push_error("Chybí vrstva postavy %s." % file)
	return texture


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


## Každá vrstva má vlastní materiál s barvami. Instanční uniformy stačí v renderu
## Compatibility jen na pár stovek objektů.
static func _material(info: Dictionary, height: float) -> ShaderMaterial:
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
		for material in _layer_materials:
			material.set_shader_parameter("%s_color" % tint_name, color)
		for material in _gear_materials:
			material.set_shader_parameter("%s_color" % tint_name, color)


func set_frame(index: int) -> void:
	var frame := clampi(index, 0, atlas_frames - 1)
	for sprite: Sprite2D in _sprites:
		sprite.frame = frame
	if _gear_on:
		for sprite: Sprite2D in _gear_sprites:
			sprite.frame = frame


## Snímek cyklu podle ušlé vzdálenosti v pixelech.
func set_travel(travel: float) -> void:
	set_frame(int(fposmod(travel / cycle_px, 1.0) * float(frames)))


## Pravá ruka natažená dopředu.
func set_hold(on: bool) -> void:
	if _body == null or _hold_texture == null:
		return
	_holding = on
	_apply_textures()


## Běh, nebo chůze. Jen u postavy postavené s walk, ostatní běží pořád.
func set_run(on: bool) -> void:
	if _walk_textures.is_empty() or _running == on:
		return
	_running = on
	cycle_px = _run_cycle_px if on else _walk_cycle_px
	_apply_textures()


func _apply_textures() -> void:
	var listed := _run_textures if _running or _walk_textures.is_empty() else _walk_textures
	var changed := false
	for i in _sprites.size():
		var texture := listed[i]
		if _sprites[i] == _body and _holding and _hold_texture != null:
			texture = _hold_texture
		if _sprites[i].texture != texture:
			_sprites[i].texture = texture
			changed = true
	var gear := _gear_run if _running or _gear_walk.is_empty() else _gear_walk
	for i in _gear_sprites.size():
		if _gear_sprites[i].texture != gear[i]:
			_gear_sprites[i].texture = gear[i]
			changed = true
	if changed:
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
	for i in _gear_sprites.size():
		ObjectLayers.fit_sprite(_gear_sprites[i], _gear_materials[i], _gear_heights[i], view, true)
