class_name KebabInteractionSystem
extends Node

const InteractableItemScript = preload("res://interactable_item.gd")
const DonerMeatStationScript = preload("res://doner_meat_station.gd")

const INTERACTION_RANGE := 2.8
const INTERACTION_LAYER := 1 << 7
const CUT_DURATION := 1.0

var player: CharacterBody3D
var camera: Camera3D
var hand_parent: Node3D
var hold_socket: Node3D
var held_item: Area3D
var held_visual: Node3D
var focused_item: Area3D
var focused_meat: Area3D
var meat_visual: MeshInstance3D
var cut_progress := 0.0
var cut_sound_timer := 0.0
var cut_anim_time := 0.0
var portions_created := 0

var ui_layer: CanvasLayer
var prompt_panel: PanelContainer
var prompt_label: Label
var held_label: Label
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

	prompt_panel = PanelContainer.new()
	prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_panel.position = Vector2(-220, -112)
	prompt_panel.size = Vector2(440, 54)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.045, 0.06, 0.88)
	panel_style.border_color = Color(0.95, 0.45, 0.26, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	prompt_panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(prompt_panel)
	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 18)
	prompt_label.add_theme_color_override("font_color", Color("fff0d2"))
	prompt_panel.add_child(prompt_label)
	prompt_panel.visible = false

	held_label = Label.new()
	held_label.position = Vector2(26, 26)
	held_label.size = Vector2(420, 60)
	held_label.add_theme_font_size_override("font_size", 17)
	held_label.add_theme_color_override("font_color", Color("ffe0a6"))
	held_label.text = "Hände frei"
	root.add_child(held_label)

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
		_spawn_knife(meat_visual.global_position + Vector3(0.85, -0.78, 0.9))

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

func _spawn_knife(world_position: Vector3) -> void:
	var item: Area3D = InteractableItemScript.new()
	item.name = "KnifePickup"
	get_tree().current_scene.add_child(item)
	item.global_position = world_position
	item.rotation = Vector3(0.05, 0.25, -0.12)
	var visual := Node3D.new()
	visual.name = "KnifeOnCounter"
	item.add_child(visual)
	_create_item_model(visual, "knife", false)
	_add_box_collider(item, Vector3(0.38, 0.16, 0.9))
	item.configure("knife", "Messer", visual)

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
		_reset_cutting()
		return
	_update_focus()
	_update_prompt()
	_update_cutting(delta)

func _update_focus() -> void:
	focused_item = null
	focused_meat = null
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * INTERACTION_RANGE, INTERACTION_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider is Area3D and collider.has_meta("interactable") and collider.available:
		focused_item = collider
	elif collider is Area3D and collider.has_meta("doner_meat_station"):
		focused_meat = collider

func _update_prompt() -> void:
	prompt_panel.visible = false
	progress_bar.visible = false
	if focused_item:
		prompt_label.text = focused_item.prompt(held_item != null)
		prompt_panel.visible = true
	elif focused_meat:
		if held_item and held_item.item_id == "knife":
			prompt_label.text = "Halte [LMB], um Dönerfleisch zu schneiden"
			progress_bar.visible = true
			progress_bar.value = cut_progress / CUT_DURATION
		else:
			prompt_label.text = "Du brauchst ein Messer zum Schneiden"
		prompt_panel.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if not player or player.third_person or not camera.current:
		return
	if event.is_action_pressed("interact"):
		if focused_item:
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
	held_item = item
	held_item.pickup()
	held_visual = Node3D.new()
	held_visual.name = "Held_%s" % item.item_id
	hold_socket.add_child(held_visual)
	_create_item_model(held_visual, item.item_id, true)
	held_label.text = "In der Hand: %s\n[E] ablegen  •  [Q] zurücklegen" % item.display_name

func _return_held() -> void:
	if not held_item:
		return
	if is_instance_valid(held_visual):
		held_visual.queue_free()
	held_item.restore()
	held_item = null
	held_visual = null
	held_label.text = "Hände frei"
	_reset_cutting()

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
