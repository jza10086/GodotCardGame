extends "res://scripts/ring_card_table.gd"
## Eight independent virtual bankrolls versus one central dealer.
const RULES = preload("res://scripts/blackjack_ring_rules.gd")
const UI = preload("res://scripts/card_ui.gd")
var game: RefCounted
var hud: Control
var footer_panel: PanelContainer
var balance_label: Label
var stake_label: Label
var dealer_label: Label
var player_label: Label
var status_label: Label
var detail_label: Label
var results_label: Label
var bet_control: SpinBox
var deal_button: Button
var hit_button: Button
var stand_button: Button
var double_button: Button
var next_button: Button
var reset_button: Button
var minus_button: Button
var plus_button: Button
var modal: ColorRect
var modal_col: VBoxContainer
var dealer_clock := 0.0
var paused := false
var textures: Dictionary = {}
var peek_ids: Dictionary = {} # Retained empty for presenter compatibility; all player cards are public.
var seat_bets: Array = []
var betting_panel: PanelContainer
var seats_control: SpinBox
var dealer_mode_control: OptionButton
var probability_label: Label
var _presented_phase := ""
var controlled_player := 0
var fixture_name := ""
var _rendered_version := -1

func _ready() -> void:
	super._ready()
	game = get_node("/root/CardSession").get_blackjack_ring()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--blackjack-fixture="): fixture_name = arg.get_slice("=",1)
	if not fixture_name.is_empty() and game.phase == "betting" and game.state_version == 0: _apply_fixture(fixture_name)
	_build_ui()
	card_requested.connect(_peek_card)
	navigation_changed.connect(_close_peek)
	set_view(false)
	_sync(false)

func _apply_fixture(value: String) -> void:
	var hands:Array=[]
	var fixture_seats := 2 if value.ends_with("-2") else 8
	for i in fixture_seats:hands.append([10,10])
	value=value.trim_suffix("-2")
	var dealer:Array=[10,6]
	var extra:Array=[10,6,3,2,4,5,6,7,8,9]
	match value:
		"natural":hands[0]=[1,13]
		"both-natural":hands[0]=[1,13];dealer=[1,12]
		"dealer-natural":dealer=[1,13]
		"five":hands[0]=[2,3];dealer=[10,7];extra=[2,2,2,10,10,10]
		"five-tie":hands[0]=[2,3];dealer=[2,3];extra=[2,2,2,2,2,2]
		"bust":hands[0]=[10,10]
		"double":hands[0]=[5,6]
		"soft17":dealer=[1,6]
		"manual":dealer=[10,7];extra=[2,1,10,3,4]
	var ranks:Array=[]
	for pass_index in 2:
		for cards in hands:ranks.append(cards[pass_index])
		ranks.append(dealer[pass_index])
	ranks.append_array(extra)
	var ids:Array=[]
	for rank in ranks:
		for card in RULES.build_deck():
			if card.rank==rank and not ids.has(card.id):ids.append(card.id);break
	game.set_next_draws(ids)

func _panel(parent: Node, color := Color("102c35")) -> PanelContainer:
	var panel := PanelContainer.new(); panel.add_theme_stylebox_override("panel",UI.style(color,12)); parent.add_child(panel); return panel
func _small_button(text_value:String, callback:Callable, primary:=false) -> Button:
	var value:=UI.button(text_value,callback,primary);value.custom_minimum_size.y=40;value.add_theme_font_size_override("font_size",16);return value
