@tool
extends Node3D

## Procedural Vice City inspired neighborhood around the existing kebab shop.
## The original shop remains the center of the playable area.

const ROAD_DARK := Color("262a35")
const SIDEWALK := Color("cbb99b")
const PAINT := Color("f4d17a")
const BUILDING_COLORS := [Color("f2a77e"), Color("efcf91"), Color("a8d1c9"), Color("e9a6a9"), Color("c5b6df"), Color("f1d8b7")]
const CAR_COLORS := [Color("e94c4c"), Color("f0bd43"), Color("39a6a6"), Color("e9e5d5"), Color("5275a4")]

var _rng := RandomNumberGenerator.new()
var _materials: Dictionary = {}

func _ready() -> void:
	_rng.seed = 19860529
	_build_city()

func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var key := color.to_html() + str(emission)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	_materials[key] = material
	return material

func _box(parent: Node3D, item_name: String, pos: Vector3, size: Vector3, color: Color, solid := false, emission := 0.0) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = item_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(color, emission)
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	parent.add_child(mesh_instance)
	if solid:
		var body := StaticBody3D.new()
		body.name = item_name + "Collision"
		body.position = pos
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.add_child(shape_node)
		parent.add_child(body)
	return mesh_instance

func _add_ground_collision() -> void:
	var ground_body := StaticBody3D.new()
	ground_body.name = "Continuous walkable city floor"
	ground_body.position = Vector3(0, -0.1, 18)
	var ground_shape := CollisionShape3D.new()
	ground_shape.name = "City floor collider"
	var shape := BoxShape3D.new()
	shape.size = Vector3(130, 0.2, 150)
	ground_shape.shape = shape
	ground_body.add_child(ground_shape)
	add_child(ground_body)

func _cylinder(parent: Node3D, item_name: String, pos: Vector3, radius: float, height: float, color: Color) -> void:
	var item := MeshInstance3D.new()
	item.name = item_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.material = _mat(color)
	item.mesh = mesh
	item.position = pos
	parent.add_child(item)

func _build_city() -> void:
	# Broad city ground. The shop and its forecourt occupy the central block.
	_box(self, "Sunbaked city ground", Vector3(0, -0.18, 18), Vector3(130, 0.25, 150), Color("c8aa78"))
	_add_ground_collision()
	# A grid of asphalt avenues with raised sidewalks and painted lane markings.
	for x in [-48.0, -16.0, 16.0, 48.0]:
		_road_x(x)
	for z in [-32.0, 0.0, 32.0, 64.0]:
		_road_z(z)
	# Fill blocks with low rise colorful Miami inspired buildings, leaving the shop clear.
	for ix in range(3):
		for iz in range(4):
			var center_x := -32.0 + float(ix) * 32.0
			var center_z := -16.0 + float(iz) * 32.0
			if absf(center_x) < 17.0 and absf(center_z - 8.0) < 18.0:
				continue
			_build_building(center_x, center_z, ix * 9 + iz)
	# Waterfront boulevard and a pastel hotel frontage give the neighborhood a coastal edge.
	_box(self, "Ocean boulevard", Vector3(0, -0.035, 82), Vector3(130, 0.08, 10), ROAD_DARK)
	_box(self, "Boulevard center stripe", Vector3(0, 0.012, 82), Vector3(130, 0.025, 0.18), PAINT)
	# Palms, parked cars and pedestrians along the walkable blocks.
	for z in range(-44, 79, 12):
		for x in [-23.0, -9.0, 23.0, 39.0, 55.0]:
			if absf(float(z) - 8.0) < 10.0 and absf(x) < 18.0:
				continue
			_add_palm(Vector3(x, 0, float(z)))
	_add_parked_cars()
	_add_pedestrians()
	_add_intersections()
	_add_street_furniture()
	# Low, warm sunset with saturated coastal colors.
	var world := WorldEnvironment.new()
	world.name = "Vice City Evening"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("253b68")
	sky_material.sky_horizon_color = Color("f5a06f")
	sky_material.ground_bottom_color = Color("292b43")
	sky_material.ground_horizon_color = Color("d88767")
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f0a77b")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	world.environment = env
	add_child(world)

