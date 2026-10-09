extends SceneTree
## Independent manual dealer state, distribution and settlement audit.
const Rules = preload("res://scripts/blackjack_ring_rules.gd")
var checks := 0
var failures := 0
func ck(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("MANUAL DEALER REVIEW: " + label)
func snap(g) -> String: return JSON.stringify(g.snapshot())
func reject(g, method: String, args: Array, label: String) -> void:
	var before := snap(g)
	var response: Dictionary = g.callv(method, args)
	ck(not response.ok and snap(g) == before, label + " rejects atomically")
func rig(hands: Array, dealer: Array, extra: Array = [], mode: String = "human"):
	var g = Rules.new(617)
	var used := {}
	var ids: Array = []
	var ranks: Array = []
	for i in 2:
		for h in hands: ranks.append(h[i])
		ranks.append(dealer[i])
	ranks.append_array(extra)
	for rank in ranks:
		var n: int = used.get(rank, 0)
		ids.append(n * 13 + rank - 1)
		used[rank] = n + 1
	ck(g.set_next_draws(ids).ok, "fixture accepted")
	var stakes: Array = []
	for i in 8: stakes.append(100 if i < hands.size() else 0)
	ck(g.start_round(stakes, g.state_version, mode).ok, "opening accepted")
	return g
func stand_players(g) -> void:
	while g.phase == "player": ck(g.stand().ok, "manual challenger stands")
func distribution(g) -> Dictionary:
	var before := snap(g)
	var d: Dictionary = g.next_card_probabilities()
	ck(snap(g) == before, "probability query is pure")
	ck(d.keys().size() == 2 and d.has("remaining") and d.has("points"), "no advice/EV/order fields in distribution")
	ck(d.remaining == g.draw_pile.size() and d.points.size() == 10, "remaining count and ten point groups")
	var counts: Array = [0,0,0,0,0,0,0,0,0,0]
	for c in g.draw_pile: counts[mini(c.rank,10)-1] += 1
	var probability := 0.0
	for i in 10:
		var row: Dictionary = d.points[i]
		ck(row.size() == 3 and row.point == i+1 and row.count == counts[i], "exact unordered point count")
		var expected: float = float(counts[i]) / g.draw_pile.size() if not g.draw_pile.is_empty() else 0.0
		ck(is_equal_approx(row.probability, expected), "exact point probability")
		probability += row.probability
	ck(is_equal_approx(probability, 0.0 if g.draw_pile.is_empty() else 1.0), "distribution normalization")
	return d
func _initialize() -> void:
	test_distribution()
	test_guards()
	test_unrestricted_actions()
	test_terminal_rules()
	test_ai_unchanged()
	test_manual_round_matrix()
	print("INDEPENDENT MANUAL DEALER REVIEW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func test_distribution() -> void:
	var g = Rules.new(910)
	var d := distribution(g)
	ck(d.points[0].count == 24 and d.points[9].count == 96, "six decks A and 10/J/Q/K group")
	g.draw_pile.reverse()
	ck(g.next_card_probabilities() == d, "reversing future order cannot change probabilities")
	g.draw_pile = [{"rank":1},{"rank":10},{"rank":11},{"rank":12},{"rank":13},{"rank":2}]
	d = distribution(g)
	ck(d.points[0].count == 1 and d.points[9].count == 4, "A single group, face cards all ten")
	g.draw_pile.clear()
	distribution(g)
	g = rig([[8,8]], [10,7], [2,1])
	distribution(g)
	g.hit(); distribution(g); stand_players(g)
	var before: Dictionary = g.next_card_probabilities()
	g.dealer_hit()
	var after := distribution(g)
	ck(after.remaining == before.remaining-1, "manual dealer draw decrements denominator")
	ck(after.points[0].count == before.points[0].count-1, "drawn Ace removed exactly once")
func test_guards() -> void:
	var g = Rules.new(51)
	ck(g.dealer_mode == "ai", "AI remains default")
	reject(g,"set_dealer_mode",["robot"],"unknown mode")
	ck(g.set_dealer_mode("human").ok, "between-round mode switch")
	var version: int = g.state_version
	reject(g,"set_dealer_mode",["ai",version-1],"stale mode switch")
	reject(g,"start_round",[[0,0,0,0,0,0,0,0],version,"ai"],"invalid stakes do not commit mode")
	reject(g,"start_round",[[100,0,0,0,0,0,0,0],version,"unknown"],"invalid mode does not debit")
	reject(g,"dealer_hit",[],"before round hit")
	g = rig([[8,8]], [10,7], [2])
	reject(g,"set_dealer_mode",["ai"],"mid-player mode change")
	reject(g,"dealer_hit",[],"dealer cannot preempt challenger")
	stand_players(g)
	ck(g.dealer_advice.is_empty(), "no manual solver result on dealer entry")
	reject(g,"dealer_step",[],"automatic dealer rejected in human mode")
	reject(g,"set_dealer_mode",["ai"],"mid-dealer mode change")
	version = g.state_version
	ck(g.dealer_hit(version).ok, "manual hit accepted")
	reject(g,"dealer_hit",[version],"stale repeated hit")
	ck(g.dealer_advice.is_empty(), "manual draw never calculates advice")
	ck(g.dealer_stand().ok, "manual stand settles")
	for method in ["dealer_hit","dealer_stand","dealer_step","hit","stand"]: reject(g,method,[],"postsettlement " + method)
	ck(g.set_dealer_mode("ai").ok, "settled mode change accepted")
func test_unrestricted_actions() -> void:
	for dh in [[10,7],[10,10],[1,6],[2,2]]:
		var g = rig([[10,9]], dh, [1])
		stand_players(g)
		ck(g.can_dealer_hit() and g.can_dealer_stand(), "manual hit/stand independent of 17 threshold")
		ck(g.dealer_hit().ok and g.dealer_hand.size() == 3, "manual draws once from any nonterminal total")
		if g.phase == "dealer": ck(g.dealer_stand().ok, "manual stand after hit")
	var g = rig([[10,9]], [2,2])
	stand_players(g); ck(g.dealer_stand().ok and g.dealer_hand.size() == 2, "manual stand allowed below 17")
	ck(g.players[0].result.net == 100, "early stand uses actual total")
func test_terminal_rules() -> void:
	var g = rig([[10,9]], [10,10], [2])
	stand_players(g);g.dealer_hit()
	ck(g.phase == "settled" and g.players[0].result.net == 100, "dealer bust immediately pays once")
	g = rig([[10,10]], [2,2], [2,2,2])
	stand_players(g)
	for i in 3: ck(g.dealer_hit().ok, "dealer five-card draw")
	ck(g.phase == "settled" and g.dealer_hand.size() == 5 and g.players[0].result.net == -100, "dealer five beats ordinary20")
	g = rig([[2,2]], [2,3], [2,2,2,3,3,3])
	for i in 3: g.hit()
	for i in 3: g.dealer_hit()
	ck(g.phase == "settled" and g.players[0].result.net == 0, "both five-card hands push regardless total")
	g = rig([[1,13],[10,8]], [1,10])
	ck(g.phase == "settled" and g.players[0].result.net == 200 and g.players[1].result.net == -100, "player natural priority net2:1 against dealer natural")
	ck(g.dealer_advice.is_empty(), "natural settlement has no manual advice")
	g = rig([[1,13]], [2,2])
	ck(g.phase == "settled" and g.players[0].balance == 1200, "all naturals finish without needless dealer interaction")
func test_ai_unchanged() -> void:
	var g = rig([[10,9]], [10,7], [2], "ai")
	stand_players(g)
	ck(not g.dealer_advice.is_empty(), "AI advice still computed")
	reject(g,"dealer_hit",[],"manual dealer hit blocked in AI")
	reject(g,"dealer_stand",[],"manual dealer stand blocked in AI")
	var n := 0
	while g.phase == "dealer" and n < 10:
		ck(g.dealer_step().ok, "AI step remains functional")
		n += 1
	ck(g.phase == "settled", "AI still terminates")

func test_manual_round_matrix() -> void:
	# Exercise every supported challenger count and random physical shoe composition.
	for count in range(1,9):
		var g = Rules.new(771 + count)
		ck(g.set_dealer_mode("human").ok, "manual mode configured")
		for round_index in 12:
			if g.phase == "settled": g.next_round()
			g.reset_bankroll()
			var stakes: Array = []
			for i in 8: stakes.append(100 if i < count else 0)
			ck(g.start_round(stakes).ok, "random manual deal")
			var guard := 0
			while g.phase == "player" and guard < 40:
				if round_index % 2 == 0: g.hit()
				else: g.stand()
				guard += 1
			while g.phase == "dealer" and guard < 50:
				if round_index % 3 == 0: g.dealer_stand()
				else: g.dealer_hit()
				guard += 1
			ck(g.phase == "settled", "manual round finishes for 1 through 8 seats")
			ck(g.dealer_advice.is_empty(), "random manual mode never stores EV")
			var cards: Array = g.draw_pile + g.discard_pile + g.dealer_hand
			var ids := {}
			for p in g.players:
				cards += p.hand
				if p.bet > 0: ck(p.balance == 1000 + p.result.net, "manual settlement wallet equation")
				else: ck(p.balance == 1000 and p.hand.is_empty(), "skipped seat untouched")
			for c in cards: ids[c.id] = true
			ck(cards.size() == 312 and ids.size() == 312, "312 unique cards conserved")
	var g = rig([[1,13],[8,8]], [2,2])
	stand_players(g)
	g.discard_pile.append_array(g.draw_pile);g.draw_pile.clear()
	ck(g.dealer_hit().ok and g.phase == "settled", "empty manual shoe safely voids")
	ck(g.players[0].balance == 1200 and g.players[1].balance == 1000, "void preserves paid natural and refunds unresolved wager")
