extends "res://scripts/layered_props.gd"

const Crystal := preload("res://scripts/crystal.gd")

## Pás kolem mapy má tři vrstvy, všechny míry jsou v metrech.
## Stěna je souvislý řetěz skal těsně u okraje. Střed skály je WALL_NEAR až WALL_FAR od okraje
## podle vlny kolem mapy, takže skála přes okraj klidně přečuhuje.
const WALL_NEAR := 0.5
const WALL_FAR := 2.5
## Sousední skály stěny mají středy na součtu dosahů obrysů směrem k sobě krát tohle.
## Pod jedna se paty lehce překrývají, takže ve stěně není škvíra.
const WALL_TOUCH_MIN := 0.82
const WALL_TOUCH_MAX := 0.94
## Jak moc se směr řetězu náhodně vychýlí od dráhy, v radiánech. Dráha ho stáčí zpátky.
const WALL_WOBBLE := 0.35
## Řidší řada před stěnou: tak daleko od dráhy stěny, s mezerami a občas vynechanou skálou.
const ROW_OFFSET := 4.5
const ROW_GAP_MIN := 1.15
const ROW_GAP_MAX := 1.9
const ROW_SKIP := 0.2
## Jak daleko se skála řady odchýlí od své dráhy.
const ROW_JITTER := 0.8
## Pár rozházených skal před řadou. Počet je na metr obvodu mapy.
const SCATTER_NEAR := 1.5
const SCATTER_FAR := 6.0
const SCATTER_PER_M := 0.05
const SCATTER_TRIES := 4
## Nejhlubší místo pásu. Podle něj je zaoblený roh dráhy rozházených skal.
const RIM_FAR := WALL_FAR + ROW_OFFSET + SCATTER_FAR
## Skály řady a rozházené skály se se sousedy překrývají nejvýš takhle.
const RIM_TOUCH := 0.78
## Varianta bez obrysu v katalogu bere kruh o tolik větší než jmenovitá pata.
const FOOT_MARGIN := 1.4
## Do této výšky je skála pod postavou a jde přeskočit. Vyšší je nad ní.
const LOW := 1.5
## Jezírko má počet podle levelu, ne šanci v povrchu. Bezedné jezírko je důl.
const POND := "jezirko"
const MINE := "dul"
const MINE_SHADER := "res://shaders/mine_layer.gdshader"
## Studánek na mapě je nejvýš tolik. Další materiál vznikne na úkor nejlevnějšího.
const POND_MAX := 11
## Volný kruh kolem továrny v metrech. Hráč se objeví u továrny a má kudy projít.
const POND_CLEAR := 10.0
## Nejmenší vzdálenost středů dvou jezírek v metrech. Jezírko má průměr asi 2 m.
const POND_GAP := 7.0
## Metry od okraje za stěnou skal, ať velká skála jezírko nepřikryje. Řada a rozházené skály
## se sázejí po jezírkách a vyhnou se jim samy.
const POND_INSET := 6.0
## O kolik pixelů dřív než o obrys se bere dotek postavy.
const TOUCH_PX := 2.0
## Kamenů v jezírku. U bezedného jezírka jsou vidět pořád, jinak ubývají.
const GEMS_IN_POND := 3
## Míst pro kameny v jezírku. Výměnami a vracením ukradených jich v jezírku může být víc než
## na začátku. Kameny nad GEM_SPOTS se kladou na stejná místa znovu, kousek posunuté.
const GEM_SPOTS := 7
const GEM_STACK := Vector2(2.0, -3.0)
## Víc kamenů než GEMS_IN_POND se do jezírka vejde menších, nejvýš na GEM_SHRINK původní velikosti.
const GEM_SHRINK := 0.6
const RIM_WEIGHTS := {
	"skala15": 0.2,
	"skala2": 0.22,
	"skala10": 0.18,
	"skala1": 0.24,
	"balvan1": 0.16,
}

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
## Největší a nejmenší dosah obrysu každého druhu. Pás podle nich odbude vzdálené a úplně
## překryté dvojice bez hledání v obrysu.
var _kind_foot := PackedFloat32Array()
var _kind_core := PackedFloat32Array()
## Poloměr ústí v px. U skály bez díry je 0.
var _mouth := PackedFloat32Array()
var _crystal: Crystal
var _gem_radius := 0.0
var _material_count := 0
## Body materiálů a jejich pořadí od nejběžnějšího. Sázení je čte ve vlákně.
var _points := PackedInt32Array()
var _by_points := PackedInt32Array()
## Kolik nejlevnějších materiálů má na mapě jezírka. Záporné jsou všechny.
var _available := -1
var _pond_kind := -1
## Druhy, které se nesází podle povrchu: jezírko a důl. Který z nich je _pond_kind, určí bottomless.
var _lone_kinds := {}
## Materiál vrstvy dolu podle [druh, vrstva, materiál]. Barvu dolu dává materiál, ne uzel.
var _mine_materials := {}
var _mine_shader: Shader
## U každé skály číslo jezírka, nebo -1. Dál už jen jezírka a kameny v nich.
var _pond_slot := PackedInt32Array()
var _pond_rock := PackedInt32Array()
var _pond_mat := PackedInt32Array()
var _gem_pos := PackedVector2Array()
var _gem_rot := PackedFloat32Array()
## Bezedné jezírko má svého materiálu pořád dost. Jinak má kameny jen v _pond_gems a ubývají.
## Nastaví svět.
var bottomless := true
## Svět pás hor nechce. Jezírka pak smí blíž ke kraji: edge_guard je odstup středu v metrech,
## záporné nechá dnešní odstup za stěnou.
var draw_rim := true
var edge_guard := -1.0
## Počet jezírek každého materiálu od nejlevnějšího. Prázdné nechá pond_layout podle levelu.
## Nastaví svět, typ hry Skafandry tak dá každému materiálu svůj důl.
var mine_plan := PackedInt32Array()
## Pás jezírek jednoho materiálu kolem továrny je široký nejvýš tolik metrů. Záporné nechá
## pásy roztáhnout po celé mapě.
var band_max := -1.0
## Kameny v jezírku podle pořadí, ve kterém do něj přišly. Bezedné tu má jen kameny vložené
## navíc, svůj materiál nepočítá.
var _pond_gems: Array[PackedInt32Array] = []
## Všechny kameny ve všech jezírkách na začátku. Výměny a krádeže je jen přesouvají.
var _gem_total := 0
## Zobrazené jezírko -> jeho uzel, ať jde po sebrání a vrácení kamene hned překreslit.
var _pond_nodes := {}


