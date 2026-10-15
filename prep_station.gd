@tool
class_name PrepStation
extends StaticBody3D

signal ingredient_added(item_id: String, item: Area3D)
signal ingredient_removed(item_id: String, item: Area3D)

const INTERACTION_LAYER := 1 << 7
const PREP_ITEM_LAYER := 1 << 8

@export var surface_size := Vector3(2.6, 0.14, 1.45)
@export var snap_columns := 4
@export var snap_rows := 2

var current_ingredients: Array[String] = []
var current_items: Array[Area3D] = []
var occupied_slots: Dictionary = {}
var detection_area: Area3D


func _ready() -> void:
	add_to_group("prep_surface")
	set_meta("assembly_station", true)
	collision_layer = 1 | INTERACTION_LAYER
	collision_mask = 0
	if get_node_or_null("Schneidebrett"):
		return
	_build_surface()
	_build_detection_area()


func _build_surface() -> void:
	var board_material := StandardMaterial3D.new()
	board_material.albedo_color = Color("b8753f")
	board_material.roughness = 0.72

	var board_mesh := BoxMesh.new()
	board_mesh.size = surface_size
	board_mesh.material = board_material
	var board := MeshInstance3D.new()
	board.name = "Schneidebrett"
	board.mesh = board_mesh
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(board)

	var board_shape := BoxShape3D.new()
	board_shape.size = surface_size
	var board_collision := CollisionShape3D.new()
	board_collision.name = "SurfaceCollision"
	board_collision.shape = board_shape
	add_child(board_collision)

	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = Color("6f3f25")
	rim_material.roughness = 0.8
	_add_rim(Vector3(0, surface_size.y * 0.5 + 0.055, -surface_size.z * 0.5 + 0.035), Vector3(surface_size.x, 0.11, 0.07), rim_material)
	_add_rim(Vector3(0, surface_size.y * 0.5 + 0.055, surface_size.z * 0.5 - 0.035), Vector3(surface_size.x, 0.11, 0.07), rim_material)
	_add_rim(Vector3(-surface_size.x * 0.5 + 0.035, surface_size.y * 0.5 + 0.055, 0), Vector3(0.07, 0.11, surface_size.z), rim_material)
	_add_rim(Vector3(surface_size.x * 0.5 - 0.035, surface_size.y * 0.5 + 0.055, 0), Vector3(0.07, 0.11, surface_size.z), rim_material)

func _add_rim(rim_position: Vector3, rim_size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = rim_size
	mesh.material = material
	var rim := MeshInstance3D.new()
	rim.mesh = mesh
	rim.position = rim_position
	add_child(rim)


func _build_detection_area() -> void:
	detection_area = Area3D.new()
	detection_area.name = "IngredientDetection"
	detection_area.position.y = surface_size.y * 0.5 + 0.22
	detection_area.collision_layer = 0
	detection_area.collision_mask = PREP_ITEM_LAYER
	detection_area.monitoring = true
	detection_area.monitorable = false
	add_child(detection_area)

	var detection_shape := BoxShape3D.new()
	detection_shape.size = Vector3(surface_size.x - 0.12, 0.42, surface_size.z - 0.12)
	var collision := CollisionShape3D.new()
	collision.name = "DetectionShape"
	collision.shape = detection_shape
	detection_area.add_child(collision)
	detection_area.area_entered.connect(_on_item_area_entered)
	detection_area.area_exited.connect(_on_item_area_exited)


func place_item(item: Area3D, item_id: String, hit_position: Vector3) -> Vector3:
	var slot: int = _find_best_free_slot(hit_position)
	occupied_slots[slot] = item
	item.set_meta("prep_slot", slot)
	item.set_meta("prep_station", self)
	item.set_meta("ingredient_id", item_id)
	item.collision_layer = INTERACTION_LAYER | PREP_ITEM_LAYER
	item.collision_mask = 0
	_register_item(item)
	return to_global(_slot_position(slot))


func remove_item(item: Area3D) -> void:
	if not is_instance_valid(item):
		return
	var slot: int = int(item.get_meta("prep_slot", -1))
	if occupied_slots.get(slot) == item:
		occupied_slots.erase(slot)
	item.remove_meta("prep_slot")
	item.remove_meta("prep_station")
	_unregister_item(item)


func has_ingredients(required: Array[String]) -> bool:
	var remaining := current_ingredients.duplicate()
	for ingredient in required:
		var index := remaining.find(ingredient)
		if index == -1:
			return false
		remaining.remove_at(index)
	return true


func _find_best_free_slot(hit_position: Vector3) -> int:
	var best_slot := -1
	var best_distance: float = INF
	var slot_count: int = snap_columns * snap_rows
	for slot in range(slot_count):
		if occupied_slots.has(slot) and is_instance_valid(occupied_slots[slot]):
			continue
		var distance := to_global(_slot_position(slot)).distance_squared_to(hit_position)
		if distance < best_distance:
			best_distance = distance
			best_slot = slot
	if best_slot >= 0:
		return best_slot
	return _oldest_slot()


func _oldest_slot() -> int:
	for slot in occupied_slots.keys():
		var old_item: Area3D = occupied_slots[slot]
		if not is_instance_valid(old_item):
			occupied_slots.erase(slot)
			return int(slot)
	return 0


func _slot_position(slot: int) -> Vector3:
	var column: int = slot % snap_columns
	var row: int = floori(float(slot) / float(snap_columns))
	var usable_x := surface_size.x - 0.48
	var usable_z := surface_size.z - 0.42
	var x := -usable_x * 0.5 + usable_x * (float(column) + 0.5) / float(snap_columns)
	var z := -usable_z * 0.5 + usable_z * (float(row) + 0.5) / float(snap_rows)
	return Vector3(x, surface_size.y * 0.5 + 0.13, z)


func _register_item(item: Area3D) -> void:
	if current_items.has(item):
		return
	current_items.append(item)
	var item_id := String(item.get_meta("ingredient_id", "unknown"))
	current_ingredients.append(item_id)
	ingredient_added.emit(item_id, item)


func _unregister_item(item: Area3D) -> void:
	var index := current_items.find(item)
	if index == -1:
		return
	var item_id := String(item.get_meta("ingredient_id", "unknown"))
	current_items.remove_at(index)
	var ingredient_index := current_ingredients.find(item_id)
	if ingredient_index >= 0:
		current_ingredients.remove_at(ingredient_index)
	ingredient_removed.emit(item_id, item)


func _on_item_area_entered(area: Area3D) -> void:
	if area.has_meta("ingredient_id"):
		_register_item(area)


func _on_item_area_exited(area: Area3D) -> void:
	if not current_items.has(area):
		return
	var slot: int = int(area.get_meta("prep_slot", -1))
	if occupied_slots.get(slot) == area:
		occupied_slots.erase(slot)
	area.remove_meta("prep_slot")
	area.remove_meta("prep_station")
	_unregister_item(area)
