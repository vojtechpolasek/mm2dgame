extends Node

## Typ hry Skafandry. Venku je jedovatý vzduch: hráči mají dýchací přístroj, vesničané
## zůstávají doma. Úkolem je naplnit zásobníky továrny (SuitFactory). Prázdný skafandr
## z výstupku továrny donese hráč ke dveřím domu a jeden obyvatel v něm vyjde ven. Až továrna
## vyčistí vzduch, vesničané ve skafandrech je odnesou na výstupek, ostatní vyjdou ven.
## LAST_WAIT sekund po posledním odloženém skafandru je level splněný.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const Town := preload("res://scripts/town.gd")
const Villagers := preload("res://scripts/villagers.gd")
const Person := preload("res://scripts/person.gd")
const SuitFactory := preload("res://scripts/suit_factory.gd")
const Monsters := preload("res://scripts/monsters.gd")

## Kámen dopadl do obyčejného zásobníku. done je kolik jich dopadlo celkem.
signal progressed(done: int)
## Vzduch je čistý a všechny skafandry jsou odložené.
signal completed

## Skafandr převezme vesničan, když je hráč blíž ke dveřím domu než tolik metrů.
const DOOR_REACH := 1.0
## Po posledním odloženém skafandru hra ještě tolik sekund běží, ať je vidět na výstupku.
const LAST_WAIT := 3.0

var _town: Town
var _villagers: Villagers
var _persons: Array[Person] = []
var _factory: SuitFactory
var _stored := 0
## Kolik skafandrů se ještě nese k výstupku. Záporné, dokud vzduch není čistý.
var _returning := -1


func setup(town: Town, villagers: Villagers, persons: Array[Person], monsters: Monsters) -> bool:
	_town = town
	_villagers = villagers
	_persons = persons
	_factory = town.suit_factory()
	if _factory == null:
		push_error("Továrna nemá zásobníky na skafandry.")
		return false
	villagers.lock_inside(_factory, monsters.carriers)
	for villager in villagers.members:
		villager.suit_returned.connect(_on_returned)
	for person in persons:
		person.wear_gear(true)
		person.stolen_vanish = true
		person.deliver_suit = _deliver
		person.took_gem.connect(villagers.leader_took.bind(person))
		person.threw_gem.connect(villagers.leader_threw.bind(person))
		person.touched_factory.connect(villagers.leader_touched.bind(person))
	_factory.stored.connect(_on_stored)
	_factory.cleaned.connect(_on_cleaned)
	_factory.suit_stored.connect(_on_suit_stored)
	return true


## Kolik kamenů chtějí obyčejné zásobníky.
func target() -> int:
	return _factory.total_needed() if _factory != null else 1


## Hráč nese skafandr. U dveří domu, kde někdo čeká, si ho obyvatel vezme.
func _deliver(pos: Vector2) -> bool:
	var reach := Person.BODY * 2.0 + DOOR_REACH * float(TerrainCatalog.TILE_SIZE)
	for house in _town.house_count():
		if pos.distance_to(_town.door(house, Person.BODY)) <= reach and _villagers.dress(house):
			return true
	return false


func _on_stored(_mat: int, _world: Vector2) -> void:
	_stored += 1
	progressed.emit(_stored)


## Vzduch je čistý. Skafandry vesničanů i ty, které hráči zrovna nesou, se vracejí na výstupek.
func _on_cleaned() -> void:
	_returning = _villagers.return_suits()
	for person in _persons:
		if is_instance_valid(person) and person.carries_suit():
			_returning += 1
	if _returning <= 0:
		completed.emit()


## Vesničan došel k výstupku, skafandr si lehne na něj.
func _on_returned() -> void:
	_factory.store_suit()


func _on_suit_stored() -> void:
	if _returning <= 0:
		return
	_returning -= 1
	if _returning > 0:
		return
	await get_tree().create_timer(LAST_WAIT, false).timeout
	if is_inside_tree():
		completed.emit()
