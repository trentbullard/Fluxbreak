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
