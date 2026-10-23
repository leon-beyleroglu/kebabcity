class_name CustomerNPC
extends CharacterBody3D

signal order_generated(ingredients: Array[String])
signal order_completed(ingredients: Array[String])

const INTERACTION_LAYER := 1 << 7
const INGREDIENT_POOL := [
	"meat",
	"tomato",
	"cucumber",
	"onion",
	"salad",
	"red_cabbage",
	"garlic_sauce",
	"cocktail_sauce",
]
const INGREDIENT_LABELS := {
	"meat": "Dönerfleisch",
	"cut_meat": "Dönerfleisch",
	"tomato": "Tomate",
	"cucumber": "Gurke",
	"onion": "Zwiebeln",
	"salad": "Salat",
	"red_cabbage": "Lila Kraut",
	"garlic_sauce": "Knoblauchsoße",
	"cocktail_sauce": "Cocktailsoße",
}
const VARIANT_NAMES := ["BJK", "FENER", "GALA"]

enum CustomerVariant { BJK, FENER, GALA }
enum CustomerState { MOVING_TO_QUEUE, WAITING_IN_QUEUE, ORDERING, LEAVING }

@export_enum("BJK", "Fener", "Gala") var customer_variant: int = CustomerVariant.BJK
@export var queue_managed := false
@export var spawn_point_path: NodePath
@export var counter_stop_point_path: NodePath
@export_range(0.2, 5.0, 0.05) var move_speed := 1.65
@export_range(0.05, 1.0, 0.01) var arrival_distance := 0.12

var requested_ingredients: Array[String] = []
var queue_index := -1
var order_active := false
var state := CustomerState.WAITING_IN_QUEUE
var _queue_manager: Node
var _spawn_point: Marker3D
var _exit_point: Marker3D
var _target_marker: Marker3D
var _rejection_time_left := 0.0
var _walk_time := 0.0

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var order_display: Node3D = $OrderDisplay
@onready var order_label: Label3D = $OrderDisplay/OrderLabel
@onready var rejection_label: Label3D = $OrderDisplay/RejectionLabel
@onready var happy_display: Node3D = $HappyDisplay
@onready var left_arm: Node3D = $Visual/LeftArm
@onready var right_arm: Node3D = $Visual/RightArm
@onready var left_leg: Node3D = $Visual/LeftLeg
@onready var right_leg: Node3D = $Visual/RightLeg


func _ready() -> void:
	add_to_group("customer_npc")
	collision_layer = INTERACTION_LAYER
	set_meta("customer_npc", true)
	set_meta("accepts_finished_durum", false)
	set_meta("customer_variant", VARIANT_NAMES[customer_variant])
	order_display.visible = false
	happy_display.visible = false
	rejection_label.visible = false
	if queue_managed:
		return
	var scene_root := get_tree().current_scene
	_spawn_point = get_node_or_null(spawn_point_path) as Marker3D
	_target_marker = get_node_or_null(counter_stop_point_path) as Marker3D
	if not is_instance_valid(_spawn_point) and is_instance_valid(scene_root):
		_spawn_point = scene_root.get_node_or_null("CustomerSpawnPoint") as Marker3D
	if not is_instance_valid(_target_marker) and is_instance_valid(scene_root):
		_target_marker = scene_root.get_node_or_null("CounterStopPoint") as Marker3D
	if is_instance_valid(_spawn_point):
		global_transform = _spawn_point.global_transform
	if is_instance_valid(_target_marker):
		queue_index = 0
		_generate_random_order()
		state = CustomerState.MOVING_TO_QUEUE


func configure_for_queue(
		manager: Node,
		assigned_index: int,
		assigned_slot: Marker3D,
		spawn_point: Marker3D,
		exit_point: Marker3D
) -> void:
	queue_managed = true
	_queue_manager = manager
	_spawn_point = spawn_point
	_exit_point = exit_point
	if is_instance_valid(_spawn_point):
		global_transform = _spawn_point.global_transform
	_generate_random_order()
	assign_queue_slot(assigned_index, assigned_slot)


func assign_queue_slot(assigned_index: int, assigned_slot: Marker3D) -> void:
	queue_index = assigned_index
	_target_marker = assigned_slot
	order_active = false
	order_display.visible = false
	rejection_label.visible = false
	set_meta("queue_index", queue_index)
	set_meta("accepts_finished_durum", false)
	if is_instance_valid(navigation_agent) and is_instance_valid(_target_marker):
		navigation_agent.target_position = _target_marker.global_position
	state = CustomerState.MOVING_TO_QUEUE


func begin_exit(exit_point: Marker3D = null) -> void:
	queue_index = -1
	order_active = false
	order_display.visible = false
	rejection_label.visible = false
	set_meta("queue_index", -1)
	set_meta("accepts_finished_durum", false)
	_target_marker = exit_point if is_instance_valid(exit_point) else _exit_point
	if not is_instance_valid(_target_marker):
		_target_marker = _spawn_point
	if is_instance_valid(navigation_agent) and is_instance_valid(_target_marker):
		navigation_agent.target_position = _target_marker.global_position
	state = CustomerState.LEAVING
	_face_target(_target_marker)


func _physics_process(delta: float) -> void:
	_update_rejection(delta)
	match state:
		CustomerState.MOVING_TO_QUEUE:
			if _walk_to(_target_marker, delta):
				_arrive_at_queue_slot()
		CustomerState.WAITING_IN_QUEUE, CustomerState.ORDERING:
			_stop_walking_animation()
		CustomerState.LEAVING:
			if _walk_to(_target_marker, delta):
				queue_free()


