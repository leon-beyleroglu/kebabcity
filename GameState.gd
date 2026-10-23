extends Node

const SAVE_PATH: String = "user://savegame.json"

signal money_changed(new_amount: int)
signal health_changed(current: float, max_val: float)
signal armour_changed(current: float, max_val: float)
signal day_changed(new_day: int)
signal stock_updated(item: String, remaining: int)
signal counter_stock_updated(ingredient_name: String, remaining: int)
signal raw_supply_stock_updated(ingredient_type: String, remaining: int)
signal inventory_item_changed(item_id: String, count: int)
signal inventory_slots_changed

const PLAYER_MAX_SLOTS: int = 10
const TRUNK_MAX_SLOTS: int = 20
const WEAPON_ITEM_IDS: Array[String] = ["knife", "glock", "ak47", "awp"]

const COUNTER_MAX_STOCK := 10
const COUNTER_INGREDIENTS: Array[String] = [
	"onion",
	"cucumber",
	"lettuce",
	"tomato",
	"red_cabbage",
]
const RAW_SUPPLY_MAX_STOCK := 5
const RAW_SUPPLY_INGREDIENTS: Array[String] = [
	"onion",
	"cucumber",
	"lettuce",
	"tomato",
	"red_cabbage",
]
const INVENTORY_ITEM_IDS: Array[String] = [
	"whole_onion",
	"whole_lettuce",
	"whole_cucumber",
	"whole_tomato",
	"whole_red_cabbage",
]

var money: int = 0
var day: int = 1
var reputation: int = 50
var shop_level: int = 1
var player_health: float = 100.0
var max_health: float = 100.0
var armour: float = 0.0
var max_armour: float = 100.0
var owned_weapons: Array[String] = ["unarmed"]
var ammo: Dictionary = {"AK47": 90, "Glock": 34, "AWP": 10}
var ingredient_stock: Dictionary = {
	"meat": 50,
	"bread": 50,
	"sauce": 50,
	"salad": 10,
	"lettuce": 10,
	"onion": 10,
	"cucumber": 10,
	"tomato": 10,
	"red_cabbage": 10,
}
var counter_stocks: Dictionary = {
	"onion": 10,
	"cucumber": 10,
	"lettuce": 10,
	"tomato": 10,
	"red_cabbage": 10,
}
var raw_supply_stocks: Dictionary = {
	"onion": 5,
	"cucumber": 5,
	"lettuce": 5,
	"tomato": 5,
	"red_cabbage": 5,
}
var inventory_items: Dictionary = {
	"whole_onion": 0,
	"whole_lettuce": 0,
	"whole_cucumber": 0,
	"whole_tomato": 0,
	"whole_red_cabbage": 0,
}
var player_slots: Array[Dictionary] = []
var trunk_slots: Array[Dictionary] = []
var unlocked_upgrades: Array[String] = []
var rival_reputation: int = 20
var player_position: Vector3 = Vector3.ZERO
var player_rotation_y: float = 0.0
var counter_items: Array[Dictionary] = []
var prep_counter_items: Array[String] = []
var meat_tray_portions: int = 0
var lavash_meat_count: int = 0
var oven_data: Dictionary = {"item_type": "", "timer_progress": 0.0, "is_baked": false}
var table_stored_weapons: Array[String] = []
var cutting_station_data: Dictionary = {"item_on_board": "", "chop_progress": 0, "is_chopped": false}
var placed_world_items: Array[Dictionary] = []
var held_kitchen_item: Dictionary = {}
var tofas_trunk_items: Array[Dictionary] = []
var placed_lavash: Dictionary = {
	"is_present": false,
	"is_baked": false,
	"is_rolled": false,
	"toppings": [],
}
var placed_lavash_state: Dictionary = {
	"is_present": false,
	"is_baked": false,
	"is_rolled": false,
	"toppings": [],
}

var _restore_player_transform := false
var _restore_counter_inventory := false
var _restore_prep_counter := false
var _restore_meat_tray := false
var _restore_oven := false
var _restore_weapon_table := false
var _restore_cutting_station := false
var _restore_placed_world_items := false
var _restore_held_kitchen_item := false
var _restore_raw_supply_stocks := false
var _restore_tofas_trunk := false


func _ready() -> void:
	_ensure_fixed_slot_arrays()
	if not load_game():
		_seed_default_player_slots()
		_sync_slot_state(true)


