extends Control

## Owns the activity lifecycle, the host's state and the request/commit boundary.
const TableStage: GDScript = preload("res://games/minigame/GP_cards/table/table_stage.gd")
const TableNet: GDScript = preload("res://games/minigame/GP_cards/state/tabletop_net.gd")
const TableHud: GDScript = preload("res://games/minigame/GP_cards/ui/table_hud.gd")
const Briefing: GDScript = preload("res://games/protocols/GP_default_protocol/briefing/briefing_gate.gd")
const Settlement: GDScript = preload("res://games/protocols/GP_default_protocol/settlement/settlement_gate.gd")
const PreviewText: Translation = preload("res://games/minigame/GP_cards/i18n/zh_Hans.po")
const PREVIEW_COLORS: Array[Color] = [
	Color("#ff6673"), Color("#4cd97b"), Color("#4da6ff"), Color("#2be3f0"),
	Color("#c77dff"), Color("#ffe047"), Color("#ff9442"), Color("#ff80c4"),
]

@export var table_stage: TableStage
@export var briefing: Briefing
@export var settlement: Settlement
@export var game_audio: PartyGameAudio
@export var hud: TableHud
@export_range(1, 8, 1) var preview_seat_count: int = 8

var api: PartyAPI
var request: Dictionary
var _state: TabletopState
var _rule_hook: CardTableRuleHook
var _net: TableNet
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _local_player_id: String
var _preview_players: Array[Dictionary] = []
var _playing: bool = false
var _initialized: bool = false
var _settling: bool = false
var _stopped: bool = false


func party_setup(context: PartyAPI, config: Dictionary) -> void:
	api = context
	request = config.duplicate(true)
	game_audio.prepare_scope()


func _ready() -> void:
	assert(table_stage != null and briefing != null and settlement != null and game_audio != null and hud != null,
		"Assign the table, both protocol pages, audio, and the table HUD.")
	if _stopped:
		return
	table_stage.action_requested.connect(_dispatch_action)
	table_stage.face_preview_changed.connect(hud.show_face)
	hud.action_requested.connect(_dispatch_hud_action)
	hud.camera_reset_requested.connect(table_stage.reset_camera)
	hud.camera_overhead_requested.connect(table_stage.toggle_overhead)
	if api != null:
		_setup_network()
		briefing.play_requested.connect(_begin_play, CONNECT_ONE_SHOT)
		briefing.configure(api, {"title": api.i18n.text(&"package.name")})
	await get_tree().process_frame
	if _stopped:
		return
	if api == null:
		if get_tree().current_scene == self:
			_start_preview()
		else:
			push_error("GP_cards requires PartyAPI when mounted as an activity.")
		return
	if api.is_open():
		var error: Error = api.mark_ready()
		if error != OK:
			api.fail("load_failed", error_string(error))


func party_start() -> void:
	briefing.transport_started()


func _setup_network() -> void:
	var roster: Array[Dictionary] = api.get_players()
	var players: Array[Dictionary] = []
	var local_index: int = -1
	for player: Dictionary in roster:
		if player.is_local and player.connected:
			local_index = players.size()
			_local_player_id = player.player_id
		var appearance: Dictionary = api.get_appearance(player.player_id)
		players.append({"player_id": player.player_id, "name": player.name,
			"color": Color(appearance.color), "connected": player.connected})
	table_stage.seat_players(players, local_index, api.input)
	_net = TableNet.new(api, _local_player_id)
	_net.snapshot_received.connect(_receive_snapshot)
	_net.event_received.connect(table_stage.apply_event)
	_net.action_rejected.connect(table_stage.reject_action)
	_net.host_action_requested.connect(_commit_action)
	_net.cursor_received.connect(table_stage.update_remote_cursor)
	_net.drag_received.connect(table_stage.update_remote_drag)
	_net.result_received.connect(_receive_result)
	_net.player_departed.connect(table_stage.hide_remote_cursor)
	table_stage.cursor_sampled.connect(_net.send_cursor)
	table_stage.drag_sampled.connect(_net.send_drag)
	if api.is_host():
		api.player_disconnected.connect(_release_disconnected)


func _begin_play() -> void:
	if _settling or _stopped:
		return
	_playing = true
	if api.is_host():
		_start_authority(api.get_players())
	else:
		_activate_table()


