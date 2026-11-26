extends "res://games/minigame/GP_cards/cards/card_entity.gd"

## The same rounded paper slab grows sublinearly with the size of the pile.
var count: int = 0
var _shuffle: Tween
@onready var _badge: Label3D = %Count
@onready var _cut_packet: MeshInstance3D = %CutPacket


func _ready() -> void:
	super._ready()
	_cut_packet.mesh = _slab.mesh
	_cut_packet.set_surface_override_material(0, _back)
	_cut_packet.set_surface_override_material(1, _back)
	_cut_packet.set_surface_override_material(2, _edge)


func apply_deck(row: Dictionary, front: Texture2D, back: Texture2D, fresh: bool) -> void:
	if row.face_up != _face_up:
		_reset_shuffle()
	count = row.count
	_thickness = PAPER + 0.055 * sqrt(float(count - 1))
	_edge.set_shader_parameter("layers", minf(16.0, float(count)))
	_badge.text = str(count)
	_badge.position.y = _thickness + 0.52
	apply_card(row, front, back, fresh)


func set_highlight(active: bool, merge: bool = false) -> void:
	super.set_highlight(active, merge)
	_badge.visible = active


func play_shuffle() -> void:
	_reset_shuffle()
	_cut_packet.show()
	_pose_shuffle(0.0)
	_shuffle = create_tween().set_trans(Tween.TRANS_SINE)
	_shuffle.tween_method(_pose_shuffle, 0.0, 1.0, 0.38)
	_shuffle.tween_callback(_reset_shuffle)


## Split into two packets, cross them with one lifted, and bring them back together.
func _pose_shuffle(progress: float) -> void:
	var envelope: float = sin(PI * progress)
	var split: float = 1.05 * envelope * cos(PI * progress)
	var side: float = 1.0 if _face_up else -1.0
	_animation_lift = 0.16 * envelope
	_slab.scale.y = _height * 0.5 / PAPER
	_cut_packet.scale.y = _slab.scale.y
	_slab.position = Vector3(split, side * (_height * 0.25 + 0.24 * envelope), 0.07 * envelope)
	_cut_packet.position = Vector3(-split, -side * _height * 0.25, 0.0)
	_slab.rotation.y = split * 0.36
	_cut_packet.rotation.y = -split * 0.30


func _reset_shuffle() -> void:
	if _shuffle != null:
		_shuffle.kill()
		_shuffle = null
	_animation_lift = 0.0
	_slab.position = Vector3.ZERO
	_slab.rotation.y = 0.0
	_slab.scale.y = _height / PAPER
	_cut_packet.hide()


func fly_to_merge(destination: Vector3) -> void:
	_reset_shuffle()
	super.fly_to_merge(destination)
