# scripts/hud/debug_wave_hud.gd (godot 4.5)
extends MarginContainer
class_name DebugWaveHUD

@export var wave_director_path: NodePath
var _wd: WaveDirector

func _ready() -> void:
	_wd = get_node_or_null(wave_director_path)

func _process(_delta: float) -> void:
	var state: RunState.State = RunState.run_state
	var pps: float = CombatStats.get_pps()
	var elapsed: float = 0.0
	var incoming_damage: float = CombatStats.get_damage_taken_per_sec()
	var kill_rate: float = CombatStats.get_enemy_kill_rate()
	var td: ThreatDirector = null
	var bud: WaveBudgeter = null
	if _wd != null:
		elapsed = _wd._elapsed_sec
		td = _wd._threat_dir
		bud = _wd._wave_budgeter
	var threat: float = 0.0
	var budgets: Dictionary = {}
	if td != null and bud != null:
		threat = td.compute_threat(
			elapsed,
			max(_wd.get_wave_index(), 1),
			max(GameFlow.get_active_stage_index(), 0),
			pps,
			incoming_damage
		)
		budgets = bud.to_budgets(threat, elapsed, max(_wd.get_wave_index(), 1), _wd._active_card)
	var snapshot: Dictionary = _wd.get_debug_snapshot() if _wd != null else {}
	var enemy_context: Dictionary = snapshot.get("enemy_effective_context", {})
	var combat_scaling: Dictionary = enemy_context.get("combat_scaling", {})
	var txt: String = "State: %d\nPPS: %.1f\nIncDPS: %.1f\nKillRate: %.2f\nThreat: %.1f\nEnemyPts: %d  TargetPts: %d\nCard: %s\nPressure: %s\nScale Intensity: %.3f\nNanobot Mult: %.2f" % [
		state,
		pps,
		incoming_damage,
		kill_rate,
		threat,
		int(budgets.get("enemy_points", 0)),
		int(budgets.get("target_points", 0)),
		String(snapshot.get("card_name", "Wave")),
		String(snapshot.get("pressure_state", "n/a")),
		float(combat_scaling.get("intensity", snapshot.get("combat_scaling_intensity", 0.0))),
		float(combat_scaling.get("nanobot_multiplier", snapshot.get("enemy_nanobot_multiplier", 1.0)))
	]
	$Label.text = txt
