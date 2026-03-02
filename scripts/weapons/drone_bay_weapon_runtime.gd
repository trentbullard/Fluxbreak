# scripts/weapons/drone_bay_weapon_runtime.gd (godot 4.5)
extends WeaponRuntime
class_name DroneBayWeaponRuntime

const DRONE_STATE_DOCKED: int = 0
const DRONE_STATE_ACTIVE: int = 1
const DRONE_STATE_ATTACKING: int = 2
const DRONE_STATE_RETURNING: int = 3
const DRONE_STATE_CHARGING: int = 4

class DroneSlot extends RefCounted:
	var slot_index: int = -1
	var state: int = 0
	var charge_remaining: float = 0.0
	var max_charge: float = 0.0
	var return_remaining: float = 0.0
	var target_ref: WeakRef = null
	var drone: DroneController = null

	func _init() -> void:
		target_ref = weakref(null)

	func set_target(target: Node3D) -> void:
		target_ref = weakref(target) if target != null else weakref(null)

	func get_target() -> Node3D:
		return target_ref.get_ref() as Node3D if target_ref != null else null

var _drone_bay_weapon: DroneBayWeaponDef = null
var _drone_slots: Array[DroneSlot] = []

func _init(turret_owner: PlayerTurret = null, weapon_def: WeaponDef = null) -> void:
	super._init(turret_owner, weapon_def)
	_drone_bay_weapon = weapon_def as DroneBayWeaponDef

func on_equip() -> void:
	_sync_slot_count()
	_prime_slots_full_charge()
	if turret != null and turret.visual_controller != null:
		turret.visual_controller.set_charge(0.0)

func on_unequip() -> void:
	_despawn_all_drones()
	_drone_slots.clear()

func physics_process(delta: float) -> void:
	if turret == null or _drone_bay_weapon == null:
		return

	var controller: TurretController = turret.get_controller()
	if controller == null:
		return

	_sync_slot_count()
	_cooldown = max(0.0, _cooldown - delta)

	var base_range: float = max(0.0, turret.get_base_range())
	var max_assign: float = max(base_range, turret.get_max_assign_range())
	var range_bonus: float = max(0.0, max_assign - base_range)
	var candidates: Array[Node3D] = controller.get_prioritized_live_targets(
		turret,
		base_range,
		range_bonus,
		_get_controller_priority_mode(),
		false
	)
	_tick_slots(delta, candidates)
	_try_launch(candidates)
	_update_visual_charge()

func get_docked_drone_count() -> int:
	var count: int = 0
	for slot in _drone_slots:
		if slot.state == DRONE_STATE_DOCKED:
			count += 1
	return count

func get_active_drone_count() -> int:
	var count: int = 0
	for slot in _drone_slots:
		if slot.state == DRONE_STATE_ACTIVE or slot.state == DRONE_STATE_ATTACKING:
			count += 1
	return count

func get_returning_drone_count() -> int:
	var count: int = 0
	for slot in _drone_slots:
		if slot.state == DRONE_STATE_RETURNING:
			count += 1
	return count

func get_active_targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for slot in _drone_slots:
		if slot.state != DRONE_STATE_ATTACKING:
			continue
		var target: Node3D = slot.get_target()
		if target != null:
			out.append(target)
	return out

func _sync_slot_count() -> void:
	var desired: int = _get_desired_drone_count()
	while _drone_slots.size() < desired:
		var slot_new: DroneSlot = _make_slot(_drone_slots.size())
		_drone_slots.append(slot_new)
	while _drone_slots.size() > desired:
		var slot_old: DroneSlot = _drone_slots[_drone_slots.size() - 1]
		_despawn_slot_drone(slot_old)
		_drone_slots.remove_at(_drone_slots.size() - 1)
	_reindex_slots()

func _make_slot(slot_index: int) -> DroneSlot:
	var slot: DroneSlot = DroneSlot.new()
	slot.slot_index = slot_index
	slot.max_charge = _get_charge_time()
	slot.charge_remaining = slot.max_charge
	slot.return_remaining = 0.0
	slot.state = DRONE_STATE_DOCKED
	slot.set_target(null)
	return slot

func _reindex_slots() -> void:
	for i in range(_drone_slots.size()):
		var slot: DroneSlot = _drone_slots[i]
		if slot == null:
			continue
		slot.slot_index = i
		slot.max_charge = max(0.01, slot.max_charge)
		slot.charge_remaining = clamp(slot.charge_remaining, 0.0, slot.max_charge)

