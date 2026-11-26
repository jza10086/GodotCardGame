extends Node3D

## The view consumes projected rows and sends player intents without a reference to host state.
signal action_requested(action: Dictionary)
signal face_preview_changed(texture: Texture2D)
signal cursor_sampled(position: Vector2, holding: bool)
signal drag_sampled(sample: Dictionary)

const CameraRig: GDScript = preload("res://games/minigame/GP_cards/table/table_camera_rig.gd")
const Card: GDScript = preload("res://games/minigame/GP_cards/cards/card_entity.gd")
const Deck: GDScript = preload("res://games/minigame/GP_cards/cards/deck_entity.gd")
const Catalog: GDScript = preload("res://games/minigame/GP_cards/cards/deck_catalog.gd")
const Hand: GDScript = preload("res://games/minigame/GP_cards/cards/floating_hand_3d.gd")
const ContextMenu: GDScript = preload("res://games/minigame/GP_cards/ui/context_menu.gd")
const RemoteCursor: GDScript = preload("res://games/minigame/GP_cards/table/remote_cursor_3d.gd")
const CARD_SCENE: PackedScene = preload("res://games/minigame/GP_cards/cards/card_entity.tscn")
const DECK_SCENE: PackedScene = preload("res://games/minigame/GP_cards/cards/deck_entity.tscn")
const CURSOR_SCENE: PackedScene = preload("res://games/minigame/GP_cards/table/remote_cursor_3d.tscn")
const SEAT_COUNT: int = 8
const TABLE_COLLISION_MASK: int = 1
const PIECE_COLLISION_MASK: int = 2
const HOLD_MSEC: int = 280
const MAX_SEAT_BACKS: int = 12
const NUMBER_KEYS: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]

@export var world: WorldEnvironment
@export var sun: DirectionalLight3D

var _catalog: Catalog = Catalog.new()
var _cards: Dictionary[int, Card] = {}
var _decks: Dictionary[int, Deck] = {}
var _seat_by_player: Dictionary[String, int] = {}
var _seat_hand_counts: Dictionary[String, int] = {}
var _cursors: Dictionary[String, RemoteCursor] = {}
var _colors: Dictionary[String, Color] = {}
var _ahead_drag: Dictionary[String, Dictionary] = {}
var _last_rev: int = -1
var _local_id: String
var _input_context: PartyInput
var _controls_active: bool = false
var _pointer: Vector2
var _last_cursor_point: Vector2
var _has_cursor_point: bool = false
var _press_point: Vector2
var _press_msec: int
var _press_whole: bool = false
var _left_down: bool = false
var _pending_piece: Dictionary = {}
var _hand_drag: int = 0
var _awaiting_hold: bool = false
var _hold_request: Dictionary = {}
var _drop_when_held: bool = false
var _queued_release_at: Vector2
var _cancel_when_held: bool = false
var _awaiting_drop: bool = false
var _held_kind: StringName
var _held_uid: int = 0
var _drag_pos: Vector2
var _alt: bool = false
var _highlighted: Card
var _preview_face: Texture2D
var _seat_back: StringName = &"poker"

@onready var _seats: Node3D = %Seats
@onready var _camera_rig: CameraRig = %CameraRig
@onready var _camera: Camera3D = %Camera3D
@onready var _cards_root: Node3D = %CardsRoot
@onready var _decks_root: Node3D = %DecksRoot
@onready var _cursors_root: Node3D = %CursorsRoot
@onready var _hand: Hand = %FloatingHandAnchor
@onready var _drop_marker: MeshInstance3D = %DropMarker
@onready var _menu: ContextMenu = %ContextMenu


func _ready() -> void:
	assert(world != null and sun != null, "Assign the table's environment and sun.")
	_camera_rig.context_requested.connect(_open_context_menu)
	_menu.action_requested.connect(_context_action)


