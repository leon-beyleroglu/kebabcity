extends CharacterBody3D

signal hitscan_hit(collider: Object, position: Vector3, normal: Vector3)
signal health_changed(current: float, max_val: float)
signal shield_changed(current: float, max_val: float)
signal held_ingredient_changed(ingredient_name: String)

@export var walk_speed := 5.0
@export var sprint_speed := 9.0
@export var jump_velocity := 5.0
@export var mouse_sensitivity := 0.002
@export var acceleration := 20.0
@export var deceleration := 26.0
@export var hand_slot: Marker3D
@export var max_health := 100.0
@export var max_shield := 100.0

@onready var camera: Camera3D = $Camera3D
@onready var player_collision: CollisionShape3D = $CollisionShape3D
@onready var legacy_avatar: Node3D = $EigenesAvatarModell
@onready var first_person_hands: Node3D = $Camera3D/ArmsHolder
@onready var ak47: Node3D = %AK47
@onready var muzzle_point: Marker3D = %MuzzlePoint
@onready var muzzle_light: OmniLight3D = %MuzzleLight
@onready var muzzle_ray: RayCast3D = %MuzzleRay
@onready var glock: Node3D = $Camera3D/HoldSocket/Glock
@onready var glock_muzzle_light: OmniLight3D = $Camera3D/HoldSocket/Glock/GlockMuzzlePoint/GlockMuzzleLight
@onready var awp: Node3D = $Camera3D/HoldSocket/AWP
@onready var awp_muzzle_light: OmniLight3D = $Camera3D/HoldSocket/AWP/AWPMuzzlePoint/AWPMuzzleLight
@onready var doener_messer: Node3D = $Camera3D/HoldSocket/DoenerMesser
@onready var blade_hit_area: RayCast3D = $Camera3D/HoldSocket/DoenerMesser/BladeHitArea
@onready var weapon_pickup_ray: RayCast3D = $Camera3D/WeaponPickupRay

enum Slot { NONE, AK47, GLOCK, AWP, KNIFE }

var avatar_model: Node3D
var arm_pivots: Array[Node3D] = []
var leg_pivots: Array[Node3D] = []
var interaction_system: KebabInteractionSystem
var orbit_yaw := 0.0
var orbit_pitch := -0.2
var first_person_pitch := 0.0
var zoom_distance := 4.2
var camera_distance := 4.2
var follow_target := Vector3.ZERO
var camera_query := PhysicsShapeQueryParameters3D.new()
var walk_phase := 0.0
var motion_blend := 0.0
var idle_time := 0.0
var is_holding_gun := false
var current_slot := Slot.NONE
var weapon_fire_cooldown := 0.0
var muzzle_flash_time := 0.0
var camera_recoil_pitch := 0.0
var weapon_recoil := 0.0
var weapon_rest_transforms: Dictionary = {}
var active_muzzle_light: OmniLight3D
var knife_swing_tween: Tween
var awp_scoped := false
var walking_parent: Node
var nearby_vehicle: Node
var active_vehicle: Node
var cutting_input_locked := false
var held_kitchen_item: Dictionary = {}
var held_ingredient := ""
var health := 100.0
var shield := 0.0

const HumanHand = preload("res://human_hand.gd")
const InteractionSystem = preload("res://interaction_system.gd")

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var third_person := false

const FIRST_PERSON_POSITION := Vector3(0.0, 0.7549808, 0.0)
const CAMERA_TARGET := Vector3(0.0, 0.38, 0.0)
const AK47_FIRE_INTERVAL := 0.1
const AK47_RANGE := 100.0
const AK47_DAMAGE := 25
const AK47_CAMERA_KICK := deg_to_rad(1.4)
const GLOCK_FIRE_INTERVAL := 0.28
const GLOCK_RANGE := 100.0
const GLOCK_DAMAGE := 38
const GLOCK_CAMERA_KICK := deg_to_rad(0.85)
const AWP_FIRE_INTERVAL := 1.2
const AWP_RANGE := 400.0
const AWP_DAMAGE := 120
const AWP_CAMERA_KICK := deg_to_rad(5.5)
const AWP_SCOPE_FOV := 30.0
const KNIFE_ATTACK_INTERVAL := 0.42
const KNIFE_DAMAGE := 45
const VEHICLE_INTERACTION_DISTANCE := 3.5

