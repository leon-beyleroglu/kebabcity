class_name LavashAssembly
extends Area3D

signal topping_added(ingredient_name: String, toppings: Array[String])
signal finalized(toppings: Array[String])

const ROLLED_DONER_SCENE := preload("res://RolledDoener.tscn")
const VEGETABLE_TOPPINGS: Array[String] = [
	"onion",
	"cucumber",
	"lettuce",
	"tomato",
	"red_cabbage",
]
const ALLOWED_TOPPINGS: Array[String] = [
	"meat",
	"onion",
	"cucumber",
	"lettuce",
	"tomato",
	"red_cabbage",
	"garlic_sauce",
	"cocktail_sauce",
]

@export var lavash_placed := true
@export var is_baked := true
@export var topping_container_path := NodePath("ToppingContainer")
@export var flat_lavash_path := NodePath("FlatLavash")
@export var rolled_container_path := NodePath("RolledContainer")

var is_rolled := false
var current_toppings: Array[String] = []

@onready var topping_container := get_node_or_null(topping_container_path) as Node3D
@onready var flat_lavash := get_node_or_null(flat_lavash_path) as Node3D
@onready var rolled_container := get_node_or_null(rolled_container_path) as Node3D


func _ready() -> void:
	add_to_group("durum_assembly")
	collision_layer = 1 << 7
	collision_mask = 0
	monitoring = false
	monitorable = true
	var saved_toppings: Variant = get_meta("ingredients", [])
	var saved_is_rolled := bool(get_meta("is_rolled", false))
	current_toppings.clear()
	if saved_toppings is Array and not saved_toppings.is_empty():
		restore_toppings(saved_toppings)
	is_rolled = saved_is_rolled
	if is_rolled:
		_apply_rolled_visual()
	else:
		_set_flat_visual_visible(true)
	_sync_metadata()


func can_add_topping(ingredient_name: String) -> bool:
	return (
		lavash_placed
		and is_baked
		and not is_rolled
		and ALLOWED_TOPPINGS.has(_normalize_topping(ingredient_name))
	)


func add_topping(ingredient_name: String, topping_visual: Node3D = null) -> bool:
	var topping := _normalize_topping(ingredient_name)
	if not can_add_topping(topping):
		return false
	var container := _get_topping_container()
	if not is_instance_valid(container):
		return false
	var visual := topping_visual
	if not is_instance_valid(visual):
		visual = _create_topping_visual(topping)
	if not is_instance_valid(visual):
		return false
	if visual.get_parent() == null:
		container.add_child(visual)
	elif visual.get_parent() != container:
		visual.reparent(container, false)
	var topping_index := current_toppings.size()
	visual.name = "Topping_%02d_%s" % [topping_index + 1, topping.to_pascal_case()]
	visual.position = _topping_position(topping_index)
	visual.rotation = Vector3(
		randf_range(-0.06, 0.06),
		randf_range(-PI, PI),
		randf_range(-0.08, 0.08)
	)
	visual.scale = Vector3.ONE
	visual.visible = true
	_disable_topping_collisions(visual)
	current_toppings.append(topping)
	_sync_metadata()
	topping_added.emit(topping, get_toppings())
	return true


func restore_toppings(toppings: Array, _visual_factory := Callable()) -> void:
	_clear_topping_visuals()
	current_toppings.clear()
	is_rolled = false
	for raw_topping: Variant in toppings:
		var topping := _normalize_topping(String(raw_topping))
		if not topping.is_empty():
			add_topping(topping)
	_sync_metadata()


func load_state(state: Dictionary) -> void:
	lavash_placed = bool(state.get("is_present", true))
	is_baked = bool(state.get("is_baked", true))
	is_rolled = false
	var toppings: Variant = state.get("toppings", state.get("ingredients", []))
	if toppings is Array:
		restore_toppings(toppings)
	if bool(state.get("is_rolled", false)):
		is_rolled = true
		_apply_rolled_visual()
	_sync_metadata()


func get_toppings() -> Array[String]:
	return current_toppings.duplicate()


func can_finalize() -> bool:
	return lavash_placed and is_baked and not is_rolled and not current_toppings.is_empty()


