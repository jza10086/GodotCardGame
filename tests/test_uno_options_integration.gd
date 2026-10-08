extends SceneTree
## Run: godot --headless --path . --script tests/test_uno_options_integration.gd
## One reusable scene exercises the real controls and mixed human/bot controller.
const RULES = preload("res://scripts/uno_rules.gd")
const OPTION_KEYS := ["continuous_draw", "jump_in", "stacking", "forbid_last_wild"]

var checks: int = 0
var failures: int = 0
var completed_rounds: int = 0
var observed_phases: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func options_for(mask: int) -> Dictionary:
	var options: Dictionary = {}
	for index in OPTION_KEYS.size():
		options[OPTION_KEYS[index]] = bool(mask & (1 << index))
	return options


func options_match(actual: Dictionary, expected: Dictionary) -> bool:
	for key in OPTION_KEYS:
		if bool(actual.get(key, false)) != bool(expected.get(key, false)):
			return false
	return true


func snapshot(g) -> String:
	return JSON.stringify([
		g.hands, g.draw_pile, g.discard_pile, g.current_player, g.direction,
		g.active_color, g.phase, g.pending_draw, g.pending_play, g.drawn_card_id,
		g.forced_play, g.options, g.state_version, g.uno_player, g.uno_announced,
		g.winner, g.pending_winner, g.score,
	])


func invariant(demo, label: String) -> void:
	var g = demo.game
	var ids: Dictionary = {}
	for card in g.draw_pile + g.discard_pile:
		ids[card.id] = true
	for hand in g.hands:
		for card in hand:
			ids[card.id] = true
	check(g.total_cards() == 108 and ids.size() == 108, label + " conserves 108 unique model cards")
	check(demo.total_cards() == 108 and demo._card_nodes.size() == 108, label + " retains 108 presenter cards")
	check(g.current_player >= 0 and g.current_player < g.hands.size(), label + " has a valid active seat")
	check(demo.active_seat == 0, label + " keeps the human seat fixed")
	var private_hands: bool = true
	for player in range(1, g.hands.size()):
		for node in demo.player_hand(player):
			if not node.viewer_masked or node.public_snapshot().has("title") or demo.inspection_snapshot(node).has("title"):
				private_hands = false
	check(private_hands, label + " masks all opponent hands and inspection snapshots")


