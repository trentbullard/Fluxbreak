extends Node3D

## Exercises shipped boss actors and shared status helpers without player saves.
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const BOSS_DEF: GreyMindDef = preload("res://content/data/enemies/grey_veiled_mind_mk1.tres")
const PRACTICE_DEF: GreyMindDef = preload("res://content/data/enemies/grey_veiled_mind_practice.tres")

var _ship: Ship = null
var _spawner: Spawner = null
var _bosses: Array[GreyVeiledMind] = []
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_silence_test_audio)
	call_deferred("_run_checks")

func _physics_process(delta: float) -> void:
	if is_instance_valid(_ship) and not get_tree().paused:
		_ship._tick_tether_status(delta)

func _silence_test_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Grey Validation":
		push_error("Grey Mind checks require the isolated Fluxbreak Grey Validation project to protect player progress.")
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
	await _check_shipped_definitions_and_scaling()
	await _clear_bosses()
	await _check_hull_phases_and_preserved_windows()
	await _clear_bosses()
	await _check_pulse_snapshot_and_dodge()
	await _clear_bosses()
	await _check_marked_harmless_displacement()
	await _clear_bosses()
	await _check_tether_limits_and_recovery()
	await _clear_bosses()
	await _check_encounter_limits()
	await _clear_bosses()
	await _check_live_sequences()
	await _clear_bosses()
	await _check_cleanup()
	await _clear_bosses()
	print("GREY_MIND_CHECKS: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_boss(definition_source: GreyMindDef = BOSS_DEF, scaled: bool = false) -> GreyVeiledMind:
	_ship._dead = false
	_ship.visible = true
	_ship.clear_tether_slow(null, false)
	_ship._tether_immunity_sec = 0.0
	_ship.global_position = Vector3.ZERO
	var definition: GreyMindDef = definition_source.duplicate(false) as GreyMindDef
	definition.displacement_windup_sec = 0.3
	definition.rupture_windup_sec = 0.3
	definition.tether_windup_sec = 0.3
	definition.tether_duration_sec = 0.6
	definition.recovery_sec = 0.25
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
	var boss: GreyVeiledMind = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, definition, Vector3(0.0, 0.0, -300.0), request) as GreyVeiledMind
	_expect(boss != null, "Shipped Veiled Mind spawns through the actual Spawner")
	if boss == null:
		return null
	boss.freeze = true
	boss.explosion_scene = null
	boss.process_mode = Node.PROCESS_MODE_PAUSABLE
	boss.set_physics_process(false)
	_bosses.append(boss)
	return boss

func _check_shipped_definitions_and_scaling() -> void:
	_expect(BOSS_DEF.id == PRACTICE_DEF.id, "Practice and Campaign use the same Veiled Mind identity")
	_expect(PRACTICE_DEF.max_hull < BOSS_DEF.max_hull and PRACTICE_DEF.max_shield < BOSS_DEF.max_shield, "Practice lowers health without changing boss identity")
	for definition: GreyMindDef in [BOSS_DEF, PRACTICE_DEF]:
		_expect(definition.actor_scene == BOSS_DEF.actor_scene and definition.model_scene == BOSS_DEF.model_scene, "Both variants use the complete shipped boss actor and model")
		_expect(is_equal_approx(definition.phase_two_hull_threshold, 0.70) and is_equal_approx(definition.phase_three_hull_threshold, 0.35), "Both variants use actual hull thresholds at 70 and 35 percent")
		_expect(definition.rupture_windup_sec >= 1.6 and definition.recovery_sec >= 2.0, "Each variant preserves readable damaging warnings and recovery")
		_expect(definition.displacement_windup_sec >= 1.0 and definition.displacement_distance <= 190.0 and definition.displacement_distance >= 170.0, "Each variant announces reachable harmless relocations")
		_expect(definition.tether_duration_sec <= 3.0 and definition.tether_movement_factor >= 0.65, "Each variant preserves bounded tether duration and movement")
	_expect(is_equal_approx(BOSS_DEF.rupture_windup_sec, PRACTICE_DEF.rupture_windup_sec) and is_equal_approx(BOSS_DEF.recovery_sec, PRACTICE_DEF.recovery_sec), "Practice keeps the complete Campaign warnings and recovery")
	var boss: GreyVeiledMind = _spawn_boss(BOSS_DEF, true)
	if boss == null:
		return
	_expect(boss.collision_layer == 8 and boss.collision_mask == 0, "Veiled Mind remains nonblocking while retaining its targeting volume")
	_expect(boss.get_node("CollisionShape3D") is CollisionShape3D, "Shipped targeting volume exists")
	_expect(is_equal_approx(boss.eff_max_hull, BOSS_DEF.max_hull * 1.5), "Final boss hull inherits encounter scaling")
	_expect(boss._spawn_context.wave_index == 30 and boss._spawn_context.stage_index == 2, "Final boss retains wave and stage attribution")
	_expect(not boss._weapon_sockets.is_empty(), "Shipped Mothership family model exposes pulse sockets")
	for socket: BossWeaponSocket in boss._weapon_sockets:
		_expect(is_equal_approx(socket.eff_damage_min, socket.weapon.damage_min * 2.0), "Pulse socket damage inherits encounter scaling")
		_expect(socket.eff_base_range >= 500.0, "Pulse socket can reach the player after a marked relocation")
	_expect(boss.get_phase() == 1 and boss.get_meta("grey_phase") == 1, "Boss begins in phase one with runtime phase metadata")

