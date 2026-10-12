extends Node2D

## Továrna uprostřed mapy. Spodek leží na zemi, mezikruží nad ním se celou hru pomalu otáčí.
## Hozený kámen dopadne na vnější konec nejbližšího pásu, pás ho odveze pod mezikruží a tam se
## kámen započítá a zmizí. Uprostřed zůstane létat prach v barvě materiálu. Každý materiál
## má své řídké mračno, třpytivý k tomu pár jisker. Míry z tovarna.json jsou v px od středu
## obrázku, jih (+y) je výstupek.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const Crystal := preload("res://scripts/crystal.gd")
const MapCamera := preload("res://scripts/map_camera.gd")

## Kámen dojel pod mezikruží. world je místo, kde zmizel.
signal counted(mat: int, world: Vector2)

## Jedna otáčka mezikruží za tolik sekund.
const RING_PERIOD := 60.0
## Pás jede tolik metrů za sekundu. Kámen po dopadu chvíli leží, než se rozjede.
const BELT_METERS := 0.42
const BELT_DELAY := 0.2
## Kámen dopadne kousek za hnací válec, ne přes okraj.
const DROP_PAST_DRUM := 8.0
## Prach zůstane v dvoře. Na materiál je DUST_AMOUNT zrnek, oběhnou střed tolikrát za sekundu.
## Jiskry přibývají s třpytivostí materiálu, nejvýš SPARKS_MAX.
const DUST_AMOUNT := 8
const DUST_LIFE := 6.0
const DUST_ORBIT := Vector2(0.16, 0.42)
const SPARKS_MAX := 3
const SPEC_PX := 16

var _crystal: Crystal
var _camera: MapCamera
var _base: Sprite2D
var _ring: Sprite2D
var _riders: Node2D
var _dust: Node2D
var _base_material: ShaderMaterial
var _ring_height := 0.0
var _belts := PackedInt32Array()
var _belt_inner := 0.0
var _belt_half := 0.0
var _drum := 0.0
var _ring_reach := 0.0
var _yard := 0.0
## Posun příček každého pásu v px. Roste jen u pásu, po kterém zrovna jede kámen.
var _shift := PackedFloat32Array()
## Kameny na pásech: [sprite, pás, vzdálenost od středu, zbývající čekání, materiál].
var _rides: Array = []
var _speck: Texture2D
## Materiály, jejichž prach už ve dvoře létá.
var _dust_mats := {}


func setup(info: Dictionary, base: Texture2D, ring: Texture2D, shader: Shader, crystal: Crystal, camera: MapCamera) -> void:
	_crystal = crystal
	_camera = camera
	var layers: Dictionary = info.get("layers", {})
	var belts: Dictionary = info.get("conveyors", {})
	for angle: Variant in belts.get("angles", []):
		_belts.append(int(angle))
	_belt_inner = float(belts.get("inner_px", 115.0))
	_belt_half = float(belts.get("half_px", 19.0))
	_drum = float(belts.get("drum_px", 171.0))
	var ring_px: Dictionary = info.get("ring_px", {})
	_ring_reach = float(ring_px.get("teeth", 127.0))
	_yard = float(ring_px.get("inner", 69.0))
	_shift.resize(8)
	var base_info: Dictionary = layers.get("base", {})
	var ring_info: Dictionary = layers.get("ring", {})
	_ring_height = float(ring_info.get("height", 1.6))
	_base_material = _material(shader, info, base_info, 0.0)
	_base_material.set_shader_parameter("belts", true)
	_base_material.set_shader_parameter("cell_px", float(base.get_width()))
	_base_material.set_shader_parameter("belt_inner", _belt_inner)
	_base_material.set_shader_parameter("belt_outer", float(belts.get("outer_px", 199.0)))
	_base_material.set_shader_parameter("belt_half", _belt_half)
	_base_material.set_shader_parameter("belt_rail", float(belts.get("rail_px", 3.0)))
	_base_material.set_shader_parameter("belt_pitch", float(belts.get("pitch_px", 12.3)))
	_base_material.set_shader_parameter("belt_slat", float(belts.get("slat_px", 2.4)))
	_base_material.set_shader_parameter("slat_gain", float(belts.get("slat_gain", 2.33)))
	_base_material.set_shader_parameter("drum_at", _drum)
	_base_material.set_shader_parameter("drum_half", float(belts.get("drum_half_px", 4.5)))
	_base_material.set_shader_parameter("belt_shift", _shift)
	_base = _sprite(base, _base_material)
	_riders = Node2D.new()
	add_child(_riders)
	_dust = Node2D.new()
	add_child(_dust)
	_ring = _sprite(ring, _material(shader, info, ring_info, _ring_height))
	# Mezikruží je nad postavou, spodek pod ní.
	_ring.z_index = 2
	_speck = _make_speck()
	camera.view_changed.connect(_fit)
	_fit()


