class_name DoenerGrillStation
extends StaticBody3D

signal cutting_mode_changed(active: bool)
signal cut_completed(cuts_count: int)
signal tray_portions_changed(portions: int)
signal spit_depleted
signal spit_cooking_started(time_left: float)
signal spit_cooking_completed

const INTERACTION_LAYER := 1 << 7
const CUTS_PER_PORTION := 2
const CUTS_PER_SESSION := 6
const MAX_TRAY_PORTIONS := 3
const MAX_SPIT_CUTS := 60
const COOK_DURATION := 10.0
const RAW_MEAT_COLOR := Color(0.8, 0.35, 0.35, 1.0)
const COOKED_MEAT_COLOR := Color(0.45, 0.25, 0.12, 1.0)

@export var cut_stroke_threshold := 180.0
@export var knife_top_y := 1.18
@export var knife_bottom_y := 0.42
@export var knife_slice_time := 0.25
@export var spit_rotation_speed := 0.55
@export var close_up_mouse_visible := true

@onready var spit_mesh := get_node_or_null("SpitMesh") as MeshInstance3D
@onready var catch_tray := get_node_or_null("CatchTray") as Area3D
@onready var tray_visuals := get_node_or_null("CatchTray/PortionVisuals") as Node3D
@onready var tray_spawn_points := get_node_or_null("CatchTray/TraySpawnPoints") as Node3D
@onready var grill_camera := get_node_or_null("GrillCam") as Camera3D
@onready var knife_rig := get_node_or_null("KnifeRig") as Node3D
@onready var slice_particles := get_node_or_null("KnifeRig/SliceParticles") as GPUParticles3D
@onready var slice_sfx := get_node_or_null("SliceSFX") as AudioStreamPlayer3D
@onready var smoke_particles := get_node_or_null("SmokeParticles") as GPUParticles3D
@onready var cooking_sizzle := get_node_or_null("CookingSizzle") as AudioStreamPlayer3D
@onready var interact_area := get_node_or_null("InteractArea") as Area3D

var current_portions := 0
var cuts_count := 0
var is_in_cutting_mode := false
var is_lmb_pressed := false
var accumulated_downward_delta := 0.0
var spit_cuts_remaining := MAX_SPIT_CUTS
var is_cooking := false
var spit_cook_time_left := 0.0

var _player: CharacterBody3D
var _player_camera: Camera3D
var _interaction_system: Node
var _knife_tween: Tween
var _slice_in_progress := false
var _knife_rest_position := Vector3.ZERO
var _spit_base_scale := Vector3.ONE
var _spit_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("doener_grill_station")
	add_to_group("meat_tray")
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(spit_mesh):
		_spit_base_scale = spit_mesh.scale
		var source_material := spit_mesh.get_active_material(0) as StandardMaterial3D
		if is_instance_valid(source_material):
			_spit_material = source_material.duplicate() as StandardMaterial3D
		else:
			_spit_material = StandardMaterial3D.new()
		_spit_material.resource_local_to_scene = true
		spit_mesh.material_override = _spit_material
	if is_instance_valid(knife_rig):
		_knife_rest_position = knife_rig.position
		knife_top_y = knife_rig.position.y
		knife_rig.visible = false
	if is_instance_valid(grill_camera):
		var camera_target := get_node_or_null("CameraTarget") as Marker3D
		if is_instance_valid(camera_target):
			grill_camera.look_at(camera_target.global_position, Vector3.UP)
	_configure_interaction_area(interact_area, "grill")
	_configure_interaction_area(catch_tray, "tray")
	set_process_input(true)
	spit_cuts_remaining = clampi(GameState.spit_cuts_remaining, 0, MAX_SPIT_CUTS)
	is_cooking = GameState.is_spit_cooking
	spit_cook_time_left = clampf(GameState.spit_cook_time_left, 0.0, COOK_DURATION)
	_apply_spit_visual()
	_rebuild_tray_visuals()


func _process(delta: float) -> void:
	if is_instance_valid(spit_mesh):
		spit_mesh.rotate_y(spit_rotation_speed * delta)
	if is_cooking:
		_update_cooking(delta)


func _exit_tree() -> void:
	if is_in_cutting_mode:
		exit_cutting_mode()