func _start_preview() -> void:
	request = {"request_id": "gp_cards_preview", "mode": "standard"}
	for i: int in preview_seat_count:
		var nickname: String = PreviewText.get_message(&"preview.player").format({"number": i + 1})
		_preview_players.append({"player_id": "preview_%d" % (i + 1), "name": nickname,
			"color": PREVIEW_COLORS[i], "connected": true})
	table_stage.seat_players(_preview_players, 0, null)
	_local_player_id = _preview_players[0].player_id
	_playing = true
	_start_authority(_preview_players)


func _start_authority(players: Array[Dictionary]) -> void:
	# The framework seed is shared with clients. The shuffle seed stays with the host.
	_rng.seed = Crypto.new().generate_random_bytes(8).decode_s64(0)
	var ids: Array[String] = []
	for player: Dictionary in players:
		ids.append(player.player_id)
	_state = TabletopState.new(ids)
	_rule_hook = SandboxRuleHook.new()
	_rule_hook.setup(_state, players, request)
	var initial_preset: StringName = _rule_hook.get_initial_preset_id()
	if initial_preset != &"":
		var initial: Dictionary = _state.spawn_preset(initial_preset, Vector2.ZERO, _rng)
		if not initial.ok:
			if api == null:
				push_error(initial.error)
			else:
				api.fail("cards_initial_preset_failed", initial.error)
			return
		_rule_hook.on_state_event(initial.event)
	if _net == null:
		_receive_snapshot(_state.build_snapshot_for(_local_player_id))
	elif _net.start_host(_state) != OK:
		return
	_evaluate_settlement()


func _receive_snapshot(snapshot: Dictionary) -> void:
	table_stage.apply_snapshot(snapshot)
	_initialized = true
	_activate_table()


func _activate_table() -> void:
	if not _playing or not _initialized:
		return
	table_stage.set_controls_active(true)
	var can_manage: bool = api == null or api.is_host()
	hud.activate(can_manage, can_manage and _rule_hook.can_host_end_manually())


func _dispatch_hud_action(action: Dictionary) -> void:
	if table_stage.can_use_controls():
		_dispatch_action(action)


func _dispatch_action(action: Dictionary) -> void:
	if not _playing or not _initialized:
		return
	if _net == null:
		_commit_action(1, _local_player_id, 0, action)
	else:
		_net.submit(action)


func _commit_action(peer_id: int, player_id: String, req_id: int, action: Dictionary) -> void:
	if not _playing:
		return
	if action.type in TableNet.HOST_ACTIONS and peer_id != 1:
		_reject(peer_id, req_id, action)
		return
	# A holder may always relinquish their own lock, including after a rejected drop.
	if action.type != &"release_lock" and not _rule_hook.validate_action(player_id, action).ok:
		_reject(peer_id, req_id, action)
		return
	if action.type == &"end_match":
		if _rule_hook.can_host_end_manually():
			_finish_table(_rule_hook.build_manual_settlement(_players(), request))
		else:
			_reject(peer_id, req_id, action)
		return
	var result: Dictionary = _apply_action(player_id, action)
	if result.ok:
		_publish_commit(result.event, peer_id, req_id)
	else:
		_reject(peer_id, req_id, action)


func _reject(peer_id: int, req_id: int, action: Dictionary) -> void:
	if _net == null:
		table_stage.reject_action(action)
	else:
		_net.reject(peer_id, req_id, action)


