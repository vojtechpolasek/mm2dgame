extends RefCounted

## Postavy hráčů a kamera, která je drží všechny na obrazovce. Pohled je vycentrovaný na střed
## obdélníku, který obepíná všechny postavy, a oddálí se tak, aby se vešly i s okrajem EDGE_PX,
## nejvýš na ZOOM_MIN. Když by se postavy rozběhly dál, než pojme největší oddálení, postava,
## která utíká, se zastaví (leash). Jeden hráč má pohled jako dřív, zoom 1.

const MapCamera := preload("res://scripts/map_camera.gd")

## Nejdál se oddálí na polovinu, tedy dvakrát víc mapy na šířku i výšku.
const ZOOM_MIN := 0.5
## Pruh u kraje obrazovky v pixelech obrazovky, kam postava nevstoupí. Nahoře je širší,
## jsou tam panely HUD.
const EDGE_PX := 60.0
const TOP_PX := 140.0

var members: Array[Node2D] = []
var _camera: MapCamera


func _init(camera: MapCamera) -> void:
	_camera = camera


## Kam smí postava, aby se celá skupina vešla na obrazovku při největším oddálení.
## Vrací pos oříznutou podle polohy ostatních.
func leash(member: Node2D, pos: Vector2) -> Vector2:
	if members.size() < 2:
		return pos
	var reach := _reach()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for other in members:
		if other == member:
			continue
		lo = lo.min(other.position)
		hi = hi.max(other.position)
	return Vector2(clampf(pos.x, hi.x - reach.x, lo.x + reach.x), clampf(pos.y, hi.y - reach.y, lo.y + reach.y))


## Natočí kameru na skupinu: střed obdélníku postav a zoom, aby se vešly i s okrajem.
func frame() -> void:
	if members.is_empty():
		return
	var lo := members[0].position
	var hi := lo
	for member in members:
		lo = lo.min(member.position)
		hi = hi.max(member.position)
	var span := hi - lo
	var room := _room()
	var zoom := 1.0
	if span.x > 0.0:
		zoom = minf(zoom, room.x / span.x)
	if span.y > 0.0:
		zoom = minf(zoom, room.y / span.y)
	zoom = clampf(zoom, ZOOM_MIN, 1.0)
	# Volný prostor je pod panely, střed skupiny patří do jeho středu, ne do středu obrazovky.
	var shift := Vector2(0.0, (TOP_PX - EDGE_PX) * 0.5 / zoom)
	_camera.frame((lo + hi) * 0.5 - shift, zoom)


## Největší rozpětí postav ve světě: obrazovka při největším oddálení bez okrajů.
func _reach() -> Vector2:
	return _room() / ZOOM_MIN


## Volný prostor obrazovky v pixelech, kam postavy smí.
func _room() -> Vector2:
	var view := _camera.get_viewport_rect().size
	return Vector2(view.x - EDGE_PX * 2.0, view.y - TOP_PX - EDGE_PX)
