# scripts/autoload/run_state.gd (autoload)
extends Node

signal score_changed(total: int, delta: int, reason: String)
signal nanobots_updated(amount: int) # called by ship when nanobots collected
signal nanobots_spent(amount: int) # called by pause menu
signal weapon_purchased_count_changed(count: int)

# --- Weapon Pricing ---
var weapons_purchased: int = 0
var weapon_price_multiplier: float = 1.5  # Each weapon costs 1.5x more than previous

# --- Nanobots ---
# base scaling
var base_drop: float = 150.0
var tier_factor: float = 50.0
var threat_factor: float = 30.0
var wave_linear: float = 1.5
var wave_quadratic: float = 0.03

# performance coupling
var pps_reference: float = 40
var pps_max_boost_pct: float = 0.35
var pps_weight: float = 0.5

# wave budget influence
var budget_enemy_norm: float = 20.0
var budget_weight: float = 0.50

# output controls
var variance_pct: float = 0.20
var elite_bonus_pct: float = 0.50

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

func start_run() -> void:
	reset_score()
	reset_weapons_purchased()


func reset_weapons_purchased() -> void:
	weapons_purchased = 0
	weapon_purchased_count_changed.emit(weapons_purchased)


func record_weapon_purchase() -> void:
	weapons_purchased += 1
	weapon_purchased_count_changed.emit(weapons_purchased)


func get_weapon_cost(base_cost: int) -> int:
	# Progressive pricing: base_cost * (multiplier ^ weapons_purchased)
	return int(round(base_cost * pow(weapon_price_multiplier, weapons_purchased)))

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

func calc_enemy_nanobots(def: EnemyDef, pps: float) -> int:
	if def == null:
		return 200
	var tier_adj: float = max(def.tier - 1, 0)
	var perf_ratio: float = 0.0
	if pps_reference > 0.0:
		perf_ratio = clamp(pps / pps_reference, 0.0, 3.0)
	var perf_multiplier: float = lerp(1.0, 1.0 + pps_max_boost_pct, clamp(perf_ratio - 1.0, 0.0, 1.0))
	perf_multiplier = lerp(1.0, perf_multiplier, clamp(pps_weight, 0.0, 1.0))
	var wave_term: float = wave_linear * _wave_index + wave_quadratic * float(_wave_index * _wave_index)
	var budget_term: float = 0.0
	if budget_enemy_norm > 0.0:
		budget_term = budget_weight * (_enemy_budget / budget_enemy_norm)
	var raw: float = (base_drop + tier_factor * tier_adj + threat_factor * float(def.threat_cost) + wave_term + budget_term)
	raw *= perf_multiplier
	var variance: float = clamp(variance_pct, 0.0, 1.0)
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
