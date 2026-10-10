extends VehicleBody3D

@export var max_engine_force: float = 380.0
@export var max_brake_force: float = 20.0
@export var max_steer_angle: float = 0.55
@export var steer_speed: float = 5.0

# Drift-Werte (Hinterrad-Friktion)
@export var rear_friction_normal: float = 1.8
@export var rear_friction_drift: float = 0.65

var current_steer: float = 0.0

@onready var wheel_rl: VehicleWheel3D = $WheelRearLeft
@onready var wheel_rr: VehicleWheel3D = $WheelRearRight

func _physics_process(delta: float) -> void:
	# Lenkung über A/D (move_left / move_right)
	var steer_input := 0.0
	if Input.is_action_pressed("move_left"):
		steer_input += 1.0
	if Input.is_action_pressed("move_right"):
		steer_input -= 1.0

	var target_steer: float = steer_input * max_steer_angle
	current_steer = move_toward(current_steer, target_steer, steer_speed * delta)
	steering = current_steer

	# Beschleunigung / Rückwärts über W/S (move_forward / move_backward)
	var throttle := 0.0
	if Input.is_action_pressed("move_forward"):
		throttle += 1.0
	if Input.is_action_pressed("move_backward"):
		throttle -= 1.0

	engine_force = throttle * max_engine_force

	# Handbremse & Drift über Leertaste (jump)
	if Input.is_action_pressed("jump"):
		brake = max_brake_force
		wheel_rl.wheel_friction_slip = rear_friction_drift
		wheel_rr.wheel_friction_slip = rear_friction_drift
	else:
		brake = 0.0
		wheel_rl.wheel_friction_slip = rear_friction_normal
		wheel_rr.wheel_friction_slip = rear_friction_normal
