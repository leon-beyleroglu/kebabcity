class_name KebabInteractionSystem
extends Node

const InteractableItemScript = preload("res://interactable_item.gd")
const DonerMeatStationScript = preload("res://doner_meat_station.gd")

const INTERACTION_RANGE := 3.2
const INTERACTION_LAYER := 1 << 7
const TABLE_ITEM_LAYER := 1 << 1
const PREP_ITEM_LAYER := 1 << 8
const CUT_DURATION := 1.0
const OVEN_BAKE_DURATION := 10.0
const OVEN_CAPACITY := 3
const DURUM_INGREDIENT_IDS := ["tomato", "salad", "red_cabbage", "onion", "cucumber", "cut_meat", "garlic_sauce", "cocktail_sauce"]

enum OvenSlotState { EMPTY, BAKING, FINISHED }

var player: CharacterBody3D
var camera: Camera3D
var interaction_ray: RayCast3D
var hold_socket: Marker3D
var right_hand_socket: Marker3D
var left_hand_socket: Marker3D
var palm_socket: Marker3D
var ladle_socket: Marker3D
var bread_socket: Marker3D
var right_hand_viewmodel: MeshInstance3D
var right_hand_rest_transform := Transform3D.IDENTITY
var hand_sockets_ready := false
var ladle_scoop_tween: Tween
var held_item: Area3D
var held_item_id := ""
var held_visual: Node3D
var focused_item: Area3D
var focused_container: Area3D
var focused_meat: Area3D
var focused_prep: Node3D
var focused_knife_mount: Node3D
var focused_oven: StaticBody3D
var focused_sauce_bin: Area3D
var focused_trash_can: StaticBody3D
var focused_durum_assembly: Area3D
var focused_customer: CharacterBody3D
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
var baking_slots: Array[Marker3D] = []
var oven_timer_label: Label3D
var oven_heat_light: OmniLight3D
var oven_heating_elements: Node3D
var oven_slot_visuals: Array[Node3D] = []
var oven_slot_states: Array[int] = []
var oven_slot_times: Array[float] = []
var current_lavash_count := 0
var held_sauce_home: Node3D

var ui_layer: CanvasLayer
var crosshair: Label
var pickup_templates: Dictionary = {}

func setup(owner_player: CharacterBody3D, view_camera: Camera3D, hand_slot: Marker3D) -> void:
	player = owner_player
	camera = view_camera
	interaction_ray = camera.get_node_or_null("InteractionRayCast") as RayCast3D
	if is_instance_valid(interaction_ray):
		interaction_ray.collision_mask |= TABLE_ITEM_LAYER
		interaction_ray.collide_with_areas = true
	hold_socket = hand_slot
	_resolve_hand_sockets()
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
	if not InputMap.has_action("mouse_right"):
		InputMap.add_action("mouse_right")
		var roll_button := InputEventMouseButton.new()
		roll_button.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("mouse_right", roll_button)

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
			"durum_assembly": templates_root.get_node_or_null("DurumAssembly"),
			"finished_durum": templates_root.get_node_or_null("FinishedDurum"),
			"cut_meat": templates_root.get_node_or_null("MeatPortion"),
		}
		templates_root.visible = false
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
		baking_slots.clear()
		oven_slot_visuals.clear()
		oven_slot_states.clear()
		oven_slot_times.clear()
		current_lavash_count = 0
		for slot_index in OVEN_CAPACITY:
			var slot := oven.get_node_or_null("BakingSlot_%d" % slot_index) as Marker3D
			if slot:
				baking_slots.append(slot)
				oven_slot_visuals.append(null)
				oven_slot_states.append(OvenSlotState.EMPTY)
				oven_slot_times.append(0.0)
		oven_timer_label = oven.get_node_or_null("TimerLabel3D") as Label3D
		oven_heat_light = oven.get_node_or_null("HeatLight") as OmniLight3D
		oven_heating_elements = oven.get_node_or_null("HeatingElements") as Node3D
		_set_oven_heat(false)
		_update_oven_label()

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
	item.set_meta("single_portion_source", true)
	if id == "lavash":
		item.set_meta("infinite_supply", true)

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
		focused_container = null
		focused_meat = null
		focused_prep = null
		focused_knife_mount = null
		focused_oven = null
		focused_sauce_bin = null
		focused_trash_can = null
		focused_durum_assembly = null
		focused_customer = null
		_reset_cutting()
		return
	_update_focus()
	_update_cutting(delta)

func _update_focus() -> void:
	_clear_focus()
	var collider: Object
	if is_instance_valid(interaction_ray):
		interaction_ray.force_raycast_update()
		if not interaction_ray.is_colliding():
			return
		focus_hit_position = interaction_ray.get_collision_point()
		focus_hit_normal = interaction_ray.get_collision_normal().normalized()
		collider = interaction_ray.get_collider()
	else:
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * INTERACTION_RANGE, INTERACTION_LAYER | TABLE_ITEM_LAYER)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return
		focus_hit_position = hit["position"]
		focus_hit_normal = (hit.get("normal", Vector3.UP) as Vector3).normalized()
		collider = hit.get("collider")
	if collider != null:
		_set_focus_from_collider(collider)


func _clear_focus() -> void:
	focused_item = null
	focused_container = null
	focused_meat = null
	focused_prep = null
	focused_knife_mount = null
	focused_oven = null
	focused_sauce_bin = null
	focused_trash_can = null
	focused_durum_assembly = null
	focused_customer = null
	focus_hit_normal = Vector3.UP


