# scripts/components/threat_director.gd (godot 4.5)
extends Node
class_name ThreatDirector

@export var base_threat: float = 5.0
@export var per_wave_slope: float = 1.35
@export var per_min_slope: float = 0.9
@export var stage_bonus_per_index: float = 1.5
@export var performance_reference_pps: float = 20.0
@export_range(0.0, 1.0, 0.01) var performance_weight: float = 0.45
@export_range(0.0, 0.5, 0.01) var performance_upshift_limit: float = 0.18
@export_range(0.0, 0.5, 0.01) var performance_downshift_limit: float = 0.12
@export var incoming_damage_reference: float = 18.0
@export_range(0.0, 1.0, 0.01) var incoming_damage_relief_weight: float = 0.35

func compute_threat(
	elapsed_sec: float,
	wave_index: int,
	stage_index: int,
	pps: float,
	incoming_damage_per_sec: float
) -> float:
	var t_min: float = elapsed_sec / 60.0
	var wave_term: float = per_wave_slope * float(max(wave_index - 1, 0))
	var stage_term: float = stage_bonus_per_index * float(max(stage_index, 0))
	var macro_curve: float = base_threat + wave_term + per_min_slope * t_min + stage_term

	var performance_nudge: float = 0.0
	if performance_reference_pps > 0.0:
		var perf_ratio: float = (pps / performance_reference_pps) - 1.0
		performance_nudge = clamp(
			perf_ratio * performance_weight,
			-performance_downshift_limit,
			performance_upshift_limit
		)

	var damage_relief: float = 0.0
	if incoming_damage_reference > 0.0:
		damage_relief = clamp(incoming_damage_per_sec / incoming_damage_reference, 0.0, 1.0)
		damage_relief *= incoming_damage_relief_weight * performance_downshift_limit

	var threat: float = macro_curve * (1.0 + performance_nudge - damage_relief)
	return max(threat, 0.0)
