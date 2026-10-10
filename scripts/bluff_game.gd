extends "res://scripts/bluff_table.gd"
const RULES = preload("res://scripts/bluff_rules.gd")
const UI = preload("res://scripts/card_ui.gd")
var game: RefCounted
var hud: Control
var modal: ColorRect
var modal_box: VBoxContainer
var turn_label: Label
var detail_label: Label
var chosen_label: Label
var play_action: Button
var selected_ids: Array=[]
var player_names: Array=[]
var rank_checks: Dictionary={}
var small_check: CheckBox
var big_check: CheckBox
var count_option: SpinBox
var settings_error: Label
var viewing_player := -1
var modal_generation := 0
var modal_kind := ""
var last_notice := ""

func _ready() -> void:
	super._ready()
	game=get_node("/root/CardSession").get_bluff()
	_build_hud()
	card_requested.connect(_choose_card)
	if game.phase=="setup": _show_settings()
	else: _handoff()
	for arg in OS.get_cmdline_user_args():
		if arg=="--bluff-demo" and game.phase=="setup":
			game.configure(4,[1,2,3,4,5,6,7,8,9,10,11,12,13],true,true,42)
			_handoff()

func _texture(record: Dictionary) -> Dictionary:
	var config := {"back":load("res://assets/blackjack/back.png")}
	if not record.has("rank"): return config
	config.face=load("res://assets/bluff/joker_%d.svg" % record.rank) if record.rank>=14 else load("res://assets/blackjack/%s_%d.png" % [record.suit,record.rank])
	return config

func _build_hud() -> void:
	var layer:=CanvasLayer.new(); layer.layer=5; add_child(layer)
	hud=Control.new(); hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.mouse_filter=Control.MOUSE_FILTER_IGNORE; hud.theme=UI.theme(); layer.add_child(hud)
	var panel:=PanelContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE); panel.offset_left=18; panel.offset_right=-18; panel.offset_top=12; panel.add_theme_stylebox_override("panel",UI.style(Color("112d36"))); hud.add_child(panel)
	var col:=VBoxContainer.new(); panel.add_child(col)
	var row:=HBoxContainer.new(); col.add_child(row)
	var title:=UI.label("吹牛牌  /  BLUFF",24,Color("f4e7bf")); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(title)
	row.add_child(_action("视角 V",toggle_view)); row.add_child(_action("俯视 T",toggle_top_down)); row.add_child(_action("菜单 Esc",_show_menu))
	turn_label=UI.label("",20); col.add_child(turn_label)
	detail_label=UI.label("",15); detail_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; col.add_child(detail_label)
	var footer:=PanelContainer.new(); footer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP); footer.offset_top=165; footer.offset_left=-310; footer.offset_right=310; footer.add_theme_stylebox_override("panel",UI.style(Color("112d36"))); hud.add_child(footer)
	var actions:=HBoxContainer.new(); footer.add_child(actions)
	chosen_label=UI.label("",16); chosen_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; actions.add_child(chosen_label)
	play_action=_action("盖牌并声明",_play,true); actions.add_child(play_action)
	actions.add_child(_action("清空",_clear_selection))
	modal=ColorRect.new(); modal.color=Color("07161bf7"); modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.add_child(modal)
	var margin:=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left",36); margin.add_theme_constant_override("margin_right",36); margin.add_theme_constant_override("margin_top",24); margin.add_theme_constant_override("margin_bottom",24); modal.add_child(margin)
	var scroll:=ScrollContainer.new(); margin.add_child(scroll)
	var center:=CenterContainer.new(); center.size_flags_horizontal=Control.SIZE_EXPAND_FILL; center.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.add_child(center)
	modal_box=VBoxContainer.new(); modal_box.custom_minimum_size.x=600; modal_box.add_theme_constant_override("separation",12); center.add_child(modal_box)

func _action(caption: String, callback: Callable, primary := false) -> Button:
	var b:=UI.button(caption,callback,primary); b.custom_minimum_size.y=42; return b

func _open_modal() -> void:
	release_mouse_look(); clear_hover(); hide_inspector(); settle_flights(); selected_ids.clear(); select(null)
	modal_generation+=1; modal_kind=""
	menu_open=true; interactions_blocked=true; modal.show()
	for child in modal_box.get_children(): modal_box.remove_child(child); child.queue_free()

func _hide_cards() -> void:
	viewing_player=-1
	if game.hands.is_empty(): return
	player_names.clear()
	for i in game.hands.size(): player_names.append("玩家 %d" % (i+1))
	present_bluff(player_names,game.public_hands(-1),game.public_pile(),_texture,-1)

