class_name TrunkUI
extends CanvasLayer

const SLOT_COUNT := 20

@onready var root_control: Control = $Control
@onready var player_grid: GridContainer = %PlayerGrid
@onready var trunk_grid: GridContainer = %TrunkGrid
@onready var player_count_label: Label = %PlayerCountLabel
@onready var trunk_count_label: Label = %TrunkCountLabel
@onready var close_button: Button = %CloseButton

var active_trunk: TrunkInteractionArea
var player_slots: Array[TrunkItemSlot] = []
var trunk_slots: Array[TrunkItemSlot] = []
var _locked_player: Node
var _opened_frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("trunk_ui")
	_build_slots(player_grid, player_slots, "player")
	_build_slots(trunk_grid, trunk_slots, "trunk")
	close_button.pressed.connect(close_trunk)
	if not GameState.inventory_item_changed.is_connected(_on_player_inventory_changed):
		GameState.inventory_item_changed.connect(_on_player_inventory_changed)
	root_control.visible = false


func open_for_trunk(trunk: TrunkInteractionArea) -> void:
	if not is_instance_valid(trunk):
		return
	if is_instance_valid(active_trunk) and active_trunk != trunk:
		_disconnect_active_trunk()
	active_trunk = trunk
	if not active_trunk.trunk_inventory_changed.is_connected(refresh):
		active_trunk.trunk_inventory_changed.connect(refresh)
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
	_disconnect_active_trunk()
	active_trunk = null
	if is_instance_valid(_locked_player) and _locked_player.has_method("set_cutting_input_locked"):
		_locked_player.call("set_cutting_input_locked", false)
	_locked_player = null
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func refresh() -> void:
	if not is_instance_valid(active_trunk):
		return
	for slot_index in SLOT_COUNT:
		var player_item: Dictionary = {}
		if slot_index < GameState.INVENTORY_ITEM_IDS.size():
			var item_id := GameState.INVENTORY_ITEM_IDS[slot_index]
			var count := PlayerInventory.get_count(item_id)
			if count > 0:
				player_item = {"id": item_id, "count": count}
		player_slots[slot_index].set_item(player_item)
		trunk_slots[slot_index].set_item(active_trunk.get_item_at(slot_index))
	player_count_label.text = "%d Gegenstände" % _get_player_item_total()
	trunk_count_label.text = "%d/%d Plätze" % [
		active_trunk.get_used_slot_count(),
		active_trunk.max_slots,
	]


func can_drop_on_slot(target_source: String, target_index: int, data: Dictionary) -> bool:
	if not is_instance_valid(active_trunk):
		return false
	var source := String(data.get("source", ""))
	var item_id := String(data.get("item_id", ""))
	var count := int(data.get("count", 0))
	if count <= 0 or not GameState.INVENTORY_ITEM_IDS.has(item_id):
		return false
	if target_source == "player":
		return source == "trunk"
	if target_source != "trunk":
		return false
	if source == "player":
		return active_trunk.can_store_item(item_id, target_index)
	if source == "trunk":
		return target_index != int(data.get("index", -1))
	return false


func drop_on_slot(target_source: String, target_index: int, data: Dictionary) -> void:
	if not can_drop_on_slot(target_source, target_index, data):
		return
	var source := String(data.get("source", ""))
	var changed := false
	if source == "player" and target_source == "trunk":
		changed = active_trunk.transfer_from_player(
			String(data.get("item_id", "")),
			int(data.get("count", 0)),
			target_index
		)
	elif source == "trunk" and target_source == "player":
		changed = active_trunk.transfer_to_player(int(data.get("index", -1)))
	elif source == "trunk" and target_source == "trunk":
		changed = active_trunk.move_item(int(data.get("index", -1)), target_index)
	if changed:
		refresh()


func create_drag_preview(data: Dictionary) -> Control:
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(72, 72)
	preview.texture = TrunkItemSlot.get_item_icon(String(data.get("item_id", "")))
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
	count_badge.text = "×%d" % int(data.get("count", 0))
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
	source: String
) -> void:
	for slot_index in SLOT_COUNT:
		var slot := TrunkItemSlot.new()
		slot.name = "%sSlot%02d" % [source.capitalize(), slot_index + 1]
		grid.add_child(slot)
		slot.configure(self, source, slot_index)
		slot_collection.append(slot)


func _get_player_item_total() -> int:
	var total := 0
	for item_id: String in GameState.INVENTORY_ITEM_IDS:
		total += PlayerInventory.get_count(item_id)
	return total


func _disconnect_active_trunk() -> void:
	if (
		is_instance_valid(active_trunk)
		and active_trunk.trunk_inventory_changed.is_connected(refresh)
	):
		active_trunk.trunk_inventory_changed.disconnect(refresh)


func _on_player_inventory_changed(_item_id: String, _count: int) -> void:
	if root_control.visible:
		refresh()
