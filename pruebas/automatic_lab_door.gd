extends Node3D

@export var left_door_path: NodePath
@export var right_door_path: NodePath
@export var trigger_path: NodePath
@export var lab_presence_path: NodePath
@export var opening_distance := 2.35
@export var transition_time := 0.62
@export var opening_axis := Vector3.RIGHT
@export var controls_lab_lighting := true

@onready var left_door: Node3D = get_node(left_door_path)
@onready var right_door: Node3D = get_node(right_door_path)
@onready var trigger: Area3D = get_node(trigger_path)
@onready var lab_presence: Area3D = get_node_or_null(lab_presence_path) as Area3D if not lab_presence_path.is_empty() else null

var left_closed_position: Vector3
var right_closed_position: Vector3
var occupants := 0
var laboratory_occupants := 0
var door_tween: Tween


func _ready() -> void:
	left_closed_position = left_door.position
	right_closed_position = right_door.position
	trigger.body_entered.connect(_on_body_entered)
	trigger.body_exited.connect(_on_body_exited)
	if controls_lab_lighting and lab_presence:
		lab_presence.body_entered.connect(_on_lab_body_entered)
		lab_presence.body_exited.connect(_on_lab_body_exited)
	if controls_lab_lighting:
		_set_lab_lighting(false)
		_set_door_seals(true)


func _on_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	occupants += 1
	_open_doors()
	if controls_lab_lighting:
		_set_lab_lighting(true)


func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	occupants = max(occupants - 1, 0)
	await get_tree().create_timer(1.1).timeout
	if occupants == 0:
		_close_doors()


func _on_lab_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	laboratory_occupants += 1
	_set_lab_lighting(true)


func _on_lab_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	laboratory_occupants = max(laboratory_occupants - 1, 0)


func _open_doors() -> void:
	if door_tween and door_tween.is_running():
		door_tween.kill()
	var slide_axis := opening_axis.normalized()
	if slide_axis.is_zero_approx():
		slide_axis = Vector3.RIGHT
	door_tween = create_tween().set_parallel(true)
	door_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	door_tween.tween_property(left_door, "position", left_closed_position - slide_axis * opening_distance, transition_time)
	door_tween.tween_property(right_door, "position", right_closed_position + slide_axis * opening_distance, transition_time)
	if controls_lab_lighting:
		_set_door_seals(false)


func _close_doors() -> void:
	if door_tween and door_tween.is_running():
		door_tween.kill()
	door_tween = create_tween().set_parallel(true)
	door_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	door_tween.tween_property(left_door, "position", left_closed_position, transition_time)
	door_tween.tween_property(right_door, "position", right_closed_position, transition_time)
	if controls_lab_lighting:
		_set_door_seals(true)


func _set_lab_lighting(enabled: bool) -> void:
	for light in get_tree().get_nodes_in_group("laboratory_lights"):
		light.visible = enabled


func _set_door_seals(closed: bool) -> void:
	var warning_light := get_node_or_null("DoorWarningSpot") as SpotLight3D
	if warning_light:
		warning_light.visible = closed
	var warning_strip := get_node_or_null("DoorCenterLight") as Node3D
	if warning_strip:
		warning_strip.visible = closed
	var laboratory_strip := get_node_or_null("DoorCenterLightLab") as Node3D
	if laboratory_strip:
		laboratory_strip.visible = closed
