extends SceneTree
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print(('PASS ' if value else 'FAIL ') + label)
func _initialize() -> void: call_deferred('run')
func card(id: int) -> Dictionary:
	return {'id':id,'title':'Card %s'%id,'rank':'A','suit':'hearts','face':load('res://assets/card_0.svg')}
func run() -> void:
	var table = load('res://scripts/ring_card_table.gd').new()
	root.add_child(table)
	await process_frame
	table.set_process(false)
	var ids := ['A','B','C','D','E','F','G','H']
	var hands: Array = []
	for i in 8: hands.append([card(i*2),card(i*2+1)])
	hands[0][1].private_hidden = true
	hands[1][1].hidden = true
	var center := [card(16),card(17)]
	center[1].hidden = true
	var deck := [card(18),card(19)]
	check(table.present_ring(ids,hands,center,deck,Callable(),false),'snapshot accepted')
	check(table._card_nodes.size()==20,'stable node per card')
	check(table.played[0].visible and table.played[1].visible,'every center card visible')
	check(table.card_node(0).get_parent()==table and table.card_node(2).get_parent()==table,'human and opponents on same tabletop')
	check(not table.card_node(1).face_up and not table.card_node(3).face_up and not table.card_node(17).face_up,'private and secret cards face down')
	check(not table.card_node(17).data.has('rank') and not table.card_node(17).data.has('suit') and not table.card_node(17).data.has('title') and table.card_node(17).face_texture==null,'hidden center sanitized')
	check(not table.inspection_snapshot(table.card_node(1)).has('title'),'private hidden inspection safe')
	check(table.inspection_snapshot(table.card_node(2)).has('title'),'open opponent inspection supported')
	var original = table.card_node(1)
	hands[0][1].peek = true
	check(table.present_ring(ids,hands,center,deck,Callable(),true),'private peek snapshot accepted')
	check(table.card_node(1)==original and original.face_up,'private peek flips same entity')
	check(not table.inspection_snapshot(table.card_node(17)).has('title'),'dealer hidden inspection safe')
	var before: Transform3D = original.global_transform
	table.set_hand_stowed(true)
	check(original.global_transform.is_equal_approx(before),'Tab never stows tabletop cards')
	table.set_hand_stowed(false)
	var dealt = table.card_node(19)
	hands[4].append(deck.pop_back())
	check(table.present_ring(ids,hands,center,deck,Callable(),true),'deal accepted')
	check(table.card_node(19)==dealt and table.flights.has(dealt),'deal uses original deck node')
	table.advance_flights(1.0)
	check(dealt.get_parent()==table and not table.flights.has(dealt),'flight settles on felt')
	var bad := hands.duplicate(true)
	bad[2].append(card(0))
	check(not table.present_ring(ids,bad,center,deck,Callable(),false) and table._card_nodes.size()==20,'duplicate rejection atomic')
	for view in 3:
		if view==1: table.set_view(true)
		if view==2: table.set_top_down(true)
		check(not table.card_node(2).viewer_masked and not table.card_node(17).face_up,'views preserve mixed public/private cards')
	table.set_seat_label(7,'机器人7 · 1000')
	check(table.seats[7].label.text=='机器人7 · 1000','seat label API')
	check(not table._model_discard[1].has('rank') and not table.deck[0].has('rank'),'retained secret snapshots sanitized too')
	var safe_provider := func(record: Dictionary) -> Dictionary:
		check(not record.get('hidden',false) or not record.has('rank'),'provider receives sanitized secrets')
		return {}
	table.present_ring(ids,hands,center,deck,safe_provider,false)
	var reveal_node = table.card_node(17)
	center[1].hidden = false
	table.present_ring(ids,hands,center,deck,Callable(),true)
	check(table.card_node(17)==reveal_node and reveal_node.face_up and reveal_node.data.has('rank'),'reveal reuses same node with now-public data')
	var shoe: Array = []
	for i in range(100,412): shoe.append({'id':i,'rank':'K','suit':'clubs'})
	table.present_ring(ids,hands,center,shoe,Callable(),false)
	check(table.deck.size()==312 and table.deck_visual.size()==12,'312-card shoe only renders12 actual card nodes')
	check(table.card_node(100).area.collision_layer==0 and not table.card_node(100).visible,'deep shoe cards not rendered or pickable')
	for index in 8: table.set_seat_label(index,'%d号 AI · 21点\n余额 1000 · 注 100 · 已停牌'%[index+1])
	for dimensions in [Vector2i(1440,960),Vector2i(1178,720),Vector2i(1024,768)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		await process_frame
		table.set_top_down(true)
		for seat in table.seats:
			var label_point: Vector2 = table.camera.unproject_position(seat.label.global_position)
			check(label_point.y>110 and label_point.y<dimensions.y-170,'top seat label safe at '+str(dimensions))
		table.reset_view()
		var own_card: Card3D = table.card_node(0)
		for x in [-0.825,0.825]:
			for z in [-1.16,1.16]:
				var point: Vector2 = table.camera.unproject_position(own_card.to_global(Vector3(x,0,z)))
				check(point.y>100 and point.y<dimensions.y-160,'first person own card fully above footer '+str(dimensions))
		check(not table.seats[1].label.visible and not table.seats[7].label.visible,'near labels hidden in first person')
		var dealer_point: Vector2 = table.camera.unproject_position(table.card_node(16).global_position)
		check(dealer_point.y>100 and dealer_point.y<dimensions.y-160,'dealer remains in first-person safe view')
		var seat_five_card_pose: Transform3D = table.seats[4].hand[0].global_transform
		table.set_view(true)
		check(table.seats[4].hand[0].global_transform.is_equal_approx(seat_five_card_pose),'observer label correction never moves cards')
		for seat in table.seats:
			var label: Label3D = seat.label
			var text_size: Vector2 = label.font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, label.font_size)
			text_size = (text_size + Vector2.ONE * label.outline_size * 2) * label.pixel_size
			var safe := true
			for x in [-text_size.x/2,text_size.x/2]:
				for y in [-text_size.y/2,text_size.y/2]:
					var world: Vector3 = label.global_position + table.camera.global_basis.x*x + table.camera.global_basis.y*y
					var point: Vector2 = table.camera.unproject_position(world)
					safe = safe and point.x>0 and point.x<dimensions.x and point.y>100 and point.y<dimensions.y-160
			check(safe,'observer full label '+str(seat.seat_id)+' fits safe viewport '+str(dimensions))
	table.free()
	print('Ring presenter: %s checks, %s failures'%[checks,failures])
	quit(1 if failures else 0)
