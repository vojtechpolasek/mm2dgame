extends Node2D

## Stíny objektů na zemi od slunce a měsíce a překážky pro světlo čelovek. Leží nad terénem,
## řekou a porostem a pod objekty.
##
## Kreslí se do obrázků zmenšených proti obrazovce (SubViewport s kamerou za hlavní kamerou):
## stíny a stíny čelovek na čtvrtinu (SHADOW_SCALE), překážky na polovinu (SCALE), obojí ještě
## krát rozlišení světa (Graphics.world_scale). Stíny jsou
## měkké, rozdíl skoro není vidět, a menší obrázek je na slabé grafice mnohem levnější:
## - stíny: každá vrstva objektu nad zemí jako černá silueta (shadow_layer.gdshader), posunutá
##   podle výšky vrstvy a globálního sun_shadow (DayNight). Obrázek se roztáhne přes svět
##   s krytím strength, překryté stíny tak neztmavnou dvakrát.
## - překážky: výška vrstev, které stíní čelovce (occluder_layer.gdshader). Čelovka je ve výšce
##   LAMP_HEIGHT, stíní vrstvy plných těles (skála, dům, příšera) a vrstvy do její výšky (keř).
##   Koruna stromu ne, ta je nad čelovkou: zapíše se jen do masky korun v kanálu G
##   (crown_mask.gdshader) a čelovka ji neosvětlí. Světlo čelovek podle obrázku trasuje
##   paprsky ke čelovkám, noční závoj (DayNight) podle masky nechá koruny tmavé.
## - světlo čelovek: kužely se stíny podle překážek a záře kolem postav (lamp_shade.gdshader),
##   jen kolem čelovek (set_lamp_area), jinde zůstane obrázek prázdný. Noční závoj
##   ho rozmaže a přidá do světla. Kde čelovka svítí, stín od slunce a měsíce slábne
##   (shadow_shown.gdshader).
## Stíny jdou vypnout v nastavení grafiky (Graphics.shadows_on), pak se obrázky stínů nekreslí.
## Obrázek překážek se kreslí, jen když svítí čelovky (set_lamps), bez stínů jen kvůli maskám korun.
##
## Vrstva vrhá stín jen nad zemí (výška > 0). Stín plného tělesa (skála, dům, postava) se
## táhne od vrstvy pod ní, nejspodnější až od země, ať se od paty neodtrhne. Vrstvy koruny
## stromu netáhnou, jejich stíny se jen překrývají a od paty je mezera jako u skutečného
## stromu (sweeps).
##
## Kmen stromu ve hře vidět není (shora ho zakryje koruna), stín ale vrhá a čelovce stíní:
## kolečko menší než pařez, stín se táhne od země ke koruně (trunk).
##
## Skály a stromy (LayeredProps) mají stíny ve svých zásobnících uzlů (holders), posouvají se
## s nimi. Ostatní (domy, sklady, továrna, postavy, vesničané, příšery) se přihlásí přes follow
## a stín se každý snímek srovná s obrázkem: poloha, natočení, snímek, textura a viditelnost.
## Zaniklý obrázek si stín uklidí sám.

