extends "res://scripts/rules_table.gd"
## Game-specific controller. Rules and the reusable 3D host remain separate.
const RULES = preload("res://scripts/uno_rules.gd")
const COLORS := ["red", "yellow", "green", "blue"]
const COLOR_NAMES := {"red":"红", "yellow":"黄", "green":"绿", "blue":"蓝", "wild":"万能"}
const COLOR_INKS := {"red":Color("e85c69"), "yellow":Color("efbd53"), "green":Color("45b696"), "blue":Color("598ddd")}
var game = RULES.new()
var players: Array = []
var textures: Dictionary = {}
var hud: Control
var turn_label: Label
var detail_label: Label
var color_indicator: Label
var event_label: Label
var roster: VBoxContainer
var action_row: HBoxContainer
var draw_action: Button
var pass_action: Button
var uno_action: Button
var catch_action: Button
var penalty_action: Button
var accept_action: Button
var challenge_action: Button
var jump_check: CheckBox
var announce_check: CheckBox
var modal: ColorRect
var modal_box: VBoxContainer
var count_option: OptionButton
var pending_card_id: Variant = null
var paused := false
var choosing := false
var bot_clock := 0.0
var bot_delay := 1.65
var game_started := false
var launch_seed := -1
var round_count := 0
var last_message := ""
var round_hand_size := 7
var hand_size_option: SpinBox
var hand_size_hint: Label
var human_catch_clock := 0.0
var rules_label: Label
const OPTION_LABELS := {
	"continuous_draw": "持续抽牌：无牌可出时摸到能出，并立即打出",
	"jump_in": "抢牌：同色同数字 / 功能可抢出，替代上一张效果",
	"stacking": "+2 叠加：可接 +2 / +4，接 +4 后只能再接 +4",
	"forbid_last_wild": "禁止最后万能牌：只剩万能牌时强制摸一张",
}
var round_options: Dictionary = {}
var option_checks: Dictionary = {}
var jump_clocks: Dictionary = {}
var reaction_serial := 0
var rendered_version := 0
var seen_reaction_card := -1

func _ready() -> void:
	super._ready()
	_build_game_ui()
	card_requested.connect(_human_card)
	draw_requested.connect(_human_draw)
	var launch_players:=4
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--uno-seed="):launch_seed=int(arg.get_slice("=",1))
		if arg.begins_with("--uno-players="):launch_players=clampi(int(arg.get_slice("=",1)),2,8)
	_start_game(launch_players)

func _texture(card: Dictionary) -> Dictionary:
	var key := "%s_%s" % [card.color,card.value]
	if not textures.has(key): textures[key] = load("res://assets/uno/%s.png" % key)
	return {"face":textures[key],"back":load("res://assets/uno/back.png")}

func _card_title(card: Dictionary) -> String:
	var names := {"skip":"跳过", "reverse":"反转", "draw_two":"+2", "wild":"换色", "draw_four":"+4"}
	return "%s %s" % [COLOR_NAMES.get(card.get("color","wild"),""), names.get(card.get("value",""),card.get("value",""))]

func _styled_button(label: String, callback: Callable, primary := false) -> Button:
	var b := button(label,callback,primary)
	b.custom_minimum_size.y = 44
	b.add_theme_font_size_override("font_size",17)
	return b

