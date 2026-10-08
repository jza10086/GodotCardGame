class_name Card3D
extends Node3D
## Reusable XZ-plane card. Root owns layout; Visual owns flip/hover animation.
signal flipped(card: Card3D, face_up: bool)
signal face_visibility_changed(card: Card3D, hidden: bool)
signal selection_changed(card: Card3D, selected: bool)
signal drag_started(card: Card3D)
signal drag_finished(card: Card3D, accepted: bool)
signal zone_changed(card: Card3D, old_zone: StringName, new_zone: StringName)
@export var card_size := Vector2(1.65, 2.32)
@export_range(0.015, 0.2) var thickness := 0.045
@export var corner_radius := 0.105
@export var face_texture: Texture2D
@export var back_texture: Texture2D
const UNKNOWN_FACE: Texture2D = preload("res://assets/question.svg")
@export var face_up := true
## Presentation state only. Keep secret data server-side in a future network layer.
@export var face_hidden := false:
	set(value):
		if face_hidden == value: return
		face_hidden = value
		_refresh_face()
		face_visibility_changed.emit(self, value)
@export var hover_scale := 1.1
var hover_offset := Vector3(0,0.14,0)
var viewer_masked := false
var data: Dictionary = {}
var zone: StringName = &"hand"
var selected := false
var hovered := false
var dragging := false
var visual: Node3D
var marker: MeshInstance3D
var area: Area3D
var _face_material: StandardMaterial3D
var _flip_tween: Tween
var _motion: Tween
var _hover_tween: Tween

func _ready() -> void:
	rebuild()

func configure(config: Dictionary) -> void:
	data = config.duplicate(true)
	card_size = config.get("size", card_size)
	card_size = Vector2(maxf(card_size.x, 0.2), maxf(card_size.y, 0.2))
	thickness = clampf(config.get("thickness", thickness), 0.015, 0.2)
	face_texture = config.get("face", null) # A replacement with no face must never retain an old identity.
	back_texture = config.get("back", back_texture)
	face_up = config.get("face_up", face_up)
	face_hidden = config.get("face_hidden", face_hidden)
	if is_inside_tree(): rebuild()

