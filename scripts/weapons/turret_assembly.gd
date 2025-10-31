# scripts/weapons/turret_assembly.gd
extends Node3D
class_name TurretAssembly

@export var mount_index: int = 0
@export var team_id: int = 0
@export var controller_path: NodePath
@export var default_visual: PackedScene

@onready var turret: PlayerTurret = $Turret

signal weapon_changed(new_weapon: WeaponDef)

func _enter_tree() -> void:
	if turret == null:
		turret = get_node_or_null("Turret")
	if turret != null:
		turret.controller_path = controller_path
		turret.team_id = team_id

func apply_weapon(w: WeaponDef, keep_cooldown: bool) -> void:
	if turret == null: return
	if w == null:
		clear_weapon(keep_cooldown)
		return
	turret.apply_weapon(w, team_id)
	weapon_changed.emit(w)
	_update_visual_for_weapon(w)

func swap_weapon(w: WeaponDef, keep_cooldown: bool) -> void:
	if turret == null: return
	turret.swap_weapon(w, keep_cooldown)
	weapon_changed.emit(w)
	_update_visual_for_weapon(w)

func clear_weapon(keep_cooldown: bool) -> void:
	if turret == null: return
	turret.swap_weapon(null, keep_cooldown)
	weapon_changed.emit(null)
	_update_visual_for_weapon(null)

func has_weapon() -> bool:
	return turret != null and turret.get_weapon() != null

func _update_visual_for_weapon(w: WeaponDef) -> void:
	pass
