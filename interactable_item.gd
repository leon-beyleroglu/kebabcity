class_name InteractableItem
extends Area3D

var item_id := ""
var display_name := "Gegenstand"
var source_visual: Node3D
var original_transform := Transform3D.IDENTITY
var consumed_on_pickup := false
var available := true

func configure(id: String, label: String, visual: Node3D, consume := false) -> void:
	item_id = id
	display_name = label
	source_visual = visual
	consumed_on_pickup = consume
	original_transform = global_transform
	collision_layer = 1 << 7
	collision_mask = 0
	monitoring = false
	monitorable = true
	set_meta("interactable", true)

func pickup() -> void:
	available = false
	collision_layer = 0
	if is_instance_valid(source_visual):
		source_visual.visible = false

func restore() -> void:
	if consumed_on_pickup:
		queue_free()
		return
	available = true
	global_transform = original_transform
	collision_layer = 1 << 7
	if is_instance_valid(source_visual):
		source_visual.visible = true

func prompt(holding_something: bool) -> String:
	if holding_something:
		return "Drücke [E], um %s auszutauschen" % display_name
	return "Drücke [E], um %s aufzuheben" % display_name
