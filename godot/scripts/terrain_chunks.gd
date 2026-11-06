extends Node2D

## Terén po chuncích. Souš, přechody a břehy (jezero i řeka) chunku se jednou předpečou do
## textury s mipmapami (terrain_bake.gdshader) a dál je kreslí obyčejný sprite. Drahý shader
## terénu tak neběží v každém snímku přes celou obrazovku. Voda jezer se vlní jen přes dlaždice,
## které mají v rohu vodu (terrain_water.gdshader); vodu řeky kreslí river.gd. Hluboká voda
## (dlaždice celé ve vodě s vodou i kolem) má vlastní levnou vrstvu (terrain_water_deep.gdshader),
## drahý shader vody běží jen u břehů. Chunky se pečou podle kamery. Vzdálený chunk vrátí sprite i texturu do zásobníku, nový chunk si je odtud
## vezme a jen se přepeče. Založit texturu je drahé (jednotky ms), proto se zásobník naplní už
## při načítání levelu. Čtverce světa sdílejí jeden zásobník (share_spare), jinak by každý
## otevřený čtverec držel své textury, i když je daleko.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapCamera := preload("res://scripts/map_camera.gd")
## Chunk se kreslí neprůhledně, alfa textury nese výšku břehu (terrain_bake.gdshader).
const CHUNK_SHADER := preload("res://shaders/terrain_chunk.gdshader")
## Levná hluboká voda, materiál je kopie materiálu vody s tímhle shaderem (stejné parametry vln).
const DEEP_SHADER := preload("res://shaders/terrain_water_deep.gdshader")

## Strana chunku v dlaždicích. Textura chunku má TILES * TILE_SIZE pixelů na stranu.
const TILES := 8
## Chunky do tolika pixelů světa za okrajem obrazovky se pečou dopředu po STRIPS vodorovných
## pruzích, jeden pruh za snímek (celý chunk najednou je na slabé grafice zásek 8-15 ms).
## Chunk, který už je na obrazovce, se dopeče hned celý, ale nejvýš BAKE_NOW za snímek, ať
## rychlé oddálení nezasekne hru. Zbytek dojde z fronty, nejbližší ke středu první.
## Při prvním zobrazení se upeče všechno, co je vidět.
const AHEAD := 256.0
const STRIPS := 4
const BAKE_NOW := 3
## Chunk dál než tolik pixelů za okrajem obrazovky se vrátí do zásobníku. Mezera proti AHEAD
## brání tomu, aby se chunk na hraně pekl a vracel dokola.
const KEEP := 384.0
## Mipmapy upečeného chunku se dělají až o tolik snímků později. Hned po pečení by se čekalo,
## až grafika pečení dokončí (na slabé grafice desítky ms). Chunk se ukáže hned, jeho
## základní úroveň je hotová.
const MIP_DELAY := 2

var _camera: MapCamera
var _water: ShaderMaterial
var _deep: ShaderMaterial
var _bake_template: ShaderMaterial
## Každé pečení v jednom snímku potřebuje vlastní materiál, liší se chunk_origin a bake_rect.
var _bakers: Array[ShaderMaterial] = []
var _chunk_px := TILES * TerrainCatalog.TILE_SIZE
var _map_px := 0
var _count := 0
## Klíč chunku -> levé horní rohy dlaždic s vodou u břehu v chunku, v pixelech od rohu chunku.
var _water_tiles := {}
## Totéž pro hlubokou vodu: dlaždice celé ve vodě, jejichž sousedé jsou taky celí ve vodě.
var _deep_tiles := {}
## Klíč chunku -> Sprite2D. Neupečený chunk je skrytý.
var _live := {}
## Volné sprity chunků i s texturou a vodou, čekají na další chunk.
var _spare := Spare.new()
## Klíč chunku -> ArrayMesh vody u břehu a hluboké vody. Postaví se poprvé, když je chunk vidět.
var _water_meshes := {}
var _deep_meshes := {}
## Chunky čekající na pečení, nejbližší ke středu obrazovky první.
var _queue: Array[Vector2i] = []
## Klíč rozpečeného chunku -> počet hotových pruhů.
var _strips := {}
## Celé chunky upečené v tomto snímku (BAKE_NOW) a všechna pečení včetně pruhů (materiály).
var _baked_this_frame := 0
var _blits_this_frame := 0
var _bake_frame := -1
var _shown := false
## Upečené chunky čekající na mipmapy: [textura, snímek, od kterého se smí udělat].
var _mips: Array = []


