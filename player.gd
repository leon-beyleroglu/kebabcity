extends CharacterBody3D

@export var walk_speed := 5.0
@export var sprint_speed := 9.0
@export var jump_velocity := 5.0
@export var mouse_sensitivity := 0.002
@export var acceleration := 20.0
@export var deceleration := 26.0

@onready var camera: Camera3D = $Camera3D
@onready var legacy_avatar: Node3D = $EigenesAvatarModell
var first_person_hands: Node3D
var avatar_model: Node3D
var arm_pivots: Array[Node3D] = []
var leg_pivots: Array[Node3D] = []
var orbit_yaw := 0.0
var orbit_pitch := -0.2
var zoom_distance := 4.2
var camera_distance := 4.2
var follow_target := Vector3.ZERO
var camera_query := PhysicsShapeQueryParameters3D.new()
var walk_phase := 0.0
var motion_blend := 0.0
var idle_time := 0.0

const HumanHand = preload("res://human_hand.gd")
const InteractionSystem = preload("res://interaction_system.gd")

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var third_person := false

const FIRST_PERSON_POSITION := Vector3(0.0, 0.7549808, 0.0)
const CAMERA_TARGET := Vector3(0.0, 0.38, 0.0)

func _ready() -> void:
	Engine.max_fps = 60
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.position = FIRST_PERSON_POSITION
	camera.rotation = Vector3.ZERO
	camera.near = 0.06
	camera.fov = 72.0
	var camera_volume := SphereShape3D.new()
	camera_volume.radius = 0.24
	camera_query.shape = camera_volume
	camera_query.exclude = [get_rid()]
	camera_query.collision_mask = collision_mask
	camera_query.margin = 0.04
	legacy_avatar.visible = false
	first_person_hands = Node3D.new()
	first_person_hands.name = "FirstPersonHands"
	camera.add_child(first_person_hands)
	_build_first_person_hands()
	_build_doner_worker()
	var interaction_system := InteractionSystem.new()
	interaction_system.name = "InteractionSystem"
	add_child(interaction_system)
	interaction_system.setup(self, camera, first_person_hands)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		_toggle_camera_mode()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if third_person:
			orbit_yaw -= event.relative.x * mouse_sensitivity
			orbit_pitch = clampf(orbit_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-62), deg_to_rad(28))
		else:
			rotate_y(-event.relative.x * mouse_sensitivity)
			camera.rotation.x = clampf(camera.rotation.x - event.relative.y * mouse_sensitivity, deg_to_rad(-85), deg_to_rad(85))
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif third_person and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_distance = maxf(2.2, zoom_distance - 0.35)
		elif third_person and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_distance = minf(6.5, zoom_distance + 0.35)

func _toggle_camera_mode() -> void:
	third_person = not third_person
	legacy_avatar.visible = false
	avatar_model.visible = third_person
	first_person_hands.visible = not third_person
	if third_person:
		orbit_yaw = global_rotation.y
		orbit_pitch = -0.2
		follow_target = global_position + CAMERA_TARGET
		camera_distance = zoom_distance
		camera.top_level = true
	else:
		global_rotation.y = orbit_yaw
		camera.top_level = false
		camera.position = FIRST_PERSON_POSITION
		camera.rotation = Vector3(orbit_pitch, 0, 0)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	var current_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var input_direction := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var movement_basis := Basis(Vector3.UP, orbit_yaw) if third_person else global_basis
	var direction := (movement_basis * Vector3(input_direction.x, 0, input_direction.y)).normalized()
	if direction:
		if third_person:
			global_rotation.y = lerp_angle(global_rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-delta * 12.0))
		velocity.x = move_toward(velocity.x, direction.x * current_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0, deceleration * delta)
	move_and_slide()
	_animate_actor(delta)
	if camera.current:
		_update_camera(delta)

