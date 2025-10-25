# combat_stats.gd (autoload godot 4.5)
extends Node

@export var dps_tau_sec: float = 3.0
var _ema_dps: float = 0.0
var _frame_damage: float = 0.0

# optional wire these later
var _evasion_est: float = 0.0    # 0..1
var _aoe_factor: float = 0.0     # 0..1-ish
var _sustain_rating: float = 0.0 # 0..1-ish

func report_damage(amount: float) -> void:
	_frame_damage += amount

func _process(delta: float) -> void:
	var inst_dps: float = 0.0
	if delta > 0.0:
		inst_dps = _frame_damage / delta
	_frame_damage = 0.0
	var alpha: float = 1.0 - exp(-delta / max(dps_tau_sec, 0.001))
	_ema_dps = _ema_dps + alpha * (inst_dps - _ema_dps)

func get_pps() -> float:
	var pps: float = _ema_dps * (1.0 + _evasion_est) + 0.3 * _aoe_factor + 0.3 * _sustain_rating
	return pps

func set_estimates(evasion_0_to_1: float, aoe_0_to_1: float, sustain_0_to_1: float) -> void:
	_evasion_est = clamp(evasion_0_to_1, 0.0, 1.0)
	_aoe_factor = clamp(aoe_0_to_1, 0.0, 1.0)
	_sustain_rating = clamp(sustain_0_to_1, 0.0, 1.0)
