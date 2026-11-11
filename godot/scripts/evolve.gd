extends "res://scripts/hunt.gd"

## Evoluce (GameSession.EVOLVE): hráč je příšera a mění se, až se stane cílem (GOAL_KIND
## z GOAL_MATERIAL). Kdo je první, vyhrál. Měří se čas, časový limit není. Losování,
## zásobu, objevování příšer a nápisy bere z Hunt.
##
## Hráč začíná jako START_KIND z START_MATERIAL. Jeho rychlost se počítá jako úprk příšer
## (Hunt._meters), speedup materiálu je tu ale vynásobený EVOLVE_STONE, u příšer i u hráčů.
## Příšera pomalejší nebo stejně rychlá jako hráč, který nemá klid, před ním utíká, když je
## blíž než FLEE_REACH, a přestane, až je dál než FLEE_KEEP. Rychlejší ho honí, když je blíž než EVOLVE_REACH. Řídí se nejbližším
## takovým hráčem, jinak se toulá.
## Dotek příšery, která hráče honí, nebo rychlejší, která nehoní nikoho: hráčův materiál
## klesne o jeden stupeň v pořadí z hunt.json (první je dno), druh zůstává. Dotek jiné příšery:
## hráč se promění v její druh i materiál, příšera se vrátí do zásoby. Pomalejší příšeru
## hráč při WORSE_MONSTER_HURTS = false ignoruje.
## Po každém doteku má hráč EVOLVE_CALM sekund klid: příšery ho ignorují, nic nechytí a bliká.
## Kameny sbírat smí. Příšera, která hráče chytila, odběhne aspoň RETREAT_M metrů od místa
## doteku, teprve pak zase poslouchá Evolve.
## Kameny bez příšery se objevují před hráči jako příšery (Hunt._ahead_spots), na souši.
## Materiál se losuje podle vah z hunt.json krát 1 + EVOLVE_RARE_BOOST × speedup. Sebraný kámen
## dá hráči svůj materiál. Horší kámen (hráč by byl pomalejší) se při WORSE_STONE_HURTS = false
## nechá ležet, kámen stejného materiálu taky.
## Aligátor (vodní druh) v Evoluci není: hráč na souši by s ním nemohl hrát.
##
## Každý hráč má loutky všech druhů postavené při startu (Monster.puppet, dítě postavy),
## proměna jen přepne a přebarví, ať se hra necukne.

## Násobitel speedup materiálu v Evoluci. Pod ~0,73 diamantového ptakoještěra nikdo nedohoní,
## cíl jde splnit jen sebráním diamantového kamene.
const EVOLVE_STONE := 0.5
## Dosah honičky a úprku v metrech.
const EVOLVE_REACH := 10.0
const FLEE_REACH := 5.0
const FLEE_KEEP := 8.0
## Příšera po chycení hráče odběhne aspoň tolik metrů od místa doteku.
const RETREAT_M := 15.0
## Klid po doteku v sekundách. Hráč bliká: půl periody EVOLVE_BLINK průhledný na EVOLVE_FADE.
const EVOLVE_CALM := 4.0
const EVOLVE_BLINK := 0.15
const EVOLVE_FADE := 0.3
## Zhorší hráče horší kámen a horší (pomalejší) příšera? false je nechá být.
const WORSE_STONE_HURTS := true
const WORSE_MONSTER_HURTS := true
## Rozhodování úprku a honičky po tolika sekundách.
const EVOLVE_CHECK := 0.15
## Kameny: další za STONE_MIN až STONE_MAX sekund, nejvýš STONES_MAX na mapě. Váha materiálu
## kamene je váha z hunt.json krát 1 + EVOLVE_RARE_BOOST × speedup, drahé padají častěji.
const STONE_MIN := 2.0
const STONE_MAX := 4.0
const STONES_MAX := 6
const EVOLVE_RARE_BOOST := 2.0
const START_KIND := "brouk"
const START_MATERIAL := "piskovec"
const GOAL_KIND := "ptakojester2"
const GOAL_MATERIAL := "diamant"
## Barvy rychlosti na nápisech: příšera, kterou nejbližší hráč chytí, a ta, která ho honí.
const SLOWER_COLOR := Color(0.62, 0.9, 0.42)
const FASTER_COLOR := Color(1.0, 0.42, 0.36)

## Hráč změnil podobu: pořadí hráče, materiál, jméno („Pískovcový brouk“) a rychlost v m/s.
signal changed(player: int, mat: int, title: String, meters: float)
## Hráč player se stal cílem za seconds sekund po changes proměnách.
signal won(player: int, seconds: float, changes: int, title: String)


