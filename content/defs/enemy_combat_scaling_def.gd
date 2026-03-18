extends Resource
class_name EnemyCombatScalingDef

@export_group("Curve")
@export var start_wave: int = 2
@export var per_wave_linear: float = 0.08
@export var per_wave_quadratic: float = 0.0035
@export var per_min_linear: float = 0.0
@export var per_min_quadratic: float = 0.0
@export var intensity_cap: float = 3.5

@export_group("Combat Strength")
@export var hull_strength: float = 0.45
@export var shield_strength: float = 0.45
@export var shield_regen_strength: float = 0.30
@export var thrust_strength: float = 0.20
@export var damage_strength: float = 0.30
@export var range_strength: float = 0.08
@export var fire_rate_haste_strength: float = 0.20
@export var fire_rate_floor_scale: float = 0.55
@export var accuracy_bonus_per_intensity: float = 0.015
@export var accuracy_bonus_cap: float = 0.08
@export var evasion_bonus_per_intensity: float = 0.01
@export var evasion_bonus_cap: float = 0.05

@export_group("Reward Strength")
@export var nanobot_base_strength: float = 0.55
@export_range(0.0, 1.0, 0.01) var nanobot_variance_pct: float = 0.15
@export var nanobot_min_multiplier: float = 1.0
