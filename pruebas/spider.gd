extends CharacterBody3D

@export var target_path: NodePath
@export var move_speed := 0.95
@export var body_height := 1.15
@export var upper_leg_length := 1.65
@export var lower_leg_length := 1.85
@export var resting_leg_radius := 2.05
@export var attack_range := 8.0
@export var attack_cooldown := 2.8

const PROJECTILE_SCRIPT = preload("res://spider_projectile.gd")

var target: Node3D
var legs: Array[Dictionary] = []
var skeleton_material: StandardMaterial3D
var leg_directions: Array = [
	Vector3(0.72, 0, -0.92).normalized(),
	Vector3(1.0, 0, -0.3).normalized(),
	Vector3(1.0, 0, 0.28).normalized(),
	Vector3(0.72, 0, 0.94).normalized()
]
var diagonal_pairs: Array = [[4, 3], [0, 7], [5, 2], [1, 6]]
var active_pair := 0
var locomotion_time := 0.0
var attack_timer := 0.0
const STEP_THRESHOLD := 0.36


func _ready() -> void:
	target = get_node_or_null(target_path) as Node3D
	skeleton_material = StandardMaterial3D.new()
	skeleton_material.albedo_color = Color(0.13, 0.19, 0.25)
	skeleton_material.metallic = 0.65
	skeleton_material.roughness = 0.3
	_add_body_collision()
	_build_body()
	_build_legs()
	_add_fog_particles()


func _physics_process(delta: float) -> void:
	locomotion_time += delta
	attack_timer = max(attack_timer - delta, 0.0)
	_move_body(delta)
	_prepare_next_step()
	for index in legs.size():
		_update_leg(legs[index], index, delta)
	_try_attack()


func _add_body_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.05
	collision.shape = shape
	collision.position = Vector3(0, 0.08, 0)
	add_child(collision)


func _add_fog_particles() -> void:
	var fog := GPUParticles3D.new()
	fog.name = "PartialFog"
	fog.amount = 150
	fog.lifetime = 4.4
	fog.visibility_aabb = AABB(Vector3(-3.8, -1.0, -3.8), Vector3(7.6, 3.4, 7.6))
	fog.draw_pass_1 = _fog_quad_mesh()
	fog.process_material = _fog_process_material()
	add_child(fog)


func _fog_quad_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.42)
	quad.orientation = PlaneMesh.FACE_Z
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.62, 0.76, 0.9, 0.26)
	material.albedo_texture = _soft_particle_texture()
	material.no_depth_test = false
	quad.material = material
	return quad


func _soft_particle_texture() -> ImageTexture:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var uv := Vector2(float(x) / float(size - 1), float(y) / float(size - 1))
			var distance_from_center: float = uv.distance_to(Vector2(0.5, 0.5))
			var alpha: float = clampf((0.5 - distance_from_center) / 0.28, 0.0, 1.0)
			alpha = alpha * alpha * (3.0 - 2.0 * alpha)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(image)


func _fog_process_material() -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 2.4
	process.direction = Vector3(0.12, 0.35, 0.08)
	process.spread = 115.0
	process.gravity = Vector3(0, 0.14, 0)
	process.initial_velocity_min = 0.08
	process.initial_velocity_max = 0.22
	process.scale_min = 0.45
	process.scale_max = 0.95
	process.color = Color(0.7, 0.82, 0.96, 0.3)
	return process


func _build_body() -> void:
	_add_sphere("Thorax", Vector3(0, 0, 0), Vector3(1.15, 0.65, 1.25))
	_add_sphere("Abdomen", Vector3(0, 0.06, 0.9), Vector3(1.0, 0.72, 1.25))
	_add_sphere("Head", Vector3(0, -0.02, -0.95), Vector3(0.7, 0.48, 0.62))


