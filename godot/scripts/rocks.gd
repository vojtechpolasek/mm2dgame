extends "res://scripts/layered_props.gd"

const Crystal := preload("res://scripts/crystal.gd")
const BasinCompass := preload("res://scripts/basin_compass.gd")

## Kámen dopadl do kotliny. mat je číslo materiálu, pos místo dopadu ve světě.
signal settled(mat: int, pos: Vector2)

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
## Jedna prázdná kotlina na mapu. Do pásu ani do šancí povrchu nepatří.
const BASIN := "kotlina"
## Jezírko má počet podle vzácnosti materiálu, ne šanci v povrchu.
const POND := "jezirko"
## Na mapě 64 má nejběžnější materiál POND_COMMON jezírek a nejvzácnější POND_RARE.
const POND_BASE := 64
const POND_COMMON := 3
const POND_RARE := 2
## Počet roste se stranou mapy na tuto mocninu. Jedna je lineárně, dvě by byla plocha.
const POND_GROWTH := 1.0
## Volný kruh kolem kotliny v metrech. Hráč se objeví u kotliny a má kudy projít.
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
## Jezírka, která nejsou bezedná, se vybírají celá, proto jich je méně: CAPPED_FIRST při
## FIRST_MATERIALS materiálech, CAPPED_LAST při všech, mezi tím rovnoměrně.
const CAPPED_FIRST := 6
const CAPPED_LAST := 15
const CAPPED_FROM := 2
## Kamenů v jezírku, které není bezedné, podle pořadí materiálu od nejběžnějšího: od
## FEWER_GEMS[0]. materiálu o jeden méně, od FEWER_GEMS[1]. ještě o jeden.
const FEWER_GEMS: Array[int] = [6, 10]
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
var _basin_kind := -1
var _basin_index := -1
var _basin_node: Node2D
## U každé skály číslo jezírka, nebo -1. Dál už jen jezírka a kameny v nich.
var _pond_slot := PackedInt32Array()
var _pond_rock := PackedInt32Array()
var _pond_mat := PackedInt32Array()
var _gem_pos := PackedVector2Array()
var _gem_rot := PackedFloat32Array()
## Bezedné jezírko má svého materiálu pořád dost. Jinak má kameny jen v _pond_gems a ubývají.
## Nastaví svět.
var bottomless := true
## Kameny v jezírku podle pořadí, ve kterém do něj přišly. Bezedné tu má jen kameny vložené
## navíc, svůj materiál nepočítá.
var _pond_gems: Array[PackedInt32Array] = []
## Všechny kameny ve všech jezírkách na začátku. Výměny a krádeže je jen přesouvají.
var _gem_total := 0
## Materiál -> úhel šipky na kotlině, kam naposledy ukazovala. Když materiál v žádném jezírku
## není, šipka tam zůstane prázdná.
var _compass_last := {}
## Zobrazené jezírko -> jeho uzel, ať jde po sebrání a vrácení kamene hned překreslit.
var _pond_nodes := {}
var _deposit_mat := PackedInt32Array()
var _deposit_pos := PackedVector2Array()
var _deposit_rot := PackedFloat32Array()


## Nejdřív kotlina u středu, potom jezírka, potom pás kolem mapy, potom skály podle povrchu.
## Stromy se sází až potom. Nesahá na scénu, smí běžet ve vlákně.
func plant(map: MapData, rng: RandomNumberGenerator) -> void:
	_pond_kind = int(_kind_of[POND]) if _kind_of.has(POND) else -1
	_basin_kind = int(_kind_of[BASIN]) if _kind_of.has(BASIN) else -1
	if _kinds.is_empty():
		return
	_begin_plant(map)
	_place_basin(map, rng)
	_place_ponds(map, rng)
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


## Jezírka dostanou jen materiály s nejmenším počtem bodů, tolik, kolik dovolí level.
## Ostatní na mapě nejsou, takže je nejde sebrat.
func set_available(count: int) -> void:
	_available = count