func _tick_slots(delta: float, candidates: Array[Node3D]) -> void:
	for i in range(_drone_slots.size()):
		var slot: DroneSlot = _drone_slots[i]
		if slot == null:
			continue
		slot.slot_index = i

		match slot.state:
			DRONE_STATE_ACTIVE:
				_tick_active_slot(slot, delta, candidates)
			DRONE_STATE_ATTACKING:
				_tick_attacking_slot(slot, delta, candidates)
			DRONE_STATE_RETURNING:
				_tick_returning_slot(slot, delta)
			_:
				_tick_grounded_slot(slot, delta)

func _tick_active_slot(slot: DroneSlot, _delta: float, candidates: Array[Node3D]) -> void:
	_ensure_slot_drone(slot)
	var previous_target: Node3D = slot.get_target()
	var current_target: Node3D = previous_target
	if not _is_target_valid_candidate(previous_target, candidates):
		current_target = _pick_first_candidate(candidates)
		slot.set_target(current_target)

	if current_target == null:
		if previous_target != null:
			_command_drone_idle(slot)
		return

	_command_drone_attack(slot, current_target)

func _tick_attacking_slot(slot: DroneSlot, delta: float, candidates: Array[Node3D]) -> void:
	_ensure_slot_drone(slot)
	var previous_target: Node3D = slot.get_target()
	var current_target: Node3D = previous_target
	if not _is_target_valid_candidate(previous_target, candidates):
		current_target = _pick_first_candidate(candidates)
		slot.set_target(current_target)
		if current_target == null:
			_command_drone_idle(slot)
			return
	if current_target != previous_target:
		_command_drone_attack(slot, current_target)

	var discharge_rate: float = _get_discharge_rate_for_target(current_target)
	slot.charge_remaining = max(0.0, slot.charge_remaining - delta * discharge_rate)
	if slot.charge_remaining <= 0.0:
		slot.charge_remaining = 0.0
		_begin_return(slot)

func _tick_returning_slot(slot: DroneSlot, delta: float) -> void:
	_ensure_slot_drone(slot)
	slot.return_remaining = max(0.0, slot.return_remaining - delta)
	if slot.return_remaining > 0.0:
		return
	slot.return_remaining = 0.0
	slot.set_target(null)
	_command_drone_dock(slot)

func _tick_grounded_slot(slot: DroneSlot, delta: float) -> void:
	if slot == null:
		return
	slot.return_remaining = 0.0
	slot.set_target(null)
	if _is_drone_valid(slot.drone):
		_command_drone_dock(slot)

	if slot.charge_remaining < slot.max_charge:
		slot.state = DRONE_STATE_CHARGING
		slot.charge_remaining = min(slot.max_charge, slot.charge_remaining + delta * _get_charge_recovery_rate())
	else:
		slot.state = DRONE_STATE_DOCKED
		slot.charge_remaining = slot.max_charge

func _ensure_slot_drone(slot: DroneSlot, replay_state: bool = true) -> void:
	if slot == null:
		return
	if _is_drone_valid(slot.drone):
		if slot.drone.origin_bay_id != get_instance_id() or slot.drone.slot_index != slot.slot_index:
			_bind_drone_to_slot(slot.drone, slot.slot_index)
		return
	slot.drone = _spawn_drone(slot.slot_index)
	if slot.drone != null:
		_bind_drone_to_slot(slot.drone, slot.slot_index)
		if replay_state:
			_sync_slot_to_drone(slot)

func _spawn_drone(slot_index: int) -> DroneController:
	if turret == null or _drone_bay_weapon == null:
		return null
	if _drone_bay_weapon.drone_scene == null:
		return null

	var inst: Node = _drone_bay_weapon.drone_scene.instantiate()
	var drone_controller: DroneController = inst as DroneController
	if drone_controller == null:
		if inst != null:
			inst.queue_free()
		return null

	drone_controller.name = "Drone_%d" % slot_index
	var parent_node: Node = _resolve_drone_parent()
	if parent_node == null:
		drone_controller.queue_free()
		return null
	parent_node.add_child(drone_controller)
	drone_controller.global_transform = _get_drone_spawn_transform()
	return drone_controller

func _resolve_drone_parent() -> Node:
	if turret == null:
		return null
	var scene_root: Node = turret.get_tree().current_scene
	if scene_root != null:
		return scene_root
	return turret

func _get_drone_spawn_transform() -> Transform3D:
	if turret == null:
		return Transform3D.IDENTITY
	var m: Marker3D = turret.muzzle
	if m != null:
		return m.global_transform
	return turret.global_transform

