class_name OvenStation
extends StaticBody3D

var _save_callback: Callable
var _load_callback: Callable


func _ready() -> void:
	add_to_group("oven")
	add_to_group("oven_interaction")
	set_meta("oven_interaction", true)


func configure_persistence(save_callback: Callable, load_callback: Callable) -> void:
	_save_callback = save_callback
	_load_callback = load_callback


func get_save_data() -> Dictionary:
	if not _save_callback.is_valid():
		return {
			"item_type": "",
			"timer_progress": 0.0,
			"is_baked": false,
			"slots": [],
		}
	var data: Variant = _save_callback.call()
	return data if data is Dictionary else {}


func load_save_data(data: Dictionary) -> bool:
	if not _load_callback.is_valid():
		return false
	_load_callback.call(data)
	return true
