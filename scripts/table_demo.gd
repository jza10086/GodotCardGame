extends Node3D
const CARD = preload("res://scenes/card_3d.tscn")
const ALLOCATION = preload("res://scripts/seat_allocation.gd")
const TOTAL := 64
const SEAT_COUNT := 8
# Regular octagon: each seat is centered on one edge, 45 degrees apart.
const TABLE_APOTHEM := 12.0
const SEAT_RADIUS := 11.0
const DECK_ORIGIN := Vector3(-6.0,0,-4.0)
const PLAY_LIMIT := 16
var seats: Array[Dictionary] = []
var active_seat := 0
var pending_player_count := 8
var player_count_select: OptionButton
var menu_open := false
var debug_menu: ColorRect
var menu_panel: PanelContainer
var menu_content: VBoxContainer
var resume_button: Button
var _menu_restore_capture := false
var _application_focused := true
var _round_players: Array = []
var _player_seats: Dictionary = {}
var seat_buttons: Array[Button] = []
var hide_button: Button
const HAND_LIMIT := 8
var camera: Camera3D
var hand: Array[Card3D] = []
var played: Array[Card3D] = []
var deck: Array[Dictionary] = []
var deck_visual: Array[Card3D] = []
# Flights animate the existing card node; logical zones reserve capacity immediately.
var flights: Dictionary = {}
var selected_cards: Array[Card3D] = []
var play_button: Button
var deck_count_label: Label3D
var last_play_panel: PanelContainer
var last_play_label: Label
var last_play_cards: HBoxContainer
var _last_play: Dictionary = {}
var _preview_textures: Dictionary = {}
var _pending_play: Dictionary = {}
var selected: Card3D
var hovered: Card3D
var pressed: Card3D
var dragged: Card3D
var press_position := Vector2.ZERO
var counts: Label
var status: Label
var draw_button: Button
var flip_button: Button
var return_button: Button
var play_border: MeshInstance3D
var action_bar: VBoxContainer
var ui: Control
var font: Font
var screenshots := 0
# The hand, table, and both cameras share one World3D.
# Observer orbit never alters the player look rig.
var player_rig: Node3D
var hand_world: Node3D
var first_camera: Camera3D
var observer_camera: Camera3D
var third_person := false
var top_down := false
var top_camera: Camera3D
var hand_stowed := false
var free_look := false
var auto_collapsed := false
var hand_idle := 0.0
var stow_button: Button
var top_button: Button
var crosshair: Label
var inspect_panel: PanelContainer
var inspect_title: Label
var inspect_grid: GridContainer
var inspect_scroll: ScrollContainer
var inspect_elapsed := 0.0
var inspect_key := ""
var inspect_target: Card3D
var aim_target: Card3D
var _group_serial := 0
signal world_target_changed(card: Card3D, controllable: bool)
# A future rules host may consume this signal; it never grants ownership.
signal world_interaction_requested(card: Card3D, controllable: bool)
var view_button: Button
var view_label: Label
var looking := false
var player_yaw := 0.0
var player_pitch := deg_to_rad(-38.0)
var observer_yaw := 0.0
var observer_pitch := 0.0
var drag_pointer_offset := Vector2.ZERO
const PITCH_MIN := -75.0
const PITCH_MAX := 65.0

func hand_rect() -> Rect2:
	# Project the actual floating hand's nominal bounds, from either camera.
	var rect := Rect2()
	var initialized := false
	var half_width := maxf(1.0, (hand.size()-1) * hand_step() / 2.0 + 0.62)
	for x in [-half_width, half_width]:
		for z in [-0.9, 0.9]:
			var world := hand_world.to_global(Vector3(x, 0, z))
			if camera.is_position_behind(world): continue
			var point := camera.unproject_position(world)
			if not initialized:
				rect = Rect2(point, Vector2.ZERO)
				initialized = true
			else: rect = rect.expand(point)
	return rect.grow(16.0).intersection(get_viewport().get_visible_rect()) if initialized else Rect2()

func hand_step() -> float:
	return minf(1.22, 6.8 / maxf(1, hand.size()-1))

func resize_hand() -> void:
	release_mouse_look()
	cancel_drag()
	update_hand_pose(1.0)
	fit_top_camera()
	position_action_bar()
	layout_cards(false)

func hand_plane(screen: Vector2, _height := 0.1) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var normal := camera.global_basis.z
	var center := camera.global_position - normal * 4.6
	var hit: Variant = Plane(normal, normal.dot(center)).intersects_ray(origin, direction)
	return hit if hit != null else center

func card_screen(card: Card3D) -> Vector2:
	if card in hand and not third_person and not top_down:
		return hand_card_rect(card).intersection(get_viewport().get_visible_rect()).get_center()
	return camera.unproject_position(card.global_position)

func screen_drop_zone(screen: Vector2) -> StringName:
	if menu_open: return &"invalid"
	if is_instance_valid(last_play_panel) and last_play_panel.get_global_rect().has_point(screen): return &"invalid"
	var size := get_viewport().get_visible_rect().size
	if not Rect2(Vector2.ZERO, size).has_point(screen) or screen.y < 160 or action_bar.get_global_rect().has_point(screen): return &"invalid"
	if hand_rect().has_point(screen): return &"hand"
	return drop_zone(screen_plane(screen, 0.0))

func place_in_world(card: Card3D, target: Node3D) -> void:
	if card.get_parent() != target: card.reparent(target, true)
	card.rotation = Vector3.ZERO
	card.scale = Vector3.ONE * (0.68 if target != self else 1.0)

func cancel_drag() -> void:
	settle_flights()
	if is_instance_valid(dragged): dragged.end_drag(false)
	dragged = null
	pressed = null
	if is_instance_valid(play_border): play_border.visible = false
	layout_cards(false)

func apply_player_look(delta: Vector2) -> void:
	player_yaw -= delta.x * 0.004
	player_pitch = clampf(player_pitch-delta.y*0.004, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))
	player_rig.rotation = Vector3(player_pitch, player_yaw, 0)

func apply_observer_look(delta: Vector2) -> void:
	observer_yaw -= delta.x * 0.004
	observer_pitch = clampf(observer_pitch + delta.y*0.004, -0.5, 0.6)
	var offset := Vector3(7, 26, -37).rotated(Vector3.RIGHT, observer_pitch).rotated(Vector3.UP, observer_yaw)
	observer_camera.look_at_from_position(Vector3(0,1,0)+offset, Vector3(0,1,0))

func clear_hover() -> void:
	if is_instance_valid(hovered): hovered.set_hovered(false)
	hovered = null

func set_view(third: bool) -> void:
	clear_hover()
	release_mouse_look()
	top_down = false
	cancel_drag()
	looking = false
	third_person = third
	if is_instance_valid(top_button): top_button.text = "俯视桌面 T"
	# The HUD identifies seats in first person; world labels belong to the overview.
	for seat in seats: seat.label.visible = third
	camera = observer_camera if third else first_camera
	camera.make_current()
	position_action_bar()
	if is_instance_valid(view_button): view_button.text = "第一人称  V" if third else "第三人称  V"
	if is_instance_valid(view_label): view_label.text = "%d 人局 · %s · 座位 %d · %s" % [_round_players.size(), player_at_seat(active_seat+1), active_seat+1, "第三人称全景" if third else "第一人称"]

