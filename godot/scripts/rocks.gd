extends "res://scripts/layered_props.gd"

## Varianta bez obrysu v katalogu bere kruh o tolik větší než jmenovitá pata.
const FOOT_MARGIN := 1.4
## Do této výšky je skála pod postavou a jde přeskočit. Vyšší je nad ní.
const LOW := 1.5
## Lávová puklina: vrstvy pod zemí, žár pulzuje. Svit vrstev od okraje ke dnu.
const CRACK_SHADER := "res://shaders/crack_layer.gdshader"
const CRACK_GLOW: Array[float] = [0.35, 0.6, 1.0]
## Nejdelší posun vrstvy pukliny v px. O tolik hlubší vrstvy sahají pod kůru, viz MAX_SHIFT
## v gen_crack.py.
const CRACK_MAX_SHIFT := 22.0
## Barvy skal na mapě, viz paint_chart.
const CHART_ROCK := Color(0.55, 0.53, 0.5)
const CHART_CRACK := Color(0.85, 0.36, 0.12)
const CHART_LOG := Color(0.33, 0.24, 0.17)
const CHART_SPRING := Color(0.2, 0.47, 0.6)
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
## Kruhy (střed x, y a poloměr v px), kam nesmí zasahovat pata skály: vtok řeky od souseda
## musí zůstat průchozí (River.clear_spots). Nastaví svět před sázením.
var keep_clear := PackedVector3Array()
## Řeka čtverce. Nastaví svět před sázením stromů.
var river


## Přírodní skály podle povrchu, hned po terénu. Řeka je pak obteče a postaví k nim
## prameniště. Nesahá na scénu, smí běžet ve vlákně.
func plant(map: MapData, rng: RandomNumberGenerator) -> void:
	if _kinds.is_empty():
		return
	_begin_plant(map)
	_scatter(map, rng)


## Mimo kruhy keep_clear a rozestup podle povrchu. Skála
## nesmí ležet na kmeni a od pukliny drží CRACK_GAP_M. Puklina se zkouší po celé délce, viz _crack_fits.
func _fits(pos: Vector2, kind: int, map: MapData) -> bool:
	for spot in keep_clear:
		var reach := spot.z + _kind_foot[kind]
		if pos.distance_squared_to(Vector2(spot.x, spot.y)) < reach * reach:
			return false
	if _is_crack(kind):
		return super._fits(pos, kind, map) and _crack_fits(pos, kind, map)
	if not super._fits(pos, kind, map):
		return false
	return _capsule_at[kind] >= 0 or not near_log(pos, _radius[kind], true)


## Vybere natočení a variantu pukliny podle polohy (náhodu sázení nebere) a zkusí, jestli
## kapsle po celé délce leží na průchozím povrchu mapy a CRACK_GAP_M od
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
			if _crowded_by(spot, radius + gap):
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
		# Vrstvy pukliny jdou pod zem: nejhlubší se kreslí první, okraj na zemi přes ně.
		var sprites: Array[Sprite2D] = []
		for child in node.get_children():
			if child is Sprite2D:
				sprites.append(child)
		for layer in sprites.size():
			sprites[layer].set_meta("layer", layer)
			node.move_child(sprites[layer], 0)
	return node


## Skála je plná od země, její stín se od paty neodtrhne.
func _solid_shadow() -> bool:
	return true


func _is_crack(kind: int) -> bool:
	return kind >= 0 and kind < _kinds.size() and bool(_kinds[kind].get("crack", false))


func _is_spring(kind: int) -> bool:
	return kind >= 0 and kind < _kinds.size() and bool(_kinds[kind].get("spring", false))


## Vejde se prameniště name na pos? Bez jiné skály v dosahu jeho paty.
## Volá ho řeka ve vlákně, po plant.
func spring_room(name: String, pos: Vector2) -> bool:
	var kind := int(_kind_of.get(name, -1))
	if not _is_spring(kind):
		return false
	return not _crowded_by(pos, _kind_foot[kind])


## Dosah paty prameniště name v px, 0 když takové není.
func spring_reach(name: String) -> float:
	var kind := int(_kind_of.get(name, -1))
	return _kind_foot[kind] if _is_spring(kind) else 0.0


## Prameniště name na pos, otočené o turn (řeka teče ve směru turn). variant je náhoda
## varianty od řeky, ať je čtverec po načtení stejný. Vrátí false, když se nevejde.
func place_spring(name: String, pos: Vector2, turn: float, variant: int) -> bool:
	if not spring_room(name, pos):
		return false
	var kind := int(_kind_of[name])
	_keep_shaped(kind, pos, posmod(variant, int(_kinds[kind]["variants"])), turn)
	return true


## Vrstvy pod zemí: puklina.
func _is_pit(kind: int) -> bool:
	return _is_crack(kind)


## Vrstvy pukliny mají vždycky vlastní shader z katalogu, žhne i bez posunu výšky. Tady okraje
## spritů podle posunu.
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
		sprite.material = info["material"]
		var height := float(info["height"])
		var rect := sprite.get_rect().grow(ObjectLayers.vertex_pad(_fitted_view, absf(height)))
		RenderingServer.canvas_item_set_custom_rect(sprite.get_canvas_item(), true, rect)


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
	if bool(info.get("spring", false)):
		entry["spring"] = true
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


## Nejdál od středu skály, kam sahá (bez těla). Bod dál od všech skal avoid neposune.
func reach() -> float:
	return _foot


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


## Skály do mapy (MiniMap.chart): dlaždice pod obrysem obarví. Skála je šedá, puklina žhne,
## padlý strom je tmavé dřevo. Volá se ve vlákně tvorby čtverce, polohy jsou ještě bez posunu
## čtverce.
func paint_chart(chart: Image) -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var side := chart.get_width()
	for index in _pos.size():
		var kind := _kind[index]
		var color := CHART_ROCK
		if _is_crack(kind):
			color = CHART_CRACK
		elif _is_spring(kind):
			color = CHART_SPRING
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

