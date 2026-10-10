extends SceneTree
## Independent state-machine and adversarial review. No production mutation.
const Rules = preload("res://scripts/bluff_rules.gd")
var checks := 0
var failures := 0
func ck(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BLUFF REVIEW: " + label)
func state(g) -> String:
	return var_to_str([g.hands,g.pile,g.latest_batch,g.current_player,g.declared_rank,g.phase,g.responders,g.winner,g.last_result,g.state_version])
func reject(g, method: String, args: Array, label: String) -> void:
	var before := state(g)
	ck(not g.callv(method,args), label + " rejected")
	ck(state(g) == before, label + " atomic")
func fresh(count := 3, ranks: Array = [1,2,3,4,5,6,7,8,9,10,11,12,13], small := true, big := true):
	var g = Rules.new()
	ck(g.configure(count,ranks,small,big,763), "valid configuration")
	return g
func all_cards(g) -> Array:
	var result: Array = g.pile.duplicate()
	for h in g.hands: result.append_array(h)
	return result
func conservation(g, ids: Array) -> void:
	var actual: Array = []
	for c in all_cards(g): actual.append(c.id)
	actual.sort()
	ck(actual == ids, "every physical card occurs exactly once")
func identities(g) -> Array:
	var result: Array = []
	for c in all_cards(g): result.append(c.id)
	result.sort()
	return result
func rig(rows: Array):
	var g = fresh(rows.size()+1)
	var pool := all_cards(g)
	g.hands.clear()
	for row in rows:
		var hand: Array = []
		for rank in row:
			var found := -1
			for i in pool.size():
				if pool[i].rank == rank: found=i;break
			ck(found >= 0,"fixture card available")
			if found >= 0: hand.append(pool.pop_at(found))
		g.hands.append(hand)
	g.hands.append(pool)
	return g
func play(g, indices: Array = [0]) -> Array:
	var ids: Array = []
	for i in indices: ids.append(g.hands[g.current_player][i].id)
	ck(g.play_cards(g.current_player,ids,g.state_version),"valid play accepted")
	return ids
func decline_all(g) -> void:
	var n := 0
	while g.phase == "response" and n < 8:
		ck(g.respond(g.response_player(),false,g.state_version),"decline accepted")
		n+=1
	ck(n < 8,"bounded response chain")
func _initialize() -> void:
	test_configuration()
	test_validation()
	test_truth_and_pile()
	test_final_hand()
	test_privacy()
	test_random_games()
	print("INDEPENDENT BLUFF REVIEW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func test_configuration() -> void:
	for players in range(2,9):
		for ranks in [[1],[13],[1,7,13],[11,12,13],[1,2,3,4,5,6,7,8,9,10,11,12,13]]:
			for mask in 4:
				var g = Rules.new()
				var total: int = ranks.size()*4 + (mask & 1) + ((mask >> 1) & 1)
				var ok: bool = g.configure(players,ranks,bool(mask & 1),bool(mask & 2),81)
				ck(ok == (total >= players),"reject insufficient cards only")
				if not ok: continue
				var low := 100; var high := 0
				var seen := {}
				for h in g.hands:
					low=mini(low,h.size());high=maxi(high,h.size())
					for c in h:
						ck(not seen.has(c.id),"unique physical ID")
						seen[c.id]=true
						ck(c.rank in ranks or (c.rank==14 and mask&1) or (c.rank==15 and mask&2),"only enabled ranks dealt")
				ck(seen.size()==total and g.pile.is_empty(),"entire configured deck dealt")
				ck(high-low<=1 and low>=1,"balanced nonempty initial hands")
				ck(g.declared_rank==ranks[0] and g.phase=="play" and g.winner==-1,"clean initial phase")
	var g = fresh()
	for count in [-1,0,1,9,100]: reject(g,"configure",[count,[1],true,true,1],"bad player count")
	for ranks in [[],[0],[14],[15],[-1],[1,99],["A"],[1,1],[1,2.5]]:
		reject(g,"configure",[3,ranks,true,true,1],"bad ranks " + str(ranks))
	reject(g,"configure",[8,[1],true,true,1],"insufficient deck")
	reject(g,"configure",[3,[1,2],false,false,1,g.state_version-1],"stale restart")
	var version:int=g.state_version
	ck(g.configure(3,[1,2],false,false,1,version),"versioned restart")
	reject(g,"configure",[3,[1,2],false,false,1,version],"repeated restart")
func test_validation() -> void:
	var g = fresh()
	var id = g.hands[0][0].id
	for ids in [[],[id,id],["nonexistent"],[id,id,id,id,id],[g.hands[1][0].id]]:
		reject(g,"play_cards",[0,ids,g.state_version],"invalid play set")
	for actor in [-1,1,3,100]: reject(g,"play_cards",[actor,[id],g.state_version],"wrong actor")
	reject(g,"respond",[1,false,g.state_version],"response before play")
	var version: int = g.state_version
	play(g)
	reject(g,"play_cards",[0,[id],version],"duplicate play")
	reject(g,"respond",[1,false,version],"stale response")
	reject(g,"respond",[0,true,g.state_version],"self challenge")
	reject(g,"respond",[2,true,g.state_version],"out of order challenge")
	version=g.state_version
	ck(g.respond(1,false,version),"first decline")
	reject(g,"respond",[1,true,version],"duplicate response")
	ck(g.respond(2,false,g.state_version),"second decline")
	ck(g.current_player==1 and g.declared_rank==2,"next seat and next rank")
	g=fresh(3,[13,1,7])
	ck(g.declared_rank==1,"enabled rank cycle sorted")
	for expected in [7,13,1]:
		play(g);decline_all(g)
		ck(g.declared_rank==expected,"cycle skips disabled ranks")
func test_truth_and_pile() -> void:
	for rank in [1,2,14,15]:
		var g=rig([[rank,3],[2,4]])
		var ids:=identities(g)
		play(g)
		ck(g.respond(1,true,g.state_version),"challenge accepted")
		var loser: int = 0 if rank==2 else 1
		ck(g.hands[loser].size()==(2 if loser==0 else 3),"only nonmatching ordinary card is lie")
		ck(g.pile.is_empty() and g.phase=="play","challenge clears pile")
		ck(g.current_player==1 and g.declared_rank==2,"challenge advances from original player")
		conservation(g,ids)
	# Earlier false A is irrelevant when latest two cards are honest 2 + joker.
	var g=rig([[3,4],[2,14,5]])
	var ids:=identities(g)
	play(g);decline_all(g);play(g,[0,1])
	ck(g.pile.size()==3,"accumulated pile")
	var challenger_count: int = g.hands[2].size()
	ck(g.respond(2,true,g.state_version),"latest batch challenged")
	ck(g.hands[2].size()==challenger_count+3,"truthful latest batch sends entire pile to challenger")
	conservation(g,ids)
	# One bad card invalidates a mixed batch despite a joker.
	g=rig([[1,2,14,4],[3,5]])
	play(g,[0,1,2]);ck(g.respond(1,true,g.state_version),"mixed batch challenge")
	ck(g.hands[0].size()==4,"mixed batch lie returns whole pile to author")
func test_final_hand() -> void:
	for challenged in [false,true]:
		for honest in [false,true]:
			var g=rig([[1 if honest else 2],[3,4]])
			var ids:=identities(g)
			play(g)
			ck(g.hands[0].is_empty() and g.winner==-1 and g.phase=="response","empty hand victory deferred")
			if challenged:
				ck(g.respond(1,true,g.state_version),"challenge final hand")
				ck((g.winner==0 and g.phase=="finished") if honest else (g.winner==-1 and g.phase=="play" and g.hands[0].size()==1),"final challenge resolves victory correctly")
			else:
				ck(g.respond(1,false,g.state_version),"first final decline")
				ck(g.winner==-1 and g.phase=="response","last challenger retains chance")
				ck(g.respond(2,false,g.state_version),"last final decline")
				ck(g.winner==0 and g.phase=="finished","unchallenged final bluff wins")
			conservation(g,ids)
			if g.phase=="finished":
				reject(g,"respond",[1,true,g.state_version],"late challenge")
				reject(g,"play_cards",[1,[g.hands[1][0].id],g.state_version],"post-victory play")
func test_privacy() -> void:
	var g=fresh()
	for viewer in [-1,0,1,2]:
		var hands: Array=g.public_hands(viewer)
		for p in hands.size():
			for c in hands[p]:
				if p!=viewer:
					for key in ["rank","suit","title","face","texture","honest"]: ck(not c.has(key),"opponent record lacks " + key)
				else: ck(c.has("rank"),"own hand readable")
	play(g)
	for c in g.public_pile():
		for key in ["rank","suit","title","face","texture","honest"]: ck(not c.has(key),"concealed pile lacks " + key)
	var before:=state(g)
	var view: Array=g.public_hands(0)
	view[0][0]["rank"]=999
	view[0].clear()
	ck(state(g)==before,"public hand snapshot detached")
	view=g.public_pile();view.clear()
	ck(state(g)==before,"public pile snapshot detached")
func test_random_games() -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=21481
	for players in range(2,9):
		for iteration in 5:
			var g=fresh(players)
			var ids:=identities(g)
			for turn in 100:
				if g.phase=="finished": break
				if g.phase=="play":
					var chosen: Array=[]
					for i in rng.randi_range(1,mini(4,g.hands[g.current_player].size())): chosen.append(i)
					play(g,chosen)
				else:
					ck(g.respond(g.response_player(),rng.randi_range(0,3)==0,g.state_version),"random response")
				conservation(g,ids)
				ck(g.winner==-1 or g.hands[g.winner].is_empty(),"winner has empty hand")
