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
	"cut_meat": "Fleisch",
	"tomato": "Tomate",
	"cucumber": "Gurke",
	"onion": "Zwiebeln",
	"salad": "Salat",
	"red_cabbage": "Lila Kraut",
	"garlic_sauce": "Knoblauchsoße",
	"cocktail_sauce": "Cocktailsoße",
}

enum CustomerState { WALKING_IN, WAITING_FOR_ORDER, LEAVING }

@export var spawn_point_path: NodePath
@export var counter_stop_point_path: NodePath
@export_range(0.2, 5.0, 0.05) var move_speed := 1.65
@export_range(0.05, 1.0, 0.01) var arrival_distance := 0.12

var requested_ingredients: Array[String] = []
var state := CustomerState.WALKING_IN
var _spawn_point: Marker3D
var _counter_stop_point: Marker3D
var _rejection_time_left := 0.0
var _walk_time := 0.0

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
	set_meta("accepts_finished_durum", true)
	order_display.visible = false
	happy_display.visible = false
	rejection_label.visible = false
	_spawn_point = get_node_or_null(spawn_point_path) as Marker3D
	_counter_stop_point = get_node_or_null(counter_stop_point_path) as Marker3D
	if not is_instance_valid(_spawn_point):
		_spawn_point = get_tree().current_scene.get_node_or_null("CustomerSpawnPoint") as Marker3D
	if not is_instance_valid(_counter_stop_point):
		_counter_stop_point = get_tree().current_scene.get_node_or_null("CounterStopPoint") as Marker3D
	if is_instance_valid(_spawn_point):
		global_transform = _spawn_point.global_transform
	if not is_instance_valid(_counter_stop_point):
		push_warning("CustomerNPC: CounterStopPoint fehlt; Bestellung wird am Spawnpunkt erzeugt.")
		_arrive_at_counter()


func _physics_process(delta: float) -> void:
	_update_rejection(delta)
	match state:
		CustomerState.WALKING_IN:
			if _walk_to(_counter_stop_point, delta):
				_arrive_at_counter()
		CustomerState.WAITING_FOR_ORDER:
			_stop_walking_animation()
		CustomerState.LEAVING:
			if _walk_to(_spawn_point, delta):
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


func _arrive_at_counter() -> void:
	velocity = Vector3.ZERO
	if is_instance_valid(_counter_stop_point):
		global_rotation.y = _counter_stop_point.global_rotation.y
	state = CustomerState.WAITING_FOR_ORDER
	_generate_random_order()


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
	order_display.visible = true
	happy_display.visible = false
	rejection_label.visible = false
	order_generated.emit(requested_ingredients.duplicate())


func _format_order_text() -> String:
	var lines: Array[String] = ["BESTELLUNG"]
	for ingredient in requested_ingredients:
		lines.append("• %s" % INGREDIENT_LABELS.get(ingredient, ingredient.capitalize()))
	return "\n".join(lines)


func try_accept_durum(durum_data: Dictionary) -> bool:
	if state != CustomerState.WAITING_FOR_ORDER:
		return false
	var delivered_ingredients: Array[String] = []
	var raw_ingredients: Array = durum_data.get("ingredients", [])
	for ingredient in raw_ingredients:
		delivered_ingredients.append(_normalize_ingredient(String(ingredient)))
	for requested in requested_ingredients:
		if _normalize_ingredient(requested) not in delivered_ingredients:
			_show_rejection()
			return false
	_accept_order(delivered_ingredients)
	return true


func _normalize_ingredient(ingredient: String) -> String:
	return "cut_meat" if ingredient == "meat" else ingredient


func _accept_order(delivered_ingredients: Array[String]) -> void:
	order_display.visible = false
	rejection_label.visible = false
	happy_display.visible = false
	set_meta("accepts_finished_durum", false)
	state = CustomerState.LEAVING
	if is_instance_valid(_spawn_point):
		var exit_direction := _spawn_point.global_position - global_position
		exit_direction.y = 0.0
		if not exit_direction.is_zero_approx():
			look_at(global_position + exit_direction.normalized(), Vector3.UP)
	order_completed.emit(delivered_ingredients.duplicate())


func _show_rejection() -> void:
	_rejection_time_left = 1.35
	rejection_label.visible = true


func _update_rejection(delta: float) -> void:
	if _rejection_time_left <= 0.0:
		return
	_rejection_time_left -= delta
	if _rejection_time_left <= 0.0:
		rejection_label.visible = false