func _build_ui() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	hud=Control.new();hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);hud.mouse_filter=Control.MOUSE_FILTER_IGNORE;hud.theme=UI.theme();layer.add_child(hud)
	var header:=PanelContainer.new();header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);header.offset_left=18;header.offset_right=-18;header.offset_top=12;header.add_theme_stylebox_override("panel",UI.style(Color("102c35"),12));hud.add_child(header)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",16);header.add_child(row)
	var titles:=VBoxContainer.new();titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(titles)
	titles.add_child(UI.label("21 点  /  八人环桌",24,Color("f2dfac")))
	titles.add_child(UI.label("庄家居中 · 六副牌 · 1–8 位挑战者 · AI / 玩家庄家 · 虚拟金币",14,Color("9bb8b6")))
	var bank:=VBoxContainer.new();row.add_child(bank);balance_label=UI.label("",21,Color("f1d58e"));bank.add_child(balance_label);stake_label=UI.label("",14);bank.add_child(stake_label)
	row.add_child(_small_button("视角 V",toggle_view));row.add_child(_small_button("俯视 T",toggle_top_down));row.add_child(_small_button("菜单",_open_menu));row.add_child(_small_button("大厅",_leave))
	var footer:=PanelContainer.new();footer_panel=footer;footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);footer.offset_left=18;footer.offset_right=-18;footer.offset_top=-160;footer.offset_bottom=-12;footer.add_theme_stylebox_override("panel",UI.style(Color("102c35"),12));hud.add_child(footer)
	var col:=VBoxContainer.new();col.add_theme_constant_override("separation",5);footer.add_child(col)
	status_label=UI.label("",20,Color("f4dfaa"));status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;col.add_child(status_label)
	detail_label=UI.label("",14,Color("a9c3bb"));detail_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;col.add_child(detail_label)
	probability_label=UI.label("",14,Color("d5e9db"));probability_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;col.add_child(probability_label)
	var actions:=HBoxContainer.new();actions.alignment=BoxContainer.ALIGNMENT_CENTER;actions.add_theme_constant_override("separation",8);col.add_child(actions)
	minus_button=_small_button("− 10",func():bet_control.value-=10);actions.add_child(minus_button)
	bet_control=SpinBox.new();bet_control.min_value=0;bet_control.max_value=1000;bet_control.step=10;bet_control.value=100;bet_control.custom_minimum_size=Vector2(125,40);bet_control.suffix="金币";actions.add_child(bet_control)
	plus_button=_small_button("+ 10",func():bet_control.value+=10);actions.add_child(plus_button)
	deal_button=_small_button("设置全桌下注",_open_betting,true);actions.add_child(deal_button)
	hit_button=_small_button("要牌 H",func():_act("hit"),true);actions.add_child(hit_button)
	stand_button=_small_button("停牌 S",func():_act("stand"));actions.add_child(stand_button)
	double_button=_small_button("加倍 D",func():_act("double_down"));actions.add_child(double_button)
	next_button=_small_button("下一局",func():_act("next_round"),true);actions.add_child(next_button)
	reset_button=_small_button("重置金币",_confirm_reset);actions.add_child(reset_button)
	player_label=UI.label("玩家全部明牌 · 轮流手动操作 · 右键转头 · Tab 自由看桌 · R 复位",13,Color("8cabaa"));player_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;col.add_child(player_label)
	results_label=UI.label("",14,Color("eed5a1"));results_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;col.add_child(results_label)
	dealer_label=UI.label("",14);dealer_label.hide();hud.add_child(dealer_label)
	modal=ColorRect.new();modal.color=Color(0.02,0.05,0.07,0.94);modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);hud.add_child(modal)
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);modal.add_child(center)
	var panel:=_panel(center);panel.custom_minimum_size.x=700
	modal_col=VBoxContainer.new();modal_col.add_theme_constant_override("separation",13);panel.add_child(modal_col);modal.hide()

func _texture(record: Dictionary) -> Dictionary:
	var config:Dictionary={"back":load("res://assets/blackjack/back.png"),"title":"暗牌"}
	if not record.has("rank"):return config
	var key := "%s_%d" % [record.suit,record.rank]
	if not textures.has(key):textures[key]=load("res://assets/blackjack/%s.png"%key)
	config.face=textures[key]
	var suits:Dictionary={"clubs":"梅花","diamonds":"方块","hearts":"红桃","spades":"黑桃"}
	config.title="%s %s"%[suits[record.suit],RULES.rank_label(record.rank)]
	return config
