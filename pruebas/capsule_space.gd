extends Node3D

const MOUSE_SENSITIVITY := 0.00215
const MOVE_SPEED := 3.55
const SPRINT_MULTIPLIER := 1.85
const AXIAL_ROTATION_SPEED := TAU / 120.0
const SHIP_MIN_Z := -8.75
const SHIP_MAX_Z := 25.1

@onready var ship_pivot: Node3D = $ShipPivot
@onready var interior: Node3D = $ShipPivot/Interior
@onready var space: Node3D = $Space
@onready var explorer: Node3D = $ShipPivot/Explorer
@onready var camera: Camera3D = $ShipPivot/Explorer/Camera3D

var yaw := 0.0
var pitch := -0.02
var elapsed := 0.0
var pulse_materials: Array[StandardMaterial3D] = []
var travel_specks: Array[MeshInstance3D] = []
var earth: MeshInstance3D
var moon: MeshInstance3D
var location_label: Label


func _ready() -> void:
	_build_space()
	_build_capsule()
	_build_lighting()
	_build_interface()
	_build_travel_specks()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENSITIVITY
		pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, -1.18, 1.18)
		camera.rotation = Vector3(pitch, yaw, 0.0)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var input_vector := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input_vector.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input_vector.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input_vector.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input_vector.x += 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		input_vector.y -= 1.0
	if Input.is_physical_key_pressed(KEY_E):
		input_vector.y += 1.0

	if input_vector.length_squared() > 0.0:
		input_vector = input_vector.normalized()
		var forward := -camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
		var current_speed := MOVE_SPEED * (SPRINT_MULTIPLIER if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		var world_movement := (right * input_vector.x - forward * input_vector.z + ship_pivot.global_basis.y * input_vector.y) * current_speed * delta
		var ship_local_movement := ship_pivot.global_basis.inverse() * world_movement
		explorer.position += ship_local_movement
		_constrain_to_ship()


func _process(delta: float) -> void:
	elapsed += delta
	ship_pivot.rotation.z = fmod(ship_pivot.rotation.z + AXIAL_ROTATION_SPEED * delta, TAU)
	if earth:
		earth.rotation.y += delta * 0.006
	if moon:
		moon.rotation.y += delta * 0.0015
	explorer.rotation.z = sin(elapsed * 0.42) * 0.0018
	for index in pulse_materials.size():
		pulse_materials[index].emission_energy_multiplier = 2.0 + sin(elapsed * 1.8 + float(index) * 0.63) * 0.38
	_animate_travel_specks(delta)
	_update_location_readout()


func _constrain_to_ship() -> void:
	var camera_z := explorer.position.z + camera.position.z
	var lateral_limit := 2.5
	var vertical_min := -0.82
	var vertical_max := 1.12
	if camera_z > 5.55 and camera_z < 8.15:
		lateral_limit = 1.12
		vertical_max = 0.82
	elif camera_z >= 8.15 and camera_z < 14.75:
		lateral_limit = 3.1
	elif camera_z >= 14.75 and camera_z < 15.75:
		lateral_limit = 1.18
		vertical_max = 0.84
	elif camera_z >= 15.75 and camera_z < 22.35:
		lateral_limit = 3.45
		vertical_max = 1.42
	elif camera_z >= 22.35:
		lateral_limit = 2.85
		vertical_max = 1.05
	explorer.position.x = clampf(explorer.position.x, -lateral_limit, lateral_limit)
	explorer.position.y = clampf(explorer.position.y, vertical_min, vertical_max)
	explorer.position.z = clampf(explorer.position.z, SHIP_MIN_Z, SHIP_MAX_Z)


func _update_location_readout() -> void:
	if not location_label:
		return
	var camera_z := explorer.position.z + camera.position.z
	var module := "CABINA DE MANDO"
	if camera_z >= 5.55 and camera_z < 8.15:
		module = "CONECTOR PRESURIZADO"
	elif camera_z >= 8.15 and camera_z < 14.75:
		module = "MÓDULO DE TRIPULACIÓN"
	elif camera_z >= 14.75 and camera_z < 15.75:
		module = "ESCLUSA INTERNA"
	elif camera_z >= 15.75 and camera_z < 22.35:
		module = "GALERÍA DE OBSERVACIÓN"
	elif camera_z >= 22.35:
		module = "NÚCLEO DE INGENIERÍA"
	location_label.text = "UBICACIÓN  //  %s" % module


func _build_space() -> void:
	var shell := MeshInstance3D.new()
	shell.name = "ProceduralStarfield"
	var sphere := SphereMesh.new()
	sphere.radius = 135.0
	sphere.height = 270.0
	sphere.radial_segments = 128
	sphere.rings = 64
	sphere.material = _space_material()
	shell.mesh = sphere
	space.add_child(shell)

	# Layered planet: solid surface, independently moving clouds and an atmospheric limb.
	earth = _sphere(space, "PlanetSurface", Vector3(-15.0, 4.0, -72.0), Vector3(25.0, 25.0, 25.0), _planet_material(), 128, 64)
	var clouds := _sphere(space, "PlanetClouds", earth.position, Vector3(25.28, 25.28, 25.28), _cloud_material(), 128, 64)
	clouds.rotation = Vector3(0.0, 0.0, -0.11)
	var atmosphere := _sphere(space, "PlanetAtmosphere", earth.position, Vector3(26.4, 26.4, 26.4), _atmosphere_material(), 128, 64)
	atmosphere.rotation = earth.rotation

	moon = _sphere(space, "DistantMoon", Vector3(45.0, 14.0, -91.0), Vector3(13.0, 13.0, 13.0), _moon_material(), 96, 48)
	moon.rotation = Vector3(0.18, -0.42, 0.08)

	var sun_material := _material(Color(1.0, 0.92, 0.72), 0.0, 0.0, Color(1.0, 0.82, 0.54), 7.5)
	_sphere(space, "DistantSun", Vector3(82.0, 34.0, -104.0), Vector3(2.0, 2.0, 2.0), sun_material, 48, 24)

	var moon_light := DirectionalLight3D.new()
	moon_light.name = "SolarKeyLight"
	moon_light.rotation_degrees = Vector3(-21.0, -37.0, 0.0)
	moon_light.light_color = Color(0.78, 0.86, 1.0)
	moon_light.light_energy = 1.42
	moon_light.shadow_enabled = true
	add_child(moon_light)


func _build_capsule() -> void:
	var hull := _material(Color(0.075, 0.095, 0.125), 0.78, 0.28)
	var hull_light := _material(Color(0.16, 0.19, 0.235), 0.58, 0.34)
	var frame := _material(Color(0.31, 0.34, 0.39), 0.84, 0.19)
	var rubber := _material(Color(0.018, 0.024, 0.032), 0.08, 0.78)
	var floor_material := _material(Color(0.055, 0.065, 0.08), 0.52, 0.42)
	var glass := _glass_material()
	var cyan := _material(Color(0.018, 0.11, 0.15), 0.32, 0.22, Color(0.02, 0.72, 1.0), 2.4)
	var amber := _material(Color(0.16, 0.065, 0.015), 0.22, 0.26, Color(1.0, 0.28, 0.025), 2.1)
	var white_light := _material(Color(0.68, 0.78, 0.88), 0.12, 0.18, Color(0.65, 0.84, 1.0), 2.25)
	pulse_materials.assign([cyan, amber])

	# Floor, roof and the faceted pressure hull.
	_box(interior, "PressureFloor", Vector3(0.0, 0.0, 0.0), Vector3(8.5, 0.28, 12.0), hull)
	_box(interior, "Walkway", Vector3(0.0, 0.17, 0.15), Vector3(3.3, 0.055, 10.8), floor_material)
	for x in [-1.75, 1.75]:
		_box(interior, "WalkwayRail", Vector3(x, 0.2, 0.1), Vector3(0.045, 0.035, 10.5), cyan)
	for z in [-4.8, -3.2, -1.6, 0.0, 1.6, 3.2, 4.8]:
		_box(interior, "FloorRib", Vector3(0.0, 0.205, z), Vector3(3.25, 0.035, 0.07), frame)

	_box(interior, "CeilingCore", Vector3(0.0, 4.55, 0.0), Vector3(4.35, 0.3, 12.0), hull)
	_box(interior, "LeftLowerBevel", Vector3(-3.66, 0.55, 0.0), Vector3(1.35, 0.28, 12.0), hull_light, Vector3(0.0, 0.0, -0.48))
	_box(interior, "RightLowerBevel", Vector3(3.66, 0.55, 0.0), Vector3(1.35, 0.28, 12.0), hull_light, Vector3(0.0, 0.0, 0.48))
	_box(interior, "LeftUpperBevel", Vector3(-3.45, 4.03, 0.0), Vector3(1.65, 0.28, 12.0), hull_light, Vector3(0.0, 0.0, 0.53))
	_box(interior, "RightUpperBevel", Vector3(3.45, 4.03, 0.0), Vector3(1.65, 0.28, 12.0), hull_light, Vector3(0.0, 0.0, -0.53))

	_build_side_windows(-1.0, hull, frame, rubber, glass)
	_build_side_windows(1.0, hull, frame, rubber, glass)
	_build_front_windows(hull, hull_light, frame, rubber, glass)
	_build_rear_bulkhead(hull, frame, cyan)
	_build_consoles(hull_light, frame, rubber, cyan, amber)
	_build_overhead(frame, hull, white_light, cyan)
	_build_seat(frame, rubber)
	_build_ship_modules(hull, hull_light, frame, rubber, floor_material, glass, cyan, amber, white_light)


func _build_side_windows(side: float, hull: StandardMaterial3D, frame: StandardMaterial3D, rubber: StandardMaterial3D, glass: StandardMaterial3D) -> void:
	var x := side * 4.18
	_box(interior, "SideLowerHull", Vector3(x, 1.02, 0.0), Vector3(0.3, 1.55, 11.8), hull)
	_box(interior, "SideUpperHull", Vector3(x, 3.92, 0.0), Vector3(0.3, 1.05, 11.8), hull)
	for z in [-5.48, -2.05, 1.38, 4.82]:
		_box(interior, "WindowMullion", Vector3(x, 2.48, z), Vector3(0.38, 2.1, 0.25), frame)
		_box(interior, "MullionInset", Vector3(x - side * 0.18, 2.48, z), Vector3(0.06, 1.72, 0.34), rubber)
	for z in [-3.765, -0.335, 3.10]:
		_box(interior, "SideGlass", Vector3(x + side * 0.025, 2.5, z), Vector3(0.045, 1.95, 3.05), glass)
		_box(interior, "WindowLowerTrim", Vector3(x - side * 0.2, 1.49, z), Vector3(0.08, 0.12, 3.15), frame)
		_box(interior, "WindowUpperTrim", Vector3(x - side * 0.2, 3.51, z), Vector3(0.08, 0.12, 3.15), frame)


func _build_front_windows(hull: StandardMaterial3D, hull_light: StandardMaterial3D, frame: StandardMaterial3D, rubber: StandardMaterial3D, glass: StandardMaterial3D) -> void:
	var front_z := -5.72
	_box(interior, "FrontLowerHull", Vector3(0.0, 0.74, front_z), Vector3(8.45, 1.48, 0.42), hull)
	_box(interior, "FrontUpperHull", Vector3(0.0, 4.18, front_z), Vector3(8.45, 0.82, 0.42), hull)
	for x in [-4.02, -2.17, 2.17, 4.02]:
		_box(interior, "FrontPillar", Vector3(x, 2.55, front_z), Vector3(0.34, 2.75, 0.48), frame)
	_box(interior, "FrontSideGlassL", Vector3(-3.1, 2.55, front_z + 0.02), Vector3(1.48, 2.35, 0.045), glass)
	_box(interior, "FrontSideGlassR", Vector3(3.1, 2.55, front_z + 0.02), Vector3(1.48, 2.35, 0.045), glass)

	_torus(interior, "PanoramicWindowOuter", Vector3(0.0, 2.55, front_z + 0.19), 1.64, 1.91, frame, Vector3(PI * 0.5, 0.0, 0.0), 72, 16)
	_torus(interior, "PanoramicWindowSeal", Vector3(0.0, 2.55, front_z + 0.23), 1.52, 1.64, rubber, Vector3(PI * 0.5, 0.0, 0.0), 72, 12)
	_cylinder(interior, "PanoramicGlass", Vector3(0.0, 2.55, front_z + 0.17), 1.53, 0.035, glass, Vector3(PI * 0.5, 0.0, 0.0), 72)

	for index in 16:
		var angle := TAU * float(index) / 16.0
		var bolt_position := Vector3(cos(angle) * 1.78, 2.55 + sin(angle) * 1.78, front_z + 0.44)
		_cylinder(interior, "WindowBolt", bolt_position, 0.035, 0.035, hull_light, Vector3(PI * 0.5, 0.0, 0.0), 12)


func _build_rear_bulkhead(hull: StandardMaterial3D, frame: StandardMaterial3D, cyan: StandardMaterial3D) -> void:
	# Open pressure doorway leading into the rest of the ship.
	_box(interior, "RearBulkheadLeft", Vector3(-2.76, 2.25, 5.82), Vector3(2.98, 4.5, 0.35), hull)
	_box(interior, "RearBulkheadRight", Vector3(2.76, 2.25, 5.82), Vector3(2.98, 4.5, 0.35), hull)
	_box(interior, "RearBulkheadHeader", Vector3(0.0, 4.05, 5.82), Vector3(2.55, 0.9, 0.35), hull)
	for x in [-1.32, 1.32]:
		_box(interior, "PressureDoorFrame", Vector3(x, 2.13, 5.57), Vector3(0.18, 3.55, 0.22), frame)
	_box(interior, "DoorHeader", Vector3(0.0, 3.87, 5.57), Vector3(2.82, 0.18, 0.22), frame)
	_box(interior, "DoorThreshold", Vector3(0.0, 0.23, 5.57), Vector3(2.82, 0.16, 0.48), frame)
	_box(interior, "DoorStatus", Vector3(0.0, 4.13, 5.38), Vector3(0.58, 0.07, 0.035), cyan)


func _build_ship_modules(hull: StandardMaterial3D, hull_light: StandardMaterial3D, frame: StandardMaterial3D, rubber: StandardMaterial3D, floor_material: StandardMaterial3D, glass: StandardMaterial3D, cyan: StandardMaterial3D, amber: StandardMaterial3D, white_light: StandardMaterial3D) -> void:
	_build_connector(hull, frame, floor_material, cyan)
	_build_crew_module(hull, hull_light, frame, rubber, floor_material, glass, cyan, amber, white_light)
	_build_observation_module(hull, frame, rubber, floor_material, glass, cyan, white_light)
	_build_engineering_module(hull, hull_light, frame, rubber, floor_material, cyan, amber, white_light)


func _build_connector(hull: StandardMaterial3D, frame: StandardMaterial3D, floor_material: StandardMaterial3D, cyan: StandardMaterial3D) -> void:
	_box(interior, "ConnectorFloor", Vector3(0.0, 0.0, 7.0), Vector3(2.82, 0.28, 2.5), floor_material)
	_box(interior, "ConnectorCeiling", Vector3(0.0, 4.25, 7.0), Vector3(2.82, 0.28, 2.5), hull)
	for side in [-1.0, 1.0]:
		var side_value := float(side)
		_box(interior, "ConnectorWall", Vector3(side_value * 1.42, 2.13, 7.0), Vector3(0.24, 4.25, 2.5), hull)
		_box(interior, "ConnectorGuide", Vector3(side_value * 1.24, 1.0, 7.0), Vector3(0.07, 0.09, 2.2), cyan)
	for z in [6.05, 7.05, 8.05]:
		_box(interior, "ConnectorRib", Vector3(0.0, 4.05, z), Vector3(2.65, 0.18, 0.13), frame)


func _build_crew_module(hull: StandardMaterial3D, hull_light: StandardMaterial3D, frame: StandardMaterial3D, rubber: StandardMaterial3D, floor_material: StandardMaterial3D, glass: StandardMaterial3D, cyan: StandardMaterial3D, amber: StandardMaterial3D, white_light: StandardMaterial3D) -> void:
	var center_z := 11.45
	_box(interior, "CrewFloor", Vector3(0.0, 0.0, center_z), Vector3(8.15, 0.28, 6.6), hull)
	_box(interior, "CrewWalkway", Vector3(0.0, 0.17, center_z), Vector3(2.45, 0.055, 6.25), floor_material)
	_box(interior, "CrewCeiling", Vector3(0.0, 4.48, center_z), Vector3(5.6, 0.28, 6.6), hull)
	for side in [-1.0, 1.0]:
		var side_value := float(side)
		var x := side_value * 4.02
		_box(interior, "CrewLowerHull", Vector3(x, 0.91, center_z), Vector3(0.28, 1.55, 6.6), hull)
		_box(interior, "CrewUpperHull", Vector3(x, 3.93, center_z), Vector3(0.28, 1.1, 6.6), hull)
		for z in [8.2, 11.47, 14.72]:
			_box(interior, "CrewWindowMullion", Vector3(x, 2.48, z), Vector3(0.34, 2.2, 0.2), frame)
		for z in [9.84, 13.1]:
			_box(interior, "CrewWindow", Vector3(x + side_value * 0.02, 2.5, z), Vector3(0.04, 2.0, 2.9), glass)
			_box(interior, "CrewWindowRail", Vector3(x - side_value * 0.16, 1.49, z), Vector3(0.07, 0.09, 3.0), frame)
		_box(interior, "CrewStorage", Vector3(side_value * 3.25, 0.68, 11.45), Vector3(1.05, 1.05, 5.5), hull_light)
		for z in [9.3, 10.75, 12.2, 13.65]:
			_box(interior, "StorageLatch", Vector3(side_value * 2.7, 0.75, z), Vector3(0.035, 0.18, 0.36), amber if z > 12.0 else cyan)

	# Compact mess/work area, kept to one side so the central route remains clear.
	_cylinder(interior, "CrewTableStem", Vector3(-1.85, 0.65, 11.35), 0.12, 1.05, frame, Vector3.ZERO, 24)
	_cylinder(interior, "CrewTable", Vector3(-1.85, 1.19, 11.35), 0.78, 0.09, hull_light, Vector3.ZERO, 40)
	for z in [10.45, 12.25]:
		_box(interior, "CrewBench", Vector3(-1.85, 0.58, z), Vector3(1.48, 0.22, 0.5), rubber)
		_box(interior, "CrewBenchBack", Vector3(-2.43, 0.98, z), Vector3(0.17, 0.75, 0.5), rubber)
	_box(interior, "GalleyCounter", Vector3(2.45, 1.0, 12.45), Vector3(1.05, 1.55, 2.6), hull_light)
	for y in [0.63, 1.15, 1.67]:
		_box(interior, "GalleyDrawer", Vector3(1.9, y, 12.45), Vector3(0.04, 0.34, 2.2), frame)
	_box(interior, "GalleyDisplay", Vector3(1.86, 1.92, 12.45), Vector3(0.04, 0.5, 1.1), cyan)
	for z in [8.9, 11.45, 14.0]:
		_box(interior, "CrewLight", Vector3(0.0, 4.29, z), Vector3(2.25, 0.045, 0.14), white_light)
	_build_pressure_frame(14.9, hull, frame, cyan)


func _build_observation_module(hull: StandardMaterial3D, frame: StandardMaterial3D, rubber: StandardMaterial3D, floor_material: StandardMaterial3D, glass: StandardMaterial3D, cyan: StandardMaterial3D, white_light: StandardMaterial3D) -> void:
	var center_z := 19.1
	_box(interior, "ObservationFloor", Vector3(0.0, 0.0, center_z), Vector3(8.85, 0.28, 7.1), hull)
	_box(interior, "ObservationWalkway", Vector3(0.0, 0.17, center_z), Vector3(2.65, 0.055, 6.75), floor_material)
	_box(interior, "ObservationCeilingSpine", Vector3(0.0, 4.65, center_z), Vector3(2.25, 0.24, 7.1), hull)
	for side in [-1.0, 1.0]:
		var side_value := float(side)
		var x := side_value * 4.4
		_box(interior, "ObservationLowerHull", Vector3(x, 0.82, center_z), Vector3(0.28, 1.48, 7.1), hull)
		_box(interior, "ObservationUpperHull", Vector3(x, 4.22, center_z), Vector3(0.28, 0.82, 7.1), hull)
		for z in [15.55, 17.92, 20.28, 22.65]:
			_box(interior, "ObservationMullion", Vector3(x, 2.55, z), Vector3(0.34, 2.65, 0.18), frame)
		for z in [16.73, 19.1, 21.46]:
			_box(interior, "ObservationGlass", Vector3(x + side_value * 0.02, 2.58, z), Vector3(0.04, 2.52, 2.12), glass)
		_box(interior, "ObservationBench", Vector3(side_value * 3.25, 0.58, 19.1), Vector3(1.2, 0.24, 4.8), rubber)
		_box(interior, "ObservationBenchBack", Vector3(side_value * 3.82, 1.05, 19.1), Vector3(0.16, 0.85, 4.8), rubber)
		_box(interior, "Skylight", Vector3(side_value * 2.45, 4.58, center_z), Vector3(2.25, 0.045, 6.55), glass)
		for z in [15.75, 18.0, 20.25, 22.5]:
			_box(interior, "SkylightRib", Vector3(side_value * 2.45, 4.52, z), Vector3(2.28, 0.12, 0.12), frame)
	for z in [16.0, 18.05, 20.1, 22.15]:
		_box(interior, "ObservationSpineLight", Vector3(0.0, 4.48, z), Vector3(1.65, 0.045, 0.12), white_light)
	_box(interior, "ObservationConsole", Vector3(0.0, 0.72, 16.35), Vector3(2.15, 0.88, 0.75), hull)
	_box(interior, "ObservationDisplay", Vector3(0.0, 1.2, 16.28), Vector3(1.55, 0.04, 0.38), cyan, Vector3(-0.16, 0.0, 0.0))
	_build_pressure_frame(22.75, hull, frame, cyan)


func _build_engineering_module(hull: StandardMaterial3D, hull_light: StandardMaterial3D, frame: StandardMaterial3D, rubber: StandardMaterial3D, floor_material: StandardMaterial3D, cyan: StandardMaterial3D, amber: StandardMaterial3D, white_light: StandardMaterial3D) -> void:
	var center_z := 26.25
	_box(interior, "EngineeringFloor", Vector3(0.0, 0.0, center_z), Vector3(7.25, 0.28, 7.2), hull)
	_box(interior, "EngineeringWalkway", Vector3(0.25, 0.17, center_z), Vector3(2.15, 0.055, 6.65), floor_material)
	_box(interior, "EngineeringCeiling", Vector3(0.0, 4.42, center_z), Vector3(7.25, 0.3, 7.2), hull)
	for side in [-1.0, 1.0]:
		var side_value := float(side)
		_box(interior, "EngineeringWall", Vector3(side_value * 3.62, 2.2, center_z), Vector3(0.3, 4.4, 7.2), hull)
		for y in [0.58, 1.12, 3.3, 3.82]:
			_cylinder(interior, "CoolantPipe", Vector3(side_value * 3.28, y, center_z), 0.085 if y < 2.0 else 0.12, 6.6, cyan if y < 2.0 else frame, Vector3(PI * 0.5, 0.0, 0.0), 18)
	_box(interior, "EngineeringEndWall", Vector3(0.0, 2.2, 29.86), Vector3(7.25, 4.4, 0.34), hull)

	# Reactor and service machinery, leaving a walkable route down the center/right side.
	var reactor_glass := _glass_material()
	reactor_glass.albedo_color = Color(0.02, 0.32, 0.42, 0.2)
	_cylinder(interior, "ReactorCoreGlass", Vector3(-1.9, 1.85, 26.55), 0.78, 2.8, reactor_glass, Vector3.ZERO, 48)
	_cylinder(interior, "ReactorEnergy", Vector3(-1.9, 1.85, 26.55), 0.34, 2.55, cyan, Vector3.ZERO, 40)
	for y in [0.45, 1.2, 2.5, 3.25]:
		_torus(interior, "ReactorBrace", Vector3(-1.9, y, 26.55), 0.77, 0.93, frame, Vector3.ZERO, 40, 12)
	_box(interior, "EngineeringConsole", Vector3(2.4, 1.18, 26.0), Vector3(1.5, 1.75, 3.9), hull_light)
	for z in [24.7, 26.0, 27.3]:
		_box(interior, "EngineeringScreen", Vector3(1.62, 1.48, z), Vector3(0.04, 0.62, 0.78), amber if z > 26.5 else cyan)
		for y in [0.58, 0.82, 1.06]:
			_box(interior, "EngineeringSwitch", Vector3(1.59, y, z), Vector3(0.035, 0.08, 0.12), frame)
	for z in [23.65, 25.4, 27.15, 28.9]:
		_box(interior, "EngineeringLight", Vector3(0.0, 4.22, z), Vector3(1.9, 0.045, 0.13), white_light)
		_box(interior, "HazardStripe", Vector3(0.25, 0.205, z), Vector3(2.1, 0.035, 0.06), amber)


func _build_pressure_frame(z_position: float, hull: StandardMaterial3D, frame: StandardMaterial3D, cyan: StandardMaterial3D) -> void:
	_box(interior, "PressureFrameLeft", Vector3(-2.72, 2.22, z_position), Vector3(3.02, 4.44, 0.26), hull)
	_box(interior, "PressureFrameRight", Vector3(2.72, 2.22, z_position), Vector3(3.02, 4.44, 0.26), hull)
	_box(interior, "PressureFrameHeader", Vector3(0.0, 4.02, z_position), Vector3(2.45, 0.84, 0.26), hull)
	for x in [-1.28, 1.28]:
		_box(interior, "PressureFrameRail", Vector3(x, 2.15, z_position - 0.12), Vector3(0.17, 3.55, 0.2), frame)
	_box(interior, "PressureFrameStatus", Vector3(0.0, 4.12, z_position - 0.17), Vector3(0.58, 0.06, 0.04), cyan)


func _build_consoles(hull: StandardMaterial3D, frame: StandardMaterial3D, rubber: StandardMaterial3D, cyan: StandardMaterial3D, amber: StandardMaterial3D) -> void:
	_box(interior, "MainConsoleBase", Vector3(0.0, 0.73, -4.15), Vector3(5.6, 1.05, 1.25), hull, Vector3(-0.10, 0.0, 0.0))
	_box(interior, "MainConsoleLip", Vector3(0.0, 1.28, -4.10), Vector3(5.85, 0.12, 1.1), frame, Vector3(-0.10, 0.0, 0.0))
	for x in [-2.12, -1.06, 0.0, 1.06, 2.12]:
		_box(interior, "ConsoleScreen", Vector3(x, 1.34, -4.14), Vector3(0.84, 0.045, 0.55), cyan, Vector3(-0.10, 0.0, 0.0))
		for light_x in [-0.27, 0.0, 0.27]:
			_box(interior, "ConsoleKey", Vector3(x + light_x, 1.39, -3.76), Vector3(0.095, 0.035, 0.08), amber if absf(light_x) > 0.1 else cyan, Vector3(-0.10, 0.0, 0.0))

	for side in [-1.0, 1.0]:
		var side_value: float = float(side)
		var x: float = side_value * 3.48
		_box(interior, "SideConsole", Vector3(x, 1.12, -1.15), Vector3(1.1, 1.25, 5.3), hull, Vector3(0.0, 0.0, side_value * -0.08))
		_box(interior, "SideConsoleTop", Vector3(x - side_value * 0.08, 1.77, -1.15), Vector3(0.82, 0.08, 4.9), frame, Vector3(0.0, 0.0, side_value * -0.08))
		for z in [-2.85, -1.7, -0.55, 0.6]:
			_box(interior, "SideDisplay", Vector3(x - side_value * 0.13, 1.83, z), Vector3(0.55, 0.035, 0.72), cyan if z < 0.0 else amber, Vector3(0.0, 0.0, side_value * -0.08))
		_cylinder(interior, "ControlDial", Vector3(x - side_value * 0.47, 1.64, 1.05), 0.16, 0.12, rubber, Vector3(0.0, 0.0, PI * 0.5), 24)


func _build_overhead(frame: StandardMaterial3D, hull: StandardMaterial3D, white_light: StandardMaterial3D, cyan: StandardMaterial3D) -> void:
	for x in [-1.62, 1.62]:
		_box(interior, "CeilingRail", Vector3(x, 4.34, 0.0), Vector3(0.16, 0.14, 10.9), frame)
	for z in [-4.15, -1.4, 1.35, 4.1]:
		_box(interior, "CeilingCrossMember", Vector3(0.0, 4.33, z), Vector3(3.65, 0.14, 0.18), frame)
		_box(interior, "CeilingLight", Vector3(0.0, 4.22, z), Vector3(1.8, 0.045, 0.12), white_light)
		_box(interior, "CeilingStatus", Vector3(1.22, 4.21, z), Vector3(0.34, 0.04, 0.08), cyan)
	_box(interior, "OverheadControl", Vector3(0.0, 4.19, -3.0), Vector3(2.8, 0.12, 1.25), hull)


func _build_seat(frame: StandardMaterial3D, rubber: StandardMaterial3D) -> void:
	# The lower edge of the flight seat anchors the first-person camera without blocking the windows.
	_box(interior, "PilotSeat", Vector3(0.0, 0.65, 3.4), Vector3(1.22, 0.28, 1.0), rubber)
	_box(interior, "PilotBack", Vector3(0.0, 1.22, 3.88), Vector3(1.22, 1.25, 0.22), rubber, Vector3(-0.08, 0.0, 0.0))
	_box(interior, "SeatFrame", Vector3(0.0, 0.35, 3.72), Vector3(0.74, 0.7, 0.14), frame)
	for x in [-0.48, 0.48]:
		_box(interior, "SeatHarness", Vector3(x, 1.42, 3.72), Vector3(0.08, 0.92, 0.04), frame, Vector3(0.0, 0.0, x * 0.32))


func _build_lighting() -> void:
	_add_omni("CabinKey", Vector3(0.0, 3.9, 0.5), Color(0.43, 0.68, 1.0), 7.0, 8.5)
	_add_omni("FrontFill", Vector3(0.0, 3.2, -4.1), Color(0.24, 0.55, 1.0), 5.0, 6.0)
	_add_omni("WarmInstrumentGlow", Vector3(2.8, 1.5, -2.4), Color(1.0, 0.24, 0.055), 3.2, 4.5)
	_add_omni("RearFill", Vector3(-2.4, 3.2, 4.1), Color(0.18, 0.34, 0.62), 3.6, 5.0)
	_add_omni("CrewModuleLight", Vector3(0.0, 3.75, 11.45), Color(0.58, 0.76, 1.0), 5.6, 7.0)
	_add_omni("ObservationPlanetFill", Vector3(-2.8, 3.0, 19.1), Color(0.16, 0.42, 0.78), 4.4, 7.5)
	_add_omni("ObservationAmbient", Vector3(0.0, 3.8, 19.1), Color(0.48, 0.62, 0.78), 5.2, 8.5)
	_add_omni("ObservationWarmFill", Vector3(3.0, 2.0, 19.1), Color(1.0, 0.38, 0.12), 2.1, 5.5)
	_add_omni("EngineeringCoolLight", Vector3(-1.6, 2.4, 26.4), Color(0.0, 0.64, 1.0), 6.2, 6.0)
	_add_omni("EngineeringWorkLight", Vector3(2.5, 3.5, 26.2), Color(1.0, 0.55, 0.25), 3.4, 5.0)


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FlightInterface"
	add_child(layer)

	var telemetry_back := ColorRect.new()
	telemetry_back.position = Vector2(24.0, 24.0)
	telemetry_back.size = Vector2(330.0, 124.0)
	telemetry_back.color = Color(0.008, 0.02, 0.035, 0.78)
	layer.add_child(telemetry_back)

	var accent := ColorRect.new()
	accent.position = Vector2(0.0, 0.0)
	accent.size = Vector2(4.0, 124.0)
	accent.color = Color(0.0, 0.72, 1.0, 0.95)
	telemetry_back.add_child(accent)

	var title := _label("ODYSSEY  //  CÁPSULA 07", Vector2(18.0, 13.0), 18, Color(0.82, 0.94, 1.0))
	telemetry_back.add_child(title)
	var status := _label("TRAYECTORIA ESTABLE", Vector2(18.0, 45.0), 13, Color(0.05, 0.84, 1.0))
	telemetry_back.add_child(status)
	var readout := _label("VELOCIDAD RELATIVA   24.8 km/s\nROTACIÓN AXIAL          3.0°/s\nSISTEMAS               NOMINAL", Vector2(18.0, 66.0), 11, Color(0.58, 0.7, 0.78))
	telemetry_back.add_child(readout)
	location_label = _label("UBICACIÓN  //  CABINA DE MANDO", Vector2(24.0, 157.0), 11, Color(0.43, 0.78, 0.94))
	layer.add_child(location_label)

	var hint_back := ColorRect.new()
	hint_back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_back.position = Vector2(-252.0, -58.0)
	hint_back.size = Vector2(504.0, 34.0)
	hint_back.color = Color(0.006, 0.012, 0.022, 0.72)
	layer.add_child(hint_back)
	var hint := _label("WASD MOVER  •  SHIFT CORRER  •  Q / E ALTURA  •  RATÓN MIRAR  •  ESC LIBERAR", Vector2(0.0, 8.0), 11, Color(0.58, 0.72, 0.8))
	hint.size = Vector2(504.0, 18.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_back.add_child(hint)

	var reticle_color := Color(0.42, 0.82, 1.0, 0.55)
	for rect in [Rect2(-10.0, -1.0, 7.0, 2.0), Rect2(3.0, -1.0, 7.0, 2.0), Rect2(-1.0, -10.0, 2.0, 7.0), Rect2(-1.0, 3.0, 2.0, 7.0)]:
		var reticle_part := ColorRect.new()
		reticle_part.set_anchors_preset(Control.PRESET_CENTER)
		reticle_part.position = rect.position
		reticle_part.size = rect.size
		reticle_part.color = reticle_color
		layer.add_child(reticle_part)


func _build_travel_specks() -> void:
	var speck_material := _material(Color(0.42, 0.55, 0.72), 0.0, 0.34, Color(0.18, 0.32, 0.5), 0.55)
	for index in 18:
		var seed := float(index)
		var x := sin(seed * 37.17) * 22.0
		var y := cos(seed * 19.83) * 14.0 + 2.0
		var z := -9.0 - fmod(seed * 11.37, 62.0)
		var speck := _box(space, "TravelSpeck", Vector3(x, y, z), Vector3(0.01, 0.01, 0.08 + fmod(seed, 4.0) * 0.025), speck_material)
		travel_specks.append(speck)


func _animate_travel_specks(delta: float) -> void:
	for index in travel_specks.size():
		var speck := travel_specks[index]
		speck.position.z += delta * (1.4 + fmod(float(index), 7.0) * 0.18)
		if speck.position.z > -6.5:
			speck.position.z = -74.0 - fmod(float(index) * 3.7, 18.0)


func _space_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 star_grid = uv * vec2(640.0, 320.0);
	vec2 cell_id = floor(star_grid);
	vec2 cell = fract(star_grid) - 0.5;
	float seed = hash21(cell_id);
	vec2 offset = vec2(hash21(cell_id + 17.1), hash21(cell_id + 41.7)) - 0.5;
	float radius = mix(0.055, 0.12, pow(seed, 18.0));
	float star_distance = length(cell - offset * 0.62);
	float star_aa = max(fwidth(star_distance) * 1.2, 0.008);
	float star = (1.0 - smoothstep(radius - star_aa, radius + star_aa, star_distance)) * step(0.985, seed);
	star *= mix(0.1, 0.78, pow(seed, 22.0));

	vec2 bright_grid = uv * vec2(240.0, 120.0);
	vec2 bright_id = floor(bright_grid);
	vec2 bright_cell = fract(bright_grid) - 0.5;
	float bright_seed = hash21(bright_id + 81.4);
	vec2 bright_offset = vec2(hash21(bright_id + 9.2), hash21(bright_id + 63.8)) - 0.5;
	float bright_distance = length(bright_cell - bright_offset * 0.58);
	float bright_radius = mix(0.055, 0.11, bright_seed);
	float bright_aa = max(fwidth(bright_distance) * 1.25, 0.008);
	float bright_star = (1.0 - smoothstep(bright_radius - bright_aa, bright_radius + bright_aa, bright_distance)) * step(0.997, bright_seed);
	bright_star *= 0.7 + bright_seed * 0.65;

	float band_center = 0.51 + sin(uv.x * 6.283 + 0.7) * 0.075;
	float band = exp(-pow(abs(uv.y - band_center) * 7.4, 2.0));
	float cloud = value_noise(uv * vec2(12.0, 7.0)) * 0.58 + value_noise(uv * vec2(31.0, 18.0)) * 0.26;
	float dust_lane = value_noise(uv * vec2(47.0, 13.0) + 8.0);
	band *= smoothstep(0.28, 0.82, cloud) * mix(0.36, 1.0, dust_lane);
	vec3 deep_space = vec3(0.00035, 0.00065, 0.0018);
	vec3 nebula = mix(vec3(0.018, 0.027, 0.052), vec3(0.052, 0.036, 0.044), value_noise(uv * 5.0));
	vec3 star_color = mix(vec3(0.58, 0.72, 1.0), vec3(1.0, 0.78, 0.52), hash21(cell_id + 7.7));
	vec3 bright_color = mix(vec3(0.66, 0.8, 1.0), vec3(1.0, 0.9, 0.72), bright_seed);
	vec3 color = deep_space + nebula * band * 0.46 + star_color * star + bright_color * bright_star;
	ALBEDO = color;
	EMISSION = color * 0.82;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _planet_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.52;
	for (int i = 0; i < 5; i++) {
		value += noise(p) * amplitude;
		p = p * 2.03 + vec2(7.1, 3.7);
		amplitude *= 0.48;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	float latitude = abs(uv.y - 0.5) * 2.0;
	float terrain = fbm(uv * vec2(7.5, 4.2) + vec2(1.7, 4.1));
	terrain += (fbm(uv * vec2(18.0, 9.0) + 12.0) - 0.5) * 0.18;
	float land = smoothstep(0.51, 0.575, terrain - latitude * 0.035);
	vec3 deep_ocean = vec3(0.006, 0.028, 0.075);
	vec3 shelf_water = vec3(0.018, 0.15, 0.21);
	vec3 water = mix(deep_ocean, shelf_water, smoothstep(0.46, 0.57, terrain));
	vec3 lowland = vec3(0.075, 0.19, 0.075);
	vec3 highland = vec3(0.34, 0.29, 0.16);
	vec3 land_color = mix(lowland, highland, smoothstep(0.56, 0.78, terrain));
	float ice = smoothstep(0.79, 0.94, latitude + noise(vec2(uv.x * 23.0, uv.y * 6.0)) * 0.14);
	vec3 color = mix(water, land_color, land);
	color = mix(color, vec3(0.7, 0.78, 0.82), ice);
	float longitude = (uv.x - 0.5) * 6.283185;
	float latitude_angle = (0.5 - uv.y) * 3.141593;
	vec3 globe_normal = vec3(cos(latitude_angle) * sin(longitude), sin(latitude_angle), cos(latitude_angle) * cos(longitude));
	float sunlight = smoothstep(-0.13, 0.24, dot(globe_normal, normalize(vec3(-0.24, 0.28, 0.93))));
	float city_seed = hash21(floor(uv * vec2(420.0, 210.0)) + 29.0);
	float city_lights = step(0.997, city_seed) * land * (1.0 - sunlight) * (1.0 - ice);
	color *= 0.1 + sunlight * 0.86;
	color += vec3(1.0, 0.38, 0.055) * city_lights * 0.8;
	ALBEDO = color;
	ROUGHNESS = mix(0.2, 0.92, max(land, ice));
	METALLIC = 0.0;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _cloud_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_back;

float hash21(vec2 p) {
	p = fract(p * vec2(137.1, 311.7));
	p += dot(p, p + 31.7);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 4; i++) {
		value += noise(p) * amplitude;
		p = p * 2.08 + vec2(4.3, 8.2);
		amplitude *= 0.46;
	}
	return value;
}

void fragment() {
	vec2 uv = UV + vec2(TIME * 0.00065, 0.0);
	float formation = fbm(uv * vec2(12.0, 6.0));
	float wisps = fbm(uv * vec2(31.0, 14.0) + 17.0);
	float clouds = smoothstep(0.58, 0.79, formation + wisps * 0.18);
	ALBEDO = vec3(0.62, 0.68, 0.74);
	ROUGHNESS = 1.0;
	ALPHA = clouds * 0.36;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = 3
	return material


func _atmosphere_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 3.3);
	vec3 atmosphere = mix(vec3(0.02, 0.18, 0.65), vec3(0.18, 0.65, 1.0), rim);
	ALBEDO = atmosphere;
	EMISSION = atmosphere * rim * 1.5;
	ALPHA = rim * 0.48;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = 4
	return material


func _moon_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 cells = floor(UV * vec2(110.0, 55.0));
	float grain = hash21(cells);
	float broad = hash21(floor(UV * vec2(23.0, 12.0)));
	float crater = smoothstep(0.84, 0.98, grain) * (0.25 + broad * 0.32);
	vec3 stone = mix(vec3(0.16, 0.17, 0.18), vec3(0.38, 0.37, 0.34), broad);
	ALBEDO = stone * (1.0 - crater);
	ROUGHNESS = 0.98;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _glass_material() -> StandardMaterial3D:
	var material := _material(Color(0.055, 0.16, 0.22, 0.085), 0.58, 0.06)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 2
	return material


func _material(color: Color, metallic: float, roughness: float, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material


func _box(parent: Node, node_name: String, location: Vector3, size: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = location
	instance.rotation = rotation
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	parent.add_child(instance)
	return instance


func _sphere(parent: Node, node_name: String, location: Vector3, scale_factor: Vector3, material: Material, radial_segments := 32, rings := 16) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = location
	instance.scale = scale_factor
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	mesh.material = material
	instance.mesh = mesh
	parent.add_child(instance)
	return instance


func _cylinder(parent: Node, node_name: String, location: Vector3, radius: float, height: float, material: Material, rotation := Vector3.ZERO, segments := 24) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = location
	instance.rotation = rotation
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.material = material
	instance.mesh = mesh
	parent.add_child(instance)
	return instance


func _torus(parent: Node, node_name: String, location: Vector3, inner_radius: float, outer_radius: float, material: Material, rotation := Vector3.ZERO, rings := 48, ring_segments := 12) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = location
	instance.rotation = rotation
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = rings
	mesh.ring_segments = ring_segments
	mesh.material = material
	instance.mesh = mesh
	parent.add_child(instance)
	return instance


func _add_omni(node_name: String, location: Vector3, color: Color, energy: float, light_range: float) -> void:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = location
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = true
	interior.add_child(light)


func _label(text: String, position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label
