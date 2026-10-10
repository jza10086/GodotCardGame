extends SceneTree
## Independent interrupted settings, stale UI callbacks and lobby continuation.
const Rules=preload("res://scripts/bluff_rules.gd")
var checks:=0
var failures:=0
func ck(v:bool,label:String)->void:
	checks+=1
	if not v:failures+=1;push_error("BLUFF LIFECYCLE: "+label)
func state(g)->String:return var_to_str([g.hands,g.pile,g.phase,g.responders,g.current_player,g.declared_rank,g.state_version])
func _initialize()->void:call_deferred("run")
func mask(scene)->void:
	ck(scene.viewing_player==-1,"handoff has no viewer")
	for card in scene._card_nodes.values():
		ck(card.face_texture==null and card.viewer_masked and not card.data.has("rank"),"handoff strips all identities")
func run()->void:
	var session=root.get_node("CardSession");session.bluff=Rules.new()
	var g=session.get_bluff()
	var scene=load("res://scenes/bluff_game.tscn").instantiate();root.add_child(scene);current_scene=scene
	await process_frame
	ck(g.phase=="setup" and scene.modal_kind=="settings","first entry waits for explicit settings")
	for check in scene.rank_checks.values():check.button_pressed=false
	var before:=state(g)
	scene._start_round(scene.modal_generation)
	ck(state(g)==before and not scene.settings_error.text.is_empty(),"joker-only deck rejected without start")
	scene.rank_checks[1].button_pressed=true;scene.count_option.value=8
	scene._start_round(scene.modal_generation)
	ck(state(g)==before,"insufficient cards rejected without start")
	scene.count_option.value=3;scene.rank_checks[3].button_pressed=true;scene.big_check.button_pressed=false
	var token:int=scene.modal_generation
	scene._start_round(token);before=state(g);scene._start_round(token)
	ck(state(g)==before and g.enabled_ranks==[1,3] and g.total==9,"start commits custom toggles once")
	mask(scene)
	token=scene.modal_generation;scene._show_menu();scene._reveal(0,token)
	mask(scene);ck(scene.menu_open and scene.modal.visible,"stale reveal cannot dismiss newer menu")
	scene._handoff();scene._reveal(0,scene.modal_generation)
	ck(not scene.menu_open and scene.viewing_player==0,"explicit current handoff reveals viewer")
	scene._choose_card(g.hands[0][0].id);scene._show_settings()
	ck(scene.selected_ids.is_empty(),"settings clears pending selected cards")
	scene.count_option.value=2;scene.rank_checks[1].button_pressed=false
	token=scene.modal_generation;scene._handoff();scene._start_round(token)
	ck(state(g)==before and g.hands.size()==3,"cancel preserves game and rejects stale restart")
	scene._reveal(0,scene.modal_generation);scene._choose_card(g.hands[0][0].id);scene._play();before=state(g)
	scene._play();ck(state(g)==before,"double play cannot consume more cards")
	mask(scene)
	# Real navigation, not just inspecting the session getter.
	scene._lobby();await process_frame;await process_frame
	ck(current_scene.scene_file_path=="res://scenes/card_lobby.tscn" and state(g)==before,"lobby preserves pending response")
	ck(change_scene_to_file("res://scenes/bluff_game.tscn")==OK,"reenter bluff scene")
	await process_frame;await process_frame
	scene=current_scene
	ck(scene.game==g and state(g)==before,"reentry resumes same model exactly")
	mask(scene)
	var actor:int=g.response_player();scene._reveal(actor,scene.modal_generation)
	var version:int=g.state_version
	scene._show_help();scene._respond(true,version)
	ck(state(g)==before,"stale response after help cannot resolve batch")
	mask(scene)
	scene._handoff();scene._reveal(actor,scene.modal_generation);scene._respond(false,version)
	ck(g.response_player()==2,"resumed response proceeds normally")
	print("INDEPENDENT BLUFF LIFECYCLE REVIEW: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