func save_game() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if is_instance_valid(player):
		player_position = player.global_position
		player_rotation_y = player.rotation.y
	counter_items = _collect_counter_items(player)
	placed_lavash_state = _collect_placed_lavash(counter_items)
	placed_lavash = placed_lavash_state.duplicate(true)
	lavash_meat_count = _count_lavash_meat(placed_lavash_state)
	_collect_station_data()
	_collect_weapon_table_data()
	_collect_kitchen_item_data(player)
	_collect_raw_supply_stocks()
	_collect_tofas_trunk_items()
	_sync_slot_state(false)

	var save_data: Dictionary = {
		"money": money,
		"day": day,
		"reputation": reputation,
		"shop_level": shop_level,
		"player_health": player_health,
		"armour": armour,
		"owned_weapons": owned_weapons,
		"ammo": ammo,
		"ingredient_stock": ingredient_stock,
		"counter_stocks": counter_stocks,
		"raw_supply_stocks": raw_supply_stocks,
		"inventory_items": inventory_items,
		"player_slots": player_slots,
		"trunk_slots": trunk_slots,
		"unlocked_upgrades": unlocked_upgrades,
		"rival_reputation": rival_reputation,
		"player_pos": {
			"x": player_position.x,
			"y": player_position.y,
			"z": player_position.z,
		},
		"player_rot_y": player_rotation_y,
		"counter_items": counter_items,
		"placed_lavash": placed_lavash,
		"placed_lavash_state": placed_lavash_state,
		"prep_counter_items": prep_counter_items,
		"meat_tray_portions": meat_tray_portions,
		"lavash_meat_count": lavash_meat_count,
		"oven_data": oven_data,
		"table_stored_weapons": table_stored_weapons,
		"cutting_station": cutting_station_data,
		"placed_world_items": placed_world_items,
		"held_kitchen_item": held_kitchen_item,
		"tofas_trunk_items": tofas_trunk_items,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open save file for writing: %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(save_data))
	file.close()


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open save file for reading: %s" % SAVE_PATH)
		return false
	var json_text := file.get_as_text()
	file.close()

	var parsed_data: Variant = JSON.parse_string(json_text)
	if not parsed_data is Dictionary:
		push_error("Save file does not contain a valid JSON object: %s" % SAVE_PATH)
		return false
	var save_data: Dictionary = parsed_data

	money = int(save_data.get("money", money))
	day = int(save_data.get("day", day))
	reputation = int(save_data.get("reputation", reputation))
	shop_level = int(save_data.get("shop_level", shop_level))
	player_health = clampf(float(save_data.get("player_health", player_health)), 0.0, max_health)
	armour = clampf(float(save_data.get("armour", armour)), 0.0, max_armour)
	rival_reputation = int(save_data.get("rival_reputation", rival_reputation))

	var loaded_weapons: Variant = save_data.get("owned_weapons", owned_weapons)
	if loaded_weapons is Array:
		owned_weapons.assign(loaded_weapons)

	_restore_weapon_table = save_data.has("table_stored_weapons")
	if _restore_weapon_table:
		var loaded_table_weapons: Variant = save_data["table_stored_weapons"]
		if loaded_table_weapons is Array:
			table_stored_weapons.clear()
			for raw_weapon: Variant in loaded_table_weapons:
				var weapon_id := _normalize_weapon_id(String(raw_weapon))
				if not weapon_id.is_empty() and not table_stored_weapons.has(weapon_id):
					table_stored_weapons.append(weapon_id)
			for weapon_id: String in table_stored_weapons:
				_remove_owned_weapon(weapon_id)
		else:
			_restore_weapon_table = false
	var loaded_ammo: Variant = save_data.get("ammo", ammo)
	if loaded_ammo is Dictionary:
		var restored_ammo: Dictionary = {}
		for weapon: Variant in loaded_ammo:
			restored_ammo[String(weapon)] = int(loaded_ammo[weapon])
		ammo = restored_ammo
	var loaded_stock: Variant = save_data.get("ingredient_stock", ingredient_stock)
	if loaded_stock is Dictionary:
		var restored_stock: Dictionary = ingredient_stock.duplicate(true)
		for item: Variant in loaded_stock:
			restored_stock[String(item)] = int(loaded_stock[item])
		ingredient_stock = restored_stock
	var loaded_counter_stocks: Variant = save_data.get("counter_stocks", {})
	if loaded_counter_stocks is Dictionary and not loaded_counter_stocks.is_empty():
		for ingredient_name: String in COUNTER_INGREDIENTS:
			counter_stocks[ingredient_name] = clampi(
				int(loaded_counter_stocks.get(ingredient_name, COUNTER_MAX_STOCK)),
				0,
				COUNTER_MAX_STOCK
			)
	else:
		# Migrate old saves which stored Gastronorm stock only in ingredient_stock.
		for ingredient_name: String in COUNTER_INGREDIENTS:
			var legacy_key := _ingredient_stock_key(ingredient_name)
			counter_stocks[ingredient_name] = clampi(
				int(ingredient_stock.get(legacy_key, COUNTER_MAX_STOCK)),
				0,
				COUNTER_MAX_STOCK
			)
	_sync_counter_stock_aliases()
	_restore_raw_supply_stocks = true
	var loaded_raw_supply: Variant = save_data.get("raw_supply_stocks", {})
	if not loaded_raw_supply is Dictionary:
		loaded_raw_supply = {}
	for ingredient_name: String in RAW_SUPPLY_INGREDIENTS:
		raw_supply_stocks[ingredient_name] = clampi(
			int(loaded_raw_supply.get(ingredient_name, RAW_SUPPLY_MAX_STOCK)),
			0,
			RAW_SUPPLY_MAX_STOCK
		)
	_restore_inventory_slots(save_data)
	_restore_tofas_trunk = true
	var loaded_upgrades: Variant = save_data.get("unlocked_upgrades", unlocked_upgrades)
	if loaded_upgrades is Array:
		unlocked_upgrades.assign(loaded_upgrades)

	_restore_player_transform = save_data.has("player_pos")
	if _restore_player_transform:
		var saved_position: Variant = save_data["player_pos"]
		if saved_position is Dictionary:
			player_position = Vector3(
				float(saved_position.get("x", 0.0)),
				float(saved_position.get("y", 0.0)),
				float(saved_position.get("z", 0.0))
			)
			player_rotation_y = float(save_data.get("player_rot_y", player_rotation_y))
		else:
			_restore_player_transform = false

	_restore_counter_inventory = save_data.has("counter_items")
	if _restore_counter_inventory:
		var loaded_counter_items: Variant = save_data["counter_items"]
		if loaded_counter_items is Array:
			counter_items.clear()
			for index in loaded_counter_items.size():
				var loaded_item: Variant = loaded_counter_items[index]
				if loaded_item is Dictionary:
					counter_items.append(loaded_item)
				elif loaded_item is String:
					var legacy_type := String(loaded_item)
					counter_items.append({
						"type": legacy_type,
						"is_baked": legacy_type == "baked_lavash",
						"slot_index": index,
					})
		else:
			_restore_counter_inventory = false
	var loaded_placed_lavash: Variant = save_data.get(
		"placed_lavash_state",
		save_data.get("placed_lavash", {})
	)
	if loaded_placed_lavash is Dictionary and not loaded_placed_lavash.is_empty():
		placed_lavash_state = _normalize_placed_lavash(loaded_placed_lavash)
	else:
		placed_lavash_state = _collect_placed_lavash(counter_items)
	placed_lavash = placed_lavash_state.duplicate(true)
	var toppings_meat_count := _count_lavash_meat(placed_lavash_state)
	lavash_meat_count = (
		maxi(int(save_data.get("lavash_meat_count", toppings_meat_count)), 0)
		if bool(placed_lavash_state.get("is_present", false))
		else 0
	)
	if lavash_meat_count > toppings_meat_count:
		_append_missing_lavash_meat(lavash_meat_count - toppings_meat_count)
	if bool(placed_lavash_state.get("is_present", false)) and not _counter_items_have_lavash(counter_items):
		counter_items.append({
			"type": "durum_assembly" if not (placed_lavash_state.get("toppings", []) as Array).is_empty() else "baked_lavash",
			"is_baked": bool(placed_lavash_state.get("is_baked", true)),
			"is_rolled": bool(placed_lavash_state.get("is_rolled", false)),
			"ingredients": (placed_lavash_state.get("toppings", []) as Array).duplicate(),
			"slot_index": counter_items.size(),
		})
		_restore_counter_inventory = true

	_restore_prep_counter = save_data.has("prep_counter_items")
	if _restore_prep_counter:
		var loaded_prep_items: Variant = save_data["prep_counter_items"]
		if loaded_prep_items is Array:
			prep_counter_items.assign(loaded_prep_items)
		else:
			_restore_prep_counter = false

	_restore_meat_tray = save_data.has("meat_tray_portions")
	if _restore_meat_tray:
		meat_tray_portions = clampi(int(save_data["meat_tray_portions"]), 0, 3)

	_restore_oven = save_data.has("oven_data")
	if _restore_oven:
		var loaded_oven_data: Variant = save_data["oven_data"]
		if loaded_oven_data is Dictionary:
			oven_data = loaded_oven_data
		else:
			_restore_oven = false

	_restore_cutting_station = save_data.has("cutting_station")
	if _restore_cutting_station:
		var loaded_cutting_data: Variant = save_data["cutting_station"]
		if loaded_cutting_data is Dictionary:
			cutting_station_data = loaded_cutting_data.duplicate(true)
		else:
			_restore_cutting_station = false

	_restore_placed_world_items = save_data.has("placed_world_items")
	if _restore_placed_world_items:
		placed_world_items.clear()
		var loaded_world_items: Variant = save_data["placed_world_items"]
		if loaded_world_items is Array:
			for raw_item: Variant in loaded_world_items:
				if not raw_item is Dictionary:
					continue
				var normalized := PickupableItem.normalize_item_data(raw_item)
				if normalized.is_empty():
					continue
				normalized["pos"] = raw_item.get("pos", {})
				normalized["rot"] = raw_item.get("rot", {})
				placed_world_items.append(normalized)
		else:
			_restore_placed_world_items = false

	_restore_held_kitchen_item = save_data.has("held_kitchen_item")
	if _restore_held_kitchen_item:
		var loaded_held_item: Variant = save_data["held_kitchen_item"]
		if loaded_held_item is Dictionary and not loaded_held_item.is_empty():
			held_kitchen_item = PickupableItem.normalize_item_data(loaded_held_item)
			if held_kitchen_item.is_empty():
				_restore_held_kitchen_item = false
		else:
			held_kitchen_item = {}
			_restore_held_kitchen_item = false

	money_changed.emit(money)
	day_changed.emit(day)
	health_changed.emit(player_health, max_health)
	armour_changed.emit(armour, max_armour)
	for item: String in ingredient_stock:
		stock_updated.emit(item, int(ingredient_stock[item]))
	for ingredient_name: String in COUNTER_INGREDIENTS:
		counter_stock_updated.emit(ingredient_name, int(counter_stocks[ingredient_name]))
	for ingredient_name: String in RAW_SUPPLY_INGREDIENTS:
		raw_supply_stock_updated.emit(ingredient_name, int(raw_supply_stocks[ingredient_name]))
	for item_id: String in INVENTORY_ITEM_IDS:
		inventory_item_changed.emit(item_id, int(inventory_items[item_id]))
	inventory_slots_changed.emit()
	_notify_player_weapon_state()

	if get_tree().current_scene == null:
		call_deferred("_restore_scene_state")
	else:
		_restore_scene_state()
	return true


