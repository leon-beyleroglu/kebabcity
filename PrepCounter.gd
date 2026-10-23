class_name PrepCounter
extends Area3D

signal stock_updated(ingredient_name: String, current_stock: int)

@export_enum("onion", "cucumber", "lettuce", "tomato", "red_cabbage")
var ingredient_name: String = "onion"
@export_range(1, 100, 1) var max_stock: int = 10
@export var fill_mesh_path: NodePath

var current_stock: int = 10
var fill_mesh: Node3D
var _full_fill_scale := Vector3.ONE


func _ready() -> void:
	add_to_group("prep_counter_container")
	fill_mesh = get_node_or_null(fill_mesh_path) as Node3D
	if is_instance_valid(fill_mesh):
		_full_fill_scale = fill_mesh.scale
	set_meta("prep_counter_container", self)
	set_meta("max_stock", max_stock)
	_sync_from_game_state()
	if not GameState.counter_stock_updated.is_connected(_on_game_state_stock_updated):
		GameState.counter_stock_updated.connect(_on_game_state_stock_updated)


func get_stock() -> int:
	return current_stock


func has_stock(amount: int = 1) -> bool:
	return amount > 0 and current_stock >= amount


func take_portion(amount: int = 1) -> bool:
	if amount <= 0 or not has_stock(amount):
		return false
	if not GameState.consume_counter_ingredient(ingredient_name, amount):
		return false
	# GameState's signal applies the stock and updates the fill visual.
	return true


func refill_from_sliced_item(item_id: String, clear_held_item: Callable) -> bool:
	var sliced_ingredient := WholeVegetableFactory.normalize_ingredient_id(item_id)
	if not item_id.begins_with("sliced_") or sliced_ingredient != ingredient_name:
		return false
	if current_stock >= max_stock:
		return false
	if not clear_held_item.is_valid() or not bool(clear_held_item.call(item_id)):
		return false
	GameState.set_counter_stock(ingredient_name, max_stock)
	return true


func set_stock(value: int, sync_game_state := true) -> void:
	var next_stock := clampi(value, 0, max_stock)
	if sync_game_state:
		GameState.set_counter_stock(ingredient_name, next_stock)
		return
	_apply_stock(next_stock)


func _sync_from_game_state() -> void:
	_apply_stock(clampi(GameState.get_counter_stock(ingredient_name), 0, max_stock))


func _on_game_state_stock_updated(updated_ingredient: String, remaining: int) -> void:
	if WholeVegetableFactory.normalize_ingredient_id(updated_ingredient) != ingredient_name:
		return
	_apply_stock(remaining)


func _apply_stock(value: int) -> void:
	current_stock = clampi(value, 0, max_stock)
	set_meta("current_stock", current_stock)
	_update_fill_visual()
	stock_updated.emit(ingredient_name, current_stock)


func _update_fill_visual() -> void:
	if not is_instance_valid(fill_mesh):
		return
	fill_mesh.visible = current_stock > 0
	if current_stock <= 0:
		return
	var fill_ratio := clampf(float(current_stock) / float(max_stock), 0.0, 1.0)
	fill_mesh.scale = Vector3(
		_full_fill_scale.x,
		_full_fill_scale.y * fill_ratio,
		_full_fill_scale.z
	)
