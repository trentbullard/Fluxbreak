extends RefCounted
class_name EnemyStatSnapshot

var max_hull: float = 0.0
var max_shield: float = 0.0
var shield_regen: float = 0.0
var evasion: float = 0.0
var thrust: float = 0.0
var weapon_stats: WeaponStatSnapshot = WeaponStatSnapshot.new()
var faction_id: StringName = &""
var role_id: StringName = &""
var combat_scaling_intensity: float = 0.0
var nanobot_multiplier: float = 1.0
var active_layers: PackedStringArray = PackedStringArray()
var layer_counts: Dictionary = {}
var source_tags: PackedStringArray = PackedStringArray()

func has_non_base_layers() -> bool:
	return not active_layers.is_empty()

func get_debug_summary() -> Dictionary:
	return {
		"faction_id": String(faction_id),
		"role_id": String(role_id),
		"body_stats": {
			"max_hull": max_hull,
			"max_shield": max_shield,
			"shield_regen": shield_regen,
			"evasion": evasion,
			"thrust": thrust,
		},
		"weapon_stats": weapon_stats.get_debug_summary() if weapon_stats != null else {},
		"combat_scaling_intensity": combat_scaling_intensity,
		"nanobot_multiplier": nanobot_multiplier,
		"active_layers": PackedStringArray(active_layers),
		"layer_counts": layer_counts.duplicate(true),
		"source_tags": PackedStringArray(source_tags),
		"has_non_base_layers": has_non_base_layers(),
	}
