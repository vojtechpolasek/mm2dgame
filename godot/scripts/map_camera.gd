extends Camera2D

const ACCELERATION := 2800.0
const MAX_SPEED := 1100.0
const STOP_SPEED := 7500.0

var _velocity := Vector2.ZERO
var _map_size := Vector2.ZERO


func setup(map_size: Vector2) -> void:
	_map_size = map_size
	position = (map_size * 0.5).round()
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
	_clamp_position()


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
