extends SceneTree
## Separate regression suite for draw flights, group play, and public history.
## Run after importing the project:
## godot --headless --path . --script res://tests/test_animations.gd

var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func reset_round(demo) -> void:
	check(demo.start_round(["alice", "bob", "carol", "dave", "erin", "frank", "grace", "heidi"]), "fresh eight-player animation round")
	demo.set_process(false)
	demo.layout_cards(false)

func members(demo) -> Dictionary:
	var result := {}
	for seat in demo.seats:
		for card in seat.hand:
			result[card.get_instance_id()] = str(seat.id)
	for card in demo.played:
		result[card.get_instance_id()] = "play"
	return result

func check_population(demo, label: String) -> void:
	var count: int = demo.played.size()
	for seat in demo.seats:
		count += seat.hand.size()
	check(demo.total_cards() == 64, label + ": 64-card population")
	check(members(demo).size() == count, label + ": no duplicated instance membership")
	for card in demo.flights:
		check(is_instance_valid(card) and members(demo).has(card.get_instance_id()), label + ": flight is an owned real card")

func hand_position(cards: Array, card: Card3D) -> Vector3:
	var index := cards.find(card)
	var center := float(index) - (cards.size() - 1) / 2.0
	var step := minf(1.22, 6.8 / maxf(1, cards.size() - 1))
	return Vector3(center * step, 0.02 * index, absf(center) * 0.025)

func check_hand_pose(demo, card: Card3D, seat_index: int, label: String) -> void:
	var seat: Dictionary = demo.seats[seat_index]
	var target := hand_position(seat.hand, card)
	check(card.get_parent() == seat.anchor and card.zone == &"hand", label + ": owner parent and zone")
	check(card.position.is_equal_approx(target), label + ": final hand fan position")
	check(card.global_position.is_equal_approx(seat.anchor.to_global(target)), label + ": current world-space anchor")
	check(card.scale.is_equal_approx(Vector3.ONE * 0.68), label + ": hand scale restored")

func check_public_cards(snapshot: Dictionary, label: String) -> void:
	var allowed := ["face_up", "face_hidden", "zone", "selected", "description", "title"]
	check(snapshot.has("actor") and snapshot.has("seat") and snapshot.has("cards"), label + ": actor/seat/cards schema")
	for public_card in snapshot.get("cards", []):
		check(public_card is Dictionary, label + ": card is data, not a live Node")
		if not public_card is Dictionary:
			continue
		for key in public_card:
			check(key in allowed, label + ": public card allowlist " + str(key))
		check(public_card.get("zone") == "play", label + ": completed play zone")
		check(not public_card.has("id") and not public_card.has("data") and not public_card.has("metadata") and not public_card.has("face") and not public_card.has("back"), label + ": no private data or resources")

