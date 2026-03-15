# content/defs/ship_def.gd (Godot 4.5)
extends Resource
class_name ShipDef

@export var id: StringName = &""
@export var display_name: String = "Ship"

@export var loadout: ShipLoadoutDef
@export var starter_weapon_options: Array[ShipStarterWeaponOptionDef] = []
@export var visuals: ShipVisualDef

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
@export_enum("Combine", "Replace") var rigidbody_linear_damp_mode: int = RigidBody3D.DAMP_MODE_REPLACE
@export var rigidbody_linear_damp: float = 0.0
@export_enum("Combine", "Replace") var rigidbody_angular_damp_mode: int = RigidBody3D.DAMP_MODE_REPLACE
@export var rigidbody_angular_damp: float = 0.0

# Translation assist tuning (base handling before upgrades)
@export_range(0.0, 1.0, 0.01) var base_spaciness: float = 0.35  # 0=tight arcade, 1=floaty/newtonian
@export var coast_brake_accel: float = 120.0
@export var lateral_brake_accel: float = 90.0
@export var vertical_brake_accel: float = 90.0
@export var turn_assist_brake_bonus: float = 140.0
@export var no_throttle_turn_assist_bonus: float = 60.0
@export var counter_thrust_brake_mult: float = 1.35
@export var thrust_drag_scale: float = 0.2
@export var coast_drag_scale: float = 1.0
@export var forward_drag_scale_throttle: float = 0.0
@export var forward_drag_scale_coast: float = 0.35

@export var pickup_range: float = 40.0
@export var nanobot_gain_mult: float = 1.0
@export var score_gain_mult: float = 1.0

# Stored in degrees for easy authoring; `Ship` converts to radians on apply.
@export var max_ang_rate_deg: Vector3 = Vector3(120.0, 120.0, 120.0)
@export var angular_accel_deg: Vector3 = Vector3(500.0, 500.0, 500.0)

func get_ship_id() -> StringName:
	if id != &"":
		return id
	if resource_path != "":
		return StringName(resource_path.get_file().get_basename())
	return &"ship"

func get_display_name_or_default() -> String:
	var trimmed: String = display_name.strip_edges()
	if trimmed != "":
		return trimmed
	var from_id: String = String(get_ship_id()).replace("_", " ").strip_edges()
	if from_id != "":
		return from_id.capitalize()
	return "Ship"