func _road_x(x: float) -> void:
	_box(self, "Avenue asphalt", Vector3(x, -0.03, 18), Vector3(10, 0.08, 150), ROAD_DARK, true)
	for side in [-1.0, 1.0]:
		_box(self, "Avenue sidewalk", Vector3(x + side * 6.2, 0.015, 18), Vector3(2.4, 0.16, 150), SIDEWALK, true)
		_box(self, "Curb", Vector3(x + side * 5.05, 0.075, 18), Vector3(0.24, 0.28, 150), Color("eee0bf"), true)
	for z in range(-50, 90, 8):
		_box(self, "Dashed lane marking", Vector3(x, 0.018, float(z)), Vector3(0.13, 0.025, 3.5), PAINT)

func _road_z(z: float) -> void:
	_box(self, "Cross street asphalt", Vector3(0, -0.03, z), Vector3(130, 0.08, 10), ROAD_DARK, true)
	for side in [-1.0, 1.0]:
		_box(self, "Cross street sidewalk", Vector3(0, 0.015, z + side * 6.2), Vector3(130, 0.16, 2.4), SIDEWALK, true)
		_box(self, "Curb", Vector3(0, 0.075, z + side * 5.05), Vector3(130, 0.28, 0.24), Color("eee0bf"), true)
	for x in range(-62, 64, 8):
		_box(self, "Dashed lane marking", Vector3(float(x), 0.018, z), Vector3(3.5, 0.025, 0.13), PAINT)

func _build_building(x: float, z: float, seed_val: int) -> void:
	var building := Node3D.new()
	building.name = "Pastel block %02d" % seed_val
	building.position = Vector3(x, 0, z)
	add_child(building)
	var width := _rng.randf_range(10.0, 15.0)
	var depth := _rng.randf_range(9.0, 13.0)
	var floors := _rng.randi_range(2, 4)
	var height := float(floors) * 3.1
	var facade: Color = BUILDING_COLORS[_rng.randi_range(0, BUILDING_COLORS.size() - 1)]
	_box(building, "Stucco facade", Vector3(0, height * 0.5, 0), Vector3(width, height, depth), facade, true)
	_box(building, "Flat roof cap", Vector3(0, height + 0.18, 0), Vector3(width + 0.6, 0.36, depth + 0.6), Color("f5dec0"))
	_box(building, "Art deco parapet", Vector3(0, height + 0.65, -depth * 0.43), Vector3(width * 0.58, 0.65, 0.34), facade)
	_box(building, "Left deco pilaster", Vector3(-width * 0.47, height * 0.5, -depth * 0.51), Vector3(0.3, height + 0.18, 0.28), Color("f8dfbd"))
	_box(building, "Right deco pilaster", Vector3(width * 0.47, height * 0.5, -depth * 0.51), Vector3(0.3, height + 0.18, 0.28), Color("f8dfbd"))
	# Recessed colored vertical facade bands and repeated bright windows.
	for floor_idx in range(floors):
		var wy := 1.25 + float(floor_idx) * 3.1
		for col in range(3):
			var wx := -width * 0.32 + float(col) * width * 0.32
			_box(building, "Window", Vector3(wx, wy, -depth * 0.505), Vector3(1.35, 1.65, 0.12), Color("82b8c3"), false, 0.12)
			_box(building, "Window mullion", Vector3(wx, wy, -depth * 0.55), Vector3(0.07, 1.65, 0.08), Color("f8dfbd"))
			_box(building, "Window crossbar", Vector3(wx, wy, -depth * 0.55), Vector3(1.35, 0.07, 0.08), Color("f8dfbd"))
			_box(building, "Window ledge", Vector3(wx, wy - 0.9, -depth * 0.54), Vector3(1.65, 0.14, 0.35), Color("f7d7ab"))
			if floor_idx > 0 and col != 1:
				_add_balcony(building, wx, wy - 0.1, -depth * 0.72)
		_box(building, "Horizontal deco trim", Vector3(0, 0.55 + float(floor_idx) * 3.1, -depth * 0.52), Vector3(width + 0.25, 0.2, 0.28), Color("fae5bf"))
	_box(building, "Shop awning", Vector3(0, 2.45, -depth * 0.57), Vector3(width * 0.46, 0.3, 1.15), Color("e75e58"))
	_box(building, "Storefront glass", Vector3(0, 1.15, -depth * 0.525), Vector3(width * 0.76, 1.95, 0.1), Color("527b83"), false, 0.08)
	_box(building, "Storefront door", Vector3(width * 0.31, 1.05, -depth * 0.59), Vector3(1.0, 2.1, 0.15), Color("d7c5a5"))
	_box(building, "Neon shop sign", Vector3(0, 2.95, -depth * 0.65), Vector3(width * 0.48, 0.58, 0.16), Color("ff5fa2"), false, 2.4)
	var sign_val := Label3D.new()
	sign_val.name = "Art deco shop lettering"
	sign_val.text = ["OCEAN VIEW", "MOTEL", "SUNSET CLUB", "PALM HOTEL", "VICE MARKET", "CORAL BAY"][seed_val % 6]
	sign_val.font_size = 48
	sign_val.pixel_size = 0.012
	sign_val.position = Vector3(0, 2.95, -depth * 0.75)
	sign_val.rotation.y = PI
	sign_val.modulate = Color("fff0c8")
	sign_val.outline_size = 5
	sign_val.outline_modulate = Color("66234e")
	building.add_child(sign_val)
	_add_rooftop_details(building, width, height, depth)