## Zásobník volných spritů. cap je velikost, nad kterou se volné sprity uvolní, ať po oddálení
## nezůstanou textury navíc.
class Spare:
	extends RefCounted
	var sprites: Array[Sprite2D] = []
	var cap := 0


## Dlaždice s vodou spočítané předem ve vlákně (find_water). Prázdné, spočítají se v setup.
var water_tiles: Array = []
## Výřezy pole koryta řeky pro pečení (River.field_tiles): klíč chunku -> [Image, počátek].
## Textura z výřezu vznikne při prvním pečení chunku a zůstane tu.
var river_tiles := {}
## Majitel sdíleného zásobníku. Sprity uvolněného čtverce se přestěhují k němu.
var _spare_owner: Node2D
## Materiál všech chunků, jeden kvůli dávkování kreslení.
static var _chunk_material: ShaderMaterial


## Bere a vrací sprity do zásobníku jiných chunků. Volá se před setup.
func share_spare(other: Node2D) -> void:
	_spare = other.get("_spare")
	_spare_owner = other


## Před uvolněním čtverce: zobrazené chunky vrátí do zásobníku a sprity, které visí pod tímto
## uzlem, přestěhuje k majiteli zásobníku, ať zůstanou ostatním čtvercům.
func detach() -> void:
	for key: Vector2i in _live.keys():
		var sprite: Sprite2D = _live[key]
		sprite.visible = false
		_spare.sprites.append(sprite)
	_live.clear()
	_queue.clear()
	_strips.clear()
	if _spare_owner == null:
		return
	for sprite in _spare.sprites:
		if is_instance_valid(sprite) and sprite.get_parent() == self:
			sprite.reparent(_spare_owner, false)


## corners jsou čtyři bajty rohů na dlaždici z MapGenerator.corner_data. Katalog už má mapu
## nastavenou (set_map).
func setup(
	catalog: TerrainCatalog,
	size: int,
	corners: PackedByteArray,
	camera: MapCamera,
	bake: ShaderMaterial = null,
	water: ShaderMaterial = null,
) -> void:
	_camera = camera
	_map_px = size * TerrainCatalog.TILE_SIZE
	_count = ceili(float(size) / float(TILES))
	_bake_template = catalog.bake_material if bake == null else bake
	_bake_template.set_shader_parameter("chunk_px", float(_chunk_px))
	_water = catalog.water_material if water == null else water
	_water.set_shader_parameter("chunk_px", float(_chunk_px))
	_deep = _water.duplicate() as ShaderMaterial
	_deep.shader = DEEP_SHADER
	if water_tiles.is_empty():
		water_tiles = find_water(size, corners, catalog.water_index)
	_water_tiles = water_tiles[0]
	_deep_tiles = water_tiles[1]
	water_tiles = []
	_prefill()
	camera.view_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	_new_frame()
	var frame := Engine.get_process_frames()
	while not _mips.is_empty() and int(_mips[0][1]) <= frame:
		(_mips.pop_front()[0] as DrawableTexture2D).generate_mipmaps()
	while not _queue.is_empty() and _blits_this_frame == 0:
		var key: Vector2i = _queue[0]
		if not _live.has(key) or (_live[key] as Sprite2D).visible:
			_queue.pop_front()
			continue
		var done: int = _strips.get(key, 0)
		_blit(key, done, done + 1)
		if done + 1 < STRIPS:
			_strips[key] = done + 1
		else:
			_queue.pop_front()
			_finish(key)


## Dlaždice s vodou v rohu rozdělí na hlubokou vodu a vodu u břehu. Hluboká je dlaždice celá ve
## vodě, kolem které je jen taková voda: posun hladiny (water_parallax) je menší než dlaždice,
## břeh tam proto nikdy neprosvitne. Vrací [voda u břehu, hluboká voda] jako _water_tiles
## a _deep_tiles. Smí běžet ve vlákně.
static func find_water(size: int, corners: PackedByteArray, water: int) -> Array:
	var shore := {}
	var deep_tiles := {}
	if water < 0:
		return [shore, deep_tiles]
	var full := PackedByteArray()
	full.resize(size * size)
	for index in size * size:
		var cell := index * 4
		if corners[cell] == water and corners[cell + 1] == water and corners[cell + 2] == water and corners[cell + 3] == water:
			full[index] = 1
	var tile := TerrainCatalog.TILE_SIZE
	for y in size:
		for x in size:
			var cell := (y * size + x) * 4
			if corners[cell] != water and corners[cell + 1] != water and corners[cell + 2] != water and corners[cell + 3] != water:
				continue
			var deep := full[y * size + x] == 1
			for ny in range(y - 1, y + 2):
				for nx in range(x - 1, x + 2):
					if nx < 0 or ny < 0 or nx >= size or ny >= size or full[ny * size + nx] == 0:
						deep = false
			var tiles: Dictionary = deep_tiles if deep else shore
			var key := Vector2i(x / TILES, y / TILES)
			var spots: PackedVector2Array = tiles.get(key, PackedVector2Array())
			spots.append(Vector2((x % TILES) * tile, (y % TILES) * tile))
			tiles[key] = spots
	return [shore, deep_tiles]


