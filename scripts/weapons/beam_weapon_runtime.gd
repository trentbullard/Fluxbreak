extends WeaponRuntime
class_name BeamWeaponRuntime

signal state_changed(lock_state: int, target: Node3D, lock_progress: float, ramp_stacks: int)

enum LockState { IDLE, ACQUIRING, LOCKED }

const LOCK_PROGRESS_BUCKET_COUNT: int = 10

var _beam_weapon: BeamWeaponDef = null
var _target_ref: WeakRef = null
var _lock_state: int = LockState.IDLE
var _acquire_remaining: float = 0.0
var _tick_accumulator: float = 0.0
var _ramp_stacks: int = 0
var _last_progress_bucket: int = -1
var _last_target_id: int = 0
var _last_state: int = -1
var _last_ramp_stacks: int = -1

func _init(turret_owner: PlayerTurret = null, weapon_def: WeaponDef = null) -> void:
	super._init(turret_owner, weapon_def)
	_beam_weapon = weapon_def as BeamWeaponDef
	_target_ref = weakref(null)

func on_equip() -> void:
	_reset_lock_state(true)
	_update_visual_charge()
	_emit_state_changed_if_needed(true)

func on_unequip() -> void:
	_reset_lock_state(true)
	if turret != null and turret.visual_controller != null:
		turret.visual_controller.set_charge(0.0)
	_emit_state_changed_if_needed(true)

func physics_process(delta: float) -> void:
	if turret == null or _beam_weapon == null:
		_reset_lock_state(true)
		_update_visual_charge()
		_emit_state_changed_if_needed(false)
		return

	var controller: TurretController = turret.get_controller()
	if controller == null:
		_reset_lock_state(true)
		_update_visual_charge()
		_emit_state_changed_if_needed(false)
		return

	var assigned_target: Node3D = controller.get_assigned_target(turret, turret.team_id)
	if not _is_target_valid(assigned_target):
		_reset_lock_state(true)
		_update_visual_charge()
		_emit_state_changed_if_needed(false)
		return

	var current_target: Node3D = get_locked_target()
	if current_target != assigned_target:
		_start_acquiring_target(assigned_target)

	match _lock_state:
		LockState.IDLE:
			_start_acquiring_target(assigned_target)
		LockState.ACQUIRING:
			_process_acquire(delta)
		LockState.LOCKED:
			_process_locked(delta)

	_update_visual_charge()
	_emit_state_changed_if_needed(false)

func get_lock_state() -> int:
	return _lock_state

func get_locked_target() -> Node3D:
	if _target_ref == null:
		return null
	return _target_ref.get_ref() as Node3D

func get_lock_progress() -> float:
	if _beam_weapon == null:
		return 0.0
	match _lock_state:
		LockState.LOCKED:
			return 1.0
		LockState.ACQUIRING:
			var acquire_time: float = get_effective_lock_acquire_time()
			if acquire_time <= 0.0:
				return 1.0
			return clamp(1.0 - (_acquire_remaining / acquire_time), 0.0, 1.0)
		_:
			return 0.0

func get_ramp_stacks() -> int:
	return _ramp_stacks

func get_ramp_ratio() -> float:
	var max_stacks: int = get_effective_max_ramp_stacks()
	if _beam_weapon == null or max_stacks <= 0:
		return 0.0
	return clamp(float(_ramp_stacks) / float(max_stacks), 0.0, 1.0)

func get_effective_lock_acquire_time() -> float:
	if turret != null:
		return max(0.0, turret.eff_channel_acquire_time)
	if _beam_weapon == null:
		return 0.0
	return max(0.0, _beam_weapon.get_channel_acquire_time())

func get_effective_tick_interval() -> float:
	if turret != null:
		return max(0.01, turret.eff_channel_tick_interval)
	if _beam_weapon == null:
		return 0.01
	return max(0.01, _beam_weapon.get_channel_tick_interval())

func get_effective_max_ramp_stacks() -> int:
	if turret != null:
		return turret.get_effective_ramp_max_stacks()
	if _beam_weapon == null:
		return 0
	return maxi(_beam_weapon.get_ramp_max_stacks(), 0)

func get_effective_ramp_damage_per_stack() -> float:
	if turret != null:
		return max(0.0, turret.eff_ramp_damage_per_stack)
	if _beam_weapon == null:
		return 0.0
	return max(0.0, _beam_weapon.get_ramp_damage_per_stack())

func get_effective_ramp_stacks_on_hit() -> int:
	if turret != null:
		return turret.get_effective_ramp_stacks_on_hit()
	if _beam_weapon == null:
		return 0
	return maxi(_beam_weapon.get_ramp_stacks_on_hit(), 0)

func get_effective_ramp_stacks_on_crit() -> int:
	if turret != null:
		return turret.get_effective_ramp_stacks_on_crit()
	if _beam_weapon == null:
		return 0
	return maxi(_beam_weapon.get_ramp_stacks_on_crit(), 0)

func get_effective_ramp_stacks_lost_on_graze() -> int:
	if turret != null:
		return turret.get_effective_ramp_stacks_lost_on_graze()
	if _beam_weapon == null:
		return 0
	return maxi(_beam_weapon.get_ramp_stacks_lost_on_graze(), 0)

