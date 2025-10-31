# scripts/weapons/player_turret.gd (godot 4.5)
extends Node3D
class_name PlayerTurret

@export var controller_path: NodePath
@export var target_groups: Array[String] = []      # targets or player
@export var systems_bonus: float = 0.10            # upgrades add here
@export var team_id: int = 0

@export var muzzle: Marker3D
@export var shot_sound: AudioStreamPlayer3D

var _weapon: WeaponDef = null
var _cooldown := 0.0
var _controller: TurretController = null
var _detector: Area3D = null

enum ShotResult { MISS, GRAZE, HIT, CRIT }

signal weapon_changed(new_weapon: WeaponDef)

func _ready() -> void:
	_bind_controller()

func _enter_tree() -> void:
	_bind_controller()

func _exit_tree() -> void:
	if _controller != null:
		_controller.unregister_turret(self, team_id)

# --- public api ---

func apply_weapon(w: WeaponDef, team_id_val: int) -> void:
	_weapon = w
	team_id = team_id_val
	weapon_changed.emit(_weapon)

func get_weapon() -> WeaponDef:
	return _weapon

func swap_weapon(new_weapon: WeaponDef, keep_cooldown: bool = true) -> void:
	var prev_cd: float = _cooldown
	apply_weapon(new_weapon, team_id)
	_cooldown = prev_cd if keep_cooldown else 0.0

# --- firing loop ---

func _physics_process(delta: float) -> void:
	if _weapon == null or _controller == null:
		return

	_cooldown -= delta
	if _cooldown > 0.0:
		return

	var tgt: Node3D = _controller.get_assigned_target(self, team_id)
	if tgt == null:
		return
	
	_fire_at_with_roll(tgt)
	_cooldown = max(0.01, _weapon.fire_rate)

func _effective_accuracy_vs(target: Node3D) -> float:
	if _weapon == null:
		return 0.0

	var ev: float = 0.0
	if target.has_method("get_evasion"):
		ev = float(target.call("get_evasion"))

	var dist: float = global_position.distance_to(target.global_position)
	var range_factor: float = clamp(dist / _weapon.base_range, 0.0, 1.0) # 0 close -> 1 far
	var acc_base: float = clamp(_weapon.base_accuracy + systems_bonus, 0.0, 1.0)
	var acc_range_scaled: float = acc_base * lerp(1.0, 1.0 - _weapon.accuracy_range_falloff, range_factor)
	return clamp(acc_range_scaled - ev, 0.0, 1.0)

func _fire_at_with_roll(target: Node3D) -> void:
	if _weapon == null or _weapon.projectile_scene == null or not target.visible:
		return

	# Aim (still straight) -- projectile will use proximity fuse to "connect"
	var dir: Vector3 = (target.global_position - muzzle.global_position).normalized()
	var aim_basis: Basis = Basis.looking_at(dir, Vector3.UP)
	
	var hit_chance: float = _effective_accuracy_vs(target)
	var outcome: int = _resolve_shot(hit_chance)
	var dmg: float = randf_range(_weapon.damage_min, _weapon.damage_max)

	var p: Projectile = _weapon.projectile_scene.instantiate() as Projectile
	if p == null:
		return

	p.global_transform = Transform3D(aim_basis, muzzle.global_position)
	p.configure_shot(self, target, outcome, dmg, _weapon.graze_mult, _weapon.crit_mult, _weapon.status_effects, true)
	get_tree().current_scene.add_child(p)

	if shot_sound != null:
		shot_sound.pitch_scale = randf_range(0.90, 1.10)
		shot_sound.play()

func _resolve_shot(hit_chance: float) -> int:
	var hc: float = clamp(hit_chance, 0.0, 1.0)
	var cc: float = clamp(_weapon.crit_chance, 0.0, 1.0)
	var gh: float = clamp(_weapon.graze_on_hit, 0.0, 1.0)
	var gm: float = clamp(_weapon.graze_on_miss, 0.0, 1.0)

	# If it hits at all…
	var r1: float = randf()
	if r1 <= hc:
		# crit → graze-on-hit → normal
		var r2: float = randf()
		if r2 <= cc:
			return ShotResult.CRIT
		elif r2 <= cc + max(0.0, 1.0 - cc) * gh:
			return ShotResult.GRAZE
		else:
			return ShotResult.HIT
	else:
		# miss → maybe graze-on-miss
		var r3: float = randf()
		if r3 <= gm:
			return ShotResult.GRAZE
		return ShotResult.MISS

# --- private ---

func _bind_controller() -> void:
	var ctrl: TurretController = null
	
	if controller_path != NodePath():
		ctrl = get_node_or_null(controller_path) as TurretController
	
	if ctrl == null:
		var p: Node = get_parent()
		while p != null and ctrl == null:
			ctrl = p as TurretController
			p = p.get_parent()
	
	_controller = ctrl
	if _controller != null:
		_controller.register_turret(self, team_id)
		_detector = _controller.detector