const MapCamera := preload("res://scripts/map_camera.gd")
const ObjectLayers := preload("res://scripts/object_layers.gd")
const SHADOW_SHADER := preload("res://shaders/shadow_layer.gdshader")
const OCCLUDER_SHADER := preload("res://shaders/occluder_layer.gdshader")
const CROWN_SHADER := preload("res://shaders/crown_mask.gdshader")
const LAMP_SHADER := preload("res://shaders/lamp_shade.gdshader")
const SHOWN_SHADER := preload("res://shaders/shadow_shown.gdshader")
const TILE := 64.0
## Nejdelší stín v metrech na metr výšky (slunce nízko nad obzorem). Stejné číslo má DayNight.
const MAX_LENGTH := 1.6
## Výšky vrstev jsou nadsazené kvůli posunu při pohybu kamery (strom 12 m). Stín bere jen
## tento podíl výšky, jinak by stromy zakryly stínem půl obrazovky.
const HEIGHT_SHARE := 0.4
## Výška čelovky v metrech. Vyšší vrstvy, které nejsou z plného tělesa, světlo nestíní.
const LAMP_HEIGHT := 1.5
## Výška v obrázku překážek je podíl HEIGHT_RANGE (kanál R má rozsah 0 až 1). Stejné číslo
## mají occluder_layer.gdshader a night_veil.gdshader.
const HEIGHT_RANGE := 16.0
## Obrázek překážek má takový podíl velikosti obrazovky.
const SCALE := 0.5
## Obrázky stínů od slunce a měsíce a stínů čelovek mají takový podíl velikosti obrazovky.
const SHADOW_SCALE := 0.25
## Poloměr kolečka kmene v obrázku (trunk), sprite se zmenší na poloměr kmene.
const DISC_RADIUS := 16

## Stíny ve hře, null bez světa. Přihlašují se do nich objekty, které vznikají jinde.
static var current

var _camera: MapCamera
var _shadow_view: SubViewport
var _shadow_camera: Camera2D
var _occluder_view: SubViewport
var _occluder_camera: Camera2D
var _lamp_view: SubViewport
var _lamp_camera: Camera2D
## Obdélník přes záběr v obrázku stínů čelovek, kreslí ho lamp_shade.gdshader.
var _lamp_rect: ColorRect
## Obrázek stínů roztažený přes záběr hlavní kamery.
var _shown: Sprite2D
var _materials := {}
var _occluder_materials := {}
var _crown_materials := {}
var _disc: ImageTexture
## Sledované obrázky: [zdroj, držáky (stín, překážka), stín, překážka nebo null].
var _follow: Array = []
var _enabled := true
var _lamps := false
## Stíny čelovek, jdou se stíny. Zvlášť je vypíná jen benchmark (set_lamp_shades).
var _lamp_shades := true
## Obdélník světa, kam čelovky dosvítí (set_lamp_area). Jen tam se počítají jejich stíny.
var _lamp_area := Rect2()
var _strength := 0.0


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func setup(camera: MapCamera) -> void:
	_camera = camera
	_shadow_view = _view("ShadowView")
	_shadow_camera = _shadow_view.get_child(0)
	_occluder_view = _view("OccluderView")
	_occluder_camera = _occluder_view.get_child(0)
	# Až po překážkách, ze kterých čte.
	_lamp_view = _view("LampView")
	_lamp_camera = _lamp_view.get_child(0)
	_lamp_rect = ColorRect.new()
	var lamp_material := ShaderMaterial.new()
	lamp_material.shader = LAMP_SHADER
	lamp_material.set_shader_parameter("occluders", occluders())
	_lamp_rect.material = lamp_material
	_lamp_view.add_child(_lamp_rect)
	_shown = Sprite2D.new()
	_shown.texture = _shadow_view.get_texture()
	_shown.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var shown_material := ShaderMaterial.new()
	shown_material.shader = SHOWN_SHADER
	shown_material.set_shader_parameter("lamp_light", lamp_light())
	_shown.material = shown_material
	add_child(_shown)
	camera.view_changed.connect(_fit)
	_fit()
	Graphics.changed.connect(_apply_setting)
	_apply_setting()


## Krytí stínů od slunce nebo měsíce, 0 je bez stínů.
func set_strength(strength: float) -> void:
	_strength = strength
	# Stín břehu řek (river.gdshader) má stejnou sílu.
	RenderingServer.global_shader_parameter_set(&"shadow_opacity", strength if _enabled else 0.0)
	_shown.modulate = Color(1.0, 1.0, 1.0, strength)
	_shown.visible = _enabled and strength > 0.001


func enabled() -> bool:
	return _enabled


## Kreslí se stíny čelovek? Bez nich svítí kužel celý (night_veil.gdshader).
func lamp_shades_on() -> bool:
	return _enabled and _lamp_shades