## Materiály, které mají na mapě jezírka, od nejlevnějšího. Každý dostane svou příšeru.
func pond_materials() -> PackedInt32Array:
	var count := _by_points.size() if _available < 0 else mini(_available, _by_points.size())
	return _by_points.slice(0, count)


## Jezírka jednoho materiálu. Nejběžnější (vzácnost 0) má na mapě 64 POND_COMMON, nejvzácnější (1)
## POND_RARE, mezi tím klesá druhá mocnina obyčejnosti. Větší mapa počet násobí podle POND_GROWTH.
static func pond_count(rarity: float, size: int) -> int:
	var common := clampf(1.0 - rarity, 0.0, 1.0)
	var on_base := float(POND_RARE) + float(POND_COMMON - POND_RARE) * common * common
	var grow := pow(float(size) / float(POND_BASE), POND_GROWTH)
	return maxi(roundi(on_base * grow), 1)


## Jedna kotlina přesně uprostřed mapy. Střed je souš, tu tam drží generátor mapy
## (MapGenerator.CENTER_CLEAR). Kdyby přesto byla voda, bere nejbližší souš. Obrys je plný,
## dovnitř se nevstupuje.
func _place_basin(map: MapData, rng: RandomNumberGenerator) -> void:
	if not _kind_of.has(BASIN):
		return
	var kind: int = _kind_of[BASIN]
	var tile := float(TerrainCatalog.TILE_SIZE)
	var center := Vector2(map.size, map.size) * tile * 0.5
	if _on_land(map, center):
		_keep(kind, center, rng)
		return
	var spot := _nearest_land(map)
	if spot < 0:
		return
	var x := spot % map.size
	var y := spot / map.size
	_keep(
		kind,
		Vector2((float(x) + rng.randf_range(0.35, 0.65)) * tile, (float(y) + rng.randf_range(0.35, 0.65)) * tile),
		rng,
	)


## Každý materiál na mapě má jezírka ve svém mezikruží kolem kotliny, vzácnější dál.
## Pásy se roztáhnou na materiály, které level pustil, a sousedé se jen dotýkají.
## Jezírka drží rozestup POND_GAP, takže mezi nimi vždycky jde projít.
func _place_ponds(map: MapData, rng: RandomNumberGenerator) -> void:
	if _pond_kind < 0 or _by_points.is_empty():
		return
	var tile := float(TerrainCatalog.TILE_SIZE)
	var origin := Vector2(float(map.size) * tile, float(map.size) * tile) * 0.5
	if _basin_index >= 0:
		origin = _pos[_basin_index]
	var materials := _by_points.size()
	var count := materials if _available < 0 else mini(_available, materials)
	var capped := capped_ponds(count, materials)
	for order in count:
		var mat := _by_points[order]
		var want := pond_count(material_rarity(order, materials), map.size) if bottomless else capped[order]
		var ring := pond_annulus(order, count, map.size) * tile
		_place_ring(map, rng, mat, want, origin, ring.x, ring.y)