## Display participants in protocol order and use a neutral angle for spectators.
func seat_players(players: Array[Dictionary], local_player_index: int, input_context: PartyInput) -> void:
	_input_context = input_context
	for seat: Node3D in _seats.get_children():
		seat.hide()
	_seat_by_player.clear()
	_colors.clear()
	_local_id = ""
	var seat_yaw: float = 0.0
	for i: int in players.size():
		var seat_idx: int = int(floor(8.0 * float(i) / float(players.size()) + 0.5)) % SEAT_COUNT
		var seat: Node3D = _seats.get_child(seat_idx)
		var nickname: Label3D = seat.get_node("Nickname")
		var strip: MeshInstance3D = seat.get_node("ColorStrip")
		var material: StandardMaterial3D = strip.material_override
		var color: Color = players[i].color
		nickname.text = players[i].name
		material.albedo_color = color
		material.emission = color
		seat.show()
		_seat_by_player[players[i].player_id] = seat_idx
		_colors[players[i].player_id] = color
		if i == local_player_index:
			_local_id = players[i].player_id
			seat_yaw = seat.rotation.y
	_camera_rig.configure(input_context, seat_yaw)


func update_remote_cursor(player_id: String, point: Vector2, holding: bool) -> void:
	if not _cursors.has(player_id):
		var cursor: RemoteCursor = CURSOR_SCENE.instantiate()
		_cursors_root.add_child(cursor)
		var seat: Node3D = _seats.get_child(_seat_by_player[player_id])
		var nickname: Label3D = seat.get_node("Nickname")
		cursor.configure(nickname.text, _colors[player_id])
		_cursors[player_id] = cursor
	_cursors[player_id].aim_at(point, holding)


func hide_remote_cursor(player_id: String) -> void:
	_ahead_drag.erase(player_id)
	if _cursors.has(player_id):
		_cursors[player_id].expire()


func update_remote_drag(player_id: String, sample: Dictionary) -> void:
	if sample.rev > _last_rev:
		# A motion sample can overtake the reliable lock event on the other channel.
		_ahead_drag[player_id] = sample
		return
	var piece: Card = _piece(sample.kind, sample.uid)
	if piece != null and piece.locked_by == player_id and piece.piece_rev == sample.rev:
		piece.drag_remotely(Vector3(sample.x, sample.y, sample.z), sample.yaw)


func set_controls_active(active: bool) -> void:
	_controls_active = active
	_camera_rig.set_controls_active(active)
	if not active:
		_left_down = false
		_cancel_drag()
		_menu.hide()
		_alt = false
		_clear_feedback()
		for player_id: String in _cursors:
			_cursors[player_id].expire()


func can_use_controls() -> bool:
	return _controls_active and (_input_context == null or not _input_context.input_blocked)


func reset_camera() -> void:
	if can_use_controls():
		_camera_rig.reset_view()


func toggle_overhead() -> void:
	if can_use_controls():
		_camera_rig.toggle_overhead()


func hand_anchor(seat_idx: int) -> Node3D:
	return _seats.get_child(seat_idx).get_node("HandBacksAnchor")


## Return the physics hit on the felt, or an empty dictionary outside its edges.
func pick_table(screen_position: Vector2) -> Dictionary:
	return _raycast(screen_position, TABLE_COLLISION_MASK)


func _raycast(at: Vector2, mask: int) -> Dictionary:
	var origin: Vector3 = _camera.project_ray_origin(at)
	var target: Vector3 = origin + _camera.project_ray_normal(at) * _camera.far
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target, mask)
	return get_world_3d().direct_space_state.intersect_ray(query)


func apply_snapshot(snapshot: Dictionary) -> void:
	_last_rev = snapshot.rev
	_reset_pieces()
	for uid: int in snapshot.table_cards:
		_upsert_piece(TabletopState.CARD, uid, snapshot.table_cards[uid])
	for uid: int in snapshot.table_decks:
		_upsert_piece(TabletopState.DECK, uid, snapshot.table_decks[uid])
	if not snapshot.table_decks.is_empty():
		_seat_back = snapshot.table_decks.values()[0].top_card.deck_type
	var origins: Dictionary[int, Vector3] = {}
	_hand.apply_hand(snapshot.hand, _catalog, origins)
	for player_id: String in snapshot.hand_counts:
		_set_seat_hand_count(player_id, snapshot.hand_counts[player_id])


