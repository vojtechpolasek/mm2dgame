extends Node

const Rocks := preload("res://scripts/rocks.gd")
## Postava odkazuje na GameSession, proto se nepřednačítá. Rychlost běhu se z ní vezme až za běhu.
const PERSON := "res://scripts/person.gd"
const CRYSTAL_CATALOG := "res://graphics/objects/crystal/crystal.json"

## Postup hráče na disku. Na Linuxu ~/.local/share/godot/app_userdata/<jméno projektu>/.
const PROGRESS := "user://progress.cfg"

## Typy hry v pořadí menu. Každý má pevná pravidla a vlastní postup levely.
## goal: points nasbírat cílový počet bodů, ponds přinést všechny kameny ze všech jezírek.
## timed: časový limit. Bez limitu se nedá prohrát a ukládá se nejlepší čas.
## bottomless: jezírko nikdy nedojde. Jinak má Rocks.GEMS_IN_POND kamenů a ty ubývají.
const MODES: Array[Dictionary] = [
	{
		"id": "ponds", "title": "Vybrat jezírka", "goal": "ponds", "timed": false, "bottomless": false,
		"about": "Každé jezírko má tři kameny. Přines do kotliny všechny. Bez limitu, počítá se nejlepší čas.",
	},
	{
		"id": "time_points", "title": "Na čas – body", "goal": "points", "timed": true, "bottomless": true,
		"about": "Nasbírej v časovém limitu potřebný počet bodů.",
	},
	{
		"id": "time_ponds", "title": "Na čas – vybrat jezírka", "goal": "ponds", "timed": true, "bottomless": false,
		"about": "Každé jezírko má tři kameny. Přines do kotliny všechny, než vyprší čas.",
	},
]
## Typ hry, kterému patří postup z doby před typy hry (progress/unlocked).
const FIRST_MODE_ID := "time_points"

## Parametry právě zakládané hry: typ (pořadí v MODES) a level. Velikost mapy, cíl i čas plynou
## z levelu pevnými vzorci, takže level je pokaždé stejný.
var mode: int = 0
var level: int = 1

## Nejvyšší odemčený level podle typu hry (id). Na začátku jen první, splněný level odemkne další.
var _unlocked := {}
## Nejlepší čas v sekundách podle typu hry, levelu a počtu hráčů. Klíč je "id/level/hráči".
var _records := {}

## Velikosti mapy z menu. Menu je ukazuje jako level, ve kterém mapa té velikosti začíná.
## Level, ve kterém mapa dosáhne poslední velikosti, je poslední level hry.
const MAP_SIZES: Array[int] = [64, 128, 256, 512]
## Limit prvního a posledního levelu v sekundách. Mezi nimi přibývá po TIME_STEP rovnoměrně.
const FIRST_TIME := 60
const LAST_TIME := 300
const TIME_STEP := 20
## Mapa roste o tolik každý level, až k poslední velikosti z menu.
const MAP_GROWTH := 0.05
## Zbyl by po kroku k další velikosti z menu menší skok než tohle, jde se na ni rovnou.
## Je to polovina běžného kroku, takže skok je vždy aspoň půl a nejvýš jeden a půl kroku.
const MAP_SNAP := 0.025
## Cíl je podíl z bodů, které by nasbíral hráč s nejlepším plánem levelu. Podíl začíná
## na EFFORT_START, každý level přidá EFFORT_STEP, nejvýš EFFORT_MAX.
const EFFORT_START := 0.55
const EFFORT_STEP := 0.007
const EFFORT_MAX := 0.75
## Příšery kradou nesené kameny. Odhad ze simulace honičky, cíl je o tolik nižší.
const THEFT := 0.15
## Kolik sekund cesty navíc stojí sebrání a hod, mimo samotný běh.
const HANDLE_SECONDS := 1.5
## Na kolik metrů hráč jezírko zahlédne. Obrazovka při zoomu 1 je asi 20 × 11 m.
const VIEW_METERS := 7.0
## Kolik materiálů s nejmenším počtem bodů má jezírka v prvním levelu. Další přibude
## každých MATERIAL_EVERY levelů.
const FIRST_MATERIALS := 2
const MATERIAL_EVERY := 1.5
## Hráči hrají spolu, body se sčítají. Každý další hráč zvedne cíl o tolik.
const PLAYER_TARGET := 0.5
## Nejvíc hráčů. Ovladačů je tolik: šipky, WASD a čtyři gamepady.
const MAX_PLAYERS := 6

## Hráči nové hry. Slovník s klíči pants, shirt a hair (hex bez mřížky) a device (číslo
## ovladače z Controls). Pořadí je pořadí připojení v menu.
var players: Array[Dictionary] = []

## Body materiálů z katalogu krystalu od nejlevnějšího. Načte se při prvním výpočtu cíle.
static var _material_points := PackedInt32Array()
static var _run_speed := 0.0

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
	_load_progress()


