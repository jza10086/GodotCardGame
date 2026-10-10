extends SceneTree
const Rules=preload("res://scripts/bluff_rules.gd")
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
	checks+=1
	if not value: failures+=1; push_error("BLUFF UI: "+label)
func _initialize()->void: call_deferred("run")
func hidden(scene)->void:
	for node in scene._card_nodes.values():
		ck(not node.data.has("rank") and not node.data.has("suit") and not node.data.has("title") and node.face_texture==null,"private identity stripped")
		ck(not scene.inspection_snapshot(node).has("title"),"inspection has no identity")
func run()->void:
	var session=root.get_node("CardSession")
	session.bluff=Rules.new()
	var game=session.get_bluff()
	ck(game.configure(4,[1,2,3,11,12,13],true,true,42),"configure")
	var scene=load("res://scenes/bluff_game.tscn").instantiate()
	root.add_child(scene); current_scene=scene
	await process_frame; scene.set_process(false)
	ck(scene.modal.visible and scene.viewing_player==-1,"initial private handoff")
	hidden(scene)
	scene._reveal(0)
	ck(not scene.modal.visible and scene.hand.size()==game.hands[0].size(),"owner hand shown")
	for i in 4:
		for card in scene.player_hand(i):
			ck(card.data.has("rank")==(i==0),"only viewer has rank data")
	var id=game.hands[0][0].id
	scene._choose_card(id)
	ck(scene.selected_ids==[id] and not scene.play_action.disabled,"select enables submission")
	scene._play()
	ck(game.phase=="response" and scene.modal.visible,"play starts handoff not auto accept")
	hidden(scene)
	var version:int=game.state_version
	scene._reveal(1)
	ck(scene.modal.visible and scene.viewing_player==1,"response view waits for manual decision")
	scene._respond(false,version)
	ck(game.response_player()==2,"decline advances responder")
	scene._respond(false,version)
	ck(game.response_player()==2,"stale callback rejected")
	hidden(scene)
	scene._show_settings()
	var token:int=scene.modal_generation
	scene._show_menu(); scene._start_round(token)
	ck(game.state_version==version+1,"cancel settings prevents stale new round")
	scene._handoff(); scene._reveal(2)
	ck(scene.active_seat==4,"third viewer physical allocation")
	scene._show_menu(); hidden(scene)
	ck(scene._model_discard.size()==1 and not scene._model_discard[0].has("rank"),"discard snapshot sanitized")
	ck(session.get_bluff()==game,"session stable")
	scene.queue_free(); await process_frame; await process_frame
	print("Bluff integration: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
