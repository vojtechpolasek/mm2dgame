extends Node

## Úkol jednoho čtverce s továrnou. Venku je jedovatý vzduch: hráči mají dýchací
## přístroj, vesničané zůstávají doma. Úkolem je naplnit zásobníky továrny (SuitFactory).
## Pro každý skafandr na výstupku vyběhne z náhodného domu vesničan, který na skafandr ještě
## čeká, a vezme si ho. Až továrna vyčistí vzduch, vesničané ve skafandrech je odnesou na výstupek, ostatní
## vyjdou ven. LAST_WAIT sekund po posledním odloženém skafandru je úkol splněný.
## Vesničané čtverce se objevují a mizí podle toho, jak blízko jsou hráči. Svět je pokaždé
## připojí (attach) a odpojí (detach).

const Town := preload("res://scripts/town.gd")
const Villagers := preload("res://scripts/villagers.gd")
const SuitFactory := preload("res://scripts/suit_factory.gd")
const Monsters := preload("res://scripts/monsters.gd")

## Kámen dopadl do obyčejného zásobníku. done je kolik jich dopadlo celkem.
signal progressed(done: int)
## Vzduch je čistý a všechny skafandry jsou odložené.
signal completed

## Po posledním odloženém skafandru hra ještě tolik sekund běží, ať je vidět na výstupku.
const LAST_WAIT := 3.0

var _villagers: Villagers
var _factory: SuitFactory
var _stored := 0
## Kolik skafandrů se ještě nese k výstupku. Záporné, dokud vzduch není čistý.
var _returning := -1
var _completed := false


func setup(town: Town) -> bool:
	_factory = town.suit_factory()
	if _factory == null:
		push_error("Továrna nemá zásobníky na skafandry.")
		return false
	_factory.stored.connect(_on_stored)
	_factory.cleaned.connect(_on_cleaned)
	_factory.suit_stored.connect(_on_suit_stored)
	_factory.suit_ready.connect(_send_for_suits)
	return true


## Vesničané čtverce se objevili. Dokud je venku jedovatý vzduch, zůstanou doma.
func attach(villagers: Villagers, monsters: Monsters) -> void:
	_villagers = villagers
	if not _factory.cleared():
		villagers.lock_inside(_factory, monsters.carriers)
	for villager in villagers.members:
		villager.suit_returned.connect(_on_returned)
	_send_for_suits()


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


## Pro každý skafandr na výstupku, pro který ještě nikdo neběží, pošle vesničana
## z náhodného domu, kde se na skafandr čeká.
func _send_for_suits() -> void:
	if _villagers == null or _factory.cleared():
		return
	var running := 0
	var waiting: Array = []
	for villager in _villagers.members:
		if villager.fetching():
			running += 1
		elif villager.waits_for_suit():
			waiting.append(villager)
	waiting.shuffle()
	for i in mini(_factory.suits_lying() - running, waiting.size()):
		waiting[i].fetch_suit()


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


## Vzduch je čistý. Skafandry vesničanů se vracejí na výstupek.
func _on_cleaned() -> void:
	_returning = _villagers.return_suits() if _villagers != null else 0
	if _returning <= 0:
		_finish()


## Skafandry, které ještě nejsou na výstupku: na vesničanech, kteří je nesou.
func _outstanding() -> int:
	var count := 0
	if _villagers != null:
		for villager in _villagers.members:
			if villager.suited():
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
