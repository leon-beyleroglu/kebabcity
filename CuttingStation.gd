class_name CuttingStation
extends StaticBody3D

const CHOPS_REQUIRED := 3

var item_on_board: String = ""
var chop_progress: int = 0
var is_chopped: bool = false
var active_visual: Node3D
var _pending_save_data: Dictionary = {}

@onready var board_surface: Marker3D = $BoardSurface
@onready var station_area: Area3D = $StationArea
@onready var progress_3d: Label3D = $Progress3D


func _ready() -> void:
	add_to_group("cutting_station")
	station_area.collision_layer = KebabInteractionSystem.INTERACTION_LAYER
	station_area.collision_mask = 0
	station_area.set_meta("cutting_station_owner", self)
	set_meta("cutting_station_owner", self)
	if _pending_save_data.is_empty():
		_update_progress_display()
	else:
		var pending_data := _pending_save_data
		_pending_save_data = {}
		load_save_data(pending_data)


func interact(interaction_system: KebabInteractionSystem) -> bool:
	if not is_instance_valid(interaction_system):
		return false
	if item_on_board.is_empty():
		return _place_held_whole(interaction_system)
	if is_chopped:
		return _pick_up_sliced(interaction_system)
	if not interaction_system.can_accept_produced_item():
		return false
	return perform_chop()


func perform_chop() -> bool:
	if item_on_board.is_empty() or is_chopped:
		return false
	chop_progress = mini(chop_progress + 1, CHOPS_REQUIRED)
	if is_instance_valid(active_visual):
		var tween := create_tween()
		tween.tween_property(active_visual, "rotation:y", active_visual.rotation.y + 0.12, 0.05)
		tween.tween_property(active_visual, "rotation:y", active_visual.rotation.y, 0.05)
	if chop_progress >= CHOPS_REQUIRED:
		var ingredient_id := WholeVegetableFactory.normalize_ingredient_id(item_on_board)
		item_on_board = "sliced_%s" % ingredient_id
		is_chopped = true
		_spawn_board_visual()
	_update_progress_display()
	return true


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
	var saved_item := String(data.get("item_on_board", ""))
	var ingredient_id := WholeVegetableFactory.normalize_ingredient_id(saved_item)
	if saved_item.is_empty() or ingredient_id.is_empty():
		item_on_board = ""
		chop_progress = 0
		is_chopped = false
		_clear_board_visual()
		_update_progress_display()
		return true
	is_chopped = bool(data.get("is_chopped", saved_item.begins_with("sliced_")))
	item_on_board = ("sliced_" if is_chopped else "whole_") + ingredient_id
	chop_progress = clampi(int(data.get("chop_progress", CHOPS_REQUIRED if is_chopped else 0)), 0, CHOPS_REQUIRED)
	if is_chopped:
		chop_progress = CHOPS_REQUIRED
	_spawn_board_visual()
	_update_progress_display()
	return true


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
	_update_progress_display()
	return true


func _pick_up_sliced(interaction_system: KebabInteractionSystem) -> bool:
	if not interaction_system.can_accept_produced_item():
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
	_update_progress_display()
	return true


func _spawn_board_visual() -> void:
	_clear_board_visual()
	if not is_instance_valid(board_surface):
		return
	var ingredient_id := WholeVegetableFactory.normalize_ingredient_id(item_on_board)
	if ingredient_id.is_empty():
		return
	active_visual = (
		WholeVegetableFactory.create_sliced(ingredient_id)
		if is_chopped
		else WholeVegetableFactory.create_whole(ingredient_id)
	)
	if not is_instance_valid(active_visual):
		return
	board_surface.add_child(active_visual)
	active_visual.transform = Transform3D.IDENTITY
	# BoardSurface is the exact contact point; primitive origins are centered.
	active_visual.position.y = 0.018 if is_chopped else _whole_contact_height(ingredient_id)


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


func _update_progress_display() -> void:
	if not is_instance_valid(progress_3d):
		return
	if item_on_board.is_empty():
		progress_3d.visible = false
		progress_3d.text = ""
	elif is_chopped:
		progress_3d.visible = true
		progress_3d.text = "FERTIG - E"
	else:
		progress_3d.visible = true
		progress_3d.text = "SCHNEIDEN %d/%d" % [chop_progress, CHOPS_REQUIRED]
