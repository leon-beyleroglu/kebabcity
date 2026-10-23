class_name SupermarketShelf
extends StaticBody3D

signal purchase_completed(item_id: String, inventory_count: int)

const ITEM_PRICE: int = 1

@export_enum(
	"whole_onion",
	"whole_lettuce",
	"whole_cucumber",
	"whole_tomato",
	"whole_red_cabbage"
)
var item_id: String = "whole_onion"

@onready var purchase_area: Area3D = $PurchaseArea
@onready var preview_anchor: Node3D = $PreviewAnchor
@onready var item_label: Label3D = $ItemLabel
@onready var cash_register: AudioStreamPlayer3D = $CashRegister


func _ready() -> void:
	var ingredient_type := WholeVegetableFactory.normalize_ingredient_id(item_id)
	if ingredient_type.is_empty():
		ingredient_type = "onion"
	item_id = "whole_%s" % ingredient_type

	purchase_area.collision_layer = KebabInteractionSystem.INTERACTION_LAYER
	purchase_area.collision_mask = 0
	purchase_area.set_meta("supermarket_shelf_owner", self)
	set_meta("supermarket_shelf_owner", self)
	_build_preview(ingredient_type)
	item_label.text = "%s\n%d€" % [
		WholeVegetableFactory.display_name(ingredient_type),
		ITEM_PRICE,
	]


func interact(_interaction_system: KebabInteractionSystem = null) -> bool:
	return purchase_item()


func purchase_item() -> bool:
	if GameState.money < ITEM_PRICE:
		_show_feedback("Nicht genug Geld – %d€ benötigt" % ITEM_PRICE, false)
		return false
	if not GameState.spend_money(ITEM_PRICE):
		return false

	PlayerInventory.add_item(item_id, 1)
	var inventory_count := PlayerInventory.get_count(item_id)
	if cash_register.stream != null:
		cash_register.play()
	_show_feedback(
		"+1 %s (-%d€)" % [
			WholeVegetableFactory.display_name(item_id),
			ITEM_PRICE,
		],
		true
	)
	purchase_completed.emit(item_id, inventory_count)
	return true


func _build_preview(ingredient_type: String) -> void:
	for child in preview_anchor.get_children():
		child.free()
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


func _show_feedback(message: String, success: bool) -> void:
	var hud := get_tree().get_first_node_in_group("money_hud")
	if is_instance_valid(hud) and hud.has_method("show_order_feedback"):
		hud.call("show_order_feedback", message, success)
