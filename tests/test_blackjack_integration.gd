extends SceneTree
const HOST=preload("res://scripts/public_card_table.gd")
const GAME=preload("res://scenes/blackjack_legacy_game.tscn")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var table=HOST.new();root.add_child(table)
	var tex=func(_record:Dictionary,_hidden:bool)->Dictionary:return {"face":load("res://assets/blackjack/clubs_1.png"),"back":load("res://assets/blackjack/back.png"),"title":"A"}
	check(table.present_rows([{"cards":[{"id":1},{"id":2,"hidden":true}],"z":0}],tex,false),"generic row accepted")
	var original=table.card_nodes[1]
	check(table.present_rows([{"cards":[{"id":1},{"id":2}],"z":2}],tex,true),"generic reveal accepted")
	check(table.card_nodes[1]==original,"stable node survives row update")
	check(not table.present_rows([{"cards":[{"id":1},{"id":1}],"z":0}],tex),"duplicate identity rejected atomically")
	check(table.card_nodes.size()==2,"invalid snapshot retains nodes")
	table.queue_free();await process_frame
	var session=root.get_node("CardSession")
	session.blackjack=load("res://scripts/blackjack_rules.gd").new(10)
	var scene=GAME.instantiate();root.add_child(scene);await process_frame
	var model=scene.game
	model.set_next_draws([4,8,18,6,9,5]);scene.bet_control.value=100;scene._deal()
	check(model.balance==900 and model.phase=="player","UI deal debits once")
	check(scene.card_nodes.size()==4,"opening deal renders four 3D cards")
	scene.animation_left=0;scene._act("double_down")
	check(model.balance==800 and model.bet==200 and model.player_hand.size()==3,"UI double debits once and adds one")
	var reference=scene.card_nodes[model.player_hand[0].id]
	scene.animation_left=0;scene._act("dealer_step")
	check(model.phase=="settled" and model.balance==1200,"double win balance is 1200")
	check(scene.card_nodes[model.player_hand[0].id]==reference,"settlement preserves existing card node")
	scene.queue_free();await process_frame
	var resumed=GAME.instantiate();root.add_child(resumed);await process_frame
	check(resumed.game==model and model.balance==1200,"scene reload preserves exact session and payout")
	resumed.animation_left=0;resumed._act("next_round")
	check(model.balance==1200 and model.phase=="betting","next round does not reset balance")
	resumed.queue_free();await process_frame
	print("Blackjack integration: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
