class_name CuttingStation
extends StaticBody3D

const SLICES_REQUIRED := 4
const DRAG_SLICE_THRESHOLD := 34.0

var item_on_board: String = ""
var chop_progress: int = 0
var is_chopped: bool = false
var is_cutting_active: bool = false
var active_visual: Node3D

var _pending_save_data: Dictionary = {}
var _interaction_system: KebabInteractionSystem
var _player: CharacterBody3D
var _player_camera: Camera3D
var _knife_rest_transform := Transform3D.IDENTITY
var _knife_tween: Tween
var _slice_in_progress := false
var _exit_after_slice := false
var _downward_drag := 0.0

@onready var board_surface: Marker3D = $BoardSurface
@onready var station_area: Area3D = $StationArea
@onready var cutting_cam: Camera3D = $CuttingCam
@onready var knife_rig: Node3D = $KnifeRig
@onready var knife_mesh: MeshInstance3D = $KnifeRig/KnifeMesh
@onready var cut_audio: AudioStreamPlayer3D = $CutAudio
@onready var finish_audio: AudioStreamPlayer3D = $FinishAudio


func _ready() -> void:
	add_to_group("cutting_station")
	station_area.collision_layer = KebabInteractionSystem.INTERACTION_LAYER
	station_area.collision_mask = 0
	station_area.set_meta("cutting_station_owner", self)
	set_meta("cutting_station_owner", self)
	cutting_cam.current = false
	knife_rig.visible = false
	_knife_rest_transform = knife_rig.transform
	_build_cut_sounds()
	if not _pending_save_data.is_empty():
		var pending_data := _pending_save_data
		_pending_save_data = {}
		load_save_data(pending_data)


func _exit_tree() -> void:
	if is_cutting_active:
		_release_player_lock()


func _input(event: InputEvent) -> void:
	if not is_cutting_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		var key := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
		if key == KEY_ESCAPE or key == KEY_E:
			exit_cutting_view()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			if button_event.pressed:
				_request_manual_slice()
			else:
				_downward_drag = 0.0
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		if motion_event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_downward_drag = maxf(0.0, _downward_drag + motion_event.relative.y)
			if _downward_drag >= DRAG_SLICE_THRESHOLD:
				_downward_drag = 0.0
				_request_manual_slice()
			get_viewport().set_input_as_handled()


func interact(interaction_system: KebabInteractionSystem) -> bool:
	if not is_instance_valid(interaction_system):
		return false
	if item_on_board.is_empty():
		return _place_held_whole(interaction_system)
	if is_chopped:
		return _pick_up_sliced(interaction_system)
	if not interaction_system.can_accept_produced_item():
		return false
	return enter_cutting_view(interaction_system)


func enter_cutting_view(interaction_system: KebabInteractionSystem) -> bool:
	if is_cutting_active or item_on_board.is_empty() or is_chopped:
		return false
	_interaction_system = interaction_system
	_player = interaction_system.player
	_player_camera = interaction_system.camera
	if not is_instance_valid(_player) or not is_instance_valid(_player_camera):
		_clear_cutting_references()
		return false
	if _player.has_method("set_cutting_input_locked"):
		_player.call("set_cutting_input_locked", true)
	_player_camera.current = false
	cutting_cam.current = true
	knife_rig.transform = _knife_rest_transform
	knife_rig.visible = true
	is_cutting_active = true
	_slice_in_progress = false
	_exit_after_slice = false
	_downward_drag = 0.0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	return true


func exit_cutting_view() -> void:
	if not is_cutting_active:
		return
	is_cutting_active = false
	_slice_in_progress = false
	_exit_after_slice = false
	_downward_drag = 0.0
	if is_instance_valid(_knife_tween):
		_knife_tween.kill()
	knife_rig.transform = _knife_rest_transform
	knife_rig.visible = false
	cutting_cam.current = false
	_release_player_lock()
	_clear_cutting_references()


func get_save_data() -> Dictionary:
	return {
		"item_on_board": item_on_board,
		"chop_progress": chop_progress,
		"is_chopped": is_chopped,
	}


func load_save_data(data: Dictionary) -> bool:
	if not is_node_ready():
		_pending_save_data = data.duplicate(true)
		return true
	if is_cutting_active:
		exit_cutting_view()
	var saved_item := String(data.get("item_on_board", ""))
	var ingredient_id := WholeVegetableFactory.normalize_ingredient_id(saved_item)
	if saved_item.is_empty() or ingredient_id.is_empty():
		item_on_board = ""
		chop_progress = 0
		is_chopped = false
		_clear_board_visual()
		return true
	is_chopped = bool(data.get("is_chopped", saved_item.begins_with("sliced_")))
	item_on_board = ("sliced_" if is_chopped else "whole_") + ingredient_id
	chop_progress = clampi(int(data.get("chop_progress", SLICES_REQUIRED if is_chopped else 0)), 0, SLICES_REQUIRED)
	if is_chopped:
		chop_progress = SLICES_REQUIRED
	_spawn_board_visual()
	return true


