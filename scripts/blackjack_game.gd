extends "res://scripts/ring_card_table.gd"
## Eight independent virtual bankrolls versus one central dealer.
const RULES = preload("res://scripts/blackjack_ring_rules.gd")
const UI = preload("res://scripts/card_ui.gd")
var game: RefCounted
var hud: Control
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
var peek_ids: Dictionary = {}
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
	_sync(false)
	set_view(false)

func _apply_fixture(value: String) -> void:
	# Deal order is eight seats then dealer, repeated twice. Physical IDs unique.
	var opening: Array = [4,22,35,48,61,74,87,100,8,18,114,127,140,153,166,179,192,6]
	match value:
		"natural": opening[0]=0; opening[9]=12
		"dealer-natural": opening[8]=0; opening[17]=12
		"bankrupt": game.players[0].balance=10; opening[0]=9; opening[9]=11
		"bust": opening[0]=9; opening[9]=11
		"push": opening[0]=9; opening[9]=12; opening[8]=25; opening[17]=38
		"soft17": opening[8]=0; opening[17]=5
	opening.append_array([9,5,21,34,47,60,73,86,99,112,125,138,151,164,177,190])
	# Fixture variants may overlap a tail id; retain one physical copy only.
	var unique: Array = []
	for id in opening:
		if not unique.has(id): unique.append(id)
	game.set_next_draws(unique)

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
	titles.add_child(UI.label("庄家居中 · 六副牌 · 1 位真人 + 7 位 AI · 虚拟金币",14,Color("9bb8b6")))
	var bank:=VBoxContainer.new();row.add_child(bank);balance_label=UI.label("",21,Color("f1d58e"));bank.add_child(balance_label);stake_label=UI.label("",14);bank.add_child(stake_label)
	row.add_child(_small_button("视角 V",toggle_view));row.add_child(_small_button("俯视 T",toggle_top_down));row.add_child(_small_button("菜单",_open_menu));row.add_child(_small_button("大厅",_leave))
	var footer:=PanelContainer.new();footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);footer.offset_left=18;footer.offset_right=-18;footer.offset_top=-160;footer.offset_bottom=-12;footer.add_theme_stylebox_override("panel",UI.style(Color("102c35"),12));hud.add_child(footer)
	var col:=VBoxContainer.new();col.add_theme_constant_override("separation",5);footer.add_child(col)
	status_label=UI.label("",20,Color("f4dfaa"));status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;col.add_child(status_label)
	detail_label=UI.label("",14,Color("a9c3bb"));detail_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;col.add_child(detail_label)
	var actions:=HBoxContainer.new();actions.alignment=BoxContainer.ALIGNMENT_CENTER;actions.add_theme_constant_override("separation",8);col.add_child(actions)
	minus_button=_small_button("− 10",func():bet_control.value-=10);actions.add_child(minus_button)
	bet_control=SpinBox.new();bet_control.min_value=10;bet_control.max_value=1000;bet_control.step=10;bet_control.value=100;bet_control.custom_minimum_size=Vector2(125,40);bet_control.suffix="金币";actions.add_child(bet_control)
	plus_button=_small_button("+ 10",func():bet_control.value+=10);actions.add_child(plus_button)
	deal_button=_small_button("下注并发牌",_deal,true);actions.add_child(deal_button)
	hit_button=_small_button("要牌 H",func():_act("hit"),true);actions.add_child(hit_button)
	stand_button=_small_button("停牌 S",func():_act("stand"));actions.add_child(stand_button)
	double_button=_small_button("加倍 D",func():_act("double_down"));actions.add_child(double_button)
	next_button=_small_button("下一局",func():_act("next_round"),true);actions.add_child(next_button)
	reset_button=_small_button("重置金币",_confirm_reset);actions.add_child(reset_button)
	player_label=UI.label("点击自己的暗牌查看 / 再点盖回 · 其他暗牌结算才亮 · 右键转头 · Tab 自由看桌 · R 复位",13,Color("8cabaa"));player_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;col.add_child(player_label)
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
		if game.phase!="settled" and cards.size()>1:
			if index==0:cards[1].private_hidden=true;cards[1].peek=peek_ids.has(cards[1].id)
			else:cards[1]={"id":cards[1].id,"hidden":true}
		hands.append(cards)
	var dealer:Array=game.dealer_hand.duplicate(true)
	if not game.dealer_revealed and dealer.size()>1:dealer[1]={"id":dealer[1].id,"hidden":true}
	var deck_cards:Array=[]
	for card in game.draw_pile:deck_cards.append({"id":card.id,"hidden":true})
	present_ring(ids,hands,dealer,deck_cards,_texture,animated)
	_rendered_version=game.state_version
	_refresh()