func _check_hull_phases_and_preserved_windows() -> void:
	var boss: GreyVeiledMind = _spawn_boss()
	if boss == null:
		return
	boss._update_weapons(_ship, 100.0)
	_expect(boss.get_phase() == 1 and boss.get_attack_state() == &"rupture", "Elapsed time begins familiar rupture without changing hull phase")
	var warning_before: float = boss._attack.get_time_remaining()
	boss.hull = boss.eff_max_hull * 0.70
	boss._update_weapons(_ship, 0.0)
	_expect(boss.get_phase() == 2 and boss.get_meta("grey_phase") == 2, "Crossing actual 70 percent hull starts phase two")
	_expect(is_equal_approx(boss._attack.get_time_remaining(), warning_before), "Phase two cannot shorten the active pulse warning")
	_expect(boss._next_major == GreyVeiledMind.Major.DISPLACEMENT and _own_major_count(boss) == 1, "Phase two schedules relocation after the current major, without overlap")
	boss.shield = 0.0
	var hull_before: float = boss.hull
	boss.apply_damage(1.0)
	_expect(is_equal_approx(boss.hull, hull_before - 1.0), "Phase change grants no invulnerability")
	await _wait(0.4)
	_expect(boss.get_attack_state() == &"recovery" and is_equal_approx(boss._state_remaining_sec, boss._grey_def.recovery_sec), "The phase transition retains full vulnerable recovery")
	var recovery_before: float = boss._state_remaining_sec
	boss.hull = boss.eff_max_hull * 0.35
	boss._update_weapons(_ship, 0.0)
	_expect(boss.get_phase() == 3 and boss.get_meta("grey_phase") == 3, "Crossing actual 35 percent hull starts the final phase")
	_expect(is_equal_approx(boss._state_remaining_sec, recovery_before), "Final phase cannot shorten a recovery already in progress")
	_expect(boss._next_major == GreyVeiledMind.Major.TETHER, "Final phase begins future tether and rupture pressure")
	boss._update_weapons(_ship, 1.0)
	_expect(boss.get_attack_state() == &"cadence" and is_equal_approx(boss._state_remaining_sec, boss._grey_def.cadence_sec * boss._grey_def.phase_three_cadence_multiplier), "Final phase quickens only the quiet cadence")
	boss.hull = boss.eff_max_hull
	boss._update_weapons(_ship, 0.0)
	_expect(boss.get_phase() == 3, "Restoring hull cannot reverse a phase or reset the encounter")

