class_name RingCardTable
extends "res://scripts/rules_table.gd"
## Model-neutral open-table presenter built on the original octagonal template.
## All eight hands remain physical cards on the felt, including the human hand.
## Hidden records are stripped before a texture provider or Card3D can see them.
signal navigation_changed

const RING_DECK_ORIGIN := Vector3(-4.8, 0, 0)

var bottom_hud_margin := 185.0 # Host-configurable unobstructed top-view band.
var center_label: Label3D
var _seat_captions: Dictionary = {}

func build_world() -> void:
	player_pitch = deg_to_rad(-54.0)
	super.build_world()
	for seat in seats: seat.camera.fov = 80
	# Move the inherited shoe outline, label, and physical card stack together.
	var original_outline := get_child(get_child_count() - 1) as Node3D
	if original_outline != null: original_outline.position += RING_DECK_ORIGIN - DECK_ORIGIN
	deck_count_label.position = RING_DECK_ORIGIN + Vector3(0, 1.3, 0)
	for child in get_children():
		if child is Label3D and child.text == "D E C K":
			child.position += RING_DECK_ORIGIN - DECK_ORIGIN
	center_label = Label3D.new()
	center_label.name = "CenterLabel"
	center_label.font = font
	center_label.font_size = 46
	center_label.pixel_size = 0.014
	center_label.outline_size = 5
	center_label.modulate = Color("f1d999")
	center_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	center_label.position = Vector3(0, 0.65, -2.0)
	center_label.text = "中央牌区"
	add_child(center_label)
	for seat in seats:
		seat.label.font_size = 34
		seat.label.pixel_size = 0.014
		seat.label.position.y = 0.65
	_update_seat_label_visibility()

## Every card in every zone must have a unique stable id. Invalid snapshots are
## rejected atomically by RulesTable. private_hidden + peek is a local viewing
## choice, not a game rule. hidden always wins and never reveals a face.
func present_ring(player_ids: Array, hands: Array, center_cards: Array, deck_cards: Array, texture_provider: Callable, animated := true) -> bool:
	var old_faces: Dictionary = {}
	for id in _card_nodes:
		old_faces[id] = _card_nodes[id].face_up
	var safe_hands: Array = []
	for cards in hands:
		if not cards is Array: return false
		safe_hands.append(_safe_records(cards))
	if not super.apply_state(player_ids, safe_hands, _safe_records(deck_cards, true), _safe_records(center_cards), texture_provider, animated):
		return false
	for id in _card_nodes:
		var card: Card3D = _card_nodes[id]
		if animated and old_faces.has(id) and old_faces[id] != card.face_up and not flights.has(card):
			var target := card.face_up
			card.set_face_up(old_faces[id], false)
			card.set_face_up(target, true)
	for player_index in _seat_captions:
		set_seat_label(player_index, _seat_captions[player_index])
	return true

func _safe_records(cards: Array, force_hidden := false) -> Array:
	var result: Array = []
	for value in cards:
		if value is Dictionary and (force_hidden or bool(value.get("hidden", false))):
			var safe: Dictionary = {"hidden": true, "face_up": false}
			if value.has("id"): safe.id = value.id
			if value.has("back"): safe.back = value.back
			result.append(safe)
		else: result.append(value)
	return result

func is_animating() -> bool:
	if not flights.is_empty(): return true
	for card in _card_nodes.values():
		if is_instance_valid(card._flip_tween) and card._flip_tween.is_running(): return true
	return false

func set_seat_label(player_index: int, caption: String) -> void:
	_seat_captions[player_index] = caption
	if player_index < 0 or player_index >= _model_player_ids.size(): return
	var index := seat_for_player(String(_model_player_ids[player_index])) - 1
	if index >= 0:
		seats[index].label.text = caption
		seats[index].label.visible = third_person or top_down or index not in [0, 1, 7]

func _presentation_config(model: Dictionary) -> Dictionary:
	var safe := model.duplicate(true)
	if bool(model.get("hidden", false)):
		safe = {"id": model.id, "hidden": true, "face_up": false}
		if model.has("back"): safe.back = model.back
	var config := super._presentation_config(safe)
	if bool(safe.get("hidden", false)):
		config.erase("title")
		config.erase("rank")
		config.erase("suit")
		config["face"] = null
		config["face_up"] = false
	config["face_hidden"] = bool(safe.get("hidden", false))
	return config

