class_name UnoRules
extends RefCounted
## Synchronous, scene-independent 108-card UNO-style round.
## House rules are opt-in; opening and scoring use the local game variant.
## Player 0 sits left of the initial dealer (the final player). Card IDs remain
## unique through draws and recycling. Classic +4 bluffs are challengeable;
## the stacking variant accepts +4 freely and replaces challenges with debt.
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
## Aggregate remaining points for diagnostics; never awarded to the finisher.
var score: int = 0
var initial_hand_size: int = 7
var finish_reason: String = ""
var drawn_card_id: int = -1
var pending_draw: int = 0
var pending_winner: int = -1
var challenge_target: int = -1
var challenge_offender: int = -1
var uno_player: int = -1
var uno_announced: bool = false

const DEFAULT_OPTIONS: Dictionary = {
	"continuous_draw": false, "jump_in": false,
	"stacking": false, "forbid_last_wild": false,
}
var options: Dictionary = DEFAULT_OPTIONS.duplicate()
var forced_play: bool = false
## A host can pass the rendered version to reject stale competing commands.
## This counter deliberately does not reset when another round starts.
var state_version: int = 0
## A colored discard remains interceptable until a valid subsequent action.
## Direction and turn are previews; physical penalty draws happen on settlement.
var pending_play: Dictionary = {}
var projected_phase: String = "idle"
var _stack_value: String = ""
var _winner_candidates: Array[int] = []

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


static func max_initial_hand_size(player_count: int) -> int:
	return int(107 / player_count) if player_count >= 2 and player_count <= 8 else 0


func start_game(player_count: int, seed_value: int = 0, opts: Dictionary = {}, hand_size: int = 7) -> Dictionary:
	if player_count < 2 or player_count > 8:
		return _error("请选择 2 至 8 位玩家。")
	if hand_size < 1 or hand_size > max_initial_hand_size(player_count):
		return _error("初始手牌须为 1 至 %d 张，保留至少一张起始牌。" % max_initial_hand_size(player_count))
	initial_hand_size = hand_size
	options = DEFAULT_OPTIONS.duplicate()
	for key in DEFAULT_OPTIONS:
		options[key] = bool(opts.get(key, false))
	forced_play = false
	pending_play.clear()
	_stack_value = ""
	_winner_candidates.clear()
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
	for _round in initial_hand_size:
		for player in player_count:
			hands[player].append(draw_pile.pop_back())
	var first: Dictionary = draw_pile.pop_back()
	discard_pile.append(first)
	active_color = first.color
	# The starter establishes only a match target. No skip, reverse or debt.
	# Both wild types let player 1 choose, without consuming that first turn.
	if first.color == "wild":
		active_color = ""
		phase = "choose_color"
	return _success("新一局开始。", {"initial_card": first.duplicate(), "player_count": player_count, "initial_hand_size": initial_hand_size})


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
	if not _valid_player(player) or player != current_player or phase not in ["playing", "drawn", "stacking"]:
		return result
	for index in hands[player].size():
		var card: Dictionary = hands[player][index]
		if phase == "drawn" and card.id != drawn_card_id:
			continue
		if _sole_wild_blocked(player, card):
			continue
		if _can_stack(card) if phase == "stacking" else _matches(card):
			result.append(index)
	return result


## Exact physical color and printed symbol; wild cards never intercept.
## The active player's ordinary match is also allowed to win this race.
func jump_in_indices(player: int) -> Array[int]:
	var result: Array[int] = []
	if not _valid_player(player) or pending_play.is_empty() or phase == "finished" or not options.jump_in:
		return result
	var previous: Dictionary = pending_play.card
	for index in hands[player].size():
		var card: Dictionary = hands[player][index]
		if card.color != "wild" and card.color == previous.color and card.value == previous.value:
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


