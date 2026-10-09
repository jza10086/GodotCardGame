extends Node3D
## Generic face-up multi-row table. Stable IDs keep the same Card3D during deals
## and reveals; masked cards receive no face texture or title until revealed.
const CARD_SCENE = preload("res://scenes/card_3d.tscn")
var card_nodes: Dictionary = {}
var camera: Camera3D
var animation_left := 0.0
var font: Font = preload("res://assets/ui_font.ttf")
var source_position := Vector3(7, 0.25, -0.2)

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b171f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c8dddc")
	env.ambient_light_energy = 0.85
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60,-25,0)
	light.light_energy = 0.65
	add_child(light)
	_slab(Vector3(26,0.7,17),Vector3(0,-0.6,0),Color("192a30"))
	_slab(Vector3(22,0.15,14),Vector3(0,-0.18,0),Color("194941"))
	_slab(Vector3(21.65,0.04,13.65),Vector3(0,-0.08,0),Color("21594d"))
	camera = Camera3D.new()
	camera.position = Vector3(0,17,9.3)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 21.5
	add_child(camera)
	camera.look_at(Vector3(0,0,0))
	camera.current = true
	for z in [-2.5,2.2]:
		_slab(Vector3(11.8,0.015,0.025),Vector3(0,-0.01,z+1.45),Color("779a79"))
	var logo := Label3D.new()
	logo.font = font
	logo.text = "T W E N T Y   O N E"
	logo.font_size = 58
	logo.pixel_size = 0.008
	logo.modulate = Color("a8b995")
	logo.rotation_degrees.x = -90
	logo.position = Vector3(0,0.015,-0.05)
	add_child(logo)

func _slab(dimensions: Vector3, at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size = dimensions
	mesh.mesh = box; mesh.position = at
	var mat := StandardMaterial3D.new(); mat.albedo_color = color; mat.roughness = 0.95
	mesh.material_override = mat
	add_child(mesh)

func present_rows(rows: Array, texture_provider: Callable, animated := true) -> bool:
	var seen := {}
	for row in rows:
		for record in row.cards:
			if not record.has("id") or seen.has(record.id): return false
			seen[record.id] = true
	for id in card_nodes.keys():
		if not seen.has(id):
			card_nodes[id].queue_free(); card_nodes.erase(id)
	for row in rows:
		var cards: Array = row.cards
		var card_scale := float(row.get("card_scale",1.0)) * minf(1.0,6.0/maxf(cards.size(),1))
		card_scale=maxf(card_scale,0.8)
		var max_width := float(row.get("max_width",12.0))
		var step := minf(1.84*card_scale,(max_width-1.65*card_scale)/maxf(cards.size()-1,1))
		for i in cards.size():
			var record: Dictionary = cards[i]
			var hidden: bool = record.get("hidden",false)
			var node: Card3D = card_nodes.get(record.id)
			var fresh := node == null
			if fresh:
				node = CARD_SCENE.instantiate()
				var config: Dictionary = texture_provider.call(record,hidden)
				config["face_up"] = false if animated else not hidden
				node.configure(config); add_child(node)
				node.position = source_position
				card_nodes[record.id] = node
			elif not hidden and node.face_texture == null:
				var config: Dictionary = texture_provider.call(record,false)
				node.face_texture = config.face
				node.data = config.duplicate()
				node._refresh_face()
			node.scale=Vector3.ONE*card_scale
			node.set_viewer_masked(hidden)
			node.set_face_up(not hidden,animated)
			node.set_zone(StringName(row.get("zone","public")))
			var target := Vector3((i-(cards.size()-1)*0.5)*step,0.08+i*0.004,float(row.z))
			node.move_to(target,0.0,animated)
	animation_left = 0.45 if animated else 0.0
	return true

func _process(delta: float) -> void:
	animation_left = maxf(0,animation_left-delta)

func is_animating() -> bool:
	return animation_left > 0
