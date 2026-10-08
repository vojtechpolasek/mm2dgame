extends RefCounted

## Pohyb po zemi, společný postavě i příšerám. Překážky jsou paty skal, keře a kmeny, ostatní
## tvorové z crowd, neschůdný povrch je voda a mimo mapu se nesmí. Tělo je kruh o poloměru
## body v pixelech. who je číslo tvora v crowd, -1 ostatní tvory nebere v úvahu.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const Rocks := preload("res://scripts/rocks.gd")
const Forest := preload("res://scripts/forest.gd")
const MapData := preload("res://scripts/map_data.gd")
const Crowd := preload("res://scripts/crowd.gd")

## Body na obvodu těla, které musí stát na souši.
const PROBES: Array[Vector2] = [
	Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(0.707, 0.707), Vector2(0.707, -0.707), Vector2(-0.707, 0.707), Vector2(-0.707, -0.707),
]

var _rocks: Rocks
var _forest: Forest
var _map_size := Vector2.ZERO
var _tiles := 0
var _walkable := PackedByteArray()
var _terrain := PackedByteArray()
var _names := PackedStringArray()
## Tvorové, kteří nechodí přes sebe. Nastaví svět, než se kdo pohne.
var crowd: Crowd


func _init(rocks: Rocks, forest: Forest, map: MapData) -> void:
	_rocks = rocks
	_forest = forest
	var tile := float(TerrainCatalog.TILE_SIZE)
	_tiles = map.size
	_map_size = Vector2(tile, tile) * float(map.size)
	_terrain = map.terrain
	_names = map.names
	_walkable.resize(map.terrain.size())
	for index in map.terrain.size():
		var info: Dictionary = map.surfaces.get(map.names[map.terrain[index]], {})
		_walkable[index] = 1 if bool(info.get("walkable", true)) else 0


## Označí v mřížce buňky (dlaždice), na kterých se nedá stát: voda.
func block_water(grid: AStarGrid2D) -> void:
	for y in _tiles:
		for x in _tiles:
			if _walkable[y * _tiles + x] != 1:
				grid.set_point_solid(Vector2i(x, y))


## Jméno povrchu pod bodem (grass, dirt, ...). Mimo mapu prázdné.
func surface(pos: Vector2) -> String:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var x := int(pos.x / tile)
	var y := int(pos.y / tile)
	if x < 0 or y < 0 or x >= _tiles or y >= _tiles:
		return ""
	return _names[_terrain[y * _tiles + x]]


## Velikost mapy v pixelech.
func world() -> Vector2:
	return _map_size


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
## nízké překážky a malé tvory přeskočí.
func place(pos: Vector2, body: float, clearance: float = -1.0, who: int = -1) -> Vector2:
	for _pass in 2:
		pos = _rocks.avoid(pos, body, clearance)
		pos = _forest.avoid(pos, body, clearance)
		if crowd != null and who >= 0:
			pos = crowd.avoid(pos, body, who, clearance >= 0.0)
	var limit := _map_size - Vector2(0.001, 0.001)
	pos.x = clampf(pos.x, 0.0, limit.x)
	pos.y = clampf(pos.y, 0.0, limit.y)
	return pos


## Střed i obvod těla musí být na schůdném povrchu. Voda má walkable false.
func stands(pos: Vector2, body: float) -> bool:
	if not dry(pos):
		return false
	for probe: Vector2 in PROBES:
		if not dry(pos + probe * body):
			return false
	return true


func dry(pos: Vector2) -> bool:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var x := int(pos.x / tile)
	var y := int(pos.y / tile)
	if x < 0 or y < 0 or x >= _tiles or y >= _tiles:
		return false
	return _walkable[y * _tiles + x] == 1


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
