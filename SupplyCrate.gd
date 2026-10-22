class_name SupplyCrate
extends StaticBody3D

@export_enum("onion", "cucumber", "lettuce", "tomato", "red_cabbage")
var ingredient_type: String = "onion"

@onready var pickup_area: Area3D = $PickupArea
@onready var preview_items: Node3D = $PreviewItems


func _ready() -> void:
	ingredient_type = WholeVegetableFactory.normalize_ingredient_id(ingredient_type)
	if ingredient_type.is_empty():
		ingredient_type = "onion"
	pickup_area.collision_layer = KebabInteractionSystem.INTERACTION_LAYER
	pickup_area.collision_mask = 0
	pickup_area.set_meta("supply_crate_owner", self)
	set_meta("supply_crate_owner", self)
	_build_preview()


func interact(interaction_system: KebabInteractionSystem) -> bool:
	if not is_instance_valid(interaction_system) or not interaction_system.can_accept_produced_item():
		return false
	var visual := WholeVegetableFactory.create_whole(ingredient_type)
	if not is_instance_valid(visual):
		return false
	return interaction_system.hold_produced_item(
		"whole_%s" % ingredient_type,
		"Ganze %s" % WholeVegetableFactory.display_name(ingredient_type),
		visual
	)


func _build_preview() -> void:
	for child in preview_items.get_children():
		child.queue_free()
	for index in 5:
		var vegetable := WholeVegetableFactory.create_whole(ingredient_type)
		if not is_instance_valid(vegetable):
			continue
		preview_items.add_child(vegetable)
		var angle := TAU * float(index) / 5.0
		vegetable.position = Vector3(cos(angle) * 0.18, 0.02 + float(index % 2) * 0.055, sin(angle) * 0.12)
		vegetable.rotation.y = angle