func _set_focus_from_collider(collider: Object) -> void:
	if collider is CharacterBody3D and (collider.is_in_group("customer_npc") or collider.has_meta("customer_npc")):
		focused_customer = collider
	elif collider is Area3D and (collider.is_in_group("durum_assembly") or collider.has_meta("durum_assembly")):
		focused_durum_assembly = collider
	elif collider is StaticBody3D and (collider.is_in_group("trash_can") or collider.has_meta("trash_can")):
		focused_trash_can = collider
	elif collider is Area3D and collider.has_meta("sauce_ladle_id"):
		focused_sauce_bin = collider
	elif collider is Area3D and (collider.is_in_group("placed_items") or (collider.has_meta("ingredient_id") and not collider.has_meta("pickup_template"))) and collider.has_meta("interactable") and collider.available and not held_item:
		focused_item = collider
	elif collider is Area3D and collider.has_meta("ingredient_id") and collider.has_meta("pickup_template"):
		focused_container = collider
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
		if not is_instance_valid(interaction_ray):
			return
		interaction_ray.force_raycast_update()
		if not interaction_ray.is_colliding():
			return
		var collider: Object = interaction_ray.get_collider()
		if collider == null:
			return
		handle_interaction(collider, interaction_ray.get_collision_point(), interaction_ray.get_collision_normal())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("mouse_right"):
		if focused_durum_assembly and not held_item and _roll_durum(focused_durum_assembly):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop_item") and held_item:
		_return_held()
		get_viewport().set_input_as_handled()


func handle_interaction(collider: Object, hit_position: Vector3, hit_normal: Vector3) -> void:
	_clear_focus()
	focus_hit_position = hit_position
	focus_hit_normal = hit_normal.normalized()
	_set_focus_from_collider(collider)
	if focused_customer:
		_interact_with_customer(focused_customer)
	elif focused_trash_can:
		_discard_held_item()
	elif focused_durum_assembly and held_item:
		if _is_sauce_portion(held_item.item_id):
			_drop_held_sauce(focused_durum_assembly, focus_hit_position, true)
		elif _is_sauce_ladle(held_item.item_id):
			_add_sauce_to_durum(focused_durum_assembly, focus_hit_position)
		elif _is_durum_ingredient(held_item.item_id):
			_add_held_ingredient_to_durum(focused_durum_assembly)
	elif focused_knife_mount and held_item and held_item.item_id == "knife":
		_place_knife_on_mount(focused_knife_mount)
	elif focused_oven:
		_interact_with_oven()
	elif focused_sauce_bin:
		_interact_with_sauce_bin(focused_sauce_bin)
	elif focused_container and not held_item:
		interact_with_container(focused_container)
	elif focused_prep and held_item:
		if not _can_place_on_station(focused_prep, focus_hit_normal):
			return
		if held_item.item_id == "baked_lavash":
			_create_durum_assembly(focused_prep, focus_hit_position, focus_hit_normal)
		elif _is_sauce_portion(held_item.item_id):
			_drop_held_sauce(focused_prep, focus_hit_position, false)
		elif _is_sauce_ladle(held_item.item_id):
			return
		elif held_item.item_id != "knife":
			_place_held_on_prep(focused_prep, focus_hit_position, focus_hit_normal)
	elif focused_item and not held_item:
		pick_up(focused_item)
	elif held_item:
		_return_held()

func pick_up(item: Node3D) -> void:
	var target := item as Area3D
	if held_item or not is_instance_valid(target) or target != focused_item or not target.available:
		return
	if target.is_in_group("placed_items") or (target.has_meta("ingredient_id") and not target.has_meta("pickup_template")):
		pickup_placed_item(target)
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
	held_item_id = target.item_id
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


func pickup_placed_item(target_item: Node3D) -> void:
	var hit_item := target_item as Area3D
	if held_item != null or not is_instance_valid(hit_item):
		return
	if not is_instance_valid(hold_socket):
		return
	var origin_station := hit_item.get_meta("prep_station", null) as Node3D
	held_origin_station = origin_station
	held_origin_transform = hit_item.global_transform
	if is_instance_valid(origin_station) and origin_station.has_method("remove_item"):
		origin_station.call("remove_item", hit_item)

	var target_visual := hit_item.source_visual as Node3D
	if is_instance_valid(target_visual) and target_visual.get_parent() != hit_item:
		target_visual.reparent(hit_item)
		target_visual.transform = Transform3D.IDENTITY

	hit_item.reparent(hold_socket)
	hit_item.top_level = false
	hit_item.transform = Transform3D.IDENTITY
	hit_item.scale = Vector3.ONE
	_set_collisions_enabled(hit_item, false)
	hit_item.collision_layer = 0
	hit_item.available = false
	hit_item.visible = true
	if is_instance_valid(target_visual):
		target_visual.visible = true

	held_item = hit_item
	held_item_id = String(hit_item.get_meta("item_id", hit_item.item_id))
	held_visual = target_visual if is_instance_valid(target_visual) else hit_item
	held_sauce_home = null
	_reset_cutting()

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
	held_item_id = portion.item_id
	held_item.pickup()
	held_visual = portion_visual
	held_visual.name = "Held_%s" % source.item_id
	if not _attach_held_visual(held_visual):
		_return_held()