func apply_event(event: Dictionary, confirms_local_action: bool = true) -> void:
	if event.rev <= _last_rev:
		return
	_last_rev = event.rev
	if event.reset:
		_reset_pieces()
		if not event.decks.is_empty():
			var deck: Dictionary = event.decks.values()[0]
			_seat_back = deck.top_card.deck_type
	var origins: Dictionary[int, Vector3] = {}
	var hand_source: Card
	var source_position: Variant = null
	var source_back: Texture2D
	if event.type in [&"deal", &"draw_top"]:
		var deck_ids: Array = event.decks.keys() + event.removed_decks
		hand_source = _decks[deck_ids[0]]
	elif event.type == &"drop_to_hand":
		hand_source = _cards[event.removed_cards[0]]
	if hand_source != null:
		source_position = hand_source.top_surface_position()
		source_back = hand_source.back_texture()
	var retiring: Array[Card] = []
	for uid: int in event.removed_cards:
		var card: Card = _cards[uid]
		origins[uid] = card.top_surface_position()
		_cards.erase(uid)
		retiring.append(card)
	for uid: int in event.removed_decks:
		var deck: Deck = _decks[uid]
		_decks.erase(uid)
		retiring.append(deck)
	for uid: int in event.cards:
		var row: Dictionary = event.cards[uid]
		var fresh: bool = not _cards.has(uid)
		_upsert_piece(TabletopState.CARD, uid, row)
		if fresh and event.type == &"draw_top" and row.locked_by == _local_id:
			_cards[uid].global_position = source_position
		if confirms_local_action:
			_accept_hold(event.type, TabletopState.CARD, uid, row)
	for uid: int in event.decks:
		var row: Dictionary = event.decks[uid]
		_upsert_piece(TabletopState.DECK, uid, row)
		if confirms_local_action:
			_accept_hold(event.type, TabletopState.DECK, uid, row)
		if event.type == &"shuffle":
			_decks[uid].play_shuffle()
	for card: Card in retiring:
		if event.has("merge_target"):
			card.fly_to_merge(_decks[event.merge_target].global_position)
		else:
			_retire(card)
	if event.has("hand"):
		_hand.apply_hand(event.hand, _catalog, origins, source_position)
	for player_id: String in event.hand_counts:
		_set_seat_hand_count(player_id, event.hand_counts[player_id], source_position, source_back)
	if _held_uid != 0:
		var held: Card = _piece(_held_kind, _held_uid)
		if held == null or held.locked_by != _local_id:
			_forget_hold()
		elif _cancel_when_held:
			_cancel_drag.call_deferred()
		elif _drop_when_held:
			_drop.call_deferred()
	for player_id: String in _ahead_drag.keys():
		var sample: Dictionary = _ahead_drag[player_id]
		if sample.rev <= _last_rev:
			_ahead_drag.erase(player_id)
			update_remote_drag(player_id, sample)
	# Alt must clear in the same commit as a revealed card is hidden.
	_update_feedback()


func _accept_hold(type: StringName, kind: StringName, uid: int, row: Dictionary) -> void:
	if not _awaiting_hold or row.locked_by != _local_id or type not in [&"grab", &"draw_top", &"play_from_hand"]:
		return
	_awaiting_hold = false
	_hold_request.clear()
	_held_kind = kind
	_held_uid = uid
	_drag_pos = row.pos
	_piece(kind, uid).set_dragging(true)
	if not _left_down and not _drop_when_held:
		_drop_when_held = true
		_queued_release_at = _pointer


func reject_action(action: Dictionary) -> void:
	if _awaiting_hold and action == _hold_request:
		_awaiting_hold = false
		_hold_request.clear()
		_drop_when_held = false
		_cancel_when_held = false
	elif _awaiting_drop and action.type in [&"drop_hand", &"drop_merge", &"drop_table"] and action.uid == _held_uid:
		_cancel_drag()


