extends Camera2D

## Ladící zoom na numerickém + a −. Rychlost je v ln(zoom) za sekundu,
## takže přiblížení má stejný rozjezd a dobrzdění jako posun.
const ZOOM_ACCELERATION := 3.2
const ZOOM_MAX_SPEED := 1.25
const ZOOM_STOP_SPEED := 8.5
## Nejdál se oddálí na polovinu, tedy dvakrát víc mapy na šířku i výšku. Celou mapu neukáže.
const ZOOM_MIN := 0.5

## Střed, zoom nebo velikost okna se změnily. Globální uniformy shaderů už mají nové hodnoty.
signal view_changed

var _zoom_velocity := 0.0
## Zoom určuje skupina hráčů (frame). Ladicí zoom na klávesnici se pak nepoužije.
var _framed := false
var _map_size := Vector2.ZERO
var _published_center := Vector2.INF
var _published_zoom := 0.0
var _published_view := Vector2.ZERO


func setup(map_size: Vector2) -> void:
	_map_size = map_size
	position = (map_size * 0.5).round()
	zoom = Vector2.ONE
	make_current()
	_clamp_position()
	_publish_view()


func _process(delta: float) -> void:
	if _map_size == Vector2.ZERO:
		return
	if OS.is_debug_build() and not _framed:
		_apply_zoom(delta)
	_clamp_position()
	_publish_view()


## Pohled na skupinu hráčů: střed a zoom. Zoom se drží v mezích mapy a ZOOM_MIN.
func frame(center: Vector2, target_zoom: float) -> void:
	_framed = true
	if _map_size != Vector2.ZERO:
		zoom = Vector2.ONE * clampf(target_zoom, _min_zoom(), 1.0)
	position = center
	_clamp_position()
	_publish_view()


## Postava je střed pohledu. U kraje mapy kamera zůstane v mapě, postava pak ze středu obrazovky odejde.
func follow(target: Vector2) -> void:
	position = target
	_clamp_position()
	_publish_view()


## Vrstvy objektů čtou střed a zoom z globálních uniforem, jedno nastavení platí pro všechny materiály.
func _publish_view() -> void:
	var center := get_screen_center_position()
	var view := get_viewport_rect().size
	if center == _published_center and zoom.x == _published_zoom and view == _published_view:
		return
	_published_center = center
	_published_zoom = zoom.x
	_published_view = view
	RenderingServer.global_shader_parameter_set(&"camera_position", center)
	RenderingServer.global_shader_parameter_set(&"camera_zoom", zoom.x)
	view_changed.emit()


func _apply_zoom(delta: float) -> void:
	var direction := 0.0
	if Input.is_physical_key_pressed(KEY_KP_ADD):
		direction += 1.0
	if Input.is_physical_key_pressed(KEY_KP_SUBTRACT):
		direction -= 1.0
	if direction != 0.0:
		_zoom_velocity += direction * ZOOM_ACCELERATION * delta
		_zoom_velocity = clampf(_zoom_velocity, -ZOOM_MAX_SPEED, ZOOM_MAX_SPEED)
	else:
		_zoom_velocity = move_toward(_zoom_velocity, 0.0, ZOOM_STOP_SPEED * delta)
	var level := zoom.x
	if _zoom_velocity != 0.0:
		level *= exp(_zoom_velocity * delta)
	zoom = Vector2.ONE * clampf(level, _min_zoom(), 1.0)


func _min_zoom() -> float:
	var view := get_viewport_rect().size
	if _map_size.x <= 0.0 or _map_size.y <= 0.0:
		return 1.0
	# První strana, která by při dalším oddálení byla menší než obrazovka, zoom zastaví.
	var cover := maxf(view.x / _map_size.x, view.y / _map_size.y)
	return clampf(cover, ZOOM_MIN, 1.0)


func _clamp_position() -> void:
	var view := get_viewport_rect().size / zoom
	var half := view * 0.5
	if half.x >= _map_size.x * 0.5:
		position.x = _map_size.x * 0.5
	else:
		position.x = clampf(position.x, half.x, _map_size.x - half.x)
	if half.y >= _map_size.y * 0.5:
		position.y = _map_size.y * 0.5
	else:
		position.y = clampf(position.y, half.y, _map_size.y - half.y)