func _build_game_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = font
	hud.theme = theme
	layer.add_child(hud)
	var header := PanelContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left=24; header.offset_right=-24; header.offset_top=20
	header.add_theme_stylebox_override("panel",style(Color("112d36"),16,Color("355661")))
	hud.add_child(header)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation",24)
	header.add_child(header_row)
	var title := VBoxContainer.new()
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	title.add_child(text_label("S P E C T R U M   /   彩序",23,Color("f1ecd5")))
	title.add_child(text_label("自定义起牌 / 计分 + 可选房规 · 本地人机",13,Color("93b8b9")))
	header_row.add_child(_styled_button("第一 / 第三人称 V",toggle_view))
	header_row.add_child(_styled_button("俯视 T",toggle_top_down))
	header_row.add_child(_styled_button("菜单 Esc",_open_pause))
	var info := PanelContainer.new()
	info.position=Vector2(24,125)
	info.custom_minimum_size=Vector2(300,0)
	info.add_theme_stylebox_override("panel",style(Color("112d36"),14,Color("355661")))
	hud.add_child(info)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",9)
	info.add_child(col)
	turn_label=text_label("",23,Color("f0e9ca")); col.add_child(turn_label)
	color_indicator=text_label("",18,Color.WHITE);col.add_child(color_indicator)
	detail_label=text_label("",16,Color("d4e2db")); col.add_child(detail_label)
	roster=VBoxContainer.new(); roster.add_theme_constant_override("separation",7);col.add_child(roster)
	var help := text_label("亮边为可出牌 / 可抢牌\n点击自己的牌直接出牌\nD 摸牌 · Tab 收起手牌\n右键转头 · R 视角复位",13,Color("86a9a8"));col.add_child(help)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bottom.offset_top=490; bottom.offset_left=24; bottom.offset_right=-24
	bottom.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.add_child(bottom)
	event_label=text_label("",18,Color("fff2c5"));event_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	event_label.add_theme_color_override("font_shadow_color",Color("102129"));event_label.add_theme_constant_override("shadow_offset_x",2);event_label.add_theme_constant_override("shadow_offset_y",2)
	event_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	bottom.add_child(event_label)
	action_row=HBoxContainer.new();action_row.alignment=BoxContainer.ALIGNMENT_CENTER;action_row.add_theme_constant_override("separation",8)
	bottom.add_child(action_row)
	draw_action=_styled_button("摸一张 D",_human_draw,true);action_row.add_child(draw_action)
	pass_action=_styled_button("保留 / 结束回合",_human_pass);action_row.add_child(pass_action)
	jump_check=CheckBox.new();jump_check.text="本次抢牌";jump_check.add_theme_font_size_override("font_size",16);jump_check.tooltip_text="勾选后，同色同数字 / 功能牌替代上一张效果。\n不勾选按正常回合出牌；同色 +2 可正常叠加。";action_row.add_child(jump_check)
	announce_check=CheckBox.new();announce_check.text="随本次出牌喊 UNO";announce_check.add_theme_font_size_override("font_size",16);action_row.add_child(announce_check)
	uno_action=_styled_button("喊 UNO!",_human_uno);action_row.add_child(uno_action)
	catch_action=_styled_button("抓漏喊 UNO",_human_catch);action_row.add_child(catch_action)
	penalty_action=_styled_button("摸罚牌并跳过",_human_penalty,true);action_row.add_child(penalty_action)
	accept_action=_styled_button("接受 +4",func():_challenge(false));action_row.add_child(accept_action)
	challenge_action=_styled_button("质疑 +4",func():_challenge(true));action_row.add_child(challenge_action)
	get_viewport().size_changed.connect(func(): bottom.offset_top=get_viewport().get_visible_rect().size.y*0.52)
	bottom.offset_top=get_viewport().get_visible_rect().size.y*0.52
	modal=ColorRect.new();modal.color=Color(0.025,0.055,0.075,0.92);modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);modal.visible=false;hud.add_child(modal)
	var center := CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);modal.add_child(center)
	var panel := PanelContainer.new();panel.custom_minimum_size=Vector2(600,0);panel.add_theme_stylebox_override("panel",style(Color("173944"),20,Color("6a9393")));center.add_child(panel)
	modal_box=VBoxContainer.new();modal_box.add_theme_constant_override("separation",10);panel.add_child(modal_box)

func _clear_modal() -> void:
	for child in modal_box.get_children():
		# A pressed button may still be emitting its signal; detach immediately
		# and defer destruction so no locked control survives the rebuild.
		modal_box.remove_child(child)
		child.queue_free()