func _collect_counter_items(_player: Node3D) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var counter := get_tree().get_first_node_in_group("assembly_counter")
	if not is_instance_valid(counter) or not counter.has_method("get_save_data"):
		return items
	var counter_data: Variant = counter.call("get_save_data")
	if not counter_data is Dictionary:
		return items
	var saved_items: Variant = counter_data.get("items", [])
	if saved_items is Array:
		for saved_item: Variant in saved_items:
			if saved_item is Dictionary:
				items.append(saved_item)
	return items


func _collect_placed_lavash(items: Array[Dictionary]) -> Dictionary:
	for entry: Dictionary in items:
		var item_type := String(entry.get("type", ""))
		if item_type != "baked_lavash" and item_type != "durum_assembly":
			continue
		var raw_toppings: Variant = entry.get("ingredients", [])
		var toppings: Array[String] = []
		if raw_toppings is Array:
			for raw_topping: Variant in raw_toppings:
				toppings.append(String(raw_topping))
		return {
			"is_present": true,
			"is_baked": bool(entry.get("is_baked", true)),
			"is_rolled": bool(entry.get("is_rolled", false)),
			"toppings": toppings,
		}
	return {"is_present": false, "is_baked": false, "is_rolled": false, "toppings": []}


func _collect_station_data() -> void:
	var prep_counter := get_tree().get_first_node_in_group("prep_counter")
	if is_instance_valid(prep_counter) and prep_counter.has_method("get_save_data"):
		var prep_data: Variant = prep_counter.call("get_save_data")
		if prep_data is Dictionary:
			var saved_items: Variant = prep_data.get("items", [])
			if saved_items is Array:
				prep_counter_items.assign(saved_items)

	var meat_tray := get_tree().get_first_node_in_group("meat_tray")
	if is_instance_valid(meat_tray) and meat_tray.has_method("get_save_data"):
		var tray_data: Variant = meat_tray.call("get_save_data")
		if tray_data is Dictionary:
			meat_tray_portions = clampi(int(tray_data.get("portions", 0)), 0, 3)

	var oven := get_tree().get_first_node_in_group("oven")
	if is_instance_valid(oven) and oven.has_method("get_save_data"):
		var saved_oven: Variant = oven.call("get_save_data")
		if saved_oven is Dictionary:
			oven_data = saved_oven

	var cutting_station := get_tree().get_first_node_in_group("cutting_station")
	if is_instance_valid(cutting_station) and cutting_station.has_method("get_save_data"):
		var saved_cutting_station: Variant = cutting_station.call("get_save_data")
		if saved_cutting_station is Dictionary:
			cutting_station_data = saved_cutting_station.duplicate(true)


