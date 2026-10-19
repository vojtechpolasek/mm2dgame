extends RefCounted

## Vygenerovaná mapa. Zůstává ve světě i po vygenerování, hra z ní čte povrch dlaždic.
## Povrch dlaždice je index do names, stejný jako vrstva v atlasu terénu.

const UNCLAIMED_TERRAIN := 255

var size := 0
var names := PackedStringArray()
var surfaces := {}
var terrain := PackedByteArray()
## Cena růstu z generátoru. Nižší cena vyhrává roh dlaždice při kreslení přechodů.
var cost := PackedInt32Array()
## Souš, kterou generátor doplňuje mezery (viz MapGenerator.grow). -1 u mapy z uložené hry.
var land := -1
## Terén hned za krajem od sousedního čtverce světa. Prázdné pole nebo UNCLAIMED_TERRAIN
## znamená, že tam soused při tvoření mapy nebyl. Po řádcích západ a východ, po sloupcích sever a jih.
var halo_w := PackedByteArray()
var halo_e := PackedByteArray()
var halo_n := PackedByteArray()
var halo_s := PackedByteArray()


func cell(x: int, y: int) -> int:
	return y * size + x


func name_at(x: int, y: int) -> String:
	return names[terrain[y * size + x]]


func info_of(terrain_id: int) -> Dictionary:
	return surfaces.get(names[terrain_id], {})


## Terén dlaždice hned za krajem ve směru (dx, dy). Bez souseda -1.
func outside(x: int, y: int, dx: int, dy: int) -> int:
	var id := UNCLAIMED_TERRAIN
	if dx < 0 and x == 0 and y >= 0 and y < halo_w.size():
		id = halo_w[y]
	elif dx > 0 and x == size - 1 and y >= 0 and y < halo_e.size():
		id = halo_e[y]
	elif dy < 0 and y == 0 and x >= 0 and x < halo_n.size():
		id = halo_n[x]
	elif dy > 0 and y == size - 1 and x >= 0 and x < halo_s.size():
		id = halo_s[x]
	return -1 if id == UNCLAIMED_TERRAIN else id
