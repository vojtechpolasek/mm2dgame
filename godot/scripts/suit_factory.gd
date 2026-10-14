extends "res://scripts/factory.gd"

## Továrna typu hry Skafandry. Na každé straně kromě výstupku jsou dva zásobníky vedle sebe
## (base_suits.png), zásobník se dá jen tam, kam patří. Před každým použitým zásobníkem je
## cedulka: obrázek materiálu a neonové číslo, kolik kamenů ještě chybí.
## Kámen dopadne na vnější konec zásobníku a dojede ke kolu, tam zůstane a další se hromadí
## za ním. Až jsou plné všechny zásobníky, rozjedou se naráz, kameny zajedou pod kolo,
## uprostřed se zvedne prach, továrna drtí (sfx/crush) a pak zafouká vítr (sfx/wind).
## Výstupkem (výdejnou) vede pás na skafandry. Kámen donesený k výstupku jde na něj, pás chce
## po jednom kameni z receptu. Plný se rozjede sám, kameny se rozdrtí bez prachu
## (sfx/crush_short) a výstupkem vyjede prázdný skafandr. Leží na výstupku vedle pásu, dokud
## si ho postava nevezme. Pás pak chce znovu stejný recept. Až je vzduch čistý, skafandry
## se na výstupek vracejí (store_suit).
## Zásobník je číslo strana * 2 + z: strana k míří na k * 45°, z 0 je na záporné kolmici
## (-sin, cos), 1 na kladné (tovarna.json, suits). Pás výstupkem je DOCK_LANE.

const Figure := preload("res://scripts/figure.gd")

## Kámen dopadl do obyčejného zásobníku. world je místo dopadu.
signal stored(mat: int, world: Vector2)
## Vítr dofoukal, vzduch je čistý.
signal cleaned
## Skafandr se vrátil na výstupek.
signal suit_stored

## Pás výstupkem na skafandry. Strana 2 je jih, pás jde jejím středem.
const DOCK_LANE := 4
## Kameny v zásobníku jsou trochu menší a leží přes sebe, ať se jich vejde pět.
const STONE_SCALE := 0.85
## Rozestup kamenů na hromadě v px, nejvýš a nejmíň.
const STACK_GAP := Vector2(7.0, 20.0)
## Při velkém spuštění jedou zásobníky tolikrát rychleji.
const RUN_BOOST := 1.6
## Délka zvuků drcení v sekundách (tools/gen_sounds.py) a jak dlouho po začátku větru je
## vzduch čistý.
const CRUSH_TIME := 4.6
const CRUSH_SHORT_TIME := 2.4
const WIND_CLEAR := 2.2
## Skafandr vyjede výstupkem za tolik sekund a lehne si na desku vedle pásu. Místa jsou ve
## dvou řadách po stranách pásu, SUIT_ROWS za sebou, SUIT_SIDE poloviční šířky výstupku od
## jeho osy. Víc skafandrů se položí přes ta místa trochu posunutých.
const SUIT_SLIDE := 1.1
const SUIT_ROWS := 3
const SUIT_SIDE := 0.58
const SUIT_SCALE := 0.75
## Řady leží na desce výstupku: první tolik px za začátkem výstupku (ten zajíždí pod zeď
## továrny), poslední tolik px před jeho koncem.
const SUIT_EDGE := Vector2(30.0, 16.0)
## Cedulka: obrázek a číslo na ose zásobníku, tolik px od středu. U výstupku jsou obrázky
## receptu vedle sebe kousek za jeho koncem a čísla pod nimi.
const SIGN_AT := 226.0
const SIGN_STEP := 32.0
const DOCK_SIGN_PAST := 26.0
const DOCK_SIGN_STEP := 34.0
const SIGN_ICON := 0.72
const NEON := Color(0.55, 1.0, 0.95)
const NEON_GLOW := Color(0.1, 0.85, 1.0, 0.55)
const NEON_DONE := Color(0.55, 1.0, 0.45)
const NEON_DONE_GLOW := Color(0.25, 1.0, 0.2, 0.55)

