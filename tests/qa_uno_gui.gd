extends SceneTree
## Manual GUI fixtures; never used by normal game startup.
## godot --path . --script res://tests/qa_uno_gui.gd -- --qa-challenge
## godot --path . --script res://tests/qa_uno_gui.gd -- --qa-result
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var demo = load("res://scenes/uno_game.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo._start_game(2)
	demo.choosing=false;demo.paused=false;demo.modal.hide()
	demo.game.start_game(2,12)
	if "--qa-result" in OS.get_cmdline_user_args():
		demo.game.phase="finished";demo.game.winner=0;demo.game.score=85
		demo._sync(false)
		return
	# A legal, conserved 108-card setup with an illegal +4, awaiting human choice.
	demo.game.current_player=1;demo.game.phase="playing";demo.game.active_color="red"
	var four: Dictionary={}
	for i in range(demo.game.draw_pile.size()-1,-1,-1):
		if demo.game.draw_pile[i].value=="draw_four":four=demo.game.draw_pile.pop_at(i);break
	demo.game.hands[1].append(four)
	var has_red:=false
	for card in demo.game.hands[1]:has_red=has_red or card.color=="red"
	if not has_red:
		for i in range(demo.game.draw_pile.size()-1,-1,-1):
			if demo.game.draw_pile[i].color=="red":demo.game.hands[1].append(demo.game.draw_pile.pop_at(i));break
	demo.game.play_card(1,demo.game.hands[1].find(four),"blue",true)
	demo.last_message="GUI 验收场景：机器人出了 +4，等待你的决定"
	demo._sync(false)