func _sync(animated := true) -> void:
	var hands:Array=[];var ids:Array=[]
	for index in game.players.size():
		var p:Dictionary=game.players[index];ids.append(str(p.id));var cards:Array=p.hand.duplicate(true)

		hands.append(cards)
	var dealer:Array=game.dealer_hand.duplicate(true)
	if not game.dealer_revealed and dealer.size()>1:dealer[1]={"id":dealer[1].id,"hidden":true}
	var deck_cards:Array=[]
	for card in game.draw_pile:deck_cards.append({"id":card.id,"hidden":true})
	bottom_hud_margin=305.0 if game.phase=="dealer" and game.dealer_mode=="human" else 185.0
	# Switch before presenting: navigation may settle old flights, never new ones.
	if game.phase == "dealer" and game.dealer_mode == "human" and _presented_phase != "dealer": set_top_down(true)
	_presented_phase = game.phase
	present_ring(ids,hands,dealer,deck_cards,_texture,animated)
	if game.phase == "player": controlled_player = game.current_player
	set_active_seat(controlled_player)
	_rendered_version=game.state_version
	_refresh()
func _refresh() -> void:
	if not is_instance_valid(balance_label) or game==null:return
	var p:Dictionary=game.players[controlled_player];var locked:bool=paused or is_animating()
	balance_label.text="%d号玩家 · 余额 %d"%[controlled_player+1,p.balance];stake_label.text="本局下注 %d · 虚拟金币"%p.bet
	var dealer_text:="玩家庄家 · 等待发牌" if game.dealer_mode == "human" else "AI庄家 · 收益最优\n等待发牌"
	if not game.dealer_hand.is_empty():dealer_text=("玩家庄家 · %s" if game.dealer_mode == "human" else "AI庄家 · %s")%(("%d 点"%RULES.hand_value(game.dealer_hand).total) if game.dealer_revealed else ("明牌 %d + 暗牌"%RULES.hand_value([game.dealer_hand[0]]).total))
	dealer_label.text=dealer_text;center_label.text=dealer_text
	for index in game.players.size():
		var seat:Dictionary=game.players[index]
		var names:Dictionary={"waiting":"待下注","playing":"行动中","stood":"已停牌","bust":"爆牌","blackjack":"天然21","five_card":"五张锁手","skipped":"未下注 / 跳过","settled":"已结算"}
		var state:String=names.get(seat.status,seat.status)
		if seat.status=="playing" and not (game.phase=="player" and game.current_player==index):state="等待行动"

		var score:=""
		if not seat.hand.is_empty():score=" · %d点"%RULES.hand_value(seat.hand).total
		if game.phase=="settled" and not seat.result.is_empty():state="净 %+d"%seat.result.net
		set_seat_label(index,"%d号 %s%s\n余额 %d · 注 %d · %s"%[index+1,"玩家",score,seat.balance,seat.bet,state])
	for i in seats.size():seats[i].label.visible=third_person or top_down or i not in [active_seat,(active_seat+1)%8,(active_seat+7)%8]
	var betting:bool=game.phase=="betting";var human_turn:bool=game.phase=="player" and game.current_player>=0
	for node in [bet_control,minus_button,plus_button]:node.visible=false
	deal_button.visible=betting;deal_button.disabled=locked;deal_button.text="设置全桌下注"

	var dealer_turn:bool=game.phase=="dealer" and game.dealer_mode=="human"
	var footer_top:float=-280.0 if dealer_turn else -160.0
	if footer_panel.offset_top!=footer_top:
		footer_panel.offset_top=footer_top
		bottom_hud_margin=-footer_top+25.0
		fit_top_camera()
	for button in [hit_button,stand_button]:button.visible=human_turn or dealer_turn;button.disabled=locked
	hit_button.text="庄家要牌 H" if dealer_turn else "要牌 H"
	stand_button.text="庄家停牌 S" if dealer_turn else "停牌 S"
	double_button.visible=human_turn
	probability_label.visible=dealer_turn
	probability_label.text=_probability_text() if dealer_turn else ""
	if dealer_turn:
		balance_label.text="你正在操作中央庄家"
		stake_label.text="八个挑战席位保留 · 虚拟金币"
		hit_button.disabled=locked or not game.can_dealer_hit()
		stand_button.disabled=locked or not game.can_dealer_stand()
	double_button.disabled=locked or not game.can_double();double_button.text="加倍 +%d D"%p.initial_bet
	next_button.visible=game.phase=="settled";next_button.disabled=locked
	reset_button.visible=game.phase in ["betting","settled"];reset_button.disabled=locked
	results_label.visible=game.phase=="settled"
	match game.phase:
		"betting":status_label.text="本地真人手动下注，轮流操作各自手牌";detail_label.text="玩家明牌 · 仅庄家一明一暗 · 天然21净2:1优先 · 五张规则"
		"player":
			status_label.text="轮到 %d号玩家  /  要牌、停牌或加倍"%(game.current_player+1)
			detail_label.text="当前玩家手牌 %d 点%s · 加倍仅限初始两张，追加同额后只补一张"%[RULES.hand_value(p.hand).total,"（软牌）" if RULES.hand_value(p.hand).soft else ""]
		"dealer":
			if game.dealer_mode=="human":
				status_label.text="轮到玩家庄家  /  手动要牌或停牌"
				detail_label.text="庄家 %d 点 · 不受17点限制 · 五张未爆或爆牌自动结算"%RULES.hand_value(game.dealer_hand).total
			else:status_label.text="中央庄家按概率决策…";detail_label.text=_advice_text()
		"settled":
			var r:Dictionary=p.result
			status_label.text="本局结算 · %d号玩家净收益 %+d"%[controlled_player+1,int(r.get("net",0))]
			detail_label.text="总下注 %d · 返还 %d（含本金） · 余额 %d"%[p.bet,int(r.get("payout",0)),p.balance]
			var parts:PackedStringArray=[]
			for i in game.players.size():parts.append("%d号 %+d"%[i+1,int(game.players[i].result.get("net",0))])
			results_label.text="   |   ".join(parts)
			if game.dealer_mode=="ai" and not game.dealer_advice.is_empty():detail_label.text += " · " + _advice_text()
			if game.dealer_mode=="human":
				var dealer_net:int=0
				var total_bets:int=0
				for seat in game.players:
					dealer_net-=int(seat.result.get("net",0))
					total_bets+=int(seat.bet)
				balance_label.text="玩家庄家 · 本局结束"
				stake_label.text="挑战者总下注 %d · 虚拟金币"%total_bets
				status_label.text="本局结算 · 庄家实际净收益 %+d"%dealer_net
				detail_label.text="各席实际输赢如下（已含天然即时结算）；下一局可更换庄家模式。"

