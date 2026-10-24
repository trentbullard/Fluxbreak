# scripts/components/threat_director.gd (Godot 4.7.2)
extends Node
class_name ThreatDirector

## Threat at the first wave before elapsed-time growth.
@export var base_threat: float = 5.0
## Threat added per completed local wave.
@export var per_wave_slope: float = 1.35
## Threat added per minute of sector time.
@export var per_min_slope: float = 0.9
## Legacy additive stage bonus; Campaign quantity carryover omits this term.
@export var stage_bonus_per_index: float = 1.5
## Player damage rate treated as neutral by the performance adjustment.
@export var performance_reference_pps: float = 20.0
## Strength of the player damage-rate adjustment before its bounds.
@export_range(0.0, 1.0, 0.01) var performance_weight: float = 0.45
## Maximum upward performance adjustment.
@export_range(0.0, 0.5, 0.01) var performance_upshift_limit: float = 0.18
## Maximum downward damage-rate adjustment and basis for incoming-damage relief.
@export_range(0.0, 0.5, 0.01) var performance_downshift_limit: float = 0.12
## Incoming damage rate that supplies the full configured relief.
@export var incoming_damage_reference: float = 18.0
## Fraction of the downward adjustment available as incoming-damage relief.
@export_range(0.0, 1.0, 0.01) var incoming_damage_relief_weight: float = 0.35

## Original wave/time threat curve without player-performance adjustments.
func compute_macro_threat(
	elapsed_sec: float,
	wave_index: int,
	stage_index: int = 0
) -> float:
	var t_min: float = elapsed_sec / 60.0
	var wave_term: float = per_wave_slope * float(max(wave_index - 1, 0))
	var stage_term: float = stage_bonus_per_index * float(max(stage_index, 0))
	return base_threat + wave_term + per_min_slope * t_min + stage_term


## Existing bounded performance adjustment, separated so quantity is constructed first.
func get_performance_scale(
	pps: float,
	incoming_damage_per_sec: float
) -> float:
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

	return 1.0 + performance_nudge - damage_relief


func compute_threat(
	elapsed_sec: float,
	wave_index: int,
	stage_index: int,
	pps: float,
	incoming_damage_per_sec: float
) -> float:
	var macro_curve: float = compute_macro_threat(elapsed_sec, wave_index, stage_index)
	var threat: float = macro_curve * get_performance_scale(pps, incoming_damage_per_sec)
	return max(threat, 0.0)
