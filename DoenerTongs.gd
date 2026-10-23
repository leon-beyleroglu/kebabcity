class_name DoenerTongs
extends Node3D

var meat_container: Node3D


static func create_viewmodel(with_meat := true) -> DoenerTongs:
	var tongs := DoenerTongs.new()
	tongs.name = "DoenerTongsViewmodel"
	tongs._build_viewmodel()
	tongs.set_meat_visible(with_meat)
	return tongs


static func create_meat_portion_visual() -> Node3D:
	var cluster := Node3D.new()
	cluster.name = "ShavedMeatPortion"
	for strip_index in 8:
		var strip := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(
			randf_range(0.045, 0.075),
			randf_range(0.008, 0.014),
			randf_range(0.018, 0.03)
		)
		mesh.material = _meat_material(strip_index)
		strip.mesh = mesh
		strip.position = Vector3(
			randf_range(-0.07, 0.07),
			float(strip_index % 3) * 0.009,
			randf_range(-0.055, 0.055)
		)
		strip.rotation = Vector3(
			randf_range(-0.12, 0.12),
			randf_range(-PI, PI),
			randf_range(-0.12, 0.12)
		)
		cluster.add_child(strip)
	return cluster


func set_meat_visible(value: bool) -> void:
	if is_instance_valid(meat_container):
		meat_container.visible = value


func _build_viewmodel() -> void:
	if get_child_count() > 0:
		return
	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	visual_root.position = Vector3(0.02, -0.035, -0.14)
	visual_root.rotation = Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(-5.0))
	add_child(visual_root)

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("aeb7bc")
	steel.metallic = 0.85
	steel.roughness = 0.24
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color("25282a")
	grip.roughness = 0.76

	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.018, 0.018, 0.42)
		arm_mesh.material = steel
		arm.mesh = arm_mesh
		arm.position = Vector3(side * 0.035, 0.0, -0.12)
		arm.rotation.y = side * deg_to_rad(3.5)
		visual_root.add_child(arm)

		var handle := MeshInstance3D.new()
		var handle_mesh := BoxMesh.new()
		handle_mesh.size = Vector3(0.026, 0.028, 0.15)
		handle_mesh.material = grip
		handle.mesh = handle_mesh
		handle.position = Vector3(side * 0.025, 0.0, 0.14)
		visual_root.add_child(handle)

	var hinge := MeshInstance3D.new()
	var hinge_mesh := SphereMesh.new()
	hinge_mesh.radius = 0.026
	hinge_mesh.height = 0.052
	hinge_mesh.material = steel
	hinge.mesh = hinge_mesh
	hinge.position = Vector3(0.0, 0.0, 0.22)
	visual_root.add_child(hinge)

	meat_container = create_meat_portion_visual()
	meat_container.name = "HeldMeat"
	meat_container.position = Vector3(0.0, -0.005, -0.34)
	meat_container.scale = Vector3.ONE * 0.72
	visual_root.add_child(meat_container)


static func _meat_material(index: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("4a2818") if index % 3 == 0 else Color("784321")
	material.roughness = 0.72
	return material
