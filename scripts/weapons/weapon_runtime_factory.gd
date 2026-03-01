# scripts/weapons/weapon_runtime_factory.gd (godot 4.5)
extends RefCounted
class_name WeaponRuntimeFactory

static func create_for(turret: PlayerTurret, weapon: WeaponDef) -> WeaponRuntime:
	if weapon == null:
		return WeaponRuntime.new(turret, weapon)
	if weapon is DroneBayWeaponDef:
		# Drone bay runtime is added in a follow-up step.
		return WeaponRuntime.new(turret, weapon)
	return ProjectileWeaponRuntime.new(turret, weapon)