func interact(player: CharacterBody3D, interaction_system: Node, hit_node: Node) -> bool:
	if not is_instance_valid(player) or not is_instance_valid(hit_node):
		return false
	var target_kind := String(hit_node.get_meta("doener_target", ""))
	if target_kind == "tray" or hit_node == catch_tray or (is_instance_valid(catch_tray) and catch_tray.is_ancestor_of(hit_node)):
		return try_pickup_tray_portion(player, interaction_system)
	if target_kind == "grill" or hit_node == interact_area or hit_node == self:
		if is_cooking:
			_show_feedback("Der neue Spieß gart noch %.1f s" % spit_cook_time_left, false)
			return true
		if spit_cuts_remaining <= 0:
			return _try_mount_raw_spit(interaction_system)
		return enter_cutting_mode(player, interaction_system)
	return false


func enter_cutting_mode(player: CharacterBody3D, interaction_system: Node = null) -> bool:
	if is_in_cutting_mode or is_cooking or spit_cuts_remaining <= 0 or not is_instance_valid(grill_camera):
		return false
	if current_portions >= MAX_TRAY_PORTIONS:
		return false
	if is_instance_valid(interaction_system) and interaction_system.has_method("can_accept_cutting_mode"):
		if not bool(interaction_system.call("can_accept_cutting_mode")):
			return false
	_player = player
	_interaction_system = interaction_system
	_player_camera = player.get_viewport().get_camera_3d()
	if is_instance_valid(_player_camera):
		_player_camera.current = false
	grill_camera.current = true
	if player.has_method("set_cutting_input_locked"):
		player.call("set_cutting_input_locked", true)
	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE if close_up_mouse_visible else Input.MOUSE_MODE_CAPTURED
	)
	cuts_count = 0
	accumulated_downward_delta = 0.0
	is_lmb_pressed = false
	is_in_cutting_mode = true
	if is_instance_valid(knife_rig):
		knife_rig.position = _knife_rest_position
		knife_rig.visible = true
	cutting_mode_changed.emit(true)
	return true


func exit_cutting_mode() -> void:
	if not is_in_cutting_mode:
		return
	if is_instance_valid(_knife_tween):
		_knife_tween.kill()
	_knife_tween = null
	_slice_in_progress = false
	is_lmb_pressed = false
	accumulated_downward_delta = 0.0
	if is_instance_valid(knife_rig):
		knife_rig.position = _knife_rest_position
		knife_rig.visible = false
	if is_instance_valid(grill_camera):
		grill_camera.current = false
	if is_instance_valid(_player_camera):
		_player_camera.current = true
	if is_instance_valid(_player) and _player.has_method("set_cutting_input_locked"):
		_player.call("set_cutting_input_locked", false)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	is_in_cutting_mode = false
	cuts_count = 0
	_player = null
	_player_camera = null
	_interaction_system = null
	cutting_mode_changed.emit(false)


func _input(event: InputEvent) -> void:
	if not is_in_cutting_mode:
		return
	if event.is_action_pressed("ui_cancel"):
		exit_cutting_mode()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_lmb_pressed = event.pressed
		if event.pressed:
			accumulated_downward_delta = 0.0
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and is_lmb_pressed:
		var motion := event as InputEventMouseMotion
		if motion.relative.y > 0.0:
			accumulated_downward_delta += motion.relative.y
		else:
			accumulated_downward_delta = maxf(0.0, accumulated_downward_delta + motion.relative.y * 0.35)
		if accumulated_downward_delta >= cut_stroke_threshold and not _slice_in_progress:
			accumulated_downward_delta = 0.0
			execute_downward_slice()
		get_viewport().set_input_as_handled()


