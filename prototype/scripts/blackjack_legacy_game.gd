extends "res://scripts/public_card_table.gd"
## Adapter: rules own money; the table owns presentation; this owns user intent.
const RULES = preload("res://scripts/blackjack_rules.gd")
const UI = preload("res://scripts/card_ui.gd")
var game: RefCounted
var hud: Control
var balance_label: Label
var stake_label: Label
var dealer_label: Label
var player_label: Label
var status_label: Label
var detail_label: Label
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
var fixture_name := ""

func _ready() -> void:
	super._ready()
	game = get_node("/root/CardSession").get_blackjack()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--blackjack-fixture="): fixture_name = arg.get_slice("=",1)
	if not fixture_name.is_empty() and game.phase == "betting" and game.state_version == 0:
		_apply_fixture(fixture_name)
	_build_table_props()
	_build_ui()
	_sync(false)

func _build_table_props() -> void:
	for i in 4:
		var card:Card3D=CARD_SCENE.instantiate()
		card.configure({"back":load("res://assets/blackjack/back.png"),"face_up":false})
		add_child(card);card.position=source_position+Vector3(0,i*0.055,0)
	for pile in 3:
		for i in 3+pile:
			var chip:=MeshInstance3D.new();var shape:=CylinderMesh.new()
			shape.top_radius=0.37;shape.bottom_radius=0.37;shape.height=0.09
			chip.mesh=shape;chip.position=Vector3(-7.0+pile*0.7,0.08+i*0.095,-0.25+pile*0.4)
			var mat:=StandardMaterial3D.new();mat.albedo_color=[Color("bfaa71"),Color("d6ded0"),Color("b55b57")][pile];mat.roughness=0.7
			chip.material_override=mat;add_child(chip)

func _apply_fixture(value: String) -> void:
	# QA-only deterministic first draw sequence. No normal gameplay reset path.
	var fixtures := {"double":[4,8,18,6,9,5], "natural":[0,8,12,6], "dealer-natural":[8,0,6,12], "push":[9,22,12,25], "bust":[9,4,11,6,8], "soft17":[9,0,6,5]}
	if fixtures.has(value): game.set_next_draws(fixtures[value])
	if value == "bankrupt":
		game.balance = 10
		game.set_next_draws([9,4,11,6,8])

func _panel(parent: Node, color := Color("102c35")) -> PanelContainer:
	var panel := PanelContainer.new(); panel.add_theme_stylebox_override("panel",UI.style(color,16)); parent.add_child(panel); return panel

func _build_ui() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	hud = Control.new(); hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.mouse_filter=Control.MOUSE_FILTER_IGNORE; hud.theme=UI.theme(); layer.add_child(hud)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.offset_left=28; margin.offset_right=-28; margin.offset_top=24; hud.add_child(margin)
	var header := _panel(margin)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",22); header.add_child(row)
	var titles := VBoxContainer.new(); titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(titles)
	titles.add_child(UI.label("TWENTY ONE   /   21 点",29,Color("f2dfac")))
	titles.add_child(UI.label("一副牌 · AI 庄家 · 软 / 硬 17 停牌",15,Color("9bb8b6")))
	var bank := VBoxContainer.new(); row.add_child(bank)
	balance_label=UI.label("",24,Color("f1d58e")); bank.add_child(balance_label)
	stake_label=UI.label("",15);bank.add_child(stake_label)
	row.add_child(UI.button("规则 / 菜单",_open_menu))
	row.add_child(UI.button("返回大厅",_leave))
	dealer_label=UI.label("",22,Color("e6dbb8")); dealer_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	dealer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);dealer_label.offset_top=185;hud.add_child(dealer_label)
	player_label=UI.label("",22,Color("e6dbb8"));player_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	player_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);player_label.anchor_top=0.685;player_label.anchor_bottom=0.685;hud.add_child(player_label)
	var footer := PanelContainer.new(); footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left=28;footer.offset_right=-28;footer.offset_top=-204;footer.offset_bottom=-24
	footer.add_theme_stylebox_override("panel",UI.style(Color("102c35"),16));hud.add_child(footer)
	var col := VBoxContainer.new();col.add_theme_constant_override("separation",10);footer.add_child(col)
	status_label=UI.label("",23,Color("f4dfaa"));status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;col.add_child(status_label)
	detail_label=UI.label("",15,Color("a9c3bb"));detail_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;col.add_child(detail_label)
	var actions := HBoxContainer.new();actions.alignment=BoxContainer.ALIGNMENT_CENTER;actions.add_theme_constant_override("separation",10);col.add_child(actions)
	minus_button=UI.button("− 10",func():bet_control.value-=10);actions.add_child(minus_button)
	bet_control=SpinBox.new();bet_control.min_value=10;bet_control.max_value=1000;bet_control.step=10;bet_control.value=100;bet_control.custom_minimum_size=Vector2(135,52);bet_control.suffix="金币";actions.add_child(bet_control)
	plus_button=UI.button("+ 10",func():bet_control.value+=10);actions.add_child(plus_button)
	deal_button=UI.button("下注并发牌",_deal,true);actions.add_child(deal_button)
	hit_button=UI.button("要牌  H",func():_act("hit"),true);actions.add_child(hit_button)
	stand_button=UI.button("停牌  S",func():_act("stand"));actions.add_child(stand_button)
	double_button=UI.button("加倍  D",func():_act("double_down"));actions.add_child(double_button)
	next_button=UI.button("下一局",func():_act("next_round"),true);actions.add_child(next_button)
	reset_button=UI.button("重置金币",_confirm_reset);actions.add_child(reset_button)
	var note:=UI.label("加倍：再下等额，只补一张后停牌  ·  A 自动计 1 / 11  ·  金币无真实价值",13,Color("8cabaa"));note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;col.add_child(note)
	modal=ColorRect.new();modal.color=Color(0.02,0.05,0.07,0.9);modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);hud.add_child(modal)
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);modal.add_child(center)
	var panel:=_panel(center);panel.custom_minimum_size.x=660
	modal_col=VBoxContainer.new();modal_col.add_theme_constant_override("separation",16);panel.add_child(modal_col);modal.hide()

