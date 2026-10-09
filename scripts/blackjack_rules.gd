class_name BlackjackRules
extends RefCounted
## Scene-independent, single-deck blackjack using virtual coins only.
## A bet is debited once when accepted; result.payout is the entire return,
## including returned stake. Pass the last rendered state_version to reject
## stale clicks. Invalid commands never change the version or any game state.
## draw_pile.back() is the next card. Cards are recycled ONLY between rounds.

const SUITS: Array[String] = ["clubs", "diamonds", "hearts", "spades"]
const INITIAL_BALANCE: int = 1000
const MIN_BET: int = 10
const BET_STEP: int = 10
## More than enough for both hands in a single-deck round, including bust cards.
const RESHUFFLE_BELOW: int = 26

var balance: int = INITIAL_BALANCE
var phase: String = "betting"
var state_version: int = 0
var round_number: int = 0
var player_hand: Array = []
var dealer_hand: Array = []
var draw_pile: Array = []
var discard_pile: Array = []
var bet: int = 0
var initial_bet: int = 0
var result: Dictionary = {}
var dealer_revealed: bool = false
var player_acted: bool = false
var doubled: bool = false
var shoe_shuffles: int = 0

var _rng := RandomNumberGenerator.new()
var _next_draws: Array[int] = []


func _init(seed_value: int = -1) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	draw_pile = build_deck()
	_shuffle(draw_pile)
	shoe_shuffles = 1


static func build_deck() -> Array:
	var cards: Array = []
	for suit in SUITS:
		for rank in range(1, 14):
			cards.append({"id": cards.size(), "suit": suit, "rank": rank})
	return cards


static func rank_label(rank: int) -> String:
	match rank:
		1: return "A"
		11: return "J"
		12: return "Q"
		13: return "K"
	return str(rank)


static func hand_value(cards: Array) -> Dictionary:
	var total: int = 0
	var high_aces: int = 0
	for card in cards:
		var rank: int = int(card.get("rank", 0))
		if rank == 1:
			total += 11
			high_aces += 1
		else:
			total += mini(rank, 10)
	while total > 21 and high_aces > 0:
		total -= 10
		high_aces -= 1
	return {
		"total": total, "soft": high_aces > 0,
		"blackjack": cards.size() == 2 and total == 21,
		"bust": total > 21,
	}


func can_hit() -> bool:
	return phase == "player" and not result and int(hand_value(player_hand).total) < 21


func can_stand() -> bool:
	return phase == "player" and result.is_empty()


func can_double() -> bool:
	return can_hit() and player_hand.size() == 2 and not player_acted and balance >= bet


