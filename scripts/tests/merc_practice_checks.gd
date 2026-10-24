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
var _boss_arrival_snapshot: Array[Dictionary] = []
var _boss_arrival_checked: bool = false

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
	var run: RunDefinition = load("res://content/data/runs/merc_practice.tres") as RunDefinition
	var stage: StageDef = run.get_stage(0)
	_check(stage.get_boss_pool().size() == 2, "Practice must offer both valid Merc bosses.")
	_check(stage.completion_flow == StageDef.CompletionFlow.BOSS_FINALE, "Practice must end with boss victory.")
	var expected_ids: Array[String] = ["merc_corvette_mk1", "merc_frigate_mk1", "merc_destroyer_mk1", "merc_cruiser_mk1", "merc_carrier_mk1"]
	for wave_offset in range(expected_ids.size()):
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
	_director.boss_wave_started.connect(_on_boss_wave_started)
	GameFlow.run_completed.connect(_on_completed)
	var menu: Control = _world.get_node("MainMenuOverlay") as Control
	menu.call("set_practice_faction_id", &"mercs")
	var button: Button = menu.get_node("CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/MercPracticeContainer/MercPractice") as Button
	_check(not button.disabled, "Merc Practice must launch with the default unlocked loadout.")
	button.pressed.emit()
	run = GameFlow.get_active_run_definition()
	stage = run.get_stage(0)
	_check(run.enemy_faction != null and run.enemy_faction.get_faction_id() == &"mercs", "Merc Practice button did not route to the authored run.")
	_check(is_equal_approx(_director._get_wave_timeout_sec(), 22.0), "Practice pacing did not override wave timeout.")
	_check(is_equal_approx(_director._get_downtime_sec(), 5.0), "Practice pacing did not override downtime.")
	var elapsed: float = 0.0
	while not _director.is_boss_wave_active() and elapsed < 190.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	_check(_director.is_boss_wave_active(), "Practice did not reach its boss within the short encounter window.")
	_check(_observed_waves == [1, 2, 3, 4, 5, 6], "Practice did not run all five teaching waves before its boss.")
	_check(_boss_arrival_checked, "Boss arrival must verify preservation of ordinary actors.")
	var boss: Enemy = _director._active_boss_instance
	if boss != null:
		boss.global_position = _ship.global_position + Vector3(0, 0, -340)
		boss.explosion_scene = null
		boss.hull = boss.eff_max_hull * 0.5
		await get_tree().process_frame
		await get_tree().process_frame
		_check(int(boss.get_meta("merc_phase", 0)) == 2, "Boss did not enter its second phase.")
		if boss is MercEnforcer:
			var escort_count: int = 0
			for enemy: Node in get_tree().get_nodes_in_group("faction_mercs"):
				if enemy.get_meta("enforcer_escort", false):
					escort_count += 1
			_check(escort_count == 1, "Enforcer must call exactly one accounted shield escort.")
			_check(int(_spawner.get_alive_counts().get("enemies", 0)) >= 2, "Spawner must account for Enforcer and escort alongside survivors.")
		elif boss is MercFlagship:
			var flagship: MercFlagship = boss as MercFlagship
			_check(flagship.get_living_escort_count() > 0 and flagship.get_living_escort_count() <= 3, "Flagship must deploy a bounded escort wing.")
			_check(int(_spawner.get_alive_counts().get("enemies", 0)) >= flagship.get_living_escort_count() + 1, "Spawner must account for Flagship and its wing alongside survivors.")
		else:
			_check(false, "Practice spawned an unsupported Merc boss.")
		var saw_warning: bool = false
		for frame in range(900):
			await get_tree().process_frame
			if _has_warning_from(boss):
				saw_warning = true
				break
		_check(saw_warning, "Boss did not produce its scheduled attack warning.")
		var boss_id: int = boss.get_instance_id()
		var boss_escorts: Array[WeakRef] = []
		if boss is MercEnforcer:
			var escort: Enemy = boss.get("_escort") as Enemy
			if is_instance_valid(escort):
				boss_escorts.append(weakref(escort))
		for node: Node in get_tree().get_nodes_in_group(MercEscortWing.ESCORT_GROUP):
			if int(node.get_meta(MercEscortWing.OWNER_META, 0)) == boss_id:
				boss_escorts.append(weakref(node))
		boss.apply_damage(boss.hull + boss.shield + 100.0)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_completed_count == 1, "Boss defeat must complete the practice run exactly once.")
		_check(get_tree().paused, "Victory must pause immediately despite surviving ordinary enemies.")
		for reference: WeakRef in boss_escorts:
			_check(not is_instance_valid(reference.get_ref()), "Boss victory must remove its own escort without requiring survivor cleanup.")
		_check_live_ability_owners(boss_id)
	else:
		_check(false, "Stage did not spawn a Merc boss actor.")
	# Let the real victory timer return to the menu, then prove a fresh launch.
	for frame_index in range(int(ceil((GameFlow.VICTORY_RETURN_DELAY_SEC + 1.0) * 60.0))):
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
		returned_menu.call("set_practice_faction_id", &"mercs")
		var restart_button: Button = returned_menu.get_node("CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/MercPracticeContainer/MercPractice") as Button
		restart_button.pressed.emit()
		_check(GameFlow.get_current_stage().get_stage_id() == stage.get_stage_id() and GameFlow.get_run_faction().get_faction_id() == &"mercs", "Merc Practice could not restart from the returned menu.")
		var restarted_director: WaveDirector = returned_world.get_node("StageRoot/WaveDirector") as WaveDirector
		_check(restarted_director.get_wave_index() == 0, "Restart retained an old wave index.")
		GameFlow._run_active = false
		GameFlow._clear_run_progression()
		returned_world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		_check_no_world_combat()
	print("MERC PRACTICE CHECKS: %s; waves=%s; boss reached at %.1fs" % ["PASS" if _failures.is_empty() else "FAIL", str(_observed_waves), elapsed])
	# Release this coroutine's loaded stage/scene locals before engine shutdown.
	call_deferred("_finish_checks")

