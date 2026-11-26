extends RefCounted

## The room host is the only endpoint allowed to publish projected state or relay motion.
signal snapshot_received(snapshot: Dictionary)
signal event_received(event: Dictionary, confirms_local_action: bool)
signal action_rejected(action: Dictionary)
signal host_action_requested(peer_id: int, player_id: String, req_id: int, action: Dictionary)
signal cursor_received(player_id: String, position: Vector2, holding: bool)
signal drag_received(player_id: String, sample: Dictionary)
signal result_received(result: Dictionary)
signal player_departed(player_id: String)

const INIT: StringName = &"cards/init"
const REQUEST: StringName = &"cards/req"
const EVENT: StringName = &"cards/evt"
const CURSOR: StringName = &"cards/cursor"
const DRAG: StringName = &"cards/drag"
const RESULT: StringName = &"cards/result"
const MOTION_MODE: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
const MOTION_CHANNEL: int = 1
const SAMPLE_USEC: int = 40000
const MOTION_THRESHOLD: float = 0.08
const YAW_THRESHOLD: float = 1.0
const HOST_ACTIONS: Array[StringName] = [&"spawn_preset", &"clear_table", &"end_match"]

var _api: PartyAPI
var _state: TabletopState
var _initialized: bool = false
var _ended: bool = false
var _local_id: String
var _next_req: int = 0
var _pending: Dictionary[int, Dictionary] = {}
var _last_request: Dictionary[int, int] = {}
var _last_cursor: Dictionary[String, Dictionary] = {}
var _last_drag: Dictionary[String, Dictionary] = {}


func _init(api: PartyAPI, local_id: String) -> void:
	_api = api
	_local_id = local_id
	_api.net.message_received.connect(_message)
	_api.player_disconnected.connect(_departed)


func stop() -> void:
	_ended = true
	_pending.clear()
	_api.net.message_received.disconnect(_message)
	_api.player_disconnected.disconnect(_departed)


func start_host(state: TabletopState) -> Error:
	_state = state
	_initialized = true
	for player: Dictionary in _api.get_room_players():
		if not player.connected or player.peer_id == 1:
			continue
		var error: Error = _api.net.send_to_peer(player.peer_id, INIT,
			_envelope({"snapshot": state.build_snapshot_for(player.player_id)}))
		if error != OK:
			_report("cards_init_failed", error)
			return error
	snapshot_received.emit(state.build_snapshot_for(_local_id))
	return OK


func submit(action: Dictionary) -> void:
	if not _initialized or _ended:
		return
	if _api.is_host():
		host_action_requested.emit(1, _local_id, 0, action)
		return
	_next_req += 1
	_pending[_next_req] = action.duplicate()
	var error: Error = _api.net.send_to_host(REQUEST, _envelope({"req_id": _next_req, "action": action}))
	if error != OK:
		_pending.erase(_next_req)
		action_rejected.emit(action)
		_report("cards_request_failed", error)


func reject(peer_id: int, req_id: int, action: Dictionary) -> void:
	if peer_id == 1:
		action_rejected.emit(action)
		return
	var error: Error = _api.net.send_to_peer(peer_id, EVENT,
		_envelope({"req_id": req_id, "rejected": true}))
	if error != OK:
		_report("cards_reject_failed", error)


func publish_event(raw_event: Dictionary, actor_peer: int = 0, req_id: int = 0) -> Error:
	for player: Dictionary in _api.get_room_players():
		if not player.connected or player.peer_id == 1:
			continue
		var packet: Dictionary = _envelope({"event": _state.sanitize_event_for(player.player_id, raw_event),
			"req_id": req_id if player.peer_id == actor_peer else 0})
		var error: Error = _api.net.send_to_peer(player.peer_id, EVENT, packet)
		if error != OK:
			_report("cards_event_failed", error)
			return error
	event_received.emit(_state.sanitize_event_for(_local_id, raw_event), actor_peer == 1)
	return OK


func publish_result(result: Dictionary) -> void:
	if _ended:
		return
	_ended = true
	_pending.clear()
	var error: Error = _api.net.broadcast(RESULT, _envelope({"result": result}),
		MultiplayerPeer.TRANSFER_MODE_RELIABLE, false)
	if error != OK:
		_report("cards_result_failed", error)
		return
	result_received.emit(result)


