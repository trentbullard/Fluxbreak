extends Node

var _failures: Array[String] = []
var _world: Node3D
var _ship: Ship
var _director: WaveDirector
var _spawner: Spawner
var _observed_waves: Array[int] = []
var _completed_count: int = 0
var _peak_brood_count: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _process(_delta: float) -> void:
	if is_instance_valid(_ship) and _completed_count == 0:
		# Validate the whole encounter flow without automating balance decisions.
		_ship.hull = _ship.eff_max_hull
		_ship.shield = _ship.eff_max_shield
	_peak_brood_count = maxi(_peak_brood_count, get_tree().get_nodes_in_group("bug_brood").size())

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name")) != "Fluxbreak Bug Validation":
		push_error("Run Bug checks in the isolated Fluxbreak Bug Validation project.")
		get_tree().quit(2)
		return
	# Accelerated flow checks do not exercise menu audio playback.
	get_tree().node_added.connect(_mute_test_menu_music)
	var world_scene: PackedScene = load("res://scenes/world/world.tscn") as PackedScene
	_world = world_scene.instantiate() as Node3D
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	await get_tree().process_frame
	_ship = _world.get_node("Ship") as Ship
	_director = _world.get_node("StageRoot/WaveDirector") as WaveDirector
	_spawner = _world.get_node("StageRoot/Spawner") as Spawner
	var buyer: BudgetBuyer = _world.get_node("StageRoot/BudgetBuyer") as BudgetBuyer
	var run: RunDefinition = load("res://content/data/runs/bugs_practice.tres") as RunDefinition
	var stage: StageDef = run.get_stage(0)
	_check(stage.get_boss_pool().size() == 2, "Practice must offer both Bug bosses.")
	_check(stage.completion_flow == StageDef.CompletionFlow.BOSS_FINALE, "Practice must complete on boss defeat.")
	var expected_ids: Array[String] = ["bug_sporeling_mk1", "bug_carapace_mk1", "bug_broodmother_mk1", "bug_devourer_mk1", "bug_hive_queen_mk1"]
	for wave_offset in range(expected_ids.size()):
		for sample in range(12):
			buyer.clear_history()
			var requests: Array[SpawnRequest] = buyer.buy_wave(stage.authored_enemy_budgets[wave_offset], 0, stage.wave_cards[wave_offset], stage.authored_tier_caps[wave_offset])
			var found_expected: bool = false
			for request: SpawnRequest in requests:
				if request.enemy_def == null:
					continue
				_check(request.enemy_def.get_faction_id() == &"bugs", "A teaching wave contains another faction.")
				_check(request.enemy_def.tier <= wave_offset + 1, "A teaching wave skips its tier limit.")
				if request.enemy_def.id == expected_ids[wave_offset] and request.count > 0:
					found_expected = true
			_check(found_expected, "Wave %d omitted its teaching enemy in sample %d." % [wave_offset + 1, sample])
	_director.wave_started.connect(_on_wave_started)
	GameFlow.run_completed.connect(_on_completed)
	var menu: Control = _world.get_node("MainMenuOverlay") as Control
	menu.call("set_practice_faction_id", &"bugs")
	var button: Button = menu.get_node("CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/MercPracticeContainer/MercPractice") as Button
	_check(not button.disabled, "Bugs Practice must work with the default unlocked loadout.")
	button.pressed.emit()
	run = GameFlow.get_active_run_definition()
	stage = run.get_stage(0)
	_check(run.enemy_faction != null and run.enemy_faction.get_faction_id() == &"bugs", "The default faction button did not launch Bugs Practice.")
	_check(is_equal_approx(_director._get_wave_timeout_sec(), 22.0), "Practice must use short wave timing.")
	_check(is_equal_approx(_director._get_downtime_sec(), 5.0), "Practice must use short downtime.")
	var hint: Label = _world.get_node("HUD/ScreenRoot/StageCombatHint") as Label
	_check(hint.visible and hint.text.contains("Broodmother"), "Bug counterplay instructions must be visible in the HUD.")
	var elapsed: float = 0.0
	while not _director.is_boss_wave_active() and elapsed < 190.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	_check(_director.is_boss_wave_active(), "Bugs Practice did not reach its boss within the short encounter window.")
	_check(_observed_waves == [1, 2, 3, 4, 5, 6], "All five teaching waves must precede the boss.")
	await get_tree().process_frame
	await get_tree().process_frame
	var boss: Enemy = _director._active_boss_instance
	if boss != null:
		for target: Node in get_tree().get_nodes_in_group("targets"):
			if target is Enemy:
				var current_brood: bool = target.is_in_group("bug_brood") and int(target.get_meta("brood_parent_id", 0)) == boss.get_instance_id()
				_check(target == boss or current_brood, "The boss handoff left normal enemies or stale brood alive.")
		boss.global_position = _ship.global_position + Vector3(0, 0, -300)
		boss.explosion_scene = null
		boss.hull = boss.eff_max_hull * 0.5
		var brood: BugBroodSpawner = boss.call("get_brood_spawner") as BugBroodSpawner
		var saw_warning: bool = false
		var saw_brood: bool = false
		for frame in range(1500):
			await get_tree().process_frame
			if not get_tree().get_nodes_in_group("enemy_attack_telegraphs").is_empty():
				saw_warning = true
			if brood.get_living_count() > 0:
				saw_brood = true
			if saw_warning and saw_brood:
				break
		_check(int(boss.get_meta("bug_phase", 0)) == 2, "Bug boss did not enter its second phase at half hull.")
		_check(saw_warning, "Bug boss never produced a visible locked attack warning.")
		_check(saw_brood, "Bug boss never released its finite brood during combat.")
		_check(brood.get_living_count() <= 8, "Bug boss exceeded eight living children.")
		_check(brood.get_total_spawned() <= 16, "Bug boss exceeded its lifetime budget.")
		boss.apply_damage(boss.hull + boss.shield + 100.0)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_completed_count == 1, "Boss defeat must complete the run exactly once.")
		_check(int(_spawner.get_alive_counts().get("enemies", -1)) == 0, "Victory left Bug enemies alive.")
		_check(get_tree().get_nodes_in_group("bug_brood").is_empty(), "Victory left summoned brood alive.")
		_check(get_tree().get_nodes_in_group("enemy_attack_telegraphs").is_empty(), "Victory left attack warnings alive.")
		_check(get_tree().get_nodes_in_group("bug_spore_zones").is_empty(), "Victory left spore zones alive.")
	else:
		_check(false, "The stage did not spawn a Bug boss actor.")
	_check(_peak_brood_count <= 12, "Practice exceeded the global brood cap.")
	for frame_index: int in range(int(ceil((GameFlow.VICTORY_RETURN_DELAY_SEC + 1.0) * 60.0))):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene != _world:
			break
	await get_tree().process_frame
	var returned_world: Node = get_tree().current_scene
	_check(returned_world != null and returned_world != _world, "Victory did not return to a fresh menu.")
	if returned_world != null and returned_world.has_node("MainMenuOverlay"):
		var returned_menu: Control = returned_world.get_node("MainMenuOverlay") as Control
		returned_menu.call("set_practice_faction_id", &"bugs")
		var restart_button: Button = returned_menu.get_node("CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/MercPracticeContainer/MercPractice") as Button
		restart_button.pressed.emit()
		_check(GameFlow.get_current_stage().get_stage_id() == stage.get_stage_id() and GameFlow.get_run_faction().get_faction_id() == &"bugs", "Bugs Practice could not restart.")
		var restarted_director: WaveDirector = returned_world.get_node("StageRoot/WaveDirector") as WaveDirector
		_check(restarted_director.get_wave_index() == 0, "Restart retained the previous wave index.")
		GameFlow._run_active = false
		GameFlow._clear_run_progression()
		returned_world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("BUG PRACTICE CHECKS: %s; waves=%s; boss reached at %.1fs; peak brood=%d" % ["PASS" if _failures.is_empty() else "FAIL", str(_observed_waves), elapsed, _peak_brood_count])
	call_deferred("_finish_checks")

func _on_wave_started(index: int, _enemy_budget: int, _target_budget: int) -> void:
	_observed_waves.append(index)
	if index <= 5:
		var stage: StageDef = GameFlow.get_current_stage()
		_check(_director._active_card == stage.wave_cards[index - 1], "Bug teaching cards played out of order.")
		var expected_primary: Array[String] = ["bug_sporeling_mk1", "bug_carapace_mk1", "bug_broodmother_mk1", "bug_devourer_mk1", "bug_hive_queen_mk1"]
		var plan: Dictionary = _director.get_debug_snapshot().get("wave_plan", {})
		_check(str(plan.get("primary_enemy_id", "")) == expected_primary[index - 1], "A live wave chose the wrong primary role.")

func _on_completed() -> void:
	_completed_count += 1

func _finish_checks() -> void:
	get_tree().quit(0 if _failures.is_empty() else 1)

func _mute_test_menu_music(node: Node) -> void:
	if node is AudioStreamPlayer and node.name == &"MenuMusic":
		(node as AudioStreamPlayer).stream = null
