class_name WholeVegetableFactory
extends RefCounted

const SUPPORTED_INGREDIENTS: Array[String] = [
	"onion",
	"cucumber",
	"lettuce",
	"tomato",
	"red_cabbage",
]

const DISPLAY_NAMES := {
	"onion": "Zwiebel",
	"cucumber": "Gurke",
	"lettuce": "Salat",
	"tomato": "Tomate",
	"red_cabbage": "Lila Kraut",
}


static func normalize_ingredient_id(raw_id: String) -> String:
	var ingredient_id := raw_id.strip_edges().to_lower()
	ingredient_id = ingredient_id.trim_prefix("whole_").trim_prefix("sliced_")
	if ingredient_id == "salad":
		ingredient_id = "lettuce"
	return ingredient_id if SUPPORTED_INGREDIENTS.has(ingredient_id) else ""


static func stock_id(raw_id: String) -> String:
	var ingredient_id := normalize_ingredient_id(raw_id)
	return "salad" if ingredient_id == "lettuce" else ingredient_id


static func display_name(raw_id: String) -> String:
	var ingredient_id := normalize_ingredient_id(raw_id)
	return String(DISPLAY_NAMES.get(ingredient_id, ingredient_id.capitalize()))


static func create_whole(raw_id: String) -> Node3D:
	var ingredient_id := normalize_ingredient_id(raw_id)
	if ingredient_id.is_empty():
		return null
	var root := Node3D.new()
	root.name = "Whole%s" % ingredient_id.to_pascal_case()
	root.set_meta("ingredient_id", ingredient_id)
	root.set_meta("item_id", "whole_%s" % ingredient_id)
	match ingredient_id:
		"onion":
			_build_onion(root)
		"cucumber":
			_build_cucumber(root)
		"lettuce":
			_build_lettuce(root)
		"tomato":
			_build_tomato(root)
		"red_cabbage":
			_build_red_cabbage(root)
	return root


static func create_sliced(raw_id: String) -> Node3D:
	var ingredient_id := normalize_ingredient_id(raw_id)
	if ingredient_id.is_empty():
		return null
	var root := Node3D.new()
	root.name = "Sliced%s" % ingredient_id.to_pascal_case()
	root.set_meta("ingredient_id", ingredient_id)
	root.set_meta("item_id", "sliced_%s" % ingredient_id)
	var color := _ingredient_color(ingredient_id)
	for index in 7:
		var piece := MeshInstance3D.new()
		piece.name = "Piece%d" % index
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.025 + float(index % 3) * 0.004
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 0.012
		mesh.radial_segments = 12
		mesh.material = _material(color.lightened(0.07 * float(index % 2)), 0.68)
		piece.mesh = mesh
		var angle := TAU * float(index) / 7.0
		piece.position = Vector3(cos(angle) * 0.065, 0.008 + float(index % 2) * 0.014, sin(angle) * 0.045)
		piece.rotation = Vector3(0.0, angle, deg_to_rad(float((index % 3) - 1) * 11.0))
		root.add_child(piece)
	return root


static func create_cut_stage(raw_id: String, stage: int, total_stages: int = 4) -> Node3D:
	var ingredient_id := normalize_ingredient_id(raw_id)
	if ingredient_id.is_empty():
		return null
	var clamped_stage := clampi(stage, 0, total_stages)
	if clamped_stage <= 0:
		return create_whole(ingredient_id)
	if clamped_stage >= total_stages:
		return create_sliced(ingredient_id)

	var root := Node3D.new()
	root.name = "CutStage%d%s" % [clamped_stage, ingredient_id.to_pascal_case()]
	root.set_meta("ingredient_id", ingredient_id)
	root.set_meta("cut_stage", clamped_stage)

	# Keep a shrinking portion of the original vegetable while adding visible cut pieces.
	var remaining := create_whole(ingredient_id)
	if is_instance_valid(remaining):
		root.add_child(remaining)
		var remaining_scale := 1.0 - float(clamped_stage) * 0.18
		remaining.scale = Vector3(remaining_scale, 1.0, 1.0)
		remaining.position = Vector3(
			-0.035 * float(clamped_stage),
			_whole_contact_height(ingredient_id),
			0.0
		)

	var color := _ingredient_color(ingredient_id).lightened(0.08)
	var piece_count := clamped_stage * 2
	for index in piece_count:
		var piece := MeshInstance3D.new()
		piece.name = "CutPiece%d" % index
		if ingredient_id == "cucumber" or ingredient_id == "onion" or ingredient_id == "tomato":
			var disc := CylinderMesh.new()
			disc.top_radius = 0.028 + float(index % 2) * 0.006
			disc.bottom_radius = disc.top_radius
			disc.height = 0.014
			disc.radial_segments = 14
			disc.material = _material(color, 0.7)
			piece.mesh = disc
		else:
			var chunk := BoxMesh.new()
			chunk.size = Vector3(0.038, 0.018, 0.034)
			chunk.material = _material(color, 0.82)
			piece.mesh = chunk
		var column := index % 3
		var row := index / 3
		piece.position = Vector3(0.045 + float(column) * 0.045, 0.012 + float(row) * 0.018, -0.04 + float(index % 2) * 0.075)
		piece.rotation = Vector3(0.0, float(index) * 0.73, deg_to_rad(float((index % 3) - 1) * 8.0))
		root.add_child(piece)
	return root