func interact_with_container(container: Node3D) -> void:
	if is_instance_valid(held_item) or not is_instance_valid(container):
		return
	if not container.has_meta("pickup_template"):
		return
	var item_id := String(container.get_meta("ingredient_id", ""))
	if item_id.is_empty():
		return
	var template: Node3D
	var template_path := container.get_meta("pickup_template", NodePath()) as NodePath
	if not template_path.is_empty():
		template = container.get_node_or_null(template_path) as Node3D
	if not is_instance_valid(template):
		template = pickup_templates.get(item_id) as Node3D
	if not is_instance_valid(template):
		return
	var new_visual := template.duplicate() as Node3D
	if not is_instance_valid(new_visual) or new_visual == template:
		return
	_normalize_pickup_copy(new_visual)
	new_visual.visible = true
	var new_item: Area3D = InteractableItemScript.new()
	new_item.name = "HeldPortion_%s" % item_id
	get_tree().current_scene.add_child(new_item)
	new_item.global_transform = Transform3D(Basis.IDENTITY, container.global_position)
	_add_box_collider(new_item, _item_collision_size(item_id))
	new_item.configure(item_id, String(container.get_meta("ingredient_label", item_id)), null, true)
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	held_item = new_item
	held_item_id = new_item.item_id
	held_item.pickup()
	held_visual = new_visual
	held_visual.name = "Held_%s" % item_id
	if not _attach_held_visual(held_visual):
		_return_held()


func _is_sauce_ladle(item_id: String) -> bool:
	return item_id == "garlic_sauce_ladle" or item_id == "cocktail_sauce_ladle"


func _is_sauce_portion(item_id: String) -> bool:
	return item_id == "garlic_sauce" or item_id == "cocktail_sauce"


func _drop_held_sauce(target_node: Node3D, hit_point: Vector3, on_bread: bool) -> void:
	if not is_instance_valid(held_item) or not is_instance_valid(target_node):
		return
	if not _is_sauce_portion(held_item.item_id):
		return

	var item := held_item
	var item_id: String = item.item_id
	var visual := held_visual
	if is_instance_valid(visual) and visual != item:
		if visual.get_parent() == null:
			item.add_child(visual)
		elif visual.get_parent() != item:
			visual.reparent(item)
		visual.transform = Transform3D.IDENTITY
		visual.scale = Vector3.ONE
		visual.visible = true
		item.source_visual = visual

	var drop_parent := target_node
	if not on_bread and target_node.has_method("get_placed_items_container"):
		drop_parent = target_node.call("get_placed_items_container") as Node3D
	if not is_instance_valid(drop_parent):
		return

	item.reparent(drop_parent)
	if on_bread:
		var local_position := target_node.to_local(hit_point)
		local_position.y = 0.04
		item.position = local_position
	else:
		item.global_position = _snapped_station_position(target_node, hit_point, Vector3.UP)
	item.rotation = Vector3.ZERO
	item.scale = Vector3.ONE
	item.available = true
	item.consumed_on_pickup = false
	item.collision_layer = TABLE_ITEM_LAYER
	item.collision_mask = 0
	item.set_meta("item_id", item_id)
	item.set_meta("ingredient_id", item_id)
	item.set_meta("prep_station", target_node)
	item.set_meta("placed_on_assembly_station", not on_bread)
	item.add_to_group("placed_items")
	_set_collisions_enabled(item, true)
	for collision_node in item.find_children("*", "CollisionShape3D", true, false):
		var collision_shape := collision_node as CollisionShape3D
		var box_shape := collision_shape.shape as BoxShape3D
		if is_instance_valid(box_shape):
			var enlarged_size := box_shape.size
			enlarged_size.y = maxf(enlarged_size.y, 0.24)
			box_shape.size = enlarged_size

	if on_bread:
		var ingredients: Array = target_node.get_meta("ingredients", [])
		ingredients.append(item_id)
		target_node.set_meta("ingredients", ingredients)
		target_node.set_meta("placed_count", int(target_node.get_meta("placed_count", 0)) + 1)
	elif target_node.has_method("get_placed_items_container") and target_node.has_method("_register_item"):
		target_node.call("_register_item", item, item_id)
	elif target_node.has_method("place_item"):
		target_node.call("place_item", item, item_id, hit_point)
		item.collision_layer = TABLE_ITEM_LAYER

	item.original_transform = item.global_transform
	held_item = null
	held_item_id = ""
	held_visual = null
	held_sauce_home = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	_reset_cutting()


func _is_durum_ingredient(item_id: String) -> bool:
	return item_id in DURUM_INGREDIENT_IDS


func _can_place_on_station(station: Node3D, hit_normal: Vector3) -> bool:
	if not is_instance_valid(station) or hit_normal.normalized().y <= 0.9:
		return false
	if station.has_method("can_place_item"):
		return bool(station.call("can_place_item", hit_normal))
	return true


func _snapped_station_position(station: Node3D, hit_position: Vector3, hit_normal: Vector3) -> Vector3:
	if station.has_method("snap_to_table_top"):
		return station.call("snap_to_table_top", hit_position, hit_normal) as Vector3
	return hit_position


func _create_durum_assembly(station: Node3D, hit_position: Vector3, hit_normal: Vector3) -> void:
	if not is_instance_valid(station) or not is_instance_valid(held_item) or held_item.item_id != "baked_lavash":
		return
	if not _can_place_on_station(station, hit_normal):
		return
	var assembly := _duplicate_pickup_template("durum_assembly") as Area3D
	if not is_instance_valid(assembly):
		return
	var baked_item := held_item
	var baked_visual := held_visual
	var source_visual := baked_item.source_visual as Node3D
	station.add_child(assembly)
	assembly.name = "DurumAssembly"
	assembly.global_transform = Transform3D(Basis.IDENTITY, _snapped_station_position(station, hit_position, hit_normal))
	assembly.collision_layer = INTERACTION_LAYER
	assembly.collision_mask = 0
	assembly.monitoring = false
	assembly.monitorable = true
	assembly.set_meta("durum_assembly", true)
	assembly.set_meta("ingredients", [])
	assembly.set_meta("item_id", "durum_assembly")
	if station.has_method("get_placed_items_container"):
		if station.call("place_item", assembly, "durum_assembly", hit_position, hit_normal) == null:
			assembly.queue_free()
			return
	if is_instance_valid(baked_visual):
		baked_visual.queue_free()
	if is_instance_valid(source_visual) and source_visual != baked_visual:
		source_visual.queue_free()
	baked_item.queue_free()
	held_item = null
	held_item_id = ""
	held_visual = null
	held_sauce_home = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	_reset_cutting()


