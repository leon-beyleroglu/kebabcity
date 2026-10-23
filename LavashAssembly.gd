class_name LavashAssembly
extends Area3D

signal topping_added(ingredient_name: String, toppings: Array[String])
signal finalized(toppings: Array[String])

const ALLOWED_TOPPINGS: Array[String] = [
	"cut_meat",
	"onion",
	"cucumber",
	"salad",
	"lettuce",
	"tomato",
	"red_cabbage",
	"garlic_sauce",
	"cocktail_sauce",
]

@export var is_baked := true
@export var topping_socket_path := NodePath("IngredientSocket")

var lavash_ingredients: Array[String] = []

@onready var topping_socket := get_node_or_null(topping_socket_path) as Node3D


func _ready() -> void:
	set_meta("durum_assembly", true)
	set_meta("is_baked", is_baked)
	var saved_toppings: Variant = get_meta("ingredients", [])
	if saved_toppings is Array:
		for raw_topping: Variant in saved_toppings:
			var topping := _normalize_topping(String(raw_topping))
			if not topping.is_empty():
				lavash_ingredients.append(topping)
	_sync_metadata()


func can_add_topping(ingredient_name: String) -> bool:
	return is_baked and ALLOWED_TOPPINGS.has(_normalize_topping(ingredient_name))


func add_topping(ingredient_name: String, topping_visual: Node3D) -> bool:
	var topping := _normalize_topping(ingredient_name)
	if not can_add_topping(topping) or not is_instance_valid(topping_visual):
		return false
	var socket := _get_topping_socket()
	if not is_instance_valid(socket):
		return false
	if topping_visual.get_parent() == null:
		socket.add_child(topping_visual)
	elif topping_visual.get_parent() != socket:
		topping_visual.reparent(socket, false)
	var stack_index := lavash_ingredients.size()
	topping_visual.name = "Topping_%02d_%s" % [stack_index + 1, topping.to_pascal_case()]
	topping_visual.position = _topping_position(topping, stack_index)
	topping_visual.rotation = Vector3(
		0.0,
		float((stack_index * 137) % 360) * PI / 180.0,
		deg_to_rad(float((stack_index % 3) - 1) * 5.0)
	)
	topping_visual.scale = Vector3.ONE
	topping_visual.visible = true
	lavash_ingredients.append(topping)
	_sync_metadata()
	topping_added.emit(topping, lavash_ingredients.duplicate())
	return true


func restore_toppings(toppings: Array, visual_factory: Callable) -> void:
	_clear_topping_visuals()
	lavash_ingredients.clear()
	_sync_metadata()
	if not visual_factory.is_valid():
		return
	for raw_topping: Variant in toppings:
		var topping := _normalize_topping(String(raw_topping))
		if not can_add_topping(topping):
			continue
		var visual := visual_factory.call(topping) as Node3D
		if is_instance_valid(visual):
			add_topping(topping, visual)


func get_toppings() -> Array[String]:
	return lavash_ingredients.duplicate()


func can_finalize() -> bool:
	return is_baked and not lavash_ingredients.is_empty()


func finalize_meal() -> Dictionary:
	if not can_finalize():
		return {}
	var toppings := get_toppings()
	finalized.emit(toppings)
	return {
		"id": "finished_durum",
		"is_baked": true,
		"ingredients": toppings,
		"toppings": toppings,
	}


func get_save_data() -> Dictionary:
	return {
		"is_present": true,
		"is_baked": is_baked,
		"toppings": get_toppings(),
	}


func _get_topping_socket() -> Node3D:
	if not is_instance_valid(topping_socket):
		topping_socket = get_node_or_null(topping_socket_path) as Node3D
	return topping_socket


func _clear_topping_visuals() -> void:
	var socket := _get_topping_socket()
	if not is_instance_valid(socket):
		return
	for child in socket.get_children():
		child.queue_free()


func _sync_metadata() -> void:
	set_meta("ingredients", lavash_ingredients.duplicate())
	set_meta("placed_count", lavash_ingredients.size())


func _normalize_topping(raw_id: String) -> String:
	var normalized := raw_id.strip_edges().to_lower()
	if normalized.begins_with("sliced_"):
		normalized = normalized.trim_prefix("sliced_")
	if normalized == "lettuce":
		normalized = "salad"
	return normalized if ALLOWED_TOPPINGS.has(normalized) else ""


func _topping_position(topping: String, index: int) -> Vector3:
	var column := index % 5
	var row := index / 5
	var x := -0.22 + float(column) * 0.11
	var z := -0.045 + float((index * 2) % 3) * 0.045
	var y := 0.012 + float(row) * 0.018
	if topping == "cut_meat":
		y += 0.004
	elif topping == "garlic_sauce" or topping == "cocktail_sauce":
		y += 0.025
	return Vector3(x, y, z)