func _start_game(count: int, next_round := false, options: Dictionary = {}, hand_size: int = 7) -> void:
	var requested_size: int = round_hand_size if next_round else hand_size
	var seed_value: int = launch_seed + (round_count if next_round else 0) if launch_seed >= 0 else int(Time.get_ticks_usec()) % 2147483647
	var result: Dictionary = game.start_game(count, seed_value, round_options if next_round else options, requested_size)
	if not result.ok:
		last_message = result.message
		_refresh_hud()
		return
	paused=false;choosing=false;pending_card_id=null;modal.hide();announce_check.button_pressed=false
	players.clear()
	for i in count: players.append("你" if i==0 else "机器人 %d" % i)
	if not next_round:
		round_count=0
		round_options=options.duplicate(true)
		round_hand_size=hand_size
	round_count+=1
	jump_clocks.clear();seen_reaction_card=-1
	game_started=true;bot_clock=0;human_catch_clock=0
	last_message="第 %d 局开始 · 每人 %d 张 · 1号先行 · %s" % [round_count,round_hand_size,_option_summary()]
	_sync(false)
	if game.phase=="choose_color" and game.current_player==0:_show_color(null)

func _sync(animated := true) -> void:
	rendered_version=game.state_version
	jump_check.button_pressed=false
	var render_hands: Array=[]
	for cards in game.hands:
		var values: Array=[]
		for c in cards:
			var shown: Dictionary=c.duplicate();shown["title"]=_card_title(c);values.append(shown)
		render_hands.append(values)
	var discards: Array=[]
	for c in game.discard_pile:
		var shown: Dictionary=c.duplicate();shown["title"]=_card_title(c);discards.append(shown)
	apply_state(players,render_hands,game.draw_pile,discards,_texture,animated)
	bot_clock=0
	_refresh_hud()
	if game.phase=="finished":_show_result()

func _refresh_hud() -> void:
	if not game_started:return
	var yours: bool=game.current_player==0
	turn_label.text="你的回合" if yours else "%s 的回合" % players[game.current_player]
	if game.phase=="challenge":turn_label.text="+4：等待质疑决定"
	if game.phase in ["stacking","pending_effect"]:turn_label.text="%s · 待摸 %d 张" % ["你" if yours else players[game.current_player],game.pending_draw]
	if not game.pending_play.is_empty():turn_label.text+=" · 可抢牌"
	if game.phase=="finished":turn_label.text="本局结束"
	var top: Dictionary=game.top_card()
	detail_label.text="当前颜色：%s   %s\n顶牌：%s\n牌堆 %d · 第 %d 局" % [COLOR_NAMES.get(game.active_color,"待选"),"顺时针 ↻" if game.direction==1 else "逆时针 ↺",_card_title(top),game.draw_pile.size(),round_count]
	color_indicator.text="● %s色" % COLOR_NAMES.get(game.active_color,"待选")
	color_indicator.add_theme_color_override("font_color",COLOR_INKS.get(game.active_color,Color.WHITE))
	for c in roster.get_children():c.free()
	for i in players.size():
		var line: String="%s %s  ·  %d 张" % ["▶" if i==game.current_player else "  ",players[i],game.hands[i].size()]
		roster.add_child(text_label(line,16,Color("ffe5a0") if i==game.current_player else Color("91b4b5")))
	event_label.text=last_message
	var locked: bool=paused or choosing or not flights.is_empty()
	draw_action.disabled=locked or not yours or game.phase not in ["playing","stacking","pending_effect"]
	draw_action.text="摸罚牌 D" if game.phase in ["stacking","pending_effect"] else ("持续摸牌 D" if round_options.get("continuous_draw",false) else "摸一张 D")
	pass_action.visible=yours and game.phase=="drawn" and not game.forced_play;pass_action.disabled=locked
	jump_check.visible=yours and not game.jump_in_indices(0).is_empty();jump_check.disabled=locked
	announce_check.visible=game.hands[0].size()==2 and (yours or not game.jump_in_indices(0).is_empty())
	uno_action.visible=game.hands[0].size()==1 and game.phase!="finished"
	uno_action.disabled=locked
	catch_action.visible=game.phase!="finished";catch_action.disabled=locked
	penalty_action.visible=yours and game.phase in ["stacking","pending_effect"];penalty_action.disabled=locked
	penalty_action.text="摸 %d 张并跳过" % game.pending_draw
	accept_action.visible=yours and game.phase=="challenge";challenge_action.visible=accept_action.visible
	accept_action.disabled=locked;challenge_action.disabled=locked
	menu_open=paused or choosing
	set_interaction_blocked(locked or (not (game.current_player==0 and game.phase in ["playing","drawn","stacking","pending_effect"]) and game.jump_in_indices(0).is_empty()))

