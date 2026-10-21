extends VehicleBody3D

@export var vehicle_mass := 1050.0
@export var max_engine_force := 3500.0
@export var max_reverse_force := 2200.0
@export var max_brake_force := 85.0
@export var light_drag := 3.0
@export var handbrake_force := 140.0
@export var parking_brake_force := 60.0
@export var max_steering_angle := 0.4
@export var steering_lerp_speed := 8.0
@export var center_of_mass_offset := Vector3(0.0, -0.35, 0.0)
@export var downforce_multiplier := 45.0
@export var rollover_recovery_delay := 2.0
@export var rollover_up_dot_threshold := 0.35
@export var rollover_lift_height := 0.75
@export var interaction_distance := 3.5
@export var camera_mouse_sensitivity := 0.003
@export var camera_min_pitch := deg_to_rad(-55.0)
@export var camera_max_pitch := deg_to_rad(10.0)
@export var camera_auto_center_delay := 1.5
@export var camera_auto_center_speed := 3.5
@export var camera_auto_center_min_speed := 2.0
@export var cockpit_min_yaw := deg_to_rad(-85.0)
@export var cockpit_max_yaw := deg_to_rad(85.0)
@export var cockpit_min_pitch := deg_to_rad(-25.0)
@export var cockpit_max_pitch := deg_to_rad(25.0)
@export var cockpit_auto_center_delay := 0.75
@export var cockpit_auto_center_speed := 4.5

# This Tofas model's visible front is local -Z. Negative VehicleBody3D wheel
# force therefore drives it toward its hood instead of toward its trunk.
const DRIVETRAIN_DIRECTION := -1.0

var can_enter := false
var is_driving := false
var driver: CharacterBody3D
var driver_original_parent: Node
var current_steer := 0.0
var rollover_timer := 0.0
var order_note_ui: CanvasLayer
var order_note_was_visible := false
var camera_yaw := 0.0
var camera_pitch := 0.0
var camera_mouse_idle_time := 0.0
var cockpit_yaw := 0.0
var cockpit_pitch := 0.0
var is_cockpit_view := false
var third_person_rig_rest_rotation := Vector3.ZERO
var spring_arm_rest_rotation := Vector3.ZERO
var exterior_camera_rest_transform := Transform3D.IDENTITY
var interior_camera_rest_transform := Transform3D.IDENTITY
var exterior_rest_pitch := 0.0

@onready var wheel_fl: VehicleWheel3D = $Wheel_FL
@onready var wheel_fr: VehicleWheel3D = $Wheel_FR
@onready var wheel_rl: VehicleWheel3D = $Wheel_RL
@onready var wheel_rr: VehicleWheel3D = $Wheel_RR
@onready var third_person_rig: Node3D = $ThirdPersonRig
@onready var spring_arm: SpringArm3D = $ThirdPersonRig/SpringArm3D
@onready var exterior_camera: Camera3D = $ThirdPersonRig/SpringArm3D/ExteriorCameraMount/ExteriorCamera
@onready var cockpit_rig: Node3D = $CockpitRig
@onready var interior_camera: Camera3D = $CockpitRig/InteriorCamera
@onready var driver_seat: Marker3D = $DriverSeat
@onready var exit_point: Marker3D = $ExitPoint


func _ready() -> void:
	add_to_group("vehicles")
	mass = vehicle_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = center_of_mass_offset
	_configure_wheels()
	spring_arm.add_excluded_object(get_rid())
	third_person_rig_rest_rotation = third_person_rig.rotation
	spring_arm_rest_rotation = spring_arm.rotation
	exterior_camera_rest_transform = exterior_camera.transform
	interior_camera_rest_transform = interior_camera.transform
	exterior_rest_pitch = (
		spring_arm_rest_rotation.x
		+ exterior_camera_rest_transform.basis.get_euler().x
	)
	_reset_vehicle_cameras()
	order_note_ui = get_tree().get_first_node_in_group("order_note_ui") as CanvasLayer
	_set_vehicle_camera_current(false)
	engine_force = 0.0
	brake = parking_brake_force
	steering = 0.0


