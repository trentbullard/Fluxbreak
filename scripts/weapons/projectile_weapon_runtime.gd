# scripts/weapons/projectile_weapon_runtime.gd (godot 4.5)
extends WeaponRuntime
class_name ProjectileWeaponRuntime

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
	return WeaponCombatResolver.compute_effective_accuracy_vs_target(turret, target)

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
	var combat_stat_context: CombatStatContext = turret.build_combat_stat_context(target)
	projectile.configure_shot(turret, target, outcome, dmg, turret.eff_graze_mult, turret.eff_crit_mult, weapon.status_effects, true, combat_stat_context)
	turret.get_tree().current_scene.add_child(projectile)

	if turret.shot_sound != null:
		turret.shot_sound.pitch_scale = randf_range(0.80, 1.20)
		turret.shot_sound.play()

	if turret.visual_controller != null:
		turret.visual_controller.reset_after_shot()

func _resolve_shot(hit_chance: float) -> int:
	return WeaponCombatResolver.resolve_shot_for_turret(turret, hit_chance)

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
