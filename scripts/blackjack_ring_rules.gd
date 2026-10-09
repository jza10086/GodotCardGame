class_name BlackjackRingRules
extends RefCounted
## Eight independent virtual bankrolls versus one S17 dealer. Six physical decks.
## Commands are synchronous, version checked and debit/pay each stake once.
## Opening order is eligible P0..P7, dealer, repeated twice. Draw pile back is top.

const BaseRules = preload("res://scripts/blackjack_rules.gd")
const SUITS: Array[String] = ["clubs", "diamonds", "hearts", "spades"]
const INITIAL_BALANCE: int = 1000
const MIN_BET: int = 10
const BET_STEP: int = 10
const PLAYER_COUNT: int = 8
const DECK_COUNT: int = 6
const SHOE_SIZE: int = 312
const RESHUFFLE_BELOW: int = 104
var phase: String = "betting"
var current_player: int = -1
var players: Array = []
var dealer_hand: Array = []
var dealer_revealed: bool = false
var draw_pile: Array = []
var discard_pile: Array = []
var state_version: int = 0
var round_number: int = 0
var shoe_shuffles: int = 0
var _rng := RandomNumberGenerator.new()
var _next_draws: Array[int] = []

func _init(seed_value: int = -1) -> void:
	if seed_value < 0: _rng.randomize()
	else: _rng.seed = seed_value
	for i in PLAYER_COUNT:
		players.append({"id": i, "name": "你" if i == 0 else "机器人 %d" % i,
			"hand": [], "balance": INITIAL_BALANCE, "bet": 0, "initial_bet": 0,
			"acted": false, "doubled": false, "status": "waiting", "result": {}})
	draw_pile = build_deck()
	_shuffle(draw_pile)
	shoe_shuffles = 1

static func build_deck() -> Array:
	var cards: Array = []
	for deck in DECK_COUNT:
		for suit in SUITS:
			for rank in range(1, 14):
				cards.append({"id": cards.size(), "suit": suit, "rank": rank, "deck": deck})
	return cards

static func hand_value(cards: Array) -> Dictionary:
	return BaseRules.hand_value(cards)

static func rank_label(rank: int) -> String:
	return BaseRules.rank_label(rank)

## Pure basic strategy: no opponent hands, hole card, shoe, RNG or model reference.
## S17, no split/insurance. A soft total keeps its usable ace after a hit.
static func decision(hand: Array, dealer_upcard: Dictionary, balance: int, bet: int, can_double: bool) -> String:
	var value: Dictionary = hand_value(hand)
	var total: int = int(value.total)
	var up: int = int(dealer_upcard.get("rank", 10))
	up = 11 if up == 1 else mini(up, 10)
	var double_allowed: bool = can_double and hand.size() == 2 and bet > 0 and balance >= bet
	if total >= 21: return "stand"
	if value.soft:
		if total >= 19: return "stand"
		if total == 18:
			if double_allowed and up >= 3 and up <= 6: return "double"
			return "stand" if up <= 8 else "hit"
		if double_allowed:
			if total == 17 and up >= 3 and up <= 6: return "double"
			if total >= 15 and total <= 16 and up >= 4 and up <= 6: return "double"
			if total >= 13 and total <= 14 and up >= 5 and up <= 6: return "double"
		return "hit"
	if total >= 17: return "stand"
	if total >= 13 and total <= 16: return "stand" if up <= 6 else "hit"
	if total == 12: return "stand" if up >= 4 and up <= 6 else "hit"
	if double_allowed:
		if total == 11 and up <= 10: return "double"
		if total == 10 and up <= 9: return "double"
		if total == 9 and up >= 3 and up <= 6: return "double"
	return "hit"

func can_hit() -> bool:
	return phase == "player" and current_player >= 0 and int(hand_value(players[current_player].hand).total) < 21

func can_stand() -> bool:
	return phase == "player" and current_player >= 0

func can_double() -> bool:
	if not can_hit(): return false
	var p: Dictionary = players[current_player]
	return p.hand.size() == 2 and not p.acted and p.balance >= p.bet