var _lane_offset := 25.0
var _lane_half := 15.0
var _dock_from := 182.0
var _dock_to := 284.0
var _dock_half := 46.0
var _apothem := 192.0
## Konec pásu výstupkem, px od středu.
var _dock_outer := 275.0
## Použité zásobníky podle čísla.
var _lanes := {}
var _rng := RandomNumberGenerator.new()
## Velké spuštění běží. Potom (_done) už zásobníky nic nepřijmou a skafandry se jen vracejí.
var _running := false
var _done := false
var _suits_lying: Array[Sprite2D] = []


## plan jsou dvojice [materiál, počet] pro obyčejné zásobníky, recipe materiály skafandru.
## Zásobníky se rozdělí rovnoměrně kolem továrny, materiály mezi ně náhodně.
func configure(info: Dictionary, plan: Array, recipe: PackedInt32Array, seed_value: int) -> void:
	_rng.seed = seed_value
	var suits: Dictionary = info.get("suits", {})
	_lane_offset = float(suits.get("lane_offset_px", 25.0))
	_lane_half = float(suits.get("lane_half_px", 15.0))
	var dock: Dictionary = info.get("dock_px", {})
	_dock_from = float(dock.get("from", 182.0))
	_dock_to = float(dock.get("to", 284.0))
	_dock_half = float(dock.get("half", 46.0))
	_apothem = float(info.get("apothem_px", 192.0))
	var belt: Dictionary = suits.get("dock_belt", {})
	_dock_outer = float(belt.get("outer_px", _dock_to - 10.0))
	_base_material.set_shader_parameter("lanes", 2)
	_base_material.set_shader_parameter("lane_offset", _lane_offset)
	_base_material.set_shader_parameter("belt_half", _lane_half)
	_base_material.set_shader_parameter("dock_outer", _dock_outer)
	_base_material.set_shader_parameter("dock_drum", float(belt.get("drum_px", _dock_outer - 12.0)))
	var normal: Array[int] = []
	for side in 8:
		if side == 2:
			continue
		for z in 2:
			normal.append(side * 2 + z)
	# Kolem dokola od náhodného místa, ať použité zásobníky nejsou natlačené na jedné straně.
	normal.sort_custom(func(a: int, b: int) -> bool: return _lane_angle(a) < _lane_angle(b))
	var count := mini(plan.size(), normal.size())
	var start := _rng.randi() % normal.size()
	var picked: Array[int] = []
	for i in count:
		picked.append(normal[(start + int(float(i) * float(normal.size()) / float(count))) % normal.size()])
	var order := range(count)
	for i in range(count - 1, 0, -1):
		var swap := _rng.randi_range(0, i)
		var saved: int = order[i]
		order[i] = order[swap]
		order[swap] = saved
	for i in count:
		var pair: Array = plan[order[i]]
		_add_lane(picked[i], {int(pair[0]): int(pair[1])}, false)
	var need := {}
	for mat in recipe:
		need[mat] = int(need.get(mat, 0)) + 1
	_add_lane(DOCK_LANE, need, true)
	_straighten()


func _add_lane(id: int, need: Dictionary, special: bool) -> void:
	var lane := Lane.new()
	lane.id = id
	lane.need = need.duplicate()
	lane.special = special
	lane.capacity = 0
	for mat: int in need:
		lane.capacity += int(need[mat])
	_lanes[id] = lane
	_make_sign(lane)


## Kolik kamenů chtějí obyčejné zásobníky dohromady.
func total_needed() -> int:
	var total := 0
	for lane: Lane in _lanes.values():
		if not lane.special:
			total += lane.capacity
	return total


## Zásobník na straně, u které stojí postava (from ve světě), kam se kámen mat ještě vejde.
## Ze dvou se vezme ten, jehož osa je k postavě blíž. U výstupku je to pás na skafandry.
## Jinak -1, kámen zůstane v ruce.
func lane_for(from: Vector2, mat: int) -> int:
	if _done or _running:
		return -1
	var local := to_local(from)
	var side := posmod(roundi(local.angle() / (PI * 0.25)), 8)
	var ids := [DOCK_LANE] if side == 2 else [side * 2, side * 2 + 1]
	var best := -1
	var best_gap := INF
	for id: int in ids:
		var lane: Lane = _lanes.get(id)
		if lane == null or lane.busy or int(lane.claimed.get(mat, 0)) >= int(lane.need.get(mat, 0)):
			continue
		var gap := absf(local.dot(_lane_cross(lane.id)) - _lane_shift(lane.id))
		if gap < best_gap:
			best_gap = gap
			best = lane.id
	return best


