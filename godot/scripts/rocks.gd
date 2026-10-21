extends "res://scripts/layered_props.gd"

const Crystal := preload("res://scripts/crystal.gd")

## Varianta bez obrysu v katalogu bere kruh o tolik větší než jmenovitá pata.
const FOOT_MARGIN := 1.4
## Do této výšky je skála pod postavou a jde přeskočit. Vyšší je nad ní.
const LOW := 1.5
## Důl materiálu. Nesází se podle povrchu, má ho jen čtverec s továrnou.
const MINE := "dul"
const MINE_SHADER := "res://shaders/mine_layer.gdshader"
## Volný kruh kolem továrny v metrech. Hráč se objeví u továrny a má kudy projít.
const POND_CLEAR := 10.0
## Nejmenší vzdálenost středů dvou dolů v metrech. Důl má průměr asi 2 m.
const POND_GAP := 7.0
## O kolik pixelů dřív než o obrys se bere dotek postavy.
const TOUCH_PX := 2.0
## Lávová puklina: vrstvy pod zemí jako důl, žár pulzuje. Svit vrstev od okraje ke dnu.
const CRACK_SHADER := "res://shaders/crack_layer.gdshader"
const CRACK_GLOW: Array[float] = [0.35, 0.6, 1.0]
## Nejdelší posun vrstvy pukliny v px. O tolik hlubší vrstvy sahají pod kůru, viz MAX_SHIFT
## v gen_crack.py.
const CRACK_MAX_SHIFT := 22.0
## Barvy skal na mapě, viz paint_chart.
const CHART_ROCK := Color(0.55, 0.53, 0.5)
const CHART_CRACK := Color(0.85, 0.36, 0.12)
const CHART_LOG := Color(0.33, 0.24, 0.17)
## Puklina drží od skal, padlých stromů a jiných puklin tolik metrů po celé délce, ať jde obejít.
const CRACK_GAP_M := 2.0
## Krok kontroly místa podél kapslí pukliny v px.
const CRACK_STEP := 12.0

var _radius := PackedFloat32Array()
## Výška vrcholu skály v metrech. Nízké jdou přeskočit.
var _top := PackedFloat32Array()
## Největší dosah paty. Podle něj se při běhu hledá jen pár buněk mřížky, ne všechny skály.
var _foot := 0.0
## Obrys paty z rocks.json: dosah od středu v px pro každý směr a variantu. Směr 0 míří doprava
## a roste po směru hodin jako Vector2.angle(). Druh začíná na _outline_at a má _steps směrů na variantu.
var _outline := PackedFloat32Array()
var _outline_at := PackedInt32Array()
var _steps := PackedInt32Array()
## Obrys rozšířený o tělo: kam až smí střed těla. Postava i příšery mají různá těla, tabulka
## se pro každé spočítá jednou a pamatuje se. _bound je ta pro tělo _bound_body.
var _bound := PackedFloat32Array()
var _bound_body := -1.0
var _bounds := {}
## Největší dosah obrysu každého druhu. Vzdálené dvojice se podle něj odbudou bez hledání v obrysu.
var _kind_foot := PackedFloat32Array()
## Ležící kmen (padlý strom) nemá obrys po paprscích, ten by postavu u dlouhého kmene smýkl
## podél něj ke konci. Má kapsli: úsečku od pařezu ke koruně, poloměr se podél ní zužuje.
## Puklina má kapslí několik podél praskliny.
## Kapsle jsou po šesticích v souřadnicích obrázku od středu: ax, ay, bx, by, ra, rb.
## _capsule_rows má pro každou variantu dvojici: první kapsle v _capsule a jejich počet.
## _capsule_at je začátek druhu v _capsule_rows, -1 u druhu bez kapslí.
var _capsule := PackedFloat32Array()
var _capsule_rows := PackedInt32Array()
var _capsule_at := PackedInt32Array()
## Natočení a varianta pukliny vybrané při kontrole místa. _keep je pak použije.
var _shaped_kind := -1
var _shaped_variant := 0
var _shaped_turn := 0.0
var _crystal: Crystal
var _material_count := 0
## Body materiálů a jejich pořadí od nejběžnějšího. Sázení je čte ve vlákně.
var _points := PackedInt32Array()
var _by_points := PackedInt32Array()
## Mezi kolika nejlevnějšími materiály jsou ty, které mají na mapě důl. Záporné jsou všechny.
var _available := -1
## Druh dolu, -1 když v katalogu chybí.
var _pond_kind := -1
## Materiál vrstvy dolu podle [druh, vrstva, materiál]. Barvu dolu dává materiál, ne uzel.
var _mine_materials := {}
var _mine_shader: Shader
## U každé skály číslo dolu, nebo -1. Dál už jen doly: skála a materiál.
var _pond_slot := PackedInt32Array()
var _pond_rock := PackedInt32Array()
var _pond_mat := PackedInt32Array()
## Střed dolu neblíž ke kraji mapy než tolik metrů. Ústí dolu zůstane na mapě.
var edge_guard := 2.0
## Počet dolů každého materiálu od nejlevnějšího. Nastaví svět.
var mine_plan := PackedInt32Array()
## Pás dolů jednoho materiálu kolem továrny je široký nejvýš tolik metrů. Záporné nechá
## pásy roztáhnout po celé mapě.
var band_max := -1.0


