extends Node

## Data odstraněných režimů. Při startu se smažou, pokud ještě na disku jsou.
const OLD_PROGRESS := "user://progress.cfg"
const OLD_SAVES := "user://suits"
## Nejvíc hráčů. Ovladačů je tolik: šipky, WASD a čtyři gamepady.
const MAX_PLAYERS := 6

## Režimy hry. Všechny se hrají v otevřeném světě, který se dotváří, jak hráči chodí.
## ROAM: volný pohyb bez příšer, času a cíle. HUNT: Chytej příšery, příšery utíkají a hráči je
## chytají. COLLECT: Sbírání materiálů, hráči sbírají kameny a příšery je honí. Oba časové
## režimy řídí Hunt a ukládají se v nich jen výkony.
const ROAM := "roam"
const HUNT := "hunt"
const COLLECT := "collect"

var mode := ROAM

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
	"pants": ["243056", "3E4A32", "1C1A22", "6B3A28", "C84B78", "D8C8A0", "5A5A60", "7A2A3A"],
	"shirt": ["C83A32", "3A5EC8", "E8C420", "2E8A4A", "E8E2D2", "8A3AB0", "201A18", "E07828"],
	"hair": ["5C3A28", "C4A060", "1A1410", "8A3A28", "C8C4C0", "D86A20", "3A2A20", "E8D8B0"],
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
	_remove_old_data()


## Je to režim s příšerami, časem a body (Hunt)?
func timed() -> bool:
	return mode == HUNT or mode == COLLECT


## Smaže data odstraněných režimů: starý postup a uložené hry Sbírání kamenů.
func _remove_old_data() -> void:
	if FileAccess.file_exists(OLD_PROGRESS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OLD_PROGRESS))
	if DirAccess.dir_exists_absolute(OLD_SAVES):
		_remove_dir(ProjectSettings.globalize_path(OLD_SAVES))


static func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)


## Čas s desetinami: 1:23.4.
static func clock(seconds: float) -> String:
	var tenths := roundi(seconds * 10.0)
	return "%d:%02d.%d" % [tenths / 600, (tenths / 10) % 60, tenths % 10]


## „1 hráč“, „2 hráči“, „5 hráčů“.
static func players_text(count: int) -> String:
	if count == 1:
		return "1 hráč"
	return "%d hráči" % count if count <= 4 else "%d hráčů" % count


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


