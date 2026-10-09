extends SceneTree
## Independent 8-seat accounting, identity, transition and public-policy audit.
const Rules = preload("res://scripts/blackjack_ring_rules.gd")
var checks := 0
var failures := 0
func ck(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("RING REVIEW: " + label)
func snap(g) -> String: return JSON.stringify(g.snapshot())
func reject(g, method: String, args: Array, label: String) -> void:
	var before := snap(g)
	var response: Dictionary = g.callv(method, args)
	ck(not response.ok and snap(g) == before, label + " atomic rejection")
func total(hand: Array) -> int:
	var value := 0
	var ace := false
	for card in hand:
		value += mini(int(card.rank),10)
		ace = ace or int(card.rank) == 1
	return value + 10 if ace and value + 10 <= 21 else value
func natural(hand: Array) -> bool: return hand.size() == 2 and total(hand) == 21
func conservation(g, label: String) -> void:
	var cards: Array = g.draw_pile + g.discard_pile + g.dealer_hand
	ck(g.players.size() == 8, label + " exactly 8 seats")
	for p in g.players:
		cards += p.hand
		ck(p.balance >= 0, label + " no negative wallet")
	var unique := {}
	for card in cards:
		unique[card.id] = true
		ck(int(card.rank) == int(card.id) % 13 + 1, label + " physical rank matches ID")
	ck(cards.size() == 312 and unique.size() == 312, label + " 312 unique physical cards conserved")
func rig(hands: Array, dealer: Array, extra: Array = []):
	var g = Rules.new(917)
	var ranks: Array = []
	for i in 2:
		for h in hands: ranks.append(h[i])
		ranks.append(dealer[i])
	ranks += extra
	var used := {}
	var ids: Array = []
	for rank in ranks:
		var count: int = used.get(rank,0)
		ids.append(count * 13 + rank - 1)
		used[rank] = count + 1
	ck(g.set_next_draws(ids).ok,"fixture valid")
	return g
func hands(a: int, b: int) -> Array:
	var out: Array = []
	for i in 8: out.append([a,b])
	return out
func balances(g) -> Array:
	var out: Array = []
	for p in g.players: out.append(p.balance)
	return out
func finish(g, human_action: String = "stand") -> void:
	var guard := 0
	var previous := -1
	while g.phase == "player" and guard < 150:
		var seat: int = g.current_player
		ck(seat >= previous,"seats take turns monotonically")
		previous = seat
		var response: Dictionary = g.call(human_action) if seat == 0 else g.ai_step()
		ck(response.ok,"player/AI step accepted")
		guard += 1
	while g.phase == "dealer" and guard < 200:
		var before: int = g.dealer_hand.size()
		ck(g.dealer_step().ok,"dealer step accepted")
		ck(g.dealer_hand.size() - before <= 1,"dealer at most 1 card per action")
		guard += 1
	ck(g.phase == "settled","round terminates")
func account(g, before: Array) -> void:
	for i in 8:
		var p: Dictionary = g.players[i]
		if p.bet == 0:
			ck(p.balance == before[i],"skipped wallet unchanged")
			continue
		var r: Dictionary = p.result
		ck(not r.is_empty(),"active player has independent result")
		if r.is_empty(): continue
		var expected := "loss"
		var pt := total(p.hand)
		var dt := total(g.dealer_hand)
		if natural(g.dealer_hand): expected = "push" if natural(p.hand) else "dealer_blackjack"
		elif pt > 21: expected = "bust"
		elif natural(p.hand): expected = "blackjack"
		elif dt > 21 or pt > dt: expected = "win"
		elif pt == dt: expected = "push"
		ck(r.outcome == expected,"seat %d independent outcome oracle %s vs %s" % [i,r.outcome,expected])
		var payout: int = p.bet * 2 if expected == "win" else (int(p.bet * 5 / 2) if expected == "blackjack" else (p.bet if expected == "push" else 0))
		ck(r.payout == payout and p.balance == before[i] - p.bet + payout,"seat %d exact wallet conservation" % i)
		ck(r.net == payout - p.bet,"seat net excludes returned stake")
		if p.doubled: ck(p.hand.size() == 3 and p.bet == p.initial_bet * 2,"every doubled hand exactly 3 cards")
	var state := snap(g)
	for method in ["hit","stand","double_down","ai_step","dealer_step"]:
		ck(not g.call(method).ok and snap(g) == state,"no repeated settlement by " + method)
func _initialize() -> void:
	test_open_and_atomicity()
	test_naturals()
	test_double()
	test_s17()
	test_bankrupt()
	test_random_rounds()
	test_public_strategy()
	test_void_refunds()
	print("INDEPENDENT RING REVIEW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func test_open_and_atomicity() -> void:
	var g = rig(hands(8,8),[10,7])
	conservation(g,"before deal")
	for amount in [-10,0,5,15,1010]: reject(g,"start_round",[amount],"invalid wager")
	var version: int = g.state_version
	ck(g.start_round(100,version).ok,"open round")
	ck(g.current_player == 0 and g.dealer_hand.size()==2,"human first and dealer 2 cards")
	for p in g.players: ck(p.hand.size()==2 and p.bet==100 and p.balance==900,"each seat debited and dealt twice")
	reject(g,"start_round",[100],"duplicate deal")
	reject(g,"hit",[version],"stale input")
	reject(g,"dealer_step",[],"dealer cannot act before players")
	conservation(g,"opening")
	finish(g); account(g,[1000,1000,1000,1000,1000,1000,1000,1000])
	var b := balances(g)
	ck(g.next_round().ok and balances(g)==b,"next round preserves all wallets")
	conservation(g,"next round")
func test_naturals() -> void:
	var h := hands(10,9); h[0]=[1,13]; h[1]=[1,10]
	var g = rig(h,[10,1]); g.start_round(100)
	ck(g.phase=="settled","dealer blackjack immediate peek resolves")
	account(g,[1000,1000,1000,1000,1000,1000,1000,1000]); conservation(g,"BJ peek")
	h = hands(10,9); h[0]=[1,13]; h[1]=[7,7]
	g=rig(h,[10,10],[7]);g.start_round(100)
	finish(g); account(g,[1000,1000,1000,1000,1000,1000,1000,1000])
	ck(g.players[0].result.payout==250,"natural pays 3:2 profit")
	ck(g.players[1].hand.size()==3 and g.players[1].result.payout==200,"ordinary 3-card21 only pays1:1")
func test_double() -> void:
	var g=rig(hands(5,6),[6,10],[10,10,10,10,10,10,10,10,10])
	g.start_round(100)
	var version: int=g.state_version
	ck(g.double_down(version).ok,"human double accepted")
	ck(g.players[0].balance==800 and g.players[0].hand.size()==3,"double debit and 1 card atomic")
	reject(g,"double_down",[version],"duplicate stale double")
	finish(g);account(g,[1000,1000,1000,1000,1000,1000,1000,1000]);conservation(g,"all doubles")
	for p in g.players: ck(p.doubled and p.hand.size()==3,"all AI double hard11 vs6")
	g=rig(hands(5,6),[6,10]);g.players[0].balance=100;g.start_round(100)
	reject(g,"double_down",[],"insufficient bankroll double")
func test_s17() -> void:
	for dh in [[1,6],[10,7]]:
		var g=rig(hands(10,8),dh,[10]);g.start_round(100);finish(g)
		ck(g.dealer_hand.size()==2,"dealer stands on soft and hard17")
		account(g,[1000,1000,1000,1000,1000,1000,1000,1000])
func test_bankrupt() -> void:
	var g=Rules.new(45)
	for i in [0,2,4]:g.players[i].balance=5
	var b:=balances(g)
	ck(g.start_round(0).ok,"bankrupt human allows AI-only round")
	for i in [0,2,4]:ck(g.players[i].hand.is_empty() and g.players[i].bet==0,"bankrupt seat skipped")
	finish(g);account(g,b);conservation(g,"bankrupt skipped")
func test_random_rounds() -> void:
	var g=Rules.new(25109)
	for round_index in 160:
		if g.phase=="settled":g.next_round()
		if round_index % 20==0:g.reset_bankroll()
		var b:=balances(g)
		var amount: int=mini(100,int(g.players[0].balance/10)*10)
		var response: Dictionary=g.start_round(amount)
		if not response.ok:
			g.reset_bankroll(); b=balances(g); response=g.start_round(100)
		ck(response.ok,"random deal")
		finish(g,"hit" if round_index%2==0 else "stand")
		account(g,b);conservation(g,"random %d"%round_index)

func policy(hand: Array, up_rank: int, funds: int, stake: int, double_ok: bool) -> String:
	var t := total(hand)
	var low := 0
	for card in hand: low += mini(int(card.rank),10)
	var soft := t != low
	var up := 11 if up_rank == 1 else mini(up_rank,10)
	var d := double_ok and hand.size()==2 and funds>=stake and stake>0
	if t>=21:return "stand"
	if soft:
		if t>=19:return "stand"
		if t==18:
			if d and up in [3,4,5,6]:return "double"
			return "stand" if up in [2,3,4,5,6,7,8] else "hit"
		var soft_doubles := {13:[5,6],14:[5,6],15:[4,5,6],16:[4,5,6],17:[3,4,5,6]}
		return "double" if d and soft_doubles.has(t) and up in soft_doubles[t] else "hit"
	if t>=17:return "stand"
	if t in [13,14,15,16] and up in [2,3,4,5,6]:return "stand"
	if t==12 and up in [4,5,6]:return "stand"
	var hard_doubles := {9:[3,4,5,6],10:[2,3,4,5,6,7,8,9],11:[2,3,4,5,6,7,8,9,10]}
	return "double" if d and hard_doubles.has(t) and up in hard_doubles[t] else "hit"
func test_public_strategy() -> void:
	for a in range(1,14):
		for b in range(1,14):
			for up in range(1,14):
				for funds in [0,99,100,1000]:
					for allow in [false,true]:
						var h: Array=[{"rank":a},{"rank":b}]
						ck(Rules.decision(h,{"rank":up},funds,100,allow)==policy(h,up,funds,100,allow),"public strategy matrix")
	var a=rig(hands(8,8),[10,7],[2]);var b=rig(hands(8,8),[10,7],[2])
	a.start_round(100);b.start_round(100);a.stand();b.stand()
	b.dealer_hand[1].rank=2
	for i in range(2,8):b.players[i].hand=[{"rank":1},{"rank":13}]
	a.ai_step();b.ai_step()
	ck(a.players[1]==b.players[1],"AI action invariant to dealer hole and opponent hidden hands")
func test_void_refunds() -> void:
	for method in ["hit","double_down"]:
		var g=rig(hands(5,6),[6,10]);g.start_round(100)
		g.discard_pile.append_array(g.draw_pile);g.draw_pile.clear()
		ck(g.call(method).ok and g.phase=="settled","empty shoe voids atomically")
		for p in g.players:ck(p.balance==1000 and p.result.outcome=="void","all8 stakes returned exactly")
		var state:=snap(g)
		g.dealer_step();g.double_down();g.hit()
		ck(state==snap(g),"void refund idempotent")
		conservation(g,"void card conservation")