func _add_balcony(parent: Node3D, x: float, y: float, z: float) -> void:
	_box(parent, "Balcony slab", Vector3(x, y - 0.83, z), Vector3(1.9, 0.14, 0.8), Color("f0d6b4"))
	_box(parent, "Balcony rail top", Vector3(x, y - 0.22, z - 0.34), Vector3(1.9, 0.09, 0.09), Color("f7e7d0"))
	for offset in [-0.88, -0.44, 0.0, 0.44, 0.88]:
		_box(parent, "Balcony baluster", Vector3(x + offset, y - 0.52, z - 0.34), Vector3(0.055, 0.62, 0.055), Color("f7e7d0"))

func _add_rooftop_details(parent: Node3D, width: float, height: float, depth: float) -> void:
	_box(parent, "Rooftop utility room", Vector3(width * 0.22, height + 1.12, depth * 0.12), Vector3(2.0, 1.4, 2.1), Color("ead7bc"))
	_box(parent, "Rooftop water tank", Vector3(-width * 0.22, height + 1.25, depth * 0.16), Vector3(1.4, 1.8, 1.4), Color("9c8270"))
	for i in range(3):
		var ac_x := -width * 0.28 + float(i) * 1.5
		_box(parent, "Air conditioner condenser", Vector3(ac_x, height * 0.55, -depth * 0.57), Vector3(0.85, 0.7, 0.42), Color("d8c8ae"))
		_box(parent, "AC grille", Vector3(ac_x, height * 0.55, -depth * 0.8), Vector3(0.56, 0.42, 0.06), Color("69747a"))
	_cylinder(parent, "Roof antenna mast", Vector3(width * 0.38, height + 2.0, depth * 0.2), 0.045, 3.0, Color("676a70"))
	_box(parent, "Roof antenna crossbar", Vector3(width * 0.38, height + 2.8, depth * 0.2), Vector3(1.2, 0.06, 0.06), Color("676a70"))

