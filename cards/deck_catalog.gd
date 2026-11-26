extends RefCounted

## Preset order and multiplicity are independent of imported texture resources.
const ROOT: String = "res://games/minigame/GP_cards/assets/decks/"
const POKER_SUITS: Array[String] = ["clubs", "diamonds", "hearts", "spades"]
const UNO_COLORS: Array[String] = ["red", "yellow", "green", "blue"]
const UNO_ACTIONS: Array[String] = ["skip", "reverse", "draw_two"]

var _presets: Dictionary[StringName, Array] = {
	&"poker": _poker_cards(),
	&"uno": _uno_cards(),
}
var _textures: Dictionary[String, Texture2D] = {}


func get_preset_cards(preset_id: StringName) -> Array[StringName]:
	var cards: Array[StringName] = []
	if _presets.has(preset_id):
		cards.assign(_presets[preset_id])
	return cards


func get_face_texture(deck_type: StringName, face_id: StringName) -> Texture2D:
	if not _presets.has(deck_type) or face_id not in _presets[deck_type]:
		return _texture("common/question.svg")
	var extension: String = "svg" if deck_type == &"poker" and face_id.begins_with("joker_") else "png"
	return _texture("%s/%s.%s" % [deck_type, face_id, extension])


func get_back_texture(deck_type: StringName) -> Texture2D:
	return _texture("%s/back.png" % deck_type)


func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(ROOT + path) as Texture2D
	return _textures[path]


static func _poker_cards() -> Array[StringName]:
	var cards: Array[StringName] = []
	for suit: String in POKER_SUITS:
		for rank: int in range(1, 14):
			cards.append(StringName("%s_%d" % [suit, rank]))
	cards.append_array([&"joker_small", &"joker_big"])
	return cards


static func _uno_cards() -> Array[StringName]:
	var cards: Array[StringName] = []
	for color: String in UNO_COLORS:
		cards.append(StringName("%s_0" % color))
		for rank: int in range(1, 10):
			var face: StringName = StringName("%s_%d" % [color, rank])
			cards.append_array([face, face])
		for action: String in UNO_ACTIONS:
			var face: StringName = StringName("%s_%s" % [color, action])
			cards.append_array([face, face])
	for copy: int in 4:
		cards.append_array([&"wild_wild", &"wild_draw_four"])
	return cards