## Továrna, cesta a domy (town) už stojí. Nejdřív doly kolem továrny, podle nich sklady
## (jen když je town chce), potom skály podle povrchu. Stromy se sází až potom. Nesahá
## na scénu, smí běžet ve vlákně.
func plant(map: MapData, rng: RandomNumberGenerator) -> void:
	_pond_kind = int(_kind_of[MINE]) if _kind_of.has(MINE) else -1
	if _kinds.is_empty():
		return
	_begin_plant(map)
	_place_ponds(map, rng)
	if town != null and town.stores:
		var mines := PackedVector2Array()
		for index in _pond_rock:
			mines.append(_pos[index])
		town.plan_stores(map, rng, mines, _kind_foot[_pond_kind] if _pond_kind >= 0 else 0.0)
	_scatter(map, rng)


func bind_crystal(crystal: Crystal) -> void:
	_crystal = crystal
	_material_count = crystal.count()
	_points.resize(_material_count)
	var order: Array[int] = []
	for index in _material_count:
		_points[index] = crystal.points_of(index)
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool: return _points[a] < _points[b])
	_by_points = PackedInt32Array(order)


## Materiály od nejlevnějšího.
func by_points() -> PackedInt32Array:
	return _by_points


## Doly dostanou jen materiály mezi count nejlevnějšími. Ostatní na mapě nejsou, takže je
## nejde sebrat.
func set_available(count: int) -> void:
	_available = count


## Materiály, které mají na mapě důl, od nejlevnějšího. Každý dostane svou příšeru.
func pond_materials() -> PackedInt32Array:
	var count := _by_points.size() if _available < 0 else mini(_available, _by_points.size())
	var out := PackedInt32Array()
	var have := {}
	for mat in _pond_mat:
		if mat >= 0:
			have[mat] = true
	for order in count:
		var mat := _by_points[order]
		if have.has(mat):
			out.append(mat)
	return out


## Každý materiál z mine_plan dostane pás kolem továrny. Vzácnější je dál.
## Pásy se roztáhnou jen na materiály, které na mapě jsou, a sousedé se jen dotýkají.
## Doly drží rozestup POND_GAP, takže mezi nimi vždycky jde projít.
func _place_ponds(map: MapData, rng: RandomNumberGenerator) -> void:
	if _pond_kind < 0 or _by_points.is_empty() or mine_plan.is_empty():
		return
	var tile := float(TerrainCatalog.TILE_SIZE)
	var origin := Vector2(float(map.size) * tile, float(map.size) * tile) * 0.5
	if town != null and town.center() != Vector2.INF:
		origin = town.center()
	var materials := _by_points.size()
	var count := materials if _available < 0 else mini(_available, materials)
	var layout := mine_plan
	var present := 0
	for order in mini(count, layout.size()):
		if layout[order] > 0:
			present += 1
	var band := 0
	for order in mini(count, layout.size()):
		var want := layout[order]
		if want <= 0:
			continue
		var mat := _by_points[order]
		var ring := pond_annulus(band, present, map.size, edge_guard, band_max) * tile
		_place_ring(map, rng, mat, want, origin, ring.x, ring.y)
		band += 1


func _pond_cell(x: int, y: int, size: int) -> bool:
	var edge := mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
	return float(edge) >= edge_guard


## Bod rovnoměrně po ploše mezikruží, ne po poloměru, ať se doly u vnitřní hrany nehromadí.
func _place_ring(
	map: MapData,
	rng: RandomNumberGenerator,
	mat: int,
	want: int,
	origin: Vector2,
	inner: float,
	outer: float,
) -> int:
	var placed := 0
	var guard := want * 40
	var gap := POND_GAP * float(TerrainCatalog.TILE_SIZE)
	while placed < want and guard > 0:
		guard -= 1
		var dist := sqrt(lerpf(inner * inner, outer * outer, rng.randf()))
		var pos := origin + Vector2.from_angle(rng.randf() * TAU) * dist
		if not _pond_site(map, pos) or _near_object(pos, gap):
			continue
		_keep(_pond_kind, pos, rng)
		_remember_pond(mat)
		placed += 1
	return placed


