# scripts/weapons/turret_assembly.gd
extends Node3D
class_name TurretAssembly

@export var mount_index: int = 0
@export var team_id: int = 0
@export var controller_path: NodePath
@export var default_visual: PackedScene

@onready var turret: PlayerTurret = $Turret
@onready var visual_root: Node3D = $VisualRoot

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
	if visual_root == null:
		return

	# Remove previous visuals
	for c in visual_root.get_children():
		visual_root.remove_child(c)
		c.queue_free()

	# Pick scene: weapon's visual, else default (if provided)
	var scene: PackedScene = null
	if w != null and w.visual_scene != null:
		scene = w.visual_scene
	elif default_visual != null:
		scene = default_visual

	# Instance and attach
	if scene != null:
		var inst := scene.instantiate()
		if inst is Node3D:
			visual_root.add_child(inst)
			# Ensure editable ownership in editor and reset local transform
			inst.owner = visual_root.owner
			(inst as Node3D).transform = Transform3D.IDENTITY
	
		var new_muzzle: Marker3D = _find_muzzle_in(inst)
		if new_muzzle == null:
			new_muzzle = Marker3D.new()
			new_muzzle.name = "Muzzle"
			inst.add_child(new_muzzle)
			new_muzzle.owner = visual_root.owner
		if turret != null:
			turret.muzzle = new_muzzle

		if turret != null:
			var vc: LaserTurretVisualController = _find_visual_controller(inst)
			if vc != null:
				turret.set_visual_controller(vc)

func _find_muzzle_in(root: Node) -> Marker3D:
	var direct: Marker3D = root.get_node_or_null("Muzzle") as Marker3D
	return direct

func _find_visual_controller(root: Node) -> LaserTurretVisualController:
	if root is LaserTurretVisualController:
		return root as LaserTurretVisualController
	for c in root.get_children():
		var got: LaserTurretVisualController = _find_visual_controller(c)
		if got != null:
			return got
	return null