func _ready() -> void:
	add_to_group("player")
	health = clampf(health, 0.0, max_health)
	shield = clampf(shield, 0.0, max_shield)
	health_changed.emit(health, max_health)
	shield_changed.emit(shield, max_shield)
	Engine.max_fps = 60
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.position = FIRST_PERSON_POSITION
	camera.rotation = Vector3.ZERO
	first_person_pitch = camera.rotation.x
	camera.near = 0.06
	camera.fov = 72.0
	for slot in [Slot.AK47, Slot.GLOCK, Slot.AWP, Slot.KNIFE]:
		var weapon := _weapon_for_slot(slot)
		weapon.visible = false
		weapon_rest_transforms[slot] = weapon.transform
	_synchronize_weapon_inventory()
	muzzle_light.visible = false
	glock_muzzle_light.visible = false
	awp_muzzle_light.visible = false
	muzzle_ray.enabled = false
	muzzle_ray.add_exception(self)
	blade_hit_area.enabled = false
	blade_hit_area.add_exception(self)
	weapon_pickup_ray.enabled = true
	weapon_pickup_ray.target_position = Vector3(0.0, 0.0, -2.5)
	weapon_pickup_ray.collision_mask = RestingWeapon.INTERACTION_LAYER
	weapon_pickup_ray.collide_with_areas = true
	weapon_pickup_ray.collide_with_bodies = false
	weapon_pickup_ray.add_exception(self)
	var camera_volume := SphereShape3D.new()
	camera_volume.radius = 0.24
	camera_query.shape = camera_volume
	camera_query.exclude = [get_rid()]
	camera_query.collision_mask = collision_mask
	camera_query.margin = 0.04
	legacy_avatar.visible = false
	_build_doner_worker()
	interaction_system = InteractionSystem.new()
	interaction_system.name = "InteractionSystem"
	add_child(interaction_system)
	interaction_system.setup(self, camera, hand_slot)


func take_damage(amount: float) -> void:
	var remaining_damage := maxf(amount, 0.0)
	if shield > 0.0 and remaining_damage > 0.0:
		var absorbed := minf(shield, remaining_damage)
		shield -= absorbed
		remaining_damage -= absorbed
		shield_changed.emit(shield, max_shield)
	if remaining_damage > 0.0:
		health = maxf(0.0, health - remaining_damage)
		health_changed.emit(health, max_health)


func heal(amount: float) -> void:
	health = clampf(health + maxf(amount, 0.0), 0.0, max_health)
	health_changed.emit(health, max_health)


func set_health(value: float) -> void:
	health = clampf(value, 0.0, max_health)
	health_changed.emit(health, max_health)


func set_shield(value: float) -> void:
	shield = clampf(value, 0.0, max_shield)
	shield_changed.emit(shield, max_shield)


func _input(event: InputEvent) -> void:
	if cutting_input_locked:
		return
	if event is InputEventMouseButton and event.pressed:
		if is_instance_valid(active_vehicle):
			return
		if event.button_index == MOUSE_BUTTON_LEFT and current_slot != Slot.NONE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			_try_primary_action()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and current_slot == Slot.AWP:
			_set_awp_scope(not awp_scoped)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if cutting_input_locked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		var physical_key: Key = key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
		if physical_key == KEY_E:
			if (
				is_instance_valid(interaction_system)
				and interaction_system.try_open_trunk_from_raycast()
			):
				get_viewport().set_input_as_handled()
				return
			if _try_pickup_table_weapon() or _try_vehicle_interaction():
				get_viewport().set_input_as_handled()
			return
	if is_instance_valid(active_vehicle):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		var physical_key: Key = key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
		if physical_key == KEY_G:
			if not held_kitchen_item.is_empty():
				if is_instance_valid(interaction_system) and interaction_system.place_held_kitchen_item_from_raycast():
					get_viewport().set_input_as_handled()
				return
			if _try_drop_current_weapon():
				get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := _slot_from_key(event)
		if slot != Slot.NONE:
			_equip_slot(Slot.NONE if current_slot == slot else slot)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		_toggle_camera_mode()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if third_person:
			orbit_yaw -= event.relative.x * mouse_sensitivity
			orbit_pitch = clampf(orbit_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-62), deg_to_rad(28))
		else:
			rotate_y(-event.relative.x * mouse_sensitivity)
			first_person_pitch = clampf(first_person_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-85), deg_to_rad(85))
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif third_person and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_distance = maxf(2.2, zoom_distance - 0.35)
		elif third_person and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_distance = minf(6.5, zoom_distance + 0.35)

