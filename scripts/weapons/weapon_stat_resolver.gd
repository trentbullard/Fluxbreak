extends RefCounted
class_name WeaponStatResolver

const Stat = StatTypes.Stat

static func resolve_snapshot(weapon: WeaponDef, compute_value: Callable = Callable()) -> WeaponStatSnapshot:
	var snapshot: WeaponStatSnapshot = WeaponStatSnapshot.new()
	if weapon == null:
		return snapshot

	var uses_channel: bool = weapon.uses_channel_stats()
	var uses_ramp: bool = weapon.uses_ramp_stats()

	var base_fire_rate: float = weapon.fire_rate
	var base_accuracy: float = weapon.base_accuracy
	var base_range: float = weapon.base_range
	var base_falloff: float = weapon.accuracy_range_falloff
	var base_crit_chance: float = weapon.crit_chance
	var base_graze_on_hit: float = weapon.graze_on_hit
	var base_graze_on_miss: float = weapon.graze_on_miss
	var base_crit_mult: float = weapon.crit_mult
	var base_graze_mult: float = weapon.graze_mult
	var base_damage_min: float = weapon.damage_min
	var base_damage_max: float = weapon.damage_max
	var base_channel_acquire: float = weapon.get_channel_acquire_time() if uses_channel else 0.0
	var base_channel_tick: float = weapon.get_channel_tick_interval() if uses_channel else 0.0
	var base_ramp_max_stacks: float = float(weapon.get_ramp_max_stacks()) if uses_ramp else 0.0
	var base_ramp_damage_per_stack: float = weapon.get_ramp_damage_per_stack() if uses_ramp else 0.0
	var base_ramp_stacks_on_hit: float = float(weapon.get_ramp_stacks_on_hit()) if uses_ramp else 0.0
	var base_ramp_stacks_on_crit: float = float(weapon.get_ramp_stacks_on_crit()) if uses_ramp else 0.0
	var base_ramp_stacks_lost_on_graze: float = float(weapon.get_ramp_stacks_lost_on_graze()) if uses_ramp else 0.0
	var base_ramp_stacks_lost_on_miss: float = float(weapon.get_ramp_stacks_lost_on_miss()) if uses_ramp else 0.0

	snapshot.fire_rate = max(0.01, _compute_value(compute_value, Stat.WEAPON_FIRE_RATE, base_fire_rate))
	snapshot.base_accuracy = clamp(_compute_value(compute_value, Stat.WEAPON_BASE_ACCURACY, base_accuracy), 0.0, 1.0)
	snapshot.range_falloff = clamp(_compute_value(compute_value, Stat.WEAPON_RANGE_FALLOFF, base_falloff), 0.0, 1.0)
	snapshot.crit_chance = clamp(_compute_value(compute_value, Stat.WEAPON_CRIT_CHANCE, base_crit_chance), 0.0, 1.0)
	snapshot.graze_on_hit = clamp(_compute_value(compute_value, Stat.WEAPON_GRAZE_ON_HIT, base_graze_on_hit), 0.0, 1.0)
	snapshot.graze_on_miss = clamp(_compute_value(compute_value, Stat.WEAPON_GRAZE_ON_MISS, base_graze_on_miss), 0.0, 1.0)
	snapshot.crit_mult = max(0.0, _compute_value(compute_value, Stat.WEAPON_CRIT_MULT, base_crit_mult))
	snapshot.graze_mult = max(0.0, _compute_value(compute_value, Stat.WEAPON_GRAZE_MULT, base_graze_mult))
	snapshot.damage_min = _compute_value(compute_value, Stat.WEAPON_DAMAGE_MIN, base_damage_min)
	snapshot.damage_max = _compute_value(compute_value, Stat.WEAPON_DAMAGE_MAX, base_damage_max)
	snapshot.base_range = _compute_value(compute_value, Stat.WEAPON_BASE_RANGE, base_range)
	snapshot.range_bonus_add = _compute_value(compute_value, Stat.WEAPON_RANGE_BONUS, 0.0)
	snapshot.systems_bonus_add = _compute_value(compute_value, Stat.WEAPON_SYSTEMS_BONUS, 0.0)
	snapshot.projectile_speed = _compute_value(compute_value, Stat.PROJECTILE_SPEED, 0.0)
	snapshot.projectile_life = _compute_value(compute_value, Stat.PROJECTILE_LIFE, 0.0)
	snapshot.projectile_spread_deg = _compute_value(compute_value, Stat.PROJECTILE_SPREAD, 0.0)

	if uses_channel:
		var tick_after_fire_rate: float = max(
			0.01,
			_compute_value(compute_value, Stat.WEAPON_FIRE_RATE, max(base_channel_tick, 0.01))
		)
		snapshot.channel_acquire_time = max(
			0.0,
			_compute_value(compute_value, Stat.WEAPON_CHANNEL_ACQUIRE_TIME, base_channel_acquire)
		)
		snapshot.channel_tick_interval = max(
			0.01,
			_compute_value(compute_value, Stat.WEAPON_CHANNEL_TICK_INTERVAL, tick_after_fire_rate)
		)

	if uses_ramp:
		snapshot.ramp_max_stacks = max(
			0.0,
			_compute_value(compute_value, Stat.WEAPON_RAMP_MAX_STACKS, base_ramp_max_stacks)
		)
		snapshot.ramp_damage_per_stack = max(
			0.0,
			_compute_value(compute_value, Stat.WEAPON_RAMP_DAMAGE_PER_STACK, base_ramp_damage_per_stack)
		)
		snapshot.ramp_stacks_on_hit = max(
			0.0,
			_compute_value(compute_value, Stat.WEAPON_RAMP_STACKS_ON_HIT, base_ramp_stacks_on_hit)
		)
		snapshot.ramp_stacks_on_crit = max(
			0.0,
			_compute_value(compute_value, Stat.WEAPON_RAMP_STACKS_ON_CRIT, base_ramp_stacks_on_crit)
		)
		snapshot.ramp_stacks_lost_on_graze = max(
			0.0,
			_compute_value(compute_value, Stat.WEAPON_RAMP_STACKS_LOST_ON_GRAZE, base_ramp_stacks_lost_on_graze)
		)
		snapshot.ramp_stacks_lost_on_miss = max(
			0.0,
			_compute_value(compute_value, Stat.WEAPON_RAMP_STACKS_LOST_ON_MISS, base_ramp_stacks_lost_on_miss)
		)

	return snapshot

