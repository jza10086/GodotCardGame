class_name RulesTable
extends "res://scripts/table_demo.gd"
## Rules-neutral presenter. The caller owns all card state and legal-move decisions.
## Every ID has one persistent Card3D, including cards currently hidden in piles.
## Player index zero is the sole human viewer; cameras never change ownership.
signal card_requested(card_id: Variant)
signal draw_requested

var presentation_overlay: Control
var _card_nodes: Dictionary = {}
var _presented_configs: Dictionary = {}
var _card_locations: Dictionary = {}
var _model_player_ids: Array = []
var _model_discard: Array = []
var _provider: Callable
var interactions_blocked := false

func _ready() -> void:
	font = load("res://assets/ui_font.ttf")
	build_world()
	build_ui()
	update_hand_pose(1.0)

func build_ui() -> void:
	# Keep native references alive for inherited navigation methods. The original
	# demonstration controls are never exposed to a rules-driven game.
	super.build_ui()
	ui.hide()
	presentation_overlay = Control.new()
	presentation_overlay.name = "PresentationOverlay"
	presentation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	presentation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presentation_overlay.theme = ui.theme
	ui.get_parent().add_child(presentation_overlay)
	crosshair.reparent(presentation_overlay, false)
	inspect_panel.reparent(presentation_overlay, false)

## hands is an array in player_ids order. Pile tops are the last array entries.
## Each card needs a unique, stable id. face/back can be Texture2D or paths.
## texture_provider.call(card_dictionary) may return a Texture2D (face), or a
## dictionary with face/back textures. Other model fields are passed through.
## Invalid snapshots leave the currently presented state entirely unchanged.
func apply_state(player_ids: Array, hands: Array, deck_cards: Array, discard_cards: Array, texture_provider: Callable, animated := true) -> bool:
	var allocation: Dictionary = ALLOCATION.allocate(player_ids)
	if allocation.is_empty() or hands.size() != player_ids.size(): return false
	var all_cards: Array = []
	for cards in hands:
		if not cards is Array: return false
		all_cards.append_array(cards)
	all_cards.append_array(deck_cards)
	all_cards.append_array(discard_cards)
	var desired: Dictionary = {}
	for value in all_cards:
		if not value is Dictionary or not value.has("id"): return false
		var id: Variant = value.id
		if not (id is String or id is StringName or id is int) or desired.has(id): return false
		desired[id] = value
	if seats.is_empty(): return false
	var starts: Dictionary = {}
	for id in _card_nodes:
		var old_card: Card3D = _card_nodes[id]
		if is_instance_valid(old_card): starts[id] = old_card.global_transform
	var old_locations := _card_locations.duplicate()
	flights.clear()
	clear_hover()
	select(null)
	hide_inspector()
	pressed = null
	dragged = null
	_pending_play.clear()
	_model_player_ids = player_ids.duplicate()
	_round_players = player_ids.duplicate()
	_player_seats = allocation
	_model_discard = discard_cards.duplicate(true)
	_provider = texture_provider
	for seat in seats:
		seat.hand.clear()
		seat.player_id = player_at_seat(seat.seat_id)
		seat.label.text = "%d · %s" % [seat.seat_id, seat.player_id if not seat.player_id.is_empty() else "空位"]
		seat.label.modulate = Color("d4e7cf") if not seat.player_id.is_empty() else Color("54736f")
	played.clear()
	deck_visual.clear()
	deck.assign(deck_cards)
	_card_locations.clear()
	for id in _card_nodes.keys():
		if desired.has(id): continue
		var removed: Card3D = _card_nodes[id]
		if is_instance_valid(removed):
			removed.visible = false
			removed.area.collision_layer = 0
			removed.queue_free()
		_card_nodes.erase(id)
		_presented_configs.erase(id)
	for id in desired:
		var config := _presentation_config(desired[id])
		if not _card_nodes.has(id):
			var created: Card3D = CARD.instantiate()
			created.configure(config)
			add_child(created)
			_card_nodes[id] = created
			_presented_configs[id] = config.duplicate(true)
		else:
			var existing: Card3D = _card_nodes[id]
			if config != _presented_configs.get(id, {}):
				existing.configure(config)
				_presented_configs[id] = config.duplicate(true)
	for player_index in player_ids.size():
		var seat_index := int(allocation[String(player_ids[player_index])]) - 1
		for config in hands[player_index]:
			var card: Card3D = _card_nodes[config.id]
			seats[seat_index].hand.append(card)
			card.set_meta("seat_id", seats[seat_index].id)
			card.set_meta("player_index", player_index)
			card.set_zone(&"hand")
			card.set_face_up(true, false)
			card.set_face_hidden(false)
			_set_card_visible(card, true)
			_card_locations[config.id] = "hand:%s" % String(player_ids[player_index])
	for config in deck_cards:
		var card: Card3D = _card_nodes[config.id]
		card.set_meta("seat_id", "")
		card.set_meta("player_index", -1)
		card.set_zone(&"deck")
		card.set_viewer_masked(true)
		card.set_face_up(false, false)
		_set_card_visible(card, false)
		_card_locations[config.id] = "deck"
	for i in discard_cards.size():
		var config: Dictionary = discard_cards[i]
		var card: Card3D = _card_nodes[config.id]
		played.append(card)
		card.set_meta("seat_id", "")
		card.set_meta("player_index", -1)
		card.set_zone(&"play")
		card.set_face_up(true, false)
		card.set_face_hidden(false)
		_set_card_visible(card, i == discard_cards.size() - 1)
		_card_locations[config.id] = "play"
	# Seat zero is fixed even when the observer/top camera is active.
	active_seat = 0
	player_rig = seats[0].rig
	first_camera = seats[0].camera
	hand_world = seats[0].anchor
	hand = seats[0].hand
	update_deck()
	refresh_viewer_faces()
	update_hand_pose(0.0)
	if animated:
		for id in desired:
			var card: Card3D = _card_nodes[id]
			var destination: String = _card_locations[id]
			var source: String = old_locations.get(id, "")
			if not starts.has(id) or source == destination or not card.visible: continue
			if destination == "deck": continue
			# Keep the same physical node. Its parent changes without a teleport.
			if card.get_parent() != self: card.reparent(self, true)
			var start: Transform3D = starts[id]
			if source == "deck": start.origin = deck_top_position()
			start_flight(card, start, "draw" if source == "deck" else "play", 0.70)
	layout_cards(animated)
	update_ui()
	return true

