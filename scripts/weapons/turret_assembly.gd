# scripts/weapons/turret_assembly.gd
extends Node3D
class_name TurretAssembly

@export var mount_index: int = 0
@export var team_id: int = 0
@export var controller_path: NodePath
@export var default_visual: PackedScene

@onready var turret: PlayerTurret = $Turret
@onready var visual_root: Node3D = $VisualRoot
@onready var beam_effect_root: Node3D = $BeamEffectRoot
@onready var muzzle_socket: Marker3D = $MuzzleSocket

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
	turret.swap_weapon(w, keep_cooldown, team_id)
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
	if visual_root == null or beam_effect_root == null:
		return

	_clear_children(visual_root)
	_clear_children(beam_effect_root)
	if turret != null:
		turret.muzzle = muzzle_socket
		turret.set_visual_controller(null)

	# Pick scene: weapon's visual, else default (if provided)
	var scene: PackedScene = null
	if w != null and w.visual_scene != null:
		scene = w.visual_scene
	elif default_visual != null:
		scene = default_visual

	# Instance and attach
	if scene != null:
		var inst: Node = scene.instantiate()
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
			turret.set_visual_controller(vc)

	var beam_scene: PackedScene = _get_beam_visual_scene(w)
	if beam_scene != null:
		var beam_inst: Node = beam_scene.instantiate()
		if beam_inst is Node3D:
			beam_effect_root.add_child(beam_inst)
			beam_inst.owner = beam_effect_root.owner
			(beam_inst as Node3D).transform = Transform3D.IDENTITY
			if beam_inst.has_method("bind_turret") and turret != null:
				beam_inst.call("bind_turret", turret)

func _clear_children(root: Node) -> void:
	for child: Node in root.get_children():
		root.remove_child(child)
		child.queue_free()

func _get_beam_visual_scene(w: WeaponDef) -> PackedScene:
	if not (w is BeamWeaponDef):
		return null
	var beam_weapon: BeamWeaponDef = w as BeamWeaponDef
	if beam_weapon == null:
		return null
	return beam_weapon.beam_visual_scene

func _find_muzzle_in(root: Node) -> Marker3D:
	if root is Marker3D and root.name == "Muzzle":
		return root as Marker3D
	for child: Node in root.get_children():
		var nested: Marker3D = _find_muzzle_in(child)
		if nested != null:
			return nested
	return null

func _find_visual_controller(root: Node) -> LaserTurretVisualController:
	if root is LaserTurretVisualController:
		return root as LaserTurretVisualController
	for c in root.get_children():
		var got: LaserTurretVisualController = _find_visual_controller(c)
		if got != null:
			return got
	return null
