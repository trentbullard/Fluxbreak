# content/defs/drone_bay_weapon_def.gd (godot 4.5)
extends WeaponDef
class_name DroneBayWeaponDef

enum TargetPriority {
	WEAKEST_TOTAL_HP,
	CLOSEST,
}

@export_category("Drone Bay")
@export_range(0, 64, 1) var base_drone_count: int = 3
@export var drone_scene: PackedScene
@export var drone_weapon: WeaponDef
@export var drone_charge_time: float = 8.0
@export var drone_redock_time: float = 1.5
@export var launch_interval: float = 0.25
@export var extended_range_discharge_mult: float = 1.15
@export var target_priority: TargetPriority = TargetPriority.WEAKEST_TOTAL_HP