## Továrna, cesta a domy (town) už stojí. Nejdřív jezírka kolem továrny, podle nich sklady
## (jen když je town chce), potom pás kolem mapy, potom skály podle povrchu. Stromy se sází až potom. Nesahá na scénu, smí běžet ve vlákně.
func plant(map: MapData, rng: RandomNumberGenerator) -> void:
	var pond_name := MINE if bottomless and _kind_of.has(MINE) else POND
	_pond_kind = int(_kind_of[pond_name]) if _kind_of.has(pond_name) else -1
	if _kinds.is_empty():
		return
	_begin_plant(map)
	_place_ponds(map, rng)
	if town != null and town.stores:
		var mines := PackedVector2Array()
		for index in _pond_rock:
			mines.append(_pos[index])
		town.plan_stores(map, rng, mines, _kind_foot[_pond_kind] if _pond_kind >= 0 else 0.0)
	if draw_rim:
		_place_rim(map, rng)
	_scatter(map, rng)


func bind_crystal(crystal: Crystal) -> void:
	_crystal = crystal
	_gem_radius = crystal.radius()
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


## Jezírka dostanou jen materiály s nejmenším počtem bodů, tolik, kolik dovolí level.
## Ostatní na mapě nejsou, takže je nejde sebrat.
func set_available(count: int) -> void:
	_available = count


## Materiály, které mají na mapě jezírka, od nejlevnějšího. Každý dostane svou příšeru.
## Levný materiál bez jezírka tu není.
func pond_materials() -> PackedInt32Array:
	var count := _by_points.size() if _available < 0 else mini(_available, _by_points.size())
	var out := PackedInt32Array()
	var have := {}
	for mat in _pond_mat:
		if mat >= 0:
			have[mat] = true
	if have.is_empty():
		return _by_points.slice(0, count)
	for order in count:
		var mat := _by_points[order]
		if have.has(mat):
			out.append(mat)
	return out


## Počty jezírek od nejlevnějšího, když je na mapě count materiálů. Level s tolika materiály
## je ten, ve kterém poslední z nich přibyl. V levelu příchodu má materiál jedno jezírko,
## v dalším dvě, dokud jich není POND_MAX. Pak se nejdřív srazí nejlevnější dvojice na jednu
## a teprve když už žádná dvojice není, nejlevnější materiál zmizí.
static func pond_layout(count: int) -> PackedInt32Array:
	var ponds := PackedInt32Array()
	ponds.resize(maxi(count, 0))
	for level in count:
		ponds[level] = 1
		_fit_pond_cap(ponds, level + 1)
		if level > 0 and _sum_ponds(ponds, level + 1) < POND_MAX and ponds[level - 1] == 1:
			ponds[level - 1] = 2
	return ponds


static func _sum_ponds(ponds: PackedInt32Array, used: int) -> int:
	var total := 0
	for i in used:
		total += ponds[i]
	return total


