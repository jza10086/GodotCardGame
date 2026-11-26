class_name TabletopState
extends RefCounted

## Only this host-side model stores the identity of every physical card.
const Catalog: GDScript = preload("res://games/minigame/GP_cards/cards/deck_catalog.gd")
const CARD: StringName = &"card"
const DECK: StringName = &"deck"
# The felt apothem is 12; leave room for a rotated card at the rail.
const PLAY_APOTHEM: float = 10.95
const MERGE_RADIUS: float = 0.93

var cards: Dictionary[int, Dictionary] = {}
var table_cards: Dictionary[int, Dictionary] = {}
var table_decks: Dictionary[int, Dictionary] = {}
var hands: Dictionary[String, Array] = {}
var revision: int = 0

var _next_card_uid: int = 1
var _next_deck_uid: int = 1
var _y_order: int = 0
var _catalog: Catalog = Catalog.new()


func _init(player_ids: Array[String] = []) -> void:
	for player_id: String in player_ids:
		var hand: Array[int] = []
		hands[player_id] = hand


static func clamp_to_table(pos: Vector2) -> Vector2:
	var corner: float = (absf(pos.x) + absf(pos.y)) * sqrt(0.5)
	var edge: float = maxf(maxf(absf(pos.x), absf(pos.y)), corner)
	return pos * (PLAY_APOTHEM / edge) if edge > PLAY_APOTHEM else pos


