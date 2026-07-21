extends Node3D

const ARENA_HALF_SIZE := 25.0


func _ready() -> void:
	_expand_floor()
	_remove_legacy_room()
	_build_hangar()
	_add_global_light()
	$Player/Head/Camera3D.far = 100.0


func _expand_floor() -> void:
	var floor_mesh := $Floor/Mesh.mesh as BoxMesh
	var floor_shape := $Floor/Collision.shape as BoxShape3D
	floor_mesh.size = Vector3(ARENA_HALF_SIZE * 2.0, 0.2, ARENA_HALF_SIZE * 2.0)
	floor_shape.size = floor_mesh.size
	var floor_material := floor_mesh.material as StandardMaterial3D
	floor_material.uv1_scale = Vector3(14, 14, 1)


func _remove_legacy_room() -> void:
	for node_name in ["BackWall", "FrontWall", "LeftWall", "RightWall", "DeformedBackWall", "DeformedFrontWall", "DeformedLeftWall", "DeformedRightWall"]:
		var wall := get_node_or_null(node_name) as Node3D
		if wall:
			wall.visible = false
			if wall is CollisionObject3D:
				wall.collision_layer = 0


func _build_hangar() -> void:
	var geometry := Node3D.new()
	geometry.name = "HangarGeometry"
	add_child(geometry)

	var hull_material := _material(Color(0.16, 0.21, 0.3), 0.55, 0.48)
	var support_material := _material(Color(0.24, 0.31, 0.42), 0.38, 0.58)
	var accent_material := _material(Color(0.07, 0.23, 0.36), 0.5, 0.34, Color(0.0, 0.16, 0.48))

	_spawn_box(geometry, "NorthHull", Vector3(0, 4, -ARENA_HALF_SIZE), Vector3(50, 8, 0.6), hull_material)
	_spawn_box(geometry, "SouthHull", Vector3(0, 4, ARENA_HALF_SIZE), Vector3(50, 8, 0.6), hull_material)
	_spawn_box(geometry, "WestHull", Vector3(-ARENA_HALF_SIZE, 4, 0), Vector3(0.6, 8, 50), hull_material)
	_spawn_box(geometry, "EastHull", Vector3(ARENA_HALF_SIZE, 4, 0), Vector3(0.6, 8, 50), hull_material)

	var supports := [
		[Vector3(-15, 3, -14), Vector3(1.4, 6, 1.4)],
		[Vector3(-6, 4, -10), Vector3(1.2, 8, 1.2)],
		[Vector3(8, 2.5, -13), Vector3(2.0, 5, 2.0)],
		[Vector3(16, 3.5, -5), Vector3(1.4, 7, 1.4)],
		[Vector3(-15, 2.5, 5), Vector3(2.2, 5, 2.2)],
		[Vector3(-5, 3, 8), Vector3(1.5, 6, 1.5)],
		[Vector3(7, 4, 10), Vector3(1.3, 8, 1.3)],
		[Vector3(16, 2.5, 15), Vector3(2.5, 5, 2.5)]
	]
	for i in supports.size():
		var item: Array = supports[i]
		_spawn_box(geometry, "Support_%02d" % i, item[0], item[1], support_material)
		_spawn_box(geometry, "SupportCap_%02d" % i, item[0] + Vector3(0, item[1].y * 0.5 + 0.12, 0), Vector3(item[1].x * 1.5, 0.24, item[1].z * 1.5), accent_material)

	_build_parking(geometry)
	_build_office(geometry)


func _build_parking(parent: Node) -> void:
	var line_material := _painted_line_material()
	var barrier_material := _material(Color(0.62, 0.45, 0.05), 0.04, 0.88)
	var concrete_material := _material(Color(0.29, 0.31, 0.34), 0.12, 0.86)
	var car_blue := _material(Color(0.05, 0.2, 0.37), 0.7, 0.26)
	var car_red := _material(Color(0.4, 0.06, 0.05), 0.6, 0.3)
	var car_dark := _material(Color(0.08, 0.1, 0.13), 0.78, 0.22)

	# Dos hileras de plazas: los separadores y topes coinciden con cada vehículo.
	for z in [-15.0, 13.0]:
		for x in [-11.0, -5.0, 1.0, 7.0, 13.0, 19.0]:
			_spawn_painted_marking(parent, "BayDivider", Vector3(x, 0.104, z), Vector2(0.1, 4.8), line_material)
			_spawn_visual_box(parent, "WheelStop", Vector3(x + 2.75, 0.22, z), Vector3(0.2, 0.2, 1.65), concrete_material)
	for x in [-16.0, 22.0]:
		_spawn_painted_marking(parent, "DriveLaneEdge", Vector3(x, 0.104, 0), Vector2(0.14, 43), line_material)
	_spawn_painted_marking(parent, "CenterLane", Vector3(3.0, 0.104, 0), Vector2(0.12, 18), line_material)

	_spawn_vehicle(parent, "BlueSedan", Vector3(-8.0, 0.0, -15.0), car_blue)
	_spawn_vehicle(parent, "RedSedan", Vector3(4.0, 0.0, -15.0), car_red)
	_spawn_vehicle(parent, "DarkSedan", Vector3(10.0, 0.0, 13.0), car_dark)

	for location in [Vector3(-1, 0.75, -20), Vector3(18, 0.75, -7), Vector3(-16, 0.75, 7)]:
		_spawn_box(parent, "SafetyBarrier", location, Vector3(3.2, 1.5, 0.22), barrier_material)