func _collect_weapon_table_data() -> void:
	var weapon_table := get_tree().get_first_node_in_group("weapon_table")
	if not is_instance_valid(weapon_table) or not weapon_table.has_method("get_save_data"):
		return
	var table_data: Variant = weapon_table.call("get_save_data")
	if not table_data is Dictionary:
		return
	var saved_weapons: Variant = table_data.get("weapons", [])
	if saved_weapons is Array:
		table_stored_weapons.clear()
		for raw_weapon: Variant in saved_weapons:
			var weapon_id := _normalize_weapon_id(String(raw_weapon))
			if not weapon_id.is_empty() and not table_stored_weapons.has(weapon_id):
				table_stored_weapons.append(weapon_id)


func _collect_kitchen_item_data(player: Node3D) -> void:
	placed_world_items.clear()
	for item_node in get_tree().get_nodes_in_group("pickupable_item"):
		var item := item_node as PickupableItem
		if not is_instance_valid(item):
			continue
		var saved_item := item.get_save_data()
		if not saved_item.is_empty():
			placed_world_items.append(saved_item)
	held_kitchen_item = {}
	if is_instance_valid(player) and player.has_method("get_held_kitchen_item_data"):
		var player_item: Variant = player.call("get_held_kitchen_item_data")
		if player_item is Dictionary:
			held_kitchen_item = PickupableItem.normalize_item_data(player_item)


func _collect_raw_supply_stocks() -> void:
	for supply_node in get_tree().get_nodes_in_group("raw_supply_box"):
		var supply_box := supply_node as SupplyBox
		if not is_instance_valid(supply_box):
			continue
		var normalized_type := _normalize_raw_supply_ingredient(supply_box.ingredient_type)
		if normalized_type.is_empty():
			continue
		raw_supply_stocks[normalized_type] = clampi(
			supply_box.current_stock,
			0,
			RAW_SUPPLY_MAX_STOCK
		)


func _collect_tofas_trunk_items() -> void:
	_ensure_fixed_slot_arrays()
	tofas_trunk_items.clear()
	for slot_index in TRUNK_MAX_SLOTS:
		var item := trunk_slots[slot_index]
		if item.is_empty():
			continue
		var saved_item := item.duplicate(true)
		saved_item["slot"] = slot_index
		tofas_trunk_items.append(saved_item)


func _restore_scene_state(attempt: int = 0) -> void:
	var needs_retry := false
	var player := get_tree().get_first_node_in_group("player") as Node3D

	if _restore_player_transform:
		if is_instance_valid(player):
			player.global_position = player_position
			player.rotation.y = player_rotation_y
			_restore_player_transform = false
		else:
			needs_retry = true

	if _restore_counter_inventory:
		var assembly_counter := get_tree().get_first_node_in_group("assembly_counter")
		if (
			is_instance_valid(assembly_counter)
			and assembly_counter.has_method("load_save_data")
			and bool(assembly_counter.call("load_save_data", {"items": counter_items}))
		):
			_restore_counter_inventory = false
		else:
			needs_retry = true

	if _restore_prep_counter:
		var prep_counter := get_tree().get_first_node_in_group("prep_counter")
		if (
			is_instance_valid(prep_counter)
			and prep_counter.has_method("load_save_data")
			and bool(prep_counter.call("load_save_data", {"items": prep_counter_items}))
		):
			_restore_prep_counter = false
		else:
			needs_retry = true

	if _restore_meat_tray:
		var meat_tray := get_tree().get_first_node_in_group("meat_tray")
		if (
			is_instance_valid(meat_tray)
			and meat_tray.has_method("load_save_data")
			and bool(meat_tray.call("load_save_data", {"portions": meat_tray_portions}))
		):
			_restore_meat_tray = false
		else:
			needs_retry = true

	if _restore_oven:
		var oven := get_tree().get_first_node_in_group("oven")
		if (
			is_instance_valid(oven)
			and oven.has_method("load_save_data")
			and bool(oven.call("load_save_data", oven_data))
		):
			_restore_oven = false
		else:
			needs_retry = true

	if _restore_weapon_table:
		var weapon_table := get_tree().get_first_node_in_group("weapon_table")
		if (
			is_instance_valid(weapon_table)
			and weapon_table.has_method("load_save_data")
			and bool(weapon_table.call("load_save_data", {"weapons": table_stored_weapons}))
		):
			_restore_weapon_table = false
		else:
			needs_retry = true

	if _restore_cutting_station:
		var cutting_station := get_tree().get_first_node_in_group("cutting_station")
		if (
			is_instance_valid(cutting_station)
			and cutting_station.has_method("load_save_data")
			and bool(cutting_station.call("load_save_data", cutting_station_data))
		):
			_restore_cutting_station = false
		else:
			needs_retry = true

	if _restore_raw_supply_stocks:
		var supply_boxes := get_tree().get_nodes_in_group("raw_supply_box")
		if supply_boxes.is_empty():
			needs_retry = true
		else:
			for supply_node in supply_boxes:
				var supply_box := supply_node as SupplyBox
				if not is_instance_valid(supply_box):
					continue
				supply_box.load_stock(get_raw_supply_stock(supply_box.ingredient_type))
			_restore_raw_supply_stocks = false

	if _restore_tofas_trunk:
		var trunk := get_tree().get_first_node_in_group("tofas_trunk")
		if is_instance_valid(trunk) and trunk.has_method("load_save_data"):
			trunk.call("load_save_data", trunk_slots)
			_restore_tofas_trunk = false
		else:
			needs_retry = true

	if _restore_placed_world_items:
		var scene := get_tree().current_scene
		if is_instance_valid(scene):
			for existing_node in get_tree().get_nodes_in_group("pickupable_item"):
				var existing := existing_node as Node
				if is_instance_valid(existing):
					existing.free()
			for saved_item: Dictionary in placed_world_items:
				PickupableItem.spawn(
					scene,
					saved_item,
					PickupableItem.vector_from_data(saved_item.get("pos", {})),
					PickupableItem.vector_from_data(saved_item.get("rot", {}))
				)
			_restore_placed_world_items = false
		else:
			needs_retry = true

	if _restore_held_kitchen_item:
		if (
			is_instance_valid(player)
			and player.has_method("restore_held_kitchen_item")
			and bool(player.call("restore_held_kitchen_item", held_kitchen_item))
		):
			_restore_held_kitchen_item = false
		else:
			needs_retry = true

	if needs_retry and attempt < 16:
		call_deferred("_restore_scene_state", attempt + 1)


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