func _presentation_config(model: Dictionary) -> Dictionary:
	var result := model.duplicate(true)
	if _provider.is_valid():
		var supplied: Variant = _provider.call(model)
		if supplied is Texture2D: result["face"] = supplied
		elif supplied is Dictionary:
			for key in ["face", "back"]:
				if supplied.has(key): result[key] = supplied[key]
	for key in ["face", "back"]:
		if result.get(key) is String: result[key] = load(result[key])
	if not result.get("back") is Texture2D: result["back"] = load("res://assets/back.svg")
	if not result.get("face") is Texture2D: result["face"] = null
	return result

func _set_card_visible(card: Card3D, value: bool) -> void:
	card.visible = value
	card.area.collision_layer = 1 if value else 0

func card_node(id: Variant) -> Card3D:
	return _card_nodes.get(id, null)

func player_hand(player_index: int) -> Array[Card3D]:
	var result: Array[Card3D] = []
	if player_index < 0 or player_index >= _model_player_ids.size(): return result
	var physical_seat := seat_for_player(String(_model_player_ids[player_index])) - 1
	result.assign(seats[physical_seat].hand)
	return result

func discard_count() -> int:
	return _model_discard.size()

func set_interaction_blocked(value: bool) -> void:
	# Rules can prohibit plays during another player's turn without freezing
	# camera controls or safe inspection. The host owns menu_open separately.
	if interactions_blocked == value: return
	interactions_blocked = value

func update_ui() -> void:
	# Game subclasses own the external HUD. No template hand/pile caps apply.
	pass

func update_deck() -> void:
	deck_visual.clear()
	for i in deck.size():
		var card: Card3D = _card_nodes.get(deck[i].id, null)
		if card == null: continue
		place_in_world(card, self)
		var visible_index := i - maxi(0, deck.size() - 12)
		card.position = DECK_ORIGIN + Vector3(0.022 * maxi(0, visible_index), 0.05 + 0.055 * maxi(0, visible_index), 0)
		_set_card_visible(card, visible_index >= 0)
		if visible_index >= 0: deck_visual.append(card)
	deck_count_label.text = "牌堆 · %02d" % deck.size()

func _hand_transform(cards: Array, index: int) -> Transform3D:
	var center := float(index) - (cards.size() - 1) / 2.0
	var step := minf(1.22, 6.8 / maxf(1, cards.size() - 1))
	var angle_step := minf(0.025, 0.32 / maxf(1, cards.size() - 1))
	var lift := minf(0.02, 0.30 / maxf(1, cards.size() - 1))
	return Transform3D(Basis(Vector3.UP, -center * angle_step).scaled(Vector3.ONE * 0.68), Vector3(center * step, lift * index, absf(center) * angle_step))

func layout_cards(animated := true) -> void:
	refresh_viewer_faces()
	for seat in seats:
		var cards: Array = seat.hand
		for i in cards.size():
			var card: Card3D = cards[i]
			if flights.has(card): continue
			place_in_world(card, seat.anchor)
			var pose := _hand_transform(cards, i)
			card.move_to(pose.origin, pose.basis.get_euler().y, animated)
	for i in played.size():
		var card: Card3D = played[i]
		if flights.has(card): continue
		place_in_world(card, self)
		card.move_to(Vector3(0, 0.16, 0), 0.0, animated)