func _finish_checks() -> void:
	get_tree().quit(0 if _failures.is_empty() else 1)

func _mute_test_menu_music(node: Node) -> void:
	if node is AudioStreamPlayer and node.name == &"MenuMusic":
		(node as AudioStreamPlayer).stream = null

func _on_wave_started(index: int, _enemy_budget: int, _target_budget: int) -> void:
	_observed_waves.append(index)
	if index == 6:
		_snapshot_boss_arrival()
	if index <= 5:
		var stage: StageDef = GameFlow.get_current_stage()
		_check(_director._active_card == stage.wave_cards[index - 1], "Teaching cards played out of order.")
		var expected_primary: Array[String] = ["merc_corvette_mk1", "merc_frigate_mk1", "merc_destroyer_mk1", "merc_cruiser_mk1", "merc_carrier_mk1"]
		var plan: Dictionary = _director.get_debug_snapshot().get("wave_plan", {})
		_check(str(plan.get("primary_enemy_id", "")) == expected_primary[index - 1], "Live wave did not choose its authored primary role.")

func _on_completed() -> void:
	_completed_count += 1

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
	for child: Node in get_tree().get_nodes_in_group(MercEscortWing.ESCORT_GROUP):
		var owner_id: int = int(child.get_meta(MercEscortWing.OWNER_META, 0))
		var owner_value: Object = instance_from_id(owner_id) if owner_id != 0 else null
		var owner_enemy: Enemy = owner_value as Enemy
		_check(is_instance_valid(owner_enemy) and not owner_enemy._dead and not owner_enemy.is_queued_for_deletion() and owner_id != defeated_boss_id, "Every retained Merc wing must have a living owner.")

func _check_no_world_combat() -> void:
	for group_name: String in ["enemy_attack_telegraphs", "bug_spore_zones", "grey_displacements", "grey_tethers", "bug_brood", "merc_escorts"]:
		_check(get_tree().get_nodes_in_group(group_name).is_empty(), "World teardown left stale combat group %s." % group_name)
	for node: Node in get_tree().get_nodes_in_group("targets"):
		_check(not node is Enemy and not node is TargetObject, "World teardown must remove all old enemies and stationary targets.")