func _texture(record: Dictionary, hidden: bool) -> Dictionary:
	var config := {"back":load("res://assets/blackjack/back.png"),"title":"牌背"}
	if not hidden:
		var key := "%s_%d" % [record.suit,record.rank]
		if not textures.has(key): textures[key]=load("res://assets/blackjack/%s.png" % key)
		config.face=textures[key]
		var suits:Dictionary={"clubs":"梅花","diamonds":"方块","hearts":"红桃","spades":"黑桃"}
		var ranks:Dictionary={1:"A",11:"J",12:"Q",13:"K"}
		config.title="%s %s" % [suits[record.suit],ranks.get(record.rank,str(record.rank))]
	return config

func _sync(animated := true) -> void:
	var dealer: Array=game.dealer_hand.duplicate(true)
	if game.phase=="player" and dealer.size()>1: dealer[1]={"id":dealer[1].id,"hidden":true}
	present_rows([{"cards":dealer,"z":-2.5,"zone":"dealer","card_scale":1.65,"max_width":15.0},{"cards":game.player_hand,"z":2.2,"zone":"player","card_scale":1.65,"max_width":15.0}],_texture,animated)
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(balance_label):return
	var locked := paused or is_animating()
	var betting:bool=game.phase=="betting"
	balance_label.text="余额  %d" % game.balance
	stake_label.text="桌上下注  %d  ·  虚拟金币" % game.bet
	if game.dealer_hand.is_empty():dealer_label.text="AI 庄家  /  等待发牌"
	elif game.phase=="player":dealer_label.text="AI 庄家  /  明牌 %d + 暗牌" % RULES.hand_value([game.dealer_hand[0]]).total
	else:dealer_label.text="AI 庄家  /  %d 点" % RULES.hand_value(game.dealer_hand).total
	player_label.text="你的牌区" if game.player_hand.is_empty() else "你  /  %d 点%s" % [RULES.hand_value(game.player_hand).total," · 软牌" if RULES.hand_value(game.player_hand).soft else ""]
	var playing:bool=game.phase=="player"
	deal_button.visible=betting;bet_control.visible=betting;minus_button.visible=betting;plus_button.visible=betting
	bet_control.max_value=maxi(10,(game.balance/10)*10)
	bet_control.editable=betting and not locked and game.balance>=10
	deal_button.disabled=locked or game.balance<10
	minus_button.disabled=locked or bet_control.value<=10;plus_button.disabled=locked or bet_control.value>=bet_control.max_value
	hit_button.visible=playing;stand_button.visible=playing;double_button.visible=playing
	hit_button.disabled=locked;stand_button.disabled=locked;double_button.disabled=locked or not game.can_double()
	double_button.text="加倍 +%d  D" % game.initial_bet
	next_button.visible=game.phase=="settled" and game.balance>=10;next_button.disabled=locked
	reset_button.visible=game.phase in ["settled","betting"] and game.balance<10;reset_button.disabled=locked
	match game.phase:
		"betting":
			status_label.text="选择下注，开始新的一局" if game.balance>=10 else "金币不足 10，暂时无法下注"
			detail_label.text="最少 10，按 10 递增。确认发牌即扣除下注。" if game.balance>=10 else "可明确重置为 1000 金币，再开始新的会话。"
		"player":
			status_label.text="轮到你了  /  要牌，还是停牌？"
			detail_label.text="加倍仅限前两张、尚未行动且余额足够。" if game.can_double() else "当前不能加倍；要牌后或余额不足时不可加倍。"
		"dealer":status_label.text="庄家行动中…";detail_label.text="庄家亮出暗牌，16 及以下要牌，17 及以上停牌。"
		"settled":
			var names:Dictionary={"bust":"你爆牌了","void":"牌堆异常，本局作废","win":"你赢了","loss":"庄家获胜","lose":"庄家获胜","push":"和局","blackjack":"天生 21 点！","player_blackjack":"天生 21 点！","dealer_blackjack":"庄家天生 21 点"}
			status_label.text="%s  /  本局净收益 %+d" % [names.get(game.result.outcome,game.result.outcome),game.result.net]
			detail_label.text="总下注 %d · 返还 %d（含本金） · 余额 %d%s" % [game.result.bet,game.result.payout,game.balance," · 金币不足，请重置后再玩" if game.balance<10 else ""]

