extends Node

## Exercise the production allocation path without spawning a rendered battle.
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const WAVES: Array[int] = [1, 10, 20, 25, 29]
const STAGE_ONE_POINTS: Array[int] = [7, 39, 95, 134, 170]
const STAGE_TWO_POINTS: Array[int] = [68, 116, 200, 258, 313]
const SCALING_DEF: EnemyCombatScalingDef = preload("res://content/data/scaling/enemy_combat_scaling_default.tres")

var _checks: int = 0
var _failures: int = 0

class UnspentBuyer extends BudgetBuyer:
	func _ready() -> void:
		pass

	func buy_wave(enemy_points: int, target_points: int, card: WaveCard, _max_enemy_tier: int, _wave_index: int = 0, _stage_index: int = 0, _elapsed_sec: float = 0.0) -> Array[SpawnRequest]:
		_last_wave_plan = {
			"card_id": str(card.get_card_id()), "enemy_points": enemy_points,
			"enemy_points_spent": 0, "enemy_points_remainder": enemy_points,
			"target_points": target_points, "planned_enemy_units": 0,
		}
		return []

class AllocationHarness extends WaveDirector:
	var boss_starts: int = 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_PAUSABLE
		set_process(false)

	func _run_requests_async(_requests: Array[SpawnRequest], _profile: Dictionary, _layouts: Dictionary) -> void:
		pass

	func _start_boss_wave() -> void:
		boss_starts += 1
		_active_boss_def = GameFlow.get_current_stage().get_boss_pool()[0]
		_active_boss_instance = ENEMY_SCENE.instantiate() as Enemy
		_active_boss_instance.freeze = true
		_active_boss_instance.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(_active_boss_instance)
		_active_boss_instance.def = _active_boss_def
		_active_boss_instance.about_to_die.connect(_on_active_boss_about_to_die)
		_boss_wave_active = true
		GameFlow.begin_boss_encounter(_active_boss_def, _wave_index)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Wave Budget Validation":
		push_error("Wave budget checks require their save-isolated validation wrapper.")
		get_tree().quit(2)
		return
	GameFlow.abandon_run()
	get_tree().paused = false
	CombatStats.set_process(false)
	CombatStats.reset_run_metrics()
	_check_curve_fixtures()
	_check_early_curve_and_configuration()
	_check_adaptive_components()
	_check_combat_stat_separation()
	await _check_campaign_allocations()
	await _check_real_opening_wait()
	await _check_authored_practice()
	await _check_performance_handoff()
	GameFlow.abandon_run()
	CombatStats.reset_run_metrics()
	CombatStats.set_process(true)
	get_tree().paused = false
	await get_tree().process_frame
	print("WAVE_BUDGET_SCALING_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _check_curve_fixtures() -> void:
	var threat: ThreatDirector = ThreatDirector.new()
	var budgeter: WaveBudgeter = WaveBudgeter.new()
	var opening_macro: float = threat.compute_macro_threat(0.0, 1)
	for index: int in range(WAVES.size()):
		var wave: int = WAVES[index]
		var elapsed: float = float(wave - 1) * 60.0
		var macro: float = threat.compute_macro_threat(elapsed, wave)
		var first: Dictionary = budgeter.build_campaign_quantity_budget(macro, wave, opening_macro)
		var second: Dictionary = budgeter.build_campaign_quantity_budget(macro, wave, opening_macro, 170.0)
		_check(int(first["enemy_points_pre_adaptive"]) == STAGE_ONE_POINTS[index], "Stage one wave %d must match its fixed neutral point fixture." % wave)
		_check(int(second["enemy_points_pre_adaptive"]) == STAGE_TWO_POINTS[index], "Stage two wave %d must match the carryover/growth fixture." % wave)
		_check(not bool(first["carryover_active"]) and bool(second["carryover_active"]), "Carryover must require an explicit completed-sector allocation.")
		_check_close(float(second["carryover_reference"]), 170.0, "Carryover diagnostics retain the allocated reference.")
		_check_close(float(first["geometric_multiplier"]), pow(1.025, maxi(wave - 10, 0)), "Geometric multiplier is based on the local wave.")
		print("QUANTITY_SAMPLE wave=%d elapsed=%.0f stage1=%d stage2=%d geometric=%.6f" % [wave, elapsed, int(first["enemy_points_pre_adaptive"]), int(second["enemy_points_pre_adaptive"]), float(first["geometric_multiplier"])])
	var twenty: Dictionary = budgeter.build_campaign_quantity_budget(threat.compute_macro_threat(1140.0, 20), 20, opening_macro)
	_check_close(float(twenty["local_quantity_points"]), 95.3022943154, "The late multiplier retains fractional points before allocation rounding.")
	var first_of_second: Dictionary = budgeter.build_campaign_quantity_budget(opening_macro, 1, opening_macro, 170.0)
	_check_close(float(first_of_second["quantity_curve_points"]), 68.0, "Stage two opens at exactly forty percent of the preceding neutral allocation.")
	var extended: Dictionary = budgeter.build_campaign_quantity_budget(threat.compute_macro_threat(1740.0, 30), 30, opening_macro, 170.0)
	_check(int(extended["enemy_points_pre_adaptive"]) > STAGE_TWO_POINTS.back(), "The quantity helper has no late-wave ceiling of its own.")
	threat.free()
	budgeter.free()

func _check_early_curve_and_configuration() -> void:
	var threat: ThreatDirector = ThreatDirector.new()
	var budgeter: WaveBudgeter = WaveBudgeter.new()
	for wave: int in range(1, 11):
		for elapsed: float in [0.0, 120.0, 955.0]:
			var macro: float = threat.compute_macro_threat(elapsed, wave)
			var previous: Dictionary = budgeter.to_budgets(macro, elapsed, wave)
			var quantity: Dictionary = budgeter.build_campaign_quantity_budget(macro, wave, threat.compute_macro_threat(0.0, 1))
			_check(int(quantity["enemy_points_pre_adaptive"]) == int(previous["enemy_points"]), "Early neutral allocation must retain the old linear quantity curve.")
			_check_close(float(quantity["geometric_multiplier"]), 1.0, "Waves one through ten have no geometric boost.")
	var zero_reference: Dictionary = budgeter.build_campaign_quantity_budget(threat.compute_macro_threat(0.0, 1), 1, threat.compute_macro_threat(0.0, 1), 0.0)
	_check(bool(zero_reference["carryover_active"]), "A recorded zero allocation is distinct from an absent reference.")
	budgeter.campaign_geometric_growth = 1.0
	var disabled_growth: Dictionary = budgeter.build_campaign_quantity_budget(threat.compute_macro_threat(1680.0, 29), 29, threat.compute_macro_threat(0.0, 1))
	_check(int(disabled_growth["enemy_points_pre_adaptive"]) == 106, "The geometric factor is a tunable setting rather than a hidden extra budget path.")
	budgeter.campaign_carryover_opening_fraction = 0.5
	var alternate_opening: Dictionary = budgeter.build_campaign_quantity_budget(threat.compute_macro_threat(0.0, 1), 1, threat.compute_macro_threat(0.0, 1), 170.0)
	_check(int(alternate_opening["enemy_points_pre_adaptive"]) == 85, "The carryover opening fraction is independently configurable.")
	threat.free()
	budgeter.free()

func _check_adaptive_components() -> void:
	var threat: ThreatDirector = ThreatDirector.new()
	var intensity: WaveIntensityDirector = WaveIntensityDirector.new()
	_check_close(threat.get_performance_scale(20.0, 0.0), 1.0, "Reference PPS has a neutral macro performance factor.")
	_check_close(threat.get_performance_scale(1000.0, 0.0), 1.18, "Macro performance still honors its existing upshift limit.")
	_check_close(threat.get_performance_scale(0.0, 18.0), 0.838, "Macro low-performance and incoming-damage relief remain unchanged.")
	_check_close(threat.compute_threat(540.0, 10, 1, 1000.0, 0.0), threat.compute_macro_threat(540.0, 10, 1) * 1.18, "Legacy compute_threat combines the macro curve and performance exactly once.")
	var adjusted: Dictionary = intensity.get_opening_adjustment(100, 1.3, 0.0)
	_check(int(adjusted["enemy_points"]) == 108, "The existing opening kill-rate nudge remains eight percent.")
	threat.free()
	intensity.free()

func _check_combat_stat_separation() -> void:
	var combat: EnemyCombatScalingDirector = EnemyCombatScalingDirector.new()
	combat.scaling_def = SCALING_DEF
	var tenth: EnemyCombatScalingSnapshot = combat.build_snapshot(10, 540.0)
	var last: EnemyCombatScalingSnapshot = combat.build_snapshot(29, 1680.0)
	_check_close(tenth.intensity, 1.408, "Enemy combat-stat progression retains its authored wave-ten intensity.")
	_check_close(tenth.hull_multiplier, 1.9856, "Quantity growth must not change hull scaling.")
	_check_close(last.intensity, 6.0, "Combat-stat intensity retains its existing cap.")
	_check_close(last.damage_multiplier, 4.3, "Quantity growth must not change damage scaling.")
	combat.set_carried_baseline_from_snapshot(last)
	_check_close(combat.build_snapshot(29, 1680.0).intensity, 12.0, "Combat-stat carryover retains its separate existing progression.")
	combat.free()

func _new_harness() -> AllocationHarness:
	var director: AllocationHarness = AllocationHarness.new()
	add_child(director)
	director._threat_dir = ThreatDirector.new()
	director.add_child(director._threat_dir)
	director._wave_budgeter = WaveBudgeter.new()
	director.add_child(director._wave_budgeter)
	director._intensity_dir = WaveIntensityDirector.new()
	director.add_child(director._intensity_dir)
	director._buyer = UnspentBuyer.new()
	director.add_child(director._buyer)
	director._enemy_combat_scaling_dir = EnemyCombatScalingDirector.new()
	director._enemy_combat_scaling_dir.scaling_def = SCALING_DEF
	director.add_child(director._enemy_combat_scaling_dir)
	GameFlow.stage_changed.connect(director._on_stage_changed)
	director._reset_stage_runtime(true, true, true)
	return director

func _set_live_performance(pps: float, incoming: float, kills: float) -> void:
	CombatStats._ema_dps = pps
	CombatStats._ema_damage_taken = incoming
	CombatStats._ema_enemy_kills_per_sec = kills
	CombatStats.set_estimates(0.0, 0.0, 0.0)

func _check_campaign_allocations() -> void:
	for faction: PracticeFactionDef in PracticeRunFactory.get_factions():
		for route_index: int in range(2):
			GameFlow.start_new_run(PracticeRunFactory.create_run(faction.faction.get_faction_id(), false))
			var director: AllocationHarness = _new_harness()
			for index: int in range(WAVES.size()):
				_start_fixture_wave(director, WAVES[index], 20.0, 0.0, 0.65)
				var snapshot: Dictionary = director.get_debug_snapshot()
				_check(int(snapshot["enemy_points"]) == STAGE_ONE_POINTS[index], "%s Campaign stage one wave %d allocates the neutral fixture." % [faction.faction.get_faction_id(), WAVES[index]])
				_check(int(snapshot["enemy_points_pre_adaptive"]) == STAGE_ONE_POINTS[index], "Pre-adaptive diagnostics record the neutral allocation.")
				_check_close(float(snapshot["threat_performance_scale"]), 1.0, "Neutral performance is applied once after the quantity curve.")
				_check_close(float(snapshot["opening_enemy_scale"]), 1.0, "Reference kill rate has a neutral opening factor.")
				_check(int((snapshot["wave_plan"] as Dictionary)["enemy_points_spent"]) == 0, "The fixture deliberately leaves all allocated budget unspent.")
			_start_fixture_wave(director, 29, 1000.0, 0.0, 1.3)
			var boosted: Dictionary = director.get_debug_snapshot()
			_check(int(boosted["enemy_points"]) == 217, "High performance applies the existing macro and opening factors once to the late curve.")
			_check_close(director._last_ordinary_enemy_points_pre_adaptive, 170.0, "The saved reference excludes BOTH adaptive adjustments and buyer spending.")
			var opening_duration: float = director._get_downtime_sec()
			var ordinary_timeout: float = director._get_wave_timeout_sec()
			var approach: StageDef = GameFlow.get_current_stage()
			director._wave_index = approach.boss_wave_index - 1
			director._next_wave()
			_check(director.boss_starts == 1 and int(director.get_debug_snapshot()["wave_index"]) == 30, "The real boss-wave branch still starts at its authored wave.")
			_check_close(director._last_ordinary_enemy_points_pre_adaptive, 170.0, "The zero-budget boss cannot overwrite the last ordinary allocation.")
			var boss: Enemy = director._active_boss_instance
			boss.about_to_die.emit(boss)
			_check(director.is_gateway_hold_active(), "Actual boss completion immediately enters gateway hold.")
			_check_close(director._quantity_carryover_reference, 170.0, "Gateway boss completion captures the preceding ordinary allocation.")
			_check_close(director._enemy_combat_scaling_dir.get_carried_baseline_intensity(), 6.0, "Quantity carryover preserves existing boss-time combat-stat carryover.")
			var route: SectorRouteDef = approach.get_gateway_routes()[route_index]
			_check(GameFlow.advance_to_next_stage(route.get_destination_id()), "The real offered gateway route accepts stage two.")
			director.begin_stage_after_gateway_transfer()
			_check(GameFlow.get_active_stage_index() == 1 and director.get_wave_index() == 0, "Confirmed transfer restarts local quantity progression.")
			_check_close(director._quantity_carryover_reference, 170.0, "Quantity carryover survives gateway hold and the stage runtime reset.")
			_check_close(director._last_ordinary_enemy_points_pre_adaptive, -1.0, "The next sector starts a fresh last-ordinary reference.")
			_check_close(director._get_downtime_sec(), opening_duration, "The budget pass keeps existing sector downtime duration.")
			_check_close(director._get_wave_timeout_sec(), ordinary_timeout, "The budget pass keeps existing wave timeout duration.")
			for index: int in range(WAVES.size()):
				_start_fixture_wave(director, WAVES[index], 20.0, 0.0, 0.65)
				var snapshot: Dictionary = director.get_debug_snapshot()
				_check(int(snapshot["enemy_points"]) == STAGE_TWO_POINTS[index], "%s Campaign stage two wave %d allocates the accelerated carryover fixture on either route." % [faction.faction.get_faction_id(), WAVES[index]])
				_check_close(float((snapshot["enemy_quantity_curve"] as Dictionary)["carryover_reference"]), 170.0, "Route changes do not replace the quantity carryover reference.")
			_start_fixture_wave(director, 20, 1000.0, 0.0, 1.3)
			_check(int(director.get_debug_snapshot()["enemy_points"]) == 256, "Stage two applies performance once after carryover and accelerated local growth without early rounding.")
			_start_fixture_wave(director, 20, 0.0, 18.0, 0.0)
			_check(int(director.get_debug_snapshot()["enemy_points"]) == 155, "Existing damage relief and low-performance factors remain bounded after the curve.")
			GameFlow.start_new_run(PracticeRunFactory.create_run(faction.faction.get_faction_id(), false))
			director._reset_stage_runtime(true, true, true)
			_check_close(director._quantity_carryover_reference, -1.0, "A new run clears quantity carryover.")
			_check_close(director._last_ordinary_enemy_points_pre_adaptive, -1.0, "A new run clears the last ordinary allocation.")
			_check(director._pending_opening_performance.is_empty(), "A new run discards previous-run opening performance.")
			_check_close(director._enemy_combat_scaling_dir.get_carried_baseline_intensity(), 0.0, "A new run resets the independent combat-stat baseline as before.")
			director.free()
			GameFlow.abandon_run()
	await get_tree().process_frame

func _start_fixture_wave(director: AllocationHarness, wave: int, pps: float, incoming: float, kills: float) -> void:
	# These fixtures intentionally jump over combat; recorder behavior is tested
	# separately using genuine damage/kill reports and active simulation time.
	CombatStats.reset_run_metrics()
	_set_live_performance(pps, incoming, kills)
	director._pending_opening_performance.clear()
	director._wave_index = wave - 1
	director._elapsed_sec = float(wave - 1) * 60.0
	director._next_wave()

func _check_real_opening_wait() -> void:
	GameFlow.start_new_run(PracticeRunFactory.create_run(&"mercs", false))
	var director: AllocationHarness = _new_harness()
	var route: SectorRouteDef = GameFlow.get_current_stage().get_gateway_routes()[0]
	_check(GameFlow.advance_to_next_stage(route.get_destination_id()), "Opening-wait fixture accepts the real second-sector route.")
	director._quantity_carryover_reference = 171.0
	director.begin_stage_after_gateway_transfer()
	CombatStats.reset_run_metrics()
	_set_live_performance(20.0, 0.0, 0.65)
	director._elapsed_sec = 5.0
	director._next_wave()
	var snapshot: Dictionary = director.get_debug_snapshot()
	_check(int(snapshot["enemy_points_pre_adaptive"]) == 68, "The real first five-second wait must not add phantom stage-two growth above its forty-percent opening.")
	_check_close(float((snapshot["enemy_quantity_curve"] as Dictionary)["quantity_curve_points"]), 68.4, "The first allocation in the second sector is exactly forty percent before adaptive adjustments.")
	director.free()
	GameFlow.abandon_run()
	await get_tree().process_frame

func _check_authored_practice() -> void:
	for faction: PracticeFactionDef in PracticeRunFactory.get_factions():
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 479021
		var run: RunDefinition = PracticeRunFactory.create_run(faction.faction.get_faction_id(), true, rng)
		GameFlow.start_new_run(run)
		var director: AllocationHarness = _new_harness()
		var stage: StageDef = GameFlow.get_current_stage()
		var budgets_before: PackedInt32Array = stage.authored_enemy_budgets.duplicate()
		var tiers_before: PackedInt32Array = stage.authored_tier_caps.duplicate()
		for index: int in range(stage.authored_enemy_budgets.size()):
			_set_live_performance(1000.0, 0.0, 3.0)
			director._wave_index = index
			director._elapsed_sec = 9000.0
			director._next_wave()
			var snapshot: Dictionary = director.get_debug_snapshot()
			_check(int(snapshot["enemy_points"]) == budgets_before[index], "%s Practice wave %d must retain its exact authored budget despite high performance and elapsed time." % [faction.faction.get_faction_id(), index + 1])
			_check(director._active_card == stage.wave_cards[index], "Short Practice keeps its authored lesson order.")
			_check(director._get_max_enemy_tier() == tiers_before[index], "Short Practice keeps its authored tier cap.")
			_check_close(float(snapshot["opening_enemy_scale"]), 1.0, "Authored Practice budgets bypass opening adjustments.")
		_check(stage.authored_enemy_budgets == budgets_before and stage.authored_tier_caps == tiers_before, "Allocation does not mutate authored Practice resources.")
		director.free()
		GameFlow.abandon_run()
	await get_tree().process_frame

func _check_performance_handoff() -> void:
	GameFlow.start_new_run(PracticeRunFactory.create_run(&"greys", false))
	CombatStats.reset_run_metrics()
	_set_live_performance(20.0, 0.0, 0.65)
	var director: AllocationHarness = _new_harness()
	director._next_wave()
	_check(str((director.get_debug_snapshot()["opening_performance"] as Dictionary)["source"]) == "live", "The first opening keeps its live-metric fallback when no previous wave exists.")
	for second: int in range(1, 11):
		CombatStats._process(1.0)
		director._process(1.0)
		CombatStats.report_damage(float(second))
		CombatStats.report_damage_taken(float(second) * 2.0)
		CombatStats.report_enemy_kill(3)
		if second == 5:
			var before_pause: Dictionary = CombatStats.get_wave_performance_snapshot()
			get_tree().paused = true
			CombatStats.report_damage(10000.0)
			CombatStats.report_damage_taken(10000.0)
			CombatStats.report_enemy_kill(10000)
			CombatStats._process(100.0)
			await get_tree().process_frame
			var after_pause: Dictionary = CombatStats.get_wave_performance_snapshot()
			_check_close(float(after_pause["duration_sec"]), float(before_pause["duration_sec"]), "Paused gameplay cannot age the active performance window.")
			_check_close(float(after_pause["pps"]), float(before_pause["pps"]), "Damage reported while paused cannot contaminate the active performance snapshot.")
			_check_close(float(after_pause["kill_rate"]), float(before_pause["kill_rate"]), "Kills reported while paused cannot contaminate the active performance snapshot.")
			get_tree().paused = false
	var rolling: Dictionary = CombatStats.get_wave_performance_snapshot()
	_check_close(float(rolling["duration_sec"]), 5.0, "The recorder retains five active seconds rather than the full wave.")
	_check_close(float(rolling["pps"]), 8.0, "Only reports from the final five active seconds contribute to next-wave PPS.")
	_check_close(float(rolling["incoming_damage_per_sec"]), 16.0, "Incoming damage uses the same final active window.")
	_check_close(float(rolling["kill_rate"]), 1.0, "Opening kill rate uses enemy count rather than threat-point count.")
	# These reports have not gone through CombatStats._process. Closing a wave
	# must capture them immediately, even if they include the final killing hit.
	CombatStats.report_damage(5.0)
	CombatStats.report_damage_taken(3.0)
	CombatStats.report_enemy_kill(9)
	director._start_downtime()
	var saved: Dictionary = director._pending_opening_performance.duplicate(true)
	_check_close(float(saved["pps"]), 9.0, "Wave closure captures the final pending damage report before its EMA update.")
	_check_close(float(saved["incoming_damage_per_sec"]), 16.6, "Wave closure captures pending incoming damage.")
	_check_close(float(saved["kill_rate"]), 1.2, "Wave closure captures the final pending kill.")
	_check(CombatStats.capture_wave_performance_window().is_empty(), "A captured recorder stops at downtime and cannot overwrite a valid saved snapshot.")
	CombatStats.report_damage(10000.0)
	CombatStats.report_damage_taken(10000.0)
	CombatStats.report_enemy_kill(10000)
	CombatStats._process(30.0)
	director._process(2.0)
	_check(director._pending_opening_performance == saved, "Downtime combat and signal decay do not replace the previous wave's snapshot.")
	_check(CombatStats.get_pps() > 0.0 and CombatStats.get_damage_taken_per_sec() > 0.0, "Stopping the opening recorder does not stop live EMAs from observing downtime combat.")
	var live_before_decay: float = CombatStats.get_pps()
	CombatStats._process(30.0)
	_check(CombatStats.get_pps() < live_before_decay, "Live EMAs continue their ordinary downtime decay independently of the saved opening window.")
	_set_live_performance(0.0, 0.0, 0.0)
	director._next_wave()
	var consumed: Dictionary = director.get_debug_snapshot()["opening_performance"] as Dictionary
	_check(str(consumed["source"]) == "active_wave_window", "The next opening selects the saved active-wave window over erased live metrics.")
	_check_close(float(consumed["pps"]), 9.0, "The next opening uses the captured PPS.")
	_check_close(float(consumed["incoming_damage_per_sec"]), 16.6, "The next opening uses captured incoming damage.")
	_check_close(float(consumed["kill_rate"]), 1.2, "The next opening uses captured kill rate.")
	_check(director._pending_opening_performance.is_empty(), "A saved opening snapshot is consumed once.")
	CombatStats.cancel_wave_performance_window()
	_set_live_performance(60.0, 0.0, 0.65)
	director._next_wave()
	var fallback: Dictionary = director.get_debug_snapshot()["opening_performance"] as Dictionary
	_check(str(fallback["source"]) == "live", "An absent new wave snapshot does not reuse already-consumed performance.")
	_check_close(float(fallback["pps"]), 60.0, "The consumed-once guard permits a new live fallback.")
	CombatStats._process(0.5)
	CombatStats.report_damage(10.0)
	CombatStats.report_damage_taken(2.0)
	CombatStats.report_enemy_kill(1)
	director._start_downtime()
	var short_wave: Dictionary = director._pending_opening_performance.duplicate(true)
	_check_close(float(short_wave["duration_sec"]), 0.5, "A sub-five-second clear uses its real active duration.")
	_check_close(float(short_wave["pps"]), 20.0, "Short clears are not diluted by a fictitious five-second denominator.")
	_check_close(float(short_wave["kill_rate"]), 2.0, "Short-clear kill rate uses the same real duration.")
	var approach: StageDef = GameFlow.get_current_stage()
	director._wave_index = approach.boss_wave_index - 1
	director._next_wave()
	_check(director._pending_opening_performance == short_wave, "The boss's zero-budget opening does not consume the last ordinary performance window.")
	var boss: Enemy = director._active_boss_instance
	boss.about_to_die.emit(boss)
	CombatStats.report_damage(10000.0)
	CombatStats.report_enemy_kill(10000)
	CombatStats._process(100.0)
	_check(director._pending_opening_performance == short_wave, "Boss/gateway survivor combat cannot replace the saved ordinary-wave snapshot.")
	_check(GameFlow.advance_to_next_stage(approach.get_gateway_routes()[0].get_destination_id()), "Performance handoff fixture accepts a real Campaign route.")
	director.begin_stage_after_gateway_transfer()
	_check(director._pending_opening_performance == short_wave, "Sector reset retains the pending ordinary-wave performance.")
	director._next_wave()
	var second_sector: Dictionary = director.get_debug_snapshot()["opening_performance"] as Dictionary
	_check(str(second_sector["source"]) == "active_wave_window", "Stage two opening uses the saved ordinary-wave snapshot.")
	_check_close(float(second_sector["pps"]), 20.0, "Stage two does not adapt from gateway kills or downtime-decayed signals.")
	_check(director._pending_opening_performance.is_empty(), "Gateway-carried performance is also consumed once.")
	director.free()
	GameFlow.abandon_run()
	await get_tree().process_frame

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _check_close(actual: float, expected: float, message: String) -> void:
	_check(is_equal_approx(actual, expected), "%s Expected %.9f; got %.9f." % [message, expected, actual])
