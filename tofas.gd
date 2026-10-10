extends VehicleBody3D

@export var max_engine_force: float = 380.0
@export var max_brake_force: float = 25.0
@export var max_steer_angle: float = 0.55
@export var steer_speed: float = 5.0
@export var interact_distance: float = 3.2

# Drift-Parameter
@export var rear_friction_normal: float = 1.8
@export var rear_friction_drift: float = 0.65

var is_player_inside: bool = false
var current_steer: float = 0.0

@onready var wheel_rl: VehicleWheel3D = $WheelRearLeft
@onready var wheel_rr: VehicleWheel3D = $WheelRearRight
@onready var car_camera: Camera3D = $CarCameraMount/Camera3D
@onready var exit_point: Marker3D = $ExitPoint
@onready var player: CharacterBody3D = get_tree().current_scene.get_node_or_null("Player")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
		if is_player_inside:
			exit_car()
		elif player and global_position.distance_to(player.global_position) <= interact_distance:
			enter_car()

func enter_car() -> void:
	is_player_inside = true
	
	# Spieler unsichtbar machen und dessen Kollision/Verarbeitung deaktivieren
	player.visible = false
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.get_node("CollisionShape3D").disabled = true
	
	# Fahrkamera aktivieren
	car_camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func exit_car() -> void:
	is_player_inside = false
	
	# Vollbremsung beim Verlassen, damit das Auto nicht wegrollt
	engine_force = 0.0
	brake = max_brake_force
	steering = 0.0
	
	# Spieler neben der Fahrertür absetzen und reaktivieren
	player.global_position = exit_point.global_position
	player.visible = true
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	player.get_node("CollisionShape3D").disabled = false
	
	# Ego-Perspektive des Spielers reaktivieren
	var player_cam: Camera3D = player.get_node("Camera3D")
	player_cam.current = true

func _physics_process(delta: float) -> void:
	# Solange kein Spieler im Auto sitzt: Motor aus, Handbremse an
	if not is_player_inside:
		engine_force = 0.0
		brake = max_brake_force
		steering = 0.0
		return

	# Lenkung über A/D (move_left / move_right)
	var steer_input := 0.0
	if Input.is_action_pressed("move_left"):
		steer_input += 1.0
	if Input.is_action_pressed("move_right"):
		steer_input -= 1.0

	var target_steer: float = steer_input * max_steer_angle
	current_steer = move_toward(current_steer, target_steer, steer_speed * delta)
	steering = current_steer

	# Gas / Rückwärts über W/S (move_forward / move_backward)
	var throttle := 0.0
	if Input.is_action_pressed("move_forward"):
		throttle += 1.0
	if Input.is_action_pressed("move_backward"):
		throttle -= 1.0

	engine_force = throttle * max_engine_force

	# Handbremse & Drift (Leertaste / jump)
	if Input.is_action_pressed("jump"):
		brake = max_brake_force
		wheel_rl.wheel_friction_slip = rear_friction_drift
		wheel_rr.wheel_friction_slip = rear_friction_drift
	else:
		brake = 0.0
		wheel_rl.wheel_friction_slip = rear_friction_normal
		wheel_rr.wheel_friction_slip = rear_friction_normal