func start_round(amount: int, expected_version: int = -1) -> Dictionary:
	if _stale(expected_version): return _error("牌局已变化，请重试。")
	if phase != "betting" and phase != "settled": return _error("请先完成当前牌局。")
	var spectating: bool = amount == 0 and players[0].balance < MIN_BET
	if not spectating and (amount < MIN_BET or amount % BET_STEP != 0): return _error("下注须为至少 10 的整十数。")
	if amount > players[0].balance: return _error("余额不足。")
	var participants: int = 0
	for i in PLAYER_COUNT:
		if (i == 0 and not spectating) or (i > 0 and players[i].balance >= MIN_BET): participants += 1
	if participants == 0: return _error("所有玩家余额不足，请重置虚拟金币。")
	var available: int = draw_pile.size() + discard_pile.size() + dealer_hand.size()
	for p in players: available += p.hand.size()
	if available < (participants + 1) * 2: return _error("牌堆不足，无法发牌。")
	_collect_hands()
	_clear_round()
	_prepare_shoe()
	if draw_pile.size() < (participants + 1) * 2: return _error("牌堆不足，无法发牌。")
	round_number += 1
	for i in PLAYER_COUNT:
		var p: Dictionary = players[i]
		var stake: int = amount if i == 0 else mini(100, int(p.balance / BET_STEP) * BET_STEP)
		if stake < MIN_BET:
			p.status = "skipped"
			continue
		p.bet = stake
		p.initial_bet = stake
		p.balance -= stake
		p.status = "playing"
	phase = "player"
	for _pass in 2:
		for p in players:
			if p.bet > 0: p.hand.append(draw_pile.pop_back())
		dealer_hand.append(draw_pile.pop_back())
	for p in players:
		if p.bet > 0 and hand_value(p.hand).blackjack: p.status = "blackjack"
	if hand_value(dealer_hand).blackjack:
		_settle_all()
	else:
		current_player = -1
		_advance_player()
	return _success("八人牌局已发牌。")

func hit(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version): return _error("牌局已变化，请重试。")
	if not can_hit(): return _error("当前不能要牌。")
	var p: Dictionary = players[current_player]
	p.acted = true
	if draw_pile.is_empty(): return _void_round()
	var card: Dictionary = draw_pile.pop_back()
	p.hand.append(card)
	var value: Dictionary = hand_value(p.hand)
	if value.bust:
		p.status = "bust"
		_advance_player()
	elif value.total == 21:
		p.status = "stood"
		_advance_player()
	return _success("已要一张牌。", {"card": card.duplicate()})

func stand(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version): return _error("牌局已变化，请重试。")
	if not can_stand(): return _error("当前不能停牌。")
	players[current_player].acted = true
	players[current_player].status = "stood"
	_advance_player()
	return _success("玩家停牌。")

func double_down(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version): return _error("牌局已变化，请重试。")
	if not can_double(): return _error("仅未行动的初始两张牌且余额充足时可加倍。")
	var p: Dictionary = players[current_player]
	p.balance -= p.bet
	p.bet *= 2
	p.acted = true
	p.doubled = true
	if draw_pile.is_empty(): return _void_round()
	var card: Dictionary = draw_pile.pop_back()
	p.hand.append(card)
	p.status = "bust" if hand_value(p.hand).bust else "stood"
	_advance_player()
	return _success("加倍后只补一张，自动停牌。", {"card": card.duplicate()})

func ai_step(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version): return _error("牌局已变化，请重试。")
	if phase != "player" or current_player <= 0: return _error("当前不是机器人行动。")
	var p: Dictionary = players[current_player]
	var choice: String = decision(p.hand.duplicate(true), dealer_hand[0].duplicate(), p.balance, p.bet, can_double())
	match choice:
		"double": return double_down(expected_version)
		"hit": return hit(expected_version)
	return stand(expected_version)

func dealer_step(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version): return _error("牌局已变化，请重试。")
	if phase != "dealer": return _error("当前不是庄家行动。")
	var card: Dictionary = {}
	if hand_value(dealer_hand).total <= 16:
		if draw_pile.is_empty(): return _void_round()
		card = draw_pile.pop_back()
		dealer_hand.append(card)
	if hand_value(dealer_hand).total >= 17: _settle_all()
	return _success("庄家行动完成。", {"card": card.duplicate()})

func next_round(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version): return _error("牌局已变化，请重试。")
	if phase != "settled": return _error("请先完成本局结算。")
	_collect_hands()
	_clear_round()
	return _success("请选择下一局下注。")

## Host must obtain UI confirmation. Replace all eight balances, never add funds.
func reset_bankroll(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version): return _error("牌局已变化，请重试。")
	if phase != "settled" and phase != "betting": return _error("请先完成本局。")
	_collect_hands()
	_clear_round()
	for p in players: p.balance = INITIAL_BALANCE
	return _success("八位玩家虚拟余额已重置为 1000。")