func _stack_durum_visual(assembly: Area3D, item_id: String, visual: Node3D) -> bool:
	if not is_instance_valid(assembly) or not is_instance_valid(visual):
		return false
	var socket := assembly.get_node_or_null("IngredientSocket") as Node3D
	if not is_instance_valid(socket):
		return false
	var ingredients: Array = assembly.get_meta("ingredients", [])
	var stack_index := ingredients.size()
	if visual.get_parent() == null:
		socket.add_child(visual)
	elif visual.get_parent() != socket:
		visual.reparent(socket, false)
	visual.name = "Ingredient_%02d_%s" % [stack_index + 1, item_id.to_pascal_case()]
	visual.position = Vector3(randf_range(-0.04, 0.04), stack_index * 0.018, randf_range(-0.04, 0.04))
	visual.rotation = Vector3(randf_range(-0.08, 0.08), randf_range(-PI, PI), randf_range(-0.08, 0.08))
	visual.scale = Vector3.ONE
	visual.visible = true
	ingredients.append(item_id)
	assembly.set_meta("ingredients", ingredients)
	return true


func _add_held_ingredient_to_durum(lavash_node: Area3D) -> void:
	if not is_instance_valid(held_item) or not is_instance_valid(held_visual) or not _is_durum_ingredient(held_item.item_id):
		return

	var item := held_item
	var visual := held_visual
	var item_id: String = item.item_id
	var lavash_length := 0.7
	var y_offset := 0.025
	match item_id:
		"cut_meat":
			y_offset = 0.01
		"garlic_sauce", "cocktail_sauce":
			y_offset = 0.04

	var local_pos := Vector3(
		randf_range(-lavash_length * 0.35, lavash_length * 0.35),
		y_offset,
		randf_range(-0.03, 0.03)
	)

	if visual != item:
		if visual.get_parent() == null:
			item.add_child(visual)
		elif visual.get_parent() != item:
			visual.reparent(item)
		visual.transform = Transform3D.IDENTITY
		visual.scale = Vector3.ONE
		visual.visible = true
		item.source_visual = visual

	item.reparent(lavash_node)
	item.position = local_pos
	item.rotation = Vector3(
		0.0,
		randf_range(-PI, PI),
		randf_range(-0.1, 0.1)
	)
	item.scale = Vector3.ONE
	var placed_count := int(lavash_node.get_meta("placed_count", 0))
	item.name = "Ingredient_%02d_%s" % [placed_count + 1, item_id.to_pascal_case()]
	item.available = false
	item.collision_layer = 0
	item.collision_mask = 0
	_set_collisions_enabled(item, false)

	var ingredients: Array = lavash_node.get_meta("ingredients", [])
	ingredients.append(item_id)
	lavash_node.set_meta("ingredients", ingredients)
	lavash_node.set_meta("placed_count", placed_count + 1)

	held_item = null
	held_item_id = ""
	held_visual = null
	held_sauce_home = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	_reset_cutting()


func _add_sauce_to_durum(assembly: Area3D, hit_position: Vector3) -> void:
	if not is_instance_valid(held_item) or not _is_sauce_ladle(held_item.item_id):
		return
	if not bool(held_item.get_meta("is_filled", false)):
		return

	var portion_id := "garlic_sauce" if held_item.item_id == "garlic_sauce_ladle" else "cocktail_sauce"
	var portion_visual := _duplicate_pickup_template(portion_id)
	if not is_instance_valid(portion_visual):
		return
	if not is_instance_valid(assembly):
		portion_visual.queue_free()
		return

	var ingredients: Array = assembly.get_meta("ingredients", [])
	var applied_sauce_count := 0
	for ingredient_id in ingredients:
		if _is_sauce_portion(String(ingredient_id)):
			applied_sauce_count += 1
	var local_pos := Vector3(0.0, 0.040, -0.015) if applied_sauce_count == 0 else Vector3(0.0, 0.042, 0.015)

	assembly.add_child(portion_visual)
	portion_visual.name = "Sauce_%s_%02d" % [portion_id.to_pascal_case(), int(assembly.get_meta("placed_count", 0)) + 1]
	portion_visual.position = local_pos
	portion_visual.rotation = Vector3.ZERO
	portion_visual.scale = Vector3.ONE
	portion_visual.visible = true

	ingredients.append(portion_id)
	assembly.set_meta("ingredients", ingredients)
	assembly.set_meta("placed_count", int(assembly.get_meta("placed_count", 0)) + 1)

	_cancel_ladle_scoop()
	held_item.set_meta("is_filled", false)
	var sauce_mesh := held_visual.find_child("SauceFill", true, false) as MeshInstance3D if is_instance_valid(held_visual) else null
	if is_instance_valid(sauce_mesh):
		sauce_mesh.visible = false