## Materiály, které obyčejným zásobníkům ještě chybí (nedopadly), od nejlevnějšího.
func missing() -> PackedInt32Array:
	var mats: Array[int] = []
	for lane: Lane in _lanes.values():
		if lane.special:
			continue
		for mat: int in lane.need:
			if int(lane.got.get(mat, 0)) < int(lane.need[mat]) and not mats.has(mat):
				mats.append(mat)
	mats.sort_custom(func(a: int, b: int) -> bool: return _crystal.points_of(a) < _crystal.points_of(b))
	return PackedInt32Array(mats)


## Vejde se do zásobníku id ještě kámen mat?
func accepts(id: int, mat: int) -> bool:
	var lane: Lane = _lanes.get(id)
	if _done or _running or lane == null or lane.busy:
		return false
	return int(lane.claimed.get(mat, 0)) < int(lane.need.get(mat, 0))


## Zásobník pro kámen mat, který nese vesničan: na straně u near, jinak kterýkoli, kam se
## kámen vejde, nejblíž k near. -1 když se nevejde nikam.
func lane_for_carrier(near: Vector2, mat: int) -> int:
	var here := lane_for(near, mat)
	if here >= 0:
		return here
	var best := -1
	var best_dist := INF
	for id: int in _lanes:
		if not accepts(id, mat):
			continue
		var dist := lane_front(id, 0.0).distance_squared_to(near)
		if dist < best_dist:
			best_dist = dist
			best = id
	return best


## Místo ve světě před vnějším koncem zásobníku, kde stojí tělo o poloměru body.
func lane_front(id: int, body: float) -> Vector2:
	if id == DOCK_LANE:
		return to_global(Vector2(0.0, _dock_to + body + 1.0))
	return to_global(_lane_point(id, _apothem + body + 1.0, 0.0))


## Kámen do zásobníku letí. Místo v něm je jeho, i kdyby mezitím přišel jiný hráč.
func claim(id: int, mat: int) -> void:
	var lane: Lane = _lanes.get(id)
	if lane != null:
		lane.claimed[mat] = int(lane.claimed.get(mat, 0)) + 1


## Místo ve světě, kam kámen dopadne: vnější konec zásobníku kousek za válcem, u výstupku
## konec pásu.
func lane_drop(id: int, rng: RandomNumberGenerator) -> Vector2:
	var side := rng.randf_range(-1.0, 1.0) * _lane_half * 0.3
	var along := _dock_outer - DROP_PAST_DRUM * 2.0 if id == DOCK_LANE else _drum + DROP_PAST_DRUM
	return to_global(_lane_point(id, along, side))


## Kámen dopadl do zásobníku. Dojede na své místo na hromadě a tam zůstane.
func receive_lane(id: int, mat: int, world: Vector2, rot: float) -> void:
	var lane: Lane = _lanes.get(id)
	if lane == null:
		return
	var sprite := _crystal.make_sprite()
	_riders.add_child(sprite)
	sprite.position = to_local(world)
	sprite.rotation = rot - global_rotation
	sprite.scale = Vector2.ONE * STONE_SCALE
	_crystal.paint(sprite, mat, 0.0, rot)
	var slot := lane.stones.size()
	var stone := Stone.new()
	stone.sprite = sprite
	stone.mat = mat
	stone.along = sprite.position.dot(_lane_dir(id))
	stone.stop = _stack_at(lane, slot)
	stone.wait = BELT_DELAY
	# Na hromadě se kameny střídají do stran, ať jsou vidět všechny.
	stone.aside = _lane_shift(id) + (float(slot % 3) - 1.0) * _lane_half * 0.35 + _rng.randf_range(-1.5, 1.5)
	lane.stones.append(stone)
	lane.got[mat] = int(lane.got.get(mat, 0)) + 1
	_update_sign(lane)
	if not lane.special:
		stored.emit(mat, world)