func spawn_preset(preset_id: StringName, pos: Vector2, rng: RandomNumberGenerator,
		replace_table: bool = false) -> Dictionary:
	var faces: Array[StringName] = _catalog.get_preset_cards(preset_id)
	if faces.is_empty() or not pos.is_finite():
		return _reject("Invalid preset or table position.")
	if replace_table:
		_clear()
	# Public physical IDs must have no fixed correspondence to catalog order.
	for i: int in range(faces.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var face: StringName = faces[i]
		faces[i] = faces[j]
		faces[j] = face
	var ids: Array[int] = []
	for face_id: StringName in faces:
		var uid: int = _next_card_uid
		_next_card_uid += 1
		cards[uid] = {"deck_type": preset_id, "back_id": &"back", "face_id": face_id}
		ids.append(uid)
	_shuffle(ids, rng)
	var deck_uid: int = _add_deck(ids, _pose(pos, 0.0, false, ""))
	return _commit(&"spawn_preset", [], [deck_uid], [], replace_table)


func clear_table() -> Dictionary:
	_clear()
	return _commit(&"clear_table", [], [], [], true)


func grab(player_id: String, kind: StringName, uid: int) -> Dictionary:
	var row: Dictionary = _row(kind, uid)
	if not _can_touch(row, player_id):
		return _reject("Object is missing or held by another player.")
	row.locked_by = player_id
	return _commit_entity(&"grab", kind, uid)


func release_lock(player_id: String, kind: StringName, uid: int) -> Dictionary:
	var row: Dictionary = _row(kind, uid)
	if not _holds(row, player_id):
		return _reject("Object is not held by this player.")
	row.locked_by = ""
	return _commit_entity(&"release_lock", kind, uid)


func release_all_locks_for(player_id: String) -> Dictionary:
	if player_id.is_empty():
		return _reject("Missing player.")
	var card_ids: Array[int] = []
	var deck_ids: Array[int] = []
	for uid: int in table_cards:
		if table_cards[uid].locked_by == player_id:
			table_cards[uid].locked_by = ""
			card_ids.append(uid)
	for uid: int in table_decks:
		if table_decks[uid].locked_by == player_id:
			table_decks[uid].locked_by = ""
			deck_ids.append(uid)
	if card_ids.is_empty() and deck_ids.is_empty():
		return {"ok": true, "error": "", "event": {}}
	return _commit(&"release_all_locks", card_ids, deck_ids)


func draw_top(player_id: String, deck_uid: int, auto_grab: bool) -> Dictionary:
	var deck: Dictionary = _row(DECK, deck_uid)
	if not _can_touch(deck, player_id):
		return _reject("Deck is missing or held by another player.")
	var ids: Array[int] = deck.card_uids
	var uid: int = ids.pop_back()
	var pos: Vector2 = deck.pos
	if not auto_grab:
		pos += Vector2(1.4, 0.0).rotated(-deg_to_rad(deck.yaw_deg))
	_add_card(uid, _pose(pos, deck.yaw_deg, deck.face_up, player_id if auto_grab else ""))
	var changed_cards: Array[int] = [uid]
	_collapse(deck_uid, changed_cards)
	return _commit(&"draw_top", changed_cards, [deck_uid])


func drop_to_table(player_id: String, kind: StringName, uid: int, pos: Vector2, yaw_deg: float) -> Dictionary:
	var row: Dictionary = _row(kind, uid)
	if not _holds(row, player_id) or not pos.is_finite() or not is_finite(yaw_deg):
		return _reject("Invalid drop pose or object is not held.")
	row.merge(_pose(pos, yaw_deg, row.face_up, ""), true)
	return _commit_entity(&"drop_to_table", kind, uid)


## The destination pose and direction determine how the combined pile is placed.
func drop_merge(player_id: String, src_kind: StringName, src_uid: int,
		dst_kind: StringName, dst_uid: int) -> Dictionary:
	var source: Dictionary = _row(src_kind, src_uid)
	var target: Dictionary = _row(dst_kind, dst_uid)
	if (src_kind == dst_kind and src_uid == dst_uid) or not _holds(source, player_id) or not _can_touch(target, player_id):
		return _reject("Invalid merge or destination is held by another player.")
	var ids: Array[int] = []
	if dst_kind == CARD:
		ids.append(dst_uid)
	else:
		ids.append_array(target.card_uids)
	if src_kind == CARD:
		ids.append(src_uid)
	else:
		ids.append_array(source.card_uids)
	var card_ids: Array[int] = []
	var deck_ids: Array[int] = []
	if src_kind == CARD:
		table_cards.erase(src_uid)
		card_ids.append(src_uid)
	else:
		table_decks.erase(src_uid)
		deck_ids.append(src_uid)
	var deck_uid: int = dst_uid
	var pose: Dictionary = _pose(target.pos, target.yaw_deg, target.face_up, "")
	if dst_kind == CARD:
		table_cards.erase(dst_uid)
		card_ids.append(dst_uid)
		deck_uid = _add_deck(ids, pose)
	else:
		target.merge(pose, true)
		target.card_uids = ids
	deck_ids.append(deck_uid)
	return _commit(&"drop_merge", card_ids, deck_ids, [], false, deck_uid)


func drop_to_hand(player_id: String, card_uid: int, insert_index: int) -> Dictionary:
	var row: Dictionary = _row(CARD, card_uid)
	if not _holds(row, player_id):
		return _reject("Card is not held by this player.")
	return _move_to_hand(player_id, card_uid, insert_index)


## Menu pickup claims and stores the card in one mutation.
func take_card(player_id: String, card_uid: int) -> Dictionary:
	if not _can_touch(_row(CARD, card_uid), player_id):
		return _reject("Card is missing or held by another player.")
	return _move_to_hand(player_id, card_uid, _hand(player_id).size())


func _move_to_hand(player_id: String, card_uid: int, insert_index: int) -> Dictionary:
	var hand: Array[int] = _hand(player_id)
	hand.insert(clampi(insert_index, 0, hand.size()), card_uid)
	table_cards.erase(card_uid)
	return _commit(&"drop_to_hand", [card_uid], [], [player_id])


func play_from_hand(player_id: String, card_uid: int, pos: Vector2, yaw_deg: float,
		face_up: bool, auto_grab: bool) -> Dictionary:
	if not hands.has(player_id) or card_uid not in hands[player_id] or not pos.is_finite() or not is_finite(yaw_deg):
		return _reject("Invalid play pose or card is not in this player's hand.")
	hands[player_id].erase(card_uid)
	_add_card(card_uid, _pose(pos, yaw_deg, face_up, player_id if auto_grab else ""))
	return _commit(&"play_from_hand", [card_uid], [], [player_id])


func reorder_hand(player_id: String, card_uid: int, new_index: int) -> Dictionary:
	if not hands.has(player_id) or card_uid not in hands[player_id]:
		return _reject("Card is not in this player's hand.")
	var hand: Array[int] = hands[player_id]
	hand.erase(card_uid)
	hand.insert(clampi(new_index, 0, hand.size()), card_uid)
	return _commit(&"reorder_hand", [], [], [player_id])


func flip(player_id: String, kind: StringName, uid: int) -> Dictionary:
	var row: Dictionary = _row(kind, uid)
	if not _can_touch(row, player_id):
		return _reject("Object is missing or held by another player.")
	row.face_up = not row.face_up
	if kind == DECK:
		row.card_uids.reverse()
	return _commit_entity(&"flip", kind, uid)


func rotate_by(player_id: String, kind: StringName, uid: int, delta_deg: float) -> Dictionary:
	var row: Dictionary = _row(kind, uid)
	if not _can_touch(row, player_id) or not is_finite(delta_deg):
		return _reject("Invalid rotation or object is held by another player.")
	row.yaw_deg = wrapf(row.yaw_deg + wrapf(delta_deg, -180.0, 180.0), -180.0, 180.0)
	return _commit_entity(&"rotate", kind, uid)


func shuffle_deck(player_id: String, deck_uid: int, rng: RandomNumberGenerator) -> Dictionary:
	var row: Dictionary = _row(DECK, deck_uid)
	if not _can_touch(row, player_id):
		return _reject("Deck is missing or held by another player.")
	_shuffle(row.card_uids, rng)
	return _commit_entity(&"shuffle", DECK, deck_uid)


func deal_from_deck(player_id: String, deck_uid: int, target_player_ids: Array[String],
		count_per_player: int) -> Dictionary:
	var row: Dictionary = _row(DECK, deck_uid)
	if not _can_touch(row, player_id) or count_per_player < 1 or target_player_ids.is_empty():
		return _reject("Invalid deal or deck is held by another player.")
	var target_ids: Dictionary[String, bool] = {}
	for target_id: String in target_player_ids:
		if target_id.is_empty() or target_ids.has(target_id):
			return _reject("Deal recipients must be distinct players.")
		target_ids[target_id] = true
	var ids: Array[int] = row.card_uids
	var changed_hands: Array[String] = []
	for round_index: int in mini(count_per_player, ids.size()):
		for target_id: String in target_player_ids:
			if ids.is_empty():
				break
			var hand: Array[int] = _hand(target_id)
			hand.append(ids.pop_back())
			if target_id not in changed_hands:
				changed_hands.append(target_id)
		if ids.is_empty():
			break
	var card_ids: Array[int] = []
	_collapse(deck_uid, card_ids)
	return _commit(&"deal", card_ids, [deck_uid], changed_hands)


func can_player_see_face(viewer_id: String, card_uid: int) -> bool:
	if table_cards.has(card_uid):
		return table_cards[card_uid].face_up
	for deck: Dictionary in table_decks.values():
		if deck.face_up and deck.card_uids[-1] == card_uid:
			return true
	return hands.has(viewer_id) and card_uid in hands[viewer_id]


func piece_at(kind: StringName, uid: int) -> Dictionary:
	return _row(kind, uid)


func build_snapshot_for(viewer_id: String) -> Dictionary:
	var card_rows: Dictionary = {}
	var deck_rows: Dictionary = {}
	for uid: int in table_cards:
		card_rows[uid] = _project_table_card(uid)
	for uid: int in table_decks:
		deck_rows[uid] = _project_table_deck(uid)
	var counts: Dictionary = {}
	for player_id: String in hands:
		if player_id != viewer_id:
			counts[player_id] = hands[player_id].size()
	return {"rev": revision, "table_cards": card_rows, "table_decks": deck_rows,
		"hand": _project_hand(viewer_id), "hand_counts": counts}


## Project the event at its commit revision. The raw envelope retains only the affected private hands.
func sanitize_event_for(viewer_id: String, raw_event: Dictionary) -> Dictionary:
	var changed_hands: Dictionary = raw_event.hands
	var counts: Dictionary = {}
	for player_id: String in changed_hands:
		if player_id != viewer_id:
			counts[player_id] = changed_hands[player_id].size()
	var event: Dictionary = {
		"rev": raw_event.rev, "type": raw_event.type, "reset": raw_event.reset,
		"cards": raw_event.cards, "decks": raw_event.decks,
		"removed_cards": raw_event.removed_cards, "removed_decks": raw_event.removed_decks,
		"hand_counts": counts,
	}
	if changed_hands.has(viewer_id):
		event["hand"] = changed_hands[viewer_id]
	if raw_event.has("merge_target"):
		event["merge_target"] = raw_event.merge_target
	return event.duplicate(true)


func _project_face(uid: int, visible: bool) -> Dictionary:
	var card: Dictionary = cards[uid]
	return {"deck_type": card.deck_type, "back_id": card.back_id,
		"face_id": card.face_id if visible else &""}


func _project_table_card(uid: int) -> Dictionary:
	var row: Dictionary = table_cards[uid].duplicate()
	row.merge(_project_face(uid, can_player_see_face("", uid)))
	return row


func _project_table_deck(uid: int) -> Dictionary:
	var row: Dictionary = table_decks[uid].duplicate()
	var ids: Array[int] = row.card_uids
	row.erase("card_uids")
	row["count"] = ids.size()
	row["top_card"] = _project_face(ids[-1], row.face_up)
	return row


func _project_hand(player_id: String) -> Array[Dictionary]:
	var projected: Array[Dictionary] = []
	var ids: Array = hands.get(player_id, [])
	for uid: int in ids:
		var card: Dictionary = _project_face(uid, true)
		card["uid"] = uid
		projected.append(card)
	return projected


func _commit_entity(type: StringName, kind: StringName, uid: int) -> Dictionary:
	if kind == CARD:
		return _commit(type, [uid], [])
	return _commit(type, [], [uid])


func _commit(type: StringName, card_ids: Array[int], deck_ids: Array[int],
		hand_ids: Array[String] = [], reset: bool = false, merge_target: int = 0) -> Dictionary:
	revision += 1
	var event: Dictionary = {"type": type, "rev": revision, "reset": reset, "cards": {},
		"decks": {}, "removed_cards": [], "removed_decks": [], "hands": {}}
	for uid: int in card_ids:
		if table_cards.has(uid):
			table_cards[uid]["rev"] = revision
			event.cards[uid] = _project_table_card(uid)
		else:
			event.removed_cards.append(uid)
	for uid: int in deck_ids:
		if table_decks.has(uid):
			table_decks[uid]["rev"] = revision
			event.decks[uid] = _project_table_deck(uid)
		else:
			event.removed_decks.append(uid)
	for player_id: String in hand_ids:
		event.hands[player_id] = _project_hand(player_id)
	if merge_target != 0:
		event["merge_target"] = merge_target
	return {"ok": true, "error": "", "event": event}


func _clear() -> void:
	cards.clear()
	table_cards.clear()
	table_decks.clear()
	for hand: Array in hands.values():
		hand.clear()
	_y_order = 0


func _row(kind: StringName, uid: int) -> Dictionary:
	match kind:
		CARD:
			return table_cards.get(uid, {})
		DECK:
			return table_decks.get(uid, {})
		_:
			return {}


func _can_touch(row: Dictionary, player_id: String) -> bool:
	return not player_id.is_empty() and not row.is_empty() and row.locked_by in ["", player_id]


func _holds(row: Dictionary, player_id: String) -> bool:
	return not player_id.is_empty() and not row.is_empty() and row.locked_by == player_id


func _hand(player_id: String) -> Array[int]:
	if not hands.has(player_id):
		var ids: Array[int] = []
		hands[player_id] = ids
	return hands[player_id]


func _pose(pos: Vector2, yaw_deg: float, face_up: bool, locked_by: String) -> Dictionary:
	_y_order += 1
	return {"pos": clamp_to_table(pos), "yaw_deg": wrapf(yaw_deg, -180.0, 180.0),
		"y_order": _y_order, "face_up": face_up, "locked_by": locked_by}


func _add_card(uid: int, pose: Dictionary) -> void:
	pose["uid"] = uid
	table_cards[uid] = pose


func _add_deck(ids: Array[int], pose: Dictionary) -> int:
	var uid: int = _next_deck_uid
	_next_deck_uid += 1
	pose["deck_uid"] = uid
	pose["card_uids"] = ids
	table_decks[uid] = pose
	return uid


func _collapse(deck_uid: int, changed_cards: Array[int]) -> void:
	var row: Dictionary = table_decks[deck_uid]
	var ids: Array[int] = row.card_uids
	if ids.size() >= 2:
		return
	table_decks.erase(deck_uid)
	if ids.size() == 1:
		var remaining: int = ids[0]
		row.erase("card_uids")
		row.erase("deck_uid")
		_add_card(remaining, row)
		changed_cards.append(remaining)


static func _shuffle(ids: Array[int], rng: RandomNumberGenerator) -> void:
	for i: int in range(ids.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var previous: int = ids[i]
		ids[i] = ids[j]
		ids[j] = previous


static func _reject(message: String) -> Dictionary:
	return {"ok": false, "error": message, "event": {}}