static func apply_snapshot_to_turret(target: Object, snapshot: WeaponStatSnapshot) -> void:
	if target == null:
		return
	var safe_snapshot: WeaponStatSnapshot = snapshot if snapshot != null else WeaponStatSnapshot.new()
	target.set("eff_fire_rate", safe_snapshot.fire_rate)
	target.set("eff_base_accuracy", safe_snapshot.base_accuracy)
	target.set("eff_range_falloff", safe_snapshot.range_falloff)
	target.set("eff_crit_chance", safe_snapshot.crit_chance)
	target.set("eff_graze_on_hit", safe_snapshot.graze_on_hit)
	target.set("eff_graze_on_miss", safe_snapshot.graze_on_miss)
	target.set("eff_crit_mult", safe_snapshot.crit_mult)
	target.set("eff_graze_mult", safe_snapshot.graze_mult)
	target.set("eff_damage_min", safe_snapshot.damage_min)
	target.set("eff_damage_max", safe_snapshot.damage_max)
	target.set("eff_base_range", safe_snapshot.base_range)
	target.set("eff_range_bonus_add", safe_snapshot.range_bonus_add)
	target.set("eff_systems_bonus_add", safe_snapshot.systems_bonus_add)
	target.set("eff_projectile_speed", safe_snapshot.projectile_speed)
	target.set("eff_projectile_life", safe_snapshot.projectile_life)
	target.set("eff_projectile_spread_deg", safe_snapshot.projectile_spread_deg)
	target.set("eff_channel_acquire_time", safe_snapshot.channel_acquire_time)
	target.set("eff_channel_tick_interval", safe_snapshot.channel_tick_interval)
	target.set("eff_ramp_max_stacks", safe_snapshot.ramp_max_stacks)
	target.set("eff_ramp_damage_per_stack", safe_snapshot.ramp_damage_per_stack)
	target.set("eff_ramp_stacks_on_hit", safe_snapshot.ramp_stacks_on_hit)
	target.set("eff_ramp_stacks_on_crit", safe_snapshot.ramp_stacks_on_crit)
	target.set("eff_ramp_stacks_lost_on_graze", safe_snapshot.ramp_stacks_lost_on_graze)
	target.set("eff_ramp_stacks_lost_on_miss", safe_snapshot.ramp_stacks_lost_on_miss)

static func _compute_value(compute_value: Callable, stat_id: int, base_value: float) -> float:
	if compute_value.is_valid():
		return float(compute_value.call(stat_id, base_value))
	return base_value
