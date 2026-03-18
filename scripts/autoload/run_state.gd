# scripts/autoload/run_state.gd (autoload)
extends Node

signal score_changed(total: int, delta: int, reason: String)
signal nanobots_updated(amount: int) # called by ship when nanobots collected
signal nanobots_spent(amount: int) # called by pause menu
signal weapon_purchased_count_changed(count: int)
signal upgrade_purchased(upgrade_id: String)

# --- Weapon Pricing ---
var weapons_purchased: int = 0
var weapon_price_multiplier: float = 1.5  # Each weapon costs 1.5x more than previous

# --- Nanobots ---
var enemy_nanobots_per_bounty_scrap: float = 100.0
var enemy_nanobot_variance_pct: float = 0.15

var _wave_index: int = 0
var _enemy_budget: int = 0
var _target_budget: int = 0

# static nanobot drops for non-enemy targets (by size_band)
var target_nanobot_drop_by_size: Dictionary = {
	1: 1000,  # e.g. small asteroids
	2: 3000, # e.g. medium wrecks
}

enum State { IN_WAVE, DOWNTIME }

var run_state: State = State.DOWNTIME
var run_score: int = 0
var _purchased_upgrade_ids: Array[String] = []

func start_run() -> void:
	reset_score()
	reset_weapons_purchased()
	reset_upgrades_purchased()
	if CombatStats != null:
		CombatStats.reset_run_metrics()


func reset_weapons_purchased() -> void:
	weapons_purchased = 0
	weapon_purchased_count_changed.emit(weapons_purchased)


func record_weapon_purchase() -> void:
	weapons_purchased += 1
	weapon_purchased_count_changed.emit(weapons_purchased)


func get_weapon_cost(base_cost: int) -> int:
	# Progressive pricing: base_cost * (multiplier ^ weapons_purchased)
	return int(round(base_cost * pow(weapon_price_multiplier, weapons_purchased)))

func record_upgrade_purchase(upgrade_id: String) -> void:
	var id: String = upgrade_id.strip_edges().to_lower()
	if id == "":
		return
	_purchased_upgrade_ids.append(id)
	upgrade_purchased.emit(id)

func reset_upgrades_purchased() -> void:
	_purchased_upgrade_ids.clear()

func get_purchased_upgrade_ids() -> Array[String]:
	return _purchased_upgrade_ids.duplicate()

func get_wave_index() -> int:
	return _wave_index

func set_state(state: State) -> void:
	run_state = state

func reset_score() -> void:
	run_score = 0
	score_changed.emit(run_score, 0, "reset")

func add_score(amount: int, reason: String = "") -> void:
	if amount == 0:
		return
	run_score += amount
	score_changed.emit(run_score, amount, reason)

func set_wave_context(wave_index: int, enemy_point_budget: int, target_point_budget: int) -> void:
	_wave_index = max(wave_index, 0)
	_enemy_budget = max(enemy_point_budget, 0)
	_target_budget = max(target_point_budget, 0)

func calc_enemy_nanobots(def: EnemyDef, combat_scaling: EnemyCombatScalingSnapshot = null) -> int:
	if def == null:
		return int(round(enemy_nanobots_per_bounty_scrap * 2.0))
	var base_enemy_nanobots: float = float(max(def.bounty_scrap, 0)) * enemy_nanobots_per_bounty_scrap
	var nanobot_multiplier: float = combat_scaling.nanobot_multiplier if combat_scaling != null else 1.0
	var raw: float = base_enemy_nanobots * max(nanobot_multiplier, 0.0)
	var variance: float = combat_scaling.nanobot_variance_pct if combat_scaling != null else enemy_nanobot_variance_pct
	variance = clamp(variance, 0.0, 1.0)
	if variance > 0.0:
		var spread: float = raw * variance
		raw = raw + randf_range(-spread, spread)
	return int(round(raw))

func calc_target_nanobots(def: TargetDef) -> int:
	if def == null:
		return int(target_nanobot_drop_by_size.get(1, 0))
	var size: int = max(def.size_band, 1)
	if target_nanobot_drop_by_size.has(size):
		return int(target_nanobot_drop_by_size[size])

	# Fall back to the largest defined size band if we don't have an exact match yet.
	var max_known: int = 0
	for s in target_nanobot_drop_by_size.keys():
		max_known = max(max_known, int(s))
	if max_known > 0:
		return int(target_nanobot_drop_by_size[max_known])

	return 0
