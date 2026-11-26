extends Node3D

signal context_requested(at: Vector2)

## The pivot moves on the table plane; the pitch and distance stay relative to it.
const MIN_PITCH: float = -80.0
const MAX_PITCH: float = -24.0
const MIN_DISTANCE: float = 7.0
const MAX_DISTANCE: float = 57.0
const ORBIT_SPEED: float = 0.18
const ZOOM_RESPONSE: float = 13.0
const PAN_SPEED: float = 0.40

@export_range(1.0, 25.0, 0.1) var pan_apothem: float = 12.0

var _input_context: PartyInput
var _seat_yaw: float
var _home_pitch: float
var _home_distance: float
var _target_distance: float
var _overhead: bool = false
var _drag_buttons: int = 0
var _right_pending: bool = false
var _right_origin: Vector2

@onready var _pitch: Node3D = %Pitch
@onready var _camera: Camera3D = %Camera3D


func _ready() -> void:
	_home_pitch = _pitch.rotation_degrees.x
	_home_distance = _camera.position.z
	set_controls_active(false)


## A null context belongs exclusively to the standalone scene preview.
func configure(input_context: PartyInput, seat_yaw: float) -> void:
	_input_context = input_context
	_seat_yaw = seat_yaw
	_set_view(false)


func set_controls_active(active: bool) -> void:
	_drag_buttons = 0
	_right_pending = false
	set_process(active)
	set_process_unhandled_input(active)


func reset_view() -> void:
	_set_view(false)


func toggle_overhead() -> void:
	_set_view(not _overhead)


func _set_view(overhead: bool) -> void:
	_overhead = overhead
	position = Vector3.ZERO
	rotation.y = _seat_yaw
	_pitch.rotation_degrees.x = -90.0 if overhead else _home_pitch
	# Keep the entire octagon visible in the overhead view.
	_target_distance = _home_distance * 1.10 if overhead else _home_distance
	_camera.position.z = _target_distance


func _process(delta: float) -> void:
	if _input_context != null and _input_context.input_blocked:
		_drag_buttons = 0
		_right_pending = false
		return
	var axes: Vector2 = Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	).limit_length()
	if axes != Vector2.ZERO and get_window().has_focus():
		_pan(axes * _camera.position.z * PAN_SPEED * delta)
	_camera.position.z = lerpf(_camera.position.z, _target_distance, 1.0 - exp(-ZOOM_RESPONSE * delta))


func _unhandled_input(event: InputEvent) -> void:
	if _input_context != null and _input_context.input_blocked:
		_drag_buttons = 0
		_right_pending = false
		return
	if event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion:
		_drag_buttons &= event.button_mask
		if _right_pending:
			if not event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
				_right_pending = false
			elif event.position.distance_squared_to(_right_origin) > 36.0:
				_right_pending = false
				_drag_buttons |= MOUSE_BUTTON_MASK_RIGHT
		if _drag_buttons & MOUSE_BUTTON_MASK_RIGHT:
			rotation_degrees.y -= event.screen_relative.x * ORBIT_SPEED
			if not _overhead:
				_pitch.rotation_degrees.x = clampf(
					_pitch.rotation_degrees.x - event.screen_relative.y * ORBIT_SPEED, MIN_PITCH, MAX_PITCH)
		elif _drag_buttons & MOUSE_BUTTON_MASK_MIDDLE:
			var world_per_pixel: float = 2.0 * _camera.position.z * tan(deg_to_rad(_camera.fov * 0.5)) / get_viewport().get_visible_rect().size.y
			_pan(Vector2(-event.relative.x, -event.relative.y) * world_per_pixel)
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and not event.is_command_or_control_pressed() and not event.alt_pressed:
		match event.physical_keycode:
			KEY_SPACE:
				reset_view()
			KEY_V:
				toggle_overhead()
			_:
				return
		get_viewport().set_input_as_handled()


func _mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_right_origin = event.position
				_right_pending = true
				return
			if _right_pending and event.position.distance_squared_to(_right_origin) <= 36.0:
				context_requested.emit(event.position)
			_right_pending = false
			_drag_buttons &= ~MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_drag_buttons |= MOUSE_BUTTON_MASK_MIDDLE
			else:
				_drag_buttons &= ~MOUSE_BUTTON_MASK_MIDDLE
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not event.pressed:
				return
			var step: float = -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_target_distance = clampf(_target_distance * pow(1.14, step * event.factor), MIN_DISTANCE, MAX_DISTANCE)
		_:
			return
	get_viewport().set_input_as_handled()


func _pan(offset: Vector2) -> void:
	var target: Vector3 = position + basis * Vector3(offset.x, 0.0, offset.y)
	var diagonal: float = (absf(target.x) + absf(target.z)) * sqrt(0.5)
	var furthest_edge: float = maxf(absf(target.x), maxf(absf(target.z), diagonal))
	if furthest_edge > pan_apothem:
		target *= pan_apothem / furthest_edge
	position = target


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_drag_buttons = 0
		_right_pending = false
