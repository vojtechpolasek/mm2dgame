extends RefCounted

## Tvorové, kteří nechodí přes sebe: postava, vesničané a chodící příšery. Každý je kruh
## o poloměru těla. Neviditelný tvor (vesničan v domě) se nepočítá.
## Létající se nepočítá, letí nad ostatními. Kdo je ve skoku, přeskočí každého, kdo není vyšší
## než výška jeho skoku, a ten ho naopak podběhne.
## Člen má metody crowd_body() (poloměr v px), crowd_height() (výška v metrech),
## crowd_clearance() (výška skoku v metrech, záporná mimo skok) a crowd_flying().

var _members: Array[Node2D] = []


## Přidá tvora a vrátí jeho číslo. Číslem se tvor při pohybu vynechá sám ze sebe.
func join(member: Node2D) -> int:
	_members.append(member)
	return _members.size() - 1


## Posune bod ven z ostatních tvorů. who je číslo tvora, který se hýbe. clearance je výška
## jeho skoku v metrech, záporná mimo skok.
func avoid(pos: Vector2, body: float, who: int, clearance: float) -> Vector2:
	if who < 0 or who >= _members.size():
		return pos
	var height := float(_members[who].crowd_height())
	var result := pos
	for i in _members.size():
		if i == who:
			continue
		var other := _members[i]
		if not is_instance_valid(other) or not other.is_inside_tree() or not other.visible or bool(other.crowd_flying()):
			continue
		if clearance >= float(other.crowd_height()) or float(other.crowd_clearance()) >= height:
			continue
		var limit := body + float(other.crowd_body())
		var delta := result - other.position
		var dist_sq := delta.length_squared()
		if dist_sq >= limit * limit:
			continue
		if dist_sq < 0.0001:
			result = other.position + Vector2(limit, 0.0)
		else:
			result = other.position + delta * (limit / sqrt(dist_sq))
	return result