func _roll_durum(assembly: Area3D) -> bool:
	if not is_instance_valid(assembly) or is_instance_valid(held_item):
		return false
	var ingredients: Array = assembly.get_meta("ingredients", [])
	if ingredients.is_empty():
		return false
	var finished_visual := _duplicate_pickup_template("finished_durum")
	if not is_instance_valid(finished_visual):
		return false
	var finished_item: Area3D = InteractableItemScript.new()
	finished_item.name = "FinishedDurumItem"
	get_tree().current_scene.add_child(finished_item)
	finished_item.global_transform = assembly.global_transform
	_add_box_collider(finished_item, _item_collision_size("finished_durum"))
	finished_item.configure("finished_durum", "Fertiges Dürüm", null, true)
	finished_item.set_meta("durum_data", {"ingredients": ingredients.duplicate()})
	finished_item.set_meta("durum_ingredients", ingredients.duplicate())
	finished_item.pickup()
	held_item = finished_item
	held_item_id = finished_item.item_id
	held_visual = finished_visual
	held_visual.name = "Held_FinishedDurum"
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	if not _attach_held_visual(held_visual):
		finished_visual.queue_free()
		finished_item.queue_free()
		held_item = null
		held_item_id = ""
		held_visual = null
		return false
	assembly.queue_free()
	focused_durum_assembly = null
	_reset_cutting()
	return true


func _interact_with_customer(customer: CharacterBody3D) -> void:
	if not is_instance_valid(customer) or not is_instance_valid(held_item):
		return
	if held_item.item_id != "finished_durum" or not customer.has_method("try_accept_durum"):
		return
	var durum_data: Dictionary = {}
	var stored_data: Variant = held_item.get_meta("durum_data", {})
	if stored_data is Dictionary:
		durum_data = (stored_data as Dictionary).duplicate(true)
	if not durum_data.has("ingredients"):
		durum_data["ingredients"] = held_item.get_meta("durum_ingredients", []).duplicate()
	if not bool(customer.call("try_accept_durum", durum_data)):
		return
	var accepted_item := held_item
	var accepted_visual := held_visual
	var source_visual := accepted_item.source_visual as Node3D
	if is_instance_valid(accepted_visual):
		accepted_visual.queue_free()
	if is_instance_valid(source_visual) and source_visual != accepted_visual:
		source_visual.queue_free()
	accepted_item.queue_free()
	held_item = null
	held_item_id = ""
	held_visual = null
	held_sauce_home = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	focused_customer = null
	_reset_cutting()


func _interact_with_sauce_bin(bin: Area3D) -> void:
	if not is_instance_valid(bin):
		return
	var ladle_id := String(bin.get_meta("sauce_ladle_id", ""))
	if held_item:
		if held_item.item_id == ladle_id:
			_fill_sauce_ladle(ladle_id)
		return
	_pickup_sauce_ladle(bin, ladle_id)


func _fill_sauce_ladle(ladle_id: String) -> void:
	if not is_instance_valid(held_item) or held_item.item_id != ladle_id:
		return
	if not _is_sauce_ladle(ladle_id) or not is_instance_valid(held_visual):
		return
	var sauce_mesh := held_visual.find_child("SauceFill", true, false) as MeshInstance3D
	if not is_instance_valid(sauce_mesh):
		return
	held_item.set_meta("is_filled", true)
	sauce_mesh.visible = true
	_animate_ladle_scoop(sauce_mesh)


func _pickup_sauce_ladle(bin: Area3D, ladle_id: String) -> void:
	if held_item or not _is_sauce_ladle(ladle_id):
		return
	var visual := _duplicate_pickup_template(ladle_id)
	var home := bin.get_node_or_null("SauceLadle") as Node3D
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
	item.set_meta("is_filled", false)
	item.pickup()
	held_item = item
	held_item_id = item.item_id
	held_visual = visual
	held_sauce_home = home
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	held_sauce_home.visible = false
	_prepare_ladle_fill(held_visual, ladle_id)
	if not _attach_held_visual(held_visual):
		_return_sauce_ladle()


func _prepare_ladle_fill(ladle_visual: Node3D, ladle_id: String) -> MeshInstance3D:
	if not is_instance_valid(ladle_visual):
		return null
	var fill := ladle_visual.find_child("SauceFill", true, false) as MeshInstance3D
	if not is_instance_valid(fill):
		return null
	fill.visible = false
	var source_material := fill.get_active_material(0) as StandardMaterial3D
	if is_instance_valid(source_material):
		var sauce_material := source_material.duplicate() as StandardMaterial3D
		sauce_material.albedo_color = Color(0.91, 0.82, 0.65, 1) if ladle_id == "garlic_sauce_ladle" else Color(0.82, 0.28, 0.12, 1)
		sauce_material.roughness = 0.22
		fill.material_override = sauce_material
	return fill


func _animate_ladle_scoop(sauce_fill: MeshInstance3D) -> void:
	_cancel_ladle_scoop()
	if not is_instance_valid(right_hand_viewmodel):
		if is_instance_valid(sauce_fill):
			sauce_fill.visible = true
		return
	right_hand_viewmodel.transform = right_hand_rest_transform
	var rest_position := right_hand_rest_transform.origin
	var dip_position := rest_position + Vector3(-0.018, -0.095, -0.045)
	ladle_scoop_tween = create_tween()
	ladle_scoop_tween.set_trans(Tween.TRANS_SINE)
	ladle_scoop_tween.set_ease(Tween.EASE_IN_OUT)
	ladle_scoop_tween.tween_property(right_hand_viewmodel, "position", dip_position, 0.2)
	ladle_scoop_tween.tween_callback(_set_ladle_fill_visible.bind(sauce_fill, true))
	ladle_scoop_tween.tween_property(right_hand_viewmodel, "position", rest_position, 0.24)