## Uvolní jezírka nad POND_MAX. Nejdřív nejlevnější materiál se dvěma, až pak někdo zmizí.
static func _fit_pond_cap(ponds: PackedInt32Array, used: int) -> void:
	while _sum_ponds(ponds, used) > POND_MAX:
		var twin := -1
		for i in used:
			if ponds[i] >= 2:
				twin = i
				break
		if twin >= 0:
			ponds[twin] -= 1
			continue
		var lone := -1
		for i in used:
			if ponds[i] > 0:
				lone = i
				break
		if lone < 0:
			return
		ponds[lone] = 0


## Každý materiál, který má jezírka, dostane pás kolem továrny. Vzácnější je dál.
## Pásy se roztáhnou jen na materiály, které na mapě jsou, a sousedé se jen dotýkají.
## Jezírka drží rozestup POND_GAP, takže mezi nimi vždycky jde projít.
func _place_ponds(map: MapData, rng: RandomNumberGenerator) -> void:
	if _pond_kind < 0 or _by_points.is_empty():
		return
	var tile := float(TerrainCatalog.TILE_SIZE)
	var origin := Vector2(float(map.size) * tile, float(map.size) * tile) * 0.5
	if town != null and town.center() != Vector2.INF:
		origin = town.center()
	var materials := _by_points.size()
	var count := materials if _available < 0 else mini(_available, materials)
	var layout := mine_plan if not mine_plan.is_empty() else pond_layout(count)
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


## Kamenů v plném jezírku, které není bezedné. V každém jsou tři, i u drahého materiálu.
static func pond_gems(_order: int) -> int:
	return GEMS_IN_POND


func _pond_cell(x: int, y: int, size: int) -> bool:
	var edge := mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
	var guard := edge_guard if edge_guard >= 0.0 else _rim_guard(size)
	return float(edge) >= guard


## Bod rovnoměrně po ploše mezikruží, ne po poloměru, ať se jezírka u vnitřní hrany nehromadí.
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
		_remember_pond(mat, rng)
		placed += 1
	return placed


## Stojí blíž než gap nějaký už postavený objekt? Při sázení jezírek jsou to jen jezírka.
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


## Mezikruží jezírek daného pořadí: vnitřní a vnější vzdálenost od továrny v metrech.
## count je počet materiálů, které na mapě opravdu mají jezírka. Pásy jsou stejně široké
## a sousedé se jen dotýkají. Nejběžnější z nich začíná za volným kruhem, nejdražší končí
## u pásu skal.
## widest omezí šířku pásu v metrech, záporné ji nechá.
static func pond_annulus(order: int, count: int, size: int, guard: float = -1.0, widest: float = -1.0) -> Vector2:
	var inset := guard if guard >= 0.0 else _rim_guard(size)
	var reach := maxf(float(size) * 0.5 - inset, POND_CLEAR)
	var bands := maxi(count, 1)
	var width := (reach - POND_CLEAR) / float(bands)
	if widest > 0.0:
		width = minf(width, widest)
	var inner := POND_CLEAR + float(clampi(order, 0, bands - 1)) * width
	return Vector2(inner, inner + width)


## Odhad vzdálenosti nejbližšího jezírka od továrny v metrech. Jezírka jsou rozložená
## po mezikruží, nejbližší je v průměru kousek za vnitřní hranou.
static func pond_distance(ring: Vector2, ponds: int) -> float:
	return ring.x + (ring.y - ring.x) / float(maxi(ponds, 1) + 1)


static func _rim_guard(size: int) -> float:
	var guard := WALL_FAR + POND_INSET
	if float(size) * 0.5 <= guard + POND_CLEAR + 2.0:
		guard = maxf(float(size) * 0.25, 1.0)
	return guard


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


## Rozestup podle povrchu a k tomu mimo cestu, továrnu a domy.
func _fits(pos: Vector2, kind: int, map: MapData) -> bool:
	return super._fits(pos, kind, map) and not _in_town(pos, _kind_foot[kind])


func _remember_pond(mat: int, rng: RandomNumberGenerator) -> void:
	var index := _pos.size() - 1
	var slot := _pond_rock.size()
	_pond_slot[index] = slot
	_pond_rock.append(index)
	_pond_mat.append(mat)
	var gems := PackedInt32Array()
	if not bottomless:
		for _gem in pond_gems(_by_points.find(mat)):
			gems.append(mat)
		_gem_total += gems.size()
	_pond_gems.append(gems)
	_scatter_gems(rng)


func _scatter_gems(rng: RandomNumberGenerator) -> void:
	var mouth := 0.0
	if _pond_kind >= 0 and _pond_kind < _mouth.size():
		mouth = _mouth[_pond_kind]
	var reach := maxf(mouth - _gem_radius - 1.0, 0.0)
	var apart := _gem_radius * 0.85
	var spots: Array[Vector2] = []
	for _gem in GEM_SPOTS:
		var spot := Vector2.ZERO
		for _try in 16:
			spot = Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * reach
			var clear := true
			for other: Vector2 in spots:
				if spot.distance_squared_to(other) < apart * apart:
					clear = false
					break
			if clear:
				break
		spots.append(spot)
		_gem_pos.append(spot)
		_gem_rot.append(rng.randf() * TAU)


