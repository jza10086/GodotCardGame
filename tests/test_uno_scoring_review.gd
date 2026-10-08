extends SceneTree
## Independent boundary and randomized review of configurable deal and penalty scoring.
const Rules = preload("res://scripts/uno_rules.gd")
var checks := 0
var failures := 0
var completed := 0
var actions := 0
var first_values: Dictionary = {}

func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SCORING REVIEW: " + label)

func opts(mask: int) -> Dictionary:
	return {"continuous_draw": bool(mask & 1), "jump_in": bool(mask & 2), "stacking": bool(mask & 4), "forbid_last_wild": bool(mask & 8)}

func expected_points(card: Dictionary) -> int:
	match card.value:
		"wild": return 20
		"draw_four": return 40
		"skip", "reverse", "draw_two": return 10
	return int(card.value)

func conserved(g) -> bool:
	var ids: Dictionary = {}
	for card in g.draw_pile + g.discard_pile:
		ids[card.id] = true
	for hand in g.hands:
		for card in hand:
			ids[card.id] = true
	return g.total_cards() == 108 and ids.size() == 108

func snapshot(g) -> String:
	return JSON.stringify([g.hands, g.draw_pile, g.discard_pile, g.phase, g.current_player, g.direction, g.state_version, g.options])

func start(g, count: int, seed_value: int, mask: int, hand_count: int) -> Dictionary:
	return g.start_game(count, seed_value, opts(mask), hand_count)

func _initialize() -> void:
	for card in Rules.build_deck():
		ck(Rules.card_points(card) == expected_points(card), "card value " + str(card))
	test_exhausted_wild_scoring()
	var rng := RandomNumberGenerator.new()
	rng.seed = 381620
	for count in range(2, 9):
		var limit: int = int(107 / count)
		for mask in 16:
			for hand_count in [1, 7, limit]:
				var g = Rules.new()
				var label: String = "%d players/%d mask/%d cards" % [count, mask, hand_count]
				var result: Dictionary = start(g, count, count * 1199 + mask * 173 + hand_count, mask, hand_count)
				ck(result.ok, label + " starts")
				if not result.ok: continue
				for hand in g.hands:
					ck(hand.size() == hand_count, label + " exact configured deal")
				ck(g.draw_pile.size() == 107 - count * hand_count and g.discard_pile.size() == 1, label + " deal then one starter")
				ck(g.current_player == 0 and g.direction == 1 and g.pending_draw == 0 and g.pending_play.is_empty(), label + " starter does not affect turn or debt")
				first_values[g.top_card().value] = true
				ck(g.phase == ("choose_color" if g.top_card().color == "wild" else "playing"), label + " initial phase")
				ck(conserved(g), label + " deal conservation")
				var before: String = snapshot(g)
				ck(not start(g, count, 7, mask, limit + 1).ok and snapshot(g) == before, label + " excessive deal rejected atomically")
				ck(not start(g, count, 7, mask, 0).ok and snapshot(g) == before, label + " zero deal rejected atomically")
				var steps := 0
				while g.phase != "finished" and steps < 10000:
					var p: int = g.current_player
					var jumped := false
					if not g.pending_play.is_empty() and rng.randf() < 0.35:
						for j in count:
							var jumps: Array = g.jump_in_indices(j)
							if not jumps.is_empty():
								result = g.jump_in(j, jumps[0], true, g.state_version)
								jumped = true
								break
					if not jumped:
						match g.phase:
							"choose_color": result = g.choose_initial_color(p, "red")
							"challenge": result = g.resolve_challenge(p, rng.randf() < 0.5)
							"pending_effect": result = g.accept_pending(p)
							"stacking":
								var legal: Array = g.legal_indices(p)
								result = g.play_card(p, legal[0], "blue", true) if not legal.is_empty() else g.accept_stack(p)
							_:
								var legal: Array = g.legal_indices(p)
								if not legal.is_empty(): result = g.play_card(p, legal[rng.randi_range(0, legal.size() - 1)], Rules.COLORS[rng.randi_range(0, 3)], true)
								elif g.phase == "drawn": result = g.pass_draw(p)
								else: result = g.draw_card(p)
					steps += 1
					actions += 1
					ck(result.ok, label + " legal progression: " + str(result))
					ck(conserved(g), label + " physical conservation")
					if not result.ok: break
				ck(g.phase == "finished", label + " completes")
				if g.phase == "finished":
					completed += 1
					verify_scores(g, label)
		print("Scoring boundary matrix complete for ", count, " players")
	for value in ["wild", "draw_four", "skip", "reverse", "draw_two"]:
		ck(first_values.has(value), "starter coverage " + value)
	print("INDEPENDENT SCORING REVIEW: %d checks, %d failures, %d completed rounds, %d actions" % [checks, failures, completed, actions])
	call_deferred("run_ui")

func verify_scores(g, label: String) -> void:
	var expected: Array[int] = []
	for hand in g.hands:
		var points := 0
		for card in hand: points += expected_points(card)
		expected.append(points)
	var standings: Array = g.round_standings()
	ck(standings.size() == expected.size(), label + " every player ranked")
	var total := 0
	var previous := -1
	var seen := {}
	for entry in standings:
		var p: int = entry.player
		ck(not seen.has(p) and p >= 0 and p < expected.size(), label + " each player once")
		seen[p] = true
		ck(entry.points == expected[p] and entry.cards == g.hands[p].size(), label + " own remaining cards scored")
		ck(entry.points >= previous, label + " low scores rank first")
		previous = entry.points
		var expected_rank := 1
		for points in expected:
			if points < expected[p]: expected_rank += 1
		ck(entry.rank == expected_rank, label + " ties share competition rank")
		total += entry.points
	ck(g.score == total, label + " diagnostic total is not winner credit")

