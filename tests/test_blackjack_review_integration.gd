extends SceneTree
## Independent controller, privacy and navigation regression.
const Rules = preload("res://scripts/blackjack_rules.gd")
var checks := 0
var failures := 0
func ck(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BLACKJACK UI REVIEW: " + label)
func _initialize() -> void: call_deferred("run")
func snap(g) -> String: return JSON.stringify(g.snapshot())
func rig(g, ids: Array) -> void:
	g.reset_bankroll()
	ck(g.set_next_draws(ids).ok, "UI fixture accepted")
func run() -> void:
	var session = root.get_node("CardSession")
	session.blackjack = Rules.new(4920)
	var g = session.get_blackjack()
	rig(g, [1,9,2,6,3,4]) # player 2,3 -> hit4; dealer10,7
	var scene = load("res://scenes/blackjack_game.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	await process_frame
	scene.set_process(false)
	ck(scene.game == g and g.balance == 1000, "controller owns same session model")
	scene.bet_control.value = 100
	scene._deal(); scene._deal(); scene._deal()
	ck(g.balance == 900 and g.player_hand.size() == 2 and g.round_number == 1, "repeated deal debits once")
	var hole = scene.card_nodes[g.dealer_hand[1].id]
	ck(hole.viewer_masked and not hole.face_up and hole.face_texture == null, "hole has no front texture before reveal")
	ck(not hole.public_snapshot().has("title") and not hole.data.has("rank") and not hole.data.has("suit"), "hole inspection cannot reveal rank or suit")
	ck(scene.dealer_label.text.contains("明牌 10 + 暗牌") and not scene.dealer_label.text.contains("17"), "HUD does not leak full dealer total")
	var state := snap(g)
	scene._act("hit"); scene._act("double_down")
	ck(snap(g) == state, "dealing animation blocks gameplay")
	scene.animation_left = 0
	scene._open_menu(); scene._act("hit"); scene._act("stand")
	ck(snap(g) == state and scene.paused, "pause freezes all actions")
	scene._confirm_reset()
	ck(snap(g) == state, "active round cannot reset through UI")
	scene._close_menu()
	scene._act("hit"); scene._act("hit"); scene._act("hit")
	ck(g.player_hand.size() == 3 and g.balance == 900, "repeated hit adds exactly one")
	state = snap(g)
	# Leaving mid-animation must preserve the wager and exact model, not refund.
	scene._leave()
	await process_frame; await process_frame
	ck(current_scene.scene_file_path == "res://scenes/card_lobby.tscn", "leave enters lobby")
	ck(snap(g) == state and session.get_blackjack() == g, "leave preserves live wager without refund")
	ck(change_scene_to_file("res://scenes/blackjack_game.tscn") == OK, "reentry succeeds")
	await process_frame; await process_frame
	scene = current_scene; scene.set_process(false)
	ck(scene.game == g and snap(g) == state and g.balance == 900, "reentry resumes same round without bonus")
	hole = scene.card_nodes[g.dealer_hand[1].id]
	ck(hole.face_texture == null and hole.viewer_masked, "reentry still masks hole")
	scene._act("stand")
	ck(g.phase == "dealer" and g.dealer_revealed and not hole.viewer_masked and hole.face_texture != null, "stand reveals same physical hole node")
	for step in 10:
		scene._process(1.0)
		if g.phase == "settled": break
	ck(g.phase == "settled" and g.balance == 900, "AI reaches expected loss settlement")
	state = snap(g)
	for step in 4: scene._process(1.0)
	ck(snap(g) == state, "AI post-settlement frames never settle twice")
	# Explicit reset modal is cancellable and applies only after confirmation.
	scene.animation_left = 0
	scene._confirm_reset()
	ck(scene.modal.visible and g.balance == 900, "reset confirmation has no immediate effect")
	scene._close_menu()
	ck(g.balance == 900, "cancel reset leaves money unchanged")
	scene._confirm_reset()
	for node in scene.modal_col.get_children():
		if node is Button and node.text == "确认重置为 1000": node.pressed.emit()
	ck(g.balance == 1000 and g.phase == "betting", "confirmed reset replaces balance exactly")
	# Double keyboard/button inputs in the same frame cannot add a second card.
	rig(g,[4,9,5,6,8]); scene._sync(false); scene.bet_control.value=100
	scene._deal(); scene.animation_left=0
	scene._act("double_down");scene._act("double_down");scene._act("hit")
	ck(g.balance==800 and g.bet==200 and g.player_hand.size()==3 and g.phase=="dealer", "UI double strictly one card and one extra stake")
	for step in 10:
		scene._process(1.0)
		if g.phase=="settled":break
	ck(g.balance==1200 and g.result.net==200, "UI double settled correctly")
	scene.animation_left=0;scene._act("next_round");scene._act("next_round")
	ck(g.balance==1200 and g.phase=="betting", "repeated next preserves winnings")
	print("INDEPENDENT BLACKJACK UI REVIEW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
