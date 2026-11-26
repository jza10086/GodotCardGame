extends Node3D

## Fixed camera-space depth keeps the hand in the same world as the table.
const Card: GDScript = preload("res://games/minigame/GP_cards/cards/card_entity.gd")
const Catalog: GDScript = preload("res://games/minigame/GP_cards/cards/deck_catalog.gd")
const CARD_SCENE: PackedScene = preload("res://games/minigame/GP_cards/cards/card_entity.tscn")
const DEPTH: float = 2.2
const ZONE_HEIGHT: float = 190.0
const DESIGN_HEIGHT: float = 1080.0

var _cards: Dictionary[int, Card] = {}
var _order: Array[int] = []
var _flights: Dictionary[int, Vector3] = {}
var _hover: int = 0
var _drag_uid: int = 0
var _drag_x: float
@onready var _camera: Camera3D = get_parent()


func apply_hand(rows: Array, catalog: Catalog, origins: Dictionary[int, Vector3],
		deal_origin: Variant = null) -> void:
	_order.clear()
	for row: Dictionary in rows:
		var uid: int = row.uid
		_order.append(uid)
		if _cards.has(uid):
			continue
		var card: Card = CARD_SCENE.instantiate()
		add_child(card)
		card.set_floating()
		card.set_card_sides(catalog.get_face_texture(row.deck_type, row.face_id),
			catalog.get_back_texture(row.deck_type), true, true)
		_cards[uid] = card
		var origin: Variant = origins.get(uid, deal_origin)
		_place_new_card(uid, origin)
	for uid: int in _cards.keys():
		if uid not in _order:
			_cards[uid].hide_face()
			_cards[uid].hide()
			_cards[uid].queue_free()
			_cards.erase(uid)
			_flights.erase(uid)
	if not _cards.has(_hover):
		_hover = 0


func _place_new_card(uid: int, origin: Variant) -> void:
	var card: Card = _cards[uid]
	var slot: Vector2 = _slot(_order.size() - 1)
	var start: Vector2 = slot + Vector2(0.0, 110.0) * _ui_scale()
	if origin != null and not _camera.is_position_behind(origin):
		start = _camera.unproject_position(origin)
	card.position = to_local(_camera.project_position(start, DEPTH))
	card.quaternion = Quaternion(Vector3.RIGHT, PI * 0.5)
	card.scale = Vector3.ONE * _card_scale() * 0.52
	_flights[uid] = Vector3(start.x, start.y, 0.0)


func is_drop_zone(pointer: Vector2, hand_press_y: float = INF) -> bool:
	var rect: Rect2 = get_viewport().get_visible_rect()
	var ui_scale: float = _ui_scale()
	var camera_button_width: float = 205.0 * ui_scale
	# A raised card can be picked above the usual entry line. Allow horizontal
	# reordering from that point until the pointer actually moves upward.
	var top: float = minf(rect.end.y - ZONE_HEIGHT * ui_scale, hand_press_y - 14.0 * ui_scale)
	return rect.has_point(pointer) and pointer.y >= top \
		and pointer.x < rect.end.x - camera_button_width


func card_at(pointer: Vector2) -> int:
	if _cards.has(_hover) and not _flights.has(_hover) and _hit_card(_cards[_hover], pointer):
		return _hover
	for i: int in range(_order.size() - 1, -1, -1):
		var uid: int = _order[i]
		if not _flights.has(uid) and _hit_card(_cards[uid], pointer):
			return uid
	return 0


func _hit_card(card: Card, pointer: Vector2) -> bool:
	var from: Vector3 = card.to_local(_camera.project_ray_origin(pointer))
	var to: Vector3 = card.to_local(_camera.project_ray_origin(pointer) + _camera.project_ray_normal(pointer))
	var direction: Vector3 = to - from
	if is_zero_approx(direction.y):
		return false
	var distance: float = -from.y / direction.y
	var hit: Vector3 = from + direction * distance
	return distance > 0.0 and absf(hit.x) <= Card.WIDTH * 0.5 and absf(hit.z) <= Card.LENGTH * 0.5


func insert_index(pointer: Vector2, excluding: int = 0) -> int:
	var index: int = 0
	for i: int in _order.size():
		if _order[i] == excluding:
			continue
		if pointer.x < _slot(i).x:
			break
		index += 1
	return index


func index_of(uid: int) -> int:
	return _order.find(uid)


func set_hover(uid: int) -> void:
	_hover = uid


func set_drag_preview(uid: int, pointer: Vector2) -> void:
	_drag_uid = uid
	_drag_x = pointer.x


func face_at(uid: int) -> Texture2D:
	return _cards[uid].face_texture if _cards.has(uid) else null


func _process(delta: float) -> void:
	var weight: float = 1.0 - exp(-19.0 * delta)
	var ui_scale: float = _ui_scale()
	var scale_factor: float = _card_scale()
	for i: int in _order.size():
		var uid: int = _order[i]
		var card: Card = _cards[uid]
		var slot: Vector2 = _slot(i)
		var raised: bool = uid == _hover or uid == _drag_uid
		var depth: float = DEPTH - float(i) * 0.0012
		if raised:
			depth -= 0.11
			slot.y -= 53.0 * ui_scale
		if uid == _drag_uid:
			slot.x = _drag_x
		var fan: float = clampf((_slot(i).x - _center_x()) / (560.0 * ui_scale), -1.0, 1.0)
		var angle: float = 0.0 if raised else -fan * 0.175
		var target: Quaternion = Quaternion(Vector3.BACK, angle) * Quaternion(Vector3.RIGHT, PI * 0.5)
		if _flights.has(uid):
			var flight: Vector3 = _flights[uid]
			flight.z = minf(1.0, flight.z + delta * 3.3)
			var ease_out: float = 1.0 - pow(1.0 - flight.z, 2.0)
			slot = Vector2(flight.x, flight.y).lerp(slot, ease_out)
			slot.y -= sin(flight.z * PI) * 94.0 * ui_scale
			_flights[uid] = flight
			if flight.z >= 1.0:
				_flights.erase(uid)
		var target_position: Vector3 = to_local(_camera.project_position(slot, depth))
		card.position = card.position.lerp(target_position, weight)
		card.quaternion = card.quaternion.slerp(target, weight)
		var size: float = scale_factor * (1.18 if raised else 1.0) * depth / DEPTH
		card.scale = card.scale.lerp(Vector3.ONE * size, weight)


func _slot(index: int) -> Vector2:
	var rect: Rect2 = get_viewport().get_visible_rect()
	var ui_scale: float = _ui_scale()
	var span: float = minf(1090.0 * ui_scale, rect.size.x - 410.0 * ui_scale)
	var step: float = minf(88.0 * ui_scale, span / maxf(1.0, float(_order.size() - 1)))
	var offset: float = (float(index) - float(_order.size() - 1) * 0.5) * step
	var bow: float = pow(offset / (560.0 * ui_scale), 2.0) * 19.0 * ui_scale
	return Vector2(_center_x() + offset, rect.end.y - 125.0 * ui_scale + bow)


func _center_x() -> float:
	return get_viewport().get_visible_rect().get_center().x


func _ui_scale() -> float:
	return get_viewport().get_visible_rect().size.y / DESIGN_HEIGHT


func _card_scale() -> float:
	return 2.0 * DEPTH * tan(deg_to_rad(_camera.fov * 0.5)) * (166.0 / DESIGN_HEIGHT) / Card.LENGTH
