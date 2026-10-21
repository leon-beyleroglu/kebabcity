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

# This Tofas model's visible front is local -Z. Negative VehicleBody3D wheel
# force therefore drives it toward its hood instead of toward its trunk.
const DRIVETRAIN_DIRECTION := -1.0

var can_enter := false
var is_driving := false
var nearby_player: CharacterBody3D
var driver: CharacterBody3D
var current_steer := 0.0
var order_note_ui: CanvasLayer
var order_note_was_visible := false

@onready var wheel_fl: VehicleWheel3D = $Wheel_FL
@onready var wheel_fr: VehicleWheel3D = $Wheel_FR
@onready var wheel_rl: VehicleWheel3D = $Wheel_RL
@onready var wheel_rr: VehicleWheel3D = $Wheel_RR
@onready var interaction_area: Area3D = $InteractionArea
@onready var vehicle_camera: Camera3D = $VehicleCamera
@onready var driver_seat: Marker3D = $DriverSeat
@onready var exit_point: Marker3D = $ExitPoint


func _ready() -> void:
	mass = vehicle_mass
	_configure_wheels()
	order_note_ui = get_tree().get_first_node_in_group("order_note_ui") as CanvasLayer
	interaction_area.body_entered.connect(_on_interaction_area_body_entered)
	interaction_area.body_exited.connect(_on_interaction_area_body_exited)
	vehicle_camera.current = false
	engine_force = 0.0
	brake = parking_brake_force
	steering = 0.0


func enter_vehicle(player: CharacterBody3D) -> void:
	if is_driving or not is_instance_valid(player):
		return
	driver = player
	is_driving = true
	can_enter = false
	sleeping = false
	_hide_order_note()
	if driver.has_method("enter_vehicle_mode"):
		driver.call("enter_vehicle_mode", self, driver_seat)
	else:
		driver.visible = false
		driver.set_physics_process(false)
		driver.set_process_input(false)
		driver.set_process_unhandled_input(false)
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
	vehicle_camera.current = false
	_restore_order_note()
	var exiting_player := driver
	driver = null
	nearby_player = null
	can_enter = false
	if not is_instance_valid(exiting_player):
		return
	if exiting_player.has_method("exit_vehicle_mode"):
		exiting_player.call("exit_vehicle_mode", exit_point.global_transform)
	else:
		exiting_player.global_transform = exit_point.global_transform
		exiting_player.visible = true
		exiting_player.set_physics_process(true)
		exiting_player.set_process_input(true)
		exiting_player.set_process_unhandled_input(true)


func _physics_process(delta: float) -> void:
	_set_rear_wheel_brake(0.0)

	if not is_driving:
		engine_force = 0.0
		brake = parking_brake_force
		current_steer = lerpf(
			current_steer,
			0.0,
			clampf(steering_lerp_speed * delta, 0.0, 1.0)
		)
		steering = current_steer
		return

	var steer_input := _get_steer_input()
	var target_steer := steer_input * max_steering_angle
	current_steer = lerpf(
		current_steer,
		target_steer,
		clampf(steering_lerp_speed * delta, 0.0, 1.0)
	)
	steering = current_steer

	var forward_pressed := Input.is_action_pressed("move_forward") or Input.is_key_pressed(KEY_UP)
	var reverse_pressed := Input.is_action_pressed("move_backward") or Input.is_key_pressed(KEY_DOWN)
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
	var steer_input := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	if Input.is_key_pressed(KEY_LEFT):
		steer_input += 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		steer_input -= 1.0
	return clampf(steer_input, -1.0, 1.0)


func _configure_wheels() -> void:
	for wheel: VehicleWheel3D in [wheel_fl, wheel_fr, wheel_rl, wheel_rr]:
		wheel.rotation = Vector3.ZERO

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


func _hide_order_note() -> void:
	if not is_instance_valid(order_note_ui):
		order_note_ui = get_tree().get_first_node_in_group("order_note_ui") as CanvasLayer
	if is_instance_valid(order_note_ui):
		order_note_was_visible = order_note_ui.visible
		order_note_ui.visible = false


func _restore_order_note() -> void:
	if is_instance_valid(order_note_ui):
		order_note_ui.visible = order_note_was_visible


func _on_interaction_area_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("player") and not is_driving:
		nearby_player = body as CharacterBody3D
		can_enter = true
		if body.has_method("set_nearby_vehicle"):
			body.call("set_nearby_vehicle", self)


func _on_interaction_area_body_exited(body: Node3D) -> void:
	if body == nearby_player and not is_driving:
		if body.has_method("set_nearby_vehicle"):
			body.call("set_nearby_vehicle", null)
		nearby_player = null
		can_enter = false
