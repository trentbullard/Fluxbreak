extends Node
class_name EnemyCombatScalingDirector

@export var scaling_def: EnemyCombatScalingDef

var _carried_baseline_intensity: float = 0.0

func build_snapshot(wave_index: int, elapsed_sec: float) -> EnemyCombatScalingSnapshot:
	var snapshot: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
	var def: EnemyCombatScalingDef = scaling_def
	if def == null:
		return snapshot

	var local_intensity: float = _build_local_intensity(def, wave_index, elapsed_sec)
	var total_intensity: float = max(_carried_baseline_intensity + local_intensity, 0.0)
	_apply_snapshot_from_intensity(snapshot, def, total_intensity)
	return snapshot

func clear_carried_baseline() -> void:
	_carried_baseline_intensity = 0.0

func set_carried_baseline_from_snapshot(snapshot: EnemyCombatScalingSnapshot) -> void:
	if snapshot == null:
		_carried_baseline_intensity = 0.0
		return
	_carried_baseline_intensity = max(snapshot.intensity, 0.0)

func get_carried_baseline_intensity() -> float:
	return _carried_baseline_intensity

func _build_local_intensity(def: EnemyCombatScalingDef, wave_index: int, elapsed_sec: float) -> float:
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
	return intensity

func _apply_snapshot_from_intensity(
	snapshot: EnemyCombatScalingSnapshot,
	def: EnemyCombatScalingDef,
	intensity: float
) -> void:
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