func _upsert_piece(kind: StringName, uid: int, row: Dictionary) -> void:
	var fresh: bool = _piece(kind, uid) == null
	if kind == TabletopState.CARD:
		if fresh:
			var card: Card = CARD_SCENE.instantiate()
			_cards[uid] = card
			_place_piece(card, _cards_root, kind, uid)
		_cards[uid].apply_card(row, _projected_texture(row), _catalog.get_back_texture(row.deck_type), fresh)
	else:
		if fresh:
			var deck: Deck = DECK_SCENE.instantiate()
			_decks[uid] = deck
			_place_piece(deck, _decks_root, kind, uid)
		var top: Dictionary = row.top_card
		_decks[uid].apply_deck(row, _projected_texture(top), _catalog.get_back_texture(top.deck_type), fresh)
	var piece: Card = _piece(kind, uid)
	var locked_by_other: bool = not row.locked_by.is_empty() and row.locked_by != _local_id
	piece.set_remote_lock(locked_by_other, _colors.get(row.locked_by, Color.WHITE))


func _place_piece(card: Card, root: Node3D, kind: StringName, uid: int) -> void:
	card.set_meta(&"kind", kind)
	card.set_meta(&"uid", uid)
	root.add_child(card)


func _projected_texture(row: Dictionary) -> Texture2D:
	return null if row.face_id == &"" else _catalog.get_face_texture(row.deck_type, row.face_id)


func _retire(card: Card) -> void:
	card.stop_picking()
	card.hide_face()
	card.hide()
	card.queue_free()


func _reset_pieces() -> void:
	_clear_feedback()
	_forget_hold()
	_pending_piece.clear()
	_hand_drag = 0
	_hand.set_drag_preview(0, _pointer)
	_awaiting_hold = false
	_hold_request.clear()
	_drop_when_held = false
	_cancel_when_held = false
	_menu.hide()
	for child: Card in _cards_root.get_children():
		_retire(child)
	for child: Card in _decks_root.get_children():
		_retire(child)
	_cards.clear()
	_decks.clear()
	var origins: Dictionary[int, Vector3] = {}
	_hand.apply_hand([], _catalog, origins)
	for player_id: String in _seat_by_player:
		_set_seat_hand_count(player_id, 0)


func _set_seat_hand_count(player_id: String, count: int, origin: Variant = null,
		back: Texture2D = null) -> void:
	if player_id == _local_id or not _seat_by_player.has(player_id):
		return
	var anchor: Node3D = hand_anchor(_seat_by_player[player_id])
	var fan: Node3D = anchor.get_node("Fan")
	var badge: Label3D = anchor.get_node("Count")
	var previous: int = _seat_hand_counts.get(player_id, 0)
	_seat_hand_counts[player_id] = count
	var shown: int = mini(count, MAX_SEAT_BACKS)
	var children: Array[Node] = fan.get_children()
	# Keep the most recent slots visible when a full fan receives another deal.
	var displaced: int = clampi(count - maxi(previous, MAX_SEAT_BACKS), 0, children.size())
	for i: int in displaced:
		var card: Card = children.pop_front()
		fan.remove_child(card)
		card.queue_free()
	while children.size() > shown:
		var card: Card = children.pop_back()
		fan.remove_child(card)
		card.queue_free()
	for i: int in shown:
		var card: Card
		var fresh: bool = i >= children.size()
		if fresh:
			card = CARD_SCENE.instantiate()
			fan.add_child(card)
			card.set_seat_display()
			card.set_card_sides(null, back if back != null else _catalog.get_back_texture(_seat_back), false, true)
		else:
			card = children[i]
		var spread: float = float(i) - float(shown - 1) * 0.5
		var slot: Vector3 = Vector3(spread * minf(0.25, 1.9 / maxf(1.0, float(shown - 1))),
			0.03 + float(i) * 0.009, absf(spread) * 0.020)
		card.set_seat_slot(slot, Vector3(-12, spread * 3.2, 0))
		if fresh and origin != null:
			card.fly_to_seat(origin, minf((i - children.size()) * 0.015, 0.075))
	badge.text = str(count)
	badge.visible = count > 0


