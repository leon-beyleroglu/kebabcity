class_name CustomerQueueManager
extends Node3D

@export var npc_scenes: Array[PackedScene] = []
@export_range(1, 3, 1) var queue_capacity := 3

var customers: Array[CustomerNPC] = []
var _queue_slots: Array[Marker3D] = []
var _spawn_serial := 0
var _started := false

@onready var customer_spawn_point: Marker3D = $CustomerSpawnPoint
@onready var customer_exit_point: Marker3D = $CustomerExitPoint
@onready var order_note_ui: CanvasLayer = %OrderNoteUI
@onready var order_note_header: Label = %OrderNoteHeader
@onready var order_note_ingredients: Label = %OrderNoteIngredients


func _ready() -> void:
	_hide_order_note()
	_queue_slots = [
		$QueueSlot_0 as Marker3D,
		$QueueSlot_1 as Marker3D,
		$QueueSlot_2 as Marker3D,
	]
	call_deferred("_initialize_queue")


func _initialize_queue() -> void:
	if _started:
		return
	_started = true
	var scene_indices: Array[int] = []
	for scene_index in npc_scenes.size():
		scene_indices.append(scene_index)
	scene_indices.shuffle()
	for index in mini(queue_capacity, mini(_queue_slots.size(), scene_indices.size())):
		_spawn_customer(scene_indices[index])


func customer_order_completed(customer: CustomerNPC) -> void:
	if customers.is_empty() or customers[0] != customer:
		return
	_hide_order_note()
	customers.pop_front()
	customer.begin_exit(customer_exit_point)
	for index in customers.size():
		customers[index].assign_queue_slot(index, _queue_slots[index])
	if customers.size() < mini(queue_capacity, _queue_slots.size()):
		_spawn_customer(randi_range(0, npc_scenes.size() - 1))


func _spawn_customer(scene_index: int) -> CustomerNPC:
	if npc_scenes.is_empty() or scene_index < 0 or scene_index >= npc_scenes.size():
		return null
	if not is_instance_valid(npc_scenes[scene_index]) or customers.size() >= _queue_slots.size():
		return null
	var customer := npc_scenes[scene_index].instantiate() as CustomerNPC
	if not is_instance_valid(customer):
		return null
	_spawn_serial += 1
	customer.name = "Customer_%s_%02d" % [CustomerNPC.VARIANT_NAMES[customer.customer_variant], _spawn_serial]
	customer.queue_managed = true
	add_child(customer)
	customers.append(customer)
	customer.order_generated.connect(_show_order_note.bind(customer))
	var assigned_index := customers.size() - 1
	customer.configure_for_queue(
		self,
		assigned_index,
		_queue_slots[assigned_index],
		customer_spawn_point,
		customer_exit_point
	)
	return customer


func _show_order_note(ingredients: Array[String], customer: CustomerNPC) -> void:
	if customers.is_empty() or customers[0] != customer or customer.queue_index != 0:
		return
	var lines: Array[String] = []
	for ingredient: String in ingredients:
		lines.append("• %s" % CustomerNPC.INGREDIENT_LABELS.get(ingredient, ingredient.capitalize()))
	order_note_header.text = "Bestellung · %s" % CustomerNPC.VARIANT_NAMES[customer.customer_variant]
	order_note_ingredients.text = "\n".join(lines)
	order_note_ui.visible = true


func _hide_order_note() -> void:
	order_note_ingredients.text = ""
	order_note_ui.visible = false
