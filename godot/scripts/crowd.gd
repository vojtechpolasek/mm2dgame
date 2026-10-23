extends RefCounted

## Tvorové, kteří nechodí přes sebe: postava, vesničané a chodící příšery. Každý je kruh
## o poloměru těla. Neviditelný tvor (vesničan v domě) se nepočítá.
## Létající se nepočítá, letí nad ostatními. Kdo je ve skoku, přeskočí každého, kdo není vyšší
## než výška jeho skoku, a ten ho naopak podběhne.
## Člen má metody crowd_body() (poloměr v px), crowd_height() (výška v metrech),
## crowd_clearance() (výška skoku v metrech, záporná mimo skok) a crowd_flying().

var _members: Array[Node2D] = []
## Poloměr těla a výška každého tvora. Za hry se nemění, uloží se při join, ať se pro každou
## dvojici nevolají metody tvora.
var _bodies := PackedFloat32Array()
var _heights := PackedFloat32Array()
## Čísla tvorů, kteří odešli (leave). Další join je použije znovu, ať pole neroste.
var _spare := PackedInt32Array()


## Přidá tvora a vrátí jeho číslo. Číslem se tvor při pohybu vynechá sám ze sebe.
func join(member: Node2D) -> int:
	if not _spare.is_empty():
		var id := _spare[_spare.size() - 1]
		_spare.resize(_spare.size() - 1)
		_members[id] = member
		_bodies[id] = float(member.crowd_body())
		_heights[id] = float(member.crowd_height())
		return id
	_members.append(member)
	_bodies.append(float(member.crowd_body()))
	_heights.append(float(member.crowd_height()))
	return _members.size() - 1


## Tvor odešel nadobro. Jeho číslo dostane příští join.
func leave(id: int) -> void:
	if id < 0 or id >= _members.size() or _members[id] == null:
		return
	_members[id] = null
	_spare.append(id)


## Posune bod ven z ostatních tvorů. who je číslo tvora, který se hýbe. clearance je výška
## jeho skoku v metrech, záporná mimo skok. Nejdřív se zkouší vzdálenost, dotaz na stav tvora
## (schovaný, letí, skáče) jen u toho, kdo je dost blízko.
func avoid(pos: Vector2, body: float, who: int, clearance: float) -> Vector2:
	if who < 0 or who >= _members.size():
		return pos
	var height := _heights[who]
	var result := pos
	for i in _members.size():
		if i == who:
			continue
		var other := _members[i]
		if not is_instance_valid(other):
			continue
		var limit := body + _bodies[i]
		var delta := result - other.position
		var dist_sq := delta.length_squared()
		if dist_sq >= limit * limit:
			continue
		if not other.is_inside_tree() or not other.visible or bool(other.crowd_flying()):
			continue
		if clearance >= _heights[i] or float(other.crowd_clearance()) >= height:
			continue
		if dist_sq < 0.0001:
			result = other.position + Vector2(limit, 0.0)
		else:
			result = other.position + delta * (limit / sqrt(dist_sq))
	return result