func _handoff() -> void:
	_open_modal(); _hide_cards(); _update_labels()
	if game.phase=="finished":
		modal_box.add_child(UI.label("玩家 %d 获胜！" % (game.winner+1),32,Color("f4e7bf")))
		modal_box.add_child(UI.label(last_notice,17))
		modal_box.add_child(_action("再开一局 / 修改规则",_show_settings,true)); modal_box.add_child(_action("返回大厅",_lobby)); return
	var actor: int=game.current_player if game.phase=="play" else game.response_player()
	modal_box.add_child(UI.label("请将屏幕交给 玩家 %d" % (actor+1),30,Color("f4e7bf")))
	modal_box.add_child(UI.label("所有手牌已遮挡。请确认其他玩家暂时移开视线。",17))
	if not last_notice.is_empty(): modal_box.add_child(UI.label(last_notice,17))
	var token:=modal_generation
	modal_box.add_child(_action("我是玩家 %d · 查看自己的手牌" % (actor+1),func():_reveal(actor,token),true))
	modal_box.add_child(_action("菜单 / 规则",_show_menu))

func _reveal(actor: int, token := -1) -> void:
	if token != -1 and token != modal_generation: return
	if actor != (game.current_player if game.phase=="play" else game.response_player()): return
	viewing_player=actor; selected_ids.clear()
	present_bluff(player_names,game.public_hands(actor),game.public_pile(),_texture,actor)
	reset_view()
	menu_open=false; interactions_blocked=game.phase!="play"; modal.hide()
	if game.phase=="response": _show_response()
	_update_labels()

func _show_response() -> void:
	# Response decisions are public; private hands remain visible only to the
	# current owner, after a deliberate handoff. No truth hint is displayed.
	_open_modal()
	modal_box.add_child(UI.label("玩家 %d · 是否质疑？" % (viewing_player+1),28,Color("f4e7bf")))
	modal_box.add_child(UI.label("玩家 %d 刚声明 %d 张 %s。桌面共 %d 张。" % [game.current_player+1,game.latest_batch.size(),RULES.rank_label(game.declared_rank),game.pile.size()],19))
	modal_box.add_child(UI.label("质疑只翻开最近一批，判输者收走整个牌堆。",17))
	var own: Array=[]
	for card in game.hands[viewing_player]: own.append(RULES.rank_label(card.rank))
	var label:=UI.label("你的手牌："+", ".join(own),16); label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.custom_minimum_size.x=600; modal_box.add_child(label)
	var version: int=game.state_version
	modal_box.add_child(_action("质疑：你在吹牛！",func():_respond(true,version),true))
	modal_box.add_child(_action("不质疑 · 交给下一位",func():_respond(false,version)))
	modal_box.add_child(_action("菜单",_show_menu))

func _respond(challenge: bool, version: int) -> void:
	if not game.respond(viewing_player,challenge,version): return
	last_notice=""
	if challenge:
		var result: Dictionary=game.last_result
		var faces: Array=[]
		for card in result.cards: faces.append(RULES.rank_label(card.rank))
		last_notice="最近一批：%s\n%s，玩家 %d 收走 %d 张。" % [", ".join(faces),"声明属实" if result.truthful else "吹牛被抓",result.loser+1,result.count]
		_open_modal(); _hide_cards()
		modal_box.add_child(UI.label("质疑结果",30,Color("f4e7bf")))
		modal_box.add_child(UI.label(last_notice,20))
		modal_box.add_child(_action("大家已看完 · 继续",_handoff,true))
	else: _handoff()

func _choose_card(id: Variant) -> void:
	if menu_open or game.phase!="play" or viewing_player!=game.current_player: return
	if selected_ids.has(id): selected_ids.erase(id)
	elif selected_ids.size()<4: selected_ids.append(id)
	for card in hand: card.set_selected(selected_ids.has(card.data.id))
	_update_labels()

func _clear_selection() -> void:
	selected_ids.clear()
	for card in hand: card.set_selected(false)
	_update_labels()

func _play() -> void:
	if menu_open or viewing_player!=game.current_player: return
	if game.play_cards(viewing_player,selected_ids.duplicate(),game.state_version): last_notice=""; _handoff()