func _build_legs() -> void:
	for side in [-1.0, 1.0]:
		for row in 4:
			var radial: Vector3 = leg_directions[row] as Vector3
			var hip_local := Vector3(side * 0.82, -0.12, radial.z * 0.82)
			var outward := Vector3(radial.x * side, 0, radial.z).normalized()
			var desired := global_position + hip_local + outward * resting_leg_radius
			var foot := _find_support(desired)
			var leg := {
				"hip": hip_local,
				"outward": outward,
				"foot": foot,
				"step_from": foot,
				"step_to": foot,
				"step": 1.0,
				"lift": 0.38 + float(row) * 0.03,
				"arc": Vector3.ZERO,
				"upper": _add_bone("UpperLeg", 0.12),
				"lower": _add_bone("LowerLeg", 0.09),
				"knee": _add_joint("Knee", 0.16),
				"foot_joint": _add_joint("Foot", 0.11)
			}
			legs.append(leg)


func _move_body(delta: float) -> void:
	if target == null:
		return
	var offset := target.global_position - global_position
	offset.y = 0.0
	if offset.length() > 4.5:
		var direction := _choose_direction(offset.normalized())
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		move_and_slide()
		look_at(global_position + direction, Vector3.UP, true)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	global_position.x = clamp(global_position.x, -22.0, 22.0)
	global_position.z = clamp(global_position.z, -22.0, 22.0)
	global_position.y = body_height + sin(locomotion_time * 3.0) * 0.035


func _choose_direction(direct_direction: Vector3) -> Vector3:
	var forward_clearance := _clearance(direct_direction)
	if forward_clearance > 3.0:
		return direct_direction
	var left := direct_direction.rotated(Vector3.UP, 0.72).normalized()
	var right := direct_direction.rotated(Vector3.UP, -0.72).normalized()
	var left_clearance := _clearance(left)
	var right_clearance := _clearance(right)
	return left if left_clearance > right_clearance else right


func _clearance(direction: Vector3) -> float:
	var state := get_world_3d().direct_space_state
	var start := global_position + Vector3.UP * 0.15
	var query := PhysicsRayQueryParameters3D.create(start, start + direction * 4.0)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	var hit := state.intersect_ray(query)
	if hit.is_empty():
		return 4.0
	return start.distance_to(hit.position)


func _try_attack() -> void:
	if target == null or attack_timer > 0.0:
		return
	var target_point := target.global_position + Vector3.UP * 1.45
	if global_position.distance_to(target_point) > attack_range:
		return
	var launch_point := global_position + global_transform.basis.z * -0.95 + Vector3.UP * 0.25
	var state := get_world_3d().direct_space_state
	var sight_query := PhysicsRayQueryParameters3D.create(launch_point, target_point)
	sight_query.exclude = [get_rid()]
	sight_query.collision_mask = 1
	var sight_hit := state.intersect_ray(sight_query)
	if not sight_hit.is_empty() and sight_hit.collider != target:
		return

	var projectile := PROJECTILE_SCRIPT.new() as Node3D
	get_parent().add_child(projectile)
	projectile.global_position = launch_point
	var horizontal := target_point - launch_point
	horizontal.y = 0.0
	projectile.velocity = horizontal.normalized() * 10.0 + Vector3.UP * 3.2
	projectile.owner_rid = get_rid()
	attack_timer = attack_cooldown


func _prepare_next_step() -> void:
	var swinging_legs := 0
	for leg in legs:
		if leg["step"] < 1.0:
			swinging_legs += 1
	if swinging_legs > 0:
		return

	var pair: Array = diagonal_pairs[active_pair]
	var pair_started := false
	for leg_index in pair:
		if _start_step_if_needed(leg_index):
			pair_started = true
	active_pair = (active_pair + 1) % diagonal_pairs.size()
	if not pair_started:
		return


