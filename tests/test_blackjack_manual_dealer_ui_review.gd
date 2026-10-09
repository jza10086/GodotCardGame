extends SceneTree
## Independent manual dealer UI interruption and state ownership audit.
const Rules=preload("res://scripts/blackjack_ring_rules.gd")
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error("MANUAL DEALER UI REVIEW: "+label)
func _initialize()->void:call_deferred("run")
func snap(g)->String:return JSON.stringify(g.snapshot())
func stable(scene)->void:
	scene.flights.clear()
	for c in scene._card_nodes.values():
		if is_instance_valid(c._flip_tween):c._flip_tween.kill()
	scene._sync(false)
func text_tree(node:Node)->String:
	var result:=""
	if node is Label or node is Button: result+=node.text+"\n"
	for child in node.get_children():result+=text_tree(child)
	return result
func no_advice(scene)->void:
	var text:String=scene.status_label.text+scene.detail_label.text+scene.results_label.text
	ck(not text.contains("EV") and not text.contains("期望") and not text.contains("建议"),"manual HUD contains no EV/advice")
	ck(scene.game.dealer_advice.is_empty(),"manual model stores no recommendation")
func select_mode(scene,mode:String)->void:
	var control:OptionButton=scene.dealer_mode_control
	var found:=false
	for i in control.item_count:
		var label:=control.get_item_text(i)
		if (mode=="human" and (label.contains("真人") or label.contains("手动") or label.contains("玩家"))) or (mode=="ai" and label.contains("AI")):
			control.select(i);found=true;break
	ck(found,"dealer mode option available: "+mode)
func run()->void:
	root.size=Vector2i(1180,800)
	root.content_scale_size=Vector2i(1180,800)
	var session=root.get_node("CardSession")
	session.blackjack_ring=Rules.new(616)
	var g=session.get_blackjack_ring()
	# One challenger 8+8, dealer 10+7, then 2, 1.
	ck(g.set_next_draws([7,9,20,6,1,0]).ok,"fixture accepted")
	var scene=load("res://scenes/blackjack_game.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	await process_frame;scene.set_process(false)
	scene._open_betting();select_mode(scene,"human")
	scene.seat_bets[0].value=100;scene.seat_bets[0].get_line_edit().text="100"
	var before:=snap(g)
	scene._close_menu()
	ck(snap(g)==before and g.dealer_mode=="ai","cancel does not commit selected mode")
	scene._deal()
	ck(snap(g)==before,"stale deal callback after cancellation cannot commit")
	scene._open_menu();scene._deal()
	ck(snap(g)==before,"stale deal callback from replaced betting menu cannot commit")
	scene._close_menu()
	scene._open_betting();select_mode(scene,"human")
	scene.seats_control.value=1
	scene.seat_bets[0].value=100;scene.seat_bets[0].get_line_edit().text="100"
	scene._deal();scene._deal()
	ck(g.dealer_mode=="human" and g.round_number==1 and g.players[0].balance==900,"confirm commits manual mode with single debit")
	before=snap(g);scene._act("hit")
	ck(snap(g)==before,"deal animation blocks repeated action")
	stable(scene);no_advice(scene)
	for i in 5:scene._process(1.0)
	ck(snap(g)==before,"challenger waits for manual action")
	scene._act("stand");stable(scene)
	ck(g.phase=="dealer","manual dealer receives turn")
	await process_frame;await process_frame;await process_frame
	var viewport_rect:Rect2=scene.get_viewport().get_visible_rect()
	ck(viewport_rect.size==Vector2(1180,800),"layout exercised at 1180 by 800")
	for node in [scene.footer_panel,scene.hit_button,scene.stand_button,scene.player_label,scene.probability_label]:
		var rect:Rect2=node.get_global_rect()
		ck(rect.position.y>=0 and rect.end.y<=viewport_rect.end.y and rect.position.x>=0 and rect.end.x<=viewport_rect.end.x,"manual footer/control within viewport: "+node.get_class())
	ck(scene.footer_panel.get_global_rect().encloses(scene.player_label.get_global_rect()),"help remains inside manual footer")
	ck(scene.footer_panel.get_global_rect().encloses(scene.probability_label.get_global_rect()),"all probability lines remain inside manual footer")
	ck(not scene.hit_button.disabled and not scene.stand_button.disabled and scene.double_button.disabled,"dealer hit/stand enabled, double forbidden")
	no_advice(scene)
	ck(scene.detail_label.text.contains("%") or text_tree(scene.hud).contains("%"),"probability percentages shown")
	before=snap(g)
	for i in 8:scene._process(2.0)
	ck(snap(g)==before,"manual dealer never autosteps after time")
	scene._act("double_down");scene._act("dealer_step")
	ck(snap(g)==before,"double and AI command cannot alter manual dealer")
	for method in ["toggle_view","toggle_top_down","toggle_hand_stowed","reset_view"]:
		scene.call(method);ck(snap(g)==before,"view change leaves dealer decision pending")
	scene._open_menu();scene._act("hit");scene._process(5.0)
	ck(snap(g)==before,"menu interruption freezes manual dealer")
	scene._close_menu();no_advice(scene)
	scene._leave();await process_frame;await process_frame
	ck(current_scene.scene_file_path=="res://scenes/card_lobby.tscn","lobby navigation succeeds")
	ck(snap(g)==before,"leaving preserves pending manual dealer")
	ck(change_scene_to_file("res://scenes/blackjack_game.tscn")==OK,"reentry accepted")
	await process_frame;await process_frame
	scene=current_scene;scene.set_process(false);stable(scene)
	ck(scene.game==g and snap(g)==before and g.dealer_mode=="human","reentry restores exact manual mode and hand")
	no_advice(scene)
	scene._act("hit");scene._act("hit")
	ck(g.dealer_hand.size()==3 and g.phase=="dealer","repeated hit during animation adds only one card")
	stable(scene);no_advice(scene)
	ck(g.next_card_probabilities().remaining==307,"distribution updates after manual dealer hit")
	scene._act("stand");scene._act("stand");stable(scene)
	ck(g.phase=="settled" and g.players[0].balance==900,"manual stand settles once")
	ck(scene.status_label.text.contains("庄家实际净收益 +100"),"manual settlement shows actual dealer net rather than EV")
	before=snap(g)
	for i in 5:scene._process(1.0)
	ck(snap(g)==before,"settlement is stable after frames")
	no_advice(scene)
	scene._act("next_round");stable(scene);scene._open_betting()
	ck(g.dealer_mode=="human","new round retains previous mode")
	select_mode(scene,"ai")
	for control in scene.seat_bets:control.value=0;control.get_line_edit().text="0"
	before=snap(g);scene._deal()
	ck(snap(g)==before and g.dealer_mode=="human","invalid empty bets do not commit alternate mode")
	scene._close_menu()
	print("INDEPENDENT MANUAL DEALER UI REVIEW: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
