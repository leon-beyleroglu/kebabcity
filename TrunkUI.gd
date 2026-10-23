class_name TrunkUI
extends CanvasLayer

@onready var root_control: Control = $Control
@onready var player_grid: GridContainer = %PlayerGrid
@onready var trunk_grid: GridContainer = %TrunkGrid
@onready var player_count_label: Label = %PlayerCountLabel
@onready var trunk_count_label: Label = %TrunkCountLabel
@onready var close_button: Button = %CloseButton

var active_trunk: TrunkInteractionArea
var player_slot_controls: Array[TrunkItemSlot] = []
var trunk_slot_controls: Array[TrunkItemSlot] = []
var _locked_player: Node
var _opened_frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("trunk_ui")
	_build_slots(
		player_grid,
		player_slot_controls,
		"player",
		GameState.PLAYER_MAX_SLOTS
	)
	_build_slots(
		trunk_grid,
		trunk_slot_controls,
		"trunk",
		GameState.TRUNK_MAX_SLOTS
	)
	close_button.pressed.connect(close_trunk)
	if not GameState.inventory_slots_changed.is_connected(refresh):
		GameState.inventory_slots_changed.connect(refresh)
	root_control.visible = false


func open_for_trunk(trunk: TrunkInteractionArea) -> void:
	if not is_instance_valid(trunk):
		return
	active_trunk = trunk
	_locked_player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(_locked_player) and _locked_player.has_method("set_cutting_input_locked"):
		_locked_player.call("set_cutting_input_locked", true)
	get_tree().paused = false
	root_control.visible = true
	_opened_frame = Engine.get_process_frames()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	refresh()


func close_trunk() -> void:
	if not root_control.visible:
		return
	root_control.visible = false
	active_trunk = null
	if is_instance_valid(_locked_player) and _locked_player.has_method("set_cutting_input_locked"):
		_locked_player.call("set_cutting_input_locked", false)
	_locked_player = null
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func refresh() -> void:
	if not is_instance_valid(root_control):
		return
	for slot_index in GameState.PLAYER_MAX_SLOTS:
		player_slot_controls[slot_index].set_item(
			GameState.get_inventory_slot("player", slot_index)
		)
	for slot_index in GameState.TRUNK_MAX_SLOTS:
		trunk_slot_controls[slot_index].set_item(
			GameState.get_inventory_slot("trunk", slot_index)
		)
	player_count_label.text = "%d/%d Slots" % [
		_count_used_slots(GameState.player_slots),
		GameState.PLAYER_MAX_SLOTS,
	]
	trunk_count_label.text = "%d/%d Slots" % [
		_count_used_slots(GameState.trunk_slots),
		GameState.TRUNK_MAX_SLOTS,
	]


func can_drop_on_slot(target_container: String, target_index: int, data: Dictionary) -> bool:
	var source_container := String(data.get("from", ""))
	var source_index := int(data.get("slot_index", -1))
	var item_data: Variant = data.get("item_data", {})
	if not item_data is Dictionary or item_data.is_empty():
		return false
	if not _is_valid_slot(source_container, source_index):
		return false
	if not _is_valid_slot(target_container, target_index):
		return false
	return source_container != target_container or source_index != target_index


func drop_on_slot(target_container: String, target_index: int, data: Dictionary) -> void:
	if not can_drop_on_slot(target_container, target_index, data):
		return
	GameState.move_inventory_slot(
		String(data.get("from", "")),
		int(data.get("slot_index", -1)),
		target_container,
		target_index
	)


func create_drag_preview(data: Dictionary) -> Control:
	var item_data := data.get("item_data", {}) as Dictionary
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(72, 72)
	preview.texture = TrunkItemSlot.get_item_icon(String(item_data.get("id", "")))
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count_badge := Label.new()
	count_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count_badge.offset_left = -42.0
	count_badge.offset_top = -28.0
	count_badge.offset_right = -2.0
	count_badge.offset_bottom = -2.0
	count_badge.add_theme_color_override("font_color", Color(1, 0.86, 0.28, 1))
	count_badge.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.05, 1))
	count_badge.add_theme_constant_override("outline_size", 5)
	count_badge.add_theme_font_size_override("font_size", 18)
	count_badge.text = "1x" if String(item_data.get("type", "")) == "weapon" else "×%d" % int(item_data.get("count", 0))
	count_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	preview.add_child(count_badge)
	return preview


func _input(event: InputEvent) -> void:
	if not root_control.visible or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var physical_key := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
	if physical_key == KEY_ESCAPE or physical_key == KEY_E:
		if physical_key == KEY_E and Engine.get_process_frames() <= _opened_frame:
			return
		close_trunk()
		get_viewport().set_input_as_handled()


func _build_slots(
	grid: GridContainer,
	slot_collection: Array[TrunkItemSlot],
	source: String,
	slot_count: int
) -> void:
	for slot_index in slot_count:
		var slot := TrunkItemSlot.new()
		slot.name = "%sSlot%02d" % [source.capitalize(), slot_index + 1]
		grid.add_child(slot)
		slot.configure(self, source, slot_index)
		slot_collection.append(slot)


func _is_valid_slot(container_name: String, slot_index: int) -> bool:
	if container_name == "player":
		return slot_index >= 0 and slot_index < GameState.PLAYER_MAX_SLOTS
	if container_name == "trunk":
		return slot_index >= 0 and slot_index < GameState.TRUNK_MAX_SLOTS
	return false


func _count_used_slots(slots: Array[Dictionary]) -> int:
	var used_slots := 0
	for item: Dictionary in slots:
		if not item.is_empty():
			used_slots += 1
	return used_slots
