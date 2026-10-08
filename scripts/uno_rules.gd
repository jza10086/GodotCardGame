class_name UnoRules
extends RefCounted
## Synchronous, scene-independent classic 108-card UNO-style round.
## Player 0 sits left of the initial dealer (the final player). Card IDs remain
## unique through draws and recycling. A +4 bluff is allowed and challengeable.
## Mutating commands validate before changing state and return {ok, message}.

const COLORS: Array[String] = ["red", "yellow", "green", "blue"]
const ACTIONS: Array[String] = ["skip", "reverse", "draw_two"]

var hands: Array = []
var draw_pile: Array = []
var discard_pile: Array = []
var current_player: int = -1
var direction: int = 1
var active_color: String = ""
var phase: String = "idle"
var winner: int = -1
var score: int = 0
var finish_reason: String = ""
var drawn_card_id: int = -1
var pending_draw: int = 0
var pending_winner: int = -1
var challenge_target: int = -1
var challenge_offender: int = -1
var uno_player: int = -1
var uno_announced: bool = false

var _rng := RandomNumberGenerator.new()
var _challenge_illegal: bool = false
var _challenge_hand: Array = []
var _empty_passes: int = 0
var _empty_draw_blocked: bool = false


static func build_deck() -> Array:
	var deck: Array = []
	for color in COLORS:
		deck.append({"id": deck.size(), "color": color, "value": "0"})
		for number in range(1, 10):
			for _copy in 2:
				deck.append({"id": deck.size(), "color": color, "value": str(number)})
		for value in ACTIONS:
			for _copy in 2:
				deck.append({"id": deck.size(), "color": color, "value": value})
	for value in ["wild", "draw_four"]:
		for _copy in 4:
			deck.append({"id": deck.size(), "color": "wild", "value": value})
	return deck


func start_game(player_count: int, seed_value: int = 0) -> Dictionary:
	if player_count < 2 or player_count > 8:
		return _error("请选择 2 至 8 位玩家。")
	hands.clear()
	for _player in player_count:
		hands.append([])
	draw_pile = build_deck()
	discard_pile.clear()
	_rng.seed = seed_value
	_shuffle(draw_pile)
	current_player = 0
	direction = 1
	active_color = ""
	phase = "playing"
	winner = -1
	score = 0
	finish_reason = ""
	drawn_card_id = -1
	pending_draw = 0
	pending_winner = -1
	challenge_target = -1
	challenge_offender = -1
	_challenge_illegal = false
	_challenge_hand.clear()
	_close_uno_window()
	_empty_passes = 0
	_empty_draw_blocked = false
	for _round in 7:
		for player in player_count:
			hands[player].append(draw_pile.pop_back())
	var first: Dictionary = draw_pile.pop_back()
	while first.value == "draw_four":
		draw_pile.append(first)
		_shuffle(draw_pile)
		first = draw_pile.pop_back()
	discard_pile.append(first)
	active_color = first.color
	match first.value:
		"wild":
			active_color = ""
			phase = "choose_color"
		"skip":
			current_player = 1
		"reverse":
			direction = -1
			current_player = player_count - 1
		"draw_two":
			_draw_many(0, 2)
			current_player = 1
	return _success("新一局开始。", {"initial_card": first.duplicate(), "player_count": player_count})


func choose_initial_color(player: int, color: String) -> Dictionary:
	if phase != "choose_color" or player != current_player:
		return _error("由首位玩家选择起始牌的颜色。")
	if not COLORS.has(color):
		return _error("请选择红色、黄色、绿色或蓝色。")
	active_color = color
	phase = "playing"
	return _success("起始万能牌的颜色已确定。")


func top_card() -> Dictionary:
	return {} if discard_pile.is_empty() else discard_pile.back().duplicate()


## Includes Wild Draw Four bluffs; can_play_draw_four exposes lawful +4 use.
func legal_indices(player: int) -> Array[int]:
	var result: Array[int] = []
	if not _valid_player(player) or player != current_player or phase not in ["playing", "drawn"]:
		return result
	for index in hands[player].size():
		var card: Dictionary = hands[player][index]
		if phase == "drawn" and card.id != drawn_card_id:
			continue
		if _matches(card):
			result.append(index)
	return result