func _update_camera(delta: float) -> void:
	var sprinting := Input.is_action_pressed("sprint") and Vector2(velocity.x, velocity.z).length() > walk_speed
	camera.fov = lerpf(camera.fov, 77.0 if sprinting else 72.0, 1.0 - exp(-delta * 5.0))
	if not third_person:
		return
	var target := global_position + CAMERA_TARGET
	follow_target = follow_target.lerp(target, 1.0 - exp(-delta * 14.0))
	var orbit_basis := Basis.from_euler(Vector3(orbit_pitch, orbit_yaw, 0))
	var desired_position := follow_target + orbit_basis.z * zoom_distance
	var motion := desired_position - target
	# Sweep a camera-sized sphere; exclude the player's capsule. Pull in immediately
	# at walls, ease out afterwards, and never interpolate through the obstruction.
	camera_query.transform = Transform3D(Basis.IDENTITY, target)
	camera_query.motion = motion
	var cast := get_world_3d().direct_space_state.cast_motion(camera_query)
	var safe_distance := maxf(0.0, motion.length() * cast[0] - 0.04)
	camera_distance = minf(safe_distance, lerpf(camera_distance, safe_distance, 1.0 - exp(-delta * 7.0)))
	camera.global_position = target + motion.normalized() * camera_distance
	if camera_distance > 0.01:
		camera.look_at(target, Vector3.UP)
	else:
		camera.global_basis = orbit_basis
	avatar_model.visible = camera_distance > 0.95

func _animate_actor(delta: float) -> void:
	idle_time += delta
	var speed := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	var walking := clampf(speed / sprint_speed, 0.0, 1.0) if is_on_floor() else 0.0
	motion_blend = lerpf(motion_blend, walking, 1.0 - exp(-delta * 12.0))
	walk_phase += delta * speed * 1.9
	for i in range(arm_pivots.size()):
		var stride := sin(walk_phase + float(i) * PI)
		arm_pivots[i].rotation.x = stride * motion_blend * 0.5
		leg_pivots[i].rotation.x = -stride * motion_blend * 0.58
	avatar_model.rotation.z = sin(walk_phase) * motion_blend * 0.022
	first_person_hands.position = Vector3(sin(walk_phase) * motion_blend * 0.014, sin(idle_time * 1.7) * 0.003 + absf(sin(walk_phase)) * motion_blend * 0.009, 0)

