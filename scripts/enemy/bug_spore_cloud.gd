extends EnemyAttackTelegraph
class_name BugSporeCloud

const CLOUD_TINT: Color = Color(0.75, 0.95, 0.20, 0.9)

var _tick_interval_sec: float = 0.5
var _next_tick_sec: float = 0.0
var _was_inside: bool = false

func _build_visuals() -> void:
	_attack_field = BugSporeCloudVisual.new()
	_attack_field.name = "LockedVolume"
	add_child(_attack_field)
	_attack_field.configure_sphere(_radius)

## The old strike snapshot becomes a fixed, immediately damaging cloud.
## Duration is also the divisor in the authored per-tick damage calculation.
func start_cloud(source: Enemy, target: Node3D, weapon_host: Object, duration_sec: float, radius: float, tick_interval_sec: float = 0.5, damage_multiplier: float = 1.2) -> void:
	if _active or _has_resolved:
		return
	_tick_interval_sec = maxf(tick_interval_sec, 0.05)
	if _warning_label.is_empty():
		set_warning_style("SPORE CLOUD", CLOUD_TINT)
	set_response_hint("LEAVE THE CLOUD")
	super.start_attack(source, target, weapon_host, maxf(duration_sec, 0.05), radius)
	if not _active:
		return
	if not _can_continue():
		cancel()
		return
	var damage_scale: float = maxf(damage_multiplier, 0.0) / _windup_sec
	eff_damage_min *= damage_scale
	eff_damage_max *= damage_scale
	_was_inside = contains_position(_target.global_position)
	if _was_inside:
		_apply_tick()
		_next_tick_sec = _tick_interval_sec

func _physics_process(delta: float) -> void:
	if _has_resolved:
		super._physics_process(delta)
		return
	if not _active:
		return
	if not _can_continue():
		cancel()
		return
	_elapsed_sec += maxf(delta, 0.0)
	var inside: bool = contains_position(_target.global_position)
	if inside:
		if _was_inside:
			# Catch up scheduled ticks during uninterrupted exposure, never at expiry.
			var through: float = minf(_elapsed_sec, _windup_sec)
			while _next_tick_sec <= through + 0.000001 and _next_tick_sec < _windup_sec - 0.000001:
				_apply_tick()
				_next_tick_sec += _tick_interval_sec
				if not _can_continue():
					cancel()
					return
		elif _elapsed_sec < _windup_sec and _elapsed_sec + 0.000001 >= _next_tick_sec:
			# A new entry receives one due tick, not a backlog from time outside.
			_apply_tick()
			_next_tick_sec = _elapsed_sec + _tick_interval_sec
	_was_inside = inside
	if not _can_continue():
		cancel()
		return
	_update_visuals(clampf(_elapsed_sec / _windup_sec, 0.0, 1.0))
	if _elapsed_sec >= _windup_sec:
		_resolve_attack()

func _can_continue() -> bool:
	return _active and not is_queued_for_deletion() and is_instance_valid(_source) and not _source._dead and not _source.is_queued_for_deletion() and is_instance_valid(_target) and not _target.is_queued_for_deletion() and _target.visible and (not _target.has_method("is_alive") or bool(_target.call("is_alive")))

func _apply_tick() -> void:
	var damage: float = randf_range(minf(eff_damage_min, eff_damage_max), maxf(eff_damage_min, eff_damage_max))
	if damage <= 0.0:
		return
	# Spatial exposure is the hit test. Poison has no additional accuracy/crit roll.
	if _target.has_method("apply_damage_over_time"):
		_target.call("apply_damage_over_time", damage, _context)
	elif _target.has_method("apply_damage"):
		_target.call("apply_damage", damage, _context)
	_pattern_hit = true

## Completion only fades the sprites and releases the actor's recovery state.
## There is no separate opening strike or final damage burst.
func _resolve_attack() -> void:
	_active = false
	_has_resolved = true
	_flash_remaining_sec = RELEASE_FLASH_SEC
	if _attack_field != null:
		_attack_field.set_release(1.0)
	_emit_pattern_resolution()
