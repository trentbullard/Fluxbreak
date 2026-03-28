extends Node3D
class_name BossGateway

@export var display_name: String = "Boss Gateway"
@export var docking_radius: float = 240.0
@export var docking_time: float = 2.5
@export var spin_speed_rad_per_sec: float = 0.4

func _ready() -> void:
	add_to_group("boss_gateways")

func _process(delta: float) -> void:
	rotate_y(max(spin_speed_rad_per_sec, 0.0) * max(delta, 0.0))

func get_display_name() -> String:
	var trimmed: String = display_name.strip_edges()
	if trimmed != "":
		return trimmed
	return "Boss Gateway"

func get_docking_radius() -> float:
	return max(docking_radius, 0.0)

func get_docking_time() -> float:
	return max(docking_time, 0.0)
