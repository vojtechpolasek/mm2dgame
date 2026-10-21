extends Node2D

## Den a noc. Celý den (24 hodin hry) trvá DAY_SECONDS. První půlka je den: slunce vyjde
## vpravo uprostřed (východ), obloukem přes horní stranu obrazovky dojde v poledne nejvýš
## a zapadne přesně vlevo. V tu chvíli vpravo vychází měsíc a druhou půlku jde stejnou cestou.
## Slunce ani měsíc ve světě vidět nejsou (pohled shora), jen jejich světlo a stíny. Ukazatel
## na obzoru je v HUD (Hud.set_sky).
##
## Stíny (Shadows) míří od slunce nebo měsíce. Délka na metr výšky je cotangens jeho výšky nad
## obzorem, nejvýš Shadows.MAX_LENGTH (a jen podíl výšky, Shadows.HEIGHT_SHARE): ráno a večer
## dlouhé, v poledne krátké. U obzoru stín
## slábne a mizí, ať se při západu nepřeklopí naráz na druhou stranu. Měsíc vrhá slabší stín.
## Barva světla: den bílý, u obzoru teplý, noc tmavá do modra. Celý svět se jí vynásobí
## (závoj nad objekty i mlhou, pod HUD). V noci zůstane dost světla, ať jde hrát.

const Shadows := preload("res://scripts/shadows.gd")
const MapCamera := preload("res://scripts/map_camera.gd")

const DAY_SECONDS := 240.0
## Hra začíná ráno, kousek po východu slunce. 0 je východ slunce, 0.5 východ měsíce.
const START := 0.06
## Nejvyšší výška slunce i měsíce nad obzorem v poledne a o půlnoci, v radiánech (55°).
const TOP_ELEVATION := 0.96
## Krytí stínů od slunce a od měsíce. Kolik podílu oblouku od obzoru stín sílí.
const SUN_SHADOW := 0.34
const MOON_SHADOW := 0.18
const SHADOW_RISE := 0.12
## Barvy světla. Za soumraku se den mění v noc, dokud je slunce kousek pod obzorem.
const DAY := Color(1.0, 1.0, 1.0)
const DAWN := Color(1.0, 0.8, 0.64)
const NIGHT := Color(0.4, 0.47, 0.72)
const TWILIGHT := Vector2(-0.06, 0.08)
const WARM := 0.35
## Závoj je o tolik větší než záběr, ať při rychlém pohybu kamery nevykoukne kraj.
const VEIL_PAD := 0.15
## Nad mlhou a sněhem (SquareAir.Z), pod jmény dolů (PondLabels).
const VEIL_Z := 10

## 0 až 1 přes celý den, viz START.
var phase := START
var _shadows: Shadows
var _camera: MapCamera
var _veil: ColorRect


func setup(camera: MapCamera, shadows: Shadows) -> void:
	_camera = camera
	_shadows = shadows
	_veil = ColorRect.new()
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_veil.material = multiply
	add_child(_veil)
	z_as_relative = false
	z_index = VEIL_Z
	camera.view_changed.connect(_fit_veil)
	_fit_veil()
	_apply()


func advance(delta: float) -> void:
	phase = fposmod(phase + delta / DAY_SECONDS, 1.0)
	_apply()


## Je den (slunce nad obzorem)?
func is_day() -> bool:
	return phase < 0.5


## Kde je slunce nebo měsíc na oblouku: 0 vychází vpravo, 0.5 nahoře, 1 zapadá vlevo.
func arc() -> float:
	return fposmod(phase * 2.0, 1.0)


func _apply() -> void:
	var along := arc()
	var lift := sin(PI * along)
	# Směr ke slunci (měsíci) na obrazovce: vpravo, nahoru, vlevo. Stín míří opačně.
	var toward := Vector2(cos(PI * along), -sin(PI * along))
	var elevation := maxf(TOP_ELEVATION * lift, 0.01)
	var length := minf(1.0 / tan(elevation), Shadows.MAX_LENGTH)
	RenderingServer.global_shader_parameter_set(&"sun_shadow", -toward * length * Shadows.TILE * Shadows.HEIGHT_SHARE)
	if _shadows != null:
		var strength := (SUN_SHADOW if is_day() else MOON_SHADOW) * smoothstep(0.0, SHADOW_RISE, lift)
		_shadows.self_modulate = Color(1.0, 1.0, 1.0, strength)
		_shadows.visible = strength > 0.001
	if _veil != null:
		var sun := sin(TAU * phase)
		var light := smoothstep(TWILIGHT.x, TWILIGHT.y, sun)
		_veil.color = NIGHT.lerp(DAWN.lerp(DAY, smoothstep(0.0, WARM, sun)), light)
		# Bílý závoj nic nemění, ve dne se nekreslí.
		_veil.visible = not _veil.color.is_equal_approx(DAY)


func _fit_veil() -> void:
	if _camera == null or _veil == null:
		return
	var view := _camera.get_viewport_rect().size / maxf(_camera.zoom.x, 0.001)
	var size := view * (1.0 + VEIL_PAD * 2.0)
	_veil.position = _camera.get_screen_center_position() - size * 0.5
	_veil.size = size