func toggle_view() -> void:
	set_view(not third_person)

func reset_view() -> void:
	set_hand_stowed(false)
	cancel_drag()
	player_yaw = float(seats[active_seat].yaw)
	player_pitch = deg_to_rad(-38.0)
	apply_player_look(Vector2.ZERO)
	observer_yaw = 0.0
	observer_pitch = 0.0
	apply_observer_look(Vector2.ZERO)
	set_view(false)


func _ready() -> void:
	font = load("res://assets/ui_font.ttf")
	build_world()
	build_ui()
	start_pending_round()

func flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func slab(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = flat_material(color)
	add_child(mesh)
	return mesh

func octagon_vertices(apothem: float, height: float) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	var radius := apothem / cos(PI / 8.0)
	for i in SEAT_COUNT:
		var angle := TAU * float(i) / SEAT_COUNT - PI / 8.0
		vertices.append(Vector3(sin(angle) * radius, height, cos(angle) * radius))
	return vertices

func octagonal_slab(apothem: float, top: float, depth: float, color: Color, node_name: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var upper := octagon_vertices(apothem, top)
	var lower := octagon_vertices(apothem, top - depth)
	for i in SEAT_COUNT:
		var next := (i + 1) % SEAT_COUNT
		st.set_normal(Vector3.UP)
		for vertex in [Vector3(0, top, 0), upper[next], upper[i]]:
			st.add_vertex(vertex)
		st.set_normal(Vector3.DOWN)
		for vertex in [Vector3(0, top-depth, 0), lower[i], lower[next]]:
			st.add_vertex(vertex)
		st.set_normal(Vector3(sin(TAU*i/SEAT_COUNT), 0, cos(TAU*i/SEAT_COUNT)))
		for vertex in [upper[i], upper[next], lower[i], lower[i], upper[next], lower[next]]:
			st.add_vertex(vertex)
	mesh.mesh = st.commit()
	mesh.material_override = flat_material(color)
	# The slab is also visible while orbiting underneath it.
	mesh.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(mesh)
	return mesh

func octagonal_border(apothem: float, height: float, color: Color, width: float) -> Node3D:
	var border := Node3D.new()
	border.name = "OctagonalInlay"
	add_child(border)
	var vertices := octagon_vertices(apothem, height)
	for i in SEAT_COUNT:
		var a := vertices[i]
		var b := vertices[(i + 1) % SEAT_COUNT]
		var edge := slab(Vector3(a.distance_to(b), width, width), (a+b)/2.0, color)
		edge.rotation.y = -atan2(b.z-a.z, b.x-a.x)
		edge.reparent(border)
	return border

func line_rect(center: Vector3, size: Vector2, color: Color, width := 0.025) -> MeshInstance3D:
	var root_mesh := MeshInstance3D.new()
	add_child(root_mesh)
	for side in [-1,1]:
		var a := slab(Vector3(size.x,width,width), center+Vector3(0,0,side*size.y/2),color)
		var b := slab(Vector3(width,width,size.y),center+Vector3(side*size.x/2,0,0),color)
		a.reparent(root_mesh)
		b.reparent(root_mesh)
	return root_mesh

func label_3d(text: String, pos: Vector3, size := 30, color := Color("698984")) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.font_size = size
	label.pixel_size = 0.006
	label.modulate = color
	label.position = pos + Vector3(0, 0.08, 0)
	label.outline_size = 0
	label.shaded = false
	label.rotation_degrees.x = -90
	label.no_depth_test = false
	add_child(label)

func build_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0c2027")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b3d7d1")
	env.ambient_light_energy = 0.28
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65,-30,0)
	light.light_energy = 0.72
	light.shadow_enabled = true
	add_child(light)
	for i in SEAT_COUNT:
		var yaw := TAU * float(i) / SEAT_COUNT
		var rig := Node3D.new()
		rig.name = "PlayerLookRig%d" % (i+1)
		add_child(rig)
		rig.position = Vector3(sin(yaw)*SEAT_RADIUS,8.0,cos(yaw)*SEAT_RADIUS)
		rig.rotation = Vector3(player_pitch,yaw,0)
		var seat_camera := Camera3D.new()
		seat_camera.fov = 58
		seat_camera.near = 0.1
		seat_camera.far = 150
		rig.add_child(seat_camera)
		var anchor := Node3D.new()
		anchor.name = "FloatingHand%d" % (i+1)
		rig.add_child(anchor)
		anchor.position = Vector3(0,-0.95,-4.6)
		anchor.rotation.x = PI/2.0
		var cards: Array[Card3D] = []
		seats.append({"id":"P%d" % (i+1),"seat_id":i+1,"player_id":"","rig":rig,"camera":seat_camera,"anchor":anchor,"hand":cards,"yaw":yaw})
		var seat_pos := Vector3(sin(yaw)*10.8,-0.05,cos(yaw)*10.8)
		var seat_label := Label3D.new()
		seat_label.text = "P%d" % (i+1)
		seat_label.font = font
		seat_label.font_size = 42
		seat_label.pixel_size = 0.010
		seat_label.modulate = Color("d4e7cf")
		seat_label.outline_size = 6
		seat_label.outline_modulate = Color("173d40")
		seat_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		seat_label.position = seat_pos + Vector3(0,0.6,0)
		add_child(seat_label)
		seats[i]["label"] = seat_label
		var marker := line_rect(Vector3.ZERO,Vector2(2.1,1.0),Color("47736d"))
		marker.name = "SeatMarker%d" % (i+1)
		marker.position = seat_pos
		marker.rotation.y = yaw
	player_rig = seats[0].rig
	first_camera = seats[0].camera
	hand_world = seats[0].anchor
	hand = seats[0].hand
	first_camera.current = true
	camera = first_camera
	observer_camera = Camera3D.new()
	observer_camera.fov = 56
	observer_camera.far = 150
	add_child(observer_camera)
	apply_observer_look(Vector2.ZERO)
	top_camera = Camera3D.new()
	top_camera.name = "TableTopCamera"
	top_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	top_camera.far = 150
	add_child(top_camera)
	top_camera.position = Vector3(0,45,0)
	top_camera.rotation = Vector3(-PI/2,0,0)
	fit_top_camera()
	octagonal_slab(TABLE_APOTHEM,-0.09,0.46,Color("567b74"),"OctagonalTableRim")
	octagonal_slab(TABLE_APOTHEM-0.38,-0.07,0.035,Color("133f43"),"OctagonalTableFelt")
	octagonal_border(TABLE_APOTHEM-0.68,-0.045,Color("709389"),0.035)
	line_rect(Vector3(0,-0.06,0),Vector2(16.4,8.4),Color("47736d"),0.025)
	play_border = line_rect(Vector3(0,-0.04,0),Vector2(16.5,8.5),Color("a9d6b6"),0.04)
	play_border.visible = false
	label_3d("S H A R E D   T A B L E",Vector3(0,-0.05,-4.8),42)
	deck_count_label = Label3D.new()
	deck_count_label.font = font
	deck_count_label.font_size = 42
	deck_count_label.pixel_size = 0.010
	deck_count_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	deck_count_label.position = DECK_ORIGIN+Vector3(0,1.3,0)
	deck_count_label.modulate = Color("d3edc8")
	deck_count_label.outline_size = 7
	add_child(deck_count_label)
	label_3d("D E C K",DECK_ORIGIN+Vector3(0,-0.05,1.7),32)
	line_rect(DECK_ORIGIN+Vector3(0,-0.04,0),Vector2(1.9,2.7),Color("416762"),0.018)

