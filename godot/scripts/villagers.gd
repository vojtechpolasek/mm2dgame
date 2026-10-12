extends Node

## Vesničané: v každém domě PER_HOUSE. Každý dostane jeden materiál z jezírek levelu, od
## nejdražšího. Když je vesničanů víc než materiálů, další kolo začne zase od nejdražšího.
## Který vesničan dostane který materiál, se vylosuje. Materiál ukazuje u bezedných jezírek.
## Při honičce pošle každé honěné postavě na pomoc nejvýš HELPERS vesničanů: ty, kdo jsou
## příšeře, která ji honí, nejblíž, nejdál HELP_NEAR metrů. Vesničan v domě se měří ode dveří. Pomoc skončí, když příšera
## přestane honit nebo je od pomocníka dál než HELP_FAR metrů. Létající příšeře se do cesty
## postavit nedá. Pomocníci se přidělují po HELP_CHECK sekundách.

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
const Monsters := preload("res://scripts/monsters.gd")
const Monster := preload("res://scripts/monster.gd")

const PER_HOUSE := Vector2i(1, 3)
const HELPERS := 2
const HELP_NEAR := 6.0
const HELP_FAR := 10.0
const HELP_CHECK := 0.25

var members: Array[Villager] = []
var _nav: NavGrid
var _monsters: Monsters
var _help_left := 0.0


## Mřížka cest pro tělo postavy. Nesahá na scénu, smí běžet ve vlákně s generováním mapy.
func set_space(origin: Vector2) -> void:
	if _nav != null:
		_nav.set_space(origin)


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
	monsters: Monsters,
	rng: RandomNumberGenerator,
) -> void:
	_monsters = monsters
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


func _process(delta: float) -> void:
	if _monsters == null or members.is_empty():
		return
	_help_left -= delta
	if _help_left > 0.0:
		return
	_help_left = HELP_CHECK
	var tile := float(TerrainCatalog.TILE_SIZE)
	var chasing: Array[Monster] = []
	for monster in _monsters.members:
		if is_instance_valid(monster) and monster.is_chasing() and not monster.is_flying():
			chasing.append(monster)
	# Kolik pomocníků už má která honěná postava.
	var guards := {}
	for villager in members:
		var monster := villager.helping()
		if monster == null:
			continue
		if not chasing.has(monster) or villager.spot().distance_to(monster.position) > HELP_FAR * tile:
			villager.stop_helping()
			continue
		var prey := monster.prey()
		if int(guards.get(prey, 0)) >= HELPERS:
			# Příšera přešla na postavu, která už pomocníky má.
			villager.stop_helping()
			continue
		guards[prey] = int(guards.get(prey, 0)) + 1
	while true:
		var best: Villager = null
		var best_monster: Monster = null
		var best_dist := HELP_NEAR * tile
		for villager in members:
			if villager.helping() != null or not villager.can_help():
				continue
			for monster in chasing:
				if int(guards.get(monster.prey(), 0)) >= HELPERS:
					continue
				var dist := villager.spot().distance_to(monster.position)
				if dist <= best_dist:
					best_dist = dist
					best = villager
					best_monster = monster
		if best == null:
			break
		best.help(best_monster)
		guards[best_monster.prey()] = int(guards.get(best_monster.prey(), 0)) + 1


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
