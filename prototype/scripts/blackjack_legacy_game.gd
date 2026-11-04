extends "res://scripts/public_card_table.gd"
## Adapter: rules own money; the table owns presentation; this owns user intent.
const RULES = preload("res://scripts/blackjack_rules.gd")
const UI = preload("res://scripts/card_ui.gd")
var game: RefCounted
@onready var hud: Control = %Hud
@onready var balance_label: Label = %BalanceLabel
@onready var stake_label: Label = %StakeLabel
@onready var dealer_label: Label = %DealerLabel
@onready var player_label: Label = %PlayerLabel
@onready var status_label: Label = %StatusLabel
@onready var detail_label: Label = %DetailLabel
@onready var bet_control: SpinBox = %BetControl
@onready var deal_button: Button = %DealButton
@onready var hit_button: Button = %HitButton
@onready var stand_button: Button = %StandButton
@onready var double_button: Button = %DoubleButton
@onready var next_button: Button = %NextButton
@onready var reset_button: Button = %ResetButton
@onready var minus_button: Button = %MinusButton
@onready var plus_button: Button = %PlusButton
@onready var modal: ColorRect = %Modal
@onready var modal_col: VBoxContainer = %ModalCol
var dealer_clock := 0.0
var paused := false
var textures: Dictionary = {}
var fixture_name := ""

func _ready() -> void:
	game = get_node("/root/CardSession").get_blackjack()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--blackjack-fixture="): fixture_name = arg.get_slice("=",1)
	if not fixture_name.is_empty() and game.phase == "betting" and game.state_version == 0:
		_apply_fixture(fixture_name)
	_sync(false)

func _apply_fixture(value: String) -> void:
	# QA-only deterministic first draw sequence. No normal gameplay reset path.
	var fixtures := {"double":[4,8,18,6,9,5], "natural":[0,8,12,6], "dealer-natural":[8,0,6,12], "push":[9,22,12,25], "bust":[9,4,11,6,8], "soft17":[9,0,6,5]}
	if fixtures.has(value): game.set_next_draws(fixtures[value])
	if value == "bankrupt":
		game.balance = 10
		game.set_next_draws([9,4,11,6,8])

func _panel(parent: Node, color := Color("102c35")) -> PanelContainer:
	var panel := PanelContainer.new(); panel.add_theme_stylebox_override("panel",UI.style(color,16)); parent.add_child(panel); return panel

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

func _decrease_bet() -> void:
	bet_control.value -= 10

func _increase_bet() -> void:
	bet_control.value += 10
