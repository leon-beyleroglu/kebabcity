class_name KebabInteractionSystem
extends Node

const InteractableItemScript = preload("res://interactable_item.gd")
const DonerMeatStationScript = preload("res://doner_meat_station.gd")

const INTERACTION_RANGE := 2.8
const INTERACTION_LAYER := 1 << 7
const PREP_ITEM_LAYER := 1 << 8
const CUT_DURATION := 1.0

var player: CharacterBody3D
var camera: Camera3D
var hand_parent: Node3D
var hold_socket: Node3D
var held_item: Area3D
var held_visual: Node3D
var focused_item: Area3D
var focused_meat: Area3D
var focused_prep: Node3D
var focused_knife_mount: Node3D
var focus_hit_position := Vector3.ZERO
var held_origin_station: Node3D
var held_origin_transform := Transform3D.IDENTITY
var meat_visual: MeshInstance3D
var cut_progress := 0.0
var cut_sound_timer := 0.0
var cut_anim_time := 0.0
var portions_created := 0

var ui_layer: CanvasLayer
var progress_bar: ProgressBar
var crosshair: Label
var cut_audio: AudioStreamPlayer

func setup(owner_player: CharacterBody3D, view_camera: Camera3D, hands: Node3D) -> void:
	player = owner_player
	camera = view_camera
	hand_parent = hands
	_setup_input()
	_setup_hold_socket()
	_setup_ui()
	_setup_audio()
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

func _setup_hold_socket() -> void:
	hold_socket = Node3D.new()
	hold_socket.name = "HeldItemSocket"
	hold_socket.position = Vector3(0.37, -0.28, -0.72)
	hold_socket.rotation = Vector3(-0.08, 0.16, 0.1)
	hand_parent.add_child(hold_socket)

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

	progress_bar = ProgressBar.new()
	progress_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	progress_bar.position = Vector2(-180, -50)
	progress_bar.size = Vector2(360, 14)
	progress_bar.min_value = 0
	progress_bar.max_value = 1
	progress_bar.show_percentage = false
	progress_bar.visible = false
	root.add_child(progress_bar)

func _setup_audio() -> void:
	cut_audio = AudioStreamPlayer.new()
	cut_audio.name = "GeneratedCutSound"
	cut_audio.volume_db = -7.0
	cut_audio.stream = _make_cut_sound()
	add_child(cut_audio)