## Podoba hráče.
class Form:
	var person: Person
	var kind := ""
	var mat := -1
	var meters := 0.0
	var title := ""
	## Zbývající klid v sekundách.
	var calm := 0.0
	## Kolikrát se hráč proměnil (chycení, kámen, chycení příšerou).
	var changes := 0
	## Loutky podle druhu: kind -> Monster.
	var looks := {}


## Uběhlý čas hry v sekundách.
var elapsed := 0.0
var _forms: Array[Form] = []
var _steer_left := 0.0
var _stone_left := STONE_MIN


func load_catalog(crystal: Crystal) -> void:
	super.load_catalog(crystal)
	for i in range(_species.size() - 1, -1, -1):
		if bool(_species[i]["aquatic"]):
			_species.remove_at(i)


func start(board, camera: MapCamera, persons: Array[Person], host: Node2D, phase: float, surfaces: Dictionary) -> void:
	super.start(board, camera, persons, host, phase, surfaces)
	var species := _species_of(START_KIND)
	var material := _material_named(START_MATERIAL)
	if species.is_empty() or material.is_empty():
		push_error("Evoluce: chybí začáteční příšera %s %s." % [START_KIND, START_MATERIAL])
		return
	for person in persons:
		var form := Form.new()
		form.person = person
		for entry in _species:
			var kind := str(entry["kind"])
			_walker.crowd = null
			var look: Monster = _maker.make(kind, int(material["material"]), _crystal, _walker, _persons,
				_camera, person, _rng, Vector2.ZERO, 1.0)
			_walker.crowd = crowd
			if look != null:
				look.puppet()
				form.looks[kind] = look
		_forms.append(form)
		_become(form, species, material)


func tick(delta: float, phase: float) -> void:
	if _over or _forms.is_empty():
		return
	elapsed += delta
	_day = phase < 0.5
	_calm_down(delta)
	_steer_left -= delta
	if _steer_left <= 0.0:
		_steer_left = EVOLVE_CHECK
		_steer()
	_touch()
	_pick_loose()
	_place_tags(delta)
	_age_floats(delta)
	_keep_spawning(delta)
	_keep_stones(delta)


## Úprk materiálu je v Evoluci slabší: speedup krát EVOLVE_STONE.
func _meters(species: Dictionary, material: Dictionary) -> float:
	var flee: Vector2 = species["flee"]
	return flee.x + (flee.y - flee.x) * float(material["speedup"]) * EVOLVE_STONE


## Příšery Evoluce poslouchají Evolve (Monster.rule).
func _build(creature: Dictionary) -> Monster:
	var monster := super._build(creature)
	if monster != null:
		monster.rule()
	return monster


## Nápis nad příšerou: jméno a rychlost místo bodů.
func _creature_tag(creature: Dictionary) -> Node2D:
	var tag := _take_tag(str(creature["title"]), 0)
	_score_of(tag).text = _speed_text(float(creature["meters"]))
	return tag


# --- Pravidla ---

## Klid ubíhá, hráč v něm bliká.
func _calm_down(delta: float) -> void:
	for form in _forms:
		if form.calm <= 0.0:
			continue
		form.calm -= delta
		var look: Monster = form.looks.get(form.kind)
		if look == null:
			continue
		if form.calm <= 0.0:
			look.fade(1.0)
		else:
			look.fade(EVOLVE_FADE if fmod(form.calm, EVOLVE_BLINK * 2.0) < EVOLVE_BLINK else 1.0)


## Každá příšera utíká před nejbližším hráčem v dosahu úprku, nebo honí nejbližšího v dosahu
## honičky (jen hráče bez klidu). Odbíhající nechá být. Nápis ukáže rychlost zeleně, když ji
## nejbližší hráč chytí, červeně, když honí.
func _steer() -> void:
	var tile := float(TerrainCatalog.TILE_SIZE)
	for prey in _alive:
		var monster := prey.monster
		var meters := float(prey.creature["meters"])
		var target: Form = null
		var nearest: Form = null
		var best := INF
		var best_any := INF
		for form in _forms:
			if not is_instance_valid(form.person):
				continue
			var dist := form.person.position.distance_to(monster.position)
			if dist < best_any:
				best_any = dist
				nearest = form
			var reach := EVOLVE_REACH * tile
			if meters <= form.meters:
				reach = (FLEE_KEEP if monster.fleeing_from() == form.person else FLEE_REACH) * tile
			if form.calm <= 0.0 and dist <= reach and dist < best:
				best = dist
				target = form
		if monster.is_retreating():
			pass
		elif target == null:
			monster.roam()
		elif meters <= target.meters:
			monster.flee_from(target.person)
		else:
			monster.chase(target.person)
		if prey.tag != null and nearest != null:
			_score_of(prey.tag).add_theme_color_override("font_color", SLOWER_COLOR if meters <= nearest.meters else FASTER_COLOR)


