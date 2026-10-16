extends Node

## Úkol jednoho čtverce typu hry Skafandry. Venku je jedovatý vzduch: hráči mají dýchací
## přístroj, vesničané zůstávají doma. Úkolem je naplnit zásobníky továrny (SuitFactory).
## Prázdný skafandr z výstupku továrny donese hráč ke dveřím domu a jeden obyvatel v něm vyjde
## ven. Až továrna vyčistí vzduch, vesničané ve skafandrech je odnesou na výstupek, ostatní
## vyjdou ven. LAST_WAIT sekund po posledním odloženém skafandru je úkol splněný.
## Vesničané čtverce se objevují a mizí podle toho, jak blízko jsou hráči. Svět je pokaždé
## připojí (attach) a odpojí (detach).

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
var _completed := false


## persons je pole postav světa. Postavy přibudou až po prvním čtverci, pole je pořád stejné.
func setup(town: Town, persons: Array[Person]) -> bool:
	_town = town
	_persons = persons
	_factory = town.suit_factory()
	if _factory == null:
		push_error("Továrna nemá zásobníky na skafandry.")
		return false
	_factory.stored.connect(_on_stored)
	_factory.cleaned.connect(_on_cleaned)
	_factory.suit_stored.connect(_on_suit_stored)
	return true


## Vesničané čtverce se objevili. Dokud je venku jedovatý vzduch, zůstanou doma.
func attach(villagers: Villagers, monsters: Monsters) -> void:
	_villagers = villagers
	if not _factory.cleared():
		villagers.lock_inside(_factory, monsters.carriers)
	for villager in villagers.members:
		villager.suit_returned.connect(_on_returned)


func detach() -> void:
	_villagers = null


func factory() -> SuitFactory:
	return _factory


## Kolik kamenů chtějí obyčejné zásobníky.
func target() -> int:
	return _factory.total_needed() if _factory != null else 1


## Kolik kamenů už dopadlo do obyčejných zásobníků.
func stored() -> int:
	return _stored


func is_completed() -> bool:
	return _completed


## Uložená hra: úkol čtverce je dávno splněný.
func mark_done() -> void:
	_completed = true


## Hráč nese skafandr. U dveří domu, kde někdo čeká, si ho obyvatel vezme.
func deliver(pos: Vector2) -> bool:
	if _villagers == null:
		return false
	var reach := Person.BODY * 2.0 + DOOR_REACH * float(TerrainCatalog.TILE_SIZE)
	for house in _town.house_count():
		if pos.distance_to(_town.door(house, Person.BODY)) <= reach and _villagers.dress(house):
			return true
	return false


## Uložená hra: kolik kamenů už dopadlo. Když je vzduch čistý, dopočítá, kolik skafandrů
## se ještě nese, a bez nich je úkol rovnou splněný.
func restore(done: int) -> void:
	_stored = done
	if not _factory.cleared() or _completed:
		return
	_returning = _outstanding()
	if _returning <= 0:
		_finish_later()


func _on_stored(_mat: int, _world: Vector2) -> void:
	_stored += 1
	progressed.emit(_stored)


## Vzduch je čistý. Skafandry vesničanů i ty, které hráči zrovna nesou, se vracejí na výstupek.
func _on_cleaned() -> void:
	_returning = _villagers.return_suits() if _villagers != null else 0
	for person in _persons:
		if is_instance_valid(person) and person.carries_suit():
			_returning += 1
	if _returning <= 0:
		_finish()


## Skafandry, které ještě nejsou na výstupku: na vesničanech, kteří je nesou, a v rukou hráčů.
func _outstanding() -> int:
	var count := 0
	if _villagers != null:
		for villager in _villagers.members:
			if villager.suited():
				count += 1
	for person in _persons:
		if is_instance_valid(person) and person.carries_suit():
			count += 1
	return count


## Vesničan došel k výstupku, skafandr si lehne na něj.
func _on_returned() -> void:
	_factory.store_suit()


func _on_suit_stored() -> void:
	if _returning <= 0:
		return
	_returning -= 1
	if _returning > 0:
		return
	_finish_later()


func _finish_later() -> void:
	await get_tree().create_timer(LAST_WAIT, false).timeout
	if is_inside_tree():
		_finish()


func _finish() -> void:
	if _completed:
		return
	_completed = true
	completed.emit()
