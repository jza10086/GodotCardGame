extends SceneTree
## Run: godot --headless --path . --script tests/test_uno_rules.gd
const Rules = preload("res://scripts/uno_rules.gd")

var checks: int = 0
var failures: int = 0
var next_id: int = 1000


func _initialize() -> void:
	test_deck_and_start()
	test_matching_and_invalid_commands()
	test_draw_and_pass()
	test_action_cards()
	test_draw_four_challenges()
	test_uno_window()
	test_recycling_and_stalemate()
	test_finishing_and_scoring()
	test_seeded_complete_rounds()
	print("UNO rules: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func card(color: String, value: String) -> Dictionary:
	next_id += 1
	return {"id": next_id, "color": color, "value": value}


func fixture(player_count: int = 3):
	var game = Rules.new()
	game.start_game(player_count, 1)
	game.hands = []
	for _player in player_count:
		game.hands.append([card("blue", "7"), card("green", "8")])
	game.draw_pile = []
	for index in 30:
		game.draw_pile.append(card("yellow", str(index % 10)))
	game.discard_pile = [card("red", "5")]
	game.current_player = 0
	game.direction = 1
	game.active_color = "red"
	game.phase = "playing"
	game.winner = -1
	game.score = 0
	game.pending_winner = -1
	game.pending_draw = 0
	game.challenge_target = -1
	game.challenge_offender = -1
	game.uno_player = -1
	game.uno_announced = false
	return game


func snapshot(game) -> String:
	return JSON.stringify([
		game.hands, game.draw_pile, game.discard_pile, game.current_player,
		game.direction, game.active_color, game.phase, game.winner, game.score,
		game.pending_winner, game.pending_draw, game.drawn_card_id,
		game.challenge_target, game.challenge_offender, game.uno_player, game.uno_announced,
	])


func unique_and_conserved(game) -> bool:
	var ids: Dictionary = {}
	var cards: Array = game.draw_pile.duplicate()
	cards.append_array(game.discard_pile)
	for hand in game.hands:
		cards.append_array(hand)
	for entry in cards:
		ids[entry.id] = true
	return cards.size() == 108 and ids.size() == 108


func test_deck_and_start() -> void:
	var deck: Array = Rules.build_deck()
	var counts: Dictionary = {}
	var ids: Dictionary = {}
	for entry in deck:
		var key: String = entry.color + ":" + entry.value
		counts[key] = counts.get(key, 0) + 1
		ids[entry.id] = true
	check(deck.size() == 108 and ids.size() == 108, "108 unique classic cards")
	for color in Rules.COLORS:
		check(counts[color + ":0"] == 1, "one zero per color")
		for number in range(1, 10):
			check(counts[color + ":" + str(number)] == 2, "two of every colored 1–9")
		for action in Rules.ACTIONS:
			check(counts[color + ":" + action] == 2, "two of each colored action")
	check(counts["wild:wild"] == 4 and counts["wild:draw_four"] == 4, "four of each wild")
	var seen_initial: Dictionary = {}
	for player_count in range(2, 9):
		for seed_value in 80:
			var game = Rules.new()
			check(game.start_game(player_count, seed_value).ok, "start accepts 2–8 players")
			check(unique_and_conserved(game), "opening conserves all 108 cards")
			var first: Dictionary = game.top_card()
			seen_initial[first.value] = true
			check(first.value != "draw_four", "opening +4 is replaced and reshuffled")
			for player in player_count:
				var expected: int = 9 if first.value == "draw_two" and player == 0 else 7
				check(game.hands[player].size() == expected, "seven-card deal plus opening +2")
			match first.value:
				"skip", "draw_two":
					check(game.current_player == 1, "opening skip/+2 skips dealer-left")
				"reverse":
					check(game.direction == -1 and game.current_player == player_count - 1, "opening reverse starts dealer anticlockwise")
				"wild":
					check(game.phase == "choose_color" and game.current_player == 0, "opening wild lets dealer-left choose")
					check(not game.choose_initial_color(1, "red").ok, "only initial first player chooses")
					check(not game.choose_initial_color(0, "wild").ok, "initial wild needs standard color")
					check(game.choose_initial_color(0, "green").ok and game.active_color == "green" and game.current_player == 0, "initial color selection keeps first turn")
				_:
					check(game.phase == "playing" and game.current_player == 0, "opening number starts dealer-left")
	for action in ["skip", "reverse", "draw_two", "wild"]:
		check(seen_initial.has(action), "seeded openings cover " + action)
	var first_game = Rules.new()
	var second_game = Rules.new()
	first_game.start_game(5, 123456)
	second_game.start_game(5, 123456)
	check(snapshot(first_game) == snapshot(second_game), "identical seeds reproduce complete initial state")
	var before: String = snapshot(first_game)
	check(not first_game.start_game(1).ok and not first_game.start_game(9).ok, "reject player counts outside 2–8")
	check(snapshot(first_game) == before, "invalid restart does not mutate game")
	first_game.start_game(2, 0)
	check(first_game.hands.size() == 2 and first_game.winner == -1 and first_game.pending_draw == 0, "restart fully clears old round")


func test_matching_and_invalid_commands() -> void:
	var game = fixture()
	game.hands[0] = [card("red", "9"), card("blue", "5"), card("green", "9"), card("wild", "wild"), card("wild", "draw_four")]
	check(game.legal_indices(0) == [0, 1, 3, 4], "match color/number and wild; allow challengeable +4 bluff")
	check(game.legal_indices(1).is_empty() and game.legal_indices(-1).is_empty(), "legal moves belong to active player only")
	var before: String = snapshot(game)
	check(not game.play_card(0, 2).ok, "reject mismatch")
	check(not game.play_card(1, 0).ok, "reject wrong player")
	check(not game.play_card(0, -1).ok and not game.play_card(0, 99).ok, "reject absent index")
	check(not game.play_card(0, 3).ok and not game.play_card(0, 4, "purple").ok, "wild requires valid chosen color")
	check(not game.pass_draw(0).ok and not game.resolve_challenge(0, true).ok, "reject commands in incorrect phase")
	check(snapshot(game) == before, "all rejected commands leave state unchanged")
	check(game.play_card(0, 0).ok and game.active_color == "red" and game.top_card().value == "9", "matching color plays")
	game = fixture()
	game.hands[0] = [card("blue", "5"), card("green", "8")]
	check(game.play_card(0, 0).ok and game.active_color == "blue", "matching number changes active color")
	game = fixture()
	game.discard_pile = [card("red", "skip")]
	game.hands[0] = [card("green", "skip"), card("blue", "8")]
	check(game.legal_indices(0) == [0] and game.play_card(0, 0).ok, "matching symbol plays across colors")
	game = fixture()
	game.hands[0] = [card("wild", "wild"), card("green", "8")]
	check(game.play_card(0, 0, "yellow").ok and game.active_color == "yellow" and game.current_player == 1, "wild chooses active color and advances normally")
	game.hands[1] = [card("yellow", "3"), card("red", "5")]
	check(game.legal_indices(1) == [0], "following a wild matches chosen color")


func test_draw_and_pass() -> void:
	var game = fixture()
	game.hands[0] = [card("red", "9"), card("blue", "4")]
	var incoming: Dictionary = card("red", "1")
	game.draw_pile.append(incoming)
	var result: Dictionary = game.draw_card(0)
	check(result.ok and result.drawn_count == 1 and result.playable, "voluntary draw allowed with playable cards")
	check(game.phase == "drawn" and game.drawn_card_id == incoming.id and game.legal_indices(0) == [2], "only exact drawn card is available")
	var before: String = snapshot(game)
	check(not game.draw_card(0).ok and not game.play_card(0, 0).ok, "cannot draw twice or play an old card after drawing")
	check(snapshot(game) == before, "invalid second draw does not mutate")
	check(game.play_card(0, 2).ok and game.current_player == 1 and game.phase == "playing", "play exact drawn card")
	game = fixture()
	game.draw_pile.append(card("red", "1"))
	game.draw_card(0)
	check(game.pass_draw(0).ok and game.current_player == 1, "may keep a playable drawn card")
	check(not game.pass_draw(0).ok, "cannot pass twice")
	game = fixture()
	game.draw_pile.append(card("blue", "1"))
	result = game.draw_card(0)
	check(not result.playable and game.legal_indices(0).is_empty(), "unplayable draw cannot be played")
	check(game.pass_draw(0).ok and game.hands[0].size() == 3, "unplayable draw remains in hand")
	game = fixture()
	game.hands[0] = [card("red", "3"), card("green", "4")]
	game.draw_pile.append(card("wild", "draw_four"))
	game.draw_card(0)
	check(not game.can_play_draw_four(0), "drawn +4 still checks old hand for matching color")
	check(game.play_card(0, 2, "blue").ok and game.resolve_challenge(1, true).challenge_success, "drawn +4 bluff can be challenged")


func test_action_cards() -> void:
	var game = fixture(4)
	game.hands[0] = [card("red", "skip"), card("green", "4")]
	check(game.play_card(0, 0).ok and game.current_player == 2, "skip jumps over next player")
	game = fixture(4)
	game.hands[0] = [card("red", "reverse"), card("green", "4")]
	check(game.play_card(0, 0).ok and game.direction == -1 and game.current_player == 3, "reverse changes direction and wraps")
	game.hands[3] = [card("red", "skip"), card("green", "4")]
	check(game.play_card(3, 0).ok and game.current_player == 1, "skip follows reversed direction")
	game = fixture(4)
	game.hands[0] = [card("red", "draw_two"), card("green", "4")]
	game.hands[1] = [card("red", "draw_two"), card("wild", "draw_four")]
	var result: Dictionary = game.play_card(0, 0)
	check(result.ok and result.penalty_player == 1 and result.penalty_count == 2 and game.hands[1].size() == 4, "+2 immediately draws two")
	check(game.current_player == 2 and game.pending_draw == 0, "+2 victim loses turn; no pending stack")
	check(not game.play_card(1, 0).ok and not game.play_card(1, 1, "red").ok, "+2 and +4 cannot stack onto penalty")
	for value in ["skip", "reverse", "draw_two"]:
		game = fixture(2)
		game.hands[0] = [card("red", value), card("green", "4")]
		check(game.play_card(0, 0).ok and game.current_player == 0, "two-player " + value + " returns to actor")
	game = fixture(3)
	game.direction = -1
	game.hands[0] = [card("red", "draw_two"), card("green", "4")]
	result = game.play_card(0, 0)
	check(result.penalty_player == 2 and game.current_player == 1, "+2 follows reversed direction")


func test_draw_four_challenges() -> void:
	var game = fixture()
	game.hands[0] = [card("wild", "draw_four"), card("blue", "5"), card("wild", "wild")]
	check(game.can_play_draw_four(0), "matching number and another wild do not prohibit +4")
	check(game.play_card(0, 0, "green").ok, "legal +4 played")
	check(game.phase == "challenge" and game.pending_draw == 4 and game.challenge_target == 1 and game.challenge_offender == 0, "+4 waits for exact target response")
	var before: String = snapshot(game)
	check(not game.draw_card(1).ok and not game.play_card(1, 0).ok and not game.pass_draw(1).ok, "target cannot play, stack, or draw normally during challenge")
	check(not game.resolve_challenge(2, false).ok and snapshot(game) == before, "other player cannot resolve challenge")
	var result: Dictionary = game.resolve_challenge(1, false)
	check(result.ok and result.penalty_count == 4 and not result.challenged and result.revealed_hand.is_empty(), "accepting +4 draws four without revealing hand")
	check(game.hands[1].size() == 6 and game.current_player == 2 and game.phase == "playing", "accepted +4 skips target")
	check(game.challenge_target == -1 and game.challenge_offender == -1 and game.pending_draw == 0, "challenge metadata clears after resolution")
	game = fixture()
	game.hands[0] = [card("wild", "draw_four"), card("blue", "5")]
	game.play_card(0, 0, "red")
	result = game.resolve_challenge(1, true)
	check(result.challenged and not result.challenge_success and result.penalty_count == 6, "incorrect challenge draws six")
	check(game.hands[1].size() == 8 and game.current_player == 2, "incorrect challenge loses turn")
	check(result.revealed_hand.size() == 1 and result.revealed_hand[0].value == "5", "challenge reveals hand at play time without already discarded +4")
	game = fixture()
	game.hands[0] = [card("wild", "draw_four"), card("red", "9"), card("green", "2")]
	check(not game.can_play_draw_four(0), "matching active color prohibits lawful +4")
	game.play_card(0, 0, "blue")
	result = game.resolve_challenge(1, true)
	check(result.challenge_success and result.penalty_player == 0 and result.penalty_count == 4, "guilty offender draws four")
	check(game.hands[0].size() == 6 and game.hands[1].size() == 2 and game.current_player == 1, "successful challenger retains normal turn")
	check(game.active_color == "blue", "successful challenge preserves selected wild color")
	game = fixture()
	game.hands[0] = [card("wild", "draw_four"), card("red", "9")]
	game.play_card(0, 0, "blue")
	result = game.resolve_challenge(1, false)
	check(result.penalty_player == 1 and game.hands[0].size() == 1, "unchallenged bluff succeeds")
	game = fixture(2)
	game.hands[0] = [card("wild", "draw_four"), card("blue", "9")]
	game.play_card(0, 0, "blue")
	game.resolve_challenge(1, false)
	check(game.current_player == 0, "two-player accepted +4 returns to actor")
	game = fixture(3)
	game.direction = -1
	game.hands[0] = [card("wild", "draw_four"), card("blue", "9")]
	game.play_card(0, 0, "blue")
	check(game.challenge_target == 2, "+4 challenge follows reverse direction")
	game.resolve_challenge(2, false)
	check(game.current_player == 1, "+4 penalty skip follows reverse direction")
	game = fixture()
	game.discard_pile = [card("wild", "wild")]
	game.active_color = "yellow"
	game.hands[0] = [card("wild", "draw_four"), card("yellow", "skip")]
	check(not game.can_play_draw_four(0), "+4 legality checks wild's selected color")
	game.play_card(0, 0, "red")
	game.start_game(4, 101)
	check(game.challenge_target == -1 and game.challenge_offender == -1 and game.pending_draw == 0 and game.pending_winner == -1 and game.uno_player == -1, "restart clears pending +4 and UNO state")


func test_uno_window() -> void:
	var game = fixture()
	game.hands[0] = [card("red", "1"), card("blue", "9")]
	game.play_card(0, 0)
	check(game.uno_player == 0 and not game.uno_announced and game.current_player == 1, "missed UNO stays catchable after turn assignment")
	check(not game.catch_uno(0).ok and not game.catch_uno(-1).ok, "only another valid player can catch")
	check(game.catch_uno(2).ok and game.hands[0].size() == 3 and game.current_player == 1, "any opponent catches missed UNO for two cards without using turn")
	check(not game.catch_uno(1).ok, "missed UNO cannot be caught twice")
	game = fixture()
	game.hands[0] = [card("red", "1"), card("blue", "9")]
	game.play_card(0, 0, "", true)
	check(game.uno_announced and not game.catch_uno(1).ok, "announcement bundled with play prevents catch")
	game = fixture()
	game.hands[0] = [card("red", "1"), card("blue", "9")]
	game.play_card(0, 0)
	check(game.announce_uno(0).ok and not game.catch_uno(1).ok, "late self-announcement before a catch saves player")
	check(not game.announce_uno(1).ok, "other player cannot announce actor's UNO")
	game = fixture()
	game.hands[0] = [card("red", "1"), card("blue", "9")]
	game.play_card(0, 0)
	var before: String = snapshot(game)
	game.play_card(2, 0)
	check(snapshot(game) == before and game.uno_player == 0, "invalid next action does not close catch window")
	game.draw_card(1)
	check(not game.catch_uno(2).ok and game.uno_player == -1, "next valid draw closes catch window")
	game = fixture()
	game.hands[0] = [card("red", "1"), card("blue", "9")]
	game.hands[1] = [card("red", "2"), card("blue", "8"), card("green", "7")]
	game.play_card(0, 0)
	game.play_card(1, 0)
	check(not game.catch_uno(2).ok, "next valid play closes old catch window")
	game = fixture(2)
	game.hands[0] = [card("red", "reverse"), card("red", "9")]
	game.play_card(0, 0)
	check(game.current_player == 0 and game.catch_uno(1).ok, "two-player reverse leaves an UNO catch opportunity")
	game = fixture()
	game.hands[0] = [card("wild", "draw_four"), card("blue", "9")]
	game.play_card(0, 0, "blue")
	check(game.catch_uno(1).ok and game.phase == "challenge", "UNO catch may precede +4 decision")
	var result: Dictionary = game.resolve_challenge(1, true)
	check(not result.challenge_success, "+4 evidence remains pre-play hand after UNO penalty")


func test_recycling_and_stalemate() -> void:
	var game = fixture()
	var older: Dictionary = card("green", "2")
	var middle: Dictionary = card("blue", "4")
	var top: Dictionary = card("wild", "wild")
	game.discard_pile = [older, middle, top]
	game.active_color = "red"
	game.draw_pile = []
	var original_total: int = game.total_cards()
	game.draw_card(0)
	check(game.discard_pile.size() == 1 and game.top_card().id == top.id, "recycle preserves top discard")
	check(game.draw_pile.size() == 1 and game.total_cards() == original_total and game.active_color == "red", "recycle conserves cards and selected color")
	check(game.hands[0].back().id in [older.id, middle.id], "recycled discarded card can be drawn")
	game = fixture()
	game.draw_pile = []
	game.hands = [[card("blue", "1")], [card("green", "2")], [card("yellow", "3")]]
	for player in 3:
		var result: Dictionary = game.draw_card(player)
		check(result.ok and result.drawn_count == 0 and not result.playable and game.phase == "drawn", "empty deck offers explicit pass")
		check(game.pass_draw(player).ok, "empty deck pass is allowed")
	check(game.phase == "finished" and game.winner == -1 and game.score == 0 and game.finish_reason == "stalemate", "all blocked empty passes end in stalemate")
	game = fixture(2)
	game.draw_pile = []
	game.hands = [[card("red", "1")], [card("green", "2")]]
	for _round in 3:
		for player in 2:
			game.draw_card(player)
			game.pass_draw(player)
	check(game.phase == "playing", "voluntarily refusing a playable card is not a stalemate")
	game = fixture()
	game.draw_pile = [card("green", "1")]
	game.hands[0] = [card("red", "draw_two"), card("blue", "9")]
	var total: int = game.total_cards()
	var result: Dictionary = game.play_card(0, 0)
	check(result.penalty_count == 2 and game.total_cards() == total and game.top_card().value == "draw_two", "penalty draw recycles mid-penalty without losing top")
	game = fixture()
	game.draw_pile = []
	game.hands[0] = [card("wild", "draw_four"), card("blue", "9")]
	game.play_card(0, 0, "green")
	var short_total: int = game.total_cards()
	result = game.resolve_challenge(1, false)
	check(result.requested_penalty == 4 and result.penalty_count == 1 and game.total_cards() == short_total, "insufficient physical cards report actual +4 draw without inventing cards")
	check(game.phase == "playing" and game.current_player == 2, "shortage still resolves penalty without hanging")


func test_finishing_and_scoring() -> void:
	check(Rules.card_points(card("red", "0")) == 0 and Rules.card_points(card("blue", "9")) == 9, "number points")
	for action in Rules.ACTIONS:
		check(Rules.card_points(card("green", action)) == 20, "colored action points")
	for value in ["wild", "draw_four"]:
		check(Rules.card_points(card("wild", value)) == 50, "wild points")
	var game = fixture()
	game.hands = [[card("red", "1")], [card("green", "9"), card("blue", "skip")], [card("wild", "draw_four"), card("wild", "wild")]]
	game.play_card(0, 0)
	check(game.phase == "finished" and game.winner == 0 and game.score == 129 and game.finish_reason == "winner", "last ordinary card finishes and scores all opponents")
	var before: String = snapshot(game)
	check(not game.play_card(1, 0).ok and not game.draw_card(1).ok and not game.announce_uno(0).ok and not game.catch_uno(1).ok, "finished round rejects all gameplay commands")
	check(snapshot(game) == before, "finished state cannot mutate through invalid commands")
	for value in ["skip", "reverse", "wild"]:
		game = fixture(2)
		game.hands[0] = [card("wild" if value == "wild" else "red", value)]
		game.play_card(0, 0, "blue")
		check(game.phase == "finished" and game.winner == 0, "final " + value + " finishes round")
	game = fixture(2)
	game.hands = [[card("red", "draw_two")], [card("blue", "3")]]
	game.draw_pile = [card("yellow", "7"), card("green", "8")]
	game.play_card(0, 0)
	check(game.phase == "finished" and game.hands[1].size() == 3 and game.score == 18, "final +2 penalty is paid before score")
	game = fixture(2)
	game.hands = [[card("wild", "draw_four")], [card("blue", "3")]]
	game.draw_pile = [card("yellow", "1"), card("green", "2"), card("yellow", "3"), card("green", "4"), card("yellow", "5"), card("green", "6")]
	game.play_card(0, 0, "green")
	check(game.phase == "challenge" and game.winner == -1 and game.pending_winner == 0 and game.score == 0, "final +4 cannot finish before challenge decision")
	game.resolve_challenge(1, false)
	check(game.phase == "finished" and game.winner == 0 and game.hands[1].size() == 5 and game.score == 21, "accepted final +4 penalty contributes to score")
	game = fixture(2)
	game.hands = [[card("wild", "draw_four")], [card("blue", "3")]]
	game.draw_pile = [card("yellow", "1"), card("green", "2"), card("yellow", "3"), card("green", "4"), card("yellow", "5"), card("green", "6")]
	game.play_card(0, 0, "blue")
	game.resolve_challenge(1, true)
	check(game.phase == "finished" and game.winner == 0 and game.hands[1].size() == 7 and game.score == 24, "failed final +4 challenge adds six before scoring")


func test_seeded_complete_rounds() -> void:
	var completed: int = 0
	var actions: int = 0
	var recycled: bool = false
	for player_count in range(2, 9):
		for seed_value in 20:
			var game = Rules.new()
			game.start_game(player_count, seed_value * 101 + player_count)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value + player_count * 999
			if game.phase == "choose_color":
				game.choose_initial_color(game.current_player, Rules.COLORS[rng.randi_range(0, 3)])
			var turns: int = 0
			while game.phase != "finished" and turns < 10000:
				turns += 1
				actions += 1
				var player: int = game.current_player
				var prior_discard: int = game.discard_pile.size()
				var result: Dictionary
				if game.phase == "challenge":
					result = game.resolve_challenge(player, rng.randf() < 0.5)
				elif game.phase == "drawn":
					var options: Array = game.legal_indices(player)
					if not options.is_empty() and rng.randf() < 0.9:
						result = game.play_card(player, options[0], Rules.COLORS[rng.randi_range(0, 3)], rng.randf() < 0.9)
					else:
						result = game.pass_draw(player)
				else:
					var options: Array = game.legal_indices(player)
					if not options.is_empty() and rng.randf() < 0.95:
						result = game.play_card(player, options[rng.randi_range(0, options.size() - 1)], Rules.COLORS[rng.randi_range(0, 3)], rng.randf() < 0.9)
					else:
						result = game.draw_card(player)
				check(result.ok, "simulated valid command succeeds")
				if game.uno_player >= 0 and not game.uno_announced and rng.randf() < 0.5:
					check(game.catch_uno((game.uno_player + 1) % player_count).ok, "simulated UNO catch succeeds")
				if game.discard_pile.size() < prior_discard:
					recycled = true
				check(unique_and_conserved(game), "simulation conserves 108 unique cards after every action")
				check(game.current_player >= 0 and game.current_player < player_count, "current player always valid")
				if not result.ok:
					break
			check(game.phase == "finished" and turns < 10000, "seeded round reaches terminal state")
			if game.phase == "finished":
				completed += 1
				check(game.winner >= 0 and game.hands[game.winner].is_empty(), "simulated round has an empty-handed winner")
				var expected_score: int = 0
				for hand in game.hands:
					for entry in hand:
						expected_score += Rules.card_points(entry)
				check(game.score == expected_score, "simulated final score matches all remaining cards")
	check(completed == 140 and recycled, "140 deterministic complete rounds across 2–8 players include recycling")
	print("Simulated %d complete rounds and %d commands." % [completed, actions])
