extends Node

const ENEMY_ROOT: String = "res://content/data/enemies/"
const SCALING: EnemyCombatScalingDef = preload("res://content/data/scaling/enemy_combat_scaling_default.tres")
const REGULARS: Dictionary = {
	&"mercs": ["merc_corvette_mk1", "merc_frigate_mk1", "merc_destroyer_mk1", "merc_cruiser_mk1", "merc_carrier_mk1"],
	&"bugs": ["bug_sporeling_mk1", "bug_carapace_mk1", "bug_broodmother_mk1", "bug_devourer_mk1", "bug_hive_queen_mk1"],
	&"greys": ["grey_probe_mk1", "grey_seeker_mk1", "grey_vessel_mk1", "grey_harbinger_mk1", "grey_mothership_mk1"],
}
const BOSSES: Dictionary = {
	&"mercs": ["merc_contract_enforcer_mk1", "merc_vanguard_flagship_mk1"],
	&"bugs": ["bug_nestbreaker_matron_mk1", "bug_first_queen_mk1"],
	&"greys": ["grey_witness_mk1", "grey_veiled_mind_mk1"],
}

var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Durability Validation":
		push_error("Durability checks require the isolated Fluxbreak Durability Validation project.")
		get_tree().quit(2)
		return
	GameFlow.abandon_run()
	var director: EnemyCombatScalingDirector = EnemyCombatScalingDirector.new()
	director.scaling_def = SCALING
	var early: EnemyCombatScalingSnapshot = director.build_snapshot(1, 0.0)
	var late: EnemyCombatScalingSnapshot = director.build_snapshot(29, 1680.0)
	director.set_carried_baseline_from_snapshot(late)
	var second_sector: EnemyCombatScalingSnapshot = director.build_snapshot(29, 1680.0)
	_check(second_sector.intensity > late.intensity and late.intensity > early.intensity, "Combat progression and stage carryover remain active.")
	for faction_id: StringName in REGULARS:
		var entries: Array = REGULARS[faction_id]
		var prior_pool: float = 0.0
		var prior_speed: float = INF
		for entry: String in entries:
			var definition: EnemyDef = _load_enemy(entry)
			if definition == null:
				continue
			_check(definition.threat_cost > 0 and definition.get_faction_id() == faction_id, "%s has a positive cost and correct faction." % entry)
			var pool: float = definition.max_hull + definition.max_shield
			_check(pool > prior_pool, "%s advances the roster's total durability." % entry)
			prior_pool = pool
			var per_point: float = pool / float(maxi(definition.threat_cost, 1))
			_check(per_point >= 30.0 and per_point <= 80.0, "%s stays in a broad durability-per-point band without requiring identical ships." % entry)
			for scaling: EnemyCombatScalingSnapshot in [early, late, second_sector]:
				_check_resolved_theme(definition, faction_id, scaling)
			if definition is BugEnemyDef:
				var bug: BugEnemyDef = definition as BugEnemyDef
				_check(bug.behavior != null and bug.behavior.max_speed < prior_speed, "%s trades ordinary movement speed for heavier hull." % entry)
				prior_speed = bug.behavior.max_speed
		_test_role_comparisons()
	_test_boss_baselines(early, late, second_sector)
	_test_damage_and_regeneration(second_sector)
	_print_reference_estimates(early, late, second_sector)
	director.free()
	print("FACTION_DURABILITY_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _check_resolved_theme(definition: EnemyDef, faction_id: StringName, scaling: EnemyCombatScalingSnapshot) -> void:
	var context: EnemySpawnContext = EnemySpawnContext.from_enemy_def(definition)
	context.enemy_combat_scaling = scaling
	var stats: EnemyStatSnapshot = EnemyStatResolver.resolve(definition, context)
	_check(stats.max_hull > 0.0 and is_finite(stats.max_hull + stats.max_shield + stats.shield_regen), "%s resolves finite live defenses at intensity %.2f." % [definition.id, scaling.intensity])
	_check(is_equal_approx(stats.max_hull / definition.max_hull, scaling.hull_multiplier), "%s receives shared hull progression without faction-specific rescaling." % definition.id)
	match faction_id:
		&"mercs":
			_check(stats.max_hull > stats.max_shield * 3.0 and stats.shield_regen > 0.0, "%s retains hull-led defenses and modest shield regeneration." % definition.id)
		&"bugs":
			_check(is_zero_approx(stats.max_shield) and is_zero_approx(stats.shield_regen), "%s never acquires shields or regeneration through progression." % definition.id)
		&"greys":
			_check(stats.max_shield > stats.max_hull * 2.0 and stats.shield_regen > 0.0, "%s retains shield-led defenses and regeneration." % definition.id)
			_check(stats.evasion > definition.evasion or is_zero_approx(scaling.intensity), "%s receives the shared evasion bonus once." % definition.id)

func _test_role_comparisons() -> void:
	var mercs: Array = REGULARS[&"mercs"]
	var bugs: Array = REGULARS[&"bugs"]
	var greys: Array = REGULARS[&"greys"]
	for index: int in range(mercs.size()):
		var merc: EnemyDef = _load_enemy(mercs[index])
		var bug: EnemyDef = _load_enemy(bugs[index])
		var grey: EnemyDef = _load_enemy(greys[index])
		if merc == null or bug == null or grey == null:
			continue
		var merc_pool_per_point: float = (merc.max_hull + merc.max_shield) / float(merc.threat_cost)
		_check(merc_pool_per_point > bug.max_hull / float(bug.threat_cost), "%s has greater burst durability per point than its Bug roster counterpart." % merc.id)
		_check(merc_pool_per_point > (grey.max_hull + grey.max_shield) / float(grey.threat_cost), "%s has greater burst durability per point than its Grey roster counterpart." % merc.id)
		_check(grey.shield_regen > merc.shield_regen, "%s trades raw durability for stronger regeneration than its Merc counterpart." % grey.id)
	var devourer: BugEnemyDef = _load_enemy("bug_devourer_mk1") as BugEnemyDef
	_check(devourer != null and devourer.behavior.charge_speed > devourer.behavior.max_speed * 2.0, "Slower Devourer transit preserves its fast committed charge.")

func _test_boss_baselines(early: EnemyCombatScalingSnapshot, late: EnemyCombatScalingSnapshot, second_sector: EnemyCombatScalingSnapshot) -> void:
	var machine: EnemyDef = _load_enemy("machine_boss_1_mk1")
	var machine_pool: float = machine.max_hull + machine.max_shield
	for faction_id: StringName in BOSSES:
		for entry: String in BOSSES[faction_id]:
			var definition: EnemyDef = _load_enemy(entry)
			if definition == null:
				continue
			var pool: float = definition.max_hull + definition.max_shield
			_check(pool >= machine_pool * 0.9 and pool <= machine_pool * 1.35, "%s uses the Campaign boss scale rather than the short Practice scale." % entry)
			for scaling: EnemyCombatScalingSnapshot in [early, late, second_sector]:
				_check_resolved_theme(definition, faction_id, scaling)

func _test_damage_and_regeneration(scaling: EnemyCombatScalingSnapshot) -> void:
	for faction_id: StringName in REGULARS:
		var definition: EnemyDef = _load_enemy(REGULARS[faction_id][2])
		var context: EnemySpawnContext = EnemySpawnContext.from_enemy_def(definition)
		context.enemy_combat_scaling = scaling
		var stats: EnemyStatSnapshot = EnemyStatResolver.resolve(definition, context)
		var enemy: Enemy = Enemy.new()
		enemy.eff_max_hull = stats.max_hull
		enemy.eff_max_shield = stats.max_shield
		enemy.eff_shield_regen = stats.shield_regen
		enemy.hull = stats.max_hull
		enemy.shield = stats.max_shield
		var damage: float = stats.max_shield + stats.max_hull * 0.1
		enemy.apply_damage(damage)
		_check(is_zero_approx(enemy.shield) and is_equal_approx(enemy.hull, stats.max_hull * 0.9), "%s spends shields before hull under actual damage resolution." % definition.id)
		enemy._on_regen_tick()
		_check(is_equal_approx(enemy.shield, minf(stats.shield_regen, stats.max_shield)), "%s regenerates the resolved amount, including depleted Grey shields and shieldless Bugs." % definition.id)
		enemy.shield = stats.max_shield
		enemy._on_regen_tick()
		_check(is_equal_approx(enemy.shield, stats.max_shield), "%s regeneration cannot exceed shield capacity." % definition.id)
		enemy.free()

func _print_reference_estimates(early: EnemyCombatScalingSnapshot, late: EnemyCombatScalingSnapshot, second_sector: EnemyCombatScalingSnapshot) -> void:
	# A transparent comparison tool, not an assertion of measured gameplay TTK.
	# Raw incoming damage is 200/sec before evasion; allied support is excluded.
	for faction_id: StringName in REGULARS:
		for entry: String in REGULARS[faction_id]:
			var definition: EnemyDef = _load_enemy(entry)
			var times: PackedFloat32Array = PackedFloat32Array()
			for scaling: EnemyCombatScalingSnapshot in [early, late, second_sector]:
				var context: EnemySpawnContext = EnemySpawnContext.from_enemy_def(definition)
				context.enemy_combat_scaling = scaling
				var stats: EnemyStatSnapshot = EnemyStatResolver.resolve(definition, context)
				var net_dps: float = 200.0 * (1.0 - stats.evasion) - stats.shield_regen
				times.append((stats.max_hull + stats.max_shield) / maxf(net_dps, 0.01))
			print("DURABILITY_REFERENCE %s: 200 raw DPS before evasion, early/S1-late/S2-late %.2f / %.2f / %.2f seconds (analytic, not playtest)" % [entry, times[0], times[1], times[2]])

func _load_enemy(stem: String) -> EnemyDef:
	var definition: EnemyDef = load(ENEMY_ROOT + stem + ".tres") as EnemyDef
	_check(definition != null, "%s loads as an enemy definition." % stem)
	return definition

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