func _result(result: Dictionary) -> void:
	last_message=String(result.get("message","操作完成"))
	if not "实际摸" in last_message and result.has("requested_penalty") and int(result.get("penalty_count",0))<int(result.requested_penalty):
		last_message+=" 牌已用尽，实际摸 %d / %d 张。" % [int(result.get("penalty_count",0)),int(result.requested_penalty)]
	if result.get("ok",false):_sync()
	elif rendered_version!=game.state_version:_sync(false)
	else:_refresh_hud()

func _can_act() -> bool:
	return game_started and not paused and not choosing and flights.is_empty() and game.current_player==0

func _human_card(id: Variant) -> void:
	if not game_started or paused or choosing or not flights.is_empty():return
	var index := _find_card(0,id)
	if index<0:return
	if index in game.jump_in_indices(0) and (game.current_player!=0 or jump_check.button_pressed):
		_result(game.jump_in(0,index,announce_check.button_pressed,rendered_version))
		announce_check.button_pressed=false;return
	if not index in game.legal_indices(0):
		last_message="这张牌现在不能正常出；同色同数字 / 功能可勾选「本次抢牌」后出牌";_refresh_hud();return
	if game.hands[0][index].color=="wild":_show_color(id);return
	_result(game.play_card(0,index,"",announce_check.button_pressed,rendered_version));announce_check.button_pressed=false

func _find_card(player: int,id: Variant) -> int:
	for i in game.hands[player].size():
		if game.hands[player][i].id==id:return i
	return -1

func _human_draw() -> void:
	if _can_act() and game.phase in ["stacking","pending_effect"]:
		_human_penalty();return
	if _can_act() and game.phase=="playing":
		_result(game.draw_card(0,rendered_version))
		if game.forced_play and game.phase=="drawn" and game.current_player==0:
			_show_color(game.drawn_card_id)

func _human_penalty() -> void:
	if not _can_act():return
	if game.phase=="stacking":_result(game.accept_stack(0,rendered_version))
	elif game.phase=="pending_effect":_result(game.accept_pending(0,rendered_version))

func _human_pass() -> void:
	if _can_act() and game.phase=="drawn":_result(game.pass_draw(0))

func _human_uno() -> void:
	if paused or choosing or not flights.is_empty():return
	_result(game.announce_uno(0))

func _human_catch() -> void:
	if paused or choosing or not flights.is_empty():return
	_result(game.catch_uno(0))

func _challenge(value: bool) -> void:
	if not _can_act() or game.phase!="challenge":return
	var outcome: Dictionary=game.resolve_challenge(0,value)
	_result(outcome)
	if value and outcome.get("ok",false) and outcome.has("revealed_hand"):
		_show_challenge_evidence(outcome)

func _show_challenge_evidence(outcome: Dictionary) -> void:
	paused=true;release_mouse_look();settle_flights();modal.show();_clear_modal()
	modal_box.add_child(text_label("+4 质疑结果",27,Color("ffe0a0")))
	modal_box.add_child(text_label(String(outcome.get("message","")),18,Color("cbe0db")))
	var evidence: Array[String]=[]
	for c in outcome.revealed_hand:evidence.append(_card_title(c))
	var proof:=text_label("出牌前的手牌证据：\n"+" · ".join(evidence),16,Color("b9cfca"))
	proof.custom_minimum_size.x=550;proof.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;modal_box.add_child(proof)
	modal_box.add_child(_styled_button("知道了，继续",_close_pause,true))
	_refresh_hud()