func _refresh() -> void:
	_new_frame()
	var size := _camera.get_viewport_rect().size / _camera.zoom
	var center := _camera.get_screen_center_position() - global_position
	var view := Rect2(center - size * 0.5, size)
	var keep := view.grow(KEEP)
	for key: Vector2i in _live.keys():
		if not keep.intersects(_chunk_rect(key)):
			var sprite: Sprite2D = _live[key]
			sprite.visible = false
			_spare.sprites.append(sprite)
			_live.erase(key)
			_strips.erase(key)
	var ahead := _cells(view.grow(AHEAD))
	var added := false
	for y in range(ahead.position.y, ahead.end.y):
		for x in range(ahead.position.x, ahead.end.x):
			var key := Vector2i(x, y)
			if not _live.has(key):
				_create(key)
				_queue.append(key)
				added = true
	# Až po nových chunkách, ty si sprity berou ze zásobníku.
	while _spare.sprites.size() > _spare.cap:
		_spare.sprites.pop_back().queue_free()
	# Co je už na obrazovce, se upeče hned, jinak by tam byla díra. Po prvním zobrazení nejvýš
	# BAKE_NOW za snímek, zbytek dopeče fronta.
	var seen := _cells(view)
	for y in range(seen.position.y, seen.end.y):
		for x in range(seen.position.x, seen.end.x):
			var key := Vector2i(x, y)
			if not (_live[key] as Sprite2D).visible and (not _shown or _baked_this_frame < BAKE_NOW):
				_bake(key)
	_shown = true
	if added:
		_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _chunk_rect(a).get_center().distance_squared_to(center) < _chunk_rect(b).get_center().distance_squared_to(center))


## Chunky, které zasahují do rect, oříznuté na mapu. end je za posledním.
func _cells(rect: Rect2) -> Rect2i:
	var from := Vector2i(clampi(floori(rect.position.x / _chunk_px), 0, _count), clampi(floori(rect.position.y / _chunk_px), 0, _count))
	var to := Vector2i(clampi(ceili(rect.end.x / _chunk_px), 0, _count), clampi(ceili(rect.end.y / _chunk_px), 0, _count))
	return Rect2i(from, to - from)


func _chunk_rect(key: Vector2i) -> Rect2:
	return Rect2(Vector2(key) * _chunk_px, Vector2(_chunk_px, _chunk_px))


## Tolik spritů, kolik chunků se při zoomu 1 vejde do obrazovky zvětšené o KEEP, nejvýš celá
## mapa. Oddálená kamera si další založí sama.
func _prefill() -> void:
	var view := _camera.get_viewport_rect().size + Vector2(KEEP, KEEP) * 2.0
	var across := mini(ceili(view.x / _chunk_px) + 1, _count)
	var down := mini(ceili(view.y / _chunk_px) + 1, _count)
	# Sdílený zásobník už naplnil první chunk.
	if _spare.cap > 0:
		return
	_spare.cap = across * down
	while _spare.sprites.size() < _spare.cap:
		_spare.sprites.append(_new_sprite())


## Sprite s prázdnou texturou a vrstvou vody. Voda se zapne jen u chunku, který vodu má.
func _new_sprite() -> Sprite2D:
	var texture := DrawableTexture2D.new()
	texture.setup(_chunk_px, _chunk_px, DrawableTexture2D.DRAWABLE_FORMAT_RGBA8, Color.BLACK, true)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _chunk_material == null:
		_chunk_material = ShaderMaterial.new()
		_chunk_material.shader = CHUNK_SHADER
		_chunk_material.set_shader_parameter("chunk_px", float(TILES * TerrainCatalog.TILE_SIZE))
	sprite.material = _chunk_material
	sprite.visible = false
	# Dítě 0 je voda u břehu, dítě 1 hluboká voda.
	for material in [_water, _deep]:
		var water := MeshInstance2D.new()
		water.texture = texture
		water.material = material
		water.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.add_child(water)
	add_child(sprite)
	return sprite


