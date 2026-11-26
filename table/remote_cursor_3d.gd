extends Node3D

## Remote motion supplies a target. The pointer's movement, grip and fade are rendered locally.
const IDLE_SECONDS: float = 3.0

var _color: Color
var _target: Vector3
var _holding: bool = false
var _idle: float = IDLE_SECONDS
var _opacity: float = 0.0

@onready var _ring: MeshInstance3D = %Ring
@onready var _dot: MeshInstance3D = %Dot
@onready var _nickname: Label3D = %Nickname


func configure(nickname: String, color: Color) -> void:
	_nickname.text = nickname
	_color = color
	hide()
	set_process(false)


func aim_at(point: Vector2, holding: bool) -> void:
	_target = Vector3(point.x, 0.047, point.y)
	if not visible:
		position = _target
		show()
		set_process(true)
	_holding = holding
	_idle = 0.0


func expire() -> void:
	_idle = IDLE_SECONDS
	_holding = false


func _process(delta: float) -> void:
	_idle += delta
	position = position.lerp(_target, 1.0 - exp(-17.0 * delta))
	var fade_target: float = 1.0 if _idle < IDLE_SECONDS else 0.0
	_opacity = move_toward(_opacity, fade_target, delta * 4.0)
	var grip: float = 0.72 if _holding else 1.0
	_ring.scale = _ring.scale.lerp(Vector3(grip, 1.0, grip), 1.0 - exp(-18.0 * delta))
	var ring_material: StandardMaterial3D = _ring.material_override
	var dot_material: StandardMaterial3D = _dot.material_override
	ring_material.albedo_color = Color(_color, _opacity * (0.89 if _holding else 0.61))
	dot_material.albedo_color = Color(_color.lightened(0.28), _opacity)
	ring_material.emission = _color * 0.36
	dot_material.emission = _color * 0.43
	_nickname.modulate = Color(_color.lightened(0.45), _opacity)
	_nickname.outline_modulate = Color(0.025, 0.035, 0.03, _opacity * 0.87)
	if _opacity == 0.0 and fade_target == 0.0:
		hide()
		set_process(false)
