class_name KebabInteractionSystem
extends Node

const InteractableItemScript = preload("res://interactable_item.gd")
const DonerMeatStationScript = preload("res://doner_meat_station.gd")

const INTERACTION_RANGE := 2.8
const INTERACTION_LAYER := 1 << 7
const PREP_ITEM_LAYER := 1 << 8
const CUT_DURATION := 1.0
const OVEN_BAKE_DURATION := 10.0

enum OvenState { IDLE, BAKING, FINISHED }

var player: CharacterBody3D
var camera: Camera3D
var hold_socket: Marker3D
var held_item: Area3D
var held_visual: Node3D
var focused_item: Area3D
var focused_meat: Area3D
var focused_prep: Node3D
var focused_knife_mount: Node3D
var focused_oven: StaticBody3D
var focused_sauce_bin: Area3D
var focus_hit_position := Vector3.ZERO
var focus_hit_normal := Vector3.UP
var held_origin_station: Node3D
var held_origin_transform := Transform3D.IDENTITY
var meat_visual: Node3D
var meat_spawn_point: Marker3D
var cut_progress := 0.0
var cut_anim_time := 0.0
var cut_requires_release := false
var portions_created := 0
var oven: StaticBody3D
var baking_slot: Marker3D
var oven_timer_label: Label3D
var oven_heat_light: OmniLight3D
var oven_heating_elements: Node3D
var oven_slot_visual: Node3D
var oven_state := OvenState.IDLE
var oven_time_left := 0.0
var held_sauce_home: Node3D

var ui_layer: CanvasLayer
var crosshair: Label
var pickup_templates: Dictionary = {}

func setup(owner_player: CharacterBody3D, view_camera: Camera3D, hand_slot: Marker3D) -> void:
	player = owner_player
	camera = view_camera
	hold_socket = hand_slot
	_resolve_hold_socket()
	_setup_input()
	_setup_ui()
	call_deferred("_register_scene_targets")

func _setup_input() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var interact_key := InputEventKey.new()
		interact_key.physical_keycode = KEY_E
		InputMap.action_add_event("interact", interact_key)
	if not InputMap.has_action("drop_item"):
		InputMap.add_action("drop_item")
		var drop_key := InputEventKey.new()
		drop_key.physical_keycode = KEY_Q
		InputMap.action_add_event("drop_item", drop_key)

func _setup_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "InteractionUI"
	ui_layer.layer = 20
	player.add_child(ui_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(root)

	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.add_theme_font_size_override("font_size", 19)
	crosshair.add_theme_color_override("font_color", Color(1, 0.92, 0.72, 0.92))
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-10, -13)
	crosshair.size = Vector2(20, 26)
	root.add_child(crosshair)

