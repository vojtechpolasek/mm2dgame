extends Node2D

## Cákání vody od nohou při chůzi vodou (brod v řece, mělčina jezera). Na každý krok
## (_footstep postavy, vesničana a chodící příšery) se od chodidla rozběhne kroužek po hladině a odletí shluk kapek, víc
## dopředu, kam postava jde. Kreslí se nad vodou a pod postavami, bez textur: kroužky
## a kapky jsou jen kreslené kruhy, ať je to levné i se šesti hráči.

const Benchmark := preload("res://scripts/benchmark.gd")

## Kroužek: počáteční a koncový poloměr v px, délka života v s, tloušťka čáry.
const RING_FROM := 4.0
const RING_TO := 26.0
const RING_LIFE := 0.7
const RING_WIDTH := 2.2
const RING_COLOR := Color(0.88, 0.96, 1.0, 0.75)
## Kapky: kolik na krok, rychlost v px/s, život v s, poloměr v px.
const DROPS := Vector2i(5, 9)
const DROP_SPEED := Vector2(40.0, 110.0)
const DROP_LIFE := Vector2(0.3, 0.55)
const DROP_SIZE := Vector2(1.2, 2.6)
const DROP_COLOR := Color(0.9, 0.97, 1.0, 0.9)
## Kapky zpomalují (odpor vzduchu) o tento podíl rychlosti za sekundu.
const DROP_DRAG := 2.5
## Nejvíc kapek najednou, starší se zahodí.
const DROP_MAX := 240

## Cákání ve hře, null bez světa. Volají ho postavy.
static var current

## Svět (WorldBoard), podle něj se pozná voda v kterémkoli čtverci. Nastaví svět.
var board

## Na kraji záběru se cáká ještě o tolik px dál. Mimo záběr ne, kapky by tam jen zabraly místo.
const VIEW_MARGIN := 64.0

## Kroužky: střed (x, y), stáří, velikost.
var _rings: Array[Vector4] = []
## Kapky: poloha, rychlost, stáří, život a poloměr.
var _drops: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	Benchmark.seed_rng(_rng, 2)


## Je bod ve vodě, kterou se brodí (řeka nebo mělčina, ne most), v kterémkoli čtverci?
## Příšery a vesničané mají chůzi jen po svém čtverci, voda se proto ptá světa.
func wet(at: Vector2) -> bool:
	return board != null and board.river_pace(at) < 1.0


## Šplouchnutí v bodě světa at. forward je směr chůze (délka nevadí), kapky letí víc tam.
## size zvětší kroužek i rozlet kapek (velká příšera cáká víc).
func splash(at: Vector2, forward: Vector2, size := 1.0) -> void:
	var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
	if not view.grow(VIEW_MARGIN).has_point(at):
		return
	var local := to_local(at)
	_rings.append(Vector4(local.x, local.y, 0.0, size))
	var ahead := forward.normalized() if forward.length_squared() > 0.0001 else Vector2.ZERO
	for i in _rng.randi_range(DROPS.x, DROPS.y):
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		dir = (dir + ahead * 0.8).normalized()
		_drops.append({
			"pos": local + dir * 3.0,
			"vel": dir * _rng.randf_range(DROP_SPEED.x, DROP_SPEED.y) * size,
			"age": 0.0,
			"life": _rng.randf_range(DROP_LIFE.x, DROP_LIFE.y),
			"size": _rng.randf_range(DROP_SIZE.x, DROP_SIZE.y) * sqrt(size),
		})
	while _drops.size() > DROP_MAX:
		_drops.pop_front()


func _process(delta: float) -> void:
	if _rings.is_empty() and _drops.is_empty():
		return
	var i := 0
	while i < _rings.size():
		var ring := _rings[i]
		ring.z += delta
		if ring.z >= RING_LIFE:
			_rings.remove_at(i)
			continue
		_rings[i] = ring
		i += 1
	i = 0
	while i < _drops.size():
		var drop := _drops[i]
		drop["age"] = float(drop["age"]) + delta
		if float(drop["age"]) >= float(drop["life"]):
			_drops.remove_at(i)
			continue
		var vel: Vector2 = drop["vel"]
		drop["pos"] = (drop["pos"] as Vector2) + vel * delta
		drop["vel"] = vel * maxf(1.0 - DROP_DRAG * delta, 0.0)
		i += 1
	queue_redraw()


func _draw() -> void:
	for ring in _rings:
		var t := ring.z / RING_LIFE
		var radius := lerpf(RING_FROM, RING_TO, 1.0 - (1.0 - t) * (1.0 - t)) * ring.w
		var color := RING_COLOR
		color.a *= 1.0 - t
		draw_arc(Vector2(ring.x, ring.y), radius, 0.0, TAU, 24, color, RING_WIDTH * (1.0 - 0.5 * t), true)
	for drop in _drops:
		var t := float(drop["age"]) / float(drop["life"])
		var color := DROP_COLOR
		color.a *= 1.0 - t * t
		# Kapka nejdřív vyletí (větší), pak dopadne (menší).
		var size := float(drop["size"]) * (1.0 + 0.6 * sin(t * PI))
		draw_circle(drop["pos"], size, color)