func _face_is_public(card: Card3D) -> bool:
	return not bool(card.data.get("hidden", false)) and (not bool(card.data.get("private_hidden", false)) or bool(card.data.get("peek", false)))

func refresh_viewer_faces() -> void:
	for seat in seats:
		for card in seat.hand:
			card.set_viewer_masked(false)
			card.set_face_hidden(bool(card.data.get("hidden", false)))
			card.set_face_up(_face_is_public(card), false)
	for card in played:
		_set_card_visible(card, true)
		card.set_viewer_masked(false)
		card.set_face_hidden(bool(card.data.get("hidden", false)))
		card.set_face_up(_face_is_public(card), false)

func _ring_transform(seat: Dictionary, index: int) -> Transform3D:
	var count: int = seat.hand.size()
	var yaw: float = seat.yaw
	# A compact, nonoverlapping row grows to two rows for unusually large hands.
	var columns := mini(5, count)
	var row := index / 5
	var row_count := mini(5, count - row * 5)
	var card_scale := minf(1.0, 4.7 / maxf(1.0, columns * 1.78))
	var offset := Vector3((index % 5 - (row_count - 1) / 2.0) * 1.78 * card_scale, 0.16, -row * 2.45 * card_scale)
	var basis := Basis(Vector3.UP, yaw)
	var origin := Vector3(sin(yaw) * 8.0, 0, cos(yaw) * 8.0) + basis * offset
	return Transform3D(basis.scaled(Vector3.ONE * card_scale), origin)

func _center_transform(index: int) -> Transform3D:
	var count := played.size()
	var card_scale := minf(1.2, 7.0 / maxf(1.0, count * 1.85))
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * card_scale), Vector3((index - (count - 1) / 2.0) * 1.85 * card_scale, 0.19, 0))

func layout_cards(animated := true) -> void:
	refresh_viewer_faces()
	for seat in seats:
		for i in seat.hand.size():
			var card: Card3D = seat.hand[i]
			if flights.has(card): continue
			_place_table_card(card, _ring_transform(seat, i), animated)
	for i in played.size():
		if not flights.has(played[i]): _place_table_card(played[i], _center_transform(i), animated)

func _place_table_card(card: Card3D, pose: Transform3D, animated: bool) -> void:
	place_in_world(card, self)
	card.scale = pose.basis.get_scale()
	card.move_to(pose.origin, pose.basis.get_euler().y, animated)
	card.hover_offset = Vector3(0, 0.15, 0)
	card.hover_scale = 1.08

func flight_target(card: Card3D) -> Transform3D:
	var index := played.find(card)
	if index >= 0: return global_transform * _center_transform(index)
	for seat in seats:
		index = seat.hand.find(card)
		if index >= 0: return global_transform * _ring_transform(seat, index)
	return card.global_transform

func update_hand_pose(_delta: float) -> void:
	# Retain the original look rigs but never attach tabletop cards to them.
	auto_collapsed = false

func pick(screen: Vector2) -> Card3D:
	if menu_open or not is_instance_valid(camera): return null
	if not get_viewport().get_visible_rect().has_point(screen): return null
	return ray_target(screen)

func update_deck() -> void:
	super.update_deck()
	for config in deck:
		var card: Card3D = _card_nodes.get(config.id)
		if card != null: card.position += RING_DECK_ORIGIN - DECK_ORIGIN

func deck_top_position() -> Vector3:
	return super.deck_top_position() + RING_DECK_ORIGIN - DECK_ORIGIN