## Sprite pro chunk ze zásobníku. Ukáže se, až je upečený. Chunk na kraji mapy kreslí jen tu
## část textury, která je v mapě. Sprite od jiného čtverce se přestěhuje sem a dostane vodu
## tohoto čtverce.
func _create(key: Vector2i) -> void:
	var sprite: Sprite2D = null
	# Nejdéle volný sprite: jeho textura už se nekreslí a přepečení nečeká na grafiku.
	while sprite == null and not _spare.sprites.is_empty():
		sprite = _spare.sprites.pop_front()
		if not is_instance_valid(sprite):
			sprite = null
	if sprite == null:
		sprite = _new_sprite()
	elif sprite.get_parent() != self:
		sprite.reparent(self, false)
	sprite.position = Vector2(key) * _chunk_px
	var inside := Vector2(mini(_chunk_px, _map_px - key.x * _chunk_px), mini(_chunk_px, _map_px - key.y * _chunk_px))
	sprite.region_enabled = inside.x < _chunk_px or inside.y < _chunk_px
	sprite.region_rect = Rect2(Vector2.ZERO, inside)
	for layer in [[0, _water, _water_tiles, _water_meshes], [1, _deep, _deep_tiles, _deep_meshes]]:
		var water := sprite.get_child(layer[0]) as MeshInstance2D
		var tiles: Dictionary = layer[2]
		var meshes: Dictionary = layer[3]
		water.material = layer[1]
		water.visible = tiles.has(key)
		if water.visible:
			if not meshes.has(key):
				meshes[key] = _water_mesh(tiles[key])
			water.mesh = meshes[key]
		else:
			water.mesh = null
	_live[key] = sprite
	_strips.erase(key)


## Čtverec za každou dlaždici s vodou. UV ukazuje do textury chunku.
func _water_mesh(spots: PackedVector2Array) -> ArrayMesh:
	var tile := float(TerrainCatalog.TILE_SIZE)
	var corners: Array[Vector2] = [Vector2(0, 0), Vector2(tile, 0), Vector2(tile, tile), Vector2(0, 0), Vector2(tile, tile), Vector2(0, tile)]
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	for spot in spots:
		for corner in corners:
			vertices.append(spot + corner)
			uvs.append((spot + corner) / float(_chunk_px))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Dopeče chunk celý (zbylé pruhy jedním pečením) a ukáže ho.
func _bake(key: Vector2i) -> void:
	_new_frame()
	_blit(key, _strips.get(key, 0), STRIPS)
	_finish(key)
	_baked_this_frame += 1


## Upeče pruhy from až to (bez to) chunku do jeho textury.
func _blit(key: Vector2i, from: int, to: int) -> void:
	_new_frame()
	while _bakers.size() <= _blits_this_frame:
		_bakers.append(_bake_template.duplicate() as ShaderMaterial)
	var baker := _bakers[_blits_this_frame]
	var share := 1.0 / STRIPS
	baker.set_shader_parameter("chunk_origin", Vector2(key) * _chunk_px)
	baker.set_shader_parameter("bake_rect", Vector4(0.0, from * share, 1.0, (to - from) * share))
	var field: Array = river_tiles.get(key, [])
	baker.set_shader_parameter("river_field_on", 0.0 if field.is_empty() else 1.0)
	if not field.is_empty():
		if field[0] is Image:
			field[0] = ImageTexture.create_from_image(field[0])
		baker.set_shader_parameter("river_field", field[0])
		baker.set_shader_parameter("river_field_size", float((field[0] as Texture2D).get_width()))
		baker.set_shader_parameter("river_field_origin", field[1])
	var rows := _chunk_px / STRIPS
	var texture := (_live[key] as Sprite2D).texture as DrawableTexture2D
	texture.blit_rect(Rect2i(0, from * rows, _chunk_px, (to - from) * rows), null, Color.WHITE, 0, baker)
	_blits_this_frame += 1


func _finish(key: Vector2i) -> void:
	var sprite: Sprite2D = _live[key]
	_strips.erase(key)
	_mips.append([sprite.texture, Engine.get_process_frames() + MIP_DELAY])
	sprite.visible = true


## Pečení se provede až při kreslení snímku. Materiál se proto smí znovu použít až v dalším snímku.
func _new_frame() -> void:
	var frame := Engine.get_process_frames()
	if frame != _bake_frame:
		_bake_frame = frame
		_baked_this_frame = 0
		_blits_this_frame = 0