func _start_step_if_needed(index: int) -> bool:
	var leg := legs[index]
	var hip: Vector3 = global_transform * (leg["hip"] as Vector3)
	var outward: Vector3 = global_transform.basis * (leg["outward"] as Vector3)
	var heading: Vector3 = -global_transform.basis.z
	var desired: Vector3 = hip + outward * resting_leg_radius + heading * 0.42
	var next_support: Vector3 = _find_support(desired)
	var foot: Vector3 = leg["foot"]
	var local_support: Vector3 = to_local(next_support)
	var leg_side: float = sign((leg["hip"] as Vector3).x)
	if sign(local_support.x) != leg_side or abs(local_support.x) < 0.65:
		return false
	for other_leg in legs:
		if other_leg == leg:
			continue
		if next_support.distance_to(other_leg["foot"] as Vector3) < 0.65:
			return false
	if foot.distance_to(next_support) <= STEP_THRESHOLD:
		return false
	leg["step_from"] = foot
	leg["step_to"] = next_support
	leg["step"] = 0.0
	leg["arc"] = heading.cross(Vector3.UP).normalized() * sign(outward.dot(global_transform.basis.x))
	return true


func _update_leg(leg: Dictionary, _index: int, delta: float) -> void:
	var hip: Vector3 = global_transform * (leg["hip"] as Vector3)
	var foot: Vector3 = leg["foot"]

	if leg["step"] < 1.0:
		leg["step"] += delta * 4.8
		var progress: float = min(leg["step"], 1.0)
		foot = leg["step_from"].lerp(leg["step_to"], progress)
		foot += (leg["arc"] as Vector3) * sin(progress * PI) * 0.24
		foot.y += sin(progress * PI) * (leg["lift"] as float)
		leg["foot"] = foot

	var outward_bias: Vector3 = global_transform.basis * (leg["outward"] as Vector3)
	var knee: Vector3 = hip + outward_bias * upper_leg_length * 0.68
	var step_progress: float = min(leg["step"] as float, 1.0)
	knee.y = hip.y + 0.32 + sin(step_progress * PI) * 0.18

	_place_bone(leg["upper"], hip, knee)
	_place_bone(leg["lower"], knee, foot)
	leg["knee"].global_position = knee
	leg["foot_joint"].global_position = foot


func _find_support(desired: Vector3) -> Vector3:
	var state := get_world_3d().direct_space_state
	var probes := [
		[desired + Vector3.UP * 5.0, desired + Vector3.DOWN * 7.0],
		[desired, desired + Vector3.RIGHT * 3.0],
		[desired, desired + Vector3.LEFT * 3.0],
		[desired, desired + Vector3.FORWARD * 3.0],
		[desired, desired + Vector3.BACK * 3.0],
		[desired, desired + Vector3.UP * 5.0]
	]
	var closest_point := Vector3.INF
	var closest_distance := INF
	for probe in probes:
		var query := PhysicsRayQueryParameters3D.create(probe[0], probe[1])
		query.collision_mask = 1
		var hit := state.intersect_ray(query)
		if not hit.is_empty():
			var hit_point: Vector3 = hit.position
			var hit_distance := desired.distance_to(hit_point)
			if hit_distance < closest_distance:
				closest_distance = hit_distance
				closest_point = hit_point + (hit.normal as Vector3) * 0.05
	if closest_point != Vector3.INF:
		return closest_point
	return desired + Vector3.DOWN * body_height


func _add_sphere(part_name: String, offset: Vector3, scale_factor: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.position = offset
	part.scale = scale_factor
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.material = skeleton_material
	part.mesh = mesh
	add_child(part)
	return part


func _add_bone(part_name: String, radius: float) -> MeshInstance3D:
	var bone := MeshInstance3D.new()
	bone.name = part_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.75
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.material = skeleton_material
	bone.mesh = mesh
	add_child(bone)
	return bone


func _add_joint(part_name: String, radius: float) -> MeshInstance3D:
	var joint := MeshInstance3D.new()
	joint.name = part_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = skeleton_material
	joint.mesh = mesh
	add_child(joint)
	return joint


func _place_bone(bone: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var direction := end - start
	bone.global_position = start.lerp(end, 0.5)
	bone.global_basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	bone.scale = Vector3(1.0, direction.length(), 1.0)