func set_next_draws(card_ids: Array, expected_version: int = -1) -> Dictionary:
	if _stale(expected_version): return _error("牌局已变化，请重试。")
	if phase != "settled" and phase != "betting": return _error("仅两局之间可设置演示牌序。")
	var seen: Dictionary = {}
	for card_id in card_ids:
		if typeof(card_id) != TYPE_INT or card_id < 0 or card_id >= SHOE_SIZE or seen.has(card_id): return _error("牌序须为互不重复的 0 至 311 卡牌 ID。")
		seen[card_id] = true
	_next_draws.assign(card_ids)
	return _success("下一局牌序已设置。")

## Internal snapshot for the local controller/tests, NOT a network privacy API.
func snapshot() -> Dictionary:
	return {"phase": phase, "current_player": current_player, "players": players.duplicate(true),
		"dealer_hand": dealer_hand.duplicate(true), "dealer_revealed": dealer_revealed,
		"draw_pile": draw_pile.duplicate(true), "discard_pile": discard_pile.duplicate(true),
		"state_version": state_version, "round_number": round_number, "shoe_shuffles": shoe_shuffles}

func _advance_player() -> void:
	for i in range(current_player + 1, PLAYER_COUNT):
		if players[i].status == "playing":
			current_player = i
			return
	current_player = -1
	dealer_revealed = true
	# Naturals already beat every non-natural dealer; no dealer draw is needed
	# if every active hand is either busted or natural.
	var needs_comparison: bool = false
	for p in players:
		if p.bet > 0 and p.status != "bust" and p.status != "blackjack": needs_comparison = true
	if needs_comparison: phase = "dealer"
	else: _settle_all()

func _settle_all(voided: bool = false) -> void:
	if phase == "settled": return
	var dealer_value: Dictionary = hand_value(dealer_hand)
	for p in players:
		if p.bet == 0 or not p.result.is_empty(): continue
		var value: Dictionary = hand_value(p.hand)
		var outcome: String = "loss"
		if voided: outcome = "void"
		elif dealer_value.blackjack: outcome = "push" if value.blackjack else "dealer_blackjack"
		elif value.blackjack: outcome = "blackjack"
		elif value.bust: outcome = "bust"
		elif dealer_value.bust or value.total > dealer_value.total: outcome = "win"
		elif value.total == dealer_value.total: outcome = "push"
		var payout: int = 0
		match outcome:
			"blackjack": payout = p.bet + int(p.bet * 3 / 2)
			"win": payout = p.bet * 2
			"push", "void": payout = p.bet
		p.balance += payout
		p.result = {"outcome": outcome, "payout": payout, "net": payout - p.bet,
			"bet": p.bet, "initial_bet": p.initial_bet, "doubled": p.doubled,
			"player_total": value.total, "dealer_total": dealer_value.total, "round_number": round_number}
		p.status = "settled"
	phase = "settled"
	current_player = -1
	dealer_revealed = true

func _void_round() -> Dictionary:
	_settle_all(true)
	return _success("牌堆异常耗尽，本局作废并退回所有下注。")

func _collect_hands() -> void:
	for p in players:
		discard_pile.append_array(p.hand)
		p.hand.clear()
	discard_pile.append_array(dealer_hand)
	dealer_hand.clear()

func _clear_round() -> void:
	phase = "betting"
	current_player = -1
	dealer_revealed = false
	for p in players:
		p.bet = 0
		p.initial_bet = 0
		p.acted = false
		p.doubled = false
		p.status = "waiting"
		p.result = {}

func _prepare_shoe() -> void:
	if draw_pile.size() < RESHUFFLE_BELOW or not _next_draws.is_empty():
		draw_pile.append_array(discard_pile)
		discard_pile.clear()
		_shuffle(draw_pile)
		shoe_shuffles += 1
	if _next_draws.is_empty(): return
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

func _stale(expected_version: int) -> bool:
	return expected_version >= 0 and expected_version != state_version

func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message, "state_version": state_version}

func _success(message: String, extra: Dictionary = {}) -> Dictionary:
	state_version += 1
	var response: Dictionary = {"ok": true, "message": message, "state_version": state_version}
	response.merge(extra.duplicate(true))
	return response
