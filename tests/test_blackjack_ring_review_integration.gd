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
func privacy(scene)->void:
	var g=scene.game
	for p in g.players:
		for record in p.hand:
			var c=scene.card_node(record.id)
			ck(c.face_up and c.face_texture!=null,"all player cards face up from deal")
			ck(c.data.has("rank") and scene.inspection_snapshot(c).has("title"),"player public face inspectable")
	if not g.dealer_revealed:
		var c=scene.card_node(g.dealer_hand[1].id)
		ck(not c.face_up and c.face_texture==null,"dealer hole face unavailable")
		ck(not c.data.has("rank") and not c.data.has("suit"),"dealer hole metadata masked")
		ck(not scene.inspection_snapshot(c).has("title"),"dealer hole hover cannot reveal")
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
	scene._open_betting()
	ck(g.phase=="betting" and g.round_number==0,"opening form does not automatically bet")
	for control in scene.seat_bets:ck(control.value==0,"each seat defaults explicit skip")
	scene.seats_control.value=1
	for i in range(1,8):ck(not scene.seat_bets[i].editable and scene.seat_bets[i].value==0,"one-seat configuration disables other bets")
	scene.seats_control.value=8
	for control in scene.seat_bets:
		control.value=100
		control.get_line_edit().text="100"
	scene._deal();scene._deal()
	ck(g.round_number==1 and g.players[0].balance==900,"duplicate UI deal debits once")
	var state:=snap(g)
	scene._act("hit")
	ck(snap(g)==state,"deal flight blocks input")
	stable(scene)
	ck(scene.played.size()==2 and scene.hand.size()==2,"central dealer and local physical hand")
	rows(scene);privacy(scene)
	ck(scene.dealer_label.text.contains("明牌 10 + 暗牌") and not scene.dealer_label.text.contains("17"),"dealer score conceals hole total")
	for method in ["toggle_view","toggle_top_down","toggle_hand_stowed","reset_view"]:
		scene.call(method)
		rows(scene);privacy(scene)
	stable(scene);scene._open_menu()
	scene._act("hit");scene._process(2.0)
	ck(snap(g)==state,"pause freezes all players and dealer")
	scene._close_menu()
	scene._leave();await process_frame;await process_frame
	ck(current_scene.scene_file_path=="res://scenes/card_lobby.tscn","leave enters lobby")
	ck(snap(g)==state and session.get_blackjack_ring()==g,"leave preserves whole table state")
	ck(change_scene_to_file("res://scenes/blackjack_game.tscn")==OK,"reentry succeeds")
	await process_frame;await process_frame
	scene=current_scene;scene.set_process(false);stable(scene)
	ck(scene.game==g and snap(g)==state,"reentry resumes8 seats exact state")
	privacy(scene);rows(scene)
	scene._act("stand");stable(scene)
	ck(g.current_player==1 and g.phase=="player","manual next-seat action follows first seat")
	ck(scene.active_seat==1 and scene.controlled_player==1,"camera and controlled seat follow manual turn")
	state=snap(g)
	for i in 5:scene._process(1.0)
	ck(snap(g)==state,"waiting manual seat never automatically plays")
	scene._act("hit");stable(scene)
	ck(g.players[1].hand.size()==3,"buttons control current local seat")
	var count:=0
	while g.phase!="settled" and count<80:
		stable(scene)
		if g.phase=="player":scene._act("stand")
		else:scene._process(1.0)
		count+=1
	ck(g.phase=="settled","manual players then automated dealer settle")
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