func roll(_animate := true) -> bool:
	if not can_finalize():
		return false
	is_rolled = true
	_sync_metadata()
	var rolled := ROLLED_DONER_SCENE.instantiate() as RolledDoener
	if not is_instance_valid(rolled):
		is_rolled = false
		_sync_metadata()
		return false
	rolled.configure(current_toppings)
	rolled.set_meta("save_slot_index", int(get_meta("save_slot_index", 0)))
	var station: Node
	if has_meta("prep_station"):
		station = get_meta("prep_station") as Node
	if is_instance_valid(station) and station.has_method("replace_item"):
		if not bool(station.call("replace_item", self, rolled, "durum_assembly")):
			rolled.queue_free()
			is_rolled = false
			_sync_metadata()
			return false
	else:
		var old_parent := get_parent()
		if not is_instance_valid(old_parent):
			rolled.queue_free()
			is_rolled = false
			_sync_metadata()
			return false
		var old_transform := global_transform
		old_parent.add_child(rolled)
		rolled.global_transform = old_transform
	finalized.emit(get_toppings())
	queue_free()
	return true


func finalize_meal() -> Dictionary:
	if not is_rolled:
		return {}
	var toppings := get_toppings()
	return {
		"id": "finished_durum",
		"is_baked": is_baked,
		"is_rolled": true,
		"ingredients": toppings,
		"toppings": toppings,
	}


func get_save_data() -> Dictionary:
	return {
		"is_present": lavash_placed,
		"is_baked": is_baked,
		"is_rolled": is_rolled,
		"toppings": get_toppings(),
	}


func _create_topping_visual(topping: String) -> Node3D:
	var cluster := Node3D.new()
	var piece_count := 6
	match topping:
		"onion":
			piece_count = 4
		"cucumber", "tomato":
			piece_count = 5
		"red_cabbage", "meat":
			piece_count = 7
	for piece_index in piece_count:
		var piece := MeshInstance3D.new()
		piece.name = "Piece_%02d" % [piece_index + 1]
		piece.mesh = _mesh_for_topping(topping, piece_index)
		piece.position = Vector3(
			randf_range(-0.075, 0.075),
			float(piece_index % 3) * 0.004,
			randf_range(-0.055, 0.055)
		)
		piece.rotation = Vector3(
			randf_range(-0.14, 0.14),
			randf_range(-PI, PI),
			randf_range(-0.14, 0.14)
		)
		cluster.add_child(piece)
	return cluster


func _mesh_for_topping(topping: String, piece_index: int) -> PrimitiveMesh:
	match topping:
		"onion":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.021 + float(piece_index % 2) * 0.004
			ring.outer_radius = ring.inner_radius + 0.006
			ring.rings = 14
			ring.ring_segments = 6
			ring.material = _material(Color("efe3d0") if piece_index % 2 == 0 else Color("b77ab7"), 0.62)
			return ring
		"cucumber":
			var disc := CylinderMesh.new()
			disc.top_radius = 0.033
			disc.bottom_radius = 0.033
			disc.height = 0.007
			disc.radial_segments = 16
			disc.material = _material(Color("4d9b46") if piece_index % 2 == 0 else Color("90c765"), 0.58)
			return disc
		"lettuce":
			var leaf := BoxMesh.new()
			leaf.size = Vector3(0.065, 0.006, 0.04 + float(piece_index % 2) * 0.012)
			leaf.material = _material(Color("78bd4f") if piece_index % 2 == 0 else Color("a2d56c"), 0.88)
			return leaf
		"tomato":
			var tomato_chunk := BoxMesh.new()
			tomato_chunk.size = Vector3(0.045, 0.018, 0.035)
			tomato_chunk.material = _material(Color("e6372e") if piece_index % 2 == 0 else Color("f15a3c"), 0.34)
			return tomato_chunk
		"red_cabbage":
			var cabbage_strand := BoxMesh.new()
			cabbage_strand.size = Vector3(0.075, 0.007, 0.012)
			cabbage_strand.material = _material(Color("713182") if piece_index % 2 == 0 else Color("9b58a4"), 0.76)
			return cabbage_strand
		"meat":
			var meat_strip := BoxMesh.new()
			meat_strip.size = Vector3(0.07, 0.014, 0.025)
			meat_strip.material = _material(Color("75401f") if piece_index % 3 else Color("3e2114"), 0.7)
			return meat_strip
		"garlic_sauce", "cocktail_sauce":
			var sauce_drop := CylinderMesh.new()
			sauce_drop.top_radius = 0.035
			sauce_drop.bottom_radius = 0.04
			sauce_drop.height = 0.005
			sauce_drop.material = _material(Color("ead7b5") if topping == "garlic_sauce" else Color("c64a28"), 0.24)
			return sauce_drop
	var fallback := BoxMesh.new()
	fallback.size = Vector3(0.04, 0.01, 0.04)
	fallback.material = _material(Color.WHITE, 0.8)
	return fallback