func enter_vehicle(player: CharacterBody3D) -> void:
	if not can_player_enter(player):
		return
	driver = player
	driver_original_parent = player.get_parent()
	is_driving = true
	can_enter = false
	sleeping = false
	_hide_order_note()
	if driver.has_method("enter_vehicle_mode"):
		driver.call("enter_vehicle_mode", self, driver_seat)
	else:
		driver.visible = false
		var player_collision := driver.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if player_collision != null:
			player_collision.disabled = true
		var player_camera := driver.get_node_or_null("Camera3D") as Camera3D
		if player_camera != null:
			player_camera.current = false
		driver.set_physics_process(false)
		driver.set_process_input(false)
		driver.reparent(driver_seat, false)
		driver.transform = Transform3D.IDENTITY
	is_cockpit_view = false
	_reset_vehicle_cameras()
	_set_vehicle_camera_current(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func exit_vehicle() -> void:
	if not is_driving:
		return
	is_driving = false
	engine_force = 0.0
	brake = max_brake_force
	_set_rear_wheel_brake(0.0)
	steering = 0.0
	current_steer = 0.0
	rollover_timer = 0.0
	_set_vehicle_camera_current(false)
	is_cockpit_view = false
	_reset_vehicle_cameras()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_restore_order_note()
	var exiting_player := driver
	driver = null
	can_enter = false
	if not is_instance_valid(exiting_player):
		driver_original_parent = null
		return
	if exiting_player.has_method("exit_vehicle_mode"):
		exiting_player.call("exit_vehicle_mode", exit_point.global_transform)
	else:
		var target_parent := driver_original_parent
		if not is_instance_valid(target_parent):
			target_parent = get_tree().current_scene
		exiting_player.reparent(target_parent, false)
		exiting_player.global_transform = exit_point.global_transform
		var player_collision := exiting_player.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if player_collision != null:
			player_collision.disabled = false
		var player_camera := exiting_player.get_node_or_null("Camera3D") as Camera3D
		if player_camera != null:
			player_camera.current = true
		exiting_player.visible = true
		exiting_player.set_physics_process(true)
		exiting_player.set_process_input(true)
		exiting_player.set_process_unhandled_input(true)
	driver_original_parent = null


func can_player_enter(player: CharacterBody3D) -> bool:
	if is_driving or not is_instance_valid(player) or not is_inside_tree():
		can_enter = false
		return false
	can_enter = global_position.distance_to(player.global_position) <= interaction_distance
	return can_enter


func _unhandled_input(event: InputEvent) -> void:
	if not is_driving:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V or event.physical_keycode == KEY_V:
			is_cockpit_view = not is_cockpit_view
			_set_vehicle_camera_current(true)
			camera_mouse_idle_time = 0.0
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		if is_cockpit_view:
			cockpit_yaw = clampf(
				cockpit_yaw - event.relative.x * camera_mouse_sensitivity,
				cockpit_min_yaw,
				cockpit_max_yaw
			)
			cockpit_pitch = clampf(
				cockpit_pitch - event.relative.y * camera_mouse_sensitivity,
				cockpit_min_pitch,
				cockpit_max_pitch
			)
			_apply_cockpit_look()
		else:
			camera_yaw = wrapf(
				camera_yaw - event.relative.x * camera_mouse_sensitivity,
				-PI,
				PI
			)
			camera_pitch = clampf(
				camera_pitch - event.relative.y * camera_mouse_sensitivity,
				camera_min_pitch - exterior_rest_pitch,
				camera_max_pitch - exterior_rest_pitch
			)
			_apply_exterior_look()
		camera_mouse_idle_time = 0.0
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_set_rear_wheel_brake(0.0)

	if not is_driving:
		rollover_timer = 0.0
		engine_force = 0.0
		brake = parking_brake_force
		current_steer = lerpf(
			current_steer,
			0.0,
			clampf(steering_lerp_speed * delta, 0.0, 1.0)
		)
		steering = current_steer
		return

	_update_stability(delta)

	var steer_input := _get_steer_input()
	var target_steer := steer_input * max_steering_angle
	current_steer = lerpf(
		current_steer,
		target_steer,
		clampf(steering_lerp_speed * delta, 0.0, 1.0)
	)
	steering = current_steer

	var forward_pressed := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	var reverse_pressed := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	var handbrake_pressed := Input.is_key_pressed(KEY_SPACE)
	var forward_speed := linear_velocity.dot(-global_transform.basis.z.normalized())
	_update_vehicle_camera(delta, forward_pressed and not reverse_pressed)

	if forward_pressed and not reverse_pressed:
		engine_force = max_engine_force * DRIVETRAIN_DIRECTION
		brake = 0.0
	elif reverse_pressed and not forward_pressed:
		if forward_speed > 0.5:
			engine_force = 0.0
			brake = max_brake_force
		else:
			engine_force = -max_reverse_force * DRIVETRAIN_DIRECTION
			brake = 0.0
	else:
		engine_force = 0.0
		brake = light_drag

	if handbrake_pressed:
		engine_force = 0.0
		_set_rear_wheel_brake(handbrake_force)


func _get_steer_input() -> float:
	var steer_input := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steer_input += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steer_input -= 1.0
	return clampf(steer_input, -1.0, 1.0)


func _configure_wheels() -> void:
	for wheel: VehicleWheel3D in [wheel_fl, wheel_fr, wheel_rl, wheel_rr]:
		wheel.rotation = Vector3.ZERO
		wheel.wheel_radius = 0.38
		wheel.wheel_rest_length = 0.22
		wheel.suspension_travel = 0.24
		wheel.suspension_stiffness = 60.0
		wheel.damping_compression = 2.4
		wheel.damping_relaxation = 3.0
		wheel.wheel_friction_slip = 2.0
		wheel.wheel_roll_influence = 0.08

	wheel_fl.use_as_steering = true
	wheel_fr.use_as_steering = true
	wheel_rl.use_as_steering = false
	wheel_rr.use_as_steering = false
	wheel_fl.use_as_traction = false
	wheel_fr.use_as_traction = false
	wheel_rl.use_as_traction = true
	wheel_rr.use_as_traction = true


func _set_rear_wheel_brake(force: float) -> void:
	wheel_rl.brake = force
	wheel_rr.brake = force


func _reset_vehicle_cameras() -> void:
	camera_yaw = 0.0
	camera_pitch = 0.0
	cockpit_yaw = 0.0
	cockpit_pitch = 0.0
	camera_mouse_idle_time = 0.0
	third_person_rig.rotation = third_person_rig_rest_rotation
	spring_arm.rotation = spring_arm_rest_rotation
	exterior_camera.transform = exterior_camera_rest_transform
	interior_camera.transform = interior_camera_rest_transform
	_apply_exterior_look()
	_apply_cockpit_look()


func _set_vehicle_camera_current(enabled: bool) -> void:
	exterior_camera.current = enabled and not is_cockpit_view
	interior_camera.current = enabled and is_cockpit_view


func _apply_exterior_look() -> void:
	third_person_rig.rotation.y = third_person_rig_rest_rotation.y + camera_yaw
	spring_arm.rotation.x = spring_arm_rest_rotation.x + camera_pitch


func _apply_cockpit_look() -> void:
	interior_camera.rotation = interior_camera_rest_transform.basis.get_euler() + Vector3(
		cockpit_pitch,
		cockpit_yaw,
		0.0
	)


func _update_vehicle_camera(delta: float, accelerating_forward := false) -> void:
	camera_mouse_idle_time += delta
	if is_cockpit_view:
		if not accelerating_forward or camera_mouse_idle_time < cockpit_auto_center_delay:
			return
		var cockpit_blend := 1.0 - exp(-cockpit_auto_center_speed * delta)
		cockpit_yaw = lerp_angle(cockpit_yaw, 0.0, cockpit_blend)
		cockpit_pitch = lerp_angle(cockpit_pitch, 0.0, cockpit_blend)
		_apply_cockpit_look()
		return
	if linear_velocity.length() <= camera_auto_center_min_speed:
		return
	if camera_mouse_idle_time < camera_auto_center_delay:
		return
	camera_yaw = lerp_angle(
		camera_yaw,
		0.0,
		1.0 - exp(-camera_auto_center_speed * delta)
	)
	camera_pitch = lerp_angle(
		camera_pitch,
		0.0,
		1.0 - exp(-camera_auto_center_speed * delta)
	)
	_apply_exterior_look()


func _update_stability(delta: float) -> void:
	var up_alignment := global_transform.basis.y.normalized().dot(Vector3.UP)

	if up_alignment >= rollover_up_dot_threshold:
		rollover_timer = 0.0
		apply_central_force(
			-global_transform.basis.y.normalized()
			* linear_velocity.length()
			* downforce_multiplier
		)
		return

	rollover_timer += delta
	if rollover_timer >= rollover_recovery_delay:
		_recover_upright()


func _recover_upright() -> void:
	var current_heading := global_rotation.y
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_rotation = Vector3(0.0, current_heading, 0.0)
	global_position += Vector3.UP * rollover_lift_height
	sleeping = false
	rollover_timer = 0.0


func _hide_order_note() -> void:
	if not is_instance_valid(order_note_ui):
		order_note_ui = get_tree().get_first_node_in_group("order_note_ui") as CanvasLayer
	if is_instance_valid(order_note_ui):
		order_note_was_visible = order_note_ui.visible
		order_note_ui.visible = false


func _restore_order_note() -> void:
	if is_instance_valid(order_note_ui):
		order_note_ui.visible = order_note_was_visible