func spend_money(amount: int) -> bool:
	if amount < 0 or amount > money:
		return false
	money -= amount
	money_changed.emit(money)
	return true


func take_damage(amount: float) -> void:
	var remaining_damage := maxf(amount, 0.0)
	if remaining_damage == 0.0:
		return

	if armour > 0.0:
		var absorbed := minf(armour, remaining_damage)
		armour -= absorbed
		remaining_damage -= absorbed
		armour_changed.emit(armour, max_armour)

	if remaining_damage > 0.0:
		player_health = maxf(player_health - remaining_damage, 0.0)
		health_changed.emit(player_health, max_health)


func consume_ingredient(item: String, count: int = 1) -> bool:
	var counter_ingredient := _normalize_counter_ingredient(item)
	if not counter_ingredient.is_empty():
		return consume_counter_ingredient(counter_ingredient, count)
	if count <= 0 or not ingredient_stock.has(item):
		return false
	var remaining := int(ingredient_stock[item])
	if count > remaining:
		return false
	remaining -= count
	ingredient_stock[item] = remaining
	stock_updated.emit(item, remaining)
	return true


func add_ingredient_stock(item: String, count: int) -> int:
	var counter_ingredient := _normalize_counter_ingredient(item)
	if item.is_empty() or count <= 0:
		return (
			get_counter_stock(counter_ingredient)
			if not counter_ingredient.is_empty()
			else int(ingredient_stock.get(item, 0))
		)
	if not counter_ingredient.is_empty():
		return set_counter_stock(
			counter_ingredient,
			get_counter_stock(counter_ingredient) + count
		)
	var remaining := int(ingredient_stock.get(item, 0)) + count
	ingredient_stock[item] = remaining
	stock_updated.emit(item, remaining)
	return remaining


func get_counter_stock(item: String) -> int:
	var ingredient_name := _normalize_counter_ingredient(item)
	if ingredient_name.is_empty():
		return 0
	return int(counter_stocks.get(ingredient_name, COUNTER_MAX_STOCK))


func get_raw_supply_stock(item: String) -> int:
	var ingredient_name := _normalize_raw_supply_ingredient(item)
	if ingredient_name.is_empty():
		return 0
	return int(raw_supply_stocks.get(ingredient_name, RAW_SUPPLY_MAX_STOCK))


func set_raw_supply_stock(item: String, value: int) -> int:
	var ingredient_name := _normalize_raw_supply_ingredient(item)
	if ingredient_name.is_empty():
		return 0
	var remaining := clampi(value, 0, RAW_SUPPLY_MAX_STOCK)
	raw_supply_stocks[ingredient_name] = remaining
	raw_supply_stock_updated.emit(ingredient_name, remaining)
	return remaining


func add_inventory_item(item_id: String, amount: int = 1) -> bool:
	var item := _slot_item_for_id(item_id, amount)
	if item.is_empty() or not _add_to_slot_array(player_slots, PLAYER_MAX_SLOTS, item):
		return false
	_sync_slot_state(true)
	return true


func remove_inventory_item(item_id: String, amount: int = 1) -> bool:
	var normalized_id := _normalize_slot_item_id(item_id)
	if normalized_id.is_empty() or amount <= 0 or get_inventory_count(normalized_id) < amount:
		return false
	var remaining := amount
	for slot_index in PLAYER_MAX_SLOTS:
		var slot_item := player_slots[slot_index]
		if String(slot_item.get("id", "")) != normalized_id:
			continue
		var slot_count := int(slot_item.get("count", 0))
		var removed := mini(slot_count, remaining)
		slot_count -= removed
		remaining -= removed
		player_slots[slot_index] = (
			{}
			if slot_count <= 0
			else _slot_item_for_id(normalized_id, slot_count)
		)
		if remaining <= 0:
			break
	_sync_slot_state(true)
	return true


