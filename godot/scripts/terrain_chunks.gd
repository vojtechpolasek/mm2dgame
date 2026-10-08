extends Node2D

## Terén po chuncích. Souš, přechody a břehy chunku se jednou předpečou do textury s mipmapami
## (terrain_bake.gdshader) a dál je kreslí obyčejný sprite. Drahý shader terénu tak neběží
## v každém snímku přes celou obrazovku. Voda se vlní jen přes dlaždice, které mají v rohu vodu
## (terrain_water.gdshader). Chunky se pečou podle kamery. Vzdálený chunk vrátí sprite i texturu
## do zásobníku, nový chunk si je odtud vezme a jen se přepeče. Založit texturu je drahé (jednotky
## ms), proto se zásobník naplní už při načítání levelu.

const TerrainCatalog := preload("res://scripts/terrain_catalog.gd")
const MapCamera := preload("res://scripts/map_camera.gd")

## Strana chunku v dlaždicích. Textura chunku má TILES * TILE_SIZE pixelů na stranu.
const TILES := 8
## Chunky do tolika pixelů světa za okrajem obrazovky se pečou dopředu, nejvýš BAKE_PER_FRAME
## za snímek. Chunk, který už je na obrazovce, se upeče hned.
const AHEAD := 256.0
const BAKE_PER_FRAME := 1
## Chunk dál než tolik pixelů za okrajem obrazovky se vrátí do zásobníku. Mezera proti AHEAD
## brání tomu, aby se chunk na hraně pekl a vracel dokola.
const KEEP := 512.0

var _camera: MapCamera
var _water: ShaderMaterial
var _bake_template: ShaderMaterial
## Každé pečení v jednom snímku potřebuje vlastní materiál, liší se chunk_origin.
var _bakers: Array[ShaderMaterial] = []
var _chunk_px := TILES * TerrainCatalog.TILE_SIZE
var _map_px := 0
var _count := 0
## Klíč chunku -> levé horní rohy dlaždic s vodou v chunku, v pixelech od rohu chunku.
var _water_tiles := {}
## Klíč chunku -> Sprite2D. Neupečený chunk je skrytý.
var _live := {}
## Volné sprity chunků i s texturou a vodou, čekají na další chunk.
var _pool: Array[Sprite2D] = []
## Klíč chunku -> ArrayMesh vody. Postaví se poprvé, když je chunk vidět.
var _water_meshes := {}
## Chunky čekající na pečení, nejbližší ke středu obrazovky první.
var _queue: Array[Vector2i] = []
var _baked_this_frame := 0
var _bake_frame := -1


## corners jsou čtyři bajty rohů na dlaždici z MapGenerator.corner_data. Katalog už má mapu
## nastavenou (set_map).
func setup(catalog: TerrainCatalog, size: int, corners: PackedByteArray, camera: MapCamera) -> void:
	_camera = camera
	_map_px = size * TerrainCatalog.TILE_SIZE
	_count = ceili(float(size) / float(TILES))
	_bake_template = catalog.bake_material
	_bake_template.set_shader_parameter("chunk_px", float(_chunk_px))
	_water = catalog.water_material
	_water.set_shader_parameter("chunk_px", float(_chunk_px))
	_find_water(size, corners, catalog.water_index)
	_prefill()
	camera.view_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	_new_frame()
	while not _queue.is_empty() and _baked_this_frame < BAKE_PER_FRAME:
		var key: Vector2i = _queue.pop_front()
		if _live.has(key) and not (_live[key] as Sprite2D).visible:
			_bake(key)


func _find_water(size: int, corners: PackedByteArray, water: int) -> void:
	_water_tiles.clear()
	if water < 0:
		return
	var tile := TerrainCatalog.TILE_SIZE
	for y in size:
		for x in size:
			var cell := (y * size + x) * 4
			if corners[cell] != water and corners[cell + 1] != water and corners[cell + 2] != water and corners[cell + 3] != water:
				continue
			var key := Vector2i(x / TILES, y / TILES)
			var spots: PackedVector2Array = _water_tiles.get(key, PackedVector2Array())
			spots.append(Vector2((x % TILES) * tile, (y % TILES) * tile))
			_water_tiles[key] = spots