func _add_palm(pos: Vector3) -> void:
	var tree := Node3D.new()
	tree.name = "Palm"
	tree.position = pos
	add_child(tree)
	# Slightly leaning trunk made from tapered sections, with the old leaf scars visible.
	var lean := _rng.randf_range(-0.22, 0.22)
	for section in range(12):
		var t := float(section) / 12.0
		var segment := MeshInstance3D.new()
		segment.name = "Tapered trunk section %02d" % section
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = lerpf(0.235, 0.17, t)
		trunk_mesh.bottom_radius = lerpf(0.27, 0.235, t)
		trunk_mesh.height = 0.53
		trunk_mesh.radial_segments = 10
		trunk_mesh.material = _mat(Color("826143") if section % 3 != 1 else Color("98714c"))
		segment.mesh = trunk_mesh
		segment.position = Vector3(lean * t * 6.0, 0.27 + float(section) * 0.5, 0)
		tree.add_child(segment)
		if section > 0:
			var scar := MeshInstance3D.new()
			scar.name = "Old frond scar"
			var scar_mesh := CylinderMesh.new()
			scar_mesh.top_radius = 0.244 - t * 0.055
			scar_mesh.bottom_radius = scar_mesh.top_radius
			scar_mesh.height = 0.045
			scar_mesh.radial_segments = 12
			scar_mesh.material = _mat(Color("604832"))
			scar.mesh = scar_mesh
			scar.position = Vector3(lean * t * 6.0, 0.53 + float(section) * 0.5, 0)
			tree.add_child(scar)
	# Exposed buttress roots spread over the sandy verge.
	for root_index in range(7):
		var root_angle := TAU * float(root_index) / 7.0
		var root_dir := Vector3(cos(root_angle), 0, sin(root_angle))
		var root := _box(tree, "Flared palm root", Vector3(root_dir.x * 0.42, 0.16, root_dir.z * 0.42), Vector3(0.22, 0.32, 1.35), Color("79583e"))
		root.rotation.y = root_angle
		root.rotation.z = -root_dir.x * 0.12
	# Dense, drooping feather fronds in two tiers around the crown.
	var crown_center := Vector3(lean * 5.5, 5.95, 0)
	var spine_transforms: Array[Transform3D] = []
	var leaflet_transforms: Array[Transform3D] = []
	var leaf_color: Color = [Color("246b49"), Color("2d8054"), Color("398e5b"), Color("4c965e")][_rng.randi_range(0, 3)]
	for frond_index in range(11):
		var angle := TAU * float(frond_index) / 11.0 + _rng.randf_range(-0.12, 0.12)
		var radial := Vector3(sin(angle), 0, cos(angle))
		var tangent := Vector3(radial.z, 0, -radial.x)
		var frond_length := _rng.randf_range(3.1, 4.0)
		var frond_drop := _rng.randf_range(1.25, 1.8)
		var frond_start := crown_center + radial * 0.18
		for segment_index in range(8):
			var u0 := float(segment_index) / 8.0
			var u1 := float(segment_index + 1) / 8.0
			var p0 := frond_start + radial * frond_length * u0 + Vector3(0, -frond_drop * u0 * u0, 0)
			var p1 := frond_start + radial * frond_length * u1 + Vector3(0, -frond_drop * u1 * u1, 0)
			var spine_size := Vector3(0.11, 0.1, p0.distance_to(p1) + 0.05)
			var spine_pitch := atan2((p1.y - p0.y), maxf(0.01, p1.distance_to(p0)))
			spine_transforms.append(Transform3D(Basis.from_euler(Vector3(spine_pitch, angle, 0)).scaled(spine_size), (p0 + p1) * 0.5))
		# Narrow pointed leaflets grow alternately from both sides of the midrib.
		for leaflet_index in range(1, 11):
			var u := float(leaflet_index) / 11.0
			var spine_point := frond_start + radial * frond_length * u + Vector3(0, -frond_drop * u * u, 0)
			var leaflet_length := 0.2 + sin(u * PI) * 0.72
			for side in [-1.0, 1.0]:
				var outward: Vector3 = tangent * side
				var leaf_center: Vector3 = spine_point + outward * leaflet_length * 0.48 + Vector3(0, -leaflet_length * 0.22, 0)
				var leaf_size := Vector3(leaflet_length, 0.045, 0.15)
				var leaf_yaw := atan2(-outward.z, outward.x)
				leaflet_transforms.append(Transform3D(Basis.from_euler(Vector3(0, leaf_yaw, -side * 0.28)).scaled(leaf_size), leaf_center))
	_add_box_multimesh(tree, "Curved feathered midribs", spine_transforms, Color("a4a45e"))
	_add_box_multimesh(tree, "Hundreds of pointed palm leaflets", leaflet_transforms, leaf_color)
		# Small coconuts cluster just below the frond crown.
	for nut_index in range(5):
		var nut_angle := TAU * float(nut_index) / 5.0
		var nut := MeshInstance3D.new()
		nut.name = "Coconut"
		var nut_mesh := SphereMesh.new()
		nut_mesh.radius = 0.2
		nut_mesh.height = 0.38
		nut_mesh.radial_segments = 10
		nut_mesh.rings = 6
		nut_mesh.material = _mat(Color("735337") if nut_index % 2 == 0 else Color("9b7046"))
		nut.mesh = nut_mesh
		nut.position = crown_center + Vector3(cos(nut_angle) * 0.42, -0.42, sin(nut_angle) * 0.42)
		tree.add_child(nut)

func _add_box_multimesh(parent: Node3D, node_name: String, transforms: Array[Transform3D], color: Color) -> void:
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = BoxMesh.new()
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
	instance.multimesh = multi
	instance.material_override = _mat(color)
	parent.add_child(instance)