func set_active_seat(index: int) -> bool:
	if index < 0 or index >= SEAT_COUNT or player_at_seat(index+1).is_empty(): return false
	cancel_drag()
	select(null)
	if is_instance_valid(hovered): hovered.set_hovered(false)
	hovered = null
	set_hand_stowed(false)
	active_seat = index
	player_rig = seats[index].rig
	first_camera = seats[index].camera
	hand_world = seats[index].anchor
	hand = seats[index].hand
	player_yaw = player_rig.rotation.y
	player_pitch = player_rig.rotation.x
	var was_top := top_down
	set_view(third_person)
	if was_top: set_top_down(true)
	refresh_viewer_faces()
	update_ui()
	status.text = "%s · 座位 %d · 本局座位固定" % [player_at_seat(index+1), index+1]
	return true

func total_cards() -> int:
	var total := deck.size()+played.size()
	for seat in seats: total += seat.hand.size()
	return total

func can_control(card: Card3D) -> bool:
	return is_instance_valid(card) and (card in hand or card in played)

func transfer_to_seat(card: Card3D, index: int) -> bool:
	if not is_instance_valid(card): return false
	if index < 0 or index >= SEAT_COUNT or player_at_seat(index+1).is_empty() or card.zone == &"deck": return false
	var destination: Array = seats[index].hand
	if card in destination: return true
	if destination.size() >= HAND_LIMIT: return false
	var known := card in played
	for seat in seats: known = known or card in seat.hand
	if not known: return false
	cancel_drag()
	for seat in seats: seat.hand.erase(card)
	played.erase(card)
	destination.append(card)
	card.set_meta("seat_id",seats[index].id)
	card.set_zone(&"hand")
	if card in selected_cards: select(null)
	layout_cards()
	update_ui()
	return true

