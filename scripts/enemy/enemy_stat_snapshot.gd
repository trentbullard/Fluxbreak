extends RefCounted
class_name EnemyStatSnapshot

var max_hull: float = 0.0
var max_shield: float = 0.0
var shield_regen: float = 0.0
var evasion: float = 0.0
var thrust: float = 0.0
var weapon_stats: WeaponStatSnapshot = WeaponStatSnapshot.new()
var active_layers: PackedStringArray = PackedStringArray()
var layer_counts: Dictionary = {}
var source_tags: PackedStringArray = PackedStringArray()

func has_non_base_layers() -> bool:
	return not active_layers.is_empty()

func get_debug_summary() -> Dictionary:
	return {
		"active_layers": PackedStringArray(active_layers),
		"layer_counts": layer_counts.duplicate(true),
		"source_tags": PackedStringArray(source_tags),
		"has_non_base_layers": has_non_base_layers(),
	}
