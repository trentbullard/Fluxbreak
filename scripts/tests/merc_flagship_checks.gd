extends Node3D

## Exercises the shipped flagship, real spawn accounting, and locked attacks.
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const BOSS_DEF: MercFlagshipDef = preload("res://content/data/enemies/merc_vanguard_flagship_mk1.tres")
const CORVETTE_DEF: MercEnemyDef = preload("res://content/data/enemies/merc_corvette_mk1.tres")

var _ship: Ship = null
var _spawner: Spawner = null
var _bosses: Array[MercFlagship] = []
var _other_enemies: Array[Enemy] = []
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_silence_audio)
	call_deferred("_run_checks")

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Merc Validation":
		push_error("Flagship checks require the isolated Fluxbreak Merc Validation project to protect player progress.")
		get_tree().quit(2)
		return
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "TestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.eff_damage_taken_mult = 1.0
	_ship.eff_evasion = 0.0
	_ship.hull = 100000.0
	_ship.shield = 100000.0
	_spawner = Spawner.new()
	_spawner.name = "TestSpawner"
	_spawner.ship_path = NodePath("../TestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.directed_mode = true
	add_child(_spawner)
	await _check_scaling_and_transitions()
	await _clear_enemies()
	await _check_distinct_sequences()
	await _clear_enemies()
	await _check_locked_damage_and_pause()
	await _clear_enemies()
	await _check_finite_wings_and_support()
	await _clear_enemies()
	await _check_death_and_exit_cleanup()
	await _clear_enemies()
	print("MERC_FLAGSHIP_CHECKS: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_boss(scaled: bool = false) -> MercFlagship:
	_ship.global_position = Vector3.ZERO
	var definition: MercFlagshipDef = BOSS_DEF.duplicate(false) as MercFlagshipDef
	definition.initial_delay_sec = 10.0
	definition.broadside_windup_sec = 0.25
	definition.salvo_windup_sec = 0.25
	definition.recovery_sec = 0.2
	definition.cadence_sec = 0.1
	var request: SpawnRequest = SpawnRequest.new()
	request.enemy_def = definition
	request.wave_index = 30
	request.stage_index = 2
	if scaled:
		var scaling: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
		scaling.hull_multiplier = 1.5
		scaling.damage_multiplier = 2.0
		request.enemy_combat_scaling = scaling
	var boss: MercFlagship = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, definition, Vector3(0.0, 0.0, -300.0), request) as MercFlagship
	_expect(boss != null, "The shipped Vanguard Flagship spawns through the actual Spawner")
	if boss == null:
		return null
	boss.freeze = true
	boss.explosion_scene = null
	boss.process_mode = Node.PROCESS_MODE_PAUSABLE
	boss.set_physics_process(false)
	_bosses.append(boss)
	return boss

func _check_scaling_and_transitions() -> void:
	var boss: MercFlagship = _spawn_boss(true)
	if boss == null:
		return
	_expect(is_equal_approx(boss.eff_max_hull, BOSS_DEF.max_hull * 1.5), "Flagship hull inherits campaign spawn scaling")
	_expect(boss._spawn_context.wave_index == 30 and boss._spawn_context.stage_index == 2, "Flagship retains its wave and stage identity")
	_expect(boss.collision_layer == 8 and boss.collision_mask == 0, "Flagship retains targeting without physical ship collision")
	_expect(boss._weapon_sockets.size() == 4, "The shipped model exposes dedicated broadside and salvo sockets")
	for socket: BossWeaponSocket in boss._weapon_sockets:
		_expect(is_equal_approx(socket.eff_damage_min, socket.weapon.damage_min * 2.0), "Each flagship socket inherits encounter damage scaling")
	_expect(BOSS_DEF.broadside_windup_sec >= 1.6 and BOSS_DEF.salvo_windup_sec >= 1.5 and BOSS_DEF.recovery_sec >= 1.8, "Shipped attacks leave readable warning and recovery windows")
	_expect(BOSS_DEF.movement_def.locomotion_profile.preferred_distance <= 350.0, "Flagship movement stays within starter weapon reach")
	boss._update_weapons(_ship, 100.0)
	_freeze_escorts(boss)
	_expect(boss.get_phase() == 1 and boss.get_attack_state() == &"windup", "Elapsed time alone leaves the boss in its first phase")
	_expect(boss._attack.get_attack_label() == "HEAVY BROADSIDE", "The first major announces the heavy broadside")
	var warning_before: float = boss._attack.get_time_remaining()
	boss.apply_damage(boss.shield + boss.eff_max_hull * 0.31)
	boss._update_weapons(_ship, 0.0)
	_freeze_escorts(boss)
	_expect(boss.get_phase() == 2 and int(boss.get_meta("flagship_phase")) == 2, "Crossing 70 percent hull enters the second phase")
	_expect(is_equal_approx(boss._attack.get_time_remaining(), warning_before), "Second phase cannot shorten an already committed warning")
	_expect(boss.get_living_escort_count() <= BOSS_DEF.escort_living_cap, "Phase reserves respect the shared living escort cap")
	var hull_before: float = boss.hull
	boss.apply_damage(1.0)
	_expect(is_equal_approx(boss.hull, hull_before - 1.0), "Flagship remains damageable during an active warning and phase transition")
	await _wait(0.32)
	_expect(boss.get_attack_state() == &"recovery" and is_equal_approx(boss._state_remaining_sec, boss._flagship_def.recovery_sec), "Every attack ends in the full vulnerable recovery")
	boss._update_weapons(_ship, 0.21)
	_expect(boss.get_attack_state() == &"cadence" and is_equal_approx(boss._state_remaining_sec, boss._flagship_def.cadence_sec * boss._flagship_def.phase_two_cadence_multiplier), "Second phase changes cadence after recovery")
	boss._update_weapons(_ship, 0.11)
	warning_before = boss._attack.get_time_remaining()
	boss.apply_damage(boss.eff_max_hull * 0.36)
	boss._update_weapons(_ship, 0.0)
	_expect(boss.get_phase() == 3, "Crossing 35 percent hull enters the final phase")
	_expect(is_equal_approx(boss._attack.get_time_remaining(), warning_before), "Final phase also preserves an active warning")
	await _wait(0.32)
	boss._update_weapons(_ship, 0.21)
	_expect(is_equal_approx(boss._state_remaining_sec, boss._flagship_def.cadence_sec * boss._flagship_def.phase_three_cadence_multiplier), "Final phase shortens only the cadence interval")
	boss._update_weapons(_ship, 0.11)
	_expect(boss._attack.get_attack_label() == "VANGUARD SALVO" and is_equal_approx(boss._attack.get_time_remaining(), boss._flagship_def.salvo_windup_sec), "Final phase begins its distinct sequence with a full salvo warning")

func _check_distinct_sequences() -> void:
	var expected_sequences: Array[Array] = [
		["HEAVY BROADSIDE", "VANGUARD SALVO"],
		["HEAVY BROADSIDE", "VANGUARD SALVO", "HEAVY BROADSIDE"],
		["VANGUARD SALVO", "HEAVY BROADSIDE", "HEAVY BROADSIDE", "VANGUARD SALVO"]
	]
	for phase_index: int in range(3):
		await _clear_enemies()
		var boss: MercFlagship = _spawn_boss()
		if boss == null:
			return
		if phase_index > 0:
			boss.apply_damage(boss.shield + boss.eff_max_hull * (0.4 if phase_index == 1 else 0.7))
		var seen: Array[String] = []
		for expected: String in expected_sequences[phase_index]:
			boss._update_weapons(_ship, 100.0)
			_freeze_escorts(boss)
			if not is_instance_valid(boss._attack):
				_expect(false, "Phase %d starts its next major" % (phase_index + 1))
				return
			seen.append(boss._attack.get_attack_label())
			var started_before: int = boss.get_attacks_started()
			boss._begin_attack(_ship)
			_expect(boss.get_attacks_started() == started_before, "Phase %d cannot overlap a second major" % (phase_index + 1))
			await _wait(0.32)
			_expect(boss.get_attack_state() == &"recovery", "Phase %d keeps a recovery between majors" % (phase_index + 1))
			boss._update_weapons(_ship, 100.0)
		_expect(seen == expected_sequences[phase_index], "Phase %d executes its distinct authored broadside/salvo order" % (phase_index + 1))

func _check_locked_damage_and_pause() -> void:
	var boss: MercFlagship = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	boss._update_weapons(_ship, 100.0)
	_freeze_escorts(boss)
	var health_before: float = _ship.hull + _ship.shield
	await _wait(0.08)
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Broadside cannot damage the target during its warning")
	_ship.global_position.y = 200.0
	await _wait(0.25)
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Moving vertically out of the fixed broadside corridor avoids all damage")
	await _clear_enemies()
	boss = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	boss._major_index = 1
	boss._update_weapons(_ship, 100.0)
	_freeze_escorts(boss)
	_expect(boss._attack.get_attack_label() == "VANGUARD SALVO", "The salvo uses a separately marked locked sphere")
	for socket: BossWeaponSocket in boss._weapon_sockets:
		socket.eff_damage_min = 999.0
		socket.eff_damage_max = 999.0
	await _wait(0.08)
	var remaining: float = boss._attack.get_time_remaining()
	get_tree().paused = true
	await _wait(0.4)
	_expect(is_equal_approx(boss._attack.get_time_remaining(), remaining), "Pause freezes the flagship's attack countdown")
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Paused flagship attacks cannot damage the player")
	get_tree().paused = false
	await _wait(0.25)
	_expect(is_equal_approx(health_before - _ship.hull - _ship.shield, 12.0), "Salvo resolves one captured hit rather than reading later weapon changes")
	await _wait(0.25)
	_expect(is_equal_approx(health_before - _ship.hull - _ship.shield, 12.0), "The release flash cannot cause repeated hits")
	await _clear_enemies()
	boss = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	boss._major_index = 1
	boss._update_weapons(_ship, 100.0)
	_freeze_escorts(boss)
	health_before = _ship.hull + _ship.shield
	_ship.global_position = Vector3(200.0, 200.0, 0.0)
	await _wait(0.32)
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Leaving the separately marked salvo sphere also avoids all damage")

func _check_finite_wings_and_support() -> void:
	var boss: MercFlagship = _spawn_boss(true)
	if boss == null:
		return
	boss._update_weapons(_ship, 0.0)
	_freeze_escorts(boss)
	_expect(boss.get_living_escort_count() == 2 and boss.get_total_escorts_spawned() == 2, "Arrival requests exactly one finite two-ship wing")
	_expect(int(_spawner.get_alive_counts()["enemies"]) == 3, "Real Spawner accounting includes the boss and its arrival wing")
	var escorts: Array[Enemy] = boss._escort_wing.get_living_escorts()
	for escort: Enemy in escorts:
		_expect(escort._spawn_context.is_summoned and not escort._spawn_context.grants_kill_rewards and not escort._spawn_context.contributes_to_pressure, "Each flagship escort is excluded from rewards and adaptive kill pressure")
		_expect(is_equal_approx(escort.eff_max_hull, escort.def.max_hull * 1.5), "Flagship escorts inherit encounter scaling")
	var outsider: Enemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, CORVETTE_DEF, Vector3(40.0, 0.0, -300.0)) as Enemy
	_other_enemies.append(outsider)
	_freeze_enemy(outsider)
	outsider.shield = 0.0
	boss.shield = 0.0
	var boss_hull: float = boss.hull
	for escort: Enemy in escorts:
		escort.shield = 0.0
	boss._restore_escort_shields()
	for escort: Enemy in escorts:
		_expect(is_equal_approx(escort.shield, minf(escort.eff_max_shield, boss._flagship_def.escort_shield_restore)), "Shield support restores a bounded amount and cannot overfill an escort")
	_expect(is_zero_approx(outsider.shield) and is_zero_approx(boss.shield) and is_equal_approx(boss.hull, boss_hull), "Flagship support cannot heal itself or unrelated Merc ships")
	escorts[0].global_position = boss.global_position + Vector3(1500.0, 0.0, 0.0)
	for escort: Enemy in escorts:
		escort.shield = 0.0
	boss._support_remaining_sec = 0.2
	boss._update_weapons(_ship, 0.1)
	_expect(is_zero_approx(escorts[1].shield), "Escort shielding waits for the support interval")
	boss._update_weapons(_ship, 0.11)
	_expect(is_zero_approx(escorts[0].shield) and escorts[1].shield > 0.0, "Support pulse affects owned escorts only while they are inside support range")
	escorts[1].shield = 0.0
	boss._update_weapons(_ship, 0.1)
	_expect(is_zero_approx(escorts[1].shield), "A support pulse cannot become continuous shield regeneration")
	var score_before: int = RunState.run_score
	var pressure_before: float = CombatStats._frame_enemy_kill_pressure
	for escort: Enemy in escorts:
		escort.apply_damage(1000000.0)
	await _wait(0.08)
	_expect(RunState.run_score == score_before and is_equal_approx(CombatStats._frame_enemy_kill_pressure, pressure_before), "Killing flagship escorts grants no score or adaptive kill-pressure credit")
	boss._update_weapons(_ship, 0.0)
	_expect(boss.get_living_escort_count() == 0 and boss.get_total_escorts_spawned() == 2, "Destroyed escorts are not replaced between phase transitions")
	boss.apply_damage(boss.eff_max_hull * 0.4)
	boss._update_weapons(_ship, 0.0)
	_freeze_escorts(boss)
	_expect(boss.get_living_escort_count() == 2 and boss.get_total_escorts_spawned() == 4, "Second phase can request its own single reserve wing")
	for escort: Enemy in boss._escort_wing.get_living_escorts():
		escort.apply_damage(1000000.0)
	await _wait(0.08)
	boss.apply_damage(boss.eff_max_hull * 0.3)
	boss._update_weapons(_ship, 0.0)
	_freeze_escorts(boss)
	_expect(boss.get_living_escort_count() == 2 and boss.get_total_escorts_spawned() == 6, "Final phase consumes the last finite reserve wing")
	for escort: Enemy in boss._escort_wing.get_living_escorts():
		escort.apply_damage(1000000.0)
	await _wait(0.08)
	boss._request_escort_wing()
	_expect(boss.get_living_escort_count() == 0 and boss.get_total_escorts_spawned() == 6, "No phase or request can bypass the shared six-escort lifetime cap")

