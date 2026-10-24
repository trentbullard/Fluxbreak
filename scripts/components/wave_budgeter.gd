# scripts/components/wave_budgeter.gd (Godot 4.7.2)
extends Node
class_name WaveBudgeter

## Enemy purchase points contributed by one macro-threat point.
@export var enemy_points_per_threat: float = 1.4
## Additional enemy purchase points per completed local wave.
@export var enemy_points_per_wave: float = 0.4
## Target purchase points before local-wave growth.
@export var target_points_base: float = 1.0
## Additional target purchase points per completed local wave.
@export var target_points_per_wave: float = 0.25
## Minimum enemy purchase allocation after quantity-curve construction.
@export var min_enemy_points: int = 3
## Minimum target purchase allocation.
@export var min_target_points: int = 0

## Campaign-only geometric factor applied once per local wave after the start wave.
@export_range(1.0, 1.2, 0.001) var campaign_geometric_growth: float = 1.025
## Local waves through this wave keep the original Campaign quantity curve.
@export_range(1, 100, 1) var campaign_geometric_start_wave: int = 10
## Fraction of the preceding sector's last ordinary allocation used at sector opening.
@export_range(0.0, 1.0, 0.01) var campaign_carryover_opening_fraction: float = 0.4
## Multiplier on first-sector local growth above its opening value after carryover.
@export_range(0.0, 3.0, 0.05) var campaign_local_growth_multiplier: float = 1.5


## Unrounded original enemy allocation, before Campaign quantity and adaptive changes.
func get_base_enemy_points(threat: float, wave_index: int) -> float:
	return threat * enemy_points_per_threat + float(max(wave_index - 1, 0)) * enemy_points_per_wave


## Builds a Campaign-only quantity curve. Adaptive adjustments belong to the caller.
## A negative carryover reference selects the first-sector curve.
func build_campaign_quantity_budget(
	macro_threat: float,
	wave_index: int,
	opening_macro_threat: float,
	carryover_reference: float = -1.0
) -> Dictionary:
	var geometric_exponent: int = max(wave_index - campaign_geometric_start_wave, 0)
	var geometric_multiplier: float = pow(max(campaign_geometric_growth, 1.0), float(geometric_exponent))
	var local_quantity_points: float = max(get_base_enemy_points(macro_threat, wave_index), float(min_enemy_points)) * geometric_multiplier
	var carryover_active: bool = carryover_reference >= 0.0
	var quantity_curve_points: float = local_quantity_points
	if carryover_active:
		var opening_points: float = max(get_base_enemy_points(opening_macro_threat, 1), float(min_enemy_points))
		var local_growth: float = max(local_quantity_points - opening_points, 0.0)
		quantity_curve_points = carryover_reference * campaign_carryover_opening_fraction + local_growth * campaign_local_growth_multiplier
	quantity_curve_points = max(quantity_curve_points, float(min_enemy_points))
	return {
		"enemy_points_pre_adaptive": int(round(quantity_curve_points)),
		"quantity_curve_points": quantity_curve_points,
		"local_quantity_points": local_quantity_points,
		"geometric_multiplier": geometric_multiplier,
		"carryover_reference": carryover_reference,
		"carryover_active": carryover_active
	}

func to_budgets(threat: float, elapsed_sec: float, wave_index: int, card: WaveCard = null) -> Dictionary:
	var enemies_pts: int = int(round(get_base_enemy_points(threat, wave_index)))
	var targets_pts: int = int(round(target_points_base + float(max(wave_index - 1, 0)) * target_points_per_wave))
	if card != null:
		targets_pts = int(round(float(targets_pts) * max(card.in_wave_target_budget_scale, 0.0)))
	enemies_pts = max(enemies_pts, min_enemy_points)
	targets_pts = max(targets_pts, min_target_points)
	return {
		"enemy_points": enemies_pts,
		"target_points": targets_pts
	}
