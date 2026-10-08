extends SceneTree
## Independent regression suite: every optional-rule combination plus hostile
## event orders, debt cycles, forced draws, UNO windows, and final scoring.
## Run: godot --headless --path . --script res://tests/test_uno_options.gd
const Rules = preload("res://scripts/uno_rules.gd")
var checks := 0
var failures := 0
var next_id := 2000
func ck(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("QA FAIL: "+label)
func c(color: String,value: String) -> Dictionary:
	next_id+=1
	return {"id":next_id,"color":color,"value":value}
func opts(mask: int) -> Dictionary:
	return {"continuous_draw":bool(mask&1),"jump_in":bool(mask&2),"stacking":bool(mask&4),"forbid_last_wild":bool(mask&8)}
func fix(mask: int=0,n: int=4):
	var g=Rules.new();g.start_game(n,101,opts(mask))
	g.hands=[]
	for p in n:g.hands.append([c("blue","7"),c("green","8")])
	g.draw_pile=[]
	for i in 40:g.draw_pile.append(c("yellow",str(i%10)))
	g.discard_pile=[c("red","5")]
	g.current_player=0;g.direction=1;g.active_color="red";g.phase="playing"
	return g
func snap(g) -> String:
	return JSON.stringify([g.hands,g.draw_pile,g.discard_pile,g.current_player,g.direction,g.phase,g.active_color,g.pending_play,g.pending_draw,g.pending_winner,g.uno_player,g.uno_announced,g.winner,g.score,g.state_version,g.forced_play,g.options])
func conserved(g) -> bool:
	var ids={}
	for card in g.draw_pile+g.discard_pile:ids[card.id]=true
	for h in g.hands:
		for card in h:ids[card.id]=true
	return g.total_cards()==108 and ids.size()==108
func _initialize() -> void:
	test_matrix()
	test_jump()
	test_continuous()
	test_stack()
	test_last_wild()
	test_extra()
	test_finishes()
	test_pending_uno_and_returned_debt()
	test_options_and_penalty_cycles()
	test_remaining_edges()
	test_strict_last_wild_exhaustion()
	print("INDEPENDENT OPTIONAL QA: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func test_matrix() -> void:
	var finished:=0
	var commands:=0
	var rng=RandomNumberGenerator.new();rng.seed=994812
	for mask in 16:
		for count in [2,3,4,8]:
			for seed_value in 12:
				var g=Rules.new();g.start_game(count,seed_value*17+count,opts(mask))
				var steps:=0
				while g.phase!="finished" and steps<5000:
					var r:Dictionary={}
					var p:int=g.current_player
					var did_jump:=false
					if not g.pending_play.is_empty() and rng.randf()<0.45:
						var order:Array=range(count)
						for j in order:
							var jumps:Array=g.jump_in_indices(j)
							if not jumps.is_empty():
								r=g.jump_in(j,jumps[0],true,g.state_version);did_jump=true;break
					if not did_jump:
						match g.phase:
							"choose_color":r=g.choose_initial_color(p,"red")
							"challenge":r=g.resolve_challenge(p,rng.randf()<0.5)
							"pending_effect":r=g.accept_pending(p)
							"stacking":
								var legal:Array=g.legal_indices(p)
								if not legal.is_empty() and rng.randf()<0.8:r=g.play_card(p,legal[0],"blue",true)
								else:r=g.accept_stack(p)
							_:
								var legal:Array=g.legal_indices(p)
								if not legal.is_empty() and (g.forced_play or rng.randf()<0.9):r=g.play_card(p,legal[rng.randi_range(0,legal.size()-1)],Rules.COLORS[rng.randi_range(0,3)],true)
								elif g.phase=="drawn":r=g.pass_draw(p)
								else:r=g.draw_card(p)
					steps+=1;commands+=1
					ck(r.get("ok",false),"matrix %d/%d/%d command phase %s: %s" % [mask,count,seed_value,g.phase,r])
					ck(conserved(g),"matrix %d/%d unique conservation" % [mask,count])
					ck(g.current_player>=0 and g.current_player<count,"matrix valid current")
					if not r.get("ok",false):break
				ck(g.phase=="finished","matrix %d/%d/%d terminates (%s)" % [mask,count,seed_value,g.phase])
				if g.phase=="finished":finished+=1
				if g.winner>=0:ck(g.hands[g.winner].is_empty(),"matrix winner empty")
		print("Matrix mask ",mask," complete")
	print("Independent matrix completed ",finished,"/768 rounds in ",commands," accepted commands")
func test_jump() -> void:
	for mask in [2,3,6,7,10,11,14,15]:
		for value in ["7","skip","reverse","draw_two"]:
			var g=fix(mask)
			g.hands[0]=[c("red",value),c("blue","1"),c("green","2")]
			g.hands[2]=[c("red",value),c("blue","1"),c("green","2")]
			ck(g.play_card(0,0).ok,"jump original "+value)
			ck(not g.pending_play.is_empty(),"colored play pending "+value)
			var ver:int=g.state_version
			var before:String=snap(g)
			ck(not g.jump_in(2,0,false,ver-1).ok and snap(g)==before,"stale jump inert")
			ck(g.jump_in(2,0,false,ver).ok,"out of turn exact jump "+value)
			ck(g.top_card().value==value,"jump changes top")
			if value=="reverse":ck(g.direction==-1 and g.current_player==1,"reverse canceled not doubled")
			if value=="skip":ck(g.current_player==0,"skip based on jumper not original")
			if value=="draw_two":
				ck(g.hands[1].size()==2 and g.hands[3].size()==2,"no canceled +2 draws")
				if mask&4:
					ck(g.pending_draw==2,"jump replaces +2 debt")
					ck(g.accept_stack(3).ok,"jumped stack accepted")
				else:ck(g.accept_pending(3).ok,"jumped penalty accepted")
				ck(g.hands[1].size()==2 and g.hands[3].size()==4,"only new +2 victim pays")
		var g=fix(mask)
		g.hands[0]=[c("red","7"),c("red","7"),c("green","2")]
		g.play_card(0,0)
		ck(g.jump_in_indices(0)==[0] and g.jump_in(0,0).ok,"self-jump")
		g=fix(mask)
		g.hands[0]=[c("red","7"),c("green","2")]
		g.hands[1]=[c("red","8"),c("blue","1")]
		g.hands[2]=[c("red","7"),c("green","2")]
		g.play_card(0,0)
		var v:int=g.state_version
		ck(g.play_card(1,0).ok,"next actual play wins race")
		var before:String=snap(g)
		ck(not g.jump_in(2,0,false,v).ok and snap(g)==before,"losing old-version jump cannot mutate")
		g=fix(mask)
		g.hands[0]=[c("red","7"),c("green","2")]
		g.hands[2]=[c("red","7"),c("green","2")]
		g.play_card(0,0)
		before=snap(g)
		ck(not g.play_card(3,0).ok and snap(g)==before,"invalid play leaves pending intact")
		ck(not g.jump_in(1,0).ok and snap(g)==before,"wrong color/value jump inert")
		g=fix(mask)
		g.hands[0]=[c("wild","wild"),c("green","2")]
		g.hands[2]=[c("wild","wild"),c("green","2")]
		g.play_card(0,0,"red")
		ck(g.jump_in_indices(2).is_empty() and not g.jump_in(2,0).ok,"wild never jumps")
func test_continuous() -> void:
	for mask in [1,3,5,7,9,11,13,15]:
		var g=fix(mask)
		g.draw_pile=[c("red","9"),c("yellow","1"),c("blue","3")]
		ck(g.draw_card(0).ok,"continuous starts")
		ck(g.hands[0].size()==4 and g.top_card().value=="9","continuous draws two then auto plays first match")
		g=fix(mask)
		var wild:Dictionary=c("wild","wild")
		g.draw_pile=[c("red","9"),wild,c("blue","3")]
		ck(g.draw_card(0).ok and g.forced_play,"continuous wild requires color")
		var before:String=snap(g)
		ck(not g.pass_draw(0).ok and snap(g)==before,"forced wild cannot pass")
		ck(not g.draw_card(0).ok and snap(g)==before,"forced wild cannot draw more")
		ck(g.play_card(0,g.hands[0].size()-1,"green").ok,"forced wild selection succeeds")
		ck(g.top_card().id==wild.id,"forced exact wild played")
		g=fix(mask)
		g.draw_pile=[];g.discard_pile=[c("red","5")]
		ck(g.draw_card(0).ok,"continuous exhausted returns")
		if g.phase=="drawn":ck(g.pass_draw(0).ok,"continuous exhausted can pass")
		ck(g.current_player!=0,"continuous exhausted no deadlock")
func test_stack() -> void:
	for mask in [4,5,6,7,12,13,14,15]:
		var g=fix(mask)
		g.hands[0]=[c("red","draw_two"),c("green","1")]
		g.hands[1]=[c("blue","draw_two"),c("green","1")]
		g.hands[2]=[c("wild","draw_four"),c("green","1")]
		g.hands[3]=[c("red","draw_two"),c("wild","draw_four"),c("green","1")]
		ck(g.play_card(0,0).ok,"stack begins")
		ck(g.play_card(1,0).ok and g.pending_draw==4,"+2+2 debt4")
		ck(g.play_card(2,0,"green").ok and g.pending_draw==8,"+2+2+4 debt8")
		var before:String=snap(g)
		ck(not g.play_card(3,0).ok and snap(g)==before,"cannot deescalate +4 to +2")
		ck(g.play_card(3,1,"green").ok and g.pending_draw==12,"+4+4 debt12")
		var amount:int=g.hands[0].size()
		ck(g.accept_stack(0).ok and g.hands[0].size()==amount+12,"stack target pays full12")
		ck(g.current_player==1 and g.pending_draw==0,"paid stack skips target and clears")
func test_last_wild() -> void:
	for mask in [8,9,10,11,12,13,14,15]:
		var g=fix(mask)
		g.hands[0]=[c("red","7"),c("wild","wild")]
		var total:int=g.total_cards()
		ck(g.play_card(0,0).ok,"lastwild transition play")
		if mask&2:
			ck(g.hands[0].size()==1,"lastwild defers during jump")
			g.draw_card(g.current_player)
		ck(g.hands[0].size()==2,"sole wild draws exactly1")
		ck(g.total_cards()==total,"lastwild conserved")
		var amount:int=g.hands[0].size()
		g.legal_indices(0);g.top_card();g.jump_in_indices(0)
		ck(g.hands[0].size()==amount,"lastwild reads never retrigger")
func test_extra() -> void:
	for mask in [6,7,14,15]:
		var g=fix(mask)
		g.hands[0]=[c("red","draw_two"),c("green","1")]
		g.hands[1]=[c("blue","draw_two"),c("green","1")]
		g.hands[2]=[c("blue","draw_two"),c("green","1")]
		g.play_card(0,0);g.play_card(1,0)
		ck(g.pending_draw==4,"stack+jump existing debt4")
		ck(g.jump_in(2,0).ok and g.pending_draw==4,"jump replaces only most recent debt contribution")
		ck(g.accept_stack(3).ok and g.hands[3].size()==6,"stack+jump pays4 not6 or2")
	for mask in [2,3,6,7,10,11,14,15]:
		var g=fix(mask)
		g.hands[0]=[c("red","7"),c("green","2")]
		g.hands[2]=[c("red","7"),c("green","2")]
		g.play_card(0,0)
		var v:int=g.state_version
		ck(g.draw_card(1).ok,"actual draw seals previous play")
		var before:String=snap(g)
		ck(not g.jump_in(2,0,false,v).ok and snap(g)==before,"old jump after draw rejected")
		g=fix(mask)
		g.hands[0]=[c("red","7"),c("green","2")]
		g.hands[1]=[c("red","7"),c("blue","1")]
		g.hands[2]=[c("red","7"),c("green","2")]
		g.play_card(0,0);v=g.state_version
		ck(g.jump_in(2,0,false,v).ok,"first submitted competitor jump accepted")
		before=snap(g)
		ck(not g.jump_in(1,0,false,v).ok and snap(g)==before,"second simultaneous old-version jump rejected")
		var old_v:int=g.state_version
		g.start_game(4,101,opts(mask))
		before=snap(g)
		ck(g.state_version>old_v and not g.jump_in(2,0,false,old_v).ok and snap(g)==before,"restart invalidates old request version")
func test_finishes() -> void:
	for mask in 16:
		for value in ["7","skip","reverse"]:
			var g=fix(mask)
			g.hands[0]=[c("red",value)]
			g.hands[2]=[c("red",value),c("green","1")]
			ck(g.play_card(0,0).ok and g.phase=="finished" and g.winner==0,"final "+value+" wins immediately mask"+str(mask))
			var before:String=snap(g)
			ck(not g.jump_in(2,0).ok and snap(g)==before,"finished rejects racing jump")
		var g=fix(mask)
		g.hands[0]=[c("red","draw_two")]
		g.hands[1]=[c("blue","draw_two"),c("green","1")]
		ck(g.play_card(0,0).ok,"final +2 accepted")
		if mask&4:
			ck(g.phase=="stacking" and g.winner==-1,"final +2 defers for debt")
			ck(g.play_card(1,0).ok,"final +2 can be stacked")
			ck(g.accept_stack(2).ok,"final stack paid")
			ck(g.hands[2].size()==6,"final stack drawn before score")
		elif mask&2:
			ck(g.phase=="pending_effect" and g.winner==-1,"final +2 jump opportunity")
			ck(g.accept_pending(1).ok,"final +2 penalty paid")
			ck(g.hands[1].size()==4,"final +2 draws before win")
		ck(g.phase=="finished" and g.winner==0,"first empty player wins after penalty")
		var score:=0
		for h in g.hands:
			for card in h:score+=Rules.card_points(card)
		ck(g.score==score,"final penalty scoring complete")
func test_pending_uno_and_returned_debt() -> void:
	for mask in [2,3,6,7,10,11,14,15]:
		var g=fix(mask)
		g.hands[0]=[c("red","7"),c("blue","1")]
		g.play_card(0,0)
		ck(g.announce_uno(0).ok,"pending colored player may announce UNO")
		g=fix(mask)
		g.hands[0]=[c("red","7"),c("blue","1")]
		g.play_card(0,0)
		ck(g.catch_uno(1).ok and g.hands[0].size()==3,"pending colored omission may be caught before next actual action")
	for mask in [4,5,6,7,12,13,14,15]:
		var g=fix(mask,2)
		g.hands[0]=[c("red","draw_two")]
		g.hands[1]=[c("blue","draw_two"),c("blue","1")]
		g.play_card(0,0);g.play_card(1,0);g.accept_stack(0)
		ck(g.phase!="finished" and g.hands[0].size()==4,"debt returned to empty candidate prevents win")
		ck(g.pending_winner==-1,"returned debt clears invalidated winner candidate")
		ck(g.play_card(1,0).ok and g.phase=="finished" and g.winner==1,"new empty player wins after former winner had to draw")
func test_options_and_penalty_cycles() -> void:
	var initial=Rules.new()
	ck(initial.options==Rules.DEFAULT_OPTIONS,"all four switches disabled by default")
	var input:Dictionary=opts(15)
	initial.start_game(4,101,input);input.continuous_draw=false
	ck(initial.options.continuous_draw,"options copied, external menu changes cannot mutate round")
	initial.start_game(4,101)
	ck(initial.options==Rules.DEFAULT_OPTIONS,"new default start resets all switches")
	for mask in [4,5,6,7,12,13,14,15]:
		var g=fix(mask,3)
		g.hands[0]=[c("red","draw_two")]
		g.hands[1]=[c("blue","draw_two")]
		g.hands[2]=[c("yellow","draw_two")]
		ck(g.play_card(0,0).ok and g.play_card(1,0).ok and g.play_card(2,0).ok,"all players empty in +2 chain")
		ck(g.accept_stack(0).ok and g.hands[0].size()==6,"full cycle empty initiator pays debt6")
		ck(g.phase=="finished" and g.winner==1,"earliest still-empty player wins stack cycle")
		g=fix(mask)
		g.hands[0]=[c("wild","draw_four"),c("red","9")]
		ck(g.play_card(0,0,"blue").ok and g.phase=="stacking","stack variant initial +4 unchallengeable")
		var before:String=snap(g)
		ck(not g.resolve_challenge(1,true).ok and snap(g)==before,"stack variant challenge cannot alter debt")
		g.hands[1]=[c("blue","draw_two"),c("wild","draw_four"),c("green","8")]
		ck(g.legal_indices(1)==[1],"+4 initial stack admits only another+4")
	for mask in [2,3,6,7,10,11,14,15]:
		var g=fix(mask,2)
		g.hands[0]=[c("red","reverse"),c("red","reverse"),c("green","1")]
		g.play_card(0,0)
		ck(g.current_player==0 and g.direction==-1,"two-player reverse projects actor turn")
		ck(g.jump_in(0,0).ok and g.direction==-1 and g.current_player==0,"two-player selfreverse replaces instead of flips again")
		var v:int=g.state_version
		var before:String=snap(g)
		ck(not g.draw_card(0,v-1).ok and snap(g)==before,"stale draw cannot seal pending")
		ck(not g.play_card(0,0,"",false,v-1).ok and snap(g)==before,"stale normal play cannot seal pending")
func test_remaining_edges() -> void:
	for mask in [1,3,5,7,9,11,13,15]:
		var g=fix(mask)
		g.hands[0]=[c("red","2"),c("blue","1")]
		g.draw_pile=[c("red","9"),c("red","8")]
		var r:Dictionary=g.draw_card(0)
		ck(r.drawn_count==1 and not g.forced_play and g.phase=="drawn","continuous applies only when no initial legal card")
		ck(g.pass_draw(0).ok,"voluntary single draw stays optional")
		g=fix(mask)
		g.draw_pile=[c("red","9"),c("wild","draw_four"),c("blue","3")]
		g.draw_card(0)
		ck(g.forced_play and g.can_play_draw_four(0),"first continuous +4 must play and is lawful")
		ck(g.play_card(0,g.hands[0].size()-1,"blue").ok,"forced+4 plays after color")
		if not mask&4:
			ck(not g.resolve_challenge(1,true).challenge_success,"lawful continuous+4 fails challenge")
	for mask in [8,9,10,11,12,13,14,15]:
		var g=fix(mask)
		g.hands[0]=[c("red","7"),c("wild","wild")]
		g.draw_pile=[c("wild","wild"),c("wild","wild")]
		g.play_card(0,0)
		if mask&2:g.draw_card(g.current_player)
		ck(g.hands[0].size()==2 and g.hands[0][1].color=="wild","lastwild draws only once even if added card wild")
	for mask in [2,3,6,7,10,11,14,15]:
		var g=fix(mask)
		g.hands[0]=[c("red","draw_two"),c("green","1")]
		g.play_card(0,0)
		ck(g.catch_uno(2).ok and not g.pending_play.is_empty(),"UNO catch does not seal jump window")
		ck(g.hands[1].size()==2,"UNO catch does not prematurely draw predecessor penalty")


func test_strict_last_wild_exhaustion() -> void:
	for mask in [8,9,10,11,12,13,14,15]:
		for value in ["wild","draw_four"]:
			var g=fix(mask,2)
			g.hands=[[c("wild",value)],[c("blue","1")]]
			g.draw_pile=[]
			g.discard_pile=[c("red","5")]
			var before:String=snap(g)
			ck(g.legal_indices(0).is_empty(),"strict solewild not legal even exhausted mask%d %s" % [mask,value])
			ck(not g.play_card(0,0,"red").ok and snap(g)==before,"strict exhausted solewild rejection preserves state/version")
			for player in 2:
				var result:Dictionary=g.draw_card(player)
				ck(result.ok and result.drawn_count==0 and g.phase=="drawn" and not g.forced_play,"strict exhausted draw bounded with no forced-play deadlock")
				ck(g.pass_draw(player).ok,"strict exhausted player can pass")
			ck(g.phase=="finished" and g.winner==-1 and g.finish_reason=="stalemate","strict solewild exhaustion ends finite stalemate")
			ck(g.hands[0].size()==1 and g.hands[0][0].value==value,"strict stalemate never discards forbidden finalwild")
