extends Node3D

## Owns the static table, physical seats and the local view. Gameplay objects mount under the fixed roots.
const CameraRig: GDScript = preload("res://games/minigame/GP_cards/table/table_camera_rig.gd")
const SEAT_COUNT: int = 8
const TABLE_COLLISION_MASK: int = 1

@export var world: WorldEnvironment
@export var sun: DirectionalLight3D

@onready var _seats: Node3D = %Seats
@onready var _camera_rig: CameraRig = %CameraRig
@onready var _camera: Camera3D = %Camera3D


func _ready() -> void:
	assert(world != null and sun != null, "Assign the table's environment and sun.")


## Display participants in the protocol's roster order and use a neutral angle for spectators.
func seat_players(players: Array[Dictionary], local_player_index: int, input_context: PartyInput) -> void:
	for seat: Node3D in _seats.get_children():
		seat.hide()
	var seat_yaw: float = 0.0
	for i: int in players.size():
		var seat_idx: int = int(floor(8.0 * float(i) / float(players.size()) + 0.5)) % SEAT_COUNT
		var seat: Node3D = _seats.get_child(seat_idx)
		var nickname: Label3D = seat.get_node("Nickname")
		var strip: MeshInstance3D = seat.get_node("ColorStrip")
		var material: StandardMaterial3D = strip.material_override
		var color: Color = players[i].color
		nickname.text = players[i].name
		material.albedo_color = color
		material.emission = color
		seat.show()
		if i == local_player_index:
			seat_yaw = seat.rotation.y
	_camera_rig.configure(input_context, seat_yaw)


func set_controls_active(active: bool) -> void:
	_camera_rig.set_controls_active(active)


func hand_anchor(seat_idx: int) -> Node3D:
	return _seats.get_child(seat_idx).get_node("HandBacksAnchor")


## Return the physics hit on the felt, or an empty dictionary outside its edges.
func pick_table(screen_position: Vector2) -> Dictionary:
	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var target: Vector3 = origin + _camera.project_ray_normal(screen_position) * _camera.far
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target, TABLE_COLLISION_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query)