## Pravidla vybraného typu hry, záznam z MODES.
func rules() -> Dictionary:
	return MODES[clampi(mode, 0, MODES.size() - 1)]


## Nejvyšší odemčený level vybraného typu hry.
func unlocked_level() -> int:
	return int(_unlocked.get(rules()["id"], 1))


## Splněný level odemkne v tomhle typu hry další. Ukládá se hned, při příštím spuštění se
## pokračuje od něj.
func unlock(at: int) -> void:
	var next := mini(at, last_level())
	if next <= unlocked_level():
		return
	_unlocked[rules()["id"]] = next
	_save_progress()


## Nejlepší čas levelu ve vybraném typu hry pro tolik hráčů. Bez rekordu záporné.
func record(at: int, player_count: int) -> float:
	return float(_records.get(_record_key(at, player_count), -1.0))


## Uloží čas, když je lepší než dosavadní rekord. Vrátí, jestli je to nový rekord.
func offer_record(at: int, player_count: int, seconds: float) -> bool:
	var best := record(at, player_count)
	if best >= 0.0 and best <= seconds:
		return false
	_records[_record_key(at, player_count)] = seconds
	_save_progress()
	return true


## Čas s desetinami: 1:23.4.
static func clock(seconds: float) -> String:
	var tenths := roundi(seconds * 10.0)
	return "%d:%02d.%d" % [tenths / 600, (tenths / 10) % 60, tenths % 10]


## „1 hráč“, „2 hráči“, „5 hráčů“.
static func players_text(count: int) -> String:
	if count == 1:
		return "1 hráč"
	return "%d hráči" % count if count <= 4 else "%d hráčů" % count


func _record_key(at: int, player_count: int) -> String:
	return "%s/%d/%d" % [rules()["id"], at, maxi(player_count, 1)]


func _save_progress() -> void:
	var config := ConfigFile.new()
	for id: String in _unlocked:
		config.set_value("unlocked", id, _unlocked[id])
	for key: String in _records:
		config.set_value("records", key, _records[key])
	if config.save(PROGRESS) != OK:
		push_warning("Nelze uložit postup do %s." % PROGRESS)


## Postup z doby před typy hry (progress/unlocked) patří typu, který tehdy byl jediný.
func _load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(PROGRESS) != OK:
		return
	if config.has_section_key("progress", "unlocked"):
		_unlocked[FIRST_MODE_ID] = int(config.get_value("progress", "unlocked", 1))
	if config.has_section("unlocked"):
		for id: String in config.get_section_keys("unlocked"):
			_unlocked[id] = int(config.get_value("unlocked", id, 1))
	for id: String in _unlocked:
		_unlocked[id] = clampi(int(_unlocked[id]), 1, last_level())
	if config.has_section("records"):
		for key: String in config.get_section_keys("records"):
			_records[key] = float(config.get_value("records", key, -1.0))


## Strana mapy v dlaždicích.
static func level_size(at: int) -> int:
	var size := MAP_SIZES[0]
	for _step in range(1, at):
		size = _grow(size)
	return size


static func _grow(size: int) -> int:
	var next := maxi(roundi(float(size) * (1.0 + MAP_GROWTH)), size + 1)
	for menu: int in MAP_SIZES:
		if menu <= size:
			continue
		if next >= menu or float(menu) / float(next) < 1.0 + MAP_SNAP:
			return menu
		return next
	return size


## Poslední level: mapa v něm poprvé dosáhne největší velikosti z menu.
static func last_level() -> int:
	return maxi(level_for_size(MAP_SIZES[MAP_SIZES.size() - 1]), 1)


## Limit v sekundách. Přidává se po TIME_STEP rozložených rovnoměrně mezi první a poslední level,
## takže přídavek přijde zhruba každý třetí až čtvrtý level a poslední level má LAST_TIME.
static func level_time(at: int) -> int:
	var last := last_level()
	var steps := (LAST_TIME - FIRST_TIME) / TIME_STEP
	var done := clampi(at - 1, 0, last - 1)
	return FIRST_TIME + TIME_STEP * (done * steps / maxi(last - 1, 1))


## Limit levelu ve vybraném typu hry, v sekundách. Body mají limit z level_time. Na vybrání
## jezírek je limit aspoň tak dlouhý, aby se do něj při podílu úsilí levelu vešel odhad
## vybrání s krádežemi, zaokrouhlený nahoru na TIME_STEP.
func mode_time(at: int) -> int:
	var limit := level_time(at)
	if rules()["goal"] != "ponds":
		return limit
	var needed := ponds_seconds(at) * (1.0 + THEFT) / level_effort(at)
	return maxi(limit, ceili(needed / float(TIME_STEP)) * TIME_STEP)