func test_rapid_draws(demo) -> void:
	reset_round(demo)
	var initial_members := members(demo)
	var initial_deck: int = demo.deck.size()
	var draw_ids: Array = []
	for index in 3:
		var expected_data: Dictionary = demo.deck[0].duplicate(true)
		var deck_start: Vector3 = demo.deck_visual.back().global_position
		var card: Card3D = demo.draw_card(true)
		check(card != null, "rapid draw %d succeeds" % index)
		if card == null:
			continue
		draw_ids.append(card.get_instance_id())
		check(card.get_parent() == demo.hand_world and card in demo.hand and card.zone == &"hand", "draw reserves real hand membership immediately")
		check(card.data == expected_data, "draw consumes the next deck card exactly once")
		check(card.get_meta("seat_id") == demo.seats[0].id, "draw records owner immediately")
		check(demo.flights.has(card), "animated draw tracks the actual Card3D")
		check(card.global_position.distance_to(deck_start) < 0.75, "draw begins in world space at the deck")
		check(card.global_position.distance_to(demo.hand_world.to_global(hand_position(demo.hand, card))) > 2.0, "draw does not begin already in hand")
		check(demo.hand.size() == 6 + index and demo.deck.size() == initial_deck - index - 1, "rapid draw reserves capacity synchronously")
		check_population(demo, "rapid draw %d" % index)
	check(demo.flights.size() == 3, "three rapid draws coexist without restarting or duplicating cards")
	var before_full := members(demo)
	check(demo.draw_card(true) == null, "reserved eighth slot blocks a fourth rapid draw")
	check(members(demo) == before_full and demo.deck.size() == initial_deck - 3 and demo.flights.size() == 3, "full draw rejection leaves memberships, deck, and flights unchanged")
	for instance_id in initial_members:
		check(members(demo).has(instance_id), "rapid draws retain every previously dealt card")
	var last: Card3D = demo.hand.back()
	var departure := last.global_position
	demo.advance_flights(0.08)
	check(demo.flights.has(last) and not last.global_position.is_equal_approx(departure), "deterministic progress visibly moves an unfinished draw")
	demo.settle_flights()
	check(demo.flights.is_empty(), "settle completes every rapid draw")
	for card in demo.hand:
		if card.get_instance_id() in draw_ids:
			check_hand_pose(demo, card, 0, "rapid draw landing")
	for instance_id in draw_ids:
		check(members(demo).has(instance_id), "landing keeps the same drawn instance")
	check(demo.last_play_snapshot().is_empty(), "drawing does not create play history")
	check_population(demo, "rapid draw completion")

func test_moving_draw_target(demo) -> void:
	reset_round(demo)
	var card: Card3D = demo.draw_card(true)
	var departure := card.global_position
	var original_target: Vector3 = demo.hand_world.to_global(hand_position(demo.hand, card))
	demo.apply_player_look(Vector2(70, -25))
	demo.advance_flights(0.0)
	check(card.global_position.is_equal_approx(departure), "unstarted draw remains at deck when owner turns")
	check(not demo.hand_world.to_global(hand_position(demo.hand, card)).is_equal_approx(original_target), "turning really changes the draw destination")
	demo.advance_flights(0.10)
	check(demo.flights.has(card), "draw survives owner look during flight")
	demo.apply_player_look(Vector2(-90, 45))
	demo.advance_flights(100.0)
	check(demo.flights.is_empty(), "large deterministic step completes moving-target draw")
	check_hand_pose(demo, card, 0, "moving-target landing")
	check_population(demo, "moving-target draw")
	reset_round(demo)
	card = demo.draw_card(false)
	check(card != null and demo.flights.is_empty(), "nonanimated draw is immediate")
	check_hand_pose(demo, card, 0, "nonanimated draw")

func test_selection(demo) -> void:
	reset_round(demo)
	var first: Card3D = demo.hand[0]
	var second: Card3D = demo.hand[1]
	var third: Card3D = demo.hand[2]
	demo.select(first)
	check(demo.selected == first and demo.selected_cards.size() == 1 and first.selected, "normal select creates a one-card selection")
	demo.select(second, true)
	check(demo.selected_cards.size() == 2 and first in demo.selected_cards and second in demo.selected_cards, "Ctrl equivalent adds another card")
	check(first.selected and second.selected and first.marker.visible and second.marker.visible, "all selected cards show markers")
	demo.select(first, true)
	check(demo.selected_cards.size() == 1 and second in demo.selected_cards and not first.selected, "Ctrl equivalent toggles a card off")
	demo.select(third)
	check(demo.selected_cards.size() == 1 and third in demo.selected_cards and not second.selected, "normal select replaces the prior group")
	demo.select(third, true)
	check(demo.selected_cards.is_empty() and demo.selected == null and not third.selected, "Ctrl toggle of final card clears selection")
	demo.select(first)
	demo.select(second, true)
	demo.select(null)
	check(demo.selected_cards.is_empty() and demo.selected == null and not first.selected and not second.selected, "empty selection clears every selected marker")
	demo.select(demo.seats[1].hand[0])
	check(demo.selected_cards.is_empty() and demo.selected == null, "other player's hand cannot enter selection")
	check(not demo.play_selected() and demo.last_play_snapshot().is_empty(), "empty group cannot play or create history")

