extends Node

var _failures: Array[String] = []
var _world: Node3D = null
var _ship: Ship = null
var _director: WaveDirector = null
var _spawner: Spawner = null
var _observed_waves: Array[int] = []
var _completed_count: int = 0
var _protected_boss: Enemy = null
var _boss_arrival_snapshot: Array[Dictionary] = []
var _boss_arrival_checked: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _process(_delta: float) -> void:
	# This suite verifies encounter flow; focused tests exercise damage and dodge.
	if is_instance_valid(_ship) and _completed_count == 0:
		_ship.hull = _ship.eff_max_hull
		_ship.shield = _ship.eff_max_shield
	if is_instance_valid(_protected_boss) and not _protected_boss._dead:
		var floor_fraction: float = 0.25 if _protected_boss is GreyVeiledMind else 0.45
		_protected_boss.hull = maxf(_protected_boss.hull, _protected_boss.eff_max_hull * floor_fraction)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name")) != "Fluxbreak Grey Validation":
		push_error("Run Grey checks in the isolated Fluxbreak Grey Validation project.")
		get_tree().quit(2)
		return
	# Audio playback is outside this accelerated flow test. Prevent a fresh menu
	# MP3 voice from remaining on the audio thread when the test exits at once.
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
	var run: RunDefinition = load("res://content/data/runs/greys_practice.tres") as RunDefinition
	var stage: StageDef = run.get_stage(0)
	_check(stage.get_boss_pool().size() == 2, "Practice must offer The Witness and The Veiled Mind.")
	_check(stage.completion_flow == StageDef.CompletionFlow.BOSS_FINALE, "Practice must complete on boss defeat.")
	var expected_ids: Array[String] = ["grey_probe_mk1", "grey_seeker_mk1", "grey_vessel_mk1", "grey_harbinger_mk1", "grey_mothership_mk1"]
	for wave_offset in range(expected_ids.size()):
		for sample in range(12):
			buyer.clear_history()
			var requests: Array[SpawnRequest] = buyer.buy_wave(stage.authored_enemy_budgets[wave_offset], 0, stage.wave_cards[wave_offset], stage.authored_tier_caps[wave_offset])
			var found_expected: bool = false
			var vessels: int = 0
			for request: SpawnRequest in requests:
				if request.enemy_def == null:
					continue
				_check(request.enemy_def.get_faction_id() == &"greys", "A Grey teaching wave contains another faction.")
				_check(request.enemy_def.tier <= wave_offset + 1, "A teaching wave skips its tier limit.")
				_check(not request.enemy_def is EnemyBossDef, "The regular catalog must exclude bosses.")
				if request.enemy_def.id == expected_ids[wave_offset] and request.count > 0:
					found_expected = true
				if request.enemy_def.id == "grey_vessel_mk1":
					vessels += request.count
			_check(found_expected, "Wave %d omitted its teaching enemy in sample %d." % [wave_offset + 1, sample])
			if wave_offset == 2:
				_check(vessels <= 1, "The tether introduction must contain at most one Vessel.")
	_director.wave_started.connect(_on_wave_started)
	_director.boss_wave_started.connect(_on_boss_wave_started)
	GameFlow.run_completed.connect(_on_completed)
	var menu: Control = _world.get_node("MainMenuOverlay") as Control
	menu.call("set_practice_faction_id", &"greys")
	var button: Button = menu.get_node("CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/MercPracticeContainer/MercPractice") as Button
	_check(not button.disabled, "Practice must launch Greys with the default loadout.")
	button.pressed.emit()
	run = GameFlow.get_active_run_definition()
	stage = run.get_stage(0)
	_check(run.enemy_faction != null and run.enemy_faction.get_faction_id() == &"greys", "The default faction button did not launch Greys Practice.")
	_check(is_equal_approx(_director._get_wave_timeout_sec(), 22.0) and is_equal_approx(_director._get_downtime_sec(), 5.0), "Practice must use short wave timing.")
	var hint: Label = _world.get_node("HUD/ScreenRoot/StageCombatHint") as Label
	_check(hint.visible and hint.text.contains("tether") and hint.text.contains("harmless"), "Grey counterplay instructions must be visible.")
	var elapsed: float = 0.0
	while not _director.is_boss_wave_active() and elapsed < 190.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	_check(_director.is_boss_wave_active(), "Greys Practice did not reach its boss within the short encounter window.")
	_check(_observed_waves == [1, 2, 3, 4, 5, 6], "All five teaching waves must precede the boss.")
	_check(_boss_arrival_checked, "Boss arrival must verify preservation of ordinary actors.")
	await get_tree().process_frame
	await get_tree().process_frame
	var boss: Enemy = _director._active_boss_instance
	if boss != null:
		_protected_boss = boss
		# Preservation was checked at the real boss handoff. Exercise the boss's
		# own cadence away from surviving Vessels competing for the Ship's
		# existing nonstacking active movement status.
		# Keep those actors alive and let their committed warnings end normally.
		boss.set_physics_process(false)
		_ship.global_position += Vector3.UP * 30000.0
		_ship.linear_velocity = Vector3.ZERO
		_ship.angular_velocity = Vector3.ZERO
		boss.global_position = _ship.global_position + Vector3(0, 0, -180)
		boss.linear_velocity = Vector3.ZERO
		boss.angular_velocity = Vector3.ZERO
		var warning_wait_sec: float = 0.0
		while _has_other_abilities(boss) and warning_wait_sec < 8.0:
			await get_tree().process_frame
			warning_wait_sec += get_process_delta_time()
		_check(not _has_other_abilities(boss), "Surviving enemies' committed warnings must resolve naturally before the isolated boss demonstration.")
		boss.set_physics_process(true)
		boss.explosion_scene = null
		boss.hull = boss.eff_max_hull * (0.3 if boss is GreyVeiledMind else 0.5)
		boss.shield = 0.0
		var states: Array[StringName] = []
		var saw_rupture_hud: bool = false
		var saw_tether_hud: bool = false
		var reacquired_after_shift: bool = false
		var shift_finished: bool = false
		var max_majors: int = 0
		var controller: TurretController = _ship.get_node("TurretController") as TurretController
		var warning_label: Label = _world.get_node("HUD/ScreenRoot/LockedAttackWarning") as Label
		for frame in range(2100):
			await get_tree().process_frame
			if not is_instance_valid(boss) or boss._dead:
				break
			var state: StringName = StringName(boss.call("get_attack_state"))
			if not states.has(state):
				states.append(state)
			if states.has(&"displacement") and state == &"recovery":
				shift_finished = true
			if shift_finished:
				for child: Node in _ship.find_children("*", "PlayerTurret", true, false):
					var turret: PlayerTurret = child as PlayerTurret
					if turret != null and controller.get_assigned_target(turret, turret.team_id) == boss:
						reacquired_after_shift = true
			if warning_label.visible and (warning_label.text.contains("RUPTURE") or warning_label.text.contains("COLLAPSE")):
				saw_rupture_hud = true
			if warning_label.visible and (warning_label.text.contains("TETHER") or warning_label.text.contains("CAPTURE CORRIDOR")):
				saw_tether_hud = true
			var majors: int = int(is_instance_valid(boss.get("_attack"))) + int(is_instance_valid(boss.get("_displacement"))) + int(is_instance_valid(boss.get("_tether")))
			max_majors = maxi(max_majors, majors)
			if states.has(&"tether") and states.has(&"displacement") and state == &"recovery" and saw_rupture_hud and saw_tether_hud and reacquired_after_shift:
				break
		_check(int(boss.get_meta("grey_phase", 0)) >= 2, "Grey boss did not enter its combined-durability later phase.")
		_check(states.has(&"displacement") and states.has(&"rupture") and states.has(&"tether"), "Witness must demonstrate all three distinct majors.")
		_check(max_majors == 1, "Witness overlapped its major abilities.")
		_check(saw_rupture_hud and saw_tether_hud, "The HUD omitted the actual rupture or tether warning.")
		_check(reacquired_after_shift, "Default automatic weapons failed to reacquire the relocated Witness.")
		# Verify victory cleans a live status, not just a finished countdown.
		_ship.clear_tether_slow(null, false)
		_ship._tether_immunity_sec = 0.0
		boss.call("_clear_encounter_runtime")
		boss.set("_attack_state", &"cadence")
		boss.global_position = _ship.global_position + Vector3(0, 0, -180)
		boss.call("_begin_tether", _ship)
		var live_tether: GreyTether = boss.get("_tether") as GreyTether
		if is_instance_valid(live_tether):
			live_tether._physics_process(2.0)
		_check(_ship.get_tether_source() == boss, "Victory cleanup needs a live attached Witness tether.")
		var boss_id: int = boss.get_instance_id()
		var boss_tether: WeakRef = weakref(live_tether) if is_instance_valid(live_tether) else null
		_protected_boss = null
		boss.apply_damage(boss.hull + boss.shield + 100.0)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_completed_count == 1, "Witness defeat must complete the run exactly once.")
		_check(get_tree().paused, "Victory must pause immediately despite surviving ordinary enemies.")
		_check(boss_tether != null and not is_instance_valid(boss_tether.get_ref()), "Victory must remove the boss-owned attached tether.")
		_check_live_ability_owners(boss_id)
		var remaining_source: Node3D = _ship.get_tether_source()
		_check(not is_instance_valid(remaining_source) or remaining_source.get_instance_id() != boss_id, "Victory must release the defeated boss's player status.")
		if not is_instance_valid(remaining_source):
			_check(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Without a living tether source, victory must leave no movement slow.")
	else:
		_check(false, "The stage did not spawn a Grey boss actor.")
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
		var restart_button: Button = returned_menu.get_node("CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/MercPracticeContainer/MercPractice") as Button
		returned_menu.call("set_practice_faction_id", &"greys")
		restart_button.pressed.emit()
		_check(GameFlow.get_current_stage().get_stage_id() == stage.get_stage_id() and GameFlow.get_run_faction().get_faction_id() == &"greys", "Greys Practice could not restart.")
		var restarted_director: WaveDirector = returned_world.get_node("StageRoot/WaveDirector") as WaveDirector
		_check(restarted_director.get_wave_index() == 0, "Restart retained the previous wave index.")
		GameFlow._run_active = false
		GameFlow._clear_run_progression()
		returned_world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		_check_no_world_combat()
	print("GREY PRACTICE CHECKS: %s; waves=%s; boss reached at %.1fs" % ["PASS" if _failures.is_empty() else "FAIL", str(_observed_waves), elapsed])
	call_deferred("_finish_checks")

func _on_wave_started(index: int, _enemy_budget: int, _target_budget: int) -> void:
	_observed_waves.append(index)
	if index == 6:
		_snapshot_boss_arrival()
	if index <= 5:
		var stage: StageDef = GameFlow.get_current_stage()
		_check(_director._active_card == stage.wave_cards[index - 1], "Grey teaching cards played out of order.")
		var expected_primary: Array[String] = ["grey_probe_mk1", "grey_seeker_mk1", "grey_vessel_mk1", "grey_harbinger_mk1", "grey_mothership_mk1"]
		var plan: Dictionary = _director.get_debug_snapshot().get("wave_plan", {})
		_check(str(plan.get("primary_enemy_id", "")) == expected_primary[index - 1], "A live wave chose the wrong primary role.")

func _on_completed() -> void:
	_completed_count += 1

func _mute_test_menu_music(node: Node) -> void:
	if node is AudioStreamPlayer and node.name == &"MenuMusic":
		(node as AudioStreamPlayer).stream = null

func _finish_checks() -> void:
	get_tree().quit(0 if _failures.is_empty() else 1)

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

func _has_other_abilities(boss: Enemy) -> bool:
	for group_name: String in ["enemy_attack_telegraphs", "grey_displacements", "grey_tethers"]:
		for ability: Node in get_tree().get_nodes_in_group(group_name):
			if not ability.is_queued_for_deletion() and ability.get("_source") != boss:
				return true
	return false

func _check_no_world_combat() -> void:
	for group_name: String in ["enemy_attack_telegraphs", "bug_spore_zones", "grey_displacements", "grey_tethers", "bug_brood", "merc_escorts"]:
		_check(get_tree().get_nodes_in_group(group_name).is_empty(), "World teardown left stale combat group %s." % group_name)
	for node: Node in get_tree().get_nodes_in_group("targets"):
		_check(not node is Enemy and not node is TargetObject, "World teardown must remove all old enemies and stationary targets.")