func flight_target(card: Card3D) -> Transform3D:
	if card in played: return Transform3D(Basis.IDENTITY, Vector3(0, 0.16, 0))
	for seat in seats:
		var cards: Array = seat.hand
		var index := cards.find(card)
		if index >= 0: return seat.anchor.global_transform * _hand_transform(cards, index)
	return card.global_transform

func advance_flights(delta: float) -> void:
	var had_flights := not flights.is_empty()
	super.advance_flights(delta)
	if had_flights and flights.is_empty(): layout_cards(false)

func can_control(card: Card3D) -> bool:
	return is_instance_valid(card) and card in hand and card.visible

func set_active_seat(index: int) -> bool:
	# Navigation never grants a new player identity.
	return index == 0

func select(card: Card3D, _additive := false) -> void:
	super.select(card, false)

func pick(screen: Vector2) -> Card3D:
	if menu_open or not is_instance_valid(camera): return null
	if not get_viewport().get_visible_rect().has_point(screen): return null
	if not third_person and not top_down and not hand_stowed:
		if is_instance_valid(hovered) and hovered in hand and not flights.has(hovered):
			if hand_card_rect(hovered).has_point(screen) or hand_card_rect(hovered, true).has_point(screen): return hovered
		for i in range(hand.size() - 1, -1, -1):
			if not flights.has(hand[i]) and hand_card_rect(hand[i]).has_point(screen): return hand[i]
	return ray_target(screen)

func ray_target(screen: Vector2) -> Card3D:
	var card := super.ray_target(screen)
	return card if is_instance_valid(card) and card.visible else null

func inspection_snapshot(card: Card3D) -> Dictionary:
	if not is_instance_valid(card): return {}
	if card.viewer_masked: return {"face_up": false, "description": "对方手牌"}
	if card in played and card.visible: return card.public_snapshot()
	return super.inspection_snapshot(card)

func inspection_group(card: Card3D) -> Array[Card3D]:
	var result: Array[Card3D] = []
	if is_instance_valid(card) and card.visible and card in played: result.append(card)
	return result

func update_inspector(delta: float) -> void:
	# Generated textures share an empty resource_path, so never reuse a preview
	# made for another identity. The base class still owns preview presentation.
	_preview_textures.clear()
	super.update_inspector(delta)

func _request_card(card: Card3D) -> void:
	if menu_open or interactions_blocked or not is_instance_valid(card) or flights.has(card): return
	if card.zone == &"deck":
		draw_requested.emit()
	elif can_control(card):
		select(card)
		card_requested.emit(card.data.get("id"))

func _input(event: InputEvent) -> void:
	if menu_open: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			toggle_hand_stowed()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_T:
			toggle_top_down()
			get_viewport().set_input_as_handled()
			return
	if free_look:
		if event is InputEventMouseMotion:
			apply_player_look(event.relative)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				var target := ray_target(get_viewport().get_visible_rect().size / 2.0)
				world_interaction_requested.emit(target, can_control(target))
				_request_card(target)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if top_down: return
		looking = event.pressed
		if looking: clear_hover()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and looking:
		if third_person: apply_observer_look(event.relative)
		else: apply_player_look(event.relative)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if menu_open: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_request_card(pick(event.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_request_card(selected if is_instance_valid(selected) else hovered)
			KEY_D: draw_card()
			KEY_V: toggle_view()
			KEY_R: reset_view()
			_: return
		get_viewport().set_input_as_handled()

# Mutation APIs from the freeform demo are deliberately unavailable. Only
# apply_state can change model zones; the convenience actions emit requests.
func draw_card(_animated := true) -> Card3D:
	if not menu_open and not interactions_blocked: draw_requested.emit()
	return null

func play_selected() -> bool:
	if menu_open or interactions_blocked or not can_control(selected): return false
	_request_card(selected)
	return true

func can_play_cards(group: Array[Card3D]) -> bool:
	return not menu_open and not interactions_blocked and group.size() == 1 and can_control(group[0]) and not flights.has(group[0])

func play_cards(group: Array[Card3D]) -> bool:
	if not can_play_cards(group): return false
	_request_card(group[0])
	return true

func move_card(_card: Card3D, _destination: StringName) -> bool: return false
func transfer_to_seat(_card: Card3D, _index: int) -> bool: return false
func flip_selected() -> void: pass
func toggle_hidden() -> void: pass
func return_selected() -> void: pass
func reset() -> void: pass
func start_pending_round() -> bool: return false
func start_round(_player_ids: Array) -> bool: return false
func showcase() -> void: pass
func open_debug_menu() -> void: pass
func close_debug_menu() -> void: pass
func toggle_debug_menu() -> void: pass
