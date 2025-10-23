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
	if _wd != null:
		elapsed = _wd._elapsed_sec
	var td: ThreatDirector = _wd._threat_dir
	var bud: WaveBudgeter = _wd._wave_budgeter
	var threat: float = 0.0
	var budgets: Dictionary = {}
	if td != null and bud != null:
		threat = td.compute_threat(elapsed, pps)
		budgets = bud.to_budgets(threat, elapsed)
	var txt: String = "State: %d\nPPS: %.1f\nThreat: %.1f\nEnemyPts: %d  TargetPts: %d" % [
		state,
		pps,
		threat,
		int(budgets.get("enemy_points", 0)),
		int(budgets.get("target_points", 0))
	]
	$Label.text = txt
