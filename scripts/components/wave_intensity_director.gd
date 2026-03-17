extends Node
class_name WaveIntensityDirector

@export_range(0.50, 1.50, 0.01) var opening_enemy_scale_min: float = 0.92
@export_range(0.50, 1.50, 0.01) var opening_enemy_scale_max: float = 1.12
@export var kill_rate_reference: float = 0.65
@export var incoming_damage_reference: float = 18.0
@export var wave_spike_cooldown_sec: float = 18.0
@export var min_wave_time_for_spike: float = 10.0
@export var steady_reinforcement_budget: int = 1
@export var spike_reinforcement_budget: int = 4
@export_range(0.0, 1.0, 0.01) var respite_damage_threshold_scale: float = 0.60
@export_range(0.0, 1.0, 0.01) var respite_alive_ratio: float = 0.80
@export_range(0.0, 1.0, 0.01) var steady_alive_ratio_max: float = 0.70
@export_range(0.0, 1.0, 0.01) var spike_alive_ratio_max: float = 0.55

var _wave_elapsed_sec: float = 0.0
var _time_since_last_spike_sec: float = 9999.0
var _last_pressure_state: String = "steady"
var _last_opening_scale: float = 1.0

func begin_wave() -> void:
	_wave_elapsed_sec = 0.0
	_time_since_last_spike_sec = wave_spike_cooldown_sec
	_last_pressure_state = "opening"
	_last_opening_scale = 1.0

func tick(delta: float, in_wave: bool) -> void:
	if in_wave:
		_wave_elapsed_sec += max(delta, 0.0)
		_time_since_last_spike_sec += max(delta, 0.0)
	else:
		_last_pressure_state = "downtime"

func get_opening_adjustment(enemy_points: int, kill_rate: float, incoming_damage: float) -> Dictionary:
	var kill_delta: float = 0.0
	if kill_rate_reference > 0.0:
		kill_delta = clamp((kill_rate / kill_rate_reference) - 1.0, -1.0, 1.0)
	var damage_relief: float = 0.0
	if incoming_damage_reference > 0.0:
		damage_relief = clamp(incoming_damage / incoming_damage_reference, 0.0, 1.0)
	var scale: float = 1.0 + kill_delta * 0.08 - damage_relief * 0.10
	scale = clamp(scale, opening_enemy_scale_min, opening_enemy_scale_max)
	_last_opening_scale = scale
	return {
		"enemy_points": max(int(round(float(max(enemy_points, 1)) * scale)), 1),
		"scale": scale,
	}

func build_pressure_plan(
	wave_index: int,
	alive_enemies: int,
	enemy_density_reference: float,
	kill_rate: float,
	incoming_damage: float,
	card: WaveCard
) -> Dictionary:
	var alive_ratio: float = 0.0
	if enemy_density_reference > 0.0:
		alive_ratio = float(max(alive_enemies, 0)) / enemy_density_reference

	var steady_budget: int = steady_reinforcement_budget
	var spike_budget: int = spike_reinforcement_budget + int(wave_index / 5)
	if card != null:
		steady_budget = max(int(round(float(card.pressure_enemy_point_budget) * 0.5)), 0)
		spike_budget = max(card.pressure_enemy_point_budget, spike_budget)

	var damage_threshold: float = incoming_damage_reference * respite_damage_threshold_scale
	if incoming_damage >= damage_threshold or alive_ratio >= respite_alive_ratio:
		_last_pressure_state = "respite"
		return {
			"state": _last_pressure_state,
			"enemy_points": 0,
			"target_points": 0,
			"alive_ratio": alive_ratio,
		}

	if card != null \
	and card.allow_pressure_spikes \
	and _wave_elapsed_sec >= min_wave_time_for_spike \
	and _time_since_last_spike_sec >= wave_spike_cooldown_sec \
	and kill_rate >= kill_rate_reference \
	and alive_ratio <= spike_alive_ratio_max:
		_time_since_last_spike_sec = 0.0
		_last_pressure_state = "spike"
		return {
			"state": _last_pressure_state,
			"enemy_points": max(spike_budget, 0),
			"target_points": max(card.pressure_target_point_budget, 0),
			"alive_ratio": alive_ratio,
		}

	if alive_ratio <= steady_alive_ratio_max and steady_budget > 0:
		_last_pressure_state = "steady"
		return {
			"state": _last_pressure_state,
			"enemy_points": steady_budget,
			"target_points": 0,
			"alive_ratio": alive_ratio,
		}

	_last_pressure_state = "hold"
	return {
		"state": _last_pressure_state,
		"enemy_points": 0,
		"target_points": 0,
		"alive_ratio": alive_ratio,
	}

func get_downtime_target_budget(next_wave_index: int, alive_targets: int, card: WaveCard) -> int:
	if alive_targets > 0:
		return 0
	if card == null:
		return 0
	var budget: int = max(card.downtime_target_point_budget, 0)
	if next_wave_index >= 6:
		budget += 1
	if next_wave_index >= 12:
		budget += 1
	return budget

func get_last_pressure_state() -> String:
	return _last_pressure_state

func get_last_opening_scale() -> float:
	return _last_opening_scale