func test_group_play_and_history(demo) -> void:
	reset_round(demo)
	var cards: Array = demo.hand.duplicate()
	var identities := members(demo)
	cards[0].data["title"] = "PUBLIC VISIBLE A"
	cards[4].data["title"] = "PUBLIC VISIBLE B"
	cards[1].data["title"] = "SECRET HIDDEN TITLE"
	cards[2].data["title"] = "SECRET BACK TITLE"
	cards[2].set_face_up(false, false)
	cards[3].data["title"] = "SECRET NULL TITLE"
	for card in cards:
		card.data["metadata"] = {"secret": "PRIVATE PAYLOAD"}
		demo.select(card, true)
	check(demo.selected_cards.size() == 5, "five-card group selected")
	var starts := {}
	for card in cards:
		starts[card.get_instance_id()] = card.global_transform
	check(demo.play_selected(), "selected group accepted in one operation")
	check(demo.hand.is_empty() and demo.played.size() == 5 and demo.flights.size() == 5, "group reserves all destinations immediately")
	check(demo.last_play_snapshot().is_empty(), "last completed play stays empty while group is airborne")
	for card in cards:
		check(card in demo.played and card.zone == &"play" and card.get_parent() == demo, "group reuses real cards in table parent")
		check(card.get_meta("seat_id") == "", "played card no longer has private hand ownership")
		check(card.global_transform.is_equal_approx(starts[card.get_instance_id()]), "group launch preserves exact world pose")
	check_population(demo, "group launch")
	demo.advance_flights(0.06)
	check(demo.last_play_snapshot().is_empty(), "partial group flight does not publish premature history")
	demo.settle_flights()
	var snapshot: Dictionary = demo.last_play_snapshot()
	check(demo.flights.is_empty() and snapshot.get("cards", []).size() == 5, "completed group publishes all five cards once")
	check(snapshot.get("actor") == "alice" and snapshot.get("seat") == 1, "history identifies actor and one-based physical seat")
	check_public_cards(snapshot, "group history")
	var serialized := JSON.stringify(snapshot)
	check(serialized.contains("PUBLIC VISIBLE A") and serialized.contains("PUBLIC VISIBLE B"), "visible public titles appear in history")
	check(not serialized.contains("SECRET") and not serialized.contains("PRIVATE"), "hidden, back, missing-face and arbitrary metadata never leak")
	for instance_id in identities:
		check(members(demo).has(instance_id), "group landing conserves every original instance")
	var saved: Dictionary = snapshot.duplicate(true)
	if not snapshot.get("cards", []).is_empty():
		snapshot.cards[0]["description"] = "CALLER MUTATION"
		snapshot.cards.append({"title": "CALLER APPEND"})
	snapshot["actor"] = "CALLER ACTOR"
	check(demo.last_play_snapshot() == saved, "history accessor returns a deep copy")
	cards[0].data["title"] = "LATER RENAMED TITLE"
	cards[1].set_face_hidden(false)
	cards[2].set_face_up(true, false)
	cards[3].data["metadata"]["secret"] = "LATER PRIVATE DATA"
	check(demo.last_play_snapshot() == saved, "history is immutable after later live card changes")
	demo.settle_flights()
	check(demo.last_play_snapshot() == saved, "settling twice does not replace completed history")
	check_population(demo, "group completion")

