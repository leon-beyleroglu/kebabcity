class_name MeatTray
extends Node3D

var current_portions: int = 0
var current_items: Array[Area3D] = []
var _portion_restore_callback: Callable


func _ready() -> void:
	add_to_group("meat_tray")


func configure_persistence(portion_restore_callback: Callable) -> void:
	_portion_restore_callback = portion_restore_callback


func register_portion(item: Area3D) -> void:
	if not is_instance_valid(item) or current_items.has(item):
		return
	current_items.append(item)
	current_portions = current_items.size()
	item.set_meta("item_id", "cut_meat")
	item.set_meta("ingredient_id", "cut_meat")
	item.set_meta("prep_station", self)
	item.add_to_group("placed_items")
	var exit_callback := _on_portion_tree_exiting.bind(item)
	if not item.tree_exiting.is_connected(exit_callback):
		item.tree_exiting.connect(exit_callback, CONNECT_ONE_SHOT)


func remove_item(item: Area3D) -> void:
	if not is_instance_valid(item):
		return
	current_items.erase(item)
	current_portions = current_items.size()
	item.remove_meta("prep_station")


func get_save_data() -> Dictionary:
	return {"portions": current_portions}


func load_save_data(data: Dictionary) -> bool:
	if not _portion_restore_callback.is_valid():
		return false
	var portions := maxi(int(data.get("portions", 0)), 0)
	var items_to_remove := current_items.duplicate()
	current_items.clear()
	current_portions = 0
	for item: Area3D in items_to_remove:
		if is_instance_valid(item):
			item.queue_free()
	_portion_restore_callback.call(portions)
	return true


func _on_portion_tree_exiting(item: Area3D) -> void:
	current_items.erase(item)
	current_portions = current_items.size()