func _process(delta: float) -> void:
	if _ring == null:
		return
	_ring.rotation = fposmod(_ring.rotation + TAU / RING_PERIOD * delta, TAU)
	if _rides.is_empty():
		return
	var speed := BELT_METERS * float(TerrainCatalog.TILE_SIZE) * delta
	var moving := {}
	var end := _ring_reach - _crystal.radius()
	for i in range(_rides.size() - 1, -1, -1):
		var ride: Array = _rides[i]
		var wait := float(ride[3])
		if wait > 0.0:
			ride[3] = wait - delta
			continue
		var belt := int(ride[1])
		moving[belt] = true
		var along := float(ride[2]) - speed
		ride[2] = along
		var sprite := ride[0] as Sprite2D
		var dir := _belt_dir(belt)
		sprite.position = dir * along + dir.orthogonal() * dir.orthogonal().dot(sprite.position)
		if along <= end:
			_rides.remove_at(i)
			var world := to_global(sprite.position)
			sprite.queue_free()
			_swirl(int(ride[4]))
			counted.emit(int(ride[4]), world)
	if moving.is_empty():
		return
	for belt: int in moving:
		_shift[belt] = fposmod(_shift[belt] + speed, 4096.0)
	_base_material.set_shader_parameter("belt_shift", _shift)


## Místo ve světě, kam dopadne kámen hozený od from: vnější konec nejbližšího pásu.
func belt_drop(from: Vector2, rng: RandomNumberGenerator) -> Vector2:
	var belt := _nearest_belt(to_local(from))
	var dir := _belt_dir(belt)
	var side := rng.randf_range(-1.0, 1.0) * maxf(_belt_half * 0.3, 1.0)
	return to_global(dir * (_drum + DROP_PAST_DRUM) + dir.orthogonal() * side)


## Kámen dopadl na pás. Odjede pod mezikruží, tam se započítá.
func receive(mat: int, world: Vector2, rot: float) -> void:
	var local := to_local(world)
	var belt := _nearest_belt(local)
	var sprite := _crystal.make_sprite()
	_riders.add_child(sprite)
	sprite.position = local
	sprite.rotation = rot - global_rotation
	_crystal.paint(sprite, mat, 0.0, rot)
	_rides.append([sprite, belt, local.dot(_belt_dir(belt)), BELT_DELAY, mat])


func _belt_dir(belt: int) -> Vector2:
	return Vector2.from_angle(float(belt) * PI * 0.25)


## Pás nejblíž směru local od středu. Výstupek pás nemá, bere se bližší soused.
func _nearest_belt(local: Vector2) -> int:
	var best := _belts[0] if not _belts.is_empty() else 0
	var best_gap := INF
	for belt in _belts:
		var gap := absf(angle_difference(local.angle(), float(belt) * PI * 0.25))
		if gap < best_gap:
			best_gap = gap
			best = belt
	return best