func _piece(kind: StringName, uid: int) -> Card:
	if kind == TabletopState.CARD:
		return _cards.get(uid)
	return _decks.get(uid)


func _pick_piece(at: Vector2) -> Dictionary:
	var hit: Dictionary = _raycast(at, TABLE_COLLISION_MASK | PIECE_COLLISION_MASK)
	if hit.is_empty():
		return {}
	var body: StaticBody3D = hit.collider
	if body.collision_layer != PIECE_COLLISION_MASK:
		return {}
	var card: Card = body.get_parent()
	if card.is_queued_for_deletion():
		return {}
	return {"kind": card.get_meta(&"kind"), "uid": card.get_meta(&"uid")}


func _table_position(at: Vector2, fallback: Vector2) -> Vector2:
	var origin: Vector3 = _camera.project_ray_origin(at)
	var direction: Vector3 = _camera.project_ray_normal(at)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if hit == null:
		return fallback
	var point: Vector3 = hit
	return TabletopState.clamp_to_table(Vector2(point.x, point.z))


func _physics_process(_delta: float) -> void:
	if not _can_interact():
		if _controls_active:
			_cancel_drag()
			_menu.hide()
			_alt = false
			_clear_feedback()
			if _has_cursor_point:
				cursor_sampled.emit(_last_cursor_point, false)
		return
	_update_feedback()
	if cursor_sampled.has_connections():
		var hit: Dictionary = pick_table(_pointer)
		if not hit.is_empty():
			var point: Vector3 = hit.position
			_last_cursor_point = Vector2(point.x, point.z)
			_has_cursor_point = true
		if _has_cursor_point:
			cursor_sampled.emit(_last_cursor_point, _held_uid != 0 and not _awaiting_drop)
		if _held_uid != 0 and not _awaiting_drop and not _drop_when_held and not _cancel_when_held:
			var piece: Card = _piece(_held_kind, _held_uid)
			drag_sampled.emit({"rev": piece.piece_rev, "kind": _held_kind, "uid": _held_uid,
				"x": _drag_pos.x, "y": Card.DRAG_HEIGHT, "z": _drag_pos.y, "yaw": rad_to_deg(piece.target_yaw)})


