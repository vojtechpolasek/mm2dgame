extends RefCounted

## Pohyb po zemi, společný postavě i příšerám. Překážky jsou paty skal, keře a kmeny, továrna
## a domy, ostatní tvorové z crowd, neschůdný povrch je voda a mimo mapu se nesmí. Tělo je kruh o poloměru
## body v pixelech. who je číslo tvora v crowd, -1 ostatní tvory nebere v úvahu.
##
## Do vody se smí jen na mělčinu: dlaždice vody, která sousedí se souší (i úhlopříčně). Jde se
## po ní pomalu jako brodem v řece. Dlaždice vody u kraje čtverce může mít souš až u souseda,
## to rozhodne svět (WorldBoard.is_dry), sama mělčinou není.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const Rocks := preload("res://scripts/rocks.gd")
const Forest := preload("res://scripts/forest.gd")
const Town := preload("res://scripts/town.gd")
const MapData := preload("res://scripts/map_data.gd")
const Crowd := preload("res://scripts/crowd.gd")

## Střed těla nesmí blíž ke kraji čtverce než tolik metrů. Platí pro postavy, příšery
## i vesničany, chodící i létající.
const EDGE_M := 1.0
## Ve vodě řeky a na mělčině se jde pomaleji.
const RIVER_PACE := 0.8
## Povrch dlaždice (ground): souš, mělčina, voda u kraje čtverce (mělčina, má-li souš soused)
## a hluboká voda.
const LAND := 1
const SHALLOW := 3
const EDGE_WATER := 2
const DEEP := 0
## Body na obvodu těla, které musí stát na souši.
const PROBES: Array[Vector2] = [
	Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(0.707, 0.707), Vector2(0.707, -0.707), Vector2(-0.707, 0.707), Vector2(-0.707, -0.707),
]

var _rocks: Rocks
var _forest: Forest
## Továrna, cesta a domy. Mřížka cest příšer z ní bere půdorysy.
var town: Town
## Řeka čtverce. Ve vodě zpomalí na RIVER_PACE, na mostě (cesta) ne. Nastaví svět.
var river
var _map_size := Vector2.ZERO
var _tiles := 0
## Světové souřadnice levého horního rohu mapy. Nula je jedna mapa od počátku.
var space_origin := Vector2.ZERO
## Když je nastavená, chůze sahá přes víc čtverců. Jinak platí tahle jedna mapa.
var world_board = null
## Povrch každé dlaždice: LAND, SHALLOW, EDGE_WATER nebo DEEP.
var _walkable := PackedByteArray()
## Jméno povrchu -> násobek rychlosti chůze (speed v surfaces.json). Jména platí ve všech čtvercích.
var _pace := {}
var _terrain := PackedByteArray()
var _names := PackedStringArray()
## Tvorové, kteří nechodí přes sebe. Nastaví svět, než se kdo pohne.
var crowd: Crowd
## Ohrada ve světě: střed těla z ní nevyjde. Prázdná nic nehlídá. Nastaví svět.
var fence := Rect2()


func _init(rocks: Rocks, forest: Forest, town_at: Town, map: MapData) -> void:
	_rocks = rocks
	_forest = forest
	town = town_at
	var tile := float(TerrainCatalog.TILE_SIZE)
	_tiles = map.size
	_map_size = Vector2(tile, tile) * float(map.size)
	_terrain = map.terrain
	_names = map.names
	_walkable.resize(map.terrain.size())
	for index in map.terrain.size():
		var info: Dictionary = map.surfaces.get(map.names[map.terrain[index]], {})
		_walkable[index] = LAND if bool(info.get("walkable", true)) else DEEP
	_mark_shallows()
	for surface_name in map.names:
		var info: Dictionary = map.surfaces.get(surface_name, {})
		_pace[surface_name] = float(info.get("speed", 1.0))


## Voda vedle souše je mělčina. U kraje čtverce, kde vedle souš není, rozhodne soused.
func _mark_shallows() -> void:
	var last := _tiles - 1
	for y in _tiles:
		for x in _tiles:
			if _walkable[y * _tiles + x] != DEEP:
				continue
			var shore := false
			for ny in range(maxi(y - 1, 0), mini(y + 1, last) + 1):
				for nx in range(maxi(x - 1, 0), mini(x + 1, last) + 1):
					if _walkable[ny * _tiles + nx] == LAND:
						shore = true
			if shore:
				_walkable[y * _tiles + x] = SHALLOW
			elif x == 0 or y == 0 or x == last or y == last:
				_walkable[y * _tiles + x] = EDGE_WATER


## Označí v mřížce buňky (dlaždice), na kterých se nedá stát: voda mimo mělčinu.
func block_water(grid: AStarGrid2D) -> void:
	for y in _tiles:
		for x in _tiles:
			var ground := _walkable[y * _tiles + x]
			if ground != LAND and ground != SHALLOW:
				grid.set_point_solid(Vector2i(x, y))


## Jméno povrchu pod bodem (grass, dirt, ...). Mimo mapu prázdné.
func set_space(origin: Vector2) -> void:
	space_origin = origin


## Násobek rychlosti chůze na povrchu pod bodem. Močál a řeka zpomalí, mimo mapu 1.
func pace(pos: Vector2) -> float:
	var ground := float(_pace.get(surface(pos), 1.0))
	if world_board != null:
		return ground * world_board.river_pace(pos)
	return ground * river_pace(pos)


