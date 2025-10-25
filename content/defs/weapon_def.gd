extends Resource
class_name WeaponDef

# Firing / targeting
@export var fire_rate: float = 0.5
@export var base_accuracy: float = 0.75
@export var base_range: float = 200.0
@export var accuracy_range_falloff: float = 0.50

# Outcome model
@export var crit_chance: float = 0.15
@export var graze_on_hit: float = 0.10
@export var graze_on_miss: float = 0.05
@export var graze_mult: float = 0.35
@export var crit_mult: float = 1.5

# Damage
@export var damage_min: float = 6.0
@export var damage_max: float = 12.0

# Projectile + effects
@export var projectile_scene: PackedScene
@export var status_effects: Array[StatusEffectDef] = []
