extends Node
class_name EnemyCombatScalingDirector

@export var scaling_def: EnemyCombatScalingDef

func build_snapshot(wave_index: int, elapsed_sec: float) -> EnemyCombatScalingSnapshot:
	var snapshot: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
	var def: EnemyCombatScalingDef = scaling_def
	if def == null:
		return snapshot

	var wave_progress: float = float(max(wave_index - def.start_wave, 0))
	var time_progress_min: float = max(elapsed_sec / 60.0, 0.0)
	var intensity: float = (
		wave_progress * def.per_wave_linear +
		wave_progress * wave_progress * def.per_wave_quadratic +
		time_progress_min * def.per_min_linear +
		time_progress_min * time_progress_min * def.per_min_quadratic
	)
	if def.intensity_cap > 0.0:
		intensity = min(intensity, def.intensity_cap)
	intensity = max(intensity, 0.0)

	snapshot.intensity = intensity
	snapshot.hull_multiplier = max(1.0 + intensity * def.hull_strength, 0.0)
	snapshot.shield_multiplier = max(1.0 + intensity * def.shield_strength, 0.0)
	snapshot.shield_regen_multiplier = max(1.0 + intensity * def.shield_regen_strength, 0.0)
	snapshot.thrust_multiplier = max(1.0 + intensity * def.thrust_strength, 0.0)
	snapshot.damage_multiplier = max(1.0 + intensity * def.damage_strength, 0.0)
	snapshot.range_multiplier = max(1.0 + intensity * def.range_strength, 0.0)
	snapshot.fire_rate_multiplier = max(
		1.0 / (1.0 + intensity * def.fire_rate_haste_strength),
		max(def.fire_rate_floor_scale, 0.01)
	)
	snapshot.accuracy_bonus = min(
		max(intensity * def.accuracy_bonus_per_intensity, 0.0),
		max(def.accuracy_bonus_cap, 0.0)
	)
	snapshot.evasion_bonus = min(
		max(intensity * def.evasion_bonus_per_intensity, 0.0),
		max(def.evasion_bonus_cap, 0.0)
	)
	snapshot.nanobot_multiplier = max(
		1.0 + intensity * def.nanobot_base_strength,
		max(def.nanobot_min_multiplier, 0.0)
	)
	snapshot.nanobot_variance_pct = clamp(def.nanobot_variance_pct, 0.0, 1.0)
	return snapshot
