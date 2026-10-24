# combat_stats.gd (autoload godot 4.6.3)
extends Node

@export var dps_tau_sec: float = 3.0
@export var damage_taken_tau_sec: float = 4.0
@export var kill_tau_sec: float = 5.0
## Active-wave seconds retained for the next Campaign opening's adaptive inputs.
@export_range(0.1, 30.0, 0.1) var opening_performance_window_sec: float = 5.0
var _ema_dps: float = 0.0
var _ema_damage_taken: float = 0.0
var _ema_enemy_kills_per_sec: float = 0.0
var _ema_enemy_kill_pressure_per_sec: float = 0.0
var _frame_damage: float = 0.0
var _frame_damage_taken: float = 0.0
var _frame_enemy_kills: float = 0.0
var _frame_enemy_kill_pressure: float = 0.0
var _wave_performance_active: bool = false
var _wave_performance_elapsed_sec: float = 0.0
var _wave_performance_buckets: Array[Dictionary] = []

# optional wire these later
var _evasion_est: float = 0.0    # 0..1
var _aoe_factor: float = 0.0     # 0..1-ish
var _sustain_rating: float = 0.0 # 0..1-ish

func report_damage(amount: float) -> void:
	_frame_damage += amount
	_record_wave_performance("damage", maxf(amount, 0.0))

func report_damage_taken(amount: float) -> void:
	_frame_damage_taken += max(amount, 0.0)
	_record_wave_performance("damage_taken", maxf(amount, 0.0))

func report_enemy_kill(threat_cost: int) -> void:
	_frame_enemy_kills += 1.0
	_frame_enemy_kill_pressure += max(threat_cost, 1)
	_record_wave_performance("enemy_kills", 1.0)

## Record opening adaptation separately from the live EMAs used by pressure.
func begin_wave_performance_window() -> void:
	cancel_wave_performance_window()
	_wave_performance_active = true

func cancel_wave_performance_window() -> void:
	_wave_performance_active = false
	_wave_performance_elapsed_sec = 0.0
	_wave_performance_buckets.clear()

func _record_wave_performance(metric: String, amount: float) -> void:
	if not _wave_performance_active or amount <= 0.0 or get_tree().paused:
		return
	_prune_wave_performance()
	if _wave_performance_buckets.is_empty() or float(_wave_performance_buckets.back()["time_sec"]) != _wave_performance_elapsed_sec:
		_wave_performance_buckets.append({"time_sec": _wave_performance_elapsed_sec, "damage": 0.0, "damage_taken": 0.0, "enemy_kills": 0.0})
	var bucket: Dictionary = _wave_performance_buckets.back()
	bucket[metric] = float(bucket[metric]) + amount

func _prune_wave_performance() -> void:
	var cutoff: float = _wave_performance_elapsed_sec - maxf(opening_performance_window_sec, 0.1)
	while not _wave_performance_buckets.is_empty() and float(_wave_performance_buckets[0]["time_sec"]) <= cutoff:
		_wave_performance_buckets.pop_front()

func get_wave_performance_snapshot() -> Dictionary:
	if not _wave_performance_active:
		return {}
	_prune_wave_performance()
	var duration: float = minf(_wave_performance_elapsed_sec, maxf(opening_performance_window_sec, 0.1))
	var damage: float = 0.0
	var damage_taken: float = 0.0
	var kills: float = 0.0
	for bucket: Dictionary in _wave_performance_buckets:
		damage += float(bucket["damage"])
		damage_taken += float(bucket["damage_taken"])
		kills += float(bucket["enemy_kills"])
	var pps: float = 0.0
	var incoming: float = 0.0
	var kill_rate: float = 0.0
	if duration > 0.0:
		pps = damage / duration * (1.0 + _evasion_est) + 0.3 * _aoe_factor + 0.3 * _sustain_rating
		incoming = damage_taken / duration
		kill_rate = kills / duration
	return {"pps": pps, "incoming_damage_per_sec": incoming, "kill_rate": kill_rate, "duration_sec": duration}

## Reports enter buckets immediately, so the closing hit need not wait for _process.
func capture_wave_performance_window() -> Dictionary:
	var snapshot: Dictionary = get_wave_performance_snapshot()
	cancel_wave_performance_window()
	return snapshot

func reset_run_metrics() -> void:
	cancel_wave_performance_window()
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
	if _wave_performance_active and not get_tree().paused:
		_wave_performance_elapsed_sec += maxf(delta, 0.0)
		_prune_wave_performance()
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
