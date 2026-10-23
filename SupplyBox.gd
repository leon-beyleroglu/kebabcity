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
	if current_stock <= 0 or not is_instance_valid(interaction_system):
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


func _on_game_state_stock_updated(updated_type: String, remaining: int) -> void:
	if (
		WholeVegetableFactory.normalize_ingredient_id(updated_type) == ingredient_type
		and remaining != current_stock
	):
		load_stock(remaining)