func _set_ladle_fill_visible(sauce_fill: MeshInstance3D, is_visible: bool) -> void:
	if is_instance_valid(sauce_fill):
		sauce_fill.visible = is_visible


func _cancel_ladle_scoop() -> void:
	if is_instance_valid(ladle_scoop_tween):
		ladle_scoop_tween.kill()
	ladle_scoop_tween = null
	if is_instance_valid(right_hand_viewmodel) and hand_sockets_ready:
		right_hand_viewmodel.transform = right_hand_rest_transform


func _apply_sauce_to_prep(station: Node3D, hit_position: Vector3, hit_normal: Vector3) -> void:
	if not is_instance_valid(held_item) or not _is_sauce_ladle(held_item.item_id):
		return
	if not _can_place_on_station(station, hit_normal):
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
	var drop_position := _snapped_station_position(station, hit_position, hit_normal)
	var drop_rotation := Vector3.ZERO
	if station.has_method("get_placed_items_container"):
		portion.add_child(portion_visual)
		portion_visual.transform = Transform3D.IDENTITY
		portion_visual.scale = Vector3.ONE
		portion_visual.visible = true
		if station.call("place_item", portion, portion_id, hit_position, hit_normal) == null:
			portion.queue_free()
			return
	else:
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
	portion.collision_layer = TABLE_ITEM_LAYER
	portion.collision_mask = 0
	portion.add_to_group("placed_items")
	_set_collisions_enabled(portion, true)
	for collision_node in portion.find_children("*", "CollisionShape3D", true, false):
		var collision_shape := collision_node as CollisionShape3D
		var box_shape := collision_shape.shape as BoxShape3D
		if is_instance_valid(box_shape):
			var enlarged_size := box_shape.size
			enlarged_size.y = maxf(enlarged_size.y, 0.24)
			box_shape.size = enlarged_size
	if station.has_method("place_item") and not station.has_method("get_placed_items_container"):
		station.call("place_item", portion, portion_id, hit_position)
		portion.collision_layer = TABLE_ITEM_LAYER
	elif not station.has_method("get_placed_items_container"):
		portion.set_meta("prep_station", station)
		portion.set_meta("ingredient_id", portion_id)
	portion.original_transform = portion.global_transform
	_return_sauce_ladle()


func _return_sauce_ladle() -> void:
	_cancel_ladle_scoop()
	if is_instance_valid(held_visual):
		held_visual.queue_free()
	if is_instance_valid(held_item):
		held_item.queue_free()
	if is_instance_valid(held_sauce_home):
		held_sauce_home.visible = true
	held_item = null
	held_item_id = ""
	held_visual = null
	held_sauce_home = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	_reset_cutting()

func _resolve_hand_sockets() -> void:
	if not is_instance_valid(camera):
		return
	right_hand_viewmodel = camera.get_node_or_null("ArmsHolder/RightHandViewmodel") as MeshInstance3D
	right_hand_socket = camera.get_node_or_null("ArmsHolder/RightHandViewmodel/RightHandSocket") as Marker3D
	left_hand_socket = camera.get_node_or_null("ArmsHolder/LeftHandViewmodel/LeftHandSocket") as Marker3D
	palm_socket = camera.get_node_or_null("ArmsHolder/RightHandViewmodel/RightHandSocket/PalmSocket") as Marker3D
	ladle_socket = camera.get_node_or_null("ArmsHolder/RightHandViewmodel/RightHandSocket/LadleSocket") as Marker3D
	bread_socket = camera.get_node_or_null("ArmsHolder/LeftHandViewmodel/LeftHandSocket/BreadSocket") as Marker3D
	if not is_instance_valid(palm_socket):
		palm_socket = hold_socket
	if not is_instance_valid(right_hand_socket):
		right_hand_socket = palm_socket
	if not is_instance_valid(left_hand_socket):
		left_hand_socket = palm_socket
	if not is_instance_valid(bread_socket):
		bread_socket = left_hand_socket
	hold_socket = palm_socket
	if is_instance_valid(right_hand_viewmodel) and not hand_sockets_ready:
		right_hand_rest_transform = right_hand_viewmodel.transform
	hand_sockets_ready = true


func _socket_for_item(item_id: String) -> Marker3D:
	_resolve_hand_sockets()
	if _is_sauce_ladle(item_id):
		return ladle_socket
	if item_id == "lavash" or item_id == "baked_lavash" or item_id == "durum_assembly":
		return bread_socket
	return palm_socket


func equip_to_hand(item_node: Node3D, target_socket: Marker3D) -> bool:
	if not is_instance_valid(item_node) or not is_instance_valid(target_socket):
		return false
	_set_collisions_enabled(item_node, false)
	if item_node.get_parent() != null:
		item_node.get_parent().remove_child(item_node)
	target_socket.add_child(item_node)
	item_node.top_level = false
	item_node.transform = Transform3D.IDENTITY
	item_node.visible = true
	return true


func _attach_held_visual(visual: Node3D) -> bool:
	var item_id: String = held_item.item_id if is_instance_valid(held_item) else ""
	var socket := _socket_for_item(item_id)
	if not is_instance_valid(socket) or not is_instance_valid(visual):
		return false
	if is_instance_valid(held_item):
		_set_collisions_enabled(held_item, false)
	return equip_to_hand(visual, socket)


func _set_collisions_enabled(root: Node, enabled: bool) -> void:
	if not is_instance_valid(root):
		return
	var shape := root as CollisionShape3D
	if shape:
		shape.disabled = not enabled
	for child in root.get_children():
		_set_collisions_enabled(child, enabled)

