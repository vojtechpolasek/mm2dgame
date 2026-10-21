extends CanvasGroup

## Stíny objektů na zemi od slunce a měsíce. Leží nad terénem, řekou a porostem a pod objekty.
## Každá vrstva objektu nad zemí má tady svůj stín: stejný obrázek se shaderem
## shadow_layer.gdshader, posunutý podle výšky vrstvy a globálního sun_shadow (DayNight).
## Celá skupina se kreslí najednou s krytím strength, překryté stíny tak neztmavnou dvakrát.
##
## Vrstva vrhá stín jen nad zemí (výška > 0). Stín plného tělesa (skála, dům, postava) se
## táhne od vrstvy pod ní, nejspodnější až od země, ať se od paty neodtrhne. Vrstvy koruny
## stromu netáhnou, jejich stíny se jen překrývají a od paty je mezera jako u skutečného
## stromu (sweeps).
##
## Skály a stromy (LayeredProps) mají stíny ve svých zásobnících uzlů, posouvají se s nimi.
## Ostatní (domy, sklady, továrna, postavy, vesničané, příšery) se přihlásí přes follow
## a stín se každý snímek srovná s obrázkem: poloha, natočení, snímek, textura a viditelnost.
## Zaniklý obrázek si stín uklidí sám.

const SHADER := preload("res://shaders/shadow_layer.gdshader")
const TILE := 64.0
## Nejdelší stín v metrech na metr výšky (slunce nízko nad obzorem). Stejné číslo má DayNight.
const MAX_LENGTH := 1.6
## Výšky vrstev jsou nadsazené kvůli posunu při pohybu kamery (strom 12 m). Stín bere jen
## tento podíl výšky, jinak by stromy zakryly stínem půl obrazovky.
const HEIGHT_SHARE := 0.35

## Stíny ve hře, null bez světa. Přihlašují se do nich objekty, které vznikají jinde.
static var current

var _materials := {}
## Sledované obrázky: [zdroj, držák stínu, stín].
var _follow: Array = []


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _process(_delta: float) -> void:
	var i := 0
	while i < _follow.size():
		var entry: Array = _follow[i]
		var source := entry[0] as Sprite2D
		var holder := entry[1] as Node2D
		if not is_instance_valid(source) or not source.is_inside_tree():
			if is_instance_valid(holder):
				holder.queue_free()
			_follow.remove_at(i)
			continue
		var shadow := entry[2] as Sprite2D
		holder.visible = source.is_visible_in_tree()
		if holder.visible:
			holder.global_transform = source.get_global_transform()
			if shadow.texture != source.texture:
				shadow.texture = source.texture
			shadow.frame = source.frame
			shadow.flip_h = source.flip_h
			shadow.flip_v = source.flip_v
		i += 1


## Materiál stínu vrstvy ve výšce height, tah sweep. Vrstvy se stejnými čísly ho sdílejí.
func material(height: float, sweep: float) -> ShaderMaterial:
	var key := Vector2(snappedf(height, 0.001), snappedf(sweep, 0.001))
	if not _materials.has(key):
		var made := ShaderMaterial.new()
		made.shader = SHADER
		made.set_shader_parameter("height_m", height)
		made.set_shader_parameter("sweep_m", sweep)
		_materials[key] = made
	return _materials[key]


## Stín obrázku source pod holder. Kopie obrázku na středu se shaderem stínu. Kreslí se
## i mimo svůj obdélník, o kolik ho stín nejvýš posune.
func shadow_of(source: Sprite2D, height: float, sweep: float, holder: Node2D) -> Sprite2D:
	var shadow := Sprite2D.new()
	shadow.texture = source.texture
	shadow.hframes = source.hframes
	shadow.vframes = source.vframes
	shadow.frame = source.frame
	shadow.region_enabled = source.region_enabled
	shadow.region_rect = source.region_rect
	shadow.centered = true
	shadow.texture_filter = source.texture_filter
	shadow.material = material(height, sweep)
	holder.add_child(shadow)
	var rect := shadow.get_rect()
	var reach := height * TILE * MAX_LENGTH * HEIGHT_SHARE + 8.0
	RenderingServer.canvas_item_set_custom_rect(shadow.get_canvas_item(), true, rect.grow(reach))
	return shadow


## Stíny vrstev sprites ve výškách heights (stejné pořadí), každý snímek za obrázkem.
## solid: plné těleso, stín každé vrstvy se táhne od země (pořadí výšek nevadí). Jinak
## netáhne (sweeps). Vrstvy pod zemí nebo na zemi stín nemají.
func follow(sprites: Array, heights: Array, solid: bool) -> void:
	var sweep := sweeps(heights, false)
	if solid:
		for i in heights.size():
			sweep[i] = maxf(float(heights[i]), 0.0)
	for i in sprites.size():
		var height := float(heights[i])
		var sprite := sprites[i] as Sprite2D
		if sprite == null or height <= 0.0:
			continue
		var holder := Node2D.new()
		add_child(holder)
		var shadow := shadow_of(sprite, height, sweep[i], holder)
		# Sprite s posunem (offset) by stín na středu nesedl: stín je o něj posunutý v držáku.
		shadow.position = sprite.offset if sprite.centered else sprite.offset + sprite.get_rect().size * 0.5
		_follow.append([sprite, holder, shadow])


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