func start_round(amount: int, expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已变化，请使用当前状态重试。")
	if phase != "betting" and phase != "settled":
		return _error("请先完成当前牌局。")
	if amount < MIN_BET or amount % BET_STEP != 0:
		return _error("下注至少 10 枚，且须为 10 的整数倍。")
	if amount > balance:
		return _error("余额不足，无法接受下注。")
	if draw_pile.size() + discard_pile.size() + player_hand.size() + dealer_hand.size() < 4:
		return _error("牌堆不足，无法发牌。")
	_collect_hands()
	_prepare_shoe()
	bet = amount
	initial_bet = amount
	balance -= amount
	result.clear()
	player_acted = false
	doubled = false
	dealer_revealed = false
	round_number += 1
	phase = "player"
	for _index in 2:
		player_hand.append(draw_pile.pop_back())
		dealer_hand.append(draw_pile.pop_back())
	var player_value: Dictionary = hand_value(player_hand)
	var dealer_value: Dictionary = hand_value(dealer_hand)
	# Peek is resolved synchronously before the host can offer Hit or Double.
	if dealer_value.blackjack:
		_settle("push" if player_value.blackjack else "dealer_blackjack")
	elif player_value.blackjack:
		_settle("blackjack")
	return _success("发牌完成。")


func hit(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已变化，请使用当前状态重试。")
	if not can_hit():
		return _error("当前不能要牌。")
	player_acted = true
	if draw_pile.is_empty():
		_settle("void")
		return _success("牌堆异常耗尽，本局作废并退回全部下注。")
	var card: Dictionary = draw_pile.pop_back()
	player_hand.append(card)
	var value: Dictionary = hand_value(player_hand)
	if value.bust:
		_settle("bust")
	elif int(value.total) == 21:
		_begin_dealer()
	return _success("已要一张牌。", {"card": card.duplicate()})


func stand(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已变化，请使用当前状态重试。")
	if not can_stand():
		return _error("当前不能停牌。")
	player_acted = true
	_begin_dealer()
	return _success("玩家停牌，庄家行动。")


func double_down(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已变化，请使用当前状态重试。")
	if not can_double():
		return _error("仅未行动的初始两张牌可加倍，且余额须足够追加同额下注。")
	# Revalidate first, then debit and draw together as one synchronous command.
	balance -= bet
	bet *= 2
	doubled = true
	player_acted = true
	if draw_pile.is_empty():
		_settle("void")
		return _success("牌堆异常耗尽，本局作废并退回全部下注。")
	var card: Dictionary = draw_pile.pop_back()
	player_hand.append(card)
	if hand_value(player_hand).bust:
		_settle("bust")
	else:
		_begin_dealer()
	return _success("加倍下注，只要一张牌后自动停牌。", {"card": card.duplicate()})


func dealer_step(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已变化，请使用当前状态重试。")
	if phase != "dealer" or not result.is_empty():
		return _error("当前不是庄家行动。")
	var dealer_value: Dictionary = hand_value(dealer_hand)
	var card: Dictionary = {}
	if int(dealer_value.total) <= 16:
		if draw_pile.is_empty():
			_settle("void")
			return _success("牌堆异常耗尽，本局作废并退回全部下注。")
		card = draw_pile.pop_back()
		dealer_hand.append(card)
		dealer_value = hand_value(dealer_hand)
	# S17: soft and hard 17 both stand. A step draws at most one real card.
	if int(dealer_value.total) >= 17:
		var player_total: int = int(hand_value(player_hand).total)
		if dealer_value.bust or player_total > int(dealer_value.total):
			_settle("win")
		elif player_total == int(dealer_value.total):
			_settle("push")
		else:
			_settle("loss")
	return _success("庄家行动完成。", {"card": card.duplicate()})


func next_round(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已变化，请使用当前状态重试。")
	if phase != "settled":
		return _error("结算完成后才能开始下一局。")
	_collect_hands()
	_clear_round()
	return _success("请选择下一局下注。")


## The controller must obtain explicit UI confirmation before calling this.
## No scene load, round start, next_round, or low balance resets the bankroll.
func reset_bankroll(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已变化，请使用当前状态重试。")
	if phase != "betting" and phase != "settled":
		return _error("请先完成当前牌局，再重置虚拟余额。")
	_collect_hands()
	_clear_round()
	balance = INITIAL_BALANCE
	return _success("虚拟余额已重置为 1000 枚。")


## Test/preview hook. The next opening deal is P,D,P,D, then subsequent draws.
## Validated IDs reorder the existing full deck next round, never clone cards.
## This hook neither starts a round nor changes the bankroll.
func set_next_draws(card_ids: Array, expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已变化，请使用当前状态重试。")
	if phase != "betting" and phase != "settled":
		return _error("只能在两局之间指定演示牌序。")
	var seen: Dictionary = {}
	for card_id in card_ids:
		if typeof(card_id) != TYPE_INT or card_id < 0 or card_id >= 52 or seen.has(card_id):
			return _error("演示牌序须为互不重复的 0 至 51 卡牌 ID。")
		seen[card_id] = true
	_next_draws.assign(card_ids)
	return _success("下一局演示牌序已设置。")


func snapshot() -> Dictionary:
	return {
		"balance": balance, "phase": phase, "state_version": state_version,
		"round_number": round_number, "bet": bet, "initial_bet": initial_bet,
		"player_hand": player_hand.duplicate(true), "dealer_hand": dealer_hand.duplicate(true),
		"draw_pile": draw_pile.duplicate(true), "discard_pile": discard_pile.duplicate(true),
		"result": result.duplicate(true), "dealer_revealed": dealer_revealed,
		"player_acted": player_acted, "doubled": doubled, "shoe_shuffles": shoe_shuffles,
	}


func _clear_round() -> void:
	phase = "betting"
	bet = 0
	initial_bet = 0
	result.clear()
	player_acted = false
	doubled = false
	dealer_revealed = false


func _collect_hands() -> void:
	discard_pile.append_array(player_hand)
	discard_pile.append_array(dealer_hand)
	player_hand.clear()
	dealer_hand.clear()


func _prepare_shoe() -> void:
	if draw_pile.size() < RESHUFFLE_BELOW or not _next_draws.is_empty():
		draw_pile.append_array(discard_pile)
		discard_pile.clear()
		_shuffle(draw_pile)
		shoe_shuffles += 1
	if _next_draws.is_empty():
		return
	var ordered: Array = []
	for card_id in _next_draws:
		for index in draw_pile.size():
			if int(draw_pile[index].id) == card_id:
				ordered.append(draw_pile[index])
				draw_pile.remove_at(index)
				break
	ordered.reverse()
	draw_pile.append_array(ordered)
	_next_draws.clear()


func _shuffle(cards: Array) -> void:
	for index in range(cards.size() - 1, 0, -1):
		var other: int = _rng.randi_range(0, index)
		var card: Dictionary = cards[index]
		cards[index] = cards[other]
		cards[other] = card


func _begin_dealer() -> void:
	phase = "dealer"
	dealer_revealed = true


func _settle(outcome: String) -> void:
	# Defense in depth against callbacks or old animation completions.
	if phase == "settled" or not result.is_empty():
		return
	var payout: int = 0
	match outcome:
		"blackjack": payout = bet + int(bet * 3 / 2)
		"win": payout = bet * 2
		"push", "void": payout = bet
	balance += payout
	result = {
		"outcome": outcome, "payout": payout, "net": payout - bet,
		"bet": bet, "initial_bet": initial_bet, "doubled": doubled,
		"player_total": int(hand_value(player_hand).total),
		"dealer_total": int(hand_value(dealer_hand).total),
		"round_number": round_number,
	}
	phase = "settled"
	dealer_revealed = true


func _stale(expected_version: int) -> bool:
	return expected_version >= 0 and expected_version != state_version


func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message, "state_version": state_version}


func _success(message: String, extra: Dictionary = {}) -> Dictionary:
	state_version += 1
	var response: Dictionary = {"ok": true, "message": message, "state_version": state_version}
	response.merge(extra.duplicate(true))
	return response