func _bind_drone_to_slot(drone_controller: DroneController, slot_index: int) -> void:
	if drone_controller == null:
		return
	drone_controller.configure_drone(get_instance_id(), slot_index, _resolve_swarm_anchor())
	if not drone_controller.state_reported.is_connected(_on_drone_state_reported):
		drone_controller.state_reported.connect(_on_drone_state_reported)

func _resolve_swarm_anchor() -> Node3D:
	if turret == null:
		return null
	var turret_controller: TurretController = turret.get_controller()
	if turret_controller != null and turret_controller.get_parent() is Node3D:
		return turret_controller.get_parent() as Node3D
	if turret.get_parent() is Node3D:
		return turret.get_parent() as Node3D
	return turret

func _on_drone_state_reported(origin_bay_id: int, slot_index: int, next_state: int) -> void:
	if origin_bay_id != get_instance_id():
		return
	if slot_index < 0 or slot_index >= _drone_slots.size():
		return
	var slot: DroneSlot = _drone_slots[slot_index]
	if slot == null:
		return

	match next_state:
		DRONE_STATE_ACTIVE:
			slot.state = DRONE_STATE_ACTIVE
		DRONE_STATE_ATTACKING:
			slot.state = DRONE_STATE_ATTACKING
		DRONE_STATE_RETURNING:
			slot.state = DRONE_STATE_RETURNING
			slot.return_remaining = max(slot.return_remaining, _get_redock_time())
			slot.set_target(null)
		DRONE_STATE_DOCKED:
			slot.return_remaining = 0.0
			slot.set_target(null)
			slot.state = DRONE_STATE_CHARGING if slot.charge_remaining < slot.max_charge else DRONE_STATE_DOCKED
			slot.drone = null

func _despawn_slot_drone(slot: DroneSlot) -> void:
	if slot == null:
		return
	if _is_drone_valid(slot.drone):
		slot.drone.queue_free()
	slot.drone = null

func _despawn_all_drones() -> void:
	for slot in _drone_slots:
		_despawn_slot_drone(slot)

func _is_drone_valid(drone_controller: DroneController) -> bool:
	return drone_controller != null and is_instance_valid(drone_controller)

func _try_launch(candidates: Array[Node3D]) -> void:
	if _cooldown > 0.0:
		return
	var slot: DroneSlot = _first_docked_slot()
	if slot == null:
		return
	var target: Node3D = _pick_first_candidate(candidates)

	_ensure_slot_drone(slot, false)
	if not _is_drone_valid(slot.drone):
		return
	slot.max_charge = max(0.01, slot.max_charge)
	slot.charge_remaining = slot.max_charge
	slot.return_remaining = 0.0
	slot.set_target(target)
	_command_drone_launch(slot, target)
	_cooldown = _get_launch_interval()

func _begin_return(slot: DroneSlot) -> void:
	if slot == null:
		return
	_ensure_slot_drone(slot)
	if not _is_drone_valid(slot.drone):
		return
	slot.return_remaining = _get_redock_time()
	slot.set_target(null)
	_command_drone_begin_return(slot)

func _update_visual_charge() -> void:
	if turret == null or turret.visual_controller == null:
		return
	var interval: float = _get_launch_interval()
	if interval <= 0.0:
		turret.visual_controller.set_charge(1.0)
		return
	var charge_t: float = 1.0 - clamp(_cooldown / interval, 0.0, 1.0)
	turret.visual_controller.set_charge(charge_t)

func _is_target_valid_candidate(target: Node3D, candidates: Array[Node3D]) -> bool:
	if target == null:
		return false
	for candidate in candidates:
		if candidate == target:
			return true
	return false

func _pick_first_candidate(candidates: Array[Node3D]) -> Node3D:
	if candidates.is_empty():
		return null
	return candidates[0]

func _first_docked_slot() -> DroneSlot:
	for slot in _drone_slots:
		if slot.state == DRONE_STATE_DOCKED:
			return slot
	return null

func _get_desired_drone_count() -> int:
	return max(0, _drone_bay_weapon.base_drone_count) if _drone_bay_weapon != null else 0

func _get_charge_time() -> float:
	return max(0.01, _drone_bay_weapon.drone_charge_time) if _drone_bay_weapon != null else 0.01

func _get_charge_recovery_rate() -> float:
	# charge_remaining is measured in "active seconds", so +1.0 per real second is a straightforward baseline.
	return 1.0

func _get_redock_time() -> float:
	return max(0.0, _drone_bay_weapon.drone_redock_time) if _drone_bay_weapon != null else 0.0