func outline(extra := 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var half := card_size * 0.5 + Vector2.ONE * extra
	var radius := clampf(corner_radius + extra, 0.01, minf(half.x, half.y))
	for corner in range(4):
		var center := Vector2((-1 if corner == 0 or corner == 3 else 1) * (half.x-radius), (-1 if corner < 2 else 1) * (half.y-radius))
		var angle := PI + corner * PI / 2.0
		for step in range(9):
			var a := angle + float(step)/8.0 * PI/2.0
			points.append(center + Vector2(cos(a), sin(a)) * radius)
	return points

func surface_mesh(y: float, extra := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := outline(extra)
	for i in p.size():
		for v in [Vector2.ZERO, p[i], p[(i+1)%p.size()]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v.x/card_size.x+0.5, v.y/card_size.y+0.5))
			st.add_vertex(Vector3(v.x,y,v.y))
	return st.commit()

func material(color: Color, texture: Texture2D = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = texture
	mat.roughness = 0.76
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func rebuild() -> void:
	if is_instance_valid(_flip_tween): _flip_tween.kill()
	if is_instance_valid(_hover_tween): _hover_tween.kill()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	visual.rotation.z = 0.0 if face_up else PI
	visual.scale = Vector3.ONE * (hover_scale if hovered else 1.0)
	visual.position = hover_offset if hovered else Vector3.ZERO
	var face := MeshInstance3D.new()
	face.mesh = surface_mesh(thickness/2.0)
	_face_material = material(Color.WHITE)
	_refresh_face()
	face.material_override = _face_material
	_face_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.add_child(face)
	var back := MeshInstance3D.new()
	back.mesh = surface_mesh(thickness/2.0)
	back.rotation.z = PI
	back.material_override = material(Color.WHITE, back_texture)
	back.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.add_child(back)
	var edge := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := outline()
	for i in p.size():
		var a := p[i]
		var b := p[(i+1)%p.size()]
		var aa := Vector3(a.x,-thickness/2,a.y)
		var ab := Vector3(a.x,thickness/2,a.y)
		var ba := Vector3(b.x,-thickness/2,b.y)
		var bb := Vector3(b.x,thickness/2,b.y)
		for v in [aa,ab,ba,ba,ab,bb]: st.add_vertex(v)
	st.generate_normals()
	edge.mesh = st.commit()
	edge.material_override = material(Color("d5d1ba"))
	visual.add_child(edge)
	marker = MeshInstance3D.new()
	marker.mesh = surface_mesh(-thickness/2.0-0.007, 0.045)
	var highlight := material(Color("b9efd8"))
	highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = highlight
	marker.visible = selected or hovered
	add_child(marker)
	area = Area3D.new()
	area.set_meta("card", self)
	area.collision_layer = 1
	area.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(card_size.x, thickness+0.12, card_size.y)
	collision.shape = box
	area.add_child(collision)
	add_child(area)

## This flag is independent of physical orientation and never clears card data.
func set_face_hidden(value: bool) -> void:
	face_hidden = value

func set_viewer_masked(value: bool) -> void:
	viewer_masked = value
	_refresh_face()

func _refresh_face() -> void:
	if is_instance_valid(_face_material):
		_face_material.albedo_texture = back_texture if viewer_masked else (UNKNOWN_FACE if face_hidden or face_texture == null else face_texture)

func public_description() -> String:
	if viewer_masked or not face_up: return "牌背"
	if face_hidden or face_texture == null: return "未知卡牌"
	return str(data.get("title", "卡牌"))

## Safe UI-facing allowlist, not an authoritative networking/security boundary.
## No identifiers, arbitrary metadata, paths or resources from data are copied.
func public_snapshot() -> Dictionary:
	var snapshot := {
		"face_up": face_up,
		"face_hidden": face_hidden,
		"zone": str(zone),
		"selected": selected,
		"description": public_description(),
	}
	if face_up and not viewer_masked and not face_hidden and face_texture != null:
		snapshot["title"] = str(data.get("title", "卡牌"))
	return snapshot

func set_face_up(value: bool, animated := true) -> void:
	if face_up == value: return
	face_up = value
	if is_instance_valid(_flip_tween): _flip_tween.kill()
	if not is_instance_valid(visual):
		flipped.emit(self, face_up)
		return
	if animated:
		_flip_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_flip_tween.tween_property(visual,"rotation:z",0.0 if value else PI,0.35)
	else: visual.rotation.z = 0.0 if value else PI
	flipped.emit(self,face_up)

func set_selected(value: bool) -> void:
	if selected == value: return
	selected = value
	marker.visible = selected or hovered
	selection_changed.emit(self, selected)

func set_hovered(value: bool) -> void:
	if hovered == value: return
	hovered = value
	marker.visible = selected or hovered
	if is_instance_valid(_hover_tween): _hover_tween.kill()
	_hover_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD)
	_hover_tween.tween_property(visual,"scale", Vector3.ONE * (hover_scale if value else 1.0),0.15)
	_hover_tween.tween_property(visual,"position",hover_offset if value else Vector3.ZERO,0.15)
	_hover_tween.tween_property(marker,"position",hover_offset if value else Vector3.ZERO,0.15)
	_hover_tween.tween_property(marker,"scale",Vector3.ONE * (hover_scale if value else 1.0),0.15)

func move_to(target: Vector3, angle := 0.0, animated := true) -> void:
	if is_instance_valid(_motion): _motion.kill()
	if not animated:
		position = target
		rotation.y = angle
		return
	_motion = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion.tween_property(self,"position",target,0.3)
	_motion.tween_property(self,"rotation:y",angle,0.3)

func begin_drag() -> void:
	if dragging: return
	dragging = true
	if is_instance_valid(_motion): _motion.kill()
	set_hovered(false)
	drag_started.emit(self)

func end_drag(accepted: bool) -> void:
	if not dragging: return
	dragging = false
	drag_finished.emit(self, accepted)

func set_zone(value: StringName) -> void:
	if zone == value: return
	var old := zone
	zone = value
	zone_changed.emit(self, old, zone)
