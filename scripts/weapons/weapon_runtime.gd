# scripts/weapons/weapon_runtime.gd (godot 4.5)
extends RefCounted
class_name WeaponRuntime

var turret: PlayerTurret
var weapon: WeaponDef
var _cooldown: float = 0.0

func _init(turret_owner: PlayerTurret = null, weapon_def: WeaponDef = null) -> void:
	turret = turret_owner
	weapon = weapon_def

func on_equip() -> void:
	pass

func on_unequip() -> void:
	pass

func physics_process(_delta: float) -> void:
	pass

func get_cooldown() -> float:
	return _cooldown

func set_cooldown(value: float) -> void:
	_cooldown = max(0.0, value)
