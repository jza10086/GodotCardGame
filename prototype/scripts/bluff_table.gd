extends "res://scripts/rules_table.gd"
## Floating-hand presenter, with privacy stripped before the texture provider.
var viewer := -1

func present_bluff(player_ids: Array, hands: Array, pile: Array, provider: Callable, viewer_index: int) -> bool:
	viewer=viewer_index
	if not apply_state(player_ids,hands,[],pile,provider,false): return false
	var seat_index := 0 if viewer < 0 else seat_for_player(String(player_ids[viewer]))-1
	active_seat=seat_index
	player_rig=seats[seat_index].rig; first_camera=seats[seat_index].camera
	hand_world=seats[seat_index].anchor; hand=seats[seat_index].hand
	refresh_viewer_faces()
	update_hand_pose(0.0)
	layout_cards(false)
	if not third_person and not top_down: camera=first_camera; camera.make_current()
	return true

func _presentation_config(model: Dictionary) -> Dictionary:
	var safe: Dictionary=model
	if model.get("hidden",false): safe={"id":model.id,"hidden":true,"face_up":false}
	var config := super._presentation_config(safe)
	if safe.get("hidden",false):
		config={"id":safe.id,"hidden":true,"face_up":false,"face":null,"back":load("res://assets/blackjack/back.png")}
	return config

func refresh_viewer_faces() -> void:
	for seat in seats:
		for card in seat.hand:
			card.set_viewer_masked(bool(card.data.get("hidden",false)))
			card.set_face_up(true,false)
	for card in played:
		card.set_viewer_masked(true)
		card.set_face_up(false,false)

func inspection_snapshot(card: Card3D) -> Dictionary:
	if not is_instance_valid(card): return {}
	if card.viewer_masked or card.data.get("hidden",false): return {"face_up":false,"description":"暗牌"}
	return super.inspection_snapshot(card)
