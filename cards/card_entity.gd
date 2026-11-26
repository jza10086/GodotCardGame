extends Node3D

## A reusable card slab. All displayed textures come from a viewer's projection.
const WIDTH: float = 1.15
const LENGTH: float = 1.61
const PAPER: float = 0.025
const CORNER: float = 0.075
const EDGE_SHADER: Shader = preload("res://games/minigame/GP_cards/cards/paper_edge.gdshader")

static var _paper_mesh: ArrayMesh
static var _rim_mesh: ArrayMesh

var face_texture: Texture2D
var locked_by: String = ""
var target_position: Vector3
var target_yaw: float = 0.0
var y_order: int = 0
var table_position: Vector2

var _face: StandardMaterial3D = StandardMaterial3D.new()
var _back: StandardMaterial3D = StandardMaterial3D.new()
var _edge: ShaderMaterial = ShaderMaterial.new()
var _thickness: float = PAPER
var _height: float = PAPER
var _face_up: bool = true
var _flipped: bool = false
var _target_flip: float = 0.0
var _dragging: bool = false
var _flight: Tween

@onready var _visual: Node3D = %Visual
@onready var _slab: MeshInstance3D = %Paper
@onready var _rim: MeshInstance3D = %Highlight
@onready var _body: StaticBody3D = %PickBody
@onready var _shape: CollisionShape3D = %CollisionShape3D


func _ready() -> void:
	if _paper_mesh == null:
		_make_meshes()
	_slab.mesh = _paper_mesh
	for material: StandardMaterial3D in [_face, _back]:
		material.roughness = 0.8
	_slab.set_surface_override_material(0, _face)
	_slab.set_surface_override_material(1, _back)
	_edge.shader = EDGE_SHADER
	_slab.set_surface_override_material(2, _edge)
	_rim.mesh = _rim_mesh


func apply_card(row: Dictionary, front: Texture2D, back: Texture2D, fresh: bool) -> void:
	table_position = row.pos
	locked_by = row.locked_by
	target_yaw = deg_to_rad(row.yaw_deg)
	y_order = row.y_order
	target_position = Vector3(table_position.x, 0.0, table_position.y)
	set_card_sides(front, back, row.face_up, fresh)
	if fresh:
		_snap_to_table()


## Clearing the face material is immediate even while a flip is still animating.
func set_card_sides(front: Texture2D, back: Texture2D, face_up: bool, immediate: bool = false) -> void:
	face_texture = front if face_up else null
	_face.albedo_texture = face_texture
	_face.albedo_color = Color.WHITE if face_texture != null else Color("#e6dccb")
	_back.albedo_texture = back
	_back.albedo_color = Color.WHITE
	_face_up = face_up
	_target_flip = 0.0 if _face_up else PI
	if immediate:
		_visual.rotation.x = _target_flip
		_flipped = false
	else:
		_flipped = absf(_visual.rotation.x - _target_flip) > 0.01


func set_floating() -> void:
	set_process(false)
	_body.collision_layer = 0
	_slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_back.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func set_seat_display() -> void:
	set_process(false)
	_body.collision_layer = 0
	_slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_highlight(active: bool, merge: bool = false) -> void:
	_rim.visible = active
	var material: StandardMaterial3D = _rim.material_override
	material.albedo_color = Color("#78f0b6") if merge else Color("#ffe39b")


func set_dragging(active: bool) -> void:
	_dragging = active
	_body.collision_layer = 0 if active else 2


func drag_at(pos: Vector2) -> void:
	target_position = Vector3(pos.x, 0.0, pos.y)


func get_pick_rid() -> RID:
	return _body.get_rid()


func stop_picking() -> void:
	_body.collision_layer = 0


func hide_face() -> void:
	face_texture = null
	_face.albedo_texture = null


func fly_to_merge(destination: Vector3) -> void:
	stop_picking()
	hide_face()
	set_highlight(false)
	set_process(false)
	_flight = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_flight.tween_property(self, "global_position", destination, 0.15)
	_flight.tween_property(self, "scale", Vector3.ONE * 0.92, 0.15)
	_flight.chain().tween_callback(queue_free)


func _snap_to_table() -> void:
	position = target_position + Vector3.UP * (_thickness * 0.5 + 0.009)
	rotation.y = target_yaw
	_scale_paper(_thickness)


func _scale_paper(thickness: float) -> void:
	_height = thickness
	_slab.scale.y = _height / PAPER
	_rim.position.y = _height * 0.5 + 0.003
	var box: BoxShape3D = _shape.shape
	box.size.y = maxf(0.045, _height)