func _begin_plant(map: MapData) -> void:
	super._begin_plant(map)
	_pond_slot = PackedInt32Array()
	_pond_rock = PackedInt32Array()
	_pond_mat = PackedInt32Array()
	_pond_gems.clear()
	_gem_total = 0
	_pond_nodes.clear()
	_gem_pos = PackedVector2Array()
	_gem_rot = PackedFloat32Array()


func _keep_shaped(kind: int, pos: Vector2, variant: int, turn: float) -> void:
	super._keep_shaped(kind, pos, variant, turn)
	_pond_slot.append(-1)


func _on_land(map: MapData, pos: Vector2) -> bool:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var x := int(pos.x / tile)
	var y := int(pos.y / tile)
	if x < 0 or y < 0 or x >= map.size or y >= map.size:
		return false
	return _walkable[map.terrain[y * map.size + x]] == 1


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
	if _is_mine(kind):
		# Vrstvy dolu jdou pod zem: nejhlubší se kreslí první, okraj na zemi přes ně.
		var sprites: Array[Sprite2D] = []
		for child in node.get_children():
			if child is Sprite2D:
				sprites.append(child)
		for layer in sprites.size():
			sprites[layer].set_meta("layer", layer)
			node.move_child(sprites[layer], 0)
	if kind == _pond_kind:
		var holder := Node2D.new()
		holder.name = "Gems"
		node.add_child(holder)
	return node


func acquire(index: int) -> Node2D:
	var node := super.acquire(index)
	var slot := _pond_slot[index] if index < _pond_slot.size() else -1
	if slot >= 0:
		_pond_nodes[slot] = node
		if _is_mine(_kind[index]):
			_paint_mine(node, _kind[index], _pond_mat[slot])
		_sync_pond(node, slot)
	return node


func _is_mine(kind: int) -> bool:
	return kind >= 0 and kind < _kinds.size() and bool(_kinds[kind].get("mine", false))


## Vrstvy dolu mají vždycky vlastní shader: barví kameny a svítí lucernou i bez posunu výšky.
## Tady jen okraje spritů podle posunu, materiál dostanou v _paint_mine.
func _fit(node: Node2D, kind: int) -> void:
	if not _is_mine(kind):
		super._fit(node, kind)
		return
	var layers: Array = _kinds[kind]["layers"]
	for child in node.get_children():
		var sprite := child as Sprite2D
		if sprite == null or not sprite.has_meta("layer"):
			continue
		var height := float(layers[int(sprite.get_meta("layer"))]["height"])
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


## Kameny schovaného jezírka se uvolní. Mají instanční uniformy a těch je na celou hru jen
## pár tisíc, ve světě s mnoha čtverci by jinak došly. Při acquire je _sync_pond vytvoří znovu.
func release(index: int, node: Node2D) -> void:
	var slot := _pond_slot[index] if index < _pond_slot.size() else -1
	if slot >= 0:
		_pond_nodes.erase(slot)
		var holder := node.get_node_or_null("Gems") as Node2D
		if holder != null:
			_match_gems(holder, 0)
	super.release(index, node)


func _scatter_kind(kind: int) -> bool:
	return not _lone_kinds.has(kind)


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
	_mouth.append(float(info.get("mouth", 0.0)))
	if kind_name == POND or kind_name == MINE:
		_lone_kinds[_kinds.size()] = true
	if bool(info.get("mine", false)):
		entry["mine"] = true
		entry["rim_color"] = Color.html(str(info.get("color", "7C6A54")))
		entry["wall_color"] = Color.html(str(info.get("wall", "6E6860")))
	_foot = maxf(_foot, radius * FOOT_MARGIN)
	_read_outline(info, int(entry["variants"]), radius * FOOT_MARGIN)
	return entry


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
	_kind_core.append(INF)
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
			_kind_core[kind] = minf(_kind_core[kind], reach)


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


## Stěna z vysokých skal, které nejde přeskočit. Před ní řidší řada a pár rozházených skal,
## tam už smí i balvany.
func _place_rim(map: MapData, rng: RandomNumberGenerator) -> void:
	var weights := _rim_weights()
	if weights.is_empty():
		return
	var tall := {}
	for kind: int in weights:
		if _top[kind] > LOW:
			tall[kind] = weights[kind]
	if tall.is_empty():
		tall = weights
	var tile := float(TerrainCatalog.TILE_SIZE)
	var world := float(map.size) * tile
	# Roh dráhy je zaoblený jen tolik, kolik vrstva leží hluboko. Stěna tak jde rohem mapy těsně.
	_place_wall(map, rng, tall, world, minf(WALL_FAR * tile, world * 0.5))
	_place_row(map, rng, weights, world, minf((WALL_FAR + ROW_OFFSET) * tile, world * 0.5))
	_place_scattered(map, rng, weights, world, minf(RIM_FAR * tile, world * 0.5))


