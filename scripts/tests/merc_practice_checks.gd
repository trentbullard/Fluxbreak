extends Node

# Run in the isolated Fluxbreak Merc Validation project so victory cannot write
# test progress into the player's normal save. See --scene merc_practice_checks.tscn.
var _failures: Array[String] = []
var _world: Node3D
var _ship: Ship
var _director: WaveDirector
var _spawner: Spawner
var _observed_waves: Array[int] = []
var _completed_count: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _process(_delta: float) -> void:
	if is_instance_valid(_ship) and _completed_count == 0:
		# This is a run-flow test, not an automated balance playthrough.
		_ship.hull = _ship.eff_max_hull
		_ship.shield = _ship.eff_max_shield

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name")) != "Fluxbreak Merc Validation":
		push_error("Run Merc checks in an isolated project named Fluxbreak Merc Validation.")
		get_tree().quit(2)
		return
	var world_scene: PackedScene = load("res://scenes/world/world.tscn") as PackedScene
	_world = world_scene.instantiate() as Node3D
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	await get_tree().process_frame
	_ship = _world.get_node("Ship") as Ship
	_director = _world.get_node("StageRoot/WaveDirector") as WaveDirector
	_spawner = _world.get_node("StageRoot/Spawner") as Spawner
	var buyer: BudgetBuyer = _world.get_node("StageRoot/BudgetBuyer") as BudgetBuyer
	var run: RunDefinition = load("res://content/data/runs/merc_practice.tres") as RunDefinition
	var stage: StageDef = run.get_stage(0)
	_check(stage.get_boss_pool().size() == 1, "Practice must have one valid Merc boss.")
	_check(stage.completion_flow == StageDef.CompletionFlow.BOSS_FINALE, "Practice must end with boss victory.")
	var expected_ids: Array[String] = ["merc_corvette_mk1", "merc_frigate_mk1", "merc_destroyer_mk1"]
	for wave_offset in range(3):
		for sample in range(12):
			# Each sample represents a fresh teaching wave, rather than asking the
			# buyer's anti-repetition history to repeat the same primary forever.
			buyer.clear_history()
			var requests: Array[SpawnRequest] = buyer.buy_wave(stage.authored_enemy_budgets[wave_offset], 0, stage.wave_cards[wave_offset], stage.authored_tier_caps[wave_offset])
			var found_expected: bool = false
			for request: SpawnRequest in requests:
				if request.enemy_def == null:
					continue
				_check(request.enemy_def.get_faction_id() == &"mercs", "Practice wave contains another faction.")
				_check(request.enemy_def.tier <= wave_offset + 1, "Practice wave skips its teaching tier.")
				if request.enemy_def.id == expected_ids[wave_offset] and request.count > 0:
					found_expected = true
			_check(found_expected, "Wave %d did not buy its teaching enemy in sample %d." % [wave_offset + 1, sample])
	_director.wave_started.connect(_on_wave_started)
	GameFlow.run_completed.connect(_on_completed)
	var menu: Control = _world.get_node("MainMenuOverlay") as Control
	# The shared faction button now defaults to Bugs; exercise the retained Merc
	# run explicitly while keeping the current menu's default intact.
	menu.set("merc_practice_run", run)
	var button: Button = menu.get_node("CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/MercPracticeContainer/MercPractice") as Button
	_check(not button.disabled, "Merc Practice must launch with the default unlocked loadout.")
	button.pressed.emit()
	_check(GameFlow.get_active_run_definition() == run, "Merc Practice button did not route to the authored run.")
	_check(is_equal_approx(_director._get_wave_timeout_sec(), 22.0), "Practice pacing did not override wave timeout.")
	_check(is_equal_approx(_director._get_downtime_sec(), 5.0), "Practice pacing did not override downtime.")
	var elapsed: float = 0.0
	while not _director.is_boss_wave_active() and elapsed < 125.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	_check(_director.is_boss_wave_active(), "Practice did not reach its boss within the short encounter window.")
	_check(_observed_waves == [1, 2, 3, 4], "Practice did not run all three teaching waves before its boss.")
	var boss: MercEnforcer = _director._active_boss_instance as MercEnforcer
	if boss != null:
		for target: Node in get_tree().get_nodes_in_group("targets"):
			if target is Enemy:
				_check(target == boss, "Normal wave enemies overlapped the boss handoff.")
		boss.global_position = _ship.global_position + Vector3(0, 0, -340)
		boss.explosion_scene = null
		boss.hull = boss.eff_max_hull * 0.5
		await get_tree().process_frame
		await get_tree().process_frame
		_check(boss.is_in_second_phase(), "Boss did not enter its second phase.")
		var escort_count: int = 0
		for enemy: Node in get_tree().get_nodes_in_group("faction_mercs"):
			if enemy.get_meta("enforcer_escort", false):
				escort_count += 1
		_check(escort_count == 1, "Boss must call exactly one accounted shield escort.")
		_check(int(_spawner.get_alive_counts().get("enemies", 0)) == 2, "Spawner did not account for boss and escort.")
		var saw_warning: bool = false
		for frame in range(900):
			await get_tree().process_frame
			if not get_tree().get_nodes_in_group("enemy_attack_telegraphs").is_empty():
				saw_warning = true
				break
		_check(saw_warning, "Boss did not produce its scheduled attack warning.")
		boss.apply_damage(boss.hull + boss.shield + 100.0)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_completed_count == 1, "Boss defeat must complete the practice run exactly once.")
		_check(_spawner.get_alive_counts().get("enemies", -1) == 0, "Boss victory left an enemy or escort alive.")
		_check(get_tree().get_nodes_in_group("enemy_attack_telegraphs").is_empty(), "Boss victory left an attack warning alive.")
	else:
		_check(false, "Stage did not spawn the Contract Enforcer actor.")
	# Let the real victory timer return to the menu, then prove a fresh launch.
	await get_tree().create_timer(GameFlow.VICTORY_RETURN_DELAY_SEC + 0.25, true).timeout
	var returned_world: Node = get_tree().current_scene
	_check(returned_world != null and returned_world != _world, "Victory did not return to a fresh menu.")
	if returned_world != null and returned_world.has_node("MainMenuOverlay"):
		var returned_menu: Control = returned_world.get_node("MainMenuOverlay") as Control
		returned_menu.set("merc_practice_run", run)
		var restart_button: Button = returned_menu.get_node("CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/MercPracticeContainer/MercPractice") as Button
		restart_button.pressed.emit()
		_check(GameFlow.get_current_stage() == stage, "Merc Practice could not restart from the returned menu.")
		var restarted_director: WaveDirector = returned_world.get_node("StageRoot/WaveDirector") as WaveDirector
		_check(restarted_director.get_wave_index() == 0, "Restart retained an old wave index.")
		GameFlow._run_active = false
		GameFlow._clear_run_progression()
		returned_world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("MERC PRACTICE CHECKS: %s; waves=%s; boss reached at %.1fs" % ["PASS" if _failures.is_empty() else "FAIL", str(_observed_waves), elapsed])
	# Release this coroutine's loaded stage/scene locals before engine shutdown.
	call_deferred("_finish_checks")

func _finish_checks() -> void:
	get_tree().quit(0 if _failures.is_empty() else 1)

func _on_wave_started(index: int, _enemy_budget: int, _target_budget: int) -> void:
	_observed_waves.append(index)
	if index <= 3:
		var stage: StageDef = GameFlow.get_current_stage()
		_check(_director._active_card == stage.wave_cards[index - 1], "Teaching cards played out of order.")
		var expected_primary: Array[String] = ["merc_corvette_mk1", "merc_corvette_mk1", "merc_destroyer_mk1"]
		var plan: Dictionary = _director.get_debug_snapshot().get("wave_plan", {})
		_check(str(plan.get("primary_enemy_id", "")) == expected_primary[index - 1], "Live wave did not choose its authored primary role.")

func _on_completed() -> void:
	_completed_count += 1
