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


func _ready() -> void:
	add_to_group("work_surface")
	set_meta("assembly_station", true)
	set_meta("work_surface", true)
	collision_layer = 1 | INTERACTION_LAYER
	collision_mask = 0
	if not is_instance_valid(placed_items):
		placed_items = Node3D.new()
		placed_items.name = "PlacedItems"
		add_child(placed_items)


func can_place_item(hit_normal: Vector3) -> bool:
	return is_instance_valid(table_mesh) and hit_normal.normalized().y > 0.9


func snap_to_table_top(hit_point: Vector3, hit_normal: Vector3) -> Vector3:
	if not can_place_item(hit_normal):
		return hit_point
	var local_hit: Vector3 = table_mesh.to_local(hit_point)
	local_hit.x = clampf(local_hit.x, -table_width * 0.45, table_width * 0.45)
	local_hit.z = clampf(local_hit.z, -table_depth * 0.45, table_depth * 0.45)
	local_hit.y = table_top_y_offset
	return table_mesh.to_global(local_hit)


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
	current_items.append(item)
	item.tree_exiting.connect(_on_placed_item_tree_exiting.bind(item), CONNECT_ONE_SHOT)
	item_placed.emit(item_id, item)


func _on_placed_item_tree_exiting(item: Node3D) -> void:
	current_items.erase(item)