func test_capacity_atomicity(demo) -> void:
	reset_round(demo)
	for seat_index in 5:
		demo.set_active_seat(seat_index)
		while not demo.hand.is_empty() and demo.played.size() < 15:
			check(demo.move_card(demo.hand[0], &"play"), "prepare shared table capacity")
			demo.settle_flights()
	check(demo.played.size() == 15 and demo.hand.size() == 2, "fifteen-card table leaves only one slot for two-card selection")
	var first: Card3D = demo.hand[0]
	var second: Card3D = demo.hand[1]
	demo.select(first)
	demo.select(second, true)
	var before := members(demo)
	var history: Dictionary = demo.last_play_snapshot()
	var first_pose := first.global_transform
	var second_pose := second.global_transform
	check(not demo.play_selected(), "oversized selected group is rejected atomically")
	check(members(demo) == before and demo.flights.is_empty() and demo.played.size() == 15, "rejected group does not move a partial subset")
	check(first.global_transform.is_equal_approx(first_pose) and second.global_transform.is_equal_approx(second_pose), "rejected group does not change world poses")
	check(demo.selected_cards.size() == 2 and first.selected and second.selected, "rejected group preserves selection")
	check(demo.last_play_snapshot() == history, "rejected group preserves prior completed history")
	demo.select(first)
	check(demo.play_selected() and demo.played.size() == 16, "single card reserves last shared slot")
	demo.select(second)
	var pending_count: int = demo.flights.size()
	check(not demo.play_selected(), "pending flight reservation blocks table overflow")
	check(demo.played.size() == 16 and second in demo.hand and demo.flights.size() == pending_count, "full-table rejection preserves active flights and source card")
	check(demo.last_play_snapshot() == history, "full-table rejection does not publish unfinished play history")
	# Rejected Enter must not cancel a separate drag or settle the prior flight.
	var drag_events := {"finished": 0}
	second.drag_finished.connect(func(_card, _accepted): drag_events.finished += 1)
	second.begin_drag()
	demo.dragged = second
	demo.pressed = second
	demo.place_in_world(second, demo)
	var rejected_drag_pose := second.global_transform
	var prior_flight_pose := first.global_transform
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	demo._unhandled_input(enter)
	check(demo.dragged == second and demo.pressed == second and second.dragging, "rejected Enter preserves active drag state")
	check(drag_events.finished == 0 and second.global_transform.is_equal_approx(rejected_drag_pose), "rejected Enter neither ends nor relocates drag")
	check(demo.flights.size() == pending_count and demo.flights.has(first) and first.global_transform.is_equal_approx(prior_flight_pose), "rejected Enter does not settle or advance prior flight")
	check(demo.last_play_snapshot() == history, "rejected Enter during drag preserves prior completed history")
	check(demo.selected_cards.size() == 1 and second in demo.selected_cards, "rejected Enter preserves selected group")
	demo.cancel_drag()
	check(demo.last_play_snapshot().get("cards", []).size() == 1, "successful final slot eventually replaces history with one card")
	check_population(demo, "capacity rejection")

