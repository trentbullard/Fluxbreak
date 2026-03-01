# scripts/weapons/drone_bay_weapon_runtime.gd (godot 4.5)
extends WeaponRuntime
class_name DroneBayWeaponRuntime

const DRONE_STATE_DOCKED: int = 0
const DRONE_STATE_ACTIVE: int = 1
const DRONE_STATE_RETURNING: int = 2
const DRONE_STATE_CHARGING: int = 3

class DroneSlot extends RefCounted:
	var state: int = 0
	var charge_remaining: float = 0.0
	var return_remaining: float = 0.0
	var target_ref: WeakRef = null

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
	if turret != null and turret.visual_controller != null:
		turret.visual_controller.set_charge(0.0)

func on_unequip() -> void:
	_drone_slots.clear()

func physics_process(delta: float) -> void:
	if turret == null or _drone_bay_weapon == null:
		return

	var controller: TurretController = turret.get_controller()
	if controller == null:
		return

	_sync_slot_count()
	_cooldown = max(0.0, _cooldown - delta)

	var candidates: Array[Node3D] = _collect_enemy_candidates(controller.get_live_targets())
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
		if slot.state == DRONE_STATE_ACTIVE:
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
		if slot.state != DRONE_STATE_ACTIVE:
			continue
		var target: Node3D = slot.get_target()
		if target != null:
			out.append(target)
	return out

func _sync_slot_count() -> void:
	var desired: int = _get_desired_drone_count()
	while _drone_slots.size() < desired:
		_drone_slots.append(DroneSlot.new())
	while _drone_slots.size() > desired:
		_drone_slots.remove_at(_drone_slots.size() - 1)

func _tick_slots(delta: float, candidates: Array[Node3D]) -> void:
	for slot in _drone_slots:
		match slot.state:
			DRONE_STATE_DOCKED:
				slot.charge_remaining = 0.0
				slot.return_remaining = 0.0
				slot.set_target(null)
			DRONE_STATE_ACTIVE:
				slot.charge_remaining = max(0.0, slot.charge_remaining - delta)
				if slot.charge_remaining <= 0.0:
					_begin_return(slot)
					continue
				var current_target: Node3D = slot.get_target()
				if not _is_target_valid_candidate(current_target, candidates):
					slot.set_target(_select_target(candidates))
			DRONE_STATE_RETURNING:
				slot.return_remaining = max(0.0, slot.return_remaining - delta)
				if slot.return_remaining <= 0.0:
					slot.state = DRONE_STATE_DOCKED
					slot.charge_remaining = 0.0
					slot.return_remaining = 0.0
					slot.set_target(null)

func _try_launch(candidates: Array[Node3D]) -> void:
	if _cooldown > 0.0:
		return
	if candidates.is_empty():
		return
	var slot: DroneSlot = _first_docked_slot()
	if slot == null:
		return
	var target: Node3D = _select_target(candidates)
	if target == null:
		return

	slot.state = DRONE_STATE_ACTIVE
	slot.charge_remaining = _get_charge_time()
	slot.return_remaining = 0.0
	slot.set_target(target)
	_cooldown = _get_launch_interval()

func _begin_return(slot: DroneSlot) -> void:
	slot.state = DRONE_STATE_RETURNING
	slot.return_remaining = _get_redock_time()
	slot.set_target(null)

func _update_visual_charge() -> void:
	if turret == null or turret.visual_controller == null:
		return
	var interval: float = _get_launch_interval()
	if interval <= 0.0:
		turret.visual_controller.set_charge(1.0)
		return
	var charge_t: float = 1.0 - clamp(_cooldown / interval, 0.0, 1.0)
	turret.visual_controller.set_charge(charge_t)

func _collect_enemy_candidates(detected: Array[Node3D]) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for target in detected:
		if target == null or not is_instance_valid(target):
			continue
		if _is_enemy_target(target):
			out.append(target)
	return out

func _is_enemy_target(target: Node3D) -> bool:
	if target.has_meta("kind"):
		var kind: String = String(target.get_meta("kind"))
		if kind == "enemy":
			return true
	if target.is_in_group("enemy"):
		return true
	if target.has_method("get_evasion") and target.has_method("apply_damage"):
		return true
	return false

func _is_target_valid_candidate(target: Node3D, candidates: Array[Node3D]) -> bool:
	if target == null:
		return false
	for candidate in candidates:
		if candidate == target:
			return true
	return false

func _select_target(candidates: Array[Node3D]) -> Node3D:
	if candidates.is_empty() or turret == null:
		return null

	var best: Node3D = null
	var best_score: float = INF
	var best_dist_sq: float = INF
	for candidate in candidates:
		var score: float = _estimate_total_health(candidate)
		var dist_sq: float = turret.global_position.distance_squared_to(candidate.global_position)
		var is_better: bool = false
		if score < best_score:
			is_better = true
		elif is_equal_approx(score, best_score) and dist_sq < best_dist_sq:
			is_better = true
		if is_better:
			best = candidate
			best_score = score
			best_dist_sq = dist_sq
	return best

func _estimate_total_health(target: Node3D) -> float:
	var hull: float = _read_float_property(target, "hull")
	var shield: float = _read_float_property(target, "shield")
	return max(0.0, hull) + max(0.0, shield)

func _read_float_property(target: Object, property_name: String) -> float:
	var raw: Variant = target.get(property_name)
	var t: int = typeof(raw)
	if t == TYPE_FLOAT or t == TYPE_INT:
		return float(raw)
	return 0.0

func _first_docked_slot() -> DroneSlot:
	for slot in _drone_slots:
		if slot.state == DRONE_STATE_DOCKED:
			return slot
	return null

func _get_desired_drone_count() -> int:
	return max(0, _drone_bay_weapon.base_drone_count) if _drone_bay_weapon != null else 0

func _get_charge_time() -> float:
	return max(0.01, _drone_bay_weapon.drone_charge_time) if _drone_bay_weapon != null else 0.01

func _get_redock_time() -> float:
	return max(0.0, _drone_bay_weapon.drone_redock_time) if _drone_bay_weapon != null else 0.0

func _get_launch_interval() -> float:
	if _drone_bay_weapon == null:
		return 0.25
	return max(0.01, _drone_bay_weapon.launch_interval)
