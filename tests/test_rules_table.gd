extends SceneTree
var failures := 0
var checks := 0
var requests: Array = []
var draws := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	print(('PASS: ' if ok else 'FAIL: ') + label)
	if not ok: failures += 1
func _initialize() -> void: call_deferred('run')
func model(id: int) -> Dictionary:
	return {'id':id,'title':'Test %d'%id,'face':load('res://assets/card_0.svg'),'back':load('res://assets/back.svg')}
func run() -> void:
	var table = load('res://scripts/rules_table.gd').new()
	root.add_child(table)
	await process_frame
	table.set_process(false)
	var own: Array = []
	for i in 30: own.append(model(i))
	var hands: Array = [own,[model(30),model(31)],[model(32)],[model(33)]]
	var deck: Array = []
	for i in range(34,60): deck.append(model(i))
	var discard: Array = [model(60),model(61)]
	check(table.apply_state(['A','B','C','D'],hands,deck,discard,Callable(),false),'apply complete state')
	check(table.hand.size()==30,'unlimited hand above template 8 limit')
	check(table.total_cards()==62,'all counts conserved')
	check(table._card_nodes.size()==62,'one persistent node for every identity')
	check(table.deck_visual.size()==12,'pile uses 12 actual nodes')
	check(table.played.size()==2 and not table.played[0].visible and table.played[1].visible,'only top discard rendered')
	check(table.played[0].area.collision_layer==0,'hidden discard not pickable')
	check(not table.ui.visible and table.presentation_overlay.visible,'original UI hidden, safe overlay visible')
	check(table.round_mapping()=={'A':1,'B':3,'C':5,'D':7},'existing deterministic seat allocator reused')
	var other: Card3D = table.player_hand(1)[0]
	for view in range(3):
		if view==1: table.set_view(true)
		if view==2: table.set_top_down(true)
		check(other.viewer_masked and not other.public_snapshot().has('title'),'opponent privacy camera %d'%view)
	check(not table.set_active_seat(2) and table.active_seat==0,'human identity cannot change')
	table.reset_view()
	var original: Card3D = table.card_node(0)
	var instance_id := original.get_instance_id()
	var initial := original.global_transform
	discard.append(hands[0].pop_front())
	check(table.apply_state(['A','B','C','D'],hands,deck,discard,Callable(),true),'play updated state')
	check(table.card_node(0).get_instance_id()==instance_id,'same node transfers hand to discard')
	check(table.flights.has(original) and original.global_transform.is_equal_approx(initial),'flight begins from original hand pose')
	table.advance_flights(0.35)
	check(not original.global_transform.is_equal_approx(initial),'play flight progresses')
	table.advance_flights(1.0)
	check(original.position.is_equal_approx(Vector3(0,0.16,0)) and original.get_parent()==table,'flight lands in centered discard')
	check(table.played.filter(func(c):return c.visible).size()==1,'single discard top after flight')
	var draw_id: int = deck.back().id
	var drawn: Card3D = table.card_node(draw_id)
	var drawn_id := drawn.get_instance_id()
	hands[0].append(deck.pop_back())
	table.apply_state(['A','B','C','D'],hands,deck,discard,Callable(),true)
	check(table.card_node(draw_id).get_instance_id()==drawn_id and table.flights.has(drawn),'draw flies actual persistent deck node')
	table.advance_flights(1.0)
	check(drawn.get_parent()==table.hand_world and not drawn.viewer_masked,'draw reparents into own floating hand')
	check(table.total_cards()==62,'draw and play conserve count')
	table.card_requested.connect(func(id): requests.append(id))
	table.draw_requested.connect(func(): draws += 1)
	table._request_card(table.hand[0])
	table._request_card(other)
	table._request_card(table.deck_visual.back())
	check(requests.size()==1 and draws==1,'own card and deck signals only')
	check(table.total_cards()==62,'request signals never mutate model')
	table.set_interaction_blocked(true)
	table._request_card(table.hand[0])
	table._request_card(table.deck_visual.back())
	var evt := InputEventKey.new()
	evt.keycode=KEY_D
	evt.pressed=true
	table._unhandled_input(evt)
	check(requests.size()==1 and draws==1,'rules action gate blocks every request')
	check(not table.menu_open, 'rules action gate does not open a modal')
	var view_key := InputEventKey.new()
	view_key.keycode = KEY_V
	view_key.pressed = true
	table._unhandled_input(view_key)
	check(table.third_person, 'camera navigation remains available while requests are blocked')
	table.set_interaction_blocked(false)
	table.menu_open = true
	table._request_card(table.hand[0])
	table._unhandled_input(evt)
	check(requests.size()==1 and draws==1, 'modal gate independently blocks requests')
	table.menu_open = false
	var bad: Array = hands.duplicate(true)
	bad[0].append(bad[0][0])
	check(not table.apply_state(['A','B','C','D'],bad,deck,discard,Callable(),false) and table.total_cards()==62,'invalid duplicate snapshot is atomic')
	check(not table.move_card(other,&'hand') and not table.transfer_to_seat(other,0),'demo mutations unavailable')
	# Seven cards keep the reusable template's clipped resting/raised hover hand.
	var short_hand: Array = []
	for i in 7: short_hand.append(model(i))
	table.apply_state(['A','B'], [short_hand,[model(7)]], [model(8)], [model(9)], Callable(), false)
	table.reset_view()
	for dimensions in [Vector2i(1440,960),Vector2i(1280,720),Vector2i(1024,768)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		await process_frame
		table.resize_hand()
		await process_frame
		var first: Card3D = table.hand[0]
		var rect: Rect2 = table.hand_card_rect(first)
		var visible: Rect2 = rect.intersection(root.get_visible_rect())
		check(visible.size.y/rect.size.y>0.40 and visible.size.y/rect.size.y<0.56, 'resting hand half-clipped at '+str(dimensions))
		check(table.pick(visible.get_center())==first, 'resting own card pickable at '+str(dimensions))
		table.hovered=first
		first.set_hovered(true)
		await create_timer(0.20).timeout
		check(root.get_visible_rect().encloses(table.hand_card_rect(first,true)), 'hovered own card fully visible at '+str(dimensions))
		check(table.pick(visible.get_center())==first, 'raised hover retains stable rest target at '+str(dimensions))
		table.clear_hover()
		await create_timer(0.20).timeout
	table.queue_free()
	await process_frame
	print('CHECKS: ',checks, ' FAILURES: ',failures)
	quit(1 if failures else 0)