func _topping_position(index: int) -> Vector3:
	var anchors := _get_topping_anchors()
	var anchor_position := Vector3(0.0, 0.0, randf_range(-0.15, 0.15))
	if not anchors.is_empty():
		anchor_position = anchors[index % anchors.size()].position
	return anchor_position + Vector3(
		randf_range(-0.04, 0.04),
		0.005 * float(index + 1),
		randf_range(-0.025, 0.025)
	)


func _get_topping_anchors() -> Array[Marker3D]:
	var anchors: Array[Marker3D] = []
	var container := _get_topping_container()
	if not is_instance_valid(container):
		return anchors
	for child in container.get_children():
		var marker := child as Marker3D
		if is_instance_valid(marker):
			anchors.append(marker)
	return anchors


func _get_topping_container() -> Node3D:
	if not is_instance_valid(topping_container):
		topping_container = get_node_or_null(topping_container_path) as Node3D
	if not is_instance_valid(topping_container):
		topping_container = get_node_or_null("IngredientSocket") as Node3D
	return topping_container


func _get_rolled_container() -> Node3D:
	if not is_instance_valid(rolled_container):
		rolled_container = get_node_or_null(rolled_container_path) as Node3D
	if not is_instance_valid(rolled_container):
		rolled_container = Node3D.new()
		rolled_container.name = "RolledContainer"
		add_child(rolled_container)
	return rolled_container


func _apply_rolled_visual() -> void:
	_set_flat_visual_visible(false)
	var container := _get_topping_container()
	if is_instance_valid(container):
		container.visible = false
		container.scale = Vector3.ONE
	var rolled_parent := _get_rolled_container()
	rolled_parent.visible = true
	if rolled_parent.get_child_count() == 0:
		var rolled_visual := ROLLED_DONER_SCENE.instantiate() as Node3D
		if is_instance_valid(rolled_visual):
			rolled_parent.add_child(rolled_visual)
			rolled_visual.transform = Transform3D.IDENTITY


func _set_flat_visual_visible(value: bool) -> void:
	if not is_instance_valid(flat_lavash):
		flat_lavash = get_node_or_null(flat_lavash_path) as Node3D
	if is_instance_valid(flat_lavash):
		flat_lavash.visible = value
		if value:
			flat_lavash.scale = Vector3.ONE
	var container := _get_topping_container()
	if is_instance_valid(container):
		container.visible = value


func _clear_topping_visuals() -> void:
	var container := _get_topping_container()
	if not is_instance_valid(container):
		return
	for child in container.get_children():
		if child is Marker3D:
			continue
		child.free()


func _disable_topping_collisions(root: Node) -> void:
	var collision_object := root as CollisionObject3D
	if is_instance_valid(collision_object):
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
		if collision_object is Area3D:
			(collision_object as Area3D).monitoring = false
			(collision_object as Area3D).monitorable = false
	var collision_shape := root as CollisionShape3D
	if is_instance_valid(collision_shape):
		collision_shape.disabled = true
	for child in root.get_children():
		_disable_topping_collisions(child)


func _sync_metadata() -> void:
	set_meta("durum_assembly", true)
	set_meta("item_id", "durum_assembly")
	set_meta("is_present", lavash_placed)
	set_meta("is_baked", is_baked)
	set_meta("is_rolled", is_rolled)
	set_meta("ingredients", current_toppings.duplicate())
	set_meta("placed_count", current_toppings.size())


func _normalize_topping(raw_id: String) -> String:
	var normalized := raw_id.strip_edges().to_lower()
	if normalized.begins_with("sliced_"):
		normalized = normalized.trim_prefix("sliced_")
	if normalized == "salad":
		normalized = "lettuce"
	elif normalized == "cut_meat":
		normalized = "meat"
	return normalized if ALLOWED_TOPPINGS.has(normalized) else ""


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
