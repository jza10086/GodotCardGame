extends SceneTree
## Explicit visual QA only. Bots deliberately frozen for manual input inspection.
## --qa-jump: click your red 7 out of turn; the next seat changes to bot 1.
## --qa-forced-wild: D draws blue 2, green 3, then wild; Escape cannot cancel.
const RULES = preload("res://scripts/uno_rules.gd")
func _initialize() -> void:call_deferred("run")
func take(pool: Array,color: String,value: String) -> Dictionary:
	for i in pool.size():
		if pool[i].color==color and pool[i].value==value:return pool.pop_at(i)
	return {}
func run() -> void:
	var demo=load("res://scenes/uno_game.tscn").instantiate();root.add_child(demo)
	await process_frame
	var stack_jump:bool="--qa-stack-jump" in OS.get_cmdline_user_args()
	var jumping:bool="--qa-jump" in OS.get_cmdline_user_args() or stack_jump
	demo._start_game(3,false,{"jump_in":jumping,"stacking":stack_jump,"continuous_draw":not jumping,"forbid_last_wild":true})
	demo.choosing=false;demo.paused=false;demo.modal.hide()
	demo.bot_delay=999999.0
	var g=demo.game
	var pool:Array=RULES.build_deck()
	g.hands=[[],[],[]];g.discard_pile=[take(pool,"red","5")]
	g.active_color="red";g.current_player=0;g.direction=1;g.phase="playing"
	g.pending_play={};g.pending_draw=0;g.pending_winner=-1;g.forced_play=false
	g.uno_player=-1;g.uno_announced=false
	if stack_jump:
		g.hands[0]=[take(pool,"red","draw_two"),take(pool,"blue","1"),take(pool,"green","9")]
		g.hands[1]=[take(pool,"yellow","3"),take(pool,"blue","8")]
		g.hands[2]=[take(pool,"red","draw_two"),take(pool,"green","4"),take(pool,"yellow","6")]
		g.draw_pile=pool;g.current_player=2
		g.play_card(2,0,"",true)
		demo.last_message="GUI 验收：轮到你，待摸2；直接点红+2叠到4，勾选本次抢牌后点红+2仍为2。"
	elif jumping:
		g.hands[0]=[take(pool,"red","7"),take(pool,"blue","1"),take(pool,"green","9")]
		g.hands[1]=[take(pool,"red","7"),take(pool,"yellow","3"),take(pool,"blue","8")]
		g.hands[2]=[take(pool,"green","4"),take(pool,"yellow","6"),take(pool,"blue","3")]
		g.draw_pile=pool;g.current_player=1
		g.play_card(1,0,"",true)
		demo.last_message="GUI 验收（机器人计时冻结）：现在轮到机器人2，你可点击红7抢牌。"
	else:
		g.hands[0]=[take(pool,"blue","1"),take(pool,"green","9")]
		g.hands[1]=[take(pool,"yellow","3"),take(pool,"blue","8")]
		g.hands[2]=[take(pool,"green","4"),take(pool,"yellow","6")]
		var drawn_wild:Dictionary=take(pool,"wild","wild")
		var green:Dictionary=take(pool,"green","3")
		var blue:Dictionary=take(pool,"blue","2")
		g.draw_pile=pool;g.draw_pile.append_array([drawn_wild,green,blue])
		demo.last_message="GUI 验收（机器人计时冻结）：按 D 连摸至万能牌，试 Esc，再选颜色。"
	demo._sync(false)
