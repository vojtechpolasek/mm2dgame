extends RefCounted

## Uložené hry a výkony. Každá hra má při založení svůj identifikátor
## a jeden soubor uložení, který se přepisuje vždy posledním stavem. Vedle něj leží malá
## hlavička pro menu (jméno, hráči, level, čas, datum), ať se seznam her nemusí číst z celých map.
## Výkony jsou jedna tabulka: řádek podle identifikátoru hry, zůstane i po smazání uložení.
## Na Linuxu ~/.local/share/godot/app_userdata/<jméno projektu>/suits.

const DIR := "user://suits"
const RESULTS := "user://suits/results.cfg"
const LAST := "user://suits/last.cfg"
## Verze souboru uložení. Starší nebo novější se nenačte. Verze 2 ukládá jména terénů.
const VERSION := 2
const PARTS: PackedStringArray = ["shirt", "pants", "hair"]


## Náhodný identifikátor nové hry.
static func new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


## Oblečení hráčů bez ovladačů, jak se ukládá do hlavičky.
static func outfits(players: Array[Dictionary]) -> Array:
	var out: Array = []
	for player in players:
		var outfit := {}
		for part in PARTS:
			outfit[part] = str(player.get(part, ""))
		out.append(outfit)
	return out


## Zapíše celou hru. header má klíče id, name, players (oblečení), level, time.
## Soubor se píše vedle a pak přejmenuje, ať pád uprostřed zápisu nezničí poslední uložení.
static func save_game(header: Dictionary, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var id := str(header["id"])
	var stamped := header.duplicate()
	stamped["date"] = int(Time.get_unix_time_from_system())
	var path := _save_path(id)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_warning("Nelze uložit hru do %s." % path)
		return false
	file.store_32(VERSION)
	file.store_var(data)
	file.close()
	var dir := DirAccess.open(DIR)
	if dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	if dir.rename(path.get_file() + ".tmp", path.get_file()) != OK:
		push_warning("Nelze přejmenovat uložení %s." % path)
		return false
	_write_header(stamped)
	_set_last(id)
	_set_result(stamped, false)
	return true


## Celá uložená hra, nebo prázdný slovník, když chybí nebo je z jiné verze.
static func load_game(id: String) -> Dictionary:
	var file := FileAccess.open(_save_path(id), FileAccess.READ)
	if file == null:
		return {}
	if file.get_32() != VERSION:
		push_warning("Uložená hra %s je z jiné verze." % id)
		return {}
	var data: Variant = file.get_var()
	return data if typeof(data) == TYPE_DICTIONARY else {}


## Hlavičky uložených her od naposledy hrané.
static func games() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for name in dir.get_files():
		if not name.ends_with(".cfg") or name == RESULTS.get_file() or name == LAST.get_file():
			continue
		var header := _read_header(name.get_basename())
		if not header.is_empty() and FileAccess.file_exists(_save_path(str(header["id"]))):
			out.append(header)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["date"]) > int(b["date"]))
	return out


## Hlavička naposledy hrané hry, prázdná když žádná rozehraná není.
static func last_game() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(LAST) != OK:
		return {}
	var id := str(config.get_value("last", "id", ""))
	if id.is_empty() or not FileAccess.file_exists(_save_path(id)):
		return {}
	return _read_header(id)


## Smaže uložení hry. Výkon v tabulce zůstane.
static func delete_game(id: String) -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for name in [id + ".save", id + ".cfg"]:
		if dir.file_exists(name):
			dir.remove(name)


## Hra je dohraná: výkon se označí a uložení zmizí, pokračovat v ní už nejde.
static func finish_game(header: Dictionary) -> void:
	var stamped := header.duplicate()
	stamped["date"] = int(Time.get_unix_time_from_system())
	_set_result(stamped, true)
	delete_game(str(header["id"]))


## Výkony pro tolik hráčů: dohrané první, pak podle dosaženého levelu, pak podle času.
static func results(players: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var config := ConfigFile.new()
	if config.load(RESULTS) != OK:
		return out
	for id in config.get_sections():
		if int(config.get_value(id, "players", 0)) != players:
			continue
		out.append({
			"id": id,
			"name": str(config.get_value(id, "name", "")),
			"players": players,
			"level": int(config.get_value(id, "level", 1)),
			"time": float(config.get_value(id, "time", 0.0)),
			"finished": bool(config.get_value(id, "finished", false)),
			"date": int(config.get_value(id, "date", 0)),
		})
	out.sort_custom(_better)
	return out


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["finished"]) != bool(b["finished"]):
		return bool(a["finished"])
	if int(a["level"]) != int(b["level"]):
		return int(a["level"]) > int(b["level"])
	return float(a["time"]) < float(b["time"])


## Datum a čas z unixového času v místním čase: 14. 10. 2026 18:32.
static func date_text(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var at := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%d. %d. %d %d:%02d" % [at["day"], at["month"], at["year"], at["hour"], at["minute"]]


## Jméno hráčů, které se nabídne u nové hry: naposledy zadané.
static func last_name() -> String:
	var config := ConfigFile.new()
	if config.load(LAST) != OK:
		return ""
	return str(config.get_value("last", "name", ""))


static func remember_name(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var config := ConfigFile.new()
	config.load(LAST)
	config.set_value("last", "name", name)
	config.save(LAST)


static func _save_path(id: String) -> String:
	return "%s/%s.save" % [DIR, id]


static func _write_header(header: Dictionary) -> void:
	var config := ConfigFile.new()
	for key: String in header:
		config.set_value("game", key, header[key])
	config.save("%s/%s.cfg" % [DIR, str(header["id"])])


static func _read_header(id: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load("%s/%s.cfg" % [DIR, id]) != OK or not config.has_section("game"):
		return {}
	var header := {}
	for key in config.get_section_keys("game"):
		header[key] = config.get_value("game", key)
	return header if header.has("id") else {}


static func _set_last(id: String) -> void:
	var config := ConfigFile.new()
	config.load(LAST)
	config.set_value("last", "id", id)
	config.save(LAST)


static func _set_result(header: Dictionary, finished: bool) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var config := ConfigFile.new()
	config.load(RESULTS)
	var id := str(header["id"])
	config.set_value(id, "name", str(header.get("name", "")))
	config.set_value(id, "players", (header.get("players", []) as Array).size())
	config.set_value(id, "level", int(header.get("level", 1)))
	config.set_value(id, "time", float(header.get("time", 0.0)))
	config.set_value(id, "finished", finished)
	config.set_value(id, "date", int(header.get("date", 0)))
	config.save(RESULTS)