func _toggle_camera_mode() -> void:
	if not third_person and is_holding_gun:
		_set_gun_equipped(false)
	third_person = not third_person
	legacy_avatar.visible = false
	avatar_model.visible = third_person
	first_person_hands.visible = not third_person
	if third_person:
		orbit_yaw = global_rotation.y
		orbit_pitch = -0.2
		follow_target = global_position + CAMERA_TARGET
		camera_distance = zoom_distance
		camera.top_level = true
	else:
		global_rotation.y = orbit_yaw
		camera.top_level = false
		camera.position = FIRST_PERSON_POSITION
		first_person_pitch = orbit_pitch
		camera.rotation = Vector3(first_person_pitch, 0, 0)


func set_cutting_input_locked(locked: bool) -> void:
	cutting_input_locked = locked
	velocity.x = 0.0
	velocity.z = 0.0
	_set_awp_scope(false)
	if is_instance_valid(interaction_system):
		interaction_system.set_process_unhandled_input(not locked and current_slot == Slot.NONE)


func set_held_kitchen_item(data: Dictionary) -> bool:
	var normalized := PickupableItem.normalize_item_data(data)
	if normalized.is_empty():
		return false
	held_kitchen_item = normalized
	return true


func clear_held_kitchen_item() -> void:
	held_kitchen_item = {}


func get_held_kitchen_item_data() -> Dictionary:
	return held_kitchen_item.duplicate(true)


func equip_raw_vegetable(item_id: String) -> bool:
	if not held_kitchen_item.is_empty() or not is_instance_valid(interaction_system):
		return false
	var item_data := PickupableItem.data_for_id(item_id)
	if item_data.is_empty() or not String(item_data.get("id", "")).begins_with("whole_"):
		return false
	return interaction_system.hold_kitchen_item_data(item_data)


func set_held_ingredient(ingredient_name: String) -> void:
	held_ingredient = ingredient_name.strip_edges().to_lower()
	held_ingredient_changed.emit(held_ingredient)


func clear_held_ingredient() -> void:
	if held_ingredient.is_empty():
		return
	held_ingredient = ""
	held_ingredient_changed.emit(held_ingredient)


func get_held_ingredient() -> String:
	return held_ingredient


func restore_held_kitchen_item(data: Dictionary) -> bool:
	if not is_instance_valid(interaction_system):
		return false
	return interaction_system.hold_kitchen_item_data(data)


func _physics_process(delta: float) -> void:
	if cutting_input_locked:
		if not is_on_floor():
			velocity.y -= gravity * delta
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		move_and_slide()
		_update_weapon_state(delta)
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	var current_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var input_direction := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var movement_basis := Basis(Vector3.UP, orbit_yaw) if third_person else global_basis
	var direction := (movement_basis * Vector3(input_direction.x, 0, input_direction.y)).normalized()
	if direction:
		if third_person:
			global_rotation.y = lerp_angle(global_rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-delta * 12.0))
		velocity.x = move_toward(velocity.x, direction.x * current_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0, deceleration * delta)
	move_and_slide()
	_animate_actor(delta)
	_update_weapon_state(delta)
	if camera.current:
		_update_camera(delta)

func _update_camera(delta: float) -> void:
	var sprinting := Input.is_action_pressed("sprint") and Vector2(velocity.x, velocity.z).length() > walk_speed
	var target_fov := AWP_SCOPE_FOV if current_slot == Slot.AWP and awp_scoped else (77.0 if sprinting else 72.0)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-delta * 9.0))
	if not third_person:
		camera.rotation.x = clampf(first_person_pitch + camera_recoil_pitch, deg_to_rad(-85), deg_to_rad(85))
		return
	var target := global_position + CAMERA_TARGET
	follow_target = follow_target.lerp(target, 1.0 - exp(-delta * 14.0))
	var orbit_basis := Basis.from_euler(Vector3(orbit_pitch, orbit_yaw, 0))
	var desired_position := follow_target + orbit_basis.z * zoom_distance
	var motion := desired_position - target
	# Sweep a camera-sized sphere; exclude the player's capsule. Pull in immediately
	# at walls, ease out afterwards, and never interpolate through the obstruction.
	camera_query.transform = Transform3D(Basis.IDENTITY, target)
	camera_query.motion = motion
	var cast := get_world_3d().direct_space_state.cast_motion(camera_query)
	var safe_distance := maxf(0.0, motion.length() * cast[0] - 0.04)
	camera_distance = minf(safe_distance, lerpf(camera_distance, safe_distance, 1.0 - exp(-delta * 7.0)))
	camera.global_position = target + motion.normalized() * camera_distance
	if camera_distance > 0.01:
		camera.look_at(target, Vector3.UP)
	else:
		camera.global_basis = orbit_basis
	avatar_model.visible = camera_distance > 0.95