func test_interruption_and_direct_api(demo) -> void:
	reset_round(demo)
	var dragged_card: Card3D = demo.hand[0]
	var group_partner: Card3D = demo.hand[1]
	demo.select(dragged_card)
	demo.select(group_partner, true)
	var drag_events := {"finished": 0}
	dragged_card.drag_finished.connect(func(_card, _accepted): drag_events.finished += 1)
	dragged_card.begin_drag()
	demo.dragged = dragged_card
	demo.pressed = dragged_card
	demo.place_in_world(dragged_card, demo)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	demo._unhandled_input(enter)
	check(demo.dragged == null and demo.pressed == null and not dragged_card.dragging and drag_events.finished == 1, "accepted Enter ends active drag exactly once")
	check(demo.played.size() == 2 and demo.flights.size() == 2 and dragged_card in demo.played and group_partner in demo.played, "accepted Enter commits full selected group after drag cleanup")
	demo.settle_flights()
	check(demo.last_play_snapshot().get("cards", []).size() == 2, "accepted Enter during drag records complete group")
	reset_round(demo)
	var card: Card3D = demo.draw_card(true)
	var identity := card.get_instance_id()
	check(demo.move_card(card, &"play"), "direct move safely accepts a still-drawing card")
	check(card.get_instance_id() == identity and card in demo.played and card not in demo.hand, "direct move preserves the actual drawing instance")
	demo.settle_flights()
	check(demo.last_play_snapshot().get("cards", []).size() == 1 and demo.flights.is_empty(), "direct hand-to-play move publishes one completed play")
	check(demo.move_card(card, &"hand"), "direct return after play remains supported")
	demo.settle_flights()
	demo.layout_cards(false)
	check_hand_pose(demo, card, 0, "direct return")
	check(demo.last_play_snapshot().get("cards", []).size() == 1, "returning does not erase last play")
	reset_round(demo)
	card = demo.draw_card(true)
	demo.advance_flights(0.05)
	demo.set_view(true)
	check(demo.flights.is_empty() and demo.third_person, "view switch safely settles active draw")
	check_hand_pose(demo, card, 0, "view-switch draw")
	demo.set_view(false)
	demo.select(card)
	check(demo.play_selected(), "prepare play interrupted by seat switch")
	check(demo.set_active_seat(1), "seat switch during play succeeds")
	check(demo.flights.is_empty() and demo.selected_cards.is_empty() and demo.selected == null, "seat switch clears flights and selection")
	var snapshot: Dictionary = demo.last_play_snapshot()
	check(snapshot.get("actor") == "alice" and snapshot.get("seat") == 1, "settled history retains initiating actor across seat switch")
	check(card in demo.played and card.get_parent() == demo, "seat switch lands play on table")
	var bob_draw: Card3D = demo.draw_card(true)
	check(demo.set_active_seat(2), "seat switch during draw succeeds")
	check(demo.flights.is_empty() and bob_draw in demo.seats[1].hand and bob_draw not in demo.hand, "seat switch cannot transfer pending draw to new player")
	check_hand_pose(demo, bob_draw, 1, "seat-switch draw")
	check_population(demo, "view and seat interruptions")
	reset_round(demo)
	card = demo.hand[0]
	demo.select(card)
	demo.play_selected()
	demo.settle_flights()
	var pending: Card3D = demo.draw_card(true)
	demo.select(demo.hand[0])
	demo.reset()
	check(demo.flights.is_empty() and demo.selected_cards.is_empty() and demo.last_play_snapshot().is_empty(), "reset clears flight, selection and completed history")
	check(not is_instance_valid(card) and not is_instance_valid(pending), "reset frees old played and airborne card instances")
	demo.advance_flights(100.0)
	check(demo.played.is_empty() and demo.hand.size() == 5 and demo.total_cards() == 64, "advancing after reset cannot resurrect old cards")
	card = demo.hand[0]
	demo.select(card)
	demo.play_selected()
	demo.settle_flights()
	pending = demo.draw_card(true)
	check(demo.start_round(["new-a", "new-b", "new-c"]), "new round accepts replacement players during active draw")
	check(demo.flights.is_empty() and demo.selected_cards.is_empty() and demo.last_play_snapshot().is_empty(), "new round clears flight, selection and prior-round history")
	check(not is_instance_valid(card) and not is_instance_valid(pending), "new round frees prior live and airborne cards")
	demo.advance_flights(100.0)
	check(demo.round_mapping().values() == [1, 4, 6] and demo.total_cards() == 64 and demo.played.is_empty(), "new round remains isolated after stale-flight advance")

func test_flying_pointer_input(demo) -> void:
	reset_round(demo)
	demo.set_view(true)
	var card: Card3D = demo.draw_card(true)
	demo.advance_flights(0.10)
	await physics_frame
	await physics_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = demo.card_screen(card)
	demo._unhandled_input(press)
	check(demo.pressed != card and card not in demo.selected_cards, "pointer press cannot select or grab a flying card")
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(30, 0)
	demo._input(motion)
	check(demo.dragged != card and not card.dragging and demo.flights.has(card), "pointer motion cannot hijack active draw flight")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	demo._input(release)
	demo.settle_flights()
	check_population(demo, "flying pointer isolation")

func run() -> void:
	var demo = load("res://scenes/table_demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set_process(false)
	test_rapid_draws(demo)
	test_moving_draw_target(demo)
	test_selection(demo)
	test_group_play_and_history(demo)
	test_capacity_atomicity(demo)
	test_interruption_and_direct_api(demo)
	await test_flying_pointer_input(demo)
	print("ANIMATION TEST RESULT: %d checks, %d failures" % [checks, failures])
	demo.free()
	quit(1 if failures else 0)