func _show_color(id: Variant) -> void:
	choosing=true;pending_card_id=id;modal.show();_clear_modal();_refresh_hud()
	modal_box.add_child(text_label("选择接下来的颜色",26,Color("f7e5b4")))
	var selected_index:int=-1 if id==null else _find_card(0,id)
	var is_draw_four:bool=selected_index>=0 and game.hands[0][selected_index].value=="draw_four"
	var color_hint:String="请选择接下来使用的颜色。"
	if is_draw_four:
		color_hint="叠加规则已开启：+4 不进行质疑。" if round_options.get("stacking",false) else "+4 只能在没有当前颜色时合法打出。\n也可冒险虚张声势，对方可以质疑。"
	modal_box.add_child(text_label(color_hint,16,Color("afc7c7")))
	if game.forced_play:modal_box.add_child(text_label("持续抽牌：这张牌必须打出，请选择颜色。",16,Color("ffe0a0")))
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);modal_box.add_child(row)
	for color in COLORS:
		var b:=_styled_button(COLOR_NAMES[color],_choose_color.bind(color));b.custom_minimum_size.x=122;b.add_theme_stylebox_override("normal",style(COLOR_INKS[color],10));row.add_child(b)
	if id!=null and not game.forced_play:modal_box.add_child(_styled_button("取消出牌",_cancel_color))

func _choose_color(color: String) -> void:
	if not choosing:return
	var id: Variant=pending_card_id
	choosing=false;pending_card_id=null;modal.hide()
	if id==null:_result(game.choose_initial_color(0,color))
	else:
		var index:=_find_card(0,id)
		if index>=0:_result(game.play_card(0,index,color,announce_check.button_pressed,rendered_version))
	announce_check.button_pressed=false

func _cancel_color() -> void:
	if pending_card_id==null or game.forced_play:return
	choosing=false;pending_card_id=null;modal.hide();_refresh_hud()

func _open_pause() -> void:
	if choosing or not game_started:return
	paused=true;release_mouse_look();settle_flights();modal.show();_clear_modal();_refresh_hud()
	modal_box.add_child(text_label("彩序 / 牌桌菜单",28,Color("f3e4b7")))
	modal_box.add_child(_styled_button("继续游戏",_close_pause,true))
	var row:=HBoxContainer.new();modal_box.add_child(row)
	count_option=OptionButton.new()
	for n in range(2,9):count_option.add_item("%d 人：你 + %d 个机器人" % [n,n-1],n)
	count_option.select(players.size()-2);row.add_child(count_option)
	row.add_child(_styled_button("重新开始",_restart_with_options))
	var hand_row:=HBoxContainer.new();modal_box.add_child(hand_row)
	hand_row.add_child(text_label("初始手牌",16,Color("cbe0db")))
	hand_size_option=SpinBox.new();hand_size_option.min_value=1;hand_size_option.max_value=RULES.max_initial_hand_size(players.size());hand_size_option.step=1;hand_size_option.value=round_hand_size;hand_size_option.custom_minimum_size.x=100;hand_row.add_child(hand_size_option)
	hand_size_hint=text_label("",14,Color("b9ceca"));hand_row.add_child(hand_size_hint)
	count_option.item_selected.connect(_update_hand_limit)
	_update_hand_limit(0)
	option_checks.clear()
	modal_box.add_child(text_label("额外规则 · 仅重新开始时生效，继续游戏不会更改本局",15,Color("ffe0a0")))
	for key in OPTION_LABELS:
		var check:=CheckBox.new();check.text=OPTION_LABELS[key]
		check.button_pressed=bool(round_options.get(key,false))
		check.add_theme_font_size_override("font_size",15)
		option_checks[key]=check;modal_box.add_child(check)
	var navigation:=HBoxContainer.new();modal_box.add_child(navigation)
	navigation.add_child(_styled_button("返回玩法大厅",func():get_tree().change_scene_to_file("res://scenes/card_lobby.tscn")))
	navigation.add_child(_styled_button("打开通用模板演示",func():get_tree().change_scene_to_file("res://scenes/table_demo.tscn")))
	rules_label=text_label("本局：%s\n抢牌截止下一次实际出牌 / 摸牌，房主按到达顺序判定。\n同色、数字 / 符号匹配；两人反转等同跳过。\n剩一张喊 UNO；漏喊可被抓，罚两张。\n叠加开启时不质疑 +4；关闭时保留经典质疑。\n起始牌不触发功能；万能牌由1号先选色，1号先行。\n剩牌：数字面值 / 功能10 / 换色20 / +4为40。\n每局按剩牌分由低到高排名，同分并列，不累计。" % _option_summary(),15,Color("b9ceca"));modal_box.add_child(rules_label)

