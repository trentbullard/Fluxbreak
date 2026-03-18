extends RefCounted
class_name EnemyCombatScalingSnapshot

var intensity: float = 0.0
var hull_multiplier: float = 1.0
var shield_multiplier: float = 1.0
var shield_regen_multiplier: float = 1.0
var thrust_multiplier: float = 1.0
var damage_multiplier: float = 1.0
var range_multiplier: float = 1.0
var fire_rate_multiplier: float = 1.0
var accuracy_bonus: float = 0.0
var evasion_bonus: float = 0.0
var nanobot_multiplier: float = 1.0
var nanobot_variance_pct: float = 0.0

func has_scaling() -> bool:
	return intensity > 0.0001

func get_debug_summary() -> Dictionary:
	return {
		"active": has_scaling(),
		"intensity": intensity,
		"hull_multiplier": hull_multiplier,
		"shield_multiplier": shield_multiplier,
		"shield_regen_multiplier": shield_regen_multiplier,
		"thrust_multiplier": thrust_multiplier,
		"damage_multiplier": damage_multiplier,
		"range_multiplier": range_multiplier,
		"fire_rate_multiplier": fire_rate_multiplier,
		"accuracy_bonus": accuracy_bonus,
		"evasion_bonus": evasion_bonus,
		"nanobot_multiplier": nanobot_multiplier,
		"nanobot_variance_pct": nanobot_variance_pct,
	}
