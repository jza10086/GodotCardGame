extends SceneTree
## --qa-result (default), --qa-menu, or --qa-starter for manual visual QA.
const RULES = preload("res://scripts/uno_rules.gd")
func _initialize() -> void: call_deferred("run")
func take(g, color: String, value: String) -> Dictionary:
	for i in g.draw_pile.size():
		if g.draw_pile[i].color==color and g.draw_pile[i].value==value:return g.draw_pile.pop_at(i)
	return {}
func run() -> void:
	var demo=load("res://scenes/uno_game.tscn").instantiate();root.add_child(demo)
	await process_frame
	demo.launch_seed=33
	demo._start_game(8,false,{"continuous_draw":true,"jump_in":true,"stacking":true,"forbid_last_wild":true},13)
	if demo.choosing:demo._choose_color("blue")
	if "--qa-menu" in OS.get_cmdline_user_args():
		demo._open_pause();return
	if "--qa-starter" in OS.get_cmdline_user_args():
		for seed_value in 1000:
			var probe=RULES.new();probe.start_game(4,seed_value,{},5)
			if probe.top_card().value=="draw_four":
				demo.launch_seed=seed_value;demo._start_game(4,false,{},5);return
	var g=demo.game
	g.draw_pile=RULES.build_deck();g.discard_pile=[take(g,"red","5")]
	g.hands=[[],[take(g,"blue","0")],[take(g,"red","9")],[take(g,"green","skip")],[take(g,"wild","wild")],[take(g,"blue","reverse"),take(g,"green","draw_two")],[take(g,"wild","draw_four")],[take(g,"wild","draw_four"),take(g,"yellow","9")]]
	g.phase="finished";g.winner=0;g.finish_reason="winner";g.active_color="red";g.current_player=0
	demo.choosing=false;demo.paused=false;demo._sync(false)