func _register_scene_targets() -> void:
	var root := get_tree().current_scene
	_optimize_small_meshes(root.get_node_or_null("Test Ablage/Kebab Theke/Zutaten"))
	var templates_root := root.get_node_or_null("Test Ablage/Kebab Theke/PickupTemplates") as Node3D
	if templates_root:
		_optimize_small_meshes(templates_root)
		pickup_templates = {
			"tomato": templates_root.get_node_or_null("TomatoPortion"),
			"salad": templates_root.get_node_or_null("SaladPortion"),
			"red_cabbage": templates_root.get_node_or_null("RedCabbagePortion"),
			"onion": templates_root.get_node_or_null("OnionPortion"),
			"cucumber": templates_root.get_node_or_null("CucumberPortion"),
			"garlic_sauce_ladle": templates_root.get_node_or_null("GarlicSauceLadle"),
			"cocktail_sauce_ladle": templates_root.get_node_or_null("CocktailSauceLadle"),
			"garlic_sauce": templates_root.get_node_or_null("GarlicSaucePortion"),
			"cocktail_sauce": templates_root.get_node_or_null("CocktailSaucePortion"),
			"lavash": templates_root.get_node_or_null("LavashPiece"),
			"baked_lavash": templates_root.get_node_or_null("ToastedLavashTemplate"),
			"cut_meat": templates_root.get_node_or_null("MeatPortion"),
		}
		templates_root.visible = false
	_register_existing_item(root.get_node_or_null("Test Ablage/Kebab Theke/Zutaten/Salat"), "salad", "Salat")
	_register_existing_item(root.get_node_or_null("Test Ablage/Kebab Theke/Zutaten/Tomaten"), "tomato", "Tomaten")
	_register_existing_item(root.get_node_or_null("Test Ablage/Kebab Theke/Zutaten/Kraut"), "red_cabbage", "Lila Kraut")
	_register_existing_item(root.get_node_or_null("Test Ablage/Kebab Theke/Zutaten/Zwiebeln"), "onion", "Zwiebeln")
	_register_existing_item(root.get_node_or_null("Test Ablage/Kebab Theke/Zutaten/Gurkenstreifen"), "cucumber", "Gurken")
	_register_existing_item(root.get_node_or_null("Test Ablage/Kebab Theke/LavashAblage/Lavash1"), "lavash", "Lavash")
	_register_existing_item(root.get_node_or_null("Test Ablage/Kebab Theke/LavashAblage/Lavash2"), "lavash", "Lavash")
	_register_existing_item(root.get_node_or_null("Test Ablage/Kebab Theke/LavashAblage/Lavash3"), "lavash", "Lavash")
	meat_visual = root.get_node_or_null("DonerSpit/Meat") as Node3D
	meat_spawn_point = root.get_node_or_null("DonerSpit/Catchment/PortionSpawnPoint") as Marker3D
	if meat_visual:
		_register_meat_station(meat_visual)
	var knife_mount := root.get_node_or_null("KnifeWallMount") as StaticBody3D
	var knife_snap := root.get_node_or_null("KnifeWallMount/KnifeSnap") as Marker3D
	var knife_visual := root.get_node_or_null("KnifeWallMount/KnifePreview") as Node3D
	if knife_mount and knife_snap and knife_visual:
		_optimize_small_meshes(knife_visual)
		_register_mounted_knife(knife_mount, knife_snap, knife_visual)
	oven = root.get_node_or_null("KitchenBackShelfCollision/Oven") as StaticBody3D
	if oven:
		baking_slot = oven.get_node_or_null("BakingSlot") as Marker3D
		oven_timer_label = oven.get_node_or_null("TimerLabel3D") as Label3D
		oven_heat_light = oven.get_node_or_null("HeatLight") as OmniLight3D
		oven_heating_elements = oven.get_node_or_null("HeatingElements") as Node3D
		_set_oven_heat(false)

func _optimize_small_meshes(root: Node) -> void:
	if not is_instance_valid(root):
		return
	var root_mesh := root as MeshInstance3D
	if root_mesh and not bool(root_mesh.get_meta("keep_detail_shadows", false)):
		root_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if not bool(mesh.get_meta("keep_detail_shadows", false)):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

func _register_existing_item(visual: Node3D, id: String, label: String) -> void:
	if not visual:
		push_warning("Interaktionsobjekt fehlt: %s" % label)
		return
	var item: Area3D = InteractableItemScript.new()
	item.name = "%sInteraction_%s" % [label, visual.name]
	get_tree().current_scene.add_child(item)
	item.global_transform = visual.global_transform
	_add_box_collider(item, _counter_pickup_size(id))
	item.configure(id, label, visual)
	if id != "lavash":
		item.set_meta("single_portion_source", true)

func _counter_pickup_size(item_id: String) -> Vector3:
	if item_id == "lavash":
		return Vector3(0.8, 0.2, 0.55)
	return Vector3(0.9, 0.36, 0.66)

func _register_meat_station(visual: Node3D) -> void:
	var station: Area3D = DonerMeatStationScript.new()
	station.name = "DonerMeatInteraction"
	get_tree().current_scene.add_child(station)
	station.global_transform = visual.global_transform
	_add_box_collider(station, Vector3(1.55, 2.15, 1.55))

func _register_mounted_knife(mount: StaticBody3D, snap: Marker3D, visual: Node3D) -> void:
	var item: Area3D = InteractableItemScript.new()
	item.name = "KnifePickup"
	mount.add_child(item)
	item.global_transform = snap.global_transform
	_add_box_collider(item, Vector3(0.38, 0.16, 0.9))
	item.configure("knife", "Messer", visual)
	item.set_meta("knife_mount_owner", mount)

