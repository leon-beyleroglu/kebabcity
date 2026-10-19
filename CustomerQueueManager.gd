class_name CustomerQueueManager
extends Node3D

@export var customer_scene: PackedScene = preload("res://CustomerNPC.tscn")
@export_range(1, 3, 1) var queue_capacity := 3

var customers: Array[CustomerNPC] = []
var _queue_slots: Array[Marker3D] = []
var _spawn_serial := 0
var _started := false

@onready var customer_spawn_point: Marker3D = $CustomerSpawnPoint
@onready var customer_exit_point: Marker3D = $CustomerExitPoint


func _ready() -> void:
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
	var initial_variants: Array[int] = [
		CustomerNPC.CustomerVariant.BJK,
		CustomerNPC.CustomerVariant.FENER,
		CustomerNPC.CustomerVariant.GALA,
	]
	initial_variants.shuffle()
	for index in mini(queue_capacity, _queue_slots.size()):
		_spawn_customer(initial_variants[index])


func customer_order_completed(customer: CustomerNPC) -> void:
	if customers.is_empty() or customers[0] != customer:
		return
	customers.pop_front()
	customer.begin_exit(customer_exit_point)
	for index in customers.size():
		customers[index].assign_queue_slot(index, _queue_slots[index])
	if customers.size() < mini(queue_capacity, _queue_slots.size()):
		_spawn_customer(randi_range(CustomerNPC.CustomerVariant.BJK, CustomerNPC.CustomerVariant.GALA))


func _spawn_customer(variant: int) -> CustomerNPC:
	if not is_instance_valid(customer_scene) or customers.size() >= _queue_slots.size():
		return null
	var customer := customer_scene.instantiate() as CustomerNPC
	if not is_instance_valid(customer):
		return null
	_spawn_serial += 1
	customer.name = "Customer_%s_%02d" % [CustomerNPC.VARIANT_NAMES[variant], _spawn_serial]
	customer.customer_variant = variant
	customer.queue_managed = true
	add_child(customer)
	customers.append(customer)
	var assigned_index := customers.size() - 1
	customer.configure_for_queue(
		self,
		assigned_index,
		_queue_slots[assigned_index],
		customer_spawn_point,
		customer_exit_point
	)
	return customer
