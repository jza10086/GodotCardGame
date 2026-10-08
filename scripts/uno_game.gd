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
var accept_action: Button
var challenge_action: Button
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
var round_seed := 0
var launch_seed := -1
var round_count := 0
var last_message := ""
var match_scores: Array = []
var human_catch_clock := 0.0
var scored_round := -1
var rules_label: Label

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
	title.add_child(text_label("经典 UNO 规则 · 原创牌面 · 本地人机",13,Color("93b8b9")))
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
	var help := text_label("亮边为当前可出牌\n点击自己的牌直接出牌\nD 摸牌 · Tab 收起手牌\n右键转头 · R 视角复位",13,Color("86a9a8"));col.add_child(help)
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
	announce_check=CheckBox.new();announce_check.text="随本次出牌喊 UNO";announce_check.add_theme_font_size_override("font_size",16);action_row.add_child(announce_check)
	uno_action=_styled_button("喊 UNO!",_human_uno);action_row.add_child(uno_action)
	catch_action=_styled_button("抓漏喊 UNO",_human_catch);action_row.add_child(catch_action)
	accept_action=_styled_button("接受 +4",func():_challenge(false));action_row.add_child(accept_action)
	challenge_action=_styled_button("质疑 +4",func():_challenge(true));action_row.add_child(challenge_action)
	get_viewport().size_changed.connect(func(): bottom.offset_top=get_viewport().get_visible_rect().size.y*0.52)
	bottom.offset_top=get_viewport().get_visible_rect().size.y*0.52
	modal=ColorRect.new();modal.color=Color(0.025,0.055,0.075,0.92);modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);modal.visible=false;hud.add_child(modal)
	var center := CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);modal.add_child(center)
	var panel := PanelContainer.new();panel.custom_minimum_size=Vector2(600,0);panel.add_theme_stylebox_override("panel",style(Color("173944"),20,Color("6a9393")));center.add_child(panel)
	modal_box=VBoxContainer.new();modal_box.add_theme_constant_override("separation",15);panel.add_child(modal_box)

func _clear_modal() -> void:
	for child in modal_box.get_children():
		# A pressed button may still be emitting its signal; detach immediately
		# and defer destruction so no locked control survives the rebuild.
		modal_box.remove_child(child)
		child.queue_free()

func _start_game(count: int, keep_scores := false) -> void:
	paused=false;choosing=false;pending_card_id=null;modal.hide();announce_check.button_pressed=false
	players.clear()
	for i in count: players.append("你" if i==0 else "机器人 %d" % i)
	if not keep_scores or match_scores.size()!=count:
		match_scores=[]
		for i in count:match_scores.append(0)
		round_count=0
		scored_round=-1
	round_count+=1
	round_seed=launch_seed+round_count-1 if launch_seed>=0 else int(Time.get_ticks_usec()) % 2147483647
	game.start_game(count,round_seed)
	game_started=true;bot_clock=0;human_catch_clock=0
	last_message="第 %d 局开始 · 每人七张 · 不叠加罚牌" % round_count
	_sync(false)
	if game.phase=="choose_color" and game.current_player==0:_show_color(null)

func _sync(animated := true) -> void:
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
	if game.phase=="finished":turn_label.text="本局结束"
	var top: Dictionary=game.top_card()
	detail_label.text="当前颜色：%s   %s\n顶牌：%s\n牌堆 %d · 第 %d 局" % [COLOR_NAMES.get(game.active_color,"待选"),"顺时针 ↻" if game.direction==1 else "逆时针 ↺",_card_title(top),game.draw_pile.size(),round_count]
	color_indicator.text="● %s色" % COLOR_NAMES.get(game.active_color,"待选")
	color_indicator.add_theme_color_override("font_color",COLOR_INKS.get(game.active_color,Color.WHITE))
	for c in roster.get_children():c.free()
	for i in players.size():
		var line: String="%s %s  ·  %d 张  ·  %d 分" % ["▶" if i==game.current_player else "  ",players[i],game.hands[i].size(),match_scores[i]]
		roster.add_child(text_label(line,16,Color("ffe5a0") if i==game.current_player else Color("91b4b5")))
	event_label.text=last_message
	var locked: bool=paused or choosing or not flights.is_empty()
	draw_action.disabled=locked or not yours or game.phase!="playing"
	pass_action.visible=yours and game.phase=="drawn";pass_action.disabled=locked
	announce_check.visible=game.hands[0].size()==2 and yours and game.phase in ["playing","drawn"]
	uno_action.visible=game.hands[0].size()==1 and game.phase!="finished"
	uno_action.disabled=locked
	catch_action.visible=game.phase!="finished";catch_action.disabled=locked
	accept_action.visible=yours and game.phase=="challenge";challenge_action.visible=accept_action.visible
	accept_action.disabled=locked;challenge_action.disabled=locked
	menu_open=paused or choosing
	set_interaction_blocked(locked or not yours or not game.phase in ["playing","drawn"])

func _result(result: Dictionary) -> void:
	last_message=String(result.get("message","操作完成"))
	if result.get("ok",false):_sync()
	else:_refresh_hud()

func _can_act() -> bool:
	return game_started and not paused and not choosing and flights.is_empty() and game.current_player==0

func _human_card(id: Variant) -> void:
	if not _can_act() or not game.phase in ["playing","drawn"]:return
	var index := _find_card(0,id)
	if index<0:return
	if not index in game.legal_indices(0):
		last_message="这张牌不能打：需要同色、同数字 / 符号，或万能牌";_refresh_hud();return
	if game.hands[0][index].color=="wild":_show_color(id);return
	_result(game.play_card(0,index,"",announce_check.button_pressed));announce_check.button_pressed=false

