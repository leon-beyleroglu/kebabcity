class_name PickupableItem
extends Area3D

const DEFAULT_SCENE_PATH := "res://PickupableItem.tscn"
const INTERACTION_LAYER := 1 << 7
const DoenerTongsScript := preload("res://DoenerTongs.gd")

var item_data: Dictionary = {}
var item_visual: Node3D


func _ready() -> void:
	add_to_group("pickupable_item")
	collision_layer = INTERACTION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	set_meta("pickupable_item", true)


func configure(data: Dictionary) -> bool:
	item_data = normalize_item_data(data)
	if item_data.is_empty():
		return false
	name = "Placed%s" % String(item_data["id"]).to_pascal_case()
	set_meta("item_data", item_data)
	set_meta("item_id", item_data["id"])
	_rebuild_visual()
	_rebuild_collision()
	return is_instance_valid(item_visual)


func get_item_data() -> Dictionary:
	return item_data.duplicate(true)


func get_save_data() -> Dictionary:
	var data := get_item_data()
	data["pos"] = _vector_to_data(global_position)
	data["rot"] = _vector_to_data(global_rotation)
	return data


func place_at_surface(point: Vector3, normal: Vector3) -> void:
	var surface_up := normal.normalized()
	if surface_up.is_zero_approx():
		surface_up = Vector3.UP
	var x_axis := Vector3.FORWARD.cross(surface_up).normalized()
	if x_axis.is_zero_approx():
		x_axis = Vector3.RIGHT
	var z_axis := x_axis.cross(surface_up).normalized()
	global_transform = Transform3D(Basis(x_axis, surface_up, z_axis).orthonormalized(), point + surface_up * 0.004)


static func normalize_item_data(data: Dictionary) -> Dictionary:
	var item_id := String(data.get("id", "")).strip_edges().to_lower()
	if item_id == "cut_meat":
		item_id = "meat_portion"
	if item_id == "meat_portion":
		return {
			"id": "meat_portion",
			"type": "meat",
			"is_cut": true,
			"scene_path": String(data.get("scene_path", DEFAULT_SCENE_PATH)),
		}
	var prefix := ""
	if item_id.begins_with("whole_"):
		prefix = "whole_"
	elif item_id.begins_with("sliced_"):
		prefix = "sliced_"
	else:
		return {}
	var ingredient_id := WholeVegetableFactory.normalize_ingredient_id(item_id)
	if ingredient_id.is_empty():
		return {}
	var normalized_id := prefix + ingredient_id
	return {
		"id": normalized_id,
		"is_cut": prefix == "sliced_",
		"scene_path": String(data.get("scene_path", DEFAULT_SCENE_PATH)),
	}


static func data_for_id(item_id: String) -> Dictionary:
	return normalize_item_data({
		"id": item_id,
		"is_cut": item_id.begins_with("sliced_"),
		"scene_path": DEFAULT_SCENE_PATH,
	})


static func spawn(
	parent: Node,
	data: Dictionary,
	position: Vector3,
	rotation := Vector3.ZERO
) -> PickupableItem:
	if not is_instance_valid(parent):
		return null
	var normalized := normalize_item_data(data)
	if normalized.is_empty():
		return null
	var item: PickupableItem
	var scene_path := String(normalized.get("scene_path", DEFAULT_SCENE_PATH))
	if ResourceLoader.exists(scene_path):
		var packed_scene := load(scene_path) as PackedScene
		if is_instance_valid(packed_scene):
			item = packed_scene.instantiate() as PickupableItem
	if not is_instance_valid(item):
		item = PickupableItem.new()
	parent.add_child(item)
	if not item.configure(normalized):
		item.queue_free()
		return null
	item.global_position = position
	item.global_rotation = rotation
	return item


static func vector_from_data(data: Variant) -> Vector3:
	if not data is Dictionary:
		return Vector3.ZERO
	return Vector3(
		float(data.get("x", 0.0)),
		float(data.get("y", 0.0)),
		float(data.get("z", 0.0))
	)


static func _vector_to_data(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


func _rebuild_visual() -> void:
	if is_instance_valid(item_visual):
		item_visual.queue_free()
	var item_id := String(item_data.get("id", ""))
	if item_id == "meat_portion":
		item_visual = DoenerTongsScript.create_meat_portion_visual()
		add_child(item_visual)
		item_visual.position = Vector3(0.0, _visual_contact_height(item_id), 0.0)
		return
	var ingredient_id := WholeVegetableFactory.normalize_ingredient_id(item_id)
	item_visual = (
		WholeVegetableFactory.create_sliced(ingredient_id)
		if bool(item_data.get("is_cut", false))
		else WholeVegetableFactory.create_whole(ingredient_id)
	)
	if not is_instance_valid(item_visual):
		return
	add_child(item_visual)
	item_visual.position = Vector3(0.0, _visual_contact_height(item_id), 0.0)


func _rebuild_collision() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			child.queue_free()
	var item_id := String(item_data.get("id", ""))
	var size := _collision_size(item_id)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "PickupCollision"
	collision.shape = shape
	collision.position.y = size.y * 0.5
	add_child(collision)


func _visual_contact_height(item_id: String) -> float:
	if item_id == "meat_portion":
		return 0.025
	if item_id.begins_with("sliced_"):
		return 0.018
	match WholeVegetableFactory.normalize_ingredient_id(item_id):
		"onion", "tomato":
			return 0.06
		"cucumber":
			return 0.035
		"lettuce":
			return 0.07
		"red_cabbage":
			return 0.09
	return 0.05


func _collision_size(item_id: String) -> Vector3:
	if item_id == "meat_portion":
		return Vector3(0.22, 0.08, 0.18)
	if item_id.begins_with("sliced_"):
		return Vector3(0.2, 0.055, 0.16)
	match WholeVegetableFactory.normalize_ingredient_id(item_id):
		"cucumber":
			return Vector3(0.3, 0.08, 0.09)
		"lettuce":
			return Vector3(0.24, 0.2, 0.24)
		"red_cabbage":
			return Vector3(0.22, 0.19, 0.22)
		"onion":
			return Vector3(0.16, 0.13, 0.16)
		"tomato":
			return Vector3(0.14, 0.13, 0.14)
	return Vector3(0.16, 0.12, 0.16)
