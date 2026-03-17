# combat_stats.gd (autoload godot 4.5)
extends Node

@export var dps_tau_sec: float = 3.0
@export var damage_taken_tau_sec: float = 4.0
@export var kill_tau_sec: float = 5.0
var _ema_dps: float = 0.0
var _ema_damage_taken: float = 0.0
var _ema_enemy_kills_per_sec: float = 0.0
var _ema_enemy_kill_pressure_per_sec: float = 0.0
var _frame_damage: float = 0.0
var _frame_damage_taken: float = 0.0
var _frame_enemy_kills: float = 0.0
var _frame_enemy_kill_pressure: float = 0.0

# optional wire these later
var _evasion_est: float = 0.0    # 0..1
var _aoe_factor: float = 0.0     # 0..1-ish
var _sustain_rating: float = 0.0 # 0..1-ish

func report_damage(amount: float) -> void:
	_frame_damage += amount

func report_damage_taken(amount: float) -> void:
	_frame_damage_taken += max(amount, 0.0)

func report_enemy_kill(threat_cost: int) -> void:
	_frame_enemy_kills += 1.0
	_frame_enemy_kill_pressure += max(threat_cost, 1)

func reset_run_metrics() -> void:
	_ema_dps = 0.0
	_ema_damage_taken = 0.0
	_ema_enemy_kills_per_sec = 0.0
	_ema_enemy_kill_pressure_per_sec = 0.0
	_frame_damage = 0.0
	_frame_damage_taken = 0.0
	_frame_enemy_kills = 0.0
	_frame_enemy_kill_pressure = 0.0
	_evasion_est = 0.0
	_aoe_factor = 0.0
	_sustain_rating = 0.0

func _process(delta: float) -> void:
	var inst_dps: float = 0.0
	var inst_damage_taken: float = 0.0
	var inst_enemy_kills: float = 0.0
	var inst_enemy_kill_pressure: float = 0.0
	if delta > 0.0:
		inst_dps = _frame_damage / delta
		inst_damage_taken = _frame_damage_taken / delta
		inst_enemy_kills = _frame_enemy_kills / delta
		inst_enemy_kill_pressure = _frame_enemy_kill_pressure / delta
	_frame_damage = 0.0
	_frame_damage_taken = 0.0
	_frame_enemy_kills = 0.0
	_frame_enemy_kill_pressure = 0.0
	_ema_dps = _apply_ema(_ema_dps, inst_dps, delta, dps_tau_sec)
	_ema_damage_taken = _apply_ema(_ema_damage_taken, inst_damage_taken, delta, damage_taken_tau_sec)
	_ema_enemy_kills_per_sec = _apply_ema(_ema_enemy_kills_per_sec, inst_enemy_kills, delta, kill_tau_sec)
	_ema_enemy_kill_pressure_per_sec = _apply_ema(_ema_enemy_kill_pressure_per_sec, inst_enemy_kill_pressure, delta, kill_tau_sec)

func get_pps() -> float:
	var pps: float = _ema_dps * (1.0 + _evasion_est) + 0.3 * _aoe_factor + 0.3 * _sustain_rating
	return pps

func get_damage_taken_per_sec() -> float:
	return _ema_damage_taken

func get_enemy_kill_rate() -> float:
	return _ema_enemy_kills_per_sec

func get_enemy_kill_pressure_rate() -> float:
	return _ema_enemy_kill_pressure_per_sec

func set_estimates(evasion_0_to_1: float, aoe_0_to_1: float, sustain_0_to_1: float) -> void:
	_evasion_est = clamp(evasion_0_to_1, 0.0, 1.0)
	_aoe_factor = clamp(aoe_0_to_1, 0.0, 1.0)
	_sustain_rating = clamp(sustain_0_to_1, 0.0, 1.0)

func _apply_ema(current: float, target: float, delta: float, tau_sec: float) -> float:
	var alpha: float = 1.0 - exp(-delta / max(tau_sec, 0.001))
	return current + alpha * (target - current)