## Matching the previous COLOR prohibits +4; matching only its symbol does not.
func can_play_draw_four(player: int) -> bool:
	if not _valid_player(player) or not COLORS.has(active_color):
		return false
	for card in hands[player]:
		if card.color == active_color:
			return false
	return true


func play_card(player: int, index: int, color: String = "", announce: bool = false) -> Dictionary:
	if not _valid_player(player) or player != current_player or phase not in ["playing", "drawn"]:
		return _error("现在不能由这位玩家出牌。")
	if index < 0 or index >= hands[player].size():
		return _error("手牌中没有这张牌。")
	var card: Dictionary = hands[player][index]
	if phase == "drawn" and card.id != drawn_card_id:
		return _error("摸牌后只能打出刚摸到的那张牌。")
	if not _matches(card):
		return _error("请匹配当前颜色、数字或符号，也可以使用万能牌。")
	if card.color == "wild" and not COLORS.has(color):
		return _error("请为万能牌选择红色、黄色、绿色或蓝色。")
	var draw_four_illegal: bool = card.value == "draw_four" and not can_play_draw_four(player)
	_close_uno_window()
	hands[player].remove_at(index)
	discard_pile.append(card)
	active_color = color if card.color == "wild" else card.color
	drawn_card_id = -1
	phase = "playing"
	_empty_passes = 0
	_empty_draw_blocked = false
	if hands[player].size() == 1:
		uno_player = player
		uno_announced = announce
	if hands[player].is_empty():
		pending_winner = player
	var extra: Dictionary = {"card": card.duplicate(), "player": player}
	match card.value:
		"skip":
			current_player = _next(player, 2)
		"reverse":
			direction *= -1
			current_player = _next(player, 2 if hands.size() == 2 else 1)
		"draw_two":
			var victim: int = _next(player)
			var drawn: Array = _draw_many(victim, 2)
			current_player = _next(victim)
			extra.merge({"penalty_player": victim, "penalty_count": drawn.size(), "requested_penalty": 2})
		"draw_four":
			challenge_offender = player
			challenge_target = _next(player)
			current_player = challenge_target
			pending_draw = 4
			_challenge_illegal = draw_four_illegal
			# Preserve evidence from the moment of play, before any UNO catch draw.
			_challenge_hand = hands[player].duplicate(true)
			phase = "challenge"
		_:
			current_player = _next(player)
	if phase != "challenge":
		_finish_if_pending()
	return _success("已出牌。", extra)


## Voluntary drawing is allowed even when another card could be played.
## An unplayable or exhausted draw still enters drawn; pass_draw ends the turn.
func draw_card(player: int) -> Dictionary:
	if not _valid_player(player) or player != current_player or phase != "playing":
		return _error("每回合出牌前只能摸一张牌。")
	var had_legal_move: bool = not legal_indices(player).is_empty()
	_close_uno_window()
	var drawn: Array = _draw_many(player, 1)
	phase = "drawn"
	drawn_card_id = -1 if drawn.is_empty() else int(drawn[0].id)
	_empty_draw_blocked = drawn.is_empty() and not had_legal_move
	if not drawn.is_empty():
		_empty_passes = 0
	return _success("牌堆已空，请结束本回合。" if drawn.is_empty() else "已摸一张牌。", {
		"card": {} if drawn.is_empty() else drawn[0].duplicate(),
		"drawn_count": drawn.size(),
		"playable": not legal_indices(player).is_empty(),
	})


func pass_draw(player: int) -> Dictionary:
	if not _valid_player(player) or player != current_player or phase != "drawn":
		return _error("请先摸牌，再结束本回合。")
	_empty_passes = _empty_passes + 1 if _empty_draw_blocked else 0
	_empty_draw_blocked = false
	drawn_card_id = -1
	phase = "playing"
	current_player = _next(player)
	if _empty_passes >= hands.size():
		phase = "finished"
		finish_reason = "stalemate"
		_close_uno_window()
		return _success("所有玩家均无法出牌或摸牌，本局平局。")
	return _success("本回合结束。")