func _duplicate_pickup_template(item_id: String) -> Node3D:
	var template := pickup_templates.get(item_id) as Node3D
	if not is_instance_valid(template):
		return null
	var copy := template.duplicate() as Node3D
	if not is_instance_valid(copy) or copy == template:
		return null
	_normalize_pickup_copy(copy)
	copy.visible = true
	for mesh in copy.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return copy


func _normalize_pickup_copy(copy: Node3D) -> void:
	var pivot_mode := String(copy.get_meta("pivot", ""))
	if pivot_mode.is_empty():
		return
	var bounds_data := {"has_bounds": false, "bounds": AABB()}
	if pivot_mode == "handle_grip_center":
		var handle := copy.find_child("Handle", true, false) as Node3D
		if is_instance_valid(handle):
			_accumulate_pickup_bounds(handle, Transform3D.IDENTITY, bounds_data)
	else:
		for child in copy.get_children():
			_accumulate_pickup_bounds(child, Transform3D.IDENTITY, bounds_data)
	if not bool(bounds_data["has_bounds"]):
		return
	var bounds: AABB = bounds_data["bounds"]
	var center := bounds.get_center()
	var anchor := center if pivot_mode == "handle_grip_center" else Vector3(center.x, bounds.position.y, center.z)
	for child in copy.get_children():
		var child_3d := child as Node3D
		if child_3d:
			child_3d.position -= anchor


func _accumulate_pickup_bounds(node: Node, parent_transform: Transform3D, bounds_data: Dictionary) -> void:
	var node_transform := parent_transform
	var node_3d := node as Node3D
	if node_3d:
		node_transform = parent_transform * node_3d.transform
	var mesh_instance := node as MeshInstance3D
	if mesh_instance and mesh_instance.mesh:
		var mesh_bounds := node_transform * mesh_instance.mesh.get_aabb()
		if bool(bounds_data["has_bounds"]):
			bounds_data["bounds"] = (bounds_data["bounds"] as AABB).merge(mesh_bounds)
		else:
			bounds_data["bounds"] = mesh_bounds
			bounds_data["has_bounds"] = true
	for child in node.get_children():
		_accumulate_pickup_bounds(child, node_transform, bounds_data)

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
	_set_collisions_enabled(item, true)
	item.restore()
	held_item = null
	held_item_id = ""
	held_visual = null
	held_sauce_home = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	_reset_cutting()


func _discard_held_item() -> void:
	if not is_instance_valid(held_item) and not is_instance_valid(held_visual):
		return
	var source_visual: Node3D
	if is_instance_valid(held_item):
		source_visual = held_item.source_visual as Node3D
	if is_instance_valid(held_visual):
		held_visual.queue_free()
	if is_instance_valid(source_visual) and source_visual != held_visual:
		source_visual.queue_free()
	if is_instance_valid(held_item):
		held_item.queue_free()
	held_item = null
	held_item_id = ""
	held_visual = null
	held_sauce_home = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	_reset_cutting()


func _place_held_on_prep(station: Node3D, hit_position: Vector3, hit_normal := Vector3.UP, _offset_from_surface := true) -> void:
	if not held_item or not is_instance_valid(held_visual) or not is_instance_valid(station):
		return
	if hit_normal.normalized().y <= 0.9:
		return
	var previous_visual := held_item.source_visual as Node3D
	if is_instance_valid(previous_visual) and previous_visual != held_visual and previous_visual.get_parent() == held_item:
		previous_visual.queue_free()

	if held_visual != held_item:
		if held_visual.get_parent() == null:
			held_item.add_child(held_visual)
		elif held_visual.get_parent() != held_item:
			held_visual.reparent(held_item)
		held_visual.transform = Transform3D.IDENTITY
		held_visual.scale = Vector3.ONE
		held_visual.visible = true
		held_item.source_visual = held_visual

	var assembly_table := station
	if station.has_method("get_placed_items_container"):
		assembly_table = station.call("get_placed_items_container") as Node3D
	if not is_instance_valid(assembly_table):
		return

	held_item.reparent(assembly_table)
	held_item.global_position = hit_position
	held_item.global_rotation = Vector3.ZERO
	held_item.scale = Vector3.ONE
	_set_collisions_enabled(held_item, true)
	held_item.consumed_on_pickup = false
	held_item.available = true
	held_item.collision_layer = TABLE_ITEM_LAYER
	held_item.collision_mask = 0
	held_item.set_meta("item_id", held_item.item_id)
	held_item.set_meta("ingredient_id", held_item.item_id)
	held_item.set_meta("prep_station", station)
	held_item.set_meta("placed_on_assembly_station", true)
	held_item.add_to_group("placed_items")
	for collision_node in held_item.find_children("*", "CollisionShape3D", true, false):
		var collision_shape := collision_node as CollisionShape3D
		if not is_instance_valid(collision_shape):
			continue
		collision_shape.disabled = false
		var box_shape := collision_shape.shape as BoxShape3D
		if is_instance_valid(box_shape):
			var enlarged_size := box_shape.size
			enlarged_size.y = maxf(enlarged_size.y, 0.24)
			box_shape.size = enlarged_size
	if station.has_method("get_placed_items_container") and station.has_method("_register_item"):
		station.call("_register_item", held_item, held_item.item_id)
	elif station.has_method("place_item"):
		station.call("place_item", held_item, held_item.item_id, hit_position)
		held_item.collision_layer = TABLE_ITEM_LAYER
	held_item.original_transform = held_item.global_transform

	held_item = null
	held_item_id = ""
	held_visual = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	_reset_cutting()


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
	_set_collisions_enabled(held_item, true)
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
	held_item_id = ""
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
		"finished_durum":
			return Vector3(0.34, 0.72, 0.34)
		"cut_meat":
			return Vector3(0.42, 0.22, 0.42)
		_:
			return Vector3(0.5, 0.3, 0.5)

