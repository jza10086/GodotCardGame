extends SceneTree
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+label)
	else: print("PASS: "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var demo = load("res://scenes/table_demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set_process(false)
	check(demo.player_rig.position.y==8.0 and is_equal_approx(demo.player_pitch,deg_to_rad(-38)),"higher player eye and downlook defaults")
	var card: Card3D = demo.hand[0]
	var other: Card3D = demo.seats[1].hand[0]
	check(other.viewer_masked and other._face_material.albedo_texture==other.back_texture,"non-owner real front surface rendered as back")
	check(not other.public_snapshot().has("title"),"masked public snapshot has no title")
	check(not demo.inspection_snapshot(other).has("title"),"inspection cannot expose opponent identity")
	check(not demo.move_card(other,&"hand"),"ray observation does not authorize stealing")
	check(demo.TABLE_APOTHEM==12.0 and demo.SEAT_RADIUS==11.0,"smaller physical table and closer equally spaced seats")
	for dimensions in [Vector2i(1440,960),Vector2i(1280,720),Vector2i(1024,768)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await process_frame
		demo.resize_hand()
		await process_frame
		var bounds: Rect2 = root.get_visible_rect()
		var previous := Rect2()
		for control in demo.action_bar.get_child(0).get_children():
			var button_bounds: Rect2 = control.get_global_rect()
			check(root.get_visible_rect().encloses(button_bounds),"toolbar control fits "+str(dimensions))
			check(not previous.intersects(button_bounds),"toolbar controls never overlap")
			previous = button_bounds
		var deck_top: Card3D = demo.deck_visual.back()
		for x in [-deck_top.card_size.x/2.0,deck_top.card_size.x/2.0]:
			for z in [-deck_top.card_size.y/2.0,deck_top.card_size.y/2.0]:
				var corner: Vector2 = demo.camera.unproject_position(deck_top.to_global(Vector3(x,0,z)))
				check(bounds.grow(-20).has_point(corner),"deck geometry fully visible "+str(dimensions))
		var deck_label: Vector2 = demo.camera.unproject_position(demo.deck_count_label.global_position)
		check(Rect2(90,160,bounds.size.x-180,bounds.size.y-180).has_point(deck_label),"deck count has readable side margins")

		var rest: Rect2 = demo.hand_card_rect(card)
		var visible: Rect2 = rest.intersection(bounds)
		check(visible.size.y/rest.size.y>0.40 and visible.size.y/rest.size.y<0.56,"roughly half resting hand clipped at "+str(dimensions))
		var pointer := visible.get_center()
		check(demo.pick(pointer)==card,"visible resting half is pickable at "+str(dimensions))
		var neighbor: Card3D = demo.hand[1]
		var neighbor_position := neighbor.global_position
		demo.hovered = card
		card.set_hovered(true)
		await create_timer(0.20).timeout
		var raised: Rect2 = demo.hand_card_rect(card,true)
		check(bounds.encloses(raised),"hovered card fully in viewport at "+str(dimensions))
		check(card.visual.scale.x>1.15 and card.visual.position.z < -1.5,"hover animates upward and enlarges")
		check(neighbor.global_position.is_equal_approx(neighbor_position) and not neighbor.hovered,"neighbors remain at resting layout")
		check(demo.pick(pointer)==card and demo.pick(raised.get_center())==card,"rest and raised hit footprints both stable")
		check(demo.action_bar.get_global_rect().end.y<raised.position.y,"buttons clear of raised card")
		check(demo.screen_drop_zone(demo.hand_rect().get_center())==&"hand","visible hand accepts returns")
		demo.select(card)
		demo.clear_hover()
		await create_timer(0.20).timeout
		check(card.visual.position.is_zero_approx() and card.selected,"hover exit returns card while selection remains")
		demo.select(null)
	root.size = Vector2i(1440,960)
	root.content_scale_size = Vector2i(1440,960)
	await process_frame
	demo.resize_hand()
	while demo.hand.size()<8: demo.draw_card(false)
	demo.resize_hand()
	for dimensions in [Vector2i(1440,960),Vector2i(1280,720),Vector2i(1024,768)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await process_frame
		demo.resize_hand()
		for candidate in demo.hand:
			check(root.get_visible_rect().encloses(demo.hand_card_rect(candidate,true)),"every full-hand hover fits "+str(dimensions))
	root.size = Vector2i(1440,960)
	root.content_scale_size = Vector2i(1440,960)
	await process_frame
	demo.reset()
	card = demo.hand[0]
	other = demo.seats[1].hand[0]
	demo.resize_hand()
	var original_id := card.get_instance_id()
	card.begin_drag()
	demo.dragged = card
	demo.pressed = card
	demo.set_hand_stowed(true)
	check(demo.dragged==null and not card.dragging,"stow safely cancels drag")
	check(demo.hand_stowed and demo.free_look and (DisplayServer.get_name()=="headless" or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED),"stow captures free look")
	check(card.get_instance_id()==original_id and card.get_parent()==demo.hand_world,"stow preserves original world node")
	check(demo.hand_world.scale.x<=0.3001 and demo.hand_world.position.x>0,"stow physically shrinks hand at right")
	var position: Vector3 = demo.player_rig.position
	var yaw: float = demo.player_yaw
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(50,-20)
	demo._input(motion)
	check(demo.player_yaw != yaw and demo.player_rig.position==position,"unheld mouse motion rotates without translating")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	demo._input(escape)
	check(not demo.free_look and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and demo.hand_stowed,"Escape releases cursor while retaining stow")
	yaw = demo.player_yaw
	demo._input(motion)
	check(demo.player_yaw==yaw,"released cursor cannot rotate player")
	demo.close_debug_menu()
	demo.set_hand_stowed(false)
	check(not demo.hand_stowed and demo.hand_world.scale.x>0.7,"expanded hand restores size and pointer")
	demo.set_hand_stowed(true)
	demo._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not demo.free_look and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"focus loss releases captured cursor")
	demo._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	demo.set_hand_stowed(true)
	demo.set_top_down(true)
	check(demo.top_down and demo.camera==demo.top_camera and not demo.third_person and not demo.free_look,"topdown is independent camera and releases capture")
	var viewport_size: Vector2 = root.get_visible_rect().size
	for corner in [Vector3(-8.2,0,-4.2),Vector3(8.2,0,-4.2),Vector3(-8.2,0,4.2),Vector3(8.2,0,4.2)]:
		var screen: Vector2 = demo.camera.unproject_position(corner)
		check(Rect2(20,160,viewport_size.x-40,viewport_size.y-240).has_point(screen),"topdown central play bounds visible")
	check(demo.top_camera.size<25.0,"topdown focuses center instead of full octagon")
	var clipped := false
	for vertex in demo.octagon_vertices(demo.TABLE_APOTHEM,0):
		if not root.get_visible_rect().has_point(demo.camera.unproject_position(vertex)): clipped = true
	check(clipped,"topdown intentionally allows outer table beyond viewport")
	check(other._face_material.albedo_texture==other.back_texture,"topdown cannot reveal opponent front")
	demo.set_view(true)
	check(not demo.top_down and demo.third_person,"V observer remains separate")
	demo.reset_view()
	check(not demo.hand_stowed and not demo.top_down and not demo.free_look,"reset restores expanded first-person safely")
	demo.set_hand_stowed(true)
	demo.set_active_seat(1)
	check(not demo.hand_stowed and not demo.free_look and not other.viewer_masked and card.viewer_masked,"seat change clears capture and updates viewer masks")
	demo.set_active_seat(0)
	demo.select(null)
	demo.hovered = null
	demo.hand_idle = 2.0
	demo.update_hand_pose(0.1)
	check(demo.auto_collapsed and not demo.hand_stowed,"idle slight collapse is independent of manual stow")
	demo.select(card)
	demo.update_hand_pose(1.0)
	check(not demo.auto_collapsed,"selected hand stays expanded")
	demo.set_hand_stowed(true)
	demo.update_hand_pose(1.0)
	check(demo.hand_stowed and not demo.auto_collapsed,"explicit stow wins over selection")
	var drawn: Card3D = demo.draw_card()
	demo.set_top_down(true)
	check(demo.flights.is_empty() and drawn in demo.hand and demo.total_cards()==64,"view transition settles reserved draw without loss")
	demo.reset_view()
	var group: Array[Card3D] = [card,demo.hand[1],demo.hand[3]]
	check(demo.play_cards(group),"group accepted")
	demo.settle_flights()
	demo.layout_cards(false)
	demo.set_top_down(true)
	check(demo.inspection_group(card).size()==3,"hover resolves whole play group")
	check(demo.inspection_snapshot(card).has("title"),"visible table face inspectable")
	check(not demo.inspection_snapshot(group[1]).has("title") and not demo.inspection_snapshot(group[2]).has("title"),"hidden and unknown group members stay unknown")
	demo.hovered = card
	demo.update_inspector(0.6)
	check(demo.inspect_panel.visible and demo.inspect_grid.get_child_count()==3,"hover displays group after dwell")
	check(demo.inspect_panel.mouse_filter==Control.MOUSE_FILTER_IGNORE,"inspector outer panel has no blanket input interception")
	check(demo.inspect_grid.get_child(0).custom_minimum_size==Vector2(150,211),"inspection cards use enlarged legible size")
	check(demo.inspect_grid.columns==3 and demo.inspect_scroll.custom_minimum_size.x<=500,"group inspection width is bounded")
	check(demo.inspect_scroll.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_AUTO,"large groups support bounded vertical scroll")
	card.set_face_up(false,false)
	demo.update_inspector(0.1)
	check(not demo.inspection_snapshot(card).has("title") and demo.inspect_grid.get_child(0).texture==demo._preview_textures[card.back_texture.resource_path],"flipped card immediately removes inspection face")
	demo.set_hand_stowed(true)
	check(not demo.inspect_panel.visible,"mode transition hides inspection")
	demo.reset()
	check(not demo.hand_stowed and not demo.free_look and demo.total_cards()==64,"reset population and stow lifecycle")
	print("VIEW TEST RESULT: %d checks, %d failures" %[checks,failures])
	demo.free()
	quit(1 if failures else 0)