func _update_hand_limit(_index: int) -> void:
	var limit: int=RULES.max_initial_hand_size(count_option.get_selected_id())
	hand_size_option.max_value=limit
	hand_size_hint.text="1–%d 张 / 人（保留起始牌）" % limit

func _restart_with_options() -> void:
	var next_options: Dictionary={}
	for key in option_checks:next_options[key]=option_checks[key].button_pressed
	hand_size_option.apply()
	_start_game(count_option.get_selected_id(),false,next_options,int(hand_size_option.value))

func _option_summary() -> String:
	var enabled: Array[String]=[]
	var names: Dictionary={"continuous_draw":"持续抽牌","jump_in":"抢牌","stacking":"罚牌叠加","forbid_last_wild":"禁最后万能牌"}
	for key in names:
		if round_options.get(key,false):enabled.append(names[key])
	return "经典规则" if enabled.is_empty() else " / ".join(enabled)

func _close_pause() -> void:
	paused=false
	if game.phase=="finished":_show_result();return
	modal.hide();bot_clock=0;_refresh_hud()

func _show_result() -> void:
	if paused:return
	paused=true;release_mouse_look();modal.show();_clear_modal()
	var won: int=game.winner
	modal_box.add_child(text_label("本局结算 · 剩牌分越低排名越高",27,Color("ffe0a0")))
	modal_box.add_child(text_label("%s 已出完手牌" % players[won] if won>=0 else "牌已用尽且无人可出，按剩牌分结算",17,Color("bbd8d2")))
	modal_box.add_child(text_label("\n".join(_score_lines()),20,Color("bbd8d2")))
	modal_box.add_child(text_label("数字面值 · 功能10 · 换色20 · +4为40\n同分并列；每局独立结算，不累计分数",15,Color("b9ceca")))
	modal_box.add_child(_styled_button("下一局",func():_start_game(players.size(),true),true))
	modal_box.add_child(_styled_button("人数 / 规则菜单",func():paused=false;_open_pause()))
	_refresh_hud()

func _score_lines() -> Array[String]:
	var lines: Array[String]=[]
	var rows: Array=game.round_standings()
	var counts: Dictionary={}
	for row in rows:counts[row.points]=int(counts.get(row.points,0))+1
	for row in rows:
		lines.append("%s第 %d 名  %s：%d 分（剩 %d 张）" % ["并列" if counts[row.points]>1 else "",row.rank,players[row.player],row.points,row.cards])
	return lines

func _bot_color(player: int) -> String:
	var counts_by_color: Dictionary={"red":0,"yellow":0,"green":0,"blue":0}
	for c in game.hands[player]:
		if counts_by_color.has(c.color):counts_by_color[c.color]+=1
	var best: String="red"
	for color in COLORS:
		if counts_by_color[color]>counts_by_color[best]:best=color
	return best