func get_inventory_count(item_id: String) -> int:
	var normalized_id := _normalize_slot_item_id(item_id)
	if normalized_id.is_empty():
		return 0
	var total := 0
	for slot_item: Dictionary in player_slots:
		if String(slot_item.get("id", "")) == normalized_id:
			total += maxi(int(slot_item.get("count", 0)), 0)
	return total


func can_add_player_item(item_id: String, amount: int = 1) -> bool:
	var item := _slot_item_for_id(item_id, amount)
	if item.is_empty():
		return false
	if String(item.get("type", "")) == "ingredient":
		for slot_item: Dictionary in player_slots:
			if String(slot_item.get("id", "")) == String(item["id"]):
				return true
	else:
		if _slot_array_has_item(player_slots, String(item["id"])):
			return false
	return _find_empty_slot(player_slots, PLAYER_MAX_SLOTS) >= 0


func get_inventory_slot(container_name: String, slot_index: int) -> Dictionary:
	var slots := _slots_for_container(container_name)
	var max_slots := _max_slots_for_container(container_name)
	if slot_index < 0 or slot_index >= max_slots:
		return {}
	return slots[slot_index].duplicate(true)


func move_inventory_slot(
	from_container: String,
	from_index: int,
	to_container: String,
	to_index: int
) -> bool:
	var source_slots := _slots_for_container(from_container)
	var target_slots := _slots_for_container(to_container)
	var source_max := _max_slots_for_container(from_container)
	var target_max := _max_slots_for_container(to_container)
	if (
		source_max == 0
		or target_max == 0
		or from_index < 0
		or from_index >= source_max
		or to_index < 0
		or to_index >= target_max
		or (from_container == to_container and from_index == to_index)
	):
		return false
	var source_item := source_slots[from_index].duplicate(true)
	if source_item.is_empty():
		return false
	var target_item := target_slots[to_index].duplicate(true)
	if (
		not target_item.is_empty()
		and String(source_item.get("type", "")) == "ingredient"
		and String(target_item.get("type", "")) == "ingredient"
		and String(source_item.get("id", "")) == String(target_item.get("id", ""))
	):
		target_item["count"] = int(target_item.get("count", 0)) + int(source_item.get("count", 0))
		target_slots[to_index] = target_item
		source_slots[from_index] = {}
	else:
		target_slots[to_index] = source_item
		source_slots[from_index] = target_item
	_sync_slot_state(true)
	return true


func player_has_weapon(weapon_id: String) -> bool:
	var normalized_id := _normalize_weapon_id(weapon_id)
	return (
		WEAPON_ITEM_IDS.has(normalized_id)
		and _slot_array_has_item(player_slots, normalized_id)
		and not _slot_array_has_item(trunk_slots, normalized_id)
		and not table_stored_weapons.has(normalized_id)
	)


func remove_weapon_from_player(weapon_id: String) -> bool:
	var normalized_id := _normalize_weapon_id(weapon_id)
	var removed := false
	for slot_index in PLAYER_MAX_SLOTS:
		if String(player_slots[slot_index].get("id", "")) == normalized_id:
			player_slots[slot_index] = {}
			removed = true
	if removed:
		_sync_slot_state(true)
	return removed


func sync_weapon_ownership() -> void:
	_sync_slot_state(true)


func set_counter_stock(item: String, value: int) -> int:
	var ingredient_name := _normalize_counter_ingredient(item)
	if ingredient_name.is_empty():
		return 0
	var remaining := clampi(value, 0, COUNTER_MAX_STOCK)
	counter_stocks[ingredient_name] = remaining
	var stock_key := _ingredient_stock_key(ingredient_name)
	ingredient_stock[stock_key] = remaining
	# Keep both names synchronized while older systems still refer to salad.
	if ingredient_name == "lettuce":
		ingredient_stock["lettuce"] = remaining
		ingredient_stock["salad"] = remaining
	stock_updated.emit(stock_key, remaining)
	counter_stock_updated.emit(ingredient_name, remaining)
	return remaining


func consume_counter_ingredient(item: String, count: int = 1) -> bool:
	var ingredient_name := _normalize_counter_ingredient(item)
	if ingredient_name.is_empty() or count <= 0:
		return false
	var remaining := get_counter_stock(ingredient_name)
	if count > remaining:
		return false
	set_counter_stock(ingredient_name, remaining - count)
	return true


func _sync_counter_stock_aliases() -> void:
	for ingredient_name: String in COUNTER_INGREDIENTS:
		var remaining := clampi(
			int(counter_stocks.get(ingredient_name, COUNTER_MAX_STOCK)),
			0,
			COUNTER_MAX_STOCK
		)
		counter_stocks[ingredient_name] = remaining
		ingredient_stock[_ingredient_stock_key(ingredient_name)] = remaining
		if ingredient_name == "lettuce":
			ingredient_stock["lettuce"] = remaining


func _normalize_counter_ingredient(item: String) -> String:
	var ingredient_name := WholeVegetableFactory.normalize_ingredient_id(item)
	return ingredient_name if COUNTER_INGREDIENTS.has(ingredient_name) else ""


func _normalize_raw_supply_ingredient(item: String) -> String:
	var ingredient_name := WholeVegetableFactory.normalize_ingredient_id(item)
	return ingredient_name if RAW_SUPPLY_INGREDIENTS.has(ingredient_name) else ""