func button_named(node: Node, title: String):
	if node is Button and node.text == title: return node
	for child in node.get_children():
		var found = button_named(child, title)
		if found != null: return found
	return null

func clear_initial(demo) -> void:
	if demo.choosing: demo._choose_color("blue")
	demo.settle_flights()

func run_ui() -> void:
	var demo = load("res://scenes/uno_game.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set_process(false)
	for count in range(2, 9):
		demo._start_game(count, false, opts(15), int(107 / count))
		clear_initial(demo)
		var before: String = snapshot(demo.game)
		demo._open_pause()
		ck(demo.hand_size_option.value == int(107 / count), "menu shows extreme configured hand size")
		demo.hand_size_option.value = 1
		demo.option_checks.stacking.button_pressed = false
		button_named(demo.modal_box, "继续游戏").pressed.emit()
		ck(snapshot(demo.game) == before and demo.round_hand_size == int(107 / count) and demo.round_options.stacking, "continue ignores pending setting edits")
		demo._open_pause()
		ck(demo.hand_size_option.value == int(107 / count) and demo.option_checks.stacking.button_pressed, "reopened menu restores actual settings")
		# Change from 2-player 53-card maximum to 8-player 13-card maximum.
		demo.count_option.select(0)
		demo.count_option.item_selected.emit(0)
		demo.hand_size_option.value = 53
		demo.count_option.select(6)
		demo.count_option.item_selected.emit(6)
		ck(demo.hand_size_option.max_value == 13 and demo.hand_size_option.value == 13, "player count clamps initial deal to actual resources")
		# Commit typed text without an Enter key before Restart.
		demo.hand_size_option.get_line_edit().text = "11"
		button_named(demo.modal_box, "重新开始").pressed.emit()
		ck(demo.players.size() == 8 and demo.round_hand_size == 11 and demo.game.initial_hand_size == 11, "restart applies freshly typed count")
		ck(demo.round_count == 1 and demo.round_options.stacking, "restart resets round counter and keeps selected options")
		clear_initial(demo)
		for hand in demo.game.hands: ck(hand.size() == 11, "restart physical hand size")
		# A result above the retired 500-point threshold must still offer Next Round.
		demo.game.phase = "finished"
		demo.game.score = 999
		demo.game.winner = -1
		demo.paused = false
		demo._show_result()
		ck(button_named(demo.modal_box, "下一局") != null and button_named(demo.modal_box, "新比赛") == null, "high diagnostic total never selects legacy championship")
		button_named(demo.modal_box, "人数 / 规则菜单").pressed.emit()
		demo.hand_size_option.value = 2
		demo.option_checks.stacking.button_pressed = false
		button_named(demo.modal_box, "继续游戏").pressed.emit()
		ck(demo.game.phase == "finished" and demo.paused, "result menu Continue returns to result")
		button_named(demo.modal_box, "下一局").pressed.emit()
		ck(demo.round_count == 2 and demo.round_hand_size == 11 and demo.game.initial_hand_size == 11 and demo.game.options.stacking, "next round preserves applied settings, not dismissed menu edits")
		ck(demo.game.score == 0 and demo.game.winner == -1, "next round resets result")
		clear_initial(demo)
		await process_frame
	# Controlled equal scores including a zero-card winner and a zero-valued card.
	demo._start_game(4)
	clear_initial(demo)
	demo.game.hands = [[], [{"id": 1000, "color": "red", "value": "0"}], [{"id": 1001, "color": "wild", "value": "wild"}], [{"id": 1002, "color": "red", "value": "skip"}, {"id": 1003, "color": "blue", "value": "reverse"}]]
	demo.game.phase = "finished"
	demo.game.winner = 0
	demo.game.score = 40
	verify_scores(demo.game, "zero score and action ties")
	var lines: Array = demo._score_lines()
	ck(lines.size() == 4 and lines[0].begins_with("并列第 1 名") and lines[1].begins_with("并列第 1 名") and lines[2].begins_with("并列第 3 名") and lines[3].begins_with("并列第 3 名"), "UI shows same score as tied rank regardless of hand count")
	demo.queue_free()
	await process_frame
	print("INDEPENDENT SCORING REVIEW FINAL: %d checks, %d failures, %d rounds, %d actions" % [checks, failures, completed, actions])
	quit(1 if failures else 0)

func test_exhausted_wild_scoring() -> void:
	# No drawable cards and forbidden sole wilds are a legitimate exhausted round.
	for mask in [8, 9, 10, 11, 12, 13, 14, 15]:
		var g = Rules.new()
		g.start_game(2, 9, opts(mask), 1)
		g.hands = [[{"id": 1001, "color": "wild", "value": "wild"}], [{"id": 1002, "color": "wild", "value": "draw_four"}]]
		g.draw_pile = []
		g.discard_pile = [{"id": 1003, "color": "red", "value": "0"}]
		g.phase = "playing"
		g.current_player = 0
		g.active_color = "red"
		for p in 2:
			ck(g.draw_card(p).ok and g.pass_draw(p).ok, "exhausted forbidden wild advances finitely")
		ck(g.phase == "finished" and g.winner == -1 and g.finish_reason == "stalemate", "exhausted wilds settle without phantom finisher")
		ck(g.score == 60, "exhausted round includes both wildcard penalties")
		verify_scores(g, "exhausted wild penalty ranking")