func get_effective_ramp_stacks_lost_on_miss() -> int:
	if turret != null:
		return turret.get_effective_ramp_stacks_lost_on_miss()
	if _beam_weapon == null:
		return 0
	return maxi(_beam_weapon.get_ramp_stacks_lost_on_miss(), 0)

func _process_acquire(delta: float) -> void:
	if _beam_weapon == null:
		return
	_acquire_remaining = max(0.0, _acquire_remaining - delta)
	if _acquire_remaining <= 0.0:
		_lock_state = LockState.LOCKED
		_tick_accumulator = 0.0

func _process_locked(delta: float) -> void:
	if _beam_weapon == null:
		return
	_clamp_ramp_stacks_to_effective_max()
	_tick_accumulator += delta
	var tick_interval: float = get_effective_tick_interval()
	while _tick_accumulator >= tick_interval:
		_tick_accumulator -= tick_interval
		_apply_tick()
		if _lock_state != LockState.LOCKED:
			break

func _apply_tick() -> void:
	var target: Node3D = get_locked_target()
	if turret == null or _beam_weapon == null or not _is_target_valid(target):
		_reset_lock_state(true)
		return

	var hit_chance: float = WeaponCombatResolver.compute_effective_accuracy_vs_target(turret, target)
	var outcome: int = WeaponCombatResolver.resolve_shot_for_turret(turret, hit_chance)
	var damage_min: float = minf(turret.eff_damage_min, turret.eff_damage_max)
	var damage_max: float = maxf(turret.eff_damage_min, turret.eff_damage_max)
	var rolled_damage: float = randf_range(damage_min, damage_max)
	var ramp_multiplier: float = 1.0 + get_effective_ramp_damage_per_stack() * float(_ramp_stacks)
	var ramped_damage: float = rolled_damage * max(0.0, ramp_multiplier)
	var combat_stat_context: CombatStatContext = turret.build_combat_stat_context(target)
	WeaponCombatResolver.apply_shot_to_target(
		turret,
		target,
		outcome,
		ramped_damage,
		turret.eff_graze_mult,
		turret.eff_crit_mult,
		weapon.status_effects,
		true,
		combat_stat_context
	)
	_apply_ramp_delta(outcome)

func _apply_ramp_delta(outcome: int) -> void:
	if _beam_weapon == null:
		return

	match outcome:
		WeaponCombatResolver.ShotResult.CRIT:
			_ramp_stacks += get_effective_ramp_stacks_on_crit()
		WeaponCombatResolver.ShotResult.HIT:
			_ramp_stacks += get_effective_ramp_stacks_on_hit()
		WeaponCombatResolver.ShotResult.GRAZE:
			_ramp_stacks -= get_effective_ramp_stacks_lost_on_graze()
		_:
			_ramp_stacks -= get_effective_ramp_stacks_lost_on_miss()

	_clamp_ramp_stacks_to_effective_max()

func _start_acquiring_target(target: Node3D) -> void:
	_target_ref = weakref(target) if target != null else weakref(null)
	_lock_state = LockState.ACQUIRING
	_tick_accumulator = 0.0
	_ramp_stacks = 0
	_acquire_remaining = get_effective_lock_acquire_time()
	if _acquire_remaining <= 0.0:
		_lock_state = LockState.LOCKED

func _reset_lock_state(clear_target: bool) -> void:
	if clear_target:
		_target_ref = weakref(null)
	_lock_state = LockState.IDLE
	_acquire_remaining = 0.0
	_tick_accumulator = 0.0
	_ramp_stacks = 0

func _is_target_valid(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.visible:
		return false

	var origin: Vector3 = WeaponCombatResolver.get_shot_origin(turret)
	var max_range: float = turret.get_max_assign_range() if turret != null else 0.0
	if max_range <= 0.0:
		return false
	var max_range_sq: float = max_range * max_range
	var distance_sq: float = origin.distance_squared_to(target.global_position)
	return distance_sq <= max_range_sq

func _clamp_ramp_stacks_to_effective_max() -> void:
	var max_stacks: int = get_effective_max_ramp_stacks()
	_ramp_stacks = clampi(_ramp_stacks, 0, max_stacks)

func _update_visual_charge() -> void:
	if turret == null or turret.visual_controller == null:
		return
	turret.visual_controller.set_charge(get_lock_progress())

func _emit_state_changed_if_needed(force: bool) -> void:
	var target: Node3D = get_locked_target()
	var target_id: int = target.get_instance_id() if target != null else 0
	var progress_bucket: int = int(floor(get_lock_progress() * float(LOCK_PROGRESS_BUCKET_COUNT)))
	var should_emit: bool = force
	if not should_emit and target_id != _last_target_id:
		should_emit = true
	if not should_emit and _lock_state != _last_state:
		should_emit = true
	if not should_emit and _ramp_stacks != _last_ramp_stacks:
		should_emit = true
	if not should_emit and progress_bucket != _last_progress_bucket:
		should_emit = true

	if should_emit:
		_last_target_id = target_id
		_last_state = _lock_state
		_last_ramp_stacks = _ramp_stacks
		_last_progress_bucket = progress_bucket
		state_changed.emit(_lock_state, target, get_lock_progress(), _ramp_stacks)
