# content/defs/ship_def.gd (Godot 4.5)
extends Resource
class_name ShipDef

@export var id: StringName = &""
@export var display_name: String = "Ship"

@export var loadout: ShipLoadoutDef
@export_range(0, 16, 1) var starting_weapons: int = 1

@export var explosion_scene: PackedScene

@export var max_hull: float = 100.0
@export var overheal: float = 0.0
@export var max_shield: float = 100.0
@export var shield_regen: float = 5.0
@export var base_evasion: float = 0.1

@export var max_speed_forward: float = 400.0
@export var max_speed_reverse: float = 60.0
@export var drag: float = 0.01
@export var accel_forward: float = 100.0
@export var accel_reverse: float = 60.0
@export var boost_mult: float = 1.5

@export var pickup_range: float = 40.0
@export var nanobot_gain_mult: float = 1.0
@export var score_gain_mult: float = 1.0

# Stored in degrees for easy authoring; `Ship` converts to radians on apply.
@export var max_ang_rate_deg: Vector3 = Vector3(120.0, 120.0, 120.0)
@export var angular_accel_deg: Vector3 = Vector3(500.0, 500.0, 500.0)