func send_cursor(position: Vector2, holding: bool) -> void:
	if _local_id.is_empty() or not _initialized or _ended:
		return
	_send_sample(CURSOR, {"x": position.x, "z": position.y, "holding": holding})


func send_drag(sample: Dictionary) -> void:
	if _local_id.is_empty() or not _initialized or _ended:
		return
	_send_sample(DRAG, sample)


func _send_sample(topic: StringName, sample: Dictionary) -> void:
	if _api.is_host():
		_relay_sample(1, _local_id, topic, sample)
	elif _accept_sample(_local_id, topic, sample):
		var error: Error = _api.net.send_to_host(topic, _envelope(sample), MOTION_MODE, MOTION_CHANNEL)
		if error != OK:
			_report("cards_motion_failed", error)


func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if _ended or topic not in [INIT, REQUEST, EVENT, CURSOR, DRAG, RESULT] or not payload is Dictionary:
		return
	if not payload.get("session") is String or payload.session != _api.session_id:
		return
	if not payload.get("scope") is String or payload.scope != _api.scope_id:
		return
	var peer: Variant = sender.get("peer_id")
	if not peer is int or peer < 1 or not sender.get("player_ids") is Array:
		return
	var ids: Array = sender.player_ids
	if ids.size() != 1 or not ids[0] is String or ids[0].is_empty():
		return
	var actor: String = ids[0]
	if _api.is_host():
		if not _initialized or peer == 1 or not _connected_as(_api.get_players(), peer, actor):
			return
		if topic == REQUEST:
			_receive_request(peer, actor, payload)
		elif topic in [CURSOR, DRAG]:
			_relay_sample(peer, actor, topic, payload)
		return
	if peer != 1 or not _connected_as(_api.get_room_players(), peer, actor):
		return
	if topic == INIT:
		if not _initialized and _valid_snapshot(payload.get("snapshot")):
			_initialized = true
			snapshot_received.emit(payload.snapshot)
		return
	if not _initialized:
		return
	match topic:
		EVENT:
			_receive_event(payload)
		CURSOR, DRAG:
			var player: Variant = payload.get("player_id")
			if player is String and player != _local_id and _connected_as(_api.get_players(), 0, player):
				_deliver_sample(player, topic, payload)
		RESULT:
			if payload.get("result") is Dictionary:
				_ended = true
				_pending.clear()
				result_received.emit(payload.result)


func _receive_request(peer: int, actor: String, payload: Dictionary) -> void:
	var req: Variant = payload.get("req_id")
	if not req is int or req <= _last_request.get(peer, 0):
		return
	_last_request[peer] = req
	var action: Variant = payload.get("action")
	if not action is Dictionary or not _valid_action(action) or StringName(action.type) in HOST_ACTIONS:
		reject(peer, req, {})
		return
	host_action_requested.emit(peer, actor, req, action)


func _receive_event(payload: Dictionary) -> void:
	var req: Variant = payload.get("req_id")
	if not req is int or req < 0:
		return
	if payload.get("rejected") is bool and payload.rejected:
		if _pending.has(req):
			var action: Dictionary = _pending[req]
			_pending.erase(req)
			action_rejected.emit(action)
		return
	if _valid_event(payload.get("event")):
		event_received.emit(payload.event, _pending.erase(req))


func _relay_sample(peer: int, actor: String, topic: StringName, sample: Dictionary) -> void:
	if topic == CURSOR:
		if not _valid_cursor(sample):
			return
		sample = {"x": sample.x, "z": sample.z, "holding": sample.holding}
	else:
		if not _valid_drag(sample):
			return
		var piece: Dictionary = _state.piece_at(sample.kind, sample.uid)
		if piece.is_empty() or piece.locked_by != actor or piece.rev != sample.rev:
			return
		sample = {"rev": sample.rev, "kind": sample.kind, "uid": sample.uid,
			"x": sample.x, "y": sample.y, "z": sample.z, "yaw": sample.yaw}
	if not _accept_sample(actor, topic, sample):
		return
	var packet: Dictionary = _envelope(sample)
	packet["player_id"] = actor
	for player: Dictionary in _api.get_room_players():
		if not player.connected or player.peer_id in [1, peer]:
			continue
		var error: Error = _api.net.send_to_peer(player.peer_id, topic, packet, MOTION_MODE, MOTION_CHANNEL)
		if error != OK:
			_report("cards_motion_failed", error)
			return
	if peer != 1:
		_deliver_sample(actor, topic, sample)


