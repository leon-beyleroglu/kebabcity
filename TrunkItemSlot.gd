class_name TrunkItemSlot
extends PanelContainer

const ITEM_ICONS := {
	"onion": preload("res://textures/ingredients/onion_slice.svg"),
	"lettuce": preload("res://textures/ingredients/lettuce_leaf.svg"),
	"cucumber": preload("res://textures/ingredients/cucumber_slice.svg"),
	"tomato": preload("res://textures/ingredients/tomato_slice.svg"),
	"red_cabbage": preload("res://textures/ingredients/red_cabbage_strip.svg"),
}

var inventory_ui: TrunkUI
var source_type: String = "player"
var slot_index: int = 0
var item_data: Dictionary = {}
var icon_rect: TextureRect
var name_label: Label
var count_label: Label
var panel_style := StyleBoxFlat.new()


func _ready() -> void:
	custom_minimum_size = Vector2(88, 92)
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel_style.bg_color = Color(0.08, 0.095, 0.11, 0.96)
	panel_style.border_color = Color(0.34, 0.39, 0.43, 1)
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 5
	panel_style.corner_radius_top_right = 5
	panel_style.corner_radius_bottom_left = 5
	panel_style.corner_radius_bottom_right = 5
	add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	add_child(margin)
	var labels := VBoxContainer.new()
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(labels)
	icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(40, 34)
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(icon_rect)
	name_label = Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 12)
	labels.add_child(name_label)
	count_label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 16)
	count_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.34, 1))
	labels.add_child(count_label)
	_update_display()


func configure(controller: TrunkUI, slot_source: String, index: int) -> void:
	inventory_ui = controller
	source_type = slot_source
	slot_index = index


func set_item(data: Dictionary) -> void:
	item_data = data.duplicate(true)
	_update_display()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_data.is_empty() or not is_instance_valid(inventory_ui):
		return null
	var drag_data := {
		"source": source_type,
		"index": slot_index,
		"item_id": String(item_data.get("id", "")),
		"count": maxi(int(item_data.get("count", 0)), 0),
	}
	set_drag_preview(inventory_ui.create_drag_preview(drag_data))
	return drag_data


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return (
		is_instance_valid(inventory_ui)
		and data is Dictionary
		and inventory_ui.can_drop_on_slot(source_type, slot_index, data)
	)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if is_instance_valid(inventory_ui) and data is Dictionary:
		inventory_ui.drop_on_slot(source_type, slot_index, data)


func _update_display() -> void:
	if not is_instance_valid(name_label) or not is_instance_valid(count_label):
		return
	if item_data.is_empty():
		icon_rect.texture = null
		name_label.text = "Leer"
		name_label.modulate = Color(0.55, 0.58, 0.62, 1)
		count_label.text = ""
		tooltip_text = "Leerer Platz"
		panel_style.border_color = Color(0.34, 0.39, 0.43, 1)
		return
	var item_id := String(item_data.get("id", ""))
	var ingredient_name := WholeVegetableFactory.normalize_ingredient_id(item_id)
	var display_name := WholeVegetableFactory.display_name(ingredient_name)
	icon_rect.texture = get_item_icon(item_id)
	name_label.text = display_name
	name_label.modulate = Color.WHITE
	count_label.text = "×%d" % maxi(int(item_data.get("count", 0)), 0)
	tooltip_text = "%s (%s)" % [display_name, source_type]
	panel_style.border_color = _item_color(ingredient_name)


static func get_item_icon(item_id: String) -> Texture2D:
	var ingredient_name := WholeVegetableFactory.normalize_ingredient_id(item_id)
	return ITEM_ICONS.get(ingredient_name) as Texture2D


func _item_color(ingredient_name: String) -> Color:
	match ingredient_name:
		"onion":
			return Color(0.76, 0.5, 0.8, 1)
		"lettuce":
			return Color(0.43, 0.82, 0.31, 1)
		"cucumber":
			return Color(0.2, 0.65, 0.32, 1)
		"tomato":
			return Color(0.9, 0.25, 0.2, 1)
		"red_cabbage":
			return Color(0.57, 0.24, 0.74, 1)
	return Color(0.65, 0.68, 0.72, 1)