func _restore_inventory_slots(save_data: Dictionary) -> void:
	player_slots.clear()
	trunk_slots.clear()
	_ensure_fixed_slot_arrays()

	var loaded_player_slots: Variant = save_data.get("player_slots", [])
	if loaded_player_slots is Array and save_data.has("player_slots"):
		_load_fixed_slot_array(player_slots, loaded_player_slots, PLAYER_MAX_SLOTS)
	else:
		var loaded_inventory: Variant = save_data.get("inventory_items", {})
		if loaded_inventory is Dictionary:
			for item_id: String in INVENTORY_ITEM_IDS:
				var count := maxi(int(loaded_inventory.get(item_id, 0)), 0)
				if count > 0:
					_add_to_slot_array(
						player_slots,
						PLAYER_MAX_SLOTS,
						_slot_item_for_id(item_id, count)
					)
		var migrated_weapon_count := 0
		for raw_weapon: String in owned_weapons:
			var weapon_id := _normalize_weapon_id(raw_weapon)
			if not WEAPON_ITEM_IDS.has(weapon_id) or table_stored_weapons.has(weapon_id):
				continue
			if _add_to_slot_array(
				player_slots,
				PLAYER_MAX_SLOTS,
				_slot_item_for_id(weapon_id, 1)
			):
				migrated_weapon_count += 1
		if migrated_weapon_count == 0:
			for weapon_id: String in ["ak47", "glock", "awp", "knife"]:
				if not table_stored_weapons.has(weapon_id):
					_add_to_slot_array(
						player_slots,
						PLAYER_MAX_SLOTS,
						_slot_item_for_id(weapon_id, 1)
					)

	var loaded_trunk_slots: Variant = save_data.get("trunk_slots", [])
	if loaded_trunk_slots is Array and save_data.has("trunk_slots"):
		_load_fixed_slot_array(trunk_slots, loaded_trunk_slots, TRUNK_MAX_SLOTS)
	else:
		var loaded_trunk_items: Variant = save_data.get("tofas_trunk_items", [])
		if loaded_trunk_items is Array:
			for raw_item: Variant in loaded_trunk_items:
				if not raw_item is Dictionary:
					continue
				var normalized_item := _normalize_slot_item(raw_item)
				if normalized_item.is_empty():
					continue
				var target_slot := int(raw_item.get("slot", -1))
				if (
					target_slot < 0
					or target_slot >= TRUNK_MAX_SLOTS
					or not trunk_slots[target_slot].is_empty()
				):
					target_slot = _find_empty_slot(trunk_slots, TRUNK_MAX_SLOTS)
				if target_slot >= 0:
					trunk_slots[target_slot] = normalized_item

	_resolve_weapon_location_conflicts()
	_sync_slot_state(false)


func _ensure_fixed_slot_arrays() -> void:
	_ensure_slot_array_size(player_slots, PLAYER_MAX_SLOTS)
	_ensure_slot_array_size(trunk_slots, TRUNK_MAX_SLOTS)


func _ensure_slot_array_size(slots: Array[Dictionary], required_size: int) -> void:
	if slots.size() > required_size:
		slots.resize(required_size)
	while slots.size() < required_size:
		slots.append({})
	for slot_index in required_size:
		slots[slot_index] = _normalize_slot_item(slots[slot_index])


func _load_fixed_slot_array(
	target: Array[Dictionary],
	raw_slots: Array,
	required_size: int
) -> void:
	target.clear()
	for slot_index in required_size:
		var raw_item: Variant = raw_slots[slot_index] if slot_index < raw_slots.size() else {}
		target.append(_normalize_slot_item(raw_item) if raw_item is Dictionary else {})


func _seed_default_player_slots() -> void:
	player_slots.clear()
	trunk_slots.clear()
	_ensure_fixed_slot_arrays()
	for weapon_id: String in ["ak47", "glock", "awp", "knife"]:
		_add_to_slot_array(
			player_slots,
			PLAYER_MAX_SLOTS,
			_slot_item_for_id(weapon_id, 1)
		)


func _normalize_slot_item(raw_item: Dictionary) -> Dictionary:
	var item_id := _normalize_slot_item_id(String(raw_item.get("id", "")))
	if item_id.is_empty():
		return {}
	var is_weapon := WEAPON_ITEM_IDS.has(item_id)
	var count := 1 if is_weapon else maxi(int(raw_item.get("count", 0)), 0)
	if count <= 0:
		return {}
	return {
		"id": item_id,
		"type": "weapon" if is_weapon else "ingredient",
		"count": count,
	}


func _slot_item_for_id(item_id: String, count: int) -> Dictionary:
	return _normalize_slot_item({"id": item_id, "count": count})


func _normalize_slot_item_id(item_id: String) -> String:
	var weapon_id := _normalize_weapon_id(item_id)
	if WEAPON_ITEM_IDS.has(weapon_id):
		return weapon_id
	return _normalize_inventory_item(item_id)


func _normalize_inventory_item(item_id: String) -> String:
	var normalized_id := item_id.strip_edges().to_lower()
	if not normalized_id.begins_with("whole_"):
		return ""
	var ingredient_name := WholeVegetableFactory.normalize_ingredient_id(normalized_id)
	normalized_id = "whole_%s" % ingredient_name
	return normalized_id if INVENTORY_ITEM_IDS.has(normalized_id) else ""


func _add_to_slot_array(
	slots: Array[Dictionary],
	max_slots: int,
	item: Dictionary
) -> bool:
	var normalized_item := _normalize_slot_item(item)
	if normalized_item.is_empty():
		return false
	var item_id := String(normalized_item["id"])
	if String(normalized_item["type"]) == "ingredient":
		for slot_index in max_slots:
			if String(slots[slot_index].get("id", "")) == item_id:
				var stacked_item := slots[slot_index]
				stacked_item["count"] = int(stacked_item.get("count", 0)) + int(normalized_item["count"])
				slots[slot_index] = stacked_item
				return true
	elif _slot_array_has_item(slots, item_id):
		return false
	var empty_slot := _find_empty_slot(slots, max_slots)
	if empty_slot < 0:
		return false
	slots[empty_slot] = normalized_item
	return true


