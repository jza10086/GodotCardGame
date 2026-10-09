extends SceneTree
const Rules=preload("res://scripts/blackjack_ring_rules.gd")
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error("RING UI REVIEW: "+label)
func _initialize()->void:call_deferred("run")
func snap(g)->String:return JSON.stringify(g.snapshot())
func stable(scene)->void:
	scene.flights.clear()
	for c in scene._card_nodes.values():
		if is_instance_valid(c._flip_tween):c._flip_tween.kill()
	scene._sync(false)
func own_hole(scene):return scene.card_node(scene.game.players[0].hand[1].id)
func privacy(scene)->void:
	var g=scene.game
	var hidden:Array=[g.dealer_hand[1].id]
	for i in range(1,8):hidden.append(g.players[i].hand[1].id)
	for id in hidden:
		var c=scene.card_node(id)
		ck(not c.face_up and c.face_texture==null,"other hidden cards have no face asset")
		ck(not c.data.has("rank") and not c.data.has("suit"),"other hidden cards have no rank/suit in presentation")
		ck(not scene.inspection_snapshot(c).has("title"),"hover cannot disclose other hidden face")
		scene._peek_card(id)
		ck(not c.face_up and not scene.peek_ids.has(id),"click cannot peek opponents/dealer")
func rows(scene)->void:
	for p in scene.game.players:
		for record in p.hand:
			var c=scene.card_node(record.id)
			ck(c.get_parent()==scene,"all hands remain parented to physical table")
			ck(c.position.y<0.5 and c.position.y>=0,"cards remain on tabletop")
func run()->void:
	var session=root.get_node("CardSession")
	session.blackjack_ring=Rules.new(494)
	var g=session.get_blackjack_ring()
	# Each player8+8, dealer10+7, later draws2. IDs are unique six-deck cards.
	var ids:Array=[]
	for i in 8:ids.append(i*13+7)
	ids.append(9)
	for i in range(8,16):ids.append(i*13+7)
	ids.append(6);ids.append(1)
	ck(g.set_next_draws(ids).ok,"fixture accepted")
	var scene=load("res://scenes/blackjack_game.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	await process_frame
	scene.set_process(false)
	ck(scene.game==g and g.players.size()==8,"session starts8 players")
	scene.bet_control.value=100;scene._deal();scene._deal()
	ck(g.round_number==1 and g.players[0].balance==900,"duplicate UI deal debits once")
	var state:=snap(g)
	scene._act("hit")
	ck(snap(g)==state,"deal flight blocks input")
	stable(scene)
	ck(scene.played.size()==2 and scene.hand.size()==2,"central dealer and local physical hand")
	rows(scene);privacy(scene)
	ck(scene.dealer_label.text.contains("明牌 10 + 暗牌") and not scene.dealer_label.text.contains("17"),"dealer score conceals hole total")
	var own=own_hole(scene)
	ck(not own.face_up and not scene.inspection_snapshot(own).has("title"),"own hole initially face down; hover hides")
	scene._peek_card(own.data.id)
	ck(own.face_up and scene.peek_ids.has(own.data.id),"own click temporarily reveals")
	ck(snap(g)==state,"local peek never mutates model")
	scene._peek_card(own.data.id)
	ck(not own.face_up and scene.peek_ids.is_empty(),"second click closes peek")
	for method in ["toggle_view","toggle_top_down","toggle_hand_stowed","reset_view"]:
		scene._peek_card(own.data.id);scene.call(method)
		ck(scene.peek_ids.is_empty() and not own.face_up,method+" closes private peek")
		rows(scene);privacy(scene)
	stable(scene);scene._peek_card(own.data.id);scene._open_menu()
	ck(scene.peek_ids.is_empty() and not own.face_up,"menu closes private peek")
	scene._act("hit");scene._process(2.0)
	ck(snap(g)==state,"pause freezes all players and dealer")
	scene._close_menu();scene._peek_card(own.data.id)
	scene._leave();await process_frame;await process_frame
	ck(current_scene.scene_file_path=="res://scenes/card_lobby.tscn","leave enters lobby")
	ck(snap(g)==state and session.get_blackjack_ring()==g,"leave preserves whole table state")
	ck(change_scene_to_file("res://scenes/blackjack_game.tscn")==OK,"reentry succeeds")
	await process_frame;await process_frame
	scene=current_scene;scene.set_process(false);stable(scene)
	ck(scene.game==g and snap(g)==state,"reentry resumes8 seats exact state")
	ck(scene.peek_ids.is_empty() and not own_hole(scene).face_up,"reentry does not restore temporary reveal")
	privacy(scene);rows(scene)
	scene._act("stand");stable(scene)
	ck(g.current_player==1 and g.phase=="player","AI1 acts after human before dealer")
	state=snap(g);scene._act("hit");scene._act("stand");scene._act("double_down")
	ck(snap(g)==state,"human buttons cannot control AI hands")
	var count:=0
	while g.phase!="settled" and count<80:
		stable(scene);scene._process(1.0);count+=1
	ck(g.phase=="settled","controller progresses7 bots then dealer to settlement")
	stable(scene);state=snap(g)
	for i in 5:scene._process(1.0)
	ck(snap(g)==state,"postsettlement frames never pay again")
	for p in g.players:
		ck(not p.result.is_empty(),"all8 result rows exist")
		for record in p.hand:ck(scene.card_node(record.id).face_up,"all player cards reveal at settlement")
	var balance:Array=[]
	for p in g.players:balance.append(p.balance)
	scene._act("next_round");stable(scene)
	for i in 8:ck(g.players[i].balance==balance[i],"next round preserves seat wallet")
	print("INDEPENDENT RING UI REVIEW: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