func _can_interact() -> bool:
	return can_use_controls() and not _local_id.is_empty()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer = event.position
	if not _can_interact():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_left_down = false
	if event is InputEventKey and (event.physical_keycode == KEY_ALT or event.keycode == KEY_ALT):
		_alt = event.pressed
		_update_feedback()
	if _pending_piece.is_empty() and _hand_drag == 0 and _held_uid == 0 and not _awaiting_hold:
		return
	if event is InputEventMouseMotion:
		_drag_motion(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drop()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _can_interact() or _menu.visible or _awaiting_hold or _awaiting_drop:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_press_point = event.position
		_left_down = true
		_press_msec = Time.get_ticks_msec()
		_press_whole = event.shift_pressed
		_hand_drag = _hand.card_at(event.position)
		if _hand_drag == 0:
			_pending_piece = _pick_piece(event.position)
			if not _pending_piece.is_empty() and not _piece(_pending_piece.kind, _pending_piece.uid).locked_by.is_empty():
				_pending_piece.clear()
		if _hand_drag != 0 or not _pending_piece.is_empty():
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and not event.is_command_or_control_pressed():
		_shortcut(event)


func _drag_motion(event: InputEventMouseMotion) -> void:
	if _awaiting_hold:
		if _left_down and not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_left_down = false
			_drop()
		return
	if _awaiting_drop:
		return
	if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_cancel_drag()
		return
	if _held_uid == 0 and _pointer.distance_squared_to(_press_point) <= 25.0:
		return
	if _hand_drag != 0:
		if _hand.is_drop_zone(_pointer, _press_point.y):
			var index: int = _hand.insert_index(_pointer, _hand_drag)
			_hand.set_drag_preview(_hand_drag, _pointer)
			if index != _hand.index_of(_hand_drag):
				action_requested.emit({"type": &"reorder_hand", "uid": _hand_drag, "index": index})
		else:
			var uid: int = _hand_drag
			_hand_drag = 0
			_hand.set_drag_preview(0, _pointer)
			_request_hold({"type": &"play_from_hand", "uid": uid,
				"pos": _table_position(_pointer, Vector2.ZERO), "yaw": _camera_rig.rotation_degrees.y})
	elif not _pending_piece.is_empty():
		var picked: Dictionary = _pending_piece
		_pending_piece = {}
		var whole: bool = _press_whole or event.shift_pressed or Time.get_ticks_msec() - _press_msec >= HOLD_MSEC
		if picked.kind == TabletopState.DECK and not whole:
			_request_hold({"type": &"draw_top", "deck_uid": picked.uid, "auto_grab": true})
		else:
			_request_hold({"type": &"grab", "kind": picked.kind, "uid": picked.uid})
	_move_held(_pointer)
	_update_feedback()


func _request_hold(action: Dictionary) -> void:
	_awaiting_hold = true
	_hold_request = action.duplicate()
	action_requested.emit(action)


func _move_held(at: Vector2) -> void:
	if _held_uid == 0 or _awaiting_drop:
		return
	_drag_pos = _table_position(at, _drag_pos)
	_piece(_held_kind, _held_uid).drag_at(_drag_pos)
	_drop_marker.position = Vector3(_drag_pos.x, 0.004, _drag_pos.y)
	_drop_marker.visible = not (_held_kind == TabletopState.CARD and _hand.is_drop_zone(at))


func _drop() -> void:
	_pending_piece = {}
	_hand_drag = 0
	_hand.set_drag_preview(0, _pointer)
	if _awaiting_hold:
		_drop_when_held = true
		_queued_release_at = _pointer
		return
	if _held_uid == 0 or _awaiting_drop:
		return
	var at: Vector2 = _queued_release_at if _drop_when_held else _pointer
	_move_held(at)
	var source: Card = _piece(_held_kind, _held_uid)
	var target: Card = _merge_target()
	_drop_when_held = false
	_awaiting_drop = true
	if _held_kind == TabletopState.CARD and _hand.is_drop_zone(at):
		action_requested.emit({"type": &"drop_hand", "uid": _held_uid, "index": _hand.insert_index(at)})
	elif target != null:
		action_requested.emit({"type": &"drop_merge", "kind": _held_kind, "uid": _held_uid,
			"dst_kind": target.get_meta(&"kind"), "dst_uid": target.get_meta(&"uid"), "pos": _drag_pos})
	else:
		action_requested.emit({"type": &"drop_table", "kind": _held_kind, "uid": _held_uid,
			"pos": _drag_pos, "yaw": rad_to_deg(source.target_yaw)})


func _cancel_drag() -> void:
	_pending_piece = {}
	_hand_drag = 0
	_hand.set_drag_preview(0, _pointer)
	_drop_when_held = false
	if _awaiting_hold:
		_cancel_when_held = true
		return
	_cancel_when_held = false
	if _held_uid != 0:
		var release: Dictionary = {"type": &"release_lock", "kind": _held_kind, "uid": _held_uid}
		_piece(_held_kind, _held_uid).restore_table_pose()
		_forget_hold()
		action_requested.emit(release)


func _forget_hold() -> void:
	if _held_uid != 0:
		var piece: Card = _piece(_held_kind, _held_uid)
		if piece != null:
			piece.set_dragging(false)
	_held_uid = 0
	_held_kind = &""
	_awaiting_drop = false
	_drop_marker.hide()


func _merge_target() -> Card:
	if _held_uid == 0 or not _drop_marker.visible:
		return null
	var closest: Card = null
	var nearest: float = TabletopState.MERGE_RADIUS * TabletopState.MERGE_RADIUS
	for pieces: Dictionary in [_cards, _decks]:
		for candidate: Card in pieces.values():
			if not candidate.locked_by.is_empty():
				continue
			var distance: float = candidate.table_position.distance_squared_to(_drag_pos)
			var same_distance: bool = closest != null and is_equal_approx(distance, nearest)
			if (distance < nearest and not same_distance) or (same_distance and candidate.y_order > closest.y_order):
				nearest = distance
				closest = candidate
	return closest


func _update_feedback() -> void:
	if not _can_interact() or _menu.visible:
		_clear_feedback()
		return
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	if hovered_control != null and hovered_control.mouse_filter == Control.MOUSE_FILTER_STOP and _held_uid == 0:
		_clear_feedback()
		return
	if _held_uid != 0:
		_move_held(_pointer)
		_hand.set_hover(0)
		_show_highlight(_merge_target(), true)
		_show_face(_piece(_held_kind, _held_uid).face_texture if _alt else null)
		return
	var hand_uid: int = _hand_drag if _hand_drag != 0 else _hand.card_at(_pointer)
	_hand.set_hover(hand_uid)
	if hand_uid != 0:
		_show_highlight(null)
		_show_face(_hand.face_at(hand_uid) if _alt else null)
		return
	var picked: Dictionary = _pick_piece(_pointer)
	var card: Card = null if picked.is_empty() else _piece(picked.kind, picked.uid)
	_show_highlight(card)
	_show_face(card.face_texture if _alt and card != null else null)


func _clear_feedback() -> void:
	_hand.set_hover(0)
	_show_highlight(null)
	_show_face(null)


func _show_highlight(card: Card, merge: bool = false) -> void:
	if is_instance_valid(_highlighted) and _highlighted != card:
		_highlighted.set_highlight(false)
	_highlighted = card
	if card != null:
		card.set_highlight(true, merge)


func _show_face(texture: Texture2D) -> void:
	if _preview_face != texture:
		_preview_face = texture
		face_preview_changed.emit(texture)


func _shortcut(event: InputEventKey) -> void:
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key not in [KEY_F, KEY_Q, KEY_E, KEY_R] and key not in NUMBER_KEYS:
		return
	var hovered: Dictionary = {} if _hand.card_at(_pointer) != 0 else _pick_piece(_pointer)
	var object: Dictionary = {"kind": _held_kind, "uid": _held_uid} if _held_uid != 0 else hovered
	if object.is_empty():
		return
	match key:
		KEY_F:
			action_requested.emit({"type": &"flip", "kind": object.kind, "uid": object.uid})
		KEY_Q, KEY_E:
			var step: float = 45.0 if event.shift_pressed else 15.0
			action_requested.emit({"type": &"rotate", "kind": object.kind, "uid": object.uid,
				"delta": -step if key == KEY_Q else step})
		KEY_R:
			if hovered.get("kind") == TabletopState.DECK:
				action_requested.emit({"type": &"shuffle", "deck_uid": hovered.uid})
		_:
			if hovered.get("kind") == TabletopState.DECK:
				action_requested.emit({"type": &"take_from_deck", "deck_uid": hovered.uid,
					"count": NUMBER_KEYS.find(key) + 1})
	get_viewport().set_input_as_handled()


func _open_context_menu(at: Vector2) -> void:
	if not _can_interact() or _held_uid != 0 or _awaiting_hold or _hand.card_at(at) != 0:
		return
	var picked: Dictionary = _pick_piece(at)
	if picked.is_empty():
		return
	_show_face(null)
	var popup_position: Vector2 = get_viewport().get_screen_transform() * at
	_menu.open_for(picked.kind, picked.uid, popup_position)


func _context_action(action: Dictionary) -> void:
	if _can_interact():
		action_requested.emit(action)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		_left_down = false
		_cancel_drag()
		_alt = false
		_clear_feedback()
