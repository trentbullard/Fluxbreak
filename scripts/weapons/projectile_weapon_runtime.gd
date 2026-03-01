# scripts/weapons/projectile_weapon_runtime.gd (godot 4.5)
extends WeaponRuntime
class_name ProjectileWeaponRuntime

enum ShotResult { MISS, GRAZE, HIT, CRIT }

func physics_process(delta: float) -> void:
	if turret == null or weapon == null:
		return

	var controller: TurretController = turret.get_controller()
	if controller == null:
		return

	_cooldown -= delta
	if turret.visual_controller != null and turret.eff_fire_rate > 0.0:
		var t_charge: float = 1.0 - clamp(_cooldown / turret.eff_fire_rate, 0.0, 1.0)
		turret.visual_controller.set_charge(t_charge)

	if _cooldown > 0.0:
		return

	var target: Node3D = controller.get_assigned_target(turret, turret.team_id)
	if target == null:
		return

	_fire_at_with_roll(target)
	_cooldown = max(0.01, turret.eff_fire_rate)

func _effective_accuracy_vs(target: Node3D) -> float:
	if weapon == null or turret == null:
		return 0.0

	var evasion: float = 0.0
	if target.has_method("get_evasion"):
		evasion = float(target.call("get_evasion"))

	var dist: float = turret.global_position.distance_to(target.global_position)
	var base_range: float = max(1.0, turret.eff_base_range)
	var range_factor: float = clamp(dist / base_range, 0.0, 1.0)
	var acc_base: float = max(turret.eff_base_accuracy + turret.systems_bonus + turret.eff_systems_bonus_add, 0.0)
	var acc_range_scaled: float = acc_base * lerp(1.0, 1.0 - turret.eff_range_falloff, range_factor)
	return clamp(acc_range_scaled - evasion, 0.0, 1.0)

func _fire_at_with_roll(target: Node3D) -> void:
	if weapon == null or weapon.projectile_scene == null or turret == null:
		return
	if not target.visible:
		return

	var muzzle: Marker3D = turret.muzzle
	if muzzle == null:
		return

	var dir: Vector3 = (target.global_position - muzzle.global_position).normalized()
	if turret.eff_projectile_spread_deg > 0.0:
		dir = _apply_spread(dir, turret.eff_projectile_spread_deg)
	var aim_basis: Basis = Basis.looking_at(dir, Vector3.UP)

	var hit_chance: float = _effective_accuracy_vs(target)
	var outcome: int = _resolve_shot(hit_chance)
	var dmg_min: float = minf(turret.eff_damage_min, turret.eff_damage_max)
	var dmg_max: float = maxf(turret.eff_damage_min, turret.eff_damage_max)
	var dmg: float = randf_range(dmg_min, dmg_max)

	var projectile: Projectile = weapon.projectile_scene.instantiate() as Projectile
	if projectile == null:
		return

	projectile.global_transform = Transform3D(aim_basis, muzzle.global_position)
	if turret.eff_projectile_speed > 0.0:
		projectile.speed = turret.eff_projectile_speed
	if turret.eff_projectile_life > 0.0:
		projectile.max_lifetime = turret.eff_projectile_life
	projectile.configure_shot(turret, target, outcome, dmg, turret.eff_graze_mult, turret.eff_crit_mult, weapon.status_effects, true)
	turret.get_tree().current_scene.add_child(projectile)

	if turret.shot_sound != null:
		turret.shot_sound.pitch_scale = randf_range(0.80, 1.20)
		turret.shot_sound.play()

	if turret.visual_controller != null:
		turret.visual_controller.reset_after_shot()

func _resolve_shot(hit_chance: float) -> int:
	if turret == null:
		return ShotResult.MISS

	var hc: float = clamp(hit_chance, 0.0, 1.0)
	var cc: float = clamp(turret.eff_crit_chance, 0.0, 1.0)
	var gh: float = clamp(turret.eff_graze_on_hit, 0.0, 1.0)
	var gm: float = clamp(turret.eff_graze_on_miss, 0.0, 1.0)

	var r1: float = randf()
	if r1 <= hc:
		var r2: float = randf()
		if r2 <= cc:
			return ShotResult.CRIT
		if r2 <= cc + max(0.0, 1.0 - cc) * gh:
			return ShotResult.GRAZE
		return ShotResult.HIT

	var r3: float = randf()
	if r3 <= gm:
		return ShotResult.GRAZE
	return ShotResult.MISS

func _apply_spread(dir: Vector3, spread_deg: float) -> Vector3:
	var angle_rad: float = deg_to_rad(spread_deg)
	var up_vec: Vector3 = Vector3.UP
	if abs(dir.dot(Vector3.UP)) > 0.99:
		up_vec = Vector3.RIGHT
	var tangent: Vector3 = dir.cross(up_vec).normalized()
	var bitangent: Vector3 = dir.cross(tangent).normalized()
	var u: float = randf()
	var v: float = randf()
	var theta: float = 2.0 * PI * u
	var radius: float = angle_rad * sqrt(v)
	var offset: Vector3 = (tangent * cos(theta) + bitangent * sin(theta)) * tan(radius)
	return (dir + offset).normalized()
