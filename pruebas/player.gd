extends CharacterBody3D

@export var speed := 4.5
@export var mouse_sensitivity := 0.0025
@export var stick_deadzone := 0.18
@export var controller_look_speed := 2.4

@onready var head: Node3D = $Head

var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var active_joypad := -1
var hit_flash_time := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var connected_joypads := Input.get_connected_joypads()
	if not connected_joypads.is_empty():
		active_joypad = connected_joypads[0]
		print("Mando conectado: ", Input.get_joy_name(active_joypad))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))
	elif event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if hit_flash_time > 0.0:
		hit_flash_time -= delta
		get_node("../Interface/Instructions").modulate = Color(1, 0.25, 0.25, 1)
	elif get_node("../Interface/Instructions").modulate != Color.WHITE:
		get_node("../Interface/Instructions").modulate = Color.WHITE
	var keyboard_input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var controller_input := _get_controller_movement()
	var input_vector := controller_input if controller_input.length() > stick_deadzone else keyboard_input
	var direction := (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	var look_input := _get_controller_look()
	if look_input.length() > stick_deadzone:
		rotate_y(-look_input.x * controller_look_speed * delta)
		head.rotate_x(-look_input.y * controller_look_speed * delta)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	move_and_slide()


func hit_by_spider_projectile() -> void:
	hit_flash_time = 0.35


func _get_controller_movement() -> Vector2:
	if active_joypad == -1:
		return Vector2.ZERO
	return Vector2(
		Input.get_joy_axis(active_joypad, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(active_joypad, JOY_AXIS_LEFT_Y)
	).limit_length()


func _get_controller_look() -> Vector2:
	if active_joypad == -1:
		return Vector2.ZERO
	return Vector2(
		Input.get_joy_axis(active_joypad, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(active_joypad, JOY_AXIS_RIGHT_Y)
	).limit_length()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		active_joypad = device
		print("Mando conectado: ", Input.get_joy_name(active_joypad))
	elif device == active_joypad:
		active_joypad = -1
		print("Mando desconectado")
