class_name SupplyBox
extends StaticBody3D

signal stock_changed(ingredient_type: String, current_stock: int)

@export_enum("onion", "cucumber", "lettuce", "tomato", "red_cabbage")
var ingredient_type: String = "onion"
@export_range(1, 5, 1) var max_capacity: int = 5

var current_stock: int = 5
var _visual_items: Array[Node3D] = []

@onready var pickup_area: Area3D = $PickupArea
@onready var preview_items: Node3D = $PreviewItems


func _ready() -> void:
	ingredient_type = WholeVegetableFactory.normalize_ingredient_id(ingredient_type)
	if ingredient_type.is_empty():
		ingredient_type = "onion"
	max_capacity = clampi(max_capacity, 1, GameState.RAW_SUPPLY_MAX_STOCK)
	add_to_group("raw_supply_box")

	pickup_area.collision_layer = KebabInteractionSystem.INTERACTION_LAYER
	pickup_area.collision_mask = 0
	pickup_area.set_meta("supply_box_owner", self)
	pickup_area.set_meta("supply_crate_owner", self)
	set_meta("supply_box_owner", self)
	set_meta("supply_crate_owner", self)

	_build_stock_visuals()
	load_stock(GameState.get_raw_supply_stock(ingredient_type))
	if not GameState.raw_supply_stock_updated.is_connected(_on_game_state_stock_updated):
		GameState.raw_supply_stock_updated.connect(_on_game_state_stock_updated)


func interact(interaction_system: KebabInteractionSystem) -> bool:
	if not is_instance_valid(interaction_system):
		return false
	if current_stock < max_capacity and PlayerInventory.get_count(_inventory_item_id()) > 0:
		return refill_from_inventory(false) > 0
	if current_stock <= 0:
		return false
	var target_player := interaction_system.player
	if not is_instance_valid(target_player):
		return false
	if not target_player.has_method("get_held_kitchen_item_data"):
		return false
	var held_data: Variant = target_player.call("get_held_kitchen_item_data")
	if not held_data is Dictionary or not held_data.is_empty():
		return false
	if not target_player.has_method("equip_raw_vegetable"):
		return false

	var item_id := "whole_%s" % ingredient_type
	if not bool(target_player.call("equip_raw_vegetable", item_id)):
		return false

	set_stock(current_stock - 1)
	return true


func refill_from_inventory(show_failure: bool = true) -> int:
	var space := max_capacity - current_stock
	if space <= 0:
		if show_failure:
			_show_feedback("Kiste ist bereits voll", false)
		return 0
	var item_id := _inventory_item_id()
	var available := PlayerInventory.get_count(item_id)
	if available <= 0:
		if show_failure:
			_show_feedback(
				"Kein %s im Rucksack" % WholeVegetableFactory.display_name(ingredient_type),
				false
			)
		return 0
	var transfer_amount := mini(space, available)
	if not PlayerInventory.remove_item(item_id, transfer_amount):
		return 0
	set_stock(current_stock + transfer_amount)
	_show_feedback(
		"+%d %s in die Kiste" % [
			transfer_amount,
			WholeVegetableFactory.display_name(ingredient_type),
		],
		true
	)
	return transfer_amount


func set_stock(value: int, sync_game_state: bool = true) -> void:
	current_stock = clampi(value, 0, max_capacity)
	_update_stock_visuals()
	if sync_game_state:
		GameState.set_raw_supply_stock(ingredient_type, current_stock)
	stock_changed.emit(ingredient_type, current_stock)


func load_stock(value: int) -> void:
	set_stock(value, false)


func _build_stock_visuals() -> void:
	_visual_items.clear()
	for child in preview_items.get_children():
		child.free()

	for index in max_capacity:
		var vegetable := WholeVegetableFactory.create_whole(ingredient_type)
		if not is_instance_valid(vegetable):
			continue
		vegetable.name = "StockItem%d" % (index + 1)
		preview_items.add_child(vegetable)
		var angle := TAU * float(index) / float(max_capacity)
		vegetable.position = Vector3(
			cos(angle) * 0.18,
			0.02 + float(index % 2) * 0.055,
			sin(angle) * 0.12
		)
		vegetable.rotation.y = angle
		_visual_items.append(vegetable)


func _update_stock_visuals() -> void:
	for index in _visual_items.size():
		_visual_items[index].visible = index < current_stock


func _inventory_item_id() -> String:
	return "whole_%s" % ingredient_type


func _show_feedback(message: String, success: bool) -> void:
	var hud := get_tree().get_first_node_in_group("money_hud")
	if is_instance_valid(hud) and hud.has_method("show_order_feedback"):
		hud.call("show_order_feedback", message, success)


func _on_game_state_stock_updated(updated_type: String, remaining: int) -> void:
	if (
		WholeVegetableFactory.normalize_ingredient_id(updated_type) == ingredient_type
		and remaining != current_stock
	):
		load_stock(remaining)
