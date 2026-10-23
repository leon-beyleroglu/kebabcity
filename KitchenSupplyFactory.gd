class_name KitchenSupplyFactory
extends RefCounted

const RAW_SPIT_SCENE := preload("res://scenes/items/RawSpit.tscn")
const SUPPORTED_ITEMS: Array[String] = [
	"sauce_bottle_cocktail",
	"sauce_bottle_garlic",
	"raw_spit",
]
const DISPLAY_NAMES := {
	"sauce_bottle_cocktail": "Cocktailsoße",
	"sauce_bottle_garlic": "Knoblauchsoße",
	"raw_spit": "Roher Dönerspieß",
}


static func normalize_item_id(raw_id: String) -> String:
	var item_id := raw_id.strip_edges().to_lower()
	return item_id if SUPPORTED_ITEMS.has(item_id) else ""


static func display_name(raw_id: String) -> String:
	var item_id := normalize_item_id(raw_id)
	return String(DISPLAY_NAMES.get(item_id, item_id.capitalize()))


static func unit_price(raw_id: String) -> int:
	var item_id := normalize_item_id(raw_id)
	if item_id.begins_with("sauce_bottle_"):
		return 5
	if item_id == "raw_spit":
		return 50
	return 0


static func create_visual(raw_id: String, held := false) -> Node3D:
	var item_id := normalize_item_id(raw_id)
	if item_id == "raw_spit":
		var raw_spit := RAW_SPIT_SCENE.instantiate() as Node3D
		if is_instance_valid(raw_spit) and held:
			raw_spit.scale = Vector3.ONE * 0.42
			raw_spit.rotation = Vector3(deg_to_rad(75.0), 0.0, deg_to_rad(-8.0))
		return raw_spit
	if item_id.begins_with("sauce_bottle_"):
		return _create_sauce_bottle(item_id.trim_prefix("sauce_bottle_"), held)
	return null


static func _create_sauce_bottle(sauce_type: String, held: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "%sSauceBottle" % sauce_type.to_pascal_case()
	root.set_meta("item_id", "sauce_bottle_%s" % sauce_type)

	var sauce_color := Color(0.82, 0.28, 0.12, 1.0) if sauce_type == "cocktail" else Color(0.91, 0.82, 0.65, 1.0)
	var bottle_material := _material(sauce_color, 0.32)
	var cap_material := _material(Color("d9d4c7"), 0.64)
	var label_material := _material(Color("f5ead2") if sauce_type == "garlic" else Color("f6b08f"), 0.72)

	var bottle := MeshInstance3D.new()
	var bottle_mesh := CylinderMesh.new()
	bottle_mesh.top_radius = 0.075
	bottle_mesh.bottom_radius = 0.09
	bottle_mesh.height = 0.31
	bottle_mesh.radial_segments = 16
	bottle_mesh.material = bottle_material
	bottle.mesh = bottle_mesh
	bottle.position.y = 0.16
	root.add_child(bottle)

	var shoulder := MeshInstance3D.new()
	var shoulder_mesh := SphereMesh.new()
	shoulder_mesh.radius = 0.074
	shoulder_mesh.height = 0.11
	shoulder_mesh.material = bottle_material
	shoulder.mesh = shoulder_mesh
	shoulder.position.y = 0.325
	root.add_child(shoulder)

	var neck := MeshInstance3D.new()
	var neck_mesh := CylinderMesh.new()
	neck_mesh.top_radius = 0.032
	neck_mesh.bottom_radius = 0.045
	neck_mesh.height = 0.09
	neck_mesh.radial_segments = 12
	neck_mesh.material = bottle_material
	neck.mesh = neck_mesh
	neck.position.y = 0.385
	root.add_child(neck)

	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.042
	cap_mesh.bottom_radius = 0.042
	cap_mesh.height = 0.055
	cap_mesh.radial_segments = 12
	cap_mesh.material = cap_material
	cap.mesh = cap_mesh
	cap.position.y = 0.455
	root.add_child(cap)

	var label := MeshInstance3D.new()
	var label_mesh := CylinderMesh.new()
	label_mesh.top_radius = 0.092
	label_mesh.bottom_radius = 0.092
	label_mesh.height = 0.105
	label_mesh.radial_segments = 16
	label_mesh.material = label_material
	label.mesh = label_mesh
	label.position.y = 0.18
	root.add_child(label)

	if held:
		root.scale = Vector3.ONE * 0.78
		root.rotation = Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(-8.0))
	return root


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
