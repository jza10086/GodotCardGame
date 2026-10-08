extends SceneTree
# Headless cannot read a rendered viewport image; intercept only file capture.
class ScreenshotProbe extends "res://scripts/table_demo.gd":
	func capture() -> void:
		screenshots += 1
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+label)
	else: print("PASS: "+label)
func key(demo, code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	demo._input(event)
	if code != KEY_ESCAPE: demo._unhandled_input(event)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var demo = ScreenshotProbe.new()
	root.add_child(demo)
	await process_frame
	demo.set_process(false)
	check(not demo.menu_open and not demo.debug_menu.visible,"menu initially hidden")
	check(demo.debug_menu.is_ancestor_of(demo.view_label) and demo.debug_menu.is_ancestor_of(demo.status),"debug status and identity inside menu")
	check(demo.debug_menu.is_ancestor_of(demo.player_count_select) and demo.debug_menu.is_ancestor_of(demo.seat_buttons[0]),"setup and seats moved into menu")
	check(not demo.debug_menu.is_ancestor_of(demo.counts) and not demo.debug_menu.is_ancestor_of(demo.action_bar),"gameplay counts and action bar preserved")
	for dimensions in [Vector2i(1440,960),Vector2i(1280,720),Vector2i(1024,768)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		key(demo,KEY_ESCAPE)
		await process_frame
		await process_frame
		check(demo.menu_open and demo.debug_menu.visible,"Escape opens "+str(dimensions))
		check(demo.capture_view_name()=="menu","menu screenshot naming independent of camera")
		check(root.get_visible_rect().encloses(demo.menu_panel.get_global_rect()),"menu fits "+str(dimensions))
		check(demo.menu_panel.get_global_rect().encloses(demo.resume_button.get_global_rect()),"resume fits panel")
		key(demo,KEY_ESCAPE)
		check(not demo.menu_open and not demo.free_look,"Escape closes without unexpected capture")
	var card: Card3D = demo.hand[0]
	demo.select(card)
	card.begin_drag()
	demo.dragged = card
	demo.pressed = card
	demo.place_in_world(card,demo)
	key(demo,KEY_ESCAPE)
	check(demo.dragged==null and demo.pressed==null and not card.dragging,"menu cancels in-progress drag")
	check(card.get_parent()==demo.hand_world and card.zone==&"hand" and demo.total_cards()==64,"drag cancellation restores original card")
	check(demo.selected==null and demo.hovered==null and not demo.inspect_panel.visible,"menu dismisses hover and inspector")
	var captures_before: int = demo.screenshots
	key(demo,KEY_F12)
	check(demo.screenshots==captures_before+1 and demo.menu_open,"F12 captures once inside menu without closing or gameplay")
	var repeat := InputEventKey.new()
	repeat.pressed = true
	repeat.echo = true
	repeat.keycode = KEY_F12
	demo._input(repeat)
	check(demo.screenshots==captures_before+1,"F12 key repeat does not create duplicate captures")
	var yaw: float = demo.player_yaw
	var count: int = demo.hand.size()
	var mapping: Dictionary = demo.round_mapping()
	for code in [KEY_D,KEY_ENTER,KEY_F,KEY_H,KEY_TAB,KEY_T,KEY_V,KEY_R,KEY_2,KEY_LEFT,KEY_F11]: key(demo,code)
	var mouse := InputEventMouseButton.new()
	mouse.pressed = true
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = demo.card_screen(card)
	demo._input(mouse)
	demo._unhandled_input(mouse)
	mouse.button_index = MOUSE_BUTTON_RIGHT
	demo._input(mouse)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(80,40)
	demo._input(motion)
	check(demo.hand.size()==count and demo.selected==null and demo.player_yaw==yaw,"menu blocks card clicks draw play and camera input")
	check(not demo.hand_stowed and not demo.third_person and not demo.top_down and demo.active_seat==0,"menu blocks gameplay mode shortcuts")
	check(demo.screen_drop_zone(Vector2(500,500))==&"invalid","menu blocks drop target")
	demo.set_pending_player_count(3)
	check(demo.round_mapping()==mapping and demo.total_cards()==64,"pending player count does not mutate round")
	demo.start_pending_round()
	check(demo._round_players.size()==3 and demo.total_cards()==64 and demo.menu_open,"explicit start applies count and keeps menu accessible")
	check(demo.seat_buttons[1].disabled and not demo.seat_buttons[3].disabled,"only occupied seats available")
	demo.seat_buttons[3].pressed.emit()
	check(demo.active_seat==3 and demo.menu_open and demo.view_label.text.contains("座位 4"),"menu seat control updates current identity")
	demo.resume_button.pressed.emit()
	check(not demo.menu_open and not demo.free_look,"resume closes menu after seat change")
	demo.set_hand_stowed(true)
	key(demo,KEY_ESCAPE)
	check(demo.menu_open and demo.hand_stowed and not demo.free_look,"captured stow releases into menu without expanding")
	key(demo,KEY_ESCAPE)
	check(demo.free_look and demo.hand_stowed,"closing restores prior captured stow")
	key(demo,KEY_ESCAPE)
	demo._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	demo._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	demo.close_debug_menu()
	check(not demo.free_look and demo.hand_stowed,"focus loss invalidates capture restoration even after focus returns")
	key(demo,KEY_ESCAPE)
	key(demo,KEY_ESCAPE)
	check(not demo.free_look,"released stow stays released after menu roundtrip")
	demo.set_hand_stowed(true)
	key(demo,KEY_ESCAPE)
	demo.set_active_seat(0)
	demo.close_debug_menu()
	check(not demo.free_look and not demo.hand_stowed,"seat change invalidates prior capture restoration")
	for mode in ["third","top"]:
		if mode=="third": demo.set_view(true)
		else: demo.set_top_down(true)
		var camera = demo.camera
		key(demo,KEY_ESCAPE)
		key(demo,KEY_ESCAPE)
		check(demo.camera==camera and not demo.free_look,"menu preserves "+mode+" view without capture")
	demo.reset_view()
	var drawn: Card3D = demo.draw_card()
	check(demo.flights.has(drawn),"draw flight started before menu")
	key(demo,KEY_ESCAPE)
	check(demo.flights.is_empty() and drawn in demo.hand and demo.total_cards()==64,"menu safely settles committed draw without reset")
	demo.reset()
	demo.close_debug_menu()
	check(demo.total_cards()==64 and not demo.menu_open and not demo.free_look,"reset while menu open preserves safe close")
	print("MENU TEST RESULT: %d checks, %d failures" %[checks,failures])
	demo.free()
	quit(1 if failures else 0)
