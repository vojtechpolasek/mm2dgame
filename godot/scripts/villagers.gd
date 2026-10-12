extends Node

## Vesničané: v každém domě PER_HOUSE. Každý dostane jeden materiál z jezírek levelu, od
## nejdražšího. Když je vesničanů víc než materiálů, další kolo začne zase od nejdražšího.
## Který vesničan dostane který materiál, se vylosuje.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const Villager := preload("res://scripts/villager.gd")
const Walker := preload("res://scripts/walker.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")
const Town := preload("res://scripts/town.gd")
const Rocks := preload("res://scripts/rocks.gd")
const Forest := preload("res://scripts/forest.gd")
const Crystal := preload("res://scripts/crystal.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
const Person := preload("res://scripts/person.gd")

const PER_HOUSE := Vector2i(1, 3)

var members: Array[Villager] = []
var _nav: NavGrid


## Mřížka cest pro tělo postavy. Nesahá na scénu, smí běžet ve vlákně s generováním mapy.
func prepare(walker: Walker, rocks: Rocks, forest: Forest) -> void:
	if walker.town == null or walker.town.house_count() == 0:
		return
	_nav = NavGrid.new()
	_nav.build(walker, rocks, forest, Person.BODY)


func spawn(
	town: Town,
	rocks: Rocks,
	crystal: Crystal,
	walker: Walker,
	persons: Array[Person],
	camera: MapCamera,
	host: Node2D,
	rng: RandomNumberGenerator,
) -> void:
	var houses := town.house_count()
	if houses == 0:
		return
	var homes := PackedInt32Array()
	for house in houses:
		for _i in rng.randi_range(PER_HOUSE.x, PER_HOUSE.y):
			homes.append(house)
	var mats := _materials(rocks, crystal, homes.size(), rng)
	var taken := PackedStringArray()
	for person in persons:
		taken.append(str(GameSession.player_colors(person.player_index).get("shirt", "")))
	for i in homes.size():
		var villager := Villager.new()
		villager.name = "Villager%d" % (i + 1)
		host.add_child(villager)
		if walker.crowd != null:
			villager.crowd_id = walker.crowd.join(villager)
		var colors := Villager.outfit(rng, taken)
		if not villager.setup(walker, _nav, town, rocks, crystal, camera, persons, host, homes[i], mats[i], colors, rng):
			villager.queue_free()
			continue
		members.append(villager)


## Materiál pro každého z count vesničanů. Od nejdražšího dokola, rozdané náhodně.
static func _materials(rocks: Rocks, crystal: Crystal, count: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	out.fill(-1)
	var levels := rocks.pond_materials()
	if levels.is_empty() or crystal == null:
		return out
	var order: Array[int] = []
	for mat in levels:
		order.append(mat)
	order.sort_custom(func(a: int, b: int) -> bool: return crystal.points_of(a) > crystal.points_of(b))
	for i in count:
		out[i] = order[i % order.size()]
	for i in range(count - 1, 0, -1):
		var swap := rng.randi_range(0, i)
		var saved := out[i]
		out[i] = out[swap]
		out[swap] = saved
	return out