func _slot_from_key(event: InputEventKey) -> int:
	var key := event.physical_keycode if event.physical_keycode != 0 else event.keycode
	match key:
		KEY_1:
			return Slot.AK47
		KEY_2:
			return Slot.GLOCK
		KEY_3:
			return Slot.AWP
		KEY_4:
			return Slot.KNIFE
	return Slot.NONE


func _weapon_for_slot(slot: int) -> Node3D:
	match slot:
		Slot.AK47:
			return ak47
		Slot.GLOCK:
			return glock
		Slot.AWP:
			return awp
		Slot.KNIFE:
			return doener_messer
	return null


func _weapon_id_for_slot(slot: int) -> String:
	match slot:
		Slot.AK47:
			return "ak47"
		Slot.GLOCK:
			return "glock"
		Slot.AWP:
			return "awp"
		Slot.KNIFE:
			return "knife"
	return ""


func _slot_for_weapon_id(weapon_id: String) -> int:
	match _normalize_weapon_id(weapon_id):
		"ak47":
			return Slot.AK47
		"glock":
			return Slot.GLOCK
		"awp":
			return Slot.AWP
		"knife":
			return Slot.KNIFE
	return Slot.NONE


func _equip_slot(slot: int) -> void:
	if slot != Slot.NONE and third_person:
		return
	if slot != Slot.NONE and not _owns_weapon(_weapon_id_for_slot(slot)):
		return
	if slot != Slot.NONE and is_instance_valid(interaction_system) and is_instance_valid(interaction_system.held_item):
		interaction_system._return_held()
	_set_awp_scope(false)
	if is_instance_valid(knife_swing_tween):
		knife_swing_tween.kill()
	for weapon_slot in [Slot.AK47, Slot.GLOCK, Slot.AWP, Slot.KNIFE]:
		var weapon := _weapon_for_slot(weapon_slot)
		weapon.visible = weapon_slot == slot
		weapon.transform = weapon_rest_transforms.get(weapon_slot, weapon.transform)
	current_slot = slot
	is_holding_gun = current_slot != Slot.NONE
	first_person_hands.visible = not is_holding_gun and not third_person
	muzzle_ray.enabled = current_slot == Slot.AK47
	blade_hit_area.enabled = current_slot == Slot.KNIFE
	if is_instance_valid(interaction_system):
		interaction_system.set_process_unhandled_input(not is_holding_gun)
		if is_holding_gun:
			interaction_system._clear_focus()
			interaction_system._reset_cutting()
	_hide_muzzle_flashes()
	weapon_fire_cooldown = 0.0
	camera_recoil_pitch = 0.0
	weapon_recoil = 0.0


func _try_drop_current_weapon() -> bool:
	if current_slot == Slot.NONE:
		return false

	var weapon_table := _find_nearby_weapon_table()
	if not is_instance_valid(weapon_table):
		return false

	var weapon_id := _weapon_id_for_slot(current_slot)
	if weapon_id.is_empty() or not weapon_table.place_weapon_on_table(weapon_id):
		return false

	_remove_owned_weapon(weapon_id)
	_equip_slot(Slot.NONE)
	return true


func _try_pickup_table_weapon() -> bool:
	if is_instance_valid(active_vehicle) or not is_instance_valid(weapon_pickup_ray):
		return false

	weapon_pickup_ray.force_raycast_update()
	if not weapon_pickup_ray.is_colliding():
		return false

	var target := weapon_pickup_ray.get_collider() as RestingWeapon
	if not is_instance_valid(target):
		return false

	var weapon_id := _normalize_weapon_id(target.weapon_type)
	var assigned_slot := _slot_for_weapon_id(weapon_id)
	if assigned_slot == Slot.NONE or target.assigned_slot != assigned_slot:
		return false
	if not target.pickup_weapon():
		return false

	GameState.retrieve_weapon_from_table(weapon_id)
	return true


