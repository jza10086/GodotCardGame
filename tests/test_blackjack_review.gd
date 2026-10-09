extends SceneTree
## Independent contract, accounting and regression review. No production mutation.
const Rules = preload("res://scripts/blackjack_rules.gd")
var checks := 0
var failures := 0

func ck(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BLACKJACK REVIEW: " + label)

func snapshot(g) -> String:
	return JSON.stringify(g.snapshot())

func rig(ranks: Array):
	var g = Rules.new(917)
	var used := {}
	var ids: Array = []
	for rank in ranks:
		var count: int = used.get(rank, 0)
		ids.append(count * 13 + rank - 1)
		used[rank] = count + 1
	g.set_next_draws(ids)
	return g

func finish(g) -> void:
	if g.phase == "player": ck(g.stand().ok, "stand accepted")
	var steps := 0
	while g.phase == "dealer" and steps < 52:
		ck(g.dealer_step().ok, "dealer progresses")
		steps += 1
	ck(g.phase == "settled", "round reaches terminal state")

func rejection(g, method: String, args: Array, label: String) -> void:
	var before := snapshot(g)
	var response: Dictionary = g.callv(method, args)
	ck(not response.ok and snapshot(g) == before, label + " atomic rejection")

func oracle_total(cards: Array) -> int:
	var total := 0
	var aces := 0
	for card in cards:
		var rank: int = card.rank
		total += mini(rank, 10)
		if rank == 1: aces += 1
	if aces > 0 and total + 10 <= 21: total += 10
	return total

func conservation(g, label: String) -> void:
	var all: Array = g.draw_pile + g.discard_pile + g.player_hand + g.dealer_hand
	var ids := {}
	for card in all: ids[card.id] = true
	ck(all.size() == 52 and ids.size() == 52, label + " 52 unique physical cards")
	ck(g.balance >= 0, label + " balance nonnegative")

func _initialize() -> void:
	test_values()
	test_payouts()
	test_double()
	test_atomicity()
	test_exhaustion()
	test_random_oracle()
	test_multi_rounds()
	test_reset_and_corruption()
	print("INDEPENDENT BLACKJACK REVIEW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_values() -> void:
	for ranks in [[1, 1], [1, 1, 9], [1, 1, 9, 10], [1, 6], [1, 6, 10], [13, 12], [1, 13], [7, 7, 7], [10, 10, 2]]:
		var cards: Array = []
		for rank in ranks: cards.append({"rank": rank})
		var value: Dictionary = Rules.hand_value(cards)
		var expected := oracle_total(cards)
		ck(value.total == expected, "ace/face total " + str(ranks))
		ck(value.blackjack == (cards.size() == 2 and expected == 21), "natural is two cards only")
		ck(value.bust == (expected > 21), "bust oracle")
	ck(Rules.hand_value([{"rank":1},{"rank":6}]).soft, "A6 soft17")
	ck(not Rules.hand_value([{"rank":1},{"rank":6},{"rank":10}]).soft, "ace downgraded hard17")

func test_payouts() -> void:
	for item in [
		[[1, 10, 13, 9], "blackjack", 1150],
		[[1, 1, 10, 13], "push", 1000],
		[[10, 1, 9, 13], "dealer_blackjack", 900],
		[[10, 10, 10, 9], "win", 1100],
		[[10, 10, 9, 10], "loss", 900],
		[[10, 10, 9, 9], "push", 1000],
		[[10, 10, 8, 6, 10], "win", 1100],
		[[10, 1, 8, 6, 10], "win", 1100]]:
		var g = rig(item[0])
		ck(g.start_round(100).ok, "fixture starts")
		finish(g)
		ck(g.result.outcome == item[1] and g.balance == item[2], "payout " + str(item))
		ck(g.result.payout == g.result.net + 100, "payout includes returned stake")
		conservation(g, "payout")
		var balance: int = g.balance
		for method in ["hit", "stand", "double_down", "dealer_step"]: rejection(g, method, [], "settled " + method)
		ck(g.balance == balance, "settlement never applied twice")
		ck(g.next_round().ok and g.balance == balance, "next round preserves result balance")
		rejection(g, "next_round", [], "duplicate next round")
	var g = rig([10, 6, 9, 10, 5])
	g.start_round(100)
	ck(g.hit().ok and g.phase == "settled" and g.result.outcome == "bust" and g.balance == 900, "player bust immediate full stake loss")
	ck(g.dealer_hand.size() == 2, "dealer need not draw after player bust")
	g = rig([10, 1, 8, 6, 10])
	g.start_round(100); finish(g)
	ck(g.dealer_hand.size() == 2 and oracle_total(g.dealer_hand) == 17, "dealer stands on soft17")

func test_double() -> void:
	var g = rig([5, 10, 6, 7, 10])
	g.start_round(100)
	ck(g.can_double(), "initial two cards permit double")
	ck(g.double_down().ok and g.bet == 200 and g.balance == 800 and g.player_hand.size() == 3, "double stakes exactly equal and draws exactly one")
	rejection(g, "double_down", [], "double cannot repeat")
	rejection(g, "hit", [], "double forces stand")
	finish(g)
	ck(g.balance == 1200 and g.result.payout == 400, "three card21 double is ordinary win")
	g = rig([10, 10, 9, 7, 10]); g.start_round(100); g.double_down()
	ck(g.balance == 800 and g.phase == "settled" and g.player_hand.size() == 3, "double bust loses both stakes once")
	g = rig([2, 10, 3, 7, 4]); g.start_round(100); g.hit()
	ck(not g.can_double(), "hit revokes double")
	rejection(g, "double_down", [], "double after hit")
	g = rig([5, 10, 6, 7, 10]); g.start_round(600)
	ck(not g.can_double(), "insufficient balance revokes double")
	rejection(g, "double_down", [], "unfunded double")
	g = rig([5, 10, 6, 7, 10]); g.start_round(500)
	ck(g.double_down().ok and g.balance == 0, "exact available balance permits double")
	finish(g); ck(g.balance == 2000, "all-in double win accounting")

func test_atomicity() -> void:
	var g = rig([5, 10, 6, 7, 10])
	for amount in [-100, 0, 1, 9, 15, 1001, 1010]: rejection(g, "start_round", [amount], "bad bet " + str(amount))
	for method in ["hit", "stand", "double_down", "dealer_step", "next_round"]: rejection(g, method, [], "betting " + method)
	var version: int = g.state_version
	ck(g.start_round(100, version).ok and g.state_version == version + 1, "one version increment for deal")
	rejection(g, "start_round", [100], "active duplicate deal")
	for method in ["hit", "stand", "double_down", "dealer_step", "next_round"]: rejection(g, method, [version], "stale " + method)
	rejection(g, "dealer_step", [], "dealer action on player turn")
	rejection(g, "next_round", [], "next round cannot abandon active wager")
	ck(not g.dealer_revealed, "dealer hole hidden while player acts")
	ck(g.stand().ok and g.dealer_revealed, "stand reveals dealer")
	for method in ["hit", "stand", "double_down"]: rejection(g, method, [], "dealer phase " + method)

func test_exhaustion() -> void:
	for action in ["hit", "double_down", "dealer_step"]:
		var g = rig([5, 10, 6, 2])
		g.start_round(100)
		if action == "dealer_step": g.stand()
		g.discard_pile.append_array(g.draw_pile); g.draw_pile.clear()
		g.call(action)
		ck(g.phase == "settled" and g.result.outcome == "void" and g.balance == 1000, "exhaustion full refund " + action)
		rejection(g, action, [], "void terminal idempotence " + action)
		conservation(g, "exhaustion")

func test_random_oracle() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 123890
	for seed_value in 1000:
		var g = Rules.new(seed_value)
		var amount: int = rng.randi_range(1, 50) * 10
		ck(g.start_round(amount).ok, "random starts")
		conservation(g, "random deal")
		var steps := 0
		while g.phase == "player" and steps < 40:
			var action := rng.randi_range(0, 2)
			if action == 2 and g.can_double(): ck(g.double_down().ok, "random double")
			elif action == 0: ck(g.hit().ok, "random hit")
			else: ck(g.stand().ok, "random stand")
			steps += 1
		finish(g)
		var p := oracle_total(g.player_hand)
		var d := oracle_total(g.dealer_hand)
		var pn: bool = p == 21 and g.player_hand.size() == 2
		var dn: bool = d == 21 and g.dealer_hand.size() == 2
		var net: int = -g.bet
		if p > 21: net = -g.bet
		elif pn and dn: net = 0
		elif dn: net = -g.bet
		elif pn: net = int(g.bet * 3 / 2)
		elif d > 21 or p > d: net = g.bet
		elif p == d: net = 0
		ck(g.balance == 1000 + net and g.result.net == net, "independent random payout oracle seed " + str(seed_value))
		conservation(g, "random finished")

func test_multi_rounds() -> void:
	var g = Rules.new(3819)
	for index in 300:
		if g.balance < 10:
			ck(g.reset_bankroll().ok, "explicit reset permitted between rounds")
		var before: int = g.balance
		ck(g.start_round(10).ok, "consecutive round starts")
		finish(g)
		ck(g.balance == before + g.result.net, "consecutive round settles exactly once")
		conservation(g, "consecutive round")
		ck(g.next_round().ok, "consecutive cleanup")
		conservation(g, "between rounds")
	ck(g.shoe_shuffles > 1, "depleted shoe shuffles between rounds")

func test_reset_and_corruption() -> void:
	var g = rig([5, 10, 6, 7])
	g.start_round(100)
	rejection(g, "reset_bankroll", [], "no active bankroll reset")
	rejection(g, "set_next_draws", [[1, 2, 3]], "no live fixture substitution")
	finish(g)
	ck(g.reset_bankroll().ok and g.balance == 1000 and g.phase == "betting", "explicit reset restores session balance")
	conservation(g, "after reset")
	for ids in [[0, 0], [-1], [52], ["1"], [1.0]]:
		rejection(g, "set_next_draws", [ids], "invalid rig IDs")
	g = Rules.new(908)
	g.draw_pile.resize(3)
	rejection(g, "start_round", [10], "insufficient deal preflight")