func _interact_with_oven() -> void:
	if held_item and held_item.item_id == "lavash":
		var empty_slot := oven_slot_states.find(OvenSlotState.EMPTY)
		if empty_slot >= 0 and current_lavash_count < OVEN_CAPACITY:
			_insert_lavash_into_oven(empty_slot)
		return
	if held_item == null:
		var finished_slot := oven_slot_states.find(OvenSlotState.FINISHED)
		if finished_slot >= 0:
			_take_baked_lavash(finished_slot)

func _insert_lavash_into_oven(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= baking_slots.size():
		return
	if not is_instance_valid(held_item) or not is_instance_valid(held_visual):
		return
	var raw_item := held_item
	var slot_visual := held_visual
	_set_collisions_enabled(slot_visual, true)
	slot_visual.reparent(baking_slots[slot_index], false)
	slot_visual.transform = Transform3D.IDENTITY
	slot_visual.scale = Vector3.ONE
	slot_visual.visible = true
	held_item = null
	held_item_id = ""
	held_visual = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	raw_item.queue_free()
	oven_slot_visuals[slot_index] = slot_visual
	oven_slot_states[slot_index] = OvenSlotState.BAKING
	oven_slot_times[slot_index] = OVEN_BAKE_DURATION
	current_lavash_count += 1
	_set_oven_heat(true)
	_update_oven_label()

func _update_oven(delta: float) -> void:
	var has_active_baking := false
	for slot_index in oven_slot_states.size():
		if oven_slot_states[slot_index] != OvenSlotState.BAKING:
			continue
		oven_slot_times[slot_index] = maxf(0.0, oven_slot_times[slot_index] - delta)
		if oven_slot_times[slot_index] <= 0.0:
			_finish_oven_bake(slot_index)
		else:
			has_active_baking = true
	_set_oven_heat(has_active_baking)
	_update_oven_label()

func _update_oven_label() -> void:
	if not is_instance_valid(oven_timer_label):
		return
	var baking_count := oven_slot_states.count(OvenSlotState.BAKING)
	var finished_count := oven_slot_states.count(OvenSlotState.FINISHED)
	if baking_count > 0:
		var next_finish := OVEN_BAKE_DURATION
		for slot_index in oven_slot_states.size():
			if oven_slot_states[slot_index] == OvenSlotState.BAKING:
				next_finish = minf(next_finish, oven_slot_times[slot_index])
		if finished_count > 0:
			oven_timer_label.text = "%d fertig | %02ds" % [finished_count, int(ceili(next_finish))]
		else:
			oven_timer_label.text = "%d/3 | %02ds" % [current_lavash_count, int(ceili(next_finish))]
	elif finished_count > 0:
		oven_timer_label.text = "Fertig: %d/3" % finished_count
	else:
		oven_timer_label.text = "Bereit 0/3"

func _finish_oven_bake(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= baking_slots.size():
		return
	if is_instance_valid(oven_slot_visuals[slot_index]):
		oven_slot_visuals[slot_index].queue_free()
	var baked_visual := _duplicate_pickup_template("baked_lavash")
	oven_slot_visuals[slot_index] = baked_visual
	if is_instance_valid(baked_visual):
		baked_visual.name = "BakedLavash_%d" % slot_index
		baking_slots[slot_index].add_child(baked_visual)
		baked_visual.transform = Transform3D.IDENTITY
		baked_visual.scale = Vector3.ONE
	oven_slot_states[slot_index] = OvenSlotState.FINISHED
	oven_slot_times[slot_index] = 0.0

func _take_baked_lavash(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= baking_slots.size():
		return
	var baked_visual := oven_slot_visuals[slot_index]
	if held_item != null or not is_instance_valid(baked_visual):
		return
	var baked_item: Area3D = InteractableItemScript.new()
	baked_item.name = "BakedLavashItem"
	get_tree().current_scene.add_child(baked_item)
	baked_item.global_transform = baking_slots[slot_index].global_transform
	_add_box_collider(baked_item, _item_collision_size("baked_lavash"))
	baked_item.configure("baked_lavash", "Gebackenes Lavash", null, true)
	baked_item.pickup()
	held_item = baked_item
	held_item_id = baked_item.item_id
	held_visual = baked_visual
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	if not _attach_held_visual(held_visual):
		_set_collisions_enabled(held_item, true)
		_set_collisions_enabled(held_visual, true)
		held_visual.reparent(baking_slots[slot_index], false)
		held_visual.transform = Transform3D.IDENTITY
		held_item.queue_free()
		held_item = null
		held_item_id = ""
		held_visual = null
		return
	oven_slot_visuals[slot_index] = null
	oven_slot_states[slot_index] = OvenSlotState.EMPTY
	oven_slot_times[slot_index] = 0.0
	current_lavash_count = maxi(0, current_lavash_count - 1)
	_update_oven_label()

func _set_oven_heat(active: bool) -> void:
	if is_instance_valid(oven_heating_elements):
		oven_heating_elements.visible = active
	if is_instance_valid(oven_heat_light):
		oven_heat_light.visible = active

func _update_cutting(delta: float) -> void:
	var holding_knife: bool = held_item != null and held_item.item_id == "knife"
	if not holding_knife:
		return
	var can_cut: bool = focused_meat != null
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
		held_visual.transform = Transform3D.IDENTITY
		held_visual.position = Vector3.ZERO
		held_visual.rotation = Vector3.ZERO
		held_visual.scale = Vector3.ONE

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