func execute_downward_slice() -> void:
	if not is_in_cutting_mode or _slice_in_progress:
		return
	_slice_in_progress = true
	if is_instance_valid(slice_sfx) and slice_sfx.stream != null:
		slice_sfx.play()
	if is_instance_valid(slice_particles):
		slice_particles.restart()
		slice_particles.emitting = true
	if is_instance_valid(_knife_tween):
		_knife_tween.kill()
	if is_instance_valid(knife_rig):
		knife_rig.position.y = knife_top_y
		_knife_tween = create_tween()
		_knife_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_knife_tween.set_trans(Tween.TRANS_QUAD)
		_knife_tween.set_ease(Tween.EASE_IN)
		_knife_tween.tween_property(knife_rig, "position:y", knife_bottom_y, knife_slice_time)
		_knife_tween.set_ease(Tween.EASE_OUT)
		_knife_tween.tween_property(knife_rig, "position:y", knife_top_y, 0.12)
		_knife_tween.tween_callback(_finish_slice)
	else:
		_finish_slice()


func _finish_slice() -> void:
	_slice_in_progress = false
	if spit_cuts_remaining <= 0 or is_cooking:
		exit_cutting_mode()
		return
	spit_cuts_remaining = maxi(spit_cuts_remaining - 1, 0)
	_apply_spit_visual()
	_sync_spit_state()
	cuts_count += 1
	cut_completed.emit(cuts_count)
	if cuts_count % CUTS_PER_PORTION == 0:
		add_tray_portion()
	if spit_cuts_remaining <= 0:
		spit_depleted.emit()
		exit_cutting_mode()
	elif cuts_count >= CUTS_PER_SESSION:
		exit_cutting_mode()


func add_tray_portion() -> bool:
	if current_portions >= MAX_TRAY_PORTIONS:
		return false
	current_portions += 1
	_spawn_portion_visual(current_portions - 1)
	_sync_tray_state()
	return true


func try_pickup_tray_portion(player: CharacterBody3D, interaction_system: Node) -> bool:
	if current_portions <= 0 or not is_instance_valid(interaction_system):
		return false
	if not interaction_system.has_method("hold_meat_portion"):
		return false
	if not bool(interaction_system.call("hold_meat_portion")):
		return false
	current_portions -= 1
	_rebuild_tray_visuals()
	_sync_tray_state()
	return true


func get_save_data() -> Dictionary:
	return {
		"portions": clampi(current_portions, 0, MAX_TRAY_PORTIONS),
		"spit_cuts_remaining": clampi(spit_cuts_remaining, 0, MAX_SPIT_CUTS),
		"is_spit_cooking": is_cooking,
		"spit_cook_time_left": clampf(spit_cook_time_left, 0.0, COOK_DURATION),
	}


func load_save_data(data: Dictionary) -> bool:
	current_portions = clampi(int(data.get("portions", 0)), 0, MAX_TRAY_PORTIONS)
	spit_cuts_remaining = clampi(
		int(data.get("spit_cuts_remaining", MAX_SPIT_CUTS)),
		0,
		MAX_SPIT_CUTS
	)
	is_cooking = bool(data.get("is_spit_cooking", false))
	spit_cook_time_left = clampf(
		float(data.get("spit_cook_time_left", 0.0)),
		0.0,
		COOK_DURATION
	)
	if is_cooking and spit_cook_time_left <= 0.0:
		_complete_cooking()
	else:
		_apply_spit_visual()
		_set_cooking_effects(is_cooking)
	_rebuild_tray_visuals()
	_sync_tray_state()
	_sync_spit_state()
	return true


func _try_mount_raw_spit(interaction_system: Node) -> bool:
	if spit_cuts_remaining > 0 or is_cooking:
		return false
	if (
		not is_instance_valid(interaction_system)
		or not interaction_system.has_method("consume_supply_item")
		or not bool(interaction_system.call("consume_supply_item", "raw_spit"))
	):
		_show_feedback("Ein roher Dönerspieß wird benötigt", false)
		return true
	start_cooking_raw_spit(COOK_DURATION)
	return true


func start_cooking_raw_spit(time_left := COOK_DURATION) -> void:
	if is_in_cutting_mode:
		exit_cutting_mode()
	spit_cuts_remaining = 0
	is_cooking = true
	spit_cook_time_left = clampf(time_left, 0.01, COOK_DURATION)
	_apply_spit_visual()
	_set_cooking_effects(true)
	_sync_spit_state()
	spit_cooking_started.emit(spit_cook_time_left)
	_show_feedback("Roher Spieß eingehängt – Garzeit 10 Sekunden", true)


