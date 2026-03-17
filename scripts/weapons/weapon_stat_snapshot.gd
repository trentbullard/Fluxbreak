extends RefCounted
class_name WeaponStatSnapshot

var fire_rate: float = 0.0
var base_accuracy: float = 0.0
var range_falloff: float = 0.0
var crit_chance: float = 0.0
var graze_on_hit: float = 0.0
var graze_on_miss: float = 0.0
var crit_mult: float = 1.0
var graze_mult: float = 0.3
var damage_min: float = 0.0
var damage_max: float = 0.0
var base_range: float = 0.0
var range_bonus_add: float = 0.0
var systems_bonus_add: float = 0.0
var projectile_speed: float = 0.0
var projectile_life: float = 0.0
var projectile_spread_deg: float = 0.0
var channel_acquire_time: float = 0.0
var channel_tick_interval: float = 0.0
var ramp_max_stacks: float = 0.0
var ramp_damage_per_stack: float = 0.0
var ramp_stacks_on_hit: float = 0.0
var ramp_stacks_on_crit: float = 0.0
var ramp_stacks_lost_on_graze: float = 0.0
var ramp_stacks_lost_on_miss: float = 0.0

func get_debug_summary() -> Dictionary:
	return {
		"fire_rate": fire_rate,
		"base_accuracy": base_accuracy,
		"range_falloff": range_falloff,
		"crit_chance": crit_chance,
		"graze_on_hit": graze_on_hit,
		"graze_on_miss": graze_on_miss,
		"crit_mult": crit_mult,
		"graze_mult": graze_mult,
		"damage_min": damage_min,
		"damage_max": damage_max,
		"base_range": base_range,
		"range_bonus_add": range_bonus_add,
		"systems_bonus_add": systems_bonus_add,
		"projectile_speed": projectile_speed,
		"projectile_life": projectile_life,
		"projectile_spread_deg": projectile_spread_deg,
		"channel_acquire_time": channel_acquire_time,
		"channel_tick_interval": channel_tick_interval,
		"ramp_max_stacks": ramp_max_stacks,
		"ramp_damage_per_stack": ramp_damage_per_stack,
		"ramp_stacks_on_hit": ramp_stacks_on_hit,
		"ramp_stacks_on_crit": ramp_stacks_on_crit,
		"ramp_stacks_lost_on_graze": ramp_stacks_lost_on_graze,
		"ramp_stacks_lost_on_miss": ramp_stacks_lost_on_miss,
	}
