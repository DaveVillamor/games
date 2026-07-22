extends Node3D

@export var patrol_points := PackedVector3Array([
	Vector3(0, 1.25, -6.0),
	Vector3(-1.2, 1.0, 0.5),
	Vector3(1.1, 1.35, 7.0),
	Vector3(0, 1.1, 10.0)
])
@export var travel_speed := 0.55
@export var pause_duration := 1.8

@onready var particles: GPUParticles3D = $Particles

var target_index := 1
var pause_time := 0.0
var elapsed := 0.0


func _ready() -> void:
	_apply_soft_particle_texture()
	particles.restart()


func _process(delta: float) -> void:
	if patrol_points.is_empty():
		return
	elapsed += delta
	if pause_time > 0.0:
		pause_time -= delta
		return

	var target := patrol_points[target_index]
	var next_position := position.move_toward(target, travel_speed * delta)
	next_position.x += sin(elapsed * 0.72) * 0.0025
	next_position.y += sin(elapsed * 0.48) * 0.0018
	position = next_position
	if position.distance_to(target) < 0.08:
		target_index = (target_index + 1) % patrol_points.size()
		pause_time = pause_duration


func _apply_soft_particle_texture() -> void:
	var quad := particles.draw_pass_1 as QuadMesh
	if quad == null:
		return
	var material := quad.material as StandardMaterial3D
	if material == null:
		return
	material.albedo_texture = _create_cloud_texture(96)


func _create_cloud_texture(texture_size: int) -> ImageTexture:
	var image := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	for y in texture_size:
		for x in texture_size:
			var uv := Vector2(float(x), float(y)) / float(texture_size - 1)
			var centered := uv * 2.0 - Vector2.ONE
			var radial := clampf(1.0 - centered.length(), 0.0, 1.0)
			var detail := 0.72 + 0.18 * sin(uv.x * 31.0 + sin(uv.y * 17.0)) + 0.1 * sin(uv.y * 43.0)
			var alpha := pow(radial, 1.8) * clampf(detail, 0.45, 1.0)
			image.set_pixel(x, y, Color(0.82, 0.9, 1.0, alpha))
	return ImageTexture.create_from_image(image)