## Obdélník světa, kam čelovky dosvítí. Stíny čelovek se trasují jen v něm.
func set_lamp_area(area: Rect2) -> void:
	_lamp_area = area
	_place_lamp_rect()


## Vypne nebo zapne jen stíny čelovek, stíny od slunce a měsíce zůstanou (benchmark).
func set_lamp_shades(on: bool) -> void:
	_lamp_shades = on
	_apply_setting()


## Svítí čelovky? Jen pak se kreslí obrázek překážek a korun.
func set_lamps(on: bool) -> void:
	if on == _lamps:
		return
	_lamps = on
	_apply_setting()


## Obrázek výšek překážek pro čelovky.
func occluders() -> Texture2D:
	return _occluder_view.get_texture()


## Obrázek kuželů čelovek se stíny (lamp_shade.gdshader).
func lamp_light() -> Texture2D:
	return _lamp_view.get_texture()


## Materiály, které potřebují polohy čelovek (lamp_light.gdshaderinc), kromě nočního závoje.
func lamp_materials() -> Array[ShaderMaterial]:
	return [_lamp_rect.material as ShaderMaterial, _shown.material as ShaderMaterial]


## Obdélník světa, který pokrývají obrázky stínů a překážek.
func view_rect() -> Rect2:
	var size := _view_size()
	return Rect2(_camera.get_screen_center_position() - size * 0.5, size)


func _view(view_name: String) -> SubViewport:
	var view := SubViewport.new()
	view.name = view_name
	view.transparent_bg = true
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var camera := Camera2D.new()
	view.add_child(camera)
	camera.make_current()
	return view


func _view_size() -> Vector2:
	return _camera.get_viewport_rect().size / maxf(_camera.zoom.x, 0.001)


## Obrázky drží záběr hlavní kamery, zmenšený o SHADOW_SCALE (stíny) a SCALE (ostatní) a
## o rozlišení světa.
func _fit() -> void:
	if _camera == null:
		return
	var screen := _camera.get_viewport_rect().size
	var center := _camera.get_screen_center_position()
	var shadow_pixels := Vector2i.ONE
	for row: Array in [[_shadow_view, _shadow_camera, SHADOW_SCALE], [_occluder_view, _occluder_camera, SCALE], [_lamp_view, _lamp_camera, SHADOW_SCALE]]:
		var view: SubViewport = row[0]
		var camera: Camera2D = row[1]
		var share: float = row[2] * Graphics.world_scale()
		var pixels := Vector2i(maxi(int(screen.x * share), 1), maxi(int(screen.y * share), 1))
		if view == _shadow_view:
			shadow_pixels = pixels
		if view.size != pixels:
			view.size = pixels
		camera.position = center
		camera.zoom = _camera.zoom * share
		camera.force_update_scroll()
	_shown.position = center
	_shown.scale = Vector2.ONE * _view_size().x / float(shadow_pixels.x)
	_place_lamp_rect()


## Obdélník trasování stínů čelovek: záběr oříznutý na dosah čelovek.
func _place_lamp_rect() -> void:
	if _camera == null:
		return
	var area := view_rect().intersection(_lamp_area)
	_lamp_rect.visible = area.has_area()
	if _lamp_rect.visible:
		_lamp_rect.position = area.position
		_lamp_rect.size = area.size


func _apply_setting() -> void:
	_enabled = Graphics.shadows_on()
	_fit()
	_shadow_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _enabled else SubViewport.UPDATE_DISABLED
	_occluder_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _lamps else SubViewport.UPDATE_DISABLED
	# Obrázek světla čelovek se kreslí vždy, když svítí, stíny v něm jsou podle lamp_shades_on.
	_lamp_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _lamps else SubViewport.UPDATE_DISABLED
	set_strength(_strength)


