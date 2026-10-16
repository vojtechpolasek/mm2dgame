extends Node

## Postup z dob, kdy hra měla víc typů. Hra se teď ukládá jen přes SuitSaves, soubor se smaže.
const OLD_PROGRESS := "user://progress.cfg"

## Popis hry v menu.
const ABOUT := "Venku je jedovatý vzduch. Naplň zásobníky továrny, ať vzduch vyčistí. Ze tří nejlevnějších kamenů vyrobíš skafandr pro vesničana. Pak šipka ukáže k další továrně. Cílem je 15. level, hra se ukládá sama."

## Pás dolů každého materiálu je kolem továrny široký nejvýš SUIT_BAND_M metrů, ať levné
## materiály jsou blízko.
const SUIT_BAND_M := 8.0
## Zásobníky levelů. Dvojice [pořadí materiálu od nejlevnějšího, počet kamenů].
## Celkem nejvýš 25 kamenů a každého materiálu nejvýš 3. Level je těžší tím, že chce víc
## různých a dražších materiálů, ne hodně kusů jednoho. Materiál, který přibyl, chce level
## jen jednou, víc až v dalších levelech. Nejlevnější materiál zásobníků s levelem jen
## stoupá, levnější se už nevrátí. Od pořadí 4 (magnetit) chce každý materiál až po
## nejdražší aspoň jednou.
## Na mapě jsou jen materiály ze zásobníků, každý s jedním dolem. Recept skafandru chce tři
## nejlevnější z nich. Poslední, patnáctý level je výjimka: limity překračuje,
## chce 26 kamenů a nejdražší materiály po čtyřech. Po něm hra končí.
const SUIT_LEVELS: Array = [
	[[0, 1], [1, 1]],
	[[0, 2], [1, 2], [2, 1]],
	[[0, 2], [1, 2], [2, 2], [3, 1]],
	[[0, 1], [1, 2], [2, 2], [3, 2], [4, 1]],
	[[0, 1], [1, 2], [2, 2], [3, 2], [4, 2], [5, 1]],
	[[1, 2], [2, 2], [3, 2], [4, 2], [5, 2], [6, 1]],
	[[1, 1], [2, 2], [3, 2], [4, 2], [5, 3], [6, 2], [7, 1]],
	[[2, 2], [3, 2], [4, 2], [5, 3], [6, 3], [7, 2], [8, 1]],
	[[2, 1], [3, 2], [4, 2], [5, 2], [6, 3], [7, 3], [8, 2], [9, 1]],
	[[3, 2], [4, 2], [5, 2], [6, 3], [7, 3], [8, 3], [9, 2], [10, 1]],
	[[3, 1], [4, 2], [5, 2], [6, 2], [7, 3], [8, 3], [9, 3], [10, 2], [11, 1]],
	[[4, 2], [5, 2], [6, 2], [7, 3], [8, 3], [9, 3], [10, 3], [11, 2], [12, 1]],
	[[4, 2], [5, 2], [6, 3], [7, 3], [8, 3], [9, 3], [10, 3], [11, 3], [12, 2]],
	[[4, 2], [5, 2], [6, 3], [7, 3], [8, 3], [9, 3], [10, 3], [11, 3], [12, 3]],
	[[5, 2], [6, 3], [7, 3], [8, 3], [9, 3], [10, 4], [11, 4], [12, 4]],
]
## Recept skafandru: po jednom z tolika nejlevnějších materiálů ze zásobníků levelu.
const SUIT_RECIPE := 3
## Nejvíc hráčů. Ovladačů je tolik: šipky, WASD a čtyři gamepady.
const MAX_PLAYERS := 6

## Identifikátor a jméno hry (kdo hraje) a uložený stav, ze kterého hra
## pokračuje. Prázdný stav je nová hra. Viz SuitSaves.
var suit_id := ""
var suit_name := ""
var suit_resume := {}
## Oblečení hráčů pokračující hry podle pořadí. Hrát ji musí stejný počet hráčů.
var suit_outfits: Array = []

## Hráči nové hry. Slovník s klíči pants, shirt a hair (hex bez mřížky) a device (číslo
## ovladače z Controls). Pořadí je pořadí připojení v menu.
var players: Array[Dictionary] = []

