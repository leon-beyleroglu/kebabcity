class_name RolledDoener
extends Area3D

var current_toppings: Array[String] = []


func _ready() -> void:
	add_to_group("rolled_doner")
	collision_layer = 1 << 7
	collision_mask = 0
	monitoring = false
	monitorable = true
	var saved_toppings: Variant = get_meta("ingredients", [])
	if saved_toppings is Array and current_toppings.is_empty():
		for topping: Variant in saved_toppings:
			current_toppings.append(String(topping))
	_sync_metadata()


func configure(toppings: Array) -> void:
	current_toppings.clear()
	for topping: Variant in toppings:
		current_toppings.append(String(topping))
	_sync_metadata()


func get_meal_data() -> Dictionary:
	return {
		"id": "finished_durum",
		"is_baked": true,
		"is_rolled": true,
		"ingredients": current_toppings.duplicate(),
		"toppings": current_toppings.duplicate(),
	}


func _sync_metadata() -> void:
	set_meta("item_id", "durum_assembly")
	set_meta("ingredient_id", "durum_assembly")
	set_meta("is_present", true)
	set_meta("is_baked", true)
	set_meta("is_rolled", true)
	set_meta("ingredients", current_toppings.duplicate())
