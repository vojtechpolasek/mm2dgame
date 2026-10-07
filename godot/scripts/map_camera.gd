extends Camera2D

const ACCELERATION := 2800.0
const MAX_SPEED := 1100.0
const STOP_SPEED := 7500.0

## Ladící zoom na numerickém + a −. Rychlost je v ln(zoom) za sekundu,
## takže přiblížení má stejný rozjezd a dobrzdění jako posun.
const ZOOM_ACCELERATION := 3.2
const ZOOM_MAX_SPEED := 1.25
const ZOOM_STOP_SPEED := 8.5

var _velocity := Vector2.ZERO
var _zoom_velocity := 0.0
var _map_size := Vector2.ZERO


func setup(map_size: Vector2) -> void:
	_map_size = map_size
	position = (map_size * 0.5).round()
	zoom = Vector2.ONE
	make_current()
	_clamp_position()


func _process(delta: float) -> void:
	if _map_size == Vector2.ZERO:
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction != Vector2.ZERO:
		_velocity += direction * ACCELERATION * delta
		if _velocity.length() > MAX_SPEED:
			_velocity = _velocity.limit_length(MAX_SPEED)
	else:
		_velocity = _velocity.move_toward(Vector2.ZERO, STOP_SPEED * delta)
	position += _velocity * delta
	if OS.is_debug_build():
		_apply_zoom(delta)
	_clamp_position()


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
	return minf(cover, 1.0)


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
