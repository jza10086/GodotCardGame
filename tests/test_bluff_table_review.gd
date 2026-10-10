extends SceneTree
## Independent 3D masking, hover, identity and camera audit.
const Rules=preload("res://scripts/bluff_rules.gd")
const Table=preload("res://scripts/bluff_table.gd")
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error("BLUFF TABLE REVIEW: "+label)
func _initialize()->void:call_deferred("run")
func provider(card:Dictionary)->Dictionary:
	if card.get("hidden",false):
		for key in ["rank","suit","title","face"]:ck(not card.has(key),"provider never receives secret "+key)
		return {"back":load("res://assets/back.svg")}
	return {"face":load("res://assets/card_0.svg"),"back":load("res://assets/back.svg")}
func masked(node)->void:
	ck(node.viewer_masked,"secret card viewer mask")
	ck(node.face_texture==null,"secret card has no retained face texture")
	for key in ["rank","suit","title"]:ck(not node.data.has(key),"secret card config strips "+key)
	var public:Dictionary=node.public_snapshot()
	ck(not public.has("title") and not public.has("face"),"secret public snapshot has no identity")
func run()->void:
	var g=Rules.new();ck(g.configure(3,[1,2,3,4,11,12,13],true,true,71),"setup")
	var table=Table.new();root.add_child(table)
	await process_frame
	var players:Array=["P1","P2","P3"]
	var stable:Dictionary={}
	for viewer in [0,-1,1,-1,2,-1,0]:
		ck(table.present_bluff(players,g.public_hands(viewer),g.public_pile(),provider,viewer),"hotseat presentation")
		ck(table.selected==null and table.hovered==null and not table.inspect_panel.visible,"handoff clears selection hover inspector")
		for p in 3:
			for c in g.hands[p]:
				var node=table.card_node(c.id)
				if stable.has(c.id):ck(stable[c.id]==node,"stable physical node across handoff")
				stable[c.id]=node
				if p!=viewer:
					masked(node)
					var snap:Dictionary=table.inspection_snapshot(node)
					ck(not snap.has("title") and not snap.has("face"),"hover cannot expose opponent")
				else:ck(node.face_texture!=null and not node.viewer_masked,"only current viewer sees own hand")
		ck(table.last_play_snapshot().is_empty(),"template recent play contains no secret")
		if viewer>=0:
			var card=table.player_hand(viewer)[0]
			table.select(card);table.hovered=card;table.inspect_panel.show()
	ck(g.play_cards(0,[g.hands[0][0].id]),"concealed batch")
	ck(table.present_bluff(players,g.public_hands(-1),g.public_pile(),provider,-1),"concealed pile presentation")
	for card in table.played:
		masked(card)
		ck(not card.face_up,"table batch physically face down")
		var snap:Dictionary=table.inspection_snapshot(card)
		ck(not snap.has("title") and not snap.has("face"),"table hover cannot expose batch")
	for method in ["toggle_view","toggle_top_down","toggle_hand_stowed","reset_view"]:
		table.call(method)
		for node in table._card_nodes.values():masked(node)
	print("INDEPENDENT BLUFF TABLE REVIEW: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