func _deliver_sample(actor: String, topic: StringName, sample: Dictionary) -> void:
	if topic == CURSOR and _valid_cursor(sample):
		cursor_received.emit(actor, Vector2(sample.x, sample.z), sample.holding)
	elif topic == DRAG and _valid_drag(sample):
		drag_received.emit(actor, sample)


func _accept_sample(actor: String, topic: StringName, sample: Dictionary) -> bool:
	var stream: Dictionary[String, Dictionary] = _last_cursor if topic == CURSOR else _last_drag
	var previous: Dictionary = stream.get(actor, {})
	var now: int = Time.get_ticks_usec()
	if not previous.is_empty():
		if now - previous.time < SAMPLE_USEC:
			return false
		var distance: float = Vector2(sample.x, sample.z).distance_to(Vector2(previous.x, previous.z))
		if topic == CURSOR:
			if sample.holding == previous.holding and distance < MOTION_THRESHOLD:
				return false
		elif sample.kind == previous.kind and sample.uid == previous.uid:
			var yaw_delta: float = absf(wrapf(sample.yaw - previous.yaw, -180.0, 180.0))
			if distance < MOTION_THRESHOLD and absf(sample.y - previous.y) < MOTION_THRESHOLD and yaw_delta < YAW_THRESHOLD:
				return false
	var recorded: Dictionary = sample.duplicate()
	recorded["time"] = now
	stream[actor] = recorded
	return true


func _departed(player_id: String, peer_id: int) -> void:
	_last_request.erase(peer_id)
	_last_cursor.erase(player_id)
	_last_drag.erase(player_id)
	player_departed.emit(player_id)


func _envelope(data: Dictionary) -> Dictionary:
	var payload: Dictionary = {"session": _api.session_id, "scope": _api.scope_id}
	payload.merge(data)
	return payload


func _report(code: String, error: Error) -> void:
	_ended = true
	var reported: Error = _api.fail(code, error_string(error))
	if reported != OK:
		push_error("%s: %s (report: %s)" % [code, error_string(error), error_string(reported)])


static func _connected_as(roster: Array[Dictionary], peer_id: int, player_id: String) -> bool:
	for player: Dictionary in roster:
		if player.connected and player.player_id == player_id and (peer_id == 0 or player.peer_id == peer_id):
			return true
	return false


static func _valid_action(action: Dictionary) -> bool:
	var type: Variant = action.get("type")
	if not _is_text(type):
		return false
	match StringName(type):
		&"spawn_preset", &"clear_table", &"end_match":
			return true
		&"grab", &"release_lock", &"flip":
			return _valid_ref(action.get("kind"), action.get("uid"))
		&"rotate":
			return _valid_ref(action.get("kind"), action.get("uid")) and _number(action.get("delta"), 360.0)
		&"drop_table":
			return _valid_ref(action.get("kind"), action.get("uid")) and _valid_pose(action)
		&"drop_merge":
			return _valid_ref(action.get("kind"), action.get("uid")) and _valid_table_pos(action.get("pos")) \
				and _valid_ref(action.get("dst_kind"), action.get("dst_uid"))
		&"draw_top":
			return _positive_id(action.get("deck_uid")) and action.get("auto_grab") is bool
		&"shuffle":
			return _positive_id(action.get("deck_uid"))
		&"deal", &"take_from_deck":
			var count: Variant = action.get("count")
			return _positive_id(action.get("deck_uid")) and count is int and count >= 1 and count <= 108
		&"play_from_hand":
			return _positive_id(action.get("uid")) and _valid_pose(action)
		&"take_card":
			return _positive_id(action.get("uid"))
		&"drop_hand", &"reorder_hand":
			return _positive_id(action.get("uid")) and action.get("index") is int and action.index >= 0
	return false