func _material(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	material.metallic = metallic
	return material

func _box(parent: Node3D, node_name: String, new_position: Vector3, size: Vector3, material: Material, new_rotation := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = new_position
	instance.rotation = new_rotation
	parent.add_child(instance)
	return instance

func _sphere(parent: Node3D, node_name: String, new_position: Vector3, new_scale: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 20
	mesh.rings = 12
	mesh.material = material
	instance.mesh = mesh
	instance.position = new_position
	instance.scale = new_scale
	parent.add_child(instance)
	return instance

func _capsule(parent: Node3D, node_name: String, new_position: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = material
	instance.mesh = mesh
	instance.position = new_position
	parent.add_child(instance)
	return instance

func _build_doner_worker() -> void:
	var avatar := Node3D.new()
	avatar.name = "ThirdPersonDoner"
	avatar.visible = false
	avatar.position.y = -0.22
	avatar.scale.y = 0.8
	add_child(avatar)
	avatar_model = avatar
	var shirt := _material(Color("173f59"))
	var apron := _material(Color("a92f2c"))
	var apron_trim := _material(Color("e2c18a"))
	var skin := _material(Color("bd805c"))
	var beard := _material(Color("38251f"))
	var trousers := _material(Color("28323d"))
	var shoe := _material(Color("17191d"))
	var white := _material(Color("eee7d5"))
	var eye := _material(Color("211a17"))
	var metal := _material(Color("c6b690"), 0.5)
	var pocket := _material(Color("792a29"))
	var wood := _material(Color("55382c"))
	# Wide, rounded silhouette: shirt, belly and shoulders form a stocky build.
	_sphere(avatar, "Broad work shirt", Vector3(0, -0.15, 0), Vector3(1.42, 1.52, 0.96), shirt)
	_sphere(avatar, "Round shirt belly", Vector3(0, -0.47, -0.17), Vector3(1.34, 0.9, 0.91), shirt)
	_box(avatar, "Apron bib", Vector3(0, -0.05, -0.49), Vector3(1.08, 0.82, 0.09), apron)
	_box(avatar, "Apron skirt", Vector3(0, -0.57, -0.47), Vector3(1.25, 0.83, 0.1), apron)
	_box(avatar, "Apron hem", Vector3(0, -0.99, -0.48), Vector3(1.28, 0.09, 0.11), apron_trim)
	_box(avatar, "Apron pocket", Vector3(0, -0.5, -0.54), Vector3(0.58, 0.35, 0.07), pocket)
	_box(avatar, "Apron pocket stitch", Vector3(0, -0.35, -0.585), Vector3(0.62, 0.035, 0.02), apron_trim)
	_box(avatar, "Apron neck strap", Vector3(0, 0.46, -0.27), Vector3(0.16, 0.58, 0.12), apron)
	_box(avatar, "Apron waist tie", Vector3(0, -0.17, 0.43), Vector3(1.3, 0.12, 0.08), apron_trim)
	_box(avatar, "Back apron strap left", Vector3(-0.34, 0.12, 0.46), Vector3(0.13, 0.85, 0.07), apron, Vector3(0, 0, -0.18))
	_box(avatar, "Back apron strap right", Vector3(0.34, 0.12, 0.46), Vector3(0.13, 0.85, 0.07), apron, Vector3(0, 0, 0.18))
	_box(avatar, "Back apron cross strap", Vector3(0, -0.12, 0.47), Vector3(0.72, 0.12, 0.07), apron_trim)
	_box(avatar, "Back shirt patch", Vector3(0, -0.08, 0.49), Vector3(0.42, 0.2, 0.04), apron_trim)
	# Shoulder and hip pivots keep the hands attached during the walk cycle.
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "LeftShoulder" if side < 0 else "RightShoulder"
		arm.position = Vector3(side * 0.70, 0.28, 0.01)
		avatar.add_child(arm)
		arm_pivots.append(arm)
		_capsule(arm, "Short sleeve", Vector3(0, -0.17, 0), 0.22, 0.52, shirt)
		var wrist := Vector3(side * 0.06, -0.81, -0.03)
		_tapered_limb(arm, "ShapedForearm", Vector3(side * 0.025, -0.36, 0), wrist, 0.135, 0.056, skin)
		var hand := HumanHand.new()
		hand.name = "AnatomicalHand"
		arm.add_child(hand)
		hand.position = wrist
		hand.rotation.y = side * 0.22
		hand.build(side)
		var leg := Node3D.new()
		leg.name = "LeftHip" if side < 0 else "RightHip"
		leg.position = Vector3(side * 0.3, -0.55, 0.02)
		avatar.add_child(leg)
		leg_pivots.append(leg)
		_capsule(leg, "Trouser leg", Vector3(0, -0.45, 0), 0.23, 0.62, trousers)
		_box(leg, "Work shoe", Vector3(0, -0.73, -0.15), Vector3(0.43, 0.22, 0.62), shoe)
		_box(leg, "Shoe sole", Vector3(0, -0.84, -0.15), Vector3(0.45, 0.06, 0.64), metal)
	# Face, trimmed beard, mustache, hair and a white kitchen cap.
	_sphere(avatar, "Head", Vector3(0, 0.82, 0), Vector3(0.53, 0.62, 0.48), skin)
	_sphere(avatar, "Full beard", Vector3(0, 0.58, -0.18), Vector3(0.45, 0.31, 0.22), beard)
	_sphere(avatar, "Mustache left", Vector3(-0.105, 0.72, -0.255), Vector3(0.22, 0.1, 0.11), beard)
	_sphere(avatar, "Mustache right", Vector3(0.105, 0.72, -0.255), Vector3(0.22, 0.1, 0.11), beard)
	for side in [-1.0, 1.0]:
		_sphere(avatar, "Ear", Vector3(side * 0.27, 0.84, 0), Vector3(0.13, 0.18, 0.13), skin)
		_sphere(avatar, "Eye", Vector3(side * 0.105, 0.91, -0.218), Vector3(0.055, 0.065, 0.035), eye)
		_box(avatar, "Eyebrow", Vector3(side * 0.105, 1.015, -0.23), Vector3(0.14, 0.045, 0.045), beard, Vector3(0, 0, side * -0.08))
	_sphere(avatar, "Nose", Vector3(0, 0.81, -0.27), Vector3(0.13, 0.17, 0.17), skin)
	_capsule(avatar, "Hair", Vector3(0, 1.09, 0.01), 0.25, 0.3, beard)
	_cook_cap(avatar, white, apron_trim)
	# Name tag and a metal döner knife/tool clipped to the apron.
	_box(avatar, "Name badge", Vector3(0.34, 0.17, -0.56), Vector3(0.28, 0.16, 0.035), white)
	_box(avatar, "Badge lettering", Vector3(0.34, 0.17, -0.583), Vector3(0.17, 0.035, 0.018), apron)
	_box(avatar, "Apron towel", Vector3(-0.43, -0.29, -0.55), Vector3(0.2, 0.45, 0.08), white, Vector3(0, 0, -0.08))
	_box(avatar, "Knife handle", Vector3(-0.54, -0.7, -0.52), Vector3(0.1, 0.32, 0.1), wood, Vector3(0, 0, -0.16))
	_box(avatar, "Knife blade", Vector3(-0.57, -0.47, -0.52), Vector3(0.035, 0.2, 0.06), metal, Vector3(0, 0, -0.16))

func _cook_cap(parent: Node3D, white: Material, trim: Material) -> void:
	var cap_band := _capsule(parent, "Chef cap band", Vector3(0, 1.18, 0), 0.25, 0.12, trim)
	cap_band.scale = Vector3(1.0, 0.55, 0.88)
	var cap := _sphere(parent, "White cook cap", Vector3(0, 1.31, 0.015), Vector3(0.48, 0.35, 0.43), white)
	cap.rotation.z = -0.035

func _build_first_person_hands() -> void:
	var skin := _material(Color("bd805c"))
	var shirt := _material(Color("173f59"))
	var cuff := _material(Color("28536a"))
	for side in [-1.0, 1.0]:
		var wrist := Vector3(side * 0.29, -0.29, -0.62)
		_tapered_limb(first_person_hands, "Sleeve", Vector3(side * 0.52, -0.64, -0.1), Vector3(side * 0.43, -0.47, -0.32), 0.12, 0.097, shirt)
		_tapered_limb(first_person_hands, "RolledCuff", Vector3(side * 0.44, -0.49, -0.29), Vector3(side * 0.42, -0.45, -0.34), 0.103, 0.097, cuff)
		_tapered_limb(first_person_hands, "Forearm", Vector3(side * 0.43, -0.47, -0.32), wrist, 0.083, 0.055, skin)
		var hand := HumanHand.new()
		hand.name = "LeftHand" if side < 0 else "RightHand"
		first_person_hands.add_child(hand)
		hand.position = wrist
		hand.rotation = Vector3(1.12, side * -0.22, side * -0.12)
		hand.build(side)
	for mesh in first_person_hands.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _tapered_limb(parent: Node3D, node_name: String, start: Vector3, end: Vector3, start_radius: float, end_radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = start_radius
	mesh.bottom_radius = end_radius
	mesh.height = start.distance_to(end)
	mesh.radial_segments = 24
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = (start + end) * 0.5
	instance.basis = Basis(Quaternion(Vector3.UP, (start - end).normalized()))
	parent.add_child(instance)