func _add_parked_cars() -> void:
	var spots := [Vector3(-21, 0, -22), Vector3(-11, 0, 11), Vector3(21, 0, 25), Vector3(43, 0, -10), Vector3(-42, 0, 49), Vector3(26, 0, 57), Vector3(59, 0, 31)]
	for i in range(spots.size()):
		var car := Node3D.new()
		car.name = "Parked 80s coupe %02d" % i
		car.position = spots[i]
		if i % 2 == 1:
			car.rotation.y = PI * 0.5
		add_child(car)
		var color: Color = CAR_COLORS[i % CAR_COLORS.size()]
		_box(car, "Coupe body", Vector3(0, 0.68, 0), Vector3(2.05, 0.72, 4.1), color)
		_box(car, "Coupe roof", Vector3(0, 1.2, 0.15), Vector3(1.62, 0.65, 1.9), Color("d9e5df"))
		_box(car, "Front glass", Vector3(0, 1.22, -0.77), Vector3(1.45, 0.48, 0.08), Color("547c87"))
		_box(car, "Rear glass", Vector3(0, 1.22, 1.08), Vector3(1.45, 0.48, 0.08), Color("547c87"))
		for side in [-1.0, 1.0]:
			for z in [-1.3, 1.3]:
				_cylinder(car, "Black tire", Vector3(side * 1.0, 0.42, z), 0.38, 0.2, Color("22252a"))
			_box(car, "Chrome front bumper", Vector3(0, 0.42, -2.12), Vector3(2.1, 0.16, 0.16), Color("c9c7b8"))
			_box(car, "Chrome rear bumper", Vector3(0, 0.42, 2.12), Vector3(2.1, 0.16, 0.16), Color("c9c7b8"))
			_box(car, "Front grille", Vector3(0, 0.72, -2.08), Vector3(0.64, 0.3, 0.08), Color("41454a"))
			_box(car, "License plate", Vector3(0, 0.53, -2.18), Vector3(0.58, 0.18, 0.04), Color("f3e6bd"))
			_box(car, "Headlamp", Vector3(side * 0.65, 0.7, -2.08), Vector3(0.42, 0.22, 0.05), Color("ffe5a6"), false, 0.25)
			_box(car, "Rear lamp", Vector3(side * 0.67, 0.72, 2.08), Vector3(0.34, 0.28, 0.06), Color("d84b43"), false, 0.15)
			_box(car, "Side mirror", Vector3(side * 1.08, 1.16, -0.6), Vector3(0.28, 0.17, 0.24), color)
			_box(car, "Door handle", Vector3(side * 1.04, 0.89, 0.25), Vector3(0.045, 0.08, 0.42), Color("ddd2b6"))

func _add_pedestrians() -> void:
	var locations := [Vector3(-22, 0, 4), Vector3(24, 0, -17), Vector3(40, 0, 39), Vector3(-39, 0, 59), Vector3(8, 0, 44), Vector3(57, 0, -29)]
	var shirts := [Color("ed725e"), Color("3d88a7"), Color("e6bf54"), Color("a46693"), Color("e8e1cc"), Color("62a87a")]
	for i in range(locations.size()):
		var person := Node3D.new()
		person.name = "Sidewalk pedestrian %02d" % i
		person.position = locations[i]
		person.rotation.y = _rng.randf_range(-PI, PI)
		add_child(person)
		_box(person, "Shirt", Vector3(0, 1.15, 0), Vector3(0.52, 0.78, 0.32), shirts[i])
		var head := MeshInstance3D.new()
		head.name = "Head"
		var sphere := SphereMesh.new()
		sphere.radius = 0.19
		sphere.height = 0.38
		sphere.material = _mat(Color("d6a27b"))
		head.mesh = sphere
		head.position = Vector3(0, 1.75, 0)
		person.add_child(head)
		for side in [-1.0, 1.0]:
			_box(person, "Trouser leg", Vector3(side * 0.14, 0.48, 0), Vector3(0.18, 0.7, 0.2), Color("343846"))
			_box(person, "Relaxed arm", Vector3(side * 0.38, 1.1, 0.03), Vector3(0.16, 0.68, 0.18), shirts[i])
			_box(person, "Hand", Vector3(side * 0.39, 0.73, 0.04), Vector3(0.14, 0.16, 0.14), Color("d6a27b"))

