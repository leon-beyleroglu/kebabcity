extends Node3D
## Wrist at the origin, fingers along -Y, back of hand toward -Z.
## The same anatomical mesh is used by the first and third person rigs.

var handedness := 1.0
var skin: StandardMaterial3D
var fold: StandardMaterial3D
var nail: StandardMaterial3D

func build(side: float) -> void:
	handedness = side
	skin = _material(Color("bd805c"), 0.65)
	fold = _material(Color("a96e50"), 0.8)
	nail = _material(Color("d8ac94"), 0.38)
	var centers: Array[Vector3] = [Vector3(0, 0.035, 0), Vector3(0, 0, 0), Vector3(0, -0.045, 0), Vector3(0, -0.10, 0.003), Vector3(0, -0.15, 0.005), Vector3(0, -0.185, 0.003), Vector3(0, -0.197, 0)]
	var widths: Array[float] = [0.052, 0.056, 0.076, 0.091, 0.09, 0.081, 0.058]
	var depths: Array[float] = [0.033, 0.031, 0.038, 0.039, 0.034, 0.027, 0.014]
	_loft("ShapedPalmAndWrist", centers, widths, depths, skin)
	_ellipsoid("ThumbPad", Vector3(-0.056, -0.07, 0.022), Vector3(0.077, 0.11, 0.045), skin)
	_ellipsoid("OuterPalmPad", Vector3(0.062, -0.103, 0.022), Vector3(0.044, 0.12, 0.035), skin)
	_digit("Index", Vector3(-0.064, -0.17, 0), 0.139, 0.021, -0.07, 0.032)
	_digit("Middle", Vector3(-0.021, -0.183, 0), 0.155, 0.022, -0.018, 0.038)
	_digit("Ring", Vector3(0.023, -0.18, 0), 0.145, 0.021, 0.045, 0.046)
	_digit("Little", Vector3(0.066, -0.157, 0.002), 0.115, 0.017, 0.13, 0.055)
	var thumb_centers: Array[Vector3] = [Vector3(-0.049, -0.037, 0.01), Vector3(-0.08, -0.065, 0.006), Vector3(-0.113, -0.095, 0.01), Vector3(-0.131, -0.121, 0.017), Vector3(-0.134, -0.144, 0.024), Vector3(-0.131, -0.157, 0.028)]
	var thumb_widths: Array[float] = [0.032, 0.028, 0.025, 0.023, 0.018, 0.003]
	var thumb_depths: Array[float] = [0.027, 0.025, 0.023, 0.022, 0.017, 0.003]
	_loft("OpposedThumb", thumb_centers, thumb_widths, thumb_depths, skin)
	_ellipsoid("Thumbnail", Vector3(-0.133, -0.133, -0.003), Vector3(0.027, 0.032, 0.006), nail)
	# Shallow folds lie on the palm; faint tendons run across its back.
	_fold_line("PalmFoldUpper", [Vector3(-0.068, -0.13, 0.035), Vector3(-0.025, -0.144, 0.039), Vector3(0.025, -0.13, 0.039), Vector3(0.066, -0.114, 0.034)], 0.0013)
	_fold_line("PalmFoldLower", [Vector3(-0.061, -0.055, 0.043), Vector3(-0.026, -0.085, 0.042), Vector3(0.022, -0.102, 0.042), Vector3(0.062, -0.098, 0.037)], 0.0012)
	_fold_line("ThumbFold", [Vector3(-0.063, -0.032, 0.03), Vector3(-0.034, -0.064, 0.045), Vector3(-0.035, -0.098, 0.044), Vector3(-0.052, -0.127, 0.036)], 0.001)
	for i in range(3):
		var x := float(i - 1) * 0.035
		var tendon_points: Array[Vector3] = [Vector3(x * 0.5, -0.02, -0.031), Vector3(x * 0.8, -0.07, -0.036), Vector3(x, -0.13, -0.031), Vector3(x, -0.165, -0.025)]
		_loft("DorsalTendon", tendon_points, [0.001, 0.002, 0.0017, 0.0005], [0.001, 0.002, 0.0017, 0.0005], skin)
	_fold_line("WristFold", [Vector3(-0.04, 0.004, 0.023), Vector3(0, 0.007, 0.032), Vector3(0.04, 0.003, 0.023)], 0.001)