func _bot_act() -> void:
	var p: int=game.current_player
	if p==0:return
	# Bots only act through the same validated rules API as the human.
	if game.phase=="choose_color":_result(game.choose_initial_color(p,_bot_color(p)));return
	if game.phase=="pending_effect":_result(game.accept_pending(p));return
	if game.phase=="challenge":
		# Decision uses only public information and a deterministic risk choice.
		var risk_challenge: bool=(int(game.top_card().id)+game.discard_pile.size()+p)%3==0
		_result(game.resolve_challenge(p,risk_challenge));return
	var legal: Array=game.legal_indices(p)
	var chosen: int=-1
	for i in legal:
		if game.forced_play or game.phase=="stacking" or game.hands[p][i].value!="draw_four" or game.can_play_draw_four(p):chosen=i;break
	if chosen>=0:
		# Occasional missed announcements make the catch interaction learnable.
		var announce: bool=(int(game.hands[p][chosen].id)%5)!=0
		_result(game.play_card(p,chosen,_bot_color(p),announce))
	elif game.phase=="stacking":_result(game.accept_stack(p))
	elif game.phase=="drawn":_result(game.pass_draw(p))
	elif game.phase=="playing":_result(game.draw_card(p))

func _process(delta: float) -> void:
	super._process(delta)
	if not game_started:return
	_refresh_action_lock()
	if paused or choosing or not flights.is_empty() or game.phase=="finished":return
	if _process_jump_requests(delta):return
	if game.current_player!=0:
		bot_clock+=delta
		if bot_clock>=bot_delay:
			bot_clock=0
			# A human can still self-announce during the visible delay.
			var caught: Dictionary=game.catch_uno(game.current_player)
			if caught.get("ok",false):_result(caught)
			else:_bot_act()

# Local host accepts requests serially. A bot's reaction is determined from
# public card ID/seat, never another player's hand. No jump expiry timer exists.
func _process_jump_requests(delta: float) -> bool:
	if game.pending_play.is_empty():
		jump_clocks.clear();seen_reaction_card=-1;return false
	var top_id:int=game.top_card().id
	if seen_reaction_card!=top_id:
		seen_reaction_card=top_id;reaction_serial+=1;jump_clocks.clear()
		for p in range(1,players.size()):
			jump_clocks[p]=0.85+float(posmod(top_id*31+p*47+reaction_serial*13,95))/100.0
	var ready:Array=[]
	for p in jump_clocks:
		jump_clocks[p]-=delta
		if jump_clocks[p]<=0 and not game.jump_in_indices(p).is_empty():ready.append(p)
	if ready.is_empty():return false
	ready.sort_custom(func(a,b):return jump_clocks[a]<jump_clocks[b])
	var p:int=ready[0]
	# When a frame spans multiple due times, honor earliest arrival rather than
	# giving jump requests artificial priority over the next bot's real action.
	if game.current_player!=0 and bot_delay-bot_clock <= float(jump_clocks[p])+delta:return false
	_result(game.jump_in(p,game.jump_in_indices(p)[0],true,game.state_version))
	return true

func _refresh_action_lock() -> void:
	var locked: bool=paused or choosing or not flights.is_empty()
	menu_open=paused or choosing
	set_interaction_blocked(locked or (not (game.current_player==0 and game.phase in ["playing","drawn","stacking","pending_effect"]) and game.jump_in_indices(0).is_empty()))
	draw_action.disabled=locked or game.current_player!=0 or game.phase not in ["playing","stacking","pending_effect"]
	pass_action.disabled=locked;uno_action.disabled=locked;catch_action.disabled=locked;jump_check.disabled=locked
	accept_action.disabled=locked;challenge_action.disabled=locked;penalty_action.disabled=locked
	var legal: Array=game.legal_indices(0) if not locked else []
	if not locked:
		for index in game.jump_in_indices(0):
			if not legal.has(index):legal.append(index)
	for i in game.hands[0].size():
		var node: Card3D=card_node(game.hands[0][i].id)
		if is_instance_valid(node):node.set_selected(i in legal)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F12:
		capture();get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		if choosing:_cancel_color()
		elif paused:_close_pause()
		elif not paused:_open_pause()
		get_viewport().set_input_as_handled();return
	if paused or choosing:return
	super._input(event)
