extends Node

var _failures: Array[String] = []
var _world: Node3D
var _ship: Ship
var _director: WaveDirector
var _spawner: Spawner
var _observed_waves: Array[int] = []
var _completed_count: int = 0
var _peak_brood_count: int = 0
var _boss_arrival_snapshot: Array[Dictionary] = []
var _boss_arrival_checked: bool = false

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
	_director.boss_wave_started.connect(_on_boss_wave_started)
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
	_check(_boss_arrival_checked, "Boss arrival must verify preservation of ordinary actors.")
	await get_tree().process_frame
	await get_tree().process_frame
	var boss: Enemy = _director._active_boss_instance
	if boss != null:
		boss.global_position = _ship.global_position + Vector3(0, 0, -300)
		boss.explosion_scene = null
		boss.hull = boss.eff_max_hull * 0.5
		var brood: BugBroodSpawner = boss.call("get_brood_spawner") as BugBroodSpawner
		var saw_warning: bool = false
		var saw_brood: bool = false
		for frame in range(1500):
			await get_tree().process_frame
			if _has_warning_from(boss):
				saw_warning = true
			if brood.get_living_count() > 0:
				saw_brood = true
			if saw_warning and saw_brood:
				break
		_check(int(boss.get_meta("bug_phase", 0)) == 2, "Bug boss did not enter its second phase at half hull.")
		_check(saw_warning, "Bug boss never produced a visible locked attack warning.")
		_check(saw_brood, "Bug boss never released its brood during combat.")
		var boss_id: int = boss.get_instance_id()
		var boss_children: Array[WeakRef] = []
		for child: Node in get_tree().get_nodes_in_group("bug_brood"):
			if int(child.get_meta("brood_parent_id", 0)) == boss_id:
				boss_children.append(weakref(child))
		boss.apply_damage(boss.hull + boss.shield + 100.0)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_completed_count == 1, "Boss defeat must complete the run exactly once.")
		_check(get_tree().paused, "Victory must pause immediately despite surviving ordinary enemies.")
		for reference: WeakRef in boss_children:
			_check(is_instance_valid(reference.get_ref()), "Boss victory must preserve its already released brood until actual world teardown.")
		_check_live_ability_owners(boss_id)
	else:
		_check(false, "The stage did not spawn a Bug boss actor.")
	for frame_index: int in range(int(ceil((GameFlow.VICTORY_RETURN_DELAY_SEC + 1.0) * 60.0))):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene != _world:
			break
	await get_tree().process_frame
	var returned_world: Node = get_tree().current_scene
	_check(returned_world != null and returned_world != _world, "Victory did not return to a fresh menu.")
	_check(_completed_count == 1, "Survivors must not produce another run completion.")
	_check_no_world_combat()
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
		_check_no_world_combat()
	print("BUG PRACTICE CHECKS: %s; waves=%s; boss reached at %.1fs; peak brood=%d" % ["PASS" if _failures.is_empty() else "FAIL", str(_observed_waves), elapsed, _peak_brood_count])
	call_deferred("_finish_checks")

func _on_wave_started(index: int, _enemy_budget: int, _target_budget: int) -> void:
	_observed_waves.append(index)
	if index == 6:
		_snapshot_boss_arrival()
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

func _snapshot_boss_arrival() -> void:
	_boss_arrival_snapshot.clear()
	for node: Node in get_tree().get_nodes_in_group("targets"):
		if node is Enemy and not node is EnemyBoss:
			var enemy: Enemy = node as Enemy
			if not enemy._dead and not enemy.is_queued_for_deletion():
				_boss_arrival_snapshot.append({"actor": enemy, "id": enemy.get_instance_id(), "hull": enemy.hull, "shield": enemy.shield})

func _on_boss_wave_started(_boss_def: EnemyBossDef, _wave_index: int) -> void:
	# Both signals run synchronously: no legitimate damage can occur in between.
	_boss_arrival_checked = true
	for entry: Dictionary in _boss_arrival_snapshot:
		var valid: bool = is_instance_valid(entry["actor"])
		_check(valid, "Boss arrival must preserve each living ordinary enemy identity.")
		if valid:
			var enemy: Enemy = entry["actor"] as Enemy
			_check(enemy.get_instance_id() == int(entry["id"]) and not enemy._dead and not enemy.is_queued_for_deletion(), "Boss arrival must keep each prior enemy alive.")
			_check(is_equal_approx(enemy.hull, float(entry["hull"])) and is_equal_approx(enemy.shield, float(entry["shield"])), "Boss arrival must preserve ordinary enemy damage.")
	_check_live_ability_owners()

func _has_warning_from(source: Enemy) -> bool:
	for node: Node in get_tree().get_nodes_in_group("enemy_attack_telegraphs"):
		var warning: EnemyAttackTelegraph = node as EnemyAttackTelegraph
		if warning != null and not warning.is_queued_for_deletion() and warning._source == source:
			return true
	return false

func _check_live_ability_owners(defeated_boss_id: int = 0) -> void:
	for group_name: String in ["enemy_attack_telegraphs", "bug_spore_zones", "grey_displacements", "grey_tethers"]:
		for ability: Node in get_tree().get_nodes_in_group(group_name):
			if ability.is_queued_for_deletion():
				continue
			var source_value: Variant = ability.get("_source")
			var source: Enemy = source_value as Enemy if is_instance_valid(source_value) else null
			var living: bool = is_instance_valid(source) and not source._dead and not source.is_queued_for_deletion()
			_check(living, "A surviving %s must belong to a living enemy; orphan warnings are forbidden." % group_name)
			if living:
				_check(source.get_instance_id() != defeated_boss_id, "Defeated boss must clean its own abilities.")
	for child: Node in get_tree().get_nodes_in_group("bug_brood"):
		var minion: Enemy = child as Enemy
		_check(is_instance_valid(minion) and minion._spawn_context.is_summoned and not minion._spawn_context.grants_kill_rewards and not minion._spawn_context.contributes_to_pressure, "Retained minions stay independent and preserve summon exclusions after owner death.")

func _check_no_world_combat() -> void:
	for group_name: String in ["enemy_attack_telegraphs", "bug_spore_zones", "grey_displacements", "grey_tethers", "bug_brood", "merc_escorts"]:
		_check(get_tree().get_nodes_in_group(group_name).is_empty(), "World teardown left stale combat group %s." % group_name)
	for node: Node in get_tree().get_nodes_in_group("targets"):
		_check(not node is Enemy and not node is TargetObject, "World teardown must remove all old enemies and stationary targets.")
