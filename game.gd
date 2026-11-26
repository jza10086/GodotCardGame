extends Control

## Formal scopes wait for protocol readiness; a directly run scene can preview the table locally.
const TableStage: GDScript = preload("res://games/minigame/GP_cards/table/table_stage.gd")
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
@export_range(1, 8, 1) var preview_seat_count: int = 8

var api: PartyAPI
var request: Dictionary
var _stopped: bool = false


func party_setup(context: PartyAPI, config: Dictionary) -> void:
	api = context
	request = config.duplicate(true)
	game_audio.prepare_scope()


func _ready() -> void:
	assert(table_stage != null and briefing != null and settlement != null and game_audio != null,
		"Assign the table, both protocol pages, and the audio component.")
	if _stopped:
		return
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
		players.append({"name": player.name, "color": Color(appearance.color)})
	table_stage.seat_players(players, local_index, api.input)
	table_stage.set_controls_active(true)


func _start_preview() -> void:
	var players: Array[Dictionary] = []
	for i: int in preview_seat_count:
		var nickname: String = PreviewText.get_message(&"preview.player").format({"number": i + 1})
		players.append({"name": nickname, "color": PREVIEW_COLORS[i]})
	table_stage.seat_players(players, 0, null)
	table_stage.set_controls_active(true)


func party_stop(_reason: StringName) -> void:
	if _stopped:
		return
	_stopped = true
	briefing.stop()
	settlement.stop()
	game_audio.close_scope()
	if is_node_ready():
		table_stage.set_controls_active(false)


func godot_party_graphics_targets() -> Dictionary:
	return {"world": table_stage.world, "sun": table_stage.sun}


func godot_party_audio_target() -> PartyGameAudio:
	return game_audio