## Prach v barvě materiálu zůstane kroužit uprostřed. Další hod téhož materiálu už mračno
## nepřidá. Třpytivý materiál k tomu má pár jisker, které blikají.
func _swirl(mat: int) -> void:
	if _dust_mats.has(mat):
		return
	_dust_mats[mat] = true
	var color := _crystal.color_of(mat)
	var cloud := _particles(DUST_AMOUNT, Vector2(0.35, 0.85))
	# Tmavší i světlejší zrnka, ať je prach vidět i na skladu podobné barvy.
	var shades := Gradient.new()
	shades.set_color(0, color.darkened(0.5))
	shades.set_color(1, color.lightened(0.4))
	cloud.color_initial_ramp = shades
	cloud.color_ramp = _fade([0.7, 0.95, 0.8, 0.9])
	var sparkle := _crystal.sparkle_of(mat)
	if sparkle <= 0.001:
		return
	var sparks := mini(maxi(roundi(sparkle * 6.0), 1), SPARKS_MAX)
	var glints := _particles(sparks, Vector2(0.18, 0.4))
	glints.color = _crystal.glint_of(mat).lightened(0.3)
	glints.color_ramp = _fade([0.0, 1.0, 0.1, 0.85, 0.0, 0.7, 0.15, 0.9])


## Zrnek je málo a létají pořád. Oběh drží uvnitř dvora, tlumení je nechá v pohybu.
func _particles(amount: int, size: Vector2) -> CPUParticles2D:
	var cloud := CPUParticles2D.new()
	cloud.texture = _speck
	cloud.amount = amount
	cloud.lifetime = DUST_LIFE
	cloud.one_shot = false
	cloud.preprocess = DUST_LIFE
	cloud.explosiveness = 0.15
	cloud.randomness = 0.6
	cloud.local_coords = true
	cloud.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	cloud.emission_sphere_radius = _yard * 0.72
	cloud.spread = 180.0
	cloud.gravity = Vector2.ZERO
	cloud.initial_velocity_min = 6.0
	cloud.initial_velocity_max = 18.0
	cloud.orbit_velocity_min = DUST_ORBIT.x
	cloud.orbit_velocity_max = DUST_ORBIT.y
	cloud.radial_accel_min = -4.0
	cloud.radial_accel_max = -0.5
	cloud.damping_min = 0.4
	cloud.damping_max = 1.4
	cloud.scale_amount_min = size.x
	cloud.scale_amount_max = size.y
	cloud.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_dust.add_child(cloud)
	cloud.emitting = true
	return cloud


## Průhlednost po dobu života. Body jsou rozložené rovnoměrně od zrodu do konce.
static func _fade(alphas: Array) -> Gradient:
	var ramp := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in alphas.size():
		offsets.append(float(i) / float(alphas.size() - 1))
		colors.append(Color(1.0, 1.0, 1.0, float(alphas[i])))
	ramp.offsets = offsets
	ramp.colors = colors
	return ramp


## Měkká tečka, bílá uprostřed a do kraje průhledná. Barvu dodají částice.
static func _make_speck() -> Texture2D:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = ramp
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = SPEC_PX
	texture.height = SPEC_PX
	return texture


func _material(shader: Shader, info: Dictionary, layer: Dictionary, height: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("height_m", height)
	material.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
	var colors: Array = layer.get("colors", [])
	var slots := ["color_r", "color_g", "color_b"]
	for i in mini(colors.size(), slots.size()):
		material.set_shader_parameter(slots[i], Color.html(str(colors[i])))
	var shade: Array = info.get("shade", [0.42, 1.1])
	var sheen: Array = info.get("sheen", [0.16, 0.7])
	material.set_shader_parameter("shade", Vector2(float(shade[0]), float(shade[1])))
	material.set_shader_parameter("shade_floor", float(info.get("shade_floor", 0.2)))
	material.set_shader_parameter("sheen", Vector2(float(sheen[0]), float(sheen[1])))
	return material


func _sprite(texture: Texture2D, material: ShaderMaterial) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.material = material
	add_child(sprite)
	return sprite


## Posun výšky vytáhne mezikruží z obdélníku spritu. Bez širšího obdélníku by ho kraj
## obrazovky ořízl dřív, než zmizí.
func _fit() -> void:
	if _ring == null or _camera == null:
		return
	var view := _camera.get_viewport_rect().size
	var rect := _ring.get_rect()
	RenderingServer.canvas_item_set_custom_rect(_ring.get_canvas_item(), true, rect.grow(ObjectLayers.vertex_pad(view, _ring_height)))