## Stojí blíž než gap nějaký už postavený objekt? Při sázení dolů jsou to jen doly.
func _near_object(pos: Vector2, gap: float) -> bool:
	var grid := _grid
	var span := ceili(gap / grid.cell)
	var side := grid.side
	var at := grid.cell_at(pos)
	var gx := at.x
	var gy := at.y
	for cy in range(maxi(gy - span, 0), mini(gy + span, side - 1) + 1):
		for cx in range(maxi(gx - span, 0), mini(gx + span, side - 1) + 1):
			var item := grid.head[cy * side + cx]
			while item >= 0:
				if pos.distance_squared_to(_pos[item]) < gap * gap:
					return true
				item = grid.next[item]
	return false


## Mezikruží dolů daného pořadí: vnitřní a vnější vzdálenost od továrny v metrech.
## count je počet materiálů, které na mapě opravdu mají důl. Pásy jsou stejně široké
## a sousedé se jen dotýkají. Nejběžnější z nich začíná za volným kruhem, nejdražší končí
## nejdál guard metrů od kraje mapy.
## widest omezí šířku pásu v metrech, záporné ji nechá.
static func pond_annulus(order: int, count: int, size: int, guard: float, widest: float = -1.0) -> Vector2:
	var reach := maxf(float(size) * 0.5 - guard, POND_CLEAR)
	var bands := maxi(count, 1)
	var width := (reach - POND_CLEAR) / float(bands)
	if widest > 0.0:
		width = minf(width, widest)
	var inner := POND_CLEAR + float(clampi(order, 0, bands - 1)) * width
	return Vector2(inner, inner + width)


func _pond_site(map: MapData, pos: Vector2) -> bool:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var x := int(pos.x / tile)
	var y := int(pos.y / tile)
	if x < 0 or y < 0 or x >= map.size or y >= map.size:
		return false
	if not _pond_cell(x, y, map.size):
		return false
	if _walkable[map.terrain[y * map.size + x]] != 1:
		return false
	return _fits(pos, _pond_kind, map)


## Rozestup podle povrchu a k tomu mimo cestu, továrnu a domy. Skála nesmí ležet na kmeni
## a od pukliny drží CRACK_GAP_M. Puklina se zkouší po celé délce, viz _crack_fits.
func _fits(pos: Vector2, kind: int, map: MapData) -> bool:
	if _is_crack(kind):
		return super._fits(pos, kind, map) and _crack_fits(pos, kind, map)
	if not super._fits(pos, kind, map) or _in_town(pos, _kind_foot[kind]):
		return false
	return _capsule_at[kind] >= 0 or not near_log(pos, _radius[kind], true)


## Vybere natočení a variantu pukliny podle polohy (náhodu sázení nebere) a zkusí, jestli
## kapsle po celé délce leží na průchozím povrchu mapy, mimo vesnici a CRACK_GAP_M od
## ostatních objektů. Když ano, _keep ji tak položí.
func _crack_fits(pos: Vector2, kind: int, map: MapData) -> bool:
	var roll := absi(hash(Vector2i(pos)))
	var variant := roll % int(_kinds[kind]["variants"])
	var turn := float((roll >> 8) % 3600) / 3600.0 * TAU
	var tile := float(TerrainCatalog.TILE_SIZE)
	var gap := CRACK_GAP_M * tile
	var row := _capsule_at[kind] + variant * 2
	var first := _capsule_rows[row]
	for c in _capsule_rows[row + 1]:
		var at := (first + c) * 6
		var a := pos + Vector2(_capsule[at], _capsule[at + 1]).rotated(turn)
		var b := pos + Vector2(_capsule[at + 2], _capsule[at + 3]).rotated(turn)
		var steps := maxi(ceili(a.distance_to(b) / CRACK_STEP), 1)
		for step in steps + 1:
			var t := float(step) / float(steps)
			var spot := a.lerp(b, t)
			var radius := lerpf(_capsule[at + 4], _capsule[at + 5], t)
			var x := floori(spot.x / tile)
			var y := floori(spot.y / tile)
			if x < 0 or y < 0 or x >= map.size or y >= map.size:
				return false
			if _walkable[map.terrain[y * map.size + x]] != 1:
				return false
			if _in_town(spot, radius) or _crowded_by(spot, radius + gap):
				return false
	_shaped_kind = kind
	_shaped_variant = variant
	_shaped_turn = turn
	return true


## Leží blíž než reach px od pos pata skály nebo kapsle jiného objektu?
func _crowded_by(pos: Vector2, reach: float) -> bool:
	var grid := _grid
	var span := ceili((_foot + reach) / grid.cell)
	var at := grid.cell_at(pos)
	for cy in range(maxi(at.y - span, 0), mini(at.y + span, grid.side - 1) + 1):
		for cx in range(maxi(at.x - span, 0), mini(at.x + span, grid.side - 1) + 1):
			var item := grid.head[cy * grid.side + cx]
			while item >= 0:
				var limit := reach
				var spot := _pos[item]
				if _capsule_at[_kind[item]] >= 0:
					var near := _capsule_near(item, pos)
					spot = Vector2(near.x, near.y)
					limit += near.z
				else:
					limit += _radius[_kind[item]]
				if pos.distance_squared_to(spot) < limit * limit:
					return true
				item = grid.next[item]
	return false


