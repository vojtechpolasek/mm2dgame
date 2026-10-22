extends Node2D

## Den a noc. Celý den (24 hodin hry) trvá DAY_SECONDS. Slunce a měsíc jdou proti sobě po
## jednom kruhu, jehož střed je o HORIZON_DROP poloměru pod obzorem: slunce vyjde vpravo,
## v poledne je nahoře, zapadne vlevo a pomalu klesne pod obzor. Když je celé pod obzorem,
## vychází vpravo měsíc a jde stejnou cestou. Fáze 0 je východ slunce, 0.5 východ měsíce,
## mezi západem jednoho a východem druhého je krátce pod obzorem obojí. Slunce ani měsíc ve
## světě vidět nejsou (pohled shora), jen jejich světlo a stíny. Ukazatel na obzoru je v HUD
## (Hud.set_sky), počítá polohu stejně (angle_of, height_of).
##
## Měsíc má fáze (MOON_PHASES): každou noc vyjde s další, první noc je úplněk. Světlo noci
## a stíny od měsíce sílí s osvětleným podílem měsíce, v novu je jen NEW_MOON_LIGHT světla
## úplňku a skoro tma.
##
## Stíny (Shadows) míří od slunce nebo měsíce, toho, který je výš. Konec stínu jde po
## půlelipse: u obzoru je stín dlouhý Shadows.MAX_LENGTH na metr výšky, v poledne
## NOON_LENGTH (a jen podíl výšky, Shadows.HEIGHT_SHARE). Nízko nad obzorem stín slábne
## a pod obzorem zmizí. Měsíc vrhá slabší stín.
##
## Světlo se kreslí závojem nad objekty i mlhou a pod HUD (night_veil.gdshader), svět se jím
## vynásobí. Den je bílý. Když slunce klesne pod DUSK.y (stíny už jsou dlouhé), světlo slábne
## a teplá, až je slunce celé pod obzorem (DUSK.x), je noc tmavá do modra. Ráno obráceně.
## Měsíc stejně přidává světlo noci podle své výšky. Za soumraku se hráčům rozsvítí
## čelovky: kužel před postavou a slabá záře kolem ní, objekty do výšky čelovky jí stíní.
## Koruny stromů jsou nad čelovkou a zůstanou tmavé.

