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


func cell(x: int, y: int) -> int:
	return y * size + x


func name_at(x: int, y: int) -> String:
	return names[terrain[y * size + x]]


func info_of(terrain_id: int) -> Dictionary:
	return surfaces.get(names[terrain_id], {})