func _find_nearby_weapon_table() -> WeaponTable:
	var closest_table: WeaponTable
	var closest_distance := INF
	for candidate: Node in get_tree().get_nodes_in_group("weapon_table"):
		var table := candidate as WeaponTable
		if not is_instance_valid(table) or not table.is_player_in_range(self):
			continue
		var distance := global_position.distance_squared_to(table.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_table = table
	return closest_table


func _synchronize_weapon_inventory() -> void:
	var has_tracked_weapon := false
	for owned_weapon: String in GameState.owned_weapons:
		if _normalize_weapon_id(owned_weapon) in ["ak47", "glock", "awp", "knife"]:
			has_tracked_weapon = true
			break

	for slot in [Slot.AK47, Slot.GLOCK, Slot.AWP, Slot.KNIFE]:
		var weapon_id := _weapon_id_for_slot(slot)
		if GameState.table_stored_weapons.has(weapon_id):
			_remove_owned_weapon(weapon_id)
		elif not has_tracked_weapon and not _owns_weapon(weapon_id):
			GameState.owned_weapons.append(weapon_id)


func _owns_weapon(weapon_id: String) -> bool:
	for owned_weapon: String in GameState.owned_weapons:
		if _normalize_weapon_id(owned_weapon) == weapon_id:
			return true
	return false


func _remove_owned_weapon(weapon_id: String) -> void:
	for index in range(GameState.owned_weapons.size() - 1, -1, -1):
		if _normalize_weapon_id(GameState.owned_weapons[index]) == weapon_id:
			GameState.owned_weapons.remove_at(index)


func _normalize_weapon_id(weapon_id: String) -> String:
	var normalized := weapon_id.strip_edges().to_lower().replace("-", "").replace("_", "")
	match normalized:
		"glock", "glock17":
			return "glock"
		"ak47", "ak":
			return "ak47"
		"awp":
			return "awp"
		"knife", "doenermesser", "dönermesser":
			return "knife"
	return normalized


func _set_gun_equipped(equipped: bool) -> void:
	_equip_slot(Slot.AK47 if equipped else Slot.NONE)


func set_nearby_vehicle(vehicle: Node) -> void:
	if is_instance_valid(active_vehicle):
		return
	nearby_vehicle = vehicle


func _try_vehicle_interaction() -> bool:
	if is_instance_valid(active_vehicle):
		active_vehicle.call("exit_vehicle")
		return true

	var vehicle := _find_closest_vehicle()
	if not is_instance_valid(vehicle):
		return false
	vehicle.call("enter_vehicle", self)
	return is_instance_valid(active_vehicle)


func _find_closest_vehicle() -> Node:
	var closest_vehicle: Node = null
	var closest_distance := VEHICLE_INTERACTION_DISTANCE
	for candidate: Node in get_tree().get_nodes_in_group("vehicles"):
		if not candidate is Node3D or not candidate.has_method("enter_vehicle"):
			continue
		if candidate.has_method("can_player_enter") and not bool(candidate.call("can_player_enter", self)):
			continue
		var candidate_3d := candidate as Node3D
		var distance := global_position.distance_to(candidate_3d.global_position)
		if distance <= closest_distance:
			closest_distance = distance
			closest_vehicle = candidate
	return closest_vehicle


func enter_vehicle_mode(vehicle: Node, driver_seat: Marker3D) -> void:
	if not is_instance_valid(vehicle) or not is_instance_valid(driver_seat):
		return
	active_vehicle = vehicle
	nearby_vehicle = vehicle
	if third_person:
		_toggle_camera_mode()
	if is_holding_gun:
		_equip_slot(Slot.NONE)
	if is_instance_valid(interaction_system):
		if is_instance_valid(interaction_system.held_item):
			interaction_system._return_held()
		interaction_system.set_process_unhandled_input(false)
	walking_parent = get_parent()
	velocity = Vector3.ZERO
	visible = false
	camera.current = false
	player_collision.disabled = true
	set_physics_process(false)
	set_process_input(false)
	reparent(driver_seat, false)
	transform = Transform3D.IDENTITY


func exit_vehicle_mode(exit_transform: Transform3D) -> void:
	active_vehicle = null
	nearby_vehicle = null
	var target_parent := walking_parent
	if not is_instance_valid(target_parent):
		target_parent = get_tree().current_scene
	reparent(target_parent, false)
	global_transform = exit_transform
	velocity = Vector3.ZERO
	player_collision.disabled = false
	visible = true
	first_person_hands.visible = not third_person and not is_holding_gun
	camera.current = true
	set_physics_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	if is_instance_valid(interaction_system):
		interaction_system.set_process_unhandled_input(current_slot == Slot.NONE)


func _try_primary_action() -> void:
	match current_slot:
		Slot.AK47:
			_try_firearm(AK47_FIRE_INTERVAL, AK47_RANGE, AK47_DAMAGE, AK47_CAMERA_KICK, muzzle_light, 0.055)
		Slot.GLOCK:
			_try_firearm(GLOCK_FIRE_INTERVAL, GLOCK_RANGE, GLOCK_DAMAGE, GLOCK_CAMERA_KICK, glock_muzzle_light, 0.032)
		Slot.AWP:
			_try_firearm(AWP_FIRE_INTERVAL, AWP_RANGE, AWP_DAMAGE, AWP_CAMERA_KICK, awp_muzzle_light, 0.085)
		Slot.KNIFE:
			_try_knife_attack()


func _try_firearm(interval: float, max_range: float, damage: int, camera_kick: float, flash: OmniLight3D, recoil_distance: float) -> void:
	if current_slot == Slot.NONE or third_person or weapon_fire_cooldown > 0.0:
		return
	weapon_fire_cooldown = interval
	_hide_muzzle_flashes()
	muzzle_flash_time = 0.05
	active_muzzle_light = flash
	active_muzzle_light.visible = true
	camera_recoil_pitch = minf(camera_recoil_pitch + camera_kick, deg_to_rad(12.0))
	weapon_recoil = maxf(weapon_recoil, recoil_distance)

	var viewport_center := get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(viewport_center)
	var ray_end := ray_origin + camera.project_ray_normal(viewport_center) * max_range
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider := hit.get("collider") as Object
	var hit_position := hit.get("position", ray_end) as Vector3
	var hit_normal := hit.get("normal", Vector3.UP) as Vector3
	hitscan_hit.emit(collider, hit_position, hit_normal)
	_apply_damage(collider, damage)


func _try_knife_attack() -> void:
	if current_slot != Slot.KNIFE or third_person or weapon_fire_cooldown > 0.0:
		return
	weapon_fire_cooldown = KNIFE_ATTACK_INTERVAL
	if is_instance_valid(knife_swing_tween):
		knife_swing_tween.kill()
	var rest: Transform3D = weapon_rest_transforms[Slot.KNIFE]
	doener_messer.transform = rest
	knife_swing_tween = create_tween()
	knife_swing_tween.set_trans(Tween.TRANS_QUAD)
	knife_swing_tween.set_ease(Tween.EASE_OUT)
	knife_swing_tween.tween_property(doener_messer, "rotation", rest.basis.get_euler() + Vector3(deg_to_rad(-52.0), 0.0, deg_to_rad(-8.0)), 0.09)
	knife_swing_tween.set_ease(Tween.EASE_IN_OUT)
	knife_swing_tween.tween_property(doener_messer, "transform", rest, 0.16)

	blade_hit_area.force_raycast_update()
	if not blade_hit_area.is_colliding():
		return
	var collider := blade_hit_area.get_collider() as Object
	var hit_position := blade_hit_area.get_collision_point()
	var hit_normal := blade_hit_area.get_collision_normal()
	hitscan_hit.emit(collider, hit_position, hit_normal)
	if is_instance_valid(collider) and collider is Area3D and collider.has_meta("doner_meat_station"):
		if is_instance_valid(interaction_system):
			interaction_system._spawn_meat_portion()
		return
	if _apply_damage(collider, KNIFE_DAMAGE):
		return
	if is_instance_valid(collider) and collider.has_method("melee_impact"):
		collider.call("melee_impact", hit_position, hit_normal)
	elif is_instance_valid(collider) and collider.has_method("hit_by_melee"):
		collider.call("hit_by_melee", KNIFE_DAMAGE, hit_position, hit_normal)


func _apply_damage(collider: Object, damage: int) -> bool:
	var target := collider as Node
	for _depth in range(4):
		if not is_instance_valid(target):
			break
		if target.has_method("take_damage"):
			target.call("take_damage", damage)
			return true
		target = target.get_parent()
	return false


func _set_awp_scope(enabled: bool) -> void:
	awp_scoped = enabled and current_slot == Slot.AWP and not third_person


func _hide_muzzle_flashes() -> void:
	muzzle_light.visible = false
	glock_muzzle_light.visible = false
	awp_muzzle_light.visible = false
	active_muzzle_light = null
	muzzle_flash_time = 0.0


func _update_weapon_state(delta: float) -> void:
	weapon_fire_cooldown = maxf(0.0, weapon_fire_cooldown - delta)
	if muzzle_flash_time > 0.0:
		muzzle_flash_time = maxf(0.0, muzzle_flash_time - delta)
		if muzzle_flash_time <= 0.0:
			_hide_muzzle_flashes()
	camera_recoil_pitch = move_toward(camera_recoil_pitch, 0.0, deg_to_rad(7.5) * delta)
	weapon_recoil = move_toward(weapon_recoil, 0.0, 0.55 * delta)
	if current_slot in [Slot.AK47, Slot.GLOCK, Slot.AWP]:
		var weapon := _weapon_for_slot(current_slot)
		var rest: Transform3D = weapon_rest_transforms[current_slot]
		weapon.position = rest.origin + Vector3(0.0, 0.0, weapon_recoil)
		weapon.rotation = rest.basis.get_euler() + Vector3(weapon_recoil * 1.8, 0.0, 0.0)
	if current_slot == Slot.AK47 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_try_primary_action()

func _animate_actor(delta: float) -> void:
	idle_time += delta
	var speed := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	var walking := clampf(speed / sprint_speed, 0.0, 1.0) if is_on_floor() else 0.0
	motion_blend = lerpf(motion_blend, walking, 1.0 - exp(-delta * 12.0))
	walk_phase += delta * speed * 1.9
	for i in range(arm_pivots.size()):
		var stride := sin(walk_phase + float(i) * PI)
		arm_pivots[i].rotation.x = stride * motion_blend * 0.5
		leg_pivots[i].rotation.x = -stride * motion_blend * 0.58
	avatar_model.rotation.z = sin(walk_phase) * motion_blend * 0.022
	first_person_hands.position = Vector3(sin(walk_phase) * motion_blend * 0.014, sin(idle_time * 1.7) * 0.003 + absf(sin(walk_phase)) * motion_blend * 0.009, 0)

func _material(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	material.metallic = metallic
	return material

func _box(parent: Node3D, node_name: String, new_position: Vector3, size: Vector3, material: Material, new_rotation := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = new_position
	instance.rotation = new_rotation
	parent.add_child(instance)
	return instance

func _sphere(parent: Node3D, node_name: String, new_position: Vector3, new_scale: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 20
	mesh.rings = 12
	mesh.material = material
	instance.mesh = mesh
	instance.position = new_position
	instance.scale = new_scale
	parent.add_child(instance)
	return instance

func _capsule(parent: Node3D, node_name: String, new_position: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = material
	instance.mesh = mesh
	instance.position = new_position
	parent.add_child(instance)
	return instance

func _build_doner_worker() -> void:
	var avatar := Node3D.new()
	avatar.name = "ThirdPersonDoner"
	avatar.visible = false
	avatar.position.y = -0.22
	avatar.scale.y = 0.8
	add_child(avatar)
	avatar_model = avatar
	var shirt := _material(Color("173f59"))
	var apron := _material(Color("a92f2c"))
	var apron_trim := _material(Color("e2c18a"))
	var skin := _material(Color("bd805c"))
	var beard := _material(Color("38251f"))
	var trousers := _material(Color("28323d"))
	var shoe := _material(Color("17191d"))
	var white := _material(Color("eee7d5"))
	var eye := _material(Color("211a17"))
	var metal := _material(Color("c6b690"), 0.5)
	var pocket := _material(Color("792a29"))
	var wood := _material(Color("55382c"))
	# Wide, rounded silhouette: shirt, belly and shoulders form a stocky build.
	_sphere(avatar, "Broad work shirt", Vector3(0, -0.15, 0), Vector3(1.42, 1.52, 0.96), shirt)
	_sphere(avatar, "Round shirt belly", Vector3(0, -0.47, -0.17), Vector3(1.34, 0.9, 0.91), shirt)
	_box(avatar, "Apron bib", Vector3(0, -0.05, -0.49), Vector3(1.08, 0.82, 0.09), apron)
	_box(avatar, "Apron skirt", Vector3(0, -0.57, -0.47), Vector3(1.25, 0.83, 0.1), apron)
	_box(avatar, "Apron hem", Vector3(0, -0.99, -0.48), Vector3(1.28, 0.09, 0.11), apron_trim)
	_box(avatar, "Apron pocket", Vector3(0, -0.5, -0.54), Vector3(0.58, 0.35, 0.07), pocket)
	_box(avatar, "Apron pocket stitch", Vector3(0, -0.35, -0.585), Vector3(0.62, 0.035, 0.02), apron_trim)
	_box(avatar, "Apron neck strap", Vector3(0, 0.46, -0.27), Vector3(0.16, 0.58, 0.12), apron)
	_box(avatar, "Apron waist tie", Vector3(0, -0.17, 0.43), Vector3(1.3, 0.12, 0.08), apron_trim)
	_box(avatar, "Back apron strap left", Vector3(-0.34, 0.12, 0.46), Vector3(0.13, 0.85, 0.07), apron, Vector3(0, 0, -0.18))
	_box(avatar, "Back apron strap right", Vector3(0.34, 0.12, 0.46), Vector3(0.13, 0.85, 0.07), apron, Vector3(0, 0, 0.18))
	_box(avatar, "Back apron cross strap", Vector3(0, -0.12, 0.47), Vector3(0.72, 0.12, 0.07), apron_trim)
	_box(avatar, "Back shirt patch", Vector3(0, -0.08, 0.49), Vector3(0.42, 0.2, 0.04), apron_trim)
	# Shoulder and hip pivots keep the hands attached during the walk cycle.
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "LeftShoulder" if side < 0 else "RightShoulder"
		arm.position = Vector3(side * 0.70, 0.28, 0.01)
		avatar.add_child(arm)
		arm_pivots.append(arm)
		_capsule(arm, "Short sleeve", Vector3(0, -0.17, 0), 0.22, 0.52, shirt)
		var wrist := Vector3(side * 0.06, -0.81, -0.03)
		_tapered_limb(arm, "ShapedForearm", Vector3(side * 0.025, -0.36, 0), wrist, 0.135, 0.056, skin)
		var hand := HumanHand.new()
		hand.name = "AnatomicalHand"
		arm.add_child(hand)
		hand.position = wrist
		hand.rotation.y = side * 0.22
		hand.build(side)
		var leg := Node3D.new()
		leg.name = "LeftHip" if side < 0 else "RightHip"
		leg.position = Vector3(side * 0.3, -0.55, 0.02)
		avatar.add_child(leg)
		leg_pivots.append(leg)
		_capsule(leg, "Trouser leg", Vector3(0, -0.45, 0), 0.23, 0.62, trousers)
		_box(leg, "Work shoe", Vector3(0, -0.73, -0.15), Vector3(0.43, 0.22, 0.62), shoe)
		_box(leg, "Shoe sole", Vector3(0, -0.84, -0.15), Vector3(0.45, 0.06, 0.64), metal)
	# Face, trimmed beard, mustache, hair and a white kitchen cap.
	_sphere(avatar, "Head", Vector3(0, 0.82, 0), Vector3(0.53, 0.62, 0.48), skin)
	_sphere(avatar, "Full beard", Vector3(0, 0.58, -0.18), Vector3(0.45, 0.31, 0.22), beard)
	_sphere(avatar, "Mustache left", Vector3(-0.105, 0.72, -0.255), Vector3(0.22, 0.1, 0.11), beard)
	_sphere(avatar, "Mustache right", Vector3(0.105, 0.72, -0.255), Vector3(0.22, 0.1, 0.11), beard)
	for side in [-1.0, 1.0]:
		_sphere(avatar, "Ear", Vector3(side * 0.27, 0.84, 0), Vector3(0.13, 0.18, 0.13), skin)
		_sphere(avatar, "Eye", Vector3(side * 0.105, 0.91, -0.218), Vector3(0.055, 0.065, 0.035), eye)
		_box(avatar, "Eyebrow", Vector3(side * 0.105, 1.015, -0.23), Vector3(0.14, 0.045, 0.045), beard, Vector3(0, 0, side * -0.08))
	_sphere(avatar, "Nose", Vector3(0, 0.81, -0.27), Vector3(0.13, 0.17, 0.17), skin)
	_capsule(avatar, "Hair", Vector3(0, 1.09, 0.01), 0.25, 0.3, beard)
	_cook_cap(avatar, white, apron_trim)
	# Name tag and a metal döner knife/tool clipped to the apron.
	_box(avatar, "Name badge", Vector3(0.34, 0.17, -0.56), Vector3(0.28, 0.16, 0.035), white)
	_box(avatar, "Badge lettering", Vector3(0.34, 0.17, -0.583), Vector3(0.17, 0.035, 0.018), apron)
	_box(avatar, "Apron towel", Vector3(-0.43, -0.29, -0.55), Vector3(0.2, 0.45, 0.08), white, Vector3(0, 0, -0.08))
	_box(avatar, "Knife handle", Vector3(-0.54, -0.7, -0.52), Vector3(0.1, 0.32, 0.1), wood, Vector3(0, 0, -0.16))
	_box(avatar, "Knife blade", Vector3(-0.57, -0.47, -0.52), Vector3(0.035, 0.2, 0.06), metal, Vector3(0, 0, -0.16))

func _cook_cap(parent: Node3D, white: Material, trim: Material) -> void:
	var cap_band := _capsule(parent, "Chef cap band", Vector3(0, 1.18, 0), 0.25, 0.12, trim)
	cap_band.scale = Vector3(1.0, 0.55, 0.88)
	var cap := _sphere(parent, "White cook cap", Vector3(0, 1.31, 0.015), Vector3(0.48, 0.35, 0.43), white)
	cap.rotation.z = -0.035

func _tapered_limb(parent: Node3D, node_name: String, start: Vector3, end: Vector3, start_radius: float, end_radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = start_radius
	mesh.bottom_radius = end_radius
	mesh.height = start.distance_to(end)
	mesh.radial_segments = 24
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = (start + end) * 0.5
	instance.basis = Basis(Quaternion(Vector3.UP, (start - end).normalized()))
	parent.add_child(instance)
