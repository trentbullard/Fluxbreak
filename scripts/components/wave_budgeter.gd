# scripts/components/wave_budgeter.gd (godot 4.5)
extends Node
class_name WaveBudgeter

@export var enemy_points_per_threat: float = 1.4
@export var enemy_points_per_wave: float = 0.4
@export var target_points_base: float = 1.0
@export var target_points_per_wave: float = 0.25
@export var min_enemy_points: int = 3
@export var min_target_points: int = 0

func to_budgets(threat: float, elapsed_sec: float, wave_index: int, card: WaveCard = null) -> Dictionary:
	var enemies_pts: int = int(round(threat * enemy_points_per_threat + float(max(wave_index - 1, 0)) * enemy_points_per_wave))
	var targets_pts: int = int(round(target_points_base + float(max(wave_index - 1, 0)) * target_points_per_wave))
	if card != null:
		targets_pts = int(round(float(targets_pts) * max(card.in_wave_target_budget_scale, 0.0)))
	enemies_pts = max(enemies_pts, min_enemy_points)
	targets_pts = max(targets_pts, min_target_points)
	return {
		"enemy_points": enemies_pts,
		"target_points": targets_pts
	}
