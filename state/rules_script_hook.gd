class_name CardTableRuleHook
extends RefCounted

## Host-side rules receive authoritative events after each successful action.
func setup(_state: TabletopState, _players: Array[Dictionary], _config: Dictionary) -> void:
	pass


func get_initial_preset_id() -> StringName:
	return &"poker"


func validate_action(_player_id: String, _action: Dictionary) -> Dictionary:
	return {"ok": true, "reason": ""}


func on_state_event(_event: Dictionary) -> void:
	pass


func can_host_end_manually() -> bool:
	return true


func evaluate_settlement(_players: Array[Dictionary], _request: Dictionary) -> Dictionary:
	return {"should_finish": false, "result": {}}


func build_manual_settlement(players: Array[Dictionary], request: Dictionary) -> Dictionary:
	var rankings: Array[Dictionary] = []
	for player: Dictionary in players:
		rankings.append({
			"player_id": player.player_id,
			"rank": 0,
			"status": "unranked" if player.connected else "withdrawn",
		})
	return {"request_id": request.request_id, "reason": "completed", "rankings": rankings}