func _process(_delta: float) -> void:
	var i := 0
	while i < _follow.size():
		var entry: Array = _follow[i]
		var into: Array = entry[1]
		# Uvolněný objekt se nesmí ani přetypovat.
		if not is_instance_valid(entry[0]) or not (entry[0] as Sprite2D).is_inside_tree():
			for holder: Node2D in into:
				if is_instance_valid(holder):
					holder.queue_free()
			_follow.remove_at(i)
			continue
		var source := entry[0] as Sprite2D
		var shown := source.is_visible_in_tree()
		var at := source.get_global_transform()
		for holder: Node2D in into:
			holder.visible = shown
			if shown:
				holder.global_transform = at
		if shown:
			for k in range(2, 4):
				var copy := entry[k] as Sprite2D
				if copy == null:
					continue
				if copy.texture != source.texture:
					copy.texture = source.texture
				copy.frame = source.frame
				copy.flip_h = source.flip_h
				copy.flip_v = source.flip_v
		i += 1


## Nové držáky jednoho objektu: [stín, překážka]. Posouvá je ten, kdo je vytvořil.
func holders() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for view: SubViewport in [_shadow_view, _occluder_view]:
		var holder := Node2D.new()
		view.add_child(holder)
		out.append(holder)
	return out


## Stín a překážka vrstvy source ve výšce height pod into (viz holders). Stín se táhne
## o sweep metrů dolů (sweeps). Překážka jen když blocks_lamp: u plného tělesa (solid) nebo
## do výšky čelovky výška, výš (koruna) maska koruny. Vrátí [stín, překážka nebo maska],
## druhá může být null.
func cast(source: Sprite2D, height: float, sweep: float, solid: bool, blocks_lamp: bool, into: Array[Node2D]) -> Array:
	var shadow := _copy(source, _material(height, sweep), into[0])
	var reach := height * TILE * MAX_LENGTH * HEIGHT_SHARE + 8.0
	RenderingServer.canvas_item_set_custom_rect(shadow.get_canvas_item(), true, shadow.get_rect().grow(reach))
	var occluder: Sprite2D = null
	if blocks_lamp and (solid or height <= LAMP_HEIGHT):
		occluder = _copy(source, _occluder_material(height, ObjectLayers.PARALLAX), into[1])
	elif blocks_lamp:
		occluder = _copy(source, _crown_material(height), into[1])
	if occluder != null:
		# Vyšší vrstva se kreslí přes nižší, v obrázku zůstane nejvyšší výška.
		occluder.z_index = clampi(int(height * 10.0), 0, 4000)
		RenderingServer.canvas_item_set_custom_rect(occluder.get_canvas_item(), true, occluder.get_rect().grow(256.0))
	return [shadow, occluder]


## Kmen stromu pod into (viz holders): sloupek o poloměru radius px od země do výšky height m.
## Stín se táhne celou výšku, překážka stojí na zemi (bez posunu výšky) a stíní celou výškou.
func trunk(radius: float, height: float, into: Array[Node2D]) -> void:
	var made := [_disc_copy(_material(height, height), into[0], radius), _disc_copy(_occluder_material(height, 0.0), into[1], radius)]
	var shadow := made[0] as Sprite2D
	var reach := height * TILE * MAX_LENGTH * HEIGHT_SHARE / shadow.scale.x + 8.0
	RenderingServer.canvas_item_set_custom_rect(shadow.get_canvas_item(), true, shadow.get_rect().grow(reach))
	# Kmeny se kreslí až po ostatních stínech všechny za sebou, se stejnou texturou v jedné dávce.
	shadow.z_index = 1
	var occluder := made[1] as Sprite2D
	occluder.z_index = clampi(int(height * 10.0), 0, 4000)


func _disc_copy(made: ShaderMaterial, holder: Node2D, radius: float) -> Sprite2D:
	if _disc == null:
		var side := DISC_RADIUS * 2
		var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
		for y in side:
			for x in side:
				var inside := Vector2(x + 0.5 - DISC_RADIUS, y + 0.5 - DISC_RADIUS).length() <= float(DISC_RADIUS)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0 if inside else 0.0))
		_disc = ImageTexture.create_from_image(image)
	var copy := Sprite2D.new()
	copy.texture = _disc
	copy.scale = Vector2.ONE * radius / float(DISC_RADIUS)
	copy.material = made
	holder.add_child(copy)
	return copy


