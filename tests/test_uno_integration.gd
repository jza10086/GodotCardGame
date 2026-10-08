extends SceneTree
const RULES = preload("res://scripts/uno_rules.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
func _initialize() -> void: call_deferred("run")
func invariant(g, label: String) -> void:
	check(g.total_cards()==108,label+" conserves 108")
	var ids := {}
	for c in g.draw_pile + g.discard_pile: ids[c.id]=true
	for h in g.hands:
		for c in h: ids[c.id]=true
	check(ids.size()==108,label+" unique identities")
func run() -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=1234567
	var completed:=0
	for count in range(2,9):
		for seed_value in range(40):
			var g=RULES.new();g.start_game(count,seed_value)
			var steps:=0
			while g.phase!="finished" and steps<3000:
				invariant(g,"rules %d/%d/%d" % [count,seed_value,steps])
				var p:int=g.current_player
				var result:Dictionary
				match g.phase:
					"choose_color":result=g.choose_initial_color(p,RULES.COLORS[rng.randi_range(0,3)])
					"challenge":result=g.resolve_challenge(p,rng.randf()<0.5)
					_:
						if g.uno_player>=0 and not g.uno_announced:
							if rng.randf()<0.5:g.announce_uno(g.uno_player)
							else:g.catch_uno((g.uno_player+1)%count)
						var legal:Array=g.legal_indices(p)
						if not legal.is_empty() and rng.randf()<0.90:result=g.play_card(p,legal[rng.randi_range(0,legal.size()-1)],RULES.COLORS[rng.randi_range(0,3)],rng.randf()<0.5)
						elif g.phase=="drawn":result=g.pass_draw(p)
						else:result=g.draw_card(p)
				check(result.ok,"random command succeeds")
				steps+=1
			check(g.phase=="finished","seeded rules round completes %d/%d" % [count,seed_value]);invariant(g,"finished")
			if g.phase=="finished":completed+=1
	print("Seeded rules rounds completed: ",completed)
	var demo=load("res://scenes/uno_game.tscn").instantiate();root.add_child(demo)
	await process_frame
	demo.set_process(false)
	for count in range(2,9):
		demo._start_game(count)
		demo.choosing=false;demo.modal.hide();demo.game.start_game(count,count+20);demo._sync(false)
		var steps:=0
		while demo.game.phase!="finished" and steps<1500:
			if demo.paused and demo.game.phase!="finished":demo._close_pause()
			demo.settle_flights();demo._refresh_hud()
			var g=demo.game
			invariant(g,"integration")
			check(demo.total_cards()==108,"presenter conserves total")
			check(demo._card_nodes.size()==108,"presenter retains unique node per card")
			for p in range(1,count):
				for card in demo.player_hand(p):
					check(card.viewer_masked and not card.public_snapshot().has("title"),"opponent remains private")
			if g.current_player==0:
				match g.phase:
					"choose_color":demo._show_color(null);demo._choose_color("red")
					"challenge":demo._challenge(steps%2==0)
					_:
						var legal:Array=g.legal_indices(0)
						if not legal.is_empty():
							var id=g.hands[0][legal[0]].id
							demo.announce_check.button_pressed=true;demo._human_card(id)
							if demo.choosing:demo._choose_color(demo._bot_color(0))
						elif g.phase=="drawn":demo._human_pass()
						else:demo._human_draw()
			else:demo._process(2.0)
			steps+=1
			await process_frame
		check(demo.game.phase=="finished","controller round completes %d" % count)
		check(demo.paused and demo.modal.visible,"result shown")
		print("Controller round ",count," players finished in ",steps," actions")
	# Repeated input, a cancellable wild, and blocked gameplay shortcuts.
	demo._start_game(4);demo.choosing=false;demo.modal.hide();demo.game.start_game(4,33)
	demo.game.current_player=0;demo.game.phase="playing";demo._sync(false)
	var before_draw:int=demo.game.hands[0].size()
	demo._human_draw();demo._human_draw();demo._human_draw()
	check(demo.game.hands[0].size()==before_draw+1,"repeated draw accepts exactly one")
	demo._start_game(4);demo.choosing=false;demo.modal.hide();demo.game.start_game(4,33)
	demo.game.current_player=0;demo.game.phase="playing"
	var wild:Dictionary={}
	for i in range(demo.game.draw_pile.size()-1,-1,-1):
		if demo.game.draw_pile[i].color=="wild":wild=demo.game.draw_pile.pop_at(i);break
	demo.game.hands[0].append(wild);demo._sync(false)
	var before_color:Array=demo.game.hands.duplicate(true)
	demo._human_card(wild.id)
	check(demo.choosing and demo.modal.visible,"wild opens color picker")
	demo._human_draw();demo._human_card(wild.id)
	check(demo.game.hands==before_color,"color modal blocks all other actions")
	demo._cancel_color()
	check(not demo.choosing and demo.game.hands==before_color,"cancel wild preserves state")
	demo._open_pause()
	for code in [KEY_D,KEY_F,KEY_H,KEY_2,KEY_ENTER]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=true
		demo._input(event);demo._unhandled_input(event)
	check(demo.game.hands==before_color and demo.active_seat==0,"pause prevents gameplay and debug cheating shortcuts")
	demo._close_pause()
	# More than the original template's eight cards: preserve every card and expose
	# a pickable strip for each at the standard viewport.
	while demo.game.hands[0].size()<30:demo.game.hands[0].append(demo.game.draw_pile.pop_back())
	demo._sync(false);demo.settle_flights();demo.update_hand_pose(1.0);demo._refresh_hud()
	check(demo.hand.size()==30 and demo.total_cards()==108,"large hand never capped or truncated")
	for card in demo.hand:
		var box:Rect2=demo.hand_card_rect(card).intersection(root.get_visible_rect())
		var found:=false
		for x in range(int(box.position.x)+1,int(box.end.x),2):
			if demo.pick(Vector2(x,box.get_center().y))==card:found=true;break
		check(found,"30-card hand exposes pick strip for "+str(card.data.id))
	for mode in [0,1,2]:
		if mode==1:demo.toggle_view()
		if mode==2:demo.toggle_top_down()
		for player in range(1,4):
			for card in demo.player_hand(player):
				check(card.viewer_masked and not demo.inspection_snapshot(card).has("title"),"all camera modes preserve opponent privacy")
	# Only the human challenger receives the hand-evidence dialog. Its pause must
	# be dismissible and prevent accidental draw commands underneath.
	demo._start_game(2);demo.choosing=false;demo.modal.hide();demo.game.start_game(2,12)
	demo.game.current_player=1;demo.game.phase="playing"
	var four:Dictionary={}
	for i in range(demo.game.draw_pile.size()-1,-1,-1):
		if demo.game.draw_pile[i].value=="draw_four":four=demo.game.draw_pile.pop_at(i);break
	demo.game.hands[1].append(four)
	var played:Dictionary=demo.game.play_card(1,demo.game.hands[1].size()-1,"blue",true)
	check(played.ok and demo.game.challenge_target==0,"human targeted by challenge fixture")
	demo._sync(false);demo._challenge(true)
	check(demo.paused and demo.modal.visible,"challenge evidence pauses in visible modal")
	var evidence_state:Array=demo.game.hands.duplicate(true)
	demo._human_draw()
	check(demo.game.hands==evidence_state,"evidence modal blocks gameplay behind it")
	demo._close_pause()
	check(not demo.paused and not demo.modal.visible,"challenge evidence dismiss resumes")
	# Restart in the middle of draw animation; old flights must never mutate new round.
	demo._start_game(4);demo.choosing=false;demo.modal.hide();demo.game.start_game(4,33);demo._sync(false)
	if demo.game.phase=="choose_color":demo._show_color(null);demo._choose_color("red")
	demo.game.current_player=0;demo.game.phase="playing";demo._human_draw()
	demo._start_game(8)
	var new_ids=demo.game.hands.duplicate(true)
	demo.advance_flights(10.0)
	check(demo.game.hands==new_ids and demo.total_cards()==108,"restart cancels prior flights")
	# Finished-state menus must preserve access to Next Round and score exactly once.
	demo.choosing=false;demo.game.phase="finished";demo.game.winner=0;demo.game.score=17;demo.paused=false;demo._show_result()
	var standings:Array=demo.game.round_standings()
	demo.paused=false;demo._open_pause();demo._close_pause()
	check(demo.paused and demo.modal.visible,"finished pause return restores result")
	check(demo.game.round_standings()==standings,"finished pause return scores only once")
	# Emit the actual pressed signal: callbacks rebuild the modal while the
	# old button is still emitting, so detach + deferred free is mandatory.
	var menu_button: Button = null
	for child in demo.modal_box.get_children():
		if child is Button and child.text == "人数 / 规则菜单":menu_button=child
	check(menu_button != null,"result exposes menu button")
	menu_button.pressed.emit()
	check(demo.modal_box.get_child(0) is Label and demo.modal_box.get_child(0).text == "彩序 / 牌桌菜单","pressed-signal rebuild leaves no stale result button")
	var escape := InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
	demo._input(escape)
	check(demo.modal_box.get_child(0) is Label and "本局结算" in demo.modal_box.get_child(0).text,"Escape from finished menu restores result")
	check(demo.game.round_standings()==standings,"pressed-signal and Escape flow never double-scores")
	await process_frame
	check(not is_instance_valid(menu_button),"pressed control is eventually freed safely")
	demo.queue_free();await process_frame
	print("UNO INTEGRATION CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
