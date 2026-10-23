@tool
class_name RestaurantOwner
extends CharacterBody3D

signal interaction_requested(owner: RestaurantOwner)

const OWNER_INTERACTION_LAYER := 1 << 2

@export_category("Identity")
@export var owner_name: String = "Shop Owner":
	set(value):
		owner_name = value
		_queue_visual_refresh()
@export var restaurant_id: StringName = &"restaurant"
@export var restaurant_name: String = "Restaurant"
@export_multiline var greeting_text: String = "Willkommen!"
@export var trade_enabled := true

@export_category("Editable appearance")
@export var skin_color := Color(0.72, 0.48, 0.32, 1.0):
	set(value):
		skin_color = value
		_queue_visual_refresh()
@export var outfit_primary := Color(0.92, 0.92, 0.9, 1.0):
	set(value):
		outfit_primary = value
		_queue_visual_refresh()
@export var outfit_accent := Color(0.25, 0.12, 0.08, 1.0):
	set(value):
		outfit_accent = value
		_queue_visual_refresh()
@export var hair_color := Color(0.08, 0.055, 0.04, 1.0):
	set(value):
		hair_color = value
		_queue_visual_refresh()

@export_category("Editable meshes")
@export var torso_mesh: Mesh:
	set(value):
		torso_mesh = value
		_queue_visual_refresh()
@export var head_mesh: Mesh:
	set(value):
		head_mesh = value
		_queue_visual_refresh()

@export_category("Editor node paths")
@export_node_path("MeshInstance3D") var torso_mesh_path := NodePath("Rig/Torso/Body")
@export_node_path("MeshInstance3D") var head_mesh_path := NodePath("Rig/Head/Face")
@export_node_path("Area3D") var interaction_area_path := NodePath("InteractionArea")
@export_node_path("Label3D") var name_label_path := NodePath("NameLabel")

var _refresh_queued := false


func _ready() -> void:
	_apply_customization()
	if not Engine.is_editor_hint():
		add_to_group("restaurant_owner")
		_setup_interaction_area()


func interact(_interaction_system: Node = null) -> bool:
	interaction_requested.emit(self)
	var hud := get_tree().get_first_node_in_group("money_hud")
	if is_instance_valid(hud) and hud.has_method("show_order_feedback"):
		var message := greeting_text
		if message.is_empty():
			message = "%s – %s" % [owner_name, restaurant_name]
		hud.call("show_order_feedback", message, true)
	return true


func _setup_interaction_area() -> void:
	var area := get_node_or_null(interaction_area_path) as Area3D
	if not is_instance_valid(area):
		return
	area.collision_layer = OWNER_INTERACTION_LAYER
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	# Keep metadata serializable. Storing `self` here makes editor scene saves
	# recursively serialize the complete CharacterBody3D.
	area.set_meta("restaurant_owner", true)
	set_meta("restaurant_owner", true)


func _queue_visual_refresh() -> void:
	if not is_inside_tree() or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_customization")


func _apply_customization() -> void:
	_refresh_queued = false
	if not is_inside_tree():
		return
	var torso := get_node_or_null(torso_mesh_path) as MeshInstance3D
	if is_instance_valid(torso) and is_instance_valid(torso_mesh):
		torso.mesh = torso_mesh
	var head := get_node_or_null(head_mesh_path) as MeshInstance3D
	if is_instance_valid(head) and is_instance_valid(head_mesh):
		head.mesh = head_mesh
	var label := get_node_or_null(name_label_path) as Label3D
	if is_instance_valid(label):
		label.text = owner_name
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
		material.roughness = 0.78
		mesh_instance.material_override = material
	match palette_slot:
		"skin":
			material.albedo_color = skin_color
		"primary":
			material.albedo_color = outfit_primary
		"accent":
			material.albedo_color = outfit_accent
		"hair":
			material.albedo_color = hair_color
