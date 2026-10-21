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

@onready var wheel_fl: VehicleWheel3D = $Wheel_FL
@onready var wheel_fr: VehicleWheel3D = $Wheel_FR
@onready var wheel_rl: VehicleWheel3D = $Wheel_RL
@onready var wheel_rr: VehicleWheel3D = $Wheel_RR
@onready var vehicle_camera: Camera3D = $VehicleCamera
@onready var driver_seat: Marker3D = $DriverSeat
@onready var exit_point: Marker3D = $ExitPoint


func _ready() -> void:
	add_to_group("vehicles")
	mass = vehicle_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = center_of_mass_offset
	_configure_wheels()
	order_note_ui = get_tree().get_first_node_in_group("order_note_ui") as CanvasLayer
	vehicle_camera.current = false
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
	vehicle_camera.current = true
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
	vehicle_camera.current = false
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