func _check_pulse_snapshot_and_dodge() -> void:
	for escape: bool in [true, false]:
		var boss: GreyVeiledMind = _spawn_boss()
		if boss == null:
			return
		_make_socket_deterministic(boss)
		var health_before: float = _ship.hull + _ship.shield
		boss._begin_attack(_ship)
		_expect(boss._attack.get_attack_label() == "VEILED RUPTURE", "Pulse exposes the shared warning and HUD label")
		var locked_position: Vector3 = boss._attack._locked_position
		await _wait(0.1)
		_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Pulse does not damage during the warning")
		var time_before: float = boss._attack.get_time_remaining()
		get_tree().paused = true
		await _wait(0.4)
		_expect(is_equal_approx(boss._attack.get_time_remaining(), time_before), "Pausing freezes the damaging pulse warning")
		_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Pulse cannot damage during pause")
		get_tree().paused = false
		if escape:
			_ship.global_position = Vector3(0.0, 160.0, 0.0)
		else:
			for socket: BossWeaponSocket in boss._weapon_sockets:
				socket.eff_damage_min = 999.0
				socket.eff_damage_max = 999.0
		_expect(boss._attack._locked_position.is_equal_approx(locked_position), "Pulse volume stays fixed after target or weapon changes")
		await _wait(0.3)
		_expect(is_equal_approx(health_before - _ship.hull - _ship.shield, 0.0 if escape else 12.0), "Leaving vertically evades the pulse; remaining inside takes one captured hit")
		_expect(boss.get_attack_state() == &"recovery" and _own_major_count(boss) == 0, "Pulse ends in full recovery with no overlapping major")
		await _wait(0.25)
		_expect(is_equal_approx(health_before - _ship.hull - _ship.shield, 0.0 if escape else 12.0), "Release flash cannot produce another hit")
		await _clear_bosses()

func _check_marked_harmless_displacement() -> void:
	var boss: GreyVeiledMind = _spawn_boss()
	if boss == null:
		return
	boss._next_major = GreyVeiledMind.Major.DISPLACEMENT
	var health_before: float = _ship.hull + _ship.shield
	var origin: Vector3 = boss.global_position
	boss._begin_attack(_ship)
	var destination: Vector3 = boss._displacement._destination
	_expect(destination.distance_squared_to(_ship.global_position) <= 190.01 * 190.01 and destination.distance_squared_to(_ship.global_position) >= 169.99 * 169.99, "Marked relocation is inside starter reach")
	_expect(boss.visible and boss.get_visual_model_root().visible, "The boss silhouette remains visible and reacquirable throughout relocation")
	await _wait(0.1)
	_expect(boss.global_position.is_equal_approx(origin), "The boss waits for the entire announced arrival countdown")
	var time_before: float = boss._displacement._remaining_sec
	get_tree().paused = true
	await _wait(0.4)
	_expect(is_equal_approx(boss._displacement._remaining_sec, time_before) and boss.global_position.is_equal_approx(origin), "Pause freezes both marked countdown and relocation")
	get_tree().paused = false
	_ship.global_position = destination
	await _wait(0.3)
	_expect(boss.global_position.is_equal_approx(destination), "The boss uses the locked destination despite player movement")
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Even direct arrival on the player has no teleport or collision damage")
	_expect(boss.get_attack_state() == &"recovery" and _own_major_count(boss) == 0, "Relocation ends with a separate full recovery before any damage")
	boss._begin_attack(_ship)
	_expect(_own_major_count(boss) == 0, "Recovery cannot be bypassed to launch another major")