func _process(delta: float) -> void:
	var weight: float = 1.0 - exp(-19.0 * delta)
	if absf(_thickness - _height) > 0.0005:
		_scale_paper(lerpf(_height, _thickness, weight))
	var flip_weight: float = 1.0 - exp(-12.0 * delta)
	_visual.rotation.x = lerpf(_visual.rotation.x, _target_flip, flip_weight)
	if absf(_visual.rotation.x - _target_flip) < 0.012:
		_visual.rotation.x = _target_flip
		_flipped = false
	var flip_lift: float = absf(sin(_visual.rotation.x)) * LENGTH * 0.43 if _flipped else 0.0
	var layers: float = float(y_order % 1000) * 0.00007
	var hover_height: float = 0.69 if _dragging else 0.0
	var destination: Vector3 = target_position + Vector3.UP * (_height * 0.5 + 0.009 + layers + flip_lift + hover_height)
	var planar_error: Vector3 = destination - position
	position = position.lerp(destination, weight)
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)
	var tilt_z: float = clampf(-planar_error.dot(basis.x) * 0.19, -0.19, 0.19) if _dragging else 0.0
	var tilt_x: float = clampf(planar_error.dot(basis.z) * 0.19, -0.19, 0.19) if _dragging else 0.0
	_slab.rotation.x = lerpf(_slab.rotation.x, tilt_x, weight)
	_slab.rotation.z = lerpf(_slab.rotation.z, tilt_z, weight)


func _make_meshes() -> void:
	var outline: PackedVector2Array = _rounded_outline(WIDTH, LENGTH, CORNER)
	_paper_mesh = ArrayMesh.new()
	for top: bool in [true, false]:
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var y: float = PAPER * (0.5 if top else -0.5)
		var normal: Vector3 = Vector3.UP if top else Vector3.DOWN
		for i: int in outline.size():
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i + 1) % outline.size()]
			var polygon: Array[Vector2] = [Vector2.ZERO, a if top else b, b if top else a]
			for point: Vector2 in polygon:
				var uv: Vector2 = Vector2(point.x / WIDTH + 0.5, point.y / LENGTH + 0.5)
				if not top:
					uv.y = 1.0 - uv.y
				_vertex(tool, point, y, uv, normal)
		tool.commit(_paper_mesh)
	var edge: SurfaceTool = SurfaceTool.new()
	edge.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var n: Vector2 = Vector2(b.y - a.y, a.x - b.x).normalized()
		var normal: Vector3 = Vector3(n.x, 0.0, n.y)
		_vertex(edge, a, -PAPER * 0.5, Vector2(0, 0), normal)
		_vertex(edge, a, PAPER * 0.5, Vector2(0, 1), normal)
		_vertex(edge, b, PAPER * 0.5, Vector2(1, 1), normal)
		_vertex(edge, a, -PAPER * 0.5, Vector2(0, 0), normal)
		_vertex(edge, b, PAPER * 0.5, Vector2(1, 1), normal)
		_vertex(edge, b, -PAPER * 0.5, Vector2(1, 0), normal)
	edge.commit(_paper_mesh)
	var outer: PackedVector2Array = _rounded_outline(WIDTH + 0.105, LENGTH + 0.105, CORNER + 0.0525)
	var rim: SurfaceTool = SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in outline.size():
		var next: int = (i + 1) % outline.size()
		var strip: Array[Vector2] = [outer[i], outer[next], outline[i], outline[i], outer[next], outline[next]]
		for point: Vector2 in strip:
			_vertex(rim, point, 0.0, Vector2.ZERO, Vector3.UP)
	_rim_mesh = rim.commit()


static func _rounded_outline(width: float, length: float, radius: float) -> PackedVector2Array:
	var result: PackedVector2Array = []
	for corner: int in 4:
		var start: float = float(corner) * PI * 0.5
		var center: Vector2 = Vector2.from_angle(start + PI * 0.25).sign() * Vector2(width * 0.5 - radius, length * 0.5 - radius)
		for step: int in 5:
			result.append(center + Vector2.from_angle(start + float(step) * PI / 8.0) * radius)
	return result


static func _vertex(tool: SurfaceTool, point: Vector2, y: float, uv: Vector2, normal: Vector3) -> void:
	tool.set_normal(normal)
	tool.set_uv(uv)
	tool.add_vertex(Vector3(point.x, y, point.y))