const Shadows := preload("res://scripts/shadows.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const VEIL_SHADER := preload("res://shaders/night_veil.gdshader")

const DAY_SECONDS := 240.0
## Hra začíná ráno, chvíli po východu slunce. 0 je východ slunce, 0.5 východ měsíce.
const START := 0.08
## Střed kruhu slunce a měsíce pod obzorem, podíl poloměru. Výška nad obzorem je
## sin(úhel) - HORIZON_DROP, nejvýš 1 - HORIZON_DROP.
const HORIZON_DROP := 0.15
## Délka stínu na metr výšky v poledne (u obzoru Shadows.MAX_LENGTH).
const NOON_LENGTH := 0.7
## Krytí stínů od slunce a od úplňku. Stín sílí od výšky SHADOW_RISE.x do SHADOW_RISE.y.
const SUN_SHADOW := 0.34
const MOON_SHADOW := 0.18
const SHADOW_RISE := Vector2(0.0, 0.2)
## Osvětlený podíl měsíce v nocích po sobě, pak znovu od začátku: úplněk, ubývá, nov, přibývá.
const MOON_PHASES: Array[float] = [1.0, 0.75, 0.5, 0.25, 0.0, 0.25, 0.5, 0.75]
## Světlo noci v novu jako podíl světla v úplňku.
const NEW_MOON_LIGHT := 0.1
## Barvy světla. NIGHT je noc v úplňku, DAWN slunce nízko nad obzorem.
const DAY := Color(1.0, 1.0, 1.0)
const DAWN := Color(1.0, 0.8, 0.64)
const NIGHT := Color(0.4, 0.47, 0.72)
## Výška slunce (měsíce), kdy je jeho světlo celé pryč (x, celé pod obzorem i v ukazateli)
## a kdy začne slábnout (y, asi čtvrtina nejvyšší výšky).
const DUSK := Vector2(-0.3, 0.22)
## Do jaké výšky slunce je světlo teplé.
const WARM := 0.4
## Čelovky se rozsvítí, když denní světlo klesne do tohoto rozmezí (podíl dne). Rozsvěcí se
## brzy za soumraku a zhasínají až dlouho po svítání.
const LAMP_DUSK := Vector2(0.6, 0.9)
## Nejvíc čelovek (hráčů). Stejné číslo má night_veil.gdshader.
const MAX_LAMPS := 6
## Závoj je o tolik větší než záběr, ať při rychlém pohybu kamery nevykoukne kraj.
const VEIL_PAD := 0.15
## Nad mlhou a sněhem (SquareAir.Z), pod jmény dolů (PondLabels).
const VEIL_Z := 10

## 0 až 1 přes celý den, viz START.
var phase := START
## Kolik dní uplynulo. Noc dne days má fázi měsíce MOON_PHASES[days % 8].
var days := 0
## Měsíc stále v úplňku (průlet v menu, ať je pozadí čitelné).
var full_moon_only := false
var _shadows: Shadows
var _camera: MapCamera
var _veil: ColorRect
var _veil_material: ShaderMaterial
## Materiály s polohami čelovek (lamp_light.gdshaderinc): závoj a ty ze stínů.
var _lamp_materials: Array[ShaderMaterial] = []
## Postavy hráčů, každá nese čelovku. Pole je ve světě a plní se, až postavy vzniknou.
var _persons: Array


func setup(camera: MapCamera, shadows: Shadows, persons: Array) -> void:
	_camera = camera
	_shadows = shadows
	_persons = persons
	_veil = ColorRect.new()
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil_material = ShaderMaterial.new()
	_veil_material.shader = VEIL_SHADER
	_veil_material.set_shader_parameter("occluders", shadows.occluders())
	_veil_material.set_shader_parameter("lamp_light", shadows.lamp_light())
	_veil.material = _veil_material
	_lamp_materials = [_veil_material]
	_lamp_materials.append_array(shadows.lamp_materials())
	add_child(_veil)
	z_as_relative = false
	z_index = VEIL_Z
	camera.view_changed.connect(_fit_veil)
	_fit_veil()
	_apply()


func advance(delta: float) -> void:
	var before := phase
	phase = fposmod(phase + delta / DAY_SECONDS, 1.0)
	if phase < before:
		days += 1
	_apply()


## Úhel slunce na kruhu ve fázi phase: 0 vpravo, PI / 2 nahoře, PI vlevo. Měsíc je o PI dál.
static func angle_of(at_phase: float) -> float:
	return TAU * at_phase + asin(HORIZON_DROP)


## Výška nad obzorem v poloměrech kruhu pro úhel angle, pod obzorem záporná.
static func height_of(angle: float) -> float:
	return sin(angle) - HORIZON_DROP


## Pořadí fáze měsíce dnešní noci v MOON_PHASES.
func moon_index() -> int:
	return 0 if full_moon_only else posmod(days, MOON_PHASES.size())


## Osvětlený podíl měsíce dnešní noci, 1 úplněk, 0 nov.
func moon_lit() -> float:
	return MOON_PHASES[moon_index()]


func _apply() -> void:
	var sun_angle := angle_of(phase)
	var moon_angle := sun_angle + PI
	var sun := height_of(sun_angle)
	var moon := height_of(moon_angle)
	var lit := moon_lit()
	# Stín od toho, kdo je výš. Při výměně jsou oba nízko a stín je slabý.
	var by_sun := sun >= moon
	var angle := sun_angle if by_sun else moon_angle
	var high := sun if by_sun else moon
	# Konec stínu po půlelipse: u obzoru do strany dlouhý, v poledne nahoru krátký. Stín míří
	# od slunce (měsíce): ráno doleva, v poledne dolů, večer doprava.
	var tip := Vector2(-cos(angle) * Shadows.MAX_LENGTH, maxf(sin(angle), 0.0) * NOON_LENGTH)
	RenderingServer.global_shader_parameter_set(&"sun_shadow", tip * Shadows.TILE * Shadows.HEIGHT_SHARE)
	if _shadows != null:
		var strength := (SUN_SHADOW if by_sun else MOON_SHADOW * lit) * smoothstep(SHADOW_RISE.x, SHADOW_RISE.y, high)
		_shadows.set_strength(strength)
	if _veil == null:
		return
	var daylight := smoothstep(DUSK.x, DUSK.y, sun)
	var moonlight := smoothstep(DUSK.x, DUSK.y, moon) * lit
	var night := NIGHT * lerpf(NEW_MOON_LIGHT, 1.0, moonlight)
	var ambient := night.lerp(DAWN.lerp(DAY, smoothstep(0.0, WARM, sun)), daylight)
	var lamp := 1.0 - smoothstep(LAMP_DUSK.x, LAMP_DUSK.y, daylight)
	_veil_material.set_shader_parameter("ambient", Vector3(ambient.r, ambient.g, ambient.b))
	_set_lamp("lamp_on", lamp)
	if _shadows != null:
		_shadows.set_lamps(lamp > 0.001)
	if lamp > 0.001:
		_aim_lamps()
	# Bílý závoj bez čelovek nic nemění, ve dne se nekreslí.
	_veil.visible = lamp > 0.001 or not ambient.is_equal_approx(DAY)


## Čelovky na hlavách postav: poloha a směr, kam postava hledí.
func _aim_lamps() -> void:
	var lamps: Array[Vector4] = []
	for person: Node2D in _persons:
		if lamps.size() >= MAX_LAMPS:
			break
		if not is_instance_valid(person) or not person.is_inside_tree():
			continue
		var facing := Vector2.from_angle(person.global_rotation - PI * 0.5)
		lamps.append(Vector4(person.global_position.x, person.global_position.y, facing.x, facing.y))
	while lamps.size() < MAX_LAMPS:
		lamps.append(Vector4.ZERO)
	_set_lamp("lamps", lamps)
	var count := 0
	for person: Node2D in _persons:
		if is_instance_valid(person) and person.is_inside_tree():
			count += 1
	_set_lamp("lamp_count", mini(count, MAX_LAMPS))
	var shadows_on := _shadows != null and _shadows.enabled()
	_veil_material.set_shader_parameter("lamp_shadows", 1.0 if shadows_on else 0.0)
	# Obrázek překážek nese i masku korun, ta platí i bez stínů.
	if _shadows != null:
		var rect := _shadows.view_rect()
		_set_lamp("view_origin", rect.position)
		_set_lamp("view_size", rect.size)


func _set_lamp(param: StringName, value: Variant) -> void:
	for made in _lamp_materials:
		made.set_shader_parameter(param, value)


func _fit_veil() -> void:
	if _camera == null or _veil == null:
		return
	var view := _camera.get_viewport_rect().size / maxf(_camera.zoom.x, 0.001)
	var size := view * (1.0 + VEIL_PAD * 2.0)
	_veil.position = _camera.get_screen_center_position() - size * 0.5
	_veil.size = size
