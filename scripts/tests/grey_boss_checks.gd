extends Node3D

## Uses shipped actors and the actual Spawner without touching player saves.
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const BOSS_DEF: GreyBossDef = preload("res://content/data/enemies/grey_witness_mk1.tres")

var _ship: Ship = null
var _spawner: Spawner = null
var _bosses: Array[GreyWitness] = []
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _physics_process(delta: float) -> void:
	if is_instance_valid(_ship) and not get_tree().paused:
		# Only status timing runs on this otherwise stationary target.
		_ship._tick_tether_status(delta)

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Grey Validation":
		push_error("Grey boss checks require the isolated Fluxbreak Grey Validation project to protect player progress.")
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
	await _check_scaling_and_phase()
	await _clear_bosses()
	await _check_harmless_displacement()
	await _clear_bosses()
	await _check_rupture_dodge_snapshot_and_pause()
	await _clear_bosses()
	await _check_tether_and_sequence()
	await _clear_bosses()
	await _check_death_and_exit_cleanup()
	await _clear_bosses()
	await _check_player_loss_cleanup()
	await _clear_bosses()
	print("GREY_BOSS_CHECKS: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_boss(scaled: bool = false) -> GreyWitness:
	_ship.clear_tether_slow(null, false)
	_ship._tether_immunity_sec = 0.0
	_ship.global_position = Vector3.ZERO
	var definition: GreyBossDef = BOSS_DEF.duplicate(false) as GreyBossDef
	definition.displacement_windup_sec = 0.35
	definition.rupture_windup_sec = 0.35
	definition.tether_windup_sec = 0.35
	definition.tether_duration_sec = 0.6
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
	var boss: GreyWitness = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, definition, Vector3(0.0, 0.0, -300.0), request) as GreyWitness
	_expect(boss != null, "Shipped Witness actor spawns through the actual Spawner")
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

func _check_scaling_and_phase() -> void:
	var boss: GreyWitness = _spawn_boss(true)
	if boss == null:
		return
	_expect(is_equal_approx(boss.eff_max_hull, BOSS_DEF.max_hull * 1.5), "Witness hull inherits encounter scaling")
	_expect(boss._spawn_context.wave_index == 7 and boss._spawn_context.stage_index == 2, "Witness retains its wave and stage identity")
	_expect(not boss._weapon_sockets.is_empty(), "Shipped model exposes configured boss weapon sockets")
	for socket: BossWeaponSocket in boss._weapon_sockets:
		_expect(is_equal_approx(socket.eff_damage_min, socket.weapon.damage_min * 2.0), "Rupture socket damage inherits encounter scaling")
	_expect(BOSS_DEF.rupture_windup_sec >= 1.6 and BOSS_DEF.recovery_sec >= 2.0, "Shipped rupture warning and recovery provide readable escape windows")
	_expect(BOSS_DEF.tether_duration_sec <= 3.0 and BOSS_DEF.displacement_distance <= 190.0, "Shipped tether is bounded and relocation stays in starting weapon reach")
	boss._update_weapons(_ship, 100.0)
	_expect(not boss.is_in_second_phase(), "Elapsed time alone cannot trigger the second phase")
	_expect(boss.get_attack_state() == &"displacement", "The first major is a harmless marked relocation")
	var delay_before: float = boss._displacement._remaining_sec
	boss.apply_damage(boss.shield + boss.eff_max_hull * 0.5)
	boss._update_weapons(_ship, 0.0)
	_expect(boss.is_in_second_phase(), "Actual hull crossing 55 percent triggers phase two")
	_expect(is_equal_approx(boss._displacement._remaining_sec, delay_before), "Phase transition cannot shorten the active relocation warning")
	_expect(not is_instance_valid(boss._attack) and not is_instance_valid(boss._tether), "Phase transition cannot create an overlapping major")
	var hull_before: float = boss.hull
	boss.apply_damage(1.0)
	_expect(is_equal_approx(boss.hull, hull_before - 1.0), "Witness remains damageable during relocation and phase transition")
	await _wait(0.45)
	_expect(boss.get_attack_state() == &"recovery" and is_equal_approx(boss._state_remaining_sec, boss._grey_def.recovery_sec), "Second phase retains the complete vulnerable recovery")
	boss._update_weapons(_ship, 0.3)
	_expect(boss.get_attack_state() == &"cadence" and is_equal_approx(boss._state_remaining_sec, boss._grey_def.cadence_sec * boss._grey_def.phase_cadence_multiplier), "Second phase adds urgency only by reducing cadence")
	boss._update_weapons(_ship, 0.1)
	_expect(boss.get_attack_state() == &"rupture" and is_instance_valid(boss._attack), "The next major after relocation remains rupture")
	_expect(is_equal_approx(boss._attack.get_time_remaining(), boss._grey_def.rupture_windup_sec), "Second phase preserves the full rupture windup")

