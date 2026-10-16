extends Node

## Vesničané: v každém domě jeden.
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
	saved: Array = [],
) -> void:
	_monsters = monsters
	var houses := town.house_count()
	if houses == 0:
		return
	# Uložená hra: stejní vesničané ve stejných domech (Villager.origin).
	var homes := PackedInt32Array()
	for entry: Dictionary in saved:
		homes.append(clampi(int(entry.get("home", 0)), 0, houses - 1))
	if saved.is_empty():
		for house in houses:
			homes.append(house)
	var taken := PackedStringArray()
	for person in persons:
		taken.append(str(GameSession.player_colors(person.player_index).get("shirt", "")))
	for i in homes.size():
		var villager := Villager.new()
		villager.name = "Villager%d" % (i + 1)
		host.add_child(villager)
		if walker.crowd != null:
			villager.crowd_id = walker.crowd.join(villager)
		var colors: Dictionary = saved[i].get("colors", {}) if not saved.is_empty() else Villager.outfit(rng, taken)
		if colors.is_empty():
			colors = Villager.outfit(rng, taken)
		if not villager.setup(walker, _nav, town, rocks, crystal, camera, persons, host, homes[i], colors, rng):
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
		# Chrání se jen hráči, ne vesničan, který nese kámen.
		if is_instance_valid(monster) and monster.is_chasing() and not monster.is_flying() and monster.prey() is Person:
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


# --- Uložení ---

## Stav všech vesničanů k uložení, po pořadí. Viz Villager.snapshot.
func snapshot(persons: Array[Person]) -> Array:
	var out: Array = []
	for villager in members:
		if is_instance_valid(villager):
			out.append(villager.snapshot(persons))
	return out


## Stav vesničanů ze snapshot. Vesničané vznikli spawn se stejným saved, pořadí sedí.
func restore(saved: Array, persons: Array[Person]) -> void:
	for i in mini(saved.size(), members.size()):
		members[i].restore(saved[i], persons)


# --- Skafandry ---

## Venku je jedovatý vzduch: všichni zůstanou doma, dokud nedostanou skafandr. Ukazují na
## doly materiálu, který továrně chybí, a dají se vzít s sebou. carriers sdílí s příšerami.
func lock_inside(factory: Node2D, carriers: Array) -> void:
	for villager in members:
		villager.needs_suit = true
		villager.suits = factory
		villager.carriers = carriers


## Hráč person vzal kámen z dolu. Kdo ho sleduje, dojde si pro stejný.
func leader_took(slot: int, mat: int, person: Person) -> void:
	for villager in members:
		villager.leader_took(slot, mat, person)


## Hráč person se dotkl továrny. Kdo ho sleduje s kamenem, jde ho tam hodit.
func leader_touched(person: Person) -> void:
	for villager in members:
		villager.leader_touched(person)


## Hráč person hodil kámen do továrny. Kdo ho sleduje s kamenem, hodí taky, bez kamene odejde.
func leader_threw(person: Person) -> void:
	for villager in members:
		villager.leader_threw(person)


## Hráč person použil plochu skladu bay. Kdo ho sleduje, udělá u stejného skladu totéž.
func leader_used_store(bay: int, left: int, took: int, person: Person) -> void:
	for villager in members:
		villager.leader_used_store(bay, left, took, person)


## Vzduch je čistý. Vesničané ve skafandrech ho dojdou odložit před výstupek, ostatní vyjdou
## ven. Vrátí, kolik skafandrů se bude odkládat. Každé odložení ohlásí signál vesničana
## suit_returned.
func return_suits() -> int:
	var count := 0
	for villager in members:
		if villager.suited():
			count += 1
		villager.return_suit()
	return count