func _refresh() -> void:
	var size := _camera.get_viewport_rect().size / _camera.zoom
	var view := Rect2(_camera.get_screen_center_position() - size * 0.5, size)
	var keep := view.grow(KEEP)
	for key: Vector2i in _live.keys():
		if not keep.intersects(_chunk_rect(key)):
			var sprite: Sprite2D = _live[key]
			sprite.visible = false
			_pool.append(sprite)
			_live.erase(key)
	var ahead := _cells(view.grow(AHEAD))
	var added := false
	for y in range(ahead.position.y, ahead.end.y):
		for x in range(ahead.position.x, ahead.end.x):
			var key := Vector2i(x, y)
			if not _live.has(key):
				_create(key)
				_queue.append(key)
				added = true
	# Co je už na obrazovce, se upeče hned, jinak by tam byla díra.
	var seen := _cells(view)
	for y in range(seen.position.y, seen.end.y):
		for x in range(seen.position.x, seen.end.x):
			var key := Vector2i(x, y)
			if not (_live[key] as Sprite2D).visible:
				_bake(key)
	if added:
		var center := view.get_center()
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
	while _pool.size() < across * down:
		_pool.append(_new_sprite())


## Sprite s prázdnou texturou a vrstvou vody. Voda se zapne jen u chunku, který vodu má.
func _new_sprite() -> Sprite2D:
	var texture := DrawableTexture2D.new()
	texture.setup(_chunk_px, _chunk_px, DrawableTexture2D.DRAWABLE_FORMAT_RGBA8, Color.BLACK, true)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.visible = false
	var water := MeshInstance2D.new()
	water.texture = texture
	water.material = _water
	water.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.add_child(water)
	add_child(sprite)
	return sprite


## Sprite pro chunk ze zásobníku. Ukáže se, až je upečený. Chunk na kraji mapy kreslí jen tu
## část textury, která je v mapě.
func _create(key: Vector2i) -> void:
	var sprite: Sprite2D = _pool.pop_back() if not _pool.is_empty() else _new_sprite()
	sprite.position = Vector2(key) * _chunk_px
	var inside := Vector2(mini(_chunk_px, _map_px - key.x * _chunk_px), mini(_chunk_px, _map_px - key.y * _chunk_px))
	sprite.region_enabled = inside.x < _chunk_px or inside.y < _chunk_px
	sprite.region_rect = Rect2(Vector2.ZERO, inside)
	var water := sprite.get_child(0) as MeshInstance2D
	water.visible = _water_tiles.has(key)
	if water.visible:
		if not _water_meshes.has(key):
			_water_meshes[key] = _water_mesh(_water_tiles[key])
		water.mesh = _water_meshes[key]
	else:
		water.mesh = null
	_live[key] = sprite


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


func _bake(key: Vector2i) -> void:
	_new_frame()
	var sprite: Sprite2D = _live[key]
	while _bakers.size() <= _baked_this_frame:
		_bakers.append(_bake_template.duplicate() as ShaderMaterial)
	var baker := _bakers[_baked_this_frame]
	baker.set_shader_parameter("chunk_origin", Vector2(key) * _chunk_px)
	var texture := sprite.texture as DrawableTexture2D
	texture.blit_rect(Rect2i(0, 0, _chunk_px, _chunk_px), null, Color.WHITE, 0, baker)
	texture.generate_mipmaps()
	sprite.visible = true
	_baked_this_frame += 1


## Pečení se provede až při kreslení snímku. Materiál se proto smí znovu použít až v dalším snímku.
func _new_frame() -> void:
	var frame := Engine.get_process_frames()
	if frame != _bake_frame:
		_bake_frame = frame
		_baked_this_frame = 0