static func _valid_snapshot(snapshot: Variant) -> bool:
	return snapshot is Dictionary and snapshot.get("rev") is int and snapshot.rev >= 0 \
		and _valid_rows(snapshot.get("table_cards"), false, snapshot.rev) \
		and _valid_rows(snapshot.get("table_decks"), true, snapshot.rev) \
		and _valid_hand(snapshot.get("hand")) and _valid_counts(snapshot.get("hand_counts"))


static func _valid_event(event: Variant) -> bool:
	if not event is Dictionary or not _positive_id(event.get("rev")) or not _is_text(event.get("type")) \
			or not event.get("reset") is bool or not _valid_rows(event.get("cards"), false, event.rev) \
			or not _valid_rows(event.get("decks"), true, event.rev) or not _valid_counts(event.get("hand_counts")):
		return false
	if event.has("hand") and not _valid_hand(event.hand):
		return false
	if event.has("merge_target") and (not _positive_id(event.merge_target) or not event.decks.has(event.merge_target)):
		return false
	for key: String in ["removed_cards", "removed_decks"]:
		if not event.get(key) is Array:
			return false
		for uid: Variant in event[key]:
			if not _positive_id(uid):
				return false
	return true


static func _valid_rows(rows: Variant, deck: bool, revision: int) -> bool:
	if not rows is Dictionary:
		return false
	for uid: Variant in rows:
		var row: Variant = rows[uid]
		if not _positive_id(uid) or not row is Dictionary or not _valid_table_pos(row.get("pos")) \
				or not _number(row.get("yaw_deg"), 180.0) or not row.get("face_up") is bool \
				or not row.get("locked_by") is String or not _positive_id(row.get("y_order")) \
				or not _positive_id(row.get("rev")) or row.rev > revision:
			return false
		if deck and (row.get("deck_uid") != uid or not row.get("count") is int or row.count < 2):
			return false
		if not deck and row.get("uid") != uid:
			return false
		var face: Variant = row.get("top_card") if deck else row
		if not _valid_face(face) or (not row.face_up and face.face_id != &""):
			return false
	return true


static func _valid_hand(hand: Variant) -> bool:
	if not hand is Array:
		return false
	for row: Variant in hand:
		if not _valid_face(row) or not _positive_id(row.get("uid")) or row.face_id == &"":
			return false
	return true


static func _valid_face(row: Variant) -> bool:
	return row is Dictionary and _is_text(row.get("deck_type")) and row.deck_type in [&"poker", &"uno"] \
		and _is_text(row.get("back_id")) and row.back_id == &"back" and _is_text(row.get("face_id"))


static func _valid_counts(counts: Variant) -> bool:
	if not counts is Dictionary:
		return false
	for player_id: Variant in counts:
		if not player_id is String or not counts[player_id] is int or counts[player_id] < 0:
			return false
	return true


static func _valid_cursor(sample: Dictionary) -> bool:
	return _number(sample.get("x"), 12.1) and _number(sample.get("z"), 12.1) \
		and absf(sample.x) + absf(sample.z) <= 17.1 and sample.get("holding") is bool


static func _valid_drag(sample: Dictionary) -> bool:
	return _valid_ref(sample.get("kind"), sample.get("uid")) and _positive_id(sample.get("rev")) \
		and _number(sample.get("x"), 11.0) and _number(sample.get("z"), 11.0) \
		and _number(sample.get("y"), 1.5) and sample.y >= 0.0 and _number(sample.get("yaw"), 180.0)


static func _valid_pose(action: Dictionary) -> bool:
	return _valid_table_pos(action.get("pos")) and _number(action.get("yaw"), 360.0)


static func _valid_table_pos(pos: Variant) -> bool:
	return pos is Vector2 and pos.is_finite() and absf(pos.x) <= 11.0 and absf(pos.y) <= 11.0


static func _valid_ref(kind: Variant, uid: Variant) -> bool:
	return _is_text(kind) and kind in [TabletopState.CARD, TabletopState.DECK] and _positive_id(uid)


static func _positive_id(value: Variant) -> bool:
	return value is int and value > 0


static func _number(value: Variant, limit: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and absf(float(value)) <= limit


static func _is_text(value: Variant) -> bool:
	return value is String or value is StringName
