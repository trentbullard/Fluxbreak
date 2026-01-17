# content/defs/weapon_def.gd (godot 4.5)
extends Resource
class_name WeaponDef

@export var weapon_id: String
@export var display_name: String
@export var cost: int = 1500

@export_category("Firing / Targeting")

## Seconds between shots.
@export var fire_rate: float = 0.5

## Base hit chance before range decay and enemy evasion. 1.0 = perfect accuracy.
## Final hit chance is clamped to [0,1] after all modifiers.
@export var base_accuracy: float = 0.75

## Maximum effective targeting range (meters). Distance is normalized by this.
@export var base_range: float = 200.0

## Linear accuracy decay with distance (0..1).
##
## Computation (see scripts/weapons/player_turret.gd):
##   range_factor = clamp(distance / base_range, 0..1)          # 0 = point-blank, 1 = at/over base_range
##   acc_base     = clamp(base_accuracy + systems_bonus, 0..1)
##   scale        = lerp(1.0, 1.0 - accuracy_range_falloff, range_factor)
##   hit_chance   = clamp(acc_base * scale - target_evasion, 0..1)
##
## Intuition:
## - 0.0 → no drop with distance (flat line).
## - 1.0 → linearly drops to 0 at base_range.
## Recommended range: 0.0..1.0
##
## Extremes (target_evasion = 0):
## - distance = 0:               hit = clamp(base_accuracy + systems_bonus, 0..1)
## - distance >= base_range:     hit = clamp((base_accuracy + systems_bonus) * (1 - accuracy_range_falloff), 0..1)
@export_range(0.0, 1.0, 0.01) var accuracy_range_falloff: float = 0.50

@export_category("Outcome Model")

## Chance that a hit upgrades to a crit. Applied only on hits.
@export var crit_chance: float = 0.15
## On-hit chance to downgrade to a graze (reduced damage).
@export var graze_on_hit: float = 0.10
## On-miss chance to upgrade to a graze (glancing blow).
@export var graze_on_miss: float = 0.05
## Damage multiplier for grazes.
@export var graze_mult: float = 0.35
## Damage multiplier for crits.
@export var crit_mult: float = 1.5

@export_category("Damage")

## Minimum damage roll (before graze/crit multipliers).
@export var damage_min: float = 6.0
## Maximum damage roll (before graze/crit multipliers).
@export var damage_max: float = 12.0

@export_category("Visuals")

## Optional turret visual to instance on the mount (e.g., a model with a Muzzle).
@export var visual_scene: PackedScene

@export_category("Projectile & Effects")

## Scene instanced per shot; must implement Projectile.configure_shot(...).
@export var projectile_scene: PackedScene
## Status effects applied on hit/graze (order matters for stacking).
@export var status_effects: Array[StatusEffectDef] = []
## Audio played on fire; PlayerTurret randomizes pitch slightly.
@export var shot_sound: AudioStream
