extends SceneTree
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+label)
	else: print("PASS: "+label)
func pointer_drag(demo, card: Card3D, destination: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = demo.card_screen(card)
	demo._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(25,0)
	demo._input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = destination
	demo._input(release)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var demo = load("res://scenes/table_demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	check(demo.hand.size()==5 and demo.deck.size()==38 and demo.total_cards()==64,"initial 64-card population")
	check(demo.hand[0].get_parent()==demo.hand_world,"hand attached to world-space floating anchor")
	check(demo.camera.projection==Camera3D.PROJECTION_PERSPECTIVE,"first person uses perspective projection")
	check(demo.hand_world.get_world_3d()==demo.get_world_3d(),"hand and table share rendering and physics world")
	check(demo.hand_world.global_position.y>2.0,"hand genuinely floats above tabletop")
	check(demo.hand_world.get_parent()==demo.player_rig,"hand follows player rig rather than screen layer")
	var initial_hand_transform: Transform3D = demo.hand_world.transform
	var initial_player_pos: Vector3 = demo.player_rig.position
	var before_rotation: Vector3 = demo.hand[2].global_position
	demo.apply_player_look(Vector2(100,-80))
	check(not demo.hand[2].global_position.is_equal_approx(before_rotation),"hand follows camera rotation in world")
	check(demo.player_rig.position==initial_player_pos,"rotation does not translate player")
	check(demo.hand_world.transform==initial_hand_transform,"camera-relative hand pose remains fixed")
	demo.apply_player_look(Vector2(0,-100000))
	check(is_equal_approx(demo.player_pitch,deg_to_rad(demo.PITCH_MAX)),"upper pitch clamped")
	demo.apply_player_look(Vector2(0,100000))
	check(is_equal_approx(demo.player_pitch,deg_to_rad(demo.PITCH_MIN)),"lower pitch clamped")
	demo.reset_view()
	var original_card: Card3D = demo.hand[2]
	var face_normal: Vector3 = original_card.global_basis.y.normalized()
	check(face_normal.dot(demo.camera.global_position-original_card.global_position)>0,"first person observes real front surface")
	var hand_before_switch: Transform3D = demo.hand_world.global_transform
	demo.set_view(true)
	check(demo.camera==demo.observer_camera and demo.third_person,"third person selects observer camera")
	check(demo.hand_world.global_transform==hand_before_switch and demo.hand[2]==original_card,"switch preserves same card geometry and world transform")
	check(face_normal.dot(demo.camera.global_position-original_card.global_position)<0 and original_card.face_up,"third person sees back without flipping card")
	demo.apply_observer_look(Vector2(40,20))
	check(demo.hand_world.global_transform==hand_before_switch,"observer orbit never rotates player hand")
	demo.reset_view()
	check(demo.camera==demo.first_camera and is_zero_approx(demo.player_yaw),"view reset restores first person pose")
	original_card.begin_drag()
	demo.dragged=original_card
	demo.pressed=original_card
	demo.set_view(true)
	check(demo.dragged==null and demo.pressed==null and not original_card.dragging,"camera switch safely cancels drag")
	check(original_card.get_parent()==demo.hand_world,"camera cancellation restores anchor")
	demo.reset_view()
	var right_press := InputEventMouseButton.new()
	right_press.button_index=MOUSE_BUTTON_RIGHT
	right_press.pressed=true
	demo._input(right_press)
	var look_motion := InputEventMouseMotion.new()
	look_motion.relative=Vector2(20,10)
	demo._input(look_motion)
	check(demo.looking and not is_zero_approx(demo.player_yaw),"RMB input and relative motion rotate player")
	right_press.pressed=false
	demo._input(right_press)
	check(not demo.looking,"RMB release stops look mode")
	demo.reset_view()
	var arrow := InputEventKey.new()
	arrow.keycode=KEY_RIGHT
	arrow.pressed=true
	demo._input(arrow)
	check(demo.player_yaw<0,"discrete arrow key rotates player without a hold")
	demo.reset_view()
	var card: Card3D = demo.hand[0]
	check(card.visual.get_child_count()==3,"3D face/back/edge geometry")
	check(card.outline().size()==36,"rounded card silhouette")
	for point in card.outline():
		check(absf(point.x)<=card.card_size.x/2.0+0.0001 and absf(point.y)<=card.card_size.y/2.0+0.0001,"outline bounded")
	card.set_face_up(false,false)
	check(not card.face_up and is_equal_approx(card.visual.rotation.z,PI),"flip transforms to back")
	card.set_face_up(true,false)
	check(card.face_up and is_zero_approx(card.visual.rotation.z),"flip restores face")
	card.set_selected(true)
	card.set_hovered(true)
	card.set_hovered(false)
	check(card.marker.visible and card.selected,"selection survives hover exit")
	card.set_selected(false)
	check(not card.marker.visible,"highlight clears")
	var events := {"start":0,"finish":0,"accepted":false}
	card.drag_started.connect(func(_c): events.start+=1)
	card.drag_finished.connect(func(_c, accepted): events.finish+=1; events.accepted=accepted)
	card.begin_drag()
	card.begin_drag()
	check(events.start==1 and card.dragging,"drag begins exactly once")
	demo.dragged = card
	check(demo.finish_drag(demo.camera.unproject_position(Vector3(0,0,-1))),"valid play drop")
	check(events.finish==1 and events.accepted and card.zone==&"play" and not card.dragging,"valid drop lifecycle and zone")
	card.begin_drag()
	demo.dragged = card
	check(not demo.finish_drag(demo.camera.unproject_position(Vector3(12,0,-1))),"invalid drop rejected")
	check(card.zone==&"play" and not card.dragging and events.finish==2 and not events.accepted,"invalid drop preserves zone and finishes")
	card.begin_drag()
	demo.dragged = card
	check(demo.finish_drag(demo.hand_rect().get_center()),"return via hand drop")
	check(card.zone==&"hand" and demo.played.is_empty(),"return membership")
	check(card.get_parent()==demo.hand_world,"returned instance restored to hand world")
	check(demo.screen_drop_zone(Vector2(100,950))==&"invalid","footer rejects drops instead of table behind HUD")
	check(demo.drop_zone(Vector3(-8.2,0,-4.2))==&"play","play boundary included")
	check(demo.drop_zone(Vector3(-8.21,0,-4.2))==&"invalid","outside boundary rejected")
	check(demo.drop_zone(Vector3(0,0,4.21))==&"invalid","outside shared table depth is invalid")
	# Input-driven press/move/release, including release over HUD.
	await create_timer(0.45).timeout
	await physics_frame
	await physics_frame
	var screen: Vector2 = demo.card_screen(card)
	var press := InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true
	press.position=screen
	demo._unhandled_input(press)
	check(demo.pressed==card,"ray-picked press")
	var motion := InputEventMouseMotion.new()
	motion.position=screen+Vector2(25,0)
	demo._input(motion)
	check(demo.dragged==card and card.dragging,"pointer threshold starts drag")
	check(card.get_parent()==demo,"drag uses original card in same world")
	var release := InputEventMouseButton.new()
	release.button_index=MOUSE_BUTTON_LEFT
	release.pressed=false
	release.position=Vector2(10,940)
	demo._input(release)
	check(demo.dragged==null and demo.pressed==null and not card.dragging,"release over HUD cannot stick")
	await create_timer(0.95).timeout
	await physics_frame
	pointer_drag(demo, card, demo.camera.unproject_position(Vector3(0,0,-1)))
	check(card.zone==&"play" and card.get_parent()==demo,"pointer hand-to-table restores table parent")
	await create_timer(0.95).timeout
	await physics_frame
	pointer_drag(demo, card, demo.hand_rect().get_center())
	check(card.zone==&"hand" and card.get_parent()==demo.hand_world,"pointer table-to-hand restores floating anchor")
	await create_timer(0.95).timeout
	await physics_frame
	card.set_hovered(true)
	card.set_face_up(false, false)
	pointer_drag(demo, card, demo.camera.unproject_position(Vector3(0,0,-1)))
	check(not card.face_up and card.zone==&"play" and not card.hovered,"cross-zone drag preserves flipped face and clears hover")
	# Reset during active interaction must free cards and all transient state.
	card.begin_drag()
	demo.dragged=card
	demo.pressed=card
	demo.reset()
	check(demo.dragged==null and demo.pressed==null and demo.selected==null,"reset clears interaction")
	check(demo.hand.size()==5 and demo.played.is_empty() and demo.deck.size()==38,"reset restores counts")
	while demo.hand.size()<8: demo.draw_card(false)
	check(demo.draw_card(false)==null and demo.deck.size()==35,"full hand blocks draw")
	for i in 4: demo.move_card(demo.hand[0],&"play")
	for i in 4: demo.draw_card(false)
	check(not demo.move_card(demo.played[0],&"hand"),"full hand blocks return")
	for seat_index in range(1,8):
		demo.set_active_seat(seat_index)
		while demo.hand.size()<demo.HAND_LIMIT and not demo.deck.is_empty(): demo.draw_card(false)
	check(demo.deck.is_empty() and demo.draw_card(false)==null,"deck empties cleanly across eight hands")
	check(demo.total_cards()==64,"card population conserved across all seats")
	for seat_index in 8:
		demo.set_active_seat(seat_index)
		while not demo.hand.is_empty() and demo.played.size()<demo.PLAY_LIMIT:
			demo.move_card(demo.hand[0],&"play")
	check(demo.played.size()==16,"shared table accepts sixteen cards")
	demo.set_active_seat(7)
	check(not demo.move_card(demo.hand[0],&"play"),"full shared table rejects seventeenth card")
	demo.set_active_seat(0)
	# Resizing keeps viewport and screen-space drop/picking coordinates consistent.
	demo.reset()
	root.size = Vector2i(1200,800)
	await process_frame
	demo.resize_hand()
	await physics_frame
	await physics_frame
	check(demo.hand_world.get_parent()==demo.player_rig,"resize retains player-space hand anchor")
	check(demo.pick(demo.card_screen(demo.hand[2]))==demo.hand[2],"resized hand ray picking")
	check(demo.screen_drop_zone(demo.hand_rect().get_center())==&"hand","resized hand drop mapping")
	check(demo.screen_drop_zone(demo.camera.unproject_position(Vector3(0,0,-1)))==&"play","resized table drop mapping")
	var return_card: Card3D = demo.hand[0]
	demo.move_card(return_card,&"play")
	demo.select(return_card)
	demo.return_selected()
	check(return_card.zone==&"hand" and return_card.get_parent()==demo.hand_world,"return button restores same instance")
	check(demo.total_cards()==64,"world-space transitions conserve data")
	root.size = Vector2i(1440,960)
	await process_frame
	await create_timer(0.95).timeout
	await physics_frame
	var cancel_card: Card3D = demo.hand[1]
	demo.pressed = cancel_card
	demo.press_position = demo.card_screen(cancel_card)
	var cancel_motion := InputEventMouseMotion.new()
	cancel_motion.position = demo.press_position + Vector2(25,0)
	demo._input(cancel_motion)
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	demo._unhandled_input(escape)
	check(demo.dragged==null and demo.pressed==null and demo.selected==null and not cancel_card.dragging,"Escape cancels world-space drag and selection")
	check(cancel_card.get_parent()==demo.hand_world and cancel_card.zone==&"hand","Escape restores original zone and parent")
	# Third-person interaction uses the same world and camera rays.
	demo.close_debug_menu()
	demo.reset()
	demo.set_view(true)
	await physics_frame
	await physics_frame
	var observer_card: Card3D = demo.hand[2]
	check(demo.pick(demo.card_screen(observer_card))==observer_card,"third person picks real hand backs")
	pointer_drag(demo,observer_card,demo.camera.unproject_position(Vector3(0,0,-1)))
	check(observer_card.zone==&"play","third person supports hand-to-table drag")
	await create_timer(0.95).timeout
	await physics_frame
	pointer_drag(demo,observer_card,demo.hand_rect().get_center())
	check(observer_card.zone==&"hand","third person supports table-to-hand drag")
	demo.reset_view()
	# Eight independent owners and inward-facing floating hands.
	demo.reset()
	check(demo.seats.size()==8 and demo.seat_buttons.size()==8,"eight seats and local switching controls")
	var rim: MeshInstance3D = demo.get_node("OctagonalTableRim")
	var felt: MeshInstance3D = demo.get_node("OctagonalTableFelt")
	check(rim.mesh is ArrayMesh and felt.mesh is ArrayMesh,"table uses real octagonal prism geometry")
	check(rim.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==96,"eight top bottom and side segments form closed slab")
	check(demo.get_node("OctagonalInlay").get_child_count()==8,"inlay follows all eight physical edges")
	var octagon: PackedVector3Array = demo.octagon_vertices(demo.TABLE_APOTHEM,0.0)
	for vertex in octagon:
		var projected: Vector2 = demo.observer_camera.unproject_position(vertex)
		check(not demo.observer_camera.is_position_behind(vertex) and Rect2(20,160,1400,660).has_point(projected),"observer frames octagon vertex clear of HUD")
	for i in 8:
		var outward := Vector3(sin(TAU*i/8.0),0,cos(TAU*i/8.0))
		var areas_inside := true
		for point in [Vector3(-8.25,0,-4.25),Vector3(8.25,0,-4.25),Vector3(-8.25,0,4.25),Vector3(8.25,0,4.25),demo.DECK_ORIGIN+Vector3(-0.95,0,-1.35),demo.DECK_ORIGIN+Vector3(-0.95,0,1.35)]:
			areas_inside = areas_inside and outward.dot(point)<demo.TABLE_APOTHEM-0.68
		check(areas_inside,"play area and deck clear octagon edge %d"%i)
	var nodes := {}
	var anchors := {}
	for seat_index in 8:
		var seat: Dictionary = demo.seats[seat_index]
		check(seat.id=="P%d"%(seat_index+1),"stable seat identity %d"%seat_index)
		check(seat.hand.size()==(5 if seat_index==0 else 3),"independent dealt hand %d"%seat_index)
		check(not anchors.has(seat.anchor.get_instance_id()),"unique hand anchor %d"%seat_index)
		anchors[seat.anchor.get_instance_id()]=true
		var radial: Vector3 = seat.rig.position
		check(is_equal_approx(Vector2(radial.x,radial.z).length(),demo.SEAT_RADIUS),"seat at equal octagon radius %d"%seat_index)
		var vertices: PackedVector3Array = demo.octagon_vertices(demo.TABLE_APOTHEM,0.0)
		var edge_center: Vector3 = (vertices[seat_index]+vertices[(seat_index+1)%8])/2.0
		var radial_flat := Vector3(radial.x,0,radial.z).normalized()
		check(edge_center.normalized().is_equal_approx(radial_flat),"seat centered on octagon edge %d"%seat_index)
		check(is_equal_approx(edge_center.length(),demo.TABLE_APOTHEM),"equal edge apothem %d"%seat_index)
		check(is_equal_approx(vertices[seat_index].distance_to(vertices[(seat_index+1)%8]),2.0*demo.TABLE_APOTHEM*tan(PI/8.0)),"equal octagon side length %d"%seat_index)
		var inward: Vector3 = -seat.rig.basis.z
		check(Vector3(inward.x,0,inward.z).normalized().is_equal_approx(-radial_flat),"seat faces center perpendicular to edge %d"%seat_index)
		check(is_equal_approx(demo.get_node("SeatMarker%d"%(seat_index+1)).rotation.y,seat.yaw),"marker follows its edge orientation %d"%seat_index)
		for owned in seat.hand:
			check(not nodes.has(owned.get_instance_id()) and owned.get_parent()==seat.anchor and owned.get_meta("seat_id")==seat.id,"exclusive node ownership %s"%seat.id)
			nodes[owned.get_instance_id()]=true
			var normal: Vector3 = owned.global_basis.y.normalized()
			check(normal.dot(seat.camera.global_position-owned.global_position)>0,"owner sees front %s"%seat.id)
			var opposite: Dictionary = demo.seats[(seat_index+4)%8]
			check(normal.dot(opposite.camera.global_position-owned.global_position)<0,"opposite seat sees physical back %s"%seat.id)
		check(demo.set_active_seat(seat_index) and demo.active_seat==seat_index and demo.first_camera==seat.camera and demo.hand_world==seat.anchor and demo.hand==seat.hand,"local seat selects camera and hand %d"%seat_index)
		demo.reset_view()
		check(is_equal_approx(demo.player_yaw,seat.yaw),"reset preserves inward seat heading %d"%seat_index)
	check(not demo.set_active_seat(-1) and not demo.set_active_seat(8) and demo.active_seat==7,"invalid seat switches preserve active seat")
	demo.set_active_seat(0)
	var private_card: Card3D = demo.hand[1]
	var other_card: Card3D = demo.seats[1].hand[0]
	check(not demo.can_control(other_card) and not demo.move_card(other_card,&"play"),"inactive hand cannot be moved directly")
	demo.select(other_card)
	check(demo.selected==null,"inactive hand cannot be selected")
	private_card.begin_drag()
	demo.dragged=private_card
	demo.pressed=private_card
	demo.place_in_world(private_card,demo)
	demo.select(private_card)
	private_card.set_hovered(true)
	demo.hovered=private_card
	demo.set_active_seat(1)
	check(demo.dragged==null and demo.pressed==null and demo.selected==null and demo.hovered==null and not private_card.dragging and not private_card.hovered,"seat switch cancels transient interaction")
	check(private_card.get_parent()==demo.seats[0].anchor and private_card in demo.seats[0].hand,"seat switch returns drag to original owner")
	var private_id := private_card.get_instance_id()
	var private_data := private_card.data.duplicate(true)
	private_card.set_face_up(false,false)
	check(demo.transfer_to_seat(private_card,1),"explicit cross-seat transfer succeeds")
	check(private_card.get_instance_id()==private_id and private_card.get_parent()==demo.seats[1].anchor and private_card in demo.hand and private_card not in demo.seats[0].hand,"transfer retains node and changes ownership")
	check(private_card.face_hidden and not private_card.face_up and private_card.data==private_data,"transfer preserves hidden state orientation and data")
	check(private_card.get_meta("seat_id")=="P2" and demo.total_cards()==64,"transfer updates owner metadata and conserves population")
	check(not demo.transfer_to_seat(null,0) and not demo.transfer_to_seat(private_card,8) and not demo.transfer_to_seat(demo.deck_visual[0],0),"invalid transfers rejected")
	check(demo.transfer_to_seat(private_card,1) and demo.hand.count(private_card)==1,"same-owner transfer is idempotent")
	while demo.hand.size()<demo.HAND_LIMIT: demo.draw_card(false)
	var source_card: Card3D = demo.seats[0].hand[0]
	check(not demo.transfer_to_seat(source_card,1) and source_card in demo.seats[0].hand and demo.total_cards()==64,"full destination rejects transfer without changing ownership")
	check(demo.move_card(private_card,&"play") and private_card in demo.played and private_card.get_meta("seat_id")=="","playing clears private ownership metadata")
	demo.set_active_seat(2)
	check(demo.move_card(private_card,&"hand") and private_card.get_meta("seat_id")=="P3" and private_card.get_parent()==demo.hand_world,"shared return assigns active owner")
	check(demo.move_card(private_card,&"play") and demo.transfer_to_seat(private_card,3) and private_card in demo.seats[3].hand and private_card not in demo.played,"shared card can transfer to explicit seat")
	check(private_card.face_hidden and not private_card.face_up and demo.total_cards()==64,"shared transfers preserve presentation and population")
	demo.set_active_seat(0)
	demo.reset()
	var hidden: Card3D = demo.hand[1]
	var unknown: Card3D = demo.hand[3]
	check(hidden.face_hidden and hidden.face_up and hidden.visual.get_child(0).material_override.albedo_texture==Card3D.UNKNOWN_FACE,"hidden face renders question mark while upright")
	check(unknown.face_texture==null and unknown.visual.get_child(0).material_override.albedo_texture==Card3D.UNKNOWN_FACE,"null-information face renders question mark")
	var secret_title: String = hidden.data.title
	var secret_id = hidden.data.id
	demo.select(hidden)
	check(not demo.status.text.contains(secret_title) and not hidden.public_snapshot().has("title") and not hidden.public_snapshot().has("id"),"hidden selection and snapshot do not expose identity")
	check(hidden.public_description()=="未知卡牌" and hidden.data.id==secret_id,"hidden public description preserves private data")
	var hidden_events := {"count":0}
	hidden.face_visibility_changed.connect(func(_c,_v): hidden_events.count+=1)
	hidden.set_face_hidden(true)
	check(hidden_events.count==0,"same hidden state does not emit duplicate change")
	demo.toggle_hidden()
	check(not hidden.face_hidden and hidden_events.count==1 and hidden.public_description()==secret_title and hidden.visual.get_child(0).material_override.albedo_texture==hidden.face_texture,"unhide restores original face and description")
	hidden.set_face_hidden(true)
	check(not demo.status.text.contains(secret_title) and demo.hide_button.text.contains("显示"),"direct hide API synchronously clears selected status identity")
	hidden.set_face_hidden(false)
	check(demo.status.text.contains(secret_title),"direct unhide API refreshes selected visible title")
	hidden.set_face_up(false,false)
	check(not demo.status.text.contains(secret_title) and hidden.public_description()=="牌背","direct physical flip synchronously clears selected status identity")
	hidden.set_face_up(true,false)
	demo.flip_selected()
	check(not hidden.face_up and hidden.public_description()=="牌背" and not hidden.public_snapshot().has("title") and not demo.status.text.contains(secret_title),"physical flip redacts public title and status")
	hidden.set_face_hidden(true)
	check(not hidden.face_up and hidden.face_hidden,"hiding is independent from physical flip")
	hidden.set_face_up(true,false)
	check(hidden.face_hidden and hidden.public_description()=="未知卡牌","flipping upright does not reveal hidden identity")
	unknown.data["title"]="SECRET NULL TITLE"
	unknown.data["id"]="SECRET NULL ID"
	unknown.data["metadata"]={"secret":"PRIVATE"}
	demo.select(unknown)
	check(not demo.status.text.contains("SECRET") and not JSON.stringify(unknown.public_snapshot()).contains("SECRET") and not unknown.public_snapshot().has("metadata"),"null texture never leaks identity or arbitrary metadata")
	demo.toggle_hidden()
	check(unknown.face_hidden and unknown.visual.get_child(0).material_override.albedo_texture==Card3D.UNKNOWN_FACE and not demo.status.text.contains("SECRET"),"hiding no-face card retains unknown presentation and safe status")
	demo.toggle_hidden()
	check(not unknown.face_hidden and unknown.visual.get_child(0).material_override.albedo_texture==Card3D.UNKNOWN_FACE and unknown.public_description()=="未知卡牌" and not demo.status.text.contains("SECRET"),"unhiding no-face card never invents or exposes a face")
	check(demo.total_cards()==64,"privacy operations preserve total population")
	var isolated := Card3D.new()
	isolated.configure({"size":Vector2(-1,0),"thickness":3.0,"id":"custom"})
	root.add_child(isolated)
	check(isolated.card_size==Vector2(0.2,0.2) and isolated.thickness==0.2,"configuration clamps invalid dimensions")
	check(isolated.data.id=="custom","custom data preserved")
	isolated.set_face_up(false)
	isolated.set_hovered(true)
	isolated.configure({"size":Vector2(2,3),"face_up":true})
	check(isolated.face_up and isolated.visual.rotation.z==0 and isolated.card_size==Vector2(2,3),"live reconfiguration safely resets geometry and flip")
	isolated.set_face_up(false)
	isolated.set_face_up(true)
	await create_timer(0.95).timeout
	check(isolated.face_up and is_zero_approx(isolated.visual.rotation.z),"rapid flip reversals settle correctly")
	isolated.configure({"face":load("res://assets/card_0.svg"),"title":"OLD IDENTITY","id":777,"face_up":true,"face_hidden":false})
	check(isolated.public_description()=="OLD IDENTITY","configured visible face exposes intended public title")
	isolated.configure({})
	check(isolated.face_texture==null and isolated.data.is_empty() and isolated.visual.get_child(0).material_override.albedo_texture==Card3D.UNKNOWN_FACE,"empty live replacement clears prior face and data")
	check(isolated.public_description()=="未知卡牌" and not JSON.stringify(isolated.public_snapshot()).contains("OLD IDENTITY"),"empty live replacement cannot leak prior identity")
	isolated.free()
	print("DIAGNOSTIC: before showcase")
	demo.showcase()
	print("DIAGNOSTIC: after showcase, before timer")
	await create_timer(0.45).timeout
	print("DIAGNOSTIC: after showcase timer")
	check(demo.played.size()==3 and demo.hand.size()==4 and not demo.played[2].face_up,"deterministic showcase")
	var expected_seats := {2:[1,5],3:[1,4,6],4:[1,3,5,7],5:[1,3,4,6,7],6:[1,2,4,5,6,8],7:[1,2,3,4,6,7,8],8:[1,2,3,4,5,6,7,8]}
	for count in range(2,9):
		var ids: Array = []
		for i in count: ids.append("stable-user-%d" % (100-i))
		check(demo.start_round(ids),"start %d-player round" % count)
		var mapping: Dictionary = demo.round_mapping()
		check(mapping.values()==expected_seats[count],"%d players use approved balanced physical seats" % count)
		var gaps: Array = []
		for i in count:
			check(demo.seat_for_player(ids[i])==expected_seats[count][i],"stable input identity maps in order")
			gaps.append((expected_seats[count][(i+1)%count]-expected_seats[count][i]+8)%8)
		check(gaps.max()-gaps.min()<=1,"cyclic seat gaps differ by at most one")
		check(demo.deck.size()==64-(5+3*(count-1)) and demo.total_cards()==64,"population reflects only occupied seats")
		for i in 8:
			var occupied: bool = (i+1) in expected_seats[count]
			check(demo.set_active_seat(i)==occupied,"only occupied physical seat can activate")
			check(demo.seat_buttons[i].disabled==not occupied,"empty seat UI disabled")
			check(demo.seats[i].hand.size()==(5 if i==0 else 3) if occupied else demo.seats[i].hand.is_empty(),"empty seats never receive cards")
			check(demo.player_at_seat(i+1)==(str(demo.seats[i].player_id)),"query and seat occupancy agree")
			if not occupied: check(not demo.transfer_to_seat(demo.hand[0],i),"transfer rejects empty seat")
		demo.set_active_seat(0)
		var preserved_card: Card3D = demo.hand[0]
		check(demo.set_pending_player_count(2 if count!=2 else 8),"next-round count accepted")
		check(demo.round_mapping()==mapping and demo.hand[0]==preserved_card,"pending setup does not mutate round or cards")
		demo.reset()
		check(demo.round_mapping()==mapping and demo.total_cards()==64,"reset preserves fixed mapping")
		var external: Dictionary = demo.round_mapping()
		external.clear()
		ids.clear()
		check(demo.round_mapping()==mapping,"caller array and query dictionary cannot mutate allocation")
	check(demo.start_round(["alice","bob","carol"]),"custom stable IDs accepted")
	var valid_mapping: Dictionary = demo.round_mapping()
	var live_card: Card3D = demo.hand[0]
	for invalid in [[],["solo"],["a","a"],["a",""],["a","  "],[1,2],["a","b","c","d","e","f","g","h","i"]]:
		check(not demo.start_round(invalid),"invalid IDs/count rejected")
		check(demo.round_mapping()==valid_mapping and demo.hand[0]==live_card and demo.total_cards()==64,"invalid start is atomic")
	check(not demo.set_pending_player_count(1) and not demo.set_pending_player_count(9),"invalid pending count rejected")
	check(demo.seat_for_player("missing")==0 and demo.player_at_seat(0).is_empty() and demo.player_at_seat(9).is_empty(),"missing mapping queries are safe")
	var round_drag := {"cancelled":0}
	live_card.drag_finished.connect(func(_card,accepted):
		if not accepted: round_drag.cancelled += 1)
	live_card.begin_drag()
	demo.dragged = live_card
	demo.pressed = live_card
	demo.select(live_card)
	demo.set_pending_player_count(2)
	check(demo.start_pending_round(),"new-round UI action commits pending count")
	check(round_drag.cancelled==1 and demo.dragged==null and demo.pressed==null and demo.selected==null,"new round cancels drag once and clears transient state")
	check(demo.round_mapping().values()==[1,5] and demo.active_seat==0 and demo.total_cards()==64 and demo.played.is_empty(),"new round commits new fixed mapping and fresh population")
	demo.set_pending_player_count(8)
	demo.start_pending_round()
	demo.set_view(false)
	for seat in demo.seats: check(not seat.label.visible,"first person hides world label clutter")
	demo.set_view(true)
	for seat in demo.seats:
		check(seat.label.visible and not seat.label.text.contains("\n"),"overview uses compact single-line physical seat labels")
	demo.set_view(false)
	var look_before_popup: float = demo.player_yaw
	var hand_before_popup: int = demo.hand.size()
	demo.player_count_select.get_popup().show()
	var popup_key := InputEventKey.new()
	popup_key.pressed = true
	popup_key.keycode = KEY_RIGHT
	demo._input(popup_key)
	check(demo.player_yaw==look_before_popup,"dropdown keyboard navigation does not rotate camera")
	popup_key.keycode = KEY_D
	demo._unhandled_input(popup_key)
	check(demo.hand.size()==hand_before_popup,"dropdown suppresses gameplay shortcuts")
	demo.player_count_select.get_popup().hide()
	print("TEST RESULT: %d checks, %d failures"%[checks,failures])
	demo.free()
	quit(1 if failures else 0)