func _deal() -> void:
	if paused or is_animating():return
	bet_control.apply()
	var result:Dictionary=game.start_round(int(bet_control.value),game.state_version)
	_accept(result)
func _act(command: String) -> void:
	if paused or is_animating():return
	_accept(game.call(command,game.state_version))
func _accept(result: Dictionary) -> void:
	if result.ok:
		dealer_clock=0;_sync()
	else:
		_refresh();detail_label.text=result.get("message","操作未生效")
func _process(delta: float) -> void:
	super._process(delta)
	if game==null:return
	_refresh()
	if game.phase!="dealer" or paused or is_animating():return
	dealer_clock+=delta
	if dealer_clock>=0.8:_act("dealer_step")
func _clear_modal() -> void:
	for child in modal_col.get_children():modal_col.remove_child(child);child.queue_free()
func _open_menu() -> void:
	paused=true;_clear_modal();modal.show()
	modal_col.add_child(UI.label("21 点  /  规则与会话",28,Color("f4dfaa")))
	modal_col.add_child(UI.label("A 自动计 1 或 11；J / Q / K 计 10。\n庄家 16 及以下要牌，软 / 硬 17 停牌。\n普通赢牌净赚 1:1；天生 21 点净赚 3:2；和局退本金。\n庄家会先检查天生 21 点，再开放你的操作。\n本版不含分牌、保险或投降。",18))
	modal_col.add_child(UI.label("返回大厅保留牌局与余额，再进入可继续。\n关闭程序结束本次会话；没有存档与真实货币。",16,Color("a9c3bb")))
	modal_col.add_child(UI.button("继续游戏",_close_menu,true))
	modal_col.add_child(UI.button("返回大厅（保留本局）",_leave))
	var reset:=UI.button("重置金币为 1000…",_confirm_reset);reset.disabled=game.phase not in ["betting","settled"];modal_col.add_child(reset)
	if reset.disabled:modal_col.add_child(UI.label("当前局未结算，不能重置金币。",15))
func _close_menu() -> void:
	paused=false;modal.hide();_refresh()
func _confirm_reset() -> void:
	if game.phase not in ["betting","settled"]:return
	paused=true;_clear_modal();modal.show()
	modal_col.add_child(UI.label("重置这次金币会话？",28,Color("f4dfaa")))
	modal_col.add_child(UI.label("当前余额将被替换为 1000，已结束的牌局会清除。\n这是明确的新会话操作，不会累加赠送金币。",18))
	modal_col.add_child(UI.button("取消",_close_menu))
	modal_col.add_child(UI.button("确认重置为 1000",func():
		var result:Dictionary=game.reset_bankroll(game.state_version)
		_close_menu();_accept(result),true))
func _leave() -> void:
	get_tree().change_scene_to_file("res://scenes/card_lobby.tscn")
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if paused:_close_menu()
				else:_open_menu()
			KEY_H:_act("hit")
			KEY_S:_act("stand")
			KEY_D:_act("double_down")