func _update_labels() -> void:
	if game.hands.is_empty(): return
	turn_label.text="玩家 %d · 声明 %s · %s · 暗牌堆 %d 张" % [game.current_player+1,RULES.rank_label(game.declared_rank),"等待逐位回应" if game.phase=="response" else "选择 1–4 张手牌",game.pile.size()]
	var counts: Array=[]
	for i in game.hands.size(): counts.append("玩家%d：%d张" % [i+1,game.hands[i].size()])
	detail_label.text="   ".join(counts)
	chosen_label.text="已选 %d / 4 · 点击手牌多选" % selected_ids.size()
	play_action.disabled=menu_open or game.phase!="play" or selected_ids.is_empty()

func _show_settings() -> void:
	_open_modal(); _hide_cards(); modal_kind="settings"
	modal_box.add_child(UI.label("吹牛牌 · 新局设置",30,Color("f4e7bf")))
	modal_box.add_child(UI.label("2–8 人同屏轮流操作 · 无 AI / 联机 · 开新局会替换当前局",16))
	count_option=SpinBox.new(); count_option.min_value=2; count_option.max_value=8; count_option.value=game.hands.size() if not game.hands.is_empty() else 4; modal_box.add_child(count_option)
	modal_box.add_child(UI.label("普通点数（每种 4 张）",18))
	var grid:=GridContainer.new(); grid.columns=7; modal_box.add_child(grid); rank_checks.clear()
	for rank in range(1,14):
		var check:=CheckBox.new(); check.text=RULES.rank_label(rank); check.button_pressed=game.enabled_ranks.has(rank) if game.phase!="setup" else true; grid.add_child(check); rank_checks[rank]=check
	small_check=CheckBox.new(); small_check.text="小王 · 1 张万能牌"; small_check.button_pressed=game.small_joker; modal_box.add_child(small_check)
	big_check=CheckBox.new(); big_check.text="大王 · 1 张万能牌"; big_check.button_pressed=game.big_joker; modal_box.add_child(big_check)
	settings_error=UI.label("",16,Color("ffaf91")); modal_box.add_child(settings_error)
	var token:=modal_generation
	modal_box.add_child(_action("洗牌并开始",func():_start_round(token),true))
	if game.phase!="setup": modal_box.add_child(_action("取消 · 返回本局",_handoff))
	modal_box.add_child(_action("玩法说明",_show_help)); modal_box.add_child(_action("返回大厅",_lobby))

func _start_round(token := -1) -> void:
	if modal_kind!="settings" or (token!=-1 and token!=modal_generation): return
	var ranks: Array=[]
	for rank in rank_checks:
		if rank_checks[rank].button_pressed: ranks.append(rank)
	if not game.configure(int(count_option.value),ranks,small_check.button_pressed,big_check.button_pressed): settings_error.text=game.error; return
	last_notice=""; _handoff()

func _show_menu() -> void:
	_open_modal(); _hide_cards()
	modal_box.add_child(UI.label("吹牛牌 · 暂停",30,Color("f4e7bf")))
	if game.phase!="setup": modal_box.add_child(_action("继续本局（重新交接）",_handoff,true))
	modal_box.add_child(_action("新局设置",_show_settings)); modal_box.add_child(_action("玩法说明",_show_help)); modal_box.add_child(_action("返回大厅（保留本局）",_lobby))

func _show_help() -> void:
	_open_modal(); _hide_cards()
	modal_box.add_child(UI.label("玩法说明",30,Color("f4e7bf")))
	var label:=UI.label("全部牌平均发完，玩家 1 先手。\n声明点数按启用点数从小到大循环，例如 A → 3 → K → A。\n每次盖着打出 1–4 张，系统声明当前点数，允许吹牛。\n大小王是万能牌；最近一批每张均为声明点数或王，才算真话。\n其他玩家顺时针逐位选择不质疑或质疑，没有自动超时。\n质疑仅公开最近一批：吹牛者或错误质疑者收走整个暗牌堆。\n之后由原出牌者的下一位出牌，声明推进到下个启用点数。\n所有人不质疑时，牌堆保留。空手须等全部不质疑或质疑证实后才赢。\n这是本地同屏手动交接，其他人请移开视线；本地隐藏不等于联网安全。\nV 切视角，T 俯视，R 复位，Tab 收手 / 自由转头，Esc 菜单。",17)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.custom_minimum_size.x=600; modal_box.add_child(label)
	modal_box.add_child(_action("返回菜单",_show_menu,true))

func _lobby() -> void:
	_hide_cards(); release_mouse_look(); get_tree().change_scene_to_file("res://scenes/card_lobby.tscn")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		_show_menu(); get_viewport().set_input_as_handled(); return
	super._input(event)
