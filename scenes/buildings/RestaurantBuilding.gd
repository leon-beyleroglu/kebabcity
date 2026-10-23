@tool
class_name ModularRestaurantBuilding
extends StaticBody3D

signal owner_interaction(owner: RestaurantOwner)

@export_category("Restaurant")
@export var restaurant_id: StringName = &"restaurant"
@export var display_name: String = "Restaurant":
	set(value):
		display_name = value
		_queue_visual_refresh()
@export_multiline var description: String = ""

@export_category("Editable palette")
@export var facade_color := Color(0.82, 0.61, 0.39, 1.0):
	set(value):
		facade_color = value
		_queue_visual_refresh()
@export var secondary_color := Color(0.95, 0.87, 0.67, 1.0):
	set(value):
		secondary_color = value
		_queue_visual_refresh()
@export var accent_color := Color(0.34, 0.16, 0.09, 1.0):
	set(value):
		accent_color = value
		_queue_visual_refresh()
@export var metal_color := Color(0.55, 0.59, 0.62, 1.0):
	set(value):
		metal_color = value
		_queue_visual_refresh()
@export var sign_color := Color(1.0, 0.82, 0.28, 1.0):
	set(value):
		sign_color = value
		_queue_visual_refresh()
@export var sign_text_color := Color(1.0, 0.9, 0.68, 1.0):
	set(value):
		sign_text_color = value
		_queue_visual_refresh()

@export_category("Editable meshes")
@export var main_wall_mesh: Mesh:
	set(value):
		main_wall_mesh = value
		_queue_visual_refresh()
@export var counter_mesh: Mesh:
	set(value):
		counter_mesh = value
		_queue_visual_refresh()

@export_category("Editor node paths")
@export_node_path("MeshInstance3D") var main_wall_path := NodePath("Exterior/BackWall")
@export_node_path("MeshInstance3D") var counter_path := NodePath("Interior/OrderCounter/CounterBody")
@export_node_path("Label3D") var sign_path := NodePath("Exterior/Sign/SignText")
@export_node_path("Node3D") var owner_anchor_path := NodePath("Interior/OwnerAnchor")

var _refresh_queued := false


func _ready() -> void:
	_apply_customization()
	if not Engine.is_editor_hint():
		add_to_group("modular_restaurant")
		_connect_owner()


func get_restaurant_owner() -> RestaurantOwner:
	var anchor := get_node_or_null(owner_anchor_path)
	if not is_instance_valid(anchor):
		return null
	for child in anchor.get_children():
		if child is RestaurantOwner:
			return child as RestaurantOwner
	return null


func get_parking_markers() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	for node in find_children("ParkingBay*", "Marker3D", true, false):
		markers.append(node as Marker3D)
	return markers


func _queue_visual_refresh() -> void:
	if not is_inside_tree() or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_customization")


func _apply_customization() -> void:
	_refresh_queued = false
	if not is_inside_tree():
		return
	var wall := get_node_or_null(main_wall_path) as MeshInstance3D
	if is_instance_valid(wall) and is_instance_valid(main_wall_mesh):
		wall.mesh = main_wall_mesh
	var counter := get_node_or_null(counter_path) as MeshInstance3D
	if is_instance_valid(counter) and is_instance_valid(counter_mesh):
		counter.mesh = counter_mesh
	var sign_label := get_node_or_null(sign_path) as Label3D
	if is_instance_valid(sign_label):
		sign_label.text = display_name
		sign_label.modulate = sign_text_color
	_apply_palette_recursive(self)


func _apply_palette_recursive(parent: Node) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D:
			_apply_mesh_palette(child as MeshInstance3D)
		_apply_palette_recursive(child)


func _apply_mesh_palette(mesh_instance: MeshInstance3D) -> void:
	var palette_slot := String(mesh_instance.get_meta("palette_slot", ""))
	if palette_slot.is_empty():
		return
	var material := mesh_instance.material_override as StandardMaterial3D
	if not is_instance_valid(material):
		material = StandardMaterial3D.new()
		material.roughness = 0.82
		mesh_instance.material_override = material
	match palette_slot:
		"facade":
			material.albedo_color = facade_color
		"secondary":
			material.albedo_color = secondary_color
		"accent":
			material.albedo_color = accent_color
		"metal":
			material.albedo_color = metal_color
		"sign":
			material.albedo_color = sign_color


func _connect_owner() -> void:
	var owner := get_restaurant_owner()
	if not is_instance_valid(owner):
		return
	owner.restaurant_id = restaurant_id
	owner.restaurant_name = display_name
	if not owner.interaction_requested.is_connected(_on_owner_interaction):
		owner.interaction_requested.connect(_on_owner_interaction)


func _on_owner_interaction(owner: RestaurantOwner) -> void:
	owner_interaction.emit(owner)