func _build_office(parent: Node) -> void:
	var wall_material := _material(Color(0.18, 0.21, 0.24), 0.25, 0.72)
	var glass_material := _material(Color(0.1, 0.35, 0.48, 0.52), 0.42, 0.18, Color(0.0, 0.1, 0.22))
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var wood_material := _material(Color(0.24, 0.13, 0.07), 0.08, 0.7)
	var screen_material := _material(Color(0.03, 0.1, 0.15), 0.25, 0.2, Color(0.0, 0.45, 0.9))
	var chair_material := _material(Color(0.07, 0.08, 0.1), 0.3, 0.6)

	_spawn_box(parent, "OfficeBackWall", Vector3(-18, 3, -21.6), Vector3(12, 6, 0.35), wall_material)
	_spawn_box(parent, "OfficeSideWall", Vector3(-23.8, 3, -17), Vector3(0.35, 6, 9), wall_material)
	_spawn_visual_box(parent, "OfficeGlassA", Vector3(-20.9, 3, -12.7), Vector3(5.2, 5.6, 0.08), glass_material)
	_spawn_visual_box(parent, "OfficeGlassB", Vector3(-15.0, 3, -14.8), Vector3(0.08, 5.6, 4.1), glass_material)
	_spawn_box(parent, "OfficeDoorFrame", Vector3(-18.2, 1.5, -12.7), Vector3(1.4, 3, 0.16), wall_material)
	for x in [-23.1, -20.9, -18.2, -15.7]:
		_spawn_visual_box(parent, "GlassFrame", Vector3(x, 3, -12.62), Vector3(0.12, 5.7, 0.14), wall_material)

	_spawn_box(parent, "OfficeDesk", Vector3(-19.5, 1.0, -18.2), Vector3(4.8, 0.18, 1.35), wood_material)
	for desk_leg in [Vector3(-21.5, 0.5, -18.65), Vector3(-21.5, 0.5, -17.75), Vector3(-17.5, 0.5, -18.65), Vector3(-17.5, 0.5, -17.75)]:
		_spawn_visual_cylinder(parent, "DeskLeg", desk_leg, 0.08, 1.0, wall_material)
	_spawn_visual_box(parent, "Monitor", Vector3(-19.5, 1.75, -18.4), Vector3(1.3, 0.85, 0.08), screen_material)
	_spawn_visual_cylinder(parent, "MonitorStand", Vector3(-19.5, 1.28, -18.25), 0.07, 0.5, chair_material)
	_spawn_box(parent, "OfficeChairSeat", Vector3(-19.5, 0.72, -16.7), Vector3(1.0, 0.18, 0.9), chair_material)
	_spawn_box(parent, "OfficeChairBack", Vector3(-19.5, 1.22, -17.05), Vector3(1.0, 0.9, 0.15), chair_material)
	_spawn_visual_cylinder(parent, "ChairStem", Vector3(-19.5, 0.4, -16.7), 0.09, 0.65, chair_material)
	_spawn_visual_cylinder(parent, "ChairBase", Vector3(-19.5, 0.08, -16.7), 0.52, 0.08, chair_material)
	_spawn_box(parent, "ArchiveCabinet", Vector3(-22.2, 1.2, -19.5), Vector3(0.9, 2.4, 1.6), wall_material)
	_spawn_box(parent, "CoffeeMachine", Vector3(-16.5, 1.15, -20.3), Vector3(0.7, 1.3, 0.65), screen_material)
	_spawn_box(parent, "OfficeShelf", Vector3(-22.1, 2.0, -15.3), Vector3(0.5, 3.8, 2.4), wall_material)
	for y in [0.65, 1.55, 2.45, 3.35]:
		_spawn_visual_box(parent, "ShelfBoard", Vector3(-21.8, y, -15.3), Vector3(0.75, 0.08, 2.2), wood_material)
	for item in [Vector3(-21.8, 0.92, -16.0), Vector3(-21.8, 1.82, -14.8), Vector3(-21.8, 2.72, -15.8)]:
		_spawn_visual_box(parent, "ArchiveBox", item, Vector3(0.5, 0.42, 0.5), wood_material)
	_spawn_visual_cylinder(parent, "PlantPot", Vector3(-16.2, 0.45, -14.2), 0.32, 0.55, wood_material)
	_spawn_visual_sphere(parent, "PlantLeaves", Vector3(-16.2, 1.05, -14.2), Vector3(0.75, 0.9, 0.75), _material(Color(0.08, 0.28, 0.12), 0.0, 0.9))

	var office_light := OmniLight3D.new()
	office_light.name = "OfficeWarmLight"
	office_light.position = Vector3(-19, 4.8, -17)
	office_light.light_color = Color(1.0, 0.7, 0.4)
	office_light.light_energy = 4.2
	office_light.omni_range = 10.0
	parent.add_child(office_light)