## Odhad vybrání všech jezírek jedním hráčem. Směr k jezírkům ukazují šipky na kotlině, takže
## se nehledá: z každého jezírka donese všechny kameny cestou tam a zpět. Jezírko je v průměru
## uprostřed mezikruží svého materiálu.
static func ponds_seconds(at: int) -> float:
	var speed := _speed()
	var size := level_size(at)
	var materials := material_points().size()
	var count := mini(level_materials(at), materials)
	var ponds := Rocks.capped_ponds(count, materials)
	var total := 0.0
	for order in count:
		var ring := Rocks.pond_annulus(order, count, size)
		var trip := (ring.x + ring.y) / speed + HANDLE_SECONDS
		total += float(ponds[order] * Rocks.pond_gems(order)) * trip
	return total


## Body potřebné ke splnění: podíl úsilí z nejlepšího plánu levelu, ponížený o krádeže příšer.
## Hráči hrají spolu, každý další přidá PLAYER_TARGET.
static func level_target(at: int, player_count: int = 1) -> int:
	var crew := 1.0 + PLAYER_TARGET * float(maxi(player_count, 1) - 1)
	return maxi(roundi(float(level_best(at)) * level_effort(at) * (1.0 - THEFT) * crew), 1)


## Kolik bodů by v limitu nasbíral hráč s nejlepším plánem. Plán je jeden materiál: hráč
## neví, kde jezírka jsou, tak ho nejdřív hledá, pak ho nosí známou cestou a zbytek času
## dorovná levnějším materiálem, na který se cesta ještě vejde.
## Hledání: hráč tuší, že vzácnější materiál je dál, tak doběhne k mezikruží materiálu
## a prochází ho pruhem širokým dvakrát VIEW_METERS. Průměrný čas je plocha mezikruží lomeno
## prohledanou plochou za sekundu krát počet jezírek. Vzdálenost nejbližšího jezírka je odhad
## z Rocks.pond_distance.
static func level_best(at: int) -> int:
	var points := material_points()
	if points.is_empty():
		return 1
	var limit := float(level_time(at))
	var plan := _plan(at)
	var trips: PackedFloat32Array = plan[0]
	var finds: PackedFloat32Array = plan[1]
	var count := finds.size()
	var best := 0
	for order in count:
		if finds[order] > limit:
			continue
		var repeats := floori((limit - finds[order]) / trips[order])
		var left := limit - finds[order] - float(repeats) * trips[order]
		var fill := 0
		for cheaper in order:
			if trips[cheaper] <= left:
				fill = maxi(fill, points[cheaper] * floori(left / trips[cheaper]))
		best = maxi(best, points[order] * (1 + repeats) + fill)
	return best


## Časy materiálů levelu od nejlevnějšího: [cesta tam a zpět známou cestou, nalezení a donesení
## prvního kamene].
static func _plan(at: int) -> Array[PackedFloat32Array]:
	var points := material_points()
	var speed := _speed()
	var size := level_size(at)
	var materials := points.size()
	var count := mini(level_materials(at), materials)
	var sweep := 2.0 * VIEW_METERS * speed
	var trips := PackedFloat32Array()
	var finds := PackedFloat32Array()
	for order in count:
		var rarity := Rocks.material_rarity(order, materials)
		var away := Rocks.pond_distance(order, count, materials, size)
		var ponds := float(Rocks.pond_count(rarity, size))
		var ring := Rocks.pond_annulus(order, count, size)
		var area := PI * (ring.y * ring.y - ring.x * ring.x)
		trips.append(2.0 * away / speed + HANDLE_SECONDS)
		finds.append(ring.x / speed + area / (ponds * sweep) + away / speed + HANDLE_SECONDS)
	return [trips, finds]


## Rychlost běhu postavy v metrech za sekundu.
static func _speed() -> float:
	if _run_speed <= 0.0:
		_run_speed = float(load(PERSON).RUN_METERS)
	return _run_speed


static func level_effort(at: int) -> float:
	return minf(EFFORT_START + EFFORT_STEP * float(at - 1), EFFORT_MAX)


static func material_points() -> PackedInt32Array:
	if not _material_points.is_empty():
		return _material_points
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CRYSTAL_CATALOG))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _material_points
	var listed: Variant = (parsed as Dictionary).get("materials", {})
	if typeof(listed) != TYPE_DICTIONARY:
		return _material_points
	var values: Array[int] = []
	for mat_name: String in listed:
		values.append(clampi(int((listed[mat_name] as Dictionary).get("points", 50)), 1, 100))
	values.sort()
	_material_points = PackedInt32Array(values)
	return _material_points


## Počet dostupných materiálů, od nejlevnějšího. Víc, než kolik jich je v katalogu, znamená všechny.
static func level_materials(at: int) -> int:
	return FIRST_MATERIALS + floori(float(at - 1) / MATERIAL_EVERY)


## První level s mapou této velikosti. Velikost, na kterou level nikdy nepřijde, vrátí -1.
static func level_for_size(size: int) -> int:
	var current := MAP_SIZES[0]
	var at := 1
	while current < size:
		var next := _grow(current)
		if next == current:
			return -1
		current = next
		at += 1
	return at if current == size else -1


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