## Řetěz kolem mapy. Každá další skála se vylosuje i s natočením a postaví se tak, aby se patou
## dotkla předchozí na spojnici středů. Obrys je hvězdicovitý, takže dotek na spojnici je
## skutečný dotek a uzavřený řetěz nemá kudy projít. Konec se dotáhne k první skále.
func _place_wall(map: MapData, rng: RandomNumberGenerator, kinds: Dictionary, world: float, corner: float) -> void:
	var total := _loop_length(world, corner)
	var at := rng.randf() * total
	var first := _wall_rock(rng, kinds, _clamp_world(_rim_point(at, 0.0, world, corner), world))
	_keep_wall(map, first)
	var last := first
	var walked := 0.0
	while true:
		var next := _wall_rock(rng, kinds, Vector2.ZERO)
		var step := (_radius[last.kind] + _radius[next.kind]) * WALL_TOUCH_MAX
		if walked + step * 2.0 >= total:
			break
		var target := _rim_point(at + step, 0.0, world, corner)
		var dir := (target - last.pos).normalized().rotated(rng.randf_range(-WALL_WOBBLE, WALL_WOBBLE))
		var touch := rng.randf_range(WALL_TOUCH_MIN, WALL_TOUCH_MAX)
		var gap := (_wall_reach(last, dir.angle()) + _wall_reach(next, dir.angle() + PI)) * touch
		next.pos = _clamp_world(last.pos + dir * gap, world)
		at += gap
		walked += gap
		_keep_wall(map, next)
		last = next
	_close_wall(map, rng, kinds, last, first, world)


## Zbytek k první skále. Skála, která mezeru zavře, se postaví mezi obě v poměru jejich dosahů,
## ať se dotkne obou. Jinak se položí k poslední směrem k první a zkouší se dál.
func _close_wall(map: MapData, rng: RandomNumberGenerator, kinds: Dictionary, last: WallRock, first: WallRock, world: float) -> void:
	for _guard in 64:
		var span := first.pos - last.pos
		var dist := span.length()
		var angle := span.angle()
		if dist <= (_wall_reach(last, angle) + _wall_reach(first, angle + PI)) * WALL_TOUCH_MAX:
			return
		var next := _wall_rock(rng, kinds, Vector2.ZERO)
		var touch := rng.randf_range(WALL_TOUCH_MIN, WALL_TOUCH_MAX)
		var near := (_wall_reach(last, angle) + _wall_reach(next, angle + PI)) * touch
		var far := (_wall_reach(next, angle) + _wall_reach(first, angle + PI)) * touch
		if near + far >= dist:
			next.pos = last.pos + span * (near / (near + far))
			_keep_wall(map, next)
			return
		next.pos = _clamp_world(last.pos + span / dist * near, world)
		_keep_wall(map, next)
		last = next


func _wall_rock(rng: RandomNumberGenerator, kinds: Dictionary, pos: Vector2) -> WallRock:
	var rock := WallRock.new()
	rock.kind = _rim_kind(kinds, rng)
	rock.variant = rng.randi_range(0, int(_kinds[rock.kind]["variants"]) - 1)
	rock.turn = rng.randf() * TAU
	rock.pos = pos
	return rock


func _wall_reach(rock: WallRock, angle: float) -> float:
	return _sample(_outline, rock.kind, rock.variant, rock.turn, angle)


## Skála ve vodě se nepostaví, ale řetěz za ní pokračuje, jako by tam byla. Voda je neschůdná sama.
## Za okrajem mapy je souš okraje, tam skála stojí.
func _keep_wall(map: MapData, rock: WallRock) -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var x := clampi(int(rock.pos.x / tile), 0, map.size - 1)
	var y := clampi(int(rock.pos.y / tile), 0, map.size - 1)
	if _walkable[map.terrain[y * map.size + x]] != 1:
		return
	_keep_shaped(rock.kind, rock.pos, rock.variant, rock.turn)


## Řada před stěnou. Krok je dotek krát náhodná mezera a občas se skála vynechá.
func _place_row(map: MapData, rng: RandomNumberGenerator, kinds: Dictionary, world: float, corner: float) -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var total := _loop_length(world, corner)
	var at := rng.randf() * total
	var end := at + total
	var prev := -1
	while true:
		var kind := _rim_kind(kinds, rng)
		var step := (_radius[kind] + (_radius[prev] if prev >= 0 else _radius[kind])) * rng.randf_range(ROW_GAP_MIN, ROW_GAP_MAX)
		at += step
		if at >= end:
			break
		prev = kind
		if rng.randf() < ROW_SKIP:
			continue
		var jitter := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * ROW_JITTER * tile
		var pos := _rim_point(at, ROW_OFFSET * tile, world, corner) + jitter
		_try_spot(map, rng, kind, pos)