func _update_cooking(delta: float) -> void:
	spit_cook_time_left = maxf(spit_cook_time_left - delta, 0.0)
	_apply_spit_visual()
	_sync_spit_state()
	if spit_cook_time_left <= 0.0:
		_complete_cooking()


func _complete_cooking() -> void:
	is_cooking = false
	spit_cook_time_left = 0.0
	spit_cuts_remaining = MAX_SPIT_CUTS
	_apply_spit_visual()
	_set_cooking_effects(false)
	_sync_spit_state()
	spit_cooking_completed.emit()
	_show_feedback("Der Dönerspieß ist fertig gegrillt", true)


func _apply_spit_visual() -> void:
	if not is_instance_valid(spit_mesh):
		return
	if is_cooking:
		spit_mesh.visible = true
		spit_mesh.scale = _spit_base_scale
		var cooked_ratio := clampf(
			1.0 - spit_cook_time_left / COOK_DURATION,
			0.0,
			1.0
		)
		if is_instance_valid(_spit_material):
			_spit_material.albedo_color = RAW_MEAT_COLOR.lerp(COOKED_MEAT_COLOR, cooked_ratio)
		_set_sear_bands_visible(false)
		return
	var fill_ratio := clampf(float(spit_cuts_remaining) / float(MAX_SPIT_CUTS), 0.0, 1.0)
	spit_mesh.visible = spit_cuts_remaining > 0
	spit_mesh.scale = Vector3(
		_spit_base_scale.x * fill_ratio,
		_spit_base_scale.y,
		_spit_base_scale.z * fill_ratio
	)
	if is_instance_valid(_spit_material):
		_spit_material.albedo_color = COOKED_MEAT_COLOR
	_set_sear_bands_visible(spit_cuts_remaining > 0)


func _set_sear_bands_visible(value: bool) -> void:
	if not is_instance_valid(spit_mesh):
		return
	for child in spit_mesh.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = value


func _set_cooking_effects(active: bool) -> void:
	if is_instance_valid(smoke_particles):
		smoke_particles.emitting = active
	if is_instance_valid(cooking_sizzle):
		if active and cooking_sizzle.stream != null:
			cooking_sizzle.play()
		elif not active:
			cooking_sizzle.stop()


func _sync_spit_state() -> void:
	GameState.spit_cuts_remaining = clampi(spit_cuts_remaining, 0, MAX_SPIT_CUTS)
	GameState.is_spit_cooking = is_cooking
	GameState.spit_cook_time_left = clampf(spit_cook_time_left, 0.0, COOK_DURATION)


func _show_feedback(message: String, success: bool) -> void:
	var hud := get_tree().get_first_node_in_group("money_hud")
	if is_instance_valid(hud) and hud.has_method("show_order_feedback"):
		hud.call("show_order_feedback", message, success)


func _configure_interaction_area(area: Area3D, target_kind: String) -> void:
	if not is_instance_valid(area):
		return
	area.collision_layer = INTERACTION_LAYER
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.set_meta("doener_grill_station_owner", self)
	area.set_meta("doener_target", target_kind)


func _rebuild_tray_visuals() -> void:
	if not is_instance_valid(tray_visuals):
		return
	for child in tray_visuals.get_children():
		child.queue_free()
	for portion_index in current_portions:
		_spawn_portion_visual(portion_index)


func _spawn_portion_visual(portion_index: int) -> void:
	if not is_instance_valid(tray_visuals):
		return
	var portion := DoenerTongs.create_meat_portion_visual()
	portion.name = "MeatPortion_%02d" % (portion_index + 1)
	tray_visuals.add_child(portion)
	var marker := _tray_marker(portion_index)
	if is_instance_valid(marker):
		portion.global_transform = marker.global_transform
	else:
		portion.position = Vector3((portion_index - 1) * 0.18, 0.08, 0.0)


func _tray_marker(index: int) -> Marker3D:
	if not is_instance_valid(tray_spawn_points):
		return null
	var marker_name := "SpawnPoint_%02d" % (index + 1)
	return tray_spawn_points.get_node_or_null(marker_name) as Marker3D


func _sync_tray_state() -> void:
	GameState.meat_tray_portions = clampi(current_portions, 0, MAX_TRAY_PORTIONS)
	tray_portions_changed.emit(current_portions)