## Leží na výstupku skafandr blíž než reach od pos? Vezme ho a vrátí true. Až je vzduch
## čistý, skafandry se jen vracejí.
func take_suit(pos: Vector2, reach: float) -> bool:
	if _done or _running:
		return false
	var best := -1
	var best_dist := reach * reach
	for i in _suits_lying.size():
		var dist := _suits_lying[i].global_position.distance_squared_to(pos)
		if dist <= best_dist:
			best_dist = dist
			best = i
	if best < 0:
		return false
	var sprite := _suits_lying[best]
	_suits_lying.remove_at(best)
	sprite.queue_free()
	return true


## Vrací se skafandr: lehne si na výstupek na první volné místo.
func store_suit() -> void:
	var sprite := _suit_sprite()
	if sprite == null:
		return
	sprite.position = _suit_slot()
	_suits_lying.append(sprite)
	Sound.at("sfx/land", sprite.global_position, -2.0)
	suit_stored.emit()


## Je vzduch čistý? Pak se skafandry na výstupek vracejí.
func cleared() -> bool:
	return _done


## Dotýká se tělo o poloměru body výstupku?
func at_dock(pos: Vector2, body: float) -> bool:
	var local := to_local(pos)
	var reach := body + 4.0
	return local.y >= _dock_from and local.y <= _dock_to + reach and absf(local.x) <= _dock_half + reach


func _process(delta: float) -> void:
	super._process(delta)
	if _lanes.is_empty():
		return
	var speed := BELT_METERS * float(TerrainCatalog.TILE_SIZE) * delta
	var moved := false
	var all_full := not _running and not _done
	for lane: Lane in _lanes.values():
		var step := speed * (RUN_BOOST if lane.running and not lane.special else 1.0)
		var lane_moving := false
		for i in range(lane.stones.size() - 1, -1, -1):
			var stone: Stone = lane.stones[i]
			if stone.wait > 0.0:
				stone.wait -= delta
				lane_moving = true
				continue
			if stone.along <= stone.stop + 0.01:
				continue
			stone.along = maxf(stone.along - step, stone.stop)
			stone.sprite.position = _lane_point(lane.id, stone.along, stone.aside - _lane_shift(lane.id))
			lane_moving = true
			if lane.running and stone.along <= stone.stop + 0.01:
				lane.stones.remove_at(i)
				stone.sprite.queue_free()
				if not lane.special:
					_swirl(stone.mat)
		if lane_moving:
			_shift[lane.id] = fposmod(_shift[lane.id] + step, 4096.0)
			moved = true
		if lane.running and lane.stones.is_empty() and lane.special:
			lane.running = false
		if not lane.special and not (lane.full() and not lane_moving):
			all_full = false
		if lane.special and not lane.busy and lane.full() and not lane_moving:
			_run_special(lane)
	if moved:
		_base_material.set_shader_parameter("belt_shift", _shift)
	if all_full:
		_run_all()


## Plný pás na skafandr: kameny zajedou pod kolo, továrna je rozdrtí a výstupkem
## vyjede skafandr. Pak pás chce znovu stejný recept.
func _run_special(lane: Lane) -> void:
	lane.busy = true
	lane.running = true
	_start(lane)
	Sound.at("sfx/crush_short", global_position)
	_hide_sign(lane, true)
	await get_tree().create_timer(CRUSH_SHORT_TIME, false).timeout
	if not is_inside_tree():
		return
	_eject_suit()
	lane.got.clear()
	lane.claimed.clear()
	lane.busy = false
	if not _running and not _done:
		_hide_sign(lane, false)
		_update_sign(lane)


## Všechny obyčejné zásobníky jsou plné: rozjedou se naráz, kameny zajedou pod kolo, uprostřed
## se zvedne prach a továrna drtí. Pak zafouká vítr a po chvíli je vzduch čistý.
func _run_all() -> void:
	_running = true
	for lane: Lane in _lanes.values():
		_hide_sign(lane, true)
		if not lane.special:
			lane.running = true
			_start(lane)
	Sound.at("sfx/crush", global_position)
	await get_tree().create_timer(CRUSH_TIME, false).timeout
	if not is_inside_tree():
		return
	Sound.at("sfx/wind", global_position)
	await get_tree().create_timer(WIND_CLEAR, false).timeout
	if not is_inside_tree():
		return
	_running = false
	_done = true
	cleaned.emit()