## Stíny vrstev sprites ve výškách heights (stejné pořadí), každý snímek za obrázkem.
## solid: plné těleso, stín každé vrstvy se táhne od země (pořadí výšek nevadí). Jinak
## netáhne (sweeps). blocks_lamp: stíní čelovkám (postava ne, ta čelovku nese).
## Vrstvy pod zemí nebo na zemi stín nemají.
func follow(sprites: Array, heights: Array, solid: bool, blocks_lamp := true) -> void:
	var sweep := sweeps(heights, false)
	if solid:
		for i in heights.size():
			sweep[i] = maxf(float(heights[i]), 0.0)
	for i in sprites.size():
		var height := float(heights[i])
		var sprite := sprites[i] as Sprite2D
		if sprite == null or height <= 0.0:
			continue
		var into := holders()
		var made := cast(sprite, height, sweep[i], solid, blocks_lamp, into)
		# Sprite s posunem (offset) by na středu nesedl: kopie je o něj posunutá v držáku.
		var shift := sprite.offset if sprite.centered else sprite.offset + sprite.get_rect().size * 0.5
		for copy in made:
			if copy != null:
				(copy as Sprite2D).position = shift
		if made[1] == null:
			into[1].queue_free()
			into.remove_at(1)
		_follow.append([sprite, into, made[0], made[1]])


## Tah stínu vrstev o výškách heights seřazených odspodu. Plné těleso (solid): každá vrstva
## od vrstvy pod sebou, nejspodnější nad zemí od země. Jinak žádný tah.
static func sweeps(heights: Array, solid: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var below := 0.0
	for height: float in heights:
		if height <= 0.0 or not solid:
			out.append(0.0)
			continue
		out.append(maxf(height - below, 0.0))
		below = height
	return out


## Kopie obrázku na středu s materiálem made pod holder.
func _copy(source: Sprite2D, made: ShaderMaterial, holder: Node2D) -> Sprite2D:
	var copy := Sprite2D.new()
	copy.texture = source.texture
	copy.hframes = source.hframes
	copy.vframes = source.vframes
	copy.frame = source.frame
	copy.region_enabled = source.region_enabled
	copy.region_rect = source.region_rect
	copy.centered = true
	copy.texture_filter = source.texture_filter
	copy.material = made
	holder.add_child(copy)
	return copy


## Materiál stínu vrstvy ve výšce height, tah sweep. Vrstvy se stejnými čísly ho sdílejí.
func _material(height: float, sweep: float) -> ShaderMaterial:
	var key := Vector2(snappedf(height, 0.001), snappedf(sweep, 0.001))
	if not _materials.has(key):
		var made := ShaderMaterial.new()
		made.shader = SHADOW_SHADER
		made.set_shader_parameter("height_m", height)
		made.set_shader_parameter("sweep_m", sweep)
		_materials[key] = made
	return _materials[key]


## Materiál masky koruny ve výšce height (crown_mask.gdshader).
func _crown_material(height: float) -> ShaderMaterial:
	var key := snappedf(height, 0.001)
	if not _crown_materials.has(key):
		var made := ShaderMaterial.new()
		made.shader = CROWN_SHADER
		made.set_shader_parameter("height_m", height)
		_crown_materials[key] = made
	return _crown_materials[key]


## Materiál překážky ve výšce height. parallax posouvá jako vrstvu ve hře, kmen má 0.
func _occluder_material(height: float, parallax: float) -> ShaderMaterial:
	var key := Vector2(snappedf(height, 0.001), parallax)
	if not _occluder_materials.has(key):
		var made := ShaderMaterial.new()
		made.shader = OCCLUDER_SHADER
		made.set_shader_parameter("height_m", height)
		made.set_shader_parameter("parallax", parallax)
		_occluder_materials[key] = made
	return _occluder_materials[key]
