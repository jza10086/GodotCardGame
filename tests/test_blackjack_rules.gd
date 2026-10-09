extends SceneTree
## Run: godot --headless --path . --script res://tests/test_blackjack_rules.gd

const Rules = preload("res://scripts/blackjack_rules.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_deck_and_values()
	_test_betting_and_atomicity()
	_test_naturals()
	_test_ordinary_results()
	_test_doubling()
	_test_dealer_policy()
	_test_versions_and_lifecycle()
	_test_fixtures_and_snapshots()
	_test_exhaustion()
	_test_long_shoe()
	print("BLACKJACK RULES: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _ids(ranks: Array) -> Array:
	var result: Array = []
	var copies: Dictionary = {}
	for rank in ranks:
		var copy: int = int(copies.get(rank, 0))
		assert(copy < 4)
		result.append(copy * 13 + int(rank) - 1)
		copies[rank] = copy + 1
	return result


func _hand(ranks: Array) -> Array:
	var cards: Array = []
	for rank in ranks:
		cards.append({"rank": rank})
	return cards


func _round(ranks: Array, amount: int = 100):
	var rules = Rules.new(123)
	_check(rules.set_next_draws(_ids(ranks)).ok, "fixture accepted")
	_check(rules.start_round(amount, rules.state_version).ok, "round starts")
	return rules


func _finish_dealer(rules) -> void:
	var steps: int = 0
	while rules.phase == "dealer" and steps < 52:
		var before: int = rules.dealer_hand.size()
		_check(rules.dealer_step(rules.state_version).ok, "dealer step accepted")
		_check(rules.dealer_hand.size() - before <= 1, "dealer draws at most one per step")
		steps += 1
	_check(rules.phase == "settled", "dealer terminates")


func _conservation(rules, label: String) -> void:
	var all: Array = rules.player_hand + rules.dealer_hand + rules.draw_pile + rules.discard_pile
	var ids: Dictionary = {}
	for card in all:
		ids[card.id] = true
	_check(all.size() == 52 and ids.size() == 52, label)


func _unchanged_failure(rules, response: Dictionary, before: Dictionary, label: String) -> void:
	_check(not response.ok, label + " rejected")
	_check(rules.snapshot() == before, label + " atomic")


func _test_deck_and_values() -> void:
	var deck: Array = Rules.build_deck()
	_check(deck.size() == 52, "52-card deck")
	var ids: Dictionary = {}
	for index in deck.size():
		var card: Dictionary = deck[index]
		_check(card.id == index, "stable integer ID %d" % index)
		_check(card.rank == index % 13 + 1, "rank mapping %d" % index)
		_check(card.suit == Rules.SUITS[int(index / 13)], "suit mapping %d" % index)
		ids[card.id] = true
	_check(ids.size() == 52, "52 unique identities")
	for sample in [
		[[], 0, false, false, false], [[1], 11, true, false, false],
		[[1, 6], 17, true, false, false], [[1, 6, 10], 17, false, false, false],
		[[1, 1, 9], 21, true, false, false], [[1, 1, 1, 8], 21, true, false, false],
		[[1, 1, 1, 1, 7], 21, true, false, false], [[1, 1, 10, 9], 21, false, false, false],
		[[1, 13], 21, true, true, false], [[10, 12], 20, false, false, false],
		[[13, 12, 2], 22, false, false, true], [[11, 1, 1], 12, false, false, false],
	]:
		var value: Dictionary = Rules.hand_value(_hand(sample[0]))
		_check(value.total == sample[1] and value.soft == sample[2] and value.blackjack == sample[3] and value.bust == sample[4], "hand " + str(sample[0]))
	_check(Rules.rank_label(1) == "A" and Rules.rank_label(11) == "J" and Rules.rank_label(12) == "Q" and Rules.rank_label(13) == "K", "face-rank labels")
	var first = Rules.new(42)
	var second = Rules.new(42)
	_check(first.draw_pile == second.draw_pile, "seeded shuffle deterministic")
	_check(first.draw_pile != deck, "deck is shuffled")


func _test_betting_and_atomicity() -> void:
	var rules = Rules.new(14)
	_check(rules.balance == 1000 and rules.phase == "betting" and rules.bet == 0, "initial bankroll")
	for amount in [-100, 0, 5, 9, 11, 15, 1001, 1010]:
		var before: Dictionary = rules.snapshot()
		_unchanged_failure(rules, rules.start_round(amount), before, "invalid bet %d" % amount)
	for method in ["hit", "stand", "double_down", "dealer_step", "next_round"]:
		var before: Dictionary = rules.snapshot()
		_unchanged_failure(rules, rules.call(method), before, "betting " + method)
	rules.set_next_draws(_ids([10, 9, 6, 8, 10]))
	_check(rules.start_round(1000).ok, "whole balance bet legal")
	_check(rules.balance == 0 and rules.bet == 1000, "stake debited exactly once")
	_check(not rules.can_double(), "cannot double without funds")
	for method in ["next_round", "reset_bankroll", "dealer_step"]:
		var before: Dictionary = rules.snapshot()
		_unchanged_failure(rules, rules.call(method), before, "active " + method)
	var before: Dictionary = rules.snapshot()
	_unchanged_failure(rules, rules.start_round(10), before, "second bet while active")
	_unchanged_failure(rules, rules.double_down(), before, "unfunded double")
	rules.hit()
	_check(rules.phase == "settled" and rules.balance == 0, "bankruptcy persists")
	rules.next_round()
	before = rules.snapshot()
	_unchanged_failure(rules, rules.start_round(10), before, "zero balance cannot bet")
	_check(rules.balance == 0, "next round never resets money")
	_check(rules.reset_bankroll().ok and rules.balance == 1000, "explicit confirmed reset is supported")


func _test_naturals() -> void:
	var player = _round([1, 9, 13, 8])
	_check(player.phase == "settled" and player.result.outcome == "blackjack", "player natural settles immediately")
	_check(player.balance == 1150 and player.result.payout == 250 and player.result.net == 150, "natural pays stake plus 3:2")
	_check(player.dealer_revealed and not player.can_double(), "natural reveals and disables actions")
	var minimum = _round([1, 9, 12, 8], 10)
	_check(minimum.balance == 1015 and minimum.result.payout == 25, "minimum bet 3:2 exact")
	var both = _round([1, 1, 10, 11])
	_check(both.result.outcome == "push" and both.balance == 1000 and both.result.payout == 100, "natural against natural pushes")
	var dealer = _round([9, 1, 10, 13])
	_check(dealer.phase == "settled" and dealer.result.outcome == "dealer_blackjack" and dealer.balance == 900, "dealer peeks before any player action")
	for method in ["hit", "stand", "double_down", "dealer_step"]:
		var before: Dictionary = dealer.snapshot()
		_unchanged_failure(dealer, dealer.call(method), before, "natural settled " + method)


func _test_ordinary_results() -> void:
	for sample in [
		[[10, 10, 9, 7], "win", 1100, 200],
		[[10, 10, 7, 9], "loss", 900, 0],
		[[10, 9, 8, 9], "push", 1000, 100],
		[[10, 10, 8, 6, 10], "win", 1100, 200],
	]:
		var rules = _round(sample[0])
		_check(rules.stand().ok, "stand accepted")
		_check(rules.phase == "dealer" and rules.dealer_revealed, "stand reveals and enters dealer")
		_finish_dealer(rules)
		_check(rules.result.outcome == sample[1] and rules.balance == sample[2] and rules.result.payout == sample[3], "ordinary " + sample[1])
		_conservation(rules, "ordinary conservation")
	var bust = _round([10, 10, 6, 7, 10])
	bust.hit()
	_check(bust.phase == "settled" and bust.result.outcome == "bust" and bust.balance == 900, "player bust loses immediately")
	_check(bust.dealer_hand.size() == 2, "dealer never draws after player bust")
	var twenty_one = _round([10, 10, 6, 7, 5])
	twenty_one.hit()
	_check(twenty_one.phase == "dealer", "hit to21 auto-stands")
	_finish_dealer(twenty_one)
	_check(twenty_one.result.outcome == "win" and twenty_one.result.payout == 200, "three-card21 never natural payout")


func _test_doubling() -> void:
	var rules = _round([5, 10, 6, 7, 9])
	_check(rules.can_double(), "initial two cards can double")
	var version: int = rules.state_version
	_check(rules.double_down(version).ok, "double accepted")
	_check(rules.balance == 800 and rules.bet == 200 and rules.initial_bet == 100, "double debits equal original stake")
	_check(rules.player_hand.size() == 3 and rules.doubled and rules.phase == "dealer", "double draws exactly one then forced stand")
	for method in ["double_down", "hit", "stand"]:
		var before: Dictionary = rules.snapshot()
		_unchanged_failure(rules, rules.call(method), before, "post-double " + method)
	_finish_dealer(rules)
	_check(rules.balance == 1200 and rules.result.payout == 400 and rules.result.net == 200, "double win pays entire double stake")
	var hit_first = _round([2, 10, 3, 7, 2])
	hit_first.hit()
	_check(not hit_first.can_double(), "hit removes double privilege")
	var before: Dictionary = hit_first.snapshot()
	_unchanged_failure(hit_first, hit_first.double_down(), before, "late double")
	var double_bust = _round([10, 10, 9, 7, 10])
	double_bust.double_down()
	_check(double_bust.result.outcome == "bust" and double_bust.balance == 800 and double_bust.player_hand.size() == 3, "double bust loses both stakes")
	var exact = Rules.new(8)
	exact.balance = 200
	exact.set_next_draws(_ids([5, 10, 6, 7, 9]))
	exact.start_round(100)
	_check(exact.can_double() and exact.double_down().ok and exact.balance == 0, "exact remaining stake permits double")
	_finish_dealer(exact)
	_check(exact.balance == 400, "exact bankroll double payout")
	var short = Rules.new(8)
	short.balance = 199
	short.set_next_draws(_ids([5, 10, 6, 7]))
	short.start_round(100)
	before = short.snapshot()
	_unchanged_failure(short, short.double_down(), before, "one coin short double")


func _test_dealer_policy() -> void:
	var soft17 = _round([10, 1, 8, 6, 10])
	soft17.stand()
	_finish_dealer(soft17)
	_check(soft17.dealer_hand.size() == 2 and soft17.result.dealer_total == 17, "soft17 stands")
	var hard17 = _round([10, 10, 8, 7, 9])
	hard17.stand()
	_finish_dealer(hard17)
	_check(hard17.dealer_hand.size() == 2, "hard17 stands")
	var hard16 = _round([10, 10, 7, 6, 5])
	hard16.stand()
	_finish_dealer(hard16)
	_check(hard16.dealer_hand.size() == 3 and hard16.result.dealer_total == 21, "hard16 hits")
	var soft16 = _round([10, 1, 9, 5, 10, 2])
	soft16.stand()
	var version: int = soft16.state_version
	soft16.dealer_step(version)
	_check(soft16.phase == "dealer" and soft16.dealer_hand.size() == 3 and Rules.hand_value(soft16.dealer_hand).total == 16, "soft16 hit ten becomes hard16, still needs draw")
	var before: Dictionary = soft16.snapshot()
	_unchanged_failure(soft16, soft16.dealer_step(version), before, "stale dealer callback")
	_finish_dealer(soft16)
	_check(soft16.dealer_hand.size() == 4 and soft16.result.dealer_total == 18, "dealer continues below17")


func _test_versions_and_lifecycle() -> void:
	var rules = _round([2, 10, 3, 7, 4, 5])
	var version: int = rules.state_version
	rules.hit(version)
	_check(rules.state_version == version + 1, "one accepted request one version")
	var before: Dictionary = rules.snapshot()
	for method in ["hit", "stand", "double_down", "dealer_step", "next_round", "reset_bankroll"]:
		_unchanged_failure(rules, rules.call(method, version), before, "stale " + method)
	_unchanged_failure(rules, rules.start_round(100, version), before, "stale new bet")
	_unchanged_failure(rules, rules.set_next_draws([0, 1, 2, 3], version), before, "stale fixture")
	rules.stand()
	_finish_dealer(rules)
	var bank: int = rules.balance
	var settled_version: int = rules.state_version
	for _repeat in 5:
		before = rules.snapshot()
		_unchanged_failure(rules, rules.dealer_step(), before, "repeat settlement")
	_check(rules.balance == bank, "settlement is idempotent")
	_check(rules.next_round(settled_version).ok, "next round available after settlement")
	_check(rules.phase == "betting" and rules.balance == bank and rules.player_hand.is_empty() and rules.dealer_hand.is_empty() and rules.result.is_empty(), "next round clears table only")
	_check(rules.state_version == settled_version + 1, "version never resets between rounds")
	_conservation(rules, "cleanup conserves all52")
	before = rules.snapshot()
	_unchanged_failure(rules, rules.next_round(), before, "repeat next round")


func _test_fixtures_and_snapshots() -> void:
	var rules = Rules.new(6)
	for invalid in [[0, 0], [-1], [52], [1.0], ["1"]]:
		var before: Dictionary = rules.snapshot()
		_unchanged_failure(rules, rules.set_next_draws(invalid), before, "invalid fixture " + str(invalid))
	var order: Array = _ids([2, 10, 3, 7, 4])
	rules.set_next_draws(order)
	order[0] = 51
	rules.start_round(100)
	_check(rules.player_hand[0].rank == 2 and rules.player_hand[1].rank == 3 and rules.dealer_hand[0].rank == 10 and rules.dealer_hand[1].rank == 7, "fixture copied and deals P,D,P,D")
	_check(not rules.dealer_revealed, "hole card hidden during player phase")
	var copied: Dictionary = rules.snapshot()
	copied.player_hand[0].rank = 13
	copied.draw_pile.clear()
	_check(rules.player_hand[0].rank == 2 and not rules.draw_pile.is_empty(), "snapshot cannot mutate model")
	var before: Dictionary = rules.snapshot()
	_unchanged_failure(rules, rules.set_next_draws([1, 2]), before, "active fixture")
	var reply: Dictionary = rules.hit()
	reply.card.rank = 13
	_check(rules.player_hand.back().rank == 4, "action response card copied")
	_conservation(rules, "fixture conserves52")


func _test_exhaustion() -> void:
	for method in ["hit", "double_down", "dealer_step"]:
		var rules = _round([5, 10, 6, 6])
		if method == "dealer_step":
			rules.stand()
		# Fault injection only: normal deals reserve >=26 cards before starting.
		rules.discard_pile.append_array(rules.draw_pile)
		rules.draw_pile.clear()
		_check(rules.call(method).ok, "exhaustion handled " + method)
		_check(rules.phase == "settled" and rules.result.outcome == "void" and rules.balance == 1000 and rules.result.net == 0, "exhaustion refunds every stake " + method)
		_conservation(rules, "no midround regeneration " + method)
		var before: Dictionary = rules.snapshot()
		_unchanged_failure(rules, rules.call(method), before, "exhaustion only refunds once " + method)
	var broken = Rules.new(0)
	broken.draw_pile.resize(3)
	var before: Dictionary = broken.snapshot()
	_unchanged_failure(broken, broken.start_round(100), before, "insufficient initial deal atomic")


func _test_long_shoe() -> void:
	var rules = Rules.new(83625)
	rules.balance = 100000
	var previous_shuffles: int = rules.shoe_shuffles
	for round_index in 500:
		var bank: int = rules.balance
		_check(rules.start_round(10, rules.state_version).ok, "long game starts %d" % round_index)
		var round_shuffles: int = rules.shoe_shuffles
		_conservation(rules, "long initial conservation")
		while rules.phase == "player":
			if Rules.hand_value(rules.player_hand).total < 16:
				rules.hit(rules.state_version)
			else:
				rules.stand(rules.state_version)
			_conservation(rules, "long player conservation")
		while rules.phase == "dealer":
			rules.dealer_step(rules.state_version)
			_conservation(rules, "long dealer conservation")
		_check(rules.phase == "settled" and rules.result.outcome != "void", "normal finite shoe never exhausts")
		_check(rules.balance == bank + rules.result.net, "long exact bankroll")
		_check(rules.shoe_shuffles == round_shuffles, "never shuffles within active round")
		_check(rules.next_round(rules.state_version).ok, "long next round")
		_conservation(rules, "long cleanup conservation")
	_check(rules.shoe_shuffles > previous_shuffles, "shoe recycled across many rounds")