func _refresh() -> void:
	if not is_instance_valid(balance_label) or game==null:return
	var p:Dictionary=game.players[0];var locked:bool=paused or is_animating()
	balance_label.text="你的余额 %d"%p.balance;stake_label.text="本局下注 %d · 虚拟金币"%p.bet
	var dealer_text:="庄家 · S17\n等待发牌"
	if not game.dealer_hand.is_empty():dealer_text="庄家 · %s"%(("%d 点"%RULES.hand_value(game.dealer_hand).total) if game.dealer_revealed else ("明牌 %d + 暗牌"%RULES.hand_value([game.dealer_hand[0]]).total))
	dealer_label.text=dealer_text;center_label.text=dealer_text
	for index in game.players.size():
		var seat:Dictionary=game.players[index]
		var names:Dictionary={"waiting":"待下注","playing":"行动中","stood":"已停牌","bust":"爆牌","blackjack":"天生21","skipped":"余额不足 / 跳过","settled":"已结算"}
		var state:String=names.get(seat.status,seat.status)
		if seat.status=="playing" and not (game.phase=="player" and game.current_player==index):state="等待行动"
		# Opponents' natural/bust state can reveal information, so show only public action.
		if index>0 and game.phase!="settled" and state=="天生21":state="已停牌"
		var score:=""
		if not seat.hand.is_empty() and (index==0 or game.phase=="settled"):score=" · %d点"%RULES.hand_value(seat.hand).total
		if game.phase=="settled" and not seat.result.is_empty():state="净 %+d"%seat.result.net
		set_seat_label(index,"%d号 %s%s\n余额 %d · 注 %d · %s"%[index+1,"你" if index==0 else "AI",score,seat.balance,seat.bet,state])
	var betting:bool=game.phase=="betting";var human_turn:bool=game.phase=="player" and game.current_player==0
	for node in [bet_control,minus_button,plus_button]:node.visible=betting and p.balance>=10
	deal_button.visible=betting;deal_button.disabled=locked;deal_button.text="旁观本局" if p.balance<10 else "下注并发牌"
	bet_control.max_value=maxi(10,int(p.balance/10)*10);bet_control.editable=not locked
	minus_button.disabled=locked or bet_control.value<=10;plus_button.disabled=locked or bet_control.value>=bet_control.max_value
	for button in [hit_button,stand_button,double_button]:button.visible=human_turn;button.disabled=locked
	double_button.disabled=locked or not game.can_double();double_button.text="加倍 +%d D"%p.initial_bet
	next_button.visible=game.phase=="settled";next_button.disabled=locked
	reset_button.visible=game.phase in ["betting","settled"] and p.balance<10;reset_button.disabled=locked
	results_label.visible=game.phase=="settled"
	match game.phase:
		"betting":status_label.text="选择下注，八位玩家分别与中央庄家比牌";detail_label.text="每方初始一明一暗 · 你可以点击自己的暗牌查看 · AI 每局下注至多100"
		"player":
			status_label.text="轮到你了  /  要牌、停牌或加倍" if human_turn else "%d号 AI 正在思考…"%(game.current_player+1)
			detail_label.text="你的手牌 %d 点%s · 加倍仅限初始两张，追加同额后只补一张"%[RULES.hand_value(p.hand).total,"（软牌）" if RULES.hand_value(p.hand).soft else ""]
		"dealer":status_label.text="中央庄家行动中…";detail_label.text="16及以下要牌；软17、硬17都停牌。各玩家独立结算。"
		"settled":
			var r:Dictionary=p.result
			status_label.text="本局结算 · 你的净收益 %+d"%int(r.get("net",0))
			detail_label.text="总下注 %d · 返还 %d（含本金） · 余额 %d"%[p.bet,int(r.get("payout",0)),p.balance]
			var parts:PackedStringArray=[]
			for i in game.players.size():parts.append("%d号 %+d"%[i+1,int(game.players[i].result.get("net",0))])
			results_label.text="   |   ".join(parts)

func _peek_card(id:Variant) -> void:
	if paused or is_animating() or game.phase=="settled":return
	var cards:Array=game.players[0].hand
	if cards.size()<2 or cards[1].id!=id:return
	if peek_ids.has(id):peek_ids.erase(id)
	else:peek_ids[id]=true
	_sync(false)
func _close_peek() -> void:
	if peek_ids.is_empty():return
	peek_ids.clear()
	if game!=null:_sync(false)
func _deal() -> void:
	if paused or is_animating():return
	bet_control.apply();_accept(game.start_round(0 if game.players[0].balance<10 else int(bet_control.value),_rendered_version))
func _act(command:String) -> void:
	if paused or is_animating():return
	if command in ["hit","stand","double_down"] and (game.phase!="player" or game.current_player!=0):return
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
	if game.phase!="dealer" and not (game.phase=="player" and game.current_player>0):return
	dealer_clock+=delta
	if dealer_clock>=0.85:_act("dealer_step" if game.phase=="dealer" else "ai_step")
func _clear_modal() -> void:
	for child in modal_col.get_children():modal_col.remove_child(child);child.queue_free()
func _open_menu() -> void:
	_close_peek();paused=true;menu_open=true;release_mouse_look();_clear_modal();modal.show()
	modal_col.add_child(UI.label("八人环桌 / 规则与 AI",26,Color("f4dfaa")))
	modal_col.add_child(UI.label("八方各有独立金币、下注与结算，庄家在中央。\n六副标准牌共312张，局内不回收；A计1/11，人头牌计10。\n普通胜净赚1:1，天生21净赚3:2，和局退本金。\n标准加倍只限初始两张，追加同额、补一张后停牌。\n庄家先查天生21；16及以下要牌，软/硬17均停。",17))
	modal_col.add_child(UI.label("AI只看自己的牌、庄家明牌和自己余额。\n按硬牌/软牌基础策略选择要牌、停牌或加倍。\n不看其他暗牌、庄家暗牌或未来牌序，不分牌/保险/投降。\n每方初始一明一暗，补牌明置，结算全亮。",16,Color("a9c3bb")))
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
