extends "res://games/minigame/GP_cards/cards/card_entity.gd"

## The same rounded paper slab grows sublinearly with the size of the pile.
var count: int = 0
var _shuffle: Tween
@onready var _badge: Label3D = %Count


func apply_deck(row: Dictionary, front: Texture2D, back: Texture2D, fresh: bool) -> void:
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
	if _shuffle != null:
		_shuffle.kill()
	_visual.position = Vector3.ZERO
	_visual.rotation.z = 0.0
	_shuffle = create_tween()
	_shuffle.tween_property(_visual, "position", Vector3(0.19, 0.15, 0.0), 0.065)
	_shuffle.parallel().tween_property(_visual, "rotation:z", 0.14, 0.065)
	_shuffle.tween_property(_visual, "position", Vector3(-0.18, 0.24, 0.03), 0.09)
	_shuffle.parallel().tween_property(_visual, "rotation:z", -0.15, 0.09)
	_shuffle.tween_property(_visual, "position", Vector3.ZERO, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_shuffle.parallel().tween_property(_visual, "rotation:z", 0.0, 0.14)
