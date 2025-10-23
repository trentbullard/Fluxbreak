# scripts/components/threat_director.gd (godot 4.5)
extends Node
class_name ThreatDirector

@export var base_threat: float = 6.0
@export var per_min_slope: float = 4.0  # linear ramp per minute
@export var quad_per_min2: float = 0.0  # start at 0; add later if you need a curve
@export var pps_coupling: float = 0.85  # how much pps pulls threat
@export var tether_weight: float = 0.25 # 0..1; 0.25 = gentle  

func compute_threat(elapsed_sec: float, pps: float) -> float:
	var t_min: float = elapsed_sec / 60.0
	var target_curve: float = base_threat + per_min_slope * t_min + quad_per_min2 * t_min * t_min
	var pps_anchor: float = pps_coupling * pps
	var threat: float = lerp(target_curve, pps_anchor, clamp(tether_weight, 0.0, 1.0))
	return max(threat, 0.0)
