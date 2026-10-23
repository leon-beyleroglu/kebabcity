class_name PlayerInventory
extends RefCounted


static func add_item(item_id: String, amount: int = 1) -> void:
	GameState.add_inventory_item(item_id, amount)


static func remove_item(item_id: String, amount: int = 1) -> bool:
	return GameState.remove_inventory_item(item_id, amount)


static func get_count(item_id: String) -> int:
	return GameState.get_inventory_count(item_id)