func _get_launch_interval() -> float:
	if _drone_bay_weapon == null:
		return 0.25
	return max(0.01, _drone_bay_weapon.launch_interval)

func _get_controller_priority_mode() -> int:
	if _drone_bay_weapon == null:
		return TurretController.TargetPriorityMode.CLOSEST
	match _drone_bay_weapon.target_priority:
		DroneBayWeaponDef.TargetPriority.WEAKEST_TOTAL_HP:
			return TurretController.TargetPriorityMode.WEAKEST_TOTAL_HP
		_:
			return TurretController.TargetPriorityMode.CLOSEST

func _get_discharge_rate_for_target(target: Node3D) -> float:
	if turret == null:
		return 1.0
	if target == null:
		return 1.0
	if _drone_bay_weapon == null:
		return 1.0

	var base_range: float = max(1.0, turret.get_base_range())
	var max_range: float = max(base_range, turret.get_max_assign_range())
	var base_sq: float = base_range * base_range
	var max_sq: float = max_range * max_range
	var dist_sq: float = turret.global_position.distance_squared_to(target.global_position)
	if dist_sq <= base_sq:
		return 1.0
	if max_range <= base_range:
		return 1.0
	if dist_sq <= max_sq:
		return max(1.0, _drone_bay_weapon.extended_range_discharge_mult)
	return 1.0

func _sync_slot_to_drone(slot: DroneSlot) -> void:
	if slot == null or not _is_drone_valid(slot.drone):
		return
	match slot.state:
		DRONE_STATE_ACTIVE:
			slot.drone.command_launch(slot.get_target())
		DRONE_STATE_ATTACKING:
			slot.drone.command_attack(slot.get_target())
		DRONE_STATE_RETURNING:
			slot.drone.command_begin_return()

func _command_drone_launch(slot: DroneSlot, target: Node3D) -> void:
	if slot == null or not _is_drone_valid(slot.drone):
		return
	slot.drone.command_launch(target)

func _command_drone_attack(slot: DroneSlot, target: Node3D) -> void:
	if slot == null or not _is_drone_valid(slot.drone):
		return
	slot.drone.command_attack(target)

func _command_drone_idle(slot: DroneSlot) -> void:
	if slot == null or not _is_drone_valid(slot.drone):
		return
	slot.drone.command_idle()

func _command_drone_begin_return(slot: DroneSlot) -> void:
	if slot == null or not _is_drone_valid(slot.drone):
		return
	slot.drone.command_begin_return()

func _command_drone_dock(slot: DroneSlot) -> void:
	if slot == null or not _is_drone_valid(slot.drone):
		return
	slot.drone.command_dock()
	slot.drone = null

func override_all_slot_max_charge(next_max_charge: float, preserve_fill_ratio: bool = true) -> void:
	for slot in _drone_slots:
		_apply_slot_max_charge_override(slot, next_max_charge, preserve_fill_ratio)

func override_slot_max_charge(slot_index: int, next_max_charge: float, preserve_fill_ratio: bool = true) -> void:
	if slot_index < 0 or slot_index >= _drone_slots.size():
		return
	var slot: DroneSlot = _drone_slots[slot_index]
	_apply_slot_max_charge_override(slot, next_max_charge, preserve_fill_ratio)

func _apply_slot_max_charge_override(slot: DroneSlot, next_max_charge: float, preserve_fill_ratio: bool) -> void:
	if slot == null:
		return
	var next_max: float = max(0.0, next_max_charge)
	if slot.max_charge <= 0.0:
		slot.max_charge = next_max
		slot.charge_remaining = clamp(slot.charge_remaining, 0.0, slot.max_charge)
		return

	if preserve_fill_ratio:
		var fill_ratio: float = clamp(slot.charge_remaining / max(0.01, slot.max_charge), 0.0, 1.0)
		slot.max_charge = next_max
		slot.charge_remaining = clamp(slot.max_charge * fill_ratio, 0.0, slot.max_charge)
	else:
		slot.max_charge = next_max
		slot.charge_remaining = clamp(slot.charge_remaining, 0.0, slot.max_charge)

func _prime_slots_full_charge() -> void:
	var full_charge: float = _get_charge_time()
	for slot in _drone_slots:
		if slot == null:
			continue
		slot.max_charge = full_charge
		slot.charge_remaining = full_charge
		slot.return_remaining = 0.0
		slot.state = DRONE_STATE_DOCKED
		slot.set_target(null)
		if _is_drone_valid(slot.drone):
			_command_drone_dock(slot)
