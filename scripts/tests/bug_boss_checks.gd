extends Node3D

## Uses shipped actors and the actual Spawner in an isolated save directory.
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const BOSS_DEF: BugBossDef = preload("res://content/data/enemies/bug_nestbreaker_matron_mk1.tres")

var _ship: Ship = null
var _spawner: Spawner = null
var _bosses: Array[NestbreakerMatron] = []
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Bug Validation":
		push_error("Bug boss checks require the isolated Fluxbreak Bug Validation project to protect player progress.")
		get_tree().quit(2)
		return
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "TestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.eff_damage_taken_mult = 1.0
	_ship.eff_evasion = 0.0
	_ship.hull = 10000.0
	_ship.shield = 10000.0
	_spawner = Spawner.new()
	_spawner.name = "TestSpawner"
	_spawner.ship_path = NodePath("../TestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.directed_mode = true
	add_child(_spawner)
	await _check_scaled_pipeline_and_phase()
	await _clear_bosses()
	await _check_locked_charge_and_movement()
	await _clear_bosses()
	await _check_brood_release_and_pause()
	await _clear_bosses()
	await _check_repeated_releases_and_no_farming()
	await _clear_bosses()
	await _check_multiple_sources_and_recursion()
	await _clear_bosses()
	await _check_death_and_exit_cleanup()
	await _clear_bosses()
	print("BUG_BOSS_CHECKS: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_boss(scaled: bool = false) -> NestbreakerMatron:
	_ship.global_position = Vector3.ZERO
	var definition: BugBossDef = BOSS_DEF.duplicate(false) as BugBossDef
	definition.charge_windup_sec = 0.35
	definition.charge_move_sec = 0.25
	definition.brood_windup_sec = 0.35
	definition.recovery_sec = 0.25
	definition.cadence_sec = 0.1
	var request: SpawnRequest = SpawnRequest.new()
	request.enemy_def = definition
	request.wave_index = 7
	request.stage_index = 2
	if scaled:
		var scaling: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
		scaling.hull_multiplier = 1.5
		scaling.damage_multiplier = 2.0
		request.enemy_combat_scaling = scaling
	var boss: NestbreakerMatron = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, definition, Vector3(0.0, 0.0, -340.0), request) as NestbreakerMatron
	_expect(boss != null, "Shipped Matron actor spawns through the real Spawner")
	if boss == null:
		return null
	boss.freeze = true
	boss.explosion_scene = null
	boss.process_mode = Node.PROCESS_MODE_PAUSABLE
	boss.set_physics_process(false)
	boss.collision_layer = 0
	boss.collision_mask = 0
	_bosses.append(boss)
	return boss

func _check_scaled_pipeline_and_phase() -> void:
	var boss: NestbreakerMatron = _spawn_boss(true)
	if boss == null:
		return
	_expect(is_equal_approx(boss.eff_max_hull, BOSS_DEF.max_hull * 1.5), "Matron hull inherits encounter scaling")
	_expect(not boss._weapon_sockets.is_empty(), "Shipped Matron model exposes a configured boss weapon socket")
	for socket: BossWeaponSocket in boss._weapon_sockets:
		_expect(is_equal_approx(socket.eff_damage_min, socket.weapon.damage_min * 2.0), "Matron socket damage inherits encounter scaling")
	_expect(BOSS_DEF.charge_windup_sec >= 1.8 and BOSS_DEF.recovery_sec >= 2.0, "Shipped charge warning and recovery leave readable escape windows")
	boss._update_weapons(_ship, 100.0)
	_expect(not boss.is_in_second_phase(), "Elapsed time cannot trigger phase two while hull remains full")
	if is_instance_valid(boss._attack):
		boss._attack.cancel()
		boss._attack = null
	boss._begin_recovery()
	boss.apply_damage(boss.shield + boss.eff_max_hull * 0.5)
	boss._update_weapons(_ship, 0.0)
	_expect(boss.is_in_second_phase(), "Actual hull crossing 55 percent starts phase two")
	var hull_before: float = boss.hull
	boss.apply_damage(1.0)
	_expect(is_equal_approx(boss.hull, hull_before - 1.0), "The Matron remains damageable during phase transition and recovery")
	boss._next_charge = false
	boss._begin_attack(_ship)
	var windup_before: float = boss._state_remaining_sec
	boss._update_weapons(_ship, 0.1)
	_expect(windup_before >= 0.35 and boss._state_remaining_sec < windup_before, "Phase two retains the full brood windup")
	_expect(boss.get_brood_spawner().get_living_count() == 0, "Phase entry does not overlap a surprise brood spawn with the current attack")
	boss._update_weapons(_ship, 0.3)
	_quiet_brood()
	_expect(boss.get_brood_spawner().get_living_count() == BOSS_DEF.phase_brood_release_count, "Phase two releases four brood only after its full windup")
	_expect(boss.get_attack_state() == &"recovery" and is_equal_approx(boss._state_remaining_sec, boss._bug_def.recovery_sec), "Phase two retains the complete vulnerable recovery")
	boss._update_weapons(_ship, 0.3)
	_expect(boss.get_attack_state() == &"cadence" and is_equal_approx(boss._state_remaining_sec, boss._bug_def.cadence_sec * boss._bug_def.phase_cadence_multiplier), "Phase two adds urgency only by shortening its next cadence")
	await get_tree().process_frame

func _check_locked_charge_and_movement() -> void:
	var boss: NestbreakerMatron = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	var health_before: float = _ship.hull + _ship.shield
	boss._begin_attack(_ship)
	_expect(is_instance_valid(boss._attack) and boss._attack.get_attack_label() == "CHARGE", "Matron charge uses the shared warning and HUD label")
	await _wait(0.12)
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Charge cannot hurt the player during its warning")
	var locked_destination: Vector3 = boss._charge_destination
	_ship.global_position = Vector3(170.0, 160.0, 0.0)
	boss.freeze = false
	var start_position: Vector3 = boss.global_position
	await _wait(0.33)
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Leaving the Matron's locked corridor vertically avoids all charge damage")
	_expect(boss.get_attack_state() == &"charge", "Warning resolution starts the committed charge movement")
	_expect(boss._charge_destination.is_equal_approx(locked_destination), "Moving the player cannot redirect the committed charge destination")
	_expect(boss.global_position.z > start_position.z + 25.0, "Matron physically travels along her committed corridor after warning resolution")
	_expect(absf(boss.linear_velocity.x) < 0.01 and absf(boss.linear_velocity.y) < 0.01, "Charging Matron cannot steer toward the escaped player")
	boss._update_weapons(_ship, 0.3)
	_expect(boss.get_attack_state() == &"recovery" and boss.linear_velocity.is_zero_approx(), "Charge travel ends with a stationary vulnerable recovery")
	boss.freeze = true
	await _clear_bosses()
	boss = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	health_before = _ship.hull + _ship.shield
	boss._begin_attack(_ship)
	await _wait(0.45)
	_expect(is_equal_approx(health_before - _ship.hull - _ship.shield, 12.0), "Remaining in the charge corridor resolves exactly one configured hit")
	await _wait(0.3)
	_expect(is_equal_approx(health_before - _ship.hull - _ship.shield, 12.0), "Committed charge movement cannot apply an extra contact hit")

func _check_brood_release_and_pause() -> void:
	var boss: NestbreakerMatron = _spawn_boss()
	if boss == null:
		return
	boss._next_charge = false
	var health_before: float = _ship.hull + _ship.shield
	var original_scale: Vector3 = boss.get_visual_model_root().scale
	boss._begin_attack(_ship)
	_expect(boss.get_attack_state() == &"brood" and not is_instance_valid(boss._attack), "Brood release is a separate harmless summon windup")
	boss.set_physics_process(true)
	await _wait(0.1)
	_expect(boss.get_visual_model_root().scale.x > original_scale.x and is_instance_valid(boss._brood_warning), "Matron visibly swells and displays her brood countdown")
	var remaining_before: float = boss._state_remaining_sec
	get_tree().paused = true
	await _wait(0.5)
	_expect(is_equal_approx(boss._state_remaining_sec, remaining_before), "Pausing freezes the brood windup")
	_expect(boss.get_brood_spawner().get_total_spawned() == 0, "Brood cannot spawn while the encounter is paused")
	get_tree().paused = false
	await _wait(0.1)
	_expect(boss.get_brood_spawner().get_total_spawned() == 0, "Unpausing preserves the unfinished brood countdown")
	await _wait(0.22)
	boss.set_physics_process(false)
	_quiet_brood()
	_expect(boss.get_brood_spawner().get_total_spawned() == BOSS_DEF.brood_release_count, "Completed phase one windup releases exactly three brood through the real Spawner")
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Brood release causes no unmarked damage")
	_expect(boss.get_visual_model_root().scale.is_equal_approx(original_scale), "Brood release restores the Matron's normal silhouette")
	_expect(boss._next_charge, "The attack after a brood release is another readable charge")

func _check_repeated_releases_and_no_farming() -> void:
	var boss: NestbreakerMatron = _spawn_boss(true)
	if boss == null:
		return
	var brood: BugBroodSpawner = boss.get_brood_spawner()
	for release: int in range(6):
		_expect(brood.spawn_brood(BOSS_DEF.brood_release_count) == BOSS_DEF.brood_release_count, "Matron launches its full batch without living or lifetime caps")
	_quiet_brood()
	_expect(brood.get_total_spawned() == 18 and brood.get_living_count() == 18, "Matron retains more than its former sixteen lifetime brood")
	for node: Node in get_tree().get_nodes_in_group("bug_brood"):
		var child: Enemy = node as Enemy
		_expect(child._spawn_context.is_summoned and not child._spawn_context.grants_kill_rewards and not child._spawn_context.contributes_to_pressure, "Summoned brood carries explicit reward and pressure exclusions")
		_expect(child._spawn_context.wave_index == 7 and child._spawn_context.stage_index == 2 and is_equal_approx(child.eff_max_hull, child.def.max_hull * 1.5), "Brood inherits the Matron's encounter scaling")
	var score_before: int = RunState.run_score
	var drops_before: int = _count_drops()
	var meta_kills_before: int = GameFlow._run_enemy_kills
	var pressure_before: float = CombatStats._frame_enemy_kills
	for node: Node in get_tree().get_nodes_in_group("bug_brood"):
		(node as Enemy).apply_damage(1000000.0)
	_expect(RunState.run_score == score_before, "Killing brood cannot farm score")
	_expect(_count_drops() == drops_before, "Killing brood cannot farm nanobot drops")
	_expect(GameFlow._run_enemy_kills == meta_kills_before, "Killing brood cannot farm persistent enemy kill progress")
	_expect(is_equal_approx(CombatStats._frame_enemy_kills, pressure_before), "Killing brood cannot inflate wave pressure metrics")
	await _wait(0.1)
	_expect(int(_spawner.get_alive_counts()["enemies"]) == 1, "Dead brood leaves real Spawner accounting clean")
	_expect(brood.spawn_brood(3) == 3, "A Matron continues releasing after earlier brood is killed")
	_quiet_brood()

func _check_multiple_sources_and_recursion() -> void:
	var first: NestbreakerMatron = _spawn_boss()
	var second: NestbreakerMatron = _spawn_boss()
	if first == null or second == null:
		return
	for release: int in range(9):
		_expect(first.get_brood_spawner().spawn_brood(3) == 3, "First mother retains its requested release size")
		_expect(second.get_brood_spawner().spawn_brood(3) == 3, "Second mother is not blocked by shared living minion limits")
		_quiet_brood()
	_expect(int(_spawner.get_alive_counts()["enemies"]) == 56, "Brood remains fully accounted beyond the former fifty-enemy summon ceiling")
	var child: Enemy = get_tree().get_nodes_in_group("bug_brood")[0] as Enemy
	var recursive_spawner: BugBroodSpawner = BugBroodSpawner.new()
	child.add_child(recursive_spawner)
	recursive_spawner.setup(child, BOSS_DEF.brood_child_def)
	_expect(recursive_spawner.spawn_brood(3) == 0, "A summoned child cannot recursively produce its own brood")

func _check_death_and_exit_cleanup() -> void:
	var boss: NestbreakerMatron = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	boss.get_brood_spawner().spawn_brood(2)
	_quiet_brood()
	boss._begin_attack(_ship)
	var attack: EnemyAttackTelegraph = boss._attack
	var health_before: float = _ship.hull + _ship.shield
	await _wait(0.1)
	boss.apply_damage(1000000.0)
	await _wait(0.5)
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Killing the Matron during charge windup cancels her damage")
	_expect(not is_instance_valid(attack), "Matron death removes her pending charge warning")
	_expect(int(_spawner.get_alive_counts()["enemies"]) == 2, "Matron death preserves her two living brood in Spawner accounting")
	boss = _spawn_boss()
	if boss == null:
		return
	boss.get_brood_spawner().spawn_brood(2)
	_quiet_brood()
	boss._next_charge = false
	boss._begin_attack(_ship)
	boss.queue_free()
	await _wait(0.5)
	_expect(int(_spawner.get_alive_counts()["enemies"]) == 4, "Removing a Matron cancels its unfinished release while existing brood persists")

func _make_socket_deterministic(boss: NestbreakerMatron) -> void:
	for socket: BossWeaponSocket in boss._weapon_sockets:
		socket.eff_base_accuracy = 1.0
		socket.eff_range_falloff = 0.0
		socket.eff_crit_chance = 0.0
		socket.eff_graze_on_hit = 0.0
		socket.eff_graze_on_miss = 0.0
		socket.eff_damage_min = 12.0
		socket.eff_damage_max = 12.0

func _quiet_brood() -> void:
	for node: Node in get_tree().get_nodes_in_group("bug_brood"):
		var child: Enemy = node as Enemy
		child.freeze = true
		child.process_mode = Node.PROCESS_MODE_DISABLED
		child.explosion_scene = null

func _count_drops() -> int:
	var count: int = 0
	for child: Node in get_children():
		if child is NanobotSwarm:
			count += 1
	return count

func _clear_bosses() -> void:
	for child: Node in get_tree().get_nodes_in_group("bug_brood"):
		child.queue_free()
	for boss: NestbreakerMatron in _bosses:
		if is_instance_valid(boss) and not boss.is_queued_for_deletion():
			boss.queue_free()
	_bosses.clear()
	await _wait(0.1)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("BUG_BOSS_CHECKS: " + description)