func _apply_action(player_id: String, action: Dictionary) -> Dictionary:
	match action.type:
		&"spawn_preset":
			return _state.spawn_preset(action.preset_id, Vector2.ZERO, _rng, action.get("replace", false))
		&"clear_table":
			return _state.clear_table()
		&"grab":
			return _state.grab(player_id, action.kind, action.uid)
		&"release_lock":
			return _state.release_lock(player_id, action.kind, action.uid)
		&"draw_top":
			return _state.draw_top(player_id, action.deck_uid, action.auto_grab)
		&"drop_table":
			return _state.drop_to_table(player_id, action.kind, action.uid, action.pos, action.yaw)
		&"drop_merge":
			var target: Dictionary = _state.piece_at(action.dst_kind, action.dst_uid)
			if target.is_empty() or action.pos.distance_to(target.pos) >= TabletopState.MERGE_RADIUS:
				return {"ok": false}
			return _state.drop_merge(player_id, action.kind, action.uid, action.dst_kind, action.dst_uid)
		&"drop_hand":
			return _state.drop_to_hand(player_id, action.uid, action.index)
		&"take_card":
			return _state.take_card(player_id, action.uid)
		&"play_from_hand":
			return _state.play_from_hand(player_id, action.uid, action.pos, action.yaw, true, true)
		&"reorder_hand":
			return _state.reorder_hand(player_id, action.uid, action.index)
		&"flip":
			return _state.flip(player_id, action.kind, action.uid)
		&"rotate":
			return _state.rotate_by(player_id, action.kind, action.uid, action.delta)
		&"shuffle":
			return _state.shuffle_deck(player_id, action.deck_uid, _rng)
		&"take_from_deck":
			return _state.deal_from_deck(player_id, action.deck_uid, [player_id], action.count)
		&"deal":
			var targets: Array[String] = []
			for player: Dictionary in _players():
				if player.connected:
					targets.append(player.player_id)
			return _state.deal_from_deck(player_id, action.deck_uid, targets, action.count)
		_:
			return {"ok": false, "error": "Unknown table action.", "event": {}}


func _publish_commit(event: Dictionary, peer_id: int = 0, req_id: int = 0) -> void:
	_rule_hook.on_state_event(event)
	if _net == null:
		table_stage.apply_event(_state.sanitize_event_for(_local_player_id, event))
	elif _net.publish_event(event, peer_id, req_id) != OK:
		return
	_evaluate_settlement()


func _evaluate_settlement() -> void:
	var outcome: Dictionary = _rule_hook.evaluate_settlement(_players(), request)
	if outcome.should_finish:
		_finish_table(outcome.result)


func _release_disconnected(player_id: String, _peer_id: int) -> void:
	if _playing and _initialized:
		var result: Dictionary = _state.release_all_locks_for(player_id)
		if not result.event.is_empty():
			_publish_commit(result.event)


func _players() -> Array[Dictionary]:
	return _preview_players if api == null else api.get_players()


func _validate_result(result: Dictionary) -> bool:
	var contract: Script = api.load_asset({"package_id": api.protocol_id, "resource_path": "protocol.gd"}) as Script
	if contract == null:
		api.fail("contract_missing", "原版协议缺少结果契约。")
		return false
	var checked: Dictionary = contract.new().validate_result(result, request, api.get_players())
	if not checked.ok:
		api.fail(checked.code, checked.message)
	return checked.ok


func _finish_table(result: Dictionary) -> void:
	if _net == null:
		_receive_result(result)
	elif _validate_result(result):
		_net.publish_result(result)


func _receive_result(result: Dictionary) -> void:
	if _settling or (api != null and not api.is_host() and not _validate_result(result)):
		return
	_settling = true
	_playing = false
	table_stage.set_controls_active(false)
	hud.hide()
	if api == null:
		settlement.show()
		settlement.view.configure({"title": PreviewText.get_message(&"package.name"),
			"rows": result.rankings, "columns": result.get("columns", [])}, _preview_players)
		settlement.view.hide_countdown()
		return
	briefing.stop()
	if api.is_host():
		settlement.continued.connect(_submit_result.bind(result), CONNECT_ONE_SHOT)
	settlement.configure(api, {"title": api.i18n.text(&"package.name"),
		"rows": result.rankings, "columns": result.get("columns", [])}, request.request_id)


func _submit_result(result: Dictionary) -> void:
	var error: Error = api.finish(result)
	if error != OK:
		api.fail("result_rejected", error_string(error))


func party_stop(_reason: StringName) -> void:
	if _stopped:
		return
	_stopped = true
	_playing = false
	if api != null and api.player_disconnected.is_connected(_release_disconnected):
		api.player_disconnected.disconnect(_release_disconnected)
	if _net != null:
		_net.stop()
	briefing.stop()
	settlement.stop()
	game_audio.close_scope()
	if is_node_ready():
		table_stage.set_controls_active(false)
		hud.hide()


func godot_party_graphics_targets() -> Dictionary:
	return {"world": table_stage.world, "sun": table_stage.sun}


func godot_party_audio_target() -> PartyGameAudio:
	return game_audio
