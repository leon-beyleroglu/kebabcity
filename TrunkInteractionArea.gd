class_name TrunkInteractionArea
extends Area3D

signal trunk_inventory_changed

const TrunkUIScene := preload("res://TrunkUI.tscn")

@export_range(20, 20, 1) var max_slots: int = GameState.TRUNK_MAX_SLOTS
var trunk_inventory: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("tofas_trunk")
	collision_layer = KebabInteractionSystem.INTERACTION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	set_meta("trunk_interaction_owner", self)
	if not GameState.inventory_slots_changed.is_connected(_on_inventory_slots_changed):
		GameState.inventory_slots_changed.connect(_on_inventory_slots_changed)
	_sync_from_game_state()


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
	return GameState.get_inventory_slot("trunk", slot_index)


func can_store_item(item_id: String, target_slot: int) -> bool:
	return (
		target_slot >= 0
		and target_slot < GameState.TRUNK_MAX_SLOTS
		and (
			GameState.INVENTORY_ITEM_IDS.has(item_id)
			or GameState.WEAPON_ITEM_IDS.has(item_id)
		)
	)


func transfer_from_player(item_id: String, _amount: int, target_slot: int) -> bool:
	for source_slot in GameState.PLAYER_MAX_SLOTS:
		if String(GameState.player_slots[source_slot].get("id", "")) == item_id:
			return GameState.move_inventory_slot("player", source_slot, "trunk", target_slot)
	return false


func transfer_to_player(source_slot: int) -> bool:
	var target_slot := _find_player_target(get_item_at(source_slot))
	if target_slot < 0:
		return false
	return GameState.move_inventory_slot("trunk", source_slot, "player", target_slot)


func move_item(source_slot: int, target_slot: int) -> bool:
	return GameState.move_inventory_slot("trunk", source_slot, "trunk", target_slot)


func get_used_slot_count() -> int:
	var used_slots := 0
	for slot_item: Dictionary in GameState.trunk_slots:
		if not slot_item.is_empty():
			used_slots += 1
	return used_slots


func get_save_data() -> Array[Dictionary]:
	return GameState.trunk_slots.duplicate(true)


func load_save_data(saved_items: Array) -> void:
	var restored_items := saved_items.duplicate(true)
	GameState.trunk_slots.clear()
	for slot_index in GameState.TRUNK_MAX_SLOTS:
		var raw_item: Variant = restored_items[slot_index] if slot_index < restored_items.size() else {}
		GameState.trunk_slots.append(raw_item.duplicate(true) if raw_item is Dictionary else {})
	GameState.sync_weapon_ownership()
	_sync_from_game_state()


func _find_player_target(item: Dictionary) -> int:
	if item.is_empty():
		return -1
	if String(item.get("type", "")) == "ingredient":
		for slot_index in GameState.PLAYER_MAX_SLOTS:
			if (
				String(GameState.player_slots[slot_index].get("id", ""))
				== String(item.get("id", ""))
			):
				return slot_index
	for slot_index in GameState.PLAYER_MAX_SLOTS:
		if GameState.player_slots[slot_index].is_empty():
			return slot_index
	return -1


func _sync_from_game_state() -> void:
	trunk_inventory.clear()
	for slot_item: Dictionary in GameState.trunk_slots:
		trunk_inventory.append(slot_item.duplicate(true))
	trunk_inventory_changed.emit()


func _on_inventory_slots_changed() -> void:
	_sync_from_game_state()


func _can_open(player: Node) -> bool:
	var vehicle := get_parent()
	if is_instance_valid(vehicle) and bool(vehicle.get("is_driving")):
		return false
	if is_instance_valid(player):
		var active_vehicle: Variant = player.get("active_vehicle")
		if active_vehicle is Node and is_instance_valid(active_vehicle):
			return false
	return true
