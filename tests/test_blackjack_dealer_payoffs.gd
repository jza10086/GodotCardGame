extends SceneTree
## Cross-check the solver's stop utility against the actual payout model.
const Solver = preload("res://scripts/blackjack_dealer_solver.gd")
const Rules = preload("res://scripts/blackjack_ring_rules.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func random_hand(rng: RandomNumberGenerator) -> Array:
	var cards: Array = []
	for i in rng.randi_range(2,5): cards.append({"rank":rng.randi_range(1,13)})
	return cards

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 761294
	var model = Rules.new(927)
	var compared: int = 0
	while compared < 1000:
		var dealer: Array = random_hand(rng)
		if Rules.hand_value(dealer).blackjack: continue # Opening natural has already ended the round.
		model._clear_round()
		model.dealer_hand = dealer
		model.phase = "dealer"
		for p in model.players:
			var hand: Array = random_hand(rng)
			# Naturals are paid before this phase; emulate that boundary explicitly.
			p.hand = hand
			p.bet = rng.randi_range(1,100) * 10
			p.initial_bet = p.bet
			p.status = "stood"
			if Rules.hand_value(hand).blackjack:
				model._pay_player(p,"blackjack",p.bet*3)
		var pending: Array = []
		for p in model.players:
			if p.result.is_empty(): pending.append(p.id)
		var advice: Dictionary = Solver.choose_action(dealer,model.players,[0,0,0,0,0,0,0,0,0,0])
		model._settle_all()
		var actual: int = 0
		for index in pending: actual -= int(model.players[index].result.net)
		check(absf(advice.stand_ev - actual) < 0.000001,"actual settlement matches stand utility %d" % compared)
		compared += 1
	print("Blackjack dealer/model payoffs: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