## Pár skal náhodně v pruhu před řadou.
func _place_scattered(map: MapData, rng: RandomNumberGenerator, kinds: Dictionary, world: float, corner: float) -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var total := _loop_length(world, corner)
	var count := int(total / tile * SCATTER_PER_M)
	for _rock in count:
		var kind := _rim_kind(kinds, rng)
		for _try in SCATTER_TRIES:
			var depth := (ROW_OFFSET + rng.randf_range(SCATTER_NEAR, SCATTER_FAR)) * tile
			if _try_spot(map, rng, kind, _rim_point(rng.randf() * total, depth, world, corner)):
				break


## Postaví skálu, jen když stojí na souši a moc nezajede do sousedů.
func _try_spot(map: MapData, rng: RandomNumberGenerator, kind: int, pos: Vector2) -> bool:
	if not _on_land(map, pos) or _in_town(pos, _kind_foot[kind]):
		return false
	var variant := rng.randi_range(0, int(_kinds[kind]["variants"]) - 1)
	var turn := rng.randf() * TAU
	if _rim_crowded(pos, kind, variant, turn, RIM_TOUCH):
		return false
	_keep_shaped(kind, pos, variant, turn)
	return true


## Délka dráhy kolem mapy: čtverec se zaoblenými rohy přímo na okraji.
static func _loop_length(world: float, corner: float) -> float:
	return (world - 2.0 * corner) * 4.0 + TAU * corner


## Bod dráhy ve vzdálenosti along od začátku, zanořený o inset dovnitř mapy. Dráha jde po směru
## hodin od levého horního rohu. Hloubka zanoření nesmí přesáhnout poloměr rohu.
static func _loop_point(along: float, inset: float, world: float, corner: float) -> Vector2:
	var straight := world - 2.0 * corner
	var side := straight + corner * PI * 0.5
	var t := fposmod(along, side * 4.0)
	var quarter := mini(int(t / side), 3)
	t -= float(quarter) * side
	var half := world * 0.5
	var local: Vector2
	if t < straight:
		local = Vector2(-half + corner + t, -half + inset)
	else:
		var turn := -PI * 0.5 + (t - straight) / maxf(corner, 0.001)
		local = Vector2(half - corner, -half + corner) + Vector2.from_angle(turn) * maxf(corner - inset, 0.0)
	return Vector2(half, half) + local.rotated(float(quarter) * PI * 0.5)


## Bod dráhy stěny a za ní o extra hlouběji. Hloubka stěny jde po vlně kolem mapy.
func _rim_point(along: float, extra: float, world: float, corner: float) -> Vector2:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var base := _loop_point(along, 0.0, world, corner)
	var center := Vector2(world, world) * 0.5
	var inset := _wall_inset((base - center).angle()) * tile + extra
	return _loop_point(along, minf(inset, corner), world, corner)


## Hloubka stěny od okraje v metrech pro úhel kolem středu mapy.
static func _wall_inset(angle: float) -> float:
	var wave := sin(angle * 2.0) * 0.42 + sin(angle * 5.0 + 1.7) * 0.33 + sin(angle * 3.0 + 2.4) * 0.25
	return lerpf(WALL_NEAR, WALL_FAR, clampf(wave * 0.5 + 0.5, 0.0, 1.0))


## Střed skály zůstane na mapě. Posun dovnitř vzdálenosti mezi skalami jen zmenší, dotek zůstane.
static func _clamp_world(pos: Vector2, world: float) -> Vector2:
	return Vector2(clampf(pos.x, 1.0, world - 1.0), clampf(pos.y, 1.0, world - 1.0))


## Překryla by se nová pata se sousední víc, než dovolí touch? Rozhoduje dosah obou obrysů
## na spojnici středů. Prohledává od buňky pod bodem ven, ať blízký soused ukončí hledání brzy.
func _rim_crowded(pos: Vector2, kind: int, variant: int, turn: float, touch: float) -> bool:
	var grid := _grid
	var span := ceili((_kind_foot[kind] + _foot) * touch / grid.cell)
	var side := grid.side
	var at := grid.cell_at(pos)
	var gx := at.x
	var gy := at.y
	for ring in span + 1:
		for cy in range(maxi(gy - ring, 0), mini(gy + ring, side - 1) + 1):
			var edge_row := absi(cy - gy) == ring
			for cx in range(maxi(gx - ring, 0), mini(gx + ring, side - 1) + 1):
				if not edge_row and absi(cx - gx) != ring:
					continue
				var item := grid.head[cy * side + cx]
				while item >= 0:
					if _overlaps(pos, kind, variant, turn, item, touch):
						return true
					item = grid.next[item]
	return false


