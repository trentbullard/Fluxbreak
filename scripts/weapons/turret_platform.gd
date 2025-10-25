# scripts/weapons/turret_platform.gd
extends Node3D
class_name TurretPlatform

enum Size { SMALL, MEDIUM, LARGE }

@export var mount_id: String = ""
@export var size: Size = Size.SMALL
@export var allowed_sizes: Array[Size] = [Size.SMALL, Size.MEDIUM, Size.LARGE]  # optional
@export var turret_path: NodePath        # points to a PlayerTurret

var _turret: PlayerTurret = null

func _ready() -> void:
	_turret = get_node_or_null(turret_path) as PlayerTurret

func get_turret() -> PlayerTurret:
	return _turret

func set_weapon(w: WeaponDef, team_id_val: int, keep_cooldown: bool = true) -> void:
	if _turret == null:
		return
	if keep_cooldown:
		_turret.swap_weapon(w, true)
	else:
		_turret.apply_weapon(w, team_id_val)