## Ve vodě řeky a na mělčině RIVER_PACE, jinde a na mostě 1. pos je bod ve světě.
func river_pace(pos: Vector2) -> float:
	if ground(pos) != LAND:
		return RIVER_PACE
	if river == null or not river.water_at(pos):
		return 1.0
	if town != null and town.on_road(pos):
		return 1.0
	return RIVER_PACE


func surface(pos: Vector2) -> String:
	if world_board != null:
		return world_board.surface_at(pos)
	var tile := float(TerrainCatalog.TILE_SIZE)
	var local := pos - space_origin
	var x := floori(local.x / tile)
	var y := floori(local.y / tile)
	if x < 0 or y < 0 or x >= _tiles or y >= _tiles:
		return ""
	return _names[_terrain[y * _tiles + x]]


## Velikost mapy v pixelech.
func world() -> Vector2:
	return _map_size


## Odkud se začíná: před výstupkem továrny. Bez továrny střed mapy.
func home() -> Vector2:
	var spot := town.home() if town != null else Vector2.INF
	return space_origin + _map_size * 0.5 if spot == Vector2.INF else spot


## Krok z from do desired. Když cíl nejde, zkusí klouzat jen po ose x, pak jen po ose y.
## Když nejde nic, zůstane na místě.
func allowed(from: Vector2, desired: Vector2, body: float, clearance: float, who: int = -1) -> Vector2:
	var landed := place(desired, body, clearance, who)
	if stands(landed, body):
		return landed
	var along_x := place(Vector2(desired.x, from.y), body, clearance, who)
	if stands(along_x, body):
		return along_x
	var along_y := place(Vector2(from.x, desired.y), body, clearance, who)
	if stands(along_y, body):
		return along_y
	return from


## Vytlačí bod z překážek a ořízne na mapu. clearance < 0 drží všechno, jinak je tělo ve skoku:
## překážky a tvory do výšky clearance metrů přeskočí.
func place(pos: Vector2, body: float, clearance: float = -1.0, who: int = -1) -> Vector2:
	if world_board != null:
		pos = world_board.move_body(pos, body, clearance)
		if crowd != null and who >= 0:
			pos = crowd.avoid(pos, body, who, clearance)
		if fence.has_area():
			pos = pos.clamp(fence.position, fence.end)
		return pos
	for _pass in 2:
		pos = _rocks.avoid(pos, body, clearance)
		pos = _forest.avoid(pos, body, clearance)
		if town != null:
			pos = town.avoid(pos, body)
		if crowd != null and who >= 0:
			pos = crowd.avoid(pos, body, who, clearance)
	return fit(pos, EDGE_M * float(TerrainCatalog.TILE_SIZE))


## Drží bod uvnitř mapy. margin je odstup od kraje v pixelech.
func fit(pos: Vector2, margin: float) -> Vector2:
	var limit := space_origin + _map_size - Vector2(margin, margin)
	return Vector2(
		clampf(pos.x, space_origin.x + margin, limit.x - 0.001),
		clampf(pos.y, space_origin.y + margin, limit.y - 0.001)
	)


## Leží bod na téhle mapě, aspoň margin pixelů od kraje?
func contains(pos: Vector2, margin: float = 0.0) -> bool:
	var local := pos - space_origin
	return local.x >= margin and local.y >= margin and local.x < _map_size.x - margin and local.y < _map_size.y - margin


## Střed i obvod těla musí být na schůdném povrchu: souš nebo mělčina.
func stands(pos: Vector2, body: float) -> bool:
	if not dry(pos):
		return false
	for probe: Vector2 in PROBES:
		if not dry(pos + probe * body):
			return false
	return true


func dry(pos: Vector2) -> bool:
	if world_board != null:
		return world_board.is_dry(pos)
	var at := ground(pos)
	return at == LAND or at == SHALLOW


## Povrch dlaždice pod bodem na téhle mapě (LAND, SHALLOW, EDGE_WATER, DEEP). Mimo mapu DEEP.
func ground(pos: Vector2) -> int:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var local := pos - space_origin
	var x := floori(local.x / tile)
	var y := floori(local.y / tile)
	if x < 0 or y < 0 or x >= _tiles or y >= _tiles:
		return DEEP
	return _walkable[y * _tiles + x]


## Stojí tělo v překážce nebo na vodě? Překážka by ho posunula, voda neunese.
func blocked(pos: Vector2, body: float, who: int = -1) -> bool:
	if place(pos, body, -1.0, who).distance_squared_to(pos) > 0.25:
		return true
	return not stands(pos, body)


## Nejbližší místo, kde tělo nikde nezavazí a stojí na souši. Kruhy kolem from po step pixelech,
## nejdál reach. Když nic není, vrátí Vector2.INF.
func free_spot(from: Vector2, body: float, reach: float, step: float, who: int = -1) -> Vector2:
	var radius := step
	while radius <= reach:
		var around := clampi(int(TAU * radius / step / 2.0), 8, 64)
		var turn := fposmod(radius * 0.37, TAU)
		for i in around:
			var spot := from + Vector2.from_angle(turn + TAU * float(i) / float(around)) * radius
			if not blocked(spot, body, who):
				return spot
		radius += step
	return Vector2.INF
