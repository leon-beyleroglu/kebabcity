class_name TrunkInteractionArea
extends Area3D

signal trunk_inventory_changed

const TrunkUIScene := preload("res://TrunkUI.tscn")

@export_range(1, 20, 1) var max_slots: int = 20
var trunk_inventory: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("tofas_trunk")
	collision_layer = KebabInteractionSystem.INTERACTION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	set_meta("trunk_interaction_owner", self)
	_ensure_slot_count()
	load_save_data(GameState.tofas_trunk_items)


func interact(player: Node = null) -> bool:
	if not _can_open(player):
		return false
	open_trunk_ui()
	return true


func open_trunk_ui() -> void:
	var trunk_ui := get_tree().get_first_node_in_group("trunk_ui") as TrunkUI
	if not is_instance_valid(trunk_ui):
		trunk_ui = TrunkUIScene.instantiate() as TrunkUI
		get_tree().current_scene.add_child(trunk_ui)
	trunk_ui.open_for_trunk(self)


func get_item_at(slot_index: int) -> Dictionary:
	_ensure_slot_count()
	if slot_index < 0 or slot_index >= max_slots:
		return {}
	return trunk_inventory[slot_index].duplicate(true)


func can_store_item(item_id: String, target_slot: int) -> bool:
	var normalized_id := _normalize_item_id(item_id)
	if normalized_id.is_empty() or target_slot < 0 or target_slot >= max_slots:
		return false
	var target_item := get_item_at(target_slot)
	return target_item.is_empty() or String(target_item.get("id", "")) == normalized_id


func transfer_from_player(item_id: String, amount: int, target_slot: int) -> bool:
	var normalized_id := _normalize_item_id(item_id)
	if amount <= 0 or not can_store_item(normalized_id, target_slot):
		return false
	var available := PlayerInventory.get_count(normalized_id)
	var transfer_amount := mini(amount, available)
	if transfer_amount <= 0 or not PlayerInventory.remove_item(normalized_id, transfer_amount):
		return false

	var target_item := trunk_inventory[target_slot]
	if target_item.is_empty():
		trunk_inventory[target_slot] = {
			"id": normalized_id,
			"count": transfer_amount,
		}
	else:
		target_item["count"] = int(target_item.get("count", 0)) + transfer_amount
		trunk_inventory[target_slot] = target_item
	trunk_inventory_changed.emit()
	return true


func transfer_to_player(source_slot: int) -> bool:
	var item := get_item_at(source_slot)
	if item.is_empty():
		return false
	var item_id := String(item.get("id", ""))
	var count := maxi(int(item.get("count", 0)), 0)
	if item_id.is_empty() or count <= 0:
		return false
	trunk_inventory[source_slot] = {}
	PlayerInventory.add_item(item_id, count)
	trunk_inventory_changed.emit()
	return true


func move_item(source_slot: int, target_slot: int) -> bool:
	_ensure_slot_count()
	if (
		source_slot < 0
		or source_slot >= max_slots
		or target_slot < 0
		or target_slot >= max_slots
		or source_slot == target_slot
		or trunk_inventory[source_slot].is_empty()
	):
		return false
	var source_item := trunk_inventory[source_slot]
	var target_item := trunk_inventory[target_slot]
	if (
		not target_item.is_empty()
		and String(target_item.get("id", "")) == String(source_item.get("id", ""))
	):
		target_item["count"] = int(target_item.get("count", 0)) + int(source_item.get("count", 0))
		trunk_inventory[target_slot] = target_item
		trunk_inventory[source_slot] = {}
	else:
		trunk_inventory[target_slot] = source_item
		trunk_inventory[source_slot] = target_item
	trunk_inventory_changed.emit()
	return true


func get_used_slot_count() -> int:
	_ensure_slot_count()
	var used_slots := 0
	for item: Dictionary in trunk_inventory:
		if not item.is_empty():
			used_slots += 1
	return used_slots


func get_save_data() -> Array[Dictionary]:
	_ensure_slot_count()
	var saved_items: Array[Dictionary] = []
	for slot_index in max_slots:
		var item := trunk_inventory[slot_index]
		if item.is_empty():
			continue
		saved_items.append({
			"slot": slot_index,
			"id": String(item.get("id", "")),
			"count": maxi(int(item.get("count", 0)), 0),
		})
	return saved_items


func load_save_data(saved_items: Array) -> void:
	trunk_inventory.clear()
	_ensure_slot_count()
	var next_free_slot := 0
	for raw_item: Variant in saved_items:
		if not raw_item is Dictionary:
			continue
		var item_id := _normalize_item_id(String(raw_item.get("id", "")))
		var count := maxi(int(raw_item.get("count", 0)), 0)
		if item_id.is_empty() or count <= 0:
			continue
		var slot_index := int(raw_item.get("slot", -1))
		if slot_index < 0 or slot_index >= max_slots or not trunk_inventory[slot_index].is_empty():
			while next_free_slot < max_slots and not trunk_inventory[next_free_slot].is_empty():
				next_free_slot += 1
			slot_index = next_free_slot
		if slot_index >= max_slots:
			break
		trunk_inventory[slot_index] = {"id": item_id, "count": count}
	trunk_inventory_changed.emit()


func _can_open(player: Node) -> bool:
	var vehicle := get_parent()
	if is_instance_valid(vehicle) and bool(vehicle.get("is_driving")):
		return false
	if is_instance_valid(player):
		var active_vehicle: Variant = player.get("active_vehicle")
		if active_vehicle is Node and is_instance_valid(active_vehicle):
			return false
	return true


func _ensure_slot_count() -> void:
	max_slots = clampi(max_slots, 1, 20)
	if trunk_inventory.size() > max_slots:
		trunk_inventory.resize(max_slots)
	while trunk_inventory.size() < max_slots:
		trunk_inventory.append({})


func _normalize_item_id(item_id: String) -> String:
	var normalized_id := item_id.strip_edges().to_lower()
	return normalized_id if GameState.INVENTORY_ITEM_IDS.has(normalized_id) else ""
