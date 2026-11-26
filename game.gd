extends Control

## Owns the activity lifecycle, the host's state and the request/commit boundary.
const TableStage: GDScript = preload("res://games/minigame/GP_cards/table/table_stage.gd")
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
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _local_player_id: String
var _preview_players: Array[Dictionary] = []
var _playing: bool = false
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


func _begin_play() -> void:
	var roster: Array[Dictionary] = api.get_players()
	var players: Array[Dictionary] = []
	var local_index: int = -1
	for player: Dictionary in roster:
		if player.is_local and player.connected:
			local_index = players.size()
		var appearance: Dictionary = api.get_appearance(player.player_id)
		players.append({"player_id": player.player_id, "name": player.name, "color": Color(appearance.color)})
	# Until the transport is wired, authority is playable only in the host's view.
	table_stage.seat_players(players, local_index if api.is_host() else -1, api.input)
	_rng.seed = api.get_seed()
	if api.is_host():
		api.player_disconnected.connect(_release_disconnected)
	_start_table(roster, local_index)


func _start_preview() -> void:
	request = {"request_id": "gp_cards_preview", "mode": "standard"}
	for i: int in preview_seat_count:
		var nickname: String = PreviewText.get_message(&"preview.player").format({"number": i + 1})
		_preview_players.append({"player_id": "preview_%d" % (i + 1), "name": nickname,
			"color": PREVIEW_COLORS[i], "connected": true})
	_rng.randomize()
	table_stage.seat_players(_preview_players, 0, null)
	_start_table(_preview_players, 0)


func _start_table(players: Array[Dictionary], local_index: int) -> void:
	if local_index >= 0:
		_local_player_id = players[local_index].player_id
	_playing = true
	table_stage.set_controls_active(true)
	var is_host: bool = api == null or api.is_host()
	if not is_host:
		hud.activate(false, false)
		return
	var ids: Array[String] = []
	for player: Dictionary in players:
		ids.append(player.player_id)
	_state = TabletopState.new(ids)
	_rule_hook = SandboxRuleHook.new()
	_rule_hook.setup(_state, players, request)
	hud.activate(true, _rule_hook.can_host_end_manually())
	table_stage.apply_snapshot(_state.build_snapshot_for(_local_player_id))
	var initial_preset: StringName = _rule_hook.get_initial_preset_id()
	if initial_preset != &"":
		_dispatch_action({"type": &"spawn_preset", "preset_id": initial_preset})


func _dispatch_hud_action(action: Dictionary) -> void:
	if table_stage.can_use_controls():
		_dispatch_action(action)


## Phase 3 can route the same player intent through the transport before host commit.
func _dispatch_action(action: Dictionary) -> void:
	if not _playing or _state == null:
		return
	var decision: Dictionary = _rule_hook.validate_action(_local_player_id, action)
	if not decision.ok:
		table_stage.reject_action(action)
		return
	if action.type == &"end_match":
		if _rule_hook.can_host_end_manually():
			_open_settlement(_rule_hook.build_manual_settlement(_players(), request))
		return
	var result: Dictionary = _apply_action(_local_player_id, action)
	if result.ok:
		_publish_commit(result.event)
	else:
		table_stage.reject_action(action)


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


func _publish_commit(event: Dictionary) -> void:
	_rule_hook.on_state_event(event)
	table_stage.apply_event(_state.sanitize_event_for(_local_player_id, event))
	var outcome: Dictionary = _rule_hook.evaluate_settlement(_players(), request)
	if outcome.should_finish:
		_open_settlement(outcome.result)


func _release_disconnected(player_id: String, _peer_id: int) -> void:
	if _playing:
		var result: Dictionary = _state.release_all_locks_for(player_id)
		_publish_commit(result.event)


func _players() -> Array[Dictionary]:
	return _preview_players if api == null else api.get_players()


func _open_settlement(result: Dictionary) -> void:
	_playing = false
	table_stage.set_controls_active(false)
	hud.hide()
	if api == null:
		settlement.show()
		settlement.view.configure({"title": PreviewText.get_message(&"package.name"),
			"rows": result.rankings, "columns": []}, _preview_players)
		settlement.view.hide_countdown()
		return
	# The protocol gate requires every connected room peer to mount the result.
	# Until Phase 3 publishes it to peers, use that gate only for a local room.
	for player: Dictionary in api.get_room_players():
		if player.connected and player.peer_id != 1:
			_submit_result(result)
			return
	settlement.continued.connect(_submit_result.bind(result), CONNECT_ONE_SHOT)
	settlement.configure(api, {"title": api.i18n.text(&"package.name"),
		"rows": result.rankings, "columns": []}, request.request_id)


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