func _add_global_light() -> void:
	var global_light := DirectionalLight3D.new()
	global_light.name = "GlobalHangarLight"
	global_light.rotation_degrees = Vector3(-55, -25, 0)
	global_light.light_color = Color(0.82, 0.9, 1.0)
	global_light.light_energy = 1.45
	global_light.shadow_enabled = true
	add_child(global_light)
	var environment: Environment = $WorldEnvironment.environment
	environment.ambient_light_energy = 1.15


func _spawn_box(parent: Node, node_name: String, location: Vector3, size: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = location
	parent.add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)


func _spawn_visual_box(parent: Node, node_name: String, location: Vector3, size: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = location
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)


func _spawn_painted_marking(parent: Node, node_name: String, location: Vector3, size: Vector2, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = location
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)


func _spawn_vehicle(parent: Node, node_name: String, location: Vector3, paint: Material) -> void:
	var vehicle := Node3D.new()
	vehicle.name = node_name
	vehicle.position = location
	parent.add_child(vehicle)
	var tire_material := _material(Color(0.025, 0.03, 0.04), 0.12, 0.95)
	var glass_material := _material(Color(0.05, 0.12, 0.17, 0.72), 0.72, 0.08)
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var light_material := _material(Color(0.75, 0.92, 1.0), 0.05, 0.25, Color(0.45, 0.75, 1.0))

	_spawn_box(vehicle, "Chassis", Vector3(0, 0.53, 0), Vector3(1.88, 0.62, 3.95), paint)
	_spawn_visual_sphere(vehicle, "Cabin", Vector3(0, 1.02, -0.12), Vector3(0.78, 0.48, 1.18), glass_material)
	_spawn_visual_box(vehicle, "Hood", Vector3(0, 0.9, -1.38), Vector3(1.76, 0.2, 0.86), paint)
	_spawn_visual_box(vehicle, "Trunk", Vector3(0, 0.88, 1.38), Vector3(1.75, 0.18, 0.72), paint)
	for offset in [Vector3(-1.0, 0.36, -1.18), Vector3(1.0, 0.36, -1.18), Vector3(-1.0, 0.36, 1.18), Vector3(1.0, 0.36, 1.18)]:
		_spawn_visual_cylinder(vehicle, "Wheel", offset, 0.37, 0.24, tire_material, Vector3(90, 0, 0))
	for offset in [Vector3(-0.58, 0.67, -1.99), Vector3(0.58, 0.67, -1.99)]:
		_spawn_visual_box(vehicle, "Headlight", offset, Vector3(0.34, 0.18, 0.04), light_material)


func _spawn_visual_cylinder(parent: Node, node_name: String, location: Vector3, radius: float, height: float, material: Material, rotation := Vector3.ZERO) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = location
	mesh_instance.rotation_degrees = rotation
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.material = material
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)


func _spawn_visual_sphere(parent: Node, node_name: String, location: Vector3, scale_factor: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = location
	mesh_instance.scale = scale_factor
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mesh.material = material
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)


func _material(color: Color, metallic: float, roughness: float, emission := Color.TRANSPARENT) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission.a > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.5
	return material


func _painted_line_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(0.0, 0.08, UV.y) * smoothstep(0.0, 0.08, 1.0 - UV.x) * smoothstep(0.0, 0.08, 1.0 - UV.y);
	float worn_paint = step(0.19, noise(UV * vec2(22.0, 9.0))) * mix(0.58, 1.0, noise(UV * 5.0));
	float dirt = noise(UV * vec2(55.0, 17.0));
	ALBEDO = mix(vec3(0.42, 0.29, 0.035), vec3(0.72, 0.54, 0.09), dirt);
	ROUGHNESS = 0.97;
	METALLIC = 0.0;
	ALPHA = edge * worn_paint * 0.86;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