func _probability_text() -> String:
	var distribution:Dictionary=game.next_card_probabilities()
	if distribution.remaining==0:return "剩余牌堆为空；要牌将使未结算手牌作废退款。"
	var parts:PackedStringArray=[]
	for entry in distribution.points:
		var point:String="A" if entry.point==1 else str(entry.point)
		parts.append("%s：%.1f%%"%[point,entry.probability*100.0])
	return "下一张点数概率 · 剩余 %d 张 · A计1/11，10含J/Q/K\n%s\n%s"%[distribution.remaining,"   ".join(parts.slice(0,5)),"   ".join(parts.slice(5,10))]

func _advice_text() -> String:
	if game.dealer_mode=="human":return ""
	var advice:Dictionary=game.dealer_advice
	if advice.is_empty():return "只按剩余牌概率计算，不读取未来顺序。"
	var hit_text:String="不可要牌" if advice.hit_ev==null else "%+.2f"%float(advice.hit_ev)
	return "庄家未结算注EV：停 %+.2f / 要 %s → %s（金币）"%[float(advice.stand_ev),hit_text,"要牌" if advice.action=="hit" else "停牌"]

func _peek_card(_id:Variant) -> void:
	pass # Players are public; dealer hole card never responds to clicks.
func _close_peek() -> void:
	peek_ids.clear()

