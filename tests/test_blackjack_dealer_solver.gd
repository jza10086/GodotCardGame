extends SceneTree
const Solver = preload("res://scripts/blackjack_dealer_solver.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func cards(ranks: Array) -> Array:
	var result: Array = []
	for rank in ranks: result.append({"rank": rank})
	return result

func player(ranks: Array, bet: int = 100) -> Dictionary:
	return {"hand": cards(ranks), "bet": bet, "result": {}}

func solve(dealer: Array, players: Array, shoe: Array) -> Dictionary:
	return Solver.choose_action(cards(dealer), players, Solver.counts_from_cards(cards(shoe)))

func near(a: float, b: float) -> bool:
	return absf(a-b) < 0.0000001

func _initialize() -> void:
	var r: Dictionary = solve([10,8], [player([10,7],100),player([10,10],10)], [3,10])
	check(r.action == "stand" and near(r.stand_ev,90) and near(r.hit_ev,0), "large winning stake favors stand")
	r = solve([10,8], [player([10,7],10),player([10,10],100)], [3,10])
	check(r.action == "hit" and near(r.stand_ev,-90) and near(r.hit_ev,0), "stake weighting changes optimal action")
	check(near(r.outcome_probabilities.get("total_21",0),0.5) and near(r.outcome_probabilities.get("dealer_bust",0),0.5), "exact terminal probabilities")
	r = solve([5,5,5,5], [player([2,3,4,5,6])], [1,10])
	check(r.action == "hit" and near(r.stand_ev,-100) and near(r.hit_ev,-50), "five-card player is not an irrevocable loss")
	r = solve([1,2,3,5], [player([10,5,6])], [1])
	check(r.action == "hit" and near(r.stand_ev,0) and near(r.hit_ev,100), "free dealer can hit soft 21 for five-card win")
	r = solve([1,1,1,1,1], [player([10,10]),player([2,2,2,2,2])], [10])
	check(r.action == "stand" and r.hit_ev == null and near(r.best_ev,100), "dealer five wins ordinary and pushes five")
	r = solve([10,10,2,2,2], [player([2,2,2,2,2])], [1])
	check(near(r.best_ev,-100), "bust overrides five-card count")
	r = solve([10,6], [player([10,10,2])], [10])
	check(r.action == "stand" and near(r.stand_ev,100) and near(r.hit_ev,100), "player bust stays won even if dealer busts; ties stand")
	var paid: Dictionary = player([1,10],1000)
	paid.result = {"outcome":"blackjack","net":2000}
	r = solve([10,8], [paid,player([10,10],100)], [3,10])
	check(near(r.stand_ev,-100) and near(r.hit_ev,0), "already paid natural excluded from objective")
	r = solve([10,8], [player([1,10],1000),player([10,10],100)], [3,10])
	check(near(r.stand_ev,-2100) and near(r.hit_ev,-2000), "unsettled natural is a fixed loss")
	r = solve([10,6], [player([10,7])], [])
	check(r.action == "stand" and r.hit_ev == null, "empty shoe cannot be sampled")
	var dealer: Array = cards([1,2])
	var players: Array = [player([10,8]),player([2,2,2,2,2])]
	var shoe: Array = cards([1,2,3,4,5,6,7,8,9,10,11,12,13])
	var counts: Array = Solver.counts_from_cards(shoe)
	check(counts == [1,1,1,1,1,1,1,1,1,4], "ten-valued ranks aggregated")
	var before: Array = [dealer.duplicate(true), players.duplicate(true), counts.duplicate()]
	var baseline: Dictionary = Solver.choose_action(dealer,players,counts)
	check(before == [dealer,players,counts], "solver leaves inputs unchanged")
	for i in 30:
		shoe.shuffle()
		var shuffled: Dictionary = Solver.choose_action(dealer,players,Solver.counts_from_cards(shoe))
		check(shuffled == baseline, "shoe order cannot change decision %d" % i)
	var probability_sum: float = 0
	for probability in baseline.outcome_probabilities.values(): probability_sum += float(probability)
	check(near(probability_sum,1), "optimal terminal probability sums to one")
	check(baseline.states_evaluated < 1500, "five-card horizon is bounded")
	print("Blackjack dealer solver: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