## Kameny zásobníku pojedou až pod kolo, tam zmizí.
func _start(lane: Lane) -> void:
	var end := _ring_reach - _crystal.radius() * STONE_SCALE
	for stone: Stone in lane.stones:
		stone.stop = end
		stone.wait = 0.0


## Skafandr vyjede po pásu výstupkem a lehne si vedle pásu na první volné místo.
func _eject_suit() -> void:
	var sprite := _suit_sprite()
	if sprite == null:
		return
	var rest := _suit_slot()
	sprite.position = Vector2(0.0, _ring_reach)
	_suits_lying.append(sprite)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "position", Vector2(0.0, rest.y), SUIT_SLIDE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite, "position", rest, SUIT_SLIDE * 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: Sound.at("sfx/land", sprite.global_position, -2.0))


func _suit_sprite() -> Sprite2D:
	var sprite := Figure.gear_item(0.0)
	if sprite == null:
		return null
	_riders.add_child(sprite)
	sprite.scale = Vector2.ONE * SUIT_SCALE
	sprite.rotation = _rng.randf_range(-0.2, 0.2)
	return sprite


## První volné místo na výstupku, střídavě vlevo a vpravo od pásu, od továrny ven. Když jsou
## všechna obsazená, položí se na náhodné místo trochu posunutý.
func _suit_slot() -> Vector2:
	var near := _dock_from + SUIT_EDGE.x
	var far := _dock_to - SUIT_EDGE.y
	var step := (far - near) / float(maxi(SUIT_ROWS - 1, 1))
	var slots: Array[Vector2] = []
	for row in SUIT_ROWS:
		for side: float in [-1.0, 1.0]:
			slots.append(Vector2(side * _dock_half * SUIT_SIDE, near + step * float(row)))
	for slot in slots:
		var free := true
		for lying in _suits_lying:
			if lying.position.distance_to(slot) < step * 0.5:
				free = false
				break
		if free:
			return slot
	return slots[_rng.randi() % slots.size()] + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-6.0, 6.0))


# --- Geometrie zásobníků ---

func _lane_dir(id: int) -> Vector2:
	return Vector2.from_angle(float(id / 2) * PI * 0.25)


## Kolmice strany, od osy strany k zásobníku 1.
func _lane_cross(id: int) -> Vector2:
	var dir := _lane_dir(id)
	return Vector2(-dir.y, dir.x)


## Posun osy zásobníku od osy strany po kolmici. Pás výstupkem jde středem.
func _lane_shift(id: int) -> float:
	if id == DOCK_LANE:
		return 0.0
	return _lane_offset if id % 2 == 1 else -_lane_offset


## Bod zásobníku: along px od středu, aside px od osy zásobníku.
func _lane_point(id: int, along: float, aside: float) -> Vector2:
	return _lane_dir(id) * along + _lane_cross(id) * (_lane_shift(id) + aside)


func _lane_angle(id: int) -> float:
	var at := _lane_point(id, _drum, 0.0)
	return fposmod(at.angle(), TAU)


## Místo kamene číslo slot na hromadě. První je u kola, další za ním, rozestup podle toho,
## kolik se jich do zásobníku vejde.
func _stack_at(lane: Lane, slot: int) -> float:
	var first := _ring_reach + _crystal.radius() * STONE_SCALE * 0.2
	var last := _drum - _crystal.radius() * STONE_SCALE * 0.6
	var gap := clampf((last - first) / float(maxi(lane.capacity - 1, 1)), STACK_GAP.x, STACK_GAP.y)
	return first + gap * float(slot)


# --- Cedulky ---