## Doteky hráčů a příšer: kdo koho chytil.
func _touch() -> void:
	var bite := Monster.BITE * float(TerrainCatalog.TILE_SIZE)
	for form in _forms:
		if form.calm > 0.0 or not is_instance_valid(form.person) or _over:
			continue
		var person := form.person
		for i in range(_alive.size() - 1, -1, -1):
			var prey := _alive[i]
			var monster := prey.monster
			var reach := monster.crowd_body() + person.body() + bite
			if person.position.distance_squared_to(monster.position) > reach * reach:
				continue
			var meters := float(prey.creature["meters"])
			if monster.prey() == person or (meters > form.meters and monster.prey() == null):
				_bitten(form, prey)
				break
			if meters < form.meters and not WORSE_MONSTER_HURTS:
				continue
			_eat(form, prey)
			break


## Příšera chytila hráče: materiál o stupeň níž, druh zůstává. Příšera odběhne.
func _bitten(form: Form, prey: Prey) -> void:
	prey.monster.retreat(form.person.position, RETREAT_M)
	form.calm = EVOLVE_CALM
	Sound.at("sfx/steal", form.person.position, 2.0)
	var step := _material_step(form.mat)
	if step > 0:
		form.changes += 1
		_become(form, _species_of(form.kind), _materials[step - 1])
	_float_text(form.title, _speed_text(form.meters), FASTER_COLOR, form.person.position)


## Hráč chytil příšeru: promění se v ni, příšera jde do zásoby.
func _eat(form: Form, prey: Prey) -> void:
	var species := _species_of(str(prey.creature["kind"]))
	var material := _material_of(int(prey.creature["material"]))
	_release(prey)
	form.calm = EVOLVE_CALM
	Sound.at("sfx/pickup", form.person.position, 2.0)
	_change(form, species, material)


## Kámen, kterého se dotkne hráč, mu dá svůj materiál, i v klidu.
func _pick_loose() -> void:
	for form in _forms:
		if not is_instance_valid(form.person) or _over:
			continue
		var reach := form.person.body() + _crystal.radius()
		var at := form.person.position
		for i in range(_stones.size() - 1, -1, -1):
			var stone := _stones[i]
			if stone.material == form.mat or at.distance_squared_to(stone.sprite.position) > reach * reach:
				continue
			var species := _species_of(form.kind)
			var material := _material_of(stone.material)
			if _meters(species, material) < form.meters and not WORSE_STONE_HURTS:
				continue
			_stones.remove_at(i)
			stone.sprite.queue_free()
			Sound.at("sfx/pickup", stone.sprite.position, 2.0)
			_change(form, species, material)
			break


## Proměna po chycení nebo sebrání: nápis zeleně, když je hráč rychlejší, jinak červeně.
func _change(form: Form, species: Dictionary, material: Dictionary) -> void:
	var before := form.meters
	form.changes += 1
	_become(form, species, material)
	_float_text(form.title, _speed_text(form.meters), SLOWER_COLOR if form.meters >= before else FASTER_COLOR, form.person.position)


## Hráč form je od teď příšera druhu species z materiálu material. Cíl hru ukončí.
func _become(form: Form, species: Dictionary, material: Dictionary) -> void:
	var kind := str(species["kind"])
	var look: Monster = form.looks.get(kind)
	if look == null:
		return
	var creature := _creature(species, material)
	var mat := int(material["material"])
	look.repaint(mat, _maker.colors_of(_crystal, mat, _maker.species_info(kind)), float(creature["speed"]))
	look.fade(1.0)
	var person := form.person
	var rejoin := kind != form.kind
	person.wear(look, float(creature["meters"]))
	# Skupina tvorů si tělo a výšku pamatuje od přidání.
	if rejoin and crowd != null and person.crowd_id >= 0:
		crowd.leave(person.crowd_id)
		person.crowd_id = crowd.join(person)
	form.kind = kind
	form.mat = mat
	form.meters = float(creature["meters"])
	form.title = str(creature["title"])
	changed.emit(person.player_index, mat, form.title, form.meters)
	if kind == GOAL_KIND and _crystal.name_of(mat) == GOAL_MATERIAL:
		_over = true
		won.emit(person.player_index, elapsed, form.changes, form.title)


# --- Kameny ---

## Další kámen před hráči, když je na mapě místo.
func _keep_stones(delta: float) -> void:
	_stone_left -= delta
	if _stone_left > 0.0:
		return
	_stone_left = RETRY
	if _stones.size() >= STONES_MAX:
		return
	for spot in _ahead_spots():
		if not _walker.stands(spot, Person.BODY) or _walker.blocked(spot, Person.BODY):
			continue
		var material := _stone_material(_walker.surface(spot))
		if material.is_empty():
			continue
		var mat := int(material["material"])
		_stones.append(_lay_stone(spot, mat, _crystal.title_of(mat), 0))
		_stone_left = _rng.randf_range(STONE_MIN, STONE_MAX)
		return