func _keep(kind: int, pos: Vector2, rng: RandomNumberGenerator) -> void:
	if kind == _shaped_kind:
		_shaped_kind = -1
		_keep_shaped(kind, pos, _shaped_variant, _shaped_turn)
		return
	super._keep(kind, pos, rng)


## Stromy drží od skal rozestup kolem středu. Od ležícího kmene ne, ten hlídá near_log
## podle kapsle, ať strom smí růst těsně u kmene. Takový objekt má rozestup záporný.
func spot_gaps() -> PackedFloat32Array:
	var gaps := super.spot_gaps()
	for index in gaps.size():
		if _capsule_at[_kind[index]] >= 0:
			gaps[index] = -1.0
	return gaps


func _remember_pond(mat: int) -> void:
	var index := _pos.size() - 1
	_pond_slot[index] = _pond_rock.size()
	_pond_rock.append(index)
	_pond_mat.append(mat)


func _begin_plant(map: MapData) -> void:
	super._begin_plant(map)
	_pond_slot = PackedInt32Array()
	_pond_rock = PackedInt32Array()
	_pond_mat = PackedInt32Array()


func _keep_shaped(kind: int, pos: Vector2, variant: int, turn: float) -> void:
	super._keep_shaped(kind, pos, variant, turn)
	_pond_slot.append(-1)


func _catalog_path() -> String:
	return "res://graphics/objects/rocks/rocks.json"


func _catalog_key() -> String:
	return "rocks"


func _surface_key() -> String:
	return "rocks"


## Nízký balvan je pod postavou. Velká skála je nad ní.
func _build(kind: int) -> Node2D:
	var node := super._build(kind)
	node.z_index = 0 if _top[kind] <= LOW else 2
	if _is_pit(kind):
		# Vrstvy dolu a pukliny jdou pod zem: nejhlubší se kreslí první, okraj na zemi přes ně.
		var sprites: Array[Sprite2D] = []
		for child in node.get_children():
			if child is Sprite2D:
				sprites.append(child)
		for layer in sprites.size():
			sprites[layer].set_meta("layer", layer)
			node.move_child(sprites[layer], 0)
	return node


func acquire(index: int) -> Node2D:
	var node := super.acquire(index)
	var slot := _pond_slot[index] if index < _pond_slot.size() else -1
	if slot >= 0 and _is_mine(_kind[index]):
		_paint_mine(node, _kind[index], _pond_mat[slot])
	return node


func _is_mine(kind: int) -> bool:
	return kind >= 0 and kind < _kinds.size() and bool(_kinds[kind].get("mine", false))


func _is_crack(kind: int) -> bool:
	return kind >= 0 and kind < _kinds.size() and bool(_kinds[kind].get("crack", false))


## Vrstvy pod zemí: důl a puklina.
func _is_pit(kind: int) -> bool:
	return _is_mine(kind) or _is_crack(kind)


## Vrstvy dolu a pukliny mají vždycky vlastní shader: důl barví kameny a svítí lucernou,
## puklina žhne, obojí i bez posunu výšky. Tady okraje spritů podle posunu, materiál pukliny
## je z katalogu, dolu ho dá _paint_mine.
func _fit(node: Node2D, kind: int) -> void:
	if not _is_pit(kind):
		super._fit(node, kind)
		return
	var layers: Array = _kinds[kind]["layers"]
	for child in node.get_children():
		var sprite := child as Sprite2D
		if sprite == null or not sprite.has_meta("layer"):
			continue
		var info: Dictionary = layers[int(sprite.get_meta("layer"))]
		if _is_crack(kind):
			sprite.material = info["material"]
		var height := float(info["height"])
		var rect := sprite.get_rect().grow(ObjectLayers.vertex_pad(_fitted_view, absf(height)))
		RenderingServer.canvas_item_set_custom_rect(sprite.get_canvas_item(), true, rect)


func _paint_mine(node: Node2D, kind: int, mat: int) -> void:
	for child in node.get_children():
		var sprite := child as Sprite2D
		if sprite != null and sprite.has_meta("layer"):
			sprite.material = _mine_material(kind, int(sprite.get_meta("layer")), mat)


func _mine_material(kind: int, layer: int, mat: int) -> ShaderMaterial:
	var key := Vector3i(kind, layer, mat)
	if _mine_materials.has(key):
		return _mine_materials[key]
	if _mine_shader == null:
		_mine_shader = load(MINE_SHADER) as Shader
	var entry := _kinds[kind]
	var layers: Array = entry["layers"]
	var depth := 0.0
	for info: Dictionary in layers:
		depth = minf(depth, float(info["height"]))
	var material := ShaderMaterial.new()
	material.shader = _mine_shader
	material.set_shader_parameter("height_m", float(layers[layer]["height"]))
	material.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
	material.set_shader_parameter("pit_depth", -depth)
	material.set_shader_parameter("rock_color", entry["rim_color"] if layer == 0 else entry["wall_color"])
	if _crystal != null and mat >= 0:
		material.set_shader_parameter("ore_color", _crystal.color_of(mat))
		material.set_shader_parameter("glint_color", _crystal.glint_of(mat))
		material.set_shader_parameter("sparkle", maxf(_crystal.sparkle_of(mat), 0.25))
	_mine_materials[key] = material
	return material