func _check_harmless_displacement() -> void:
	var boss: GreyWitness = _spawn_boss()
	if boss == null:
		return
	var health_before: float = _ship.hull + _ship.shield
	var origin: Vector3 = boss.global_position
	boss._begin_attack(_ship)
	var destination: Vector3 = boss._displacement._destination
	_expect(destination.distance_squared_to(_ship.global_position) <= 190.01 * 190.01, "The announced destination is inside automatic weapon reach")
	_expect(boss.visible and boss.get_visual_model_root().visible, "Witness stays visible and targetable during displacement")
	await _wait(0.1)
	_expect(boss.global_position.is_equal_approx(origin), "Witness cannot relocate before the arrival countdown completes")
	var remaining_before: float = boss._displacement._remaining_sec
	get_tree().paused = true
	await _wait(0.5)
	_expect(is_equal_approx(boss._displacement._remaining_sec, remaining_before), "Pausing freezes the relocation countdown")
	_expect(boss.global_position.is_equal_approx(origin), "Displacement cannot move the boss during pause")
	get_tree().paused = false
	_ship.global_position = Vector3(180.0, 120.0, 0.0)
	await _wait(0.3)
	_expect(boss.global_position.is_equal_approx(destination), "Relocation uses the announced destination despite player movement")
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Relocation is completely harmless")
	_expect(boss.get_attack_state() == &"recovery", "Relocation ends in a separate vulnerable recovery")
	boss._begin_attack(_ship)
	_expect(not is_instance_valid(boss._attack) and not is_instance_valid(boss._tether), "Recovery cannot be bypassed to begin an overlapping attack")

func _check_rupture_dodge_snapshot_and_pause() -> void:
	var boss: GreyWitness = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	boss._next_major = GreyWitness.Major.RUPTURE
	var health_before: float = _ship.hull + _ship.shield
	boss._begin_attack(_ship)
	_expect(boss._attack.get_attack_label() == "RUPTURE", "Rupture uses the shared warning and HUD label")
	await _wait(0.1)
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Rupture cannot cause damage during its warning")
	_ship.global_position = Vector3(0.0, 160.0, 0.0)
	await _wait(0.35)
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Leaving the fixed rupture sphere vertically avoids the hit")
	_expect(boss.get_attack_state() == &"recovery", "Rupture resolution starts the full recovery")
	await _clear_bosses()
	boss = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	boss._next_major = GreyWitness.Major.RUPTURE
	health_before = _ship.hull + _ship.shield
	boss._begin_attack(_ship)
	for socket: BossWeaponSocket in boss._weapon_sockets:
		socket.eff_damage_min = 999.0
		socket.eff_damage_max = 999.0
	await _wait(0.1)
	var remaining_before: float = boss._attack.get_time_remaining()
	get_tree().paused = true
	await _wait(0.5)
	_expect(is_equal_approx(boss._attack.get_time_remaining(), remaining_before), "Pausing freezes the damaging rupture countdown")
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Rupture cannot damage the target during pause")
	get_tree().paused = false
	await _wait(0.3)
	_expect(is_equal_approx(health_before - _ship.hull - _ship.shield, 12.0), "Rupture resolves exactly one captured weapon hit despite later socket changes")
	await _wait(0.3)
	_expect(is_equal_approx(health_before - _ship.hull - _ship.shield, 12.0), "Rupture flash and recovery cannot cause extra damage")

