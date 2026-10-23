@tool
class_name ButcherOwner
extends RestaurantOwner

signal raw_spit_purchased

const RAW_SPIT_ITEM_ID := "raw_spit"
const RAW_SPIT_PRICE := 50


func interact(_interaction_system: Node = null) -> bool:
	interaction_requested.emit(self)
	if GameState.money < RAW_SPIT_PRICE:
		_show_trade_feedback("Nicht genug Geld – der rohe Spieß kostet 50€", false)
		return true
	if not PlayerInventory.can_add(RAW_SPIT_ITEM_ID, 1):
		_show_trade_feedback("Kein freier Inventarplatz für den Dönerspieß", false)
		return true
	if not GameState.spend_money(RAW_SPIT_PRICE):
		return true
	if not PlayerInventory.add_item(RAW_SPIT_ITEM_ID, 1):
		GameState.add_money(RAW_SPIT_PRICE)
		return true
	raw_spit_purchased.emit()
	_show_trade_feedback("+1 roher Dönerspieß (-50€)", true)
	return true


func _show_trade_feedback(message: String, success: bool) -> void:
	var hud := get_tree().get_first_node_in_group("money_hud")
	if is_instance_valid(hud) and hud.has_method("show_order_feedback"):
		hud.call("show_order_feedback", message, success)