func _scatter_kind(kind: int) -> bool:
	return kind != int(_kind_of.get(MINE, -1))


## Poloměr paty podle spodní vrstvy. Podle něj se odhaduje krok stěny a kruh varianty bez obrysu.
func _load_entry(kind_name: String, info: Dictionary, columns: int) -> Dictionary:
	var entry := super._load_entry(kind_name, info, columns)
	if entry.is_empty():
		return entry
	var listed: Dictionary = info.get("layers", {})
	var base: Dictionary = listed[_sorted_keys(listed)[0]]
	var radius := float(base.get("width", 64.0)) * 0.5
	var top := 0.0
	for key: Variant in _sorted_keys(listed):
		var layer_info: Dictionary = listed[key]
		top = maxf(top, float(layer_info.get("height", 0.0)))
	_radius.append(radius)
	_top.append(top)
	if bool(info.get("mine", false)):
		entry["mine"] = true
		entry["rim_color"] = Color.html(str(info.get("color", "7C6A54")))
		entry["wall_color"] = Color.html(str(info.get("wall", "6E6860")))
	if bool(info.get("crack", false)):
		entry["crack"] = true
		entry["mask_path"] = "%s/%s/mask.png" % [_root(), kind_name]
		_crack_materials(entry)
	_foot = maxf(_foot, radius * FOOT_MARGIN)
	_read_outline(info, int(entry["variants"]), radius * FOOT_MARGIN)
	_read_capsule(info, int(entry["variants"]))
	return entry


## Vlastní materiál každé vrstvy pukliny: výška a síla žáru.
func _crack_materials(entry: Dictionary) -> void:
	var shader := load(CRACK_SHADER) as Shader
	var layers: Array = entry["layers"]
	for layer in layers.size():
		var info: Dictionary = layers[layer]
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("height_m", float(info["height"]))
		material.set_shader_parameter("parallax", ObjectLayers.PARALLAX)
		material.set_shader_parameter("max_shift", CRACK_MAX_SHIFT)
		material.set_shader_parameter("glow", CRACK_GLOW[mini(layer, CRACK_GLOW.size() - 1)])
		info["material"] = material


## Puklině se s texturami vrstev načte i maska díry pro hlubší vrstvy.
func _load_textures(kind: int) -> void:
	super._load_textures(kind)
	var entry := _kinds[kind]
	if not entry.has("mask_path") or entry.has("mask"):
		return
	var mask := _texture_from(str(entry["mask_path"]))
	entry["mask"] = mask
	if mask == null:
		push_error("Puklině chybí maska %s." % entry["mask_path"])
		return
	var layers: Array = entry["layers"]
	for layer in range(1, layers.size()):
		var material: ShaderMaterial = layers[layer]["material"]
		material.set_shader_parameter("mask", mask)
		material.set_shader_parameter("masked", true)


## Kapsle variant. Řádek je šestice (jedna kapsle, padlý strom), nebo seznam šestic (puklina).
func _read_capsule(info: Dictionary, variants: int) -> void:
	var listed: Variant = info.get("capsule", [])
	var rows: Array = listed if typeof(listed) == TYPE_ARRAY else []
	if rows.size() < variants:
		_capsule_at.append(-1)
		return
	_capsule_at.append(_capsule_rows.size())
	for variant in variants:
		var row: Array = rows[variant]
		var shapes: Array = row if not row.is_empty() and typeof(row[0]) == TYPE_ARRAY else [row]
		_capsule_rows.append(_capsule.size() / 6)
		_capsule_rows.append(shapes.size())
		for shape: Array in shapes:
			for value in shape:
				_capsule.append(float(value))


## Index do _capsule_rows pro variantu objektu, -1 u objektu bez kapslí.
func _capsule_of(item: int) -> int:
	var start := _capsule_at[_kind[item]]
	return -1 if start < 0 else start + _variant[item] * 2


