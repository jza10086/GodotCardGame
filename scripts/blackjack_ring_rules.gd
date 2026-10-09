class_name BlackjackRingRules
extends RefCounted
## Eight independent virtual bankrolls versus one unrestricted expected-profit dealer. Six physical decks.
## Commands are synchronous, version checked and debit/pay each stake once.
## Opening order is eligible P0..P7, dealer, repeated twice. Draw pile back is top.

const DealerSolver = preload("res://scripts/blackjack_dealer_solver.gd")
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
var dealer_advice: Dictionary = {}
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
		players.append({"id": i, "name": "玩家 %d" % (i + 1),
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

func can_hit() -> bool:
	return phase == "player" and current_player >= 0 and int(hand_value(players[current_player].hand).total) < 21

func can_stand() -> bool:
	return phase == "player" and current_player >= 0

func can_double() -> bool:
	if not can_hit(): return false
	var p: Dictionary = players[current_player]
	return p.hand.size() == 2 and not p.acted and p.balance >= p.bet

## Explicit local-human stakes for all eight fixed seats. Zero voluntarily skips.
func start_round(stakes: Array, expected_version: int = -1) -> Dictionary:
	if _stale(expected_version): return _error("牌局已变化，请重试。")
	if phase != "betting" and phase != "settled": return _error("请先完成当前牌局。")
	if stakes.size() != PLAYER_COUNT: return _error("请明确全部八个座位的下注；0 为跳过。")
	var participants: int = 0
	for i in PLAYER_COUNT:
		if typeof(stakes[i]) != TYPE_INT: return _error("下注须为整数。")
		var stake: int = stakes[i]
		if stake < 0 or stake % BET_STEP != 0: return _error("下注须为非负整十数；0 为跳过。")
		if stake > players[i].balance: return _error("%d号玩家余额不足。" % (i + 1))
		if stake > 0: participants += 1
	if participants == 0: return _error("至少一位玩家需要下注；余额不足可重置虚拟金币。")
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
		var stake: int = stakes[i]
		if stake == 0:
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
	# House priority: player naturals pay immediately, including against dealer natural.
	for p in players:
		if p.bet > 0 and hand_value(p.hand).blackjack: _pay_player(p, "blackjack", p.bet * 3)
	if hand_value(dealer_hand).blackjack:
		_settle_all()
	else:
		current_player = -1
		_advance_player()
	return _success("手动玩家牌局已发牌。")

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
	elif p.hand.size() >= 5:
		p.status = "five_card"
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

## Compatibility rejection: there are no player bots or automatic player decisions.
func ai_step(_expected_version: int = -1) -> Dictionary:
	return _error("全部玩家由本地真人操作；只有庄家自动行动。")

func dealer_step(expected_version: int = -1) -> Dictionary:
	if _stale(expected_version): return _error("牌局已变化，请重试。")
	if phase != "dealer": return _error("当前不是庄家行动。")
	var card: Dictionary = {}
	var advice: Dictionary = DealerSolver.choose_action(dealer_hand, players, DealerSolver.counts_from_cards(draw_pile))
	dealer_advice = advice.duplicate(true)
	if advice.action == "hit":
		if draw_pile.is_empty(): return _void_round()
		card = draw_pile.pop_back()
		dealer_hand.append(card)
		if hand_value(dealer_hand).bust or dealer_hand.size() >= 5: _settle_all()
	else: _settle_all()
	return _success("庄家按最大期望净收益行动。", {"card": card.duplicate(), "advice": advice})

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
		"dealer_hand": dealer_hand.duplicate(true), "dealer_revealed": dealer_revealed, "dealer_advice": dealer_advice.duplicate(true),
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
		if p.bet > 0 and p.result.is_empty() and p.status != "bust": needs_comparison = true
	if needs_comparison:
		phase = "dealer"
		dealer_advice = DealerSolver.choose_action(dealer_hand, players, DealerSolver.counts_from_cards(draw_pile))
	else: _settle_all()

func _settle_all(voided: bool = false) -> void:
	if phase == "settled": return
	var dealer_value: Dictionary = hand_value(dealer_hand)
	for p in players:
		if p.bet == 0 or not p.result.is_empty(): continue
		var value: Dictionary = hand_value(p.hand)
		var outcome: String = "loss"
		if voided: outcome = "void"
		elif value.bust: outcome = "bust"
		elif dealer_value.blackjack: outcome = "dealer_blackjack"
		elif value.blackjack: outcome = "blackjack"
		elif p.hand.size() >= 5 and not dealer_value.bust and dealer_hand.size() >= 5: outcome = "push"
		elif p.hand.size() >= 5: outcome = "five_card"
		elif not dealer_value.bust and dealer_hand.size() >= 5: outcome = "loss"
		elif dealer_value.bust or value.total > dealer_value.total: outcome = "win"
		elif value.total == dealer_value.total: outcome = "push"
		var payout: int = 0
		match outcome:
			"blackjack": payout = p.bet * 3
			"win", "five_card": payout = p.bet * 2
			"push", "void": payout = p.bet
		_pay_player(p, outcome, payout)
	phase = "settled"
	current_player = -1
	dealer_revealed = true

func _pay_player(p: Dictionary, outcome: String, payout: int) -> void:
	if not p.result.is_empty(): return
	p.balance += payout
	p.result = {"outcome": outcome, "payout": payout, "net": payout - p.bet,
		"bet": p.bet, "initial_bet": p.initial_bet, "doubled": p.doubled,
		"player_total": hand_value(p.hand).total, "dealer_total": hand_value(dealer_hand).total, "round_number": round_number}
	p.status = "settled"

func _void_round() -> Dictionary:
	_settle_all(true)
	return _success("牌堆异常耗尽，未结算手牌作废并退回下注；已即时结算奖励保留。")

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
	dealer_advice.clear()
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