## A successful challenge restores the challenger's normal turn. The wild's
## chosen color remains active. A failed challenge draws six and loses the turn.
func resolve_challenge(player: int, challenge: bool) -> Dictionary:
	if phase != "challenge" or player != challenge_target:
		return _error("只有被加四的玩家可以决定是否质疑。")
	_close_uno_window()
	var offender: int = challenge_offender
	var successful: bool = challenge and _challenge_illegal
	var victim: int = offender if successful else player
	var amount: int = 6 if challenge and not successful else 4
	var revealed: Array = _challenge_hand.duplicate(true) if challenge else []
	var drawn: Array = _draw_many(victim, amount)
	current_player = player if successful else _next(player)
	if successful:
		pending_winner = -1
	pending_draw = 0
	challenge_target = -1
	challenge_offender = -1
	_challenge_illegal = false
	_challenge_hand.clear()
	phase = "playing"
	_finish_if_pending()
	var message: String = "接受加四：摸四张牌，并跳过本回合。"
	if challenge:
		message = "质疑成功：出牌者摸四张牌，现在由你出牌。" if successful else "质疑失败：摸六张牌，并跳过本回合。"
	if drawn.size() < amount:
		message += " 牌已用尽，实际摸到 %d 张。" % drawn.size()
	return _success(message, {
		"challenged": challenge, "challenge_success": successful,
		"penalty_player": victim, "penalty_count": drawn.size(),
		"requested_penalty": amount, "revealed_hand": revealed,
	})


func announce_uno(player: int) -> Dictionary:
	if not _valid_player(player) or phase == "finished" or uno_player != player or hands[player].size() != 1:
		return _error("只剩一张牌且宣告时限未过时，才可喊 UNO。")
	uno_announced = true
	return _success("UNO!")


func catch_uno(catcher: int) -> Dictionary:
	if not _valid_player(catcher) or phase == "finished" or uno_player < 0 or catcher == uno_player or uno_announced:
		return _error("目前没有可抓的漏喊 UNO。")
	var offender: int = uno_player
	if hands[offender].size() != 1:
		return _error("这位玩家的手牌已不止一张。")
	var drawn: Array = _draw_many(offender, 2)
	_close_uno_window()
	var message: String = "抓到漏喊 UNO，罚摸两张牌。"
	if drawn.size() < 2:
		message += " 牌已用尽，实际摸到 %d 张。" % drawn.size()
	return _success(message, {
		"penalty_player": offender, "penalty_count": drawn.size(), "requested_penalty": 2,
	})


static func card_points(card: Dictionary) -> int:
	if card.value in ["wild", "draw_four"]:
		return 50
	if card.value in ACTIONS:
		return 20
	return int(card.value)


func total_cards() -> int:
	var total: int = draw_pile.size() + discard_pile.size()
	for hand in hands:
		total += hand.size()
	return total


func _matches(card: Dictionary) -> bool:
	return card.color == "wild" or card.color == active_color or (not discard_pile.is_empty() and card.value == discard_pile.back().value)


func _valid_player(player: int) -> bool:
	return player >= 0 and player < hands.size()


func _next(player: int, steps: int = 1) -> int:
	return posmod(player + direction * steps, hands.size())


func _draw_many(player: int, count: int) -> Array:
	var result: Array = []
	for _index in count:
		if draw_pile.is_empty():
			_recycle()
		if draw_pile.is_empty():
			break
		var card: Dictionary = draw_pile.pop_back()
		hands[player].append(card)
		result.append(card)
	return result


func _recycle() -> void:
	if discard_pile.size() <= 1:
		return
	var top: Dictionary = discard_pile.pop_back()
	draw_pile.append_array(discard_pile)
	discard_pile = [top]
	_shuffle(draw_pile)


func _shuffle(cards: Array) -> void:
	for index in range(cards.size() - 1, 0, -1):
		var other: int = _rng.randi_range(0, index)
		var card: Dictionary = cards[index]
		cards[index] = cards[other]
		cards[other] = card


func _close_uno_window() -> void:
	uno_player = -1
	uno_announced = false


func _finish_if_pending() -> void:
	if pending_winner < 0 or not hands[pending_winner].is_empty():
		return
	winner = pending_winner
	pending_winner = -1
	score = 0
	for player in hands.size():
		if player == winner:
			continue
		for card in hands[player]:
			score += card_points(card)
	phase = "finished"
	finish_reason = "winner"
	_close_uno_window()


func _success(message: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": true, "message": message}
	result.merge(extra)
	return result


func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