## Bod kapslí objektu nejblíž pos (k povrchu, ne k ose) a poloměr v tom místě, ve světě.
func _capsule_near(item: int, pos: Vector2) -> Vector3:
	var row := _capsule_of(item)
	var turn := _turn[item]
	var local := (pos - _pos[item]).rotated(-turn)
	var best := Vector3.ZERO
	var best_gap := INF
	var first := _capsule_rows[row]
	for c in _capsule_rows[row + 1]:
		var at := (first + c) * 6
		var a := Vector2(_capsule[at], _capsule[at + 1])
		var b := Vector2(_capsule[at + 2], _capsule[at + 3])
		var ab := b - a
		var t := clampf((local - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var axis := a + ab * t
		var radius := lerpf(_capsule[at + 4], _capsule[at + 5], t)
		var gap := local.distance_to(axis) - radius
		if gap < best_gap:
			best_gap = gap
			best = Vector3(axis.x, axis.y, radius)
	var near := _pos[item] + Vector2(best.x, best.y).rotated(turn)
	return Vector3(near.x, near.y, best.z)


## Leží blíž než reach px od některého ležícího kmene nebo pukliny? Pro sázení stromů a skal
## kolem nich. spaced přidá od pukliny CRACK_GAP_M, skály ji tak nezatarasí.
func near_log(pos: Vector2, reach: float, spaced: bool = false) -> bool:
	if _capsule.is_empty() or _grid == null:
		return false
	var grid := _grid
	var extra := CRACK_GAP_M * float(TerrainCatalog.TILE_SIZE) if spaced else 0.0
	var span := ceili((_foot + reach + extra) / grid.cell)
	var at := grid.cell_at(pos)
	for cy in range(maxi(at.y - span, 0), mini(at.y + span, grid.side - 1) + 1):
		for cx in range(maxi(at.x - span, 0), mini(at.x + span, grid.side - 1) + 1):
			var item := grid.head[cy * grid.side + cx]
			while item >= 0:
				if _capsule_at[_kind[item]] >= 0:
					var near := _capsule_near(item, pos)
					var limit := near.z + reach + (extra if _is_crack(_kind[item]) else 0.0)
					if pos.distance_squared_to(Vector2(near.x, near.y)) < limit * limit:
						return true
				item = grid.next[item]
	return false


## Obrys všech variant druhu. Varianta bez obrysu v katalogu dostane kruh jako dřív.
func _read_outline(info: Dictionary, variants: int, fallback: float) -> void:
	var listed: Variant = info.get("outline", [])
	var rows: Array = listed if typeof(listed) == TYPE_ARRAY else []
	var steps := 1
	for row: Variant in rows:
		if typeof(row) == TYPE_ARRAY and not (row as Array).is_empty():
			steps = (row as Array).size()
			break
	_outline_at.append(_outline.size())
	_steps.append(steps)
	_kind_foot.append(0.0)
	var kind := _kind_foot.size() - 1
	for variant in variants:
		var row: Variant = rows[variant] if variant < rows.size() else null
		var usable := typeof(row) == TYPE_ARRAY and (row as Array).size() == steps
		if not usable and not rows.is_empty():
			push_warning("Skála nemá obrys varianty %d, bere kruh." % variant)
		for step in steps:
			var reach := float((row as Array)[step]) if usable else fallback
			_outline.append(reach)
			_foot = maxf(_foot, reach)
			_kind_foot[kind] = maxf(_kind_foot[kind], reach)


## Pro každý směr: nejdál od středu, kde se kruh těla dotkne obrysu. Úzká špička tak nepropustí
## tělo, které by šlo kolem ní. Hodnota obrysu je nejdelší dosah celé výseče, proto se bere
## její střed i oba kraje.
func _build_bounds(body: float) -> void:
	_bound_body = body
	_bound = PackedFloat32Array()
	_bound.resize(_outline.size())
	for kind in _steps.size():
		var steps := _steps[kind]
		var start := _outline_at[kind]
		var variants := int(_kinds[kind]["variants"])
		var slice := TAU / float(steps)
		var points := PackedVector2Array()
		points.resize(steps * 3)
		# Bod za čtvrt otáčky už střed nevytlačí dál než na body, stačí okolí směru.
		var window := mini(steps / 4 + 1, steps / 2)
		for variant in variants:
			var row := start + variant * steps
			for step in steps:
				var reach := _outline[row + step]
				var angle := float(step) * slice
				points[step * 3] = Vector2.from_angle(angle - slice * 0.5) * reach
				points[step * 3 + 1] = Vector2.from_angle(angle) * reach
				points[step * 3 + 2] = Vector2.from_angle(angle + slice * 0.5) * reach
			for step in steps:
				var dir := Vector2.from_angle(float(step) * slice)
				var best := body
				for offset in range(-window, window + 1):
					var near := posmod(step + offset, steps) * 3
					for k in 3:
						var point := points[near + k]
						var side := absf(point.cross(dir))
						if side < body:
							best = maxf(best, point.dot(dir) + sqrt(body * body - side * side))
				_bound[row + step] = best


## Hodnota z tabulky po směrech (obrys nebo hranice těla) pro úhel ve světě.
## Uzel skály je natočený o turn, tabulka je v souřadnicích obrázku. Mezi sousedními směry se prolíná.
func _sample(table: PackedFloat32Array, kind: int, variant: int, turn: float, angle: float) -> float:
	var steps := _steps[kind]
	var row := _outline_at[kind] + variant * steps
	var f := fposmod((angle - turn) / TAU, 1.0) * float(steps)
	var step := int(f) % steps
	return lerpf(table[row + step], table[row + (step + 1) % steps], f - floorf(f))


func _pair_gap(left: int, right: int) -> float:
	var meters := maxf(float(_kinds[left]["spacing"]), float(_kinds[right]["spacing"]))
	return meters * float(TerrainCatalog.TILE_SIZE)


## Posune bod ven z pat skal podle jejich obrysu, body je poloměr postavy.
## Mřížka ze sázení má buňku větší než pata, takže stačí buňka pod bodem a její okolí.
## clearance < 0 drží všechny skály. Jinak skála nižší nebo rovná této výšce pustí, jde přeskočit.
## Označí v mřížce buňky (dlaždice), jejichž střed je blíž než hranice těla body plus margin.
## Hranice je stejná, jakou drží avoid, takže cesta nevede tam, kam tělo nesmí.
## Skála nižší nebo rovná clearance se přeskočí, neoznačí se. clearance < 0 označí všechny.
func block_cells(grid: AStarGrid2D, body: float, margin: float, clearance: float = -1.0) -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var region := grid.region
	_use_bounds(body)
	for item in _pos.size():
		var kind := _kind[item]
		if clearance >= 0.0 and _top[kind] <= clearance:
			continue
		var center := _pos[item]
		var reach := _kind_foot[kind] + body + margin
		var x0 := maxi(int((center.x - reach) / tile), region.position.x)
		var x1 := mini(int((center.x + reach) / tile), region.end.x - 1)
		var y0 := maxi(int((center.y - reach) / tile), region.position.y)
		var y1 := mini(int((center.y + reach) / tile), region.end.y - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var cell := Vector2((float(x) + 0.5) * tile, (float(y) + 0.5) * tile)
				if _capsule_at[kind] >= 0:
					var near := _capsule_near(item, cell)
					var reach_log := near.z + body + margin
					if cell.distance_squared_to(Vector2(near.x, near.y)) < reach_log * reach_log:
						grid.set_point_solid(Vector2i(x, y))
					continue
				var delta := cell - center
				var limit := _sample(_bound, kind, _variant[item], _turn[item], delta.angle()) + margin
				if delta.length_squared() < limit * limit:
					grid.set_point_solid(Vector2i(x, y))


func avoid(pos: Vector2, body: float, clearance: float = -1.0) -> Vector2:
	if _grid == null or _pos.is_empty():
		return pos
	_use_bounds(body)
	var result := pos
	for _pass in 2:
		result = _push(result, body, clearance)
	return result


## Spočítá hranice pro tělo dopředu, třeba ve vlákně při generování mapy, ať se to nestane
## uprostřed hry.
func prepare_bounds(body: float) -> void:
	_use_bounds(body)


## Tabulka hranic pro tělo. Spočítá se jen poprvé, dál se bere z paměti.
func _use_bounds(body: float) -> void:
	if body == _bound_body:
		return
	if _bounds.has(body):
		_bound = _bounds[body]
		_bound_body = body
		return
	_build_bounds(body)
	_bounds[body] = _bound


func _push(pos: Vector2, body: float, clearance: float) -> Vector2:
	var grid := _grid
	var reach := _foot + body
	var span := ceili(reach / grid.cell)
	var side := grid.side
	var at := grid.cell_at(pos)
	var gx := at.x
	var gy := at.y
	var result := pos
	for cy in range(maxi(gy - span, 0), mini(gy + span, side - 1) + 1):
		for cx in range(maxi(gx - span, 0), mini(gx + span, side - 1) + 1):
			var item := grid.head[cy * side + cx]
			while item >= 0:
				var kind := _kind[item]
				if clearance >= 0.0 and _top[kind] <= clearance:
					item = grid.next[item]
					continue
				var delta := result - _pos[item]
				var dist_sq := delta.length_squared()
				# Hranice nesahá dál než obrys druhu plus tělo. Vzdálená skála se odmítne bez úhlu.
				var most := _kind_foot[kind] + body
				if dist_sq >= most * most:
					item = grid.next[item]
					continue
				if _capsule_at[kind] >= 0:
					result = _off_log(result, item, body)
					item = grid.next[item]
					continue
				var limit := _sample(_bound, kind, _variant[item], _turn[item], delta.angle())
				if dist_sq < limit * limit:
					if dist_sq < 0.0001:
						result = _pos[item] + Vector2(limit, 0.0)
					else:
						result = _pos[item] + delta * (limit / sqrt(dist_sq))
				item = grid.next[item]
	return result


## Vytlačí bod kolmo od ležícího kmene. Postava se o kmen zarazí a klouže podél něj
## jako podél skály, nesmýkne se ke konci stromu.
func _off_log(pos: Vector2, item: int, body: float) -> Vector2:
	var near := _capsule_near(item, pos)
	var axis := Vector2(near.x, near.y)
	var limit := near.z + body
	var away := pos - axis
	var dist_sq := away.length_squared()
	if dist_sq >= limit * limit:
		return pos
	if dist_sq < 0.0001:
		var at := _capsule_rows[_capsule_of(item)] * 6
		var along := Vector2(_capsule[at + 2] - _capsule[at], _capsule[at + 3] - _capsule[at + 1])
		away = along.orthogonal().rotated(_turn[item])
	return axis + away.normalized() * limit


## Důl, jehož obrysu se střed postavy dotýká. Žádný je -1.
func pond_at(pos: Vector2, body: float) -> int:
	var best := -1
	var best_dist := INF
	for slot in _pond_rock.size():
		if _pond_mat[slot] < 0:
			continue
		var index := _pond_rock[slot]
		if not _touches(pos, index, body):
			continue
		var dist := pos.distance_squared_to(_pos[index])
		if dist < best_dist:
			best_dist = dist
			best = slot
	return best


## Je střed postavy do body od obrysu dolu slot?
func near_pond(slot: int, pos: Vector2, body: float) -> bool:
	return _touches(pos, _pond_rock[slot], body)


## Skály do mapy (MiniMap.chart): dlaždice pod obrysem obarví. Skála je šedá, puklina žhne,
## padlý strom je tmavé dřevo, důl má barvu svého materiálu. Volá se ve vlákně tvorby čtverce,
## polohy jsou ještě bez posunu čtverce.
func paint_chart(chart: Image) -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var side := chart.get_width()
	var mine_mat := {}
	for slot in _pond_rock.size():
		mine_mat[_pond_rock[slot]] = _pond_mat[slot]
	for index in _pos.size():
		var kind := _kind[index]
		var color := CHART_ROCK
		if mine_mat.has(index):
			var mat: int = mine_mat[index]
			color = _crystal.color_of(mat) if _crystal != null and mat >= 0 else CHART_ROCK
		elif _is_crack(kind):
			color = CHART_CRACK
		elif _capsule_at[kind] >= 0:
			color = CHART_LOG
		# Dlaždice pod středem vždycky, malý balvan jinak středy dlaždic mine.
		var at := Vector2i((_pos[index] / tile).floor())
		if at.x >= 0 and at.y >= 0 and at.x < side and at.y < side:
			chart.set_pixelv(at, color)
		var reach := _radius[kind]
		var from := ((_pos[index] - Vector2(reach, reach)) / tile).floor()
		var to := ((_pos[index] + Vector2(reach, reach)) / tile).floor()
		for y in range(maxi(int(from.y), 0), mini(int(to.y), side - 1) + 1):
			for x in range(maxi(int(from.x), 0), mini(int(to.x), side - 1) + 1):
				var delta := Vector2(x + 0.5, y + 0.5) * tile - _pos[index]
				if delta.length() <= _sample(_outline, kind, _variant[index], _turn[index], delta.angle()):
					chart.set_pixel(x, y, color)


## Doly materiálu mat.
func ponds_holding(mat: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for slot in _pond_rock.size():
		if _pond_mat[slot] == mat:
			out.append(slot)
	return out


## Materiál dolu.
func pond_material(slot: int) -> int:
	return _pond_mat[slot]


## Střed dolu ve světě.
func pond_center(slot: int) -> Vector2:
	return _pos[_pond_rock[slot]]


## Místo, kde stojí tělo o poloměru body u okraje dolu, na straně k from. Střed dolu je
## neprůchodný, cesta k němu by nevedla.
func pond_edge(slot: int, from: Vector2, body: float) -> Vector2:
	var index := _pond_rock[slot]
	var away := from - _pos[index]
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	return _pos[index] + away.normalized() * (_radius[_kind[index]] + body + TOUCH_PX)


## Výměna u dolu: důl nikdy nedojde a nic se do něj nedává. Levnější kámen z ruky (held, -1 je
## prázdná ruka) se vymění za materiál dolu a zmizí, stejný nebo dražší zůstane v ruce
## a vrátí se held.
func swap_gem(slot: int, held: int) -> int:
	var own := _pond_mat[slot]
	if held >= 0 and _points[held] >= _points[own]:
		return held
	return own


## Doly: poloha ve světě, číslo materiálu a dolu, po trojicích [pos, mat, slot].
func pond_spots() -> Array:
	var spots := []
	for slot in _pond_rock.size():
		if _pond_mat[slot] >= 0:
			spots.append([_pos[_pond_rock[slot]], _pond_mat[slot], slot])
	return spots


func _touches(pos: Vector2, index: int, body: float) -> bool:
	_use_bounds(body)
	var kind := _kind[index]
	var delta := pos - _pos[index]
	var limit := _sample(_bound, kind, _variant[index], _turn[index], delta.angle()) + TOUCH_PX
	return delta.length_squared() <= limit * limit

