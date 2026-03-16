extends WeaponDef
class_name BeamWeaponDef

@export_category("Beam Lock")
@export var lock_acquire_time: float = 0.35
@export var damage_tick_interval: float = 0.20

@export_category("Beam Ramp")
@export var max_ramp_stacks: int = 5
@export var damage_ramp_per_stack: float = 0.12
@export var ramp_gain_on_hit: int = 1
@export var ramp_gain_on_crit: int = 2
@export var ramp_loss_on_graze: int = 1
@export var ramp_loss_on_miss: int = 2

func uses_channel_stats() -> bool:
	return true

func uses_ramp_stats() -> bool:
	return true

func get_channel_acquire_time() -> float:
	return lock_acquire_time

func get_channel_tick_interval() -> float:
	return damage_tick_interval

func get_ramp_max_stacks() -> int:
	return max_ramp_stacks

func get_ramp_damage_per_stack() -> float:
	return damage_ramp_per_stack

func get_ramp_stacks_on_hit() -> int:
	return ramp_gain_on_hit

func get_ramp_stacks_on_crit() -> int:
	return ramp_gain_on_crit

func get_ramp_stacks_lost_on_graze() -> int:
	return ramp_loss_on_graze

func get_ramp_stacks_lost_on_miss() -> int:
	return ramp_loss_on_miss