static func _build_onion(root: Node3D) -> void:
	var body := SphereMesh.new()
	body.radius = 0.08
	body.height = 0.12
	body.radial_segments = 24
	body.rings = 12
	_add_mesh(root, "PaperyBulb", body, _material(Color("b99052"), 0.82))
	var tip := CylinderMesh.new()
	tip.top_radius = 0.006
	tip.bottom_radius = 0.018
	tip.height = 0.035
	tip.radial_segments = 10
	_add_mesh(root, "DryStem", tip, _material(Color("735432"), 0.95), Vector3(0.0, 0.074, 0.0))


static func _build_cucumber(root: Node3D) -> void:
	var body := CapsuleMesh.new()
	body.radius = 0.035
	body.height = 0.28
	body.radial_segments = 20
	body.rings = 8
	var cucumber := _add_mesh(root, "Cucumber", body, _material(Color("174d25"), 0.72))
	cucumber.rotation.z = deg_to_rad(90.0)
	for index in 5:
		var bump := SphereMesh.new()
		bump.radius = 0.004
		bump.height = 0.008
		var x := -0.09 + float(index) * 0.045
		_add_mesh(root, "SkinBump%d" % index, bump, _material(Color("75a94b"), 0.9), Vector3(x, 0.034, 0.0))


static func _build_lettuce(root: Node3D) -> void:
	var colors := [Color("72b948"), Color("8dcc5b"), Color("a8d878")]
	for index in 11:
		var leaf := SphereMesh.new()
		leaf.radius = 0.055 if index > 0 else 0.085
		leaf.height = 0.09 if index > 0 else 0.14
		leaf.radial_segments = 14
		leaf.rings = 7
		var angle := TAU * float(index) / 10.0
		var radius := 0.065 if index > 0 else 0.0
		var position := Vector3(cos(angle) * radius, 0.008 + float(index % 3) * 0.012, sin(angle) * radius)
		_add_mesh(root, "RuffledLeaf%d" % index, leaf, _material(colors[index % colors.size()], 0.96), position)


static func _build_tomato(root: Node3D) -> void:
	var body := SphereMesh.new()
	body.radius = 0.07
	body.height = 0.12
	body.radial_segments = 24
	body.rings = 12
	_add_mesh(root, "Tomato", body, _material(Color("e52f27"), 0.23, 0.34))
	var cap := CylinderMesh.new()
	cap.top_radius = 0.007
	cap.bottom_radius = 0.026
	cap.height = 0.009
	cap.radial_segments = 5
	_add_mesh(root, "TopIndentAndCalyx", cap, _material(Color("2f7d32"), 0.78), Vector3(0.0, 0.064, 0.0))
	var stem := CylinderMesh.new()
	stem.top_radius = 0.004
	stem.bottom_radius = 0.006
	stem.height = 0.026
	stem.radial_segments = 7
	_add_mesh(root, "Stem", stem, _material(Color("356e2f"), 0.85), Vector3(0.0, 0.079, 0.0))


static func _build_red_cabbage(root: Node3D) -> void:
	var body := SphereMesh.new()
	body.radius = 0.11
	body.height = 0.18
	body.radial_segments = 24
	body.rings = 12
	_add_mesh(root, "CabbageHead", body, _material(Color("592468"), 0.88))
	for index in 6:
		var vein := TorusMesh.new()
		vein.inner_radius = 0.086 + float(index % 2) * 0.008
		vein.outer_radius = vein.inner_radius + 0.004
		vein.rings = 24
		vein.ring_segments = 6
		var ring := _add_mesh(root, "LeafVein%d" % index, vein, _material(Color("8f5a9e"), 0.8))
		ring.rotation = Vector3(deg_to_rad(90.0), float(index) * PI / 3.0, 0.0)
		ring.scale = Vector3(1.0, 0.82, 1.0)


static func _ingredient_color(ingredient_id: String) -> Color:
	match ingredient_id:
		"onion":
			return Color("e8d1a1")
		"cucumber":
			return Color("3b873e")
		"lettuce":
			return Color("83c857")
		"tomato":
			return Color("e6372e")
		"red_cabbage":
			return Color("713182")
	return Color.WHITE


static func _whole_contact_height(ingredient_id: String) -> float:
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


static func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


static func _add_mesh(
	root: Node3D,
	mesh_name: String,
	mesh: PrimitiveMesh,
	material: Material,
	position := Vector3.ZERO
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	mesh.material = material
	instance.mesh = mesh
	instance.position = position
	root.add_child(instance)
	return instance