func _find_empty_slot(slots: Array[Dictionary], max_slots: int) -> int:
	for slot_index in max_slots:
		if slots[slot_index].is_empty():
			return slot_index
	return -1


func _slot_array_has_item(slots: Array[Dictionary], item_id: String) -> bool:
	for slot_item: Dictionary in slots:
		if String(slot_item.get("id", "")) == item_id:
			return true
	return false


func _slots_for_container(container_name: String) -> Array[Dictionary]:
	match container_name:
		"player":
			return player_slots
		"trunk":
			return trunk_slots
	return [] as Array[Dictionary]


func _max_slots_for_container(container_name: String) -> int:
	match container_name:
		"player":
			return PLAYER_MAX_SLOTS
		"trunk":
			return TRUNK_MAX_SLOTS
	return 0


func _resolve_weapon_location_conflicts() -> void:
	for weapon_id: String in WEAPON_ITEM_IDS:
		var keep_player_copy := (
			not _slot_array_has_item(trunk_slots, weapon_id)
			and not table_stored_weapons.has(weapon_id)
		)
		var player_copy_found := false
		for slot_index in PLAYER_MAX_SLOTS:
			if String(player_slots[slot_index].get("id", "")) != weapon_id:
				continue
			if keep_player_copy and not player_copy_found:
				player_copy_found = true
			else:
				player_slots[slot_index] = {}
		var trunk_copy_found := false
		for slot_index in TRUNK_MAX_SLOTS:
			if String(trunk_slots[slot_index].get("id", "")) != weapon_id:
				continue
			if not trunk_copy_found:
				trunk_copy_found = true
			else:
				trunk_slots[slot_index] = {}


func _sync_slot_state(emit_signals: bool) -> void:
	_ensure_fixed_slot_arrays()
	for item_id: String in INVENTORY_ITEM_IDS:
		inventory_items[item_id] = get_inventory_count(item_id)
	_collect_tofas_trunk_items()
	owned_weapons.clear()
	owned_weapons.append("unarmed")
	for weapon_id: String in WEAPON_ITEM_IDS:
		if player_has_weapon(weapon_id):
			owned_weapons.append(weapon_id)
	if not emit_signals:
		return
	for item_id: String in INVENTORY_ITEM_IDS:
		inventory_item_changed.emit(item_id, int(inventory_items[item_id]))
	inventory_slots_changed.emit()
	_notify_player_weapon_state()


func _notify_player_weapon_state() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("sync_weapon_slots_from_inventory"):
		player.call("sync_weapon_slots_from_inventory")


func _ingredient_stock_key(ingredient_name: String) -> String:
	return "salad" if ingredient_name == "lettuce" else ingredient_name


func _normalize_placed_lavash(data: Dictionary) -> Dictionary:
	var toppings: Array[String] = []
	var raw_toppings: Variant = data.get("toppings", data.get("ingredients", []))
	if raw_toppings is Array:
		for raw_topping: Variant in raw_toppings:
			toppings.append(String(raw_topping))
	return {
		"is_present": bool(data.get("is_present", false)),
		"is_baked": bool(data.get("is_baked", false)),
		"is_rolled": bool(data.get("is_rolled", false)),
		"toppings": toppings,
	}


func _count_lavash_meat(state: Dictionary) -> int:
	var count := 0
	var raw_toppings: Variant = state.get("toppings", state.get("ingredients", []))
	if raw_toppings is Array:
		for raw_topping: Variant in raw_toppings:
			var topping := String(raw_topping).strip_edges().to_lower()
			if topping == "meat" or topping == "cut_meat" or topping == "meat_portion":
				count += 1
	return count


func _append_missing_lavash_meat(amount: int) -> void:
	if amount <= 0 or not bool(placed_lavash_state.get("is_present", false)):
		return
	var toppings: Array[String] = []
	var raw_toppings: Variant = placed_lavash_state.get("toppings", [])
	if raw_toppings is Array:
		for raw_topping: Variant in raw_toppings:
			toppings.append(String(raw_topping))
	for _index in amount:
		toppings.append("meat")
	placed_lavash_state["toppings"] = toppings
	placed_lavash = placed_lavash_state.duplicate(true)
	for item_index in counter_items.size():
		var entry := counter_items[item_index]
		var item_type := String(entry.get("type", ""))
		if item_type != "baked_lavash" and item_type != "durum_assembly":
			continue
		entry["type"] = "durum_assembly"
		entry["ingredients"] = toppings.duplicate()
		counter_items[item_index] = entry
		_restore_counter_inventory = true
		break


func _counter_items_have_lavash(items: Array[Dictionary]) -> bool:
	for entry: Dictionary in items:
		var item_type := String(entry.get("type", ""))
		if item_type == "baked_lavash" or item_type == "durum_assembly":
			return true
	return false


func retrieve_weapon_from_table(weapon_type: String) -> bool:
	var weapon_id := _normalize_weapon_id(weapon_type)
	if not WEAPON_ITEM_IDS.has(weapon_id) or not can_add_player_item(weapon_id, 1):
		return false

	while table_stored_weapons.has(weapon_id):
		table_stored_weapons.erase(weapon_id)
	return add_inventory_item(weapon_id, 1)


func _remove_owned_weapon(weapon_id: String) -> void:
	for index in range(owned_weapons.size() - 1, -1, -1):
		if _normalize_weapon_id(owned_weapons[index]) == weapon_id:
			owned_weapons.remove_at(index)


func _normalize_weapon_id(weapon_id: String) -> String:
	var normalized := weapon_id.strip_edges().to_lower().replace("-", "").replace("_", "")
	match normalized:
		"glock", "glock17":
			return "glock"
		"ak47", "ak":
			return "ak47"
		"awp":
			return "awp"
		"knife", "doenermesser", "dönermesser":
			return "knife"
	return normalized
