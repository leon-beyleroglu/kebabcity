class_name RestingWeapon
extends Area3D

const INTERACTION_LAYER := 1 << 2

@export var weapon_type: String = ""
@export_range(1, 4, 1) var assigned_slot: int = 1

var weapon_table: WeaponTable


func configure(type: String, slot: int, table: WeaponTable) -> void:
	weapon_type = type
	assigned_slot = slot
	weapon_table = table
	collision_layer = INTERACTION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group("table_weapon")
	set_meta("interactable", true)
	set_meta("weapon_type", weapon_type)
	set_meta("assigned_slot", assigned_slot)


func pickup_weapon() -> bool:
	if not is_instance_valid(weapon_table):
		return false
	return weapon_table.take_weapon_from_table(weapon_type, self)
