extends RefCounted
class_name WeaponCombatResolver

enum ShotResult { MISS, GRAZE, HIT, CRIT }

static func compute_effective_accuracy_vs_target(turret: PlayerTurret, target: Node3D) -> float:
	if turret == null or target == null:
		return 0.0

	var evasion: float = 0.0
	if target.has_method("get_evasion"):
		evasion = float(target.call("get_evasion"))

	var dist_sq: float = turret.global_position.distance_squared_to(target.global_position)
	var base_range: float = max(1.0, turret.eff_base_range)
	var range_factor: float = clamp(sqrt(dist_sq) / base_range, 0.0, 1.0)
	var acc_base: float = max(turret.eff_base_accuracy + turret.systems_bonus + turret.eff_systems_bonus_add, 0.0)
	var acc_range_scaled: float = acc_base * lerp(1.0, 1.0 - turret.eff_range_falloff, range_factor)
	return clamp(acc_range_scaled - evasion, 0.0, 1.0)

static func resolve_shot_for_turret(turret: PlayerTurret, hit_chance: float) -> int:
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

static func apply_shot_to_target(source: Object, target: Object, outcome: int, rolled_damage: float, graze_mult: float, crit_mult: float, effects: Array[StatusEffectDef], from_player: bool) -> float:
	if target == null:
		return 0.0

	var valid_source: Object = null
	if source != null and is_instance_valid(source):
		valid_source = source

	var fx_pos: Vector3 = Vector3.ZERO
	if target is Node3D:
		fx_pos = (target as Node3D).global_position
	elif valid_source is Node3D:
		fx_pos = (valid_source as Node3D).global_position

	var damage: float = 0.0
	match outcome:
		ShotResult.CRIT:
			EffectsBus.show_float(fx_pos, "CRIT", Color.GREEN)
			damage = max(0.0, rolled_damage) * crit_mult
		ShotResult.HIT:
			damage = max(0.0, rolled_damage)
		ShotResult.GRAZE:
			EffectsBus.show_float(fx_pos, "GRAZE", Color(0.8, 0.8, 0.8))
			damage = max(0.0, rolled_damage) * graze_mult
		_:
			EffectsBus.show_float(fx_pos, "MISS", Color(1.0, 0.569, 0.271, 1.0))
			damage = 0.0

	if damage > 0.0 and target.has_method("apply_damage"):
		target.call("apply_damage", damage)
		if from_player:
			CombatStats.report_damage(damage)

	if not effects.is_empty() and target.has_method("apply_status_effect"):
		for effect_def in effects:
			if effect_def == null:
				continue
			var chance: float = 0.0
			match outcome:
				ShotResult.CRIT:
					chance = effect_def.chance_on_crit
				ShotResult.HIT:
					chance = effect_def.chance_on_hit
				ShotResult.GRAZE:
					chance = effect_def.chance_on_graze
				_:
					chance = 0.0
			if randf() <= chance:
				target.call("apply_status_effect", effect_def, valid_source)

	return damage
