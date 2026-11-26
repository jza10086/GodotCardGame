extends CanvasLayer

signal action_requested(action: Dictionary)
signal camera_reset_requested()
signal camera_overhead_requested()

@onready var _host: HBoxContainer = %HostActions
@onready var _preview: TextureRect = %FacePreview
@onready var _end: Button = %EndMatch


func _ready() -> void:
	%Poker.pressed.connect(_choose_preset.bind(&"poker"))
	%Uno.pressed.connect(_choose_preset.bind(&"uno"))
	%Clear.pressed.connect(_request_simple.bind(&"clear_table"))
	_end.pressed.connect(_request_simple.bind(&"end_match"))
	%Reset.pressed.connect(func() -> void: camera_reset_requested.emit())
	%Overhead.pressed.connect(func() -> void: camera_overhead_requested.emit())
	hide()


func activate(can_manage: bool, can_end: bool) -> void:
	_host.visible = can_manage
	_end.visible = can_end
	show()


func show_face(texture: Texture2D) -> void:
	_preview.texture = texture
	_preview.visible = texture != null


func _choose_preset(preset_id: StringName) -> void:
	action_requested.emit({"type": &"spawn_preset", "preset_id": preset_id, "replace": true})


func _request_simple(type: StringName) -> void:
	action_requested.emit({"type": type})