func set_active_seat(index: int) -> bool:
	if index < 0 or index >= seats.size(): return false
	active_seat = index
	player_rig = seats[index].rig
	first_camera = seats[index].camera
	hand_world = seats[index].anchor
	hand = seats[index].hand
	player_yaw = float(seats[index].yaw)
	player_pitch = deg_to_rad(-54.0)
	if not third_person and not top_down:
		camera=first_camera
		camera.make_current()
	player_rig.rotation=Vector3(player_pitch,player_yaw,0)
	clear_hover()
	return true

func _open_betting() -> void:
	if paused or is_animating() or game.phase != "betting": return
	paused=true;menu_open=true;release_mouse_look();_clear_modal();modal.show()
	modal_col.add_child(UI.label("全桌手动下注 · 0 表示跳过",26,Color("f4dfaa")))
	var mode_row := HBoxContainer.new();modal_col.add_child(mode_row)
	mode_row.add_child(UI.label("本局庄家",17))
	dealer_mode_control=OptionButton.new();dealer_mode_control.add_item("AI庄家");dealer_mode_control.add_item("玩家庄家（手动要牌 / 停牌）");dealer_mode_control.select(1 if game.dealer_mode=="human" else 0);mode_row.add_child(dealer_mode_control)
	var count_row := HBoxContainer.new();modal_col.add_child(count_row)
	count_row.add_child(UI.label("挑战者席位数",17))
	seats_control=SpinBox.new();seats_control.min_value=1;seats_control.max_value=8;seats_control.value=2 if fixture_name.ends_with("-2") else 8;count_row.add_child(seats_control)
	count_row.add_child(_small_button("全部填100（按余额）",func():
		for i in 8: seat_bets[i].value=mini(100,int(game.players[i].balance/10)*10) if i<int(seats_control.value) else 0))
	seat_bets.clear()
	var grid := GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",28);modal_col.add_child(grid)
	for i in 8:
		var row := HBoxContainer.new();grid.add_child(row)
		row.add_child(UI.label("%d号 · 余额 %d"%[i+1,game.players[i].balance],17))
		var amount := SpinBox.new();amount.min_value=0;amount.max_value=int(game.players[i].balance/10)*10;amount.step=10;amount.value=0;amount.custom_minimum_size.x=125;row.add_child(amount);seat_bets.append(amount);amount.editable=i<int(seats_control.value)
	seats_control.value_changed.connect(func(value:float):
		for i in 8:
			seat_bets[i].editable=i<int(value)
			if i>=int(value):seat_bets[i].value=0)
	modal_col.add_child(UI.label("每席独立金币。请填写金额或明确批量填入，再一次确认发牌。
无人下注无法开始；不会自动补充金币或替玩家操作。",16))
	modal_col.add_child(_small_button("确认全桌下注并发牌",_deal,true))
	modal_col.add_child(_small_button("取消",_close_menu))
func _deal() -> void:
	if not paused or not modal.visible or is_animating() or game.phase != "betting" or seat_bets.size()!=8:return
	if not is_instance_valid(dealer_mode_control) or not dealer_mode_control.is_inside_tree():return
	var stakes:Array=[]
	for value in seat_bets:value.apply();stakes.append(int(value.value))
	var result:Dictionary=game.start_round(stakes,_rendered_version,"human" if dealer_mode_control.selected==1 else "ai")
	if result.ok:_close_menu();_accept(result)
	else:
		var error := UI.label(result.message,16,Color("ffaaa0"));modal_col.add_child(error)
func _act(command:String) -> void:
	if paused or is_animating():return
	if command in ["hit","stand"] and game.phase=="dealer" and game.dealer_mode=="human":command="dealer_"+command
	if command in ["hit","stand","double_down"] and (game.phase!="player" or game.current_player<0):return
	_accept(game.call(command,_rendered_version))
func _accept(result:Dictionary) -> void:
	if result.ok:dealer_clock=0;_sync()
	else:_refresh();detail_label.text=result.get("message","操作未生效")
func _process(delta:float) -> void:
	if paused:return
	super._process(delta)
	if game==null:return
	_refresh()
	if is_animating():return
	if game.phase!="dealer" or game.dealer_mode!="ai":return
	dealer_clock+=delta
	if dealer_clock>=0.85:_act("dealer_step")
func _clear_modal() -> void:
	for child in modal_col.get_children():modal_col.remove_child(child);child.queue_free()
func _open_menu() -> void:
	_close_peek();paused=true;menu_open=true;release_mouse_look();_clear_modal();modal.show()
	modal_col.add_child(UI.label("八人环桌 / 本地真人与庄家",26,Color("f4dfaa")))
	modal_col.add_child(UI.label("1–8位本地挑战者与中央庄家，共用设备轮流手动操作。\n六副标准牌共312张，局内不回收；A计1/11，人头牌计10。\n美式：玩家全明，庄家一明一暗，起手预检天然21。\n玩家天然21优先独立支付净2:1，双方天然也玩家胜。\n普通胜净1:1，和局退本金。加倍补一张后停牌。",17))
	modal_col.add_child(UI.label("玩家五张未爆锁手：胜普通庄家；双方五张未爆平局。\n庄家五张未爆胜普通玩家；爆牌优先判负。\n天然21已支付，不再参与末结算。\n庄家可选AI或玩家；两局之间在下注面板切换。\nAI按剩余牌概率最大化净收益；玩家庄家自由要牌/停牌，\n仅显示下一张点数概率，不显示期望收益或行动建议。",16,Color("a9c3bb")))
	modal_col.add_child(UI.label("V 第一/第三视角 · T 中心俯视 · Tab 自由看桌 · R 复位\n离桌保留整桌牌局和余额；关闭程序结束会话。金币无真实价值。",15))
	modal_col.add_child(_small_button("继续游戏",_close_menu,true));modal_col.add_child(_small_button("返回大厅（保留整桌）",_leave))
	var reset:=_small_button("重置全桌金币为1000…",_confirm_reset);reset.disabled=game.phase not in ["betting","settled"];modal_col.add_child(reset)
func _close_menu() -> void:
	paused=false;menu_open=false;modal.hide();_refresh()
func _confirm_reset() -> void:
	if game.phase not in ["betting","settled"]:return
	_close_peek();paused=true;menu_open=true;release_mouse_look();_clear_modal();modal.show()
	modal_col.add_child(UI.label("重置全桌金币会话？",26,Color("f4dfaa")))
	modal_col.add_child(UI.label("八位玩家的余额将分别替换为1000，已结束牌局清除。\n不是累加赠送；取消会完整保留当前状态。",17))
	modal_col.add_child(_small_button("取消",_close_menu));modal_col.add_child(_small_button("确认重置为 1000",func():var result:Dictionary=game.reset_bankroll(_rendered_version);_close_menu();_accept(result),true))
func _leave() -> void:
	_close_peek();release_mouse_look();get_tree().change_scene_to_file("res://scenes/card_lobby.tscn")
func _unhandled_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if paused:_close_menu()
				else:_open_menu()
				get_viewport().set_input_as_handled();return
			KEY_H:_act("hit");get_viewport().set_input_as_handled();return
			KEY_S:_act("stand");get_viewport().set_input_as_handled();return
			KEY_D:_act("double_down");get_viewport().set_input_as_handled();return
	super._unhandled_input(event)
