extends Node

const SCALING_DEF: EnemyCombatScalingDef = preload("res://content/data/scaling/enemy_combat_scaling_default.tres")
const ENEMY_PATHS: Array[String] = [
	"res://content/data/enemies/machine_drone_mk1.tres",
	"res://content/data/enemies/merc_corvette_mk1.tres",
	"res://content/data/enemies/bug_sporeling_mk1.tres",
	"res://content/data/enemies/grey_probe_mk1.tres",
]

var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Enemy Reward Validation":
		push_error("Enemy reward checks require their save-isolated validation wrapper.")
		get_tree().quit(2)
		return
	_check_configuration()
	_check_production_rewards()
	_check_variance_and_edge_cases()
	_check_target_and_collection_separation()
	print("ENEMY_REWARD_SCALING_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _check_configuration() -> void:
	_check(is_equal_approx(SCALING_DEF.nanobot_base_strength, 0.20), "Campaign reward strength uses the reduced authored value.")
	_check(is_equal_approx(EnemyCombatScalingDef.new().nanobot_base_strength, 0.20), "Fallback definitions use the same reward strength.")
	_check(is_equal_approx(SCALING_DEF.nanobot_variance_pct, 0.15), "Authored fifteen-percent drop variance is unchanged.")
	_check(is_equal_approx(SCALING_DEF.nanobot_min_multiplier, 1.0), "The base reward floor remains unchanged.")
	_check(is_equal_approx(RunState.enemy_nanobots_per_bounty_scrap, 100.0), "Base nanobots per bounty scrap remain one hundred.")
	_check(is_equal_approx(RunState.enemy_nanobot_variance_pct, 0.15), "Unscaled drop variance remains unchanged.")
	_check(is_equal_approx(RunState.weapon_price_multiplier, 1.5), "Weapon purchase price growth is unchanged.")

func _check_production_rewards() -> void:
	var def: EnemyCombatScalingDef = SCALING_DEF.duplicate(true) as EnemyCombatScalingDef
	def.nanobot_variance_pct = 0.0
	var director: EnemyCombatScalingDirector = EnemyCombatScalingDirector.new()
	director.scaling_def = def
	var opening: EnemyCombatScalingSnapshot = director.build_snapshot(1, 0.0)
	var first_cap: EnemyCombatScalingSnapshot = director.build_snapshot(29, 1680.0)
	director.set_carried_baseline_from_snapshot(first_cap)
	var second_cap: EnemyCombatScalingSnapshot = director.build_snapshot(29, 1680.0)
	var snapshots: Array[EnemyCombatScalingSnapshot] = [opening, first_cap, second_cap]
	var expected_intensities: Array[float] = [0.0, 6.0, 12.0]
	var expected_rewards: Array[int] = [100, 220, 340]
	var one_bounty: EnemyDef = EnemyDef.new()
	one_bounty.bounty_scrap = 1
	for index: int in range(snapshots.size()):
		var snapshot: EnemyCombatScalingSnapshot = snapshots[index]
		_check(is_equal_approx(snapshot.intensity, expected_intensities[index]), "The production combat curve preserves intensity %.0f." % expected_intensities[index])
		_check(RunState.calc_enemy_nanobots(one_bounty, snapshot) == expected_rewards[index], "The real reward path pays %d per bounty at intensity %.0f." % [expected_rewards[index], snapshot.intensity])
		for path: String in ENEMY_PATHS:
			var enemy: EnemyDef = load(path) as EnemyDef
			_check(enemy != null, "Representative faction enemy loads: %s" % path)
			if enemy != null:
				_check(RunState.calc_enemy_nanobots(enemy, snapshot) == enemy.bounty_scrap * expected_rewards[index], "Every faction uses the same reduced scaling without changing its authored bounty.")
		print("REWARD_SAMPLE intensity=%.0f nanobots_per_bounty=%d multiplier=%.2f" % [snapshot.intensity, RunState.calc_enemy_nanobots(one_bounty, snapshot), snapshot.nanobot_multiplier])
	_check(is_equal_approx(first_cap.hull_multiplier, 5.2) and is_equal_approx(first_cap.shield_multiplier, 4.9), "Stage-one hull and shield scaling remain unchanged.")
	_check(is_equal_approx(first_cap.damage_multiplier, 4.3) and is_equal_approx(first_cap.fire_rate_multiplier, 0.55), "Stage-one damage and fire-rate scaling remain unchanged.")
	_check(is_equal_approx(second_cap.hull_multiplier, 9.4) and is_equal_approx(second_cap.damage_multiplier, 7.6), "Stage-two combat strength remains independent of reward tuning.")
	_check(is_equal_approx(first_cap.nanobot_variance_pct, 0.0), "Deterministic fixtures disable variance on their private definition only.")
	_check(is_equal_approx(SCALING_DEF.nanobot_variance_pct, 0.15), "Checks never mutate the production resource.")
	director.free()

func _check_variance_and_edge_cases() -> void:
	var enemy: EnemyDef = EnemyDef.new()
	enemy.bounty_scrap = 1
	var snapshot: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
	snapshot.nanobot_multiplier = 2.2
	snapshot.nanobot_variance_pct = 0.15
	seed(1719)
	var seen: Dictionary = {}
	for sample: int in range(128):
		var reward: int = RunState.calc_enemy_nanobots(enemy, snapshot)
		_check(reward >= 187 and reward <= 253, "Real late-stage drops retain their authored variance bounds.")
		seen[reward] = true
	_check(seen.size() > 1, "Normal drops still vary instead of becoming a fixed payout.")
	enemy.bounty_scrap = 0
	_check(RunState.calc_enemy_nanobots(enemy, snapshot) == 0, "A zero-bounty enemy cannot acquire reward from scaling.")
	enemy.bounty_scrap = -1
	_check(RunState.calc_enemy_nanobots(enemy, snapshot) == 0, "Negative authored bounty remains clamped to zero.")
	enemy.bounty_scrap = 1
	var previous_variance: float = RunState.enemy_nanobot_variance_pct
	RunState.enemy_nanobot_variance_pct = 0.0
	_check(RunState.calc_enemy_nanobots(enemy) == 100, "Enemies without a scaling context retain their base reward.")
	RunState.enemy_nanobot_variance_pct = previous_variance
	_check(RunState.calc_enemy_nanobots(null, snapshot) == 200, "The missing-definition fallback remains unchanged.")

func _check_target_and_collection_separation() -> void:
	var asteroid: TargetDef = load("res://content/data/targets/asteroid_small.tres") as TargetDef
	var wreck: TargetDef = load("res://content/data/targets/wreck_medium.tres") as TargetDef
	_check(RunState.calc_target_nanobots(asteroid) == 1000, "Asteroid rewards remain independent of combat scaling.")
	_check(RunState.calc_target_nanobots(wreck) == 3000, "Wreck rewards remain independent of combat scaling.")
	var ship: Ship = Ship.new()
	ship.eff_nanobot_gain_mult = 1.25
	ship.collect_nanobots(220)
	_check(ship.get_nanobots() == 275, "The real pickup path still applies player collection multipliers.")
	ship.free()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
