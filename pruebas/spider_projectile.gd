extends Node3D

var velocity := Vector3.ZERO
var owner_rid: RID
var life := 4.0


func _ready() -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.85, 0.34, 1)
	material.emission_enabled = true
	material.emission = Color(0.04, 0.7, 0.12, 1)
	material.emission_energy_multiplier = 2.0
	mesh.material = material
	mesh_instance.mesh = mesh
	add_child(mesh_instance)


func _physics_process(delta: float) -> void:
	var previous_position := global_position
	velocity.y -= 8.5 * delta
	global_position += velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return

	var state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(previous_position, global_position)
	query.exclude = [owner_rid]
	query.collision_mask = 1
	var hit := state.intersect_ray(query)
	if not hit.is_empty():
		if hit.collider.has_method("hit_by_spider_projectile"):
			hit.collider.hit_by_spider_projectile()
		queue_free()
