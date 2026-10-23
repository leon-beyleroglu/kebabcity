class_name SupermarketShelf
extends StaticBody3D

signal purchase_completed(item_id: String, inventory_count: int)

const VEGETABLE_PRICE: int = 1
const SAUCE_PRICE: int = 5

@export_enum(
	"whole_onion",
	"whole_lettuce",
	"whole_cucumber",
	"whole_tomato",
	"whole_red_cabbage",
	"sauce_bottle_cocktail",
	"sauce_bottle_garlic"
)
var item_id: String = "whole_onion"

@onready var purchase_area: Area3D = $PurchaseArea
@onready var preview_anchor: Node3D = $PreviewAnchor
@onready var item_label: Label3D = $ItemLabel
@onready var cash_register: AudioStreamPlayer3D = $CashRegister


func _ready() -> void:
	var ingredient_type := WholeVegetableFactory.normalize_ingredient_id(item_id)
	var supply_id := KitchenSupplyFactory.normalize_item_id(item_id)
	if supply_id.begins_with("sauce_bottle_"):
		item_id = supply_id
	else:
		if ingredient_type.is_empty():
			ingredient_type = "onion"
		item_id = "whole_%s" % ingredient_type

	purchase_area.collision_layer = KebabInteractionSystem.INTERACTION_LAYER
	purchase_area.collision_mask = 0
	purchase_area.set_meta("supermarket_shelf_owner", self)
	set_meta("supermarket_shelf_owner", self)
	_build_preview(ingredient_type)
	item_label.text = "%s\n%d€" % [
		_item_display_name(),
		_item_price(),
	]


func interact(_interaction_system: KebabInteractionSystem = null) -> bool:
	return purchase_item()


func purchase_item() -> bool:
	var price := _item_price()
	if GameState.money < price:
		_show_feedback("Nicht genug Geld – %d€ benötigt" % price, false)
		return false
	if not PlayerInventory.can_add(item_id, 1):
		_show_feedback("Rucksack ist voll", false)
		return false
	if not GameState.spend_money(price):
		return false

	if not PlayerInventory.add_item(item_id, 1):
		GameState.add_money(price)
		return false
	var inventory_count := PlayerInventory.get_count(item_id)
	if cash_register.stream != null:
		cash_register.play()
	_show_feedback(
		"+1 %s (-%d€)" % [
			_item_display_name(),
			price,
		],
		true
	)
	purchase_completed.emit(item_id, inventory_count)
	return true


func _build_preview(ingredient_type: String) -> void:
	for child in preview_anchor.get_children():
		child.free()
	if item_id.begins_with("sauce_bottle_"):
		for index in 3:
			var bottle := KitchenSupplyFactory.create_visual(item_id)
			if not is_instance_valid(bottle):
				continue
			preview_anchor.add_child(bottle)
			bottle.position = Vector3((float(index) - 1.0) * 0.2, 0.02, 0.0)
			bottle.rotation.y = float(index - 1) * 0.18
		return
	for index in 3:
		var vegetable := WholeVegetableFactory.create_whole(ingredient_type)
		if not is_instance_valid(vegetable):
			continue
		preview_anchor.add_child(vegetable)
		vegetable.position = Vector3(
			(float(index) - 1.0) * 0.22,
			0.04 + float(index % 2) * 0.08,
			0.0
		)
		vegetable.rotation.y = float(index) * 0.7


func _item_price() -> int:
	return SAUCE_PRICE if item_id.begins_with("sauce_bottle_") else VEGETABLE_PRICE


func _item_display_name() -> String:
	if item_id.begins_with("sauce_bottle_"):
		return KitchenSupplyFactory.display_name(item_id)
	return WholeVegetableFactory.display_name(item_id)


func _show_feedback(message: String, success: bool) -> void:
	var hud := get_tree().get_first_node_in_group("money_hud")
	if is_instance_valid(hud) and hud.has_method("show_order_feedback"):
		hud.call("show_order_feedback", message, success)