func _check_death_and_exit_cleanup() -> void:
	for direct_exit: bool in [false, true]:
		await _clear_enemies()
		var boss: MercFlagship = _spawn_boss()
		if boss == null:
			return
		_make_socket_deterministic(boss)
		boss._update_weapons(_ship, 100.0)
		_freeze_escorts(boss)
		_expect(boss.get_living_escort_count() == 2 and is_instance_valid(boss._attack), "Cleanup begins with live escorts and a pending damaging warning")
		var health_before: float = _ship.hull + _ship.shield
		if direct_exit:
			boss.queue_free()
		else:
			boss.apply_damage(1000000.0)
		await _wait(0.4)
		_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Boss %s cancels pending damage" % ("exit" if direct_exit else "death"))
		_expect(get_tree().get_nodes_in_group("enemy_attack_telegraphs").is_empty() and get_tree().get_nodes_in_group("merc_escorts").is_empty(), "Boss %s removes its warning and all owned escorts" % ("exit" if direct_exit else "death"))
		_expect(int(_spawner.get_alive_counts()["enemies"]) == 0, "Boss %s returns real Spawner accounting to zero" % ("exit" if direct_exit else "death"))

func _freeze_escorts(boss: MercFlagship) -> void:
	for escort: Enemy in boss._escort_wing.get_living_escorts():
		_freeze_enemy(escort)

