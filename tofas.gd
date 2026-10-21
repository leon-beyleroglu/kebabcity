extends VehicleBody3D

@export var max_engine_force := 900.0
@export var reverse_engine_force := 500.0
@export var max_brake_force := 35.0
@export var rolling_brake_force := 2.5
@export var parking_brake_force := 18.0
@export var max_steer_angle := 0.4
@export var steer_speed := 2.5

var can_enter := false
var is_driving := false
var nearby_player: CharacterBody3D
var driver: CharacterBody3D
var current_steer := 0.0

@onready var wheel_fl: VehicleWheel3D = $Wheel_FL
@onready var wheel_fr: VehicleWheel3D = $Wheel_FR
@onready var wheel_rl: VehicleWheel3D = $Wheel_RL
@onready var wheel_rr: VehicleWheel3D = $Wheel_RR
@onready var interaction_area: Area3D = $InteractionArea
@onready var vehicle_camera: Camera3D = $VehicleCamera
@onready var driver_seat: Marker3D = $DriverSeat
@onready var exit_point: Marker3D = $ExitPoint


func _ready() -> void:
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
	steering = 0.0
	current_steer = 0.0
	vehicle_camera.current = false
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
	if not is_driving:
		engine_force = move_toward(engine_force, 0.0, max_engine_force * delta * 4.0)
		brake = parking_brake_force
		current_steer = move_toward(current_steer, 0.0, steer_speed * delta)
		steering = current_steer
		return

	var steer_input := _get_steer_input()
	var target_steer := steer_input * max_steer_angle
	current_steer = move_toward(current_steer, target_steer, steer_speed * delta)
	steering = current_steer

	var forward_pressed := Input.is_action_pressed("move_forward") or Input.is_key_pressed(KEY_UP)
	var reverse_pressed := Input.is_action_pressed("move_backward") or Input.is_key_pressed(KEY_DOWN)
	var forward_speed := linear_velocity.dot(-global_basis.z)

	if forward_pressed and not reverse_pressed:
		engine_force = move_toward(engine_force, max_engine_force, max_engine_force * delta * 3.0)
		brake = 0.0
	elif reverse_pressed and not forward_pressed:
		if forward_speed > 0.5:
			engine_force = move_toward(engine_force, 0.0, max_engine_force * delta * 5.0)
			brake = max_brake_force
		else:
			engine_force = move_toward(engine_force, -reverse_engine_force, reverse_engine_force * delta * 3.0)
			brake = 0.0
	else:
		engine_force = move_toward(engine_force, 0.0, max_engine_force * delta * 2.0)
		brake = rolling_brake_force


func _get_steer_input() -> float:
	var steer_input := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	if Input.is_key_pressed(KEY_LEFT):
		steer_input += 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		steer_input -= 1.0
	return clampf(steer_input, -1.0, 1.0)


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
