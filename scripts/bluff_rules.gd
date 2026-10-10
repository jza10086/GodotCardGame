class_name BluffRules
extends RefCounted
## Local hotseat rules. Only sanitized views belong in a renderer.
const SUITS := ["clubs", "diamonds", "hearts", "spades"]
var hands: Array = []
var pile: Array = []
var latest_batch: Array = []
var enabled_ranks: Array = []
var current_player := 0
var declared_rank := 1
var phase := "setup"
var responders: Array = []
var winner := -1
var last_result: Dictionary = {}
var error := ""
var small_joker := true
var big_joker := true
var total := 0
var state_version := 0

static func rank_label(rank: int) -> String:
	return {1:"A",11:"J",12:"Q",13:"K",14:"小王",15:"大王"}.get(rank, str(rank))

func configure(player_count: int, ranks: Array, small := true, big := true, seed_value := -1, expected_version := -1) -> bool:
	if expected_version != -1 and expected_version != state_version: return false
	if player_count < 2 or player_count > 8: return _reject("请选择 2–8 位玩家。")
	var sorted: Array = []
	for rank in ranks:
		if not rank is int or rank < 1 or rank > 13 or sorted.has(rank): return _reject("点数必须是互不重复的 A–K。")
		sorted.append(rank)
	if sorted.is_empty(): return _reject("至少启用一种普通点数，不能只有万能王。")
	sorted.sort()
	var cards: Array = []
	for rank in sorted:
		for suit in SUITS: cards.append({"id":"%s_%d" % [suit,rank], "rank":rank,"suit":suit,"title":"%s %s" % [suit,rank_label(rank)]})
	if small: cards.append({"id":"joker_small","rank":14,"suit":"joker","title":"小王 · 万能"})
	if big: cards.append({"id":"joker_big","rank":15,"suit":"joker","title":"大王 · 万能"})
	if cards.size() < player_count: return _reject("牌数少于玩家数，请增加点数或减少人数。")
	var rng := RandomNumberGenerator.new()
	if seed_value < 0: rng.randomize()
	else: rng.seed = seed_value
	for i in range(cards.size()-1,0,-1):
		var j := rng.randi_range(0,i)
		var temp: Dictionary = cards[i]; cards[i]=cards[j]; cards[j]=temp
	for i in cards.size(): cards[i].id = "c_%d_%d" % [rng.randi(), i]
	hands.clear()
	for i in player_count: hands.append([])
	for i in cards.size(): hands[i % player_count].append(cards[i])
	enabled_ranks=sorted; small_joker=small; big_joker=big; total=cards.size()
	pile.clear(); latest_batch.clear(); responders.clear(); last_result.clear()
	current_player=0; declared_rank=sorted[0]; phase="play"; winner=-1; error=""; state_version+=1
	return true

func _reject(message: String) -> bool:
	error=message
	return false

func play_cards(actor: int, ids: Array, expected_version := -1) -> bool:
	if expected_version != -1 and expected_version != state_version: return false
	if phase != "play" or actor != current_player: return _reject("现在不是你的出牌阶段。")
	if ids.is_empty() or ids.size()>4: return _reject("每次请选择 1–4 张牌。")
	var batch: Array = []
	var seen: Array = []
	for id in ids:
		if seen.has(id): return _reject("不能重复选择同一张牌。")
		seen.append(id)
		var found := false
		for card in hands[actor]:
			if card.id == id: batch.append(card); found=true; break
		if not found: return _reject("只能打出自己的手牌。")
	for card in batch: hands[actor].erase(card)
	latest_batch=batch.duplicate(true); pile.append_array(batch)
	responders.clear()
	for offset in range(1,hands.size()): responders.append((actor+offset)%hands.size())
	phase="response"; last_result.clear(); error=""; state_version+=1
	return true

func response_player() -> int:
	return int(responders[0]) if phase=="response" and not responders.is_empty() else -1

func respond(actor: int, challenge: bool, expected_version := -1) -> bool:
	if expected_version != -1 and expected_version != state_version: return false
	if phase!="response" or actor!=response_player(): return _reject("请按顺序由当前回应玩家决定。")
	if challenge:
		var truthful := true
		for card in latest_batch:
			if card.rank != declared_rank and card.rank < 14: truthful=false
		var loser := actor if truthful else current_player
		last_result={"challenger":actor,"actor":current_player,"truthful":truthful,"loser":loser,"count":pile.size(),"rank":declared_rank,"cards":latest_batch.duplicate(true)}
		hands[loser].append_array(pile)
		pile.clear(); responders.clear()
		_finish_batch()
	else:
		responders.pop_front()
		if responders.is_empty():
			last_result={"accepted":true,"actor":current_player,"rank":declared_rank,"count":latest_batch.size()}
			_finish_batch()
	error=""; state_version+=1
	return true

func _finish_batch() -> void:
	if hands[current_player].is_empty():
		winner=current_player; phase="finished"; latest_batch.clear(); return
	current_player=(current_player+1)%hands.size()
	declared_rank=enabled_ranks[(enabled_ranks.find(declared_rank)+1)%enabled_ranks.size()]
	latest_batch.clear(); phase="play"

func public_hands(viewer: int) -> Array:
	var result: Array=[]
	for i in hands.size():
		var cards: Array=[]
		for card in hands[i]: cards.append(card.duplicate(true) if i==viewer else {"id":card.id,"hidden":true})
		result.append(cards)
	return result

func public_pile() -> Array:
	var result: Array=[]
	for card in pile: result.append({"id":card.id,"hidden":true})
	return result