func _walk_to(target: Marker3D, delta: float) -> bool:
	if not is_instance_valid(target):
		velocity = Vector3.ZERO
		return true
	var offset := target.global_position - global_position
	offset.y = 0.0
	if offset.length() <= arrival_distance:
		velocity = Vector3.ZERO
		global_position.x = target.global_position.x
		global_position.z = target.global_position.z
		_stop_walking_animation()
		return true
	var direction := offset.normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	velocity.y = -0.2 if is_on_floor() else velocity.y - 18.0 * delta
	look_at(global_position + direction, Vector3.UP)
	move_and_slide()
	_animate_walk(delta)
	return false


func _face_target(target: Marker3D) -> void:
	if not is_instance_valid(target):
		return
	var direction := target.global_position - global_position
	direction.y = 0.0
	if not direction.is_zero_approx():
		look_at(global_position + direction.normalized(), Vector3.UP)


func _animate_walk(delta: float) -> void:
	_walk_time += delta * move_speed * 5.0
	var swing := sin(_walk_time) * 0.42
	left_arm.rotation.x = swing
	right_arm.rotation.x = -swing
	left_leg.rotation.x = -swing * 0.72
	right_leg.rotation.x = swing * 0.72


func _stop_walking_animation() -> void:
	left_arm.rotation.x = move_toward(left_arm.rotation.x, 0.0, 0.08)
	right_arm.rotation.x = move_toward(right_arm.rotation.x, 0.0, 0.08)
	left_leg.rotation.x = move_toward(left_leg.rotation.x, 0.0, 0.08)
	right_leg.rotation.x = move_toward(right_leg.rotation.x, 0.0, 0.08)


func _arrive_at_queue_slot() -> void:
	velocity = Vector3.ZERO
	if is_instance_valid(_target_marker):
		global_rotation.y = _target_marker.global_rotation.y
	if queue_index == 0:
		_activate_front_order()
	else:
		state = CustomerState.WAITING_IN_QUEUE
		order_active = false
		order_display.visible = false


func _activate_front_order() -> void:
	state = CustomerState.ORDERING
	order_active = true
	order_display.visible = false
	rejection_label.visible = false
	set_meta("accepts_finished_durum", true)
	order_generated.emit(requested_ingredients.duplicate())


func _generate_random_order() -> void:
	var available: Array[String] = []
	for ingredient: String in INGREDIENT_POOL:
		if ingredient != "meat":
			available.append(ingredient)
	available.shuffle()
	requested_ingredients.clear()
	requested_ingredients.append("meat")
	var ingredient_count := randi_range(2, 5)
	for index in ingredient_count - 1:
		requested_ingredients.append(available[index])
	set_meta("requested_ingredients", requested_ingredients.duplicate())
	order_label.text = _format_order_text()
	order_display.visible = false
	happy_display.visible = false
	rejection_label.visible = false


func _format_order_text() -> String:
	var lines: Array[String] = ["BESTELLUNG"]
	for ingredient in requested_ingredients:
		lines.append("• %s" % INGREDIENT_LABELS.get(ingredient, ingredient.capitalize()))
	return "\n".join(lines)


func try_accept_durum(durum_data: Dictionary) -> bool:
	if not order_active or queue_index != 0 or state != CustomerState.ORDERING:
		return false
	var delivered_ingredients: Array[String] = []
	var raw_ingredients: Array = durum_data.get("ingredients", [])
	for ingredient in raw_ingredients:
		delivered_ingredients.append(String(ingredient))
	if not validate_durum_order(delivered_ingredients, requested_ingredients):
		_show_rejection()
		return false
	var normalized_delivery: Array[String] = []
	for ingredient in delivered_ingredients:
		normalized_delivery.append(_normalize_ingredient(ingredient))
	_accept_order(normalized_delivery)
	return true


func validate_durum_order(
	prepared_ingredients: Array[String],
	order_ingredients: Array[String]
) -> bool:
	var normalized_prepared: Array[String] = []
	for ingredient in prepared_ingredients:
		normalized_prepared.append(_normalize_ingredient(ingredient))
	var normalized_request: Array[String] = []
	for ingredient in order_ingredients:
		normalized_request.append(_normalize_ingredient(ingredient))
	for ingredient in normalized_prepared:
		if ingredient not in normalized_request:
			_show_order_feedback("Falsche Bestellung!")
			return false
	for requested in normalized_request:
		if requested not in normalized_prepared:
			_show_order_feedback("Falsche Bestellung!")
			return false
	return true


func _normalize_ingredient(ingredient: String) -> String:
	match ingredient:
		"meat", "cut_meat":
			return "cut_meat"
		"lettuce", "salad":
			return "salad"
	return ingredient


func _show_order_feedback(message: String, success := false) -> void:
	if is_instance_valid(_queue_manager) and _queue_manager.has_method("show_order_feedback"):
		_queue_manager.call("show_order_feedback", message, success)
		return
	var money_hud := get_tree().get_first_node_in_group("money_hud") as MoneyHUD
	if is_instance_valid(money_hud):
		money_hud.show_order_feedback(message, success)


func _accept_order(delivered_ingredients: Array[String]) -> void:
	order_active = false
	order_display.visible = false
	rejection_label.visible = false
	happy_display.visible = false
	set_meta("accepts_finished_durum", false)
	order_completed.emit(delivered_ingredients.duplicate())
	if is_instance_valid(_queue_manager) and _queue_manager.has_method("customer_order_completed"):
		_queue_manager.call("customer_order_completed", self)
	else:
		begin_exit(_exit_point)


func _show_rejection() -> void:
	_rejection_time_left = 1.35
	rejection_label.visible = true


func _update_rejection(delta: float) -> void:
	if _rejection_time_left <= 0.0:
		return
	_rejection_time_left -= delta
	if _rejection_time_left <= 0.0:
		rejection_label.visible = false
