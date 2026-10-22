class_name WeaponTable
extends StaticBody3D

const RestingWeaponScript = preload("res://RestingWeapon.gd")
const SUPPORTED_WEAPONS: Array[String] = ["glock", "ak47", "awp", "knife"]
const WEAPON_NODE_PATHS := {
	"glock": NodePath("Camera3D/HoldSocket/Glock"),
	"ak47": NodePath("Camera3D/HoldSocket/AK47"),
	"awp": NodePath("Camera3D/HoldSocket/AWP"),
	"knife": NodePath("Camera3D/HoldSocket/DoenerMesser"),
}
const FLAT_ROTATIONS := {
	"glock": Vector3(0.0, 0.0, 90.0),
	"ak47": Vector3(0.0, 0.0, 90.0),
	"awp": Vector3(0.0, 0.0, 90.0),
	"knife": Vector3(90.0, 0.0, 0.0),
}
const SURFACE_CLEARANCE := {
	"glock": 0.055,
	"ak47": 0.06,
	"awp": 0.065,
	"knife": 0.035,
}
const ASSIGNED_SLOTS := {
	"ak47": 1,
	"glock": 2,
	"awp": 3,
	"knife": 4,
}
const COLLISION_SIZES := {
	"glock": Vector3(0.10, 0.22, 0.55),
	"ak47": Vector3(0.12, 0.34, 1.10),
	"awp": Vector3(0.13, 0.34, 1.55),
	"knife": Vector3(0.16, 0.75, 0.07),
}

@export var interaction_distance := 2.5

@onready var weapon_slots: Dictionary = {
	"glock": $Slots/GlockSlot,
	"ak47": $Slots/AK47Slot,
	"awp": $Slots/AWPSlot,
	"knife": $Slots/KnifeSlot,
}

var stored_weapons: Array[String] = []
var displayed_weapons: Dictionary = {}


func _ready() -> void:
	add_to_group("weapon_table")


func is_player_in_range(player: Node3D) -> bool:
	if not is_instance_valid(player):
		return false
	var player_position_2d := Vector2(player.global_position.x, player.global_position.z)
	var table_position_2d := Vector2(global_position.x, global_position.z)
	return player_position_2d.distance_to(table_position_2d) <= interaction_distance


func place_weapon_on_table(weapon_type: String) -> bool:
	var weapon_id := _normalize_weapon_id(weapon_type)
	if weapon_id.is_empty() or stored_weapons.has(weapon_id):
		return false
	if not _spawn_display_weapon(weapon_id):
		return false

	stored_weapons.append(weapon_id)
	_sync_game_state()
	return true


func get_save_data() -> Dictionary:
	return {"weapons": stored_weapons.duplicate()}


func take_weapon_from_table(weapon_type: String, target: RestingWeapon) -> bool:
	var weapon_id := _normalize_weapon_id(weapon_type)
	if weapon_id.is_empty() or not stored_weapons.has(weapon_id):
		return false
	if displayed_weapons.get(weapon_id) != target:
		return false

	stored_weapons.erase(weapon_id)
	displayed_weapons.erase(weapon_id)
	_sync_game_state()
	target.queue_free()
	return true


func load_save_data(data: Dictionary) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(player):
		return false

	_clear_display_weapons()
	var raw_weapons: Variant = data.get("weapons", [])
	if raw_weapons is Array:
		for raw_weapon: Variant in raw_weapons:
			var weapon_id := _normalize_weapon_id(String(raw_weapon))
			if weapon_id.is_empty() or stored_weapons.has(weapon_id):
				continue
			if _spawn_display_weapon(weapon_id):
				stored_weapons.append(weapon_id)

	_sync_game_state()
	return true


func _spawn_display_weapon(weapon_id: String) -> bool:
	var slot := weapon_slots.get(weapon_id) as Marker3D
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(slot) or not is_instance_valid(player):
		return false

	var template_path: NodePath = WEAPON_NODE_PATHS.get(weapon_id, NodePath())
	var template := player.get_node_or_null(template_path) as Node3D
	if not is_instance_valid(template):
		return false

	var display := template.duplicate() as Node3D
	if not is_instance_valid(display):
		return false

	var target := RestingWeaponScript.new() as RestingWeapon
	if not is_instance_valid(target):
		display.queue_free()
		return false

	target.name = "%sTableWeapon" % weapon_id.to_pascal_case()
	slot.add_child(target)
	target.transform = Transform3D.IDENTITY
	target.position.y = float(SURFACE_CLEARANCE.get(weapon_id, 0.05))
	target.rotation_degrees = FLAT_ROTATIONS.get(weapon_id, Vector3.ZERO)
	target.configure(weapon_id, int(ASSIGNED_SLOTS[weapon_id]), self)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "PickupCollision"
	var box_shape := BoxShape3D.new()
	box_shape.size = COLLISION_SIZES.get(weapon_id, Vector3(0.2, 0.2, 0.5))
	collision_shape.shape = box_shape
	target.add_child(collision_shape)

	display.name = "%sDisplay" % weapon_id.to_pascal_case()
	target.add_child(display)
	display.transform = Transform3D.IDENTITY
	display.visible = true
	_prepare_display_copy(display)
	displayed_weapons[weapon_id] = target
	return true


func _prepare_display_copy(display: Node3D) -> void:
	display.process_mode = Node.PROCESS_MODE_DISABLED
	for child: Node in display.find_children("*", "", true, false):
		if child is RayCast3D:
			(child as RayCast3D).enabled = false
		elif child is Light3D:
			(child as Light3D).visible = false
		elif child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
		elif child is RigidBody3D:
			var rigid_body := child as RigidBody3D
			rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			rigid_body.freeze = true
			rigid_body.linear_velocity = Vector3.ZERO
			rigid_body.angular_velocity = Vector3.ZERO


func _clear_display_weapons() -> void:
	for display: Variant in displayed_weapons.values():
		if is_instance_valid(display):
			(display as Node).queue_free()
	displayed_weapons.clear()
	stored_weapons.clear()


func _sync_game_state() -> void:
	GameState.table_stored_weapons.assign(stored_weapons)
	for weapon_id: String in stored_weapons:
		for index in range(GameState.owned_weapons.size() - 1, -1, -1):
			if _normalize_weapon_id(GameState.owned_weapons[index]) == weapon_id:
				GameState.owned_weapons.remove_at(index)


func _normalize_weapon_id(weapon_type: String) -> String:
	var normalized := weapon_type.strip_edges().to_lower().replace("-", "").replace("_", "")
	match normalized:
		"glock", "glock17":
			return "glock"
		"ak47", "ak":
			return "ak47"
		"awp":
			return "awp"
		"knife", "doenermesser", "dönermesser":
			return "knife"
	return ""
