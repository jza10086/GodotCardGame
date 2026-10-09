class_name BlackjackDealerSolver
extends RefCounted
## Exact finite-shoe expectimax for the current round, after opening naturals.
## Information boundary: receives only rank counts, never the shuffled shoe.
## Players and input arrays are never mutated. Ten-valued ranks share one bucket.
## Five non-busting cards terminate the dealer: win ordinary hands, push five cards.

var _opponents: Array = []
var _memo: Dictionary = {}
var _states: int = 0

static func counts_from_cards(cards: Array) -> Array:
	var counts: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for card in cards:
		var rank: int = int(card.get("rank", 0))
		assert(rank >= 1 and rank <= 13, "Card rank must be 1..13")
		counts[mini(rank, 10) - 1] += 1
	return counts

static func choose_action(dealer_hand: Array, players: Array, remaining_counts: Array) -> Dictionary:
	assert(remaining_counts.size() == 10, "Expected counts for A,2..9,10")
	var solver = load("res://scripts/blackjack_dealer_solver.gd").new()
	var counts: Array = remaining_counts.duplicate()
	for count in counts:
		assert(typeof(count) == TYPE_INT and count >= 0, "Counts must be nonnegative integers")
	for player in players:
		if int(player.get("bet", 0)) <= 0 or not player.get("result", {}).is_empty():
			continue
		var hand: Array = player.get("hand", [])
		var values: Dictionary = _values(hand)
		solver._opponents.append({"total": values.total, "bust": values.total > 21,
			"five": hand.size() >= 5 and values.total <= 21,
			"natural": hand.size() == 2 and values.total == 21, "bet": int(player.bet)})
	var initial: Dictionary = _values(dealer_hand)
	var answer: Dictionary = solver._solve(initial.hard, initial.aces, dealer_hand.size(), counts).duplicate(true)
	answer["states_evaluated"] = solver._states
	answer["information_mode"] = "remaining_rank_counts"
	answer["method"] = "exact_expectimax"
	return answer

static func _values(cards: Array) -> Dictionary:
	var hard: int = 0
	var aces: int = 0
	for card in cards:
		var rank: int = int(card.get("rank", 0))
		assert(rank >= 1 and rank <= 13, "Card rank must be 1..13")
		hard += mini(rank, 10)
		if rank == 1: aces += 1
	return {"hard": hard, "aces": aces, "total": hard + 10 if aces > 0 and hard + 10 <= 21 else hard}

func _utility(total: int, card_count: int) -> float:
	var value: float = 0.0
	var dealer_bust: bool = total > 21
	var dealer_five: bool = card_count >= 5 and not dealer_bust
	for player in _opponents:
		var bet: float = float(player.bet)
		# Already-paid naturals are omitted above; unresolved naturals are fixed losses.
		if player.natural: value -= 2.0 * bet
		elif player.bust: value += bet
		elif dealer_bust: value -= bet
		elif player.five:
			if not dealer_five: value -= bet
		elif dealer_five or total > int(player.total): value += bet
		elif total < int(player.total): value -= bet
	return value

func _solve(hard: int, aces: int, card_count: int, counts: Array) -> Dictionary:
	var key: String = str(hard) + ":" + str(aces) + ":" + str(card_count) + ":" + str(counts)
	if _memo.has(key): return _memo[key]
	_states += 1
	var total: int = hard + 10 if aces > 0 and hard + 10 <= 21 else hard
	var stand_ev: float = _utility(total, card_count)
	var label: String = "dealer_bust" if total > 21 else ("dealer_five" if card_count >= 5 else "total_%d" % total)
	var stop_probabilities: Dictionary = {label: 1.0}
	var result: Dictionary = {"action": "stand", "stand_ev": stand_ev, "hit_ev": null,
		"best_ev": stand_ev, "outcome_probabilities": stop_probabilities, "hit_outcome_probabilities": {}}
	var remaining: int = 0
	for count in counts: remaining += int(count)
	if total > 21 or card_count >= 5 or remaining == 0 or _opponents.is_empty():
		_memo[key] = result
		return result
	var hit_ev: float = 0.0
	var hit_probabilities: Dictionary = {}
	for index in 10:
		var count: int = int(counts[index])
		if count == 0: continue
		var probability: float = float(count) / float(remaining)
		counts[index] -= 1
		var next: Dictionary = _solve(hard + index + 1, aces + (1 if index == 0 else 0), card_count + 1, counts)
		counts[index] += 1
		hit_ev += probability * float(next.best_ev)
		for outcome in next.outcome_probabilities:
			hit_probabilities[outcome] = float(hit_probabilities.get(outcome, 0.0)) + probability * float(next.outcome_probabilities[outcome])
	result.hit_ev = hit_ev
	result.hit_outcome_probabilities = hit_probabilities
	# Prefer stand for ties, including accumulated floating-point roundoff.
	var tolerance: float = 1e-12 * maxf(1.0, maxf(absf(stand_ev), absf(hit_ev)))
	if hit_ev > stand_ev + tolerance:
		result.action = "hit"
		result.best_ev = hit_ev
		result.outcome_probabilities = hit_probabilities
	_memo[key] = result
	return result