func _find_card(player: int,id: Variant) -> int:
	for i in game.hands[player].size():
		if game.hands[player][i].id==id:return i
	return -1

func _human_draw() -> void:
	if _can_act() and game.phase=="playing":_result(game.draw_card(0))

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
	modal_box.add_child(text_label("+4 只能在没有当前颜色时合法打出。\n也可冒险虚张声势，对方可以质疑。",16,Color("afc7c7")))
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);modal_box.add_child(row)
	for color in COLORS:
		var b:=_styled_button(COLOR_NAMES[color],_choose_color.bind(color));b.custom_minimum_size.x=122;b.add_theme_stylebox_override("normal",style(COLOR_INKS[color],10));row.add_child(b)
	if id!=null:modal_box.add_child(_styled_button("取消出牌",_cancel_color))

func _choose_color(color: String) -> void:
	if not choosing:return
	var id: Variant=pending_card_id
	choosing=false;pending_card_id=null;modal.hide()
	if id==null:_result(game.choose_initial_color(0,color))
	else:
		var index:=_find_card(0,id)
		if index>=0:_result(game.play_card(0,index,color,announce_check.button_pressed))
	announce_check.button_pressed=false

func _cancel_color() -> void:
	if pending_card_id==null:return
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
	row.add_child(_styled_button("重新开始",func():_start_game(count_option.get_selected_id())))
	modal_box.add_child(_styled_button("打开通用模板演示",func():get_tree().change_scene_to_file("res://scenes/table_demo.tscn")))
	rules_label=text_label("同色、同数字或符号可以出牌；每次只打一张。\n可以主动摸一张，摸后只能打刚摸到的牌，也可保留。\n+2 与 +4 不叠加。两人局反转等同跳过。\n剩一张需要喊 UNO；下一位实际行动前可抓漏喊，罚两张。\n+4 质疑：成功则出牌者摸四；失败你摸六并跳过。\n数字按面值，功能牌 20，万能牌 50；累计 500 分获胜。\n本地机器人原型；不含联机或官方品牌素材。",16,Color("b9ceca"));modal_box.add_child(rules_label)

func _close_pause() -> void:
	paused=false
	if game.phase=="finished":_show_result();return
	modal.hide();bot_clock=0;_refresh_hud()

func _show_result() -> void:
	if paused:return
	paused=true;release_mouse_look();modal.show();_clear_modal()
	var won: int=game.winner
	if won>=0 and scored_round!=round_count:
		match_scores[won]+=game.score
		scored_round=round_count
	var champ: int=-1
	for i in match_scores.size():
		if match_scores[i]>=500:champ=i
	modal_box.add_child(text_label("%s 赢得比赛！" % players[champ] if champ>=0 else ("%s 赢得本局！" % players[won] if won>=0 else "本局平局"),29,Color("ffe0a0")))
	modal_box.add_child(text_label("本局得分 +%d\n%s" % [game.score,"\n".join(_score_lines())],20,Color("bbd8d2")))
	modal_box.add_child(_styled_button("新比赛" if champ>=0 else "下一局",func():_start_game(players.size(),champ<0),true))
	modal_box.add_child(_styled_button("人数 / 规则菜单",func():paused=false;_open_pause()))
	_refresh_hud()

func _score_lines() -> Array[String]:
	var lines: Array[String]=[]
	for i in players.size():lines.append("%s：%d 分" % [players[i],match_scores[i]])
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
	if game.phase=="challenge":
		# Decision uses only public information and a deterministic risk choice.
		var risk_challenge: bool=(int(game.top_card().id)+game.discard_pile.size()+p)%3==0
		_result(game.resolve_challenge(p,risk_challenge));return
	var legal: Array=game.legal_indices(p)
	var chosen: int=-1
	for i in legal:
		if game.hands[p][i].value!="draw_four" or game.can_play_draw_four(p):chosen=i;break
	if chosen>=0:
		# Occasional missed announcements make the catch interaction learnable.
		var announce: bool=(int(game.hands[p][chosen].id)%5)!=0
		_result(game.play_card(p,chosen,_bot_color(p),announce))
	elif game.phase=="drawn":_result(game.pass_draw(p))
	elif game.phase=="playing":_result(game.draw_card(p))

func _process(delta: float) -> void:
	super._process(delta)
	if not game_started:return
	_refresh_action_lock()
	if paused or choosing or not flights.is_empty() or game.phase=="finished":return
	if game.current_player!=0:
		bot_clock+=delta
		if bot_clock>=bot_delay:
			bot_clock=0
			# A human can still self-announce during the visible delay.
			var caught: Dictionary=game.catch_uno(game.current_player)
			if caught.get("ok",false):_result(caught)
			else:_bot_act()

func _refresh_action_lock() -> void:
	var locked: bool=paused or choosing or not flights.is_empty()
	menu_open=paused or choosing
	set_interaction_blocked(locked or game.current_player!=0 or not game.phase in ["playing","drawn"])
	draw_action.disabled=locked or game.current_player!=0 or game.phase!="playing"
	pass_action.disabled=locked;uno_action.disabled=locked;catch_action.disabled=locked
	accept_action.disabled=locked;challenge_action.disabled=locked
	var legal: Array=game.legal_indices(0) if game.current_player==0 and not locked else []
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