func button_named(node: Node, caption: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == caption:
			return child
		var found: Button = button_named(child, caption)
		if found != null:
			return found
	return null


func send_key(demo, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	demo._input(event)
	demo._unhandled_input(event)


func take_card(g, color: String, value: String) -> Dictionary:
	for index in g.draw_pile.size():
		var card: Dictionary = g.draw_pile[index]
		if card.color == color and card.value == value:
			return g.draw_pile.pop_at(index)
	check(false, "fixture has available " + color + ":" + value)
	return {}


func fixture(demo, options: Dictionary, hand_specs: Array, active: int = 0) -> void:
	demo._start_game(hand_specs.size(), false, options)
	demo.choosing = false
	demo.pending_card_id = null
	demo.paused = false
	demo.modal.hide()
	var g = demo.game
	g.draw_pile = RULES.build_deck()
	g.discard_pile = [take_card(g, "red", "5")]
	g.hands = []
	for specs in hand_specs:
		var hand: Array = []
		for spec in specs:
			hand.append(take_card(g, spec[0], spec[1]))
		g.hands.append(hand)
	g.current_player = active
	g.direction = 1
	g.active_color = "red"
	g.phase = "playing"
	g.winner = -1
	g.score = 0
	g.finish_reason = ""
	g.drawn_card_id = -1
	g.pending_draw = 0
	g.pending_winner = -1
	g.challenge_target = -1
	g.challenge_offender = -1
	g.uno_player = -1
	g.uno_announced = false
	g.forced_play = false
	g.pending_play = {}
	g._stack_value = ""
	demo.jump_clocks.clear()
	demo.seen_reaction_card = -1
	demo._sync(false)
	demo.settle_flights()
	demo._refresh_action_lock()


func test_settings(demo) -> void:
	demo.launch_seed = 33
	demo._start_game(4)
	if demo.choosing:
		demo._choose_color("red")
	demo.settle_flights()
	demo._open_pause()
	check(demo.option_checks.size() == 4, "menu exposes all four independent options")
	for key in OPTION_KEYS:
		check(not demo.option_checks[key].button_pressed, key + " defaults off")
	var before: String = snapshot(demo.game)
	for key in OPTION_KEYS:
		demo.option_checks[key].button_pressed = true
	check(snapshot(demo.game) == before and options_match(demo.round_options, {}), "editing menu checkboxes cannot mutate an active round")
	demo._close_pause()
	check(snapshot(demo.game) == before, "Continue preserves every model state field")
	demo._open_pause()
	for key in OPTION_KEYS:
		check(not demo.option_checks[key].button_pressed, "reopening discards unapplied " + key)
	demo._close_pause()
	for mask in 16:
		if demo.choosing:
			demo._choose_color("red")
		demo._open_pause()
		var expected: Dictionary = options_for(mask)
		for key in OPTION_KEYS:
			demo.option_checks[key].button_pressed = expected[key]
		demo.count_option.select(mask % 7)
		var restart: Button = button_named(demo.modal_box, "重新开始")
		check(restart != null, "menu has a restart control")
		if restart != null:
			restart.pressed.emit()
		check(demo.players.size() == 2 + mask % 7, "restart applies selected player count for mask %d" % mask)
		check(options_match(demo.round_options, expected) and options_match(demo.game.options, expected), "restart applies independent option mask %d to controller and model" % mask)
		check(demo.round_count == 1, "explicit restart resets match round count")
		invariant(demo, "menu mask %d" % mask)
		await process_frame
	# Exercise the actual result-button callback, including safe modal rebuilding.
	if demo.choosing:
		demo._choose_color("red")
	demo.settle_flights()
	demo.game.phase = "finished"
	demo.game.winner = 0
	demo.game.score = 17
	demo.paused = false
	demo._show_result()
	var next_round: Button = button_named(demo.modal_box, "下一局")
	check(next_round != null, "completed round exposes Next Round")
	if next_round != null:
		next_round.pressed.emit()
	check(options_match(demo.round_options, options_for(15)) and options_match(demo.game.options, options_for(15)), "Next Round preserves all selected options")
	check(demo.round_count == 2 and demo.game.score == 0, "Next Round resets round scoring and increments round")
	await process_frame
	check(not demo.paused, "Next Round resumes the controller after the pressed callback")
	if demo.choosing:
		demo._choose_color("red")
	demo.settle_flights()
	demo.game.phase = "finished"
	demo.game.winner = 0
	demo.game.score = 500
	demo.paused = false
	demo._show_result()
	check(button_named(demo.modal_box, "新比赛") == null, "500 aggregate points do not trigger an obsolete championship")
	var next_again: Button = button_named(demo.modal_box, "下一局")
	check(next_again != null, "every result retains Next Round")
	if next_again != null:
		next_again.pressed.emit()
	check(demo.game.score == 0 and demo.round_count == 3, "each subsequent round has independent scoring")
	var supplied: Dictionary = options_for(15)
	demo._start_game(3, false, supplied)
	supplied["jump_in"] = false
	check(demo.round_options.jump_in and demo.game.options.jump_in, "starting a round copies caller option values")


func test_compulsory_color(demo) -> void:
	for value in ["wild", "draw_four"]:
		fixture(demo, {"continuous_draw": true}, [
			[["blue", "1"], ["green", "8"]],
			[["yellow", "2"], ["blue", "3"]],
			[["green", "3"], ["yellow", "8"]],
		])
		var incoming: Dictionary = take_card(demo.game, "wild", value)
		var miss: Dictionary = take_card(demo.game, "yellow", "9")
		demo.game.draw_pile.append(incoming)
		demo.game.draw_pile.append(miss)
		demo._sync(false)
		demo._human_draw()
		check(demo.choosing and demo.modal.visible and demo.game.forced_play, "continuous drawn " + value + " opens a compulsory color modal")
		check(demo.game.hands[0].size() == 4 and demo.pending_card_id == incoming.id, "continuous draw reaches the first playable " + value)
		check(button_named(demo.modal_box, "取消出牌") == null and not demo.pass_action.visible, "compulsory " + value + " has no Cancel or Keep action")
		var hint: String = demo.modal_box.get_child(1).text
		check(("+4" in hint and "质疑" in hint) if value == "draw_four" else (not "+4" in hint and not "质疑" in hint), "color picker shows challenge guidance only for " + value)
		check("必须打出" in demo.modal_box.get_child(2).text, "compulsory " + value + " retains its mandatory-play guidance")
		var before: String = snapshot(demo.game)
		demo.settle_flights()
		demo._cancel_color()
		send_key(demo, KEY_ESCAPE)
		send_key(demo, KEY_D)
		demo._human_pass()
		demo._open_pause()
		check(demo.choosing and demo.modal.visible and snapshot(demo.game) == before, "Escape, draw, pass and menu cannot dismiss compulsory " + value)
		var blue: Button = button_named(demo.modal_box, "蓝")
		check(blue != null, "compulsory picker exposes a blue choice")
		if blue != null:
			blue.pressed.emit()
		check(not demo.choosing and not demo.modal.visible and not demo.game.forced_play, "selecting a color closes compulsory " + value)
		check(demo.game.top_card().id == incoming.id and demo.game.active_color == "blue", "color choice actually plays the compulsory " + value)
		invariant(demo, "compulsory " + value)
		await process_frame
	# Continuous numeric draw is committed without a separate pass/play choice.
	fixture(demo, {"continuous_draw": true}, [
		[["blue", "1"], ["green", "8"]], [["yellow", "2"], ["blue", "3"]],
	])
	var red: Dictionary = take_card(demo.game, "red", "7")
	demo.game.draw_pile.append(red)
	demo._sync(false)
	demo._human_draw()
	check(demo.game.top_card().id == red.id and demo.game.current_player == 1 and not demo.choosing, "continuous drawn number auto-plays through the controller")
	invariant(demo, "continuous number")
	fixture(demo, {"stacking": true}, [
		[["wild", "draw_four"], ["green", "8"]], [["yellow", "2"], ["blue", "3"]],
	])
	demo._human_card(demo.game.hands[0][0].id)
	check("不进行质疑" in demo.modal_box.get_child(1).text, "stacking +4 picker explains that challenge is disabled")
	demo._cancel_color()
	demo._show_color(null)
	check(not "+4" in demo.modal_box.get_child(1).text and not "质疑" in demo.modal_box.get_child(1).text, "initial color picker has no unrelated +4 challenge guidance")


func test_jump_input(demo) -> void:
	fixture(demo, {"jump_in": true}, [
		[["red", "7"], ["green", "8"]],
		[["red", "7"], ["blue", "2"]],
		[["green", "3"], ["yellow", "8"]],
	], 1)
	demo._bot_act()
	demo.settle_flights()
	demo._refresh_action_lock()
	var jump_id: int = demo.game.hands[0][0].id
	check(demo.game.current_player == 2 and demo.game.jump_in_indices(0) == [0], "human can intercept a bot while another bot owns the turn")
	check(not demo.interactions_blocked and demo.card_node(jump_id).selected, "out-of-turn human jump is enabled and highlighted")
	demo._human_card(jump_id)
	check(demo.game.top_card().id == jump_id and demo.game.hands[0].size() == 1 and demo.game.current_player == 1, "human card input dispatches an out-of-turn jump")
	invariant(demo, "out-of-turn jump")
	# An accepted competing action can arrive after the displayed snapshot.
	fixture(demo, {"jump_in": true}, [
		[["red", "7"], ["green", "8"]],
		[["red", "7"], ["blue", "2"]],
		[["green", "3"], ["yellow", "8"]],
	], 1)
	var old_rendered_version: int = demo.rendered_version
	var competing: Dictionary = demo.game.play_card(1, 0, "", true)
	check(competing.ok and demo.game.state_version != old_rendered_version, "competing accepted play advances beyond the rendered snapshot")
	var authoritative: String = snapshot(demo.game)
	var stale_jump_id: int = demo.game.hands[0][0].id
	demo._human_card(stale_jump_id)
	check(snapshot(demo.game) == authoritative, "stale rendered jump is rejected without gameplay mutation")
	check(demo.rendered_version == demo.game.state_version, "stale request rejection refreshes the authoritative rendered version")
	invariant(demo, "stale jump refresh")
	demo._human_card(stale_jump_id)
	check(demo.game.top_card().id == stale_jump_id and demo.game.hands[0].size() == 1, "fresh retry can jump after a stale view rejection")
	fixture(demo, {"jump_in": true}, [
		[["red", "7"], ["red", "7"], ["green", "8"]],
		[["blue", "2"], ["yellow", "8"]],
		[["green", "3"], ["yellow", "2"]],
	])
	var first_id: int = demo.game.hands[0][0].id
	var second_id: int = demo.game.hands[0][1].id
	demo._human_card(first_id)
	demo.settle_flights()
	demo._refresh_action_lock()
	check(demo.game.current_player == 1 and demo.game.jump_in_indices(0) == [0], "human can self-intercept a duplicate just played")
	demo._human_card(second_id)
	check(demo.game.top_card().id == second_id and demo.game.hands[0].size() == 1, "self-jump accepts the second physical card")
	check(demo.game.discard_pile[-2].id == first_id, "self-jump retains the replaced physical discard")
	invariant(demo, "self-jump")
	# No elapsed-time timeout may commit a human-owned reaction window.
	fixture(demo, {"jump_in": true}, [
		[["blue", "1"], ["green", "8"]],
		[["yellow", "2"], ["blue", "3"]],
		[["red", "7"], ["yellow", "8"]],
	], 2)
	demo._bot_act()
	demo.settle_flights()
	var before: String = snapshot(demo.game)
	demo._process(30.0)
	check(not demo.game.pending_play.is_empty() and snapshot(demo.game) == before, "jump opportunity survives a long human thinking interval")
	demo._human_draw()
	check(demo.game.pending_play.is_empty() and demo.game.phase == "drawn", "an actual accepted human draw settles the jump opportunity")
	invariant(demo, "reaction settled by draw")
	for mode in 3:
		if mode == 1:
			demo.toggle_view()
		if mode == 2:
			demo.toggle_top_down()
		invariant(demo, "jump privacy camera %d" % mode)


func test_current_turn_jump_mode(demo) -> void:
	for use_jump in [false, true]:
		fixture(demo, {"jump_in": true, "stacking": true}, [
			[["red", "draw_two"], ["green", "8"]],
			[["yellow", "2"], ["blue", "3"]],
			[["red", "draw_two"], ["yellow", "8"]],
		], 2)
		demo._bot_act()
		demo.settle_flights()
		demo._refresh_action_lock()
		check(demo.game.current_player == 0 and demo.game.pending_draw == 2 and demo.game.phase == "stacking", "same-color +2 fixture gives the human a pending stack")
		check(demo.jump_check.visible and not demo.jump_check.disabled and not demo.jump_check.button_pressed, "current-turn exact match exposes an unchecked jump opt-in")
		var card_id: int = demo.game.hands[0][0].id
		demo.jump_check.button_pressed = use_jump
		demo._human_card(card_id)
		check(demo.game.pending_draw == (2 if use_jump else 4), "current-turn +2 %s" % ("opted jump replaces the prior contribution" if use_jump else "default play adds to the existing debt"))
		check(demo.game.top_card().id == card_id and demo.game.current_player == 1, "current-turn +2 action consumes the card and advances from the human")
		check(not demo.jump_check.button_pressed, "accepted current-turn +2 clears the one-action jump opt-in")
		invariant(demo, "current-turn +2 jump=%s" % use_jump)
		demo.jump_check.button_pressed = true
		demo._start_game(3, false, {"jump_in": true, "stacking": true})
		check(not demo.jump_check.button_pressed, "restart clears a previously checked jump mode")
	# In two-player play Reverse previews another turn for its own actor.
	# Opting into a self-jump must replace that reversal, rather than flip twice.
	fixture(demo, {"jump_in": true}, [
		[["red", "reverse"], ["red", "reverse"], ["green", "8"]],
		[["yellow", "2"], ["blue", "3"]],
	])
	var original: int = demo.game.hands[0][0].id
	var duplicate: int = demo.game.hands[0][1].id
	demo._human_card(original)
	demo.settle_flights()
	demo._refresh_action_lock()
	check(demo.game.current_player == 0 and demo.game.direction == -1 and demo.jump_check.visible, "two-player Reverse exposes current-turn self-jump")
	demo.jump_check.button_pressed = true
	demo._human_card(duplicate)
	check(demo.game.top_card().id == duplicate and demo.game.direction == -1 and demo.game.current_player == 0, "opted current-turn self-jump replaces rather than doubles Reverse")
	check(demo.game.discard_pile[-2].id == original and demo.game.hands[0].size() == 1 and not demo.jump_check.button_pressed, "self-jump retains both discards and clears jump mode")
	invariant(demo, "current-turn Reverse self-jump")


func test_penalty_keyboard(demo) -> void:
	for use_stacking in [false, true]:
		fixture(demo, {"jump_in": true, "stacking": use_stacking}, [
			[["blue", "1"], ["green", "8"]],
			[["yellow", "2"], ["blue", "3"]],
			[["red", "draw_two"], ["yellow", "8"]],
		], 2)
		demo._bot_act()
		demo.settle_flights()
		demo._refresh_action_lock()
		var expected_phase: String = "stacking" if use_stacking else "pending_effect"
		check(demo.game.phase == expected_phase and demo.game.current_player == 0 and demo.game.pending_draw == 2, "penalty fixture enters " + expected_phase)
		check(not demo.draw_action.disabled and demo.penalty_action.visible, expected_phase + " exposes both penalty controls")
		var before_count: int = demo.game.hands[0].size()
		send_key(demo, KEY_D)
		check(demo.game.hands[0].size() == before_count + 2 and demo.game.pending_draw == 0, "D accepts exactly the pending penalty in " + expected_phase)
		check(demo.game.current_player == 1 and demo.game.phase == "playing" and demo.game.pending_play.is_empty(), "D completes and skips the penalized turn in " + expected_phase)
		var after: String = snapshot(demo.game)
		send_key(demo, KEY_D)
		check(snapshot(demo.game) == after, "repeated D cannot draw again after " + expected_phase)
		invariant(demo, "penalty key " + expected_phase)


func test_last_wild_controller(demo) -> void:
	for use_jump in [false, true]:
		fixture(demo, {"forbid_last_wild": true, "jump_in": use_jump}, [
			[["red", "7"], ["wild", "wild"]],
			[["red", "2"], ["blue", "3"]],
			[["green", "3"], ["yellow", "8"]],
		])
		var safe_draw: Dictionary = take_card(demo.game, "blue", "6")
		demo.game.draw_pile.append(safe_draw)
		demo._sync(false)
		demo.announce_check.button_pressed = true
		demo._human_card(demo.game.hands[0][0].id)
		if use_jump:
			check(demo.game.hands[0].size() == 1 and not demo.game.pending_play.is_empty(), "last-wild draw remains deferred while an interception is possible")
			demo.settle_flights()
			demo._bot_act()
		check(demo.game.hands[0].size() == 2 and demo._find_card(0, safe_draw.id) >= 0, "settled sole wild forces exactly one physical draw, jump=%s" % use_jump)
		check(demo.game.uno_player != 0 and not demo.uno_action.visible, "forced last-wild draw clears the human UNO affordance, jump=%s" % use_jump)
		invariant(demo, "last wild jump=%s" % use_jump)
	# A singleton wild cannot even open a playable color picker while cards remain.
	fixture(demo, {"forbid_last_wild": true}, [
		[["wild", "draw_four"]], [["red", "2"], ["blue", "3"]],
	])
	var before: String = snapshot(demo.game)
	demo._human_card(demo.game.hands[0][0].id)
	check(not demo.choosing and snapshot(demo.game) == before, "forbidden final +4 input cannot start a color modal or mutate the round")
	demo._human_draw()
	check(demo.game.hands[0].size() == 2 and demo.game.phase == "drawn", "forbidden final wild still permits the required draw")
	invariant(demo, "forbidden final wild input")


func play_human_step(demo, step: int) -> void:
	var g = demo.game
	if demo.choosing:
		demo._choose_color(demo._bot_color(0))
		return
	match g.phase:
		"choose_color":
			demo._show_color(null)
			demo._choose_color(demo._bot_color(0))
		"challenge":
			demo._challenge(step % 2 == 0)
		"pending_effect":
			demo._human_draw()
		_:
			var legal: Array = g.legal_indices(0)
			if not legal.is_empty():
				demo.announce_check.button_pressed = true
				demo._human_card(g.hands[0][legal[0]].id)
				if demo.choosing:
					demo._choose_color(demo._bot_color(0))
			elif g.phase == "drawn":
				demo._human_pass()
			else:
				demo._human_draw()


func test_combination_rounds(demo) -> void:
	for count in [2, 8]:
		for mask in 16:
			var seed_value: int = count * 1009 + mask * 31
			demo.launch_seed = seed_value
			demo._start_game(count, false, options_for(mask))
			var steps: int = 0
			var stalls: int = 0
			var label: String = "count=%d mask=%d seed=%d" % [count, mask, seed_value]
			while demo.game.phase != "finished" and steps < 2500:
				if demo.paused:
					demo._close_pause()
				demo.settle_flights()
				demo._refresh_action_lock()
				var g = demo.game
				observed_phases[g.phase] = true
				var before_version: int = g.state_version
				if g.current_player == 0:
					play_human_step(demo, steps)
				elif not g.jump_in_indices(0).is_empty():
					demo.announce_check.button_pressed = true
					demo._human_card(g.hands[0][g.jump_in_indices(0)[0]].id)
				else:
					# The real scheduler arbitrates jumps and accepted bot actions.
					# Never force-commit a pending effect based on elapsed time.
					demo._process(3.0)
				steps += 1
				stalls = stalls + 1 if g.state_version == before_version else 0
				invariant(demo, label + " step=%d" % steps)
				check(options_match(g.options, options_for(mask)), label + " keeps round options fixed")
				if stalls >= 4:
					check(false, "%s controller stalled at step=%d phase=%s player=%d forced=%s pending=%s" % [label, steps, g.phase, g.current_player, g.forced_play, str(g.pending_play)])
					break
				if steps % 16 == 0:
					await process_frame
			check(demo.game.phase == "finished", label + " mixed human/bot round completes")
			if demo.game.phase == "finished":
				completed_rounds += 1
				check(demo.paused and demo.modal.visible, label + " shows the result modal")
				if demo.game.winner >= 0:
					check(demo.game.hands[demo.game.winner].is_empty(), label + " winner has no cards")
					var expected_score: int = 0
					for hand in demo.game.hands:
						for card in hand:
							expected_score += RULES.card_points(card)
					check(demo.game.score == expected_score, label + " final score matches remaining physical cards")
			print("Optional controller ", label, " finished=", demo.game.phase == "finished", " actions=", steps)
			await process_frame
	check(completed_rounds == 32, "all 16 combinations complete at both 2 and 8 players")
	check(observed_phases.has("stacking") and observed_phases.has("pending_effect") and observed_phases.has("challenge"), "mixed rounds cover both optional penalty phases and classic challenge")


func run() -> void:
	var demo = load("res://scenes/uno_game.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set_process(false)
	await test_settings(demo)
	await test_compulsory_color(demo)
	test_jump_input(demo)
	test_current_turn_jump_mode(demo)
	test_penalty_keyboard(demo)
	test_last_wild_controller(demo)
	await test_combination_rounds(demo)
	demo.queue_free()
	await process_frame
	print("UNO OPTIONAL INTEGRATION CHECKS ", checks, " FAILURES ", failures, " COMPLETED ROUNDS ", completed_rounds)
	quit(1 if failures else 0)