func _make_sign(lane: Lane) -> void:
	var holder := Node2D.new()
	holder.name = "Sign%d" % lane.id
	add_child(holder)
	lane.sign = holder
	var mats: Array = lane.need.keys()
	mats.sort_custom(func(a: int, b: int) -> bool: return _crystal.points_of(a) < _crystal.points_of(b))
	for i in mats.size():
		var mat: int = mats[i]
		var icon_at: Vector2
		var number_at: Vector2
		if lane.special:
			icon_at = Vector2((float(i) - float(mats.size() - 1) * 0.5) * DOCK_SIGN_STEP, _dock_to + DOCK_SIGN_PAST)
			number_at = icon_at + Vector2(0.0, SIGN_STEP * 0.85)
		else:
			icon_at = _lane_point(lane.id, SIGN_AT, 0.0)
			number_at = _lane_point(lane.id, SIGN_AT + SIGN_STEP, 0.0)
		var plate := SignPlate.new()
		plate.position = icon_at
		holder.add_child(plate)
		var icon := _crystal.make_sprite()
		icon.position = icon_at
		icon.scale = Vector2.ONE * SIGN_ICON
		_crystal.paint(icon, mat, 0.0, _rng.randf() * TAU)
		holder.add_child(icon)
		var label := Label.new()
		label.label_settings = _neon(false)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = Vector2(40, 34)
		var anchor := Node2D.new()
		anchor.position = number_at
		holder.add_child(anchor)
		anchor.add_child(label)
		label.position = -label.size * 0.5
		lane.labels[mat] = anchor
	_update_sign(lane)


## Čísla ukazují, kolik kamenů ještě chybí. Hotový materiál svítí zeleně.
func _update_sign(lane: Lane) -> void:
	for mat: int in lane.labels:
		var anchor: Node2D = lane.labels[mat]
		var label := anchor.get_child(0) as Label
		var left := maxi(int(lane.need[mat]) - int(lane.got.get(mat, 0)), 0)
		label.text = str(left)
		label.label_settings = _neon(left == 0)


func _hide_sign(lane: Lane, hidden: bool) -> void:
	if lane.sign != null:
		lane.sign.visible = not hidden


## Čísla stojí rovně na obrazovce, i když je továrna natočená. Továrna se po postavení nehýbe.
func _straighten() -> void:
	for lane: Lane in _lanes.values():
		for mat: int in lane.labels:
			(lane.labels[mat] as Node2D).global_rotation = 0.0


static var _neon_on: LabelSettings
static var _neon_done: LabelSettings


static func _neon(done: bool) -> LabelSettings:
	if _neon_on == null:
		_neon_on = _neon_style(NEON, NEON_GLOW)
		_neon_done = _neon_style(NEON_DONE, NEON_DONE_GLOW)
	return _neon_done if done else _neon_on


static func _neon_style(color: Color, glow: Color) -> LabelSettings:
	var style := LabelSettings.new()
	style.font_size = 24
	style.font_color = color
	style.outline_size = 5
	style.outline_color = glow
	style.shadow_size = 10
	style.shadow_color = glow
	style.shadow_offset = Vector2.ZERO
	return style


class Lane:
	var id := 0
	## Pás výstupkem na skafandry.
	var special := false
	## Materiál -> kolik kamenů zásobník chce, kolik do něj letí nebo leží a kolik dopadlo.
	var need := {}
	var claimed := {}
	var got := {}
	var capacity := 0
	var stones: Array = []
	## Zásobník jede: kameny míří pod kolo. busy: pás na skafandr právě vyrábí.
	var running := false
	var busy := false
	var sign: Node2D
	## Materiál -> uzel s číslem na cedulce.
	var labels := {}

	func full() -> bool:
		for mat: int in need:
			if int(got.get(mat, 0)) < int(need[mat]):
				return false
		return true


class Stone:
	var sprite: Sprite2D
	var mat := -1
	## Vzdálenost od středu po ose zásobníku a kam dojede. aside je od osy strany.
	var along := 0.0
	var stop := 0.0
	var aside := 0.0
	var wait := 0.0


## Tmavý kruh pod obrázkem materiálu, ať je cedulka vidět na každé zemi.
class SignPlate:
	extends Node2D

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 15.0, Color(0.06, 0.07, 0.08, 0.6))
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 32, Color(0.1, 0.85, 1.0, 0.45), 1.5, true)