func _add_intersections() -> void:
	# Crosswalks, stop bars and traffic signals make the grid read as real streets.
	for road_x in [-48.0, -16.0, 16.0, 48.0]:
		for road_z in [-32.0, 0.0, 32.0, 64.0]:
			for direction in [-1.0, 1.0]:
				for stripe in range(6):
					var offset := float(stripe) * 0.72 - 1.8
					_box(self, "Crosswalk stripe", Vector3(road_x + offset, 0.025, road_z + direction * 6.3), Vector3(0.42, 0.035, 2.6), Color("f3e7d0"))
					_box(self, "Crosswalk stripe", Vector3(road_x + direction * 6.3, 0.025, road_z + offset), Vector3(2.6, 0.035, 0.42), Color("f3e7d0"))
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				_add_traffic_signal(Vector3(road_x + corner.x * 6.8, 0, road_z + corner.y * 6.8))

func _add_traffic_signal(pos: Vector3) -> void:
	var traffic_light := Node3D.new()
	traffic_light.name = "Traffic signal"
	traffic_light.position = pos
	add_child(traffic_light)
	_cylinder(traffic_light, "Signal pole", Vector3(0, 2.1, 0), 0.09, 4.2, Color("55585a"))
	_box(traffic_light, "Signal housing", Vector3(0, 3.9, -0.15), Vector3(0.4, 1.15, 0.45), Color("34383a"))
	_cylinder(traffic_light, "Red lens", Vector3(0, 4.22, -0.39), 0.105, 0.06, Color("ed4e4a"))
	_cylinder(traffic_light, "Amber lens", Vector3(0, 3.91, -0.39), 0.105, 0.06, Color("efb84c"))
	_cylinder(traffic_light, "Green lens", Vector3(0, 3.6, -0.39), 0.105, 0.06, Color("64bd83"))

func _add_street_furniture() -> void:
	var spots := [Vector3(-23, 0, -8), Vector3(-9, 0, 28), Vector3(23, 0, 4), Vector3(39, 0, 60), Vector3(-39, 0, 28), Vector3(55, 0, -8), Vector3(9, 0, 60), Vector3(-55, 0, 60)]
	for i in range(spots.size()):
		var cluster := Node3D.new()
		cluster.name = "Street furniture cluster %02d" % i
		cluster.position = spots[i]
		add_child(cluster)
		# Deco streetlamp with a warm glowing globe.
		_cylinder(cluster, "Streetlamp pole", Vector3(0, 3.0, 0), 0.09, 6.0, Color("45484d"))
		_box(cluster, "Lamp arm", Vector3(0.52, 5.75, 0), Vector3(1.15, 0.1, 0.1), Color("45484d"))
		var lamp := _box(cluster, "Warm lamp", Vector3(1.02, 5.58, 0), Vector3(0.5, 0.24, 0.42), Color("ffc979"), false, 1.8)
		lamp.rotation.z = -0.1
		# Bench, public bin and a bright fire hydrant at each block corner.
		_box(cluster, "Bench seat", Vector3(2.8, 0.55, 1.2), Vector3(2.0, 0.16, 0.58), Color("a76548"))
		_box(cluster, "Bench back", Vector3(2.8, 1.02, 1.48), Vector3(2.0, 0.72, 0.14), Color("a76548"))
		for leg_x in [2.05, 3.55]:
			_box(cluster, "Bench metal leg", Vector3(leg_x, 0.28, 1.2), Vector3(0.12, 0.55, 0.12), Color("444a4e"))
		_box(cluster, "Public trash bin", Vector3(-1.5, 0.62, 1.1), Vector3(0.7, 1.2, 0.7), Color("4b7771"))
		_box(cluster, "Bin lid", Vector3(-1.5, 1.25, 1.1), Vector3(0.82, 0.12, 0.82), Color("d6b780"))
		_cylinder(cluster, "Red fire hydrant", Vector3(-2.8, 0.48, 0.2), 0.23, 0.95, Color("d94b42"))
		_cylinder(cluster, "Hydrant cap", Vector3(-2.8, 1.0, 0.2), 0.3, 0.16, Color("e6b34e"))
		# Concrete planter with tropical leaves at the base of the lamp.
		_box(cluster, "Planter", Vector3(0, 0.4, 2.7), Vector3(1.25, 0.8, 1.15), Color("d4b88e"))
		for leaf_idx in range(5):
			var leaf := _box(cluster, "Planter foliage", Vector3((float(leaf_idx) - 2.0) * 0.16, 1.15, 2.7), Vector3(0.16, 1.0, 0.16), Color("397d57"))
			leaf.rotation.z = (float(leaf_idx) - 2.0) * 0.16