func play_card(player: int, index: int, color: String = "", announce: bool = false, expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已更新，请按最新状态操作。")
	if not _valid_player(player) or player != current_player or phase not in ["playing", "drawn", "stacking"]:
		return _error("现在不能由这位玩家出牌。")
	if index < 0 or index >= hands[player].size():
		return _error("手牌中没有这张牌。")
	var card: Dictionary = hands[player][index]
	if phase == "drawn" and card.id != drawn_card_id:
		return _error("摸牌后只能打出刚摸到的那张牌。")
	if _sole_wild_blocked(player, card):
		return _error("最后一张不能是万能牌，请先摸一张牌。")
	if phase == "stacking":
		if not _can_stack(card):
			return _error("加二可叠加二或加四；加四只能继续叠加四。")
	elif not _matches(card):
		return _error("请匹配当前颜色、数字或符号，也可以使用万能牌。")
	if card.color == "wild" and not COLORS.has(color):
		return _error("请为万能牌选择红色、黄色、绿色或蓝色。")
	# Invalid commands above never close the interception window.
	var settled: Dictionary = _settle_pending()
	if phase == "finished":
		return _success("本局已结束。", settled)
	var extra: Dictionary = _record_play(player, index, color, announce)
	extra = _merge_action_metadata(settled, extra)
	return _success("已出牌。", extra)


func jump_in(player: int, index: int, announce: bool = false, expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已更新，抢牌未成功。")
	if not jump_in_indices(player).has(index):
		return _error("只能用与刚出的牌同色、同数字或同符号的非万能牌抢牌。")
	var previous: Dictionary = pending_play
	# Only the effect is replaced. Every previously played card stays discarded.
	direction = int(previous.base_direction)
	pending_draw = int(previous.incoming_draw)
	_stack_value = String(previous.incoming_stack)
	var participants: Array = previous.participants
	pending_play = {}
	phase = "stacking" if pending_draw > 0 else "playing"
	var extra: Dictionary = _record_play(player, index, "", announce, participants)
	extra["jumped_in"] = true
	return _success("抢牌成功，上一张牌的效果被替代。", extra)


## Explicit settlement is available to simulations and controller transitions.
## Ordinary play/draw settles automatically after validating the next action.
func commit_pending_play() -> Dictionary:
	if pending_play.is_empty():
		return _error("目前没有等待结算的牌。")
	var extra: Dictionary = _settle_pending()
	return _success(_penalty_message("已结算上一张牌。", extra), extra)


## With jump-in enabled, a non-stacking +2 does not physically draw until this
## actual penalty action wins the race against an exact-card interception.
func accept_pending(player: int, expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已更新，请按最新状态操作。")
	if not _valid_player(player) or phase != "pending_effect" or player != current_player or pending_play.is_empty():
		return _error("目前没有由这位玩家接受的加二罚牌。")
	var extra: Dictionary = _settle_pending()
	return _success(_penalty_message("摸罚牌并跳过本回合。", extra), extra)


func accept_stack(player: int, expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已更新，请按最新状态操作。")
	if not _valid_player(player) or phase != "stacking" or player != current_player:
		return _error("只有当前被罚玩家可以接受叠加罚牌。")
	var settled: Dictionary = _settle_pending()
	_close_uno_window()
	var amount: int = pending_draw
	var drawn: Array = _draw_many(player, amount)
	pending_draw = 0
	_stack_value = ""
	current_player = _next(player)
	phase = "playing"
	forced_play = false
	_finish_if_pending()
	var extra: Dictionary = _merge_action_metadata(settled, {
		"penalty_player": player, "penalty_count": drawn.size(), "requested_penalty": amount,
	})
	return _success(_penalty_message("摸取累计罚牌，并跳过本回合。", extra), extra)


func _record_play(player: int, index: int, color: String, announce: bool, participants: Array = []) -> Dictionary:
	var card: Dictionary = hands[player][index]
	var draw_four_illegal: bool = card.value == "draw_four" and not can_play_draw_four(player)
	var base_direction: int = direction
	var incoming_draw: int = pending_draw
	var incoming_stack: String = _stack_value
	_close_uno_window()
	hands[player].remove_at(index)
	discard_pile.append(card)
	active_color = color if card.color == "wild" else card.color
	drawn_card_id = -1
	forced_play = false
	phase = "playing"
	_empty_passes = 0
	_empty_draw_blocked = false
	if hands[player].is_empty():
		if not _winner_candidates.has(player):
			_winner_candidates.append(player)
		_refresh_pending_winner()
	var extra: Dictionary = {"card": card.duplicate(), "player": player}
	var may_jump: bool = bool(options.jump_in) and card.color != "wild"
	match card.value:
		"skip":
			current_player = _next(player, 2)
		"reverse":
			direction *= -1
			current_player = _next(player, 2 if hands.size() == 2 else 1)
		"draw_two":
			current_player = _next(player)
			if options.stacking:
				pending_draw += 2
				_stack_value = "draw_two"
				phase = "stacking"
			elif may_jump:
				pending_draw = 2
				phase = "pending_effect"
			else:
				var victim: int = current_player
				var drawn: Array = _draw_many(victim, 2)
				current_player = _next(victim)
				extra.merge({"penalty_player": victim, "penalty_count": drawn.size(), "requested_penalty": 2})
		"draw_four":
			current_player = _next(player)
			if options.stacking:
				pending_draw += 4
				_stack_value = "draw_four"
				phase = "stacking"
			else:
				challenge_offender = player
				challenge_target = current_player
				pending_draw = 4
				_challenge_illegal = draw_four_illegal
				_challenge_hand = hands[player].duplicate(true)
				phase = "challenge"
		_:
			current_player = _next(player)
	if may_jump:
		_update_uno(player, announce)
		participants.append({"player": player, "announce": announce})
		pending_play = {
			"card": card.duplicate(), "player": player, "incoming_draw": incoming_draw,
			"base_direction": base_direction, "incoming_stack": incoming_stack,
			"participants": participants,
		}
		# An empty hand already guarantees victory unless a penalty is pending.
		# Do not leave a finished round waiting for an impossible next action.
		if pending_winner >= 0 and phase == "playing":
			extra.merge(_settle_pending())
	else:
		var last_wild: Dictionary = _settle_last_wild(player)
		if not last_wild.is_empty():
			extra["last_wild_penalties"] = [last_wild]
			extra.merge(last_wild)
		_update_uno(player, announce)
		if phase not in ["challenge", "stacking"]:
			_finish_if_pending()
	return extra


func _settle_pending() -> Dictionary:
	if pending_play.is_empty():
		return {}
	var previous: Dictionary = pending_play
	pending_play = {}
	var extra: Dictionary = {}
	if phase == "pending_effect":
		var victim: int = current_player
		var amount: int = pending_draw
		var drawn: Array = _draw_many(victim, amount)
		pending_draw = 0
		current_player = _next(victim)
		phase = "playing"
		extra.merge({"penalty_player": victim, "penalty_count": drawn.size(), "requested_penalty": amount})
	# Defer sole-wild penalties until the race has settled, so an intercepted
	# effect never forces a physical rollback. Each affected hand is checked once.
	var checked: Dictionary = {}
	for participant in previous.participants:
		var player: int = int(participant.player)
		if not checked.has(player):
			var penalty: Dictionary = _settle_last_wild(player)
			if not penalty.is_empty():
				if not extra.has("last_wild_penalties"):
					extra["last_wild_penalties"] = []
				extra.last_wild_penalties.append(penalty)
			checked[player] = true
	# Keep any announcement/catch made while the interception window was open.
	if uno_player >= 0 and hands[uno_player].size() != 1:
		_close_uno_window()
	if phase not in ["challenge", "stacking"]:
		_finish_if_pending()
	return extra


func _settle_last_wild(player: int) -> Dictionary:
	if not options.forbid_last_wild or hands[player].size() != 1 or hands[player][0].color != "wild":
		return {}
	var drawn: Array = _draw_many(player, 1)
	return {"last_wild_player": player, "last_wild_drawn": drawn.size()}


func _update_uno(player: int, announce: bool) -> void:
	_close_uno_window()
	if hands[player].size() == 1:
		uno_player = player
		uno_announced = announce


func _can_stack(card: Dictionary) -> bool:
	return card.value == "draw_four" or (_stack_value == "draw_two" and card.value == "draw_two")


func _sole_wild_blocked(player: int, card: Dictionary) -> bool:
	return bool(options.forbid_last_wild) and hands[player].size() == 1 and card.color == "wild"


func _stale(expected_version: int) -> bool:
	return expected_version >= 0 and expected_version != state_version


## Voluntary single drawing remains allowed with a legal card in hand.
## Continuous drawing applies only when no legal card exists and stops at the
## first match; a colored match auto-plays, a wild waits for mandatory color.
## Unplayable/exhausted draws enter drawn; pass_draw ends the turn.
func draw_card(player: int, expected_version: int = -1) -> Dictionary:
	if _stale(expected_version):
		return _error("牌局已更新，请按最新状态操作。")
	if not _valid_player(player) or player != current_player or phase != "playing":
		return _error("每回合出牌前只能摸牌。")
	var settled: Dictionary = _settle_pending()
	if phase == "finished":
		return _success("本局已结束。", settled)
	# Settlement may have given this player a forced sole-wild penalty card.
	var had_legal_move: bool = not legal_indices(player).is_empty()
	_close_uno_window()
	var continuous: bool = bool(options.continuous_draw) and not had_legal_move
	var drawn: Array = []
	var playable: bool = false
	# Each iteration moves one finite physical card into the hand. No played
	# card enters discard until this loop has stopped, even when recycling.
	while true:
		var next_cards: Array = _draw_many(player, 1)
		if next_cards.is_empty():
			break
		drawn.append(next_cards[0])
		playable = _matches(next_cards[0])
		if not continuous or playable:
			break
	phase = "drawn"
	drawn_card_id = -1 if drawn.is_empty() else int(drawn.back().id)
	_empty_draw_blocked = drawn.is_empty() and not had_legal_move
	forced_play = continuous and playable
	if not drawn.is_empty():
		_empty_passes = 0
	var extra: Dictionary = {
		"card": {} if drawn.is_empty() else drawn.back().duplicate(),
		"drawn_count": drawn.size(), "playable": playable,
		"forced_play": forced_play, "auto_played": false,
	}
	if forced_play and drawn.back().color != "wild":
		var played: Dictionary = _record_play(player, hands[player].size() - 1, "", false)
		extra = _merge_action_metadata(extra, played)
		extra["auto_played"] = true
		extra["forced_play"] = false
		return _success("持续摸牌，已自动打出第一张可用牌。", _merge_action_metadata(settled, extra))
	return _success("牌堆已空，请结束本回合。" if drawn.is_empty() else ("请为摸到的万能牌选色并出牌。" if forced_play else "已摸牌。"), _merge_action_metadata(settled, extra))


func pass_draw(player: int) -> Dictionary:
	if not _valid_player(player) or player != current_player or phase != "drawn":
		return _error("请先摸牌，再结束本回合。")
	if forced_play:
		return _error("持续摸到的可用牌必须打出，请先选择万能牌颜色。")
	_empty_passes = _empty_passes + 1 if _empty_draw_blocked else 0
	_empty_draw_blocked = false
	drawn_card_id = -1
	phase = "playing"
	forced_play = false
	current_player = _next(player)
	if _empty_passes >= hands.size():
		phase = "finished"
		finish_reason = "stalemate"
		_close_uno_window()
		score = 0
		for hand in hands:
			for card in hand:
				score += card_points(card)
		return _success("所有玩家均无法出牌或摸牌，按剩余手牌分结算。")
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
		_winner_candidates.clear()
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
	if card.value == "wild":
		return 20
	if card.value == "draw_four":
		return 40
	if card.value in ACTIONS:
		return 10
	return int(card.value)


## Competition ranking: equal point totals share a rank (1, 1, 3).
## Seat order is presentation only and is never a tie-breaker.
func round_standings() -> Array:
	var rows: Array = []
	for player in hands.size():
		var points: int = 0
		for card in hands[player]:
			points += card_points(card)
		rows.append({"player": player, "points": points, "cards": hands[player].size(), "rank": 0})
	rows.sort_custom(func(a, b): return a.points < b.points)
	for index in rows.size():
		rows[index].rank = rows[index - 1].rank if index > 0 and rows[index].points == rows[index - 1].points else index + 1
	return rows


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
	if not result.is_empty() and (_winner_candidates.has(player) or pending_winner == player):
		_winner_candidates.erase(player)
		_refresh_pending_winner()
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


func _refresh_pending_winner() -> void:
	var eligible: Array[int] = []
	for player in _winner_candidates:
		if _valid_player(player) and hands[player].is_empty():
			eligible.append(player)
	_winner_candidates = eligible
	pending_winner = -1 if eligible.is_empty() else eligible[0]


func _finish_if_pending() -> void:
	_refresh_pending_winner()
	if pending_winner < 0:
		return
	winner = pending_winner
	pending_winner = -1
	_winner_candidates.clear()
	score = 0
	for player in hands.size():
		if player == winner:
			continue
		for card in hands[player]:
			score += card_points(card)
	phase = "finished"
	finish_reason = "winner"
	_close_uno_window()


func _penalty_message(message: String, extra: Dictionary) -> String:
	if int(extra.get("penalty_count", 0)) < int(extra.get("requested_penalty", 0)):
		message += " 牌已用尽，实际摸到 %d 张。" % int(extra.penalty_count)
	return message


func _merge_action_metadata(first: Dictionary, second: Dictionary) -> Dictionary:
	var combined: Dictionary = first.duplicate(true)
	var last_wild: Array = combined.get("last_wild_penalties", []).duplicate(true)
	last_wild.append_array(second.get("last_wild_penalties", []))
	combined.merge(second, true)
	if not last_wild.is_empty():
		combined["last_wild_penalties"] = last_wild
	return combined


func _success(message: String, extra: Dictionary = {}) -> Dictionary:
	for penalty in extra.get("last_wild_penalties", []):
		message += " 玩家 %d 最后只剩万能牌，强制摸 %d 张。" % [int(penalty.last_wild_player) + 1, int(penalty.last_wild_drawn)]
		if int(penalty.last_wild_drawn) == 0:
			message += " 牌已用尽，不再重复罚摸。"
	state_version += 1
	projected_phase = phase
	var result: Dictionary = {"ok": true, "message": message, "state_version": state_version}
	result.merge(extra)
	return result


func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