const PARTS: PackedStringArray = ["pants", "shirt", "hair"]
const PART_TITLES := {
	"pants": "Kalhoty",
	"shirt": "Triko",
	"hair": "Vlasy",
}
const SWATCHES := {
	"pants": ["243056", "3E4A32", "1C1A22", "6B3A28", "C84B78", "D8C8A0", "5A5A60", "7A2A3A", "2E6E8A", "8A7A30"],
	"shirt": ["C83A32", "3A5EC8", "E8C420", "2E8A4A", "E8E2D2", "8A3AB0", "201A18", "E07828", "30B0C0", "E070A8"],
	"hair": ["5C3A28", "C4A060", "1A1410", "8A3A28", "C8C4C0", "D86A20", "3A2A20", "E8D8B0", "6A3A6A", "2A4A8A"],
}
## Výchozí oblečení hráčů podle pořadí připojení. Triko je shora nejvíc vidět, proto má každý
## jinou výraznou barvu trika a k ní kontrastní kalhoty a vlasy.
const OUTFITS: Array[Dictionary] = [
	{"shirt": "C83A32", "pants": "243056", "hair": "5C3A28"},
	{"shirt": "3A5EC8", "pants": "3E4A32", "hair": "C4A060"},
	{"shirt": "E8C420", "pants": "1C1A22", "hair": "1A1410"},
	{"shirt": "2E8A4A", "pants": "6B3A28", "hair": "D86A20"},
	{"shirt": "E8E2D2", "pants": "C84B78", "hair": "3A2A20"},
	{"shirt": "8A3AB0", "pants": "D8C8A0", "hair": "C8C4C0"},
]


func _ready() -> void:
	if players.is_empty():
		players.append(default_player())
	_remove_old_progress()


## Smaže postup starých typů hry, pokud ještě na disku je.
func _remove_old_progress() -> void:
	if FileAccess.file_exists(OLD_PROGRESS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OLD_PROGRESS))


## Čas s desetinami: 1:23.4.
static func clock(seconds: float) -> String:
	var tenths := roundi(seconds * 10.0)
	return "%d:%02d.%d" % [tenths / 600, (tenths / 10) % 60, tenths % 10]


## „1 hráč“, „2 hráči“, „5 hráčů“.
static func players_text(count: int) -> String:
	if count == 1:
		return "1 hráč"
	return "%d hráči" % count if count <= 4 else "%d hráčů" % count


## Poslední level hry.
static func last_level() -> int:
	return SUIT_LEVELS.size()


## Počet materiálů od nejlevnějšího, mezi kterými jsou všechny materiály levelu. Na mapu
## z nich přijdou jen ty ze zásobníků (suit_orders).
static func material_window(at: int) -> int:
	var most := 0
	for order in suit_orders(at):
		most = maxi(most, order + 1)
	return most


## Zásobníky levelu: dvojice [pořadí materiálu, počet kamenů].
static func suit_lanes(at: int) -> Array:
	return SUIT_LEVELS[clampi(at, 1, SUIT_LEVELS.size()) - 1]


## Pořadí materiálů ze zásobníků levelu, od nejlevnějšího, každé jednou.
static func suit_orders(at: int) -> PackedInt32Array:
	var seen := {}
	for pair: Array in suit_lanes(at):
		seen[int(pair[0])] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out


## První hráč na šipkách s prvním oblečením. Hra spuštěná rovnou bez menu má aspoň jeho.
func default_player() -> Dictionary:
	var player := OUTFITS[0].duplicate()
	player["device"] = 0
	return player


## Oblečení pro nově připojeného hráče: první z OUTFITS, které zatím nikdo nemá.
func free_outfit() -> Dictionary:
	for outfit: Dictionary in OUTFITS:
		var taken := false
		for player: Dictionary in players:
			if str(player.get("shirt", "")) == str(outfit["shirt"]):
				taken = true
				break
		if not taken:
			return outfit.duplicate()
	return OUTFITS[players.size() % OUTFITS.size()].duplicate()


func player_colors(index: int = 0) -> Dictionary:
	if players.is_empty():
		players.append(default_player())
	return players[clampi(index, 0, players.size() - 1)]


