@tool
class_name AssemblyStation
extends StaticBody3D

signal item_placed(item_id: String, item: Node3D)
signal item_removed(item_id: String, item: Node3D)

const INTERACTION_LAYER := 1 << 7
const PREP_ITEM_LAYER := 1 << 8
@export var table_mesh_path := NodePath("../Arbeitsplatte")
@export var table_width := 7.9843507
@export var table_depth := 1.5
@export var table_top_y_offset := 0.07

@onready var table_mesh := get_node_or_null(table_mesh_path) as MeshInstance3D
@onready var placed_items := get_node_or_null("PlacedItems") as Node3D

var current_items: Array[Node3D] = []
var _item_restore_callback: Callable


func _ready() -> void:
	add_to_group("assembly_counter")
	add_to_group("work_surface")
	set_meta("assembly_station", true)
	set_meta("work_surface", true)
	collision_layer = 1 | INTERACTION_LAYER
	collision_mask = 0
	if not is_instance_valid(placed_items):
		placed_items = Node3D.new()
		placed_items.name = "PlacedItems"
		add_child(placed_items)


func configure_persistence(item_restore_callback: Callable) -> void:
	_item_restore_callback = item_restore_callback


func get_save_data() -> Dictionary:
	var saved_items: Array[Dictionary] = []
	for slot_index in current_items.size():
		var item := current_items[slot_index]
		if not is_instance_valid(item):
			continue
		var item_type := String(item.get_meta("item_id", item.get_meta("ingredient_id", "")))
		if item_type.is_empty():
			continue
		var ingredients: Array = item.get_meta("ingredients", [])
		if item_type == "durum_assembly" and ingredients.is_empty():
			item_type = "baked_lavash"
		var saved_slot_index := int(item.get_meta("save_slot_index", slot_index))
		var table_position := table_mesh.to_local(item.global_position)
		var entry: Dictionary = {
			"type": item_type,
			"is_baked": item_type == "baked_lavash" or item_type == "durum_assembly",
			"slot_index": saved_slot_index,
			"local_x": table_position.x,
			"local_z": table_position.z,
		}
		if not ingredients.is_empty():
			entry["ingredients"] = ingredients.duplicate()
		saved_items.append(entry)
	return {"items": saved_items}


func load_save_data(data: Dictionary) -> bool:
	if not _item_restore_callback.is_valid():
		return false
	var saved_items: Array[Dictionary] = []
	var raw_items: Variant = data.get("items", [])
	if raw_items is Array:
		for index in raw_items.size():
			var raw_item: Variant = raw_items[index]
			if raw_item is Dictionary:
				saved_items.append(raw_item)
			elif raw_item is String:
				var legacy_type := String(raw_item)
				saved_items.append({
					"type": legacy_type,
					"is_baked": legacy_type == "baked_lavash",
					"slot_index": index,
				})

	var items_to_remove := current_items.duplicate()
	current_items.clear()
	for item: Node3D in items_to_remove:
		if is_instance_valid(item):
			item.queue_free()

	_item_restore_callback.call(saved_items)
	return true


func can_place_item(hit_normal: Vector3) -> bool:
	return is_instance_valid(table_mesh) and hit_normal.normalized().y > 0.9


func snap_to_table_top(hit_point: Vector3, hit_normal: Vector3) -> Vector3:
	if not can_place_item(hit_normal):
		return hit_point
	var local_hit: Vector3 = table_mesh.to_local(hit_point)
	local_hit.x = clampf(local_hit.x, -table_width * 0.45, table_width * 0.45)
	local_hit.z = clampf(local_hit.z, -table_depth * 0.45, table_depth * 0.45)
	local_hit.y = get_surface_local_y()
	return table_mesh.to_global(local_hit)


func get_surface_local_y() -> float:
	if is_instance_valid(table_mesh) and is_instance_valid(table_mesh.mesh):
		return table_mesh.mesh.get_aabb().end.y
	return table_top_y_offset


func get_slot_position(slot_index: int, total: int) -> Vector3:
	var column_count := 6
	var occupied_slots := maxi(maxi(total, 1), slot_index + 1)
	var row_count := ceili(float(occupied_slots) / float(column_count))
	var column := slot_index % column_count
	var row := slot_index / column_count
	var local_x := lerpf(-table_width * 0.35, table_width * 0.35, float(column) / float(column_count - 1))
	var local_z := 0.0
	if row_count > 1:
		local_z = lerpf(-table_depth * 0.28, table_depth * 0.28, float(row) / float(row_count - 1))
	return table_mesh.to_global(Vector3(local_x, get_surface_local_y(), local_z))


func get_placed_items_container() -> Node3D:
	return placed_items


func place_item(item: Node3D, item_id: String, hit_point: Vector3, hit_normal: Vector3) -> Node3D:
	if not is_instance_valid(item) or not can_place_item(hit_normal):
		return null
	var snapped_position := snap_to_table_top(hit_point, hit_normal)
	var table := placed_items
	if item.get_parent() != table:
		item.reparent(table)
	item.global_transform = Transform3D(Basis.IDENTITY, snapped_position)
	item.scale = Vector3.ONE
	item.set_meta("item_id", item_id)
	item.set_meta("ingredient_id", item_id)
	item.set_meta("prep_station", self)
	item.set_meta("placed_on_assembly_station", true)
	item.add_to_group("placed_items")
	if item is CollisionObject3D:
		(item as CollisionObject3D).collision_layer = 1 << 1
		(item as CollisionObject3D).collision_mask = 0
	for collision_node in item.find_children("*", "CollisionShape3D", true, false):
		var collision_shape := collision_node as CollisionShape3D
		if not is_instance_valid(collision_shape):
			continue
		collision_shape.disabled = false
		var box_shape := collision_shape.shape as BoxShape3D
		if is_instance_valid(box_shape):
			var enlarged_size := box_shape.size
			enlarged_size.y = maxf(enlarged_size.y, 0.24)
			box_shape.size = enlarged_size
	_register_item(item, item_id)
	return item


func remove_item(item: Node3D) -> void:
	if not is_instance_valid(item):
		return
	var item_id := String(item.get_meta("item_id", item.get_meta("ingredient_id", "")))
	current_items.erase(item)
	item.remove_meta("prep_station")
	item.remove_meta("placed_on_assembly_station")
	item_removed.emit(item_id, item)


func _register_item(item: Node3D, item_id: String) -> void:
	if current_items.has(item):
		return
	if not item.has_meta("save_slot_index"):
		item.set_meta("save_slot_index", current_items.size())
	current_items.append(item)
	var exit_callback := _on_placed_item_tree_exiting.bind(item)
	if not item.tree_exiting.is_connected(exit_callback):
		item.tree_exiting.connect(exit_callback, CONNECT_ONE_SHOT)
	item_placed.emit(item_id, item)


func _on_placed_item_tree_exiting(item: Node3D) -> void:
	current_items.erase(item)