func style(color: Color, radius := 10, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 11
	s.content_margin_bottom = 11
	if border.a > 0:
		s.border_color = border
		s.set_border_width_all(1)
	return s

func text_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	return label

func button(text: String, callback: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal",style(Color("c2e8ce") if primary else Color("183a3f"),9,Color("426365")))
	b.add_theme_stylebox_override("hover",style(Color("dcf5e1") if primary else Color("2d5757"),9,Color("91b9a3")))
	b.add_theme_stylebox_override("pressed",style(Color("95c8ac"),9))
	b.add_theme_stylebox_override("disabled",style(Color("193436"),9))
	b.add_theme_color_override("font_color",Color("153431") if primary else Color("e5eee3"))
	b.add_theme_color_override("font_hover_color",Color("173e36") if primary else Color.WHITE)
	b.add_theme_font_size_override("font_size",18)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	return b

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = font
	ui.theme = theme
	layer.add_child(ui)
	get_viewport().size_changed.connect(resize_hand)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left",48)
	margin.add_theme_constant_override("margin_right",48)
	margin.add_theme_constant_override("margin_top",31)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# This entire former upper-left block lives in the Escape menu.
	menu_content = titles
	var setup_row := HBoxContainer.new()
	setup_row.add_theme_constant_override("separation",12)
	titles.add_child(setup_row)
	setup_row.add_child(text_label("ARC / 八角牌桌",24,Color("e7eddf")))
	player_count_select = OptionButton.new()
	player_count_select.add_theme_font_size_override("font_size",16)
	for count in range(2,9): player_count_select.add_item("下局 %d 人" % count,count)
	player_count_select.select(6)
	player_count_select.item_selected.connect(func(index: int): set_pending_player_count(player_count_select.get_item_id(index)))
	setup_row.add_child(player_count_select)
	setup_row.add_child(button("开始新局",start_pending_round,true))
	view_label = text_label("第一人称 · 手牌随视线悬浮",16,Color("92aea6"))
	titles.add_child(view_label)
	var seat_row := HBoxContainer.new()
	seat_row.add_theme_constant_override("separation",6)
	titles.add_child(seat_row)
	for i in SEAT_COUNT:
		var seat_button := button("座位%d" % (i+1),set_active_seat.bind(i))
		seat_button.add_theme_font_size_override("font_size",13)
		seat_button.add_theme_stylebox_override("normal",style(Color("183a3f"),6))
		seat_buttons.append(seat_button)
		seat_row.add_child(seat_button)
	counts = text_label("",17,Color("b8c9bd"))
	counts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	counts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	counts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(counts)
	var bottom := VBoxContainer.new()
	action_bar = bottom
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.position.y = -get_viewport().get_visible_rect().size.y*0.45-48
	bottom.offset_bottom = -get_viewport().get_visible_rect().size.y*0.45
	bottom.add_theme_constant_override("separation",13)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bottom)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation",8)
	bottom.add_child(buttons)
	draw_button = button("摸牌 D",draw_card,true)
	play_button = button("出牌 Enter",play_selected,true)
	buttons.add_child(play_button)
	flip_button = button("翻面  F",flip_selected)
	return_button = button("收回手牌",return_selected)
	buttons.add_child(draw_button)
	buttons.add_child(flip_button)
	buttons.add_child(return_button)
	hide_button = button("隐藏  H",toggle_hidden)
	buttons.add_child(hide_button)
	view_button = button("全景 V",toggle_view)
	buttons.add_child(view_button)
	buttons.add_child(button("复位 R",reset_view))
	buttons.add_child(button("重置本局",reset))
	stow_button = button("收起手牌 Tab",toggle_hand_stowed)
	buttons.add_child(stow_button)
	top_button = button("俯视桌面 T",toggle_top_down)
	buttons.add_child(top_button)
	# One measured row, including navigation, instead of overlapping anchored groups.
	buttons.add_theme_constant_override("separation",6)
	for control in buttons.get_children():
		control.add_theme_font_size_override("font_size",16)
		for state in ["normal","hover","pressed","disabled"]:
			var box: StyleBoxFlat = control.get_theme_stylebox(state).duplicate()
			box.content_margin_left = 9
			box.content_margin_right = 9
			control.add_theme_stylebox_override(state,box)
	crosshair = text_label("+",23,Color("dbf3db"))
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-8,-17)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.visible = false
	ui.add_child(crosshair)
	build_inspector()
	status = text_label("",16,Color("a3bdb1"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(status)
	var hint := text_label("Esc 菜单 · Tab 收起 / 展开 · T 俯视 · Ctrl 多选 / Enter 出牌",14,Color("72978d"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.position.y = 31
	var history := PanelContainer.new()
	last_play_panel = history
	history.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	history.position = Vector2(-350,172)
	history.size = Vector2(302,140)
	history.add_theme_stylebox_override("panel",style(Color("102e34e8"),10,Color("416762")))
	history.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(history)
	var history_column := VBoxContainer.new()
	history_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history.add_child(history_column)
	last_play_label = text_label("最近出牌 · 暂无",16,Color("c2e8ce"))
	last_play_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history_column.add_child(last_play_label)
	last_play_cards = HBoxContainer.new()
	last_play_cards.add_theme_constant_override("separation",4)
	last_play_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history_column.add_child(last_play_cards)
	var note := text_label("保留最近一次出牌（单张 / 一组）",12,Color("72978d"))
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history_column.add_child(note)

	# Last child: a full-screen input shield above gameplay and inspection UI.
	debug_menu = ColorRect.new()
	debug_menu.name = "EscapeMenu"
	debug_menu.color = Color(0.015,0.04,0.045,0.78)
	debug_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	debug_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(debug_menu)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	debug_menu.add_child(center)
	menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(720,0)
	menu_panel.add_theme_stylebox_override("panel",style(Color("102e34"),16,Color("62867a")))
	center.add_child(menu_panel)
	var padding := MarginContainer.new()
	for edge in ["left","right","top","bottom"]:
		padding.add_theme_constant_override("margin_"+edge,26)
	menu_panel.add_child(padding)
	titles.add_theme_constant_override("separation",20)
	padding.add_child(titles)
	titles.add_child(text_label("调试与本局设置 · 修改下局人数后，点击开始新局生效",16,Color("92aea6")))
	resume_button = button("继续游戏  Esc",close_debug_menu,true)
	titles.add_child(resume_button)
	debug_menu.hide()

func open_debug_menu() -> void:
	if menu_open: return
	var restore := free_look
	release_mouse_look()
	# Committed flights settle; an uncommitted drag returns to its original zone.
	cancel_drag()
	select(null)
	clear_hover()
	hide_inspector()
	aim_target = null
	menu_open = true
	_menu_restore_capture = restore and _application_focused
	debug_menu.show()

func close_debug_menu() -> void:
	if not menu_open: return
	var restore := _menu_restore_capture and _application_focused and hand_stowed and not third_person and not top_down
	player_count_select.get_popup().hide()
	menu_open = false
	debug_menu.hide()
	release_mouse_look()
	if restore:
		free_look = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		crosshair.show()

func toggle_debug_menu() -> void:
	if menu_open: close_debug_menu()
	else: open_debug_menu()

## Editing next-round setup never changes the current round.
func set_pending_player_count(count: int) -> bool:
	if count < 2 or count > SEAT_COUNT: return false
	pending_player_count = count
	if is_instance_valid(player_count_select): player_count_select.select(count-2)
	return true

func start_pending_round() -> bool:
	var ids: Array = []
	for i in pending_player_count: ids.append("玩家%d" % (i+1))
	return start_round(ids)

## Atomically validate first. No mid-round joining, leaving, or rebalancing.
func start_round(player_ids: Array) -> bool:
	var allocation: Dictionary = ALLOCATION.allocate(player_ids)
	if allocation.is_empty(): return false
	cancel_drag()
	select(null)
	looking = false
	_round_players = player_ids.duplicate()
	_player_seats = allocation
	for seat in seats:
		seat.player_id = player_at_seat(seat.seat_id)
		seat.label.text = "%d · %s" % [seat.seat_id, seat.player_id if not seat.player_id.is_empty() else "空位"]
		seat.label.modulate = Color("d4e7cf") if not seat.player_id.is_empty() else Color("54736f")
		seat.rig.rotation = Vector3(deg_to_rad(-38.0),seat.yaw,0)
	set_active_seat(0)
	reset()
	reset_view()
	return true

## Public numbers are 1–8; existing set_active_seat uses a 0–7 index.
func seat_for_player(player_id: String) -> int:
	return int(_player_seats.get(player_id,0))

func player_at_seat(seat_number: int) -> String:
	for id in _player_seats:
		if _player_seats[id] == seat_number: return String(id)
	return ""

func round_mapping() -> Dictionary:
	return _player_seats.duplicate()

func reset() -> void:
	set_hand_stowed(false)
	hide_inspector()
	flights.clear()
	_pending_play.clear()
	_last_play.clear()
	selected_cards.clear()
	refresh_last_play()
	if is_instance_valid(dragged): dragged.end_drag(false)
	dragged = null
	pressed = null
	hovered = null
	selected = null
	for seat in seats:
		for card in seat.hand: card.free()
		seat.hand.clear()
	for card in played+deck_visual:
		card.free()
	played.clear()
	deck_visual.clear()
	deck.clear()
	for i in TOTAL:
		deck.append({"id":i,"title":["ORBIT","BLOOM","TIDE","EMBER","ECHO","PRISM"][i%6],"face":load("res://assets/card_%d.svg"%(i%6)),"back":load("res://assets/back.svg")})
	# Deal only to occupied seats; resetting preserves this round’s mapping.
	for seat_index in SEAT_COUNT:
		if player_at_seat(seat_index+1).is_empty(): continue
		for i in (5 if seat_index == 0 else 3):
			var card: Card3D = CARD.instantiate()
			var config: Dictionary = deck.pop_front()
			if seat_index == 0 and i == 1: config["face_hidden"] = true
			if seat_index == 0 and i == 3: config = {"back":load("res://assets/back.svg")}
			card.configure(config)
			watch_card(card)
			seats[seat_index].anchor.add_child(card)
			card.set_meta("seat_id",seats[seat_index].id)
			seats[seat_index].hand.append(card)
	update_deck()
	refresh_viewer_faces()
	layout_cards(false)
	play_border.visible = false
	status.text = "%d 人已就位 · 座位本局固定 · 下局人数需点「开始新局」生效" % _round_players.size()
	update_ui()

func draw_card(animated := true) -> Card3D:
	if deck.is_empty():
		status.text = "牌堆已空 · 点击重置重新开始"
		return null
	if hand.size() >= HAND_LIMIT:
		status.text = "手牌已满（8 张）· 先打出一张"
		return null
	var card: Card3D = CARD.instantiate()
	card.configure(deck.pop_front())
	watch_card(card)
	hand_world.add_child(card)
	card.scale = Vector3.ONE * 0.68
	card.position = Vector3.ZERO
	card.zone = &"hand"
	hand.append(card)
	card.set_meta("seat_id",seats[active_seat].id)
	if animated:
		var start := Transform3D(Basis.IDENTITY,deck_top_position())
		start_flight(card,start,"draw",0.85)
	layout_cards(animated)
	update_deck()
	update_ui()
	status.text = "已抽取 %s"%card.public_description()
	return card

func update_deck() -> void:
	for card in deck_visual: card.free()
	deck_visual.clear()
	for i in mini(deck.size(),12):
		var card: Card3D = CARD.instantiate()
		card.configure({"back":load("res://assets/back.svg"),"face_up":false})
		add_child(card)
		card.position = DECK_ORIGIN+Vector3(0.022*i,0.05+0.055*i,0)
		card.zone = &"deck"
		deck_visual.append(card)
	deck_count_label.text = "牌堆 · %02d" % deck.size()

func layout_cards(animated := true) -> void:
	refresh_viewer_faces()
	for seat in seats:
		var cards: Array = seat.hand
		for i in cards.size():
			if cards[i] == dragged or flights.has(cards[i]): continue
			place_in_world(cards[i],seat.anchor)
			var center := float(i)-(cards.size()-1)/2.0
			var step := minf(1.22,6.8/maxf(1,cards.size()-1))
			cards[i].move_to(Vector3(center*step,0.02*i,absf(center)*0.025),-center*0.025,animated)
	for i in played.size():
		if played[i] == dragged or flights.has(played[i]): continue
		place_in_world(played[i], self)
		var columns := mini(8,played.size())
		var column := i % 8
		var row := i / 8
		played[i].move_to(Vector3((column-(columns-1)/2.0)*1.95,0.12+0.002*i,-1.3+row*2.7),0,animated)

func update_ui() -> void:
	counts.text = "%s · 座位 %d / %d 人局\n牌堆 %02d  ·  手牌 %d/8  ·  桌面 %d/16"%[player_at_seat(active_seat+1),active_seat+1,_round_players.size(),deck.size(),hand.size(),played.size()]
	draw_button.disabled = deck.is_empty() or hand.size() >= HAND_LIMIT
	var playable := 0
	for card in selected_cards:
		if is_instance_valid(card) and card in hand and not flights.has(card): playable += 1
	play_button.disabled = playable == 0 or playable != selected_cards.size() or played.size()+playable > PLAY_LIMIT
	play_button.text = "出牌 %d 张 ↵" % playable if playable > 0 else "出牌 Enter"
	for i in seat_buttons.size():
		var occupant := player_at_seat(i+1)
		seat_buttons[i].disabled = occupant.is_empty()
		seat_buttons[i].text = "%d%s" % [i+1, " 空" if occupant.is_empty() else "号座"]
		seat_buttons[i].tooltip_text = "空位" if occupant.is_empty() else "%s · 座位 %d" % [occupant,i+1]
		seat_buttons[i].modulate = Color("d3f8b9") if i == active_seat else Color("70928b")
	hide_button.disabled = not is_instance_valid(selected)
	if is_instance_valid(selected): hide_button.text = "显示  H" if selected.face_hidden else "隐藏  H"
	flip_button.disabled = not is_instance_valid(selected)
	return_button.disabled = not is_instance_valid(selected) or selected.zone != &"play" or hand.size() >= HAND_LIMIT

func watch_card(card: Card3D) -> void:
	card.face_visibility_changed.connect(refresh_selected_info)
	card.flipped.connect(refresh_selected_info)

func refresh_selected_info(card: Card3D, _value: bool) -> void:
	if selected != card: return
	status.text = "%s · %s" % [card.public_description(),"正面" if card.face_up else "背面"]
	update_ui()

func select(card: Card3D, additive := false) -> void:
	if card != null and not can_control(card): card = null
	if not additive or card == null:
		for previous in selected_cards:
			if is_instance_valid(previous): previous.set_selected(false)
		selected_cards.clear()
	if card != null:
		if additive and card in selected_cards:
			selected_cards.erase(card)
			card.set_selected(false)
		else:
			selected_cards.append(card)
			card.set_selected(true)
	selected = selected_cards.back() if not selected_cards.is_empty() else null
	if is_instance_valid(selected):
		status.text = "已选 %d 张 · Enter 出牌 · Ctrl 点击增减选择" % selected_cards.size() if selected_cards.size()>1 else "%s · %s" % [selected.public_description(),"正面" if selected.face_up else "背面"]
	update_ui()

func play_selected() -> bool:
	var group: Array[Card3D] = selected_cards.duplicate()
	var accepted := false
	if can_play_cards(group):
		if is_instance_valid(dragged): cancel_drag()
		accepted = play_cards(group)
	if not accepted: status.text = "请选择当前手牌 · 整组须能放入桌面（最多 16 张）"
	return accepted

func can_play_cards(group: Array[Card3D]) -> bool:
	# This predicate never settles flights, changes selection, or ends a drag.
	if group.is_empty() or played.size()+group.size()>PLAY_LIMIT: return false
	var unique: Array[Card3D] = []
	for card in group:
		if not is_instance_valid(card) or card not in hand or card in unique: return false
		unique.append(card)
	return true

func play_cards(group: Array[Card3D]) -> bool:
	# Validate the entire group before touching cards, selection, or history.
	if not can_play_cards(group): return false
	settle_flights()
	var snapshots: Array[Dictionary] = []
	_group_serial += 1
	for card in group:
		card.set_meta("play_group",_group_serial)
		var start := card.global_transform
		hand.erase(card)
		played.append(card)
		card.set_meta("seat_id","")
		card.set_zone(&"play")
		place_in_world(card,self)
		start_flight(card,start,"play",0.65+0.06*snapshots.size())
		snapshots.append(card.public_snapshot())
	_pending_play = {"actor":player_at_seat(active_seat+1),"seat":active_seat+1,"cards":snapshots}
	layout_cards()
	update_ui()
	status.text = "%s 出牌 · %d 张" % [player_at_seat(active_seat+1),group.size()]
	return true

func flip_selected() -> void:
	settle_flights()
	if is_instance_valid(selected):
		selected.set_face_up(not selected.face_up)
		status.text = "%s · %s"%[selected.public_description(),"正面" if selected.face_up else "背面"]

func toggle_hidden() -> void:
	settle_flights()
	if not can_control(selected): return
	selected.set_face_hidden(not selected.face_hidden)
	select(selected)

func return_selected() -> void:
	if is_instance_valid(selected) and selected.zone == &"play":
		move_card(selected,&"hand")

func move_card(card: Card3D, destination: StringName) -> bool:
	if not can_control(card): return false
	if destination != &"hand" and destination != &"play": return false
	if destination == card.zone: return true
	if destination == &"hand" and hand.size() >= HAND_LIMIT: return false
	if destination == &"play" and played.size() >= PLAY_LIMIT: return false
	if destination == &"play":
		var single: Array[Card3D] = [card]
		return play_cards(single)
	settle_flights()
	hand.erase(card)
	played.erase(card)
	if destination == &"hand":
		hand.append(card)
		card.set_meta("seat_id",seats[active_seat].id)
	else:
		played.append(card)
		card.set_meta("seat_id","")
	card.set_zone(destination)
	layout_cards()
	update_ui()
	return true

func screen_plane(screen: Vector2, height := 0.5) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var hit: Variant = Plane(Vector3.UP,height).intersects_ray(origin,direction)
	return hit if hit != null else Vector3.INF

func hand_card_rect(card: Card3D, raised := false) -> Rect2:
	var rect := Rect2()
	var first := true
	for x in [-card.card_size.x/2.0,card.card_size.x/2.0]:
		for z in [-card.card_size.y/2.0,card.card_size.y/2.0]:
			var local := Vector3(x,0,z)
			if raised: local = local*card.hover_scale+card.hover_offset
			var point := camera.unproject_position(card.to_global(local))
			if first:
				rect = Rect2(point,Vector2.ZERO)
				first = false
			else: rect = rect.expand(point)
	return rect

func pick(screen: Vector2) -> Card3D:
	if is_instance_valid(last_play_panel) and last_play_panel.get_global_rect().has_point(screen): return null
	var size := get_viewport().get_visible_rect().size
	if not Rect2(Vector2.ZERO,size).has_point(screen) or screen.y < 160 or action_bar.get_global_rect().has_point(screen): return null
	if not third_person and not top_down and not hand_stowed:
		# Preserve the resting hit target as the visual rises, and include the raised card.
		if is_instance_valid(hovered) and hovered in hand and not flights.has(hovered):
			if hand_card_rect(hovered).has_point(screen) or hand_card_rect(hovered,true).has_point(screen): return hovered
		for i in range(hand.size()-1,-1,-1):
			if not flights.has(hand[i]) and hand_card_rect(hand[i]).has_point(screen): return hand[i]
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*100,1)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.collider.has_meta("card"):
		var card: Card3D = hit.collider.get_meta("card")
		if card.zone == &"deck" or (can_control(card) and not flights.has(card)): return card
	return null

func drop_zone(pos: Vector3) -> StringName:
	if absf(pos.x) <= 8.2 and absf(pos.z) <= 4.2: return &"play"
	return &"invalid"

func finish_drag(screen: Vector2) -> bool:
	if not is_instance_valid(dragged): return false
	var card := dragged
	var destination := screen_drop_zone(screen)
	var accepted := move_card(card,destination)
	card.end_drag(accepted)
	dragged = null
	pressed = null
	play_border.visible = false
	layout_cards()
	status.text = ("已放入桌面" if destination == &"play" else "已收回手牌") if accepted else "无效位置或区域已满 · 卡牌已归位"
	return accepted

func _process(_delta: float) -> void:
	advance_flights(_delta)
	if menu_open: return
	update_hand_pose(_delta)
	update_inspector(_delta)
	if free_look:
		var target := ray_target(get_viewport().get_visible_rect().size/2.0)
		if target != aim_target:
			aim_target = target
			world_target_changed.emit(target,can_control(target))
		return
	if not is_instance_valid(camera): return
	var mouse := get_viewport().get_mouse_position()
	if is_instance_valid(dragged):
		dragged.global_position = hand_plane(mouse + drag_pointer_offset)
		return
	if looking: return
	var over_ui := get_viewport().gui_get_hovered_control()
	var next := pick(mouse) if over_ui == null else null
	if next == hovered: return
	if is_instance_valid(hovered): hovered.set_hovered(false)
	hovered = next
	if is_instance_valid(hovered) and hovered.zone != &"deck": hovered.set_hovered(true)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		toggle_debug_menu()
		get_viewport().set_input_as_handled()
		return
	# Screenshots are diagnostic only and remain available inside the menu.
	if menu_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		capture()
		get_viewport().set_input_as_handled()
		return
	# Leave GUI events available to menu controls, but never run gameplay here.
	if menu_open: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_TAB,KEY_T]:
		if event.keycode == KEY_TAB: toggle_hand_stowed()
		else: toggle_top_down()
		get_viewport().set_input_as_handled()
		return
	if free_look:
		if event is InputEventMouseMotion:
			apply_player_look(event.relative)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				var target := ray_target(get_viewport().get_visible_rect().size/2.0)
				world_interaction_requested.emit(target,can_control(target))
				if target != null:
					if target.zone == &"deck": draw_card()
					elif can_control(target): select(target)
					else: status.text = "对方手牌 · 仅瞄准，未授权移动 / 抽取"
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and is_instance_valid(player_count_select) and player_count_select.get_popup().visible: return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN]:
		var step := Vector2.ZERO
		match event.keycode:
			KEY_LEFT: step.x = -18
			KEY_RIGHT: step.x = 18
			KEY_UP: step.y = -18
			KEY_DOWN: step.y = 18
		cancel_drag()
		if top_down: return
		if third_person: apply_observer_look(step)
		else: apply_player_look(step)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if top_down: return
		if event.pressed: cancel_drag()
		looking = event.pressed
	if event is InputEventMouseMotion and looking:
		if third_person: apply_observer_look(event.relative)
		else: apply_player_look(event.relative)
		return
	# A release is handled even over HUD so drag never becomes stuck.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if is_instance_valid(dragged): finish_drag(event.position)
		pressed = null
	if event is InputEventMouseMotion and is_instance_valid(pressed) and not is_instance_valid(dragged):
		if event.position.distance_to(press_position) > 8:
			dragged = pressed
			dragged.begin_drag()
			drag_pointer_offset = card_screen(dragged) - press_position
			place_in_world(dragged, self)
			dragged.global_basis = camera.global_basis * Basis(Vector3.RIGHT, PI/2.0)
			dragged.scale = Vector3.ONE * 0.68
			play_border.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		toggle_debug_menu()
		get_viewport().set_input_as_handled()
		return
	if menu_open: return
	if free_look and event is InputEventMouse: return
	if event is InputEventKey and is_instance_valid(player_count_select) and player_count_select.get_popup().visible: return
	if event is InputEventMouseButton and event.pressed:
		var card := pick(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if card and card.zone == &"deck":
				draw_card()
				return
			select(card,event.ctrl_pressed or event.meta_pressed)
			pressed = null if event.ctrl_pressed or event.meta_pressed else card
			press_position = event.position
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_8:
			set_active_seat(event.keycode-KEY_1)
			return
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER: play_selected()
			KEY_H: toggle_hidden()
			KEY_D: draw_card()
			KEY_F: flip_selected()
			KEY_V: toggle_view()
			KEY_R: reset_view()
			KEY_F11: showcase()
			KEY_F12: capture()

func showcase() -> void:
	set_active_seat(0)
	reset_view()
	reset()
	hand[4].set_face_up(false,false)
	var group: Array[Card3D] = [hand[0],hand[1],hand[4]]
	play_cards(group)
	draw_card()
	draw_card()
	settle_flights()
	select(played[0])
	status.text = "%d 人就位 · ? 为隐藏 / 无信息正面 · 本局座位固定" % _round_players.size()

func capture_view_name() -> String:
	return "menu" if menu_open else ("top" if top_down else ("third" if third_person else ("stowed" if hand_stowed else "first")))

func capture() -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	screenshots += 1
	var path := "res://captures/cards_%s_%02d.png"%[capture_view_name(),screenshots]
	get_viewport().get_texture().get_image().save_png(path)
	print("SCREENSHOT: ",ProjectSettings.globalize_path(path))

func deck_top_position() -> Vector3:
	var i := maxi(0, mini(deck.size()+1,12)-1)
	return DECK_ORIGIN+Vector3(0.022*i,0.05+0.055*i,0)

func flight_target(card: Card3D) -> Transform3D:
	if card in played:
		var i := played.find(card)
		var columns := mini(8,played.size())
		return Transform3D(Basis.IDENTITY,Vector3((i%8-(columns-1)/2.0)*1.95,0.12+0.002*i,-1.3+int(i/8)*2.7))
	for seat in seats:
		var cards: Array = seat.hand
		var i := cards.find(card)
		if i < 0: continue
		var center := float(i)-(cards.size()-1)/2.0
		var step := minf(1.22,6.8/maxf(1,cards.size()-1))
		var local := Transform3D(Basis(Vector3.UP,-center*0.025).scaled(Vector3.ONE*0.68),Vector3(center*step,0.02*i,absf(center)*0.025))
		return seat.anchor.global_transform * local
	return card.global_transform

func start_flight(card: Card3D, start: Transform3D, kind: String, duration: float) -> void:
	if is_instance_valid(card._motion): card._motion.kill()
	card.set_hovered(false)
	card.global_transform = start
	flights[card] = {"start":start,"elapsed":0.0,"duration":duration,"kind":kind}
	if kind == "draw": card.visual.rotation.z = PI

func advance_flights(delta: float) -> void:
	if flights.is_empty(): return
	for card in flights.keys():
		if not is_instance_valid(card):
			flights.erase(card)
			continue
		var flight: Dictionary = flights[card]
		flight.elapsed += maxf(delta,0.0)
		var t := clampf(flight.elapsed/flight.duration,0.0,1.0)
		var ease_t := t*t*(3.0-2.0*t)
		var target := flight_target(card)
		var pose: Transform3D = flight.start.interpolate_with(target,ease_t)
		# A single continuous arc with a small decaying tilt settles onto the felt.
		pose.origin.y += sin(t*PI)*(2.0 if flight.kind=="draw" else 1.5)
		pose.basis = pose.basis * Basis(Vector3.FORWARD,sin(t*PI)*0.16)
		card.global_transform = pose
		if flight.kind=="draw":
			card.visual.rotation.z = lerpf(PI,0.0 if card.face_up else PI,smoothstep(0.2,0.85,t))
		if t >= 1.0:
			card.global_transform = target
			flights.erase(card)
	var playing := false
	for flight in flights.values(): playing = playing or flight.kind=="play"
	if not playing and not _pending_play.is_empty():
		_last_play = _pending_play.duplicate(true)
		_pending_play.clear()
		refresh_last_play()
	if flights.is_empty(): update_ui()

func settle_flights() -> void:
	# Navigation completes already committed moves, rather than undoing reservations.
	advance_flights(100.0)

func last_play_snapshot() -> Dictionary:
	return _last_play.duplicate(true)

func refresh_last_play() -> void:
	if not is_instance_valid(last_play_label): return
	for child in last_play_cards.get_children():
		last_play_cards.remove_child(child)
		child.queue_free()
	if _last_play.is_empty():
		last_play_label.text = "最近出牌 · 暂无"
		return
	last_play_label.text = "最近出牌 · %s / %d 号座 · %d 张" % [_last_play.actor,_last_play.seat,_last_play.cards.size()]
	# Render only public snapshot fields. Never retain a live card or secret texture.
	var titles := ["ORBIT","BLOOM","TIDE","EMBER","ECHO","PRISM"]
	for snapshot in _last_play.cards:
		var preview := TextureRect.new()
		preview.custom_minimum_size = Vector2(52,74) if _last_play.cards.size()<=4 else Vector2(28,42)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not snapshot.face_up: preview.texture = load("res://assets/back.svg")
		elif snapshot.has("title") and titles.has(snapshot.title): preview.texture = load("res://assets/card_%d.svg" % titles.find(snapshot.title))
		else: preview.texture = Card3D.UNKNOWN_FACE
		# Explicit mipmaps keep small card-face thumbnails stable and legible.
		var source_key := preview.texture.resource_path
		if not _preview_textures.has(source_key):
			var thumb_image := preview.texture.get_image()
			if thumb_image.is_compressed(): thumb_image.decompress()
			if not thumb_image.has_mipmaps(): thumb_image.generate_mipmaps()
			_preview_textures[source_key] = ImageTexture.create_from_image(thumb_image)
		preview.texture = _preview_textures[source_key]
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		last_play_cards.add_child(preview)


func release_mouse_look() -> void:
	_menu_restore_capture = false
	free_look = false
	looking = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(crosshair): crosshair.visible = false
	if is_instance_valid(stow_button): stow_button.text = "展开手牌 Tab" if hand_stowed else "收起手牌 Tab"

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_application_focused = true
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_application_focused = false
		release_mouse_look()
		if is_instance_valid(hand_world): cancel_drag()

func toggle_hand_stowed() -> void:
	set_hand_stowed(not hand_stowed)

func set_hand_stowed(value: bool) -> void:
	clear_hover()
	if not is_instance_valid(hand_world): return
	cancel_drag()
	release_mouse_look()
	hand_stowed = value
	hand_idle = 0.0
	auto_collapsed = false
	hide_inspector()
	if value and not third_person and not top_down and not menu_open and _application_focused:
		free_look = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if is_instance_valid(crosshair): crosshair.visible = true
	if is_instance_valid(stow_button): stow_button.text = "展开手牌 Tab" if value else "收起手牌 Tab"
	if is_instance_valid(status): status.text = "自由转头 · Tab 展开 · Esc 菜单 · 左键瞄准交互" if free_look else "手牌展开 · 鼠标选牌 / 拖拽 · 不操作时自动略微收拢"
	update_hand_pose(1.0)

func position_action_bar() -> void:
	if not is_instance_valid(action_bar): return
	var inset := 22.0 if third_person or top_down else get_viewport().get_visible_rect().size.y*0.45
	action_bar.offset_top = -inset-48.0
	action_bar.offset_bottom = -inset

func update_hand_pose(delta: float) -> void:
	if not is_instance_valid(hand_world): return
	var viewport_size := get_viewport().get_visible_rect().size
	position_action_bar()
	var half_height := tan(deg_to_rad(first_camera.fov/2.0))*4.6
	var half_width := half_height*viewport_size.x/maxf(1,viewport_size.y)
	var nominal_width := maxf(1.2,(hand.size()-1)*hand_step()+1.3)
	var fit := minf(1.0,(half_width*2.0-0.6)/nominal_width)
	var interacting := is_instance_valid(dragged) or is_instance_valid(pressed) or (is_instance_valid(hovered) and hovered in hand) or not selected_cards.is_empty()
	# Keep a broad wake region so the lowered hand can always be raised naturally.
	var pointer := get_viewport().get_mouse_position()
	var wake := not third_person and not top_down and pointer.y>viewport_size.y*0.60
	hand_idle = 0.0 if interacting or wake else hand_idle+delta
	auto_collapsed = not hand_stowed and hand_idle>1.3 and not top_down and not third_person
	for seat in seats:
		var anchor: Node3D = seat.anchor
		var target_scale := 1.0
		var target_position := Vector3(0,-half_height,-4.6)
		if seat.seat_id == active_seat+1:
			target_scale = fit
			if hand_stowed:
				target_scale = minf(fit,0.30)
				target_position = Vector3(half_width-nominal_width*target_scale/2.0-0.18,-half_height+half_height*280.0/viewport_size.y+0.22,-4.6)
			elif auto_collapsed:
				target_scale = fit*0.98
		for card in seat.hand:
			card.hover_offset = Vector3(0,0.08,-1.76) if seat.seat_id == active_seat+1 and not hand_stowed and not third_person and not top_down else Vector3(0,0.14,0)
			card.hover_scale = 1.16 if seat.seat_id == active_seat+1 and not hand_stowed and not third_person and not top_down else 1.1
		anchor.position = anchor.position.lerp(target_position,minf(1.0,delta*10.0))
		anchor.scale = anchor.scale.lerp(Vector3.ONE*target_scale,minf(1.0,delta*10.0))

func fit_top_camera() -> void:
	if not is_instance_valid(top_camera): return
	var size := get_viewport().get_visible_rect().size
	top_camera.size = maxf(20.5,22.8*size.y/maxf(100.0,size.x-80.0))
	# Center the play surface within the unobstructed band above the hand toolbar.
	top_camera.position.z = top_camera.size*0.10

func set_top_down(value: bool) -> void:
	clear_hover()
	if not value:
		set_view(false)
		if is_instance_valid(top_button): top_button.text = "俯视桌面 T"
		return
	cancel_drag()
	release_mouse_look()
	hide_inspector()
	top_down = true
	third_person = false
	camera = top_camera
	fit_top_camera()
	camera.make_current()
	position_action_bar()
	for seat in seats: seat.label.visible = true
	view_label.text = "%d 人局 · %s · 座位 %d · 正俯视桌面" % [_round_players.size(),player_at_seat(active_seat+1),active_seat+1]
	top_button.text = "返回视线 T"
	view_button.text = "第三人称 V"
	status.text = "俯视桌面 · 悬停看单张 / 同组牌 · T 返回 · 其他玩家手牌只显示牌背"

func toggle_top_down() -> void:
	set_top_down(not top_down)

func refresh_viewer_faces() -> void:
	for seat in seats:
		for card in seat.hand: card.set_viewer_masked(seat.seat_id != active_seat+1)
	for card in played: card.set_viewer_masked(false)

func ray_target(screen: Vector2) -> Card3D:
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*100,1)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.collider.has_meta("card"):
		var card: Card3D = hit.collider.get_meta("card")
		if not flights.has(card): return card
	return null

func inspection_snapshot(card: Card3D) -> Dictionary:
	if not is_instance_valid(card): return {}
	if not can_control(card) or card.viewer_masked: return {"face_up":false,"description":"对方手牌"}
	var normal: Vector3 = card.visual.global_basis.y.normalized()
	if normal.dot(camera.global_position-card.global_position)<=0: return {"face_up":false,"description":"牌背"}
	return card.public_snapshot()

func inspection_group(card: Card3D) -> Array[Card3D]:
	var result: Array[Card3D] = []
	if not is_instance_valid(card) or card not in played: return result
	var id: int = card.get_meta("play_group",-1)
	for candidate in played:
		if candidate == card or (id>=0 and candidate.get_meta("play_group",-2)==id): result.append(candidate)
	return result

func build_inspector() -> void:
	inspect_panel = PanelContainer.new()
	inspect_panel.position = Vector2(38,180)
	inspect_panel.add_theme_stylebox_override("panel",style(Color("102e34ed"),10,Color("709389")))
	inspect_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(inspect_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspect_panel.add_child(column)
	inspect_title = text_label("桌面牌",16,Color("d9edda"))
	inspect_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(inspect_title)
	inspect_scroll = ScrollContainer.new()
	inspect_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspect_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inspect_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(inspect_scroll)
	inspect_grid = GridContainer.new()
	inspect_grid.columns = 3
	inspect_grid.add_theme_constant_override("h_separation",8)
	inspect_grid.add_theme_constant_override("v_separation",10)
	inspect_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspect_scroll.add_child(inspect_grid)
	inspect_panel.visible = false

func hide_inspector() -> void:
	inspect_target = null
	inspect_elapsed = 0.0
	inspect_key = ""
	if is_instance_valid(inspect_panel): inspect_panel.visible = false

func update_inspector(delta: float) -> void:
	if not is_instance_valid(inspect_panel): return
	if free_look or looking or is_instance_valid(dragged):
		hide_inspector()
		return
	var target := hovered if is_instance_valid(hovered) and hovered in played else null
	# A large group can be scrolled without the preview disappearing on entry.
	if inspect_panel.visible and inspect_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
		target = inspect_target if is_instance_valid(inspect_target) and inspect_target in played else null
	if target != inspect_target:
		hide_inspector()
		inspect_target = target
	if target == null: return
	inspect_elapsed += delta
	if inspect_elapsed<0.45: return
	var group := inspection_group(target)
	var next_key := ""
	for card in group: next_key += str(card.get_instance_id())+str(inspection_snapshot(card))
	if next_key == inspect_key and inspect_panel.visible: return
	inspect_key = next_key
	# Refresh from live public state; hidden/flip transitions never leave stale faces.
	for child in inspect_grid.get_children():
		inspect_grid.remove_child(child)
		child.queue_free()
	var available_width := maxf(180.0,get_viewport().get_visible_rect().size.x-100.0)
	inspect_grid.columns = mini(3,maxi(1,int((available_width-52.0)/158.0)))
	var visible_columns := mini(inspect_grid.columns,group.size())
	var rows := ceili(float(group.size())/inspect_grid.columns)
	inspect_scroll.custom_minimum_size = Vector2(visible_columns*158.0+14.0,minf(rows*220.0,minf(440.0,get_viewport().get_visible_rect().size.y-390.0)))
	inspect_title.text = "桌面 · %d 张同组牌%s" % [group.size()," · 滚轮查看" if rows>2 else ""] if group.size()>1 else "桌面 · "+inspection_snapshot(target).get("description","未知卡牌")
	for card in group:
		var snapshot := inspection_snapshot(card)
		var preview := TextureRect.new()
		preview.custom_minimum_size = Vector2(150,211)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.texture = card.face_texture if snapshot.has("title") else (Card3D.UNKNOWN_FACE if snapshot.get("face_up",false) else card.back_texture)
		if preview.texture != null:
			var source_key := preview.texture.resource_path
			if not _preview_textures.has(source_key):
				var thumbnail := preview.texture.get_image()
				if thumbnail.is_compressed(): thumbnail.decompress()
				if not thumbnail.has_mipmaps(): thumbnail.generate_mipmaps()
				_preview_textures[source_key] = ImageTexture.create_from_image(thumbnail)
			preview.texture = _preview_textures[source_key]
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		inspect_grid.add_child(preview)
	inspect_panel.size = Vector2.ZERO
	inspect_panel.visible = true