## Materiál kamene na povrchu terrain: váhy z hunt.json, drahé zvýhodněné.
func _stone_material(terrain: String) -> Dictionary:
	var weights := PackedFloat32Array()
	for entry in _materials:
		weights.append(_weight(entry, terrain) * (1.0 + EVOLVE_RARE_BOOST * float(entry["speedup"])))
	return _pick(_materials, weights)


# --- Pomocné ---

func _species_of(kind: String) -> Dictionary:
	for entry in _species:
		if str(entry["kind"]) == kind:
			return entry
	return {}


func _material_of(mat: int) -> Dictionary:
	for entry in _materials:
		if int(entry["material"]) == mat:
			return entry
	return {}


func _material_named(key: String) -> Dictionary:
	for entry in _materials:
		if _crystal.name_of(int(entry["material"])) == key:
			return entry
	return {}


## Pořadí materiálu mat v hunt.json, -1 když chybí.
func _material_step(mat: int) -> int:
	for i in _materials.size():
		if int(_materials[i]["material"]) == mat:
			return i
	return -1


## Popisek bodů v nápisu (druhý Label řádku).
static func _score_of(tag: Node2D) -> Label:
	return tag.get_child(0).get_child(1) as Label


## „3,4 m/s“.
static func _speed_text(meters: float) -> String:
	return ("%.1f m/s" % meters).replace(".", ",")


## Nápis title a text v barvě color nad místem at, vystoupá a zmizí.
func _float_text(title: String, text: String, color: Color, at: Vector2) -> void:
	var rising := Rising.new()
	rising.tag = _take_tag(title, 0)
	var score := _score_of(rising.tag)
	score.text = text
	score.add_theme_color_override("font_color", color)
	rising.tag.visible = true
	rising.at = at
	_floats.append(rising)
	_put_float(rising)


# --- Výkony ---

## Zda se čas seconds vejde mezi RECORDS_KEPT nejlepších pro tolik hráčů. Při shodě zůstává
## výš dřívější výkon.
static func time_qualifies(players: int, seconds: float) -> bool:
	var rows := time_records(players)
	return rows.size() < RECORDS_KEPT or seconds < float(rows[-1]["seconds"])


## Zapíše čas pod jménem name a vrátí jeho pořadí pro stejný počet hráčů (od 1), 0 když se
## nevešel. Horší výkony nad RECORDS_KEPT se smažou. Jméno se zapamatuje (Hunt.last_name).
static func record_time(players: int, seconds: float, changes: int, name: String) -> int:
	var config := ConfigFile.new()
	config.load(EVOLVE_RECORDS)
	var id := "%d_%d" % [Time.get_unix_time_from_system(), randi()]
	config.set_value(id, "players", players)
	config.set_value(id, "name", name)
	config.set_value(id, "seconds", seconds)
	config.set_value(id, "changes", changes)
	config.set_value(id, "date", int(Time.get_unix_time_from_system()))
	config.set_value(NAMES, str(players), name)
	var rows := _time_rows(config, players)
	var rank := 0
	for i in rows.size():
		if i >= RECORDS_KEPT:
			config.erase_section(str(rows[i]["id"]))
		elif str(rows[i]["id"]) == id:
			rank = i + 1
	config.save(EVOLVE_RECORDS)
	return rank


## Nejvýš RECORDS_KEPT výkonů pro tolik hráčů od nejkratšího času. Řádky mají i points (čas
## jako text) a caught (proměny) pro tabulku v HUD.
static func time_records(players: int) -> Array[Dictionary]:
	var config := ConfigFile.new()
	if config.load(EVOLVE_RECORDS) != OK:
		return []
	var rows := _time_rows(config, players)
	rows.resize(mini(rows.size(), RECORDS_KEPT))
	return rows


static func _time_rows(config: ConfigFile, players: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in config.get_sections():
		if id == NAMES or int(config.get_value(id, "players", 0)) != players:
			continue
		var seconds := float(config.get_value(id, "seconds", 0.0))
		out.append({
			"id": id,
			"name": str(config.get_value(id, "name", "")),
			"seconds": seconds,
			"points": GameSession.clock(seconds),
			"caught": int(config.get_value(id, "changes", 0)),
			"date": int(config.get_value(id, "date", 0)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["seconds"]), float(b["seconds"])):
			return float(a["seconds"]) < float(b["seconds"])
		return int(a["date"]) < int(b["date"]))
	return out
