extends SceneTree

const Rules = preload("res://scripts/blackjack_ring_rules.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func fixture(hands: Array, dealer: Array, extra: Array = []) -> RefCounted:
	var m = Rules.new(7)
	var ranks: Array = []
	for pass_index in 2:
		for hand in hands: ranks.append(hand[pass_index])
		ranks.append(dealer[pass_index])
	ranks.append_array(extra)
	var ids: Array = []
	var used: Dictionary = {}
	for rank in ranks:
		for card in Rules.build_deck():
			if card.rank == rank and not used.has(card.id):
				ids.append(card.id)
				used[card.id] = true
				break
	check(m.set_next_draws(ids).ok, "fixture accepted")
	return m

func same_hands(a: int, b: int) -> Array:
	var hands: Array = []
	for i in 8: hands.append([a,b])
	return hands

func finish(m: RefCounted) -> void:
	var guard: int = 0
	while m.phase == "player" or m.phase == "dealer":
		guard += 1
		if guard > 400:
			check(false,"round terminates")
			break
		if m.phase == "dealer": check(m.dealer_step().ok, "dealer accepted")
		elif m.current_player == 0: check(m.stand().ok, "human stand")
		else: check(m.ai_step().ok, "bot step")

func conservation(m: RefCounted) -> void:
	var seen: Dictionary = {}
	var cards: Array = m.draw_pile.duplicate()
	cards.append_array(m.discard_pile)
	cards.append_array(m.dealer_hand)
	for p in m.players: cards.append_array(p.hand)
	check(cards.size() == 312, "312 physical cards")
	for c in cards:
		check(not seen.has(c.id), "unique id %d" % c.id)
		seen[c.id] = true
		check(c.id >= 0 and c.id < 312 and c.rank == (c.id % 13) + 1, "valid physical identity")

func run() -> void:
	var m = Rules.new(99)
	conservation(m)
	check(m.players.size() == 8,"eight seats")
	for p in m.players: check(p.balance == 1000,"independent 1000")
	var before: Dictionary = m.snapshot()
	for bad in [-10,0,5,15,1010]: check(not m.start_round(bad).ok,"reject invalid stake")
	check(m.snapshot() == before,"invalid stakes atomic")
	check(not m.set_next_draws([0,0]).ok and not m.set_next_draws([312]).ok,"bad fixtures reject")
	check(m.snapshot() == before,"invalid fixture atomic")
	check(m.start_round(100).ok,"opening")
	check(m.draw_pile.size() == 294,"18 opening cards")
	check(not m.reset_bankroll().ok,"active reset rejected")
	check(not m.next_round().ok,"active next rejected")
	before = m.snapshot()
	check(not m.stand(m.state_version-1).ok,"stale command rejected")
	check(m.snapshot() == before,"stale atomic")
	var snap: Dictionary = m.snapshot()
	snap.players[0].balance = -9
	check(m.players[0].balance >= 0,"deep copy snapshot")
	finish(m)
	before=m.snapshot()
	check(not m.dealer_step().ok and not m.stand().ok and not m.double_down().ok,"settled callbacks rejected")
	check(m.snapshot()==before,"settlement idempotent")
	conservation(m)
	check(m.next_round().ok,"next round")
	check(m.players[0].hand.is_empty() and m.dealer_hand.is_empty(),"collect on next")
	conservation(m)

	var hands: Array = same_hands(10,7)
	hands[0]=[1,13]
	m=fixture(hands,[1,10])
	check(m.start_round(100).ok,"dealer natural")
	check(m.phase=="settled","peek immediate")
	check(m.players[0].balance==1000 and m.players[0].result.outcome=="push","both natural push")
	for i in range(1,8): check(m.players[i].balance==900 and m.players[i].result.outcome=="dealer_blackjack","dealer natural beats player")
	check(not m.double_down().ok,"no double after peek")

	m=fixture(hands,[10,7])
	m.start_round(100)
	check(m.current_player==1,"skip human natural")
	finish(m)
	check(m.players[0].balance==1150 and m.players[0].result.payout==250,"natural 3:2")
	for i in range(1,8): check(m.players[i].balance==1000,"independent push")

	m=fixture(same_hands(5,6),[10,7],[10,10,10,10,10,10,10,10])
	m.start_round(100)
	for i in 8:
		check(m.current_player==i,"serial seat %d"%i)
		var size_before: int=m.draw_pile.size()
		check(m.double_down().ok,"double accepted")
		check(m.players[i].bet==200 and m.players[i].balance==800,"double debit seat only")
		check(m.players[i].hand.size()==3 and m.draw_pile.size()==size_before-1,"double exactly one card")
	finish(m)
	for p in m.players: check(p.balance==1200 and p.result.payout==400 and p.result.outcome=="win","double normal21 pays 1:1")
	conservation(m)

	m=fixture(same_hands(10,6),[5,6],[10,10,10,10,10,10,10,10])
	m.start_round(100)
	for i in 8: check(m.hit().ok,"all bust hit")
	check(m.phase=="settled" and m.dealer_hand.size()==2,"all bust no dealer draws")
	for p in m.players: check(p.balance==900 and p.result.outcome=="bust","bust independent")

	m=fixture(same_hands(10,8),[1,6])
	m.start_round(100)
	for i in 8: m.stand()
	m.dealer_step()
	check(m.phase=="settled" and m.dealer_hand.size()==2,"soft17 stand")
	for p in m.players: check(p.balance==1100,"beat soft17")

	m=fixture(same_hands(5,6),[10,7])
	m.start_round(100)
	m.discard_pile.append_array(m.draw_pile)
	m.draw_pile.clear()
	check(m.double_down().ok,"exhaustion is void command")
	for p in m.players: check(p.balance==1000 and p.result.outcome=="void","void refunds even doubled")
	before=m.snapshot()
	check(not m.double_down().ok and m.snapshot()==before,"void idempotent")
	conservation(m)

	m=Rules.new(31)
	m.players[0].balance=0
	m.players[1].balance=5
	m.players[2].balance=35
	check(m.start_round(0).ok,"bankrupt spectate")
	check(m.players[0].status=="skipped" and m.players[1].status=="skipped","skip bankrupt seats")
	check(m.players[2].bet==30 and m.players[2].balance==5,"bot affordable whole step")
	finish(m)
	check(m.players[0].balance==0 and m.players[1].balance==5,"no automatic free bankroll")
	check(m.reset_bankroll().ok,"explicit reset allowed")
	for p in m.players: check(p.balance==1000,"reset replaces all balances")

	var ace: Dictionary={"rank":1}
	check(Rules.hand_value([ace,ace,{"rank":9}]).total==21,"multiple ace values")
	check(Rules.decision([ace,{"rank":7}],{"rank":6},100,100,true)=="double","soft18 double6")
	check(Rules.decision([ace,{"rank":7}],{"rank":9},100,100,true)=="hit","soft18 hit9")
	check(Rules.decision([ace,{"rank":8}],{"rank":10},100,100,true)=="stand","soft19 stand")
	check(Rules.decision([{"rank":5},{"rank":6}],{"rank":6},99,100,true)=="hit","no unaffordable double")
	check(Rules.decision([{"rank":10},{"rank":6}],{"rank":6},100,100,true)=="stand","hard16 vs6")
	check(Rules.decision([{"rank":10},{"rank":6}],ace,100,100,true)=="hit","hard16 vs ace")

	m=Rules.new(984211)
	for round_index in 400:
		if m.players[0].balance<10:
			m.reset_bankroll()
		var balances: Array=[]
		for p in m.players: balances.append(p.balance)
		check(m.start_round(mini(100,int(m.players[0].balance/10)*10)).ok,"random start")
		finish(m)
		check(m.phase=="settled","random settles")
		for i in 8:
			var p: Dictionary=m.players[i]
			check(p.balance>=0,"never negative")
			if p.bet>0: check(p.balance==balances[i]-p.bet+p.result.payout,"individual accounting")
			else: check(p.balance==balances[i],"skipped keeps balance")
		conservation(m)
		check(m.next_round().ok,"random collect")
	check(m.shoe_shuffles>1,"recycles between rounds")
	print("Blackjack ring: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