func _digit(node_name: String, base: Vector3, length: float, radius: float, spread: float, curl: float) -> void:
	var centers: Array[Vector3] = []
	var widths: Array[float] = []
	var depths: Array[float] = []
	var samples := [0.0, 0.12, 0.28, 0.4, 0.51, 0.65, 0.76, 0.88, 0.96, 1.0]
	var profile := [1.0, 0.99, 0.9, 0.98, 0.85, 0.82, 0.86, 0.72, 0.45, 0.08]
	for i in range(samples.size()):
		var t: float = samples[i]
		centers.append(base + Vector3(spread * length * t, -length * t, curl * t * t))
		widths.append(radius * float(profile[i]))
		depths.append(radius * float(profile[i]) * 0.86)
	_loft(node_name + "JointedFinger", centers, widths, depths, skin)
	_ellipsoid(node_name + "Knuckle", base + Vector3(0, -0.015, -radius * 0.62), Vector3(radius * 1.65, 0.035, 0.02), skin)
	var nail_center := base + Vector3(spread * length * 0.83, -length * 0.83, curl * 0.83 * 0.83 - radius * 0.66)
	var nail_mesh := _ellipsoid(node_name + "Nail", nail_center, Vector3(radius * 1.3, length * 0.22, 0.005), nail)
	nail_mesh.rotation.x = -atan2(curl * 1.66, length)
	for joint in [0.4, 0.75]:
		var center: Vector3 = base + Vector3(spread * length * joint, -length * joint, curl * joint * joint + radius * 0.79)
		_fold_line(node_name + "JointFold", [center + Vector3(-radius * 0.65, 0.002, -0.003), center, center + Vector3(radius * 0.65, 0.002, -0.003)], 0.0009)

func _fold_line(node_name: String, points: Array[Vector3], radius: float) -> void:
	var radii: Array[float] = []
	for i in range(points.size()):
		radii.append(radius * (0.45 if i == 0 or i == points.size() - 1 else 1.0))
	_loft(node_name, points, radii, radii, fold)

func _loft(node_name: String, centers: Array[Vector3], widths: Array[float], depths: Array[float], material: Material) -> void:
	const SEGMENTS := 20
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring in range(centers.size()):
		var tangent := (centers[mini(ring + 1, centers.size() - 1)] - centers[maxi(ring - 1, 0)]).normalized()
		var axis_x := Vector3.RIGHT - tangent * tangent.dot(Vector3.RIGHT)
		if axis_x.length_squared() < 0.01:
			axis_x = Vector3.FORWARD - tangent * tangent.dot(Vector3.FORWARD)
		axis_x = axis_x.normalized()
		var axis_z := tangent.cross(axis_x).normalized()
		for segment in range(SEGMENTS):
			var angle := TAU * float(segment) / float(SEGMENTS)
			var vertex := centers[ring] + axis_x * cos(angle) * widths[ring] + axis_z * sin(angle) * depths[ring]
			var normal := (axis_x * cos(angle) / widths[ring] + axis_z * sin(angle) / depths[ring]).normalized()
			vertex.x *= handedness
			normal.x *= handedness
			vertices.append(vertex)
			normals.append(normal)
			if ring < centers.size() - 1:
				var a := ring * SEGMENTS + segment
				var b := ring * SEGMENTS + (segment + 1) % SEGMENTS
				indices.append_array([a, a + SEGMENTS, b, b, a + SEGMENTS, b + SEGMENTS])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	add_child(instance)

func _ellipsoid(node_name: String, center: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 20
	mesh.rings = 12
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	center.x *= handedness
	instance.position = center
	instance.scale = dimensions
	add_child(instance)
	return instance

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	# Mirrored hands share the same winding; explicit normals retain smooth lighting.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