func _check_tether_and_sequence() -> void:
	var boss: GreyWitness = _spawn_boss()
	if boss == null:
		return
	boss._next_major = GreyWitness.Major.TETHER
	var health_before: float = _ship.hull + _ship.shield
	boss._begin_attack(_ship)
	_expect(boss.get_attack_state() == &"tether" and not is_instance_valid(boss._attack), "Tether acquisition is a separate harmless major")
	await _wait(0.1)
	_expect(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Tether cannot slow the target before its warning completes")
	await _wait(0.3)
	_expect(is_instance_valid(boss._tether) and boss._tether.is_attached(), "Remaining in the marked tether sphere permits attachment")
	_expect(is_equal_approx(_ship.get_movement_slow_multiplier(), 0.7), "Witness tether uses a bounded movement slow")
	_expect(_ship.get_tether_source() == boss, "Ship tracks the actual Witness as its single tether source")
	boss._update_weapons(_ship, 100.0)
	_expect(boss.get_attack_state() == &"tether" and not is_instance_valid(boss._attack) and not is_instance_valid(boss._displacement), "An attached tether blocks every other major regardless of elapsed cadence")
	_ship.global_position = Vector3(800.0, 0.0, 0.0)
	await _wait(0.05)
	_expect(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Flying beyond break distance immediately restores movement")
	_expect(_ship.is_tether_immune(), "Breaking the boss tether grants brief protection from another source")
	_expect(boss.get_attack_state() == &"recovery", "A broken link starts the complete recovery")
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Acquiring and breaking the tether causes no damage")
	await _clear_bosses()
	boss = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	boss._state_remaining_sec = 0.0
	boss.set_physics_process(true)
	var seen_states: Array[StringName] = []
	var peak_majors: int = 0
	for frame in range(220):
		if not seen_states.has(boss.get_attack_state()):
			seen_states.append(boss.get_attack_state())
		var active_count: int = int(is_instance_valid(boss._attack)) + int(is_instance_valid(boss._displacement)) + int(is_instance_valid(boss._tether))
		peak_majors = maxi(peak_majors, active_count)
		await get_tree().physics_frame
	_expect(seen_states.has(&"displacement") and seen_states.has(&"rupture") and seen_states.has(&"tether") and seen_states.has(&"recovery"), "Live boss processing runs all three majors with recovery between them")
	_expect(peak_majors == 1, "The live Witness never overlaps its major abilities")
	_expect(not is_instance_valid(boss._tether), "The bounded tether interval expires before the next major")
	boss.set_physics_process(false)

func _check_death_and_exit_cleanup() -> void:
	for major: int in [GreyWitness.Major.DISPLACEMENT, GreyWitness.Major.RUPTURE, GreyWitness.Major.TETHER]:
		var boss: GreyWitness = _spawn_boss()
		if boss == null:
			return
		_make_socket_deterministic(boss)
		boss._next_major = major
		var health_before: float = _ship.hull + _ship.shield
		boss._begin_attack(_ship)
		await _wait(0.1)
		boss.apply_damage(1000000.0)
		await _wait(0.4)
		_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Killing the Witness cancels pending major %d without damage" % major)
		_expect(int(_spawner.get_alive_counts()["enemies"]) == 0, "Death during major %d cleans actual Spawner accounting" % major)
		_expect(get_tree().get_nodes_in_group("grey_displacements").is_empty() and get_tree().get_nodes_in_group("grey_tethers").is_empty() and get_tree().get_nodes_in_group("enemy_attack_telegraphs").is_empty(), "Death during major %d removes every associated warning and link" % major)
	var linked_boss: GreyWitness = _spawn_boss()
	if linked_boss == null:
		return
	linked_boss._next_major = GreyWitness.Major.TETHER
	linked_boss._begin_attack(_ship)
	await _wait(0.4)
	_expect(_ship.get_tether_source() == linked_boss, "Exit cleanup begins with an actual attached boss tether")
	linked_boss.queue_free()
	await _wait(0.1)
	_expect(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Boss scene exit immediately restores the target's movement")
	_expect(get_tree().get_nodes_in_group("grey_tethers").is_empty() and int(_spawner.get_alive_counts()["enemies"]) == 0, "Boss scene exit cleans linked warnings and Spawner accounting")

func _check_player_loss_cleanup() -> void:
	for hidden_target: bool in [false, true]:
		for action_index: int in range(4):
			var boss: GreyWitness = _spawn_boss()
			if boss == null:
				return
			var major: int = mini(action_index, GreyWitness.Major.TETHER)
			boss._next_major = major
			boss._begin_attack(_ship)
			await _wait(0.4 if action_index == 3 else 0.1)
			var health_before: float = _ship.hull + _ship.shield
			_ship.visible = not hidden_target
			_ship._dead = not hidden_target
			boss._physics_process(0.01)
			_expect(not is_instance_valid(boss._attack) and not is_instance_valid(boss._displacement) and not is_instance_valid(boss._tether), "Player loss cancels pending or attached Witness action %d" % action_index)
			await _wait(0.4)
			_expect(is_equal_approx(health_before, _ship.hull + _ship.shield), "Cancelled Witness action cannot damage a lost player")
			_expect(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Player loss clears an attached Witness slow")
			_ship._dead = false
			_ship.visible = true
			await _clear_bosses()

func _make_socket_deterministic(boss: GreyWitness) -> void:
	for socket: BossWeaponSocket in boss._weapon_sockets:
		socket.eff_base_accuracy = 1.0
		socket.eff_range_falloff = 0.0
		socket.eff_crit_chance = 0.0
		socket.eff_graze_on_hit = 0.0
		socket.eff_graze_on_miss = 0.0
		socket.eff_damage_min = 12.0
		socket.eff_damage_max = 12.0

func _clear_bosses() -> void:
	for boss: GreyWitness in _bosses:
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
		push_error("GREY_BOSS_CHECKS: " + description)