func _add_box_collider(parent: Area3D, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	parent.add_child(collision)

func _process(delta: float) -> void:
	if is_instance_valid(meat_visual):
		meat_visual.rotate_y(delta * 0.42)
	_update_oven(delta)
	if not is_instance_valid(player) or not is_instance_valid(camera):
		return
	var first_person: bool = not player.third_person and player.visible and camera.current
	ui_layer.visible = first_person
	if not first_person:
		focused_item = null
		focused_meat = null
		focused_prep = null
		focused_knife_mount = null
		focused_oven = null
		focused_sauce_bin = null
		_reset_cutting()
		return
	_update_focus()
	_update_cutting(delta)

func _update_focus() -> void:
	focused_item = null
	focused_meat = null
	focused_prep = null
	focused_knife_mount = null
	focused_oven = null
	focused_sauce_bin = null
	focus_hit_normal = Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * INTERACTION_RANGE, INTERACTION_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	focus_hit_position = hit["position"]
	focus_hit_normal = (hit.get("normal", Vector3.UP) as Vector3).normalized()
	var collider: Object = hit.get("collider")
	if collider is Area3D and collider.has_meta("sauce_ladle_id"):
		focused_sauce_bin = collider
	elif collider is Area3D and collider.has_meta("interactable") and collider.available and not held_item:
		focused_item = collider
	elif collider is Area3D and collider.has_meta("doner_meat_station"):
		focused_meat = collider
	elif collider is StaticBody3D and collider.has_meta("oven_interaction"):
		focused_oven = collider
	elif collider is Node3D and (collider.is_in_group("knife_mount") or collider.has_meta("knife_mount")):
		focused_knife_mount = collider
	elif collider is Node3D and (collider.is_in_group("work_surface") or collider.has_meta("work_surface") or collider.is_in_group("prep_surface") or collider.has_meta("assembly_station")):
		focused_prep = collider

func _unhandled_input(event: InputEvent) -> void:
	if not player or player.third_person or not camera.current:
		return
	if event.is_action_pressed("interact"):
		if focused_knife_mount and held_item and held_item.item_id == "knife":
			_place_knife_on_mount(focused_knife_mount)
		elif focused_oven:
			_interact_with_oven()
		elif focused_sauce_bin:
			_interact_with_sauce_bin(focused_sauce_bin)
		elif focused_prep and held_item:
			if _is_sauce_ladle(held_item.item_id):
				_apply_sauce_to_prep(focused_prep, focus_hit_position, focus_hit_normal)
			elif held_item.item_id != "knife":
				_place_held_on_prep(focused_prep, focus_hit_position, focus_hit_normal)
		elif focused_item and not held_item:
			_pickup(focused_item)
		elif held_item:
			_return_held()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop_item") and held_item:
		_return_held()
		get_viewport().set_input_as_handled()

func _pickup(target: Area3D) -> void:
	if held_item or not is_instance_valid(target) or target != focused_item or not target.available:
		return
	if target.has_meta("single_portion_source"):
		_pickup_single_portion(target)
		return
	var placed_visual := target.source_visual as Node3D
	held_origin_station = null
	if target.has_meta("prep_station"):
		held_origin_station = target.get_meta("prep_station") as Node3D
	if is_instance_valid(held_origin_station):
		held_origin_transform = target.global_transform
		if held_origin_station.has_method("remove_item"):
			held_origin_station.call("remove_item", target)
		else:
			target.remove_meta("prep_station")
	else:
		held_origin_transform = Transform3D.IDENTITY
	held_item = target
	held_item.pickup()
	held_visual = placed_visual if is_instance_valid(held_origin_station) and is_instance_valid(placed_visual) else _duplicate_pickup_template(target.item_id)
	if not is_instance_valid(held_visual):
		if target.item_id != "knife":
			_return_held()
			return
		held_visual = Node3D.new()
		_create_item_model(held_visual, target.item_id, true)
	held_visual.name = "Held_%s" % target.item_id
	if not _attach_held_visual(held_visual):
		_return_held()

func _pickup_single_portion(source: Area3D) -> void:
	var portion_visual := _duplicate_pickup_template(source.item_id)
	if not is_instance_valid(portion_visual):
		return
	var portion: Area3D = InteractableItemScript.new()
	portion.name = "HeldPortion_%s" % source.item_id
	get_tree().current_scene.add_child(portion)
	portion.global_transform = source.global_transform
	_add_box_collider(portion, _item_collision_size(source.item_id))
	portion.configure(source.item_id, source.display_name, null, true)
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	held_item = portion
	held_item.pickup()
	held_visual = portion_visual
	held_visual.name = "Held_%s" % source.item_id
	if not _attach_held_visual(held_visual):
		_return_held()


func _is_sauce_ladle(item_id: String) -> bool:
	return item_id == "garlic_sauce_ladle" or item_id == "cocktail_sauce_ladle"


func _interact_with_sauce_bin(bin: Area3D) -> void:
	if not is_instance_valid(bin):
		return
	var ladle_id := String(bin.get_meta("sauce_ladle_id", ""))
	if held_item:
		if held_item.item_id == ladle_id:
			_return_sauce_ladle()
		return
	_pickup_sauce_ladle(bin, ladle_id)


func _pickup_sauce_ladle(bin: Area3D, ladle_id: String) -> void:
	if held_item or not _is_sauce_ladle(ladle_id):
		return
	var visual := _duplicate_pickup_template(ladle_id)
	var home := bin.get_parent().get_node_or_null("SauceLadle") as Node3D
	if not is_instance_valid(visual) or not is_instance_valid(home):
		if is_instance_valid(visual):
			visual.queue_free()
		return
	var item: Area3D = InteractableItemScript.new()
	item.name = "Held_%s" % ladle_id
	get_tree().current_scene.add_child(item)
	item.global_transform = bin.global_transform
	_add_box_collider(item, _item_collision_size(ladle_id))
	item.configure(ladle_id, String(bin.get_meta("sauce_label", "Soßenkelle")), null, true)
	item.pickup()
	held_item = item
	held_visual = visual
	held_sauce_home = home
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	held_sauce_home.visible = false
	if not _attach_held_visual(held_visual):
		_return_sauce_ladle()


func _apply_sauce_to_prep(station: Node3D, hit_position: Vector3, hit_normal: Vector3) -> void:
	if not is_instance_valid(held_item) or not _is_sauce_ladle(held_item.item_id):
		return
	var portion_id := "garlic_sauce" if held_item.item_id == "garlic_sauce_ladle" else "cocktail_sauce"
	var portion_label := "Knoblauchsoße" if portion_id == "garlic_sauce" else "Cocktailsoße"
	var portion_visual := _duplicate_pickup_template(portion_id)
	if not is_instance_valid(portion_visual):
		return
	var portion: Area3D = InteractableItemScript.new()
	portion.name = "%sPortion" % portion_id.to_pascal_case()
	get_tree().current_scene.add_child(portion)
	portion.global_transform = station.global_transform
	_add_box_collider(portion, _item_collision_size(portion_id))
	portion.configure(portion_id, portion_label, portion_visual)
	var surface_normal := hit_normal.normalized() if not hit_normal.is_zero_approx() else Vector3.UP
	var drop_position := hit_position + surface_normal * (_visual_height(portion_visual, portion_id) * 0.5)
	var drop_rotation := Vector3(0.0, randf_range(-PI, PI), 0.0)
	portion.reparent(station, true)
	portion.global_position = drop_position
	portion.global_rotation = drop_rotation
	station.add_child(portion_visual)
	portion_visual.global_position = drop_position
	portion_visual.global_rotation = drop_rotation
	portion_visual.scale = Vector3.ONE
	portion_visual.visible = true
	portion.source_visual = portion_visual
	portion.consumed_on_pickup = false
	portion.available = true
	portion.collision_layer = INTERACTION_LAYER | PREP_ITEM_LAYER
	portion.collision_mask = 0
	if station.has_method("place_item"):
		station.call("place_item", portion, portion_id, hit_position)
	else:
		portion.set_meta("prep_station", station)
		portion.set_meta("ingredient_id", portion_id)
	portion.original_transform = portion.global_transform
	_return_sauce_ladle()


func _return_sauce_ladle() -> void:
	if is_instance_valid(held_visual):
		held_visual.queue_free()
	if is_instance_valid(held_item):
		held_item.queue_free()
	if is_instance_valid(held_sauce_home):
		held_sauce_home.visible = true
	held_item = null
	held_visual = null
	held_sauce_home = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	_reset_cutting()

func _resolve_hold_socket() -> Marker3D:
	if is_instance_valid(hold_socket):
		return hold_socket
	if is_instance_valid(camera):
		hold_socket = camera.get_node_or_null("ArmsHolder/HandAttachmentPoint") as Marker3D
		if not is_instance_valid(hold_socket):
			hold_socket = Marker3D.new()
			hold_socket.name = "RuntimeHandAttachmentPoint"
			camera.add_child(hold_socket)
			hold_socket.position = Vector3(0.37, -0.28, -0.72)
			hold_socket.rotation = Vector3(-0.08, 0.16, 0.1)
	return hold_socket

func _attach_held_visual(visual: Node3D) -> bool:
	var socket := _resolve_hold_socket()
	if not is_instance_valid(socket) or not is_instance_valid(visual):
		return false
	if visual.get_parent() == null:
		socket.add_child(visual)
	elif visual.get_parent() != socket:
		visual.reparent(socket, false)
	visual.visible = true
	visual.position = Vector3.ZERO
	visual.rotation = Vector3.ZERO
	visual.scale = Vector3.ONE * 0.85
	return true

func _duplicate_pickup_template(item_id: String) -> Node3D:
	var template := pickup_templates.get(item_id) as Node3D
	if not is_instance_valid(template):
		return null
	var copy := template.duplicate() as Node3D
	if not is_instance_valid(copy) or copy == template:
		return null
	copy.visible = true
	for mesh in copy.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return copy

func _return_held() -> void:
	if not held_item:
		return
	if _is_sauce_ladle(held_item.item_id):
		_return_sauce_ladle()
		return
	var item := held_item
	var origin_station := held_origin_station
	var origin_transform := held_origin_transform
	if is_instance_valid(origin_station) and is_instance_valid(held_visual):
		_place_held_on_prep(origin_station, origin_transform.origin, Vector3.UP, false)
		return
	if is_instance_valid(held_visual):
		held_visual.queue_free()
	item.restore()
	held_item = null
	held_visual = null
	held_sauce_home = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	_reset_cutting()


func _place_held_on_prep(station: Node3D, hit_position: Vector3, hit_normal := Vector3.UP, offset_from_surface := true) -> void:
	if not held_item or not is_instance_valid(held_visual) or not is_instance_valid(station):
		return
	var previous_visual := held_item.source_visual as Node3D
	if is_instance_valid(previous_visual) and previous_visual != held_visual and previous_visual.get_parent() == held_item:
		previous_visual.queue_free()

	var surface_normal := hit_normal.normalized() if not hit_normal.is_zero_approx() else Vector3.UP
	var drop_position := hit_position
	if offset_from_surface:
		drop_position += surface_normal * (_visual_height(held_visual, held_item.item_id) * 0.5)
	var drop_rotation := Vector3(0.0, randf_range(-PI, PI), 0.0)

	if held_item.get_parent() != station:
		held_item.reparent(station, true)
	held_item.global_position = drop_position
	held_item.global_rotation = drop_rotation
	if held_visual.get_parent() != station:
		held_visual.reparent(station, true)
	held_visual.global_position = drop_position
	held_visual.global_rotation = drop_rotation
	held_visual.visible = true
	held_item.source_visual = held_visual

	for child in held_item.find_children("*", "CollisionShape3D", true, false):
		var shape := child as CollisionShape3D
		if shape:
			shape.disabled = false
			var box_shape := shape.shape as BoxShape3D
			if box_shape:
				box_shape.size = _item_collision_size(held_item.item_id)

	var reset_metadata: Array[StringName] = [&"origin_position", &"spawn_point", &"return_to_origin", &"return_timer"]
	for metadata_key in reset_metadata:
		if held_item.has_meta(metadata_key):
			held_item.remove_meta(metadata_key)
	for child in held_item.find_children("*", "Timer", true, false):
		var return_timer := child as Timer
		if return_timer:
			return_timer.stop()

	_freeze_item_physics(held_item)
	held_item.consumed_on_pickup = false
	held_item.available = true
	held_item.collision_layer = INTERACTION_LAYER | PREP_ITEM_LAYER
	held_item.collision_mask = 0
	if station.has_method("place_item"):
		station.call("place_item", held_item, held_item.item_id, hit_position)
	else:
		held_item.set_meta("prep_station", station)
		held_item.set_meta("ingredient_id", held_item.item_id)
	held_item.original_transform = held_item.global_transform

	held_item = null
	held_visual = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	_reset_cutting()


func _visual_height(visual: Node3D, fallback_item_id: String) -> float:
	var bounds := AABB()
	var has_bounds := false
	var root_mesh := visual as MeshInstance3D
	if root_mesh and root_mesh.mesh:
		bounds = root_mesh.get_aabb()
		has_bounds = true
	var visual_inverse := visual.global_transform.affine_inverse()
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if not mesh_instance or not mesh_instance.mesh:
			continue
		var mesh_bounds: AABB = (visual_inverse * mesh_instance.global_transform) * mesh_instance.get_aabb()
		bounds = bounds.merge(mesh_bounds) if has_bounds else mesh_bounds
		has_bounds = true
	if not has_bounds:
		return _item_collision_size(fallback_item_id).y
	return maxf(0.01, bounds.size.y * absf(visual.global_basis.get_scale().y))


func _freeze_item_physics(item: Node) -> void:
	var rigid_item := item as RigidBody3D
	if rigid_item:
		rigid_item.freeze = true
		rigid_item.linear_velocity = Vector3.ZERO
		rigid_item.angular_velocity = Vector3.ZERO


func _place_knife_on_mount(mount: Node3D) -> void:
	if not held_item or held_item.item_id != "knife" or not is_instance_valid(mount):
		return
	var snap := mount.get_node_or_null("KnifeSnap") as Marker3D
	if not snap:
		return
	if held_item.get_parent() != mount:
		held_item.reparent(mount, true)
	if is_instance_valid(held_item.source_visual):
		held_item.source_visual.visible = true
	_freeze_item_physics(held_item)
	held_item.available = true
	held_item.collision_layer = INTERACTION_LAYER
	held_item.collision_mask = 0
	held_item.global_transform = snap.global_transform
	held_item.original_transform = held_item.global_transform
	held_item.set_meta("knife_mount_owner", mount)
	if is_instance_valid(held_visual):
		held_visual.queue_free()
	held_item = null
	held_visual = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	_reset_cutting()


func _item_collision_size(item_id: String) -> Vector3:
	match item_id:
		"knife":
			return Vector3(0.38, 0.16, 0.9)
		"garlic_sauce_ladle", "cocktail_sauce_ladle":
			return Vector3(0.7, 0.2, 0.34)
		"garlic_sauce", "cocktail_sauce":
			return Vector3(0.4, 0.08, 0.34)
		"lavash":
			return Vector3(0.55, 0.2, 0.4)
		"baked_lavash":
			return Vector3(0.57, 0.2, 0.42)
		"cut_meat":
			return Vector3(0.42, 0.22, 0.42)
		_:
			return Vector3(0.5, 0.3, 0.5)

func _interact_with_oven() -> void:
	match oven_state:
		OvenState.IDLE:
			if held_item and held_item.item_id == "lavash":
				_insert_lavash_into_oven()
		OvenState.BAKING:
			return
		OvenState.FINISHED:
			if held_item == null:
				_take_baked_lavash()

func _insert_lavash_into_oven() -> void:
	if not is_instance_valid(baking_slot) or not is_instance_valid(held_item) or not is_instance_valid(held_visual):
		return
	var raw_item := held_item
	oven_slot_visual = held_visual
	oven_slot_visual.reparent(baking_slot, false)
	oven_slot_visual.transform = Transform3D.IDENTITY
	oven_slot_visual.scale = Vector3.ONE
	oven_slot_visual.visible = true
	held_item = null
	held_visual = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	raw_item.queue_free()
	oven_state = OvenState.BAKING
	oven_time_left = OVEN_BAKE_DURATION
	_set_oven_heat(true)
	_update_oven_label()

func _update_oven(delta: float) -> void:
	if oven_state != OvenState.BAKING:
		return
	oven_time_left = maxf(0.0, oven_time_left - delta)
	if oven_time_left <= 0.0:
		_finish_oven_bake()
	else:
		_update_oven_label()

func _update_oven_label() -> void:
	if is_instance_valid(oven_timer_label):
		oven_timer_label.text = "00:%02d" % int(ceili(oven_time_left))

func _finish_oven_bake() -> void:
	if is_instance_valid(oven_slot_visual):
		oven_slot_visual.queue_free()
	oven_slot_visual = _duplicate_pickup_template("baked_lavash")
	if is_instance_valid(oven_slot_visual) and is_instance_valid(baking_slot):
		oven_slot_visual.name = "BakedLavash"
		baking_slot.add_child(oven_slot_visual)
		oven_slot_visual.transform = Transform3D.IDENTITY
		oven_slot_visual.scale = Vector3.ONE
	oven_state = OvenState.FINISHED
	oven_time_left = 0.0
	_set_oven_heat(false)
	if is_instance_valid(oven_timer_label):
		oven_timer_label.text = "Fertig!"

func _take_baked_lavash() -> void:
	if held_item != null or not is_instance_valid(oven_slot_visual):
		return
	var baked_item: Area3D = InteractableItemScript.new()
	baked_item.name = "BakedLavashItem"
	get_tree().current_scene.add_child(baked_item)
	baked_item.global_transform = baking_slot.global_transform
	_add_box_collider(baked_item, _item_collision_size("baked_lavash"))
	baked_item.configure("baked_lavash", "Gebackenes Lavash", null, true)
	baked_item.pickup()
	held_item = baked_item
	held_visual = oven_slot_visual
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	if not _attach_held_visual(held_visual):
		held_visual.reparent(baking_slot, false)
		held_visual.transform = Transform3D.IDENTITY
		held_item.queue_free()
		held_item = null
		held_visual = null
		return
	oven_slot_visual = null
	oven_state = OvenState.IDLE
	if is_instance_valid(oven_timer_label):
		oven_timer_label.text = "Bereit"

func _set_oven_heat(active: bool) -> void:
	if is_instance_valid(oven_heating_elements):
		oven_heating_elements.visible = active
	if is_instance_valid(oven_heat_light):
		oven_heat_light.visible = active

func _update_cutting(delta: float) -> void:
	var can_cut: bool = focused_meat != null and held_item != null and held_item.item_id == "knife"
	var cutting_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not cutting_pressed:
		cut_requires_release = false
	if not can_cut or not cutting_pressed or cut_requires_release:
		if held_visual:
			held_visual.rotation = held_visual.rotation.lerp(Vector3.ZERO, 1.0 - exp(-delta * 14.0))
			held_visual.position = held_visual.position.lerp(Vector3.ZERO, 1.0 - exp(-delta * 14.0))
		if not cut_requires_release:
			cut_progress = maxf(0.0, cut_progress - delta * 0.55)
		return
	cut_progress += delta
	cut_anim_time += delta
	if held_visual:
		var stroke := sin(cut_anim_time * 24.0)
		held_visual.rotation = Vector3(0.45 + stroke * 0.22, 0.05, -0.55 + stroke * 0.32)
		held_visual.position = Vector3(0, stroke * 0.055, 0)
	if cut_progress >= CUT_DURATION:
		_spawn_meat_portion()
		cut_requires_release = true
		cut_progress = 0.0
		cut_anim_time = 0.0

func _reset_cutting() -> void:
	cut_progress = 0.0
	cut_anim_time = 0.0
	cut_requires_release = false
	if held_visual:
		held_visual.rotation = Vector3.ZERO
		held_visual.position = Vector3.ZERO

func _spawn_meat_portion() -> void:
	var visual := _duplicate_pickup_template("cut_meat")
	if not is_instance_valid(visual) or not is_instance_valid(meat_spawn_point):
		if is_instance_valid(visual):
			visual.queue_free()
		return
	portions_created += 1
	var item: Area3D = InteractableItemScript.new()
	item.name = "CutMeatPortion_%02d" % portions_created
	get_tree().current_scene.add_child(item)
	var row := (portions_created - 1) % 4
	var stack := floori(float(portions_created - 1) / 4.0)
	item.global_position = meat_spawn_point.global_position + Vector3((row - 1.5) * 0.24, stack * 0.08, 0)
	visual.name = "FreshCutMeat"
	item.add_child(visual)
	visual.transform = Transform3D.IDENTITY
	_add_box_collider(item, Vector3(0.42, 0.22, 0.42))
	item.configure("cut_meat", "geschnittenes Dönerfleisch", visual)

func _create_item_model(parent: Node3D, id: String, held: bool) -> void:
	match id:
		"knife":
			_box(parent, Vector3(0, 0, 0.18), Vector3(0.1, 0.1, 0.38), Color("4b2c20"))
			_box(parent, Vector3(0, 0, -0.2), Vector3(0.16, 0.035, 0.45), Color("d5d8d8"), 0.8)
			_box(parent, Vector3(0, 0, 0), Vector3(0.2, 0.06, 0.05), Color("ba9b68"), 0.6)
	if held:
		parent.scale = Vector3.ONE * (0.85 if id != "knife" else 1.0)
	for mesh in parent.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

func _box(parent: Node3D, new_position: Vector3, size: Vector3, color: Color, metallic := 0.0) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	material.metallic = metallic
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = new_position
	parent.add_child(instance)
	return instance