func _make_cut_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.16
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4571
	for i in range(count):
		var t := float(i) / float(sample_rate)
		var envelope := pow(1.0 - t / duration, 2.2)
		var scrape := sin(TAU * (880.0 - t * 2100.0) * t) * 0.55
		var noise := rng.randf_range(-1.0, 1.0) * 0.35
		data.encode_s16(i * 2, int(clampf((scrape + noise) * envelope, -1.0, 1.0) * 26000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream

func _register_scene_targets() -> void:
	var root := get_tree().current_scene
	_register_existing_item(root.get_node_or_null("Test Ablage/Kebab Theke/Zutaten/Salat"), "salad", "Salat")
	_register_existing_item(root.get_node_or_null("Test Ablage/Kebab Theke/Zutaten/Tomaten"), "tomato", "Tomaten")
	_register_existing_item(root.get_node_or_null("Test Ablage/Kebab Theke/Zutaten/Gurkenstreifen"), "cucumber", "Gurken")
	_register_existing_item(root.get_node_or_null("Test Ablage/Kebab Theke/LavashAblage/Lavash3"), "lavash", "Lavash")
	meat_visual = root.get_node_or_null("DonerSpit/Meat") as MeshInstance3D
	if meat_visual:
		_register_meat_station(meat_visual)
	var knife_mount := root.get_node_or_null("KnifeWallMount") as StaticBody3D
	var knife_snap := root.get_node_or_null("KnifeWallMount/KnifeSnap") as Marker3D
	var knife_visual := root.get_node_or_null("KnifeWallMount/KnifePreview") as Node3D
	if knife_mount and knife_snap and knife_visual:
		_register_mounted_knife(knife_mount, knife_snap, knife_visual)

func _register_existing_item(visual: MeshInstance3D, id: String, label: String) -> void:
	if not visual or not visual.mesh:
		push_warning("Interaktionsobjekt fehlt: %s" % label)
		return
	var item: Area3D = InteractableItemScript.new()
	item.name = label + "Interaction"
	get_tree().current_scene.add_child(item)
	item.global_transform = visual.global_transform
	_add_box_collider(item, visual.mesh.get_aabb().size * 1.35)
	item.configure(id, label, visual)

func _register_meat_station(visual: MeshInstance3D) -> void:
	var station: Area3D = DonerMeatStationScript.new()
	station.name = "DonerMeatInteraction"
	get_tree().current_scene.add_child(station)
	station.global_transform = visual.global_transform
	_add_box_collider(station, visual.mesh.get_aabb().size * 1.35)

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
	if not is_instance_valid(player) or not is_instance_valid(camera):
		return
	var first_person: bool = not player.third_person and player.visible and camera.current
	ui_layer.visible = first_person
	if not first_person:
		focused_item = null
		focused_meat = null
		focused_prep = null
		focused_knife_mount = null
		_reset_cutting()
		return
	_update_focus()
	_update_prompt()
	_update_cutting(delta)

func _update_focus() -> void:
	focused_item = null
	focused_meat = null
	focused_prep = null
	focused_knife_mount = null
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * INTERACTION_RANGE, INTERACTION_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	focus_hit_position = hit["position"]
	var collider: Object = hit.get("collider")
	if collider is Area3D and collider.has_meta("interactable") and collider.available:
		focused_item = collider
	elif collider is Area3D and collider.has_meta("doner_meat_station"):
		focused_meat = collider
	elif collider is Node3D and (collider.is_in_group("knife_mount") or collider.has_meta("knife_mount")):
		focused_knife_mount = collider
	elif collider is Node3D and (collider.is_in_group("prep_surface") or collider.has_meta("assembly_station")):
		focused_prep = collider

func _update_prompt() -> void:
	progress_bar.visible = false
	if focused_meat and held_item and held_item.item_id == "knife":
		progress_bar.visible = true
		progress_bar.value = cut_progress / CUT_DURATION

func _unhandled_input(event: InputEvent) -> void:
	if not player or player.third_person or not camera.current:
		return
	if event.is_action_pressed("interact"):
		if focused_knife_mount and held_item and held_item.item_id == "knife":
			_place_knife_on_mount(focused_knife_mount)
		elif focused_prep and held_item:
			if held_item.item_id != "knife":
				_place_held_on_prep(focused_prep, focus_hit_position)
		elif focused_item:
			_pickup(focused_item)
		elif held_item:
			_return_held()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop_item") and held_item:
		_return_held()
		get_viewport().set_input_as_handled()

func _pickup(item: Area3D) -> void:
	if held_item:
		_return_held()
	held_origin_station = item.get_meta("prep_station", null) as Node3D
	if is_instance_valid(held_origin_station):
		held_origin_transform = item.global_transform
		held_origin_station.call("remove_item", item)
	else:
		held_origin_transform = Transform3D.IDENTITY
	held_item = item
	held_item.pickup()
	held_visual = Node3D.new()
	held_visual.name = "Held_%s" % item.item_id
	hold_socket.add_child(held_visual)
	_create_item_model(held_visual, item.item_id, true)

func _return_held() -> void:
	if not held_item:
		return
	var item := held_item
	var origin_station := held_origin_station
	var origin_transform := held_origin_transform
	if is_instance_valid(held_visual):
		held_visual.queue_free()
	item.restore()
	if is_instance_valid(origin_station) and is_instance_valid(item):
		item.global_transform = origin_transform
		origin_station.call("place_item", item, item.item_id, origin_transform.origin)
	held_item = null
	held_visual = null
	held_origin_station = null
	held_origin_transform = Transform3D.IDENTITY
	_reset_cutting()


func _place_held_on_prep(station: Node3D, hit_position: Vector3) -> void:
	if not held_item or not is_instance_valid(station):
		return
	if not is_instance_valid(held_item.source_visual) or held_item.source_visual.get_parent() != held_item:
		var placed_visual := Node3D.new()
		placed_visual.name = "PlacedVisual"
		held_item.add_child(placed_visual)
		_create_item_model(placed_visual, held_item.item_id, false)
		held_item.source_visual = placed_visual
	else:
		held_item.source_visual.visible = true

	if held_item.get_parent() != station:
		held_item.reparent(station, true)
	held_item.global_transform = Transform3D(Basis.IDENTITY, held_item.global_position)

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
	held_item.available = true
	held_item.collision_layer = INTERACTION_LAYER | PREP_ITEM_LAYER
	held_item.collision_mask = 0
	var snap_position: Vector3 = station.call("place_item", held_item, held_item.item_id, hit_position)
	held_item.global_position = snap_position
	held_item.global_rotation = Vector3(0, player.global_rotation.y, 0)
	held_item.original_transform = held_item.global_transform

	if is_instance_valid(held_visual):
		held_visual.queue_free()
	held_item = null
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
		"lavash":
			return Vector3(0.55, 0.2, 0.4)
		"cut_meat":
			return Vector3(0.42, 0.22, 0.42)
		_:
			return Vector3(0.5, 0.3, 0.5)

func _update_cutting(delta: float) -> void:
	var can_cut: bool = focused_meat != null and held_item != null and held_item.item_id == "knife"
	if not can_cut or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if held_visual:
			held_visual.rotation = held_visual.rotation.lerp(Vector3.ZERO, 1.0 - exp(-delta * 14.0))
			held_visual.position = held_visual.position.lerp(Vector3.ZERO, 1.0 - exp(-delta * 14.0))
		cut_progress = maxf(0.0, cut_progress - delta * 0.55)
		return
	cut_progress += delta
	cut_anim_time += delta
	cut_sound_timer -= delta
	if held_visual:
		var stroke := sin(cut_anim_time * 24.0)
		held_visual.rotation = Vector3(0.45 + stroke * 0.22, 0.05, -0.55 + stroke * 0.32)
		held_visual.position = Vector3(0, stroke * 0.055, 0)
	if cut_sound_timer <= 0.0:
		cut_audio.play()
		cut_sound_timer = 0.28
	if cut_progress >= CUT_DURATION:
		_spawn_meat_portion()
		cut_progress = 0.0
		cut_anim_time = 0.0

func _reset_cutting() -> void:
	cut_progress = 0.0
	cut_anim_time = 0.0
	cut_sound_timer = 0.0
	if held_visual:
		held_visual.rotation = Vector3.ZERO
		held_visual.position = Vector3.ZERO

func _spawn_meat_portion() -> void:
	portions_created += 1
	var item: Area3D = InteractableItemScript.new()
	item.name = "CutMeatPortion_%02d" % portions_created
	get_tree().current_scene.add_child(item)
	var row := (portions_created - 1) % 4
	var stack := (portions_created - 1) / 4
	item.global_position = meat_visual.global_position + Vector3(0.7 + row * 0.24, -0.95 + stack * 0.08, 1.0)
	var visual := Node3D.new()
	visual.name = "FreshCutMeat"
	item.add_child(visual)
	_create_item_model(visual, "cut_meat", false)
	_add_box_collider(item, Vector3(0.42, 0.22, 0.42))
	item.configure("cut_meat", "geschnittenes Dönerfleisch", visual)

func _create_item_model(parent: Node3D, id: String, held: bool) -> void:
	match id:
		"salad":
			_add_bowl(parent, Color("d9d4c5"))
			for i in range(9):
				var leaf := _box(parent, Vector3((i % 3 - 1) * 0.09, 0.04 + (i / 3) * 0.025, (i % 2) * 0.09 - 0.045), Vector3(0.14, 0.035, 0.1), Color("4f9d49"))
				leaf.rotation.y = i * 0.73
		"tomato":
			_add_bowl(parent, Color("d9d4c5"))
			for i in range(7):
				var slice := _cylinder(parent, Vector3((i % 3 - 1) * 0.09, 0.05 + (i / 3) * 0.025, (i % 2) * 0.08 - 0.04), 0.075, 0.018, Color("d94b3e"))
				slice.rotation = Vector3(0, i * 0.7, 0.05)
		"cucumber":
			_add_bowl(parent, Color("d9d4c5"))
			for i in range(8):
				var strip := _box(parent, Vector3((i % 4 - 1.5) * 0.055, 0.065 + (i / 4) * 0.035, (i % 2) * 0.07 - 0.035), Vector3(0.045, 0.035, 0.25), Color("498448"))
				strip.rotation.y = (i - 3) * 0.12
		"lavash":
			for i in range(3):
				var bread := _box(parent, Vector3(0, i * 0.035, 0), Vector3(0.48, 0.025, 0.32), Color("d9ad6d"))
				bread.rotation.y = (i - 1) * 0.12
		"knife":
			_box(parent, Vector3(0, 0, 0.18), Vector3(0.1, 0.1, 0.38), Color("4b2c20"))
			_box(parent, Vector3(0, 0, -0.2), Vector3(0.16, 0.035, 0.45), Color("d5d8d8"), 0.8)
			_box(parent, Vector3(0, 0, 0), Vector3(0.2, 0.06, 0.05), Color("ba9b68"), 0.6)
		"cut_meat":
			_add_bowl(parent, Color("b9b0a0"))
			for i in range(11):
				var shaving := _box(parent, Vector3((i % 4 - 1.5) * 0.055, 0.045 + (i / 4) * 0.025, (i % 3 - 1) * 0.05), Vector3(0.045, 0.035, 0.2), Color("824029"))
				shaving.rotation.y = i * 0.77
	if held:
		parent.scale = Vector3.ONE * (0.85 if id != "knife" else 1.0)
	for mesh in parent.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _add_bowl(parent: Node3D, color: Color) -> void:
	var bowl := _cylinder(parent, Vector3(0, -0.035, 0), 0.24, 0.08, color)
	bowl.scale.z = 0.72

func _box(parent: Node3D, position: Vector3, size: Vector3, color: Color, metallic := 0.0) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	material.metallic = metallic
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	return instance

func _cylinder(parent: Node3D, position: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.68
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	return instance
