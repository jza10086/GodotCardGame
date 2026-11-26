extends PopupMenu

signal action_requested(action: Dictionary)

var _actions: Array[Dictionary] = []


func _ready() -> void:
	id_pressed.connect(_choose)


func open_for(kind: StringName, uid: int, at: Vector2) -> void:
	clear()
	_actions.clear()
	if kind == &"card":
		_add("翻面", {"type": &"flip", "kind": kind, "uid": uid})
		_add("收入手牌", {"type": &"take_card", "kind": kind, "uid": uid})
		_add("旋转 90°", {"type": &"rotate", "kind": kind, "uid": uid, "delta": 90.0})
	else:
		_add("洗牌", {"type": &"shuffle", "deck_uid": uid})
		_add("翻面", {"type": &"flip", "kind": kind, "uid": uid})
		_add("抽 1 张", {"type": &"take_from_deck", "deck_uid": uid, "count": 1})
		for count: int in [1, 5, 7]:
			_add("全员发 %d 张" % count, {"type": &"deal", "deck_uid": uid, "count": count})
	position = Vector2i(at)
	reset_size()
	popup()


func _add(label: String, action: Dictionary) -> void:
	add_item(label, _actions.size())
	_actions.append(action)


func _choose(id: int) -> void:
	hide()
	action_requested.emit(_actions[id])
