# scripts/components/wave_budgeter.gd (godot 4.5)
extends Node
class_name WaveBudgeter

@export var enemy_points_per_threat: float = 1.4
@export var target_points_base: float = 4.0
@export var target_points_per_min: float = 0.4
@export var min_enemy_points: int = 3
@export var min_target_points: int = 1

func to_budgets(threat: float, elapsed_sec: float) -> Dictionary:
	var enemies_pts: int = int(round(threat * enemy_points_per_threat))
	var t_min: float = elapsed_sec / 60.0
	var targets_pts: int = int(round(target_points_base + target_points_per_min * t_min))
	enemies_pts = max(enemies_pts, min_enemy_points)
	targets_pts = max(targets_pts, min_target_points)
	return {
		"enemy_points": enemies_pts,
		"target_points": targets_pts
	}