func _freeze_enemy(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	enemy.freeze = true
	enemy.explosion_scene = null
	enemy.set_physics_process(false)
	var turret: EnemyTurret = enemy.get_node_or_null("Turret") as EnemyTurret
	if is_instance_valid(turret):
		turret.set_physics_process(false)

func _make_socket_deterministic(boss: MercFlagship) -> void:
	for socket: BossWeaponSocket in boss._weapon_sockets:
		socket.eff_base_accuracy = 1.0
		socket.eff_range_falloff = 0.0
		socket.eff_crit_chance = 0.0
		socket.eff_graze_on_hit = 0.0
		socket.eff_graze_on_miss = 0.0
		socket.eff_damage_min = 12.0
		socket.eff_damage_max = 12.0

func _clear_enemies() -> void:
	get_tree().paused = false
	for boss: MercFlagship in _bosses:
		if is_instance_valid(boss) and not boss.is_queued_for_deletion():
			boss.queue_free()
	_bosses.clear()
	for enemy: Enemy in _other_enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			enemy.queue_free()
	_other_enemies.clear()
	await _wait(0.1)

func _silence_audio(node: Node) -> void:
	if node is AudioStreamPlayer3D:
		var player_3d: AudioStreamPlayer3D = node as AudioStreamPlayer3D
		player_3d.stream = null
	elif node is AudioStreamPlayer:
		var player: AudioStreamPlayer = node as AudioStreamPlayer
		player.stream = null

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("MERC_FLAGSHIP_CHECKS: " + description)