func _request_manual_slice() -> void:
	if not is_cutting_active or _slice_in_progress or is_chopped or item_on_board.is_empty():
		return
	_slice_in_progress = true
	if is_instance_valid(_knife_tween):
		_knife_tween.kill()
	knife_rig.transform = _knife_rest_transform
	var impact_position := _knife_rest_transform.origin + Vector3(-0.1, -0.22, -0.015)
	var impact_rotation := _knife_rest_transform.basis.get_euler() + Vector3(deg_to_rad(-22.0), 0.0, deg_to_rad(7.0))
	_knife_tween = create_tween()
	_knife_tween.set_trans(Tween.TRANS_QUAD)
	_knife_tween.set_ease(Tween.EASE_IN)
	_knife_tween.tween_property(knife_rig, "position", impact_position, 0.075)
	_knife_tween.parallel().tween_property(knife_rig, "rotation", impact_rotation, 0.075)
	_knife_tween.tween_callback(_land_manual_slice)
	_knife_tween.set_ease(Tween.EASE_OUT)
	_knife_tween.tween_property(knife_rig, "transform", _knife_rest_transform, 0.14)
	_knife_tween.tween_callback(_finish_slice_animation)


func _land_manual_slice() -> void:
	if not is_cutting_active or is_chopped:
		return
	if is_instance_valid(cut_audio):
		cut_audio.play()
	chop_progress = mini(chop_progress + 1, SLICES_REQUIRED)
	if chop_progress >= SLICES_REQUIRED:
		var ingredient_id := WholeVegetableFactory.normalize_ingredient_id(item_on_board)
		item_on_board = "sliced_%s" % ingredient_id
		is_chopped = true
		_exit_after_slice = true
		if is_instance_valid(finish_audio):
			finish_audio.play()
	_spawn_board_visual()


func _finish_slice_animation() -> void:
	_slice_in_progress = false
	knife_rig.transform = _knife_rest_transform
	if _exit_after_slice:
		exit_cutting_view()


func _place_held_whole(interaction_system: KebabInteractionSystem) -> bool:
	var held_id := interaction_system.get_held_item_id()
	if not held_id.begins_with("whole_"):
		return false
	var ingredient_id := WholeVegetableFactory.normalize_ingredient_id(held_id)
	if ingredient_id.is_empty() or not interaction_system.consume_held_item(held_id):
		return false
	item_on_board = "whole_%s" % ingredient_id
	chop_progress = 0
	is_chopped = false
	_spawn_board_visual()
	return true


func _pick_up_sliced(interaction_system: KebabInteractionSystem) -> bool:
	if is_cutting_active or not interaction_system.can_accept_produced_item():
		return false
	var ingredient_id := WholeVegetableFactory.normalize_ingredient_id(item_on_board)
	if ingredient_id.is_empty():
		return false
	var visual := active_visual
	if not is_instance_valid(visual):
		visual = WholeVegetableFactory.create_sliced(ingredient_id)
	if not interaction_system.hold_produced_item(
		"sliced_%s" % ingredient_id,
		"Geschnittene %s" % WholeVegetableFactory.display_name(ingredient_id),
		visual
	):
		return false
	active_visual = null
	item_on_board = ""
	chop_progress = 0
	is_chopped = false
	return true


func _spawn_board_visual() -> void:
	_clear_board_visual()
	if not is_instance_valid(board_surface):
		return
	var ingredient_id := WholeVegetableFactory.normalize_ingredient_id(item_on_board)
	if ingredient_id.is_empty():
		return
	if is_chopped:
		active_visual = WholeVegetableFactory.create_sliced(ingredient_id)
	elif chop_progress > 0:
		active_visual = WholeVegetableFactory.create_cut_stage(ingredient_id, chop_progress, SLICES_REQUIRED)
	else:
		active_visual = WholeVegetableFactory.create_whole(ingredient_id)
	if not is_instance_valid(active_visual):
		return
	board_surface.add_child(active_visual)
	active_visual.transform = Transform3D.IDENTITY
	if is_chopped:
		active_visual.position.y = 0.018
	elif chop_progress > 0:
		active_visual.position.y = 0.0
	else:
		active_visual.position.y = _whole_contact_height(ingredient_id)


func _whole_contact_height(ingredient_id: String) -> float:
	match ingredient_id:
		"onion", "tomato":
			return 0.06
		"cucumber":
			return 0.035
		"lettuce":
			return 0.07
		"red_cabbage":
			return 0.09
	return 0.05


func _clear_board_visual() -> void:
	if is_instance_valid(active_visual):
		active_visual.queue_free()
	active_visual = null


func _release_player_lock() -> void:
	if is_instance_valid(_player_camera):
		_player_camera.current = true
	if is_instance_valid(_player) and _player.has_method("set_cutting_input_locked"):
		_player.call("set_cutting_input_locked", false)


func _clear_cutting_references() -> void:
	_interaction_system = null
	_player = null
	_player_camera = null


func _build_cut_sounds() -> void:
	if is_instance_valid(cut_audio) and cut_audio.stream == null:
		cut_audio.stream = _make_knife_sound(false)
	if is_instance_valid(finish_audio) and finish_audio.stream == null:
		finish_audio.stream = _make_knife_sound(true)


func _make_knife_sound(finishing: bool) -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.12 if finishing else 0.075
	var sample_count := int(float(sample_rate) * duration)
	var sample_data := PackedByteArray()
	sample_data.resize(sample_count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 9137 if finishing else 4211
	for index in sample_count:
		var time := float(index) / float(sample_rate)
		var envelope := exp(-time * (25.0 if finishing else 42.0))
		var tone := sin(TAU * (410.0 if finishing else 760.0) * time) * 0.38
		var noise := random.randf_range(-1.0, 1.0) * 0.5
		var sample := clampf((tone + noise) * envelope, -1.0, 1.0)
		sample_data.encode_s16(index * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = sample_data
	return stream