## Počty jezírek materiálů od nejběžnějšího, když jezírka nejsou bezedná. Celkem jich je mezi
## CAPPED_FIRST a CAPPED_LAST podle počtu materiálů na mapě. Každý materiál má aspoň jedno,
## zbytek se rozdělí podle běžnosti jako v pond_count.
static func capped_ponds(count: int, materials: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if count <= 0:
		return out
	var share := clampf(float(count - CAPPED_FROM) / float(maxi(materials - CAPPED_FROM, 1)), 0.0, 1.0)
	var total := maxi(roundi(lerpf(CAPPED_FIRST, CAPPED_LAST, share)), count)
	var weights := PackedFloat32Array()
	var sum := 0.0
	for order in count:
		var common := 1.0 - material_rarity(order, materials)
		weights.append(float(POND_RARE) + float(POND_COMMON - POND_RARE) * common * common)
		sum += weights[order]
	# Každý materiál jedno, zbytek po celých dílech a zbylá jezírka těm s největším zbytkem.
	var extra := total - count
	var rests := PackedFloat32Array()
	var given := 0
	for order in count:
		var part := float(extra) * weights[order] / sum
		out.append(1 + floori(part))
		rests.append(part - floorf(part))
		given += floori(part)
	var order_by_rest: Array[int] = []
	for order in count:
		order_by_rest.append(order)
	order_by_rest.sort_custom(func(a: int, b: int) -> bool: return rests[a] > rests[b])
	for i in extra - given:
		out[order_by_rest[i]] += 1
	return out


## Kamenů v plném jezírku, které není bezedné, podle pořadí materiálu od nejběžnějšího.
static func pond_gems(order: int) -> int:
	var gems := GEMS_IN_POND
	for from in FEWER_GEMS:
		if order + 1 >= from:
			gems -= 1
	return maxi(gems, 1)


func _pond_cell(x: int, y: int, size: int) -> bool:
	var edge := mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
	return float(edge) >= _rim_guard(size)


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


## Stojí blíž než gap nějaký už postavený objekt? Při sázení jezírek jsou to jen kotlina a jezírka.
func _near_object(pos: Vector2, gap: float) -> bool:
	var grid := _grid
	var span := ceili(gap / grid.cell)
	var side := grid.side
	var gx := clampi(int(pos.x / grid.cell), 0, side - 1)
	var gy := clampi(int(pos.y / grid.cell), 0, side - 1)
	for cy in range(maxi(gy - span, 0), mini(gy + span, side - 1) + 1):
		for cx in range(maxi(gx - span, 0), mini(gx + span, side - 1) + 1):
			var item := grid.head[cy * side + cx]
			while item >= 0:
				if pos.distance_squared_to(_pos[item]) < gap * gap:
					return true
				item = grid.next[item]
	return false


## Vzácnost podle pořadí od nejlevnějšího, 0 až 1. Na bodech nezávisí, takže úprava bodů
## nehne s rozmístěním jezírek. Pořadí se bere ze všech materiálů, ne jen z dostupných.
static func material_rarity(order: int, count: int) -> float:
	return clampf(float(order) / float(maxi(count - 1, 1)), 0.0, 1.0)


## Mezikruží jezírek daného pořadí: vnitřní a vnější vzdálenost od kotliny v metrech.
## count je počet materiálů, které na mapě mají jezírka. Pásy jsou stejně široké a sousedé
## se jen dotýkají. Nejběžnější začíná za volným kruhem, nejdražší z nich končí u pásu skal.
static func pond_annulus(order: int, count: int, size: int) -> Vector2:
	var reach := maxf(float(size) * 0.5 - _rim_guard(size), POND_CLEAR)
	var bands := maxi(count, 1)
	var width := (reach - POND_CLEAR) / float(bands)
	var inner := POND_CLEAR + float(clampi(order, 0, bands - 1)) * width
	return Vector2(inner, inner + width)


## Odhad vzdálenosti nejbližšího jezírka daného pořadí od kotliny v metrech. Jezírka jsou
## rozložená po mezikruží, nejbližší je v průměru kousek za vnitřní hranou.
## bands je počet materiálů na mapě, materials počet všech v katalogu. Počet jezírek se
## bere z celého katalogu, ať vzácnost neposkočí jen proto, že dražší materiály chybí.
static func pond_distance(order: int, bands: int, materials: int, size: int) -> float:
	var ring := pond_annulus(order, bands, size)
	var rarity := material_rarity(order, materials)
	return ring.x + (ring.y - ring.x) / float(pond_count(rarity, size) + 1)


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
	_compass_last.clear()
	_pond_nodes.clear()
	_gem_pos = PackedVector2Array()
	_gem_rot = PackedFloat32Array()
	_deposit_mat = PackedInt32Array()
	_deposit_pos = PackedVector2Array()
	_deposit_rot = PackedFloat32Array()
	_basin_index = -1
	_basin_node = null


func _keep_shaped(kind: int, pos: Vector2, variant: int, turn: float) -> void:
	super._keep_shaped(kind, pos, variant, turn)
	_pond_slot.append(-1)
	if kind == _basin_kind:
		_basin_index = _pos.size() - 1


func _on_land(map: MapData, pos: Vector2) -> bool:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var x := int(pos.x / tile)
	var y := int(pos.y / tile)
	if x < 0 or y < 0 or x >= map.size or y >= map.size:
		return false
	return _walkable[map.terrain[y * map.size + x]] == 1


## Nejbližší schůdná dlaždice ke středu mapy. Prochází čtvercové prstence, ne celou mapu najednou.
func _nearest_land(map: MapData) -> int:
	var half := map.size / 2
	for radius in map.size:
		var y0 := maxi(half - radius, 0)
		var y1 := mini(half + radius, map.size - 1)
		var x0 := maxi(half - radius, 0)
		var x1 := mini(half + radius, map.size - 1)
		var best := -1
		var best_dist := 2147483647
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if radius > 0 and y != y0 and y != y1 and x != x0 and x != x1:
					continue
				var index := y * map.size + x
				if _walkable[map.terrain[index]] != 1:
					continue
				var dx := x - half
				var dy := y - half
				var dist := dx * dx + dy * dy
				if dist < best_dist:
					best_dist = dist
					best = index
		if best >= 0:
			return best
	return -1


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
	if kind == _pond_kind or kind == _basin_kind:
		var holder := Node2D.new()
		holder.name = "Gems"
		node.add_child(holder)
	if kind == _basin_kind:
		var compass := BasinCompass.new()
		compass.name = "Compass"
		compass.setup(_top[kind], _crystal)
		node.add_child(compass)
	return node


func acquire(index: int) -> Node2D:
	var node := super.acquire(index)
	if index == _basin_index:
		_basin_node = node
		_sync_deposits()
		_sync_compass()
	var slot := _pond_slot[index] if index < _pond_slot.size() else -1
	if slot >= 0:
		_pond_nodes[slot] = node
		_sync_pond(node, slot)
	return node


func release(index: int, node: Node2D) -> void:
	if node == _basin_node:
		_basin_node = null
	var slot := _pond_slot[index] if index < _pond_slot.size() else -1
	if slot >= 0:
		_pond_nodes.erase(slot)
	super.release(index, node)


func _scatter_kind(kind: int) -> bool:
	return kind != _pond_kind


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
	if not _on_land(map, pos):
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
	var gx := clampi(int(pos.x / grid.cell), 0, side - 1)
	var gy := clampi(int(pos.y / grid.cell), 0, side - 1)
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
	var gx := clampi(int(pos.x / grid.cell), 0, side - 1)
	var gy := clampi(int(pos.y / grid.cell), 0, side - 1)
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
				var limit := _sample(_bound, kind, _variant[item], _turn[item], delta.angle())
				var dist_sq := delta.length_squared()
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


## Všechny kameny ve všech jezírkách na začátku levelu.
func gem_total() -> int:
	return _gem_total


## Výměna u jezírka: postava vezme nejdražší kámen, který v jezírku byl, a nesený (held, -1 je
## prázdná ruka) v něm nechá. Bezedné jezírko si nechá jen kámen dražší, než je jeho materiál,
## levnější zmizí. Vrátí vzatý materiál. Do prázdného jezírka se nesený kámen jen odloží
## a vrátí se -1, s prázdnou rukou se tam nestane nic.
func swap_gem(slot: int, held: int) -> int:
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
	_sync_compass()
	return best


## Ukradený kámen doletěl zpátky do jezírka, ze kterého ho postava vzala.
func return_gem(slot: int, mat: int) -> void:
	if slot < 0 or slot >= _pond_gems.size() or mat < 0:
		return
	_keep_gem(slot, mat)
	_refresh_pond(slot)
	_sync_compass()


func _keep_gem(slot: int, mat: int) -> void:
	if bottomless and _points[mat] <= _points[_pond_mat[slot]]:
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


## Šipky na kotlině, jedna na materiál, po trojicích [úhel od středu kotliny, materiál, leží
## někde v jezírku]. Šipka míří k jezírku nejblíž kotlině, kde materiál zrovna leží. Když není
## v žádném (je v kotlině nebo ho někdo nese), zůstane mířit, kam mířila, a je prázdná.
func compass_targets() -> Array:
	var targets := []
	if _basin_index < 0 or _crystal == null:
		return targets
	var origin := _pos[_basin_index]
	var nearest := {}
	for slot in _pond_mat.size():
		if _pond_mat[slot] < 0:
			continue
		var pos := _pos[_pond_rock[slot]]
		var held := Array(_pond_gems[slot])
		if bottomless:
			held.append(_pond_mat[slot])
		for mat: int in held:
			if not nearest.has(mat) or origin.distance_squared_to(pos) < origin.distance_squared_to(nearest[mat]):
				nearest[mat] = pos
	for mat in pond_materials():
		if nearest.has(mat):
			_compass_last[mat] = ((nearest[mat] as Vector2) - origin).angle()
		if _compass_last.has(mat):
			targets.append([_compass_last[mat], mat, nearest.has(mat)])
	return targets


func _sync_compass() -> void:
	if _basin_node == null:
		return
	var compass := _basin_node.get_node_or_null("Compass") as BasinCompass
	if compass == null:
		return
	# Kotlina je otočená, šipky míří ve světě.
	compass.rotation = -_turn[_basin_index]
	compass.show_targets(compass_targets())


## Střed kotliny ve světě. Bez kotliny Vector2.INF.
func basin_position() -> Vector2:
	return _pos[_basin_index] if _basin_index >= 0 else Vector2.INF


## Jezírka s materiálem: poloha ve světě, číslo materiálu a jezírka, po trojicích [pos, mat, slot].
func pond_spots() -> Array:
	var spots := []
	for slot in _pond_rock.size():
		if _pond_mat[slot] >= 0:
			spots.append([_pos[_pond_rock[slot]], _pond_mat[slot], slot])
	return spots


func touches_basin(pos: Vector2, body: float) -> bool:
	if _basin_index < 0:
		return false
	return _touches(pos, _basin_index, body)


## Náhodný bod ve světě uvnitř středového kruhu kotliny. Souřadnice jsou jako u postavy.
func basin_spot(gem_radius: float, rng: RandomNumberGenerator) -> Vector2:
	var mouth := 0.0
	if _basin_kind >= 0 and _basin_kind < _mouth.size():
		mouth = _mouth[_basin_kind]
	var room := maxf(mouth - gem_radius - 1.0, 0.0)
	var local := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * room
	return _pos[_basin_index] + local.rotated(_turn[_basin_index])


## Kámen zůstal v kotlině. world je ve stejných souřadnicích jako basin_spot, rot je otočení ve světě.
func settle(mat: int, world: Vector2, rot: float) -> void:
	if _basin_index < 0:
		return
	var local := (world - _pos[_basin_index]).rotated(-_turn[_basin_index])
	_deposit_mat.append(mat)
	_deposit_pos.append(local)
	_deposit_rot.append(rot - _turn[_basin_index])
	_sync_deposits()
	if _crystal != null:
		Sound.at("basin/" + _crystal.name_of(mat), world)
	settled.emit(mat, world)


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
	var own := GEMS_IN_POND if bottomless else 0
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


func _sync_deposits() -> void:
	if _basin_node == null or _crystal == null:
		return
	var holder := _basin_node.get_node_or_null("Gems") as Node2D
	if holder == null:
		return
	_match_gems(holder, _deposit_mat.size())
	for i in _deposit_mat.size():
		var sprite := holder.get_child(i) as Sprite2D
		sprite.position = _deposit_pos[i]
		sprite.rotation = _deposit_rot[i]
		sprite.visible = true
		_crystal.paint(sprite, _deposit_mat[i], 0.0, _deposit_rot[i])


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