func _check_tether_limits_and_recovery() -> void:
	var boss: GreyVeiledMind = _spawn_boss()
	if boss == null:
		return
	boss._next_major = GreyVeiledMind.Major.TETHER
	boss._grey_def.tether_duration_sec = 30.0
	boss._grey_def.tether_movement_factor = 0.1
	var health_before: float = _ship.hull + _ship.shield
	boss._begin_attack(_ship)
	_expect(boss.get_attack_state() == &"tether" and _own_major_count(boss) == 1, "Tether acquisition is a separate harmless warning")
	await _wait(0.1)
	_expect(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Tether cannot apply its slow before the complete warning")
	await _wait(0.3)
	_expect(is_instance_valid(boss._tether) and boss._tether.is_attached(), "Remaining inside the locked capture sphere permits a tether")
	_expect(is_equal_approx(_ship.get_movement_slow_multiplier(), 0.65), "Malformed definition cannot slow movement beyond 35 percent")
	_expect(_ship.get_tether_time_remaining() <= 3.0, "Malformed definition cannot lengthen tether beyond three seconds")
	_expect(_ship.get_tether_source() == boss, "The Ship retains actual boss source attribution")
	boss._update_weapons(_ship, 100.0)
	_expect(boss.get_attack_state() == &"tether" and _own_major_count(boss) == 1, "Attached tether blocks all other boss majors regardless of elapsed cadence")
	_ship.global_position = Vector3(800.0, 0.0, 0.0)
	await _wait(0.05)
	_expect(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0) and _ship.is_tether_immune(), "Breaking distance restores movement and grants immunity")
	_expect(_ship._tether_immunity_sec >= 2.9, "The break grants the full three second protection window")
	_expect(boss.get_attack_state() == &"recovery" and is_equal_approx(boss._state_remaining_sec, boss._grey_def.recovery_sec), "Breaking the link grants full vulnerable boss recovery")
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Tether acquisition, attachment, and break never cause damage")
	await _clear_bosses()
	boss = _spawn_boss()
	if boss == null:
		return
	boss._next_major = GreyVeiledMind.Major.TETHER
	boss._begin_attack(_ship)
	_ship.global_position = Vector3(0.0, 160.0, 0.0)
	await _wait(0.4)
	_expect(_ship.get_tether_source() == null and is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Leaving the fixed capture volume vertically avoids attachment")
	_expect(boss.get_attack_state() == &"recovery", "An evaded tether still grants the complete recovery")

func _check_encounter_limits() -> void:
	var first: GreyVeiledMind = _spawn_boss()
	var second: GreyVeiledMind = _spawn_boss()
	var third: GreyVeiledMind = _spawn_boss()
	if first == null or second == null or third == null:
		return
	first._grey_def.rupture_windup_sec = 2.0
	second._grey_def.rupture_windup_sec = 2.0
	first._begin_attack(_ship)
	second._begin_attack(_ship)
	third._begin_attack(_ship)
	_expect(_own_major_count(first) == 1 and _own_major_count(second) == 1 and _own_major_count(third) == 0, "A third source cannot exceed two encounter wide major warnings")
	_expect(third.get_attack_state() == &"cadence" and is_equal_approx(third._state_remaining_sec, GreyVeiledMind.RETRY_SEC), "A full encounter retries later without silently skipping its attack")
	first._clear_encounter_runtime()
	third._begin_attack(_ship)
	_expect(is_instance_valid(third._attack), "A released major slot becomes usable without waiting for a cancelled visual")
	await _clear_bosses()
	first = _spawn_boss()
	second = _spawn_boss()
	third = _spawn_boss()
	if first == null or second == null or third == null:
		return
	first._next_major = GreyVeiledMind.Major.TETHER
	second._next_major = GreyVeiledMind.Major.TETHER
	third._grey_def.rupture_windup_sec = 2.0
	first._begin_attack(_ship)
	second._begin_attack(_ship)
	third._begin_attack(_ship)
	_expect(is_instance_valid(first._tether) and not is_instance_valid(second._tether), "One pending tether prevents a second capture warning across sources")
	_expect(is_instance_valid(third._attack), "One damaging warning can coexist with the single capture warning")
	await _wait(0.4)
	_expect(is_instance_valid(first._tether) and first._tether.is_attached(), "Limiter test reaches a genuinely attached tether")
	second._next_major = GreyVeiledMind.Major.RUPTURE
	second._begin_attack(_ship)
	_expect(not is_instance_valid(second._attack), "Attached link continues to consume one of the two major slots")
	_expect(not GreyThreatLimiter.can_start_tether(second), "Attached link prevents any new source from beginning another tether")

func _check_live_sequences() -> void:
	for phase: int in [1, 2, 3]:
		var boss: GreyVeiledMind = _spawn_boss()
		if boss == null:
			return
		_make_socket_deterministic(boss)
		if phase == 2:
			boss.hull = boss.eff_max_hull * 0.65
		elif phase == 3:
			boss.hull = boss.eff_max_hull * 0.30
		boss._state_remaining_sec = 0.0
		boss.set_physics_process(true)
		var seen_states: Array[StringName] = []
		var peak_majors: int = 0
		var attacks_started: int = 0
		var previous_state: StringName = &""
		for frame in range(600):
			var state: StringName = boss.get_attack_state()
			if not seen_states.has(state):
				seen_states.append(state)
			if state != previous_state and state in [&"rupture", &"displacement", &"tether"]:
				attacks_started += 1
			previous_state = state
			peak_majors = maxi(peak_majors, _own_major_count(boss))
			await get_tree().physics_frame
		_expect(boss.get_phase() == phase, "Live phase %d is determined by hull" % phase)
		_expect(seen_states.has(&"rupture") and seen_states.has(&"recovery") and attacks_started >= 3, "Live phase %d executes repeated pulses with recovery" % phase)
		_expect(peak_majors == 1, "Live phase %d never overlaps its own majors" % phase)
		_expect(seen_states.has(&"displacement") == (phase >= 2), "Live phase %d exposes relocation only after phase two" % phase)
		_expect(seen_states.has(&"tether") == (phase == 3), "Live phase %d exposes tether only in the final phase" % phase)
		boss.set_physics_process(false)
		await _clear_bosses()

func _check_cleanup() -> void:
	for major: int in [GreyVeiledMind.Major.DISPLACEMENT, GreyVeiledMind.Major.RUPTURE, GreyVeiledMind.Major.TETHER]:
		for reason: StringName in [&"boss_death", &"source_exit", &"player_death"]:
			var boss: GreyVeiledMind = _spawn_boss()
			if boss == null:
				return
			boss._next_major = major
			var health_before: float = _ship.hull + _ship.shield
			boss._begin_attack(_ship)
			await _wait(0.1)
			match reason:
				&"boss_death":
					boss.apply_damage(1000000.0)
				&"source_exit":
					boss.queue_free()
				&"player_death":
					_ship._dead = true
					boss._update_weapons(_ship, 0.0)
			await _wait(0.4)
			_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "%s cancels pending major %d without a delayed hit" % [reason, major])
			_expect(_warnings_empty(), "%s removes every major %d warning and spatial marker" % [reason, major])
			_expect(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "%s leaves no major %d movement penalty" % [reason, major])
			if reason != &"player_death":
				_expect(int(_spawner.get_alive_counts()["enemies"]) == 0, "%s cleans actual Spawner accounting for major %d" % [reason, major])
			await _clear_bosses()
	for reason: StringName in [&"boss_death", &"source_exit", &"player_death"]:
		var boss: GreyVeiledMind = _spawn_boss()
		if boss == null:
			return
		boss._next_major = GreyVeiledMind.Major.TETHER
		boss._begin_attack(_ship)
		await _wait(0.4)
		_expect(_ship.get_tether_source() == boss, "Cleanup begins with a real attached link before %s" % reason)
		match reason:
			&"boss_death":
				boss.apply_damage(1000000.0)
			&"source_exit":
				boss.queue_free()
			&"player_death":
				_ship._dead = true
				boss._update_weapons(_ship, 0.0)
		await _wait(0.1)
		_expect(_warnings_empty() and is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "%s clears the attached link and immediately restores movement" % reason)
		await _clear_bosses()

func _own_major_count(boss: GreyVeiledMind) -> int:
	return int(is_instance_valid(boss._attack)) + int(is_instance_valid(boss._displacement)) + int(is_instance_valid(boss._tether))

func _warnings_empty() -> bool:
	return get_tree().get_nodes_in_group("grey_displacements").is_empty() and get_tree().get_nodes_in_group("grey_tethers").is_empty() and get_tree().get_nodes_in_group("enemy_attack_telegraphs").is_empty()

func _make_socket_deterministic(boss: GreyVeiledMind) -> void:
	for socket: BossWeaponSocket in boss._weapon_sockets:
		socket.eff_base_accuracy = 1.0
		socket.eff_range_falloff = 0.0
		socket.eff_crit_chance = 0.0
		socket.eff_graze_on_hit = 0.0
		socket.eff_graze_on_miss = 0.0
		socket.eff_damage_min = 12.0
		socket.eff_damage_max = 12.0

func _clear_bosses() -> void:
	for boss: GreyVeiledMind in _bosses:
		if is_instance_valid(boss) and not boss.is_queued_for_deletion():
			boss.queue_free()
	_bosses.clear()
	_ship._dead = false
	_ship.visible = true
	await _wait(0.1)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("GREY_MIND_CHECKS: " + description)