func fit_top_camera() -> void:
	if not is_instance_valid(top_camera): return
	var viewport_size := get_viewport().get_visible_rect().size
	# Fit the complete ring into the unobstructed band, reserving the external
	# host's top header and configurable bottom action/status panel, plus room
	# for billboard labels. Measure projection to respect Camera3D aspect mode.
	var safe_top := 120.0
	var safe_bottom := maxf(safe_top + 80.0, viewport_size.y - bottom_hud_margin)
	var safe_width := maxf(100.0, viewport_size.x - 100.0)
	var pixels_per_unit := minf(safe_width / 28.0, (safe_bottom - safe_top) / 26.0)
	top_camera.position.z = 0
	top_camera.size = 30.0
	var projected_origin := top_camera.unproject_position(Vector3.ZERO)
	var projected_unit := top_camera.unproject_position(Vector3.RIGHT)
	var current_pixels := absf(projected_unit.x - projected_origin.x)
	top_camera.size *= current_pixels / maxf(1.0, pixels_per_unit)
	var target_center := (safe_top + safe_bottom) * 0.5
	top_camera.position.z = (viewport_size.y * 0.5 - target_center) / maxf(1.0, pixels_per_unit)

func reset_view() -> void:
	super.reset_view()
	player_pitch = deg_to_rad(-54.0)
	apply_player_look(Vector2.ZERO)

func apply_observer_look(delta: Vector2) -> void:
	observer_yaw -= delta.x * 0.004
	observer_pitch = clampf(observer_pitch + delta.y * 0.004, -0.35, 0.45)
	var offset := Vector3(0, 25, -20).rotated(Vector3.RIGHT, observer_pitch).rotated(Vector3.UP, observer_yaw)
	# Frame the actual table, with a slight upward screen bias for the footer.
	observer_camera.look_at_from_position(Vector3(0, -2.0, 0) + offset, Vector3(0, -2.0, 0))

func _update_seat_label_visibility() -> void:
	for index in seats.size():
		var seat: Dictionary = seats[index]
		seat.label.visible = third_person or top_down or index not in [0, 1, 7]
		# The near-end observer label needs extra room above a 160px footer.
		# Move only its label inward; no hand/card or camera pose is changed.
		var radius := 9.8 if third_person and index == 4 else 10.8
		seat.label.position = Vector3(sin(seat.yaw) * radius, 0.65, cos(seat.yaw) * radius)

func set_view(third: bool) -> void:
	navigation_changed.emit()
	super.set_view(third)
	_update_seat_label_visibility()

func set_top_down(value: bool) -> void:
	navigation_changed.emit()
	super.set_top_down(value)
	_update_seat_label_visibility()

func set_hand_stowed(value: bool) -> void:
	navigation_changed.emit()
	super.set_hand_stowed(value)
	if is_instance_valid(stow_button): stow_button.text = "结束自由转头 Tab" if free_look else "自由转头 Tab"

func inspection_snapshot(card: Card3D) -> Dictionary:
	if not is_instance_valid(card) or not card.visible: return {}
	if not _face_is_public(card) or card.zone == &"deck":
		return {"face_up": false, "description": "牌背"}
	return card.public_snapshot()

func inspection_group(card: Card3D) -> Array[Card3D]:
	var result: Array[Card3D] = []
	if not is_instance_valid(card) or not card.visible or card.zone == &"deck": return result
	# Inspect precisely the hovered card; never disclose neighbors accidentally.
	result.append(card)
	return result

func update_inspector(delta: float) -> void:
	if not is_instance_valid(inspect_panel): return
	if free_look or looking or menu_open:
		hide_inspector()
		return
	var target: Card3D = hovered if is_instance_valid(hovered) and hovered.zone != &"deck" else null
	if target != inspect_target:
		hide_inspector()
		inspect_target = target
	if target == null: return
	inspect_elapsed += delta
	if inspect_elapsed < 0.45: return
	var snapshot := inspection_snapshot(target)
	var next_key := str(target.get_instance_id()) + str(snapshot)
	if next_key == inspect_key and inspect_panel.visible: return
	inspect_key = next_key
	for child in inspect_grid.get_children():
		inspect_grid.remove_child(child)
		child.queue_free()
	inspect_grid.columns = 1
	inspect_scroll.custom_minimum_size = Vector2(170, 220)
	inspect_title.text = snapshot.get("description", "未知卡牌")
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(150, 211)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.texture = target.face_texture if snapshot.has("title") else (Card3D.UNKNOWN_FACE if snapshot.get("face_up", false) else target.back_texture)
	inspect_grid.add_child(preview)
	inspect_panel.size = Vector2.ZERO
	inspect_panel.visible = true