## Dvojice dál než součet největších dosahů se nepřekryje, blíž než součet nejmenších vždycky.
## Jen mezi tím se hledá v obrysech.
func _overlaps(pos: Vector2, kind: int, variant: int, turn: float, item: int, touch: float) -> bool:
	var other := _kind[item]
	var delta := _pos[item] - pos
	var dist_sq := delta.length_squared()
	var most := (_kind_foot[kind] + _kind_foot[other]) * touch
	if dist_sq >= most * most:
		return false
	var least := (_kind_core[kind] + _kind_core[other]) * touch
	if dist_sq < least * least:
		return true
	var angle := delta.angle()
	var mine := _sample(_outline, kind, variant, turn, angle)
	var theirs := _sample(_outline, other, _variant[item], _turn[item], angle + PI)
	var gap := (mine + theirs) * touch
	return dist_sq < gap * gap


## Druhy okraje s jejich podílem. Chybí-li všechny, okraj staví první skálu z katalogu.
func _rim_weights() -> Dictionary:
	var weights := {}
	for kind_name: String in RIM_WEIGHTS:
		if _kind_of.has(kind_name):
			weights[_kind_of[kind_name]] = float(RIM_WEIGHTS[kind_name])
	if weights.is_empty() and not _kinds.is_empty():
		weights[0] = 1.0
	return weights


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
				var delta := Vector2((float(x) + 0.5) * tile, (float(y) + 0.5) * tile) - center
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
				var limit := _sample(_bound, kind, _variant[item], _turn[item], delta.angle())
				if dist_sq < limit * limit:
					if dist_sq < 0.0001:
						result = _pos[item] + Vector2(limit, 0.0)
					else:
						result = _pos[item] + delta * (limit / sqrt(dist_sq))
				item = grid.next[item]
	return result


