extends CharacterBody3D

@export var walk_speed := 5.0
@export var sprint_speed := 9.0
@export var jump_velocity := 5.0
@export var mouse_sensitivity := 0.002

@onready var camera: Camera3D = $Camera3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

const FIRST_PERSON_POSITION := Vector3(0.0, 0.7549808, 0.0)

func _ready() -> void:
	Engine.max_fps = 60
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.position = FIRST_PERSON_POSITION
	camera.rotation = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Nur relative Mausbewegung verwenden
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-event.relative.x * mouse_sensitivity)

			camera.rotate_x(-event.relative.y * mouse_sensitivity)

			camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:

	# =========================
	# SCHWERKRAFT
	# =========================

	if not is_on_floor():
		velocity.y -= gravity * delta


	# =========================
	# SPRINGEN
	# =========================

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity


	# =========================
	# GESCHWINDIGKEIT
	# =========================

	var current_speed := walk_speed

	if Input.is_action_pressed("sprint"):
		current_speed = sprint_speed


	# =========================
	# WASD
	# =========================

	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)

	var direction := (transform.basis * Vector3(
		input_direction.x,
		0,
		input_direction.y
	)).normalized()


	# =========================
	# BEWEGUNG
	# =========================

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(
			velocity.x,
			0,
			current_speed
		)

		velocity.z = move_toward(
			velocity.z,
			0,
			current_speed
		)


	# Bewegung ausführen
	move_and_slide()