## Druh podle podílů. Podíly nemusí dávat dohromady jedna.
func _rim_kind(weights: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for kind: int in weights:
		total += weights[kind]
	var roll := rng.randf() * total
	var cursor := 0.0
	for kind: int in weights:
		cursor += weights[kind]
		if roll <= cursor:
			return kind
	return weights.keys()[0]


## Jezírko, jehož obrysu se střed postavy dotýká. Žádné je -1. Prázdné jezírko se počítá jen
## s empty, tedy když postava nese kámen a může ho do něj odložit.
func pond_at(pos: Vector2, body: float, empty: bool = false) -> int:
	var best := -1
	var best_dist := INF
	for slot in _pond_rock.size():
		if _pond_mat[slot] < 0 or (pond_left(slot) <= 0 and not empty):
			continue
		var index := _pond_rock[slot]
		if not _touches(pos, index, body):
			continue
		var dist := pos.distance_squared_to(_pos[index])
		if dist < best_dist:
			best_dist = dist
			best = slot
	return best


## Kolik kamenů je v jezírku vidět. Bezedné má vždy aspoň GEMS_IN_POND svého materiálu.
func pond_left(slot: int) -> int:
	if slot < 0 or slot >= _pond_gems.size():
		return 0
	return _pond_gems[slot].size() + (GEMS_IN_POND if bottomless else 0)


## Nejdražší kámen v jezírku, prázdné -1.
func pond_best(slot: int) -> int:
	var best := _pond_mat[slot] if bottomless else -1
	for mat in _pond_gems[slot]:
		if best < 0 or _points[mat] > _points[best]:
			best = mat
	return best


## Co v jezírku leží, od nejdražšího: dvojice [materiál, počet]. Materiál bezedného jezírka má
## počet -1.
func pond_summary(slot: int) -> Array:
	var counts := {}
	if bottomless:
		counts[_pond_mat[slot]] = -1
	for mat in _pond_gems[slot]:
		if int(counts.get(mat, 0)) >= 0:
			counts[mat] = int(counts.get(mat, 0)) + 1
	var out := []
	for mat: int in counts:
		out.append([mat, counts[mat]])
	out.sort_custom(func(a: Array, b: Array) -> bool: return _points[a[0]] > _points[b[0]])
	return out


## Jezírka, ve kterých kámen mat právě leží. Bezedné má svůj materiál pořád.
func ponds_holding(mat: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for slot in _pond_rock.size():
		if _pond_mat[slot] < 0:
			continue
		if (bottomless and _pond_mat[slot] == mat) or _pond_gems[slot].has(mat):
			out.append(slot)
	return out


## Jezírka, ve kterých leží aspoň jeden kámen. Bezedné má kámen vždycky.
func ponds_with_gems() -> PackedInt32Array:
	var out := PackedInt32Array()
	for slot in _pond_rock.size():
		if _pond_mat[slot] >= 0 and pond_left(slot) > 0:
			out.append(slot)
	return out


## Střed jezírka ve světě.
func pond_center(slot: int) -> Vector2:
	return _pos[_pond_rock[slot]]


## Místo, kde stojí tělo o poloměru body u okraje jezírka, na straně k from. Střed jezírka je
## neprůchodný, cesta k němu by nevedla.
func pond_edge(slot: int, from: Vector2, body: float) -> Vector2:
	var index := _pond_rock[slot]
	var away := from - _pos[index]
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	return _pos[index] + away.normalized() * (_radius[_kind[index]] + body + TOUCH_PX)


## Všechny kameny ve všech jezírkách na začátku levelu.
func gem_total() -> int:
	return _gem_total


## Výměna u jezírka: postava vezme nejdražší kámen, který v jezírku byl, a nesený (held, -1 je
## prázdná ruka) v něm nechá. Vrátí vzatý materiál. Do prázdného jezírka se nesený kámen jen
## odloží a vrátí se -1, s prázdnou rukou se tam nestane nic.
## Do bezedného dolu nic dát nejde: levnější kámen z ruky se vymění za materiál dolu
## a zmizí, stejný nebo dražší zůstane v ruce a vrátí se held.
func swap_gem(slot: int, held: int) -> int:
	if bottomless:
		var own := _pond_mat[slot]
		if held >= 0 and _points[held] >= _points[own]:
			return held
		return own
	var best := pond_best(slot)
	if best < 0 and held < 0:
		return -1
	var gems := _pond_gems[slot]
	var at := gems.find(best) if best >= 0 else -1
	if at >= 0:
		gems.remove_at(at)
	_pond_gems[slot] = gems
	if held >= 0:
		_keep_gem(slot, held)
	_refresh_pond(slot)
	return best


## Ukradený kámen doletěl zpátky do jezírka, ze kterého ho postava vzala.
func return_gem(slot: int, mat: int) -> void:
	if slot < 0 or slot >= _pond_gems.size() or mat < 0:
		return
	_keep_gem(slot, mat)
	_refresh_pond(slot)


## Bezedný důl si žádný kámen nenechá, ani ukradený, který k němu doletí zpátky.
func _keep_gem(slot: int, mat: int) -> void:
	if bottomless:
		return
	var gems := _pond_gems[slot]
	gems.append(mat)
	_pond_gems[slot] = gems


## Místo ve světě, kam dopadne vracený kámen: další volné místo jezírka.
func gem_home(slot: int) -> Vector2:
	var index := _pond_rock[slot]
	return _pos[index] + _gem_spot(slot, pond_left(slot)).rotated(_turn[index])


## Místo kamene v jezírku. Nad GEM_SPOTS se místa opakují, každé kolo o kus posunuté.
func _gem_spot(slot: int, gem: int) -> Vector2:
	return _gem_pos[slot * GEM_SPOTS + gem % GEM_SPOTS] + GEM_STACK * float(gem / GEM_SPOTS)


func _refresh_pond(slot: int) -> void:
	var node: Node2D = _pond_nodes.get(slot)
	if node != null:
		_sync_pond(node, slot)


## Jezírka s materiálem: poloha ve světě, číslo materiálu a jezírka, po trojicích [pos, mat, slot].
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


func _sync_pond(node: Node2D, slot: int) -> void:
	if _crystal == null or slot >= _pond_mat.size() or _pond_mat[slot] < 0:
		return
	var holder := node.get_node_or_null("Gems") as Node2D
	if holder == null:
		return
	# Bezedné jezírko ukazuje GEMS_IN_POND svého materiálu a za nimi kameny vložené navíc.
	# Důl svůj materiál ukazuje obarvenými stěnami.
	var own := GEMS_IN_POND if bottomless and not _is_mine(_pond_kind) else 0
	var gems := _pond_gems[slot]
	var count := own + gems.size()
	_match_gems(holder, count)
	var size := clampf(sqrt(float(GEMS_IN_POND) / float(maxi(count, 1))), GEM_SHRINK, 1.0)
	for i in count:
		var sprite := holder.get_child(i) as Sprite2D
		var spin := _gem_rot[slot * GEM_SPOTS + i % GEM_SPOTS]
		sprite.position = _gem_spot(slot, i)
		sprite.rotation = spin
		sprite.scale = Vector2(size, size)
		sprite.visible = true
		_crystal.paint(sprite, _pond_mat[slot] if i < own else gems[i - own], 0.0, spin)


func _match_gems(holder: Node2D, count: int) -> void:
	while holder.get_child_count() > count:
		var extra := holder.get_child(holder.get_child_count() - 1)
		holder.remove_child(extra)
		extra.queue_free()
	while holder.get_child_count() < count:
		holder.add_child(_crystal.make_sprite())


## Skála stěny, než se rozhodne, jestli se postaví.
class WallRock:
	var kind := 0
	var variant := 0
	var turn := 0.0
	var pos := Vector2.ZERO
